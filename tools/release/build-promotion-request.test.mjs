import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash, createSign, generateKeyPairSync } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { canonicalJson, withoutSignature } from "../datapack/lib/manifest-validation.mjs";

const script = path.resolve("tools/release/build-promotion-request.mjs");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const signingPublicKey = publicKey.export({ type: "spki", format: "pem" });

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
    (fixture) => {
      const manifest = path.join(fixture.roots[0], "catalog", "current.json");
      writeFileSync(manifest, JSON.stringify({ ...JSON.parse(readFileSync(manifest)), signature: { algorithm: "rsa-sha256-manifest-v2", value: "bad" } }));
    },
    (fixture) => rewriteComponent(fixture, 0, { manifestSha256: "e".repeat(64) }),
    (fixture) => writeFileSync(path.join(fixture.roots[0], "current.provenance.json"), JSON.stringify({ schemaVersion: 1, artifactKind: "datapack-field-provenance", candidateBuild: { sourceSnapshotSetHash: "f".repeat(64) } })),
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

test("manifest declared pack 누락과 undeclared sqlite pack을 fail closed한다", () => {
  for (const mutate of [
    (fixture) => fixture.roots.forEach((root) => unlinkSync(path.join(root, "catalog/capital-v1.sqlite.gz"))),
    (fixture) => fixture.roots.forEach((root) => file(root, "catalog/extra.sqlite.gz", "extra")),
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

test("duplicate candidate run IDs는 identity 검증 뒤 parity set에서 거부한다", () => {
  const fixture = createFixture();
  try {
    rewriteComponent(fixture, 2, { workflowRunId: "124" });
    fixture.candidateWorkflowRunIds[2] = "124";
    const result = run(fixture);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /candidate parity is invalid/);
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
  const roots = ["123", "124", "125"].map((workflowRunId, index) => {
    const candidateRoot = path.join(root, `candidate-${index + 1}`);
    file(candidateRoot, "artifact.bin", "artifact");
    file(candidateRoot, "catalog/capital-v1.sqlite.gz", "pack");
    const provenance = { schemaVersion: 1, artifactKind: "datapack-field-provenance", candidateBuild: { sourceSnapshotSetHash: "c".repeat(64) } };
    file(candidateRoot, "current.provenance.json", JSON.stringify(provenance));
    const manifestBytes = Buffer.from(JSON.stringify(productionManifest()));
    file(candidateRoot, "catalog/current.json", manifestBytes);
    const inventoryBytes = Buffer.from(JSON.stringify(inventoryValue(candidateRoot)));
    const component = componentValue(workflowRunId, sha256(inventoryBytes), sha256(manifestBytes));
    file(candidateRoot, "data-component-manifest.json", JSON.stringify(component));
    file(candidateRoot, "data-artifact-inventory.json", inventoryBytes);
    return { root: candidateRoot, component, inventoryBytes };
  });
  const components = roots.map(({ component }) => component);
  const inventoryBytes = roots[0].inventoryBytes;
  const compatibility = compatibilityValue(components[0]);
  const compatibilityBytes = Buffer.from(JSON.stringify(compatibility));
  const approvalBytes = Buffer.from(JSON.stringify([approvedReview()]));
  return {
    root,
    roots: roots.map(({ root: candidateRoot }) => candidateRoot),
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

function refreshCandidateMetadata(fixture) {
  fixture.components = fixture.roots.map((root, index) => {
    const inventoryBytes = Buffer.from(JSON.stringify(inventoryValue(root)));
    const component = componentValue(
      fixture.candidateWorkflowRunIds[index], sha256(inventoryBytes),
      sha256(readFileSync(path.join(root, "catalog/current.json"))),
    );
    writeFileSync(path.join(root, "data-artifact-inventory.json"), inventoryBytes);
    writeFileSync(path.join(root, "data-component-manifest.json"), JSON.stringify(component));
    return component;
  });
  writeFileSync(fixture.compatibilityPath, JSON.stringify(compatibilityValue(fixture.components[0])));
}

function approvedReview() {
  return { state: "approved", environments: [{ name: "datapack-promotion" }], user: { login: "AquilaXk" } };
}

function inventoryValue(root) {
  const entries = ["artifact.bin", "catalog/current.json", "current.provenance.json", "catalog/capital-v1.sqlite.gz", "catalog/extra.sqlite.gz"]
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

function productionManifest() {
  const manifest = {
    manifestVersion: 2, channel: "production", releaseSequence: 1,
    publishedAt: "2026-07-30T00:00:00.000Z", expiresAt: "2026-08-01T00:00:00.000Z",
    keyId: "production-v1", ttlSeconds: 3600, activePack: { id: "capital", version: "1" },
    packs: [{
      id: "capital", version: "1", artifactKind: "production", url: "https://datapack.example.org/catalog/capital-v1.sqlite.gz",
      sha256: "a".repeat(64), sqliteSha256: "b".repeat(64), sizeBytes: 1,
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
    "--candidate-root-1", fixture.roots[0], "--candidate-root-2", fixture.roots[1], "--candidate-root-3", fixture.roots[2],
    "--candidate-workflow-run-id-1", fixture.candidateWorkflowRunIds[0], "--candidate-workflow-run-id-2", fixture.candidateWorkflowRunIds[1], "--candidate-workflow-run-id-3", fixture.candidateWorkflowRunIds[2],
    "--candidate-head-sha-1", fixture.candidateHeadShas[0], "--candidate-head-sha-2", fixture.candidateHeadShas[1], "--candidate-head-sha-3", fixture.candidateHeadShas[2],
    "--selected-candidate-workflow-run-id", fixture.selectedCandidateWorkflowRunId,
    "--compatibility-evidence", fixture.compatibilityPath, "--requested-by", "AquilaXk",
    "--approval-evidence", fixture.approvalPath, "--workflow-run-id", fixture.workflowRunId,
    "--issue-ref", "AquilaXk/easysubway#2705", "--rebuild-parity-evidence-output", fixture.evidenceOutput,
    "--output", fixture.output,
  ], { encoding: "utf8", env: { ...process.env, EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM: signingPublicKey, EASYSUBWAY_DATAPACK_SIGNING_KEY_ID: "production-v1", ...env } });
}
