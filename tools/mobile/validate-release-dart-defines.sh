#!/usr/bin/env bash
set -euo pipefail

for arg in "$@"; do
  case "${arg}" in
    --dart-define=EASYSUBWAY_DEMO_HOME_DATA=true|--dart-define=EASYSUBWAY_DEMO_HOME_DATA=True|--dart-define=EASYSUBWAY_DEMO_HOME_DATA=TRUE)
      printf 'EASYSUBWAY_DEMO_HOME_DATA is not allowed in release.\n' >&2
      exit 1
      ;;
  esac
done
