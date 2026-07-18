#!/usr/bin/env bash
set -euo pipefail

umask 077

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/easysubway}"
EXPECTED_DEPLOYED_SHA="${EXPECTED_DEPLOYED_SHA:-}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://easysubway-api.aquilaxk.site}"

read_env_value() {
	local file="${1:?file is required}"
	local name="${2:?name is required}"
	local line value="" match_count=0
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ "${line}" == "${name}="* ]] || continue
		match_count=$((match_count + 1))
		value="${line#*=}"
		if [[ "${value}" == \"*\" && "${value}" == *\" ]] || [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
			value="${value:1:${#value}-2}"
		fi
	done < "${file}"
	if (( match_count > 1 )); then
		echo "${name} is defined ${match_count} times in the deployment environment" >&2
		return 1
	fi
	(( match_count == 1 )) || return 1
	printf '%s\n' "${value}"
	return 0
}

if [[ "${1:-}" == --test-read-env-value ]]; then
	[[ $# -eq 3 && -f "${2}" && "${3}" =~ ^[A-Z0-9_]+$ ]] || exit 2
	read_env_value "${2}" "${3}"
	exit
fi

[[ "${EXPECTED_DEPLOYED_SHA}" =~ ^[0-9a-f]{40}$ ]] || { echo 'expected deployed SHA is invalid' >&2; exit 2; }
[[ "${PUBLIC_BASE_URL}" == https://easysubway-api.aquilaxk.site ]] \
	|| { echo 'public base URL must be the approved production origin' >&2; exit 2; }

exec 9>"${DEPLOY_ROOT}/deploy.lock"
flock -w 300 9 || { echo 'timed out waiting for deployment lock' >&2; exit 1; }

current_sha="$(<"${DEPLOY_ROOT}/shared/current-sha")"
current_digest="$(<"${DEPLOY_ROOT}/shared/current-image-digest")"
compose_env="${DEPLOY_ROOT}/shared/current-env/compose.env"
[[ "${current_sha}" == "${EXPECTED_DEPLOYED_SHA}" ]] || { echo 'deployed SHA does not match requested evidence SHA' >&2; exit 1; }
[[ "${current_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'deployed image digest marker is invalid' >&2; exit 1; }
[[ -f "${compose_env}" ]] || { echo 'current compose environment is missing' >&2; exit 1; }

require_bounded_limit() {
	local name="${1:?name is required}"
	local maximum="${2:?maximum is required}"
	local value
	value="$(read_env_value "${compose_env}" "${name}")" || { echo "${name} is missing" >&2; exit 1; }
	[[ "${value}" =~ ^[1-9][0-9]*$ ]] || { echo "${name} is invalid" >&2; exit 1; }
	(( value <= maximum )) || { echo "${name} is relaxed beyond the approved maximum" >&2; exit 1; }
	printf '%s\n' "${value}"
}

ingress_enabled="$(read_env_value "${compose_env}" EASYSUBWAY_ROUTE_V2_INGRESS_ENABLED | tr '[:upper:]' '[:lower:]')"
[[ "${ingress_enabled}" == false ]] || { echo 'production Route V2 ingress must be closed for isolated load evidence' >&2; exit 1; }
session_rate="$(require_bounded_limit EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE 5)"
session_burst="$(require_bounded_limit EASYSUBWAY_ROUTE_V2_SESSION_BURST 2)"
search_rate="$(require_bounded_limit EASYSUBWAY_ROUTE_V2_SEARCH_RATE_PER_MINUTE 10)"
search_burst="$(require_bounded_limit EASYSUBWAY_ROUTE_V2_SEARCH_BURST 3)"

backend_image="easysubway-backend:${current_sha}"
image_revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${backend_image}")"
[[ "${image_revision}" == "${current_sha}" ]] || { echo 'backend image revision mismatch' >&2; exit 1; }
repo_digests="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "${backend_image}")"
grep -Fxq "ghcr.io/aquilaxk/easysubway-backend@${current_digest}" <<< "${repo_digests}" \
	|| { echo 'backend image immutable digest mismatch' >&2; exit 1; }
expected_image_id="$(docker image inspect --format '{{.Id}}' "${backend_image}")"
[[ "$(docker inspect --format '{{.Config.Image}}' easysubway-backend)" == "${backend_image}" ]] \
	|| { echo 'running backend tag mismatch' >&2; exit 1; }
[[ "$(docker inspect --format '{{.Image}}' easysubway-backend)" == "${expected_image_id}" ]] \
	|| { echo 'running backend image mismatch' >&2; exit 1; }

public_status() {
	local path="${1:?path is required}"
	curl -sS --connect-timeout 3 --max-time 10 --output /dev/null --write-out '%{http_code}' \
		--request POST --header 'content-type: application/json' --data-binary '{}' "${PUBLIC_BASE_URL}${path}"
}
[[ "$(public_status /api/v2/routes/session)" == 404 ]] || { echo 'public Route V2 session ingress is not closed' >&2; exit 1; }
[[ "$(public_status /api/v2/routes/search)" == 404 ]] || { echo 'public Route V2 search ingress is not closed' >&2; exit 1; }

run_id="${GITHUB_RUN_ID:-$$}"
run_attempt="${GITHUB_RUN_ATTEMPT:-1}"
[[ "${run_id}" =~ ^[0-9]+$ && "${run_attempt}" =~ ^[0-9]+$ ]] || { echo 'run identity is invalid' >&2; exit 2; }
prefix="easysubway-2095-${run_id}-${run_attempt}"
network="${prefix}"
volume="${prefix}-db-data"
clone_db="${prefix}-db"
clone_backend="${prefix}-backend"
clone_gateway="${prefix}-gateway"
clone_curl="${prefix}-curl"
work_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/issue-2095-capacity.XXXXXX")"
backup_file="${work_dir}/production.dump"
postgres_env_file="${work_dir}/postgres.env"
backend_env_file="${work_dir}/backend.env"
gateway_env_file="${work_dir}/gateway.env"
tokens_file="${work_dir}/tokens.tsv"
issued_tokens_file="${work_dir}/issued-tokens.tsv"
planner_identity_file="${work_dir}/planner-identity.json"
metrics_file="${work_dir}/metrics.tsv"
logs_file="${work_dir}/service.log"
resource_metrics_file="${work_dir}/resource.tsv"
resource_stop_file="${work_dir}/resource.stop"
resource_ready_file="${work_dir}/resource.ready"
resource_sampler_pid=""

stop_resource_sampler() {
	[[ -n "${resource_sampler_pid}" ]] || return 0
	if kill -0 "${resource_sampler_pid}" >/dev/null 2>&1; then
		: > "${resource_stop_file}" || return 1
	fi
	if ! wait "${resource_sampler_pid}"; then
		return 1
	fi
	resource_sampler_pid=""
}

cleanup() {
	local cleanup_failed=0
	local container existing_object
	if ! stop_resource_sampler; then
		cleanup_failed=1
	fi
	for container in "${clone_gateway}" "${clone_backend}" "${clone_curl}" "${clone_db}"; do
		if ! existing_object="$(docker container ls -a --filter "name=^/${container}$" --format '{{.Names}}')"; then
			cleanup_failed=1
		elif [[ "${existing_object}" == "${container}" ]] \
			&& ! docker rm -f "${container}" >/dev/null 2>&1; then
			cleanup_failed=1
		fi
	done
	if ! existing_object="$(docker volume ls --filter "name=^${volume}$" --format '{{.Name}}')"; then
		cleanup_failed=1
	elif [[ "${existing_object}" == "${volume}" ]] \
		&& ! docker volume rm "${volume}" >/dev/null 2>&1; then
		cleanup_failed=1
	fi
	if ! existing_object="$(docker network ls --filter "name=^${network}$" --format '{{.Name}}')"; then
		cleanup_failed=1
	elif [[ "${existing_object}" == "${network}" ]] \
		&& ! docker network rm "${network}" >/dev/null 2>&1; then
		cleanup_failed=1
	fi
	if ! rm -rf "${work_dir}"; then
		cleanup_failed=1
	fi
	return "${cleanup_failed}"
}
cleanup_on_exit() {
	local original_status=$?
	trap - EXIT
	if ! cleanup; then
		echo 'isolated capacity evidence cleanup failed' >&2
		exit 1
	fi
	exit "${original_status}"
}
trap cleanup_on_exit EXIT

postgres_user="$(read_env_value "${compose_env}" EASYSUBWAY_POSTGRES_USER)"
postgres_db="$(read_env_value "${compose_env}" EASYSUBWAY_POSTGRES_DB)"
[[ "${postgres_user}" =~ ^[A-Za-z0-9_.-]+$ && "${postgres_db}" =~ ^[A-Za-z0-9_.-]+$ ]] \
	|| { echo 'production PostgreSQL identity is invalid' >&2; exit 1; }
mapfile -t synthetic_secrets < <(node -e '
const { randomBytes } = require("node:crypto");
console.log(randomBytes(32).toString("hex"));
console.log(randomBytes(32).toString("hex"));
console.log(randomBytes(32).toString("base64url"));
')
(( ${#synthetic_secrets[@]} == 3 )) || { echo 'synthetic credential generation failed' >&2; exit 1; }
clone_db_password="${synthetic_secrets[0]}"
synthetic_secret="${synthetic_secrets[1]}"
synthetic_certificate_digest="${synthetic_secrets[2]}"
[[ "${clone_db_password}" =~ ^[0-9a-f]{64}$ && "${synthetic_secret}" =~ ^[0-9a-f]{64}$ \
	&& "${synthetic_certificate_digest}" =~ ^[A-Za-z0-9_-]{43}$ ]] \
	|| { echo 'synthetic credential format is invalid' >&2; exit 1; }
{
	printf 'POSTGRES_USER=%s\n' "${postgres_user}"
	printf 'POSTGRES_DB=%s\n' "${postgres_db}"
	printf 'POSTGRES_PASSWORD=%s\n' "${clone_db_password}"
} > "${postgres_env_file}"
{
	printf 'SPRING_PROFILES_ACTIVE=prod,capacity-evidence\n'
	printf 'EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql://postgres:5432/%s\n' "${postgres_db}"
	printf 'EASYSUBWAY_DATASOURCE_USERNAME=%s\n' "${postgres_user}"
	printf 'EASYSUBWAY_DATASOURCE_PASSWORD=%s\n' "${clone_db_password}"
	printf 'EASYSUBWAY_ADS_ASSET_ORIGIN=https://assets.easysubway.invalid\n'
	printf 'EASYSUBWAY_ADS_EVENT_DAILY_CAP=1\n'
	printf 'EASYSUBWAY_REPORT_RECEIPT_PEPPER=%s\n' "${synthetic_secret}"
	printf 'EASYSUBWAY_REPORT_UPLOAD_BUCKET=capacity-evidence\n'
	printf 'EASYSUBWAY_REPORT_UPLOAD_INTENT_SIGNING_KEY=%s\n' "${synthetic_secret}"
	printf 'EASYSUBWAY_REPORT_ABUSE_STORE_MODE=local\n'
	printf 'EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http://127.0.0.1:9\n'
	printf 'EASYSUBWAY_REPORT_UPLOAD_PUBLIC_BASE_URL=https://uploads.easysubway.invalid\n'
	printf 'EASYSUBWAY_OBJECT_STORAGE_ACCESS_KEY=capacity-evidence\n'
	printf 'EASYSUBWAY_OBJECT_STORAGE_SECRET_KEY=%s\n' "${synthetic_secret}"
	printf 'EASYSUBWAY_OBJECT_STORAGE_REGION=us-east-1\n'
	printf 'EASYSUBWAY_ADMIN_USERNAME=capacity-admin\n'
	printf 'EASYSUBWAY_ADMIN_PASSWORD=%s\n' "${synthetic_secret}"
	printf 'EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED=false\n'
	printf 'EASYSUBWAY_TRUSTED_PROXY_CIDRS=172.16.0.0/12\n'
	printf 'EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET=%s\n' "${synthetic_secret}"
	printf 'EASYSUBWAY_ROUTE_V2_SESSION_MAX_REQUESTS=50\n'
	printf 'EASYSUBWAY_ROUTE_V2_PLAY_INTEGRITY_CERTIFICATE_SHA256=%s\n' "${synthetic_certificate_digest}"
	printf 'EASYSUBWAY_ROUTE_V2_CAPACITY_EVIDENCE_ATTESTATION_KEY=%s\n' "${synthetic_secret}"
	printf 'EASYSUBWAY_PLAY_INTEGRITY_CREDENTIALS_BASE64=e30=\n'
	printf 'EASYSUBWAY_PUSH_EXTERNAL_ENABLED=false\n'
	printf 'EASYSUBWAY_PUSH_DELIVERY_ENABLED=false\n'
	printf 'EASYSUBWAY_TIMETABLE_SEED_ENABLED=false\n'
	printf 'EASYSUBWAY_TIMETABLE_SEED_INCLUDES_ITX=false\n'
	printf 'EASYSUBWAY_SCHEDULING_ENABLED=true\n'
	printf 'EASYSUBWAY_ROUTE_V2_STATE_PURGE_INTERVAL_MS=1000\n'
} > "${backend_env_file}"
{
	printf 'NGINX_ENVSUBST_FILTER=EASYSUBWAY_\n'
	printf 'NGINX_ENVSUBST_OUTPUT_DIR=/tmp/nginx-conf.d\n'
	printf 'EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET=%s\n' "${synthetic_secret}"
	printf 'EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE=%s\n' "${session_rate}"
	printf 'EASYSUBWAY_ROUTE_V2_SESSION_BURST=%s\n' "${session_burst}"
	printf 'EASYSUBWAY_ROUTE_V2_SEARCH_RATE_PER_MINUTE=%s\n' "${search_rate}"
	printf 'EASYSUBWAY_ROUTE_V2_SEARCH_BURST=%s\n' "${search_burst}"
	printf 'EASYSUBWAY_ROUTE_V2_TRUSTED_PROXY_CIDR=172.16.0.0/12\n'
} > "${gateway_env_file}"
chmod 600 "${postgres_env_file}" "${backend_env_file}" "${gateway_env_file}"

production_psql() {
	local sql="${1:?SQL is required}"
	docker exec easysubway-postgres sh -lc \
		'psql -X -v ON_ERROR_STOP=1 -A -t -U "$POSTGRES_USER" "$POSTGRES_DB" -c "$1"' sh "${sql}"
}
available_bytes() {
	local path="${1:?filesystem path is required}"
	local available_kib
	available_kib="$(df -Pk "${path}" | awk 'NR == 2 { print $4 }')"
	[[ "${available_kib}" =~ ^[0-9]+$ ]] || { echo 'filesystem available capacity is invalid' >&2; exit 1; }
	printf '%s\n' "$((available_kib * 1024))"
}
database_size_bytes="$(production_psql 'SELECT pg_database_size(current_database());')"
[[ "${database_size_bytes}" =~ ^[1-9][0-9]*$ ]] || { echo 'production database size is invalid' >&2; exit 1; }
required_copy_bytes="$((database_size_bytes * 4 + 2147483648))"
docker_root_dir="$(docker info --format '{{.DockerRootDir}}')"
[[ "${docker_root_dir}" =~ ^/[A-Za-z0-9._/-]+$ && "${docker_root_dir}" != *..* && -d "${docker_root_dir}" ]] \
	|| { echo 'Docker data root is invalid' >&2; exit 1; }
dump_available_bytes="$(available_bytes "${work_dir}")"
docker_available_bytes="$(available_bytes "${docker_root_dir}")"
if (( dump_available_bytes < required_copy_bytes || docker_available_bytes < required_copy_bytes )); then
	echo 'insufficient capacity for production dump and isolated restore' >&2
	exit 1
fi

docker exec easysubway-postgres sh -lc \
	'pg_dump --format=custom --no-owner --no-privileges -U "$POSTGRES_USER" "$POSTGRES_DB"' > "${backup_file}"
[[ -s "${backup_file}" ]] || { echo 'production backup is empty' >&2; exit 1; }

postgres_image="$(docker inspect --format '{{.Config.Image}}' easysubway-postgres)"
gateway_image="$(docker inspect --format '{{.Image}}' easysubway-route-v2-gateway)"
[[ "${gateway_image}" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'gateway image ID is invalid' >&2; exit 1; }
docker network create --internal "${network}" >/dev/null
docker volume create "${volume}" >/dev/null
docker run -d --name "${clone_db}" --network "${network}" --network-alias postgres \
	--env-file "${postgres_env_file}" --mount "source=${volume},target=/var/lib/postgresql/data" \
	--cpus 1 --memory 1g --memory-swap 1g --pids-limit 256 "${postgres_image}" >/dev/null

db_ready=false
for _ in $(seq 1 90); do
	if [[ "$(docker exec "${clone_db}" cat /proc/1/comm 2>/dev/null || true)" == postgres ]] \
		&& docker exec "${clone_db}" sh -lc 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
		db_ready=true
		break
	fi
	sleep 1
done
[[ "${db_ready}" == true ]] || { echo 'isolated PostgreSQL readiness timed out' >&2; exit 1; }
docker exec -i "${clone_db}" sh -lc \
	'pg_restore --clean --if-exists --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < "${backup_file}"

clone_psql() {
	local sql="${1:?SQL is required}"
	docker exec "${clone_db}" sh -lc \
		'psql -X -v ON_ERROR_STOP=1 -A -t -U "$POSTGRES_USER" "$POSTGRES_DB" -c "$1"' sh "${sql}"
}

active_timetable_identity="$(clone_psql "
SELECT history.snapshot_id || '|' || history.snapshot_sha256 || '|' || TO_CHAR(history.fresh_until::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')
FROM timetable_snapshot_active active
JOIN timetable_snapshot_history history ON history.snapshot_sha256 = active.snapshot_sha256
WHERE active.singleton_id = 1 AND history.fresh_until::timestamptz > CURRENT_TIMESTAMP;")"
expected_timetable_identity="$(node -e '
const evidence = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(`${evidence.snapshotId}|${evidence.snapshotSha256}|${new Date(evidence.freshUntil).toISOString().replace(/\.\d{3}Z$/, "Z")}`);
' backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json)"
[[ "${active_timetable_identity}" == "${expected_timetable_identity}" ]] \
	|| { echo 'isolated restore timetable identity does not match checked-in evidence' >&2; exit 1; }
IFS='|' read -r snapshot_id snapshot_sha256 snapshot_fresh_until <<< "${active_timetable_identity}"
[[ "${snapshot_id}" =~ ^[A-Za-z0-9._-]+$ && "${snapshot_sha256}" =~ ^[0-9a-f]{64}$ \
	&& "${snapshot_fresh_until}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
	|| { echo 'timetable snapshot identity is invalid' >&2; exit 1; }
node -e '
const evidence = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
require("node:fs").writeFileSync(process.argv[2], JSON.stringify({
  timetableSnapshotSha256: evidence.snapshotSha256,
  canonicalPackSha256: evidence.canonicalPackIdentity.sha256,
  canonicalPackSqliteSha256: evidence.canonicalPackIdentity.sqliteSha256,
  canonicalStationVersion: evidence.canonicalStationSet.version,
  canonicalStationSetSha256: evidence.canonicalStationSet.sha256,
  sourceLineageSha256: evidence.sourceLineageSha256,
  evidenceHash: evidence.evidenceHash,
}));
' backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json "${planner_identity_file}"
itx_load_target="$(clone_psql "
WITH snapshot AS (
  SELECT history.fresh_until::timestamptz AS fresh_until
  FROM timetable_snapshot_active active
  JOIN timetable_snapshot_history history ON history.snapshot_sha256 = active.snapshot_sha256
  WHERE active.singleton_id = 1
), dates AS (
  SELECT day::date AS service_date, snapshot.fresh_until
  FROM snapshot
  CROSS JOIN LATERAL generate_series(
    (CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Seoul')::date,
    (snapshot.fresh_until AT TIME ZONE 'Asia/Seoul')::date,
    INTERVAL '1 day'
  ) day
), active_services AS (
  SELECT dates.service_date, dates.fresh_until, calendars.service_id
  FROM dates
  JOIN service_calendars calendars
    ON dates.service_date BETWEEN TO_DATE(calendars.start_date, 'YYYYMMDD') AND TO_DATE(calendars.end_date, 'YYYYMMDD')
  LEFT JOIN service_calendar_dates exceptions
    ON exceptions.service_id = calendars.service_id
   AND exceptions.date = TO_CHAR(dates.service_date, 'YYYYMMDD')
  WHERE (CASE EXTRACT(ISODOW FROM dates.service_date)
      WHEN 1 THEN calendars.monday WHEN 2 THEN calendars.tuesday WHEN 3 THEN calendars.wednesday
      WHEN 4 THEN calendars.thursday WHEN 5 THEN calendars.friday WHEN 6 THEN calendars.saturday
      WHEN 7 THEN calendars.sunday END
    AND COALESCE(exceptions.exception_type, 0) <> 2)
    OR exceptions.exception_type = 1
), candidates AS (
  SELECT origin.station_id AS origin_station_id, destination.station_id AS destination_station_id,
    ((active.service_date::timestamp + MAKE_INTERVAL(secs => origin.departure_seconds)) AT TIME ZONE 'Asia/Seoul') AS train_departure,
    ((active.service_date::timestamp + MAKE_INTERVAL(secs => destination.arrival_seconds)) AT TIME ZONE 'Asia/Seoul') AS train_arrival,
    active.fresh_until, destination.stop_sequence - origin.stop_sequence AS stop_span
  FROM active_services active
  JOIN transit_trips trips ON trips.service_id = active.service_id AND trips.service_class = 'ITX_CHEONGCHUN'
  JOIN transit_stop_times origin ON origin.trip_id = trips.id AND origin.pickup_type = 0
  JOIN transit_stop_times destination ON destination.trip_id = trips.id
    AND destination.stop_sequence > origin.stop_sequence AND destination.drop_off_type = 0
)
SELECT origin_station_id || '|' || destination_station_id || '|' ||
  TO_CHAR((train_departure - INTERVAL '15 minutes') AT TIME ZONE 'Asia/Seoul', 'YYYY-MM-DD\"T\"HH24:MI:SS\"+09:00\"')
FROM candidates
WHERE train_departure - INTERVAL '15 minutes' > CURRENT_TIMESTAMP + INTERVAL '1 minute'
  AND train_arrival < fresh_until
ORDER BY train_departure, stop_span DESC
LIMIT 1;")"
IFS='|' read -r origin_station_id destination_station_id departure_time <<< "${itx_load_target}"
[[ "${origin_station_id}" =~ ^station-[A-Za-z0-9_-]+$ && "${destination_station_id}" =~ ^station-[A-Za-z0-9_-]+$ \
	&& "${departure_time}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+09:00$ ]] \
	|| { echo 'no fresh active ITX-청춘 load target is available' >&2; exit 1; }

docker run -d --name "${clone_backend}" --network "${network}" --network-alias backend \
	--env-file "${backend_env_file}" \
	--cpus 1 --memory 1g --memory-swap 1g --pids-limit 256 \
	"${expected_image_id}" >/dev/null

# The isolated network is --internal, so it has no route to/from the host: neither
# --publish nor `docker port` work for containers on it (verified against Docker's
# bridge driver; the host cannot even reach a container's bridge IP directly). All
# HTTP access to the isolated backend/gateway must originate from a container that is
# itself attached to the isolated network. clone_curl is a dedicated, unmeasured
# helper for that purpose — built from the already-pulled backend image (which ships
# curl), kept out of docker_stats/OOM/restart sampling so load-generation traffic
# never taints the backend/gateway resource-peak evidence.
docker run -d --name "${clone_curl}" --network "${network}" --user "$(id -u):$(id -g)" --entrypoint sh \
	--cpus 1 --memory 128m --memory-swap 128m --pids-limit 64 \
	-v "${work_dir}:${work_dir}" \
	"${expected_image_id}" -c 'sleep infinity' >/dev/null
curl_helper_ready=false
for _ in $(seq 1 30); do
	if docker exec "${clone_curl}" curl --version >/dev/null 2>&1; then
		curl_helper_ready=true
		break
	fi
	sleep 1
done
[[ "${curl_helper_ready}" == true ]] || { echo 'isolated curl helper is missing curl or failed to start' >&2; exit 1; }

backend_ready=false
for _ in $(seq 1 120); do
	if [[ "$(docker exec "${clone_curl}" curl -sS --noproxy '*' --connect-timeout 1 --max-time 2 -o /dev/null -w '%{http_code}' "http://backend:8080/actuator/health/readiness" 2>/dev/null || true)" == 200 ]]; then
		backend_ready=true
		break
	fi
	sleep 1
done
[[ "${backend_ready}" == true ]] || { echo 'isolated backend readiness timed out' >&2; exit 1; }

docker run -d --name "${clone_gateway}" --network "${network}" --network-alias gateway --user 10001:10001 --read-only \
	--tmpfs /tmp:rw,nosuid,nodev \
	--env-file "${gateway_env_file}" \
	--cpus 1 --memory 256m --memory-swap 256m --pids-limit 128 \
	--entrypoint /etc/nginx/route-v2-entrypoint.sh \
	-v "${PWD}/infra/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
	-v "${PWD}/infra/nginx/route-v2-entrypoint.sh:/etc/nginx/route-v2-entrypoint.sh:ro" \
	-v "${PWD}/infra/nginx/route-v2-gateway.conf.template:/etc/nginx/templates/default.conf.template:ro" \
	-v "${PWD}/infra/nginx/route-v2-proxy-headers.conf.template:/etc/nginx/templates/route-v2-proxy-headers.inc.template:ro" \
	"${gateway_image}" nginx -g 'daemon off;' >/dev/null
gateway_base="http://gateway:8081"
gateway_ready=false
for _ in $(seq 1 60); do
	if [[ "$(docker exec "${clone_curl}" curl -sS --noproxy '*' --connect-timeout 1 --max-time 2 -o /dev/null -w '%{http_code}' "${gateway_base}/" 2>/dev/null || true)" == 404 ]]; then
		gateway_ready=true
		break
	fi
	sleep 1
done
[[ "${gateway_ready}" == true ]] || { echo 'isolated gateway readiness timed out' >&2; exit 1; }

node -e '
const { createHash, randomBytes } = require("node:crypto");
const { writeFileSync } = require("node:fs");
const rows = Array.from({ length: 20 }, () => {
  const token = randomBytes(32).toString("base64url");
  return `${token}\t${createHash("sha256").update(token).digest("hex")}`;
});
writeFileSync(process.argv[1], `${rows.join("\n")}\n`, { mode: 0o600 });
' "${tokens_file}"
: > "${issued_tokens_file}"

session_values=""
while IFS=$'\t' read -r _ hash; do
	[[ "${hash}" =~ ^[0-9a-f]{64}$ ]] || { echo 'synthetic session hash is invalid' >&2; exit 1; }
	[[ -z "${session_values}" ]] || session_values+=","
	session_values+="('${hash}', 'route:v2:itx', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '10 minutes', 0)"
done < "${tokens_file}"
clone_psql "INSERT INTO route_v2_sessions (token_sha256, scope, issued_at, expires_at, request_count) VALUES ${session_values};" >/dev/null

request_body="$(node -e '
process.stdout.write(JSON.stringify({
  originStationId: process.argv[1],
  destinationStationId: process.argv[2],
  departureTime: process.argv[3],
  transportScope: "SUBWAY_AND_ITX_CHEONGCHUN",
  objective: "FASTEST",
  mobilityType: "SENIOR",
  constraintMode: "ALLOW_WITH_WARNINGS",
  useRealtime: false,
  maxTransfers: 0,
  alternativeCount: 1,
}));
' "${origin_station_id}" "${destination_station_id}" "${departure_time}")"
request_index=0
last_status=""
last_headers=""
last_body=""

send_session() {
	local profile="${1:?profile is required}"
	local client_ip="${2:?client IP is required}"
	request_index=$((request_index + 1))
	last_headers="${work_dir}/headers-${request_index}.txt"
	last_body="${work_dir}/body-${request_index}.json"
	local result time_seconds latency_ms session_request
	session_request="$(node -e '
const { createHmac, randomBytes } = require("node:crypto");
const nonce = randomBytes(16).toString("base64url");
const signature = createHmac("sha256", Buffer.from(process.argv[1], "hex")).update(nonce).digest("base64url");
process.stdout.write(JSON.stringify({ integrityToken: `${nonce}.${signature}`, clientNonce: nonce }));
' "${synthetic_secret}")"
	result="$(docker exec "${clone_curl}" curl -sS --noproxy '*' --connect-timeout 2 --max-time 10 \
		-D "${last_headers}" -o "${last_body}" -w '%{http_code} %{time_total}' \
		--request POST --header 'content-type: application/json' \
		--header "CF-Connecting-IP: ${client_ip}" \
		--data-binary "${session_request}" \
		"${gateway_base}/api/v2/routes/session")"
	last_status="${result%% *}"
	time_seconds="${result#* }"
	latency_ms="$(node -e 'const value = Number(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); process.stdout.write(String(Math.round(value * 1000)));' "${time_seconds}")"
	printf '%s\t%s\t%s\n' "${profile}" "${last_status}" "${latency_ms}" >> "${metrics_file}"
	grep -Eqi '^Cache-Control:[[:space:]]*private,[[:space:]]*no-store[[:space:]]*\r?$' "${last_headers}" \
		|| { echo 'Route V2 session response is missing Cache-Control: private, no-store' >&2; exit 1; }
}

capture_issued_session() {
	node -e '
const { appendFileSync, readFileSync } = require("node:fs");
const { createHash } = require("node:crypto");
const value = JSON.parse(readFileSync(process.argv[1], "utf8"));
if (!/^[A-Za-z0-9_-]{43}$/.test(value?.token ?? "") || value.scope !== "route:v2:itx"
    || !Number.isFinite(Date.parse(value.issuedAt)) || !Number.isFinite(Date.parse(value.expiresAt))
    || Date.parse(value.expiresAt) <= Date.parse(value.issuedAt)) process.exit(1);
const row = `${value.token}\t${createHash("sha256").update(value.token).digest("hex")}\n`;
appendFileSync(process.argv[2], row);
appendFileSync(process.argv[3], row);
' "${last_body}" "${issued_tokens_file}" "${tokens_file}" \
		|| { echo 'normal session response is invalid' >&2; exit 1; }
}

send_search() {
	local profile="${1:?profile is required}"
	local token="${2:?token is required}"
	local client_ip="${3:?client IP is required}"
	request_index=$((request_index + 1))
	last_headers="${work_dir}/headers-${request_index}.txt"
	last_body="${work_dir}/body-${request_index}.json"
	local result time_seconds latency_ms
	result="$(docker exec "${clone_curl}" curl -sS --noproxy '*' --connect-timeout 2 --max-time 10 \
		-D "${last_headers}" -o "${last_body}" -w '%{http_code} %{time_total}' \
		--request POST --header 'content-type: application/json' \
		--header "CF-Connecting-IP: ${client_ip}" --header "Authorization: Bearer ${token}" \
		--data-binary "${request_body}" "${gateway_base}/api/v2/routes/search")"
	last_status="${result%% *}"
	time_seconds="${result#* }"
	latency_ms="$(node -e 'const value = Number(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); process.stdout.write(String(Math.round(value * 1000)));' "${time_seconds}")"
	printf '%s\t%s\t%s\n' "${profile}" "${last_status}" "${latency_ms}" >> "${metrics_file}"
	grep -Eqi '^Cache-Control:[[:space:]]*private,[[:space:]]*no-store[[:space:]]*\r?$' "${last_headers}" \
		|| { echo 'Route V2 response is missing Cache-Control: private, no-store' >&2; exit 1; }
}

validate_normal_search_body() {
	local body_file="${1:?body file is required}"
	local validation_status
	if node -e '
const value = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
const data = value?.data;
const itineraries = data?.itineraries;
if (!value?.success || !Array.isArray(itineraries) || itineraries.length === 0
    || data.statuses?.includes("NO_TIMETABLE_SERVICE") || data.statuses?.includes("STALE_TIMETABLE")
    || itineraries.some((itinerary) => !Array.isArray(itinerary.legs)
      || !itinerary.legs.some((leg) => leg.legType === "RIDE"))) {
  process.exit(10);
}
if (itineraries.some((itinerary) => !itinerary.legs.some((leg) =>
  leg.legType === "RIDE" && leg.serviceClass === "ITX_CHEONGCHUN"))) process.exit(12);
const identity = data.plannerIdentity;
const expected = JSON.parse(require("node:fs").readFileSync(process.argv[2], "utf8"));
if (identity?.timetableSnapshotSha256 !== expected.timetableSnapshotSha256
    || identity?.canonicalPackSha256 !== expected.canonicalPackSha256
    || identity?.canonicalPackSqliteSha256 !== expected.canonicalPackSqliteSha256
    || identity?.canonicalStationVersion !== expected.canonicalStationVersion
    || identity?.canonicalStationSetSha256 !== expected.canonicalStationSetSha256
    || identity?.sourceLineageSha256 !== expected.sourceLineageSha256
    || identity?.evidenceHash !== expected.evidenceHash) {
  process.exit(11);
}
' "${body_file}" "${planner_identity_file}"; then
		return 0
	else
		validation_status=$?
	fi
	case "${validation_status}" in
		10) echo 'normal search response has no itinerary' >&2 ;;
		11) echo 'normal search response planner identity mismatch' >&2 ;;
		12) echo 'normal search response has no ITX-청춘 ride' >&2 ;;
		*) echo 'normal search response is invalid' >&2 ;;
	esac
	return 1
}

sample_resources() {
	local backend_resource gateway_resource sampled_at_ms
	backend_resource="$(docker stats --no-stream --format '{{.MemPerc}} {{.CPUPerc}}' "${clone_backend}")"
	gateway_resource="$(docker stats --no-stream --format '{{.MemPerc}} {{.CPUPerc}}' "${clone_gateway}")"
	sampled_at_ms="$(date +%s%3N)"
	printf '%s %s %s\n' "${sampled_at_ms}" "${backend_resource}" "${gateway_resource}" >> "${resource_metrics_file}"
}

(
	while [[ ! -e "${resource_stop_file}" ]]; do
		sample_resources
		: > "${resource_ready_file}"
		sleep 1
	done
) &
resource_sampler_pid=$!
resource_ready_attempt=0
while [[ ! -e "${resource_ready_file}" ]]; do
	resource_ready_attempt=$((resource_ready_attempt + 1))
	(( resource_ready_attempt <= 100 )) || { echo 'load resource sampler readiness timed out' >&2; exit 1; }
	kill -0 "${resource_sampler_pid}" >/dev/null 2>&1 \
		|| { echo 'load resource sampler exited before readiness' >&2; exit 1; }
	sleep 0.1
done
load_started_ms="$(date +%s%3N)"
sample_resources

unexpected_error_count=0
for ((index = 0; index < session_rate; index += 1)); do
	send_session normal "198.51.100.$((index + 101))"
	[[ "${last_status}" == 200 ]] || { echo 'normal session profile did not return exact 200' >&2; exit 1; }
	capture_issued_session
done
for ((index = 0; index <= session_burst; index += 1)); do
	send_session burst 198.51.100.180
	[[ "${last_status}" == 200 ]] || { echo 'session limiter rejected before the configured burst was consumed' >&2; exit 1; }
	capture_issued_session
done
send_session burst 198.51.100.180
[[ "${last_status}" == 429 ]] || { echo 'session burst profile did not return exact 429' >&2; exit 1; }
grep -Eqi '^Retry-After: [1-9][0-9]*' "${last_headers}" || { echo 'session 429 is missing integer Retry-After' >&2; exit 1; }

mapfile -t tokens < <(cut -f 1 "${issued_tokens_file}")
mapfile -t seeded_tokens < <(head -n 20 "${tokens_file}" | cut -f 1)
(( ${#tokens[@]} >= session_rate && ${#seeded_tokens[@]} >= 2 )) || { echo 'not enough synthetic sessions' >&2; exit 1; }

normal_state_count_before="$(clone_psql "SELECT COUNT(*) FROM route_v2_states
WHERE origin_station_id = '${origin_station_id}'
  AND destination_station_id = '${destination_station_id}'
  AND requested_departure_at = '${departure_time}'::timestamptz
  AND timetable_artifact_id = '${snapshot_id}';")"
[[ "${normal_state_count_before}" =~ ^[0-9]+$ ]] || { echo 'normal state baseline is invalid' >&2; exit 1; }
for ((index = 0; index < search_rate; index += 1)); do
	send_search normal "${tokens[$((index % session_rate))]}" "198.51.100.$((index + 1))"
	[[ "${last_status}" == 200 ]] || { echo 'normal search profile did not return exact 200' >&2; exit 1; }
	validate_normal_search_body "${last_body}" || exit 1
done
normal_state_count_after="$(clone_psql "SELECT COUNT(*) FROM route_v2_states
WHERE origin_station_id = '${origin_station_id}'
  AND destination_station_id = '${destination_station_id}'
  AND requested_departure_at = '${departure_time}'::timestamptz
  AND timetable_artifact_id = '${snapshot_id}';")"
[[ "${normal_state_count_after}" =~ ^[0-9]+$ ]] || { echo 'normal state result is invalid' >&2; exit 1; }
(( normal_state_count_after - normal_state_count_before == search_rate )) \
	|| { echo 'normal search profile did not persist one state per request' >&2; exit 1; }
(( unexpected_error_count == 0 )) || { echo 'normal profile observed an unexpected status' >&2; exit 1; }

burst_token="${seeded_tokens[0]}"
burst_pids=()
burst_headers_files=()
burst_result_files=()
for ((index = 0; index <= search_burst; index += 1)); do
	request_index=$((request_index + 1))
	burst_headers="${work_dir}/headers-${request_index}.txt"
	burst_body="${work_dir}/body-${request_index}.json"
	burst_result="${work_dir}/result-${request_index}.txt"
	(
		docker exec "${clone_curl}" curl -sS --noproxy '*' --connect-timeout 2 --max-time 10 \
			-D "${burst_headers}" -o "${burst_body}" -w '%{http_code} %{time_total}' \
			--request POST --header 'content-type: application/json' \
			--header 'CF-Connecting-IP: 198.51.100.200' --header "Authorization: Bearer ${burst_token}" \
			--data-binary "${request_body}" "${gateway_base}/api/v2/routes/search" > "${burst_result}"
	) &
	burst_pids+=("$!")
	burst_headers_files+=("${burst_headers}")
	burst_result_files+=("${burst_result}")
done
for index in "${!burst_pids[@]}"; do
	burst_pid="${burst_pids[${index}]}"
	if ! wait "${burst_pid}"; then
		echo 'concurrent search burst request failed' >&2
		exit 1
	fi
	burst_result="$(<"${burst_result_files[${index}]}")"
	last_status="${burst_result%% *}"
	burst_time_seconds="${burst_result#* }"
	burst_latency_ms="$(node -e 'const value = Number(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); process.stdout.write(String(Math.round(value * 1000)));' "${burst_time_seconds}")"
	printf '%s\t%s\t%s\n' burst "${last_status}" "${burst_latency_ms}" >> "${metrics_file}"
	grep -Eqi '^Cache-Control:[[:space:]]*private,[[:space:]]*no-store[[:space:]]*\r?$' "${burst_headers_files[${index}]}" \
		|| { echo 'concurrent Route V2 response is missing Cache-Control: private, no-store' >&2; exit 1; }
	[[ "${last_status}" == 200 ]] \
		|| { echo 'search burst profile did not return exact 200 before rate limiting' >&2; exit 1; }
done
send_search burst "${burst_token}" 198.51.100.200
[[ "${last_status}" == 429 ]] || { echo 'burst profile did not return exact 429' >&2; exit 1; }
grep -Eqi '^Retry-After: [1-9][0-9]*' "${last_headers}" || { echo '429 response is missing integer Retry-After' >&2; exit 1; }
node -e '
const value = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (value.code !== "ROUTE_RATE_LIMITED") process.exit(1);
' "${last_body}" || { echo '429 response machine code mismatch' >&2; exit 1; }

clone_psql "UPDATE timetable_snapshot_history SET fresh_until = TO_CHAR((CURRENT_TIMESTAMP - INTERVAL '1 second') AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"') WHERE snapshot_sha256 = (SELECT snapshot_sha256 FROM timetable_snapshot_active WHERE singleton_id = 1);" >/dev/null
send_search unavailable "${seeded_tokens[1]}" 198.51.100.210
[[ "${last_status}" == 503 ]] || { echo 'unavailable profile did not return exact 503' >&2; exit 1; }
node -e '
const value = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (value.code !== "ITX_TIMETABLE_UNAVAILABLE") process.exit(1);
' "${last_body}" || { echo 'unavailable response machine code mismatch' >&2; exit 1; }
sample_resources
load_finished_ms="$(date +%s%3N)"
stop_resource_sampler || { echo 'load resource sampler failed' >&2; exit 1; }
resource_summary="$(node -e '
const rows = require("node:fs").readFileSync(process.argv[1], "utf8").trim().split(/\n/).filter(Boolean);
if (rows.length === 0) process.exit(1);
const samples = rows.map((line) => line.trim().split(/\s+/).map((value) => Number(value.replace(/%$/, ""))));
const loadStartedMs = Number(process.argv[2]);
const loadFinishedMs = Number(process.argv[3]);
if (!Number.isSafeInteger(loadStartedMs) || !Number.isSafeInteger(loadFinishedMs) || loadFinishedMs < loadStartedMs) process.exit(1);
if (samples.some((sample) => sample.length !== 5 || sample.some((value) => !Number.isFinite(value)))) process.exit(1);
const loadSamples = samples.filter(([sampledAtMs]) => sampledAtMs >= loadStartedMs && sampledAtMs <= loadFinishedMs);
if (loadSamples.length === 0) {
  process.stderr.write("load interval has no resource sample\n");
  process.exit(1);
}
const backendMemoryPeak = Math.max(...loadSamples.map(([, memory]) => memory));
const backendCpuPeak = Math.max(...loadSamples.map(([, , cpu]) => cpu));
const gatewayMemoryPeak = Math.max(...loadSamples.map(([, , , memory]) => memory));
const gatewayCpuPeak = Math.max(...loadSamples.map(([, , , , cpu]) => cpu));
process.stdout.write(`${backendMemoryPeak} ${backendCpuPeak} ${gatewayMemoryPeak} ${gatewayCpuPeak} ${loadSamples.length}`);
' "${resource_metrics_file}" "${load_started_ms}" "${load_finished_ms}")" \
	|| { echo 'load resource samples are invalid' >&2; exit 1; }
read -r backend_memory_peak backend_cpu_peak gateway_memory_peak gateway_cpu_peak resource_sample_count <<< "${resource_summary}"
[[ "${backend_memory_peak}" =~ ^[0-9]+([.][0-9]+)?$ && "${backend_cpu_peak}" =~ ^[0-9]+([.][0-9]+)?$ \
	&& "${gateway_memory_peak}" =~ ^[0-9]+([.][0-9]+)?$ && "${gateway_cpu_peak}" =~ ^[0-9]+([.][0-9]+)?$ \
	&& "${resource_sample_count}" =~ ^[1-9][0-9]*$ ]] || { echo 'load resource peak summary is invalid' >&2; exit 1; }

expired_hash="$(node -e 'process.stdout.write(require("node:crypto").createHash("sha256").update("issue-2095-expired-session").digest("hex"))')"
expired_nonce_hash="$(node -e 'process.stdout.write(require("node:crypto").createHash("sha256").update("issue-2095-expired-nonce").digest("hex"))')"
purge_budget_ms=600000
purge_started_ms="$(date +%s%3N)"
purge_deadline_ms=$((purge_started_ms + purge_budget_ms))
clone_psql "
INSERT INTO route_v2_sessions (token_sha256, scope, issued_at, expires_at, request_count)
VALUES ('${expired_hash}', 'route:v2:itx', CURRENT_TIMESTAMP - INTERVAL '20 minutes', CURRENT_TIMESTAMP - INTERVAL '10 minutes', 0);
INSERT INTO route_v2_nonce_replays (nonce_sha256, expires_at)
VALUES ('${expired_nonce_hash}', CURRENT_TIMESTAMP - INTERVAL '10 minutes');
INSERT INTO route_v2_states (route_state_id, origin_station_id, destination_station_id, transport_scope,
  requested_departure_at, itinerary_json, timetable_artifact_id, created_at, planned_arrival_at, expires_at)
VALUES ('route-2095-expired', 'synthetic-origin', 'synthetic-destination', 'SUBWAY_AND_ITX_CHEONGCHUN',
	  CURRENT_TIMESTAMP - INTERVAL '7 hours', '{}', 'synthetic-2095',
	  CURRENT_TIMESTAMP - INTERVAL '7 hours', CURRENT_TIMESTAMP - INTERVAL '7 hours', CURRENT_TIMESTAMP - INTERVAL '6 hours 30 minutes');" >/dev/null
synthetic_purge_remaining="1|1|1"
while true; do
	synthetic_purge_remaining="$(clone_psql "SELECT
  (SELECT COUNT(*) FROM route_v2_states WHERE route_state_id = 'route-2095-expired'),
  (SELECT COUNT(*) FROM route_v2_sessions WHERE token_sha256 = '${expired_hash}'),
  (SELECT COUNT(*) FROM route_v2_nonce_replays WHERE nonce_sha256 = '${expired_nonce_hash}');")"
	[[ "${synthetic_purge_remaining}" == "0|0|0" ]] && break
	current_time_ms="$(date +%s%3N)"
	(( current_time_ms < purge_deadline_ms )) || break
	sleep 1
done
purge_finished_ms="$(date +%s%3N)"
purge_ms=$((purge_finished_ms - purge_started_ms))
[[ "${synthetic_purge_remaining}" == "0|0|0" ]] \
	|| { echo 'application purge path did not delete all synthetic expired rows' >&2; exit 1; }
(( purge_ms <= purge_budget_ms )) || { echo 'purge exceeded the 10 minute deletion budget' >&2; exit 1; }
purged_states=1
purged_sessions=1
purged_nonces=1

docker logs "${clone_backend}" > "${logs_file}" 2>&1
docker logs "${clone_gateway}" >> "${logs_file}" 2>&1
for synthetic_credential in "${clone_db_password}" "${synthetic_secret}" "${synthetic_certificate_digest}"; do
	if grep -Fq -- "${synthetic_credential}" "${logs_file}"; then
		echo 'synthetic credential appeared in service logs' >&2
		exit 1
	fi
done
grep -Fq 'route V2 timetable cache result=miss' "${logs_file}" || { echo 'cache miss evidence is missing' >&2; exit 1; }
grep -Fq 'route V2 timetable cache result=hit' "${logs_file}" || { echo 'cache hit evidence is missing' >&2; exit 1; }
grep -Eq 'Purged [1-9][0-9]* expired Route V2 state rows' "${logs_file}" \
	|| { echo 'application purge scheduler evidence is missing' >&2; exit 1; }
if grep -Eqi 'Authorization:|Bearer [A-Za-z0-9_-]+|CF-Connecting-IP' "${logs_file}" \
	|| grep -Fq -- "${origin_station_id}" "${logs_file}" \
	|| grep -Fq -- "${destination_station_id}" "${logs_file}"; then
	echo 'service logs contain a forbidden request identifier' >&2
	exit 1
fi
while IFS=$'\t' read -r token hash; do
	if grep -Fq "${token}" "${logs_file}" || grep -Fq "${hash}" "${logs_file}"; then
		echo 'service logs contain a synthetic session credential' >&2
		exit 1
	fi
done < "${tokens_file}"
for forbidden_column in integrity_token session_token raw_token raw_nonce ip_address device_id account_id raw_search latitude longitude; do
	column_count="$(clone_psql "SELECT COUNT(*) FROM information_schema.columns WHERE table_name IN ('route_v2_sessions', 'route_v2_nonce_replays', 'route_v2_states') AND column_name = '${forbidden_column}';")"
	[[ "${column_count}" == 0 ]] || { echo 'Route V2 storage contains a forbidden raw column' >&2; exit 1; }
done

latency_summary="$(node -e '
const rows = require("node:fs").readFileSync(process.argv[1], "utf8").trim().split(/\n/).filter(Boolean)
  .map((line) => Number(line.split("\t")[2])).sort((a, b) => a - b);
const percentile = (p) => rows[Math.max(0, Math.ceil(rows.length * p) - 1)];
process.stdout.write(`p50=${percentile(0.50)} p95=${percentile(0.95)} p99=${percentile(0.99)} max=${rows.at(-1)}`);
' "${metrics_file}")"
status_summary="$(node -e '
const rows = require("node:fs").readFileSync(process.argv[1], "utf8").trim().split(/\n/).filter(Boolean);
const counts = new Map();
for (const row of rows) {
  const status = row.split("\t")[1];
  counts.set(status, (counts.get(status) ?? 0) + 1);
}
process.stdout.write([...counts].sort(([left], [right]) => left.localeCompare(right)).map(([status, count]) => `${status}=${count}`).join(","));
' "${metrics_file}")"
p95="$(sed -nE 's/.*p95=([0-9]+).*/\1/p' <<< "${latency_summary}")"
p99="$(sed -nE 's/.*p99=([0-9]+).*/\1/p' <<< "${latency_summary}")"
[[ "${p95}" =~ ^[0-9]+$ && "${p99}" =~ ^[0-9]+$ ]] || { echo 'latency percentile output is invalid' >&2; exit 1; }
(( p95 <= 2000 )) || { echo 'p95 latency exceeded 2000 ms' >&2; exit 1; }
(( p99 <= 5000 )) || { echo 'p99 latency exceeded 5000 ms' >&2; exit 1; }

oom_killed="$(docker inspect --format '{{.State.OOMKilled}}' "${clone_backend}")"
restart_count="$(docker inspect --format '{{.RestartCount}}' "${clone_backend}")"
[[ "${oom_killed}" == false && "${restart_count}" == 0 ]] || { echo 'isolated backend restarted or was OOM-killed' >&2; exit 1; }
gateway_oom_killed="$(docker inspect --format '{{.State.OOMKilled}}' "${clone_gateway}")"
gateway_restart_count="$(docker inspect --format '{{.RestartCount}}' "${clone_gateway}")"
[[ "${gateway_oom_killed}" == false && "${gateway_restart_count}" == 0 ]] \
	|| { echo 'isolated gateway restarted or was OOM-killed' >&2; exit 1; }

[[ "$(public_status /api/v2/routes/session)" == 404 && "$(public_status /api/v2/routes/search)" == 404 ]] \
	|| { echo 'production Route V2 ingress changed during isolated evidence' >&2; exit 1; }

trap - EXIT
if ! cleanup; then
	echo 'isolated capacity evidence cleanup failed' >&2
	exit 1
fi

summary_file="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
{
	echo '### Production Route V2 capacity evidence'
	echo "- deployed SHA: \`${current_sha}\`"
	echo "- image digest: \`${current_digest}\`"
	echo "- timetable: \`${snapshot_id}\`, SHA-256 \`${snapshot_sha256}\`, freshUntil \`${snapshot_fresh_until}\`"
	echo "- configured limits: session ${session_rate}/m burst ${session_burst}; search ${search_rate}/m burst ${search_burst}"
	echo "- profile=normal: PASS, session_requests=${session_rate}, search_requests=${search_rate}, unexpected_error_count=0"
	echo "- profile=burst: PASS, exact 429 + Retry-After + private, no-store"
	echo '- profile=unavailable: PASS, exact 503 ITX_TIMETABLE_UNAVAILABLE'
	echo "- HTTP status counts: ${status_summary}"
	echo "- latency: ${latency_summary} ms"
	echo "- backend resource during load: memory_peak=${backend_memory_peak}% cpu_peak=${backend_cpu_peak}% samples=${resource_sample_count}, OOM=false, restart=0"
	echo "- gateway resource during load: memory_peak=${gateway_memory_peak}% cpu_peak=${gateway_cpu_peak}% samples=${resource_sample_count}, OOM=false, restart=0"
	echo "- purge: states=${purged_states} sessions=${purged_sessions} nonces=${purged_nonces} duration_ms=${purge_ms}, budget_ms=600000"
	echo '- isolated synthetic data cleanup: PASS'
	echo '- cache: miss=1+, hit=1+'
	echo '- privacy: undeclared_data_transfer_count=0, sensitive_payload_count=0'
	echo '- ingress_closed=true'
} >> "${summary_file}"
