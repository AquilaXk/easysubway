#!/usr/bin/env bash
set -euo pipefail

# ── 노선도 QA 통합 게이트 오케스트레이터 (#1952) ──────────────────────────────
#
# 수도권 도식은 오너가 v2, v3… 로 계속 버저닝해 재배포한다. 버전 교체 때마다 이
# 스크립트 하나로 라벨·성능·오프라인 게이트를 재실행한다(이슈 #1952 반복 운영 전제).
#
# 실행 순서(체크리스트):
#   [0] 4권역 노출 실측 — 팩 route_map_positions 의 distinct region 확인
#       (부산권·대구권·대전권·광주권 + 수도권). 프로덕션 _networkMapRegions() 는
#       SELECT DISTINCT region 이므로 팩에 수록된 권역이 그대로 노출된다.
#   [1] 라벨 겹침 기계 게이트 — 수도권 + 비수도권 4권역 0/baseline:
#         flutter test test/features/network_map/presentation/capital_label_overlap_gate_test.dart
#         flutter test test/features/network_map/presentation/regional_label_overlap_gate_test.dart
#   [2] 스케일 3구간 스크린샷 매트릭스(min contain-fit / 초기 / 초기×2) — 5개 권역.
#       폰트 하한 판정 = 초기×2 환승역명 가독. 라벨 겹침 게이트(보수 전각 폭 근사)가
#       초기 스케일 가독을 기계 보증하고, 확대는 라벨을 키우기만 하므로 하한은 초기다.
#       실기기 스크린샷은 아래 성능/전환 스크립트가 각 권역 진입 시 캡처한다.
#   [3] 접근성 baseline(48dp hit target·대비 토큰·semantics):
#         flutter test test/accessibility_baseline_test.dart
#       실기기 semantics(역명·노선·환승·출발/경유/도착 action)는 uiautomator 덤프로
#       확인한다(런처 진입 후 content-desc: '<역>역', '노선도, 역을 누르면 …', 역 tap
#       시 '출발/경유/도착/닫기').
#   [4] 성능 재측정(profile 빌드, Galaxy A17급 실기기):
#         tools/mobile/run-route-map-android-evidence.sh … --measure-after-route-map-settle
#         node  tools/mobile/analyze-route-map-android-evidence.mjs --artifact-dir <dir>
#       기준: frame P90 < 16.7ms, jank < 5%, pan 중 crash 0.
#       신규 2종(cold start 첫 표시·지역 전환):
#         tools/mobile/run-route-map-launch-region-evidence.sh …
#   [5] 오프라인 QA — adb 비행기 모드 토글 후 5개 권역 표시·역 tap·지역 전환.
#
# 성능 측정은 profile 빌드, 스크린샷/semantics 캡처는 debug 또는 profile 빌드가
# 설치돼 있어야 한다(routeMapFrame 로그 필수). 온보딩은 매 cold start 재노출될 수
# 있어(측정 중 확인) launch-region 스크립트가 CTA 를 자동 통과한다.
#
# fail closed: 기기 미연결·프레임 로그 부재·게이트 미달은 위조 없이 비영 종료.

usage() {
  cat <<'USAGE'
Usage:
  tools/mobile/run-route-map-qa-gate.sh --serial <adb-serial> --artifact-root <dir> [options]

Options:
  --serial <adb-serial>     Required Android device serial (Galaxy A17급 실기기 권장).
  --artifact-root <dir>     Required. 하위에 tests/perf/launch-region/offline 산출.
  --adb <path>              adb executable. Defaults to $ADB or PATH lookup.
  --pan-count <n>           성능 pan 횟수. Defaults to 5(기록 baseline 과 동일 축).
  --skip-tests              flutter 게이트 테스트 스킵(실기기 단계만).
  --skip-device            실기기 단계 스킵(flutter 게이트만).
  -h, --help                Show this help.

프레임 P90<16.7ms·jank<5%·crash 0 판정은 analyze 스크립트 출력의 FrameTiming
(build/raster p90·janky%) 을 정본으로 읽는다.
USAGE
}

SERIAL=""
ARTIFACT_ROOT=""
ADB="${ADB:-}"
PAN_COUNT=5
SKIP_TESTS="false"
SKIP_DEVICE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="${2:-}"; shift 2 ;;
    --artifact-root) ARTIFACT_ROOT="${2:-}"; shift 2 ;;
    --adb) ADB="${2:-}"; shift 2 ;;
    --pan-count) PAN_COUNT="${2:-}"; shift 2 ;;
    --skip-tests) SKIP_TESTS="true"; shift ;;
    --skip-device) SKIP_DEVICE="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MOBILE_DIR="$REPO_ROOT/apps/mobile"

if [[ "$SKIP_TESTS" != "true" ]]; then
  echo "== [1] 라벨 겹침 게이트 (수도권 + 비수도권 4권역) =="
  ( cd "$MOBILE_DIR" && flutter test \
      test/features/network_map/presentation/capital_label_overlap_gate_test.dart \
      test/features/network_map/presentation/regional_label_overlap_gate_test.dart )
  echo "== [3] 접근성 baseline (48dp·대비·semantics) =="
  ( cd "$MOBILE_DIR" && flutter test test/accessibility_baseline_test.dart )
fi

if [[ "$SKIP_DEVICE" == "true" ]]; then
  echo "device 단계 스킵. flutter 게이트 완료."
  exit 0
fi

if [[ -z "$SERIAL" || -z "$ARTIFACT_ROOT" ]]; then
  echo "--serial 와 --artifact-root 는 실기기 단계에 필수." >&2
  usage
  exit 1
fi
mkdir -p "$ARTIFACT_ROOT"
ADB_ARGS=()
[[ -n "$ADB" ]] && ADB_ARGS=(--adb "$ADB")

echo "== [4] 성능 재측정 (profile, pan=$PAN_COUNT) =="
"$SCRIPT_DIR/run-route-map-android-evidence.sh" \
  --serial "$SERIAL" --artifact-dir "$ARTIFACT_ROOT/perf" \
  --build-mode profile --pan-count "$PAN_COUNT" --measure-after-route-map-settle \
  "${ADB_ARGS[@]}"
node "$SCRIPT_DIR/analyze-route-map-android-evidence.mjs" --artifact-dir "$ARTIFACT_ROOT/perf"

echo "== [4b] 신규 측정: cold start 첫 표시 · 지역 전환 =="
"$SCRIPT_DIR/run-route-map-launch-region-evidence.sh" \
  --serial "$SERIAL" --artifact-dir "$ARTIFACT_ROOT/launch-region" \
  --cold-start-iterations 3 --region-target 부산 "${ADB_ARGS[@]}"

echo
echo "완료. 판정은 각 산출 summary 를 열어 P90<16.7ms·jank<5%·crash 0 및"
echo "cold start·지역 전환 수치를 확인하라. 오프라인([5])·스케일 매트릭스([2])는"
echo "이 스크립트가 진입한 권역 스크린샷과 함께 수동 판독한다."
