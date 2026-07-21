import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { DAEGU_LINES, decodeOfficialCsv, normalizedStationName } from "./collect-daegu-datapack-sources.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const readSnapshot = async (name) => JSON.parse(await readFile(path.join(root, "tools/datapack/sources", name), "utf8"));

// 공식 원문 파일별 SHA-256(이슈 #2407 표) — 취득 원문 identity 고정
const RAW_SHA256 = {
  1: { topology: "29398e8792899bc614c8e6563b0f4eaf1fec5182668b89d29045409395aae5c5",
    up: "892b8d397ef917a07851d4a2b33d375a6973df4c19ddadbaff52137f84c9d4e0",
    dn: "3c858a4f8f0ba792635f5bc03fd6e0e7450eb7c853147972529d72cf5ae45c43" },
  2: { topology: "80ea59d739c3a327e1242c67ae9b400f4d393b8acd202ec4a26e9e737f1123c0",
    up: "000c341909c1628f0664b50beef60d232cfae21e38b474467689fddf3b7ad1d8",
    dn: "3b0189ee63f54f313284d0ead497da9a1bb804e7c60499f2c18cf2b27c972dde" },
  3: { topology: "844329649f860449b84e34e2af3841a16387fd39c9b313593bfc850f479eddf7",
    up: "092c4041cffaea99c9dff56671dda2d0de025ced143d1effdcff95c89cb1d42b",
    dn: "a2a3d8ad68decc30222d431eb437799d011cdf3d7f60bff8db2f417300b20bd5" },
};

test("파일별 인코딩(EUC-KR·UTF-8 BOM·UTF-8)을 역명 손상 없이 정규화한다", () => {
  // EUC-KR(cp949)로 인코딩된 "역코드"(bf aa c4 da b5 e5)는 UTF-8로 유효하지 않아 cp949 fallback으로 복원된다.
  assert.equal(decodeOfficialCsv(Buffer.from("bfaac4dab5e5", "hex")), "역코드");
  // UTF-8 BOM은 제거하고, BOM 없는 UTF-8은 그대로 읽는다.
  assert.equal(decodeOfficialCsv(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from("역명", "utf8")])), "역명");
  assert.equal(decodeOfficialCsv(Buffer.from("역명", "utf8")), "역명");
  assert.throws(() => decodeOfficialCsv(Buffer.alloc(0)), /required/);
});

test("환승역 접미 숫자·괄호 부기·축약형을 정본 역명으로 정규화한다", () => {
  assert.equal(normalizedStationName("반월당1"), normalizedStationName("반월당"));
  assert.equal(normalizedStationName("청라언덕2"), normalizedStationName("청라언덕3"));
  assert.equal(normalizedStationName("명덕(2.28민주운동기념회관)"), normalizedStationName("명덕3"));
  assert.equal(normalizedStationName("성서산업단지"), normalizedStationName("성서산단"));
  assert.equal(normalizedStationName("대곡(정부대구청사)"), normalizedStationName("대곡"));
});

test("고정된 대구 topology snapshot 6종이 취득 원문·내부 해시·노선 완전성과 일치한다", async () => {
  for (const config of DAEGU_LINES) {
    const topology = await readSnapshot(`daegu-line${config.lineNumber}-route-topology-20260721.json`);
    assert.equal(topology.artifactKind, "daegu-route-topology-snapshot");
    assert.equal(topology.lineId, config.lineId);
    assert.equal(topology.rawSha256, RAW_SHA256[config.lineNumber].topology);
    assert.equal(topology.stationCount, config.stationCount);
    assert.equal(topology.scope.length, config.stationCount);
    assert.equal(topology.edgeCount, config.edgeCount);
    assert.equal(topology.edges.length, config.edgeCount);
    assert.equal(topology.scopeSha256, sha256(JSON.stringify(topology.scope)));
    assert.equal(topology.edgesSha256, sha256(JSON.stringify(topology.edges)));
    assert.equal(topology.contentSha256, sha256(JSON.stringify({ scope: topology.scope, edges: topology.edges })));
    // 인접 edge는 양방향이며 거리가 대칭이고 소요시간이 양수다.
    const distances = new Map();
    for (const edge of topology.edges) {
      assert.ok(Number.isInteger(edge.distanceMeters) && edge.distanceMeters > 0);
      assert.ok(Number.isInteger(edge.durationSeconds) && edge.durationSeconds > 0);
      distances.set([edge.fromStationCode, edge.toStationCode].sort((a, b) => a.localeCompare(b, "en")).join(":"), edge.distanceMeters);
    }
    assert.equal(distances.size, config.edgeCount / 2);
    // 차량기지·비영업 행은 exact tuple로 격리되고 scope에 포함되지 않는다.
    const scopeCodes = new Set(topology.scope.map(({ stationCode }) => stationCode));
    for (const depot of topology.quarantinedDepots) {
      assert.equal(depot.stationType, "차량기지");
      assert.ok(!scopeCodes.has(depot.stationCode));
    }
    assert.equal(topology.depotExcludedCount, topology.quarantinedDepots.length);
  }
});

test("고정된 대구 시각표 snapshot 3종이 취득 원문·trip 완전성·원문 결함 정규화를 고정한다", async () => {
  const expectedDayLabelNormalized = { 1: 0, 2: 55, 3: 0 };
  const expectedRollover = { 1: 12, 2: 9, 3: 6 };
  for (const config of DAEGU_LINES) {
    const timetable = await readSnapshot(`daegu-line${config.lineNumber}-train-timetable-20260721.json`);
    assert.equal(timetable.artifactKind, "daegu-train-timetable-snapshot");
    assert.equal(timetable.lineId, config.lineId);
    assert.equal(timetable.rawUpSha256, RAW_SHA256[config.lineNumber].up);
    assert.equal(timetable.rawDownSha256, RAW_SHA256[config.lineNumber].dn);
    assert.equal(timetable.tripCount, config.tripCount);
    assert.equal(timetable.trips.length, config.tripCount);
    assert.equal(timetable.tripsSha256, sha256(JSON.stringify(timetable.trips)));
    assert.equal(timetable.contentSha256, sha256(JSON.stringify({
      tripsSha256: timetable.tripsSha256, stopTimeCount: timetable.stopTimeCount, stationCount: config.stationCount,
    })));
    assert.deepEqual(timetable.dayCodes, ["WEEK", "SAT", "HOLI"]);
    assert.deepEqual(timetable.directions, ["up", "dn"]);
    // 2호선 하선 파일의 휴일(상) 오라벨 행은 파일 방향(하)으로 정규화한 건수로 고정한다.
    assert.equal(timetable.dayLabelNormalizedCount, expectedDayLabelNormalized[config.lineNumber]);
    // 자정을 넘는 막차만 24시 이후 service second로 rollover 한다.
    assert.equal(timetable.rolloverTripCount, expectedRollover[config.lineNumber]);
    let stopTotal = 0;
    for (const trip of timetable.trips) {
      assert.ok(trip.stops.length >= 2);
      let previous = -1;
      for (const stop of trip.stops) {
        assert.ok(stop.a >= previous && stop.d >= stop.a);
        previous = stop.d;
      }
      stopTotal += trip.stops.length;
    }
    assert.equal(stopTotal, config.stopTimeCount);
  }
});
