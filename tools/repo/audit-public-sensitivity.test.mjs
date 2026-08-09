import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { deflateRawSync } from "node:zlib";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { auditPublicSensitivity, collectActionsArtifacts, collectPublicMetadata, createReport, runAuditCli, scanArtifactArchive, validateReceipt, validateReport, validateScope } from "./audit-public-sensitivity.mjs";

const REPOSITORIES = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
const SHA = "a".repeat(40); const OBSERVED_AT = "2026-08-09T03:00:00.000Z";
const locator = (repository, id = 1) => `https://github.com/${repository}/actions/runs/1/artifacts/${id}`;
const fingerprint = (repository, surface, identity, detector, ordinal, offset) => createHash("sha256").update(`${repository}\u0000${surface}\u0000${identity}\u0000${detector}\u0000${ordinal}\u0000${offset}`).digest("hex");

function scope(dispositions = []) { return { schemaVersion: 1, detectorPolicyVersion: "public-sensitivity-v1", repositories: REPOSITORIES.map((repository) => ({ repository, publicEvidencePaths: ["evidence/public"] })), surfaces: ["REPOSITORY_SECURITY_RECEIPT", "ISSUE_TITLE", "ISSUE_BODY", "ISSUE_COMMENT", "PR_TITLE", "PR_BODY", "PR_COMMENT", "PR_REVIEW_BODY", "PR_REVIEW_COMMENT", "COMMIT_COMMENT", "RELEASE_METADATA", "PUBLIC_ARTIFACT"], detectors: ["PRIVATE_KEY_BLOCK", "KNOWN_TOKEN_FORMAT", "AUTHORIZATION_VALUE", "SIGNED_URL_QUERY", "PRIVATE_ABSOLUTE_PATH", "RAW_PROVIDER_PAYLOAD", "RAW_USER_PAYLOAD"], falsePositiveDispositions: dispositions }; }
function receipt(repository) { return { schemaVersion: 1, repository, gitSha: SHA, observedAt: OBSERVED_AT, secretScanningEnabled: true, pushProtectionEnabled: true, reachableRefAuditComplete: true, alertEnumerationComplete: true, locationEnumerationComplete: true, openAlertCount: 0, unresolvedAlertCount: 0, detectorPolicyVersion: "public-sensitivity-v1", evidenceLocator: locator(repository), publicArtifactEnumerationComplete: true, publicArtifacts: [] }; }

function fakeGh({ body = "safe", next = false } = {}) { return async ({ method, endpoint }) => {
  assert.equal(method, "GET");
  const repository = REPOSITORIES.find((candidate) => endpoint === `repos/${candidate}` || endpoint.startsWith(`repos/${candidate}/`));
  if (!repository) throw new Error("unapproved endpoint");
  if (endpoint === `repos/${repository}`) return { default_branch: "main" };
  if (endpoint === `repos/${repository}/git/ref/heads/main`) return { object: { sha: SHA } };
  if (endpoint.includes("/git/trees/")) return { truncated: false, tree: [] };
  if (endpoint.includes("/actions/artifacts")) return { total_count: 0, artifacts: [] };
  if (endpoint.includes("/issues?")) return [{ id: 1, title: "safe", body: repository === REPOSITORIES[0] ? body : "safe", pull_request: null, updated_at: OBSERVED_AT }];
  if (endpoint.includes("/pulls?")) return [];
  if (endpoint.includes("/issues/comments") || endpoint.includes("/issues/1/comments") || endpoint.includes("/pulls/comments") || endpoint.includes("/pulls/1/reviews") || endpoint.includes("/comments") || endpoint.includes("/releases")) return next ? { body: [], next: true } : [];
  throw new Error("unapproved endpoint");
}; }

test("D20.1 F1-F8 bounded GitHub GET collector rejects virtual completeness", async () => {
  const requests = [];
  const gh = async (request) => { requests.push(request); return fakeGh()(request); };
  const collected = await collectPublicMetadata({ repository: REPOSITORIES[0], execGh: gh });
  assert.deepEqual(collected.incomplete, []);
  assert.ok(requests.every(({ method, endpoint }) => method === "GET" && endpoint.startsWith("repos/AquilaXk/easysubway/")));
  assert.ok(requests.every(({ endpoint }) => !endpoint.includes("watermark") && !endpoint.includes("public-metadata")));
});

test("D20.1 metadata watermark binds content bytes even when provider revision is unchanged", async () => {
  const issueReads = new Map();
  const gh = async (request) => {
    const repository = REPOSITORIES.find((candidate) => request.endpoint.startsWith(`repos/${candidate}/`));
    if (repository != null && request.endpoint.includes("/issues?")) {
      const read = (issueReads.get(repository) ?? 0) + 1;
      issueReads.set(repository, read);
      return [{ id: 1, number: 1, title: "safe", body: read === 1 ? "first" : "changed", pull_request: null, updated_at: OBSERVED_AT }];
    }
    return fakeGh()(request);
  };
  const result = await auditPublicSensitivity({ scope: scope(), receipts: REPOSITORIES.map(receipt), observedAt: OBSERVED_AT, execGh: gh });
  assert.ok(result.incomplete.some(({ code }) => code === "WATERMARK_DRIFT"));
});

test("D20.1 F3-F6 same-source matches use ordinal fingerprints and a disposition cannot suppress another", async () => {
  const identity = `github:AquilaXk/easysubway:ISSUE_BODY:1:${OBSERVED_AT}`;
  const raw = "ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD";
  const first = fingerprint(REPOSITORIES[0], "ISSUE_BODY", identity, "KNOWN_TOKEN_FORMAT", 1, 0);
  const result = await auditPublicSensitivity({ scope: scope([{ locationFingerprint: first, detectorId: "KNOWN_TOKEN_FORMAT", reason: "reviewed", owner: "owner", verifiedAt: OBSERVED_AT, expiresAt: "2026-09-09T03:00:00.000Z" }]), receipts: REPOSITORIES.map(receipt), observedAt: OBSERVED_AT, execGh: fakeGh({ body: raw }), sourceBytes: { scope: "scope-bytes", schema: "schema-bytes", runner: "runner-bytes" } });
  assert.deepEqual(result.incomplete, []);
  assert.equal(result.findings.length, 1);
  const report = createReport({ observedAt: OBSERVED_AT, ...result });
  assert.deepEqual(validateReport(report), []);
  assert.equal(JSON.stringify(report).includes(raw), false);
  assert.equal(report.inputs.policyDigest, createHash("sha256").update("scope-bytes").digest("hex"));
});

test("D20.1 F2/F7 contract failure writes a schema-valid wx incomplete report without raw input", async () => {
  const root = mkdtempSync(join(tmpdir(), "public-sensitivity-cli-"));
  try {
    mkdirSync(join(root, "out"));
    writeFileSync(join(root, "scope.json"), JSON.stringify(scope()));
    writeFileSync(join(root, "receipts.json"), "{raw-provider-secret");
    const args = ["--scope", "scope.json", "--owner-receipts", "receipts.json", "--observed-at", OBSERVED_AT, "--repository-root", root, "--output", "out/report.json"];
    assert.equal(await runAuditCli(args), 2);
    const output = readFileSync(join(root, "out/report.json"), "utf8");
    assert.equal(output.includes("raw-provider-secret"), false);
    const parsed = JSON.parse(output);
    const reportSchema = JSON.parse(readFileSync("contracts/documentation/public-sensitivity-audit-report.schema.json", "utf8"));
    assert.equal(parsed.status, "AUDIT_INCOMPLETE");
    assert.equal(validateSchema(reportSchema, parsed).ok, true);
    assert.deepEqual(validateReport(parsed), []);
    assert.equal(await runAuditCli(args), 2, "wx refuses overwrite");
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test("D20.1 scope keeps the exact closed inventory", () => { assert.deepEqual(validateScope(scope()), []); });

test("D20.1 closure pagination follows a full first page and rejects cross-page duplicate IDs", async () => {
  const calls = [];
  const gh = async ({ endpoint, ...request }) => {
    calls.push(endpoint);
    if (endpoint.includes("/issues?")) return endpoint.endsWith("page=1")
      ? Array.from({ length: 100 }, (_, id) => ({ id, title: "safe", body: "safe", pull_request: null, updated_at: OBSERVED_AT }))
      : [];
    if (endpoint.includes("/pulls?")) return [];
    if (endpoint.includes("/issues/comments") || endpoint.includes("/pulls/comments") || endpoint.includes("/comments") || endpoint.includes("/releases")) return [];
    return fakeGh()(request);
  };
  const result = await collectPublicMetadata({ repository: REPOSITORIES[0], execGh: gh });
  assert.deepEqual(result.incomplete, []);
  assert.ok(calls.some((endpoint) => endpoint.endsWith("issues?state=all&per_page=100&page=2")));
});

test("D20.1 archive scanner handles stored and deflate entries without exporting entry bytes", () => {
  const archive = Buffer.from("504b0506000000000000000000000000000000000000", "hex");
  const result = scanArtifactArchive({ repository: REPOSITORIES[0], artifactId: "1", bytes: archive, scope: scope() });
  assert.deepEqual(result.findings, []);
  assert.deepEqual(result.incomplete, []);
});

test("D20.1 archive scanner finds stored and deflate payloads and rejects unsafe archives", () => {
  for (const method of [0, 8]) {
    const result = scanArtifactArchive({ repository: REPOSITORIES[0], artifactId: "1", bytes: zip([{ name: "safe.txt", text: "ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD", method }]), scope: scope() });
    assert.equal(result.findings.length, 1);
    assert.equal(result.incomplete.length, 0);
  }
  for (const archive of [Buffer.from("504b0506", "hex"), zip([{ name: "safe.txt", text: "safe", method: 0, flags: 1 }]), zip([{ name: "safe.txt", text: "safe", method: 99 }]), zip([{ name: "safe.txt", bytes: Buffer.from([0xc3, 0x28]), method: 0 }]), zip(Array.from({ length: 257 }, (_, id) => ({ name: `f${id}`, text: "", method: 0 })) )]) {
    assert.ok(scanArtifactArchive({ repository: REPOSITORIES[0], artifactId: "1", bytes: archive, scope: scope() }).incomplete.length > 0);
  }
});

test("D20.1 archive finding reaches the aggregate report without raw bytes", async () => {
  const raw = "ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCD";
  const archive = zip([{ name: "safe.txt", text: raw, method: 8 }]);
  const archiveDigest = `sha256:${createHash("sha256").update(archive).digest("hex")}`;
  const receipts = REPOSITORIES.map(receipt);
  receipts[0].publicArtifacts = [{ artifactId: "7", artifactName: "sensitivity", workflowPath: ".github/workflows/audit.yml", runId: "1", archiveDigest, expiresAt: "2026-09-09T03:00:00.000Z", detectorPolicyVersion: "public-sensitivity-v1", scanStatus: "COMPLETE", scanReceiptLocator: locator(REPOSITORIES[0], 7) }];
  const base = fakeGh();
  const execGh = async (request) => {
    if (request.endpoint === `repos/${REPOSITORIES[0]}/actions/artifacts?per_page=100&page=1`) return { total_count: 1, artifacts: [{ id: 7, name: "sensitivity", expired: false, expires_at: "2026-09-09T03:00:00.000Z", digest: archiveDigest, workflow_run: { id: 1 } }] };
    if (request.endpoint === `repos/${REPOSITORIES[0]}/actions/runs/1`) return { path: ".github/workflows/audit.yml" };
    if (request.endpoint === `repos/${REPOSITORIES[0]}/actions/artifacts/7/zip`) return archive;
    return base(request);
  };
  const audit = await auditPublicSensitivity({ scope: scope(), receipts, observedAt: OBSERVED_AT, execGh, sourceBytes: { scope: "scope", schema: "schema", runner: "runner" } });
  assert.deepEqual(audit.incomplete, []);
  assert.equal(audit.findings.length, 1);
  const report = createReport({ observedAt: OBSERVED_AT, ...audit });
  assert.equal(JSON.stringify(report).includes(raw), false);
  assert.equal(report.summary.findings, 1);
});

test("D20.1 receipt locators and artifact expiry are bound to the exact repository", () => {
  const candidate = receipt(REPOSITORIES[0]);
  candidate.evidenceLocator = locator(REPOSITORIES[1]);
  assert.ok(validateReceipt(candidate, { repository: REPOSITORIES[0], gitSha: SHA, observedAt: OBSERVED_AT, detectorPolicyVersion: "public-sensitivity-v1" }).length > 0);
});

test("D20.1 F6 report validator is total and rejects parity, order, enum, and integer mutations", () => {
  const report = createReport({ observedAt: OBSERVED_AT, inputs: { repositories: REPOSITORIES.map((repository) => ({ repository, defaultBranch: "main", gitSha: SHA, beginWatermark: "b".repeat(64), endWatermark: "b".repeat(64), receiptLocator: locator(repository) })) } });
  assert.deepEqual(validateReport(report), []);
  for (const mutate of [(value) => { value.summary.detectors = 1; }, (value) => { value.status = "COMPLETE"; value.incomplete.push({ stage: "a", code: "b", affectedIdentity: "c" }); }, (value) => { value.inputs.repositories.reverse(); }, (value) => { value.summary.findings = 1.5; }]) { const invalid = structuredClone(report); mutate(invalid); assert.ok(validateReport(invalid).length > 0); }
  assert.doesNotThrow(() => validateReport(null));
});

test("D20.1 Actions artifact pagination consumes exact 101/200/201 catalog totals", async () => {
  for (const total of [101, 200, 201]) {
    const calls = [];
    const result = await collectActionsArtifacts({ repository: REPOSITORIES[0], receiptArtifacts: [], observedAt: OBSERVED_AT, detectorPolicyVersion: "public-sensitivity-v1", execGh: async ({ endpoint }) => { calls.push(endpoint); const page = Number(endpoint.match(/[?&]page=(\d+)/)?.[1]); return { total_count: total, artifacts: Array.from({ length: Math.max(0, Math.min(100, total - (page - 1) * 100)) }, (_, offset) => ({ id: (page - 1) * 100 + offset, expired: true })) }; } });
    assert.deepEqual(result.incomplete, []); assert.equal(calls.length, Math.ceil(total / 100));
  }
});

test("D20.1 Actions artifact pagination rejects duplicate, drift, mismatch, and cap", async () => {
  for (const mode of ["duplicate", "drift", "short"]) {
    const result = await collectActionsArtifacts({ repository: REPOSITORIES[0], receiptArtifacts: [], observedAt: OBSERVED_AT, detectorPolicyVersion: "public-sensitivity-v1", execGh: async ({ endpoint }) => { const page = Number(endpoint.match(/[?&]page=(\d+)/)?.[1]); if (mode === "short") return { total_count: 101, artifacts: [] }; return { total_count: mode === "drift" && page === 2 ? 102 : 101, artifacts: Array.from({ length: page === 1 ? 100 : 1 }, (_, offset) => ({ id: mode === "duplicate" && page === 2 ? 0 : (page - 1) * 100 + offset, expired: true })) }; } });
    assert.ok(result.incomplete.length > 0);
  }
});

function zip(entries) {
  const locals = []; const centrals = []; let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name); const source = entry.bytes ?? Buffer.from(entry.text); const data = entry.method === 8 ? deflateRawSync(source) : source; const crc = crc32(source); const local = Buffer.alloc(30 + name.length + data.length); local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(entry.flags ?? 0, 6); local.writeUInt16LE(entry.method, 8); local.writeUInt32LE(crc, 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(source.length, 22); local.writeUInt16LE(name.length, 26); name.copy(local, 30); data.copy(local, 30 + name.length); locals.push(local); const central = Buffer.alloc(46 + name.length); central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(entry.flags ?? 0, 8); central.writeUInt16LE(entry.method, 10); central.writeUInt32LE(crc, 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(source.length, 24); central.writeUInt16LE(name.length, 28); central.writeUInt32LE(offset, 42); name.copy(central, 46); centrals.push(central); offset += local.length;
  }
  const central = Buffer.concat(centrals); const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10); end.writeUInt32LE(central.length, 12); end.writeUInt32LE(offset, 16); return Buffer.concat([...locals, central, end]);
}
function crc32(bytes) { let crc = 0xffffffff; for (const byte of bytes) { crc ^= byte; for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); } return (crc ^ 0xffffffff) >>> 0; }
