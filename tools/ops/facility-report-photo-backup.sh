#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${EASYSUBWAY_ENV_FILE:-${ROOT_DIR}/.env.example}"
COMPOSE_FILE="${EASYSUBWAY_COMPOSE_FILE:-${ROOT_DIR}/infra/docker-compose.yml}"
BACKUP_DIR="${1:-${EASYSUBWAY_PHOTO_BACKUP_DIR:-${ROOT_DIR}/.codex/backups/facility-report-photos}}"

umask 077
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

run_dir="$(mktemp -d "${BACKUP_DIR}/easysubway-report-photos-${timestamp}.XXXXXX")"
objects_dir="${run_dir}/objects"
manifest_file="${run_dir}/manifest.tsv"
rows_file="${run_dir}/photos.tsv"

cleanup() {
	rm -f "${rows_file}"
}
trap cleanup EXIT

decode_base64_to_file() {
	local encoded="$1"
	local object_file="$2"
	if printf '%s' "${encoded}" | base64 --decode > "${object_file}"; then
		return
	fi
	printf '%s' "${encoded}" | base64 -D > "${object_file}"
}

mkdir -p "${objects_dir}"
chmod 700 "${run_dir}" "${objects_dir}"

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T postgres sh -lc \
	'psql -U "$POSTGRES_USER" "$POSTGRES_DB"' <<'SQL' > "${rows_file}"
COPY (
SELECT report_id,
	COALESCE(photo_file_name, '') AS photo_file_name,
	COALESCE(photo_content_type, '') AS photo_content_type,
	photo_data_base64
FROM facility_reports
WHERE photo_data_base64 IS NOT NULL
	AND photo_data_base64 <> ''
ORDER BY report_id ASC
) TO STDOUT WITH (FORMAT csv, DELIMITER E'\t');
SQL

printf 'report_id\tfile_name\tcontent_type\tobject_path\n' > "${manifest_file}"

while IFS=$'\t' read -r report_id file_name content_type photo_data_base64; do
	if [[ -z "${report_id}" || -z "${photo_data_base64}" ]]; then
		continue
	fi
	safe_report_id="$(printf '%s' "${report_id}" | tr -c 'A-Za-z0-9._-' '_')"
	object_path="objects/${safe_report_id}.bin"
	object_file="${run_dir}/${object_path}"
	decode_base64_to_file "${photo_data_base64}" "${object_file}"
	printf '%s\t%s\t%s\t%s\n' "${report_id}" "${file_name}" "${content_type}" "${object_path}" >> "${manifest_file}"
done < "${rows_file}"

trap - EXIT
cleanup
printf 'facility report photo backup written: %s\n' "${run_dir}"
