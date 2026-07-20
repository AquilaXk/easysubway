import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { promisify } from "node:util";
import test from "node:test";

import { parseMolitDaejeonStationMappings } from "./build-molit-nationwide-fixture.mjs";
import { materializeBusanRouteTopology, parseCanonicalBusanStationMappings } from "./materialize-busan-route-topology.mjs";
import { materializeBusanTimetable } from "./materialize-busan-timetable.mjs";
import { materializeDaejeonTimetable } from "./materialize-daejeon-timetable.mjs";
import {
  materializeBusanRouteMapPositions,
  materializedBusanRouteMapPackContentHash,
} from "./materialize-busan-route-map-positions.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const topologyNow = new Date("2026-07-19T18:14:03.004Z");
const routeMapNow = new Date("2026-07-20T10:20:00.000Z");

async function inputs() {
  const [
    baseFixture,
    topologySnapshot,
    timetableSnapshot,
    routeMapSnapshot,
    daejeonTopologySnapshot,
    daejeonTimetableSnapshot,
    inventory,
    stationMapCsv,
    molitStationMapCsv,
  ] = await Promise.all([
    readJson("tools/datapack/release/capital-production-reviewed-pack.json"),
    readJson("tools/datapack/sources/busan-transportation-route-topology-20260720.json"),
    readJson("tools/datapack/sources/busan-transportation-timetable-20260720.json"),
    readJson("tools/datapack/sources/busan-transportation-route-map-positions-20260720.json"),
    readJson("tools/datapack/sources/daejeon-route-topology-20260720.json"),
    readJson("tools/datapack/sources/daejeon-train-timetable-20260720.json"),
    readJson("tools/datapack/source-inventory.json"),
    readFile(path.join(root, "tools/datapack/sources/regional-official-svg-route-map-coordinates-20260624.csv"), "utf8"),
    readFile(path.join(root, "tools/datapack/sources/molit-urban-rail-full-route-20251211.csv")),
  ]);
  const topologyFixture = materializeBusanRouteTopology({
    baseFixture,
    snapshot: topologySnapshot,
    inventory,
    canonicalStationMappings: parseCanonicalBusanStationMappings(stationMapCsv),
    now: topologyNow,
  });
  const daejeonFixture = materializeDaejeonTimetable({
    baseFixture: topologyFixture,
    timetableSnapshot: daejeonTimetableSnapshot,
    topologySnapshot: daejeonTopologySnapshot,
    inventory,
    canonicalStationMappings: parseMolitDaejeonStationMappings(molitStationMapCsv),
    now: routeMapNow,
  });
  const timetableFixture = materializeBusanTimetable({
    baseFixture: daejeonFixture,
    timetableSnapshot,
    topologySnapshot,
    inventory,
    now: routeMapNow,
  });
  return { timetableFixture, topologySnapshot, routeMapSnapshot, inventory };
}

test("공식 부산 좌표 snapshot을 누적 production candidate pack에 materialize한다", async () => {
  const { timetableFixture, topologySnapshot, routeMapSnapshot, inventory } = await inputs();
  const fixture = materializeBusanRouteMapPositions({
    baseFixture: timetableFixture,
    snapshot: routeMapSnapshot,
    topologySnapshot,
    inventory,
    now: routeMapNow,
  });
  const pack = fixture.packs[0];
  const rows = pack.routeMapPositions.filter(({ sourceId }) => sourceId === routeMapSnapshot.sourceId);
  const source = pack.sourceInventory.find(({ id }) => id === routeMapSnapshot.sourceId);

  assert.equal(rows.length, 114);
  assert.ok(rows.every(({ labelPolygon }) => labelPolygon.length === 4));
  assert.equal(new Set(rows.map(({ lineId }) => lineId)).size, 4);
  assert.deepEqual(source.coverageScope.lineIds, routeMapSnapshot.lineIds);
  assert.equal(pack.minimumTableRows.route_map_positions, pack.routeMapPositions.length);
  assert.match(pack.id, /^nationwide-busan-route-map-[a-f0-9]{64}$/);
  assert.equal(pack.id, `nationwide-busan-route-map-${materializedBusanRouteMapPackContentHash(pack, pack.version)}`);

  const mismatchedInventory = structuredClone(inventory);
  mismatchedInventory.sources.find(({ id }) => id === routeMapSnapshot.sourceId)
    .routeMapAdmissionEvidence.positionsSha256 = "0".repeat(64);
  assert.throws(
    () => materializeBusanRouteMapPositions({
      baseFixture: timetableFixture,
      snapshot: routeMapSnapshot,
      topologySnapshot,
      inventory: mismatchedInventory,
      now: routeMapNow,
    }),
    /inventory evidence/,
  );
  const incompleteFixture = structuredClone(timetableFixture);
  incompleteFixture.packs[0].stationLines = incompleteFixture.packs[0].stationLines.filter(
    ({ lineId, stationCode }) => !(lineId === "line-ab1a041f6266" && stationCode === "95"),
  );
  assert.throws(
    () => materializeBusanRouteMapPositions({
      baseFixture: incompleteFixture,
      snapshot: routeMapSnapshot,
      topologySnapshot,
      inventory,
      now: routeMapNow,
    }),
    /canonical station scope/,
  );
});

test("materialized SQLite와 provenance가 부산 route_map_positions 4건을 SUPPORTED로 만든다", async (context) => {
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-busan-route-map-pack-"));
  context.after(() => rm(outputDir, { recursive: true, force: true }));
  const fixturePath = path.join(outputDir, "fixture.json");
  const packOutput = path.join(outputDir, "pack");
  const reportPath = path.join(outputDir, "coverage.json");
  const { timetableFixture, topologySnapshot, routeMapSnapshot, inventory } = await inputs();
  const fixture = materializeBusanRouteMapPositions({
    baseFixture: timetableFixture,
    snapshot: routeMapSnapshot,
    topologySnapshot,
    inventory,
    now: routeMapNow,
  });
  await writeFile(fixturePath, `${JSON.stringify(fixture, null, 2)}\n`);
  await mkdir(packOutput, { recursive: true });

  const { privateKey } = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
    publicKeyEncoding: { type: "spki", format: "pem" },
  });
  await execFileAsync(process.execPath, [
    "tools/datapack/build-datapack.mjs", "--fixture", fixturePath, "--output", packOutput,
  ], { cwd: root, env: { ...process.env, EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM: privateKey } });

  const manifestPath = path.join(packOutput, "current.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const sqlitePath = path.join(
    packOutput,
    new URL(manifest.packs[0].url).pathname.split("/").slice(-2).join("/"),
  ).replace(/\.gz$/, "");
  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  assert.equal(database.prepare("SELECT COUNT(*) AS count FROM route_map_positions WHERE source_id = ?")
    .get(routeMapSnapshot.sourceId).count, 114);
  assert.equal(database.prepare("SELECT COUNT(*) AS count FROM route_map_positions WHERE source_id = ? AND label_polygon <> ''")
    .get(routeMapSnapshot.sourceId).count, 114);
  database.close();

  await execFileAsync(process.execPath, [
    "tools/datapack/report-coverage-gaps.mjs",
    "--targets", "tools/datapack/nationwide-coverage-targets.json",
    "--inventory", "tools/datapack/source-inventory.json",
    "--manifest", manifestPath,
    "--provenance", path.join(packOutput, "current.provenance.json"),
    "--resolution-plan", "tools/datapack/release/nationwide-public-api-coverage-search-plan-20260720.json",
    "--resolutions", "tools/datapack/release/nationwide-public-api-coverage-resolutions-20260720.json",
    "--output", reportPath,
    "--allow-gaps",
  ], { cwd: root });
  const report = JSON.parse(await readFile(reportPath, "utf8"));
  const routeMapRequirements = report.requirements.filter(
    ({ operatorId, sourceDomain }) => operatorId === "busan-transportation" && sourceDomain === "route_map_positions",
  );
  assert.equal(routeMapRequirements.length, 4);
  assert.ok(routeMapRequirements.every(({ status }) => status === "SUPPORTED"));
  assert.deepEqual(report.summary.launchRequired, {
    totalCount: 270,
    supportedCount: 19,
    explicitlyUnsupportedCount: 76,
    missingCount: 175,
    supportedRatio: 0.0704,
    terminalResolutionRatio: 0.3519,
    completionReady: false,
  });
});

async function readJson(relativePath) {
  return JSON.parse(await readFile(path.join(root, relativePath), "utf8"));
}
