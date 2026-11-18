#!/usr/bin/env bash
set -euo pipefail

umask 077

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/easysubway}"
EXPECTED_DEPLOYED_SHA="${EXPECTED_DEPLOYED_SHA:?EXPECTED_DEPLOYED_SHA is required}"
[[ "${EXPECTED_DEPLOYED_SHA}" =~ ^[0-9a-f]{40}$ ]] || { echo 'expected deployed SHA is invalid' >&2; exit 2; }

exec 9>"${DEPLOY_ROOT}/deploy.lock"
flock -w 300 9 || { echo 'timed out waiting for deployment lock' >&2; exit 1; }

current_sha="$(<"${DEPLOY_ROOT}/shared/current-sha")"
if [[ "${current_sha}" != "${EXPECTED_DEPLOYED_SHA}" ]]; then
	echo 'current_sha != EXPECTED_DEPLOYED_SHA' >&2
	exit 1
fi

backend_image="easysubway-backend:${current_sha}"
current_image_digest="$(<"${DEPLOY_ROOT}/shared/current-image-digest")"
[[ "${current_image_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] \
	|| { echo 'deployed image digest marker is invalid' >&2; exit 1; }
image_revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${backend_image}")"
[[ "${image_revision}" == "${current_sha}" ]] || { echo 'backend image revision mismatch' >&2; exit 1; }
image_repo_digests="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "${backend_image}")"
grep -Fxq "ghcr.io/aquilaxk/easysubway-backend@${current_image_digest}" <<< "${image_repo_digests}" \
	|| { echo 'backend image immutable digest mismatch' >&2; exit 1; }
expected_image_id="$(docker image inspect --format '{{.Id}}' "${backend_image}")"
runtime_config_image="$(docker inspect --format '{{.Config.Image}}' easysubway-backend)"
runtime_image_id="$(docker inspect --format '{{.Image}}' easysubway-backend)"
[[ "${runtime_config_image}" == "${backend_image}" ]] || { echo 'running backend image tag mismatch' >&2; exit 1; }
[[ "${runtime_image_id}" == "${expected_image_id}" ]] || { echo 'running backend image ID mismatch' >&2; exit 1; }

production_psql() {
	local sql="${1:?SQL is required}"
	docker exec easysubway-postgres sh -lc \
		'psql -X -v ON_ERROR_STOP=1 -A -t -F "|" -U "$POSTGRES_USER" "$POSTGRES_DB" -c "$1"' sh "${sql}"
}

identity_sql="
SELECT active.snapshot_sha256, history.snapshot_id, history.schema_identity,
  history.source_artifact_id, history.source_artifact_sha256, history.completeness_evidence_sha256,
  history.canonical_pack_sha256, history.canonical_pack_sqlite_sha256,
  history.canonical_station_version, history.canonical_station_set_sha256, history.canonical_station_member_count,
  history.source_lineage_sha256, history.evidence_hash,
  (SELECT COUNT(*) FROM service_calendars),
  (SELECT COUNT(*) FROM transit_routes),
  (SELECT COUNT(*) FROM transit_trips),
  (SELECT COUNT(*) FROM transit_stop_times),
  (SELECT COUNT(*) FROM transit_trips WHERE service_class = 'SUBWAY'),
  (SELECT COUNT(*) FROM transit_stop_times stops JOIN transit_trips trips ON trips.id = stops.trip_id WHERE trips.service_class = 'SUBWAY'),
  (SELECT COUNT(*) FROM transit_trips WHERE service_class = 'ITX_CHEONGCHUN'),
  (SELECT COUNT(*) FROM transit_stop_times stops JOIN transit_trips trips ON trips.id = stops.trip_id WHERE trips.service_class = 'ITX_CHEONGCHUN'),
  (SELECT COUNT(*) FROM route_service_artifact_evidence evidence
    WHERE evidence.service_class = 'ITX_CHEONGCHUN'
      AND evidence.timetable_artifact_id = history.source_artifact_id
      AND evidence.timetable_artifact_sha256 = history.source_artifact_sha256
      AND evidence.canonical_pack_sha256 = history.canonical_pack_sha256
      AND evidence.canonical_pack_sqlite_sha256 = history.canonical_pack_sqlite_sha256
      AND evidence.admission_status = 'ADMITTED' AND evidence.admission_eligible = TRUE
      AND evidence.fresh_until = history.fresh_until AND evidence.source_issue = 2135),
  TO_CHAR(history.fresh_until::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')
FROM timetable_snapshot_active active
JOIN timetable_snapshot_history history ON history.snapshot_sha256 = active.snapshot_sha256
WHERE active.singleton_id = 1 AND history.fresh_until::timestamptz > CURRENT_TIMESTAMP;"
active_identity="$(production_psql "${identity_sql}")"
expected_identity="$(node -e '
const evidence = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
const rows = evidence.rowCounts;
process.stdout.write([
  evidence.snapshotSha256, evidence.snapshotId, evidence.schemaIdentity,
  evidence.sourceArtifact.id, evidence.sourceArtifact.sha256, evidence.sourceArtifact.completenessEvidenceSha256,
  evidence.canonicalPackIdentity.sha256, evidence.canonicalPackIdentity.sqliteSha256,
  evidence.canonicalStationSet.version, evidence.canonicalStationSet.sha256, evidence.canonicalStationSet.memberCount,
  evidence.sourceLineageSha256, evidence.evidenceHash,
  rows.calendars, rows.routes, rows.trips, rows.stopTimes,
  rows.subwayTrips, rows.subwayStopTimes, rows.itxTrips, rows.itxStopTimes,
  rows.routeServiceEvidence,
  new Date(evidence.freshUntil).toISOString().replace(/\.\d{3}Z$/, "Z"),
].join("|"));
' backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json)"
if [[ "${active_identity}" != "${expected_identity}" ]]; then
	echo 'active timetable snapshot does not match checked-in evidence' >&2
	exit 1
fi
IFS='|' read -r snapshot_sha snapshot_id schema_identity source_artifact_id source_artifact_sha completeness_evidence_sha canonical_pack_sha canonical_pack_sqlite_sha canonical_station_version canonical_station_set_sha canonical_station_member_count source_lineage_sha evidence_hash calendar_count route_count trip_count stop_time_count subway_trip_count subway_stop_time_count itx_trip_count itx_stop_time_count route_service_evidence_count fresh_until <<< "${active_identity}"
[[ "${snapshot_sha}" =~ ^[0-9a-f]{64}$ && "${snapshot_id}" == server-timetable-snapshot-* ]] \
	|| { echo 'fresh active timetable snapshot identity is missing' >&2; exit 1; }
for count in "${calendar_count}" "${route_count}" "${trip_count}" "${stop_time_count}" "${subway_trip_count}" "${subway_stop_time_count}" "${itx_trip_count}" "${itx_stop_time_count}" "${route_service_evidence_count}"; do
	[[ "${count}" =~ ^[0-9]+$ ]] || { echo 'active timetable row count is invalid' >&2; exit 1; }
done

run_id="${GITHUB_RUN_ID:-$$}"
run_attempt="${GITHUB_RUN_ATTEMPT:-1}"
[[ "${run_id}" =~ ^[0-9]+$ && "${run_attempt}" =~ ^[0-9]+$ ]] || { echo 'run identity is invalid' >&2; exit 2; }
session_tokens=()
session_hashes=()
for _ in 1 2; do
	session_token="$(node -e 'process.stdout.write(require("node:crypto").randomBytes(32).toString("base64url"))')"
	[[ "${session_token}" =~ ^[A-Za-z0-9_-]{43}$ ]] || { echo 'session token is invalid' >&2; exit 1; }
	if command -v sha256sum >/dev/null 2>&1; then
		session_hash="$(printf '%s' "${session_token}" | sha256sum | cut -d ' ' -f 1)"
	else
		session_hash="$(printf '%s' "${session_token}" | shasum -a 256 | cut -d ' ' -f 1)"
	fi
	[[ "${session_hash}" =~ ^[0-9a-f]{64}$ ]] || { echo 'session hash is invalid' >&2; exit 1; }
	session_tokens+=("${session_token}")
	session_hashes+=("${session_hash}")
done
[[ "${session_hashes[0]}" != "${session_hashes[1]}" ]] || { echo 'session hashes must be unique' >&2; exit 1; }
unset session_token session_hash

work_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/issue-2145-evidence.XXXXXX")"
network="easysubway-2145-${run_id}-${run_attempt}"
volume="${network}"
clone_db="${network}-db"
candidate_app="${network}-candidate"
cache_app="${network}-cache"
sessions_created=false
route_state_ids=()
cleanup() {
	if [[ "${sessions_created}" == true ]]; then
		production_psql "DELETE FROM route_v2_sessions WHERE token_sha256 IN ('${session_hashes[0]}', '${session_hashes[1]}');" >/dev/null 2>&1 || true
	fi
	for route_state_id in "${route_state_ids[@]}"; do
		production_psql "DELETE FROM route_v2_states WHERE route_state_id = '${route_state_id}';" >/dev/null 2>&1 || true
	done
	docker rm -f "${cache_app}" "${candidate_app}" "${clone_db}" >/dev/null 2>&1 || true
	docker volume rm "${volume}" >/dev/null 2>&1 || true
	docker network rm "${network}" >/dev/null 2>&1 || true
	rm -rf "${work_dir}"
}
trap cleanup EXIT

backend_env_json="${work_dir}/backend-env.json"
backend_env_nul="${work_dir}/backend-env.nul"
docker inspect --format '{{json .Config.Env}}' easysubway-backend > "${backend_env_json}"
chmod 600 "${backend_env_json}"
node -e '
const entries = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
for (const entry of entries) {
  const separator = entry.indexOf("=");
  if (separator < 1) throw new Error("backend environment entry is invalid");
  process.stdout.write(entry.slice(0, separator));
  process.stdout.write(Buffer.from([0]));
  process.stdout.write(entry.slice(separator + 1));
  process.stdout.write(Buffer.from([0]));
}
' "${backend_env_json}" > "${backend_env_nul}"
chmod 600 "${backend_env_nul}"
run_backend_clone() (
	local timeout_seconds="${1:?timeout is required}"
	shift
	[[ "${timeout_seconds}" =~ ^[0-9]+$ ]] || { echo 'backend clone timeout is invalid' >&2; exit 2; }
	local docker_cli timeout_cli env_name env_value
	local -a backend_env_args=()
	docker_cli="$(command -v docker)"
	timeout_cli="$(command -v timeout)"
	[[ -x "${docker_cli}" && -x "${timeout_cli}" ]] \
		|| { echo 'backend clone runtime is unavailable' >&2; exit 1; }
	while IFS= read -r -d '' env_name && IFS= read -r -d '' env_value; do
		[[ "${env_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
			|| { echo 'backend environment name is invalid' >&2; exit 1; }
		printf -v "${env_name}" '%s' "${env_value}"
		export "${env_name}"
		backend_env_args+=(--env "${env_name}")
	done < "${backend_env_nul}"
	(( ${#backend_env_args[@]} > 0 )) || { echo 'backend environment is empty' >&2; exit 1; }
	"${timeout_cli}" "${timeout_seconds}" "${docker_cli}" run "${backend_env_args[@]}" "$@"
)
production_network="$(docker inspect --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' easysubway-backend | head -n 1)"
[[ "${production_network}" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo 'production Docker network is invalid' >&2; exit 1; }

run_backend_clone 30 -d --name "${cache_app}" --network "${production_network}" \
	--cpus 1 --memory 1g --memory-swap 1g --pids-limit 256 \
	--publish 127.0.0.1::8080 \
	-e EASYSUBWAY_SCHEDULING_ENABLED=false \
	-e EASYSUBWAY_PUSH_EXTERNAL_ENABLED=false \
	-e EASYSUBWAY_PUSH_DELIVERY_ENABLED=false \
	"${backend_image}" >/dev/null
cache_binding="$(docker port "${cache_app}" 8080/tcp)"
[[ "${cache_binding}" =~ ^127\.0\.0\.1:[0-9]+$ ]] || { echo 'controlled cache application port binding is invalid' >&2; exit 1; }
cache_base_url="http://${cache_binding}" # NOSONAR -- 로컬 루프백(127.0.0.1) 컨테이너 전용 평문 HTTP 프로브로 외부 노출이 없다.
origin_secret="$(node -e '
const entries = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
const entry = entries.find((value) => value.startsWith("EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET="));
if (!entry) throw new Error("route V2 origin secret is missing");
process.stdout.write(entry.slice(entry.indexOf("=") + 1));
' "${backend_env_json}")"
[[ "${origin_secret}" =~ ^[A-Za-z0-9_-]{43,128}$ ]] \
	|| { echo 'route V2 origin secret is invalid' >&2; exit 1; }
cache_ready=false
for _ in $(seq 1 90); do
	if [[ "$(docker inspect --format '{{.State.Running}}' "${cache_app}" 2>/dev/null || true)" != true ]]; then
		echo 'controlled cache application stopped before readiness' >&2
		exit 1
	fi
	if [[ "$(curl -sS --noproxy '*' --connect-timeout 1 --max-time 2 -o /dev/null -w '%{http_code}' "${cache_base_url}/actuator/health/readiness" 2>/dev/null || true)" == 200 ]]; then # NOSONAR
		cache_ready=true
		break
	fi
	sleep 1
done
[[ "${cache_ready}" == true ]] || { echo 'controlled cache application readiness timed out' >&2; exit 1; }

production_psql "
INSERT INTO route_v2_sessions (token_sha256, scope, issued_at, expires_at, request_count)
VALUES
  ('${session_hashes[0]}', 'route:v2:itx', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '10 minutes', 0),
  ('${session_hashes[1]}', 'route:v2:itx', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '10 minutes', 0);" >/dev/null
sessions_created=true

request_body='{"originStationId":"station-sangnoksu","destinationStationId":"station-sadang","departureTime":"2026-07-16T15:00:00+09:00","mobilityType":"SENIOR","constraintMode":"ALLOW_WITH_WARNINGS","useRealtime":false,"maxTransfers":3,"alternativeCount":1}'

for attempt in 0 1; do
	response_file="${work_dir}/cache-response-${attempt}.json"
	curl_config="${work_dir}/cache-request-${attempt}.curl-config"
	{
		printf 'header = "X-EasySubway-Origin-Verify: %s"\n' "${origin_secret}"
		printf 'header = "Authorization: Bearer %s"\n' "${session_tokens[${attempt}]}"
	} > "${curl_config}"
	chmod 600 "${curl_config}"
	status="$(curl --config "${curl_config}" -sS --noproxy '*' --connect-timeout 2 --max-time 10 --output "${response_file}" --write-out '%{http_code}' \
		--request POST --header 'content-type: application/json' \
		--data-binary "${request_body}" "${cache_base_url}/api/v2/routes/search")" # NOSONAR
	rm -f "${curl_config}"
	route_state_id="$(node -e '
const response = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(response?.data?.itineraries?.[0]?.itineraryId ?? "");
' "${response_file}")"
	if [[ -n "${route_state_id}" ]]; then
		[[ "${route_state_id}" =~ ^route-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-primary$ ]] \
			|| { echo 'controlled route state ID is invalid' >&2; exit 1; }
		route_state_ids+=("${route_state_id}")
	fi
	if [[ "${status}" != 503 ]]; then
		if [[ -n "${route_state_id}" ]]; then
			deleted_route_state_count="$(production_psql "WITH deleted AS (DELETE FROM route_v2_states WHERE route_state_id = '${route_state_id}' RETURNING 1) SELECT COUNT(*) FROM deleted;")"
			[[ "${deleted_route_state_count}" == 1 ]] || { echo 'controlled route state was not deleted exactly' >&2; exit 1; }
			route_state_ids=()
		fi
		echo "controlled timetable request returned ${status}, expected 503" >&2
		exit 1
	fi
done
unset session_tokens origin_secret

session_uses="$(production_psql "SELECT STRING_AGG(request_count::text, ',' ORDER BY token_sha256) FROM route_v2_sessions WHERE token_sha256 IN ('${session_hashes[0]}', '${session_hashes[1]}');")"
[[ "${session_uses}" == 1,1 ]] || { echo 'controlled timetable sessions were not consumed exactly once each' >&2; exit 1; }
cache_logs="$(docker logs "${cache_app}" 2>&1)"
grep -Fq 'route V2 timetable cache result=miss' <<< "${cache_logs}" \
	|| { echo 'controlled cache miss evidence is missing' >&2; exit 1; }
grep -Fq 'route V2 timetable cache result=hit' <<< "${cache_logs}" \
	|| { echo 'controlled cache hit evidence is missing' >&2; exit 1; }

deleted_session_count="$(production_psql "WITH deleted AS (DELETE FROM route_v2_sessions WHERE token_sha256 IN ('${session_hashes[0]}', '${session_hashes[1]}') RETURNING 1) SELECT COUNT(*) FROM deleted;")"
[[ "${deleted_session_count}" == 2 ]] || { echo 'controlled timetable sessions were not deleted exactly' >&2; exit 1; }
sessions_created=false

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

backup_file="${work_dir}/production.dump"
docker exec easysubway-postgres sh -lc \
	'pg_dump --format=custom --no-owner --no-privileges -U "$POSTGRES_USER" "$POSTGRES_DB"' > "${backup_file}"
[[ -s "${backup_file}" ]] || { echo 'production backup is empty' >&2; exit 1; }

postgres_image="$(docker inspect --format '{{.Image}}' easysubway-postgres)"
[[ "${postgres_image}" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'production PostgreSQL image is invalid' >&2; exit 1; }
docker network create --internal "${network}" >/dev/null
docker volume create "${volume}" >/dev/null
docker run -d --name "${clone_db}" --network "${network}" --network-alias db \
	--cpus 1 --memory 2g --memory-swap 2g --pids-limit 256 \
	-v "${volume}:/var/lib/postgresql/data" \
	-e POSTGRES_DB=easysubway_rehearsal -e POSTGRES_USER=rehearsal -e POSTGRES_PASSWORD=rehearsal_local \
	"${postgres_image}" >/dev/null

ready=false
for _ in $(seq 1 60); do
	if [[ "$(docker exec "${clone_db}" cat /proc/1/comm 2>/dev/null || true)" == postgres ]] \
		&& docker exec "${clone_db}" pg_isready -U rehearsal -d easysubway_rehearsal >/dev/null 2>&1; then
		ready=true
		break
	fi
	sleep 1
done
[[ "${ready}" == true ]] || { echo 'isolated PostgreSQL readiness timed out' >&2; exit 1; }

docker exec -i "${clone_db}" pg_restore --clean --if-exists --no-owner --no-privileges \
	-U rehearsal -d easysubway_rehearsal < "${backup_file}"
clone_psql() {
	docker exec -i "${clone_db}" psql -X -v ON_ERROR_STOP=1 -A -t -F '|' -U rehearsal -d easysubway_rehearsal "$@"
}
clone_identity_sql="
SELECT active.snapshot_sha256, history.evidence_hash
FROM timetable_snapshot_active active
JOIN timetable_snapshot_history history ON history.snapshot_sha256 = active.snapshot_sha256
WHERE active.singleton_id = 1;"
clone_identity_before="$(clone_psql -c "${clone_identity_sql}")"
[[ "${clone_identity_before}" == "${snapshot_sha}|"* ]] || { echo 'restored timetable identity mismatch' >&2; exit 1; }

clone_timetable_fingerprint() {
	local table
	if command -v sha256sum >/dev/null 2>&1; then
		{
			for table in service_calendars service_calendar_dates transit_feed_info transit_routes transit_trips transit_stop_times transit_frequencies route_service_artifact_evidence timetable_snapshot_active timetable_snapshot_history; do
				printf '%s\n' "${table}"
				clone_psql -c "SELECT row_json FROM (SELECT row_to_json(row_value)::text AS row_json FROM ${table} row_value) rows ORDER BY row_json COLLATE \"C\";"
			done
		} | sha256sum | cut -d ' ' -f 1
	else
		{
			for table in service_calendars service_calendar_dates transit_feed_info transit_routes transit_trips transit_stop_times transit_frequencies route_service_artifact_evidence timetable_snapshot_active timetable_snapshot_history; do
				printf '%s\n' "${table}"
				clone_psql -c "SELECT row_json FROM (SELECT row_to_json(row_value)::text AS row_json FROM ${table} row_value) rows ORDER BY row_json COLLATE \"C\";"
			done
		} | shasum -a 256 | cut -d ' ' -f 1
	fi
}
fingerprint_before="$(clone_timetable_fingerprint)"
[[ "${fingerprint_before}" =~ ^[0-9a-f]{64}$ ]] || { echo 'restored timetable fingerprint is invalid' >&2; exit 1; }

clone_psql >/dev/null <<'SQL'
CREATE FUNCTION issue_2145_reject_trip() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'issue 2145 injected trip failure';
END;
$$;
CREATE TRIGGER issue_2145_reject_trip BEFORE INSERT ON transit_trips
FOR EACH ROW EXECUTE FUNCTION issue_2145_reject_trip();
SQL

candidate_dir="${work_dir}/candidate"
node tools/ops/prepare-timetable-rollback-candidate.mjs \
	backend/src/main/resources/timetable/line4-timetable-seed.sql.gz \
	backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json \
	"${candidate_dir}"
chmod 755 "${work_dir}" "${candidate_dir}"
chmod 644 "${candidate_dir}/candidate.sql.gz" "${candidate_dir}/evidence.json"

run_backend_clone 30 -d --name "${candidate_app}" --network "${network}" \
	--cpus 1 --memory 1g --memory-swap 1g --pids-limit 256 \
	-e SPRING_PROFILES_ACTIVE=prod \
	-e EASYSUBWAY_DATASOURCE_URL=jdbc:postgresql://db:5432/easysubway_rehearsal \
	-e EASYSUBWAY_DATASOURCE_USERNAME=rehearsal \
	-e EASYSUBWAY_DATASOURCE_PASSWORD=rehearsal_local \
	-e EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http://127.0.0.1:9 \
	-e EASYSUBWAY_PUSH_EXTERNAL_ENABLED=false \
	-e EASYSUBWAY_PUSH_DELIVERY_ENABLED=false \
	-e EASYSUBWAY_TIMETABLE_SEED_ENABLED=true \
	-e EASYSUBWAY_TIMETABLE_SEED_INCLUDES_ITX=true \
	-e EASYSUBWAY_TIMETABLE_SEED_RESOURCE=file:/evidence/candidate.sql.gz \
	-e EASYSUBWAY_TIMETABLE_SEED_EVIDENCE_RESOURCE=file:/evidence/evidence.json \
	-v "${candidate_dir}:/evidence:ro" \
	"${backend_image}" >/dev/null
candidate_log="${work_dir}/candidate.log"
candidate_failure_observed=false
for _ in $(seq 1 300); do
	docker logs "${candidate_app}" > "${candidate_log}" 2>&1 || true
	if grep -Fq 'transit timetable snapshot activation failed' "${candidate_log}" \
		&& grep -Fq 'issue 2145 injected trip failure' "${candidate_log}"; then
		candidate_failure_observed=true
		break
	fi
	if [[ "$(docker inspect --format '{{.State.Running}}' "${candidate_app}" 2>/dev/null || true)" != true ]]; then
		break
	fi
	sleep 1
done
docker logs "${candidate_app}" > "${candidate_log}" 2>&1 || true
if grep -Fq 'transit timetable snapshot activation failed' "${candidate_log}" \
	&& grep -Fq 'issue 2145 injected trip failure' "${candidate_log}"; then
	candidate_failure_observed=true
fi
[[ "${candidate_failure_observed}" == true ]] \
	|| { echo 'injected activation failure was not observed within timeout' >&2; exit 1; }
grep -Fq 'transit timetable snapshot activation failed' "${work_dir}/candidate.log" \
	|| { echo 'candidate did not reach timetable activation' >&2; exit 1; }
grep -Fq 'issue 2145 injected trip failure' "${work_dir}/candidate.log" \
	|| { echo 'candidate did not reach the injected SQL failure' >&2; exit 1; }
docker rm -f "${candidate_app}" >/dev/null

clone_identity_after="$(clone_psql -c "${clone_identity_sql}")"
[[ "${clone_identity_after}" == "${clone_identity_before}" ]] || { echo 'rollback changed active snapshot identity' >&2; exit 1; }
fingerprint_after="$(clone_timetable_fingerprint)"
if [[ "${fingerprint_before}" != "${fingerprint_after}" ]]; then
	echo 'fingerprint_before != fingerprint_after' >&2
	exit 1
fi

{
	echo '### #2145 production timetable snapshot evidence'
	echo "- deployed SHA: \`${current_sha}\`"
	echo "- snapshot: \`${snapshot_id}\` / \`${snapshot_sha}\`"
	echo "- schema/fresh until: \`${schema_identity}\` / \`${fresh_until}\`"
	echo "- calendar/route/trip/stop-time rows: \`${calendar_count}/${route_count}/${trip_count}/${stop_time_count}\`"
	echo "- subway/ITX trips and stop times: \`${subway_trip_count}/${subway_stop_time_count}/${itx_trip_count}/${itx_stop_time_count}\`"
	echo '- controlled cache: `miss=1+, hit=1+`, two random sessions consumed once each, responses `503/503`'
	echo '- rollback: production backup isolated restore, injected SQL failure, active identity and aggregate fingerprint unchanged'
	echo '- production mutation: synthetic sessions inserted and removed; any synthetic route state is tracked and removed; timetable rows read-only'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

echo 'production timetable snapshot evidence completed'
