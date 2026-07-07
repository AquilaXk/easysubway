// #1789 P2.1: 밀집 회랑을 공유 노선 track 방향으로 arc-length 재배치하고 그룹-원자 splice로 옮긴다
// (캡슐 강체 보존, respace 무재실행). 축은 track 로컬 방향(붕괴 그룹도 정의됨), 정렬은 line_sequence.
// track 방향 이동이라 8선형이 구성상 보존된다.

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
