#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tools/mobile/run-android-16kb-page-size-smoke.sh --serial <adb-serial> --artifact-dir <dir> [options]

Options:
  --serial <adb-serial>       Required Android emulator serial.
  --artifact-dir <dir>        Required output directory for local-only evidence.
  --expected-page-size <n>    Defaults to 16384.
  --package <package>         App package. Defaults to com.easysubway.app.
  --adb <path>                adb executable. Defaults to $ADB or PATH lookup.
  --settle-seconds <seconds>  Wait after launch. Defaults to 2.
  -h, --help                  Show this help.
USAGE
}

SERIAL=""
ARTIFACT_DIR=""
EXPECTED_PAGE_SIZE=16384
PACKAGE="com.easysubway.app"
ADB="${ADB:-}"
SETTLE_SECONDS=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --serial) SERIAL="${2:-}"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="${2:-}"; shift 2 ;;
    --expected-page-size) EXPECTED_PAGE_SIZE="${2:-}"; shift 2 ;;
    --package) PACKAGE="${2:-}"; shift 2 ;;
    --adb) ADB="${2:-}"; shift 2 ;;
    --settle-seconds) SETTLE_SECONDS="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
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

qemu="$(adb_device shell getprop ro.kernel.qemu | tr -d '\r')"
page_size="$(adb_device shell getconf PAGE_SIZE | tr -d '\r')"
android_sdk="$(adb_device shell getprop ro.build.version.sdk | tr -d '\r')"
pm_path="$(adb_device shell pm path "$PACKAGE" 2>/dev/null | tr -d '\r' || true)"
launch_activity="$(adb_device shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN \
  -c android.intent.category.LAUNCHER \
  -p "$PACKAGE" 2>/dev/null | tr -d '\r' | tail -n 1 || true)"

{
  echo "android_16kb_page_size_runtime_smoke"
  echo "serial=$SERIAL"
  echo "package=$PACKAGE"
  echo "ro.kernel.qemu=$qemu"
  echo "android_sdk=$android_sdk"
  echo "page_size=$page_size"
  echo "expected_page_size=$EXPECTED_PAGE_SIZE"
  echo "package_installed=$([[ -n "$pm_path" ]] && echo true || echo false)"
  echo "launch_activity=$launch_activity"
} > "$ARTIFACT_DIR/summary.txt"

if [[ "$qemu" != "1" ]]; then
  echo "Expected local Android emulator, got ro.kernel.qemu=$qemu" >&2
  exit 1
fi
if [[ "$page_size" != "$EXPECTED_PAGE_SIZE" ]]; then
  echo "Expected PAGE_SIZE=$EXPECTED_PAGE_SIZE, got $page_size" >&2
  exit 1
fi
if [[ -z "$pm_path" ]]; then
  echo "Package is not installed: $PACKAGE" >&2
  exit 1
fi
if [[ "$launch_activity" != "$PACKAGE/"* ]]; then
  echo "Launch activity not found for package: $PACKAGE" >&2
  exit 1
fi

adb_device logcat -c
adb_device shell am start -n "$launch_activity" > "$ARTIFACT_DIR/am-start.txt"
sleep "$SETTLE_SECONDS"
adb_device shell dumpsys activity activities > "$ARTIFACT_DIR/current-focus.txt"
adb_device exec-out screencap -p > "$ARTIFACT_DIR/current-screen.png"
adb_device exec-out uiautomator dump /dev/tty > "$ARTIFACT_DIR/current-screen.xml"
adb_device logcat -d > "$ARTIFACT_DIR/logcat.txt"
if grep -E "FATAL EXCEPTION| [EF] AndroidRuntime:|Fatal signal|Abort message|tombstoned" "$ARTIFACT_DIR/logcat.txt" > "$ARTIFACT_DIR/crash-excerpt.txt"; then
  echo "Launch logcat contains crash markers. See crash-excerpt.txt." >&2
  exit 1
fi
foreground_package="$(grep -E "mResumedActivity|topResumedActivity" "$ARTIFACT_DIR/current-focus.txt" | head -n 1 | grep -oF "$PACKAGE" || true)"
if [[ "$foreground_package" != "$PACKAGE" ]]; then
  echo "App is not foreground after launch: $PACKAGE" >&2
  exit 1
fi
{
  echo "foreground_package_verified=true"
  echo "logcat_no_crash=true"
  echo "screenshot=current-screen.png"
  echo "ui_tree=current-screen.xml"
} >> "$ARTIFACT_DIR/summary.txt"
