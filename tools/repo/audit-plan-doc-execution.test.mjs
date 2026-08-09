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
  parseClosingIssues,
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
      closingIssues: record.relation === "CLOSES" ? [{ number: record.issueNumber, state: "CLOSED" }] : [],
    })),
    self: {
      issueNumber: scope.self.issueNumber,
      prNumber: 2798,
      repository: scope.executionRepository,
      mergeSha: SHA,
      mergedAt: OBSERVED_AT,
      changedFiles: ["contracts/documentation/plan-doc-execution-audit-scope.json"],
      relationText: `Closes #${scope.self.issueNumber}`,
      closingIssues: [{ number: scope.self.issueNumber, state: "CLOSED" }],
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
  live.records[4].closingIssues = [{ number: 9999, state: "CLOSED" }];
  live.records[0].closingIssues = [{ number: 2748, state: "CLOSED" }];
  live.records[5].relationText = `Fixes #${SCOPE.historical[5].issueNumber}`;

  assert.deepEqual(
    auditPlanDocExecution({ scope: SCOPE, sourceSha: SHA, live }).map(({ code, identity }) => [code, identity]),
    [
      ["EXECUTION_REPOSITORY_MISMATCH", "pr:2755"],
      ["MERGE_SHA_MISMATCH", "pr:2749"],
      ["RELATION_MISMATCH", "pr:2749"],
      ["RELATION_MISMATCH", "pr:2757"],
      ["RELATION_MISMATCH", "pr:2761"],
      ["RELATION_MISMATCH", "pr:2763"],
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

test("plan-doc execution audit preserves both sides of a rename without treating one PR file as two", async () => {
  const recordByPr = new Map(SCOPE.historical.map((record) => [record.prNumber, record]));
  const provider = async ([, endpoint]) => {
    if (endpoint === `repos/AquilaXk/easysubway/commits/${SHA}/pulls`) return JSON.stringify([{ number: 2798 }]);
    const prMatch = endpoint.match(/^repos\/AquilaXk\/easysubway\/pulls\/(\d+)$/);
    if (prMatch != null) {
      const prNumber = Number(prMatch[1]);
      const record = recordByPr.get(prNumber) ?? { issueNumber: 2797, relation: "CLOSES", mergeSha: SHA };
      return JSON.stringify({ number: prNumber, merged: true, merge_commit_sha: record.mergeSha, base: { repo: { full_name: SCOPE.executionRepository } }, changed_files: 1, body: record.relation === "CLOSES" ? `Closes #${record.issueNumber}` : `Refs #${record.issueNumber}`, merged_at: OBSERVED_AT });
    }
    const filesMatch = endpoint.match(/^repos\/AquilaXk\/easysubway\/pulls\/(\d+)\/files\?per_page=100&page=(\d+)$/);
    if (filesMatch != null) {
      if (Number(filesMatch[2]) !== 1) return "[]";
      return JSON.stringify(Number(filesMatch[1]) === 2749
        ? [{ filename: "contracts/documentation/renamed.json", previous_filename: "apps/mobile/lib/old.dart" }]
        : [{ filename: "contracts/documentation/example.json" }]);
    }
    throw new Error(`unexpected provider request: ${endpoint}`);
  };

  const graphql = async (prNumber) => {
    const record = recordByPr.get(prNumber) ?? { issueNumber: 2797, relation: "CLOSES", mergeSha: SHA };
    return JSON.stringify({ data: { repository: { pullRequest: {
      number: prNumber, merged: true, mergeCommit: { oid: record.mergeSha },
      closingIssuesReferences: { totalCount: record.relation === "CLOSES" ? 1 : 0, pageInfo: { hasNextPage: false }, nodes: record.relation === "CLOSES" ? [{ number: record.issueNumber, state: "CLOSED", repository: { nameWithOwner: SCOPE.executionRepository } }] : [] },
    } } } });
  };

  const live = await collectPlanDocExecutionLive({ scope: SCOPE, sourceSha: SHA, execGh: provider, execGraphql: graphql });
  assert.deepEqual(live.records[0].changedFiles, ["apps/mobile/lib/old.dart", "contracts/documentation/renamed.json"]);
  assert.deepEqual(auditPlanDocExecution({ scope: SCOPE, sourceSha: SHA, live }).filter(({ code }) => code === "TARGET_PATH_MODIFICATION"), [{ code: "TARGET_PATH_MODIFICATION", identity: "pr:2749:apps/mobile/lib/old.dart" }]);
});

test("plan-doc execution audit accepts a GitHub-shaped null close event only through an exact GraphQL closing reference", async () => {
  const recordByPr = new Map(SCOPE.historical.map((record) => [record.prNumber, record]));
  const provider = async ([, endpoint]) => {
    if (endpoint === `repos/AquilaXk/easysubway/commits/${SHA}/pulls`) return JSON.stringify([{ number: 2798 }]);
    const pr = endpoint.match(/^repos\/AquilaXk\/easysubway\/pulls\/(\d+)$/);
    if (pr != null) {
      const record = recordByPr.get(Number(pr[1])) ?? { issueNumber: 2797, relation: "CLOSES", mergeSha: SHA };
      return JSON.stringify({ number: Number(pr[1]), merged: true, merge_commit_sha: record.mergeSha, base: { repo: { full_name: SCOPE.executionRepository } }, changed_files: 0, body: record.relation === "CLOSES" ? `Closes #${record.issueNumber}` : `Refs #${record.issueNumber}`, merged_at: OBSERVED_AT });
    }
    if (/\/files\?per_page=100&page=1$/.test(endpoint)) return "[]";
    throw new Error(`unexpected REST request: ${endpoint}`);
  };
  const graphql = async (prNumber) => {
    const record = recordByPr.get(prNumber) ?? { issueNumber: 2797, relation: "CLOSES", mergeSha: SHA };
    return JSON.stringify({ data: { repository: { pullRequest: {
      number: prNumber, merged: true, mergeCommit: { oid: record.mergeSha },
      closingIssuesReferences: { totalCount: record.relation === "CLOSES" ? 1 : 0, pageInfo: { hasNextPage: false }, nodes: record.relation === "CLOSES" ? [{ number: record.issueNumber, state: "CLOSED", repository: { nameWithOwner: SCOPE.executionRepository } }] : [] },
    } } } });
  };

  const live = await collectPlanDocExecutionLive({ scope: SCOPE, sourceSha: SHA, execGh: provider, execGraphql: graphql });
  assert.deepEqual(auditPlanDocExecution({ scope: SCOPE, sourceSha: SHA, live }), []);
});

test("plan-doc execution audit fails closed for GraphQL relation provider drift", async () => {
  const valid = JSON.stringify({ data: { repository: { pullRequest: {
    number: 2749, merged: true, mergeCommit: { oid: SCOPE.historical[0].mergeSha },
    closingIssuesReferences: { totalCount: 1, pageInfo: { hasNextPage: false }, nodes: [{ number: 2748, state: "CLOSED", repository: { nameWithOwner: SCOPE.executionRepository } }] },
  } } } });
  for (const response of [
    JSON.stringify({ errors: [{ message: "unavailable" }] }),
    JSON.stringify({ data: { repository: { pullRequest: { number: 2749, merged: true, mergeCommit: { oid: SCOPE.historical[0].mergeSha }, closingIssuesReferences: { totalCount: 1, pageInfo: { hasNextPage: false }, nodes: [] } } } } }),
    JSON.stringify({ data: { repository: { pullRequest: { number: 2749, merged: true, mergeCommit: { oid: SCOPE.historical[0].mergeSha }, closingIssuesReferences: { totalCount: 101, pageInfo: { hasNextPage: true }, nodes: [] } } } } }),
    JSON.stringify({ data: { repository: { pullRequest: { number: 2749, merged: true, mergeCommit: { oid: "b".repeat(40) }, closingIssuesReferences: { totalCount: 0, pageInfo: { hasNextPage: false }, nodes: [] } } } } }),
    JSON.stringify({ data: { repository: { pullRequest: { number: 2749, merged: true, mergeCommit: { oid: SCOPE.historical[0].mergeSha }, closingIssuesReferences: { totalCount: 1, pageInfo: { hasNextPage: false }, nodes: [{ number: 2748, state: "CLOSED", repository: { nameWithOwner: "AquilaXk/other" } }] } } } } }),
    JSON.stringify({ data: { repository: { pullRequest: { number: 2749, merged: true, mergeCommit: { oid: SCOPE.historical[0].mergeSha }, closingIssuesReferences: { totalCount: 2, pageInfo: { hasNextPage: false }, nodes: [{ number: 2748, state: "CLOSED", repository: { nameWithOwner: SCOPE.executionRepository } }, { number: 2748, state: "CLOSED", repository: { nameWithOwner: SCOPE.executionRepository } }] } } } } }),
    "{malformed",
  ]) {
    assert.throws(() => parseClosingIssues(response, 2749, SCOPE.historical[0].mergeSha), AuditIncomplete);
  }
  assert.deepEqual(parseClosingIssues(valid, 2749, SCOPE.historical[0].mergeSha), [{ number: 2748, state: "CLOSED" }]);
});

test("plan-doc execution audit report uses the repository codepoint comparator", () => {
  const live = matchingLive();
  live.self.changedFiles = ["contracts/😀.json", "contracts/\uE000.json"];

  const report = createPlanDocExecutionReport({
    scope: SCOPE, scopeText: JSON.stringify(SCOPE), sourceSha: SHA, observedAt: OBSERVED_AT, live,
  });

  assert.deepEqual(
    report.records.find((record) => record.kind === "SELF").changedFiles,
    ["contracts/😀.json", "contracts/\uE000.json"],
  );
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

test("plan-doc execution audit CLI emits one sanitized incomplete report for invalid scope values", async () => {
  const directory = mkdtempSync(join(tmpdir(), "plan-doc-execution-audit-invalid-scope-"));
  const schema = JSON.parse(readFileSync("contracts/documentation/plan-doc-execution-audit-report.schema.json", "utf8"));
  const argv = (name) => [
    "--scope", "scope", "--scope-schema", "scope-schema", "--report-schema", "report-schema",
    "--source-sha", SHA, "--observed-at", OBSERVED_AT, "--output", join(directory, name),
  ];
  const read = async (path) => ({
    "scope-schema": readFileSync("contracts/documentation/plan-doc-execution-audit-scope.schema.json", "utf8"),
    "report-schema": readFileSync("contracts/documentation/plan-doc-execution-audit-report.schema.json", "utf8"),
  })[path];
  try {
    for (const [name, scopeText] of [["invalid", "{"], ["null", "null"], ["missing", "{}"], ["wrong-repository", JSON.stringify({ ...SCOPE, executionRepository: "AquilaXk/easysubway-mobile" })]]) {
      const result = await runAuditCli({ argv: argv(`${name}.json`), read: async (path) => path === "scope" ? scopeText : read(path), collectLive: async () => matchingLive() });
      assert.equal(result.exitCode, 2, name);
      const reportText = readFileSync(join(directory, `${name}.json`), "utf8");
      const report = JSON.parse(reportText);
      assert.equal(validateSchema(schema, report).ok, true, name);
      assert.deepEqual([report.status, report.inputs.executionRepository, report.summary.incomplete], ["AUDIT_INCOMPLETE", "AquilaXk/easysubway", 1], name);
    }
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
