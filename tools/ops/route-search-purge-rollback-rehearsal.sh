#!/usr/bin/env bash
set -euo pipefail

umask 077

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/easysubway}"
DEPLOY_SHA="${DEPLOY_SHA:?DEPLOY_SHA is required}"
CURRENT_DEPLOYED_SHA="${CURRENT_DEPLOYED_SHA:?CURRENT_DEPLOYED_SHA is required}"
BACKEND_ENV_FILE="${BACKEND_ENV_FILE:?BACKEND_ENV_FILE is required}"

for sha in "${DEPLOY_SHA}" "${CURRENT_DEPLOYED_SHA}"; do
	[[ "${sha}" =~ ^[0-9a-f]{40}$ ]] || { printf 'invalid rehearsal SHA\n' >&2; exit 2; }
done
[[ -f "${BACKEND_ENV_FILE}" ]] || { printf 'backend env file is missing\n' >&2; exit 2; }

MARKER_FILE="${DEPLOY_ROOT}/shared/1913-route-purge-snapshot/snapshot-${DEPLOY_SHA}.env"
[[ -f "${MARKER_FILE}" ]] || { printf 'route purge snapshot marker is missing\n' >&2; exit 1; }

marker_value() {
	local key="${1:?marker key is required}"
	local value
	value="$(sed -n "s/^${key}=//p" "${MARKER_FILE}")"
	[[ -n "${value}" && "${value}" != *$'\n'* ]] || { printf 'invalid snapshot marker field: %s\n' "${key}" >&2; exit 1; }
	printf '%s\n' "${value}"
}

backup_file="$(marker_value backup_file)"
schema_version="$(marker_value schema_version)"
route_total="$(marker_value route_total)"
delete_candidates="$(marker_value delete_candidates)"
case "${backup_file}" in
	"${DEPLOY_ROOT}/backups/postgres/1913-route-purge/"*.dump) ;;
	*) printf 'snapshot backup path is invalid\n' >&2; exit 1 ;;
esac
[[ -f "${backup_file}" ]] || { printf 'snapshot backup is missing\n' >&2; exit 1; }
[[ "${schema_version}" =~ ^[0-9]+$ && "${route_total}" =~ ^[0-9]+$ && "${delete_candidates}" =~ ^[0-9]+$ ]] \
	|| { printf 'snapshot aggregate is invalid\n' >&2; exit 1; }
(( delete_candidates <= route_total )) || { printf 'snapshot delete candidate count is invalid\n' >&2; exit 1; }

PR1_IMAGE="easysubway-backend:${CURRENT_DEPLOYED_SHA}"
TARGET_IMAGE="easysubway-backend:${DEPLOY_SHA}"
POSTGRES_IMAGE="$(docker inspect --format '{{.Image}}' easysubway-postgres)"
[[ "${POSTGRES_IMAGE}" =~ ^sha256:[0-9a-f]{64}$ ]] || { printf 'production PostgreSQL image is invalid\n' >&2; exit 1; }

for pair in "${PR1_IMAGE}:${CURRENT_DEPLOYED_SHA}" "${TARGET_IMAGE}:${DEPLOY_SHA}"; do
	image="${pair%:*}"
	expected_revision="${pair##*:}"
	revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${image}")"
	[[ "${revision}" == "${expected_revision}" ]] || { printf 'rehearsal image revision mismatch\n' >&2; exit 1; }
done

suffix="${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}"
[[ "${suffix}" =~ ^[0-9]+-[0-9]+$ ]] || { printf 'invalid rehearsal run identity\n' >&2; exit 2; }
NETWORK="easysubway-1913-rollback-${suffix}"
VOLUME="easysubway-1913-rollback-${suffix}"
DB="easysubway-1913-rollback-db-${suffix}"
TARGET_MIGRATE="easysubway-1913-target-migrate-${suffix}"
ROLLBACK_BACKEND="easysubway-1913-pr1-backend-${suffix}"
ROLLBACK_WORKER="easysubway-1913-pr1-worker-${suffix}"

cleanup() {
	for container in "${TARGET_MIGRATE}" "${ROLLBACK_BACKEND}" "${ROLLBACK_WORKER}" "${DB}"; do
		docker rm -f "${container}" >/dev/null 2>&1 || true
	done
	docker volume rm "${VOLUME}" >/dev/null 2>&1 || true
	docker network rm "${NETWORK}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

app_run() {
	local name="${1:?name is required}"
	local image="${2:?image is required}"
	local worker="${3:?worker flag is required}"
	docker run -d --name "${name}" \
		--network "${NETWORK}" \
		--env-file "${BACKEND_ENV_FILE}" \
		-e SPRING_PROFILES_ACTIVE=prod \
		-e EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql://db:5432/easysubway_rehearsal \
		-e EASYSUBWAY_DATASOURCE_USERNAME=rehearsal \
		-e EASYSUBWAY_DATASOURCE_PASSWORD=rehearsal_local \
		-e EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http://127.0.0.1:9 \
		-e EASYSUBWAY_PUSH_EXTERNAL_ENABLED=false \
		-e EASYSUBWAY_PUSH_DELIVERY_ENABLED="${worker}" \
		"${image}" >/dev/null
}

wait_ready() {
	local name="${1:?name is required}"
	for _ in $(seq 1 300); do
		[[ "$(docker inspect --format '{{.State.Running}}' "${name}" 2>/dev/null || true)" == true ]] \
			|| { printf 'rehearsal application stopped before readiness\n' >&2; exit 1; }
		if [[ "$(docker exec "${name}" curl -sS --noproxy '*' --connect-timeout 1 --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/actuator/health/readiness 2>/dev/null || true)" == 200 ]]; then
			return
		fi
		sleep 1
	done
	printf 'rehearsal application readiness timed out\n' >&2
	exit 1
}

docker network create --internal "${NETWORK}" >/dev/null
docker volume create "${VOLUME}" >/dev/null
docker run -d --name "${DB}" --network "${NETWORK}" --network-alias db \
	--cpus 1 --memory 2g --memory-swap 2g --pids-limit 256 \
	-v "${VOLUME}:/var/lib/postgresql/data" \
	-e POSTGRES_DB=easysubway_rehearsal \
	-e POSTGRES_USER=rehearsal \
	-e POSTGRES_PASSWORD=rehearsal_local \
	"${POSTGRES_IMAGE}" >/dev/null

ready=false
for _ in $(seq 1 60); do
	if [[ "$(docker exec "${DB}" cat /proc/1/comm 2>/dev/null || true)" == postgres ]] \
		&& docker exec "${DB}" pg_isready -U rehearsal -d easysubway_rehearsal >/dev/null 2>&1; then
		ready=true
		break
	fi
	sleep 1
done
[[ "${ready}" == true ]] || { printf 'rehearsal PostgreSQL readiness timed out\n' >&2; exit 1; }

docker exec -i "${DB}" pg_restore --clean --if-exists --no-owner --no-privileges \
	-U rehearsal -d easysubway_rehearsal < "${backup_file}"

schema_before="$(docker exec "${DB}" psql -X -A -t -U rehearsal -d easysubway_rehearsal \
	-c 'SELECT version FROM flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1;' | tr -d '[:space:]')"
rows_before="$(docker exec "${DB}" psql -X -A -t -U rehearsal -d easysubway_rehearsal \
	-c 'SELECT count(*) FROM route_search_results;' | tr -d '[:space:]')"
[[ "${schema_before}" == "${schema_version}" && "${rows_before}" == "${route_total}" ]] \
	|| { printf 'restored rehearsal identity mismatch\n' >&2; exit 1; }

app_run "${TARGET_MIGRATE}" "${TARGET_IMAGE}" false
wait_ready "${TARGET_MIGRATE}"
schema_after="$(docker exec "${DB}" psql -X -A -t -U rehearsal -d easysubway_rehearsal \
	-c 'SELECT version FROM flyway_schema_history WHERE success ORDER BY installed_rank DESC LIMIT 1;' | tr -d '[:space:]')"
rows_after="$(docker exec "${DB}" psql -X -A -t -U rehearsal -d easysubway_rehearsal \
	-c 'SELECT count(*) FROM route_search_results;' | tr -d '[:space:]')"
expected_rows="$((route_total - delete_candidates))"
[[ "${schema_after}" == 51 ]]
[[ "${rows_after}" == "${expected_rows}" ]] || { printf 'V51 rehearsal delete count mismatch\n' >&2; exit 1; }
docker rm -f "${TARGET_MIGRATE}" >/dev/null

app_run "${ROLLBACK_BACKEND}" "${PR1_IMAGE}" false
app_run "${ROLLBACK_WORKER}" "${PR1_IMAGE}" true
wait_ready "${ROLLBACK_BACKEND}"
wait_ready "${ROLLBACK_WORKER}"

status_v1="$(docker exec "${ROLLBACK_BACKEND}" curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data-binary '{"originStationId":"rehearsal","destinationStationId":"rehearsal","mobilityType":"SENIOR"}' http://127.0.0.1:8080/api/v1/routes/search)"
status_v2="$(docker exec "${ROLLBACK_BACKEND}" curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data-binary '{"originStationId":"rehearsal","destinationStationId":"rehearsal","departureTime":"2026-07-15T09:15:00+09:00","mobilityType":"SENIOR","constraintMode":"ALLOW_WITH_WARNINGS","useRealtime":false,"maxTransfers":3,"alternativeCount":1}' http://127.0.0.1:8080/api/v2/routes/search)"
status_refresh="$(docker exec "${ROLLBACK_BACKEND}" curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data-binary '{}' http://127.0.0.1:8080/api/v2/routes/rehearsal/refresh)"
[[ "${status_v1}/${status_v2}/${status_refresh}" == 403/403/403 ]] || { printf 'PR1 route closure rehearsal failed\n' >&2; exit 1; }

pr1_image_id="$(docker image inspect --format '{{.Id}}' "${PR1_IMAGE}")"
for container in "${ROLLBACK_BACKEND}" "${ROLLBACK_WORKER}"; do
	[[ "$(docker inspect --format '{{.Image}}' "${container}")" == "${pr1_image_id}" ]] \
		|| { printf 'PR1 rollback image identity mismatch\n' >&2; exit 1; }
	if docker logs "${container}" 2>&1 | grep -E 'Validate failed|Migration checksum mismatch|Flyway.*(ERROR|failed)' >/dev/null; then
		printf 'Flyway validation error in PR1 rollback rehearsal\n' >&2
		exit 1
	fi
done

{
	echo '### #1913 PR1 image rollback rehearsal'
	echo "- target/PR1 SHA: \`${DEPLOY_SHA}/${CURRENT_DEPLOYED_SHA}\`"
	echo "- schema before/after: \`${schema_before}/${schema_after}\`"
	echo "- route rows before/after: \`${rows_before}/${rows_after}\`"
	echo '- readiness=backend:200,back-worker:200'
	echo '- route_statuses=403/403/403'
	echo '- Flyway validation errors: `0`'
	echo '- isolation: internal network, no published ports'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

printf 'PR1 image rollback rehearsal completed\n'
