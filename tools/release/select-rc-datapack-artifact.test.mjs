import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { selectRcDataPackArtifact } from "./select-rc-datapack-artifact.mjs";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

async function fixture(outcome) {
  const root = await mkdtemp(path.join(tmpdir(), "easysubway-rc-datapack-"));
  const catalog = path.join(root, "catalog");
  await mkdir(catalog, { recursive: true });
  const packBytes = Buffer.from(`pack-${outcome}`);
  const manifest = {
    manifestVersion: 2,
    channel: "production",
    releaseSequence: outcome === "PUBLISHED_AND_VERIFIED" ? 12 : 11,
    activePack: { id: "capital", version: "12" },
    packs: [{ id: "capital", version: "12", sha256: sha256(packBytes), sizeBytes: packBytes.length }],
  };
  await writeFile(path.join(catalog, "current.json"), JSON.stringify({
    ...manifest,
    releaseSequence: 12,
    packs: [{
      ...manifest.packs[0],
      sha256: outcome === "PUBLISHED_AND_VERIFIED" ? manifest.packs[0].sha256 : "f".repeat(64),
    }],
  }));
  await writeFile(path.join(root, "current-production.json"), JSON.stringify({ ...manifest, releaseSequence: 11 }));
  await writeFile(path.join(catalog, "capital-v12.sqlite.gz"), packBytes);
  const selectedManifest = outcome === "PUBLISHED_AND_VERIFIED"
    ? await readFile(path.join(catalog, "current.json"))
    : await readFile(path.join(root, "current-production.json"));
  await writeFile(path.join(root, "final-release-decision.json"), JSON.stringify({
    schemaVersion: 1,
    artifactKind: "datapack-release-decision",
    outcome,
    productionWriteAllowed: outcome === "PUBLISHED_AND_VERIFIED",
    strictValidationPassed: true,
    publishAttempted: outcome === "PUBLISHED_AND_VERIFIED",
    remoteValidationPassed: true,
    sourceSnapshotSetHash: "a".repeat(64),
    selectedManifestSha256: sha256(selectedManifest),
    selectedReleaseSequence: outcome === "PUBLISHED_AND_VERIFIED" ? 12 : 11,
    reasonCodes: [],
  }));
  return { root, packBytes };
}

test("PUBLISHED_AND_VERIFIED는 게시 candidate manifest와 일치하는 pack을 선택한다", async () => {
  const { root, packBytes } = await fixture("PUBLISHED_AND_VERIFIED");
  const result = await selectRcDataPackArtifact(root, path.join(root, "selected"));

  assert.equal(result.outcome, "PUBLISHED_AND_VERIFIED");
  assert.equal(JSON.parse(await readFile(result.manifestPath, "utf8")).releaseSequence, 12);
  assert.equal(JSON.parse(await readFile(result.decisionPath, "utf8")).sourceSnapshotSetHash, "a".repeat(64));
  assert.deepEqual(await readFile(result.artifactPath), packBytes);
});

test("NO_CHANGE_VALID는 staged candidate가 아니라 current-production manifest를 선택한다", async () => {
  const { root, packBytes } = await fixture("NO_CHANGE_VALID");
  const result = await selectRcDataPackArtifact(root, path.join(root, "selected"));

  assert.equal(result.outcome, "NO_CHANGE_VALID");
  assert.equal(JSON.parse(await readFile(result.manifestPath, "utf8")).releaseSequence, 11);
  assert.equal(JSON.parse(await readFile(result.decisionPath, "utf8")).sourceSnapshotSetHash, "a".repeat(64));
  assert.deepEqual(await readFile(result.artifactPath), packBytes);
});

test("emergencyOverride가 있으면 activePack보다 override pack을 선택한다", async () => {
  const { root } = await fixture("PUBLISHED_AND_VERIFIED");
  const manifestPath = path.join(root, "catalog/current.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const overrideBytes = Buffer.from("emergency-override-pack");
  manifest.emergencyOverride = { id: "capital-rescue", version: "13", reason: "검증된 긴급 복구" };
  manifest.packs.push({
    id: "capital-rescue",
    version: "13",
    sha256: sha256(overrideBytes),
    sizeBytes: overrideBytes.length,
  });
  await writeFile(manifestPath, JSON.stringify(manifest));
  await writeFile(path.join(root, "catalog/capital-rescue-v13.sqlite.gz"), overrideBytes);
  const decisionPath = path.join(root, "final-release-decision.json");
  const decision = JSON.parse(await readFile(decisionPath, "utf8"));
  decision.selectedManifestSha256 = sha256(await readFile(manifestPath));
  await writeFile(decisionPath, JSON.stringify(decision));

  const result = await selectRcDataPackArtifact(root, path.join(root, "selected"));

  assert.deepEqual(await readFile(result.artifactPath), overrideBytes);
  assert.deepEqual(await readFile(result.fallbackArtifactPath), Buffer.from("pack-PUBLISHED_AND_VERIFIED"));
});

test("decision에 결속된 manifest digest나 sequence가 다르면 거부한다", async () => {
  const digestMismatch = await fixture("NO_CHANGE_VALID");
  const digestDecisionPath = path.join(digestMismatch.root, "final-release-decision.json");
  const digestDecision = JSON.parse(await readFile(digestDecisionPath, "utf8"));
  digestDecision.selectedManifestSha256 = "f".repeat(64);
  await writeFile(digestDecisionPath, JSON.stringify(digestDecision));
  await assert.rejects(
    selectRcDataPackArtifact(digestMismatch.root, path.join(digestMismatch.root, "selected")),
    /selected manifest does not match the final release decision/,
  );

  const sequenceMismatch = await fixture("PUBLISHED_AND_VERIFIED");
  const sequenceDecisionPath = path.join(sequenceMismatch.root, "final-release-decision.json");
  const sequenceDecision = JSON.parse(await readFile(sequenceDecisionPath, "utf8"));
  sequenceDecision.selectedReleaseSequence += 1;
  await writeFile(sequenceDecisionPath, JSON.stringify(sequenceDecision));
  await assert.rejects(
    selectRcDataPackArtifact(sequenceMismatch.root, path.join(sequenceMismatch.root, "selected")),
    /selected manifest does not match the final release decision/,
  );
});

test("activePack이 없으면 런타임과 같이 최신 capital pack을 선택한다", async () => {
  const { root, packBytes } = await fixture("PUBLISHED_AND_VERIFIED");
  const manifestPath = path.join(root, "catalog/current.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  delete manifest.activePack;
  manifest.packs = [
    { id: "capital", version: "11", sha256: "f".repeat(64), sizeBytes: 1 },
    { id: "aux", version: "99", sha256: "e".repeat(64), sizeBytes: 1 },
    manifest.packs[0],
  ];
  await writeFile(manifestPath, JSON.stringify(manifest));
  const decisionPath = path.join(root, "final-release-decision.json");
  const decision = JSON.parse(await readFile(decisionPath, "utf8"));
  decision.selectedManifestSha256 = sha256(await readFile(manifestPath));
  await writeFile(decisionPath, JSON.stringify(decision));

  const result = await selectRcDataPackArtifact(root, path.join(root, "selected-default"));

  assert.deepEqual(await readFile(result.artifactPath), packBytes);
});

test("실패·미검증 decision과 manifest에 결속되지 않은 pack은 거부한다", async () => {
  const failed = await fixture("NO_CHANGE_VALID");
  await writeFile(path.join(failed.root, "final-release-decision.json"), JSON.stringify({
    artifactKind: "datapack-release-decision",
    outcome: "FAILED",
  }));
  await assert.rejects(
    selectRcDataPackArtifact(failed.root, path.join(failed.root, "selected")),
    /final data pack release decision is not RC eligible/,
  );

  const mismatched = await fixture("NO_CHANGE_VALID");
  await writeFile(path.join(mismatched.root, "catalog/capital-v12.sqlite.gz"), "different-pack");
  await assert.rejects(
    selectRcDataPackArtifact(mismatched.root, path.join(mismatched.root, "selected")),
    /exactly one staged pack must match each selected production manifest identity/,
  );
});
