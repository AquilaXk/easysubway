// #1789 P2.1: 밀집 회랑을 공유 노선 track 방향으로 arc-length 재배치하고 그룹-원자 splice로 옮긴다
// (캡슐 강체 보존, respace 무재실행). 축은 track 로컬 방향(붕괴 그룹도 정의됨), 정렬은 line_sequence.
// track 방향 이동이라 8선형이 구성상 보존된다.

import { spliceTrackToNode } from "./splice-transfer-convergence.mjs";

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
  let buildIdx = 0;
  if (idx > 0) segs.push({ seg: [trackVerts[idx - 1], trackVerts[idx]], buildIdx: buildIdx++ });
  if (idx < trackVerts.length - 1) segs.push({ seg: [trackVerts[idx], trackVerts[idx + 1]], buildIdx: buildIdx++ });
  if (segs.length === 0) return { ux: 1, uy: 0 };
  segs.sort((a, b) => {
    const lenA = Math.hypot(a.seg[1].x - a.seg[0].x, a.seg[1].y - a.seg[0].y);
    const lenB = Math.hypot(b.seg[1].x - b.seg[0].x, b.seg[1].y - b.seg[0].y);
    return (lenB - lenA) || (b.buildIdx - a.buildIdx);
  });
  const [p, q] = segs[0].seg;
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

/** 회랑 역들을 track축 따라 targetGap 간격·seq 순·centroid 중심 재배치(비축=centroid 통일, 정수). */
export function corridorTargets(membersSeq, trackVerts, targetGap = 30) {
  const { axis, ordered, centroid } = corridorLayout(membersSeq, trackVerts);
  const n = ordered.length;
  const cProj = centroid.x * axis.ux + centroid.y * axis.uy;       // centroid 축좌표
  const perp = { x: centroid.x - cProj * axis.ux, y: centroid.y - cProj * axis.uy }; // centroid 비축 성분(통일)
  const start = cProj - ((n - 1) * targetGap) / 2;
  const out = new Map();
  ordered.forEach((id, k) => {
    const s = start + k * targetGap;
    out.set(id, { x: Math.round(perp.x + s * axis.ux), y: Math.round(perp.y + s * axis.uy) });
  });
  return out;
}

/** 회랑 그룹 적용: 전 노선노드 강체 델타 이동(캡슐 보존) + 노선 track splice(부착 실패 원자적 미이동). */
export function applyCorridor(membersSeq, trackVerts, memberLines, tracksByLine, maxDist = 30) {
  const targets = corridorTargets(membersSeq, trackVerts, 30);
  const { axis } = corridorLayout(membersSeq, trackVerts);            // 정렬용 축
  const reprById = new Map(membersSeq.map((m) => [m.stationId, { x: m.x, y: m.y }]));
  const positionUpdates = [];
  const trackUpdates = [];
  // 목표 축 투영 오름차순(135° 포함 정확) — 단일 패스로 공유 정점 순서 처리.
  const proj = (id) => targets.get(id).x * axis.ux + targets.get(id).y * axis.uy;
  const order = [...targets.keys()].sort((a, b) => proj(a) - proj(b));
  for (const stationId of order) {
    const np = targets.get(stationId);
    const repr = reprById.get(stationId);
    const dx = np.x - repr.x, dy = np.y - repr.y;                     // 강체 델타(캡슐 span 보존)
    const nodes = memberLines.get(stationId) ?? [];
    let attachedAny = false;
    const pending = [];
    const nodeNew = [];
    for (const node of nodes) {
      const nnp = { x: Math.round(node.x + dx), y: Math.round(node.y + dy) };  // 노드별 동일 델타
      nodeNew.push({ node, nnp });
      for (const trk of tracksByLine.get(node.lineId) ?? []) {
        const { verts, attached } = spliceTrackToNode(trk.verts, { x: node.x, y: node.y }, nnp, { maxDist });
        if (attached) { attachedAny = true; if (JSON.stringify(verts) !== JSON.stringify(trk.verts)) pending.push({ lineId: node.lineId, trackIndex: trk.trackIndex, verts, trk }); }
      }
    }
    if (!attachedAny) continue;                                       // 원자성
    for (const p of pending) { p.trk.verts = p.verts; trackUpdates.push({ lineId: p.lineId, trackIndex: p.trackIndex, verts: p.verts }); }
    for (const { node, nnp } of nodeNew) positionUpdates.push({ stationId, lineId: node.lineId, x: nnp.x, y: nnp.y });
  }
  return { positionUpdates, trackUpdates };
}

/**
 * 공유 노선 없는 그룹(반포↔잠원): 첫 역만 자기 노선 track 방향으로 targetGap 이동해 분리.
 * 둘 다 기하축으로 밀면 둘 다 자기 track 밖으로 나가므로 한 역만 자기 노선 방향으로.
 */
export function applyNoSharedLine(g, memberLines, tracksByLine, repr, targetGap = 30, maxDist = 30) {
  const [aId, bId] = g;
  const a = repr.get(aId), b = repr.get(bId);
  const aLine = (memberLines.get(aId) ?? [])[0];
  const track = aLine ? (tracksByLine.get(aLine.lineId) ?? [])[0] : null;
  if (!track) return { positionUpdates: [], trackUpdates: [] };
  const axis = trackAxis8(track.verts, a);
  const away = ((a.x - b.x) * axis.ux + (a.y - b.y) * axis.uy) >= 0 ? 1 : -1;
  const dx = away * targetGap * axis.ux, dy = away * targetGap * axis.uy;   // 강체 델타
  const positionUpdates = [], trackUpdates = [];
  let attached = false;
  for (const node of memberLines.get(aId) ?? []) {
    const nnp = { x: Math.round(node.x + dx), y: Math.round(node.y + dy) };
    for (const trk of tracksByLine.get(node.lineId) ?? []) {
      const r = spliceTrackToNode(trk.verts, { x: node.x, y: node.y }, nnp, { maxDist });
      if (r.attached) { attached = true; if (JSON.stringify(r.verts) !== JSON.stringify(trk.verts)) { trk.verts = r.verts; trackUpdates.push({ lineId: node.lineId, trackIndex: trk.trackIndex, verts: r.verts }); } }
    }
  }
  if (attached) for (const node of memberLines.get(aId) ?? []) positionUpdates.push({ stationId: aId, lineId: node.lineId, x: Math.round(node.x + dx), y: Math.round(node.y + dy) });
  return { positionUpdates, trackUpdates };
}
