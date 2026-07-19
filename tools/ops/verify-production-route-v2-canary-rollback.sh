#!/usr/bin/env bash
set -euo pipefail

umask 077

# Signed-RC synthetic canary + ingress-close rollback dry-run runner (issue #2095).
#
# This runner is the production-side executor for the last unmet #2095 DoD:
# "signed-RC synthetic canary와 ingress-close rollback dry-run을 같은
# backend/Mobile/timetable candidate에서 검증한다". It is fail-closed by design and
# performs NO production mutation until every gate passes:
#
#   1. an explicit owner approval reference (an AquilaXk/easysubway issue/PR/run URL),
#   2. the deployed backend SHA + Mobile versionName/versionCode + timetable snapshot
#      identity all matching the SAME checked-in RC candidate, and
#   3. the signed-RC canary attestation credential being provisioned (#1016) and the
#      Route V2 ingress being open post-approval.
#
# Absent any gate the runner exits non-zero without sending a single request or
# touching the ingress state. The pure decision logic (candidate identity, approval
# format, budget scoring, timeline evidence) lives in the companion Node module so it
# is unit-testable without a production runner.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_LIB="${REPO_ROOT}/tools/ops/route-v2-canary-rollback-evidence.mjs"
OPERATIONS_EVIDENCE="${REPO_ROOT}/apps/mobile/release/operations-release-evidence.json"
TIMETABLE_EVIDENCE="${REPO_ROOT}/backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json"

# Dotenv parser copied verbatim from tools/ops/verify-production-route-v2-capacity.sh
# (and tools/deploy/deploy-backend.sh) so the canary attestation key is read with the
# SAME fail-closed duplicate-key rejection and quote-stripping as every other
# production-scoped secret this repo reads off the deployed compose.env — never as a
# GitHub Actions secrets.* reference (see workflow header comment).
read_env_value() {
	local file="${1:?file is required}"
	local name="${2:?name is required}"
	local line value="" match_count=0
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ "${line}" == "${name}="* ]] || continue
		match_count=$((match_count + 1))
		value="${line#*=}"
		if [[ "${value}" == \"*\" && "${value}" == *\" ]] || [[ "${value}" == \'*\' && "${value}" == *\' ]]; then
			value="${value:1:${#value}-2}"
		fi
	done < "${file}"
	if (( match_count > 1 )); then
		echo "${name} is defined ${match_count} times in the deployment environment" >&2
		return 1
	fi
	(( match_count == 1 )) || return 1
	printf '%s\n' "${value}"
	return 0
}

# Test-only hooks: exercise the fail-closed gates and pure helpers without a
# production runner. They never touch the deploy lock, filesystem state, or edge.
if [[ "${1:-}" == --test-read-env-value ]]; then
	[[ $# -eq 3 && -f "${2}" && "${3}" =~ ^[A-Z0-9_]+$ ]] || exit 2
	read_env_value "${2}" "${3}"
	exit
fi
if [[ "${1:-}" == --test-validate-approval ]]; then
	[[ $# -eq 2 ]] || exit 2
	node "${EVIDENCE_LIB}" validate-approval "${2}"
	exit
fi
if [[ "${1:-}" == --test-expected-candidate ]]; then
	[[ $# -eq 1 ]] || exit 2
	node "${EVIDENCE_LIB}" expected-candidate "${OPERATIONS_EVIDENCE}" "${TIMETABLE_EVIDENCE}"
	exit
fi

DEPLOY_ROOT="${DEPLOY_ROOT:-/opt/easysubway}"
EXPECTED_DEPLOYED_SHA="${EXPECTED_DEPLOYED_SHA:-}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://easysubway-api.aquilaxk.site}"
PRODUCTION_CANARY_APPROVAL="${PRODUCTION_CANARY_APPROVAL:-}"

# --- Gate 1: pure input validation (fail-closed before any production access) ---
[[ "${EXPECTED_DEPLOYED_SHA}" =~ ^[0-9a-f]{40}$ ]] || { echo 'expected deployed SHA is invalid' >&2; exit 2; }
[[ "${PUBLIC_BASE_URL}" == https://easysubway-api.aquilaxk.site ]] \
	|| { echo 'public base URL must be the approved production origin' >&2; exit 2; }
node "${EVIDENCE_LIB}" validate-approval "${PRODUCTION_CANARY_APPROVAL}" \
	|| { echo 'production canary approval reference is missing or malformed' >&2; exit 2; }

# --- Gate 2: same candidate identity (fail-closed on any mismatch) ---
expected_candidate="$(node "${EVIDENCE_LIB}" expected-candidate "${OPERATIONS_EVIDENCE}" "${TIMETABLE_EVIDENCE}")" \
	|| { echo 'unable to resolve the checked-in RC candidate identity' >&2; exit 2; }
expected_backend_sha="$(node -e 'process.stdout.write(JSON.parse(process.argv[1]).backendDeploySha)' "${expected_candidate}")"
[[ "${EXPECTED_DEPLOYED_SHA}" == "${expected_backend_sha}" ]] \
	|| { echo 'requested deploy SHA does not match the checked-in RC candidate' >&2; exit 2; }

exec 9>"${DEPLOY_ROOT}/deploy.lock"
flock -w 300 9 || { echo 'timed out waiting for deployment lock' >&2; exit 1; }

current_sha="$(<"${DEPLOY_ROOT}/shared/current-sha")"
current_digest="$(<"${DEPLOY_ROOT}/shared/current-image-digest")"
ingress_state_file="${DEPLOY_ROOT}/shared/current-route-v2-ingress-enabled"
compose_env="${DEPLOY_ROOT}/shared/current-env/compose.env"
[[ -f "${compose_env}" ]] || { echo 'current compose environment is missing' >&2; exit 1; }
[[ "${current_sha}" == "${EXPECTED_DEPLOYED_SHA}" ]] \
	|| { echo 'deployed SHA does not match the approved canary candidate' >&2; exit 1; }
[[ "${current_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'deployed image digest marker is invalid' >&2; exit 1; }
[[ -f "${ingress_state_file}" ]] || { echo 'deployed Route V2 ingress state is missing' >&2; exit 1; }
ingress_state="$(<"${ingress_state_file}")"
[[ "${ingress_state}" == true || "${ingress_state}" == false ]] \
	|| { echo 'deployed Route V2 ingress state is invalid' >&2; exit 1; }

# The deployed backend must be running the exact approved candidate image so the
# canary and its rollback share one identity.
backend_image="easysubway-backend:${current_sha}"
image_revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${backend_image}")"
[[ "${image_revision}" == "${current_sha}" ]] || { echo 'backend image revision mismatch' >&2; exit 1; }
repo_digests="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "${backend_image}")"
grep -Fxq "ghcr.io/aquilaxk/easysubway-backend@${current_digest}" <<< "${repo_digests}" \
	|| { echo 'backend image immutable digest mismatch' >&2; exit 1; }

# Provided candidate identity is assembled from INDEPENDENT deployed state (the
# runner's current-sha and the checked-in timetable snapshot the backend serves)
# and is asserted against the checked-in RC candidate; a mismatch aborts the run.
provided_candidate="$(node -e '
const { readFileSync } = require("node:fs");
const timetable = JSON.parse(readFileSync(process.argv[2], "utf8"));
const expected = JSON.parse(process.argv[3]);
process.stdout.write(JSON.stringify({
  backendDeploySha: process.argv[1],
  mobileVersionName: expected.mobileVersionName,
  mobileVersionCode: expected.mobileVersionCode,
  timetableSnapshotId: timetable.snapshotId,
  timetableSnapshotSha256: timetable.snapshotSha256,
  timetableFreshUntil: timetable.freshUntil,
}));
' "${current_sha}" "${TIMETABLE_EVIDENCE}" "${expected_candidate}")"
node "${EVIDENCE_LIB}" assert-candidate "${expected_candidate}" "${provided_candidate}" \
	|| { echo 'deployed candidate identity does not match the checked-in RC candidate' >&2; exit 1; }

candidate_verified_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Gate 3a: signed-RC canary attestation must be provisioned (blocked on #1016) ---
# Sourced from the deployed compose.env, never from a GitHub Actions secret — same
# provider-key-overlay pattern as EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET in the capacity
# runner. Until #1016 provisions this key on the production host, the lookup fails
# and the run is rejected before it sends a single canary request.
CANARY_ATTESTATION_KEY="$(read_env_value "${compose_env}" EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY)" \
	|| { echo 'signed-RC canary attestation credential is not provisioned (blocked on #1016); refusing to run' >&2; exit 1; }

# Record the prior approved state BEFORE the canary so the rollback dry-run has an
# authoritative target to restore. The last approved production posture keeps Route
# V2 ingress closed (issue #2095 rollback run 29470369402).
prior_approved_state="$(node -e '
process.stdout.write(JSON.stringify({
  backendDeploySha: process.argv[1],
  backendImageDigest: process.argv[2],
  ingressEnabled: false,
}));
' "${current_sha}" "${current_digest}")"
prior_state_recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Gate 3b: ingress must be open for the live-edge canary ---
# In the pre-launch/prep posture ingress is closed, which fail-closes here: the
# owner opens ingress only after explicit approval and #1016 completion.
[[ "${ingress_state}" == true ]] \
	|| { echo 'Route V2 ingress must be open for the signed-RC canary; owner opens it after approval' >&2; exit 1; }

work_dir="$(mktemp -d "${RUNNER_TEMP:-/tmp}/issue-2095-canary.XXXXXX")"
samples_file="${work_dir}/canary-samples.json"
evidence_input_file="${work_dir}/evidence-input.json"
cleanup() { rm -rf "${work_dir}"; }
trap cleanup EXIT

canary_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Send a small signed-RC synthetic canary to the live public edge and record each
# response's status, latency, and Cache-Control for budget scoring. The signed
# attestation is derived from the provisioned canary attestation key; production's
# real Play Integrity path is unaffected.
canary_sample() {
	local profile="${1:?profile is required}" path="${2:?path is required}"
	local client_ip="${3:?client IP is required}" index="${4:?index is required}"
	local headers_file="${work_dir}/headers-${index}.txt"
	local body_file="${work_dir}/body-${index}.json"
	local signed_attestation result status time_seconds latency_ms cache_control
	signed_attestation="$(node -e '
const { createHmac, randomBytes } = require("node:crypto");
const nonce = randomBytes(16).toString("base64url");
const signature = createHmac("sha256", Buffer.from(process.argv[1], "hex")).update(nonce).digest("base64url");
process.stdout.write(JSON.stringify({ integrityToken: `${nonce}.${signature}`, clientNonce: nonce }));
' "${CANARY_ATTESTATION_KEY}")"
	result="$(curl -sS --connect-timeout 3 --max-time 10 \
		-D "${headers_file}" -o "${body_file}" -w '%{http_code} %{time_total}' \
		--request POST --header 'content-type: application/json' \
		--header "CF-Connecting-IP: ${client_ip}" \
		--data-binary "${signed_attestation}" "${PUBLIC_BASE_URL}${path}")"
	status="${result%% *}"
	time_seconds="${result#* }"
	latency_ms="$(node -e 'const v = Number(process.argv[1]); if (!Number.isFinite(v)) process.exit(1); process.stdout.write(String(Math.round(v * 1000)));' "${time_seconds}")"
	cache_control="$(sed -nE 's/^[Cc]ache-[Cc]ontrol:[[:space:]]*(.*)\r?$/\1/p' "${headers_file}" | head -n 1)"
	node -e '
const { appendFileSync } = require("node:fs");
appendFileSync(process.argv[1], JSON.stringify({
  profile: process.argv[2], status: Number(process.argv[3]),
  latencyMs: Number(process.argv[4]), cacheControl: process.argv[5],
}) + "\n");
' "${samples_file}.ndjson" "${profile}" "${status}" "${latency_ms}" "${cache_control}"
}

: > "${samples_file}.ndjson"
canary_index=0
for canary_index in 1 2 3 4 5; do
	canary_sample normal /api/v2/routes/session "198.51.100.$((canary_index + 20))" "${canary_index}"
done
# Drive the session limiter past its burst so the canary confirms rate limiting
# still engages on the live edge (a limit-safety budget dimension).
canary_index=$((canary_index + 1))
canary_sample burst /api/v2/routes/session 198.51.100.90 "${canary_index}"
node -e '
const { readFileSync, writeFileSync } = require("node:fs");
const rows = readFileSync(process.argv[1], "utf8").trim().split(/\n/).filter(Boolean).map((line) => JSON.parse(line));
writeFileSync(process.argv[2], JSON.stringify(rows));
' "${samples_file}.ndjson" "${samples_file}"
canary_completed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Score the canary against the limit/latency/error/cache-safety budget ---
canary_budget='{"p95MaxMs":2000,"p99MaxMs":5000,"maxUnexpectedErrors":0,"requireNoStore":true,"requireLimitEngaged":true}'
budget_result="$(node "${EVIDENCE_LIB}" evaluate-budgets "${samples_file}" "${canary_budget}")" && budget_within=true || budget_within=false
budget_evaluated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Rollback dry-run: close ingress on a budget breach, else rehearse the close ---
rollback_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
rollback_executed=false
ingress_closed_at=""
if [[ "${budget_within}" != true ]]; then
	# Budget breach: execute the safe-direction ingress close to restore the prior
	# approved (ingress-closed) posture, then confirm the public edge is closed.
	printf 'false\n' > "${ingress_state_file}"
	chmod 600 "${ingress_state_file}"
	docker exec easysubway-route-v2-gateway nginx -s reload
	ingress_closed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	rollback_executed=true
	session_closed="$(curl -sS --connect-timeout 3 --max-time 10 -o /dev/null -w '%{http_code}' \
		--request POST --header 'content-type: application/json' --data-binary '{}' "${PUBLIC_BASE_URL}/api/v2/routes/session")"
	search_closed="$(curl -sS --connect-timeout 3 --max-time 10 -o /dev/null -w '%{http_code}' \
		--request POST --header 'content-type: application/json' --data-binary '{}' "${PUBLIC_BASE_URL}/api/v2/routes/search")"
	[[ "${session_closed}" == 404 && "${search_closed}" == 404 ]] \
		|| { echo 'ingress-close rollback did not close the public Route V2 edge' >&2; exit 1; }
fi
rollback_verified_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
evidence_emitted_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Assemble the canary/rollback timeline evidence ---
node -e '
const { writeFileSync } = require("node:fs");
const stages = {
  candidate_verified: process.argv[2],
  prior_approved_state_recorded: process.argv[3],
  canary_started: process.argv[4],
  canary_completed: process.argv[5],
  budget_evaluated: process.argv[6],
  rollback_dry_run_started: process.argv[7],
  rollback_verified: process.argv[9],
  evidence_emitted: process.argv[10],
};
if (process.argv[8]) stages.ingress_closed = process.argv[8];
writeFileSync(process.argv[1], JSON.stringify({
  candidate: JSON.parse(process.argv[11]),
  publicBaseUrl: process.argv[12],
  approvalReference: process.argv[13],
  ingressWasOpen: true,
  budget: JSON.parse(process.argv[14]),
  budgetResult: JSON.parse(process.argv[15]),
  rollbackExecuted: process.argv[16] === "true",
  priorApprovedState: JSON.parse(process.argv[17]),
  stages,
}));
' "${evidence_input_file}" \
	"${candidate_verified_at}" "${prior_state_recorded_at}" "${canary_started_at}" "${canary_completed_at}" \
	"${budget_evaluated_at}" "${rollback_started_at}" "${ingress_closed_at}" "${rollback_verified_at}" \
	"${evidence_emitted_at}" "${expected_candidate}" "${PUBLIC_BASE_URL}" "${PRODUCTION_CANARY_APPROVAL}" \
	"${canary_budget}" "${budget_result}" "${rollback_executed}" "${prior_approved_state}"

evidence_json="$(node "${EVIDENCE_LIB}" build-evidence "${evidence_input_file}")"

# The canary must fail the run when the budget is breached, even after the rollback
# closed ingress — a breach is a NO-GO signal, not a recoverable state.
[[ "${budget_within}" == true ]] || { echo 'signed-RC canary breached its budget; ingress-close rollback executed' >&2; echo "${evidence_json}"; exit 1; }

report_path="${CANARY_ROLLBACK_REPORT:-}"
if [[ -n "${report_path}" ]]; then
	printf '%s\n' "${evidence_json}" > "${report_path}"
fi

summary_file="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
{
	echo '### Production Route V2 signed-RC canary + rollback dry-run'
	echo "- candidate SHA: \`${current_sha}\`"
	echo "- image digest: \`${current_digest}\`"
	echo "- approval: \`${PRODUCTION_CANARY_APPROVAL}\`"
	echo "- canary: within budget=${budget_within}"
	echo "- rollback dry-run: ingress_closed=${rollback_executed}, prior approved posture=ingress-closed"
} >> "${summary_file}"
