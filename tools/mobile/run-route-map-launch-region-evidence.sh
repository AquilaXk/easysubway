#!/usr/bin/env bash
set -euo pipefail

# #1952 작업 4 신규 측정 2종:
#   ① cold start → 노선도 첫 표시 시간 (목표 ≤ 2s)
#   ② 지역 전환 시간 (권역 메뉴 탭 → 새 권역 노선도 첫 프레임)
#
# 정본 프레임 신호는 앱이 로깅하는 'routeMapFrame'(#1643, FrameTiming)이다. 노선도는
# Flutter 자체 렌더 파이프라인이라 dumpsys gfxinfo로 프레임이 안 잡혀, 첫 표시/전환
# 완료 판정을 첫 routeMapFrame 로그 타임스탬프로 한다. 측정 정확도를 위해 debug 또는
# profile 빌드가 설치돼 있어야 하며(routeMapFrame 미기록 시 fail closed), 온보딩은
# 완료돼 실행 즉시 노선도가 홈으로 뜨는 상태여야 한다.
#
# 이 스크립트는 아무것도 설치하지 않는다. 기기 미연결·노선도 미구동·프레임 로그
# 부재·측정 파싱 불가는 전부 실패(exit 1)로 처리한다(측정치 위조 금지).

usage() {
  cat <<'USAGE'
Usage:
  tools/mobile/run-route-map-launch-region-evidence.sh --serial <adb-serial> --artifact-dir <dir> [options]

Options:
  --serial <adb-serial>     Required Android device serial.
  --artifact-dir <dir>      Required output directory for logs and summary.
  --package <package>       App package. Defaults to com.easysubway.app.
  --activity <name>         Launcher activity. Defaults to
                            com.easysubway.easysubway_mobile.MainActivity
                            (축약 .MainActivity 는 Error type 3 이므로 FQN 필수).
  --adb <path>              adb executable. Defaults to $ADB or PATH lookup.
  --cold-start-iterations N Cold start 반복 측정 횟수. Defaults to 3.
  --region-target <name>    지역 전환 목표 권역 (메뉴 셀 텍스트). Defaults to 부산.
  --settle-seconds <sec>    각 단계 안착 대기. Defaults to 4.
  -h, --help                Show this help.
USAGE
}

SERIAL=""
ARTIFACT_DIR=""
PACKAGE="com.easysubway.app"
ACTIVITY="com.easysubway.easysubway_mobile.MainActivity"
ADB="${ADB:-}"
COLD_START_ITERATIONS=3
REGION_TARGET="부산"
SETTLE_SECONDS=4
ONBOARDING_MAX_STEPS=8

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="${2:-}"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="${2:-}"; shift 2 ;;
    --package) PACKAGE="${2:-}"; shift 2 ;;
    --activity) ACTIVITY="${2:-}"; shift 2 ;;
    --adb) ADB="${2:-}"; shift 2 ;;
    --cold-start-iterations) COLD_START_ITERATIONS="${2:-}"; shift 2 ;;
    --region-target) REGION_TARGET="${2:-}"; shift 2 ;;
    --settle-seconds) SETTLE_SECONDS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$SERIAL" || -z "$ARTIFACT_DIR" ]]; then
  echo "--serial and --artifact-dir are required." >&2
  usage
  exit 1
fi

if [[ -z "$ADB" ]]; then
  ADB="$(command -v adb || true)"
fi
if [[ -z "$ADB" ]]; then
  echo "adb executable not found. Pass --adb or set \$ADB." >&2
  exit 1
fi

mkdir -p "$ARTIFACT_DIR"

adb_device() { "$ADB" -s "$SERIAL" "$@"; }

require_non_empty() {
  local path="$1"
  if [[ ! -s "$path" ]]; then
    echo "Expected non-empty artifact: $path" >&2
    exit 1
  fi
}

if ! adb_device get-state | grep -qx "device"; then
  echo "adb target is not ready: $SERIAL" >&2
  exit 1
fi

wm_size="$(adb_device shell wm size | tr -d '\r')"
if [[ ! "$wm_size" =~ ([0-9]+)x([0-9]+) ]]; then
  echo "Unable to parse device size from: $wm_size" >&2
  exit 1
fi
WIDTH="${BASH_REMATCH[1]}"
HEIGHT="${BASH_REMATCH[2]}"

# 기기 시계 epoch(나노초). logcat -v epoch 와 동일 시계축(기기 date)이라 host 시계와
# 섞이지 않는다. cold start·전환 시작 시각을 기기에서 직접 읽어 정확도를 높인다.
device_epoch_ns() {
  adb_device shell 'date +%s%N' | tr -d '\r'
}

# logcat epoch 버퍼에서 첫 routeMapFrame 라인의 epoch(초.밀리)를 반환. 호출 직전에
# logcat -c 로 버퍼를 비운 뒤 사용한다(그 이후 첫 프레임 = 측정 대상).
first_route_map_frame_epoch() {
  # awk 로 첫 매치만 출력하되 exit 하지 않고 입력을 끝까지 읽는다. exit 로 조기
  # 종료하면 set -o pipefail 하에서 앞단 logcat 이 SIGPIPE(141)로 죽어 매치가
  # 있어도 파이프라인이 실패로 처리된다(첫 프레임 판정 오탐).
  adb_device logcat -d -v epoch \
    | awk '/routeMapFrame/ && !seen { print $1; seen = 1 }' \
    | tr -d '\r'
}

# 첫 routeMapFrame 이 로그에 나타날 때까지 최대 max_wait 초 폴링(초.밀리 반환, 없으면
# 공란). cold start 첫 표시는 데이터팩 압축 해제·레이아웃 때문에 편차가 커, 고정
# settle 대신 프레임 등장을 폴링해 측정치의 위·아래 편향을 줄인다.
wait_route_map_frame_epoch() {
  local max_wait="$1"
  local waited=0 epoch=""
  while (( waited < max_wait )); do
    epoch="$(first_route_map_frame_epoch)"
    if [[ -n "$epoch" ]]; then
      echo "$epoch"
      return 0
    fi
    sleep 1
    waited=$(( waited + 1 ))
  done
  echo ""
}

# 시작 epoch(ns)와 첫 프레임 epoch(초.밀리) 사이의 ms.
elapsed_ms_from_ns() {
  local start_ns="$1" frame_epoch_s="$2"
  awk -v s="$start_ns" -v f="$frame_epoch_s" 'BEGIN{printf "%.0f", (f - s/1e9) * 1000}'
}

# Flutter 제스처 인식기가 `input tap` 합성 이벤트를 드롭하는 케이스가 있어(온보딩
# CTA·노선도), DOWN/UP 분리 motionevent 로 탭한다(실측: tap 무반응, motionevent 정상).
robust_tap() {
  local x="$1" y="$2"
  adb_device shell input motionevent DOWN "$x" "$y" >/dev/null 2>&1
  sleep 0.15
  adb_device shell input motionevent UP "$x" "$y" >/dev/null 2>&1
}

onboarding_cta_bounds() {
  adb_device shell uiautomator dump /sdcard/ob.xml >/dev/null
  adb_device pull /sdcard/ob.xml "$ARTIFACT_DIR/onboarding-dump.xml" >/dev/null
  if [[ -s "$ARTIFACT_DIR/onboarding-dump.xml" ]]; then
    grep -o 'content-desc="[^"]*\(시작하기\|이대로 시작\)[^"]*"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$ARTIFACT_DIR/onboarding-dump.xml" | head -1 | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | head -1 || true
  fi
}

# 온보딩 CTA를 UI 트리에서 찾아 bounded loop로 통과한다. 마지막 CTA 탭 시각(ns)은
# cold start의 순수 map-load 구간 측정에 쓴다.
dismiss_onboarding() {
  local completed_ns=""
  local cta_bounds=""
  for ((step = 1; step <= ONBOARDING_MAX_STEPS; step += 1)); do
    # grep -q 는 첫 매치에서 종료해 pipefail 하 logcat 을 SIGPIPE 로 죽인다 —
    # grep -c 로 입력을 끝까지 읽어 매치 수를 세고, 0 초과면 프레임이 이미 떴다고
    # 판정한다(로그 존재 시 온보딩 단계 종료).
    if [[ "$(adb_device logcat -d | grep -c routeMapFrame)" -gt 0 ]]; then
      break
    fi
    cta_bounds="$(onboarding_cta_bounds)"
    if [[ -z "$cta_bounds" ]]; then
      # UI 트리에 CTA 가 없으면 온보딩이 아니거나 이미 지나감 — 종료.
      break
    fi
    if [[ "$cta_bounds" =~ \[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\] ]]; then
      local cx=$(( (${BASH_REMATCH[1]} + ${BASH_REMATCH[3]}) / 2 ))
      local cy=$(( (${BASH_REMATCH[2]} + ${BASH_REMATCH[4]}) / 2 ))
      completed_ns="$(device_epoch_ns)"
      robust_tap "$cx" "$cy"
      sleep 2
    else
      break
    fi
  done
  cta_bounds="$(onboarding_cta_bounds)"
  if [[ -n "$cta_bounds" ]]; then
    echo "Onboarding did not finish within $ONBOARDING_MAX_STEPS steps." >&2
    exit 1
  fi
  # 마지막 CTA 탭 시각(ns)을 파일로 남긴다 — $(…) stdout 캡처보다 견고.
  echo "$completed_ns" > "$ARTIFACT_DIR/.onboarding-done-ns"
}

# ── ① cold start → 노선도 첫 표시 ───────────────────────────────────────────
COLD_LOG="$ARTIFACT_DIR/cold-start.csv"
# launch_to_frame_ms : am start → 첫 routeMapFrame (온보딩 자동 통과 포함, 실사용
#   returning-user 관점의 총 cold start). map_load_ms : 온보딩 완료(마지막 CTA 탭)
#   → 첫 routeMapFrame (데이터팩 해제·레이아웃 등 순수 노선도 로드 구간).
echo "iteration,am_total_time_ms,launch_to_frame_ms,map_load_ms" > "$COLD_LOG"

for ((it = 1; it <= COLD_START_ITERATIONS; it += 1)); do
  adb_device shell am force-stop "$PACKAGE"
  # 프로세스 종료 안착 + 파일 캐시가 아닌 process cold 보장.
  sleep 2
  adb_device logcat -c
  start_ns="$(device_epoch_ns)"
  # am start -W: TotalTime = 앱 프로세스 시작→첫 프레임 그려짐(activity displayed).
  am_out="$(adb_device shell am start -W -n "$PACKAGE/$ACTIVITY" 2>&1 | tr -d '\r')"
  echo "$am_out" >> "$ARTIFACT_DIR/am-start-$it.txt"
  # TotalTime 은 activity 최초 draw 시에만 나온다. 이미 resumed(warm no-op) 이면
  # WaitTime 만 나온다 — cold start 정본은 first routeMapFrame(첫 표시)이므로
  # TotalTime 부재는 참고값 공란으로 두고 실패시키지 않는다(측정 계속).
  am_total="$(echo "$am_out" | awk -F': ' '/^TotalTime/ {print $2}')"
  am_total="${am_total:-}"
  sleep "$SETTLE_SECONDS"
  # 온보딩이 뜨면 자동 통과하고 완료(마지막 CTA 탭) 시각(ns)을 파일로 받는다.
  : > "$ARTIFACT_DIR/.onboarding-done-ns"
  dismiss_onboarding
  onboarding_done_ns="$(tr -d '\r\n' < "$ARTIFACT_DIR/.onboarding-done-ns")"
  # 첫 routeMapFrame epoch − 프로세스 시작 epoch(ns) = 노선도 첫 표시까지(ms).
  frame_epoch="$(wait_route_map_frame_epoch "$(( SETTLE_SECONDS + 8 ))")"
  if [[ -z "$frame_epoch" ]]; then
    echo "No routeMapFrame log after cold start (iteration $it)." >&2
    echo "Use a debug/profile build; onboarding 자동 통과 실패 여부 확인." >&2
    exit 1
  fi
  launch_to_frame_ms="$(elapsed_ms_from_ns "$start_ns" "$frame_epoch")"
  if [[ -n "$onboarding_done_ns" ]]; then
    map_load_ms="$(elapsed_ms_from_ns "$onboarding_done_ns" "$frame_epoch")"
  else
    map_load_ms="$launch_to_frame_ms"
  fi
  echo "$it,$am_total,$launch_to_frame_ms,$map_load_ms" >> "$COLD_LOG"
done

# ── ② 지역 전환 시간 ────────────────────────────────────────────────────────
# 노선도 홈에서 지역 메뉴 버튼(Semantics '지역: …, 지역 변경')을 UI 트리에서 찾아 탭,
# 목표 권역 셀을 탭한 뒤 새 권역 첫 routeMapFrame 까지의 시간을 측정한다.
REGION_LOG="$ARTIFACT_DIR/region-switch.csv"
echo "region_target,switch_ms" > "$REGION_LOG"

adb_device shell am force-stop "$PACKAGE"
sleep 2
adb_device logcat -c
adb_device shell am start -n "$PACKAGE/$ACTIVITY" >/dev/null
sleep "$SETTLE_SECONDS"
# 노선도 홈까지 온보딩 자동 통과.
dismiss_onboarding >/dev/null
sleep 2

UI_XML="$ARTIFACT_DIR/region-ui-before.xml"
adb_device exec-out uiautomator dump /dev/tty 2>/dev/null | sed 's/UI hierchary dumped to: \/dev\/tty//' > "$UI_XML" || true
if [[ ! -s "$UI_XML" ]]; then
  adb_device shell uiautomator dump /sdcard/region-ui.xml >/dev/null 2>&1
  adb_device pull /sdcard/region-ui.xml "$UI_XML" >/dev/null 2>&1 || true
fi
require_non_empty "$UI_XML"

# '지역 변경' 을 포함한 노드의 bounds 를 파싱해 중심 좌표를 얻는다.
region_bounds="$(grep -o 'content-desc="[^"]*지역 변경[^"]*"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$UI_XML" | head -1 | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | head -1 || true)"
if [[ -z "$region_bounds" ]]; then
  echo "지역 변경 컨트롤을 UI 트리에서 찾지 못했다 — semantics 라벨/노선도 홈 상태 확인." >&2
  echo "UI dump: $UI_XML" >&2
  exit 1
fi
if [[ "$region_bounds" =~ \[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\] ]]; then
  rx=$(( (${BASH_REMATCH[1]} + ${BASH_REMATCH[3]}) / 2 ))
  ry=$(( (${BASH_REMATCH[2]} + ${BASH_REMATCH[4]}) / 2 ))
else
  echo "지역 변경 bounds 파싱 실패: $region_bounds" >&2
  exit 1
fi

robust_tap "$rx" "$ry"
sleep 1

# 메뉴에서 목표 권역 셀 탭.
MENU_XML="$ARTIFACT_DIR/region-ui-menu.xml"
adb_device shell uiautomator dump /sdcard/region-menu.xml >/dev/null 2>&1
adb_device pull /sdcard/region-menu.xml "$MENU_XML" >/dev/null 2>&1 || true
require_non_empty "$MENU_XML"

target_bounds="$(grep -o "text=\"$REGION_TARGET\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" "$MENU_XML" | head -1 | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | head -1 || true)"
if [[ -z "$target_bounds" ]]; then
  # content-desc 로도 시도.
  target_bounds="$(grep -o "content-desc=\"[^\"]*${REGION_TARGET}[^\"]*\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" "$MENU_XML" | head -1 | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' | head -1 || true)"
fi
if [[ -z "$target_bounds" ]]; then
  echo "권역 메뉴에서 '$REGION_TARGET' 셀을 찾지 못했다." >&2
  echo "Menu dump: $MENU_XML" >&2
  exit 1
fi
if [[ "$target_bounds" =~ \[([0-9]+),([0-9]+)\]\[([0-9]+),([0-9]+)\] ]]; then
  tx=$(( (${BASH_REMATCH[1]} + ${BASH_REMATCH[3]}) / 2 ))
  ty=$(( (${BASH_REMATCH[2]} + ${BASH_REMATCH[4]}) / 2 ))
else
  echo "권역 셀 bounds 파싱 실패: $target_bounds" >&2
  exit 1
fi

adb_device logcat -c
tap_ns="$(device_epoch_ns)"
robust_tap "$tx" "$ty"

switch_frame_epoch="$(wait_route_map_frame_epoch "$(( SETTLE_SECONDS + 8 ))")"
if [[ -z "$switch_frame_epoch" ]]; then
  echo "지역 전환 후 routeMapFrame 로그가 없다 — 전환 실패 또는 프레임 미기록." >&2
  exit 1
fi
switch_ms="$(elapsed_ms_from_ns "$tap_ns" "$switch_frame_epoch")"
echo "$REGION_TARGET,$switch_ms" >> "$REGION_LOG"

adb_device exec-out screencap -p > "$ARTIFACT_DIR/region-switched.png" || true

# ── 요약 ────────────────────────────────────────────────────────────────────
{
  echo "# EasySubway route map cold-start / region-switch evidence (#1952 작업 4)"
  echo
  echo "- serial: $SERIAL"
  echo "- package: $PACKAGE"
  echo "- activity: $ACTIVITY"
  echo "- viewport: ${WIDTH}x${HEIGHT}"
  echo "- captured_at_utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## ① Cold start → 노선도 첫 표시 (목표 ≤ 2000ms)"
  echo "- launch_to_frame_ms = am start → 첫 routeMapFrame (온보딩 자동 통과 포함)"
  echo "- map_load_ms = 온보딩 완료 CTA 탭 → 첫 routeMapFrame (순수 노선도 로드)"
  echo "- 주: 이 빌드는 온보딩 완료가 cold 재시작에 persist 되지 않아 매 회 온보딩"
  echo "  2페이지를 자동 통과한다 — 순수 로드 비용은 map_load_ms 로 판정한다."
  echo '```'
  cat "$COLD_LOG"
  echo '```'
  awk -F, 'NR>1 {s3+=$3; s4+=$4; n+=1; if($3>m3)m3=$3; if($4>m4)m4=$4} END {if(n>0) printf "- mean_launch_to_frame_ms=%.0f max=%.0f | mean_map_load_ms=%.0f max=%.0f (n=%d)\n", s3/n, m3, s4/n, m4, n}' "$COLD_LOG"
  echo
  echo "## ② 지역 전환 시간"
  echo '```'
  cat "$REGION_LOG"
  echo '```'
} > "$ARTIFACT_DIR/launch-region-summary.md"

require_non_empty "$ARTIFACT_DIR/launch-region-summary.md"
echo "Wrote $ARTIFACT_DIR/launch-region-summary.md"
