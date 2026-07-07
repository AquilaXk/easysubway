import assert from "node:assert/strict";
import test from "node:test";
import { trackAxis8, corridorLayout, corridorTargets } from "./densify-corridors.mjs";

test("trackAxis8은 centroid 인접 세그먼트 긴 쪽 방향을 8축 스냅(세로 track→(0,1))", () => {
  // 세로 track, centroid가 (100,100) 근처 — 인접 세그먼트 모두 수직
  const verts = [{ x: 100, y: 0 }, { x: 100, y: 100 }, { x: 100, y: 300 }];
  const a = trackAxis8(verts, { x: 100, y: 100 });
  assert.deepEqual({ ux: Math.round(a.ux), uy: Math.round(a.uy) }, { ux: 0, uy: 1 });
});

test("corridorLayout: 0px 붕괴 3역·세로 track → 축(0,1)·정렬=line_sequence(역전 방지)", () => {
  // 세 역이 (100,100)에 붕괴, 입력 순서는 뒤섞임, seq가 진짜 순서
  const membersSeq = [
    { stationId: "도라산", x: 100, y: 100, seq: 3 },
    { stationId: "운천", x: 100, y: 100, seq: 1 },
    { stationId: "임진강", x: 100, y: 100, seq: 2 },
  ];
  const verts = [{ x: 100, y: 0 }, { x: 100, y: 100 }, { x: 100, y: 300 }];
  const r = corridorLayout(membersSeq, verts);
  assert.deepEqual({ ux: Math.round(r.axis.ux), uy: Math.round(r.axis.uy) }, { ux: 0, uy: 1 });
  assert.deepEqual(r.ordered, ["운천", "임진강", "도라산"]); // seq 순, 기하 아님
});

test("corridorTargets는 track축 따라 targetGap 간격·seq 순·centroid 중심 재배치(정수)", () => {
  // 3역 (100,100) 붕괴, 세로 track, seq 1/2/3
  const membersSeq = [
    { stationId: "a", x: 100, y: 100, seq: 1 }, { stationId: "b", x: 100, y: 100, seq: 2 }, { stationId: "c", x: 100, y: 100, seq: 3 },
  ];
  const verts = [{ x: 100, y: 0 }, { x: 100, y: 100 }, { x: 100, y: 300 }];
  const t = corridorTargets(membersSeq, verts, 30);
  const ys = ["a", "b", "c"].map((id) => t.get(id).y);
  assert.ok(ys[1] - ys[0] === 30 && ys[2] - ys[1] === 30, `y간격 ${ys}`); // 세로축 펼침
  assert.ok(Math.abs((ys[0] + ys[2]) / 2 - 100) < 1, "centroid y≈100 보존");
  assert.ok(["a", "b", "c"].every((id) => t.get(id).x === 100), "비축(x) 성분 통일");
});
