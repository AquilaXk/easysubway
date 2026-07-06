import assert from "node:assert/strict";
import test from "node:test";
import { transferGroups, classifyGroup, capsuleAxis, capsuleTargets, spliceTrackToNode } from "./splice-transfer-convergence.mjs";

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

test("spliceTrackToNode는 track 끝점 허브도 새 위치로 이동(한쪽 윈도우)", () => {
  const verts = [{ x: 0, y: 100 }, { x: 100, y: 100 }, { x: 200, y: 100 }];
  const out = spliceTrackToNode(verts, { x: 0, y: 100 }, { x: 0, y: 112 }, { radius: 1 });
  assert.ok(out.some((v) => Math.abs(v.y - 112) < 1e-6), "끝점 허브 이동");
  for (let i = 1; i < out.length; i += 1) {
    const dx = out[i].x - out[i - 1].x, dy = out[i].y - out[i - 1].y;
    if (Math.hypot(dx, dy) === 0) continue;
    const ang = (Math.atan2(dy, dx) * 180) / Math.PI, mod = ((ang % 45) + 45) % 45;
    assert.ok(Math.min(mod, 45 - mod) <= 0.5, `세그 ${i} 비8선형`);
  }
});

test("spliceTrackToNode는 근처 정점을 newPos로 이동, 국소 rectify", () => {
  // 수평 5-정점 트랙: (0,100), (100,100), (200,100), (300,100), (400,100)
  const verts = [
    { x: 0, y: 100 },
    { x: 100, y: 100 },
    { x: 200, y: 100 },
    { x: 300, y: 100 },
    { x: 400, y: 100 },
  ];

  // 중앙 정점(200,100)을 (200,108)로 이동, radius=1 국소 rectify
  const result = spliceTrackToNode(verts, { x: 200, y: 100 }, { x: 200, y: 108 }, { radius: 1, eps: 1 });

  // 결과는 새 배열
  assert.notEqual(result, verts);

  // 허브 정점이 새 위치(y≈108)로 이동
  const moved = result.find((v) => Math.abs(v.y - 108) < 1e-6);
  assert.ok(moved, "허브 정점이 새 위치(y≈108)로 이동");

  // 끝 정점은 변경 안 됨: 첫 점이 (0,100), 마지막 점이 (400,100)
  assert.equal(result[0].x, 0);
  assert.equal(result[0].y, 100);
  assert.equal(result[result.length - 1].x, 400);
  assert.equal(result[result.length - 1].y, 100);

  // 8선형 검사: 모든 세그먼트가 8방향(±0.5°)
  assert.ok(result.length >= 2, `결과 배열이 최소 2개 점을 가져야 함, 실제: ${result.length}`);
  for (let i = 0; i < result.length - 1; i += 1) {
    const dx = result[i + 1].x - result[i].x;
    const dy = result[i + 1].y - result[i].y;
    if (dx === 0 && dy === 0) continue; // 중복 점 무시
    const angle = Math.atan2(dy, dx) * (180 / Math.PI);
    // 8선형: 0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°
    const snapAngles = [0, 45, 90, 135, 180, 225, 270, 315];
    const minDiff = Math.min(
      ...snapAngles.map((a) => Math.min(Math.abs(angle - a), Math.abs(angle - a + 360), Math.abs(angle - a - 360)))
    );
    assert.ok(minDiff <= 0.5, `세그먼트 ${i}->${i + 1} 각도=${angle.toFixed(2)}°, 8선형 오차=${minDiff.toFixed(2)}°`);
  }
});
