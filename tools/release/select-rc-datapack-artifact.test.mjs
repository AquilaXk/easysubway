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
  await writeFile(path.join(root, "final-release-decision.json"), JSON.stringify({
    schemaVersion: 1,
    artifactKind: "datapack-release-decision",
    outcome,
    productionWriteAllowed: outcome === "PUBLISHED_AND_VERIFIED",
    strictValidationPassed: true,
    publishAttempted: outcome === "PUBLISHED_AND_VERIFIED",
    remoteValidationPassed: true,
    sourceSnapshotSetHash: "a".repeat(64),
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
    /exactly one staged pack must match the selected production manifest/,
  );
});
