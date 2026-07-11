#!/usr/bin/env bash
set -euo pipefail

api_base_url=""
api_base_url_seen=false

for arg in "$@"; do
  case "${arg}" in
    --dart-define=EASYSUBWAY_DEMO_HOME_DATA=true|--dart-define=EASYSUBWAY_DEMO_HOME_DATA=True|--dart-define=EASYSUBWAY_DEMO_HOME_DATA=TRUE)
      printf 'EASYSUBWAY_DEMO_HOME_DATA is not allowed in release.\n' >&2
      exit 1
      ;;
    --dart-define=EASYSUBWAY_API_BASE_URL=*)
      if [[ "${api_base_url_seen}" == "true" ]]; then
        printf 'EASYSUBWAY_API_BASE_URL must be defined exactly once.\n' >&2
        exit 1
      fi
      api_base_url_seen=true
      api_base_url="${arg#--dart-define=EASYSUBWAY_API_BASE_URL=}"
      ;;
  esac
done

if [[ "${api_base_url_seen}" != "true" || -z "${api_base_url}" ]]; then
  printf 'EASYSUBWAY_API_BASE_URL is required for release.\n' >&2
  exit 1
fi
if [[ "${api_base_url}" != "${api_base_url//[[:space:]]/}" ]]; then
  printf 'EASYSUBWAY_API_BASE_URL must not contain whitespace.\n' >&2
  exit 1
fi
if [[ "${api_base_url}" != https://* ]]; then
  printf 'EASYSUBWAY_API_BASE_URL must use HTTPS.\n' >&2
  exit 1
fi

remainder="${api_base_url#https://}"
authority="${remainder%%[/?#]*}"
if [[ -z "${authority}" || "${authority}" == *"@"* || "${authority}" == *"["* || "${authority}" == *"]"* ]]; then
  printf 'EASYSUBWAY_API_BASE_URL must include a public host.\n' >&2
  exit 1
fi

host="${authority%%:*}"
if [[ "${authority}" == *":"* ]]; then
  port="${authority#*:}"
  if [[ "${port}" == *":"* || ! "${port}" =~ ^[0-9]+$ ]]; then
    printf 'EASYSUBWAY_API_BASE_URL has an invalid port.\n' >&2
    exit 1
  fi
fi
host="$(printf '%s' "${host}" | tr '[:upper:]' '[:lower:]')"
if [[ ! "${host}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ || "${host}" != *.* || "${host}" == *".."* ]]; then
  printf 'EASYSUBWAY_API_BASE_URL must include a valid public host.\n' >&2
  exit 1
fi

case "${host}" in
  localhost|*.localhost|127.*|0.0.0.0|*.local|example.com|*.example.com|example.org|*.example.org|example.net|*.example.net|*.example|*.invalid|*.test)
    printf 'EASYSUBWAY_API_BASE_URL must use a public non-placeholder host.\n' >&2
    exit 1
    ;;
esac
