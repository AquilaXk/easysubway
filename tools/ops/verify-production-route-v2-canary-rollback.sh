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
#   2. the deployed backend SHA + Mobile version (read from apps/mobile/pubspec.yaml,
#      independent of the checked-in RC candidate record) + the PRODUCTION host's own
#      live active timetable snapshot (read directly from the production database,
#      independent of the checked-in timetable evidence file) all matching the SAME
#      checked-in RC candidate, and
#   3. the signed-RC canary attestation credential being provisioned (#1016) and the
#      Route V2 ingress being open post-approval.
#
# Absent any gate the runner exits non-zero without sending a single request or
# touching the ingress state. The pure decision logic (candidate identity, approval
# format, budget scoring, timeline evidence) lives in the companion Node module so it
# is unit-testable without a production runner.
#
# The rollback dry-run ALWAYS physically closes the REAL host Nginx Route V2 routing
# decision (the same infra/nginx/host-easysubway.conf.template render that
# deploy-backend.sh performs), not just an internal state marker: on a healthy
# canary this is a real close/verify/restore rehearsal, and on a budget breach it is
# the permanent rollback to the prior approved (ingress-closed) posture.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_LIB="${REPO_ROOT}/tools/ops/route-v2-canary-rollback-evidence.mjs"
OPERATIONS_EVIDENCE="${REPO_ROOT}/apps/mobile/release/operations-release-evidence.json"
TIMETABLE_EVIDENCE="${REPO_ROOT}/backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json"
PUBSPEC_PATH="${REPO_ROOT}/apps/mobile/pubspec.yaml"
HOST_NGINX_TEMPLATE="${REPO_ROOT}/infra/nginx/host-easysubway.conf.template"

# Dotenv parser copied verbatim from tools/ops/verify-production-route-v2-capacity.sh
# (and tools/deploy/deploy-backend.sh) so production-scoped values (the canary
# attestation key, Postgres identity, host proxy ports) are read with the SAME
# fail-closed duplicate-key rejection and quote-stripping as every other
# production-scoped secret this repo reads off the deployed compose.env — never as
# a GitHub Actions secrets.* reference (see workflow header comment).
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

# Parses the Mobile app's own canonical version declaration
# (apps/mobile/pubspec.yaml's `version: X.Y.Z+CODE` line) as an INDEPENDENT source
# for the deployed candidate's Mobile identity — independent of the
# operations-release-evidence.json candidate record that resolveExpectedCandidate()
# reads, so a drift between the two is actually detectable (see review finding on
# tools/ops/verify-production-route-v2-canary-rollback.sh lines 124-130).
parse_pubspec_version() {
	local file="${1:?pubspec path is required}"
	local line value name code
	line="$(grep -E '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$' "${file}")" || return 1
	value="${line#version:}"
	value="${value// /}"
	name="${value%%+*}"
	code="${value##*+}"
	[[ "${name}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "${code}" =~ ^[0-9]+$ ]] || return 1
	printf '{"versionName":"%s","versionCode":%s}\n' "${name}" "${code}"
}

# Test-only hooks: exercise the fail-closed gates and pure helpers without a
# production runner. They never touch the deploy lock, filesystem state, or edge.
if [[ "${1:-}" == --test-read-env-value ]]; then
	[[ $# -eq 3 && -f "${2}" && "${3}" =~ ^[A-Z0-9_]+$ ]] || exit 2
	read_env_value "${2}" "${3}"
	exit
fi
if [[ "${1:-}" == --test-parse-pubspec-version ]]; then
	[[ $# -eq 2 && -f "${2}" ]] || exit 2
	parse_pubspec_version "${2}" || exit 1
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

# Renders and atomically applies the SAME host Nginx Route V2 ingress action that
# deploy-backend.sh performs (infra/nginx/host-easysubway.conf.template,
# __ROUTE_V2_ACTION__), so a canary rollback closes the REAL public routing
# decision point — host Nginx decides open/closed BEFORE a request ever reaches the
# route-v2-gateway container, so reloading the gateway container alone (the
# previous implementation) never actually closed public ingress. Route/default
# proxy snippets are not re-installed here: deploy-backend.sh always installs them
# on every deploy, and the candidate identity gate below already guarantees this
# exact candidate SHA's last deploy-backend.sh run is what is currently live, so
# they are guaranteed already in sync.
apply_route_v2_host_ingress() {
	local action="${1:?ingress action is required}"
	local site_target="/etc/nginx/sites-available/easysubway"
	local candidate site_backup
	local site_existed=0 install_failed=0 restore_failed=0
	candidate="$(mktemp)" || return 1
	site_backup="$(mktemp)" || { rm -f "${candidate}"; return 1; }
	if ! sed \
		-e "s/__BACKEND_PORT__/${backend_port}/g" \
		-e "s|__ROUTE_V2_ACTION__|${action}|g" \
		"${HOST_NGINX_TEMPLATE}" > "${candidate}"; then
		rm -f "${candidate}" "${site_backup}"
		return 1
	fi
	if sudo test -f "${site_target}"; then
		if ! sudo cp "${site_target}" "${site_backup}"; then
			rm -f "${candidate}" "${site_backup}"
			return 1
		fi
		site_existed=1
	fi
	sudo install -m 0644 "${candidate}" "${site_target}" || install_failed=1
	if [[ "${install_failed}" -eq 0 ]] && ! sudo nginx -t >/dev/null 2>&1; then install_failed=1; fi
	if [[ "${install_failed}" -eq 0 ]] && ! sudo systemctl reload nginx; then install_failed=1; fi
	if [[ "${install_failed}" -ne 0 ]]; then
		if [[ "${site_existed}" -eq 1 ]]; then
			sudo install -m 0644 "${site_backup}" "${site_target}" || restore_failed=1
		else
			sudo rm -f "${site_target}" || restore_failed=1
		fi
		if [[ "${restore_failed}" -eq 0 ]]; then
			sudo nginx -t >/dev/null 2>&1 || restore_failed=1
		fi
		if [[ "${restore_failed}" -eq 0 ]]; then
			sudo systemctl reload nginx || restore_failed=1
		fi
		rm -f "${candidate}" "${site_backup}"
		[[ "${restore_failed}" -eq 0 ]] || echo 'failed to restore Route V2 host ingress after a failed apply' >&2
		return 1
	fi
	rm -f "${candidate}" "${site_backup}"
	return 0
}

public_status() {
	local path="${1:?path is required}"
	curl -sS --connect-timeout 3 --max-time 10 --output /dev/null --write-out '%{http_code}' \
		--request POST --header 'content-type: application/json' --data-binary '{}' "${PUBLIC_BASE_URL}${path}"
}

# Validates and extracts an issued Route V2 session token WITHOUT aborting the run
# on an invalid/missing body — a normal-profile session failure must still be
# collectible as a scored sample (see evaluateCanaryBudgets), not an early exit that
# would skip the rollback dry-run entirely.
capture_issued_session() {
	local body_file="${1:?body file is required}"
	node -e '
const { readFileSync } = require("node:fs");
try {
  const value = JSON.parse(readFileSync(process.argv[1], "utf8"));
  if (!/^[A-Za-z0-9_-]{43}$/.test(value?.token ?? "") || value.scope !== "route:v2:itx"
      || !Number.isFinite(Date.parse(value.issuedAt)) || !Number.isFinite(Date.parse(value.expiresAt))
      || Date.parse(value.expiresAt) <= Date.parse(value.issuedAt)) process.exit(1);
  process.stdout.write(value.token);
} catch { process.exit(1); }
' "${body_file}"
}

# --- Gate 1: pure input validation (fail-closed before any production access) ---
[[ "${EXPECTED_DEPLOYED_SHA}" =~ ^[0-9a-f]{40}$ ]] || { echo 'expected deployed SHA is invalid' >&2; exit 2; }
[[ "${PUBLIC_BASE_URL}" == https://easysubway-api.aquilaxk.site ]] \
	|| { echo 'public base URL must be the approved production origin' >&2; exit 2; }
node "${EVIDENCE_LIB}" validate-approval "${PRODUCTION_CANARY_APPROVAL}" \
	|| { echo 'production canary approval reference is missing or malformed' >&2; exit 2; }

# --- Gate 1b: the requested deploy SHA must be the checked-in RC candidate ---
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

# The deployed IMAGE must be the exact approved candidate image, AND the RUNNING
# container must actually be using that image (not just the local tag) — a host
# could have a stale/drifted container running under a different image while the
# local `easysubway-backend:<sha>` tag still looks correct, which would silently
# canary the wrong backend.
backend_image="easysubway-backend:${current_sha}"
image_revision="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "${backend_image}")"
[[ "${image_revision}" == "${current_sha}" ]] || { echo 'backend image revision mismatch' >&2; exit 1; }
repo_digests="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "${backend_image}")"
grep -Fxq "ghcr.io/aquilaxk/easysubway-backend@${current_digest}" <<< "${repo_digests}" \
	|| { echo 'backend image immutable digest mismatch' >&2; exit 1; }
expected_image_id="$(docker image inspect --format '{{.Id}}' "${backend_image}")"
[[ "$(docker inspect --format '{{.Config.Image}}' easysubway-backend)" == "${backend_image}" ]] \
	|| { echo 'running backend tag mismatch' >&2; exit 1; }
[[ "$(docker inspect --format '{{.Image}}' easysubway-backend)" == "${expected_image_id}" ]] \
	|| { echo 'running backend image mismatch' >&2; exit 1; }

backend_port="$(read_env_value "${compose_env}" EASYSUBWAY_BACKEND_PORT)"
backend_port="${backend_port:-8080}"
route_v2_gateway_port="$(read_env_value "${compose_env}" EASYSUBWAY_ROUTE_V2_GATEWAY_PORT)"
route_v2_gateway_port="${route_v2_gateway_port:-8081}"
route_v2_open_action="proxy_pass http://127.0.0.1:${route_v2_gateway_port};"
route_v2_closed_action="return 404;"

# The configured session burst allowance sizes the canary's own request volume
# (see the canary loop below): on the real public edge the caller-supplied
# CF-Connecting-IP is not trusted and is overwritten with the runner's actual
# source IP, so every request this runner sends shares ONE limiter key. Reading
# the configured value lets the canary size itself to that reality instead of
# guessing.
session_burst="$(read_env_value "${compose_env}" EASYSUBWAY_ROUTE_V2_SESSION_BURST)"
[[ "${session_burst}" =~ ^[0-9]+$ && "${session_burst}" -le 20 ]] \
	|| { echo 'configured Route V2 session burst is invalid or unexpectedly large' >&2; exit 1; }

# --- Gate 2: same candidate identity, sourced from INDEPENDENT deployed state ---
# Mobile version comes from the Mobile app's own pubspec.yaml (not copied from the
# same operations-release-evidence.json record used to build `expected`), and the
# timetable identity comes from a LIVE read against the production database's
# active snapshot (not the checked-in evidence file) — so a signed-but-wrong Mobile
# RC, or a production active-timetable drift, is actually detectable here instead
# of trivially matching itself.
mobile_version_json="$(parse_pubspec_version "${PUBSPEC_PATH}")" \
	|| { echo 'unable to parse the deployed Mobile RC version from pubspec.yaml' >&2; exit 1; }

postgres_user="$(read_env_value "${compose_env}" EASYSUBWAY_POSTGRES_USER)"
postgres_db="$(read_env_value "${compose_env}" EASYSUBWAY_POSTGRES_DB)"
[[ "${postgres_user}" =~ ^[A-Za-z0-9_.-]+$ && "${postgres_db}" =~ ^[A-Za-z0-9_.-]+$ ]] \
	|| { echo 'production PostgreSQL identity is invalid' >&2; exit 1; }
production_psql() {
	local sql="${1:?SQL is required}"
	docker exec easysubway-postgres sh -lc \
		'psql -X -v ON_ERROR_STOP=1 -A -t -U "$POSTGRES_USER" "$POSTGRES_DB" -c "$1"' sh "${sql}"
}
# fresh_until is rendered in UTC ("...Z") here, while the checked-in RC evidence
# keeps its original zone offset (e.g. "+09:00") for the SAME instant.
# assertCandidateMatch() (route-v2-canary-rollback-evidence.mjs) compares this
# field as parsed epoch milliseconds rather than by literal string equality, so
# this UTC rendering does not need to match the evidence file's offset text.
live_timetable_identity="$(production_psql "
SELECT history.snapshot_id || '|' || history.snapshot_sha256 || '|' || TO_CHAR(history.fresh_until::timestamptz AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')
FROM timetable_snapshot_active active
JOIN timetable_snapshot_history history ON history.snapshot_sha256 = active.snapshot_sha256
WHERE active.singleton_id = 1 AND history.fresh_until::timestamptz > CURRENT_TIMESTAMP;")"
IFS='|' read -r live_snapshot_id live_snapshot_sha256 live_snapshot_fresh_until <<< "${live_timetable_identity}"
[[ "${live_snapshot_id}" =~ ^[A-Za-z0-9._-]+$ && "${live_snapshot_sha256}" =~ ^[0-9a-f]{64}$ \
	&& "${live_snapshot_fresh_until}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
	|| { echo 'production active timetable snapshot identity is invalid, missing, or stale' >&2; exit 1; }

provided_candidate="$(node -e '
const mobile = JSON.parse(process.argv[2]);
process.stdout.write(JSON.stringify({
  backendDeploySha: process.argv[1],
  mobileVersionName: mobile.versionName,
  mobileVersionCode: mobile.versionCode,
  timetableSnapshotId: process.argv[3],
  timetableSnapshotSha256: process.argv[4],
  timetableFreshUntil: process.argv[5],
}));
' "${current_sha}" "${mobile_version_json}" "${live_snapshot_id}" "${live_snapshot_sha256}" "${live_snapshot_fresh_until}")"
node "${EVIDENCE_LIB}" assert-candidate "${expected_candidate}" "${provided_candidate}" \
	|| { echo 'deployed candidate identity does not match the checked-in RC candidate (independent Mobile pubspec.yaml + live production timetable identity)' >&2; exit 1; }

candidate_verified_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Gate 3a: signed-RC canary attestation must be provisioned (blocked on #1016) ---
# Sourced from the deployed compose.env, never from a GitHub Actions secret — same
# provider-key-overlay pattern as EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET in the capacity
# runner. The value is a JSON array of already-minted, genuine signed-RC Play
# Integrity token/nonce pairs (see the "Signed-RC canary integrity token pool"
# header comment in route-v2-canary-rollback-evidence.mjs for the full input
# contract) — never a raw key this runner signs locally, since production's real
# GooglePlayIntegrityDecoder (the `prod` profile) would reject any local
# synthesis. Until #1016 provisions enough pairs on the production host, the
# lookup/parse fails and the run is rejected before it sends a single request.
CANARY_INTEGRITY_TOKENS_RAW="$(read_env_value "${compose_env}" EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY)" \
	|| { echo 'signed-RC canary attestation credential is not provisioned (blocked on #1016); refusing to run' >&2; exit 1; }
# 1 normal-profile session request, plus enough burst-profile requests to exceed
# the CONFIGURED burst allowance by one — see the canary loop below for why
# normal and burst share a single request budget on the real public edge.
required_canary_requests=$((session_burst + 2))
canary_integrity_tokens="$(node "${EVIDENCE_LIB}" parse-integrity-tokens "${CANARY_INTEGRITY_TOKENS_RAW}" "${required_canary_requests}")" \
	|| { echo 'signed-RC canary attestation credential payload is invalid or has too few pairs (blocked on #1016); refusing to run' >&2; exit 1; }

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

# station-sangnoksu -> station-sadang is a direct Seoul Line 4 pair already used as
# a stable canonical OD fixture elsewhere in this repo (tools/datapack/official-od-fare-quotes.json).
# transportScope=SUBWAY avoids any ITX-청춘 freshness-window computation so the
# search canary works at any time of day; a departure well outside subway service
# hours can still legitimately return no itinerary, which is why the search sample
# below only requires HTTP 200 + a matching plannerIdentity, not a populated
# itinerary list.
departure_time="$(node -e '
const target = new Date(Date.now() + 20 * 60 * 1000 + 9 * 3600 * 1000);
const pad = (value) => String(value).padStart(2, "0");
process.stdout.write(`${target.getUTCFullYear()}-${pad(target.getUTCMonth() + 1)}-${pad(target.getUTCDate())}T${pad(target.getUTCHours())}:${pad(target.getUTCMinutes())}:${pad(target.getUTCSeconds())}+09:00`);
')"
search_request_body="$(node -e '
process.stdout.write(JSON.stringify({
  originStationId: "station-sangnoksu",
  destinationStationId: "station-sadang",
  departureTime: process.argv[1],
  transportScope: "SUBWAY",
  objective: "FASTEST",
  mobilityType: "SENIOR",
  constraintMode: "ALLOW_WITH_WARNINGS",
  useRealtime: false,
  maxTransfers: 1,
  alternativeCount: 1,
}));
' "${departure_time}")"

# Send a small signed-RC canary to the live public edge using a REAL pre-minted
# token/nonce pair from the integrity token pool (never a locally-synthesized
# attestation — see the Gate 3a comment) and record each response's status,
# latency, and Cache-Control for budget scoring.
#
# The public edge does not trust a caller-supplied CF-Connecting-IP (it is
# overwritten with the runner's real source IP before it reaches the limiter),
# so this function no longer accepts or sends one: every request this runner
# sends shares exactly one limiter key, by construction, not by header choice.
canary_sample() {
	local profile="${1:?profile is required}" path="${2:?path is required}"
	local index="${3:?index is required}" token_index="${4:?token index is required}"
	local result time_seconds attestation_file
	last_headers="${work_dir}/headers-${index}.txt"
	last_body="${work_dir}/body-${index}.json"
	attestation_file="${work_dir}/attestation-${index}.json"
	# Extracted to a file and sent via curl's `--data-binary @file` (not an
	# inline argv string) so the token value never appears in this process's own
	# argv either, on general principle — though these are already single-use,
	# short-lived, pool-issued tokens rather than a reusable signing credential.
	node -e '
const { writeFileSync } = require("node:fs");
const tokens = JSON.parse(process.argv[1]);
const pair = tokens[Number(process.argv[2])];
if (!pair) process.exit(1);
writeFileSync(process.argv[3], JSON.stringify({ integrityToken: pair.integrityToken, clientNonce: pair.clientNonce }));
' "${canary_integrity_tokens}" "${token_index}" "${attestation_file}" \
		|| { echo 'insufficient signed-RC canary integrity tokens for this request (blocked on #1016)' >&2; exit 1; }
	result="$(curl -sS --connect-timeout 3 --max-time 10 \
		-D "${last_headers}" -o "${last_body}" -w '%{http_code} %{time_total}' \
		--request POST --header 'content-type: application/json' \
		--data-binary "@${attestation_file}" "${PUBLIC_BASE_URL}${path}")"
	last_status="${result%% *}"
	time_seconds="${result#* }"
	last_latency_ms="$(node -e 'const v = Number(process.argv[1]); if (!Number.isFinite(v)) process.exit(1); process.stdout.write(String(Math.round(v * 1000)));' "${time_seconds}")"
	last_cache_control="$(sed -nE 's/^[Cc]ache-[Cc]ontrol:[[:space:]]*(.*)\r?$/\1/p' "${last_headers}" | head -n 1)"
	node -e '
const { appendFileSync } = require("node:fs");
appendFileSync(process.argv[1], JSON.stringify({
  profile: process.argv[2], status: Number(process.argv[3]),
  latencyMs: Number(process.argv[4]), cacheControl: process.argv[5],
}) + "\n");
' "${samples_file}.ndjson" "${profile}" "${last_status}" "${last_latency_ms}" "${last_cache_control}"
}

# Calls /api/v2/routes/search with an issued session token and records whether the
# response's plannerIdentity matches the same-candidate timetable identity — a
# canary that only ever probes /session never exercises the route search path or
# the active timetable it actually serves, so planner outages or timetable drift
# behind a healthy session endpoint would previously go undetected.
canary_search_sample() {
	local token="${1:?token is required}" index="${2:?index is required}"
	local headers_file="${work_dir}/headers-${index}.txt"
	local body_file="${work_dir}/body-${index}.json"
	local result status time_seconds latency_ms cache_control planner_identity_match
	result="$(curl -sS --connect-timeout 3 --max-time 10 \
		-D "${headers_file}" -o "${body_file}" -w '%{http_code} %{time_total}' \
		--request POST --header 'content-type: application/json' \
		--header "Authorization: Bearer ${token}" \
		--data-binary "${search_request_body}" "${PUBLIC_BASE_URL}/api/v2/routes/search")"
	status="${result%% *}"
	time_seconds="${result#* }"
	latency_ms="$(node -e 'const v = Number(process.argv[1]); if (!Number.isFinite(v)) process.exit(1); process.stdout.write(String(Math.round(v * 1000)));' "${time_seconds}")"
	cache_control="$(sed -nE 's/^[Cc]ache-[Cc]ontrol:[[:space:]]*(.*)\r?$/\1/p' "${headers_file}" | head -n 1)"
	if [[ "${status}" == 200 ]]; then
		planner_identity_match="$(node -e '
const body = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
const candidate = JSON.parse(process.argv[2]);
const identity = body?.success === true ? body?.data?.plannerIdentity : null;
process.stdout.write(String(identity?.timetableSnapshotSha256 === candidate.timetableSnapshotSha256));
' "${body_file}" "${expected_candidate}")"
	else
		planner_identity_match="false"
	fi
	node -e '
const { appendFileSync } = require("node:fs");
appendFileSync(process.argv[1], JSON.stringify({
  profile: process.argv[2], status: Number(process.argv[3]),
  latencyMs: Number(process.argv[4]), cacheControl: process.argv[5],
  plannerIdentityMatch: process.argv[6] === "true",
}) + "\n");
' "${samples_file}.ndjson" normal "${status}" "${latency_ms}" "${cache_control}" "${planner_identity_match}"
}

# Exactly ONE normal-profile request, then enough burst-profile requests to
# exceed the configured burst allowance by one. All of it goes through the SAME
# real limiter key (the runner's own source IP — see canary_sample), so sending
# more than a couple of "normal" requests before the burst phase would risk the
# limiter itself rejecting a later "normal" request and producing a false
# breach; sending too few burst requests would never observe the 429 the limit
# check requires. `session_burst + 2` matches the exact count the isolated
# capacity runner uses to reliably cross its own burst allowance.
: > "${samples_file}.ndjson"
issued_token=""
canary_sample normal /api/v2/routes/session 1 0
issued_token="$(capture_issued_session "${last_body}" || true)"
for ((burst_attempt = 0; burst_attempt <= session_burst; burst_attempt += 1)); do
	canary_index=$((burst_attempt + 2))
	canary_sample burst /api/v2/routes/session "${canary_index}" "$((canary_index - 1))"
	if [[ -z "${issued_token}" ]]; then
		issued_token="$(capture_issued_session "${last_body}" || true)"
	fi
done
# Only attempt the route search canary if session issuance produced a usable
# token — if none did, the normal/burst samples above already recorded enough
# non-200 statuses for evaluateCanaryBudgets to treat this as a budget breach on
# its own, and the rollback dry-run below still runs unconditionally.
if [[ -n "${issued_token}" ]]; then
	canary_search_sample "${issued_token}" "$((required_canary_requests + 1))"
fi
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

# --- Rollback dry-run: ALWAYS physically close host ingress, then either restore
# (healthy canary rehearsal) or leave it closed (budget breach, permanent) ---
rollback_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

apply_route_v2_host_ingress "${route_v2_closed_action}" \
	|| { echo 'ingress-close rollback failed to apply the host Nginx configuration' >&2; exit 1; }
printf 'false\n' > "${ingress_state_file}"
chmod 600 "${ingress_state_file}"
ingress_closed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

session_closed="$(public_status /api/v2/routes/session)"
search_closed="$(public_status /api/v2/routes/search)"
[[ "${session_closed}" == 404 && "${search_closed}" == 404 ]] \
	|| { echo 'ingress-close rollback did not close the public Route V2 edge' >&2; exit 1; }

restored_after_rehearsal=false
ingress_restored_at=""
if [[ "${budget_within}" == true ]]; then
	# Healthy canary: this is a REAL, non-mutating-net-effect close/verify/restore
	# rehearsal — the close is proven for real against the live edge, then ingress
	# is restored to the state the canary started in (open), so the rollback
	# mechanism is exercised end-to-end without a lasting production change.
	apply_route_v2_host_ingress "${route_v2_open_action}" \
		|| { echo 'rollback rehearsal failed to restore the host Nginx configuration' >&2; exit 1; }
	printf 'true\n' > "${ingress_state_file}"
	chmod 600 "${ingress_state_file}"
	ingress_restored_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	session_restored="$(public_status /api/v2/routes/session)"
	search_restored="$(public_status /api/v2/routes/search)"
	[[ "${session_restored}" != 404 && "${search_restored}" != 404 ]] \
		|| { echo 'rollback rehearsal did not restore the public Route V2 edge' >&2; exit 1; }
	restored_after_rehearsal=true
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
  ingress_closed: process.argv[8],
  rollback_verified: process.argv[10],
  evidence_emitted: process.argv[11],
};
if (process.argv[9]) stages.ingress_restored = process.argv[9];
writeFileSync(process.argv[1], JSON.stringify({
  candidate: JSON.parse(process.argv[12]),
  publicBaseUrl: process.argv[13],
  approvalReference: process.argv[14],
  ingressWasOpen: true,
  budget: JSON.parse(process.argv[15]),
  budgetResult: JSON.parse(process.argv[16]),
  restoredAfterRehearsal: process.argv[17] === "true",
  priorApprovedState: JSON.parse(process.argv[18]),
  stages,
}));
' "${evidence_input_file}" \
	"${candidate_verified_at}" "${prior_state_recorded_at}" "${canary_started_at}" "${canary_completed_at}" \
	"${budget_evaluated_at}" "${rollback_started_at}" "${ingress_closed_at}" "${ingress_restored_at}" \
	"${rollback_verified_at}" "${evidence_emitted_at}" "${expected_candidate}" "${PUBLIC_BASE_URL}" \
	"${PRODUCTION_CANARY_APPROVAL}" "${canary_budget}" "${budget_result}" "${restored_after_rehearsal}" \
	"${prior_approved_state}"

evidence_json="$(node "${EVIDENCE_LIB}" build-evidence "${evidence_input_file}")"

# Evidence is ALWAYS persisted outside work_dir (which is removed on EXIT) — on both
# a PASS and a budget breach — so the workflow's artifact upload step can preserve
# the dry-run's full timeline/candidate/budget detail regardless of outcome.
report_path="${CANARY_ROLLBACK_REPORT:-${RUNNER_TEMP:-/tmp}/route-v2-canary-rollback-evidence.json}"
printf '%s\n' "${evidence_json}" > "${report_path}"
chmod 600 "${report_path}"

# The canary must fail the run when the budget is breached, even after the rollback
# closed ingress — a breach is a NO-GO signal, not a recoverable state.
[[ "${budget_within}" == true ]] || { echo 'signed-RC canary breached its budget; ingress-close rollback executed' >&2; exit 1; }

summary_file="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
{
	echo '### Production Route V2 signed-RC canary + rollback dry-run'
	echo "- candidate SHA: \`${current_sha}\`"
	echo "- image digest: \`${current_digest}\`"
	echo "- approval: \`${PRODUCTION_CANARY_APPROVAL}\`"
	echo "- canary: within budget=${budget_within}"
	echo "- rollback dry-run: ingress_closed=true, restored_after_rehearsal=${restored_after_rehearsal}"
	echo "- evidence: \`${report_path}\`"
} >> "${summary_file}"
