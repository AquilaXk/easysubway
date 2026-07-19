#!/usr/bin/env bash
set -euo pipefail

base_url=""
departure_id=""
arrival_id=""
departure_date=""
output_dir=""
nodes=""
max_duration_seconds="120"
provider_call_count=""
quota_verdict=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		--base-url) base_url="${2:-}"; shift 2 ;;
		--departure-id) departure_id="${2:-}"; shift 2 ;;
		--arrival-id) arrival_id="${2:-}"; shift 2 ;;
		--date) departure_date="${2:-}"; shift 2 ;;
		--output-dir) output_dir="${2:-}"; shift 2 ;;
		--nodes) nodes="${2:-}"; shift 2 ;;
		--max-duration-seconds) max_duration_seconds="${2:-}"; shift 2 ;;
		--provider-call-count) provider_call_count="${2:-}"; shift 2 ;;
		--quota-verdict) quota_verdict="${2:-}"; shift 2 ;;
		*) echo "unknown argument" >&2; exit 2 ;;
	esac
done

[[ "${base_url}" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?/?$ ]] || { echo "--base-url must be a public HTTPS origin" >&2; exit 2; }
[[ "${departure_id}" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "--departure-id is invalid" >&2; exit 2; }
[[ "${arrival_id}" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "--arrival-id is invalid" >&2; exit 2; }
[[ "${departure_date}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--date is invalid" >&2; exit 2; }
[[ "${output_dir}" == /* ]] || { echo "--output-dir must be absolute" >&2; exit 2; }
[[ "${nodes}" == "3" ]] || { echo "--nodes 3 is required" >&2; exit 2; }
[[ "${max_duration_seconds}" =~ ^[0-9]+$ ]] && (( max_duration_seconds >= 20 && max_duration_seconds <= 600 )) \
	|| { echo "--max-duration-seconds must be 20 through 600" >&2; exit 2; }
[[ "${provider_call_count}" =~ ^[0-9]+$ ]] || { echo "--provider-call-count is invalid" >&2; exit 2; }
[[ "${quota_verdict}" == "PASS" ]] || { echo "--quota-verdict PASS is required" >&2; exit 2; }

mkdir -p "${output_dir}"
duration_seconds=$((max_duration_seconds / 2))
(( duration_seconds > 30 )) && duration_seconds=30

for workload in repeated unique; do
	TRAIN_SEARCH_WORKLOAD="${workload}" \
	TRAIN_SEARCH_BASE_URL="${base_url}" \
	TRAIN_SEARCH_DEPARTURE_ID="${departure_id}" \
	TRAIN_SEARCH_ARRIVAL_ID="${arrival_id}" \
	TRAIN_SEARCH_DATE="${departure_date}" \
	TRAIN_SEARCH_DURATION="${duration_seconds}s" \
	TRAIN_SEARCH_RATE=1 \
	TRAIN_SEARCH_PROVIDER_CALL_COUNT="${provider_call_count}" \
	TRAIN_SEARCH_QUOTA_VERDICT="${quota_verdict}" \
	TRAIN_SEARCH_SUMMARY_PATH="${output_dir}/${workload}.json" \
		k6 run tools/test/train-search-capacity.k6.js
done

node tools/test/validate-train-search-capacity.mjs \
	"${output_dir}/repeated.json" \
	"${output_dir}/unique.json"

echo "train-search capacity PASS: nodes=3 providerCallCount=${provider_call_count} quotaVerdict=${quota_verdict}"
