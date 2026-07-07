import assert from "node:assert/strict";
import test from "node:test";
import { trackAxis8, corridorLayout } from "./densify-corridors.mjs";

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
