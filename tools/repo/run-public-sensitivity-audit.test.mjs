import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { assembleOwnerReceipts, downloadOwnerHandoffs, runFanInCli, verifyOwnerEvidence } from "./run-public-sensitivity-audit.mjs";

const REPOSITORIES = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
const SHA = "a".repeat(40);
const OBSERVED_AT = "2026-08-09T00:00:00.000Z";

function receipt(repository, overrides = {}) {
  return { schemaVersion: 1, repository, gitSha: SHA, observedAt: OBSERVED_AT, secretScanningEnabled: true, pushProtectionEnabled: true, reachableRefAuditComplete: true, alertEnumerationComplete: true, locationEnumerationComplete: true, openAlertCount: 0, unresolvedAlertCount: 0, detectorPolicyVersion: "public-sensitivity-v1", evidenceLocator: `https://github.com/${repository}/actions/runs/7/artifacts/9`, publicArtifactEnumerationComplete: true, publicArtifacts: [], ...overrides };
}

test("fan-in accepts exactly five immutable one-object handoffs with matching time, head, and policy", () => {
  const result = assembleOwnerReceipts({ observedAt: OBSERVED_AT, heads: Object.fromEntries(REPOSITORIES.map((repository) => [repository, SHA])), handoffs: REPOSITORIES.map((repository) => ({ locator: `https://github.com/${repository}/actions/runs/8/artifacts/10`, files: [{ name: "receipt.json", text: JSON.stringify(receipt(repository)) }] })) });
  assert.equal(result.length, 5);
});

test("fan-in rejects missing, mixed-time, and malformed handoff transport", () => {
  const valid = REPOSITORIES.map((repository) => ({ locator: `https://github.com/${repository}/actions/runs/8/artifacts/10`, files: [{ name: "receipt.json", text: JSON.stringify(receipt(repository)) }] }));
  assert.throws(() => assembleOwnerReceipts({ observedAt: OBSERVED_AT, heads: Object.fromEntries(REPOSITORIES.map((repository) => [repository, SHA])), handoffs: valid.slice(0, 4) }), /RECEIPT_SET_INCOMPLETE/);
  valid[0].files[0].text = JSON.stringify(receipt(REPOSITORIES[0], { observedAt: "2026-08-09T00:00:01.000Z" }));
  assert.throws(() => assembleOwnerReceipts({ observedAt: OBSERVED_AT, heads: Object.fromEntries(REPOSITORIES.map((repository) => [repository, SHA])), handoffs: valid }), /RECEIPT_IDENTITY_MISMATCH/);
  valid[0].files = [{ name: "one.json", text: "{}" }, { name: "two.json", text: "{}" }];
  assert.throws(() => assembleOwnerReceipts({ observedAt: OBSERVED_AT, heads: Object.fromEntries(REPOSITORIES.map((repository) => [repository, SHA])), handoffs: valid }), /HANDOFF_INVALID/);
});

test("fan-in rejects a schema-invalid receipt even when semantic fields look valid", () => {
  const handoffs = REPOSITORIES.map((repository) => ({ locator: `https://github.com/${repository}/actions/runs/8/artifacts/10`, files: [{ name: "receipt.json", text: JSON.stringify(receipt(repository, { rawProviderBody: "must-not-pass" })) }] }));
  assert.throws(() => assembleOwnerReceipts({ observedAt: OBSERVED_AT, heads: Object.fromEntries(REPOSITORIES.map((repository) => [repository, SHA])), handoffs }), /RECEIPT_IDENTITY_MISMATCH/);
});

test("fan-in rejects a handoff archive digest mismatch", async () => {
  const archives = new Map(REPOSITORIES.map((repository) => [repository, zip("receipt.json", JSON.stringify(receipt(repository)))]));
  const inputs = REPOSITORIES.map((repository) => ({ repository, gitSha: SHA, locator: `https://github.com/${repository}/actions/runs/8/artifacts/10` }));
  const execGh = async ({ endpoint, binary }) => {
    const repository = REPOSITORIES.find((candidate) => endpoint.startsWith(`repos/${candidate}/`));
    if (endpoint.endsWith("/actions/artifacts/10")) return { id: 10, name: `d20-public-sensitivity-owner-receipt-${code(repository)}-${SHA}`, digest: `sha256:${"0".repeat(64)}`, expired: false, created_at: "2026-08-09T00:00:00.001Z", expires_at: "2026-09-09T00:00:00.000Z", workflow_run: { id: 8 } };
    if (endpoint.endsWith("/actions/artifacts/10/zip")) { assert.equal(binary, true); return archives.get(repository); }
    throw new Error(`unexpected ${endpoint}`);
  };
  await assert.rejects(() => downloadOwnerHandoffs({ observedAt: OBSERVED_AT, inputs, execGh }), /HANDOFF_INVALID/);
});

test("valid CLI arguments write a sanitized incomplete report on malformed handoff input", async () => {
  const root = await mkdtemp(join(tmpdir(), "d20-fanin-")); await mkdir(join(root, "out"));
  await writeFile(join(root, "scope.json"), "{}"); await writeFile(join(root, "handoffs.json"), "{raw-provider-secret");
  const resolvedName = `resolved-owner-receipts-${createHash("sha256").update("out/report.json").digest("hex").slice(0, 16)}-0.json`;
  await writeFile(join(root, "out", resolvedName), "already-owned-by-another-attempt\n");
  const exitCode = await runFanInCli(["--scope", "scope.json", "--owner-receipts", "handoffs.json", "--observed-at", OBSERVED_AT, "--runner-sha", SHA, "--repository-root", root, "--output", "out/report.json"]);
  assert.equal(exitCode, 2);
  const text = await readFile(join(root, "out/report.json"), "utf8");
  assert.equal(text.includes("raw-provider-secret"), false);
  assert.equal(JSON.parse(text).status, "AUDIT_INCOMPLETE");
  assert.equal(await readFile(join(root, "out", resolvedName), "utf8"), "already-owned-by-another-attempt\n");
  assert.equal(JSON.parse(await readFile(join(root, "out", `${resolvedName.slice(0, -6)}1.json`), "utf8")).length, 0);
});

test("malformed observed_at still writes one schema-valid incomplete report", async () => {
  const root = await mkdtemp(join(tmpdir(), "d20-invalid-time-")); await mkdir(join(root, "out"));
  await writeFile(join(root, "scope.json"), await readFile("contracts/documentation/public-sensitivity-audit-scope.json", "utf8")); await writeFile(join(root, "handoffs.json"), "[]");
  const exitCode = await runFanInCli(["--scope", "scope.json", "--owner-receipts", "handoffs.json", "--observed-at", "not-a-time", "--runner-sha", SHA, "--repository-root", root, "--output", "out/report.json"]);
  assert.equal(exitCode, 2);
  const report = JSON.parse(await readFile(join(root, "out/report.json"), "utf8"));
  assert.equal(report.status, "AUDIT_INCOMPLETE"); assert.equal(report.observedAt, "1970-01-01T00:00:00.000Z");
});

test("fan-in binds every receipt to the exact post-cutoff evidence archive", async () => {
  const receipts = REPOSITORIES.map((repository) => receipt(repository));
  const archives = new Map(receipts.map((item) => [item.repository, zip("evidence.json", JSON.stringify(Object.fromEntries(Object.entries(item).filter(([key]) => key !== "evidenceLocator"))))]));
  const execGh = async ({ endpoint, binary }) => {
    const repository = REPOSITORIES.find((candidate) => endpoint.startsWith(`repos/${candidate}/`)); const bytes = archives.get(repository);
    if (endpoint.endsWith("/actions/artifacts/9")) return { id: 9, name: `d20-public-sensitivity-evidence-${code(repository)}-${SHA}`, digest: `sha256:${createDigest(bytes)}`, expired: false, created_at: "2026-08-09T00:00:00.001Z", expires_at: "2026-09-09T00:00:00.000Z", workflow_run: { id: 7 } };
    if (endpoint.endsWith("/actions/artifacts/9/zip")) { assert.equal(binary, true); return bytes; }
    throw new Error(`unexpected ${endpoint}`);
  };
  await verifyOwnerEvidence({ receipts, observedAt: OBSERVED_AT, execGh });
  archives.set(REPOSITORIES[0], zip("evidence.json", JSON.stringify({ changed: true })));
  await assert.rejects(() => verifyOwnerEvidence({ receipts, observedAt: OBSERVED_AT, execGh }), /EVIDENCE_INVALID|HANDOFF_INVALID/);
});

test("fan-in rejects a stale coordinator head before provider reads and still writes incomplete evidence", async () => {
  const root = await mkdtemp(join(tmpdir(), "d20-stale-runner-")); await mkdir(join(root, "out"));
  const scope = await readFile("contracts/documentation/public-sensitivity-audit-scope.json", "utf8");
  await writeFile(join(root, "scope.json"), scope);
  await writeFile(join(root, "handoffs.json"), JSON.stringify(REPOSITORIES.map((repository) => ({ repository, gitSha: SHA, locator: `https://github.com/${repository}/actions/runs/8/artifacts/10` }))));
  let calls = 0;
  const exitCode = await runFanInCli(["--scope", "scope.json", "--owner-receipts", "handoffs.json", "--observed-at", OBSERVED_AT, "--runner-sha", "b".repeat(40), "--repository-root", root, "--output", "out/report.json"], { execGh: async () => { calls += 1; throw new Error("must not call"); } });
  assert.equal(exitCode, 2); assert.equal(calls, 0);
  assert.equal(JSON.parse(await readFile(join(root, "out/report.json"), "utf8")).status, "AUDIT_INCOMPLETE");
});

test("fan-in success passes only the five A-bound receipts to the existing auditor", async () => {
  const root = await mkdtemp(join(tmpdir(), "d20-success-")); await mkdir(join(root, "out"));
  await writeFile(join(root, "scope.json"), await readFile("contracts/documentation/public-sensitivity-audit-scope.json", "utf8"));
  const inputs = REPOSITORIES.map((repository) => ({ repository, gitSha: SHA, locator: `https://github.com/${repository}/actions/runs/8/artifacts/10` }));
  await writeFile(join(root, "handoffs.json"), JSON.stringify(inputs));
  const bArchives = new Map(); const aArchives = new Map();
  for (const repository of REPOSITORIES) {
    const value = receipt(repository); bArchives.set(repository, zip("receipt.json", JSON.stringify(value)));
    aArchives.set(repository, zip("evidence.json", JSON.stringify(Object.fromEntries(Object.entries(value).filter(([key]) => key !== "evidenceLocator")))));
  }
  const execGh = async ({ endpoint }) => {
    const repository = REPOSITORIES.find((candidate) => endpoint.startsWith(`repos/${candidate}/`)); const isHandoff = endpoint.includes("/artifacts/10"); const bytes = isHandoff ? bArchives.get(repository) : aArchives.get(repository); const artifactId = isHandoff ? 10 : 9; const runId = isHandoff ? 8 : 7;
    if (endpoint.endsWith(`/artifacts/${artifactId}`)) return { id: artifactId, name: `${isHandoff ? "d20-public-sensitivity-owner-receipt" : "d20-public-sensitivity-evidence"}-${code(repository)}-${SHA}`, digest: `sha256:${createDigest(bytes)}`, expired: false, created_at: "2026-08-09T00:00:00.001Z", expires_at: "2026-09-09T00:00:00.000Z", workflow_run: { id: runId } };
    if (endpoint.endsWith(`/artifacts/${artifactId}/zip`)) return bytes;
    throw new Error(`unexpected ${endpoint}`);
  };
  let resolved;
  const exitCode = await runFanInCli(["--scope", "scope.json", "--owner-receipts", "handoffs.json", "--observed-at", OBSERVED_AT, "--runner-sha", SHA, "--repository-root", root, "--output", "out/report.json"], { execGh, auditCli: async (args) => { resolved = JSON.parse(await readFile(join(root, args[3]), "utf8")); return 0; } });
  assert.equal(exitCode, 0); assert.deepEqual(resolved.map(({ repository }) => repository), REPOSITORIES);
});

function zip(name, text) {
  const filename = Buffer.from(name); const data = Buffer.from(text); const crc = crc32(data);
  const local = Buffer.alloc(30 + filename.length + data.length); local.writeUInt32LE(0x04034b50, 0); local.writeUInt32LE(crc, 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(filename.length, 26); filename.copy(local, 30); data.copy(local, 30 + filename.length);
  const central = Buffer.alloc(46 + filename.length); central.writeUInt32LE(0x02014b50, 0); central.writeUInt32LE(crc, 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(filename.length, 28); central.writeUInt32LE(0, 42); filename.copy(central, 46);
  const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10); end.writeUInt32LE(central.length, 12); end.writeUInt32LE(local.length, 16);
  return Buffer.concat([local, central, end]);
}
function crc32(bytes) { let crc = 0xffffffff; for (const byte of bytes) { crc ^= byte; for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); } return (crc ^ 0xffffffff) >>> 0; }
function code(repository) { return repository === "AquilaXk/easysubway" ? "hub" : repository.slice("AquilaXk/easysubway-".length); }
function createDigest(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
