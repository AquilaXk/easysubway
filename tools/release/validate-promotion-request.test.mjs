import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const script = path.resolve("tools/release/validate-promotion-request.mjs");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

// Break caught: request validation could accept parity evidence whose selected candidate or raw hash is altered.
test("request는 raw parity evidence hash와 selected candidate의 exact identity를 요구한다", () => {
  const fixture = createFixture();
  try {
    assert.equal(run(fixture).status, 0);
    fixture.evidence.selectedCandidateWorkflowRunId = "124";
    writeEvidence(fixture);
    assert.notEqual(run(fixture).status, 0);
  } finally {
    fixture.cleanup();
  }
});

test("validator는 request/approval/compatibility와 parity evidence의 불일치를 거부한다", () => {
  for (const mutate of [
    (fixture) => { fixture.request.extra = true; writeRequest(fixture); },
    (fixture) => { fixture.request.candidate.dataVersion = "other"; writeRequest(fixture); },
    (fixture) => { fixture.workflowRunId = "789"; },
    (fixture) => { fixture.request.approval.reviewer = "other"; writeRequest(fixture); },
    (fixture) => writeFileSync(fixture.approvalPath, JSON.stringify([approvedReview(), approvedReview()])),
    (fixture) => writeFileSync(fixture.compatibilityPath, "changed"),
    (fixture) => replaceCompatibility(fixture, { ...compatibilityValue(fixture.evidence.candidates[0]), decision: "NO_GO" }),
    (fixture) => replaceCompatibility(fixture, { ...compatibilityValue(fixture.evidence.candidates[0]), extra: true }),
    (fixture) => { fixture.evidence.candidates[2].workflowRunId = "124"; writeEvidence(fixture); },
    (fixture) => { fixture.evidence.candidates[1].dataVersion = "other"; writeEvidence(fixture); },
    (fixture) => { fixture.evidence.candidates.reverse(); writeEvidence(fixture); },
    (fixture) => writeFileSync(fixture.evidencePath, "changed"),
  ]) {
    const fixture = createFixture();
    try { mutate(fixture); assert.notEqual(run(fixture).status, 0); } finally { fixture.cleanup(); }
  }
});

test("validator도 inventory의 안전한 경로·정렬·정확한 field를 fail closed한다", () => {
  for (const entries of [
    [],
    [{ path: "z.bin", sizeBytes: 1, sha256: "d".repeat(64) }, { path: "a.bin", sizeBytes: 1, sha256: "d".repeat(64) }],
    [{ path: "/absolute.bin", sizeBytes: 1, sha256: "d".repeat(64) }],
    [{ path: "artifact.bin", sizeBytes: 1, sha256: "d".repeat(64), extra: true }],
  ]) {
    const fixture = createFixture();
    try {
      writeFileSync(fixture.inventoryPath, JSON.stringify({ schemaVersion: 1, artifactKind: "datapack-candidate-inventory", entries }));
      assert.notEqual(run(fixture).status, 0);
    } finally { fixture.cleanup(); }
  }
});

function createFixture() {
  const root = mkdtempSync(path.join(os.tmpdir(), "promotion-validate-"));
  const inventoryBytes = Buffer.from(JSON.stringify(inventoryValue()));
  const components = ["123", "124", "125"].map((workflowRunId) => componentValue(workflowRunId, sha256(inventoryBytes)));
  const compatibilityBytes = Buffer.from(JSON.stringify(compatibilityValue(components[0])));
  const approvalBytes = Buffer.from(JSON.stringify([approvedReview()]));
  const evidence = {
    schemaVersion: 1, artifactKind: "datapack-rebuild-parity-evidence", selectedCandidateWorkflowRunId: "123",
    candidates: components, artifactInventorySha256: sha256(inventoryBytes),
    contractVersion: "datapack-rebuild-parity-v1", issueRef: "AquilaXk/easysubway#2705",
  };
  const evidenceBytes = Buffer.from(JSON.stringify(evidence));
  const request = {
    schemaVersion: 1, artifactKind: "datapack-promotion-request", candidate: structuredClone(components[0]),
    compatibilityEvidenceSha256: sha256(compatibilityBytes), rebuildParityEvidenceSha256: sha256(evidenceBytes),
    requestedBy: "AquilaXk", approval: { workflowRunId: "456", environment: "datapack-promotion", reviewer: "AquilaXk", approvalEvidenceSha256: sha256(approvalBytes) },
    contractVersion: "datapack-promotion-v1", issueRef: "AquilaXk/easysubway#2705",
  };
  return {
    root, request, requestPath: file(root, "request.json", JSON.stringify(request)), componentPath: file(root, "component.json", JSON.stringify(components[0])),
    inventoryPath: file(root, "inventory.json", inventoryBytes), compatibilityPath: file(root, "compatibility.json", compatibilityBytes),
    approvalPath: file(root, "approval.json", approvalBytes), evidence, evidencePath: file(root, "evidence.json", evidenceBytes),
    workflowRunId: "456", cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}

function writeEvidence(fixture) {
  const bytes = Buffer.from(JSON.stringify(fixture.evidence));
  writeFileSync(fixture.evidencePath, bytes);
  fixture.request.rebuildParityEvidenceSha256 = sha256(bytes);
  writeRequest(fixture);
}
function writeRequest(fixture) { writeFileSync(fixture.requestPath, JSON.stringify(fixture.request)); }
function replaceCompatibility(fixture, value) {
  const bytes = Buffer.from(JSON.stringify(value));
  writeFileSync(fixture.compatibilityPath, bytes);
  fixture.request.compatibilityEvidenceSha256 = sha256(bytes);
  writeRequest(fixture);
}
function inventoryValue() { return { schemaVersion: 1, artifactKind: "datapack-candidate-inventory", entries: [{ path: "artifact.bin", sizeBytes: 1, sha256: "d".repeat(64) }] }; }
function approvedReview() { return { state: "approved", environments: [{ name: "datapack-promotion" }], user: { login: "AquilaXk" } }; }
function componentValue(workflowRunId, artifactInventorySha256) { return { schemaVersion: 1, component: "data", repository: "AquilaXk/easysubway-data", gitSha: "a".repeat(40), workflowRunId, dataVersion: "1", releaseSequence: 1, manifestSha256: "b".repeat(64), provenance: { sourceSnapshotSetHash: "c".repeat(64) }, artifactInventorySha256, contractVersion: "datapack-contract-v3", issueRef: "AquilaXk/easysubway#2705" }; }
function compatibilityValue(component) { return { schemaVersion: 1, artifactKind: "datapack-mobile-compatibility-evidence", decision: "PASS", candidate: structuredClone(component) }; }
function file(root, name, value) { const target = path.join(root, name); writeFileSync(target, value); return target; }
function run(fixture) { return spawnSync(process.execPath, [script, "--request", fixture.requestPath, "--component", fixture.componentPath, "--inventory", fixture.inventoryPath, "--compatibility-evidence", fixture.compatibilityPath, "--rebuild-parity-evidence", fixture.evidencePath, "--approval-evidence", fixture.approvalPath, "--workflow-run-id", fixture.workflowRunId], { encoding: "utf8" }); }
