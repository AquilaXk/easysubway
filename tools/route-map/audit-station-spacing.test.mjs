import assert from "node:assert/strict";
import { test } from "node:test";
import { buildRespaceGraph, parsePathPoints } from "./respace-route-map.mjs";
import {
  chainLengthStats,
  segmentCrossingCount,
  octolinearityViolations,
} from "./audit-station-spacing.mjs";

test("chainLengthStats: 분포와 p95/p5", () => {
  const graph = buildRespaceGraph({
    tracks: [
      {
        lineId: "L1",
        trackIndex: 0,
        points: parsePathPoints("M 0 0 L 10 0 L 110 0 L 510 0"),
      },
    ],
    positions: [
      { stationId: "a", lineId: "L1", x: 0, y: 0 },
      { stationId: "b", lineId: "L1", x: 10, y: 0 },
      { stationId: "c", lineId: "L1", x: 110, y: 0 },
      { stationId: "d", lineId: "L1", x: 510, y: 0 },
    ],
  });
  const stats = chainLengthStats(graph);
  assert.equal(stats.count, 3); // 10, 100, 400
  assert.equal(stats.median, 100);
  assert.equal(stats.max, 400);
  assert.ok(stats.p95OverP5 > 1);
});

test("segmentCrossingCount: 교차는 세고 끝점 접촉은 무시", () => {
  const crossing = [
    parsePathPoints("M 0 0 L 100 100"),
    parsePathPoints("M 0 100 L 100 0"),
  ];
  assert.equal(segmentCrossingCount(crossing), 1);
  const touching = [
    parsePathPoints("M 0 0 L 100 0"),
    parsePathPoints("M 100 0 L 200 0"),
  ];
  assert.equal(segmentCrossingCount(touching), 0);
});

test("octolinearityViolations: 45° 배수 이탈만 잡는다", () => {
  const tracks = [parsePathPoints("M 0 0 L 100 0 L 200 103")];
  const violations = octolinearityViolations(tracks, { toleranceDeg: 0.5 });
  assert.equal(violations.length, 1);
  assert.equal(violations[0].segIdx, 1);
});
