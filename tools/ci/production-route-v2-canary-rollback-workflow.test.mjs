import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

import {
  assertCandidateMatch,
  buildCanaryRollbackEvidence,
  CANARY_TIMELINE_STAGES,
  evaluateCanaryBudgets,
  parseCanaryIntegrityTokens,
  resolveExpectedCandidate,
  validateApprovalReference,
} from "../ops/route-v2-canary-rollback-evidence.mjs";

const workflowPath = ".github/workflows/production-route-v2-canary-rollback-dry-run.yml";
const runnerPath = "tools/ops/verify-production-route-v2-canary-rollback.sh";
const deployBackendPath = "tools/deploy/deploy-backend.sh";
const operationsEvidencePath = "apps/mobile/release/operations-release-evidence.json";
const timetableEvidencePath = "backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json";
const composeAllowlistPath = "tools/deploy/compose-server-env.allowlist";
const prepareDeploymentEnvPath = "tools/deploy/prepare-deployment-env.sh";
const execFileAsync = promisify(execFile);

const validApproval = "https://github.com/AquilaXk/easysubway/issues/2095";

// A real signed-RC Play Integrity clientNonce is exactly 22 base64url
// characters decoding to 16 bytes (matches RouteV2SessionService's own
// validation) — this generates genuine ones so pool-fixture tests exercise
// the SAME format/uniqueness rules the parser now enforces.
function makeNonce() {
  return randomBytes(16).toString("base64url");
}

function validPoolPayload({ mintedAt = new Date().toISOString(), pairCount = 4 } = {}) {
  return JSON.stringify({
    mintedAt,
    mobileVersionName: "1.0.5",
    mobileVersionCode: 10006,
    pairs: Array.from({ length: pairCount }, (_, index) => ({
      integrityToken: `token-${index}`,
      clientNonce: makeNonce(),
    })),
  });
}

test("canary rollback workflow는 승인 input과 main-only production 게이트를 강제한다", async () => {
  const workflow = await readFile(workflowPath, "utf8");

  assert.match(workflow, /workflow_dispatch:/);
  assert.doesNotMatch(workflow, /^\s+(push|schedule|pull_request):/m);
  assert.match(workflow, /runs-on:\n\s+- self-hosted\n\s+- easysubway-production/);
  assert.match(workflow, /environment: production/);
  assert.match(workflow, /permissions:\n\s+contents: read/);
  assert.match(workflow, /persist-credentials: false/);
  assert.match(workflow, /timeout-minutes: 30/);
  assert.match(workflow, /cancel-in-progress: false/);
  assert.match(workflow, /group: production-route-v2-canary-rollback-dry-run/);
  assert.match(
    workflow,
    /production_approval:\n\s+description: "[^"]+"\n\s+required: true\n\s+type: string/,
  );
  assert.match(
    workflow,
    /deploy_sha:\n\s+description: "[^"]+"\n\s+required: false\n\s+type: string/,
  );
  assert.match(workflow, /PRODUCTION_CANARY_APPROVAL: \$\{\{ inputs\.production_approval \}\}/);
  assert.match(
    workflow,
    /CANARY_ROLLBACK_REPORT: \$\{\{ runner\.temp \}\}\/route-v2-canary-rollback-evidence\.json/,
  );
  // The token pool is delivered as a host-local file (see the runner's Gate 3
  // comment), never via a GitHub Actions secret or workflow_dispatch input — a
  // plain-string dispatch input would be publicly visible on this public repo.
  for (const match of workflow.matchAll(/secrets(?:\.([A-Z0-9_]+)|\[['"]([A-Z0-9_]+)['"]\])/g)) {
    const secretName = match[1] ?? match[2];
    assert.ok(
      secretName === "EASYSUBWAY_ENV" || secretName === "GITHUB_TOKEN",
      `unexpected scoped secret reference: ${secretName}`,
    );
  }
  assert.doesNotMatch(workflow, /canary_integrity_tokens/i);
  assert.match(workflow, /actions\/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e/);
  assert.match(workflow, /node-version: "24"/);
  assert.match(workflow, /bash tools\/ops\/verify-production-route-v2-canary-rollback\.sh/);
  assert.match(
    workflow,
    /if \[\[ "\$\{GITHUB_REF\}" != "refs\/heads\/main" \]\]; then\s+echo "production Route V2 canary rollback dry-run must run from main" >&2\s+exit 1\s+fi/,
  );
  assert.match(workflow, /fetch-depth: 0/);

  // The runner tooling must always execute from the reviewed main checkout: the
  // canary/rollback scripts are new in this PR and may not exist at an
  // already-approved historical candidate SHA, so the workflow resolves and
  // ancestor-verifies the candidate SHA WITHOUT checking its tree out.
  assert.match(workflow, /name: Resolve and verify canary candidate SHA/);
  // workflow_dispatch input is passed via env (DEPLOY_SHA_INPUT), never
  // interpolated directly into the shell script, so it cannot inject shell
  // syntax — the same pattern this repo already uses for every other dispatch
  // input (e.g. cd.yml's DISPATCH_SHA).
  assert.match(workflow, /DEPLOY_SHA_INPUT: \$\{\{ inputs\.deploy_sha \}\}/);
  assert.doesNotMatch(workflow, /="\$\{\{\s*inputs\./);
  assert.match(workflow, /candidate_sha="\$\{DEPLOY_SHA_INPUT\}"/);
  assert.match(workflow, /if \[\[ -z "\$\{candidate_sha\}" \]\]; then/);
  assert.match(
    workflow,
    /routeV2Readiness\.realisticLoadEvidence\.candidate\.candidateGitSha/,
  );
  assert.match(workflow, /if \[\[ ! "\$\{candidate_sha\}" =~ \^\[0-9a-f\]\{40\}\$ \]\]; then/);
  assert.match(workflow, /if ! git merge-base --is-ancestor "\$\{candidate_sha\}" origin\/main; then/);
  assert.match(workflow, /echo "EXPECTED_DEPLOYED_SHA=\$\{candidate_sha\}" >> "\$\{GITHUB_ENV\}"/);
  assert.doesNotMatch(workflow, /git checkout --detach/);
  assert.doesNotMatch(workflow, /EXPECTED_DEPLOYED_SHA: \$\{\{ inputs\.deploy_sha/);
  assert.ok(
    workflow.indexOf("Resolve and verify canary candidate SHA") < workflow.indexOf("Set up Node.js"),
  );

  // Evidence is always uploaded (even on a fail-closed early rejection, when no
  // file exists yet — hence `warn` not this repo's default `error`).
  assert.match(workflow, /name: Upload canary rollback evidence/);
  assert.match(workflow, /if: always\(\)/);
  assert.match(workflow, /uses: actions\/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02/);
  assert.match(workflow, /name: route-v2-canary-rollback-evidence-\$\{\{ github\.sha \}\}/);
  assert.match(
    workflow,
    /path: \$\{\{ runner\.temp \}\}\/route-v2-canary-rollback-evidence\.json/,
  );
  assert.match(workflow, /if-no-files-found: warn/);
  assert.match(workflow, /retention-days: 14/);
});

test("canary rollback runner는 fail-closed 게이트와 rollback 경로를 갖춘다", async () => {
  const runner = await readFile(runnerPath, "utf8");

  assert.match(runner, /^set -euo pipefail$/m);
  assert.match(runner, /^umask 077$/m);
  // Explicit owner approval + same-candidate identity gates.
  assert.match(runner, /validate-approval/);
  assert.match(runner, /production canary approval reference is missing or malformed/);
  assert.match(runner, /requested deploy SHA does not match the checked-in RC candidate/);
  assert.match(runner, /assert-candidate/);
  assert.match(
    runner,
    /deployed candidate identity does not match the checked-in RC candidate \(signed-RC token pool provisioning evidence \+ live production timetable identity\)/,
  );
  // #1016 attestation + ingress-open preconditions are fail-closed.
  assert.match(runner, /blocked on #1016/);
  assert.match(runner, /Route V2 ingress must be open for the signed-RC canary/);
  assert.match(runner, /EXPECTED_DEPLOYED_SHA\}" =~ \^\[0-9a-f\]\{40\}\$/);
  assert.match(runner, /PUBLIC_BASE_URL.*==.*https:\/\/easysubway-api\.aquilaxk\.site/);
  // pure-input gate runs before the deploy lock so fail-closed never touches state.
  assert.ok(runner.indexOf("validate-approval") < runner.indexOf('exec 9>"${DEPLOY_ROOT}/deploy.lock"'));
  // No more compose.env-based key: the token pool is never sourced from a
  // GitHub Actions secret NOR the durable deploy-time compose.env.
  assert.doesNotMatch(runner, /EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY/);
  assert.doesNotMatch(runner, /CANARY_ATTESTATION_KEY/);
  assert.match(runner, /is defined \$\{match_count\} times in the deployment environment/);

  // Production runs the real GooglePlayIntegrityDecoder (prod profile) — this
  // runner must never locally synthesize an attestation, so it consumes a
  // freshly-minted, host-local, single-use token pool file instead.
  assert.doesNotMatch(runner, /createHmac/);
  assert.doesNotMatch(runner, /randomBytes\(16\)\.toString\("base64url"\)/);

  // Gate 3: the token pool is a HOST-LOCAL file (never compose.env, never a GH
  // secret/input) that is MOVED (not copied) out of the well-known shared
  // location and deleted, so a second run can never replay it.
  assert.match(
    runner,
    /canary_pool_source="\$\{DEPLOY_ROOT\}\/shared\/route-v2-canary-integrity-tokens\.json"/,
  );
  assert.match(runner, /signed-RC canary attestation token pool is not provisioned \(blocked on #1016\)/);
  assert.match(runner, /mv "\$\{canary_pool_source\}" "\$\{canary_pool_raw_file\}"/);
  assert.match(runner, /rm -f "\$\{canary_pool_raw_file\}"/);
  assert.match(runner, /node "\$\{EVIDENCE_LIB\}" parse-integrity-tokens "\$\{required_canary_requests\}" \\\n\s*< "\$\{canary_pool_raw_file\}"/);
  assert.match(runner, /signed-RC canary attestation token pool is invalid, stale, or has too few pairs \(blocked on #1016\)/);
  assert.match(runner, /required_canary_requests=\$\(\(session_burst \+ 2\)\)/);
  // Gate 2 (ingress-open) runs BEFORE Gate 3 (pool consumption) so a
  // not-yet-approved run never burns a freshly-minted single-use pool.
  assert.ok(
    runner.indexOf("Route V2 ingress must be open for the signed-RC canary")
      < runner.indexOf('canary_pool_source="${DEPLOY_ROOT}/shared/route-v2-canary-integrity-tokens.json"'),
  );

  // Gate 4: Mobile candidate identity comes from the token pool's OWN declared
  // provisioning evidence (mobileVersionName/mobileVersionCode — what #1016
  // actually signed to mint the tokens), never from the reviewed-main
  // checkout's pubspec.yaml.
  assert.doesNotMatch(runner, /PUBSPEC_PATH/);
  assert.doesNotMatch(runner, /parse_pubspec_version/);
  assert.match(
    runner,
    /const p = JSON\.parse\(require\("node:fs"\)\.readFileSync\(process\.argv\[1\], "utf8"\)\);\nprocess\.stdout\.write\(JSON\.stringify\(\{ versionName: p\.mobileVersionName, versionCode: p\.mobileVersionCode \}\)\);/,
  );
  assert.match(runner, /production_psql\(\) \{/);
  assert.match(runner, /docker exec easysubway-postgres/);
  assert.match(runner, /timetable_snapshot_active/);
  assert.match(runner, /timetable_snapshot_history/);
  assert.match(runner, /production active timetable snapshot identity is invalid, missing, or stale/);

  // Running-container drift check (image tag AND image ID), not just the local
  // image inspect by tag.
  assert.match(runner, /expected_image_id="\$\(docker image inspect --format '\{\{\.Id\}\}' "\$\{backend_image\}"\)"/);
  assert.match(
    runner,
    /\[\[ "\$\(docker inspect --format '\{\{\.Config\.Image\}\}' easysubway-backend\)" == "\$\{backend_image\}" \]\] \\\n\s*\|\| \{ echo 'running backend tag mismatch' >&2; exit 1; \}/,
  );
  assert.match(
    runner,
    /\[\[ "\$\(docker inspect --format '\{\{\.Image\}\}' easysubway-backend\)" == "\$\{expected_image_id\}" \]\] \\\n\s*\|\| \{ echo 'running backend image mismatch' >&2; exit 1; \}/,
  );

  // The public edge overwrites any caller-supplied CF-Connecting-IP with the
  // runner's real source IP, so every request shares one limiter key.
  assert.doesNotMatch(runner, /--header "CF-Connecting-IP/);
  assert.match(runner, /session_burst="\$\(read_env_value "\$\{compose_env\}" EASYSUBWAY_ROUTE_V2_SESSION_BURST\)"/);
  assert.match(runner, /canary_sample normal \/api\/v2\/routes\/session 1 0/);
  assert.match(
    runner,
    /for \(\(burst_attempt = 0; burst_attempt <= session_burst; burst_attempt \+= 1\)\)/,
  );

  // Route search canary + planner identity cross-check.
  assert.match(runner, /canary_search_sample\(\) \{/);
  assert.match(runner, /\/api\/v2\/routes\/search/);
  assert.match(runner, /plannerIdentityMatch/);
  assert.match(runner, /capture_issued_session/);
  assert.match(runner, /route:v2:itx/);
  // A malformed/truncated/non-JSON 200 search body must not let JSON.parse
  // throw inside the node -e call: an uncaught exception would exit non-zero
  // under `set -e`, aborting the script BEFORE the rollback section. Wrapped
  // in try/catch so any parse failure is scored as plannerIdentityMatch=false
  // (a breach sample) instead of skipping rollback entirely.
  const searchSampleBlock = runner.match(/canary_search_sample\(\) \{[\s\S]*?\n\}\n/)?.[0] ?? "";
  assert.match(searchSampleBlock, /try \{/);
  assert.match(searchSampleBlock, /\} catch \{\n\s*process\.stdout\.write\("false"\);\n\s*\}/);

  // If NO normal/burst response ever yielded a usable session token (every
  // 200 body was invalid/missing — capture_issued_session only recognizes a
  // well-formed token/scope/timestamp), the route search canary can never run
  // at all. Skipping it silently would let the run pass on 200s + a 429 alone
  // without ever exercising search — so this must itself be recorded as an
  // explicit breach sample (a normal-profile sample that is not exact 200),
  // not silently skipped.
  assert.match(
    runner,
    /if \[\[ -n "\$\{issued_token\}" \]\]; then\n\s*canary_search_sample "\$\{issued_token\}" "\$\(\(required_canary_requests \+ 1\)\)"\nelse/,
  );
  const noTokenBranch = runner.match(
    /if \[\[ -n "\$\{issued_token\}" \]\]; then\n[\s\S]*?\nelse\n([\s\S]*?)\nfi\n/,
  )?.[1] ?? "";
  assert.match(noTokenBranch, /no usable Route V2 session token was captured/);
  assert.match(
    noTokenBranch,
    /profile: "normal", status: 0, latencyMs: 0, cacheControl: "", plannerIdentityMatch: false,/,
  );

  // Token pool pair lookups pass only the FILE PATH and a numeric index as
  // node -e argv, never the pool content itself — a same-UID process reading
  // /proc/<pid>/cmdline sees no token material.
  assert.match(runner, /attestation_file="\$\{work_dir\}\/attestation-\$\{index\}\.json"/);
  assert.match(
    runner,
    /"\$\{canary_pool_parsed_file\}" "\$\{token_index\}" "\$\{attestation_file\}"/,
  );
  assert.match(runner, /--data-binary "@\$\{attestation_file\}"/);
  assert.doesNotMatch(runner, /process\.argv\[1\], "hex"/);

  // Transport failures (curl non-zero: DNS/TLS/timeout) must not trip `set -e`
  // mid-canary and skip the rollback section — captured as curl's own "000"
  // sentinel via a `|| true` guard instead.
  assert.match(runner, /send_canary_request\(\) \{/);
  assert.match(runner, /\|\| true$/m);
  assert.match(runner, /if \[\[ "\$\{last_status\}" == 000 \|\| -z "\$\{last_status\}" \]\]; then/);
  assert.match(runner, /canary request transport failure \(DNS\/TLS\/connect\/timeout\)/);
  assert.match(
    runner,
    /curl -sS --connect-timeout 3 --max-time 10 --output \/dev\/null --write-out '%\{http_code\}' \\\n\s*--request POST --header 'content-type: application\/json' --data-binary '\{\}' "\$\{PUBLIC_BASE_URL\}\$\{path\}" \|\| true/,
  );

  // Ingress-close rollback ALWAYS applies the real host Nginx configuration (not
  // just the state marker or a gateway-container-only reload). The atomic
  // install/backup/restore primitive is factored into install_route_v2_site_config,
  // shared by apply_route_v2_host_ingress (fresh template render) and
  // restore_route_v2_host_ingress_original (reinstalls the exact pre-rehearsal
  // bytes — see below).
  assert.match(runner, /install_route_v2_site_config\(\) \{/);
  assert.match(runner, /apply_route_v2_host_ingress\(\) \{/);
  assert.match(runner, /restore_route_v2_host_ingress_original\(\) \{/);
  assert.match(runner, /__ROUTE_V2_ACTION__/);
  assert.match(runner, /__BACKEND_PORT__/);
  assert.match(runner, /sudo install -m 0644 "\$\{candidate_file\}" "\$\{site_target\}"/);
  assert.match(runner, /sudo nginx -t/);
  assert.match(runner, /sudo systemctl reload nginx/);
  assert.doesNotMatch(runner, /docker exec easysubway-route-v2-gateway nginx -s reload/);
  assert.match(runner, /route_v2_closed_action="return 404;"/);
  assert.match(runner, /route_v2_open_action="proxy_pass http:\/\/127\.0\.0\.1:\$\{route_v2_gateway_port\};"/);
  assert.match(runner, /printf 'false\\n' > "\$\{ingress_state_file\}"/);
  assert.match(runner, /ingress-close rollback did not close the public Route V2 edge/);

  // The exact pre-rehearsal Nginx site config is preserved BEFORE the first
  // close, and restore_route_v2_host_ingress_original reinstalls those exact
  // bytes on the healthy path — NOT a fresh host-easysubway.conf.template
  // render, which could already differ from what a HISTORICAL candidate SHA's
  // own deploy-backend.sh run actually installed and would otherwise
  // permanently drift its config as a side effect of a supposedly
  // zero-net-effect rehearsal.
  assert.match(runner, /original_site_config="\$\{work_dir\}\/original-route-v2-site-config"/);
  assert.match(
    runner,
    /sudo test -f \/etc\/nginx\/sites-available\/easysubway/,
  );
  assert.match(
    runner,
    /sudo cp \/etc\/nginx\/sites-available\/easysubway "\$\{original_site_config\}"/,
  );
  assert.ok(
    runner.indexOf('original_site_config="${work_dir}/original-route-v2-site-config"')
      < runner.indexOf('apply_route_v2_host_ingress "${route_v2_closed_action}"'),
  );

  // The breach/healthy split happens IMMEDIATELY after the close is applied,
  // BEFORE any public verification probe — the healthy branch must reach its
  // OWN restore step regardless of what the close-verification probe reports
  // (see below), and the breach branch must write its durable lock before its
  // own close-verification probe can abort the script.
  assert.match(runner, /if \[\[ "\$\{budget_within\}" != true \]\]; then/);
  assert.doesNotMatch(runner, /if \[\[ "\$\{budget_within\}" == true \]\]; then/);
  assert.ok(
    runner.indexOf("ingress_closed_at=") < runner.indexOf('if [[ "${budget_within}" != true ]]; then'),
  );

  // write_route_v2_rollback_lock persists a durable lock — used by BOTH the
  // budget-breach path (immediately after the host close is applied, BEFORE
  // its own public verification probe, which depends on the network and
  // could itself return curl's "000" transport sentinel) and the healthy
  // rehearsal path's restore-failure branch (finding: a restore that fails
  // after a successful close must not leave production silently closed with
  // NO lock, letting a later unrelated deploy reopen it from compose.env's
  // stale desired state).
  assert.match(runner, /write_route_v2_rollback_lock\(\) \{/);
  assert.match(
    runner,
    /lock_file="\$\{DEPLOY_ROOT\}\/shared\/route-v2-canary-rollback-lock\.json"/,
  );
  assert.match(runner, /reason: process\.argv\[2\]/);
  const breachBranch = runner.match(
    /if \[\[ "\$\{budget_within\}" != true \]\]; then([\s\S]*?)\nelse\n/,
  )?.[1] ?? "";
  assert.match(breachBranch, /write_route_v2_rollback_lock 'signed-RC canary budget breach'/);
  assert.ok(
    breachBranch.indexOf("write_route_v2_rollback_lock 'signed-RC canary budget breach'")
      < breachBranch.indexOf("session_closed="),
  );
  // A verification failure on the PERMANENT-close path does NOT exit — the
  // evidence assembly/persistence below (candidate, samples, budget result,
  // timeline) must still run, so a transient "000"/non-404 probe never
  // discards that evidence. The run still fails via the budget-breach check
  // at the very end of the script regardless of this probe's own outcome.
  assert.match(
    breachBranch,
    /if \[\[ "\$\{session_closed\}" != 404 \|\| "\$\{search_closed\}" != 404 \]\]; then\n\s*echo 'ingress-close rollback did not close the public Route V2 edge \(continuing to persist evidence before failing the run\)' >&2\n\s*fi/,
  );
  assert.doesNotMatch(
    breachBranch,
    /\[\[ "\$\{session_closed\}" == 404 && "\$\{search_closed\}" == 404 \]\] \\\n\s*\|\| \{ echo 'ingress-close rollback did not close the public Route V2 edge' >&2; exit 1; \}/,
  );

  // Healthy-path REAL close/verify/restore rehearsal: the close-verification
  // probe's failure (including curl's "000" transport sentinel) must NOT skip
  // the restore step — it is only RECORDED (rehearsal_verification_failed=1)
  // and the restore is attempted unconditionally right after, so a network
  // blip on this specific probe can never leave the rehearsal's promised zero
  // net effect broken (production ingress stuck closed).
  const healthyBranch = runner.match(/\nelse\n([\s\S]*?)\nfi\nrollback_verified_at=/)?.[1] ?? "";
  assert.match(healthyBranch, /rehearsal_verification_failed=0/);
  assert.match(
    healthyBranch,
    /if \[\[ "\$\{session_closed\}" != 404 \|\| "\$\{search_closed\}" != 404 \]\]; then/,
  );
  assert.match(healthyBranch, /rehearsal_verification_failed=1/);
  assert.match(healthyBranch, /restore_route_v2_host_ingress_original/);
  assert.match(healthyBranch, /rollback rehearsal did not restore the public Route V2 edge/);
  assert.match(healthyBranch, /restored_after_rehearsal=true/);
  // The restore APPLICATION call must be UNCONDITIONAL — it appears after the
  // close-verification probe's failure is merely recorded, never inside an
  // `exit`-guarded branch that the probe's own failure could skip. And if the
  // restore APPLICATION itself fails, ingress must be durably LOCKED closed
  // (not just abandoned) before the script exits.
  assert.ok(
    healthyBranch.indexOf('rehearsal_verification_failed=1')
      < healthyBranch.indexOf('if ! restore_route_v2_host_ingress_original; then'),
  );
  assert.match(
    healthyBranch,
    /if ! restore_route_v2_host_ingress_original; then\n\s*write_route_v2_rollback_lock 'rollback rehearsal failed to restore ingress after a successful close'\n\s*echo '[^']+' >&2\n\s*exit 1\n\s*fi/,
  );
  // The overall pass/fail decision (exit on any recorded verification failure)
  // comes AFTER the restore application, not before it.
  assert.ok(
    healthyBranch.indexOf('if ! restore_route_v2_host_ingress_original; then')
      < healthyBranch.lastIndexOf('rehearsal_verification_failed=1')
      && healthyBranch.lastIndexOf('rehearsal_verification_failed=1')
      < healthyBranch.indexOf('[[ "${rehearsal_verification_failed}" -eq 0 ]]'),
  );

  // Restore verification rejects the "000" transport sentinel explicitly — a
  // network outage during THIS probe must not be misread as "not 404, so
  // restored". Both probes must be a real 3-digit status, neither 404 nor 000.
  assert.match(
    healthyBranch,
    /\[\[ "\$\{session_restored\}" =~ \^\[0-9\]\{3\}\$ && "\$\{session_restored\}" != 404 && "\$\{session_restored\}" != 000 \\\n\s*&& "\$\{search_restored\}" =~ \^\[0-9\]\{3\}\$ && "\$\{search_restored\}" != 404 && "\$\{search_restored\}" != 000 \]\]/,
  );
  assert.doesNotMatch(runner, /"\$\{session_restored\}" != 404 && "\$\{search_restored\}" != 404 \]\]/);

  assert.match(runner, /build-evidence/);
  assert.match(runner, /signed-RC canary breached its budget; ingress-close rollback executed/);

  // Evidence is ALWAYS persisted (both PASS and breach), before the budget check
  // can exit the run.
  assert.match(runner, /report_path="\$\{CANARY_ROLLBACK_REPORT:-\$\{RUNNER_TEMP:-\/tmp\}\/route-v2-canary-rollback-evidence\.json\}"/);
  assert.ok(
    runner.indexOf('printf \'%s\\n\' "${evidence_json}" > "${report_path}"')
      < runner.indexOf('[[ "${budget_within}" == true ]] || { echo \'signed-RC canary breached'),
  );

  // No secret leakage or trace expansion.
  assert.doesNotMatch(runner, /set -x/);
  assert.doesNotMatch(runner, /gh secret set/);
});

test("canary attestation key는 표준 CD 배포 allowlist에 더 이상 없다(실행-시점 파일 공급으로 일원화)", async () => {
  // Round 2 stored the token pool in compose.env (a durable deploy-time
  // artifact); this was superseded because RouteV2SessionService rejects a
  // Play Integrity verdict older than 2 minutes and rejects a replayed nonce —
  // a pool sitting in compose.env since the last deploy would always be stale.
  // The design is now unified on execution-time delivery (a host-local file
  // consumed by the runner's Gate 3), so the compose.env allowlist entry and
  // its conditional value-validation contract are both reverted.
  const allowlist = await readFile(composeAllowlistPath, "utf8");
  assert.doesNotMatch(allowlist, /^EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY$/m);

  const prepareScript = await readFile(prepareDeploymentEnvPath, "utf8");
  assert.doesNotMatch(prepareScript, /EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY/);
  assert.doesNotMatch(prepareScript, /canary_attestation_key_value/);
});

test("deploy-backend.sh는 canary rollback lock이 있으면 Route V2 ingress를 강제로 닫는다", async () => {
  const deploy = await readFile(deployBackendPath, "utf8");
  assert.match(
    deploy,
    /route_v2_canary_rollback_lock="\$\{SHARED_DIR\}\/route-v2-canary-rollback-lock\.json"/,
  );
  assert.match(deploy, /if \[\[ -f "\$\{route_v2_canary_rollback_lock\}" \]\]; then/);
  const overrideBlock = deploy.match(
    /if \[\[ -f "\$\{route_v2_canary_rollback_lock\}" \]\]; then([\s\S]*?)\nfi\n/,
  )?.[1] ?? "";
  assert.match(overrideBlock, /route_v2_ingress_enabled_normalized=false/);
  assert.match(overrideBlock, /route_v2_host_action="return 404;"/);
});

test("canary runner --test-validate-approval는 승인 형식을 강제한다", async () => {
  await execFileAsync("bash", [runnerPath, "--test-validate-approval", validApproval]);
  await assert.rejects(
    execFileAsync("bash", [runnerPath, "--test-validate-approval", "approved-by-owner"]),
  );
  await assert.rejects(execFileAsync("bash", [runnerPath, "--test-validate-approval", ""]));
});

test("canary runner dotenv parser는 배포 parser와 동일하게 외부 따옴표를 제거한다", async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), "route-canary-env-"));
  const envPath = path.join(tempDir, "compose.env");
  try {
    await writeFile(envPath, [
      'EASYSUBWAY_ROUTE_V2_SESSION_BURST="2"',
      "",
    ].join("\n"));
    const key = await execFileAsync("bash", [
      runnerPath,
      "--test-read-env-value",
      envPath,
      "EASYSUBWAY_ROUTE_V2_SESSION_BURST",
    ]);
    assert.equal(key.stdout, "2\n");
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test("canary runner dotenv parser는 중복 정의된 키를 fail-closed로 거부한다", async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), "route-canary-env-dup-"));
  const envPath = path.join(tempDir, "compose.env");
  try {
    await writeFile(envPath, [
      "EASYSUBWAY_ROUTE_V2_SESSION_BURST=1",
      "EASYSUBWAY_ROUTE_V2_SESSION_BURST=2",
      "",
    ].join("\n"));
    await assert.rejects(
      execFileAsync("bash", [
        runnerPath,
        "--test-read-env-value",
        envPath,
        "EASYSUBWAY_ROUTE_V2_SESSION_BURST",
      ]),
    );
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test("canary runner dotenv parser는 키가 없으면 fail-closed로 거부한다", async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), "route-canary-env-missing-"));
  const envPath = path.join(tempDir, "compose.env");
  try {
    await writeFile(envPath, "EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET=unrelated\n");
    await assert.rejects(
      execFileAsync("bash", [
        runnerPath,
        "--test-read-env-value",
        envPath,
        "EASYSUBWAY_ROUTE_V2_SESSION_BURST",
      ]),
    );
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test("canary runner --test-expected-candidate는 정합된 operations-release-evidence.json과 timetable evidence에서 checked-in RC candidate를 resolve한다", async () => {
  // apps/mobile/release/operations-release-evidence.json's
  // routeV2Readiness.timetableSnapshotCache.currentImplementation is now
  // reconciled with the checked-in timetable evidence file this runner actually
  // reads (backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json)
  // — the earlier known drift was reconciled in #2095. resolveExpectedCandidate()
  // therefore resolves the SAME checked-in RC candidate from the two matching
  // evidences instead of fail-closing on a snapshot mismatch.
  const [operations, timetable] = await Promise.all([
    readFile(operationsEvidencePath, "utf8").then(JSON.parse),
    readFile(timetableEvidencePath, "utf8").then(JSON.parse),
  ]);
  const resolved = resolveExpectedCandidate(operations, timetable);
  assert.equal(resolved.timetableSnapshotId, timetable.snapshotId);
  assert.equal(resolved.timetableSnapshotSha256, timetable.snapshotSha256);
  assert.equal(
    resolved.backendDeploySha,
    operations.backendControlPlane.publicApiSurface.routeV2Readiness.realisticLoadEvidence.candidate
      .candidateGitSha,
  );
  await execFileAsync("bash", [runnerPath, "--test-expected-candidate"]);
});

test("resolveExpectedCandidate는 operations-release-evidence.json과 timetable evidence의 snapshot 일치 여부를 검증한다", () => {
  const buildOperations = (timetableSnapshotCache) => ({
    backendControlPlane: {
      publicApiSurface: {
        routeV2Readiness: {
          realisticLoadEvidence: {
            candidate: { candidateGitSha: "a".repeat(40), versionName: "1.0.5", versionCode: 10006 },
          },
          timetableSnapshotCache,
        },
      },
    },
  });
  const boundSnapshot = { snapshotSha256: "b".repeat(64), freshUntil: "2026-07-20T00:00:00+09:00" };
  const operations = buildOperations({ currentImplementation: boundSnapshot });
  const matchingTimetable = {
    snapshotId: "server-timetable-snapshot-x",
    snapshotSha256: "b".repeat(64),
    // Same instant as boundSnapshot.freshUntil (2026-07-20T00:00:00+09:00),
    // represented in UTC — proves the cross-check compares instants, not text.
    freshUntil: "2026-07-19T15:00:00Z",
  };
  const resolved = resolveExpectedCandidate(operations, matchingTimetable);
  assert.equal(resolved.timetableSnapshotSha256, "b".repeat(64));

  const mismatchedSha = { ...matchingTimetable, snapshotSha256: "c".repeat(64) };
  assert.throws(
    () => resolveExpectedCandidate(operations, mismatchedSha),
    /timetableSnapshotCache does not match the timetable evidence file/,
  );

  const mismatchedFreshUntil = { ...matchingTimetable, freshUntil: "2026-07-19T15:00:01Z" };
  assert.throws(
    () => resolveExpectedCandidate(operations, mismatchedFreshUntil),
    /timetableSnapshotCache does not match the timetable evidence file/,
  );

  const missingBoundSnapshot = buildOperations(undefined);
  assert.throws(
    () => resolveExpectedCandidate(missingBoundSnapshot, matchingTimetable),
    /timetableSnapshotCache does not match the timetable evidence file/,
  );
});

test("canary runner는 잘못된 SHA·승인·candidate에서 production 접근 전에 fail-closed한다", async () => {
  const nonMatchingSha = "0".repeat(40);
  // invalid SHA format
  await assert.rejects(
    execFileAsync("bash", [runnerPath], {
      env: { ...process.env, EXPECTED_DEPLOYED_SHA: "not-a-sha", PRODUCTION_CANARY_APPROVAL: validApproval },
    }),
    (error) => error.code === 2,
  );
  // valid SHA format, missing approval
  await assert.rejects(
    execFileAsync("bash", [runnerPath], {
      env: { ...process.env, EXPECTED_DEPLOYED_SHA: nonMatchingSha, PRODUCTION_CANARY_APPROVAL: "" },
    }),
    (error) => error.code === 2,
  );
  // valid SHA + approval, but SHA does not match the checked-in RC candidate
  await assert.rejects(
    execFileAsync("bash", [runnerPath], {
      env: { ...process.env, EXPECTED_DEPLOYED_SHA: nonMatchingSha, PRODUCTION_CANARY_APPROVAL: validApproval },
    }),
    (error) => error.code === 2,
  );
});

test("evaluateCanaryBudgets는 normal profile의 200 성공을 강제하고 예산 위반을 구분한다", () => {
  const budget = { p95MaxMs: 2000, p99MaxMs: 5000, maxUnexpectedErrors: 0, requireNoStore: true, requireLimitEngaged: true };
  const healthy = evaluateCanaryBudgets(
    [
      { profile: "normal", status: 200, latencyMs: 120, cacheControl: "private, no-store" },
      { profile: "normal", status: 200, latencyMs: 180, cacheControl: "private, no-store" },
      { profile: "burst", status: 429, latencyMs: 90, cacheControl: "private, no-store" },
    ],
    budget,
  );
  assert.equal(healthy.withinBudget, true);
  assert.deepEqual(healthy.breaches, []);
  assert.equal(healthy.summary.limitEngaged, true);
  assert.equal(healthy.summary.failedNormalSampleCount, 0);

  // A canary whose EVERY normal-profile response was rejected (e.g. every
  // attestation denied with 403) must NOT pass just because one burst request
  // got rate-limited to 429 — this was the vacuous-pass gap.
  const allNormalRejected = evaluateCanaryBudgets(
    [
      { profile: "normal", status: 403, latencyMs: 90, cacheControl: "private, no-store" },
      { profile: "normal", status: 403, latencyMs: 95, cacheControl: "private, no-store" },
      { profile: "burst", status: 429, latencyMs: 80, cacheControl: "private, no-store" },
    ],
    budget,
  );
  assert.equal(allNormalRejected.withinBudget, false);
  assert.equal(allNormalRejected.summary.failedNormalSampleCount, 2);
  assert.ok(allNormalRejected.breaches.some((b) => /did not return exact HTTP 200/.test(b)));

  const slow = evaluateCanaryBudgets(
    [{ profile: "normal", status: 200, latencyMs: 9000, cacheControl: "private, no-store" }, { profile: "burst", status: 429, latencyMs: 80, cacheControl: "private, no-store" }],
    budget,
  );
  assert.equal(slow.withinBudget, false);
  assert.ok(slow.breaches.some((b) => /latency/.test(b)));

  const errored = evaluateCanaryBudgets(
    [{ profile: "normal", status: 500, latencyMs: 100, cacheControl: "private, no-store" }, { profile: "burst", status: 429, latencyMs: 80, cacheControl: "private, no-store" }],
    budget,
  );
  assert.equal(errored.withinBudget, false);
  assert.ok(errored.breaches.some((b) => /error/.test(b)));

  const leaky = evaluateCanaryBudgets(
    [{ profile: "normal", status: 200, latencyMs: 100, cacheControl: "public, max-age=60" }, { profile: "burst", status: 429, latencyMs: 80, cacheControl: "private, no-store" }],
    budget,
  );
  assert.equal(leaky.withinBudget, false);
  assert.ok(leaky.breaches.some((b) => /Cache-Control/.test(b)));

  const noLimit = evaluateCanaryBudgets(
    [{ profile: "normal", status: 200, latencyMs: 100, cacheControl: "private, no-store" }],
    budget,
  );
  assert.equal(noLimit.withinBudget, false);
  assert.ok(noLimit.breaches.some((b) => /limiter/.test(b)));

  // Route search planner identity mismatch is its own breach dimension, distinct
  // from the HTTP status code (a 200 with the WRONG timetable identity must fail).
  const identityMismatch = evaluateCanaryBudgets(
    [
      { profile: "normal", status: 200, latencyMs: 120, cacheControl: "private, no-store" },
      { profile: "normal", status: 200, latencyMs: 130, cacheControl: "private, no-store", plannerIdentityMatch: false },
      { profile: "burst", status: 429, latencyMs: 80, cacheControl: "private, no-store" },
    ],
    budget,
  );
  assert.equal(identityMismatch.withinBudget, false);
  assert.ok(identityMismatch.breaches.some((b) => /planner identity mismatch/.test(b)));

  assert.throws(() => evaluateCanaryBudgets([], budget), /no samples/);
  assert.throws(
    () => evaluateCanaryBudgets([{ profile: "burst", status: 429, latencyMs: 80, cacheControl: "private, no-store" }], budget),
    /normal-profile sample/,
  );
});

test("evaluateCanaryBudgets는 burst의 200/429 외 응답과 curl 전송 실패 sentinel을 breach로 집계한다", () => {
  const budget = { p95MaxMs: 2000, p99MaxMs: 5000, maxUnexpectedErrors: 0, requireNoStore: true, requireLimitEngaged: true };
  const cacheControl = "private, no-store";

  // session normal 200, burst 403·403·429, search normal 200: repeated
  // invalid-attestation burst responses must fail the budget even though one
  // burst request did get rate-limited and both normal-profile requests were
  // exact 200.
  const invalidBurst = evaluateCanaryBudgets(
    [
      { profile: "normal", status: 200, latencyMs: 100, cacheControl },
      { profile: "burst", status: 403, latencyMs: 90, cacheControl },
      { profile: "burst", status: 403, latencyMs: 95, cacheControl },
      { profile: "burst", status: 429, latencyMs: 80, cacheControl },
      { profile: "normal", status: 200, latencyMs: 110, cacheControl },
    ],
    budget,
  );
  assert.equal(invalidBurst.withinBudget, false);
  assert.equal(invalidBurst.summary.invalidBurstSampleCount, 2);
  assert.ok(invalidBurst.breaches.some((b) => /returned neither 200 nor 429/.test(b)));

  // A clean burst batch (only 200s and one 429) must not trip this check.
  const cleanBurst = evaluateCanaryBudgets(
    [
      { profile: "normal", status: 200, latencyMs: 100, cacheControl },
      { profile: "burst", status: 200, latencyMs: 90, cacheControl },
      { profile: "burst", status: 429, latencyMs: 80, cacheControl },
    ],
    budget,
  );
  assert.equal(cleanBurst.withinBudget, true);
  assert.equal(cleanBurst.summary.invalidBurstSampleCount, 0);

  // status 0 is the bash runner's curl transport-failure sentinel (curl's own
  // "000" for a DNS/TLS/connect/timeout that never reached the server) — it
  // must be accepted by normalizeSample (not throw) and scored as a breach,
  // not silently ignored, for both normal and burst profiles.
  const transportFailureNormal = evaluateCanaryBudgets(
    [
      { profile: "normal", status: 0, latencyMs: 0, cacheControl: "" },
      { profile: "burst", status: 429, latencyMs: 80, cacheControl },
    ],
    budget,
  );
  assert.equal(transportFailureNormal.withinBudget, false);
  assert.equal(transportFailureNormal.summary.failedNormalSampleCount, 1);

  const transportFailureBurst = evaluateCanaryBudgets(
    [
      { profile: "normal", status: 200, latencyMs: 100, cacheControl },
      { profile: "burst", status: 0, latencyMs: 0, cacheControl: "" },
      { profile: "burst", status: 429, latencyMs: 80, cacheControl },
    ],
    budget,
  );
  assert.equal(transportFailureBurst.withinBudget, false);
  assert.equal(transportFailureBurst.summary.invalidBurstSampleCount, 1);
});

test("evaluateCanaryBudgets는 normal·burst가 동일 limiter key를 공유하는 실측 설계에서 오탐 breach되지 않는다", () => {
  const budget = { p95MaxMs: 2000, p99MaxMs: 5000, maxUnexpectedErrors: 0, requireNoStore: true, requireLimitEngaged: true };
  const cacheControl = "private, no-store";
  // Real design: 1 normal request, then configured-burst+1 burst requests
  // against the SAME real limiter key (the runner's own source IP — see
  // tools/ops/verify-production-route-v2-canary-rollback.sh, since
  // CF-Connecting-IP is not trusted on the public edge). With
  // EASYSUBWAY_ROUTE_V2_SESSION_BURST=2, that is 1 normal + 3 burst = 4 total
  // requests, where the burst allowance is exceeded on the last one.
  const sharedKeyRun = evaluateCanaryBudgets(
    [
      { profile: "normal", status: 200, latencyMs: 100, cacheControl },
      { profile: "burst", status: 200, latencyMs: 90, cacheControl },
      { profile: "burst", status: 200, latencyMs: 95, cacheControl },
      { profile: "burst", status: 429, latencyMs: 80, cacheControl },
    ],
    budget,
  );
  assert.equal(sharedKeyRun.withinBudget, true);
  assert.deepEqual(sharedKeyRun.breaches, []);
  assert.equal(sharedKeyRun.summary.normalSampleCount, 1);
  assert.equal(sharedKeyRun.summary.failedNormalSampleCount, 0);
  assert.equal(sharedKeyRun.summary.limitEngaged, true);

  // If the single normal request itself lands on an already-partially-consumed
  // shared budget (e.g. immediately after a prior run) and is rejected, that is
  // scored as a real breach (fail-safe: close ingress) rather than silently
  // ignored — the shared key does not weaken the "at least one clean success"
  // requirement, it only changes how many normal samples are sent.
  const normalItselfLimited = evaluateCanaryBudgets(
    [
      { profile: "normal", status: 429, latencyMs: 80, cacheControl },
      { profile: "burst", status: 429, latencyMs: 80, cacheControl },
    ],
    budget,
  );
  assert.equal(normalItselfLimited.withinBudget, false);
  assert.ok(normalItselfLimited.breaches.some((b) => /did not return exact HTTP 200/.test(b)));
});

test("assertCandidateMatch와 validateApprovalReference는 fail-closed다", () => {
  const candidate = {
    backendDeploySha: "a".repeat(40),
    mobileVersionName: "1.0.5",
    mobileVersionCode: 10006,
    timetableSnapshotId: "server-timetable-snapshot-x",
    timetableSnapshotSha256: "b".repeat(64),
    timetableFreshUntil: "2026-07-20T00:00:00+09:00",
  };
  assert.equal(assertCandidateMatch({ ...candidate }, candidate), true);
  assert.throws(() => assertCandidateMatch({ ...candidate, mobileVersionCode: 10007 }, candidate), /same candidate identity/);
  assert.throws(() => validateApprovalReference("not-a-url"), /approval reference/);
  assert.equal(validateApprovalReference(validApproval), validApproval);

  // timetableFreshUntil represents one instant: the live production DB query
  // renders it in UTC ("...Z"), the checked-in RC evidence keeps its original
  // zone offset — the SAME instant in a different representation must match.
  const utcCandidate = { ...candidate, timetableFreshUntil: "2026-07-19T15:00:00Z" };
  assert.equal(assertCandidateMatch(utcCandidate, candidate), true);
  // A genuinely different instant (even by one second) must still mismatch.
  const differentInstant = { ...candidate, timetableFreshUntil: "2026-07-19T15:00:01Z" };
  assert.throws(
    () => assertCandidateMatch(differentInstant, candidate),
    /same candidate identity; mismatched fields: timetableFreshUntil/,
  );
  // An unparseable value must fail closed, not silently pass.
  const unparseable = { ...candidate, timetableFreshUntil: "not-a-date" };
  assert.throws(
    () => assertCandidateMatch(unparseable, candidate),
    /same candidate identity; mismatched fields: timetableFreshUntil/,
  );
});

test("parseCanaryIntegrityTokens는 #1016의 실행-시점 attestation 입력 계약(freshness·provisioning evidence)을 강제한다", () => {
  const now = Date.parse("2026-07-20T02:00:00.000Z");
  const mintedAt = "2026-07-20T01:59:30.000Z"; // 30 seconds before `now`, within the 60-second window
  const [nonce0, nonce1, nonce2] = [makeNonce(), makeNonce(), makeNonce()];
  const payload = JSON.stringify({
    mintedAt,
    mobileVersionName: "1.0.5",
    mobileVersionCode: 10006,
    pairs: [
      { integrityToken: "token-0", clientNonce: nonce0 },
      { integrityToken: "token-1", clientNonce: nonce1 },
      { integrityToken: "token-2", clientNonce: nonce2 },
    ],
  });
  const result = parseCanaryIntegrityTokens(payload, 2, { now });
  assert.deepEqual(result, {
    mintedAt,
    mobileVersionName: "1.0.5",
    mobileVersionCode: 10006,
    pairs: [
      { integrityToken: "token-0", clientNonce: nonce0 },
      { integrityToken: "token-1", clientNonce: nonce1 },
    ],
  });

  assert.throws(() => parseCanaryIntegrityTokens("not-json", 1, { now }), /not valid JSON/);
  assert.throws(
    () => parseCanaryIntegrityTokens(JSON.stringify({ mobileVersionName: "1.0.5", mobileVersionCode: 10006, pairs: [] }), 1, { now }),
    /mintedAt/,
  );
  // A pool minted 90 seconds before now (past the 60-second window, but still
  // WELL within the backend's 2-minute verdict acceptance window) must be
  // rejected here — that is the entire point of finding #3: this gate must be
  // strictly tighter than the backend's own limit, accounting for the gate-to
  // -last-request latency of the canary loop, not merely "not yet expired".
  const barelyStalePayload = JSON.stringify({
    mintedAt: "2026-07-20T01:58:30.000Z",
    mobileVersionName: "1.0.5",
    mobileVersionCode: 10006,
    pairs: [{ integrityToken: "token-0", clientNonce: makeNonce() }],
  });
  assert.throws(() => parseCanaryIntegrityTokens(barelyStalePayload, 1, { now }), /within 60 second/);
  // A pool "minted" in the future (clock skew or bad input) must also fail closed.
  const futurePayload = JSON.stringify({
    mintedAt: "2026-07-20T02:05:00.000Z",
    mobileVersionName: "1.0.5",
    mobileVersionCode: 10006,
    pairs: [{ integrityToken: "token-0", clientNonce: makeNonce() }],
  });
  assert.throws(() => parseCanaryIntegrityTokens(futurePayload, 1, { now }), /within 60 second/);

  assert.throws(
    () => parseCanaryIntegrityTokens(JSON.stringify({ mintedAt, mobileVersionCode: 10006, pairs: [] }), 1, { now }),
    /mobileVersionName/,
  );
  assert.throws(
    () => parseCanaryIntegrityTokens(JSON.stringify({ mintedAt, mobileVersionName: "1.0.5", mobileVersionCode: 0, pairs: [] }), 1, { now }),
    /mobileVersionCode/,
  );
  assert.throws(
    () => parseCanaryIntegrityTokens(JSON.stringify({ mintedAt, mobileVersionName: "1.0.5", mobileVersionCode: 10006, pairs: [] }), 1, { now }),
    /at least 1 pair/,
  );
  assert.throws(
    () => parseCanaryIntegrityTokens(JSON.stringify({ mintedAt, mobileVersionName: "1.0.5", mobileVersionCode: 10006, pairs: [{ clientNonce: makeNonce() }] }), 1, { now }),
    /integrityToken/,
  );
  assert.throws(
    () => parseCanaryIntegrityTokens(JSON.stringify({ mintedAt, mobileVersionName: "1.0.5", mobileVersionCode: 10006, pairs: [{ integrityToken: "token-0" }] }), 1, { now }),
    /clientNonce/,
  );
  assert.throws(() => parseCanaryIntegrityTokens(validPoolPayload(), 0), /requiredCount/);

  // Defaults to Date.now() when `now` is not supplied (real runner path) — a
  // freshly-minted payload must pass without needing to inject a clock.
  const liveResult = parseCanaryIntegrityTokens(validPoolPayload({ pairCount: 1 }), 1);
  assert.equal(liveResult.pairs.length, 1);
});

test("parseCanaryIntegrityTokens는 backend와 동일한 clientNonce 형식·pool 내 유일성을 강제한다", () => {
  const mintedAt = new Date().toISOString();
  const buildPayload = (pairs) => JSON.stringify({ mintedAt, mobileVersionName: "1.0.5", mobileVersionCode: 10006, pairs });

  // Too short / wrong alphabet / wrong length are all rejected — backend
  // requires exactly 22 base64url characters decoding to 16 bytes.
  assert.throws(
    () => parseCanaryIntegrityTokens(buildPayload([{ integrityToken: "token-0", clientNonce: "too-short" }]), 1),
    /pair\[0\]\.clientNonce must be a 22-character base64url value/,
  );
  assert.throws(
    () => parseCanaryIntegrityTokens(buildPayload([{ integrityToken: "token-0", clientNonce: `${"a".repeat(21)}!` }]), 1),
    /pair\[0\]\.clientNonce must be a 22-character base64url value/,
  );
  assert.throws(
    () => parseCanaryIntegrityTokens(buildPayload([{ integrityToken: "token-0", clientNonce: makeNonce() + "AB" }]), 1),
    /pair\[0\]\.clientNonce must be a 22-character base64url value/,
  );

  // A genuinely valid 22-character base64url nonce passes.
  const validNonce = makeNonce();
  const passed = parseCanaryIntegrityTokens(buildPayload([{ integrityToken: "token-0", clientNonce: validNonce }]), 1);
  assert.equal(passed.pairs[0].clientNonce, validNonce);

  // A duplicated nonce anywhere in the pool (not just within the consumed
  // subset) is rejected — matches the backend's own nonce-replay rejection,
  // and this repo's runner would otherwise burn a "budget breach" verdict on
  // an otherwise-healthy candidate purely from a provisioning bug.
  const duplicateNonce = makeNonce();
  assert.throws(
    () => parseCanaryIntegrityTokens(
      buildPayload([
        { integrityToken: "token-0", clientNonce: duplicateNonce },
        { integrityToken: "token-1", clientNonce: makeNonce() },
        { integrityToken: "token-2", clientNonce: duplicateNonce },
      ]),
      2,
    ),
    /pair\[2\]\.clientNonce is duplicated within the pool/,
  );
  // The duplicate is rejected even when only the FIRST (not the duplicated)
  // pair would actually be consumed — the whole pool is validated up front.
  assert.throws(
    () => parseCanaryIntegrityTokens(
      buildPayload([
        { integrityToken: "token-0", clientNonce: duplicateNonce },
        { integrityToken: "token-1", clientNonce: duplicateNonce },
        { integrityToken: "token-2", clientNonce: makeNonce() },
      ]),
      1,
    ),
    /pair\[1\]\.clientNonce is duplicated within the pool/,
  );

  // The SAME integrityToken paired with two DIFFERENT (each individually
  // valid) nonces is also rejected: the token's underlying request hash can
  // only match ONE of those nonces server-side, so at least one canary
  // request would get a 403 from an otherwise-healthy backend — misread as a
  // budget breach that closes production ingress over a provisioning bug.
  assert.throws(
    () => parseCanaryIntegrityTokens(
      buildPayload([
        { integrityToken: "shared-token", clientNonce: makeNonce() },
        { integrityToken: "shared-token", clientNonce: makeNonce() },
      ]),
      2,
    ),
    /pair\[1\]\.integrityToken is duplicated within the pool/,
  );
});

test("buildCanaryRollbackEvidence는 시간순 timeline과 rollback 일관성을 강제한다", () => {
  const candidate = {
    backendDeploySha: "a".repeat(40),
    mobileVersionName: "1.0.5",
    mobileVersionCode: 10006,
    timetableSnapshotId: "server-timetable-snapshot-x",
    timetableSnapshotSha256: "b".repeat(64),
    timetableFreshUntil: "2026-07-20T00:00:00+09:00",
  };
  const priorApprovedState = { backendDeploySha: "a".repeat(40), backendImageDigest: `sha256:${"c".repeat(64)}`, ingressEnabled: false };
  const budget = { p95MaxMs: 2000, p99MaxMs: 5000 };
  const passResult = { withinBudget: true, breaches: [], summary: { sampleCount: 3 } };
  const base = 1_760_000_000_000;
  const iso = (offset) => new Date(base + offset).toISOString();
  const passStages = {
    candidate_verified: iso(0),
    prior_approved_state_recorded: iso(1000),
    canary_started: iso(2000),
    canary_completed: iso(3000),
    budget_evaluated: iso(4000),
    rollback_dry_run_started: iso(5000),
    ingress_closed: iso(5500),
    ingress_restored: iso(6000),
    rollback_verified: iso(6500),
    evidence_emitted: iso(7000),
  };
  // Healthy canary: ingress_closed is ALWAYS required (the rollback is a real
  // rehearsal, not a no-op), and ingress_restored is required because the
  // rehearsal restores ingress after proving the close works.
  const passEvidence = buildCanaryRollbackEvidence({
    candidate,
    publicBaseUrl: "https://easysubway-api.aquilaxk.site",
    approvalReference: validApproval,
    ingressWasOpen: true,
    budget,
    budgetResult: passResult,
    restoredAfterRehearsal: true,
    priorApprovedState,
    stages: passStages,
  });
  assert.equal(passEvidence.rollbackDryRun.trigger, "rehearsal");
  assert.equal(passEvidence.rollbackDryRun.ingressClosed, true);
  assert.equal(passEvidence.rollbackDryRun.restoredAfterRehearsal, true);
  assert.equal(passEvidence.timeline.length, CANARY_TIMELINE_STAGES.length);
  assert.deepEqual(passEvidence.sameCandidateIdentity, candidate);

  // Budget breach path: ingress_closed required, ingress_restored FORBIDDEN (the
  // breach path never restores — it leaves ingress at the prior approved/closed
  // posture).
  const breachResult = { withinBudget: false, breaches: ["p95 latency 9000ms exceeds 2000ms"], summary: { sampleCount: 3 } };
  const breachStages = { ...passStages, ingress_restored: undefined };
  delete breachStages.ingress_restored;
  const breachEvidence = buildCanaryRollbackEvidence({
    candidate,
    publicBaseUrl: "https://easysubway-api.aquilaxk.site",
    approvalReference: validApproval,
    ingressWasOpen: true,
    budget,
    budgetResult: breachResult,
    restoredAfterRehearsal: false,
    priorApprovedState,
    stages: breachStages,
  });
  assert.equal(breachEvidence.rollbackDryRun.trigger, "budget-breach");
  assert.equal(breachEvidence.rollbackDryRun.ingressClosed, true);
  assert.equal(breachEvidence.rollbackDryRun.restoredAfterRehearsal, false);
  assert.ok(breachEvidence.timeline.some((entry) => entry.stage === "ingress_closed"));
  assert.ok(!breachEvidence.timeline.some((entry) => entry.stage === "ingress_restored"));

  // ingress_closed is now ALWAYS required, regardless of outcome.
  const noCloseStages = { ...passStages };
  delete noCloseStages.ingress_closed;
  assert.throws(
    () => buildCanaryRollbackEvidence({
      candidate, publicBaseUrl: "https://easysubway-api.aquilaxk.site", approvalReference: validApproval,
      ingressWasOpen: true, budget, budgetResult: passResult, restoredAfterRehearsal: true, priorApprovedState,
      stages: noCloseStages,
    }),
    /timeline is missing required stage: ingress_closed/,
  );
  // A healthy canary that claims it did NOT restore is rejected (must tie
  // withinBudget to restoredAfterRehearsal 1:1).
  assert.throws(
    () => buildCanaryRollbackEvidence({
      candidate, publicBaseUrl: "https://easysubway-api.aquilaxk.site", approvalReference: validApproval,
      ingressWasOpen: true, budget, budgetResult: passResult, restoredAfterRehearsal: false, priorApprovedState,
      stages: breachStages,
    }),
    /must restore ingress/,
  );
  // A breach that claims it restored is rejected too.
  assert.throws(
    () => buildCanaryRollbackEvidence({
      candidate, publicBaseUrl: "https://easysubway-api.aquilaxk.site", approvalReference: validApproval,
      ingressWasOpen: true, budget, budgetResult: breachResult, restoredAfterRehearsal: true, priorApprovedState,
      stages: passStages,
    }),
    /must not restore it/,
  );
  // out-of-order timeline -> reject.
  assert.throws(
    () => buildCanaryRollbackEvidence({
      candidate, publicBaseUrl: "https://easysubway-api.aquilaxk.site", approvalReference: validApproval,
      ingressWasOpen: true, budget, budgetResult: passResult, restoredAfterRehearsal: true, priorApprovedState,
      stages: { ...passStages, evidence_emitted: iso(-1000) },
    }),
    /chronological order/,
  );
  // missing approval -> reject.
  assert.throws(
    () => buildCanaryRollbackEvidence({
      candidate, publicBaseUrl: "https://easysubway-api.aquilaxk.site", approvalReference: "nope",
      ingressWasOpen: true, budget, budgetResult: passResult, restoredAfterRehearsal: true, priorApprovedState, stages: passStages,
    }),
    /approval reference/,
  );
});
