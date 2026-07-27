import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash, generateKeyPairSync } from "node:crypto";
import { copyFile, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { promisify } from "node:util";
import test from "node:test";
import { gunzipSync } from "node:zlib";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const env = {
  ...process.env,
  EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM: privateKey.export({ type: "pkcs8", format: "pem" }),
};
const verifierEnv = { ...process.env };
delete verifierEnv.EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM;
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

test("production build와 bundled asset/index의 artifact identity를 exact-match한다", async () => {
  const workspace = await mkdtemp(path.join(tmpdir(), "easysubway-production-pack-identity-"));
  const baselineDir = path.join(workspace, "baseline");
  const assetPath = path.join(workspace, "capital.sqlite.gz");
  const indexPath = path.join(workspace, "index.json");
  try {
    await execFileAsync(process.execPath, [
      "tools/datapack/build-datapack.mjs",
      "--build-spec", "tools/datapack/release/candidate-build-spec.json",
      "--output", baselineDir,
    ], { cwd: root, env });
    const manifest = JSON.parse(await readFile(path.join(baselineDir, "current.json"), "utf8"));
    const pack = manifest.packs.find(({ id }) => id === "capital");
    await copyFile(path.join(baselineDir, "catalog/capital-v1.sqlite.gz"), assetPath);
    const gzipBytes = await readFile(assetPath);
    assert.equal(gzipBytes[9], 255);
    const sqliteBytes = gunzipSync(gzipBytes);
    assert.equal(sqliteBytes.readUInt32BE(96), 3_053_000);
    const sqlitePath = path.join(workspace, "capital.sqlite");
    await writeFile(sqlitePath, sqliteBytes);
    const database = new DatabaseSync(sqlitePath, { readOnly: true });
    try {
      assert.deepEqual(database.prepare(
        "SELECT name FROM sqlite_schema WHERE name LIKE 'sqlite_stat%' ORDER BY name",
      ).all(), []);
      const provenance = database.prepare(`
        SELECT
          SUM(verification_status = 'VERIFIED') AS verifiedCount,
          SUM(verification_status = 'UNKNOWN') AS unknownCount,
          SUM(
            verification_status = 'VERIFIED'
            AND (
              source_id = '' OR source_snapshot_id = '' OR provider_record_hash = ''
              OR provenance_kind != 'OFFICIAL_SOURCE' OR last_verified_at IS NULL
              OR evidence_hash = ''
            )
          ) AS incompleteVerifiedCount,
          SUM(service_class = 'ITX_CHEONGCHUN' AND verification_status = 'VERIFIED') AS verifiedItxCount
        FROM network_edges
      `).get();
      assert.ok(provenance.verifiedCount > 48);
      assert.ok(provenance.unknownCount > 0);
      assert.equal(provenance.incompleteVerifiedCount, 0);
      assert.equal(provenance.verifiedItxCount, 48);
      const unsupportedCapitalLine = database.prepare(`
        SELECT COUNT(*) AS edgeCount,
               SUM(verification_status = 'VERIFIED') AS verifiedCount
        FROM network_edges
        WHERE from_node_id GLOB '*:line-472a81add377'
      `).get();
      assert.ok(unsupportedCapitalLine.edgeCount > 0);
      assert.equal(unsupportedCapitalLine.verifiedCount, 0);
    } finally {
      database.close();
    }
    await writeFile(indexPath, `${JSON.stringify({ packs: [{
      id: "capital",
      sha256: pack.sha256,
      sqliteSha256: pack.sqliteSha256,
      byteSize: pack.sizeBytes,
    }] })}\n`);

    const { stdout } = await execFileAsync(process.execPath, [
      "tools/datapack/verify-production-pack-artifact-identity.mjs",
      "--build-spec", "tools/datapack/release/candidate-build-spec.json",
      "--asset", assetPath,
      "--index", indexPath,
      "--pack-id", "capital",
    ], { cwd: root, env: verifierEnv });
    const report = JSON.parse(stdout);
    assert.equal(report.gzipSha256, pack.sha256);
    assert.equal(report.sqliteSha256, pack.sqliteSha256);
    assert.equal(report.byteSize, pack.sizeBytes);
    assert.ok(report.rowCounts.stations > 0);

    const index = JSON.parse(await readFile(indexPath, "utf8"));
    index.packs[0].sha256 = "f".repeat(64);
    await writeFile(indexPath, `${JSON.stringify(index)}\n`);
    await assert.rejects(
      execFileAsync(process.execPath, [
        "tools/datapack/verify-production-pack-artifact-identity.mjs",
        "--build-spec", "tools/datapack/release/candidate-build-spec.json",
        "--asset", assetPath,
        "--index", indexPath,
        "--pack-id", "capital",
      ], { cwd: root, env: verifierEnv }),
      /index sha256 mismatch/,
    );
  } finally {
    await rm(workspace, { recursive: true, force: true });
  }
});

test("network edge evidence는 pinned bytes·freshness·fixture projection mismatch를 거부한다", async () => {
  const workspace = await mkdtemp(path.join(tmpdir(), "easysubway-network-edge-evidence-"));
  const outputDir = path.join(workspace, "output");
  const spec = JSON.parse(await readFile("tools/datapack/release/candidate-build-spec.json", "utf8"));
  const runRejectedBuild = async (candidate, pattern) => {
    const specPath = path.join(workspace, `spec-${Date.now()}.json`);
    await writeFile(specPath, `${JSON.stringify(candidate, null, 2)}\n`);
    await assert.rejects(execFileAsync(process.execPath, [
      "tools/datapack/build-datapack.mjs",
      "--build-spec", specPath,
      "--output", outputDir,
    ], { cwd: root, env }), pattern);
  };
  try {
    const tampered = structuredClone(spec);
    tampered.networkEdgeEvidence.sourceInventory.sha256 = "f".repeat(64);
    await runRejectedBuild(tampered, /sourceInventory\.sha256 must match tracked input bytes/);

    const staleInventory = JSON.parse(await readFile("tools/datapack/source-inventory.json", "utf8"));
    staleInventory.sources.find(({ routeMapAdmissionEvidence }) =>
      routeMapAdmissionEvidence?.topologySnapshotId === "capital-route-topology-20260724"
    ).routeMapAdmissionEvidence.freshUntil = "2026-07-27T00:00:00.000Z";
    const staleBytes = Buffer.from(`${JSON.stringify(staleInventory, null, 2)}\n`);
    const stalePath = path.join(workspace, "stale-source-inventory.json");
    await writeFile(stalePath, staleBytes);
    const stale = structuredClone(spec);
    stale.networkEdgeEvidence.sourceInventory = { path: stalePath, sha256: sha256(staleBytes) };
    await runRejectedBuild(stale, /capital topology admission is stale/);

    const partialFixture = JSON.parse(await readFile(
      "tools/datapack/release/capital-production-canonical-pack.json",
      "utf8",
    ));
    partialFixture.packs[0].networkEdges.find(({ id }) =>
      id.startsWith("edge-line-051552e50435-")
    ).distanceMeters += 1;
    const partialPath = path.join(workspace, "partial-fixture.json");
    await writeFile(partialPath, `${JSON.stringify(partialFixture)}\n`);
    const partial = structuredClone(spec);
    partial.fixturePath = partialPath;
    await runRejectedBuild(partial, /capital topology fixture projection mismatch/);
  } finally {
    await rm(workspace, { recursive: true, force: true });
  }
});
