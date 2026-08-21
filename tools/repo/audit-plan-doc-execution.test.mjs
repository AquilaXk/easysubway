import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { AuditIncomplete, auditPlanDocExecution, collectPlanDocExecutionLive, createPlanDocExecutionReport, parseClosingIssues, runAuditCli, validatePlanDocExecutionScope } from "./audit-plan-doc-execution.mjs";

const SCOPE = JSON.parse(readFileSync("contracts/documentation/plan-doc-execution-audit-scope.json", "utf8"));
const REPORT_SCHEMA = JSON.parse(readFileSync("contracts/documentation/plan-doc-execution-audit-report.schema.json", "utf8"));
const SHA = "a".repeat(40);
const OBSERVED_AT = "2026-08-15T00:00:00.000Z";

function matchingLive(scope = SCOPE) {
  const observed = (record) => ({ issueNumber: record.issueNumber, prNumber: record.prNumber, repository: record.repository, mergeSha: record.mergeSha, changedFiles: [...record.allowedChangedFiles], relationText: record.relation === "CLOSES" ? `Closes #${record.issueNumber}` : `Refs #${record.issueNumber} — coordinator`, closingIssues: record.relation === "CLOSES" ? [{ number: record.issueNumber, state: "CLOSED" }] : [] });
  return { records: scope.historical.map(observed), self: { ...observed({ ...scope.self, prNumber: 9999, mergeSha: SHA, relation: "CLOSES" }), mergeSha: SHA } };
}

test("plan-doc execution audit scope fixes the federated 75-record inventory and self binding", () => {
  assert.equal(SCOPE.schemaVersion, 2);
  assert.equal(SCOPE.historical.length, 75);
  assert.deepEqual(SCOPE.repositories, ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"]);
  assert.equal(SCOPE.self.issueNumber, 2896);
  for (const expected of [
    { repository: "AquilaXk/easysubway", issueNumber: 2886, prNumber: 2887, mergeSha: "995b4ae9913d1256e3933afe401d2a6c559588a3", relation: "CLOSES", planOwner: "PLAN-DOC", changedPathClass: "HUB_GOVERNANCE_ONLY", allowedChangedFiles: ["contracts/documentation/documentation-fragment.json", "contracts/documentation/plan-doc-execution-audit-scope.json", "tools/ci/check-contracts.mjs", "tools/ci/check-contracts.test.mjs", "tools/repo/audit-plan-doc-execution.mjs", "tools/repo/audit-plan-doc-execution.test.mjs"] },
    { repository: "AquilaXk/easysubway-data", issueNumber: 316, prNumber: 317, mergeSha: "4f41584328518046d91312c3bcc78cd4ba40308c", relation: "CLOSES", planOwner: "PLAN-DOC", changedPathClass: "TARGET_DOCUMENTATION_FRAGMENT", allowedChangedFiles: ["contracts/documentation/documentation-fragment.json"] },
    { repository: "AquilaXk/easysubway", issueNumber: 2888, prNumber: 2889, mergeSha: "baa030f5a7bbc431f636079486ddf4289b9c858f", relation: "CLOSES", planOwner: "PLAN-DOC", changedPathClass: "HUB_GOVERNANCE_ONLY", allowedChangedFiles: ["contracts/documentation/plan-doc-execution-audit-scope.json", "tools/ci/check-contracts.mjs", "tools/ci/check-contracts.test.mjs", "tools/repo/audit-plan-doc-execution.mjs", "tools/repo/audit-plan-doc-execution.test.mjs"] },
    { repository: "AquilaXk/easysubway-data", issueNumber: 399, prNumber: 401, mergeSha: "f9885b3c966c6edce4e96552c3de3dd99409bcd6", relation: "CLOSES", planOwner: "PLAN-DOC", changedPathClass: "TARGET_DOCUMENTATION_FRAGMENT", allowedChangedFiles: ["contracts/documentation/documentation-fragment.json"] },
    { repository: "AquilaXk/easysubway-backend", issueNumber: 261, prNumber: 262, mergeSha: "dc5e1d70808711621adcd7aa564973d43b588c2d", relation: "CLOSES", planOwner: "PLAN-DOC", changedPathClass: "TARGET_DOCUMENTATION_FRAGMENT", allowedChangedFiles: ["contracts/documentation/documentation-fragment.json"] },
    { repository: "AquilaXk/easysubway-mobile", issueNumber: 255, prNumber: 256, mergeSha: "6f3333a3b5e639b6bc120b9c51c74838b8ed0a54", relation: "CLOSES", planOwner: "PLAN-DOC", changedPathClass: "TARGET_DOCUMENTATION_FRAGMENT", allowedChangedFiles: ["contracts/documentation/documentation-fragment.json"] },
    { repository: "AquilaXk/easysubway", issueNumber: 2894, prNumber: 2895, mergeSha: "9113a3dab647e270d816272aff1875e9a114dfdf", relation: "CLOSES", planOwner: "PLAN-DOC", changedPathClass: "HUB_GOVERNANCE_ONLY", allowedChangedFiles: ["contracts/documentation/plan-doc-execution-audit-scope.json", "tools/ci/check-contracts.mjs", "tools/ci/check-contracts.test.mjs", "tools/repo/audit-plan-doc-execution.mjs", "tools/repo/audit-plan-doc-execution.test.mjs"] },
    { repository: "AquilaXk/easysubway-data", issueNumber: 406, prNumber: 407, mergeSha: "cb3e7bffacaec936c92c7ef705b70ee6a9f41440", relation: "CLOSES", planOwner: "PLAN-DOC", changedPathClass: "TARGET_DOCUMENTATION_FRAGMENT", allowedChangedFiles: ["contracts/documentation/documentation-fragment.json"] },
  ]) assert.deepEqual(SCOPE.historical.find((record) => record.repository === expected.repository && record.prNumber === expected.prNumber), expected);
  assert.equal(new Set(SCOPE.historical.map((record) => `${record.repository}:${record.prNumber}`)).size, 75);
  assert.equal(new Set(SCOPE.historical.map((record) => `${record.repository}:${record.mergeSha}`)).size, 75);
  assert.equal(SCOPE.historical.some((record) => record.repository === "AquilaXk/easysubway" && record.issueNumber === 2890 && record.prNumber === 2891), false);
  assert.equal(SCOPE.historical.some((record) => record.repository === "AquilaXk/easysubway" && record.issueNumber === 2731 && record.prNumber === 2893), false);
  for (const [repository, issueNumber, prNumber, mergeSha, changedPathClass, allowedChangedFiles] of [["AquilaXk/easysubway", 2881, 2882, "1057c4defa13edc39a631516e463e789857ba854", "HUB_GOVERNANCE_ONLY", ["contracts/documentation/plan-doc-execution-audit-report.schema.json", "contracts/documentation/plan-doc-execution-audit-scope.json", "contracts/documentation/plan-doc-execution-audit-scope.schema.json", "tools/ci/check-contracts.mjs", "tools/ci/check-contracts.test.mjs", "tools/repo/audit-plan-doc-execution.mjs", "tools/repo/audit-plan-doc-execution.test.mjs"]], ["AquilaXk/easysubway-data", 310, 311, "da6b58662a0e84acde1ac1223732e4d3f54874cb", "TARGET_DOCUMENTATION_FRAGMENT", ["contracts/documentation/documentation-fragment.json"]], ["AquilaXk/easysubway", 2884, 2885, "813556b82969ef59ac25cda6318b730dc4c79c0b", "HUB_GOVERNANCE_ONLY", ["contracts/documentation/plan-doc-execution-audit-scope.schema.json", "tools/ci/check-contracts.test.mjs"]]]) assert.deepEqual(SCOPE.historical.find((record) => record.repository === repository && record.prNumber === prNumber), { repository, issueNumber, prNumber, mergeSha, relation: "CLOSES", planOwner: "PLAN-DOC", changedPathClass, allowedChangedFiles });
  assert.deepEqual(SCOPE.self.allowedChangedFiles, ["contracts/documentation/plan-doc-execution-audit-scope.json", "tools/ci/check-contracts.mjs", "tools/ci/check-contracts.test.mjs", "tools/repo/audit-plan-doc-execution.mjs", "tools/repo/audit-plan-doc-execution.test.mjs"]);
  const byIdentity = new Map(SCOPE.historical.map((record) => [`${record.repository}:${record.prNumber}`, record]));
  assert.deepEqual(byIdentity.get("AquilaXk/easysubway:2852").allowedChangedFiles, [".github/workflows/ci.yml", "apps/mobile/pubspec.lock", "apps/mobile/pubspec.yaml", "tools/ci/repository-contract.test.mjs"]);
  assert.equal(byIdentity.get("AquilaXk/easysubway:2852").changedPathClass, "PLAN_DOC_CI_RECOVERY");
  assert.deepEqual(byIdentity.get("AquilaXk/easysubway-backend:248").allowedChangedFiles, ["contracts/documentation/documentation-fragment.json"]);
  assert.deepEqual(validatePlanDocExecutionScope(SCOPE), []);
  const finalReport = createPlanDocExecutionReport({ scope: SCOPE, scopeText: JSON.stringify(SCOPE), sourceSha: SHA, observedAt: OBSERVED_AT, live: matchingLive() });
  assert.deepEqual([finalReport.status, finalReport.summary.records, finalReport.summary.findings, finalReport.summary.incomplete], ["COMPLETE", 76, 0, 0]);
  const invalid = structuredClone(SCOPE); invalid.historical[0].allowedChangedFiles.reverse();
  assert.ok(validatePlanDocExecutionScope(invalid).length > 0);
});

test("plan-doc execution audit uses composite identities, merge deltas, decorated Refs, and exact self files", () => {
  const live = matchingLive();
  const coordinator = live.records.find((record) => record.repository === "AquilaXk/easysubway" && record.prNumber === 2878);
  coordinator.relationText = "Refs #2729 — exact coordinator handoff";
  assert.deepEqual(auditPlanDocExecution({ scope: SCOPE, sourceSha: SHA, live }), []);
  live.records.find((record) => record.repository === "AquilaXk/easysubway-backend" && record.prNumber === 248).changedFiles = ["backend/src/main.java"];
  live.records.find((record) => record.repository === "AquilaXk/easysubway" && record.prNumber === 2878).relationText = "Notes Refs #2729 — inline";
  const findings = auditPlanDocExecution({ scope: SCOPE, sourceSha: SHA, live });
  assert.ok(findings.some((finding) => finding.code === "MERGE_DELTA_MISMATCH" && finding.identity === "AquilaXk/easysubway-backend:248"));
  assert.ok(findings.some((finding) => finding.code === "RELATION_MISMATCH" && finding.identity === "AquilaXk/easysubway:2878"));
});

test("plan-doc execution audit collects a single-parent commit delta instead of PR files", async () => {
  const record = SCOPE.historical.find((value) => value.repository === "AquilaXk/easysubway-backend" && value.prNumber === 248);
  const provider = async ([, endpoint]) => {
    if (endpoint === `repos/${record.repository}/pulls/${record.prNumber}`) return JSON.stringify({ number: record.prNumber, merged: true, merge_commit_sha: record.mergeSha, base: { repo: { full_name: record.repository } }, body: `Closes #${record.issueNumber}` });
    if (endpoint === `repos/${record.repository}/commits/${record.mergeSha}?per_page=100&page=1`) return JSON.stringify({ sha: record.mergeSha, parents: [{ sha: "b".repeat(40) }], files: [{ filename: "contracts/documentation/documentation-fragment.json" }] });
    if (endpoint === `repos/AquilaXk/easysubway/commits/${SHA}/pulls`) return JSON.stringify([{ number: 9999 }]);
    if (endpoint === `repos/AquilaXk/easysubway/pulls/9999`) return JSON.stringify({ number: 9999, merged: true, merge_commit_sha: SHA, base: { repo: { full_name: "AquilaXk/easysubway" } }, body: "Closes #2886" });
    if (endpoint === `repos/AquilaXk/easysubway/commits/${SHA}?per_page=100&page=1`) return JSON.stringify({ sha: SHA, parents: [{ sha: "b".repeat(40) }], files: SCOPE.self.allowedChangedFiles.map((filename) => ({ filename })) });
    throw new Error(`unexpected ${endpoint}`);
  };
  const graphql = async (repository, prNumber) => { const value = repository === record.repository ? record : { issueNumber: 2886, mergeSha: SHA }; return JSON.stringify({ data: { repository: { pullRequest: { number: prNumber, merged: true, mergeCommit: { oid: value.mergeSha }, closingIssuesReferences: { totalCount: 1, pageInfo: { hasNextPage: false }, nodes: [{ number: value.issueNumber, state: "CLOSED", repository: { nameWithOwner: repository } }] } } } } }); };
  const scope = { ...SCOPE, historical: [record] };
  const live = await collectPlanDocExecutionLive({ scope, sourceSha: SHA, execGh: provider, execGraphql: graphql });
  assert.deepEqual(live.records[0].changedFiles, ["contracts/documentation/documentation-fragment.json"]);
  await assert.rejects(() => collectPlanDocExecutionLive({ scope, sourceSha: SHA, execGh: async (args) => args[1].includes(`/commits/${record.mergeSha}?`) ? JSON.stringify({ sha: record.mergeSha, parents: [{}, {}], files: [] }) : provider(args), execGraphql: graphql }), (error) => error instanceof AuditIncomplete && error.code === "COMMIT_MALFORMED");
});

test("plan-doc execution audit fails closed for malformed closing references and reports schema-valid incomplete data", () => {
  assert.throws(() => parseClosingIssues("{", "AquilaXk/easysubway", 1, "a".repeat(40)), AuditIncomplete);
  const report = createPlanDocExecutionReport({ scope: SCOPE, scopeText: JSON.stringify(SCOPE), sourceSha: SHA, observedAt: OBSERVED_AT, incomplete: [{ stage: "github", code: "PROVIDER_PARTIAL", affectedIdentity: "AquilaXk/easysubway:1" }] });
  assert.equal(report.status, "AUDIT_INCOMPLETE");
  assert.equal(validateSchema(REPORT_SCHEMA, report).ok, true);
});

test("plan-doc execution audit accepts only exact decorated coordinator Refs grammar", () => {
  const coordinator = SCOPE.historical.find((record) => record.repository === "AquilaXk/easysubway" && record.prNumber === 2878);
  for (const body of ["Refs #2729", "Refs #2729 — coordinator", "Refs #2729 – coordinator", "Refs #2729 - coordinator", "Refs #2729 : coordinator"]) {
    const live = matchingLive(); live.records.find((record) => record.repository === coordinator.repository && record.prNumber === coordinator.prNumber).relationText = body;
    assert.equal(auditPlanDocExecution({ scope: SCOPE, sourceSha: SHA, live }).some((finding) => finding.identity === `${coordinator.repository}:${coordinator.prNumber}`), false, body);
  }
  for (const body of ["Refs #2729—adjacent", "Refs #2729\t—tab", "Refs #2729\n—newline", "Refs #2729\n  — spaced-newline", "Notes Refs #2729 — inline", "Refs #27290 — similar"]) {
    const live = matchingLive(); live.records.find((record) => record.repository === coordinator.repository && record.prNumber === coordinator.prNumber).relationText = body;
    assert.ok(auditPlanDocExecution({ scope: SCOPE, sourceSha: SHA, live }).some((finding) => finding.code === "RELATION_MISMATCH" && finding.identity === `${coordinator.repository}:${coordinator.prNumber}`), body);
  }
});

test("plan-doc execution audit preserves duplicate, self, GraphQL, commit-page, rename, ordering, and CLI failure protections", async () => {
  const invalidScope = structuredClone(SCOPE);
  invalidScope.historical[1].prNumber = invalidScope.historical[0].prNumber;
  invalidScope.historical[2].mergeSha = invalidScope.historical[0].mergeSha;
  const live = matchingLive(invalidScope);
  live.self.mergeSha = "c".repeat(40);
  live.self.relationText = "Refs #2886";
  const codes = auditPlanDocExecution({ scope: invalidScope, sourceSha: SHA, live }).map((finding) => finding.code);
  for (const code of ["DUPLICATE_RECORD_IDENTITY", "DUPLICATE_MERGE_IDENTITY", "SELF_SOURCE_SHA_MISMATCH", "SELF_CLOSING_ISSUE_MISMATCH"]) assert.ok(codes.includes(code));
  const drift = matchingLive();
  drift.records[0].mergeSha = "d".repeat(40);
  drift.records[1].repository = "AquilaXk/other";
  const driftCodes = auditPlanDocExecution({ scope: SCOPE, sourceSha: SHA, live: drift }).map((finding) => finding.code);
  assert.ok(driftCodes.includes("MERGE_SHA_MISMATCH"));
  assert.ok(driftCodes.includes("EXECUTION_REPOSITORY_MISMATCH"));

  const record = SCOPE.historical.find((value) => value.repository === "AquilaXk/easysubway-backend" && value.prNumber === 248);
  const graphqlError = JSON.stringify({ errors: [{ message: "unavailable" }] });
  assert.throws(() => parseClosingIssues(graphqlError, record.repository, record.prNumber, record.mergeSha), AuditIncomplete);
  assert.throws(() => parseClosingIssues(JSON.stringify({ data: { repository: { pullRequest: { number: record.prNumber, merged: true, mergeCommit: { oid: record.mergeSha }, closingIssuesReferences: { totalCount: 2, pageInfo: { hasNextPage: true }, nodes: [] } } } } }), record.repository, record.prNumber, record.mergeSha), AuditIncomplete);
  for (const response of [
    JSON.stringify({ data: { repository: { pullRequest: { number: record.prNumber, merged: true, mergeCommit: { oid: "e".repeat(40) }, closingIssuesReferences: { totalCount: 0, pageInfo: { hasNextPage: false }, nodes: [] } } } } }),
    JSON.stringify({ data: { repository: { pullRequest: { number: record.prNumber, merged: true, mergeCommit: { oid: record.mergeSha }, closingIssuesReferences: { totalCount: 1, pageInfo: { hasNextPage: false }, nodes: [{ number: record.issueNumber, state: "CLOSED", repository: { nameWithOwner: "AquilaXk/other" } }] } } } } }),
    JSON.stringify({ data: { repository: { pullRequest: { number: record.prNumber, merged: true, mergeCommit: { oid: record.mergeSha }, closingIssuesReferences: { totalCount: 2, pageInfo: { hasNextPage: false }, nodes: [{ number: record.issueNumber, state: "CLOSED", repository: { nameWithOwner: record.repository } }, { number: record.issueNumber, state: "CLOSED", repository: { nameWithOwner: record.repository } }] } } } } }),
    JSON.stringify({ data: { repository: { pullRequest: { number: record.prNumber, merged: true, mergeCommit: { oid: record.mergeSha }, closingIssuesReferences: { totalCount: 1, pageInfo: { hasNextPage: false }, nodes: [{ number: record.issueNumber, state: "OPEN", repository: { nameWithOwner: record.repository } }] } } } } }),
    "{malformed",
  ]) assert.throws(() => parseClosingIssues(response, record.repository, record.prNumber, record.mergeSha), AuditIncomplete);

  const provider = async ([, endpoint]) => {
    if (endpoint === `repos/${record.repository}/pulls/${record.prNumber}`) return JSON.stringify({ number: record.prNumber, merged: true, merge_commit_sha: record.mergeSha, base: { repo: { full_name: record.repository } }, body: `Closes #${record.issueNumber}` });
    if (endpoint === `repos/${record.repository}/commits/${record.mergeSha}?per_page=100&page=1`) return JSON.stringify({ sha: record.mergeSha, parents: [{ sha: "b".repeat(40) }], files: Array.from({ length: 100 }, (_, index) => ({ filename: `contracts/${index}.json` })) });
    if (endpoint === `repos/${record.repository}/commits/${record.mergeSha}?per_page=100&page=2`) return JSON.stringify({ sha: record.mergeSha, parents: [{ sha: "b".repeat(40) }], files: [] });
    throw new Error(`unexpected ${endpoint}`);
  };
  await assert.rejects(() => collectPlanDocExecutionLive({ scope: { ...SCOPE, historical: [record] }, sourceSha: SHA, execGh: provider, execGraphql: async () => "{}" }), (error) => error instanceof AuditIncomplete && error.code === "PROVIDER_PARTIAL");
  const renameProvider = async ([, endpoint]) => endpoint === `repos/${record.repository}/pulls/${record.prNumber}`
    ? JSON.stringify({ number: record.prNumber, merged: true, merge_commit_sha: record.mergeSha, base: { repo: { full_name: record.repository } }, body: `Closes #${record.issueNumber}` })
    : JSON.stringify({ sha: record.mergeSha, parents: [{ sha: "b".repeat(40) }], files: [{ filename: "new.json", previous_filename: "old.json", status: "renamed" }] });
  await assert.rejects(() => collectPlanDocExecutionLive({ scope: { ...SCOPE, historical: [record] }, sourceSha: SHA, execGh: renameProvider, execGraphql: async () => "{}" }), (error) => error instanceof AuditIncomplete && error.code === "COMMIT_RENAME_UNSUPPORTED");

  const ordered = createPlanDocExecutionReport({ scope: SCOPE, scopeText: JSON.stringify(SCOPE), sourceSha: SHA, observedAt: OBSERVED_AT, live: { records: [...matchingLive().records].reverse(), self: matchingLive().self } });
  const orderedAgain = createPlanDocExecutionReport({ scope: SCOPE, scopeText: JSON.stringify(SCOPE), sourceSha: SHA, observedAt: OBSERVED_AT, live: matchingLive() });
  assert.deepEqual(ordered.records, orderedAgain.records);
  const incompleteOrdering = createPlanDocExecutionReport({ scope: SCOPE, scopeText: JSON.stringify(SCOPE), sourceSha: SHA, observedAt: OBSERVED_AT, incomplete: [
    { stage: "github", code: "ZETA", affectedIdentity: "z" },
    { stage: "github", code: "ALPHA", affectedIdentity: "z" },
    { stage: "alpha", code: "ZETA", affectedIdentity: "z" },
    { stage: "github", code: "ALPHA", affectedIdentity: "a" },
  ] });
  assert.deepEqual(incompleteOrdering.incomplete, [
    { stage: "alpha", code: "ZETA", affectedIdentity: "z" },
    { stage: "github", code: "ALPHA", affectedIdentity: "a" },
    { stage: "github", code: "ALPHA", affectedIdentity: "z" },
    { stage: "github", code: "ZETA", affectedIdentity: "z" },
  ]);

  const directory = mkdtempSync(join(tmpdir(), "plan-doc-execution-v2-"));
  const argv = ["--scope", "scope", "--scope-schema", "scope-schema", "--report-schema", "report-schema", "--source-sha", SHA, "--observed-at", OBSERVED_AT, "--output", join(directory, "report.json")];
  const read = async (path) => ({ scope: JSON.stringify(SCOPE), "scope-schema": JSON.stringify(JSON.parse(readFileSync("contracts/documentation/plan-doc-execution-audit-scope.schema.json", "utf8"))), "report-schema": JSON.stringify(REPORT_SCHEMA) })[path];
  try {
    const success = await runAuditCli({ argv, read, collectLive: async () => matchingLive() });
    assert.equal(success.exitCode, 0); assert.equal(validateSchema(REPORT_SCHEMA, JSON.parse(readFileSync(argv.at(-1), "utf8"))).ok, true);
    const finding = await runAuditCli({ argv: [...argv.slice(0, -1), join(directory, "finding.json")], read, collectLive: async () => ({ ...matchingLive(), records: matchingLive().records.map((value, index) => index === 0 ? { ...value, changedFiles: ["extra.json"] } : value) }) });
    assert.equal(finding.exitCode, 1); assert.equal(JSON.parse(readFileSync(join(directory, "finding.json"), "utf8")).summary.findings, 1);
    writeFileSync(join(directory, "exists.json"), "existing\n");
    const exists = await runAuditCli({ argv: [...argv.slice(0, -1), join(directory, "exists.json")], read, collectLive: async () => matchingLive() });
    assert.equal(exists.exitCode, 2); assert.equal(readFileSync(join(directory, "exists.json"), "utf8"), "existing\n");
    const failure = await runAuditCli({ argv: [...argv.slice(0, -1), join(directory, "failure.json")], read, collectLive: async () => { throw new Error("provider-secret"); } });
    const failureReport = JSON.parse(readFileSync(join(directory, "failure.json"), "utf8"));
    assert.equal(failure.exitCode, 2); assert.equal(validateSchema(REPORT_SCHEMA, failureReport).ok, true); assert.deepEqual([failureReport.status, failureReport.summary.incomplete], ["AUDIT_INCOMPLETE", 1]); assert.doesNotMatch(JSON.stringify(failureReport), /provider-secret/);
    for (const [name, scopeText] of [["malformed", "{"], ["null", "null"], ["empty", "{}"], ["wrong-repositories", JSON.stringify({ ...SCOPE, repositories: ["AquilaXk/easysubway-mobile"] })]]) {
      const output = join(directory, `${name}.json`);
      const invalid = await runAuditCli({ argv: [...argv.slice(0, -1), output], read: async (path) => path === "scope" ? scopeText : read(path), collectLive: async () => matchingLive() });
      const invalidReport = JSON.parse(readFileSync(output, "utf8"));
      assert.equal(invalid.exitCode, 2, name); assert.equal(validateSchema(REPORT_SCHEMA, invalidReport).ok, true, name); assert.deepEqual([invalidReport.status, invalidReport.summary.incomplete], ["AUDIT_INCOMPLETE", 1], name);
    }
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
