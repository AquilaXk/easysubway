#!/usr/bin/env bash
set -euo pipefail

readonly ENV_FILE="${1:-.env}"
readonly REPO="${GITHUB_REPOSITORY:-AquilaXk/easysubway}"
readonly SECRET_NAME="EASYSUBWAY_ENV"

if [[ ! -f "${ENV_FILE}" ]]; then
	printf 'Local env file not found: %s\n' "${ENV_FILE}" >&2
	exit 1
fi

if [[ "${ENV_FILE}" == ".env.example" || "$(basename "${ENV_FILE}")" == ".env.example" ]]; then
	printf '.env.example is a template. Pass the local .env file with real deployment values.\n' >&2
	exit 1
fi

missing_names=()
while IFS= read -r name; do
	if [[ -n "${name}" ]] && ! grep -Eq "^${name}=" "${ENV_FILE}"; then
		missing_names+=("${name}")
	fi
done < <(sed -nE 's/^([A-Z0-9_]+)=.*/\1/p' .env.example)

if (( ${#missing_names[@]} > 0 )); then
	printf 'Missing required env names in %s:\n' "${ENV_FILE}" >&2
	printf ' - %s\n' "${missing_names[@]}" >&2
	exit 1
fi

# 값은 로그에 남기지 않고 dotenv 파일 전체를 GitHub Actions secret 하나로 저장한다.
gh secret set "${SECRET_NAME}" --repo "${REPO}" < "${ENV_FILE}"
printf 'Updated GitHub Actions secret %s for %s from %s\n' "${SECRET_NAME}" "${REPO}" "${ENV_FILE}"
