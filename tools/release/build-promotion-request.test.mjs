import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const script = path.resolve("tools/release/build-promotion-request.mjs");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

test("candidate run과 별도 promotion run을 canonical request로 발행한다", () => {
  const fixture = createFixture();
  try {
    const result = run(fixture);
    assert.equal(result.status, 0, result.stderr);
    const request = JSON.parse(readFileSync(fixture.output));
    assert.deepEqual(request, {
      schemaVersion: 1,
      artifactKind: "datapack-promotion-request",
      candidate: fixture.component,
      compatibilityEvidenceSha256: sha256(fixture.compatibilityBytes),
      requestedBy: "AquilaXk",
      approval: {
        workflowRunId: "456",
        environment: "datapack-promotion",
        reviewer: "AquilaXk",
        approvalEvidenceSha256: sha256(fixture.approvalBytes),
      },
      contractVersion: "datapack-promotion-v1",
      issueRef: "AquilaXk/easysubway#2699",
    });
    assert.equal(readFileSync(fixture.output, "utf8"), `${JSON.stringify(request, null, 2)}\n`);
  } finally {
    fixture.cleanup();
  }
});

test("입력 hash, approval, output, symlink, run 경계를 fail closed한다", () => {
  const cases = [
    (fixture) => {
      fixture.component.artifactInventorySha256 = "0".repeat(64);
      writeFileSync(fixture.componentPath, JSON.stringify(fixture.component));
    },
    (fixture) => writeApproval(fixture, [{
      state: "approved",
      environments: [{ name: "datapack-promotion" }, { name: "other" }],
      user: { login: "AquilaXk" },
    }]),
    (fixture) => writeApproval(fixture, [approvedReview(), approvedReview()]),
    (fixture) => writeFileSync(fixture.output, "sentinel"),
    (fixture) => {
      const link = `${fixture.compatibilityPath}.link`;
      symlinkSync(fixture.compatibilityPath, link);
      fixture.compatibilityPath = link;
    },
    (fixture) => writeCompatibility(fixture, { ...fixture.compatibility, decision: "NO_GO" }),
    (fixture) => writeCompatibility(fixture, { ...fixture.compatibility, extra: true }),
    (fixture) => { fixture.workflowRunId = "0"; },
  ];
  for (const mutate of cases) assertRejectedWithoutOutputDamage(mutate);
});

test("inventory는 non-empty sorted unique safe POSIX path만 허용한다", () => {
  const cases = [
    [],
    [entry("b.bin"), entry("a.bin")],
    [entry("a.bin"), entry("a.bin")],
    [entry("/absolute.bin")],
    [entry("nested\\windows.bin")],
    [entry("nested/../escape.bin")],
    [{ ...entry("a.bin"), extra: true }],
  ];
  for (const entries of cases) {
    assertRejectedWithoutOutputDamage((fixture) => replaceInventory(fixture, entries));
  }
});

function assertRejectedWithoutOutputDamage(mutate) {
  const fixture = createFixture();
  try {
    mutate(fixture);
    const prior = exists(fixture.output) ? readFileSync(fixture.output, "utf8") : null;
    assert.notEqual(run(fixture).status, 0);
    if (prior == null) assert.equal(exists(fixture.output), false);
    else assert.equal(readFileSync(fixture.output, "utf8"), prior);
  } finally {
    fixture.cleanup();
  }
}

function createFixture() {
  const root = mkdtempSync(path.join(os.tmpdir(), "promotion-build-"));
  const inventory = inventoryValue();
  const inventoryBytes = Buffer.from(JSON.stringify(inventory));
  const component = componentValue(sha256(inventoryBytes));
  const compatibility = compatibilityValue(component);
  const compatibilityBytes = Buffer.from(JSON.stringify(compatibility));
  const approvalBytes = Buffer.from(JSON.stringify([approvedReview()]));
  return {
    root,
    component,
    componentPath: file(root, "component.json", JSON.stringify(component)),
    inventoryPath: file(root, "inventory.json", inventoryBytes),
    compatibility,
    compatibilityPath: file(root, "compatibility.json", compatibilityBytes),
    compatibilityBytes,
    approvalPath: file(root, "approvals.json", approvalBytes),
    approvalBytes,
    workflowRunId: "456",
    output: path.join(root, "request.json"),
    cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}

function replaceInventory(fixture, entries) {
  const bytes = Buffer.from(JSON.stringify(inventoryValue(entries)));
  writeFileSync(fixture.inventoryPath, bytes);
  fixture.component.artifactInventorySha256 = sha256(bytes);
  writeFileSync(fixture.componentPath, JSON.stringify(fixture.component));
}

function writeApproval(fixture, reviews) {
  writeFileSync(fixture.approvalPath, JSON.stringify(reviews));
}

function writeCompatibility(fixture, value) {
  writeFileSync(fixture.compatibilityPath, JSON.stringify(value));
}

function approvedReview() {
  return { state: "approved", environments: [{ name: "datapack-promotion" }], user: { login: "AquilaXk" } };
}

function inventoryValue(entries = [entry("artifact.bin")]) {
  return { schemaVersion: 1, artifactKind: "datapack-candidate-inventory", entries };
}

function entry(artifactPath) {
  return { path: artifactPath, sizeBytes: 1, sha256: "d".repeat(64) };
}

function componentValue(inventorySha256) {
  return {
    schemaVersion: 1,
    component: "data",
    repository: "AquilaXk/easysubway",
    gitSha: "a".repeat(40),
    workflowRunId: "123",
    dataVersion: "1",
    releaseSequence: 1,
    manifestSha256: "b".repeat(64),
    provenance: { sourceSnapshotSetHash: "c".repeat(64) },
    artifactInventorySha256: inventorySha256,
    contractVersion: "datapack-contract-v3",
    issueRef: "AquilaXk/easysubway#2699",
  };
}

function compatibilityValue(component) {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-mobile-compatibility-evidence",
    decision: "PASS",
    candidate: structuredClone(component),
  };
}

function file(root, name, value) {
  const target = path.join(root, name);
  writeFileSync(target, value);
  return target;
}

function exists(target) {
  try {
    readFileSync(target);
    return true;
  } catch {
    return false;
  }
}

function run(fixture) {
  return spawnSync(process.execPath, [
    script,
    "--component", fixture.componentPath,
    "--inventory", fixture.inventoryPath,
    "--compatibility-evidence", fixture.compatibilityPath,
    "--requested-by", "AquilaXk",
    "--approval-evidence", fixture.approvalPath,
    "--workflow-run-id", fixture.workflowRunId,
    "--issue-ref", "AquilaXk/easysubway#2699",
    "--output", fixture.output,
  ], { encoding: "utf8" });
}
