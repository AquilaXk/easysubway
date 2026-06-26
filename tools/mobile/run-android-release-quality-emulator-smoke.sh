#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tools/mobile/run-android-release-quality-emulator-smoke.sh --serial <adb-serial> --artifact-dir <dir> [options]

Options:
  --serial <adb-serial>       Required Android emulator serial.
  --artifact-dir <dir>        Required output directory for local-only evidence.
  --expected-font-scale <n>   Required current Android font scale, such as 1.5 or 2.0.
  --package <package>         App package. Defaults to com.easysubway.app.
  --adb <path>                adb executable. Defaults to $ADB or PATH lookup.
  --settle-seconds <seconds>  Wait after launch/settings changes. Defaults to 2.
  -h, --help                  Show this help.

This smoke is for Codex PR evidence and intentionally requires a local Android
emulator. It writes screenshots, UI trees, settings, package, gfxinfo, and
logcat summaries under the artifact directory. It does not use physical devices.
USAGE
}

SERIAL=""
ARTIFACT_DIR=""
EXPECTED_FONT_SCALE=""
PACKAGE="com.easysubway.app"
ADB="${ADB:-}"
SETTLE_SECONDS=2
MIN_ANDROID_API=35
MAX_COMPACT_WIDTH_DP=599

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
    --expected-font-scale)
      EXPECTED_FONT_SCALE="${2:-}"
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
    --settle-seconds)
      SETTLE_SECONDS="${2:-}"
      shift 2
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

if [[ -z "$SERIAL" || -z "$ARTIFACT_DIR" || -z "$EXPECTED_FONT_SCALE" ]]; then
  usage >&2
  exit 2
fi

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

current_focus() {
  adb_device shell dumpsys activity activities | grep -E "topResumedActivity|ResumedActivity" | tr -d '\r' || true
}

resolve_launch_activity() {
  adb_device shell cmd package resolve-activity --brief "$PACKAGE" | tr -d '\r' | tail -n 1
}

if ! adb_device get-state | grep -qx "device"; then
  echo "adb target is not ready: $SERIAL" >&2
  exit 1
fi

kernel_qemu="$(adb_device shell getprop ro.kernel.qemu | tr -d '\r')"
if [[ "$kernel_qemu" != "1" ]]; then
  echo "adb target is not a local Android emulator: $SERIAL" >&2
  exit 1
fi

wm_size="$(adb_device shell wm size | tr -d '\r')"
wm_density="$(adb_device shell wm density | tr -d '\r')"
font_scale="$(adb_device shell settings get system font_scale | tr -d '\r')"
high_text_contrast="$(adb_device shell settings get secure high_text_contrast_enabled | tr -d '\r' || true)"
page_size="$(adb_device shell getconf PAGE_SIZE | tr -d '\r' || true)"
sdk="$(adb_device shell getprop ro.build.version.sdk | tr -d '\r')"

if [[ ! "$sdk" =~ ^[0-9]+$ || "$sdk" -lt "$MIN_ANDROID_API" ]]; then
  echo "Android SDK $sdk does not satisfy minimum API $MIN_ANDROID_API." >&2
  exit 1
fi

if [[ ! "$wm_size" =~ ([0-9]+)x([0-9]+) ]]; then
  echo "Unable to parse device size from: $wm_size" >&2
  exit 1
fi
width_px="${BASH_REMATCH[1]}"
height_px="${BASH_REMATCH[2]}"

if [[ ! "$wm_density" =~ ([0-9]+)$ ]]; then
  echo "Unable to parse device density from: $wm_density" >&2
  exit 1
fi
density_dpi="${BASH_REMATCH[1]}"
width_dp=$((width_px * 160 / density_dpi))
height_dp=$((height_px * 160 / density_dpi))
if [[ "$width_px" -ge "$height_px" ]]; then
  echo "Emulator viewport must be compact phone portrait: ${width_px}x${height_px}px." >&2
  exit 1
fi
if [[ "$width_dp" -gt "$MAX_COMPACT_WIDTH_DP" ]]; then
  echo "Emulator width ${width_dp}dp is not compact phone width." >&2
  exit 1
fi

if [[ "$font_scale" != "$EXPECTED_FONT_SCALE" ]]; then
  echo "Android font_scale $font_scale does not match expected $EXPECTED_FONT_SCALE." >&2
  exit 1
fi

{
  echo "serial=$SERIAL"
  echo "package=$PACKAGE"
  echo "ro.kernel.qemu=$kernel_qemu"
  echo "android_sdk=$sdk"
  echo "wm_size=$wm_size"
  echo "wm_density=$wm_density"
  echo "width_dp=$width_dp"
  echo "height_dp=$height_dp"
  echo "viewport_orientation=portrait"
  echo "font_scale=${font_scale:-unknown}"
  echo "expected_font_scale=$EXPECTED_FONT_SCALE"
  echo "high_text_contrast_enabled=${high_text_contrast:-unknown}"
  echo "page_size=${page_size:-unknown}"
  echo "adb=$ADB"
  date -u +"captured_at_utc=%Y-%m-%dT%H:%M:%SZ"
} > "$ARTIFACT_DIR/metadata.env"

adb_device shell pm path "$PACKAGE" > "$ARTIFACT_DIR/package-path.txt"
require_non_empty "$ARTIFACT_DIR/package-path.txt"
adb_device shell dumpsys package "$PACKAGE" > "$ARTIFACT_DIR/package.txt"
require_non_empty "$ARTIFACT_DIR/package.txt"

adb_device logcat -c
adb_device shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
launch_activity="$(resolve_launch_activity)"
if [[ "$launch_activity" != "$PACKAGE/"* ]]; then
  echo "Unable to resolve launch activity for $PACKAGE: $launch_activity" >&2
  exit 1
fi
adb_device shell am start -n "$launch_activity" > "$ARTIFACT_DIR/launch.txt"
require_non_empty "$ARTIFACT_DIR/launch.txt"
sleep "$SETTLE_SECONDS"

current_focus > "$ARTIFACT_DIR/current-focus.txt"
require_non_empty "$ARTIFACT_DIR/current-focus.txt"
if ! grep -q "$PACKAGE" "$ARTIFACT_DIR/current-focus.txt"; then
  echo "App package $PACKAGE is not foreground after launch." >&2
  exit 1
fi

capture_screen "current-screen"
capture_ui_tree "current-screen"

adb_device shell dumpsys gfxinfo "$PACKAGE" > "$ARTIFACT_DIR/gfxinfo.txt"
adb_device shell dumpsys meminfo "$PACKAGE" > "$ARTIFACT_DIR/meminfo.txt"
adb_device logcat -d -v time > "$ARTIFACT_DIR/logcat.txt"

{
  echo "android_release_quality_emulator_smoke"
  cat "$ARTIFACT_DIR/metadata.env"
  echo "screenshot=current-screen.png"
  echo "ui_tree=current-screen.xml"
  echo "foreground_package_verified=true"
} > "$ARTIFACT_DIR/summary.txt"

require_non_empty "$ARTIFACT_DIR/summary.txt"
printf 'android release quality emulator smoke evidence written: %s\n' "$ARTIFACT_DIR"
