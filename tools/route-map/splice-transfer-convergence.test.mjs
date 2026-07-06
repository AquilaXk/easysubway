import assert from "node:assert/strict";
import test from "node:test";
import { transferGroups, classifyGroup } from "./splice-transfer-convergence.mjs";

test("transferGroups는 route_map_positions를 역별 환승 그룹으로 묶는다", () => {
  const rows = [
    { station_id: "s1", line_id: "L1", x: 0, y: 0 },
    { station_id: "s1", line_id: "L2", x: 10, y: 0 },
    { station_id: "s2", line_id: "L1", x: 100, y: 100 },
  ];
  const groups = transferGroups(rows);
  assert.equal(groups.length, 1, "2노선 이상만 그룹화");
  assert.equal(groups[0].station_id, "s1");
  assert.equal(groups[0].memberCount, 2);
  assert.equal(groups[0].span, 10);
});

test("transferGroups는 span을 최대 쌍거리로 계산한다", () => {
  const rows = [
    { station_id: "s1", line_id: "L1", x: 0, y: 0 },
    { station_id: "s1", line_id: "L2", x: 3, y: 4 },
    { station_id: "s1", line_id: "L3", x: 0, y: 5 },
  ];
  const groups = transferGroups(rows);
  // 쌍거리: (0,0)-(3,4)=5, (0,0)-(0,5)=5, (3,4)-(0,5)=sqrt(9+1)=sqrt(10)≈3.16
  // 최대=5
  assert.equal(groups[0].span, 5);
});

test("classifyGroup는 환승 그룹을 티어로 분류한다", () => {
  const oracle = { 2: 13, 3: 28, 4: 54, 5: 56 };
  const group = { memberCount: 2, span: 13 };
  const tier = classifyGroup(group, oracle);
  // displacement = (13-13)/2 = 0
  assert.equal(tier, "mild");
});

test("classifyGroup는 mid/large/extreme을 구분한다", () => {
  const oracle = { 2: 13 };
  // span=13: displacement=0 → mild
  assert.equal(classifyGroup({ memberCount: 2, span: 13 }, oracle), "mild");
  // span=23: displacement=(23-13)/2=5 → mild (boundary)
  assert.equal(classifyGroup({ memberCount: 2, span: 23 }, oracle), "mild");
  // span=25: displacement=(25-13)/2=6 → mid
  assert.equal(classifyGroup({ memberCount: 2, span: 25 }, oracle), "mid");
  // span=35: displacement=(35-13)/2=11 → large
  assert.equal(classifyGroup({ memberCount: 2, span: 35 }, oracle), "large");
  // span=55: displacement=(55-13)/2=21 → extreme
  assert.equal(classifyGroup({ memberCount: 2, span: 55 }, oracle), "extreme");
});

test("transferGroups는 단일 노선 역을 필터링한다", () => {
  const rows = [
    { station_id: "s1", line_id: "L1", x: 0, y: 0 },
    { station_id: "s2", line_id: "L2", x: 10, y: 0 },
  ];
  const groups = transferGroups(rows);
  assert.equal(groups.length, 0, "2노선 미만은 환승 그룹이 아님");
});

test("transferGroups는 빈 입력을 처리한다", () => {
  const groups = transferGroups([]);
  assert.equal(groups.length, 0);
});

test("classifyGroup은 oracle에 없는 memberCount를 2로 폴백한다", () => {
  const oracle = { 2: 10 };
  // memberCount=5는 oracle에 없으므로 fallback to 2
  const tier = classifyGroup({ memberCount: 5, span: 15 }, oracle);
  // displacement = (15-10)/2 = 2.5 → mild
  assert.equal(tier, "mild");
});
