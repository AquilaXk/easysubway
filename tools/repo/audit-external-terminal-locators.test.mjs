import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import {
  auditExternalTerminalLocators,
  AuditIncomplete,
  runAuditCli,
  verifyReadyLocator,
  collectLiveIssues,
  collectLive,
  gh,
  validateExternalTerminalLocatorScope,
  validateExternalTerminalLocatorReport,
} from "./audit-external-terminal-locators.mjs";

const SCOPE = JSON.parse(readFileSync("contracts/documentation/external-terminal-locator-audit-scope.json", "utf8"));

test("external terminal locator audit completes the exact eight pending slots", () => {
  assert.equal(validateSchema(JSON.parse(readFileSync("contracts/documentation/external-terminal-locator-audit-scope.schema.json", "utf8")), SCOPE).ok, true);
  assert.deepEqual(validateExternalTerminalLocatorScope(SCOPE), []);

  const report = auditExternalTerminalLocators({
    scope: SCOPE,
    sourceSha: "a".repeat(40),
    observedAt: "2026-08-10T00:00:00.000Z",
    issues: SCOPE.slots.map((slot) => ({ repository: slot.ownerRepository, number: slot.ownerIssue, state: "OPEN" })),
    stateBeginSha256: "d".repeat(64),
    stateEndSha256: "d".repeat(64),
  });

  assert.deepEqual(
    [report.status, report.summary.pending, report.summary.ready, report.summary.findings, report.summary.incomplete],
    ["COMPLETE", 8, 0, 0, 0],
  );
});

test("external terminal locator audit verifies exact Git blob, OCI digest, and Actions archive identities", async () => {
  const slot = (terminalLocator) => ({ ...SCOPE.slots[0], state: "READY", terminalLocator });
  const git = slot({ kind: "GIT_BLOB", repository: "AquilaXk/easysubway", commitSha: "b".repeat(40), path: "contracts/x.json", blobSha: "c".repeat(40) });
  await verifyReadyLocator({ slot: git, ghGet: async (endpoint) => endpoint === "repos/AquilaXk/easysubway/contents/contracts/x.json?ref=" + "b".repeat(40) ? { sha: "c".repeat(40) } : null });

  const oci = slot({ kind: "OCI_DIGEST", registry: "ghcr.io", repositoryPath: "aquilaxk/example", digest: "sha256:" + "d".repeat(64) });
  await verifyReadyLocator({ slot: oci, fetchImpl: async (url, init) => ({ status: url === "https://ghcr.io/v2/aquilaxk/example/manifests/sha256:" + "d".repeat(64) && init.method === "HEAD" && /application\/vnd\.oci\.image\.manifest\.v1\+json/.test(init.headers.Accept) ? 200 : 404, headers: new Headers({ "Docker-Content-Digest": "sha256:" + "d".repeat(64) }) }) });

  const archive = new TextEncoder().encode("artifact");
  const digest = "sha256:" + (await import("node:crypto")).createHash("sha256").update(archive).digest("hex");
  const actions = slot({ kind: "ACTIONS_ARTIFACT", repository: "AquilaXk/easysubway", runId: 7, artifactId: 8, artifactName: "terminal", archiveDigest: digest, workflowPath: ".github/workflows/audit.yml", headSha: "e".repeat(40), createdAt: "2026-08-10T00:00:00Z", expiresAt: "2026-08-11T00:00:00Z" });
  const actionsGhGet = async (endpoint) => endpoint.endsWith("runs/7") ? { conclusion: "success", path: ".github/workflows/audit.yml", head_sha: "e".repeat(40) } : { id: 8, name: "terminal", expired: false, created_at: "2026-08-10T00:00:00Z", expires_at: "2026-08-11T00:00:00Z", digest, workflow_run: { id: 7, head_sha: "e".repeat(40) } };
  await verifyReadyLocator({ slot: actions, now: "2026-08-10T12:00:00.000Z", ghGet: actionsGhGet, downloadArtifact: async () => archive });
  assert.deepEqual(await verifyReadyLocator({ slot: actions, now: "2026-08-10T12:00:00.000Z", ghGet: async (endpoint) => endpoint.endsWith("runs/7") ? actionsGhGet(endpoint) : { ...(await actionsGhGet(endpoint)), workflow_run: { id: 9, head_sha: "e".repeat(40) } }, downloadArtifact: async () => archive }), { identity: "AquilaXk/easysubway#2764", ok: false, code: "ACTIONS_ARTIFACT_MISMATCH" });
});

test("external terminal locator audit records a Git blob identity mismatch as a completed observation", async () => {
  const slot = { ...SCOPE.slots[0], state: "READY", terminalLocator: { kind: "GIT_BLOB", repository: "AquilaXk/easysubway", commitSha: "b".repeat(40), path: "contracts/x.json", blobSha: "c".repeat(40) } };
  assert.deepEqual(await verifyReadyLocator({ slot, ghGet: async () => ({ sha: "d".repeat(40) }) }), { identity: "AquilaXk/easysubway#2764", ok: false, code: "GIT_BLOB_MISMATCH" });
  assert.deepEqual(await verifyReadyLocator({ slot, ghGet: async () => { throw Object.assign(new Error("not found"), { status: 404 }); } }), { identity: "AquilaXk/easysubway#2764", ok: false, code: "GIT_BLOB_MISMATCH" });
});

test("external terminal locator audit normalizes lowercase GitHub issue states", async () => {
  const issues = await collectLiveIssues(SCOPE, async ([, endpoint]) => JSON.stringify({ number: Number(endpoint.split("/").at(-1)), repository_url: `https://api.github.com/repos/${endpoint.split("/").slice(1, 3).join("/")}`, state: "open" }));
  assert.ok(issues.every((issue) => issue.state === "OPEN"));
});

test("external terminal locator audit rejects state and fixed mapping drift", () => {
  for (const mutate of [
    (scope) => { scope.slots[0].terminalLocator = { kind: "GIT_BLOB" }; },
    (scope) => { scope.slots[1].ownerIssue = 2764; },
    (scope) => { scope.slots[7].accountablePlan = "PLAN-REPO"; },
  ]) {
    const invalid = structuredClone(SCOPE);
    mutate(invalid);
    assert.notDeepEqual(validateExternalTerminalLocatorScope(invalid), []);
  }
});

test("external terminal locator audit writes a sanitized incomplete report for an unavailable provider", async () => {
  const directory = mkdtempSync(join(tmpdir(), "external-terminal-locator-"));
  const output = join(directory, "report.json");
  const argv = [
    "--scope", "contracts/documentation/external-terminal-locator-audit-scope.json",
    "--scope-schema", "contracts/documentation/external-terminal-locator-audit-scope.schema.json",
    "--report-schema", "contracts/documentation/external-terminal-locator-audit-report.schema.json",
    "--source-sha", "a".repeat(40), "--observed-at", "2026-08-10T00:00:00.000Z", "--output", output,
  ];
  try {
    const result = await runAuditCli({ argv, collectIssues: async () => { throw new AuditIncomplete("PROVIDER_TIMEOUT", "AquilaXk/easysubway#2764"); } });
    const report = JSON.parse(readFileSync(output, "utf8"));
    const schema = JSON.parse(readFileSync("contracts/documentation/external-terminal-locator-audit-report.schema.json", "utf8"));
    assert.equal(result.exitCode, 2);
    assert.equal(validateSchema(schema, report).ok, true);
    assert.deepEqual([report.status, report.summary.incomplete, report.incomplete[0].code], ["AUDIT_INCOMPLETE", 1, "PROVIDER_TIMEOUT"]);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("external terminal locator audit makes completed identity mismatches findings, not incomplete", () => {
  const ready = structuredClone(SCOPE);
  ready.slots[0].state = "READY";
  ready.slots[0].terminalLocator = { kind: "GIT_BLOB", repository: "AquilaXk/easysubway", commitSha: "b".repeat(40), path: "contracts/x.json", blobSha: "c".repeat(40) };
  const report = auditExternalTerminalLocators({
    scope: ready, sourceSha: "a".repeat(40), observedAt: "2026-08-10T00:00:00.000Z",
    issues: ready.slots.map((slot) => ({ repository: slot.ownerRepository, number: slot.ownerIssue, state: slot === ready.slots[0] ? "OPEN" : "CLOSED" })),
    providerResults: [{ identity: "AquilaXk/easysubway#2764", ok: false, code: "GIT_BLOB_MISMATCH" }],
    stateBeginSha256: "d".repeat(64), stateEndSha256: "d".repeat(64), scopeText: JSON.stringify(ready),
  });
  assert.deepEqual(report.findings, [
    { code: "GIT_BLOB_MISMATCH", identity: "AquilaXk/easysubway#2764" },
    { code: "OWNER_ISSUE_NOT_TERMINAL", identity: "AquilaXk/easysubway#2764" },
  ]);
  assert.deepEqual([report.status, report.summary.incomplete], ["COMPLETE", 0]);
});

test("external terminal locator audit rejects duplicate or extra provider identities as incomplete", () => {
  const issues = SCOPE.slots.map((slot) => ({ repository: slot.ownerRepository, number: slot.ownerIssue, state: "OPEN" }));
  assert.throws(
    () => auditExternalTerminalLocators({ scope: SCOPE, sourceSha: "a".repeat(40), observedAt: "2026-08-10T00:00:00.000Z", issues: [...issues, issues[0]], providerResults: [] }),
    (error) => error instanceof AuditIncomplete && error.code === "ISSUE_RESULT_IDENTITY",
  );
  assert.throws(
    () => auditExternalTerminalLocators({ scope: SCOPE, sourceSha: "a".repeat(40), observedAt: "2026-08-10T00:00:00.000Z", issues, providerResults: [{ identity: "AquilaXk/easysubway#9999", ok: true }] }),
    (error) => error instanceof AuditIncomplete && error.code === "PROVIDER_RESULT_IDENTITY",
  );
});

test("external terminal locator audit detects source or normalized snapshot watermark drift", async () => {
  const issueResponses = SCOPE.slots.map((slot) => ({ repository: slot.ownerRepository, number: slot.ownerIssue, state: "OPEN" }));
  let snapshot = 0;
  await assert.rejects(
    () => collectLive(SCOPE, {
      getSourceHead: async () => "a".repeat(40),
      collectSnapshot: async () => ({ issues: issueResponses.map((issue, index) => ({ ...issue, state: snapshot++ === 0 || index !== 0 ? "OPEN" : "CLOSED" })), providerResults: [] }),
      sourceSha: "a".repeat(40),
    }),
    (error) => error instanceof AuditIncomplete && error.code === "STATE_WATERMARK_DRIFT",
  );
});

test("external terminal locator audit CLI writes an exact fallback report for malformed scope/schema/provider and refuses existing output", async () => {
  const directory = mkdtempSync(join(tmpdir(), "external-terminal-locator-fallback-"));
  const argv = (name) => [
    "--scope", "scope", "--scope-schema", "scope-schema", "--report-schema", "report-schema",
    "--source-sha", "a".repeat(40), "--observed-at", "2026-08-10T00:00:00.000Z", "--output", join(directory, name),
  ];
  const canonicalScopeSchema = readFileSync("contracts/documentation/external-terminal-locator-audit-scope.schema.json", "utf8");
  const canonicalReportSchema = JSON.parse(readFileSync("contracts/documentation/external-terminal-locator-audit-report.schema.json", "utf8"));
  try {
    for (const [name, scopeText, reportSchemaText, collectIssues] of [
      ["malformed-scope", "{", JSON.stringify(canonicalReportSchema), async () => ({ issues: [], providerResults: [] })],
      ["malformed-report-schema", JSON.stringify(SCOPE), "{", async () => ({ issues: [], providerResults: [] })],
      ["provider", JSON.stringify(SCOPE), JSON.stringify(canonicalReportSchema), async () => { throw new AuditIncomplete("PROVIDER_TIMEOUT", "AquilaXk/easysubway#2764"); }],
    ]) {
      const result = await runAuditCli({ argv: argv(`${name}.json`), read: async (path) => ({ scope: scopeText, "scope-schema": canonicalScopeSchema, "report-schema": reportSchemaText })[path], collectIssues });
      const report = JSON.parse(readFileSync(join(directory, `${name}.json`), "utf8"));
      assert.equal(result.exitCode, 2, name);
      assert.equal(validateSchema(canonicalReportSchema, report).ok, true, name);
      assert.deepEqual(report.slots.map(({ state, terminalLocator, issueState }) => [state, terminalLocator, issueState]), Array.from({ length: 8 }, () => ["PENDING", null, "UNAVAILABLE"]), name);
      assert.deepEqual([report.status, report.summary.pending, report.summary.ready, report.summary.findings, report.summary.incomplete], ["AUDIT_INCOMPLETE", 8, 0, 0, 1], name);
    }
    const existing = join(directory, "existing.json"); writeFileSync(existing, "existing\n");
    assert.equal((await runAuditCli({ argv: argv("existing.json"), read: async (path) => ({ scope: JSON.stringify(SCOPE), "scope-schema": canonicalScopeSchema, "report-schema": JSON.stringify(canonicalReportSchema) })[path], collectIssues: async () => ({ issues: SCOPE.slots.map((slot) => ({ repository: slot.ownerRepository, number: slot.ownerIssue, state: "OPEN" })), providerResults: [] }) })).exitCode, 2);
    assert.equal(readFileSync(existing, "utf8"), "existing\n");
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("external terminal locator audit rejects nested locator path/time/repository and contract weakening", () => {
  for (const mutate of [
    (scope) => { scope.slots[0] = { ...scope.slots[0], state: "READY", terminalLocator: { kind: "GIT_BLOB", repository: "AquilaXk/other", commitSha: "a".repeat(40), path: "../secret", blobSha: "b".repeat(40) } }; },
    (scope) => { scope.slots[0] = { ...scope.slots[0], state: "READY", terminalLocator: { kind: "OCI_DIGEST", registry: "ghcr.io", repositoryPath: "aquilaxk/../other", digest: "sha256:" + "a".repeat(64) } }; },
    (scope) => { scope.slots[0] = { ...scope.slots[0], state: "READY", terminalLocator: { kind: "ACTIONS_ARTIFACT", repository: "AquilaXk/easysubway", runId: 1, artifactId: 1, artifactName: "a", archiveDigest: "sha256:" + "a".repeat(64), workflowPath: ".github/workflows/../audit.yml", headSha: "a".repeat(40), createdAt: "2026-08-10T00:00:00.000+00:00", expiresAt: "2026-08-09T00:00:00.000Z" } }; },
  ]) { const invalid = structuredClone(SCOPE); mutate(invalid); assert.notDeepEqual(validateExternalTerminalLocatorScope(invalid), []); }
});

test("external terminal locator audit requires stable non-null watermarks for COMPLETE", () => {
  const report = auditExternalTerminalLocators({
    scope: SCOPE,
    sourceSha: "a".repeat(40),
    observedAt: "2026-08-10T00:00:00.000Z",
    issues: SCOPE.slots.map((slot) => ({ repository: slot.ownerRepository, number: slot.ownerIssue, state: "OPEN" })),
  });
  assert.ok(validateExternalTerminalLocatorReport(report).includes("report parity mismatch"));
});

test("external terminal locator audit accepts a safe GHCR repository path without inventing owner-name equality", () => {
  const scope = structuredClone(SCOPE);
  scope.slots[0] = { ...scope.slots[0], state: "READY", terminalLocator: { kind: "OCI_DIGEST", registry: "ghcr.io", repositoryPath: "aquilaxk/example", digest: "sha256:" + "a".repeat(64) } };
  assert.deepEqual(validateExternalTerminalLocatorScope(scope), []);
});

test("external terminal locator audit gh boundary rejects dot-segment content paths before execution", async () => {
  let executed = false;
  await assert.rejects(() => gh(["api", `repos/AquilaXk/easysubway/contents/contracts/../secret?ref=${"a".repeat(40)}`], async () => { executed = true; return { stdout: "{}" }; }), /allowlist/);
  assert.equal(executed, false);
});
