import assert from "node:assert/strict";
import test from "node:test";
import { transferGroups, classifyGroup } from "./splice-transfer-convergence.mjs";

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
