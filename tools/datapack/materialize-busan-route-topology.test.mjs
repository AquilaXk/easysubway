import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { promisify } from "node:util";
import test from "node:test";

import { materializeBusanRouteTopology } from "./materialize-busan-route-topology.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");

async function inputs() {
  return Promise.all([
    readJson("tools/datapack/release/capital-production-reviewed-pack.json"),
    readJson("tools/datapack/sources/busan-transportation-route-topology-20260720.json"),
    readJson("tools/datapack/source-inventory.json"),
  ]);
}

test("부산 topology snapshot을 실제 production pack 입력으로 materialize한다", async () => {
  const [baseFixture, snapshot, inventory] = await inputs();
  const fixture = materializeBusanRouteTopology({ baseFixture, snapshot, inventory });
  const pack = fixture.packs[0];
  const source = pack.sourceInventory.find(({ id }) => id === snapshot.sourceId);
  const busanEdges = pack.networkEdges.filter(({ sourceId }) => sourceId === snapshot.sourceId);
  const busanStationLines = pack.stationLines.filter(({ sourceId }) => sourceId === snapshot.sourceId);

  assert.deepEqual(fixture.manifest.activePack, { id: pack.id, version: pack.version });
  assert.equal(pack.artifactKind, "production");
  assert.equal(busanEdges.length, 220);
  assert.equal(busanStationLines.length, 114);
  assert.deepEqual(source.coverageScope.lineIds, snapshot.lineIds);
  assert.deepEqual(source.fields, snapshot.fieldsProvided);
  assert.ok(busanEdges.every(({ derivationKind }) => derivationKind === "OFFICIAL"));
  assert.ok(busanEdges.every(
    ({ sourceSnapshotId }) => sourceSnapshotId === "busan-transportation-route-topology-20260720",
  ));
  assert.equal(busanEdges[0].distanceMeters, snapshot.edges[0].distanceMeters);
  assert.equal(busanEdges[0].durationSeconds, snapshot.edges[0].durationSeconds);

  const stale = structuredClone(snapshot);
  stale.freshUntil = "2026-07-19T18:13:31.841Z";
  assert.throws(
    () => materializeBusanRouteTopology({ baseFixture, snapshot: stale, inventory }),
    /freshness|freshUntil|stale/,
  );
});

test("materialized production SQLite와 provenance만 부산 4개 topology requirement를 SUPPORTED로 만든다", async (context) => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-busan-topology-pack-"));
  context.after(() => rm(outputDir, { recursive: true, force: true }));
  const fixturePath = path.join(outputDir, "fixture.json");
  const packOutput = path.join(outputDir, "pack");
  const reportPath = path.join(outputDir, "coverage.json");
  const [baseFixture, snapshot, inventory] = await inputs();
  const fixture = materializeBusanRouteTopology({ baseFixture, snapshot, inventory });
  await writeFile(fixturePath, `${JSON.stringify(fixture, null, 2)}\n`);
  await mkdir(packOutput, { recursive: true });

  const { privateKey } = generateKeyPairSync("rsa", {
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
  const sqlitePath = path.join(packOutput, new URL(manifest.packs[0].url).pathname.split("/").slice(-2).join("/")).replace(/\.gz$/, "");
  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  assert.equal(database.prepare(
    "SELECT COUNT(*) AS count FROM network_edges WHERE source_id = ?",
  ).get(snapshot.sourceId).count, 220);
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
  const busan = report.requirements.filter(({ operatorId }) => operatorId === "busan-transportation");
  assert.deepEqual(
    busan.filter(({ status }) => status === "SUPPORTED").map(({ lineId, sourceDomain }) => ({ lineId, sourceDomain })),
    snapshot.lineIds.map((lineId) => ({ lineId, sourceDomain: "route_graph_topology" })),
  );
});

async function readJson(relativePath) {
  return JSON.parse(await readFile(path.join(root, relativePath), "utf8"));
}
