#!/usr/bin/env bash
set -euo pipefail

umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/easysubway}"
DEPLOY_COMPOSE_PROJECT="${DEPLOY_COMPOSE_PROJECT:-easysubway}"
EXPECTED_DEPLOYED_SHA="${EXPECTED_DEPLOYED_SHA:-}"
RESTORE_CPU_LIMIT="1"
RESTORE_MEMORY_LIMIT="2g"
RESTORE_PIDS_LIMIT="256"
WAL_HEADROOM_BYTES="$((256 * 1024 * 1024))"
MIN_OPERATIONAL_RESERVE_BYTES="$((1024 * 1024 * 1024))"
SPACE_CLASS='[:space:]'

if [[ ! "${DEPLOY_ROOT}" =~ ^/[A-Za-z0-9._/-]+$ || "${DEPLOY_ROOT}" == *..* ]]; then
	printf 'DEPLOY_ROOT is invalid\n' >&2
	exit 2
fi
if [[ ! "${DEPLOY_COMPOSE_PROJECT}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
	printf 'DEPLOY_COMPOSE_PROJECT is invalid\n' >&2
	exit 2
fi
if [[ ! "${EXPECTED_DEPLOYED_SHA}" =~ ^[0-9a-f]{40}$ ]]; then
	printf 'EXPECTED_DEPLOYED_SHA is invalid\n' >&2
	exit 2
fi

SHARED_DIR="${DEPLOY_ROOT}/shared"
BACKUP_DIR="${DEPLOY_ROOT}/backups/postgres/1913-route-purge"
EVIDENCE_DIR="${SHARED_DIR}/1913-route-purge-snapshot"
MARKER_FILE="${EVIDENCE_DIR}/snapshot.env"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/null}"

mkdir -p "${BACKUP_DIR}" "${EVIDENCE_DIR}"
chmod 700 "${BACKUP_DIR}" "${EVIDENCE_DIR}"

exec 9>"${DEPLOY_ROOT}/deploy.lock"
if ! flock -w 300 9; then
	printf 'could not acquire deploy lock within timeout\n' >&2
	exit 1
fi

current_sha="$(<"${SHARED_DIR}/current-sha")"
if [[ ! "${current_sha}" =~ ^[0-9a-f]{40}$ ]]; then
	printf 'deployed SHA marker is invalid\n' >&2
	exit 1
fi
if [[ "${current_sha}" != "${EXPECTED_DEPLOYED_SHA}" ]]; then
	printf 'deployed SHA changed after closure verification\n' >&2
	exit 1
fi

if [[ -f "${MARKER_FILE}" ]] && grep -qx 'status=snapshot-complete' "${MARKER_FILE}"; then
	marker_sha="$(sed -n 's/^current_sha=//p' "${MARKER_FILE}")"
	if [[ "${marker_sha}" != "${EXPECTED_DEPLOYED_SHA}" ]]; then
		printf 'snapshot marker SHA does not match verified deployment\n' >&2
		exit 1
	fi
	backup_file="$(sed -n 's/^backup_file=//p' "${MARKER_FILE}")"
	case "${backup_file}" in
		"${BACKUP_DIR}"/*.dump) ;;
		*) printf 'snapshot marker backup path is invalid\n' >&2; exit 1 ;;
	esac
	if [[ ! -f "${backup_file}" || ! -f "${backup_file}.sha256" ]]; then
		printf 'existing snapshot backup or checksum file is missing\n' >&2
		exit 1
	fi
	if ! sha256sum -c "${backup_file}.sha256" >/dev/null; then
		printf 'existing snapshot backup checksum mismatch\n' >&2
		exit 1
	fi
	{
		echo '### #1913 route purge snapshot gate'
		echo '- status: `snapshot-complete` (existing verified backup)'
	} >> "${SUMMARY_FILE}"
	exit 0
fi

expected_image="easysubway-backend:${current_sha}"
image_revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${expected_image}")"
if [[ "${image_revision}" != "${current_sha}" ]]; then
	printf 'deployed image revision does not match current SHA\n' >&2
	exit 1
fi

production_image="$(docker inspect --format '{{.Image}}' easysubway-postgres)"
production_version_num="$(docker exec easysubway-postgres sh -lc \
	'psql -X -v ON_ERROR_STOP=1 -A -t -U "$POSTGRES_USER" "$POSTGRES_DB" -c "SHOW server_version_num;"' \
	| tr -d "${SPACE_CLASS}")"
if [[ ! "${production_version_num}" =~ ^16[0-9]{4}$ ]]; then
	printf 'production PostgreSQL major version is not 16\n' >&2
	exit 1
fi

production_count() {
	docker exec easysubway-postgres sh -lc \
		'psql -X -v ON_ERROR_STOP=1 -A -t -U "$POSTGRES_USER" "$POSTGRES_DB" -c "SELECT count(*) FROM route_search_results;"' \
		| tr -d "${SPACE_CLASS}"
}

storage_probe() {
	docker run --rm --pull never \
		--network none \
		--read-only \
		--user 0:0 \
		--mount "type=bind,src=${BACKUP_DIR},dst=/probe/backup,readonly" \
		--mount type=volume,target=/probe/docker \
		--entrypoint sh \
		"${production_image}" -c '
set -eu
set -- $(df -PB1 /probe/backup | tail -n 1)
backup_available="$4"
set -- $(df -PB1 /probe/docker | tail -n 1)
docker_available="$4"
printf "%s|%s|%s|%s\n" \
  "$(stat -c %d /probe/backup)" "${backup_available}" \
  "$(stat -c %d /probe/docker)" "${docker_available}"
'
}

source_count_before="$(production_count)"
source_database_bytes="$(docker exec easysubway-postgres sh -lc \
	'psql -X -v ON_ERROR_STOP=1 -A -t -U "$POSTGRES_USER" "$POSTGRES_DB" -c "SELECT pg_database_size(current_database());"' \
	| tr -d "${SPACE_CLASS}")"
IFS='|' read -r backup_device_before backup_available_before docker_device_before docker_available_before <<< "$(storage_probe)"
if [[ ! "${source_count_before}" =~ ^[0-9]+$ || ! "${source_database_bytes}" =~ ^[0-9]+$ \
	|| ! "${backup_device_before}" =~ ^[0-9]+$ || ! "${backup_available_before}" =~ ^[0-9]+$ \
	|| ! "${docker_device_before}" =~ ^[0-9]+$ || ! "${docker_available_before}" =~ ^[0-9]+$ ]]; then
	printf 'production snapshot preflight metrics are invalid\n' >&2
	exit 1
fi

operational_reserve_bytes="${MIN_OPERATIONAL_RESERVE_BYTES}"
if (( source_database_bytes > operational_reserve_bytes )); then
	operational_reserve_bytes="${source_database_bytes}"
fi
backup_reserve_bytes="$((source_database_bytes * 2))"
restore_cluster_reserve_bytes="$((source_database_bytes * 2))"
restore_wal_reserve_bytes="$((source_database_bytes * 2))"
if (( restore_wal_reserve_bytes < WAL_HEADROOM_BYTES )); then
	restore_wal_reserve_bytes="${WAL_HEADROOM_BYTES}"
fi
restore_required_bytes="$((restore_cluster_reserve_bytes + restore_wal_reserve_bytes + operational_reserve_bytes))"
backup_required_before="$((backup_reserve_bytes + operational_reserve_bytes))"
storage_shared_before=false
if [[ "${backup_device_before}" == "${docker_device_before}" ]]; then
	storage_shared_before=true
	backup_required_before="$((backup_reserve_bytes + restore_required_bytes))"
fi

if (( backup_available_before < backup_required_before )); then
	printf 'insufficient backup filesystem headroom\n' >&2
	exit 1
fi
if (( docker_available_before < restore_required_bytes )); then
	printf 'insufficient Docker filesystem headroom before backup\n' >&2
	exit 1
fi

backup_file="$(
	EASYSUBWAY_ENV_FILE="${SHARED_DIR}/current-env/compose.env" \
	EASYSUBWAY_COMPOSE_FILE="${DEPLOY_ROOT}/repository/infra/docker-compose.yml" \
	EASYSUBWAY_COMPOSE_PROJECT="${DEPLOY_COMPOSE_PROJECT}" \
	EASYSUBWAY_BACKUP_DIR="${BACKUP_DIR}" \
		bash "${ROOT_DIR}/tools/ops/postgres-backup.sh"
)"
case "${backup_file}" in
	"${BACKUP_DIR}"/*.dump) ;;
	*) printf 'backup script returned an invalid path\n' >&2; exit 1 ;;
esac

source_count_after="$(production_count)"
if [[ "${source_count_before}" != "${source_count_after}" ]]; then
	printf 'production route rows changed during backup\n' >&2
	exit 1
fi

backup_sha256="$(sha256sum "${backup_file}" | awk '{print $1}')"
backup_bytes="$(stat -c '%s' "${backup_file}")"
if [[ ! "${backup_sha256}" =~ ^[0-9a-f]{64}$ || ! "${backup_bytes}" =~ ^[0-9]+$ ]]; then
	printf 'backup identity is invalid\n' >&2
	exit 1
fi
IFS='|' read -r backup_device_after backup_available_after docker_device_after docker_available_after_backup <<< "$(storage_probe)"
if [[ ! "${backup_device_after}" =~ ^[0-9]+$ || ! "${backup_available_after}" =~ ^[0-9]+$ \
	|| ! "${docker_device_after}" =~ ^[0-9]+$ || ! "${docker_available_after_backup}" =~ ^[0-9]+$ ]]; then
	printf 'post-backup filesystem metrics are invalid\n' >&2
	exit 1
fi
if [[ "${backup_device_after}" != "${backup_device_before}" || "${docker_device_after}" != "${docker_device_before}" ]]; then
	printf 'snapshot filesystem layout changed during backup\n' >&2
	exit 1
fi
if (( backup_available_after < operational_reserve_bytes )); then
	printf 'insufficient operational reserve after backup\n' >&2
	exit 1
fi
if (( docker_available_after_backup < restore_required_bytes )); then
	printf 'insufficient Docker filesystem headroom\n' >&2
	exit 1
fi

run_suffix="${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}"
if [[ ! "${run_suffix}" =~ ^[0-9]+-[0-9]+$ ]]; then
	printf 'snapshot run identity is invalid\n' >&2
	exit 1
fi
restore_container="easysubway-1913-restore-${run_suffix}"
restore_volume="easysubway-1913-restore-${run_suffix}"

cleanup() {
	docker rm -f "${restore_container}" >/dev/null 2>&1 || true
	docker volume rm "${restore_volume}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker volume create "${restore_volume}" >/dev/null
docker run -d --rm --pull never \
	--name "${restore_container}" \
	--network none \
	--cpus "${RESTORE_CPU_LIMIT}" \
	--memory "${RESTORE_MEMORY_LIMIT}" \
	--memory-swap "${RESTORE_MEMORY_LIMIT}" \
	--pids-limit "${RESTORE_PIDS_LIMIT}" \
	--volume "${restore_volume}:/var/lib/postgresql/data" \
	-e POSTGRES_DB=easysubway_restore \
	-e POSTGRES_USER=snapshot_gate \
	-e POSTGRES_PASSWORD=snapshot_gate_local \
	"${production_image}" >/dev/null

ready=false
for _ in $(seq 1 60); do
	if docker exec "${restore_container}" pg_isready -U snapshot_gate -d easysubway_restore >/dev/null 2>&1; then
		ready=true
		break
	fi
	sleep 1
done
if [[ "${ready}" != "true" ]]; then
	printf 'isolated restore PostgreSQL did not become ready\n' >&2
	exit 1
fi

docker exec -i "${restore_container}" \
	pg_restore --no-owner --no-privileges -U snapshot_gate -d easysubway_restore \
	< "${backup_file}"

restore_psql() {
	docker exec -i "${restore_container}" \
		psql -X -v ON_ERROR_STOP=1 -A -t -U snapshot_gate -d easysubway_restore "$@"
}

restore_count="$(restore_psql -c 'SELECT count(*) FROM route_search_results;' | tr -d "${SPACE_CLASS}")"
if [[ "${restore_count}" != "${source_count_before}" ]]; then
	printf 'restored route row count does not match production backup count\n' >&2
	exit 1
fi

counts="$(restore_psql -F '|' -c "
WITH reference_ids AS (
    SELECT route_search_id FROM favorite_routes
    UNION SELECT route_search_id FROM favorite_route_stations
    UNION SELECT route_search_id FROM route_feedbacks
), metrics AS (
    SELECT 'route_total' AS key, count(*)::bigint AS value FROM route_search_results
    UNION ALL SELECT 'favorite_routes_raw', count(DISTINCT route_search_id) FROM favorite_routes
    UNION ALL SELECT 'favorite_routes_preserved', count(DISTINCT favorite.route_search_id) FROM favorite_routes favorite JOIN route_search_results route USING (route_search_id)
    UNION ALL SELECT 'favorite_routes_dangling', count(DISTINCT favorite.route_search_id) FROM favorite_routes favorite LEFT JOIN route_search_results route USING (route_search_id) WHERE route.route_search_id IS NULL
    UNION ALL SELECT 'favorite_route_stations_raw', count(DISTINCT route_search_id) FROM favorite_route_stations
    UNION ALL SELECT 'favorite_route_stations_preserved', count(DISTINCT station.route_search_id) FROM favorite_route_stations station JOIN route_search_results route USING (route_search_id)
    UNION ALL SELECT 'favorite_route_stations_dangling', count(DISTINCT station.route_search_id) FROM favorite_route_stations station LEFT JOIN route_search_results route USING (route_search_id) WHERE route.route_search_id IS NULL
    UNION ALL SELECT 'route_feedbacks_raw', count(DISTINCT route_search_id) FROM route_feedbacks
    UNION ALL SELECT 'route_feedbacks_preserved', count(DISTINCT feedback.route_search_id) FROM route_feedbacks feedback JOIN route_search_results route USING (route_search_id)
    UNION ALL SELECT 'route_feedbacks_dangling', count(DISTINCT feedback.route_search_id) FROM route_feedbacks feedback LEFT JOIN route_search_results route USING (route_search_id) WHERE route.route_search_id IS NULL
    UNION ALL SELECT 'reference_union_raw', count(*) FROM reference_ids
    UNION ALL SELECT 'preserved_union', count(*) FROM reference_ids reference JOIN route_search_results route USING (route_search_id)
    UNION ALL SELECT 'dangling_union', count(*) FROM reference_ids reference LEFT JOIN route_search_results route USING (route_search_id) WHERE route.route_search_id IS NULL
    UNION ALL SELECT 'delete_candidates', count(*) FROM route_search_results route
      WHERE NOT EXISTS (SELECT 1 FROM favorite_routes favorite WHERE favorite.route_search_id = route.route_search_id)
        AND NOT EXISTS (SELECT 1 FROM favorite_route_stations station WHERE station.route_search_id = route.route_search_id)
        AND NOT EXISTS (SELECT 1 FROM route_feedbacks feedback WHERE feedback.route_search_id = route.route_search_id)
)
SELECT key, value FROM metrics ORDER BY key;")"

required_metrics=(
	route_total favorite_routes_raw favorite_routes_preserved favorite_routes_dangling
	favorite_route_stations_raw favorite_route_stations_preserved favorite_route_stations_dangling
	route_feedbacks_raw route_feedbacks_preserved route_feedbacks_dangling
	reference_union_raw preserved_union dangling_union delete_candidates
)
for metric in "${required_metrics[@]}"; do
	value="$(awk -F '|' -v key="${metric}" '$1 == key {print $2}' <<< "${counts}")"
	if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
		printf 'missing aggregate metric: %s\n' "${metric}" >&2
		exit 1
	fi
	printf -v "${metric}" '%s' "${value}"
done

restore_psql -c 'ANALYZE route_search_results, favorite_routes, favorite_route_stations, route_feedbacks;' >/dev/null

plan_file="${EVIDENCE_DIR}/purge-plan-${backup_sha256:0:12}.txt"
start_ns="$(date +%s%N)"
restore_psql > "${plan_file}" <<'SQL'
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, WAL)
DELETE FROM route_search_results AS route
WHERE NOT EXISTS (
    SELECT 1 FROM favorite_routes AS favorite
    WHERE favorite.route_search_id = route.route_search_id
)
AND NOT EXISTS (
    SELECT 1 FROM favorite_route_stations AS station
    WHERE station.route_search_id = route.route_search_id
)
AND NOT EXISTS (
    SELECT 1 FROM route_feedbacks AS feedback
    WHERE feedback.route_search_id = route.route_search_id
);
ROLLBACK;
SQL
end_ns="$(date +%s%N)"
chmod 600 "${plan_file}"

wall_ms="$(( (end_ns - start_ns) / 1000000 ))"
execution_ms="$(sed -n 's/.*Execution Time: \([0-9.]*\) ms.*/\1/p' "${plan_file}" | tail -n 1)"
wal_bytes="$(awk '
  /WAL:/ {
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^bytes=/) {
        value = $i
        sub(/^bytes=/, "", value)
        sub(/,$/, "", value)
        total += value
      }
    }
  }
  END { print total + 0 }
' "${plan_file}")"
if [[ ! "${execution_ms}" =~ ^[0-9]+([.][0-9]+)?$ || ! "${wall_ms}" =~ ^[0-9]+$ || ! "${wal_bytes}" =~ ^[0-9]+$ ]]; then
	printf 'purge plan metrics are invalid\n' >&2
	exit 1
fi

rollback_count="$(restore_psql -c 'SELECT count(*) FROM route_search_results;' | tr -d "${SPACE_CLASS}")"
if [[ "${rollback_count}" != "${restore_count}" ]]; then
	printf 'route row count was not restored after rollback\n' >&2
	exit 1
fi

cpu_model="$(lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -n 1)"
cpu_cores="$(nproc)"
memory_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
root_filesystem="$(findmnt -n -o FSTYPE /)"
docker_storage_driver="$(docker info --format '{{.Driver}}')"
production_settings_sql="SELECT current_setting('server_version'), current_setting('shared_buffers'), current_setting('work_mem'), current_setting('maintenance_work_mem'), current_setting('effective_cache_size'), current_setting('max_wal_size'), current_setting('checkpoint_timeout'), current_setting('synchronous_commit');"
production_settings="$(docker exec easysubway-postgres sh -lc \
	'psql -X -v ON_ERROR_STOP=1 -A -t -F "|" -U "$POSTGRES_USER" "$POSTGRES_DB" -c "$1"' sh \
	"${production_settings_sql}")"
restore_settings="$(restore_psql -F '|' -c "SELECT current_setting('server_version'), current_setting('shared_buffers'), current_setting('work_mem'), current_setting('maintenance_work_mem'), current_setting('effective_cache_size'), current_setting('max_wal_size'), current_setting('checkpoint_timeout'), current_setting('synchronous_commit');")"

adjusted_execution_ms="$(awk -v value="${execution_ms}" 'BEGIN { printf "%.3f", value * 2 }')"
adjusted_wall_ms="$(( wall_ms * 2 ))"

report_file="${EVIDENCE_DIR}/report-${backup_sha256:0:12}.md"
{
	echo '### #1913 route purge snapshot gate'
	echo "- deployed SHA: \`${current_sha}\`"
	echo "- backup SHA-256: \`${backup_sha256}\`"
	echo "- backup bytes: \`${backup_bytes}\`"
	echo "- source database bytes: \`${source_database_bytes}\`"
	echo "- backup filesystem available/required before: \`${backup_available_before}/${backup_required_before}\`"
	echo "- backup filesystem available after: \`${backup_available_after}\`"
	echo "- Docker available before/after backup: \`${docker_available_before}/${docker_available_after_backup}\`"
	echo "- storage shared before backup: \`${storage_shared_before}\`"
	echo "- operational reserve bytes: \`${operational_reserve_bytes}\`"
	echo "- restore cluster/WAL/total reserve bytes: \`${restore_cluster_reserve_bytes}/${restore_wal_reserve_bytes}/${restore_required_bytes}\`"
	echo "- PostgreSQL image: \`${production_image}\`"
	echo "- CPU: \`${cpu_model}\`, cores \`${cpu_cores}\`"
	echo "- memory KiB: \`${memory_kib}\`"
	echo "- storage: root filesystem \`${root_filesystem}\`, Docker \`${docker_storage_driver}\`, IOPS/throughput not independently measured"
	echo "- production settings: \`${production_settings}\`"
	echo "- restore settings: \`${restore_settings}\`"
	echo "- route rows production/restored/after rollback: \`${source_count_before}/${restore_count}/${rollback_count}\`"
	echo "- favorite_routes raw/preserved/dangling: \`${favorite_routes_raw}/${favorite_routes_preserved}/${favorite_routes_dangling}\`"
	echo "- favorite_route_stations raw/preserved/dangling: \`${favorite_route_stations_raw}/${favorite_route_stations_preserved}/${favorite_route_stations_dangling}\`"
	echo "- route_feedbacks raw/preserved/dangling: \`${route_feedbacks_raw}/${route_feedbacks_preserved}/${route_feedbacks_dangling}\`"
	echo "- reference union raw/preserved/dangling: \`${reference_union_raw}/${preserved_union}/${dangling_union}\`"
	echo "- delete candidates: \`${delete_candidates}\`"
	echo "- EXPLAIN execution/wall: \`${execution_ms} ms/${wall_ms} ms\`"
	echo "- 2x safety execution/wall: \`${adjusted_execution_ms} ms/${adjusted_wall_ms} ms\`"
	echo "- WAL bytes: \`${wal_bytes}\`"
	echo '- restore isolation: same host/image/storage driver, separate Docker volume, no network or published port'
	echo "- restore resource limits: \`${RESTORE_CPU_LIMIT} CPU, ${RESTORE_MEMORY_LIMIT} memory/no swap, ${RESTORE_PIDS_LIMIT} pids\`"
	echo '- budget decision: pending explicit owner approval of 30 seconds and 256 MiB'
	echo
	echo '<details><summary>Sanitized EXPLAIN plan</summary>'
	echo
	echo '```text'
	cat "${plan_file}"
	echo '```'
	echo '</details>'
} > "${report_file}"
chmod 600 "${report_file}"
cat "${report_file}" >> "${SUMMARY_FILE}"
cat "${report_file}"

marker_tmp="$(mktemp "${EVIDENCE_DIR}/snapshot.XXXXXX")"
{
	printf 'status=snapshot-complete\n'
	printf 'current_sha=%s\n' "${current_sha}"
	printf 'backup_file=%s\n' "${backup_file}"
	printf 'backup_sha256=%s\n' "${backup_sha256}"
	printf 'backup_bytes=%s\n' "${backup_bytes}"
	printf 'route_total=%s\n' "${route_total}"
	printf 'delete_candidates=%s\n' "${delete_candidates}"
	printf 'execution_ms=%s\n' "${execution_ms}"
	printf 'wall_ms=%s\n' "${wall_ms}"
	printf 'wal_bytes=%s\n' "${wal_bytes}"
} > "${marker_tmp}"
chmod 600 "${marker_tmp}"
mv "${marker_tmp}" "${MARKER_FILE}"

printf 'route purge snapshot gate completed: %s\n' "${backup_sha256}"
