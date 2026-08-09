import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { AuditIncomplete, auditPostGoBoundary, collectPostGoBoundaryLive, createPostGoBoundaryReport, runAuditCli, validatePostGoBoundaryScope } from "./audit-post-go-boundary.mjs";

const SCOPE = JSON.parse(readFileSync("contracts/documentation/post-go-boundary-audit-scope.json", "utf8"));
const SHA = "a".repeat(40);
const OBSERVED_AT = "2026-08-09T00:00:00.000Z";

function live(children = []) {
  return {
    defaultHead: SHA,
    issues: {
      releaseDecision: { repository: "AquilaXk/easysubway", number: 1020, state: "OPEN", body: "## Current decision record\n\n```text\nFINAL = NO_GO\n```" },
      fieldResearch: { repository: "AquilaXk/easysubway", number: 2766, state: "OPEN", body: "## 판정·역할\n\n```text\nactivation      Hub #1020 GO + stable public release scope\n```\n\n## activation evidence audit\n\n```text\nstable public release      NOT_PROVEN\nactivation                 NOT_PROVEN\n```" },
      privacyMetrics: { repository: "AquilaXk/easysubway", number: 2768, state: "OPEN", body: "## 판정·역할\n\n```text\nactivation      Mobile #36 terminal + public release + exact product question\n```\n\n## activation evidence audit\n\n```text\nMobile #36 terminal        NOT_PROVEN\nstable public release      NOT_PROVEN\nexact product question     NOT_PROVEN\nactivation                 NOT_PROVEN\n```" },
      mobilePrivacy: { repository: "AquilaXk/easysubway-mobile", number: 36, state: "OPEN", body: "Current issue remains `open`." },
    },
    declaredChildren: children,
  };
}

test("post-GO boundary audit scope fixes only declared parents, prerequisites, and JIT relations", () => {
  assert.deepEqual(validatePostGoBoundaryScope(SCOPE), []);
  const invalid = structuredClone(SCOPE);
  invalid.declaredJitChildren.push({ repository: "AquilaXk/easysubway", number: 1, parent: "fieldResearch", relation: "JIT_CHILD", allowedPaths: ["tools/repo/"] });
  assert.ok(validatePostGoBoundaryScope(invalid).length > 0);
});

test("post-GO boundary audit reports field-research child created before the current NO_GO activation", () => {
  const findings = auditPostGoBoundary({ scope: SCOPE, sourceSha: SHA, live: live([{ repository: "AquilaXk/easysubway", number: 99, parent: "fieldResearch", relation: "JIT_CHILD" }]) });
  assert.deepEqual(findings, [{ code: "JIT_CHILD_CREATED_BEFORE_ACTIVATION", identity: "fieldResearch:AquilaXk/easysubway:99" }]);
});

test("post-GO boundary audit needs no fabricated child path metadata", () => {
  const findings = auditPostGoBoundary({ scope: SCOPE, sourceSha: SHA, live: live([{ repository: "AquilaXk/easysubway", number: 99, parent: "fieldResearch", relation: "JIT_CHILD" }]) });
  assert.deepEqual(findings, [{ code: "JIT_CHILD_CREATED_BEFORE_ACTIVATION", identity: "fieldResearch:AquilaXk/easysubway:99" }]);
});

test("post-GO boundary audit reports privacy child while Mobile #36 remains OPEN", () => {
  const findings = auditPostGoBoundary({ scope: SCOPE, sourceSha: SHA, live: live([{ repository: "AquilaXk/easysubway-mobile", number: 99, parent: "privacyMetrics", relation: "JIT_CHILD" }]) });
  assert.deepEqual(findings, [{ code: "JIT_CHILD_CREATED_BEFORE_ACTIVATION", identity: "privacyMetrics:AquilaXk/easysubway-mobile:99" }]);
});

test("post-GO boundary audit does not infer stable release or product question and creates a sanitized incomplete report", () => {
  const report = createPostGoBoundaryReport({ scope: SCOPE, scopeText: JSON.stringify(SCOPE), sourceSha: SHA, observedAt: OBSERVED_AT, incomplete: [{ stage: "marker", code: "MARKER_AMBIGUOUS", affectedIdentity: "privacyMetrics" }] });
  assert.deepEqual([report.status, report.summary.incomplete, report.findings], ["AUDIT_INCOMPLETE", 1, []]);
  assert.throws(() => { throw new AuditIncomplete("PROVIDER_MALFORMED", "issue:1020"); }, AuditIncomplete);
});

test("post-GO boundary audit rejects generic or duplicate decision and activation markers", () => {
  for (const [name, body] of [["releaseDecision", "NO_GO"], ["fieldResearch", "activation      Hub #1020 GO + stable public release scope\nactivation      Hub #1020 GO + stable public release scope"]]) {
    const candidate = live(); candidate.issues[name].body = body;
    assert.throws(() => auditPostGoBoundary({ scope: SCOPE, sourceSha: SHA, live: candidate }), AuditIncomplete);
  }
});

test("post-GO boundary audit rejects contradictory blocked-marker values", () => {
  const candidate = live();
  candidate.issues.fieldResearch.body = candidate.issues.fieldResearch.body.replace("activation                 NOT_PROVEN\n```", "activation                 NOT_PROVEN\nstable public release      PROVEN\n```");
  assert.throws(() => auditPostGoBoundary({ scope: SCOPE, sourceSha: SHA, live: candidate }), AuditIncomplete);
});

test("post-GO boundary audit accepts the actual decision rows and rejects parent markers outside 판정·역할", () => {
  const candidate = live();
  candidate.issues.releaseDecision.body = "## Current decision record\n\n```text\nData FAIL\nMobile FAIL\nFINAL = NO_GO\n```";
  assert.doesNotThrow(() => auditPostGoBoundary({ scope: SCOPE, sourceSha: SHA, live: candidate }));
  candidate.issues.fieldResearch.body = candidate.issues.fieldResearch.body.replace("activation      Hub #1020 GO + stable public release scope\n", "") + "\nactivation      Hub #1020 GO + stable public release scope";
  assert.throws(() => auditPostGoBoundary({ scope: SCOPE, sourceSha: SHA, live: candidate }), AuditIncomplete);
});

test("post-GO boundary audit fails closed for default-head drift and partial parent sub-issue connection", async () => {
  assert.throws(() => auditPostGoBoundary({ scope: SCOPE, sourceSha: SHA, live: { ...live(), defaultHead: "b".repeat(40) } }), AuditIncomplete);
  const execGh = async (repository, suffix) => {
    if (suffix === "") return JSON.stringify({ default_branch: "main" });
    if (suffix === "commits/main") return JSON.stringify({ sha: SHA });
    const issueNumber = Number(suffix.split("/").at(-1));
    return JSON.stringify({ repository_url: `https://api.github.com/repos/${repository}`, number: issueNumber, state: "open", body: live().issues[issueNumber === 1020 ? "releaseDecision" : issueNumber === 2766 ? "fieldResearch" : issueNumber === 2768 ? "privacyMetrics" : "mobilePrivacy"].body });
  };
  await assert.rejects(() => collectPostGoBoundaryLive({ scope: SCOPE, sourceSha: SHA, execGh, execGraphql: async () => JSON.stringify({ data: { repository: { issue: { subIssues: { totalCount: 1, pageInfo: { hasNextPage: false }, nodes: [] } } } } }) }), AuditIncomplete);
});

test("post-GO boundary audit CLI writes schema-valid success, finding, and sanitized incomplete reports once", async () => {
  const directory = mkdtempSync(join(tmpdir(), "post-go-boundary-")); const reportSchema = JSON.parse(readFileSync("contracts/documentation/post-go-boundary-audit-report.schema.json", "utf8"));
  const argv = (output) => ["--scope", "scope", "--scope-schema", "scope-schema", "--report-schema", "report-schema", "--source-sha", SHA, "--observed-at", OBSERVED_AT, "--output", join(directory, output)];
  const read = async (path) => ({ scope: JSON.stringify(SCOPE), "scope-schema": readFileSync("contracts/documentation/post-go-boundary-audit-scope.schema.json", "utf8"), "report-schema": readFileSync("contracts/documentation/post-go-boundary-audit-report.schema.json", "utf8") })[path];
  try {
    for (const [name, candidate, expected] of [["success", live(), 0], ["finding", live([{ repository: "AquilaXk/easysubway", number: 7, parent: "fieldResearch", relation: "JIT_CHILD" }]), 1]]) { const result = await runAuditCli({ argv: argv(`${name}.json`), read, collectLive: async () => ({ ...candidate, stateBeginSha256: "b".repeat(64), stateEndSha256: "b".repeat(64) }) }); assert.equal(result.exitCode, expected); assert.equal(validateSchema(reportSchema, JSON.parse(readFileSync(join(directory, `${name}.json`), "utf8"))).ok, true); }
    const incomplete = await runAuditCli({ argv: argv("incomplete.json"), read, collectLive: async () => { throw new Error("provider-secret"); } }); assert.equal(incomplete.exitCode, 2); assert.doesNotMatch(readFileSync(join(directory, "incomplete.json"), "utf8"), /provider-secret/);
    writeFileSync(join(directory, "existing.json"), "existing\n"); assert.equal((await runAuditCli({ argv: argv("existing.json"), read, collectLive: async () => live() })).exitCode, 2); assert.equal(readFileSync(join(directory, "existing.json"), "utf8"), "existing\n");
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

function snapshotProvider(first, second = first) {
  let phase = -1;
  const issueKey = (number) => number === 1020 ? "releaseDecision" : number === 2766 ? "fieldResearch" : number === 2768 ? "privacyMetrics" : "mobilePrivacy";
  return {
    execGh: async (repository, suffix) => {
      if (suffix === "") { phase += 1; return JSON.stringify({ default_branch: "main" }); }
      const current = phase === 0 ? first : second;
      if (suffix === "commits/main") return JSON.stringify({ sha: current.defaultHead });
      const number = Number(suffix.split("/").at(-1)); const value = current.issues[issueKey(number)];
      return JSON.stringify({ repository_url: `https://api.github.com/repos/${repository}`, number, state: value.state.toLowerCase(), body: value.body });
    },
    execGraphql: async (number) => { const current = phase === 0 ? first : second; const parent = number === 2766 ? "fieldResearch" : "privacyMetrics"; const nodes = current.declaredChildren.filter((child) => child.parent === parent).map((child) => ({ number: child.number, repository: { nameWithOwner: child.repository } })); return JSON.stringify({ data: { repository: { issue: { subIssues: { totalCount: nodes.length, pageInfo: { hasNextPage: false, endCursor: null }, nodes } } } } }); },
  };
}

test("post-GO boundary snapshots reject begin/end head, issue, relation, and frozen total drift", async () => {
  const base = live();
  for (const mutate of [
    (value) => { value.defaultHead = "b".repeat(40); },
    (value) => { value.issues.fieldResearch.body += "\nchanged"; },
  ]) { const end = structuredClone(base); mutate(end); const provider = snapshotProvider(base, end); await assert.rejects(() => collectPostGoBoundaryLive({ scope: SCOPE, sourceSha: SHA, ...provider }), (error) => error instanceof AuditIncomplete && error.code === "STATE_WATERMARK_DRIFT"); }
  const relationEnd = structuredClone(base); relationEnd.declaredChildren = [{ repository: "AquilaXk/easysubway", number: 7, parent: "fieldResearch", relation: "JIT_CHILD" }];
  await assert.rejects(() => collectPostGoBoundaryLive({ scope: SCOPE, sourceSha: SHA, ...snapshotProvider(base, relationEnd) }), (error) => error instanceof AuditIncomplete && error.code === "STATE_WATERMARK_DRIFT");
  let page = 0; const provider = snapshotProvider(base);
  provider.execGraphql = async (number) => {
    if (number !== 2766) return JSON.stringify({ data: { repository: { issue: { subIssues: { totalCount: 0, pageInfo: { hasNextPage: false }, nodes: [] } } } } });
    page += 1; return JSON.stringify({ data: { repository: { issue: { subIssues: { totalCount: page === 1 ? 101 : 100, pageInfo: { hasNextPage: page === 1, endCursor: page === 1 ? "next" : null }, nodes: page === 1 ? Array.from({ length: 100 }, (_, index) => ({ number: index + 1, repository: { nameWithOwner: "AquilaXk/easysubway" } })) : [] } } } } });
  };
  await assert.rejects(() => collectPostGoBoundaryLive({ scope: SCOPE, sourceSha: SHA, ...provider }), AuditIncomplete);
});

test("post-GO boundary stable snapshots persist equal state watermarks", async () => {
  const begin = live([{ repository: "AquilaXk/easysubway", number: 2, parent: "fieldResearch", relation: "JIT_CHILD" }, { repository: "AquilaXk/easysubway", number: 1, parent: "fieldResearch", relation: "JIT_CHILD" }]);
  const end = structuredClone(begin); end.declaredChildren.reverse(); const provider = snapshotProvider(begin, end); const observed = await collectPostGoBoundaryLive({ scope: SCOPE, sourceSha: SHA, ...provider });
  const report = createPostGoBoundaryReport({ scope: SCOPE, scopeText: JSON.stringify(SCOPE), sourceSha: SHA, observedAt: OBSERVED_AT, live: observed });
  assert.match(report.inputs.stateBeginSha256, /^[0-9a-f]{64}$/); assert.equal(report.inputs.stateBeginSha256, report.inputs.stateEndSha256);
});
