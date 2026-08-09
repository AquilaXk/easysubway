import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import {
  AuditIncomplete,
  auditPlanDocExecution,
  collectPlanDocExecutionLive,
  createPlanDocExecutionReport,
  runAuditCli,
  validatePlanDocExecutionScope,
} from "./audit-plan-doc-execution.mjs";

const SCOPE = JSON.parse(readFileSync("contracts/documentation/plan-doc-execution-audit-scope.json", "utf8"));
const SHA = "a".repeat(40);
const OBSERVED_AT = "2026-08-09T00:00:00.000Z";

function matchingLive(scope = SCOPE) {
  return {
    records: scope.historical.map((record) => ({
      ...record,
      repository: scope.executionRepository,
      mergedAt: OBSERVED_AT,
      changedFiles: ["contracts/documentation/example.json"],
      relationText: record.relation === "CLOSES" ? `Closes #${record.issueNumber}` : `Refs #${record.issueNumber}`,
      closedByMerge: record.relation === "CLOSES",
    })),
    self: {
      issueNumber: scope.self.issueNumber,
      prNumber: 2798,
      repository: scope.executionRepository,
      mergeSha: SHA,
      mergedAt: OBSERVED_AT,
      changedFiles: ["contracts/documentation/plan-doc-execution-audit-scope.json"],
      relationText: `Closes #${scope.self.issueNumber}`,
      closedByMerge: true,
    },
  };
}

test("plan-doc execution audit scope fixes the exact historical inventory and self binding", () => {
  assert.deepEqual(validatePlanDocExecutionScope(SCOPE), []);
  for (const mutate of [
    (scope) => { scope.historical[0].mergeSha = "b".repeat(40); },
    (scope) => { scope.historical[1].prNumber = scope.historical[0].prNumber; },
    (scope) => { scope.historical[0].planOwner = "PLAN-REPO"; },
    (scope) => { scope.executionRepository = "AquilaXk/easysubway-mobile"; },
    (scope) => { scope.historical[1].relation = "COORDINATOR_FOLLOWUP"; },
  ]) {
    const invalid = structuredClone(SCOPE);
    mutate(invalid);
    assert.notDeepEqual(validatePlanDocExecutionScope(invalid), []);
  }
});

test("plan-doc execution audit emits concrete findings for merge, relation, repository, and target path drift", () => {
  const live = matchingLive();
  live.records[0].mergeSha = "b".repeat(40);
  live.records[1].repository = "AquilaXk/easysubway-mobile";
  live.records[2].relationText = `Refs #${SCOPE.historical[2].issueNumber}`;
  live.records[3].changedFiles = ["apps/mobile/lib/main.dart"];

  assert.deepEqual(
    auditPlanDocExecution({ scope: SCOPE, sourceSha: SHA, live }).map(({ code, identity }) => [code, identity]),
    [
      ["EXECUTION_REPOSITORY_MISMATCH", "pr:2755"],
      ["MERGE_SHA_MISMATCH", "pr:2749"],
      ["RELATION_MISMATCH", "pr:2757"],
      ["TARGET_PATH_MODIFICATION", "pr:2759:apps/mobile/lib/main.dart"],
    ],
  );
});

test("plan-doc execution audit rejects duplicate PR/SHA and self source to PR to closing issue mismatch", () => {
  const scope = structuredClone(SCOPE);
  scope.historical[1].prNumber = scope.historical[0].prNumber;
  scope.historical[2].mergeSha = scope.historical[0].mergeSha;
  const live = matchingLive(scope);
  live.self.mergeSha = "c".repeat(40);
  live.self.relationText = "Refs #2797";

  const codes = auditPlanDocExecution({ scope, sourceSha: SHA, live }).map(({ code }) => code);
  for (const code of ["DUPLICATE_PR", "DUPLICATE_MERGE_SHA", "SELF_SOURCE_SHA_MISMATCH", "SELF_CLOSING_ISSUE_MISMATCH"]) assert.ok(codes.includes(code));
});

test("plan-doc execution audit fail closes malformed or partial provider responses as AUDIT_INCOMPLETE", async () => {
  const malformed = async () => "{malformed";
  await assert.rejects(
    () => collectPlanDocExecutionLive({ scope: SCOPE, sourceSha: SHA, execGh: malformed }),
    (error) => error.code === "PROVIDER_MALFORMED",
  );

  const partial = async ([, endpoint]) => {
    if (endpoint === "repos/AquilaXk/easysubway/pulls/2749") return JSON.stringify({ number: 2749, merged: true, merge_commit_sha: SCOPE.historical[0].mergeSha, base: { repo: { full_name: "AquilaXk/easysubway" } }, changed_files: 101, body: "Refs #2748" });
    if (endpoint.endsWith("/files?per_page=100&page=1")) return JSON.stringify(Array.from({ length: 100 }, (_, index) => ({ filename: `contracts/${index}.json` })));
    if (endpoint.endsWith("/files?per_page=100&page=2")) return "[]";
    throw new Error("unexpected provider request");
  };
  await assert.rejects(
    () => collectPlanDocExecutionLive({ scope: SCOPE, sourceSha: SHA, execGh: partial }),
    (error) => error.code === "PROVIDER_PARTIAL",
  );

  const report = createPlanDocExecutionReport({
    scope: SCOPE, scopeText: JSON.stringify(SCOPE), sourceSha: SHA, observedAt: OBSERVED_AT,
    incomplete: [{ stage: "github", code: "PROVIDER_MALFORMED", affectedIdentity: "pr:2749" }],
  });
  assert.equal(report.status, "AUDIT_INCOMPLETE");
  assert.equal(report.summary.incomplete, 1);
});

test("plan-doc execution audit CLI writes one schema-valid report for success, finding, and sanitized provider failure", async () => {
  const directory = mkdtempSync(join(tmpdir(), "plan-doc-execution-audit-"));
  const schema = JSON.parse(readFileSync("contracts/documentation/plan-doc-execution-audit-report.schema.json", "utf8"));
  const argv = (name) => [
    "--scope", "contracts/documentation/plan-doc-execution-audit-scope.json",
    "--scope-schema", "contracts/documentation/plan-doc-execution-audit-scope.schema.json",
    "--report-schema", "contracts/documentation/plan-doc-execution-audit-report.schema.json",
    "--source-sha", SHA, "--observed-at", OBSERVED_AT, "--output", join(directory, name),
  ];
  try {
    const success = await runAuditCli({ argv: argv("success.json"), collectLive: async () => matchingLive() });
    assert.equal(success.exitCode, 0);
    assert.equal(validateSchema(schema, JSON.parse(readFileSync(join(directory, "success.json"), "utf8"))).ok, true);

    const findingLive = matchingLive(); findingLive.records[0].changedFiles = ["tools/ops/release.mjs"];
    assert.equal((await runAuditCli({ argv: argv("finding.json"), collectLive: async () => findingLive })).exitCode, 1);
    const finding = JSON.parse(readFileSync(join(directory, "finding.json"), "utf8"));
    assert.equal(validateSchema(schema, finding).ok, true);
    assert.equal(finding.status, "COMPLETE");
    assert.ok(finding.summary.findings > 0);

    assert.equal((await runAuditCli({ argv: argv("failure.json"), collectLive: async () => { throw new Error("provider-secret"); } })).exitCode, 2);
    const failureText = readFileSync(join(directory, "failure.json"), "utf8");
    const failure = JSON.parse(failureText);
    assert.equal(validateSchema(schema, failure).ok, true);
    assert.equal(failure.status, "AUDIT_INCOMPLETE");
    assert.doesNotMatch(failureText, /provider-secret/);

    writeFileSync(join(directory, "exists.json"), "existing\n");
    assert.equal((await runAuditCli({ argv: argv("exists.json"), collectLive: async () => matchingLive() })).exitCode, 2);
    assert.equal(readFileSync(join(directory, "exists.json"), "utf8"), "existing\n");
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
