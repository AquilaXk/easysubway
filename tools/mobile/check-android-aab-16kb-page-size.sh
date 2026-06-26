#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tools/mobile/check-android-aab-16kb-page-size.sh --aab <app.aab> --artifact-dir <dir> [options]

Options:
  --aab <path>           Required Android App Bundle.
  --artifact-dir <dir>  Required output directory for local-only evidence.
  --bundletool <path>   bundletool executable. Defaults to PATH lookup.
  -h, --help            Show this help.
USAGE
}

AAB=""
ARTIFACT_DIR=""
BUNDLETOOL=""
MIN_ALIGN=16384
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --aab) AAB="${2:-}"; shift 2 ;;
    --artifact-dir) ARTIFACT_DIR="${2:-}"; shift 2 ;;
    --bundletool) BUNDLETOOL="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$AAB" || -z "$ARTIFACT_DIR" ]]; then
  usage >&2
  exit 2
fi
if [[ ! -s "$AAB" ]]; then
  echo "AAB not found or empty: $AAB" >&2
  exit 2
fi

BUNDLETOOL="${BUNDLETOOL:-$(command -v bundletool || true)}"
if [[ -z "$BUNDLETOOL" || ! -x "$BUNDLETOOL" ]]; then
  echo "bundletool executable not found. Pass --bundletool." >&2
  exit 2
fi

mkdir -p "$ARTIFACT_DIR"
"$BUNDLETOOL" dump config --bundle="$AAB" > "$ARTIFACT_DIR/bundle-config.txt"
if ! grep -q '"alignment": "PAGE_ALIGNMENT_16K"' "$ARTIFACT_DIR/bundle-config.txt"; then
  {
    echo "android_16kb_aab_page_size_check"
    echo "aab=$AAB"
    echo "minimum_load_segment_alignment=$MIN_ALIGN"
    echo "bundle_config=bundle-config.txt"
    echo "result=fail"
    echo "reason=missing_PAGE_ALIGNMENT_16K_native_library_alignment"
  } > "$ARTIFACT_DIR/summary.txt"
  exit 1
fi
zipinfo -1 "$AAB" | grep -E '(^|/)lib/[^/]+/[^/]+\.so$' > "$ARTIFACT_DIR/native-libraries.txt" || true

if [[ ! -s "$ARTIFACT_DIR/native-libraries.txt" ]]; then
  echo "No native libraries found in AAB." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

status=0
summary="$ARTIFACT_DIR/native-alignment-summary.tsv"
printf 'library\tload_alignments\tstatus\n' > "$summary"
while IFS= read -r library; do
  out="$tmp_dir/$(basename "$library")"
  unzip -p "$AAB" "$library" > "$out"
  align_out="$ARTIFACT_DIR/$(echo "$library" | tr '/:' '__').load-alignments.txt"
  lib_status="pass"
  if ! node "$SCRIPT_DIR/check-elf-load-alignment.mjs" --min-align "$MIN_ALIGN" "$out" > "$align_out"; then
    lib_status="fail"
    status=1
  fi
  aligns="$(cat "$align_out")"
  printf '%s\t%s\t%s\n' "$library" "$aligns" "$lib_status" >> "$summary"
done < "$ARTIFACT_DIR/native-libraries.txt"

{
  echo "android_16kb_aab_page_size_check"
  echo "aab=$AAB"
  echo "minimum_load_segment_alignment=$MIN_ALIGN"
  echo "bundle_config=bundle-config.txt"
  echo "native_libraries=native-libraries.txt"
  echo "native_alignment_summary=native-alignment-summary.tsv"
  echo "result=$([[ "$status" -eq 0 ]] && echo pass || echo fail)"
} > "$ARTIFACT_DIR/summary.txt"

exit "$status"
