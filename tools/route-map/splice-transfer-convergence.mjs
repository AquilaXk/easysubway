#!/usr/bin/env node
// #1789: 환승 그룹 티어 분류 — 오라클 스팬과 실측 스팬의 displacement 기반
// 분류로, 렌더 3-모드 선택(스택/스팬/분리)의 데이터 근거를 제공한다.

const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

/**
 * route_map_positions 행을 역별 환승 그룹(memberCount, span)으로 묶는다.
 * - station_id별 그룹화
 * - 2노선 이상만 반환
 * - span = 최대 쌍거리
 */
export function transferGroups(rows) {
  const byStation = new Map();
  for (const row of rows) {
    if (!byStation.has(row.station_id)) {
      byStation.set(row.station_id, []);
    }
    byStation.get(row.station_id).push(row);
  }

  const groups = [];
  for (const [stationId, members] of byStation) {
    const lineIds = new Set(members.map((m) => m.line_id));
    if (lineIds.size < 2) continue;

    let span = 0;
    for (let i = 0; i < members.length; i += 1) {
      for (let j = i + 1; j < members.length; j += 1) {
        span = Math.max(span, dist(members[i], members[j]));
      }
    }

    groups.push({
      station_id: stationId,
      memberCount: lineIds.size,
      span,
    });
  }

  return groups;
}

/**
 * 환승 그룹을 displacement 기반으로 분류한다.
 * displacement = (span - target) / 2
 * - mild: 0 ≤ displacement ≤ 5
 * - mid: 5 < displacement ≤ 10
 * - large: 10 < displacement ≤ 20
 * - extreme: displacement > 20
 */
export function classifyGroup(group, oracle) {
  const target = oracle[String(group.memberCount)] ?? oracle["2"];
  const displacement = (group.span - target) / 2;

  if (displacement <= 5) return "mild";
  if (displacement <= 10) return "mid";
  if (displacement <= 20) return "large";
  return "extreme";
}
