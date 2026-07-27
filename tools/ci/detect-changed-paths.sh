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
datapack=false
route_map=false
realtime=false
release=false
contracts=false
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
    contracts/**)
      repository=true
      contracts=true
      backend=true
      mobile=true
      android=true
      ios=true
      datapack=true
      ;;
    apps/mobile/assets/datapacks/**)
      repository=true
      contracts=true
      mobile=true
      android=true
      ios=true
      datapack=true
      ;;
    .github/workflows/cd.yml)
      ci=true
      repository=true
      deploy=true
      ;;
    .github/workflows/*.yml|.github/actionlint.yaml|tools/ci/**|tools/repo/**|tools/qa/**)
      ci=true
      repository=true
      ;;
    tools/lib/**)
      # tools/lib는 계약·datapack·route-map 등 도구 전반이 공유하는 단일 원본이다(#2515).
      # ci=true로 올려야 정렬 의미 변경이 tracked ledger 회귀까지 도달한다.
      ci=true
      repository=true
      ;;
    tools/design/**)
      repository=true
      ;;
    .env.example)
      repository=true
      contracts=true
      ;;
    backend/quality/**)
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
    tools/datapack/**)
      repository=true
      datapack=true
      mobile=true
      android=true
      ios=true
      deploy=true
      ;;
    tools/mobile/**)
      # tools/mobile은 Android 릴리즈 산출물 가드(dart-define 검증, 16KB page size,
      # ELF load 정렬)와 status voice 인벤토리를 담는다(#2518).
      # repository=true: 이 스크립트를 읽고 실행하는 계약 테스트가 스킵되면 안 된다.
      # android=true: 가드를 실제로 실행하는 소비자는 release-artifacts.yml의
      #   android-release job(if: android || mobile)이다. mobile=true는 tools/mobile을
      #   소비하지 않는 Flutter mobile-app job까지 깨우므로 올리지 않는다.
      repository=true
      android=true
      ;;
    tools/route-map/**|tools/routes/**)
      repository=true
      route_map=true
      ;;
    tools/realtime/**)
      repository=true
      realtime=true
      ;;
    tools/test/**)
      repository=true
      ;;
    tools/security/**)
      repository=true
      ;;
    tools/ops/**)
      repository=true
      ;;
    tools/release/**)
      repository=true
      release=true
      ;;
    apps/mobile/release/**)
      # repository=true여야 contract test(claim 스캔)가 실행된다(#2390). 이 게이트가 지키는 자산이 여기 있다.
      repository=true
      mobile=true
      android=true
      ios=true
      release=true
      contracts=true
      ;;
    apps/mobile/android/app/build.gradle.kts)
      mobile=true
      android=true
      ;;
    apps/mobile/ios/Runner.xcodeproj/**|apps/mobile/ios/Runner/PrivacyInfo.xcprivacy|apps/mobile/ios/Runner/Info.plist)
      mobile=true
      ios=true
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
  datapack=true
  route_map=true
  realtime=true
  release=true
  contracts=true
  docs_only=false
fi

if [[ "${ci}" == "true" ]]; then
  android=true
  backend=true
  mobile=true
  ios=true
  repository=true
  datapack=true
  route_map=true
  realtime=true
  release=true
  contracts=true
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
datapack=${datapack}
route_map=${route_map}
realtime=${realtime}
release=${release}
contracts=${contracts}
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
    echo "- datapack: ${datapack}"
    echo "- route_map: ${route_map}"
    echo "- realtime: ${realtime}"
    echo "- release: ${release}"
    echo "- contracts: ${contracts}"
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
