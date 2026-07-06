import assert from "node:assert/strict";
import test from "node:test";
import { transferGroups, classifyGroup, capsuleAxis, capsuleTargets } from "./splice-transfer-convergence.mjs";

test("transferGroups는 2+노선 역만 그룹화하고 span=최대쌍거리", () => {
  const rows = [
    { station_id: "s1", line_id: "L1", x: 0, y: 0 },
    { station_id: "s1", line_id: "L2", x: 30, y: 40 }, // span 50
    { station_id: "s2", line_id: "L1", x: 5, y: 5 },   // 단일 노선 → 제외
  ];
  const g = transferGroups(rows);
  assert.equal(g.length, 1);
  assert.equal(g[0].stationId, "s1");
  assert.equal(g[0].memberCount, 2);
  assert.equal(g[0].span, 50);
});

test("classifyGroup은 변위=(span-target)/2로 티어를 나눈다", () => {
  const oracle = { "2": 13 };
  // span 50, target 13 → 변위 18.5 → mid
  assert.equal(classifyGroup({ memberCount: 2, span: 50 }, oracle).tier, "mid");
  // span 216, target 13 → 변위 101.5 → extreme
  assert.equal(classifyGroup({ memberCount: 2, span: 216 }, oracle).tier, "extreme");
  // span 14, target 13 → 변위 0.5 → mild
  assert.equal(classifyGroup({ memberCount: 2, span: 14 }, oracle).tier, "mild");
});

test("capsuleAxis는 멤버 분산 주방향을 H/V로 스냅한다", () => {
  // 수평으로 벌어진 멤버 → H
  assert.equal(capsuleAxis([{ x: 0, y: 0 }, { x: 100, y: 5 }]), "H");
  // 수직으로 벌어진 멤버 → V
  assert.equal(capsuleAxis([{ x: 0, y: 0 }, { x: 5, y: 100 }]), "V");
});

test("capsuleTargets는 centroid 중심 targetSpan 폭으로 축 따라 균등 배치", () => {
  const members = [
    { lineId: "A", x: 0, y: 0 }, { lineId: "B", x: 60, y: 0 }, // centroid (30,0)
  ];
  const t = capsuleTargets(members, 13, "H");
  // 2멤버, 폭 13, centroid x=30 → x=23.5, 36.5, y=centroid 0
  assert.equal(t.length, 2);
  assert.ok(Math.abs((t[1].x - t[0].x) - 13) < 1e-9, `피치 ${t[1].x - t[0].x}`);
  assert.ok(Math.abs(((t[0].x + t[1].x) / 2) - 30) < 1e-9); // centroid 보존
  assert.equal(t[0].y, 0);
  assert.equal(t[1].y, 0);
  assert.deepEqual(t.map((m) => m.lineId), ["A", "B"]); // 순서 안정
});

test("capsuleTargets 단일 멤버는 centroid(자기 위치)에 그대로 둔다", () => {
  const t = capsuleTargets([{ lineId: "X", x: 10, y: 20 }], 13, "H");
  assert.deepEqual(t, [{ lineId: "X", x: 10, y: 20 }]);
});
