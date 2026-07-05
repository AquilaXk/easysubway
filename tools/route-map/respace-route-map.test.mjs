import assert from "node:assert/strict";
import { test } from "node:test";
import {
  parsePathPoints,
  serializePathPoints,
  buildRespaceGraph,
} from "./respace-route-map.mjs";

test("parse/serialize 왕복 + 연속 중복 정점 제거", () => {
  const points = parsePathPoints("M 0 0 L 100 0 L 100 0 L 100 50");
  assert.deepEqual(points, [
    { x: 0, y: 0 },
    { x: 100, y: 0 },
    { x: 100, y: 50 },
  ]);
  assert.equal(serializePathPoints(points), "M 0 0 L 100 0 L 100 50");
});

test("선분 위 역은 정점으로 삽입되고 chain이 갈라진다", () => {
  const graph = buildRespaceGraph({
    tracks: [
      { lineId: "L1", trackIndex: 0, points: parsePathPoints("M 0 0 L 100 0") },
    ],
    positions: [
      { stationId: "a", lineId: "L1", x: 0, y: 0 },
      { stationId: "b", lineId: "L1", x: 37, y: 0 },
      { stationId: "c", lineId: "L1", x: 100, y: 0 },
    ],
  });
  assert.equal(graph.nodes.length, 3); // 0,0 / 37,0 / 100,0
  assert.equal(graph.stationNodes.length, 3);
  assert.equal(graph.chains.length, 2); // a—b, b—c
  assert.ok(graph.chains.every((c) => c.hasStationEnds));
  assert.deepEqual(graph.tracks[0].nodeIds.length, 3);
});

test("기존 정점과 일치하는 역은 중복 삽입하지 않는다", () => {
  const graph = buildRespaceGraph({
    tracks: [
      {
        lineId: "L1",
        trackIndex: 0,
        points: parsePathPoints("M 0 0 L 50 0 L 50 50"),
      },
    ],
    positions: [{ stationId: "bend", lineId: "L1", x: 50, y: 0 }],
  });
  assert.equal(graph.nodes.length, 3);
});

test("닫힌 track(순환선)은 closed=true, 첫·끝 정점은 같은 노드", () => {
  const graph = buildRespaceGraph({
    tracks: [
      {
        lineId: "ring",
        trackIndex: 0,
        points: parsePathPoints("M 0 0 L 100 0 L 100 100 L 0 100 L 0 0"),
      },
    ],
    positions: [],
  });
  assert.equal(graph.tracks[0].closed, true);
  const ids = graph.tracks[0].nodeIds;
  assert.equal(ids[0], ids[ids.length - 1]);
  assert.equal(graph.nodes.length, 4);
});

test("같은 stationId의 노선별 정점은 cluster로 묶이고 offset을 기록한다", () => {
  const graph = buildRespaceGraph({
    tracks: [
      { lineId: "L1", trackIndex: 0, points: parsePathPoints("M 0 0 L 100 0") },
      { lineId: "L2", trackIndex: 0, points: parsePathPoints("M 0 6 L 100 6") },
    ],
    positions: [
      { stationId: "x", lineId: "L1", x: 50, y: 0 },
      { stationId: "x", lineId: "L2", x: 50, y: 6 },
    ],
  });
  assert.equal(graph.clusters.length, 1);
  const [m1, m2] = graph.clusters[0].members;
  assert.deepEqual(m1.offset, { x: 0, y: -3 });
  assert.deepEqual(m2.offset, { x: 0, y: 3 });
});

test("역 없는 트랙 꼬리는 hasStationEnds=false chain", () => {
  const graph = buildRespaceGraph({
    tracks: [
      {
        lineId: "L1",
        trackIndex: 0,
        points: parsePathPoints("M 0 0 L 40 0 L 120 0"),
      },
    ],
    positions: [{ stationId: "only", lineId: "L1", x: 40, y: 0 }],
  });
  // 꼬리 2개(0→40, 40→120)는 역-역 chain이 아니다.
  assert.equal(graph.chains.filter((c) => c.hasStationEnds).length, 0);
  assert.equal(graph.chains.filter((c) => !c.hasStationEnds).length, 2);
});
