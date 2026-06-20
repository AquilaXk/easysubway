#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <dotenv-file>\n' "$0" >&2
  exit 2
fi

env_file="$1"
if [[ ! -f "${env_file}" ]]; then
  printf 'deployment env file not found: %s\n' "${env_file}" >&2
  exit 2
fi

has_env_name() {
  local name="$1"
  grep -Eq "^${name}=" "${env_file}"
}

is_satisfied_by_runtime_fallback() {
  local name="$1"
  case "${name}" in
    EASYSUBWAY_REPORT_RECEIPT_PEPPER)
      has_env_name EASYSUBWAY_REPORT_RECEIPT_TOKEN_PEPPER
      ;;
    EASYSUBWAY_REPORT_UPLOAD_INTENT_SIGNING_KEY)
      has_env_name EASYSUBWAY_REPORT_RECEIPT_PEPPER || has_env_name EASYSUBWAY_REPORT_RECEIPT_TOKEN_PEPPER
      ;;
    EASYSUBWAY_OBJECT_STORAGE_REGION)
      true
      ;;
    *)
      false
      ;;
  esac
}

missing_names=()
while IFS= read -r name; do
  if [[ -n "${name}" ]] && ! has_env_name "${name}" && ! is_satisfied_by_runtime_fallback "${name}"; then
    missing_names+=("${name}")
  fi
done < <(sed -nE 's/^([A-Z0-9_]+)=.*/\1/p' .env.example)

if (( ${#missing_names[@]} > 0 )); then
  printf 'Missing required deployment env names:\n' >&2
  printf ' - %s\n' "${missing_names[@]}" >&2
  exit 1
fi
