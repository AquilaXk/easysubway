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

has_non_empty_env_value() {
  local name="$1"
  [[ -n "$(env_value "${name}")" ]]
}

trim_blank() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

env_value() {
  local name="$1"
  local value
  value="$(sed -nE "s/^${name}=(.*)$/\\1/p" "${env_file}" | tail -n 1)"
  value="$(trim_blank "${value}")"
  case "${value}" in
    \"*\"|\'*\')
      if (( ${#value} >= 2 )); then
        value="${value:1:${#value}-2}"
      fi
      ;;
    *)
      ;;
  esac
  trim_blank "${value}"
}

normalized_env_value() {
  local name="$1"
  env_value "${name}" | tr '[:upper:]' '[:lower:]'
}

is_bool_env_value() {
  local name="$1"
  case "$(normalized_env_value "${name}")" in
    true|false|on|off|yes|no|1|0)
      true
      ;;
    *)
      false
      ;;
  esac
}

is_admin_basic_auth_enabled() {
  case "$(normalized_env_value EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED)" in
    true|on|yes|1)
      true
      ;;
    *)
      false
      ;;
  esac
}

is_truthy_env_value() {
  local name="$1"
  case "$(normalized_env_value "${name}")" in
    true|on|yes|1)
      true
      ;;
    *)
      false
      ;;
  esac
}

is_false_env_value() {
  local name="$1"
  case "$(normalized_env_value "${name}")" in
    false|off|no|0)
      true
      ;;
    *)
      false
      ;;
  esac
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
    EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL)
      true
      ;;
    EASYSUBWAY_REPORT_ABUSE_STORE_MODE)
      true
      ;;
    EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED)
      true
      ;;
    EASYSUBWAY_ADMIN_REVISION)
      true
      ;;
    EASYSUBWAY_ADMIN_MASTER_DATA_VERSION)
      true
      ;;
    EASYSUBWAY_ADMIN_CUTOVER_ENFORCED)
      true
      ;;
    EASYSUBWAY_ADMIN_PLATFORM_FLAGS_RBAC_ENFORCEMENT)
      true
      ;;
    EASYSUBWAY_ADMIN_PLATFORM_FLAGS_AUDIT_ENFORCEMENT)
      true
      ;;
    EASYSUBWAY_ADMIN_PLATFORM_FLAGS_LEGACY_ENV_ADMIN_FALLBACK)
      true
      ;;
    EASYSUBWAY_ADMIN_PLATFORM_FLAGS_BREAK_GLASS_BOOTSTRAP)
      true
      ;;
    EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER)
      ! is_admin_basic_auth_enabled
      ;;
    EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT)
      ! is_admin_basic_auth_enabled
      ;;
    *)
      false
      ;;
  esac
}

is_required_env_satisfied() {
  local name="$1"
  case "${name}" in
    EASYSUBWAY_ADMIN_BASIC_AUTH_ENABLED)
      if has_env_name "${name}"; then
        is_bool_env_value "${name}"
      else
        is_satisfied_by_runtime_fallback "${name}"
      fi
      ;;
    EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_OWNER|EASYSUBWAY_ADMIN_BASIC_AUTH_EXCEPTION_EXPIRES_AT)
      if is_admin_basic_auth_enabled; then
        has_non_empty_env_value "${name}"
      else
        has_env_name "${name}" || is_satisfied_by_runtime_fallback "${name}"
      fi
      ;;
    *)
      has_env_name "${name}" || is_satisfied_by_runtime_fallback "${name}"
      ;;
  esac
}

missing_names=()
while IFS= read -r name; do
  if [[ -n "${name}" ]] && ! is_required_env_satisfied "${name}"; then
    missing_names+=("${name}")
  fi
done < <(sed -nE 's/^([A-Z0-9_]+)=.*/\1/p' .env.example)

if (( ${#missing_names[@]} > 0 )); then
  printf 'Missing required deployment env names:\n' >&2
  printf ' - %s\n' "${missing_names[@]}" >&2
  exit 1
fi

cutover_invalid_names=()
if is_truthy_env_value EASYSUBWAY_ADMIN_CUTOVER_ENFORCED; then
  if ! is_truthy_env_value EASYSUBWAY_ADMIN_PLATFORM_FLAGS_RBAC_ENFORCEMENT; then
    cutover_invalid_names+=(EASYSUBWAY_ADMIN_PLATFORM_FLAGS_RBAC_ENFORCEMENT)
  fi
  if ! is_truthy_env_value EASYSUBWAY_ADMIN_PLATFORM_FLAGS_AUDIT_ENFORCEMENT; then
    cutover_invalid_names+=(EASYSUBWAY_ADMIN_PLATFORM_FLAGS_AUDIT_ENFORCEMENT)
  fi
  if ! is_false_env_value EASYSUBWAY_ADMIN_PLATFORM_FLAGS_LEGACY_ENV_ADMIN_FALLBACK; then
    cutover_invalid_names+=(EASYSUBWAY_ADMIN_PLATFORM_FLAGS_LEGACY_ENV_ADMIN_FALLBACK)
  fi
  if ! is_false_env_value EASYSUBWAY_ADMIN_PLATFORM_FLAGS_BREAK_GLASS_BOOTSTRAP; then
    cutover_invalid_names+=(EASYSUBWAY_ADMIN_PLATFORM_FLAGS_BREAK_GLASS_BOOTSTRAP)
  fi
fi

if (( ${#cutover_invalid_names[@]} > 0 )); then
  printf 'Invalid admin cutover env values:\n' >&2
  printf ' - %s\n' "${cutover_invalid_names[@]}" >&2
  exit 1
fi
