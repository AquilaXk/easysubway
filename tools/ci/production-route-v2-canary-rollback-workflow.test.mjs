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
  assert.match(
    workflow,
    /EXPECTED_DEPLOYED_SHA: \$\{\{ inputs\.deploy_sha != '' && inputs\.deploy_sha \|\| github\.sha \}\}/,
  );
  assert.match(workflow, /PRODUCTION_CANARY_APPROVAL: \$\{\{ inputs\.production_approval \}\}/);
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
  assert.match(workflow, /name: Verify deploy SHA is an ancestor of main/);
  assert.match(
    workflow,
    /if ! git merge-base --is-ancestor "\$\{EXPECTED_DEPLOYED_SHA\}" origin\/main; then/,
  );
  assert.match(workflow, /git checkout --detach "\$\{EXPECTED_DEPLOYED_SHA\}"/);
  assert.ok(
    workflow.indexOf("Verify deploy SHA is an ancestor of main") < workflow.indexOf("Set up Node.js"),
  );
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
  assert.match(runner, /deployed candidate identity does not match the checked-in RC candidate/);
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
  // Ingress-close rollback + timeline evidence.
  assert.match(runner, /printf 'false\\n' > "\$\{ingress_state_file\}"/);
  assert.match(runner, /nginx -s reload/);
  assert.match(runner, /ingress-close rollback did not close the public Route V2 edge/);
  assert.match(runner, /build-evidence/);
  assert.match(runner, /signed-RC canary breached its budget; ingress-close rollback executed/);
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

test("canary runner --test-expected-candidate는 체크인된 RC candidate를 산출한다", async () => {
  const [operations, timetable] = await Promise.all([
    readFile(operationsEvidencePath, "utf8").then(JSON.parse),
    readFile(timetableEvidencePath, "utf8").then(JSON.parse),
  ]);
  const expected = resolveExpectedCandidate(operations, timetable);
  const { stdout } = await execFileAsync("bash", [runnerPath, "--test-expected-candidate"]);
  assert.deepEqual(JSON.parse(stdout), expected);
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

test("evaluateCanaryBudgets는 예산 준수와 위반을 구분한다", () => {
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

  assert.throws(() => evaluateCanaryBudgets([], budget), /no samples/);
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
    rollback_verified: iso(6000),
    evidence_emitted: iso(7000),
  };
  const passEvidence = buildCanaryRollbackEvidence({
    candidate,
    publicBaseUrl: "https://easysubway-api.aquilaxk.site",
    approvalReference: validApproval,
    ingressWasOpen: true,
    budget,
    budgetResult: passResult,
    rollbackExecuted: false,
    priorApprovedState,
    stages: passStages,
  });
  assert.equal(passEvidence.rollbackDryRun.trigger, "rehearsal");
  assert.equal(passEvidence.rollbackDryRun.ingressClosed, false);
  assert.equal(passEvidence.timeline.length, CANARY_TIMELINE_STAGES.length - 1); // no ingress_closed
  assert.deepEqual(passEvidence.sameCandidateIdentity, candidate);

  // Budget breach path requires the ingress_closed stage.
  const breachResult = { withinBudget: false, breaches: ["p95 latency 9000ms exceeds 2000ms"], summary: { sampleCount: 3 } };
  const breachStages = { ...passStages, ingress_closed: iso(5500) };
  const breachEvidence = buildCanaryRollbackEvidence({
    candidate,
    publicBaseUrl: "https://easysubway-api.aquilaxk.site",
    approvalReference: validApproval,
    ingressWasOpen: true,
    budget,
    budgetResult: breachResult,
    rollbackExecuted: true,
    priorApprovedState,
    stages: breachStages,
  });
  assert.equal(breachEvidence.rollbackDryRun.trigger, "budget-breach");
  assert.equal(breachEvidence.rollbackDryRun.ingressClosed, true);
  assert.ok(breachEvidence.timeline.some((entry) => entry.stage === "ingress_closed"));

  // rollback executed but no ingress_closed timestamp -> reject.
  assert.throws(
    () => buildCanaryRollbackEvidence({
      candidate, publicBaseUrl: "https://easysubway-api.aquilaxk.site", approvalReference: validApproval,
      ingressWasOpen: true, budget, budgetResult: breachResult, rollbackExecuted: true, priorApprovedState, stages: passStages,
    }),
    /ingress_closed stage timestamp is missing/,
  );
  // out-of-order timeline -> reject.
  assert.throws(
    () => buildCanaryRollbackEvidence({
      candidate, publicBaseUrl: "https://easysubway-api.aquilaxk.site", approvalReference: validApproval,
      ingressWasOpen: true, budget, budgetResult: passResult, rollbackExecuted: false, priorApprovedState,
      stages: { ...passStages, evidence_emitted: iso(-1000) },
    }),
    /chronological order/,
  );
  // missing approval -> reject.
  assert.throws(
    () => buildCanaryRollbackEvidence({
      candidate, publicBaseUrl: "https://easysubway-api.aquilaxk.site", approvalReference: "nope",
      ingressWasOpen: true, budget, budgetResult: passResult, rollbackExecuted: false, priorApprovedState, stages: passStages,
    }),
    /approval reference/,
  );
});
