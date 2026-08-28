import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const script = path.resolve("tools/release/validate-promotion-request.mjs");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

// Break caught: request validation could accept a component or inventory whose exact candidate identity is altered.
test("request는 단일 candidate의 exact identity를 요구한다", () => {
  const fixture = createFixture();
  try {
    const valid = run(fixture);
    assert.equal(valid.status, 0, valid.stderr);
    fixture.request.candidate.workflowRunId = "124";
    writeRequest(fixture);
    assert.notEqual(run(fixture).status, 0);
  } finally {
    fixture.cleanup();
  }
});

test("validator는 유효한 compatibility evidence와 다른 request evidence hash를 거부한다", () => {
  const fixture = createFixture();
  try {
    fixture.request.compatibilityEvidenceSha256 = "d".repeat(64);
    writeRequest(fixture);
    assert.notEqual(run(fixture).status, 0);
  } finally {
    fixture.cleanup();
  }
});

test("validator는 execution evidence를 candidate run/head/manifest/source identity에 결속한다", () => {
  for (const [name, mutate] of [
    ["release-evidence-bundle.json", (value) => { value.builderGitSha = "f".repeat(40); }],
    ["release-evidence-bundle.json", (value) => { value.workflowRunUrl = "https://github.com/AquilaXk/easysubway-data/actions/runs/999"; }],
    ["release-evidence-bundle.json", (value) => { value.manifestSha256 = "f".repeat(64); }],
    ["release-evidence-bundle.json", (value) => { value.candidateServerRouteEvidence.buildSpecSha256 = "f".repeat(64); }],
    ["release-decision.json", (value) => { value.sourceSnapshotSetHash = "f".repeat(64); }],
    ["release-decision.json", (value) => { value.outcome = "NO_CHANGE_VALID"; }],
  ]) {
    const fixture = createFixture();
    try {
      const target = path.join(fixture.executionEvidenceRoot, name);
      const value = JSON.parse(readFileSync(target));
      mutate(value);
      writeFileSync(target, JSON.stringify(value));
      assert.notEqual(run(fixture).status, 0);
    } finally { fixture.cleanup(); }
  }
});

test("validator는 선택되지 않은 release decision의 부분 selection identity를 거부한다", () => {
  for (const outcome of [
    { name: "CHANGE_BLOCKED", values: {} },
    {
      name: "PUBLISH_REQUIRED",
      values: {
        outcome: "PUBLISH_REQUIRED",
        productionWriteAllowed: true,
        materialChange: false,
        approvalValid: true,
      },
    },
    { name: "FAILED", values: { outcome: "FAILED", strictValidationPassed: false } },
  ]) {
    for (const partialSelection of [
      { selectedManifestSha256: "f".repeat(64), selectedReleaseSequence: null },
      { selectedManifestSha256: null, selectedReleaseSequence: 1 },
    ]) {
      const fixture = createFixture();
      try {
        const decision = JSON.parse(readFileSync(path.join(fixture.executionEvidenceRoot, "release-decision.json")));
        Object.assign(decision, outcome.values, partialSelection);
        writeReleaseDecision(fixture, decision);
        assert.notEqual(run(fixture).status, 0, `${outcome.name} accepted partial selection identity`);
      } finally { fixture.cleanup(); }
    }
  }
});

test("validator는 request/approval/compatibility와 candidate의 불일치를 거부한다", () => {
  for (const mutate of [
    (fixture) => { fixture.request.extra = true; writeRequest(fixture); },
    (fixture) => { fixture.request.candidate.dataVersion = "other"; writeRequest(fixture); },
    (fixture) => { fixture.workflowRunId = "789"; },
    (fixture) => { fixture.request.approval.reviewer = "other"; writeRequest(fixture); },
    (fixture) => writeFileSync(fixture.approvalPath, JSON.stringify([approvedReview(), approvedReview()])),
    (fixture) => writeFileSync(fixture.compatibilityPath, "changed"),
    (fixture) => replaceCompatibility(fixture, { ...compatibilityValue(fixture.component), decision: "NO_GO" }),
    (fixture) => replaceCompatibility(fixture, { ...compatibilityValue(fixture.component), extra: true }),
    (fixture) => { fixture.component.workflowRunId = "124"; writeComponent(fixture); },
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

test("validator는 server route bundle 없는 hand-built inventory를 거부한다", () => {
  const fixture = createFixture();
  try {
    rebindInventory(fixture, { schemaVersion: 1, artifactKind: "datapack-candidate-inventory", entries: [{ path: "artifact.bin", sizeBytes: 1, sha256: "d".repeat(64) }] });
    const result = run(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /inventory server route bundle is required/);
  } finally { fixture.cleanup(); }
});

function createFixture() {
  const root = mkdtempSync(path.join(os.tmpdir(), "promotion-validate-"));
  const inventoryBytes = Buffer.from(JSON.stringify(inventoryValue()));
  const component = componentValue("123", sha256(inventoryBytes));
  const compatibilityBytes = Buffer.from(JSON.stringify(compatibilityValue(component)));
  const approvalBytes = Buffer.from(JSON.stringify([approvedReview()]));
  const executionEvidenceRoot = path.join(root, "candidate-execution-evidence");
  const releaseEvidenceBundleBytes = Buffer.from(JSON.stringify(releaseEvidenceBundleValue(component)));
  const releaseDecisionBytes = Buffer.from(JSON.stringify(releaseDecisionValue(component)));
  file(executionEvidenceRoot, "release-evidence-bundle.json", releaseEvidenceBundleBytes);
  file(executionEvidenceRoot, "release-decision.json", releaseDecisionBytes);
  const request = {
    schemaVersion: 1, artifactKind: "datapack-promotion-request", candidate: structuredClone(component),
    compatibilityEvidenceSha256: sha256(compatibilityBytes),
    candidateExecutionEvidence: {
      releaseEvidenceBundleSha256: sha256(releaseEvidenceBundleBytes),
      releaseDecisionSha256: sha256(releaseDecisionBytes),
    },
    requestedBy: "AquilaXk", approval: { workflowRunId: "456", environment: "datapack-promotion", reviewer: "AquilaXk", approvalEvidenceSha256: sha256(approvalBytes) },
    contractVersion: "datapack-promotion-v2", issueRef: "AquilaXk/easysubway#2705",
  };
  return {
    root, request, component, requestPath: file(root, "request.json", JSON.stringify(request)), componentPath: file(root, "component.json", JSON.stringify(component)),
    inventoryPath: file(root, "inventory.json", inventoryBytes), compatibilityPath: file(root, "compatibility.json", compatibilityBytes),
    approvalPath: file(root, "approval.json", approvalBytes),
    executionEvidenceRoot,
    workflowRunId: "456", cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}

function writeComponent(fixture) { writeFileSync(fixture.componentPath, JSON.stringify(fixture.component)); }
function writeRequest(fixture) { writeFileSync(fixture.requestPath, JSON.stringify(fixture.request)); }
function writeReleaseDecision(fixture, value) {
  const bytes = Buffer.from(JSON.stringify(value));
  writeFileSync(path.join(fixture.executionEvidenceRoot, "release-decision.json"), bytes);
  fixture.request.candidateExecutionEvidence.releaseDecisionSha256 = sha256(bytes);
  writeRequest(fixture);
}
function replaceCompatibility(fixture, value) {
  const bytes = Buffer.from(JSON.stringify(value));
  writeFileSync(fixture.compatibilityPath, bytes);
  fixture.request.compatibilityEvidenceSha256 = sha256(bytes);
  writeRequest(fixture);
}
function rebindInventory(fixture, value) {
  const bytes = Buffer.from(JSON.stringify(value));
  const artifactInventorySha256 = sha256(bytes);
  const component = componentValue("123", artifactInventorySha256);
  writeFileSync(fixture.inventoryPath, bytes);
  writeFileSync(fixture.componentPath, JSON.stringify(component));
  fixture.component = component;
  fixture.request.candidate = structuredClone(component);
  replaceCompatibility(fixture, compatibilityValue(component));
  writeRequest(fixture);
}
function inventoryValue() { return { schemaVersion: 1, artifactKind: "datapack-candidate-inventory", entries: [{ path: "artifact.bin", sizeBytes: 1, sha256: "d".repeat(64) }, { path: "server-route-bundle/manifest.json", sizeBytes: 1, sha256: "e".repeat(64) }] }; }
function approvedReview() { return { state: "approved", environments: [{ name: "datapack-promotion" }], user: { login: "AquilaXk" } }; }
function componentValue(workflowRunId, artifactInventorySha256) { return { schemaVersion: 1, component: "data", repository: "AquilaXk/easysubway-data", gitSha: "a".repeat(40), workflowRunId, dataVersion: "1", releaseSequence: 1, manifestSha256: "b".repeat(64), provenance: { sourceSnapshotSetHash: "c".repeat(64) }, artifactInventorySha256, contractVersion: "datapack-contract-v3", issueRef: "AquilaXk/easysubway#2705" }; }
function compatibilityValue(component) { return { schemaVersion: 1, artifactKind: "datapack-mobile-compatibility-evidence", decision: "PASS", candidate: structuredClone(component) }; }
function releaseEvidenceBundleValue(component) {
  return {
    schemaVersion: 1, artifactKind: "datapack-release-evidence-bundle", releaseMode: "release-candidate",
    candidateId: "capital@1", buildCandidateId: "candidate-1", candidateBuilderGitSha: "9".repeat(40),
    builderGitSha: component.gitSha, buildSpecSha256: "8".repeat(64), manifestSha256: component.manifestSha256,
    releaseSequence: component.releaseSequence, sourceSnapshotSetHash: component.provenance.sourceSnapshotSetHash,
    validatorStatus: "PASS", manifestSignatureStatus: "PASS", createdAt: "2026-08-28T00:00:00.000Z",
    workflowRunUrl: `https://github.com/AquilaXk/easysubway-data/actions/runs/${component.workflowRunId}`,
    candidateServerRouteEvidence: {
      candidateId: "candidate-1", sourceSnapshotSetHash: component.provenance.sourceSnapshotSetHash,
      buildSpecSha256: "8".repeat(64), manifestSha256: component.manifestSha256,
      eligibility: { path: "server-route-bundle-evidence/route-accessibility-eligibility.json", sha256: "7".repeat(64) },
      final: { path: "server-route-bundle-evidence/server-route-bundle-final.json", sha256: "6".repeat(64) },
    },
  };
}
function releaseDecisionValue(component) {
  return {
    schemaVersion: 1, artifactKind: "datapack-release-decision", outcome: "CHANGE_BLOCKED",
    productionWriteAllowed: false, materialChange: true, approvalValid: false, strictValidationPassed: true,
    publishRequired: true, publishAttempted: false, remoteValidationPassed: false,
    sourceSnapshotSetHash: component.provenance.sourceSnapshotSetHash,
    selectedManifestSha256: null, selectedReleaseSequence: null,
    reasonCodes: ["MATERIAL_CHANGE_UNAPPROVED"], evaluationAt: "2026-08-28T00:00:00.000Z",
  };
}
function file(root, name, value) { const target = path.join(root, name); mkdirSync(path.dirname(target), { recursive: true }); writeFileSync(target, value); return target; }
function run(fixture) { return spawnSync(process.execPath, [script, "--request", fixture.requestPath, "--component", fixture.componentPath, "--inventory", fixture.inventoryPath, "--compatibility-evidence", fixture.compatibilityPath, "--approval-evidence", fixture.approvalPath, "--candidate-execution-evidence-root", fixture.executionEvidenceRoot, "--workflow-run-id", fixture.workflowRunId], { encoding: "utf8" }); }
