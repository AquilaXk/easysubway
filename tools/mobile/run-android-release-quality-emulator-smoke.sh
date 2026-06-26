#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tools/mobile/run-android-release-quality-emulator-smoke.sh --serial <adb-serial> --artifact-dir <dir> [options]

Options:
  --serial <adb-serial>       Required Android emulator serial.
  --artifact-dir <dir>        Required output directory for local-only evidence.
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
PACKAGE="com.easysubway.app"
ADB="${ADB:-}"
SETTLE_SECONDS=2

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

if [[ -z "$SERIAL" || -z "$ARTIFACT_DIR" ]]; then
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

{
  echo "serial=$SERIAL"
  echo "package=$PACKAGE"
  echo "ro.kernel.qemu=$kernel_qemu"
  echo "android_sdk=$sdk"
  echo "wm_size=$wm_size"
  echo "wm_density=$wm_density"
  echo "font_scale=${font_scale:-unknown}"
  echo "high_text_contrast_enabled=${high_text_contrast:-unknown}"
  echo "page_size=${page_size:-unknown}"
  echo "adb=$ADB"
  date -u +"captured_at_utc=%Y-%m-%dT%H:%M:%SZ"
} > "$ARTIFACT_DIR/metadata.env"

adb_device shell dumpsys package "$PACKAGE" > "$ARTIFACT_DIR/package.txt" || true
adb_device logcat -c || true
adb_device shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
adb_device shell monkey -p "$PACKAGE" 1 > "$ARTIFACT_DIR/launch.txt" 2>&1 || true
sleep "$SETTLE_SECONDS"

capture_screen "current-screen"
capture_ui_tree "current-screen"

adb_device shell dumpsys gfxinfo "$PACKAGE" > "$ARTIFACT_DIR/gfxinfo.txt" || true
adb_device shell dumpsys meminfo "$PACKAGE" > "$ARTIFACT_DIR/meminfo.txt" || true
adb_device logcat -d -v time > "$ARTIFACT_DIR/logcat.txt" || true

{
  echo "android_release_quality_emulator_smoke"
  cat "$ARTIFACT_DIR/metadata.env"
  echo "screenshot=current-screen.png"
  echo "ui_tree=current-screen.xml"
  if grep -q "Unable to find instrumentation info" "$ARTIFACT_DIR/launch.txt"; then
    echo "launch_status=package_not_started"
  else
    echo "launch_status=attempted"
  fi
} > "$ARTIFACT_DIR/summary.txt"

require_non_empty "$ARTIFACT_DIR/summary.txt"
printf 'android release quality emulator smoke evidence written: %s\n' "$ARTIFACT_DIR"
