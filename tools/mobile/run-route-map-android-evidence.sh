#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tools/mobile/run-route-map-android-evidence.sh --serial <adb-serial> --artifact-dir <dir> [options]

Options:
  --serial <adb-serial>     Required Android device serial. Use a real device for PR evidence.
  --artifact-dir <dir>      Required output directory for screenshots, UI trees, logs, and summaries.
  --package <package>       App package. Defaults to com.easysubway.app.
  --adb <path>              adb executable. Defaults to $ADB or PATH lookup.
  --build-mode <mode>       Installed APK mode: debug or profile. Defaults to debug.
  --pan-count <count>       Number of map pan gestures after route map entry. Defaults to 5.
  --settle-seconds <sec>    Wait after app launch and tab changes. Defaults to 3.
  --measure-after-route-map-settle
                            Reset frame/log evidence after route map settles, so gfxinfo and
                            renderer latency focus on gestures instead of initial map entry.
  -h, --help                Show this help.

The script installs nothing. Install a debug or profile APK first (framestats
are most useful there) and complete onboarding so the app opens directly to the
route map home. The route map uses the structured native canvas renderer
(#1641); there is no WebView dispose signal, so the gate is renderer crash
signatures during pan/zoom instead. It fails when the device is unavailable,
the route map cannot be driven, evidence files are empty, or a renderer crash
signature is observed during the gesture window.
USAGE
}

SERIAL=""
ARTIFACT_DIR=""
PACKAGE="com.easysubway.app"
ADB="${ADB:-}"
BUILD_MODE="debug"
PAN_COUNT=5
SETTLE_SECONDS=3
MEASURE_AFTER_ROUTE_MAP_SETTLE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial)
      SERIAL="${2:-}"
      shift 2
      ;;
    --artifact-dir)
      ARTIFACT_DIR="${2:-}"
      shift 2
      ;;
    --package)
      PACKAGE="${2:-}"
      shift 2
      ;;
    --adb)
      ADB="${2:-}"
      shift 2
      ;;
    --build-mode)
      BUILD_MODE="${2:-}"
      shift 2
      ;;
    --pan-count)
      PAN_COUNT="${2:-}"
      shift 2
      ;;
    --settle-seconds)
      SETTLE_SECONDS="${2:-}"
      shift 2
      ;;
    --measure-after-route-map-settle)
      MEASURE_AFTER_ROUTE_MAP_SETTLE="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SERIAL" || -z "$ARTIFACT_DIR" ]]; then
  usage >&2
  exit 2
fi

if [[ "$MEASURE_AFTER_ROUTE_MAP_SETTLE" == "true" ]]; then
  MEASUREMENT_SCOPE="gesture_after_route_map_settle"
else
  MEASUREMENT_SCOPE="route_map_entry_and_pan"
fi

case "$BUILD_MODE" in
  debug|profile)
    ;;
  *)
    echo "Unsupported build mode: $BUILD_MODE. Use debug or profile." >&2
    exit 2
    ;;
esac

if [[ -z "$ADB" ]]; then
  ADB="$(command -v adb || true)"
fi

if [[ -z "$ADB" || ! -x "$ADB" ]]; then
  echo "adb executable not found. Pass --adb or set ADB." >&2
  exit 2
fi

mkdir -p "$ARTIFACT_DIR"

adb_device() {
  "$ADB" -s "$SERIAL" "$@"
}

require_non_empty() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo "Expected non-empty evidence file: $file" >&2
    exit 1
  fi
}

capture_screen() {
  local name="$1"
  adb_device exec-out screencap -p > "$ARTIFACT_DIR/$name.png"
  require_non_empty "$ARTIFACT_DIR/$name.png"
}

capture_ui_tree() {
  local name="$1"
  local device_path="/sdcard/easysubway-${name}.xml"
  adb_device shell uiautomator dump "$device_path" >/dev/null
  adb_device pull "$device_path" "$ARTIFACT_DIR/$name.xml" >/dev/null
  require_non_empty "$ARTIFACT_DIR/$name.xml"
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
# 노선도는 홈 화면이다(#1641 구조화 canvas 전환 이후 하단 탭 없음). 앱은 온보딩을
# 마친 상태여야 하며, 실행 즉시 노선도가 표시된다.
PAN_Y=$((HEIGHT / 2))
PAN_LEFT_X=$((WIDTH * 3 / 10))
PAN_RIGHT_X=$((WIDTH * 7 / 10))

{
  echo "serial=$SERIAL"
  echo "package=$PACKAGE"
  echo "width=$WIDTH"
  echo "height=$HEIGHT"
  echo "build_mode=$BUILD_MODE"
  echo "pan_count=$PAN_COUNT"
  echo "settle_seconds=$SETTLE_SECONDS"
  echo "measurement_scope=$MEASUREMENT_SCOPE"
  echo "gfxinfo_reset_after_route_map_settle=$MEASURE_AFTER_ROUTE_MAP_SETTLE"
  echo "adb=$ADB"
  date -u +"captured_at_utc=%Y-%m-%dT%H:%M:%SZ"
} > "$ARTIFACT_DIR/metadata.env"

adb_device shell dumpsys package "$PACKAGE" > "$ARTIFACT_DIR/package.txt"
require_non_empty "$ARTIFACT_DIR/package.txt"

adb_device logcat -c
adb_device shell am force-stop "$PACKAGE"
adb_device shell dumpsys gfxinfo "$PACKAGE" reset >/dev/null 2>&1 || true
adb_device shell monkey -p "$PACKAGE" 1 > "$ARTIFACT_DIR/launch.txt"
sleep "$SETTLE_SECONDS"

# 노선도는 홈 화면이라 실행 즉시 표시된다(별도 진입 탭 없음).
capture_screen "route-map"
capture_ui_tree "route-map"

if [[ "$MEASURE_AFTER_ROUTE_MAP_SETTLE" == "true" ]]; then
  # 제스처 구간만 분리 측정: 노선도 안착 후 프레임/로그 증거를 리셋한다.
  adb_device shell dumpsys gfxinfo "$PACKAGE" reset >/dev/null
  adb_device logcat -c
fi

for ((i = 0; i < PAN_COUNT; i += 1)); do
  adb_device shell input swipe "$PAN_RIGHT_X" "$PAN_Y" "$PAN_LEFT_X" "$PAN_Y" 350
  adb_device shell input swipe "$PAN_LEFT_X" "$PAN_Y" "$PAN_RIGHT_X" "$PAN_Y" 350
done

adb_device shell dumpsys gfxinfo "$PACKAGE" > "$ARTIFACT_DIR/gfxinfo.txt"
adb_device shell dumpsys gfxinfo "$PACKAGE" framestats > "$ARTIFACT_DIR/gfxinfo-framestats.txt"
adb_device shell dumpsys meminfo "$PACKAGE" > "$ARTIFACT_DIR/meminfo.txt"

require_non_empty "$ARTIFACT_DIR/gfxinfo.txt"
require_non_empty "$ARTIFACT_DIR/gfxinfo-framestats.txt"
require_non_empty "$ARTIFACT_DIR/meminfo.txt"

capture_screen "after-pan"
capture_ui_tree "after-pan"
adb_device logcat -d -v time > "$ARTIFACT_DIR/logcat.txt"
require_non_empty "$ARTIFACT_DIR/logcat.txt"

# 구조화 canvas 렌더러는 pure Flutter CustomPaint라 WebView dispose 신호가 없다
# (#1641에서 WebView 렌더러·health monitor 제거). 대신 pan/zoom 구간에서 렌더러
# 크래시(FATAL EXCEPTION / Flutter 엔진 abort)가 없었는지를 차단 조건으로 둔다.
grep -E "FATAL EXCEPTION|E AndroidRuntime|Lost connection to device|## Flutter engine|libflutter.*abort" \
  "$ARTIFACT_DIR/logcat.txt" > "$ARTIFACT_DIR/renderer-crashes.log" || true
if [[ -s "$ARTIFACT_DIR/renderer-crashes.log" ]]; then
  echo "Route map renderer crash signatures observed during pan/zoom:" >&2
  cat "$ARTIFACT_DIR/renderer-crashes.log" >&2
  exit 1
fi

# #1643: FrameTiming 계측 로그(routeMapFrame buildMs/rasterMs/totalMs). 구조화
# canvas는 dumpsys gfxinfo로 프레임이 안 잡혀 이 로그가 프레임 성능의 정본이다.
grep "routeMapFrame" "$ARTIFACT_DIR/logcat.txt" > "$ARTIFACT_DIR/route-map-frames.log" || true
if [[ ! -s "$ARTIFACT_DIR/route-map-frames.log" ]]; then
  echo "No routeMapFrame timing logs captured. Use a debug/profile build and" >&2
  echo "ensure the route map was on screen during the gesture window." >&2
  exit 1
fi

{
  echo "# EasySubway Android route map evidence"
  echo
  echo "- serial: $SERIAL"
  echo "- package: $PACKAGE"
  echo "- viewport: ${WIDTH}x${HEIGHT}"
  echo "- build_mode: $BUILD_MODE"
  echo "- pan_count: $PAN_COUNT"
  echo "- measurement_scope: $MEASUREMENT_SCOPE"
  echo
  echo "## Renderer stability"
  echo "- renderer: structured-canvas (#1641)"
  echo "- crash_signatures_during_pan: $(wc -l < "$ARTIFACT_DIR/renderer-crashes.log" | tr -d ' ')"
  echo
  echo "## Frame timing (FrameTiming, primary)"
  echo "- routeMapFrame_samples: $(wc -l < "$ARTIFACT_DIR/route-map-frames.log" | tr -d ' ')"
  echo "- analyze with: node tools/mobile/analyze-route-map-android-evidence.mjs --artifact-dir <dir>"
  echo
  echo "## gfxinfo headline (HWUI only — NOT Flutter canvas frames)"
  echo "- note: Flutter는 자체 렌더 파이프라인이라 dumpsys gfxinfo가 노선도 프레임을"
  echo "  잡지 못한다. 프레임 성능은 위 FrameTiming(route-map-frames.log)이 정본이다."
  grep -E "Total frames rendered|Janky frames|50th percentile|90th percentile|95th percentile|99th percentile" "$ARTIFACT_DIR/gfxinfo.txt" || true
  echo
  echo "## meminfo headline"
  grep -E "TOTAL PSS|TOTAL RSS|Java Heap|Native Heap|Graphics" "$ARTIFACT_DIR/meminfo.txt" || true
} > "$ARTIFACT_DIR/summary.md"

require_non_empty "$ARTIFACT_DIR/summary.md"
echo "Evidence written to $ARTIFACT_DIR"
