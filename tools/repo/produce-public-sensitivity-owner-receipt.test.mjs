import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import { produceOwnerEvidence, produceOwnerReceipt } from "./produce-public-sensitivity-owner-receipt.mjs";

const REPOSITORY = "AquilaXk/easysubway";
const SHA = "a".repeat(40);
const OBSERVED_AT = "2026-08-09T00:00:00.000Z";
const LOCATOR = `https://github.com/${REPOSITORY}/actions/runs/7/artifacts/9`;

function artifact(id, overrides = {}) {
  return { id, expired: false, created_at: "2026-08-08T00:00:00.000Z", expires_at: "2026-09-09T00:00:00.000Z", name: `evidence-${id}`, digest: `sha256:${"b".repeat(64)}`, workflow_run: { id: 7 }, ...overrides };
}

function gh({ evidence = artifact(9, { created_at: "2026-08-09T00:00:00.001Z" }), evidenceArchive = null } = {}) {
  return async ({ endpoint, binary }) => {
    if (endpoint === `repos/${REPOSITORY}/actions/artifacts?per_page=100&page=1`) return { total_count: 1, artifacts: [evidence] };
    if (endpoint === `repos/${REPOSITORY}/git/ref/heads/main`) return { ref: "refs/heads/main", object: { sha: SHA } };
    if (endpoint === `repos/${REPOSITORY}/actions/runs/7`) return { path: ".github/workflows/public-sensitivity-owner-receipt.yml" };
    if (endpoint === `repos/${REPOSITORY}/actions/artifacts/9/zip`) return evidenceArchive ?? Buffer.from("PK\x05\x06\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0", "binary");
    throw new Error(`unexpected ${binary ? "binary " : ""}${endpoint}`);
  };
}

function alerts({ open = [], locations = [] } = {}) {
  return async ({ endpoint }) => {
    if (endpoint === `repos/${REPOSITORY}`) return { security_and_analysis: { secret_scanning: { status: "enabled" }, secret_scanning_push_protection: { status: "enabled" } } };
    if (endpoint === `repos/${REPOSITORY}/secret-scanning/alerts?state=open&per_page=100&page=1`) return open;
    if (endpoint === `repos/${REPOSITORY}/secret-scanning/alerts/1/locations?per_page=100&page=1`) return locations;
    throw new Error(`unexpected ${endpoint}`);
  };
}

function zip(name, text) {
  const filename = Buffer.from(name); const data = Buffer.from(text); const crc = crc32(data);
  const local = Buffer.alloc(30 + filename.length + data.length);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt32LE(crc, 14); local.writeUInt32LE(data.length, 18); local.writeUInt32LE(data.length, 22); local.writeUInt16LE(filename.length, 26); filename.copy(local, 30); data.copy(local, 30 + filename.length);
  const central = Buffer.alloc(46 + filename.length);
  central.writeUInt32LE(0x02014b50, 0); central.writeUInt32LE(crc, 16); central.writeUInt32LE(data.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(filename.length, 28); central.writeUInt32LE(0, 42); filename.copy(central, 46);
  const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10); end.writeUInt32LE(central.length, 12); end.writeUInt32LE(local.length, 16);
  return Buffer.concat([local, central, end]);
}

function crc32(bytes) { let crc = 0xffffffff; for (const byte of bytes) { crc ^= byte; for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); } return (crc ^ 0xffffffff) >>> 0; }

test("receipt is created only after the post-cutoff evidence artifact identity is available", async () => {
  const evidence = await produceOwnerEvidence({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, execGh: gh(), execAlerts: alerts() });
  await assert.rejects(() => produceOwnerReceipt({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, evidenceLocator: LOCATOR, evidence, execGh: gh() }), /EVIDENCE_TRANSPORT_INVALID/);
  const transport = artifact(9, { created_at: "2026-08-09T00:00:00.001Z" });
  const archive = zip("evidence.json", JSON.stringify(evidence));
  transport.digest = `sha256:${createHash("sha256").update(archive).digest("hex")}`;
  const result = await produceOwnerReceipt({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, evidenceLocator: LOCATOR, evidence, expectedEvidenceDigest: transport.digest.slice("sha256:".length), evidenceArtifact: transport, execGh: gh({ evidence: transport, evidenceArchive: archive }) });
  assert.equal(result.receipt.evidenceLocator, LOCATOR);
  assert.equal(result.receipt.alertEnumerationComplete, true);
  assert.equal(result.receipt.publicArtifactEnumerationComplete, true);
});

test("producer fails closed when alert capability or post-cutoff evidence boundary is incomplete", async () => {
  const evidence = await produceOwnerEvidence({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, execGh: gh(), execAlerts: alerts() });
  const beforeCutoff = artifact(9);
  await assert.rejects(() => produceOwnerReceipt({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, evidenceLocator: LOCATOR, evidence, expectedEvidenceDigest: beforeCutoff.digest.slice("sha256:".length), evidenceArtifact: beforeCutoff, execGh: gh({ evidence: beforeCutoff }) }), /EVIDENCE_TRANSPORT_INVALID/);
  await assert.rejects(() => produceOwnerEvidence({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, execGh: gh(), execAlerts: async () => { throw new Error("403 secret value"); } }), /ALERT_CAPABILITY_UNAVAILABLE/);
});

test("receipt finalization rejects missing, digest-mismatched, malformed, and changed uploaded evidence", async () => {
  const evidence = await produceOwnerEvidence({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, execGh: gh(), execAlerts: alerts() });
  const transport = artifact(9, { created_at: "2026-08-09T00:00:00.001Z" });
  const original = zip("evidence.json", JSON.stringify(evidence));
  transport.digest = `sha256:${createHash("sha256").update(original).digest("hex")}`;
  const input = { repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, evidenceLocator: LOCATOR, evidence, expectedEvidenceDigest: transport.digest.slice("sha256:".length), evidenceArtifact: transport };
  await assert.rejects(() => produceOwnerReceipt({ ...input, execGh: async ({ endpoint }) => { if (endpoint.endsWith("/zip")) throw new Error("404"); return gh({ evidence: transport })({ endpoint }); } }), /EVIDENCE_TRANSPORT_INVALID/);
  const malformed = Buffer.from("not-a-zip");
  const malformedTransport = { ...transport, digest: `sha256:${createHash("sha256").update(malformed).digest("hex")}` };
  await assert.rejects(() => produceOwnerReceipt({ ...input, expectedEvidenceDigest: malformedTransport.digest.slice("sha256:".length), evidenceArtifact: malformedTransport, execGh: gh({ evidence: malformedTransport, evidenceArchive: malformed }) }), /EVIDENCE_TRANSPORT_INVALID/);
  const changed = zip("evidence.json", JSON.stringify({ ...evidence, openAlertCount: 1 }));
  transport.digest = `sha256:${createHash("sha256").update(changed).digest("hex")}`;
  await assert.rejects(() => produceOwnerReceipt({ ...input, expectedEvidenceDigest: transport.digest.slice("sha256:".length), evidenceArtifact: transport, execGh: gh({ evidence: transport, evidenceArchive: changed }) }), /EVIDENCE_TRANSPORT_INVALID/);
});

test("complete scan with findings remains COMPLETE for receipt admission", async () => {
  const archive = zip("finding.txt", "authorization: bearer not-a-real-secret");
  const digest = `sha256:${createHash("sha256").update(archive).digest("hex")}`;
  const eligible = artifact(5, { created_at: "2026-08-08T00:00:00.000Z", name: "eligible", digest, workflow_run: { id: 5 } });
  const execGh = async ({ endpoint, binary }) => {
    if (endpoint.endsWith("/actions/artifacts?per_page=100&page=1")) return { total_count: 1, artifacts: [eligible] };
    if (endpoint.endsWith("/git/ref/heads/main")) return { ref: "refs/heads/main", object: { sha: SHA } };
    if (endpoint.endsWith("/actions/runs/5")) return { path: ".github/workflows/ci.yml" };
    if (endpoint.endsWith("/actions/artifacts/5/zip")) { assert.equal(binary, true); return archive; }
    throw new Error(`unexpected ${endpoint}`);
  };
  const evidence = await produceOwnerEvidence({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, execGh, execAlerts: alerts() });
  assert.equal(evidence.publicArtifacts[0].scanStatus, "COMPLETE");
});

test("receipt reuses the uploaded evidence snapshot without a second live scan", async () => {
  const evidence = await produceOwnerEvidence({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, execGh: gh(), execAlerts: alerts() });
  const transport = artifact(9, { created_at: "2026-08-09T00:00:00.001Z" });
  const archive = zip("evidence.json", JSON.stringify(evidence));
  transport.digest = `sha256:${createHash("sha256").update(archive).digest("hex")}`;
  const result = await produceOwnerReceipt({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, evidenceLocator: LOCATOR, evidence, expectedEvidenceDigest: transport.digest.slice("sha256:".length), evidenceArtifact: transport, execGh: gh({ evidence: transport, evidenceArchive: archive }), execAlerts: async () => { throw new Error("must not rescan"); } });
  assert.deepEqual(result.receipt, { ...evidence, evidenceLocator: LOCATOR });
  await assert.rejects(() => produceOwnerReceipt({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, evidenceLocator: LOCATOR, evidence, expectedEvidenceDigest: `sha256:${"c".repeat(64)}`, evidenceArtifact: transport, execGh: gh() }), /EVIDENCE_TRANSPORT_INVALID/);
});

test("location enumeration accepts the native location shape without invented numeric IDs", async () => {
  const evidence = await produceOwnerEvidence({ repository: REPOSITORY, gitSha: SHA, observedAt: OBSERVED_AT, execGh: gh(), execAlerts: alerts({ open: [{ number: 1 }], locations: [{ type: "commit", details: { path: "safe.txt", start_line: 1 } }] }) });
  assert.equal(evidence.alertEnumerationComplete, true);
  assert.equal(evidence.locationEnumerationComplete, true);
  assert.equal(evidence.openAlertCount, 1);
});
