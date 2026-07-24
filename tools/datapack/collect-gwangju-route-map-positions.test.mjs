import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import {
  collectGwangjuRouteMapPositions,
  parseGwangjuRouteMapPositionsCsv,
  validateGwangjuRouteMapPositionsSnapshot,
} from "./collect-gwangju-route-map-positions.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const FIXTURE_PATH = path.join(root, "tools/datapack/fixtures/gwangju-route-map-positions-raw/data-go-15109340.csv");
const TOPOLOGY_PATH = path.join(root, "tools/datapack/sources/gwangju-transportation-route-topology-20260720.json");
const SNAPSHOT_PATH = path.join(root, "tools/datapack/sources/gwangju-transportation-route-map-positions-20260725.json");
const capturedAt = "2026-07-25T02:00:00.000Z";

async function loadInputs() {
  const [csvBytes, topologySnapshot] = await Promise.all([
    readFile(FIXTURE_PATH),
    readFile(TOPOLOGY_PATH, "utf8").then(JSON.parse),
  ]);
  return { csvBytes, topologySnapshot };
}

test("광주 공식 문화노선도 FILE CSV에서 1호선 20역 좌표 snapshot을 만든다(stationCode join)", async () => {
  const { csvBytes, topologySnapshot } = await loadInputs();
  const snapshot = collectGwangjuRouteMapPositions({
    csvBytes,
    topologySnapshot,
    now: new Date(capturedAt),
  });

  assert.equal(snapshot.artifactKind, "gwangju-route-map-positions-snapshot");
  assert.equal(snapshot.sourceId, "gwangju-transportation-route-map-positions");
  assert.equal(snapshot.datasetId, "15109340");
  assert.deepEqual(snapshot.datasetIds, ["15109340"]);
  assert.equal(snapshot.rawStationCount, 20);
  assert.equal(snapshot.stationCount, 20);
  assert.equal(snapshot.quarantinedCount, 0);
  assert.deepEqual(snapshot.lineStationCounts, { "1": 20 });
  assert.deepEqual(snapshot.lineIds, ["line-e57a361e8892"]);
  assert.deepEqual(snapshot.quarantinedPositions, []);
  assert.equal(snapshot.credentialRequired, false);
  assert.equal(snapshot.credentialRedacted, true);
  assert.equal(snapshot.observedDataUpdatedAt, "2022-12-02");
  assert.equal(snapshot.topologySourceId, "gwangju-transportation-route-topology");
  assert.equal(snapshot.topologySnapshotId, "gwangju-transportation-route-topology-20260720");
  assert.equal(snapshot.topologyContentSha256, topologySnapshot.contentSha256);
  assert.equal(
    snapshot.rawSha256,
    createHash("sha256").update(csvBytes).digest("hex"),
  );
  assert.equal(snapshot.positionsSha256, createHash("sha256").update(JSON.stringify(snapshot.positions)).digest("hex"));

  const munhwa = snapshot.positions.find(({ stationCode }) => stationCode === "104");
  assert.equal(munhwa.stationName, "문화전당");
  assert.equal(munhwa.lineId, "line-e57a361e8892");
  assert.ok(Number.isInteger(munhwa.x) && munhwa.x > 0);
  assert.ok(Number.isInteger(munhwa.y) && munhwa.y > 0);
  assert.equal(munhwa.labelPolygon.length, 4);

  const songjeong = snapshot.positions.find(({ stationCode }) => stationCode === "117");
  assert.equal(songjeong.stationName, "광주송정");

  assert.deepEqual(
    snapshot.positions.map(({ stationCode }) => stationCode),
    Array.from({ length: 20 }, (_, index) => String(100 + index)),
  );
  assert.equal(validateGwangjuRouteMapPositionsSnapshot(snapshot), snapshot);
  assert.doesNotMatch(JSON.stringify(snapshot), /serviceKey/i);
});

test("좌표 누락·topology 미매칭은 fail closed 한다", async () => {
  const { csvBytes, topologySnapshot } = await loadInputs();
  const text = new TextDecoder().decode(csvBytes);
  const lines = text.split(/\r?\n/).filter((line) => line.length > 0);
  const broken = Buffer.from(lines.filter((_, index) => index !== 1).join("\n"), "utf8");
  assert.throws(
    () => parseGwangjuRouteMapPositionsCsv({ csvBytes: broken, topologySnapshot }),
    /station count mismatch|station code scope mismatch|join failed/,
  );
  const unknown = Buffer.from(
    `${lines[0]}\n999,가짜역,S2901,광주도시철도 1호선,Fake,일반역,35.15,126.85,주소,062-000-0000,2022-12-02\n${lines.slice(1).join("\n")}`,
    "utf8",
  );
  assert.throws(
    () => parseGwangjuRouteMapPositionsCsv({ csvBytes: unknown, topologySnapshot }),
    /station count mismatch|join failed|duplicate|scope mismatch/,
  );
});

test("snapshot hash나 좌표가 바뀌면 admission을 거부한다", async () => {
  const { csvBytes, topologySnapshot } = await loadInputs();
  const snapshot = collectGwangjuRouteMapPositions({
    csvBytes,
    topologySnapshot,
    now: new Date(capturedAt),
  });
  const tampered = structuredClone(snapshot);
  tampered.positions[0].x += 1;
  assert.throws(() => validateGwangjuRouteMapPositionsSnapshot(tampered), /invalid Gwangju route map positions snapshot/);
});

test("#2494 inventory·candidate는 snapshot byte identity와 자유 이용 근거를 고정한다", async () => {
  const [snapshotBytes, inventory, candidates] = await Promise.all([
    readFile(SNAPSHOT_PATH),
    readFile(path.join(root, "tools/datapack/source-inventory.json"), "utf8").then(JSON.parse),
    readFile(path.join(root, "tools/datapack/source-candidates.json"), "utf8").then(JSON.parse),
  ]);
  const source = inventory.sources.find(({ id }) => id === "gwangju-transportation-route-map-positions");
  const candidate = candidates.candidates.find(({ id }) => id === source.id);
  assert.equal(source.productionUseAllowed, true);
  assert.equal(source.license.redistributionAllowed, true);
  assert.equal(source.license.derivativeWorkAllowed, true);
  assert.equal(source.license.evidenceUrl, "https://www.data.go.kr/data/15109340/fileData.do");
  assert.equal(source.routeMapAdmissionEvidence.admissionKind, "official-file-latlon");
  assert.equal(source.routeMapAdmissionEvidence.issue, 2494);
  assert.equal(
    source.routeMapAdmissionEvidence.snapshotSha256,
    createHash("sha256").update(snapshotBytes).digest("hex"),
  );
  assert.equal(candidate.admissionStatus, "production_route_map_positions_materialized");
  assert.equal(candidate.apiCatalog, false);
  assert.equal(candidate.evidence.coverageAssessment.requirementCount, 1);
  assert.equal(candidate.evidence.coverageAssessment.state, "SUPPORTED");
  assert.equal(JSON.parse(snapshotBytes).stationCount, 20);
  assert.equal(JSON.parse(snapshotBytes).rawStationCount, 20);
});

test("fixture CSV는 trailing whitespace와 EOF 빈 줄이 없다", async () => {
  const bytes = await readFile(FIXTURE_PATH);
  const text = bytes.toString("utf8");
  assert.equal(text.endsWith("\n"), true);
  assert.equal(text.endsWith("\n\n"), false);
  for (const line of text.split("\n").slice(0, -1)) {
    assert.equal(/[ \t]$/.test(line), false, `trailing whitespace: ${line}`);
  }
});
