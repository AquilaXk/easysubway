import assert from "node:assert/strict";
import test from "node:test";

import {
  buildBaselineIngestionGateReport,
  buildRosterFromPack,
} from "./build-baseline-ingestion-gate-report.mjs";

const pack = {
  stations: [
    { id: "station-sadang", nameKo: "사당", normalizedName: "사당" },
    { id: "station-gangnam", nameKo: "강남", normalizedName: "강남" },
    { id: "station-seongsu", nameKo: "성수", normalizedName: "성수" },
  ],
  stationAliases: [{ stationId: "station-sadang", alias: "사당역", normalizedAlias: "사당역" }],
  lines: [
    { id: "seoul-2", nameKo: "수도권 2호선" },
    { id: "seoul-4", nameKo: "수도권 4호선" },
    { id: "shinbundang", nameKo: "신분당선" },
    { id: "seoul-2-branch", nameKo: "수도권 2호선 지선" },
  ],
  stationLines: [
    { stationId: "station-sadang", lineId: "seoul-2" },
    { stationId: "station-sadang", lineId: "seoul-4" },
    { stationId: "station-gangnam", lineId: "seoul-2" },
    { stationId: "station-gangnam", lineId: "shinbundang" },
    { stationId: "station-seongsu", lineId: "seoul-2" },
    { stationId: "station-seongsu", lineId: "seoul-2-branch" },
  ],
  stationPathwayNodes: [
    { id: "n-sadang-2", stationId: "station-sadang", lineId: "seoul-2", nodeType: "PLATFORM" },
    { id: "n-sadang-4", stationId: "station-sadang", lineId: "seoul-4", nodeType: "PLATFORM" },
  ],
  stationPathwayEdges: [
    { id: "e-sadang", fromNodeId: "n-sadang-4", toNodeId: "n-sadang-2", bidirectional: true },
  ],
};

test("buildRosterFromPack: 짧은 lineNameKo 도출('수도권 2호선'→'2호선')", () => {
  const roster = buildRosterFromPack(pack);
  assert.equal(roster.length, 6);
  const sadang2 = roster.find((r) => r.stationId === "station-sadang" && r.lineId === "seoul-2");
  assert.equal(sadang2.lineNameKo, "2호선");
  const branch = roster.find((r) => r.lineId === "seoul-2-branch");
  assert.equal(branch.lineNameKo, "2호선 지선");
  const shinbundang = roster.find((r) => r.lineId === "shinbundang");
  assert.equal(shinbundang.lineNameKo, "신분당선");
});

test("리포트: 수집 전량 기준 coverage + 게이트 + 스코프 metadata", () => {
  const roster = buildRosterFromPack(pack);
  const transferRows = [
    { 연번: 1, 호선: 2, 환승거리: 74, 환승노선: "4호선", 환승소요시간: "01:02", 환승역명: "사당" },
    { 연번: 2, 호선: 4, 환승거리: 74, 환승노선: "2호선", 환승소요시간: "01:02", 환승역명: "사당" },
    { 연번: 3, 호선: 2, 환승거리: 214, 환승노선: "신분당선", 환승소요시간: "02:58", 환승역명: "강남" },
    { 연번: 4, 호선: 2, 환승거리: 23, 환승노선: "2호선", 환승소요시간: "00:19", 환승역명: "성수" },
    { 연번: 5, 호선: 1, 환승거리: 159, 환승노선: "2호선", 환승소요시간: "02:13", 환승역명: "없는역" },
  ];
  const carDoorRows = [
    {
      stnNm: "사당",
      lineNm: "2호선",
      qckgffVhclDoorNo: "3-2",
      upbdnbSe: "상행",
      plfmCmgFac: "계단",
      qckgffMngNo: "1",
      facNo: "1",
    },
    { stnNm: "없는역", lineNm: "9호선", qckgffVhclDoorNo: "1-1", upbdnbSe: "상행", plfmCmgFac: "계단" },
  ];
  const kricMovement = { header: { resultCode: "00", resultCnt: 8 }, body: new Array(8).fill({}) };

  const report = buildBaselineIngestionGateReport({
    roster,
    transferRows,
    carDoorRows,
    kricMovement: {
      ...kricMovement,
    },
    existingEdges: pack.stationPathwayEdges,
    existingNodes: pack.stationPathwayNodes,
  });

  // 스코프 metadata 명기.
  assert.equal(report.metadata.issue, "#1701");
  assert.match(report.metadata.scopeDecision, /비범위/);
  assert.match(report.metadata.scopeDecision, /#1702\/#1414/);
  assert.match(report.metadata.countingBasis, /수집 전량/);

  // coverage: 전량 5행 기준, 사당 양방향+강남 매칭(3), 성수 자기루프 제외, 없는역 quarantine.
  assert.equal(report.coverage.transfer.totalRows, 5);
  assert.equal(report.coverage.transfer.admittedRules, 3);
  assert.equal(report.coverage.transfer.fixtureReflectedRules.count, 2);
  assert.equal(report.coverage.transfer.selfLoopExcludedRules.length, 1);
  assert.equal(report.coverage.transfer.selfLoopExcludedRules[0].stationId, "station-seongsu");
  assert.ok(report.coverage.transfer.quarantinedRows >= 1);

  // 게이트①: 사당 방향쌍 일치(62초 양방향).
  const sadangPair = report.gateInternalConsistency.directionPairReport.find(
    (row) => row.stationId === "station-sadang",
  );
  assert.equal(sadangPair.forwardMinTransferSeconds, 62);
  assert.equal(sadangPair.hasReverse, true);
  assert.equal(sadangPair.secondsMismatch, false);

  // 게이트②: KRIC detailed admitted + 구조 정합.
  assert.equal(report.gateKricStructuralAlignment.kricMovementDetailed.admitted, true);
  assert.equal(report.gateKricStructuralAlignment.kricMovementDetailed.stepCount, 8);
  assert.match(report.gateKricStructuralAlignment.kricStandardResult, /no-data/);

  // 게이트③: OFFICIAL_SOURCE 구분 축.
  assert.equal(report.gateTimeSourceDistinction.provenanceKindAxis, "OFFICIAL_SOURCE");

  // pilot 편차 SKIPPED.
  assert.equal(report.pilotFieldDeviation.status, "SKIPPED");

  // car-door 전량 2행 중 1행 매칭, 1행 quarantine.
  assert.equal(report.coverage.carDoor.totalRows, 2);
  assert.equal(report.coverage.carDoor.admittedHints, 1);
  assert.ok(report.coverage.carDoor.quarantinedRows >= 1);
});

test("게이트②: 충무로 3↔4 baseline 행을 전량에서 추출한다", () => {
  const roster = buildRosterFromPack(pack);
  const transferRows = [
    { 연번: 52, 호선: 3, 환승거리: 17, 환승노선: "4호선", 환승소요시간: "00:14", 환승역명: "충무로" },
    { 연번: 71, 호선: 4, 환승거리: 17, 환승노선: "3호선", 환승소요시간: "00:14", 환승역명: "충무로" },
  ];
  const report = buildBaselineIngestionGateReport({
    roster,
    transferRows,
    carDoorRows: [],
    kricMovement: { header: { resultCode: "00" }, body: [{}] },
  });
  assert.equal(report.gateKricStructuralAlignment.transferBaselineChungmuro.length, 2);
  assert.equal(report.gateKricStructuralAlignment.structurallyAligned, true);
});
