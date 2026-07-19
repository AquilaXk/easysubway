import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { promisify } from "node:util";
import test from "node:test";

import {
  materializeDaejeonRouteTopology,
} from "./materialize-daejeon-route-topology.mjs";
import { parseMolitDaejeonStationMappings } from "./build-molit-nationwide-fixture.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const evidenceNow = new Date("2026-07-19T22:30:00.000Z");

async function inputs() {
  const [baseFixture, snapshot, inventory, stationMapCsv] = await Promise.all([
    readJson("tools/datapack/release/capital-production-reviewed-pack.json"),
    readJson("tools/datapack/sources/daejeon-route-topology-20260720.json"),
    readJson("tools/datapack/source-inventory.json"),
    readFile(path.join(root, "tools/datapack/sources/molit-urban-rail-full-route-20251211.csv")),
  ]);
  return [baseFixture, snapshot, inventory, parseMolitDaejeonStationMappings(stationMapCsv)];
}

test("대전 topology snapshot을 실제 production pack 입력으로 materialize한다", async () => {
  const [baseFixture, snapshot, inventory, canonicalStationMappings] = await inputs();
  const fixture = materializeDaejeonRouteTopology({
    baseFixture, snapshot, inventory, canonicalStationMappings, now: evidenceNow,
  });
  const pack = fixture.packs[0];
  const edges = pack.networkEdges.filter(({ sourceId }) => sourceId === snapshot.sourceId);
  const stationLines = pack.stationLines.filter(({ lineId }) => lineId === "line-7051a9c2525c");

  assert.deepEqual(fixture.manifest.activePack, { id: pack.id, version: pack.version });
  assert.equal(fixture.manifest.releaseSequence, baseFixture.manifest.releaseSequence);
  assert.equal(pack.artifactKind, "production");
  assert.equal(edges.length, 42);
  assert.equal(stationLines.length, 22);
  assert.ok(stationLines.every(({ sourceId }) => sourceId === "molit-urban-rail-full-route"));
  assert.ok(pack.stations
    .filter(({ id }) => stationLines.some(({ stationId }) => stationId === id))
    .every(({ sourceId, dataSourceType }) =>
      sourceId === "molit-urban-rail-full-route" && dataSourceType === "OFFICIAL_FILE"));
  assert.equal(edges.filter(({ fromNodeId, toNodeId }) => fromNodeId < toNodeId)
    .reduce((sum, edge) => sum + edge.durationSeconds, 0), 2_400);
  assert.equal(edges.filter(({ fromNodeId, toNodeId }) => fromNodeId < toNodeId)
    .reduce((sum, edge) => sum + edge.distanceMeters, 0), 20_500);
  assert.ok(edges.every(({ sourceSnapshotId }) => sourceSnapshotId === "daejeon-station-distance-fare-topology-20260720"));
  assert.ok(edges.every(({ derivationKind }) => derivationKind === "OFFICIAL"));
  assert.deepEqual(stationLines.map(({ stationId, stationCode, lineSequence }) => ({ stationId, stationCode, lineSequence })), [
    { stationId: "station-1a68b52a9b0d", stationCode: "101", lineSequence: 1 },
    { stationId: "station-8fa8dda24824", stationCode: "102", lineSequence: 2 },
    { stationId: "station-4a9886a49721", stationCode: "103", lineSequence: 3 },
    { stationId: "station-a8e6a45c3c35", stationCode: "104", lineSequence: 4 },
    { stationId: "station-102781067ad4", stationCode: "105", lineSequence: 5 },
    { stationId: "station-4f6b91cd4b74", stationCode: "106", lineSequence: 6 },
    { stationId: "station-ee3cc9d04ee7", stationCode: "107", lineSequence: 7 },
    { stationId: "station-49f924643e04", stationCode: "108", lineSequence: 8 },
    { stationId: "station-8c3f83ab1056", stationCode: "109", lineSequence: 9 },
    { stationId: "station-961042c194fb", stationCode: "110", lineSequence: 10 },
    { stationId: "station-0e902d05cec4", stationCode: "111", lineSequence: 11 },
    { stationId: "station-b35cc28f2c19", stationCode: "112", lineSequence: 12 },
    { stationId: "station-e0293fcce108", stationCode: "113", lineSequence: 13 },
    { stationId: "station-9affffdcaf16", stationCode: "114", lineSequence: 14 },
    { stationId: "station-18ba692610bf", stationCode: "115", lineSequence: 15 },
    { stationId: "station-6423e0901f89", stationCode: "116", lineSequence: 16 },
    { stationId: "station-11db8e56e157", stationCode: "117", lineSequence: 17 },
    { stationId: "station-5cfb7a665888", stationCode: "118", lineSequence: 18 },
    { stationId: "station-7ee5ea397b9d", stationCode: "119", lineSequence: 19 },
    { stationId: "station-70f297332b8c", stationCode: "120", lineSequence: 20 },
    { stationId: "station-f5572903bf54", stationCode: "121", lineSequence: 21 },
    { stationId: "station-c94180e4d057", stationCode: "122", lineSequence: 22 },
  ]);

  const mismatchedInventory = structuredClone(inventory);
  mismatchedInventory.sources.find(({ id }) => id === snapshot.sourceId)
    .topologyAdmissionEvidence.contentSha256 = "0".repeat(64);
  assert.throws(() => materializeDaejeonRouteTopology({
    baseFixture, snapshot, inventory: mismatchedInventory, canonicalStationMappings, now: evidenceNow,
  }), /inventory evidence/);
  assert.throws(() => materializeDaejeonRouteTopology({
    baseFixture, snapshot, inventory, canonicalStationMappings, now: new Date("2026-07-20T22:12:49.895Z"),
  }), /stale/);
  for (const malformedFreshUntil of [undefined, "not-a-date"]) {
    const malformedInventory = structuredClone(inventory);
    malformedInventory.sources.find(({ id }) => id === snapshot.sourceId)
      .topologyAdmissionEvidence.freshUntil = malformedFreshUntil;
    assert.throws(() => materializeDaejeonRouteTopology({
      baseFixture, snapshot, inventory: malformedInventory, canonicalStationMappings, now: evidenceNow,
    }), /freshUntil is invalid/);
  }
  assert.throws(() => materializeDaejeonRouteTopology({
    baseFixture, snapshot, inventory, canonicalStationMappings, now: new Date("not-a-date"),
  }), /materialization time is invalid/);
});

test("materialized production SQLite와 provenance만 대전 1호선 topology requirement를 SUPPORTED로 만든다", async (context) => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-daejeon-topology-pack-"));
  context.after(() => rm(outputDir, { recursive: true, force: true }));
  const fixturePath = path.join(outputDir, "fixture.json");
  const packOutput = path.join(outputDir, "pack");
  const reportPath = path.join(outputDir, "coverage.json");
  const [baseFixture, snapshot, inventory, canonicalStationMappings] = await inputs();
  const fixture = materializeDaejeonRouteTopology({
    baseFixture, snapshot, inventory, canonicalStationMappings, now: evidenceNow,
  });
  await writeFile(fixturePath, `${JSON.stringify(fixture, null, 2)}\n`);
  await mkdir(packOutput, { recursive: true });

  const { privateKey, publicKey } = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" },
  });
  await execFileAsync(process.execPath, [
    "tools/datapack/build-datapack.mjs", "--fixture", fixturePath, "--output", packOutput,
  ], {
    cwd: root,
    env: { ...process.env, EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM: privateKey },
  });

  const manifestPath = path.join(packOutput, "current.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  await execFileAsync(process.execPath, [
    "tools/datapack/validate-datapack.mjs",
    "--manifest", manifestPath,
    "--root", packOutput,
    "--require-production",
  ], {
    cwd: root,
    env: { ...process.env, EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM: publicKey },
  });
  const sqlitePath = path.join(packOutput, new URL(manifest.packs[0].url).pathname.split("/").slice(-2).join("/")).replace(/\.gz$/, "");
  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  assert.equal(database.prepare("SELECT COUNT(*) AS count FROM network_edges WHERE source_id = ?")
    .get(snapshot.sourceId).count, 42);
  database.close();

  await execFileAsync(process.execPath, [
    "tools/datapack/report-coverage-gaps.mjs",
    "--targets", "tools/datapack/nationwide-coverage-targets.json",
    "--inventory", "tools/datapack/source-inventory.json",
    "--manifest", manifestPath,
    "--provenance", path.join(packOutput, "current.provenance.json"),
    "--output", reportPath,
    "--allow-gaps",
  ], { cwd: root });

  const report = JSON.parse(await readFile(reportPath, "utf8"));
  const daejeon = report.requirements.filter(({ operatorId }) => operatorId === "daejeon-transportation");
  assert.deepEqual(
    daejeon.filter(({ status }) => status === "SUPPORTED").map(({ lineId, sourceDomain }) => ({ lineId, sourceDomain })),
    [{ lineId: "line-7051a9c2525c", sourceDomain: "route_graph_topology" }],
  );
});

async function readJson(relativePath) {
  return JSON.parse(await readFile(path.join(root, relativePath), "utf8"));
}
