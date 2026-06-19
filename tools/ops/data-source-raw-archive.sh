#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${EASYSUBWAY_ENV_FILE:-${ROOT_DIR}/.env.example}"
COMPOSE_FILE="${EASYSUBWAY_COMPOSE_FILE:-${ROOT_DIR}/infra/docker-compose.yml}"
BACKUP_DIR="${1:-${EASYSUBWAY_DATA_SOURCE_ARCHIVE_DIR:-${ROOT_DIR}/.codex/backups/data-sources}}"

umask 077
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

run_dir="$(mktemp -d "${BACKUP_DIR}/easysubway-data-sources-${timestamp}.XXXXXX")"
collection_runs_file="${run_dir}/collection-runs.csv"
raw_archives_file="${run_dir}/raw-archives.csv"

chmod 700 "${run_dir}"

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
	'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" "$POSTGRES_DB"' <<'SQL' > "${collection_runs_file}"
COPY (
SELECT run_id,
	source,
	status,
	requested_by,
	started_at,
	completed_at,
	collected_count,
	failure_message,
	retryable,
	operator_action
FROM data_collection_runs
ORDER BY started_at DESC, run_id ASC
) TO STDOUT WITH (FORMAT csv, HEADER true);
SQL

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
	'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" "$POSTGRES_DB"' <<'SQL' > "${raw_archives_file}"
COPY (
SELECT archive_id,
	run_id,
	source,
	source_url,
	storage_uri,
	payload_sha256,
	content_type,
	captured_at
FROM data_source_raw_archives
ORDER BY captured_at DESC, archive_id ASC
) TO STDOUT WITH (FORMAT csv, HEADER true);
SQL

printf 'data source archive written: %s\n' "${run_dir}"
