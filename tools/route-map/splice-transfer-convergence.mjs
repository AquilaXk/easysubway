#!/usr/bin/env node
// #1789: 환승 그룹 티어 분류 — 오라클 스팬과 실측 스팬의 displacement 기반
// 분류로, 렌더 3-모드 선택(스택/스팬/분리)의 데이터 근거를 제공한다.

import { rectifyPolyline } from "./octi-to-pack.mjs";

const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

/** posRows({station_id,line_id,x,y}) → 환승 그룹(2+ 노선). span=최대 쌍거리. */
export function transferGroups(posRows) {
  const byStation = new Map();
  for (const r of posRows) {
    if (!byStation.has(r.station_id)) byStation.set(r.station_id, []);
    byStation.get(r.station_id).push(r);
  }
  const groups = [];
  for (const [stationId, rows] of byStation) {
    if (new Set(rows.map((r) => r.line_id)).size < 2) continue;
    let span = 0;
    for (let i = 0; i < rows.length; i += 1)
      for (let j = i + 1; j < rows.length; j += 1)
        span = Math.max(span, Math.hypot(rows[i].x - rows[j].x, rows[i].y - rows[j].y));
    groups.push({
      stationId,
      members: rows.map((r) => ({ lineId: r.line_id, x: r.x, y: r.y })),
      memberCount: new Set(rows.map((r) => r.line_id)).size,
      span,
    });
  }
  return groups;
}

/** 변위=(span-target)/2. 티어: mild<4·mid<20·large<extremeDisp·나머지 extreme. */
export function classifyGroup(group, oracle, { extremeDisp = 35 } = {}) {
  const target = oracle[String(group.memberCount)] ?? oracle["5"] ?? 56;
  const displacement = Math.max(0, (group.span - target) / 2);
  let tier;
  if (displacement < 4) tier = "mild";
  else if (displacement < 20) tier = "mid";
  else if (displacement < extremeDisp) tier = "large";
  else tier = "extreme";
  return { target, displacement, tier };
}

/** 멤버 분산 주방향을 H/V로 스냅(분산이 큰 축). */
export function capsuleAxis(members) {
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (const m of members) {
    minX = Math.min(minX, m.x); maxX = Math.max(maxX, m.x);
    minY = Math.min(minY, m.y); maxY = Math.max(maxY, m.y);
  }
  return maxX - minX >= maxY - minY ? "H" : "V";
}

/** centroid 중심, targetSpan 폭, axis(H/V) 따라 멤버를 균등 배치. 입력 순서 보존. */
export function capsuleTargets(members, targetSpan, axis) {
  const n = members.length;
  const cx = members.reduce((s, m) => s + m.x, 0) / n;
  const cy = members.reduce((s, m) => s + m.y, 0) / n;
  const pitch = n > 1 ? targetSpan / (n - 1) : 0;
  const start = n > 1 ? -(targetSpan) / 2 : 0;
  return members.map((m, i) => {
    const off = start + i * pitch;
    return axis === "H"
      ? { lineId: m.lineId, x: cx + off, y: cy }
      : { lineId: m.lineId, x: cx, y: cy + off };
  });
}

/**
 * oldPos에서 가장 가까운 정점 인덱스를 찾는다 (threshold 30px).
 * 범위 내 정점이 없으면 -1 반환.
 * @internal
 */
function nearestVertexIndex(verts, oldPos, threshold = 30) {
  let minDist = Infinity;
  let minIdx = -1;
  for (let i = 0; i < verts.length; i += 1) {
    const d = dist(verts[i], oldPos);
    if (d < minDist) {
      minDist = d;
      minIdx = i;
    }
  }
  return minDist <= threshold ? minIdx : -1;
}

/**
 * 트랙 정점 배열에서 oldPos 근처 정점을 newPos로 이동하고,
 * 국소 윈도우(idx-radius ~ idx+radius)만 rectify한다.
 * @param verts - 정점 배열 [{x,y}, ...]
 * @param oldPos - 찾을 위치
 * @param newPos - 이동할 위치
 * @param options - {radius=1, eps=1}
 * @returns 새 배열 (입력 변경 안 함)
 */
export function spliceTrackToNode(verts, oldPos, newPos, { radius = 1, eps = 1 } = {}) {
  const idx = nearestVertexIndex(verts, oldPos);
  if (idx === -1) {
    // 범위 내 정점이 없으면 변경 없이 복사본 반환
    return verts.slice();
  }

  // idx 정점을 newPos로 이동한 배열 생성
  const modified = verts.map((v, i) => (i === idx ? { x: newPos.x, y: newPos.y } : { x: v.x, y: v.y }));

  // rectify 윈도우 범위: [Math.max(0, idx-radius), Math.min(len-1, idx+radius)]
  const windowStart = Math.max(0, idx - radius);
  const windowEnd = Math.min(verts.length - 1, idx + radius);

  // 윈도우 추출 후 rectify
  const window = modified.slice(windowStart, windowEnd + 1);
  const rectified = rectifyPolyline(window, { eps, tol: 0.5 });

  // 결과 배열: prefix + rectified + suffix
  const result = [
    ...modified.slice(0, windowStart),
    ...rectified,
    ...modified.slice(windowEnd + 1),
  ];

  return result;
}
