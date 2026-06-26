#!/usr/bin/env bash
set -euo pipefail

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/easysubway}"
DEPLOY_REPO_URL="${DEPLOY_REPO_URL:-https://github.com/AquilaXk/easysubway.git}"
DEPLOY_COMPOSE_PROJECT="${DEPLOY_COMPOSE_PROJECT:?DEPLOY_COMPOSE_PROJECT is required}"
DEPLOY_SHA="${DEPLOY_SHA:?DEPLOY_SHA is required}"
INCOMING_DIR="${INCOMING_DIR:?INCOMING_DIR is required}"

case "${DEPLOY_SHA}" in
	*[!0-9a-f]*|"") printf 'invalid DEPLOY_SHA\n' >&2; exit 2 ;;
esac
if [[ ${#DEPLOY_SHA} -ne 40 ]]; then
	printf 'invalid DEPLOY_SHA length\n' >&2
	exit 2
fi
if [[ "${DEPLOY_REPO_URL}" != "https://github.com/AquilaXk/easysubway.git" ]]; then
	printf 'unexpected deploy repository URL\n' >&2
	exit 2
fi
if [[ ! "${DEPLOY_COMPOSE_PROJECT}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
	printf 'invalid DEPLOY_COMPOSE_PROJECT\n' >&2
	exit 2
fi
case "${INCOMING_DIR}" in
	"${DEPLOY_ROOT}"/incoming/*) ;;
	*) printf 'invalid INCOMING_DIR\n' >&2; exit 2 ;;
esac

REPOSITORY_DIR="${DEPLOY_ROOT}/repository"
SHARED_DIR="${DEPLOY_ROOT}/shared"
BACKUP_DIR="${DEPLOY_ROOT}/backups/postgres"
DIAGNOSTICS_DIR="${SHARED_DIR}/diagnostics"
STATE_FILE="${SHARED_DIR}/deployment-state.env"
RESULT_FILE="${SHARED_DIR}/last-result.env"
LOCK_FILE="${DEPLOY_ROOT}/deploy.lock"

JAR_FILE="${INCOMING_DIR}/backend.jar"
CHECKSUM_FILE="${INCOMING_DIR}/backend.jar.sha256"
COMPOSE_ENV="${INCOMING_DIR}/compose.env"
BACKEND_ENV="${INCOMING_DIR}/backend.env"

for file in "${JAR_FILE}" "${CHECKSUM_FILE}" "${COMPOSE_ENV}" "${BACKEND_ENV}"; do
	[[ -f "${file}" ]] || { printf 'missing staged file: %s\n' "${file}" >&2; exit 2; }
	chmod 600 "${file}"
done

mkdir -p "${REPOSITORY_DIR}" "${SHARED_DIR}/env-sets" "${DIAGNOSTICS_DIR}" "${BACKUP_DIR}"
chmod 700 "${SHARED_DIR}" "${SHARED_DIR}/env-sets" "${DIAGNOSTICS_DIR}" "${BACKUP_DIR}"

write_result() {
	local status="$1"
	local detail="${2:-none}"
	local tmp
	tmp="$(mktemp "${SHARED_DIR}/last-result.XXXXXX")"
	chmod 600 "${tmp}"
	{
		printf 'status=%s\n' "${status}"
		printf 'detail=%s\n' "${detail}"
		printf 'sha=%s\n' "${DEPLOY_SHA}"
	} > "${tmp}"
	mv "${tmp}" "${RESULT_FILE}"
}

write_phase() {
	local phase="$1"
	local tmp
	tmp="$(mktemp "${SHARED_DIR}/deployment-state.XXXXXX")"
	chmod 600 "${tmp}"
	{
		printf 'phase=%s\n' "${phase}"
		printf 'sha=%s\n' "${DEPLOY_SHA}"
	} > "${tmp}"
	mv "${tmp}" "${STATE_FILE}"
}

exec 9>"${LOCK_FILE}"
flock 9

if [[ -f "${STATE_FILE}" ]] && ! grep -qx 'phase=completed' "${STATE_FILE}"; then
	write_result "blocked" "interrupted_state"
	printf 'previous deployment state is incomplete\n' >&2
	exit 1
fi

cleanup() {
	rm -rf "${INCOMING_DIR}"
}
trap cleanup EXIT

if [[ ! -d "${REPOSITORY_DIR}/.git" ]]; then
	git clone "${DEPLOY_REPO_URL}" "${REPOSITORY_DIR}"
fi
cd "${REPOSITORY_DIR}"

origin_url="$(git config --get remote.origin.url)"
if [[ "${origin_url}" != "${DEPLOY_REPO_URL}" ]]; then
	write_result "failed" "repository_url_mismatch"
	exit 1
fi

timeout 120 git fetch origin main
if ! git merge-base --is-ancestor "${DEPLOY_SHA}" origin/main; then
	write_result "blocked" "target_not_on_main"
	exit 1
fi

current_sha=""
if [[ -f "${SHARED_DIR}/current-sha" ]]; then
	current_sha="$(cat "${SHARED_DIR}/current-sha")"
	if ! git merge-base --is-ancestor "${current_sha}" "${DEPLOY_SHA}"; then
		write_result "blocked" "downgrade_or_divergent"
		exit 1
	fi
fi

pushd "${INCOMING_DIR}" >/dev/null
sha256sum -c "$(basename "${CHECKSUM_FILE}")"
popd >/dev/null
jar_sha="$(cut -d ' ' -f 1 "${CHECKSUM_FILE}")"

read_env_value() {
	local file="$1"
	local name="$2"
	sed -nE "s/^${name}=//p" "${file}" | tail -n 1 | sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
}
backend_port="$(read_env_value "${COMPOSE_ENV}" EASYSUBWAY_BACKEND_PORT)"
backend_port="${backend_port:-8080}"

compose() {
	local backend_env="$1"
	local compose_env="$2"
	local image_tag="$3"
	shift 3
	EASYSUBWAY_BACKEND_ENV_FILE="${backend_env}" \
	EASYSUBWAY_BACKEND_IMAGE_TAG="${image_tag}" \
	EASYSUBWAY_BACKEND_JAR_SHA256="${jar_sha}" \
	docker compose --project-name "${DEPLOY_COMPOSE_PROJECT}" --env-file "${compose_env}" -f infra/docker-compose.yml "$@"
}

compose "${BACKEND_ENV}" "${COMPOSE_ENV}" "${DEPLOY_SHA}" config --quiet

postgres_id="$(compose "${BACKEND_ENV}" "${COMPOSE_ENV}" "${DEPLOY_SHA}" ps -q postgres || true)"
object_storage_id="$(compose "${BACKEND_ENV}" "${COMPOSE_ENV}" "${DEPLOY_SHA}" ps -q object-storage || true)"
if [[ -z "${postgres_id}" || -z "${object_storage_id}" ]]; then
	write_result "blocked" "stateful_missing"
	exit 1
fi

for service in postgres object-storage; do
	container_id="$(compose "${BACKEND_ENV}" "${COMPOSE_ENV}" "${DEPLOY_SHA}" ps -q "${service}")"
	label_project="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "${container_id}")"
	label_service="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "${container_id}")"
	health="$(docker inspect --format '{{ if .State.Health }}{{ .State.Health.Status }}{{ else }}missing{{ end }}' "${container_id}")"
	if [[ "${label_project}" != "${DEPLOY_COMPOSE_PROJECT}" || "${label_service}" != "${service}" || "${health}" != "healthy" ]]; then
		write_result "blocked" "stateful_${service}_drift"
		exit 1
	fi
done

backend_id="$(compose "${BACKEND_ENV}" "${COMPOSE_ENV}" "${DEPLOY_SHA}" ps -q backend || true)"
if [[ -z "${current_sha}" && -n "${backend_id}" ]]; then
	write_result "blocked" "unmanaged_backend"
	exit 1
fi
if [[ -n "${current_sha}" ]]; then
	current_image_id="$(docker image inspect "easysubway-backend:${current_sha}" --format '{{.Id}}' 2>/dev/null || true)"
	running_image_id=""
	if [[ -n "${backend_id}" ]]; then
		running_image_id="$(docker inspect --format '{{.Image}}' "${backend_id}" 2>/dev/null || true)"
	fi
	if [[ -z "${backend_id}" || -z "${current_image_id}" || "${running_image_id}" != "${current_image_id}" ]]; then
		write_result "blocked" "managed_image_drift"
		exit 1
	fi
fi

target_env_hash="$(
	{
		printf 'compose.env\0'
		sha256sum "${COMPOSE_ENV}" | cut -d ' ' -f 1
		printf '\nbackend.env\0'
		sha256sum "${BACKEND_ENV}" | cut -d ' ' -f 1
		printf '\n'
	} | sha256sum | cut -d ' ' -f 1
)"
current_env_hash=""
if [[ -f "${SHARED_DIR}/current-env/metadata.env" ]]; then
	current_env_hash="$(sed -n 's/^env_hash=//p' "${SHARED_DIR}/current-env/metadata.env")"
fi

if [[ "${current_sha}" == "${DEPLOY_SHA}" && "${current_env_hash}" == "${target_env_hash}" ]]; then
	if curl -fsS --connect-timeout 2 --max-time 5 "http://127.0.0.1:${backend_port}/actuator/health/readiness" >/dev/null 2>&1; then
		write_phase "completed"
		write_result "noop" "same_sha_same_env_ready"
		exit 0
	fi
fi

git checkout --detach "${DEPLOY_SHA}"
git clean -ffdx
mkdir -p backend/build/libs
cp "${JAR_FILE}" backend/build/libs/app.jar

needs_build=1
if [[ "${current_sha}" == "${DEPLOY_SHA}" ]]; then
	needs_build=0
fi

if [[ "${needs_build}" -eq 1 ]]; then
	timeout 900 compose "${BACKEND_ENV}" "${COMPOSE_ENV}" "${DEPLOY_SHA}" build backend
fi

needs_backup=0
if [[ -z "${current_sha}" ]]; then
	needs_backup=1
elif git diff --name-only "${current_sha}" "${DEPLOY_SHA}" -- backend/src/main/resources/db/migration/postgresql | grep -q .; then
	needs_backup=1
fi
if [[ "${needs_backup}" -eq 1 ]]; then
	EASYSUBWAY_ENV_FILE="${COMPOSE_ENV}" \
	EASYSUBWAY_COMPOSE_FILE="${REPOSITORY_DIR}/infra/docker-compose.yml" \
	EASYSUBWAY_COMPOSE_PROJECT="${DEPLOY_COMPOSE_PROJECT}" \
	EASYSUBWAY_BACKUP_DIR="${BACKUP_DIR}" \
		timeout 300 tools/ops/postgres-backup.sh
fi

write_phase "started"
env_set="${SHARED_DIR}/env-sets/${DEPLOY_SHA}-${target_env_hash}-$(date -u +%Y%m%dT%H%M%SZ)"
tmp_env_set="${env_set}.tmp"
rm -rf "${tmp_env_set}"
mkdir -p "${tmp_env_set}"
chmod 700 "${tmp_env_set}"
cp "${COMPOSE_ENV}" "${tmp_env_set}/compose.env"
cp "${BACKEND_ENV}" "${tmp_env_set}/backend.env"
{
	printf 'sha=%s\n' "${DEPLOY_SHA}"
	printf 'jar_sha256=%s\n' "${jar_sha}"
	printf 'env_hash=%s\n' "${target_env_hash}"
} > "${tmp_env_set}/metadata.env"
chmod 600 "${tmp_env_set}/compose.env" "${tmp_env_set}/backend.env" "${tmp_env_set}/metadata.env"
mv "${tmp_env_set}" "${env_set}"
if [[ -L "${SHARED_DIR}/current-env" ]]; then
	previous_target="$(readlink "${SHARED_DIR}/current-env")"
	ln -sfn "${previous_target}" "${SHARED_DIR}/previous-env"
fi
ln -sfn "${env_set}" "${SHARED_DIR}/current-env.next"
mv -Tf "${SHARED_DIR}/current-env.next" "${SHARED_DIR}/current-env"

write_phase "restarting"
compose "${SHARED_DIR}/current-env/backend.env" "${SHARED_DIR}/current-env/compose.env" "${DEPLOY_SHA}" up -d --no-deps --no-build backend

ready=0
for _ in $(seq 1 60); do
	if curl -fsS --connect-timeout 2 --max-time 5 "http://127.0.0.1:${backend_port}/actuator/health/readiness" >/dev/null 2>&1; then
		ready=1
		break
	fi
	sleep 5
done

if [[ "${ready}" -ne 1 ]]; then
	diagnostic="${DIAGNOSTICS_DIR}/${DEPLOY_SHA}-$(date -u +%Y%m%dT%H%M%SZ).log"
	compose "${SHARED_DIR}/current-env/backend.env" "${SHARED_DIR}/current-env/compose.env" "${DEPLOY_SHA}" logs --no-color --tail=200 backend > "${diagnostic}" 2>&1 || true
	chmod 600 "${diagnostic}"
	if [[ -n "${current_sha}" && -L "${SHARED_DIR}/previous-env" ]]; then
		ln -sfn "$(readlink "${SHARED_DIR}/previous-env")" "${SHARED_DIR}/current-env.next"
		mv -Tf "${SHARED_DIR}/current-env.next" "${SHARED_DIR}/current-env"
		compose "${SHARED_DIR}/current-env/backend.env" "${SHARED_DIR}/current-env/compose.env" "${current_sha}" up -d --no-deps --no-build backend || true
		write_result "failed" "readiness_failed_rollback_attempted"
	else
		write_result "failed" "readiness_failed_rollback_unavailable"
	fi
	write_phase "completed"
	printf '%s\n' "${DEPLOY_SHA}" > "${SHARED_DIR}/failed-sha"
	exit 1
fi

printf '%s\n' "${DEPLOY_SHA}" > "${SHARED_DIR}/current-sha"
printf '%s\n' "${jar_sha}" > "${SHARED_DIR}/current-jar.sha256"
chmod 600 "${SHARED_DIR}/current-sha" "${SHARED_DIR}/current-jar.sha256"
write_phase "completed"
write_result "success" "backend_ready"
