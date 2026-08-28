import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash, createSign, generateKeyPairSync } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { canonicalJson, withoutSignature } from "../datapack/lib/manifest-validation.mjs";

const script = path.resolve("tools/release/build-promotion-request.mjs");
const candidateVerifier = path.resolve("tools/release/verify-promotion-candidate-root.mjs");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const signingPublicKey = publicKey.export({ type: "spki", format: "pem" });

// Break caught: accepting a stale inventory or a different run identity would let promotion
// proceed without binding the one immutable candidate to its promotion authorization.
test("단일 data 후보의 raw inventory와 component identity를 v2 request에 묶어 발행한다", () => {
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
      candidateExecutionEvidence: {
        releaseEvidenceBundleSha256: sha256(fixture.releaseEvidenceBundleBytes),
        releaseDecisionSha256: sha256(fixture.releaseDecisionBytes),
      },
      requestedBy: "AquilaXk",
      approval: {
        workflowRunId: "456",
        environment: "datapack-promotion",
        reviewer: "AquilaXk",
        approvalEvidenceSha256: sha256(fixture.approvalBytes),
      },
      contractVersion: "datapack-promotion-v2",
      issueRef: "AquilaXk/easysubway#2705",
    });
  } finally {
    fixture.cleanup();
  }
});

test("candidate root의 symlink·실제 inventory drift·identity·approval·compatibility를 fail closed한다", () => {
  for (const mutate of [
    (fixture) => {
      const component = path.join(fixture.root, "data-component-manifest.json");
      unlinkSync(component);
      symlinkSync(path.join(fixture.root, "current.provenance.json"), component);
    },
    (fixture) => writeFileSync(path.join(fixture.root, "artifact.bin"), "drift"),
    (fixture) => {
      const manifest = path.join(fixture.root, "catalog", "current.json");
      writeFileSync(manifest, JSON.stringify({ ...JSON.parse(readFileSync(manifest)), signature: { algorithm: "rsa-sha256-manifest-v2", value: "bad" } }));
    },
    (fixture) => rewriteComponent(fixture, { manifestSha256: "e".repeat(64) }),
    (fixture) => writeFileSync(path.join(fixture.root, "current.provenance.json"), JSON.stringify({ schemaVersion: 1, artifactKind: "datapack-field-provenance", candidateBuild: { sourceSnapshotSetHash: "f".repeat(64) } })),
    (fixture) => rewriteComponent(fixture, { dataVersion: "other" }),
    (fixture) => { fixture.candidateHeadSha = "f".repeat(40); },
    (fixture) => { fixture.candidateWorkflowRunId = "999"; },
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
    (fixture) => writeFileSync(fixture.compatibilityPath, JSON.stringify({ ...compatibilityValue(fixture.component), decision: "NO_GO" })),
    (fixture) => writeFileSync(fixture.compatibilityPath, JSON.stringify({ ...compatibilityValue(fixture.component), extra: true })),
    (fixture) => file(fixture.executionEvidenceRoot, "extra.json", "extra"),
    (fixture) => unlinkSync(path.join(fixture.executionEvidenceRoot, "release-decision.json")),
    (fixture) => {
      const decision = path.join(fixture.executionEvidenceRoot, "release-decision.json");
      unlinkSync(decision);
      symlinkSync(path.join(fixture.executionEvidenceRoot, "release-evidence-bundle.json"), decision);
    },
    (fixture) => rewriteExecutionEvidence(fixture, "release-evidence-bundle.json", (value) => {
      value.builderGitSha = "f".repeat(40);
    }),
    (fixture) => rewriteExecutionEvidence(fixture, "release-evidence-bundle.json", (value) => {
      value.workflowRunUrl = "https://github.com/AquilaXk/easysubway-data/actions/runs/999";
    }),
    (fixture) => rewriteExecutionEvidence(fixture, "release-evidence-bundle.json", (value) => {
      value.manifestSha256 = "f".repeat(64);
    }),
    (fixture) => rewriteExecutionEvidence(fixture, "release-evidence-bundle.json", (value) => {
      value.candidateServerRouteEvidence.final.sha256 = "invalid";
    }),
    (fixture) => rewriteExecutionEvidence(fixture, "release-decision.json", (value) => {
      value.sourceSnapshotSetHash = "f".repeat(64);
    }),
    (fixture) => rewriteExecutionEvidence(fixture, "release-decision.json", (value) => {
      value.outcome = "NO_CHANGE_VALID";
    }),
    (fixture) => { fixture.workflowRunId = "0"; },
    (fixture) => writeFileSync(fixture.output, "sentinel"),
  ]) assertRejectedWithoutOutputDamage(mutate);
});

test("단일 candidate inventory에는 recorded server route bundle이 필수다", () => {
  const fixture = createFixture();
  try {
    unlinkSync(path.join(fixture.root, "server-route-bundle/manifest.json"));
    refreshCandidateMetadata(fixture);
    assert.notEqual(run(fixture).status, 0);
  } finally {
    fixture.cleanup();
  }
});

test("candidate signature validation key가 없으면 fail closed한다", () => {
  for (const env of [
    { EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM: "" },
    { EASYSUBWAY_DATAPACK_SIGNING_KEY_ID: "" },
  ]) {
    const fixture = createFixture();
    try {
      assert.notEqual(run(fixture, env).status, 0);
    } finally {
      fixture.cleanup();
    }
  }
});

test("standalone candidate verifier는 approved build spec source snapshot set에 결속한다", () => {
  const fixture = createFixture();
  try {
    const approvedSpec = file(path.dirname(fixture.root), "approved-build-spec.json", JSON.stringify({
      sourceSnapshotSetHash: "c".repeat(64),
      builderGitSha: "a".repeat(40),
    }));
    const approved = runCandidateVerifier(fixture, approvedSpec);
    assert.equal(approved.status, 0, approved.stderr);
    const differentSpec = file(path.dirname(fixture.root), "different-build-spec.json", JSON.stringify({
      sourceSnapshotSetHash: "d".repeat(64),
      builderGitSha: "a".repeat(40),
    }));
    const result = runCandidateVerifier(fixture, differentSpec);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /candidate source snapshot set hash does not match build spec/);
    const differentBuilderSpec = file(path.dirname(fixture.root), "different-builder-build-spec.json", JSON.stringify({
      sourceSnapshotSetHash: "c".repeat(64),
      builderGitSha: "b".repeat(40),
    }));
    const builderResult = runCandidateVerifier(fixture, differentBuilderSpec);
    assert.notEqual(builderResult.status, 0);
    assert.match(builderResult.stderr, /candidate builder git SHA does not match build spec/);
  } finally {
    fixture.cleanup();
  }
});

test("manifest declared pack 누락과 undeclared sqlite pack을 fail closed한다", () => {
  for (const mutate of [
    (fixture) => unlinkSync(path.join(fixture.root, "catalog/capital-v1.sqlite.gz")),
    (fixture) => file(fixture.root, "catalog/extra.sqlite.gz", "extra"),
  ]) {
    const fixture = createFixture();
    try {
      mutate(fixture);
      refreshCandidateMetadata(fixture);
      assert.notEqual(run(fixture).status, 0);
    } finally {
      fixture.cleanup();
    }
  }
});

test("signed manifest와 다른 declared pack bytes를 fail closed한다", () => {
  const fixture = createFixture();
  try {
    file(fixture.root, "catalog/capital-v1.sqlite.gz", "replaced");
    refreshCandidateMetadata(fixture);
    assert.notEqual(run(fixture).status, 0);
  } finally {
    fixture.cleanup();
  }
});

test("candidate workflow run ID는 component identity와 exact match해야 한다", () => {
  const fixture = createFixture();
  try {
    rewriteComponent(fixture, { workflowRunId: "124" });
    const result = run(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /candidate inventory is invalid/);
  } finally {
    fixture.cleanup();
  }
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
    writeFileSync(fixture.root + "/data-artifact-inventory.json", JSON.stringify({
      schemaVersion: 1,
      artifactKind: "datapack-candidate-inventory",
      entries,
    }));
  });
});

function assertRejectedWithoutOutputDamage(mutate) {
  const fixture = createFixture();
  try {
    mutate(fixture);
    const priorRequest = exists(fixture.output) ? readFileSync(fixture.output, "utf8") : null;
    assert.notEqual(run(fixture).status, 0);
    assert.equal(priorRequest == null ? exists(fixture.output) : readFileSync(fixture.output, "utf8"), priorRequest ?? false);
  } finally {
    fixture.cleanup();
  }
}

function createFixture() {
  const root = mkdtempSync(path.join(os.tmpdir(), "promotion-build-"));
  const candidateRoot = path.join(root, "candidate");
  file(candidateRoot, "artifact.bin", "artifact");
  file(candidateRoot, "server-route-bundle/manifest.json", "signed-route-bundle");
  file(candidateRoot, "catalog/capital-v1.sqlite.gz", "pack");
  const provenance = { schemaVersion: 1, artifactKind: "datapack-field-provenance", candidateBuild: { sourceSnapshotSetHash: "c".repeat(64) } };
  file(candidateRoot, "current.provenance.json", JSON.stringify(provenance));
  const manifestBytes = Buffer.from(JSON.stringify(productionManifest(readFileSync(path.join(candidateRoot, "catalog/capital-v1.sqlite.gz")))));
  file(candidateRoot, "catalog/current.json", manifestBytes);
  const inventoryBytes = Buffer.from(JSON.stringify(inventoryValue(candidateRoot)));
  const component = componentValue("123", sha256(inventoryBytes), sha256(manifestBytes));
  file(candidateRoot, "data-component-manifest.json", JSON.stringify(component));
  file(candidateRoot, "data-artifact-inventory.json", inventoryBytes);
  const compatibility = compatibilityValue(component);
  const compatibilityBytes = Buffer.from(JSON.stringify(compatibility));
  const approvalBytes = Buffer.from(JSON.stringify([approvedReview()]));
  const executionEvidenceRoot = path.join(root, "candidate-execution-evidence");
  const releaseEvidenceBundleBytes = Buffer.from(JSON.stringify(releaseEvidenceBundleValue(component)));
  const releaseDecisionBytes = Buffer.from(JSON.stringify(releaseDecisionValue(component)));
  file(executionEvidenceRoot, "release-evidence-bundle.json", releaseEvidenceBundleBytes);
  file(executionEvidenceRoot, "release-decision.json", releaseDecisionBytes);
  return {
    root,
    root: candidateRoot,
    component,
    inventoryBytes,
    compatibilityPath: file(root, "compatibility.json", compatibilityBytes),
    compatibilityBytes,
    approvalPath: file(root, "approvals.json", approvalBytes),
    approvalBytes,
    executionEvidenceRoot,
    releaseEvidenceBundleBytes,
    releaseDecisionBytes,
    candidateWorkflowRunId: "123",
    candidateHeadSha: "a".repeat(40),
    workflowRunId: "456",
    output: path.join(root, "request.json"),
    cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}

function releaseEvidenceBundleValue(component) {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-release-evidence-bundle",
    releaseMode: "release-candidate",
    candidateId: "capital@1",
    buildCandidateId: "candidate-1",
    candidateBuilderGitSha: "9".repeat(40),
    builderGitSha: component.gitSha,
    buildSpecSha256: "8".repeat(64),
    manifestSha256: component.manifestSha256,
    releaseSequence: component.releaseSequence,
    sourceSnapshotSetHash: component.provenance.sourceSnapshotSetHash,
    validatorStatus: "PASS",
    manifestSignatureStatus: "PASS",
    createdAt: "2026-08-28T00:00:00.000Z",
    workflowRunUrl: `https://github.com/AquilaXk/easysubway-data/actions/runs/${component.workflowRunId}`,
    candidateServerRouteEvidence: {
      candidateId: "candidate-1",
      sourceSnapshotSetHash: component.provenance.sourceSnapshotSetHash,
      buildSpecSha256: "8".repeat(64),
      manifestSha256: component.manifestSha256,
      eligibility: {
        path: "server-route-bundle-evidence/route-accessibility-eligibility.json",
        sha256: "7".repeat(64),
      },
      final: {
        path: "server-route-bundle-evidence/server-route-bundle-final.json",
        sha256: "6".repeat(64),
      },
    },
  };
}

function releaseDecisionValue(component) {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-release-decision",
    outcome: "CHANGE_BLOCKED",
    productionWriteAllowed: false,
    materialChange: true,
    approvalValid: false,
    strictValidationPassed: true,
    publishRequired: true,
    publishAttempted: false,
    remoteValidationPassed: false,
    sourceSnapshotSetHash: component.provenance.sourceSnapshotSetHash,
    selectedManifestSha256: null,
    selectedReleaseSequence: null,
    reasonCodes: ["MATERIAL_CHANGE_UNAPPROVED"],
    evaluationAt: "2026-08-28T00:00:00.000Z",
  };
}

function rewriteComponent(fixture, patch) {
  fixture.component = { ...fixture.component, ...patch };
  writeFileSync(path.join(fixture.root, "data-component-manifest.json"), JSON.stringify(fixture.component));
}

function rewriteExecutionEvidence(fixture, name, mutate) {
  const target = path.join(fixture.executionEvidenceRoot, name);
  const value = JSON.parse(readFileSync(target));
  mutate(value);
  writeFileSync(target, JSON.stringify(value));
}

function refreshCandidateMetadata(fixture) {
  const inventoryBytes = Buffer.from(JSON.stringify(inventoryValue(fixture.root)));
  fixture.component = componentValue(
    fixture.candidateWorkflowRunId, sha256(inventoryBytes),
    sha256(readFileSync(path.join(fixture.root, "catalog/current.json"))),
  );
  writeFileSync(path.join(fixture.root, "data-artifact-inventory.json"), inventoryBytes);
  writeFileSync(path.join(fixture.root, "data-component-manifest.json"), JSON.stringify(fixture.component));
  writeFileSync(fixture.compatibilityPath, JSON.stringify(compatibilityValue(fixture.component)));
}

function approvedReview() {
  return { state: "approved", environments: [{ name: "datapack-promotion" }], user: { login: "AquilaXk" } };
}

function inventoryValue(root) {
  const entries = ["artifact.bin", "server-route-bundle/manifest.json", "catalog/current.json", "current.provenance.json", "catalog/capital-v1.sqlite.gz", "catalog/extra.sqlite.gz"]
    .filter((entry) => exists(path.join(root, entry))).sort().map((entry) => {
    const bytes = readFileSync(path.join(root, entry));
    return { path: entry, sizeBytes: bytes.length, sha256: sha256(bytes) };
  });
  return {
    schemaVersion: 1,
    artifactKind: "datapack-candidate-inventory",
    entries,
  };
}

function componentValue(workflowRunId, artifactInventorySha256, manifestSha256) {
  return {
    schemaVersion: 1, component: "data", repository: "AquilaXk/easysubway-data", gitSha: "a".repeat(40),
    workflowRunId, dataVersion: "1", releaseSequence: 1, manifestSha256,
    provenance: { sourceSnapshotSetHash: "c".repeat(64) }, artifactInventorySha256,
    contractVersion: "datapack-contract-v3", issueRef: "AquilaXk/easysubway#2705",
  };
}

function productionManifest(packBytes) {
  const manifest = {
    manifestVersion: 2, channel: "production", releaseSequence: 1,
    publishedAt: "2026-07-30T00:00:00.000Z", expiresAt: "2026-08-01T00:00:00.000Z",
    keyId: "production-v1", ttlSeconds: 3600, activePack: { id: "capital", version: "1" },
    packs: [{
      id: "capital", version: "1", artifactKind: "production", url: "https://datapack.example.org/catalog/capital-v1.sqlite.gz",
      sha256: sha256(packBytes), sqliteSha256: "b".repeat(64), sizeBytes: packBytes.length,
      signature: { algorithm: "rsa-sha256-pack-manifest-v2", value: "x" }, schemaVersion: "1",
      sourceInventory: [{ id: "source", owner: "owner", url: "https://data.example.org/source", license: "open", licenseStatus: "redistributable", redistributionAllowed: true, updateFrequency: "daily", updatedAt: "2026-07-30T00:00:00.000Z", fields: ["stations"], coverageScope: { regionIds: ["capital"], operatorIds: ["operator"], sourceDomains: ["data.example.org"] } }],
      regionalQualityMetrics: { stationCount: 1, edgeCount: 1, facilityCoverageRatio: 1, requiredFacilityEvidenceCoverageRatio: 1, strictRouteEligibleFacilityRatio: 1, operationalKnownRatio: 1, freshnessValidRatio: 1, fieldVerifiedPathwayRatio: 1, unknownAccessibilityRatio: 0, unknownEdgeRatioByProfile: { wheelchair: 0, stroller: 0, lowMobility: 0 } },
      representativeRouteRegressions: [], representativeRouteRegressionSignature: { algorithm: "sha256-route-regression-v1", value: "d".repeat(64) },
      requiredTables: ["stations", "station_lines", "network_edges", "facilities", "station_facility_evidence"], minimumTableRows: { stations: 1, station_lines: 1, network_edges: 1, facilities: 1, station_facility_evidence: 1 },
    }],
  };
  manifest.signature = { algorithm: "rsa-sha256-manifest-v2", value: createSign("RSA-SHA256").update(canonicalJson(withoutSignature(manifest))).sign(privateKey).toString("base64url") };
  return manifest;
}

function compatibilityValue(component) {
  return { schemaVersion: 1, artifactKind: "datapack-mobile-compatibility-evidence", decision: "PASS", candidate: structuredClone(component) };
}

function file(root, name, value) {
  const target = path.join(root, name);
  mkdirSync(path.dirname(target), { recursive: true });
  writeFileSync(target, value);
  return target;
}

function exists(target) {
  try { readFileSync(target); return true; } catch { return false; }
}

function run(fixture, env = {}) {
  return spawnSync(process.execPath, [
    script,
    "--candidate-root", fixture.root,
    "--candidate-workflow-run-id", fixture.candidateWorkflowRunId,
    "--candidate-head-sha", fixture.candidateHeadSha,
    "--candidate-execution-evidence-root", fixture.executionEvidenceRoot,
    "--compatibility-evidence", fixture.compatibilityPath, "--requested-by", "AquilaXk",
    "--approval-evidence", fixture.approvalPath, "--workflow-run-id", fixture.workflowRunId,
    "--issue-ref", "AquilaXk/easysubway#2705",
    "--output", fixture.output,
  ], { encoding: "utf8", env: { ...process.env, EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM: signingPublicKey, EASYSUBWAY_DATAPACK_SIGNING_KEY_ID: "production-v1", ...env } });
}

function runCandidateVerifier(fixture, buildSpec) {
  return spawnSync(process.execPath, [
    candidateVerifier,
    "--root", fixture.root,
    "--workflow-run-id", fixture.candidateWorkflowRunId,
    "--git-sha", fixture.candidateHeadSha,
    "--build-spec", buildSpec,
  ], {
    encoding: "utf8",
    env: {
      ...process.env,
      EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM: signingPublicKey,
      EASYSUBWAY_DATAPACK_SIGNING_KEY_ID: "production-v1",
    },
  });
}
