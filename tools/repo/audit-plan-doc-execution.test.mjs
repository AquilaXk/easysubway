import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { AuditIncomplete, auditPlanDocExecution, collectPlanDocExecutionLive, createPlanDocExecutionReport, parseClosingIssues, validatePlanDocExecutionScope } from "./audit-plan-doc-execution.mjs";

const SCOPE = JSON.parse(readFileSync("contracts/documentation/plan-doc-execution-audit-scope.json", "utf8"));
const REPORT_SCHEMA = JSON.parse(readFileSync("contracts/documentation/plan-doc-execution-audit-report.schema.json", "utf8"));
const SHA = "a".repeat(40);
const OBSERVED_AT = "2026-08-15T00:00:00.000Z";

function matchingLive(scope = SCOPE) {
  const observed = (record) => ({ issueNumber: record.issueNumber, prNumber: record.prNumber, repository: record.repository, mergeSha: record.mergeSha, changedFiles: [...record.allowedChangedFiles], relationText: record.relation === "CLOSES" ? `Closes #${record.issueNumber}` : `Refs #${record.issueNumber} — coordinator`, closingIssues: record.relation === "CLOSES" ? [{ number: record.issueNumber, state: "CLOSED" }] : [] });
  return { records: scope.historical.map(observed), self: { ...observed({ ...scope.self, prNumber: 9999, mergeSha: SHA, relation: "CLOSES" }), mergeSha: SHA } };
}

test("plan-doc execution audit scope fixes the federated 64-record inventory and self binding", () => {
  assert.equal(SCOPE.schemaVersion, 2);
  assert.equal(SCOPE.historical.length, 64);
  assert.deepEqual(SCOPE.repositories, ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"]);
  assert.equal(SCOPE.self.issueNumber, 2881);
  const byIdentity = new Map(SCOPE.historical.map((record) => [`${record.repository}:${record.prNumber}`, record]));
  assert.deepEqual(byIdentity.get("AquilaXk/easysubway:2852").allowedChangedFiles, [".github/workflows/ci.yml", "apps/mobile/pubspec.lock", "apps/mobile/pubspec.yaml", "tools/ci/repository-contract.test.mjs"]);
  assert.equal(byIdentity.get("AquilaXk/easysubway:2852").changedPathClass, "PLAN_DOC_CI_RECOVERY");
  assert.deepEqual(byIdentity.get("AquilaXk/easysubway-backend:248").allowedChangedFiles, ["contracts/documentation/documentation-fragment.json"]);
  assert.deepEqual(validatePlanDocExecutionScope(SCOPE), []);
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
    if (endpoint === `repos/AquilaXk/easysubway/pulls/9999`) return JSON.stringify({ number: 9999, merged: true, merge_commit_sha: SHA, base: { repo: { full_name: "AquilaXk/easysubway" } }, body: "Closes #2881" });
    if (endpoint === `repos/AquilaXk/easysubway/commits/${SHA}?per_page=100&page=1`) return JSON.stringify({ sha: SHA, parents: [{ sha: "b".repeat(40) }], files: SCOPE.self.allowedChangedFiles.map((filename) => ({ filename })) });
    throw new Error(`unexpected ${endpoint}`);
  };
  const graphql = async (repository, prNumber) => { const value = repository === record.repository ? record : { issueNumber: 2881, mergeSha: SHA }; return JSON.stringify({ data: { repository: { pullRequest: { number: prNumber, merged: true, mergeCommit: { oid: value.mergeSha }, closingIssuesReferences: { totalCount: 1, pageInfo: { hasNextPage: false }, nodes: [{ number: value.issueNumber, state: "CLOSED", repository: { nameWithOwner: repository } }] } } } } }); };
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
