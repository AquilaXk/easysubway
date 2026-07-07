#!/usr/bin/env node
// #1789 P2.1: 밀집 회랑을 공유 노선 track 방향으로 arc-length 재배치하고 그룹-원자 splice로 옮긴다
// (캡슐 강체 보존, respace 무재실행). 축은 track 로컬 방향(붕괴 그룹도 정의됨), 정렬은 line_sequence.
// track 방향 이동이라 8선형이 구성상 보존된다.
import { spliceTrackToNode } from "./splice-transfer-convergence.mjs";
import { parsePathVertices, verticesToPath } from "./audit-octolinearity.mjs";
import { cleanupPackDir, openPack, writePack } from "./pack-io.mjs";

const SNAP8 = [
  { ux: 1, uy: 0 }, { ux: Math.SQRT1_2, uy: Math.SQRT1_2 }, { ux: 0, uy: 1 }, { ux: -Math.SQRT1_2, uy: Math.SQRT1_2 },
];
/** 벡터를 4개 무방향 8축(0/45/90/135°) 중 최근접으로 스냅. */
function snapAxis(dx, dy) {
  let best = SNAP8[0], bestDot = -1;
  for (const a of SNAP8) { const d = Math.abs(dx * a.ux + dy * a.uy); if (d > bestDot) { bestDot = d; best = a; } }
  return best;
}

/** centroid 최근접 정점의 인접 세그먼트 중 긴 쪽 방향을 8축 스냅(코너 tie-break=긴 세그먼트). */
export function trackAxis8(trackVerts, centroid) {
  let idx = 0, bd = Infinity;
  for (let i = 0; i < trackVerts.length; i += 1) { const d = Math.hypot(trackVerts[i].x - centroid.x, trackVerts[i].y - centroid.y); if (d < bd) { bd = d; idx = i; } }
  const segs = [];
  if (idx > 0) segs.push([trackVerts[idx - 1], trackVerts[idx]]);
  if (idx < trackVerts.length - 1) segs.push([trackVerts[idx], trackVerts[idx + 1]]);
  if (segs.length === 0) return { ux: 1, uy: 0 };
  segs.sort((a, b) => Math.hypot(b[1].x - b[0].x, b[1].y - b[0].y) - Math.hypot(a[1].x - a[0].x, a[1].y - a[0].y));
  const [p, q] = segs[0];
  return snapAxis(q.x - p.x, q.y - p.y);
}

/** membersSeq([{stationId,x,y,seq}]) + 공유 노선 track → 축(track 방향)·정렬(seq)·centroid. */
export function corridorLayout(membersSeq, trackVerts) {
  const cx = membersSeq.reduce((s, m) => s + m.x, 0) / membersSeq.length;
  const cy = membersSeq.reduce((s, m) => s + m.y, 0) / membersSeq.length;
  const axis = trackAxis8(trackVerts, { x: cx, y: cy });
  const ordered = [...membersSeq].sort((a, b) => a.seq - b.seq).map((m) => m.stationId);
  return { axis, ordered, centroid: { x: cx, y: cy } };
}
