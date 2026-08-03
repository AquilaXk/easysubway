import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const script = path.resolve("tools/release/build-promotion-request.mjs");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

// Break caught: accepting one candidate, a stale inventory, or a different run identity
// would let promotion proceed without proving three byte-identical rebuilds.
test("세 data 후보의 raw inventory와 component identity를 묶어 parity evidence와 request를 발행한다", () => {
  const fixture = createFixture();
  try {
    const result = run(fixture);
    assert.equal(result.status, 0, result.stderr);
    const evidenceBytes = readFileSync(fixture.evidenceOutput);
    const evidence = JSON.parse(evidenceBytes);
    assert.deepEqual(evidence, {
      schemaVersion: 1,
      artifactKind: "datapack-rebuild-parity-evidence",
      selectedCandidateWorkflowRunId: "123",
      candidates: fixture.components,
      artifactInventorySha256: sha256(fixture.inventoryBytes),
      contractVersion: "datapack-rebuild-parity-v1",
      issueRef: "AquilaXk/easysubway#2705",
    });
    const request = JSON.parse(readFileSync(fixture.output));
    assert.deepEqual(request, {
      schemaVersion: 1,
      artifactKind: "datapack-promotion-request",
      candidate: fixture.components[0],
      compatibilityEvidenceSha256: sha256(fixture.compatibilityBytes),
      rebuildParityEvidenceSha256: sha256(evidenceBytes),
      requestedBy: "AquilaXk",
      approval: {
        workflowRunId: "456",
        environment: "datapack-promotion",
        reviewer: "AquilaXk",
        approvalEvidenceSha256: sha256(fixture.approvalBytes),
      },
      contractVersion: "datapack-promotion-v1",
      issueRef: "AquilaXk/easysubway#2705",
    });
  } finally {
    fixture.cleanup();
  }
});

test("candidate root의 symlink·실제 inventory drift·identity·approval·compatibility를 fail closed한다", () => {
  for (const mutate of [
    (fixture) => {
      const component = path.join(fixture.roots[1], "data-component-manifest.json");
      unlinkSync(component);
      symlinkSync(path.join(fixture.roots[0], "data-component-manifest.json"), component);
    },
    (fixture) => writeFileSync(path.join(fixture.roots[2], "artifact.bin"), "drift"),
    (fixture) => rewriteComponent(fixture, 2, { workflowRunId: "123" }),
    (fixture) => rewriteComponent(fixture, 1, { dataVersion: "other" }),
    (fixture) => { fixture.candidateHeadShas[1] = "f".repeat(40); },
    (fixture) => { fixture.candidateWorkflowRunIds[2] = "999"; },
    (fixture) => { fixture.selectedCandidateWorkflowRunId = "999"; },
    (fixture) => writeFileSync(fixture.approvalPath, JSON.stringify([{
      ...approvedReview(),
      environments: [{ name: "datapack-promotion" }, { name: "other" }],
    }])),
    (fixture) => writeFileSync(fixture.approvalPath, JSON.stringify([approvedReview(), approvedReview()])),
    (fixture) => {
      const link = `${fixture.compatibilityPath}.link`;
      symlinkSync(fixture.compatibilityPath, link);
      fixture.compatibilityPath = link;
    },
    (fixture) => writeFileSync(fixture.compatibilityPath, JSON.stringify({ ...compatibilityValue(fixture.components[0]), decision: "NO_GO" })),
    (fixture) => writeFileSync(fixture.compatibilityPath, JSON.stringify({ ...compatibilityValue(fixture.components[0]), extra: true })),
    (fixture) => { fixture.workflowRunId = "0"; },
    (fixture) => writeFileSync(fixture.output, "sentinel"),
    (fixture) => writeFileSync(fixture.evidenceOutput, "evidence-sentinel"),
  ]) assertRejectedWithoutOutputDamage(mutate);
});

test("candidate inventory는 safe POSIX path와 exact fields만 허용한다", () => {
  for (const entries of [
    [],
    [{ path: "z.bin", sizeBytes: 1, sha256: "d".repeat(64) }, { path: "a.bin", sizeBytes: 1, sha256: "d".repeat(64) }],
    [{ path: "artifact.bin", sizeBytes: 1, sha256: "d".repeat(64) }, { path: "artifact.bin", sizeBytes: 1, sha256: "d".repeat(64) }],
    [{ path: "/absolute.bin", sizeBytes: 1, sha256: "d".repeat(64) }],
    [{ path: "nested\\windows.bin", sizeBytes: 1, sha256: "d".repeat(64) }],
    [{ path: "nested/../escape.bin", sizeBytes: 1, sha256: "d".repeat(64) }],
    [{ path: "artifact.bin", sizeBytes: 1, sha256: "d".repeat(64), extra: true }],
  ]) assertRejectedWithoutOutputDamage((fixture) => {
    for (const candidateRoot of fixture.roots) {
      writeFileSync(candidateRoot + "/data-artifact-inventory.json", JSON.stringify({
        schemaVersion: 1,
        artifactKind: "datapack-candidate-inventory",
        entries,
      }));
    }
  });
});

function assertRejectedWithoutOutputDamage(mutate) {
  const fixture = createFixture();
  try {
    mutate(fixture);
    const priorEvidence = exists(fixture.evidenceOutput) ? readFileSync(fixture.evidenceOutput, "utf8") : null;
    const priorRequest = exists(fixture.output) ? readFileSync(fixture.output, "utf8") : null;
    assert.notEqual(run(fixture).status, 0);
    assert.equal(priorEvidence == null ? exists(fixture.evidenceOutput) : readFileSync(fixture.evidenceOutput, "utf8"), priorEvidence ?? false);
    assert.equal(priorRequest == null ? exists(fixture.output) : readFileSync(fixture.output, "utf8"), priorRequest ?? false);
  } finally {
    fixture.cleanup();
  }
}

function createFixture() {
  const root = mkdtempSync(path.join(os.tmpdir(), "promotion-build-"));
  const inventoryBytes = Buffer.from(JSON.stringify(inventoryValue("artifact")));
  const components = ["123", "124", "125"].map((workflowRunId) => componentValue(workflowRunId, sha256(inventoryBytes)));
  const roots = components.map((component, index) => {
    const candidateRoot = path.join(root, `candidate-${index + 1}`);
    file(candidateRoot, "artifact.bin", "artifact");
    file(candidateRoot, "data-component-manifest.json", JSON.stringify(component));
    file(candidateRoot, "data-artifact-inventory.json", inventoryBytes);
    return candidateRoot;
  });
  const compatibility = compatibilityValue(components[0]);
  const compatibilityBytes = Buffer.from(JSON.stringify(compatibility));
  const approvalBytes = Buffer.from(JSON.stringify([approvedReview()]));
  return {
    root,
    roots,
    components,
    inventoryBytes,
    compatibilityPath: file(root, "compatibility.json", compatibilityBytes),
    compatibilityBytes,
    approvalPath: file(root, "approvals.json", approvalBytes),
    approvalBytes,
    selectedCandidateWorkflowRunId: "123",
    candidateWorkflowRunIds: ["123", "124", "125"],
    candidateHeadShas: ["a".repeat(40), "a".repeat(40), "a".repeat(40)],
    workflowRunId: "456",
    evidenceOutput: path.join(root, "rebuild-parity-evidence.json"),
    output: path.join(root, "request.json"),
    cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}

function rewriteComponent(fixture, index, patch) {
  fixture.components[index] = { ...fixture.components[index], ...patch };
  writeFileSync(path.join(fixture.roots[index], "data-component-manifest.json"), JSON.stringify(fixture.components[index]));
}

function approvedReview() {
  return { state: "approved", environments: [{ name: "datapack-promotion" }], user: { login: "AquilaXk" } };
}

function inventoryValue(contents) {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-candidate-inventory",
    entries: [{ path: "artifact.bin", sizeBytes: Buffer.byteLength(contents), sha256: sha256(contents) }],
  };
}

function componentValue(workflowRunId, artifactInventorySha256) {
  return {
    schemaVersion: 1, component: "data", repository: "AquilaXk/easysubway-data", gitSha: "a".repeat(40),
    workflowRunId, dataVersion: "1", releaseSequence: 1, manifestSha256: "b".repeat(64),
    provenance: { sourceSnapshotSetHash: "c".repeat(64) }, artifactInventorySha256,
    contractVersion: "datapack-contract-v3", issueRef: "AquilaXk/easysubway#2705",
  };
}

function compatibilityValue(component) {
  return { schemaVersion: 1, artifactKind: "datapack-mobile-compatibility-evidence", decision: "PASS", candidate: structuredClone(component) };
}

function file(root, name, value) {
  mkdirSync(root, { recursive: true });
  const target = path.join(root, name);
  writeFileSync(target, value);
  return target;
}

function exists(target) {
  try { readFileSync(target); return true; } catch { return false; }
}

function run(fixture) {
  return spawnSync(process.execPath, [
    script,
    "--candidate-root-1", fixture.roots[0], "--candidate-root-2", fixture.roots[1], "--candidate-root-3", fixture.roots[2],
    "--candidate-workflow-run-id-1", fixture.candidateWorkflowRunIds[0], "--candidate-workflow-run-id-2", fixture.candidateWorkflowRunIds[1], "--candidate-workflow-run-id-3", fixture.candidateWorkflowRunIds[2],
    "--candidate-head-sha-1", fixture.candidateHeadShas[0], "--candidate-head-sha-2", fixture.candidateHeadShas[1], "--candidate-head-sha-3", fixture.candidateHeadShas[2],
    "--selected-candidate-workflow-run-id", fixture.selectedCandidateWorkflowRunId,
    "--compatibility-evidence", fixture.compatibilityPath, "--requested-by", "AquilaXk",
    "--approval-evidence", fixture.approvalPath, "--workflow-run-id", fixture.workflowRunId,
    "--issue-ref", "AquilaXk/easysubway#2705", "--rebuild-parity-evidence-output", fixture.evidenceOutput,
    "--output", fixture.output,
  ], { encoding: "utf8" });
}
