import assert from "node:assert/strict";
import test from "node:test";

import { applyLine4RoutingGraph } from "./apply-kric-line4-pilot-schedule.mjs";

const SELF_DRAWN_SOURCE_ID = "easysubway-owner-route-map-capital";

test("4호선 corridor는 중간역을 pass-through로 두고 인접 RIDE·도식 좌표를 만든다", () => {
  const input = {
    sourceIds: ["molit-urban-rail-full-route", "kric-subway-timetable"],
    supportedV1Scope: {
      includedStationIds: ["station-sadang", "station-sangnoksu"],
      includedLineIds: ["seoul-4"],
      includedOperatorIds: ["seoul-metro"],
      facilityCoverageDenominator: {
        kind: "station_line_x_required_facility_type",
        expectedRows: 6,
      },
      requiredFacilityTypes: ["ELEVATOR", "ESCALATOR", "WHEELCHAIR_LIFT"],
    },
    stationMappings: [],
    stationLineRows: [],
    routeEdges: [],
    routeMapPositions: [],
    minimumProductionCoverage: { stations: 2, stationLines: 2, routeEdges: 1, facilities: 1 },
    scheduleProvenance: {
      sourceId: "kric-subway-timetable",
      sourceSnapshotId: "kric-subway-timetable-snapshot-20260712",
      providerRecordHash: "a".repeat(64),
      evidenceHash: "b".repeat(64),
      retrievedAt: "2026-07-12T00:00:00.000Z",
    },
  };
  const roster = {
    lnCd: "4",
    stations: [
      { stinConsOrdr: 28, stinCd: "433", railOprIsttCd: "S1", stinNm: "사당" },
      { stinConsOrdr: 29, stinCd: "434", railOprIsttCd: "S1", stinNm: "남태령" },
      { stinConsOrdr: 30, stinCd: "448", railOprIsttCd: "KR", stinNm: "상록수" },
    ],
  };
  const artifact = {
    capturedAt: "2026-07-12",
    transitTrips: [
      { id: "up", routeId: "route-seoul-4-up", serviceId: "weekday-kric", directionId: "up", servicePattern: "LOCAL" },
      { id: "down", routeId: "route-seoul-4-down", serviceId: "weekday-kric", directionId: "down", servicePattern: "LOCAL" },
    ],
    transitStopTimes: [
      stop("up", 1, "433", 100, 110),
      stop("up", 2, "434", 200, 210),
      stop("up", 3, "448", 310, 320),
      stop("down", 1, "448", 400, 410),
      stop("down", 2, "434", 500, 510),
      stop("down", 3, "433", 610, 620),
    ],
  };
  const geometry = {
    sourceSvgSha256: "c".repeat(64),
    stationNodes: [
      node("사당", 100, 100, true),
      node("남태령", 120, 140),
      node("상록수", 160, 180),
    ],
    labels: [
      label("사당", 90, 70, 120, 90),
      label("남태령", 110, 150, 145, 170),
      label("상록수", 150, 190, 185, 210),
    ],
  };

  const result = applyLine4RoutingGraph(input, artifact, roster, geometry);

  assert.deepEqual(result.supportedV1Scope.includedStationIds, ["station-sadang", "station-sangnoksu"]);
  assert.deepEqual(result.supportedV1Scope.transitPassThroughStationIds, ["station-seoul-4-434"]);
  assert.ok(result.sourceIds.includes(SELF_DRAWN_SOURCE_ID));
  assert.equal(new Set(result.stationLineRows.map((row) => row.stationCode)).size, 3);
  assert.equal(result.transitTrips.length, 2);
  assert.deepEqual(
    result.transitStopTimes.filter((row) => row.tripId === "up").map((row) => row.stationId),
    ["station-sadang", "station-seoul-4-434", "station-sangnoksu"],
  );
  assert.equal(result.routeEdges.filter((edge) => edge.edgeType === "RIDE").length, 4);
  assert.equal(result.routeMapPositions.length, 3);
  assert.deepEqual(
    result.routeMapPositions.find((position) => position.station.sourceStationCode === "capital-v2:남태령").labelPolygon,
    label("남태령", 110, 150, 145, 170).polygon,
  );
  assert.deepEqual(result.routeGraphTopologyPolicy, { summaryRideEdges: "fixture-only" });
  assert.deepEqual(result.minimumProductionCoverage, {
    stations: 3,
    stationLines: 3,
    routeEdges: 4,
    facilities: 1,
  });
});

function stop(tripId, stopSequence, stationCode, arrivalSeconds, departureSeconds) {
  return {
    tripId,
    stopSequence,
    stationId: `station-seoul-4-${stationCode}`,
    lineId: "seoul-4",
    arrivalSeconds,
    departureSeconds,
  };
}

function node(dataStation, x, y, transfer = false) {
  return {
    dataStation,
    dataLine: "4",
    dataLineName: transfer ? "" : "4호선",
    transferLines: transfer ? "4 2" : "",
    x,
    y,
  };
}

function label(normalizedText, minX, minY, maxX, maxY) {
  const polygon = [
    { x: minX, y: minY },
    { x: maxX, y: minY },
    { x: maxX, y: maxY },
    { x: minX, y: maxY },
  ];
  return { normalizedText, bounds: { minX, minY, maxX, maxY }, polygon };
}
