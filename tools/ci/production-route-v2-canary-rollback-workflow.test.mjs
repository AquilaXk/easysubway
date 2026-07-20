import assert from "node:assert/strict";
import { execFile } from "node:child_process";
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
  resolveExpectedCandidate,
  validateApprovalReference,
} from "../ops/route-v2-canary-rollback-evidence.mjs";

const workflowPath = ".github/workflows/production-route-v2-canary-rollback-dry-run.yml";
const runnerPath = "tools/ops/verify-production-route-v2-canary-rollback.sh";
const operationsEvidencePath = "apps/mobile/release/operations-release-evidence.json";
const timetableEvidencePath = "backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json";
const pubspecPath = "apps/mobile/pubspec.yaml";
const execFileAsync = promisify(execFile);

const validApproval = "https://github.com/AquilaXk/easysubway/issues/2095";

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
  // canary attestation key는 GitHub Actions secret으로 결속하지 않는다 — 기존
  // capacity workflow가 EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET을 다루는 것과 동일하게,
  // #1016 provisioning 이후 배포된 compose.env에서만 읽는다(러너가 직접 읽음).
  assert.doesNotMatch(workflow, /secrets\.[A-Z0-9_]*CANARY[A-Z0-9_]*/);
  assert.doesNotMatch(workflow, /EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY:\s*\$\{\{\s*secrets\./);
  for (const match of workflow.matchAll(/secrets(?:\.([A-Z0-9_]+)|\[['"]([A-Z0-9_]+)['"]\])/g)) {
    const secretName = match[1] ?? match[2];
    assert.ok(
      secretName === "EASYSUBWAY_ENV" || secretName === "GITHUB_TOKEN",
      `unexpected scoped secret reference: ${secretName}`,
    );
  }
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
    /deployed candidate identity does not match the checked-in RC candidate \(independent Mobile pubspec\.yaml \+ live production timetable identity\)/,
  );
  // #1016 attestation + ingress-open preconditions are fail-closed.
  assert.match(runner, /blocked on #1016/);
  assert.match(runner, /Route V2 ingress must be open for the signed-RC canary/);
  assert.match(runner, /EXPECTED_DEPLOYED_SHA\}" =~ \^\[0-9a-f\]\{40\}\$/);
  assert.match(runner, /PUBLIC_BASE_URL.*==.*https:\/\/easysubway-api\.aquilaxk\.site/);
  // pure-input gate runs before the deploy lock so fail-closed never touches state.
  assert.ok(runner.indexOf("validate-approval") < runner.indexOf('exec 9>"${DEPLOY_ROOT}/deploy.lock"'));
  // canary attestation key is read from the deployed compose.env with the SAME
  // dotenv parser as the capacity runner — never from a GitHub Actions secret.
  assert.match(runner, /compose_env="\$\{DEPLOY_ROOT\}\/shared\/current-env\/compose\.env"/);
  assert.match(runner, /current compose environment is missing/);
  assert.match(
    runner,
    /CANARY_ATTESTATION_KEY="\$\(read_env_value "\$\{compose_env\}" EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY\)"/,
  );
  assert.doesNotMatch(runner, /EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY:-/);
  assert.match(runner, /is defined \$\{match_count\} times in the deployment environment/);

  // Independent candidate identity sources (finding: no more copying `expected`).
  assert.match(runner, /parse_pubspec_version/);
  assert.match(runner, /PUBSPEC_PATH="\$\{REPO_ROOT\}\/apps\/mobile\/pubspec\.yaml"/);
  assert.doesNotMatch(runner, /mobileVersionName: expected\.mobileVersionName/);
  assert.doesNotMatch(runner, /mobileVersionCode: expected\.mobileVersionCode/);
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

  // Route search canary + planner identity cross-check (finding: session-only
  // canary never exercised route search or the active timetable it serves).
  assert.match(runner, /canary_search_sample\(\) \{/);
  assert.match(runner, /\/api\/v2\/routes\/search/);
  assert.match(runner, /plannerIdentityMatch/);
  assert.match(runner, /capture_issued_session/);
  assert.match(runner, /route:v2:itx/);

  // Attestation key is passed via stdin, never as a node -e argv value.
  assert.doesNotMatch(runner, /Buffer\.from\(process\.argv\[1\], "hex"\)/);
  assert.match(runner, /printf '%s' "\$\{CANARY_ATTESTATION_KEY\}" \| node -e/);
  assert.match(runner, /readFileSync\(0, "utf8"\)/);

  // Ingress-close rollback ALWAYS applies the real host Nginx configuration (not
  // just the state marker or a gateway-container-only reload).
  assert.match(runner, /apply_route_v2_host_ingress\(\) \{/);
  assert.match(runner, /__ROUTE_V2_ACTION__/);
  assert.match(runner, /__BACKEND_PORT__/);
  assert.match(runner, /sudo install -m 0644 "\$\{candidate\}" "\$\{site_target\}"/);
  assert.match(runner, /sudo nginx -t/);
  assert.match(runner, /sudo systemctl reload nginx/);
  assert.doesNotMatch(runner, /docker exec easysubway-route-v2-gateway nginx -s reload/);
  assert.match(runner, /route_v2_closed_action="return 404;"/);
  assert.match(runner, /route_v2_open_action="proxy_pass http:\/\/127\.0\.0\.1:\$\{route_v2_gateway_port\};"/);
  assert.match(runner, /printf 'false\\n' > "\$\{ingress_state_file\}"/);
  assert.match(runner, /ingress-close rollback did not close the public Route V2 edge/);

  // Healthy-path REAL close/verify/restore rehearsal — restore only happens when
  // the canary is within budget, and only after the close was verified.
  assert.match(runner, /if \[\[ "\$\{budget_within\}" == true \]\]; then/);
  assert.match(runner, /apply_route_v2_host_ingress "\$\{route_v2_open_action\}"/);
  assert.match(runner, /rollback rehearsal did not restore the public Route V2 edge/);
  assert.match(runner, /restored_after_rehearsal=true/);
  assert.ok(
    runner.indexOf("session_closed=") < runner.indexOf('if [[ "${budget_within}" == true ]]; then'),
  );

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
  assert.doesNotMatch(runner, /echo.*CANARY_ATTESTATION_KEY/);
});

test("canary runner --test-validate-approval는 승인 형식을 강제한다", async () => {
  await execFileAsync("bash", [runnerPath, "--test-validate-approval", validApproval]);
  await assert.rejects(
    execFileAsync("bash", [runnerPath, "--test-validate-approval", "approved-by-owner"]),
  );
  await assert.rejects(execFileAsync("bash", [runnerPath, "--test-validate-approval", ""]));
});

test("canary runner --test-parse-pubspec-version는 Mobile RC 버전을 독립적으로 파싱한다", async () => {
  const { stdout } = await execFileAsync("bash", [runnerPath, "--test-parse-pubspec-version", pubspecPath]);
  const parsed = JSON.parse(stdout);
  assert.match(parsed.versionName, /^\d+\.\d+\.\d+$/);
  assert.ok(Number.isInteger(parsed.versionCode) && parsed.versionCode > 0);

  const tempDir = await mkdtemp(path.join(os.tmpdir(), "route-canary-pubspec-"));
  try {
    const malformedPath = path.join(tempDir, "pubspec.yaml");
    await writeFile(malformedPath, "name: easysubway\nversion: not-a-version\n");
    await assert.rejects(
      execFileAsync("bash", [runnerPath, "--test-parse-pubspec-version", malformedPath]),
    );
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test("canary runner dotenv parser는 배포 parser와 동일하게 외부 따옴표를 제거한다", async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), "route-canary-env-"));
  const envPath = path.join(tempDir, "compose.env");
  try {
    await writeFile(envPath, [
      'EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY="deadbeef"',
      "",
    ].join("\n"));
    const key = await execFileAsync("bash", [
      runnerPath,
      "--test-read-env-value",
      envPath,
      "EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY",
    ]);
    assert.equal(key.stdout, "deadbeef\n");
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test("canary runner dotenv parser는 중복 정의된 키를 fail-closed로 거부한다", async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), "route-canary-env-dup-"));
  const envPath = path.join(tempDir, "compose.env");
  try {
    await writeFile(envPath, [
      "EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY=a",
      "EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY=b",
      "",
    ].join("\n"));
    await assert.rejects(
      execFileAsync("bash", [
        runnerPath,
        "--test-read-env-value",
        envPath,
        "EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY",
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
        "EASYSUBWAY_ROUTE_V2_CANARY_ATTESTATION_KEY",
      ]),
    );
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test("canary runner --test-expected-candidate는 체크인된 RC candidate를 산출하고 pubspec.yaml과 정합한다", async () => {
  const [operations, timetable] = await Promise.all([
    readFile(operationsEvidencePath, "utf8").then(JSON.parse),
    readFile(timetableEvidencePath, "utf8").then(JSON.parse),
  ]);
  const expected = resolveExpectedCandidate(operations, timetable);
  const { stdout } = await execFileAsync("bash", [runnerPath, "--test-expected-candidate"]);
  assert.deepEqual(JSON.parse(stdout), expected);

  // Gate 2 sources the Mobile identity independently from pubspec.yaml — assert
  // it is currently in sync with the checked-in RC candidate (an out-of-sync
  // repo state would legitimately fail-closed at runtime, which is intended).
  const { stdout: pubspecStdout } = await execFileAsync("bash", [
    runnerPath,
    "--test-parse-pubspec-version",
    pubspecPath,
  ]);
  const mobileVersion = JSON.parse(pubspecStdout);
  assert.equal(mobileVersion.versionName, expected.mobileVersionName);
  assert.equal(mobileVersion.versionCode, expected.mobileVersionCode);
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
