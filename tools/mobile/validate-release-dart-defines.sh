#!/usr/bin/env bash
set -euo pipefail

api_base_url=""
api_base_url_seen=false
route_v2_online_enabled=false
play_integrity_cloud_project_number=""
play_integrity_cloud_project_number_seen=false
kakao_map_native_app_key=""
kakao_map_native_app_key_seen=false

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
    --dart-define=EASYSUBWAY_ROUTE_V2_ONLINE_FIRST_ENABLED=true)
      route_v2_online_enabled=true
      ;;
    --dart-define=EASYSUBWAY_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=*)
      if [[ "${play_integrity_cloud_project_number_seen}" == "true" ]]; then
        printf 'EASYSUBWAY_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER must be defined exactly once.\n' >&2
        exit 1
      fi
      play_integrity_cloud_project_number_seen=true
      play_integrity_cloud_project_number="${arg#--dart-define=EASYSUBWAY_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER=}"
      ;;
    --dart-define=EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY=*)
      if [[ "${kakao_map_native_app_key_seen}" == "true" ]]; then
        printf 'EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY must be defined exactly once.\n' >&2
        exit 1
      fi
      kakao_map_native_app_key_seen=true
      kakao_map_native_app_key="${arg#--dart-define=EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY=}"
      ;;
  esac
done

if [[ "${route_v2_online_enabled}" == "true" &&
  ! "${play_integrity_cloud_project_number}" =~ ^[1-9][0-9]*$ ]]; then
  printf 'EASYSUBWAY_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER must be a positive integer when Route V2 online transport is enabled.\n' >&2
  exit 1
fi

if [[ "${api_base_url_seen}" != "true" || -z "${api_base_url}" ]]; then
  printf 'EASYSUBWAY_API_BASE_URL is required for release.\n' >&2
  exit 1
fi
if [[ "${kakao_map_native_app_key_seen}" != "true" || -z "${kakao_map_native_app_key}" ]]; then
  printf 'EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY is required for release.\n' >&2
  exit 1
fi
if [[ "${kakao_map_native_app_key}" != "${kakao_map_native_app_key//[[:space:]]/}" ]]; then
  printf 'EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY must not contain whitespace.\n' >&2
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
  if [[ "${port}" == *":"* || ! "${port}" =~ ^[0-9]+$ ||
    "${port}" == 0* || ${#port} -gt 5 ||
    ( ${#port} -eq 5 && "${port}" > "65535" ) ]]; then
    printf 'EASYSUBWAY_API_BASE_URL has an invalid port.\n' >&2
    exit 1
  fi
fi
host="$(printf '%s' "${host}" | tr '[:upper:]' '[:lower:]')"
if [[ ! "${host}" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ || "${host}" != *.* || "${host}" == *".."* ]]; then
  printf 'EASYSUBWAY_API_BASE_URL must include a valid public host.\n' >&2
  exit 1
fi
if [[ "${host}" =~ ^[0-9.]+$ ]]; then
  printf 'EASYSUBWAY_API_BASE_URL must not use an IP literal.\n' >&2
  exit 1
fi

case "${host}" in
  localhost|*.localhost|127.*|0.0.0.0|*.local|example.com|*.example.com|example.org|*.example.org|example.net|*.example.net|*.example|*.invalid|*.test)
    printf 'EASYSUBWAY_API_BASE_URL must use a public non-placeholder host.\n' >&2
    exit 1
    ;;
  *) ;;
esac
