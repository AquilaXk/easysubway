#!/usr/bin/env bash
set -euo pipefail

changed_files_path="${1:?changed files path is required}"

android=false
backend=false
mobile=false
ios=false
repository=false
docs_only=true
ci=false
deploy=false
saw_file=false

is_docs_file() {
  case "$1" in
    README.md|LICENSE|LICENSE.*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

while IFS= read -r file; do
  [[ -z "${file}" ]] && continue
  saw_file=true

  if ! is_docs_file "${file}"; then
    docs_only=false
  fi

  case "${file}" in
    .github/workflows/*.yml|tools/ci/**)
      ci=true
      repository=true
      ;;
    .github/**|.gitignore|.coderabbit.yaml)
      repository=true
      ;;
    tools/deploy/**|infra/**|docker-compose*.yml)
      repository=true
      deploy=true
      ;;
    scripts/**)
      repository=true
      ;;
  esac

  case "${file}" in
    backend/**)
      backend=true
      deploy=true
      ;;
  esac

  case "${file}" in
    apps/mobile/**)
      mobile=true
      android=true
      ios=true
      ;;
  esac

  case "${file}" in
    apps/mobile/android/**)
      android=true
      ;;
  esac

  case "${file}" in
    apps/mobile/ios/**)
      ios=true
      ;;
  esac
done < "${changed_files_path}"

if [[ "${saw_file}" == "false" ]]; then
  android=true
  backend=true
  mobile=true
  ios=true
  repository=true
  deploy=true
  docs_only=false
fi

if [[ "${ci}" == "true" ]]; then
  android=true
  backend=true
  mobile=true
  ios=true
  repository=true
  docs_only=false
fi

outputs_payload() {
  cat <<EOF
android=${android}
backend=${backend}
mobile=${mobile}
ios=${ios}
repository=${repository}
docs_only=${docs_only}
ci=${ci}
deploy=${deploy}
EOF
}

write_outputs() {
  {
    outputs_payload
  } >> "${GITHUB_OUTPUT}"
}

write_summary() {
  {
    echo "### Changed files"
    sed 's/^/- `/' "${changed_files_path}" | sed 's/$/`/'
    echo
    echo "### CI gates"
    echo "- android: ${android}"
    echo "- backend: ${backend}"
    echo "- mobile: ${mobile}"
    echo "- ios: ${ios}"
    echo "- repository: ${repository}"
    echo "- docs_only: ${docs_only}"
    echo "- ci: ${ci}"
    echo "- deploy: ${deploy}"
  } >> "${GITHUB_STEP_SUMMARY}"
}

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  write_outputs
else
  outputs_payload
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  write_summary
fi
