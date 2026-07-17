#!/usr/bin/env bash
set -euo pipefail

umask 077

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/easysubway}"
EXPECTED_DEPLOYED_SHA="${EXPECTED_DEPLOYED_SHA:?EXPECTED_DEPLOYED_SHA is required}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://easysubway-api.aquilaxk.site}"
[[ "${EXPECTED_DEPLOYED_SHA}" =~ ^[0-9a-f]{40}$ ]] || { echo 'expected deployed SHA is invalid' >&2; exit 2; }
[[ "${PUBLIC_BASE_URL}" == https://* ]] || { echo 'public base URL must use HTTPS' >&2; exit 2; }

exec 9>"${DEPLOY_ROOT}/deploy.lock"
flock -w 300 9 || { echo 'timed out waiting for deployment lock' >&2; exit 1; }

current_sha="$(<"${DEPLOY_ROOT}/shared/current-sha")"
current_digest="$(<"${DEPLOY_ROOT}/shared/current-image-digest")"
compose_env="${DEPLOY_ROOT}/shared/current-env/compose.env"
[[ "${current_sha}" == "${EXPECTED_DEPLOYED_SHA}" ]] || { echo 'deployed SHA does not match requested evidence SHA' >&2; exit 1; }
[[ "${current_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'deployed image digest marker is invalid' >&2; exit 1; }
[[ -f "${compose_env}" ]] || { echo 'current compose environment is missing' >&2; exit 1; }

read_env_value() {
	local file="${1:?file is required}"
	local name="${2:?name is required}"
	local line
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ "${line}" == "${name}="* ]] || continue
		printf '%s\n' "${line#*=}"
		return 0
	done < "${file}"
	return 1
}

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
work_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/issue-2095-capacity.XXXXXX")"
backup_file="${work_dir}/production.dump"
postgres_env_file="${work_dir}/postgres.env"
backend_env_file="${work_dir}/backend.env"
gateway_env_file="${work_dir}/gateway.env"
tokens_file="${work_dir}/tokens.tsv"
metrics_file="${work_dir}/metrics.tsv"
logs_file="${work_dir}/service.log"

cleanup() {
	local cleanup_failed=0
	local container
	for container in "${clone_gateway}" "${clone_backend}" "${clone_db}"; do
		if docker container inspect "${container}" >/dev/null 2>&1 \
			&& ! docker rm -f "${container}" >/dev/null 2>&1; then
			cleanup_failed=1
		fi
	done
	if docker volume inspect "${volume}" >/dev/null 2>&1 \
		&& ! docker volume rm "${volume}" >/dev/null 2>&1; then
		cleanup_failed=1
	fi
	if docker network inspect "${network}" >/dev/null 2>&1 \
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

docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' easysubway-postgres > "${postgres_env_file}"
docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' easysubway-backend > "${backend_env_file}"
docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' easysubway-route-v2-gateway > "${gateway_env_file}"
chmod 600 "${postgres_env_file}" "${backend_env_file}" "${gateway_env_file}"

postgres_user="$(read_env_value "${postgres_env_file}" POSTGRES_USER)"
postgres_db="$(read_env_value "${postgres_env_file}" POSTGRES_DB)"
[[ "${postgres_user}" =~ ^[A-Za-z0-9_.-]+$ && "${postgres_db}" =~ ^[A-Za-z0-9_.-]+$ ]] \
	|| { echo 'production PostgreSQL identity is invalid' >&2; exit 1; }

docker exec easysubway-postgres sh -lc \
	'pg_dump --format=custom --no-owner --no-privileges -U "$POSTGRES_USER" "$POSTGRES_DB"' > "${backup_file}"
[[ -s "${backup_file}" ]] || { echo 'production backup is empty' >&2; exit 1; }

postgres_image="$(docker inspect --format '{{.Config.Image}}' easysubway-postgres)"
gateway_image="$(docker inspect --format '{{.Config.Image}}' easysubway-route-v2-gateway)"
docker network create --internal "${network}" >/dev/null
docker volume create "${volume}" >/dev/null
docker run -d --name "${clone_db}" --network "${network}" --network-alias postgres \
	--env-file "${postgres_env_file}" --mount "source=${volume},target=/var/lib/postgresql/data" \
	--cpus 1 --memory 1g --memory-swap 1g --pids-limit 256 "${postgres_image}" >/dev/null

db_ready=false
for _ in $(seq 1 90); do
	if docker exec "${clone_db}" sh -lc 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
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
SELECT history.snapshot_id || '|' || history.snapshot_sha256 || '|' || TO_CHAR(history.fresh_until AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')
FROM timetable_snapshot_active active
JOIN timetable_snapshot_history history ON history.snapshot_sha256 = active.snapshot_sha256
WHERE active.singleton_id = 1 AND history.fresh_until > CURRENT_TIMESTAMP;")"
expected_timetable_identity="$(node -e '
const evidence = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(`${evidence.snapshotId}|${evidence.snapshotSha256}|${new Date(evidence.freshUntil).toISOString().replace(/\.\d{3}Z$/, "Z")}`);
' backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json)"
[[ "${active_timetable_identity}" == "${expected_timetable_identity}" ]] \
	|| { echo 'isolated restore timetable identity does not match checked-in evidence' >&2; exit 1; }
IFS='|' read -r snapshot_id snapshot_sha256 snapshot_fresh_until <<< "${active_timetable_identity}"
departure_time="$(node -e '
const now = Date.now();
const freshUntil = Date.parse(process.argv[1]);
const departure = Math.min(now + 5 * 60_000, freshUntil - 5 * 60_000);
if (!Number.isFinite(freshUntil) || departure <= now) process.exit(1);
process.stdout.write(new Date(departure + 9 * 60 * 60_000).toISOString().replace(/\.\d{3}Z$/, "+09:00"));
' "${snapshot_fresh_until}")" || { echo 'fresh timetable window is too short for capacity evidence' >&2; exit 1; }

docker run -d --name "${clone_backend}" --network "${network}" --network-alias backend \
	--env-file "${backend_env_file}" \
	-e "EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql://postgres:5432/${postgres_db}" \
	-e EASYSUBWAY_SCHEDULING_ENABLED=false \
	-e EASYSUBWAY_PUSH_EXTERNAL_ENABLED=false \
	-e EASYSUBWAY_PUSH_DELIVERY_ENABLED=false \
	-e EASYSUBWAY_TIMETABLE_SEED_ENABLED=false \
	--cpus 1 --memory 1g --memory-swap 1g --pids-limit 256 \
	--publish 127.0.0.1::8080 "${backend_image}" >/dev/null

backend_binding="$(docker port "${clone_backend}" 8080/tcp)"
[[ "${backend_binding}" =~ ^127\.0\.0\.1:[0-9]+$ ]] || { echo 'isolated backend binding is invalid' >&2; exit 1; }
backend_ready=false
for _ in $(seq 1 120); do
	if [[ "$(curl -sS --noproxy '*' --connect-timeout 1 --max-time 2 -o /dev/null -w '%{http_code}' "http://${backend_binding}/actuator/health/readiness" 2>/dev/null || true)" == 200 ]]; then
		backend_ready=true
		break
	fi
	sleep 1
done
[[ "${backend_ready}" == true ]] || { echo 'isolated backend readiness timed out' >&2; exit 1; }

docker run -d --name "${clone_gateway}" --network "${network}" --user 10001:10001 --read-only \
	--tmpfs /tmp:rw,nosuid,nodev --publish 127.0.0.1::8081 \
	--env-file "${gateway_env_file}" \
	--entrypoint /etc/nginx/route-v2-entrypoint.sh \
	-v "${PWD}/infra/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
	-v "${PWD}/infra/nginx/route-v2-entrypoint.sh:/etc/nginx/route-v2-entrypoint.sh:ro" \
	-v "${PWD}/infra/nginx/route-v2-gateway.conf.template:/etc/nginx/templates/default.conf.template:ro" \
	-v "${PWD}/infra/nginx/route-v2-proxy-headers.conf.template:/etc/nginx/templates/route-v2-proxy-headers.inc.template:ro" \
	"${gateway_image}" nginx -g 'daemon off;' >/dev/null
gateway_binding="$(docker port "${clone_gateway}" 8081/tcp)"
[[ "${gateway_binding}" =~ ^127\.0\.0\.1:[0-9]+$ ]] || { echo 'isolated gateway binding is invalid' >&2; exit 1; }
gateway_base="http://${gateway_binding}"
gateway_ready=false
for _ in $(seq 1 60); do
	if [[ "$(curl -sS --noproxy '*' --connect-timeout 1 --max-time 2 -o /dev/null -w '%{http_code}' "${gateway_base}/" 2>/dev/null || true)" == 404 ]]; then
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

session_values=""
while IFS=$'\t' read -r _ hash; do
	[[ "${hash}" =~ ^[0-9a-f]{64}$ ]] || { echo 'synthetic session hash is invalid' >&2; exit 1; }
	[[ -z "${session_values}" ]] || session_values+=","
	session_values+="('${hash}', 'route:v2:itx', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '10 minutes', 0)"
done < "${tokens_file}"
clone_psql "INSERT INTO route_v2_sessions (token_sha256, scope, issued_at, expires_at, request_count) VALUES ${session_values};" >/dev/null

request_body="$(node -e '
process.stdout.write(JSON.stringify({
  originStationId: "station-sangnoksu",
  destinationStationId: "station-sadang",
  departureTime: process.argv[1],
  mobilityType: "SENIOR",
  constraintMode: "ALLOW_WITH_WARNINGS",
  useRealtime: false,
  maxTransfers: 3,
  alternativeCount: 1,
}));
' "${departure_time}")"
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
	local result time_seconds latency_ms
	result="$(curl -sS --noproxy '*' --connect-timeout 2 --max-time 10 \
		-D "${last_headers}" -o "${last_body}" -w '%{http_code} %{time_total}' \
		--request POST --header 'content-type: application/json' \
		--header "CF-Connecting-IP: ${client_ip}" \
		--data-binary '{"integrityToken":"invalid","clientNonce":"AAAAAAAAAAAAAAAAAAAAAA"}' \
		"${gateway_base}/api/v2/routes/session")"
	last_status="${result%% *}"
	time_seconds="${result#* }"
	latency_ms="$(node -e 'const value = Number(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); process.stdout.write(String(Math.round(value * 1000)));' "${time_seconds}")"
	printf '%s\t%s\t%s\n' "${profile}" "${last_status}" "${latency_ms}" >> "${metrics_file}"
	grep -Eqi '^Cache-Control: private, no-store' "${last_headers}" \
		|| { echo 'Route V2 session response is missing Cache-Control: private, no-store' >&2; exit 1; }
}

send_search() {
	local profile="${1:?profile is required}"
	local token="${2:?token is required}"
	local client_ip="${3:?client IP is required}"
	request_index=$((request_index + 1))
	last_headers="${work_dir}/headers-${request_index}.txt"
	last_body="${work_dir}/body-${request_index}.json"
	local result time_seconds latency_ms
	result="$(curl -sS --noproxy '*' --connect-timeout 2 --max-time 10 \
		-D "${last_headers}" -o "${last_body}" -w '%{http_code} %{time_total}' \
		--request POST --header 'content-type: application/json' \
		--header "CF-Connecting-IP: ${client_ip}" --header "Authorization: Bearer ${token}" \
		--data-binary "${request_body}" "${gateway_base}/api/v2/routes/search")"
	last_status="${result%% *}"
	time_seconds="${result#* }"
	latency_ms="$(node -e 'const value = Number(process.argv[1]); if (!Number.isFinite(value)) process.exit(1); process.stdout.write(String(Math.round(value * 1000)));' "${time_seconds}")"
	printf '%s\t%s\t%s\n' "${profile}" "${last_status}" "${latency_ms}" >> "${metrics_file}"
	grep -Eqi '^Cache-Control: private, no-store' "${last_headers}" \
		|| { echo 'Route V2 response is missing Cache-Control: private, no-store' >&2; exit 1; }
}

mapfile -t tokens < <(cut -f 1 "${tokens_file}")
(( ${#tokens[@]} >= search_rate + 3 )) || { echo 'not enough synthetic sessions' >&2; exit 1; }
unexpected_error_count=0
for ((index = 0; index < session_rate; index += 1)); do
	send_session normal "198.51.100.$((index + 101))"
	case "${last_status}" in
		403|503) ;;
		*) echo 'normal session profile observed an unexpected status' >&2; exit 1 ;;
	esac
done
for ((index = 0; index <= session_burst; index += 1)); do
	send_session burst 198.51.100.180
	case "${last_status}" in
		403|503) ;;
		429) echo 'session limiter rejected before the configured burst was consumed' >&2; exit 1 ;;
		*) echo 'session burst profile observed an unexpected status' >&2; exit 1 ;;
	esac
done
send_session burst 198.51.100.180
[[ "${last_status}" == 429 ]] || { echo 'session burst profile did not return exact 429' >&2; exit 1; }
grep -Eqi '^Retry-After: [1-9][0-9]*' "${last_headers}" || { echo 'session 429 is missing integer Retry-After' >&2; exit 1; }

for ((index = 0; index < search_rate; index += 1)); do
	send_search normal "${tokens[${index}]}" "198.51.100.$((index + 1))"
	case "${last_status}" in
		200|503) ;;
		*) unexpected_error_count=$((unexpected_error_count + 1)) ;;
	esac
done
(( unexpected_error_count == 0 )) || { echo 'normal profile observed an unexpected status' >&2; exit 1; }

# ponytail: planner completion belongs to #2098; capacity accepts its current 200/503 contract states.
burst_token="${tokens[${search_rate}]}"
burst_pids=()
burst_headers_files=()
burst_result_files=()
for ((index = 0; index <= search_burst; index += 1)); do
	request_index=$((request_index + 1))
	burst_headers="${work_dir}/headers-${request_index}.txt"
	burst_body="${work_dir}/body-${request_index}.json"
	burst_result="${work_dir}/result-${request_index}.txt"
	(
		curl -sS --noproxy '*' --connect-timeout 2 --max-time 10 \
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
	grep -Eqi '^Cache-Control: private, no-store' "${burst_headers_files[${index}]}" \
		|| { echo 'concurrent Route V2 response is missing Cache-Control: private, no-store' >&2; exit 1; }
	case "${last_status}" in
		200|503) ;;
		429) echo 'burst limiter rejected before the configured burst was consumed' >&2; exit 1 ;;
		*) echo 'search burst profile observed an unexpected status' >&2; exit 1 ;;
	esac
done
send_search burst "${burst_token}" 198.51.100.200
[[ "${last_status}" == 429 ]] || { echo 'burst profile did not return exact 429' >&2; exit 1; }
grep -Eqi '^Retry-After: [1-9][0-9]*' "${last_headers}" || { echo '429 response is missing integer Retry-After' >&2; exit 1; }
node -e '
const value = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (value.code !== "ROUTE_RATE_LIMITED") process.exit(1);
' "${last_body}" || { echo '429 response machine code mismatch' >&2; exit 1; }

clone_psql "UPDATE timetable_snapshot_history SET fresh_until = CURRENT_TIMESTAMP - INTERVAL '1 second' WHERE snapshot_sha256 = (SELECT snapshot_sha256 FROM timetable_snapshot_active WHERE singleton_id = 1);" >/dev/null
send_search unavailable "${tokens[$((search_rate + 1))]}" 198.51.100.210
[[ "${last_status}" == 503 ]] || { echo 'unavailable profile did not return exact 503' >&2; exit 1; }
node -e '
const value = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (value.code !== "ITX_TIMETABLE_UNAVAILABLE") process.exit(1);
' "${last_body}" || { echo 'unavailable response machine code mismatch' >&2; exit 1; }

expired_hash="$(node -e 'process.stdout.write(require("node:crypto").createHash("sha256").update("issue-2095-expired-session").digest("hex"))')"
expired_baseline="$(clone_psql "SELECT
  (SELECT COUNT(*) FROM route_v2_states WHERE expires_at <= CURRENT_TIMESTAMP),
  (SELECT COUNT(*) FROM route_v2_sessions WHERE expires_at <= CURRENT_TIMESTAMP),
  (SELECT COUNT(*) FROM route_v2_nonce_replays WHERE expires_at <= CURRENT_TIMESTAMP);")"
IFS='|' read -r baseline_expired_states baseline_expired_sessions baseline_expired_nonces <<< "${expired_baseline}"
for baseline_count in "${baseline_expired_states}" "${baseline_expired_sessions}" "${baseline_expired_nonces}"; do
	[[ "${baseline_count}" =~ ^[0-9]+$ ]] || { echo 'expired-row baseline is invalid' >&2; exit 1; }
done
expected_purged_states=$((baseline_expired_states + 1))
expected_purged_sessions=$((baseline_expired_sessions + 1))
expected_purged_nonces=${baseline_expired_nonces}
clone_psql "
INSERT INTO route_v2_sessions (token_sha256, scope, issued_at, expires_at, request_count)
VALUES ('${expired_hash}', 'route:v2:itx', CURRENT_TIMESTAMP - INTERVAL '20 minutes', CURRENT_TIMESTAMP - INTERVAL '10 minutes', 0);
INSERT INTO route_v2_states (route_state_id, origin_station_id, destination_station_id, transport_scope,
  requested_departure_at, itinerary_json, timetable_artifact_id, created_at, planned_arrival_at, expires_at)
VALUES ('route-2095-expired', 'synthetic-origin', 'synthetic-destination', 'SUBWAY_AND_ITX_CHEONGCHUN',
  CURRENT_TIMESTAMP - INTERVAL '7 hours', '{}', 'synthetic-2095',
  CURRENT_TIMESTAMP - INTERVAL '7 hours', CURRENT_TIMESTAMP - INTERVAL '7 hours', CURRENT_TIMESTAMP - INTERVAL '6 hours 30 minutes');" >/dev/null
purge_started_ms="$(date +%s%3N)"
purged_counts="$(clone_psql "WITH states AS (DELETE FROM route_v2_states WHERE expires_at <= CURRENT_TIMESTAMP RETURNING 1), sessions AS (DELETE FROM route_v2_sessions WHERE expires_at <= CURRENT_TIMESTAMP RETURNING 1), nonces AS (DELETE FROM route_v2_nonce_replays WHERE expires_at <= CURRENT_TIMESTAMP RETURNING 1) SELECT (SELECT COUNT(*) FROM states), (SELECT COUNT(*) FROM sessions), (SELECT COUNT(*) FROM nonces);")"
purge_finished_ms="$(date +%s%3N)"
purge_ms=$((purge_finished_ms - purge_started_ms))
IFS='|' read -r purged_states purged_sessions purged_nonces <<< "${purged_counts}"
[[ "${purged_states}" == "${expected_purged_states}" \
	&& "${purged_sessions}" == "${expected_purged_sessions}" \
	&& "${purged_nonces}" == "${expected_purged_nonces}" ]] \
	|| { echo 'purge profile did not delete the baseline plus synthetic expired rows' >&2; exit 1; }
(( purge_ms <= 600000 )) || { echo 'purge exceeded the 10 minute deletion budget' >&2; exit 1; }

docker logs "${clone_backend}" > "${logs_file}" 2>&1
docker logs "${clone_gateway}" >> "${logs_file}" 2>&1
grep -Fq 'route V2 timetable cache result=miss' "${logs_file}" || { echo 'cache miss evidence is missing' >&2; exit 1; }
grep -Fq 'route V2 timetable cache result=hit' "${logs_file}" || { echo 'cache hit evidence is missing' >&2; exit 1; }
if grep -Eqi 'Authorization:|Bearer [A-Za-z0-9_-]+|CF-Connecting-IP|station-sangnoksu|station-sadang' "${logs_file}"; then
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
resource_sample="$(docker stats --no-stream --format '{{.MemPerc}} memory, {{.CPUPerc}} cpu' "${clone_backend}")"
[[ -n "${resource_sample}" ]] || { echo 'resource sample is missing' >&2; exit 1; }

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
	echo "- resource: ${resource_sample}, OOM=false, restart=0"
	echo "- purge: states=${purged_states} sessions=${purged_sessions} nonces=${purged_nonces} duration_ms=${purge_ms}, budget_ms=600000"
	echo '- isolated synthetic data cleanup: PASS'
	echo '- cache: miss=1+, hit=1+'
	echo '- privacy: undeclared_data_transfer_count=0, sensitive_payload_count=0'
	echo '- ingress_closed=true'
} >> "${summary_file}"
