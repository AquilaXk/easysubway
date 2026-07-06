#!/usr/bin/env node
// #1789: 환승 그룹 티어 분류 — 오라클 스팬과 실측 스팬의 displacement 기반
// 분류로, 렌더 3-모드 선택(스택/스팬/분리)의 데이터 근거를 제공한다.

import { readFileSync } from "node:fs";
import { octilinearPolyline } from "./octolinearize-line-tracks.mjs";
import { parsePathVertices, verticesToPath } from "./audit-octolinearity.mjs";
import { openPack, writePack, cleanupPackDir } from "./pack-io.mjs";

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
 * 허브 정점을 newPos로 옮기고 [idx-radius, idx+radius] 윈도우만 8선형 재구성(원위 불변).
 * octilinearPolyline은 입력 정점(윈도우 끝점 + 이동한 허브)을 정확히 보존하고 45° dogleg를
 * 삽입해 8선형화한다 — rectify와 달리 수직 오프셋 지점을 정확히 통과한다(국소 dogleg는
 * radius-1 국소라 전역 재생성의 자유교차와 무관, 교차는 Task 6 게이트가 실측).
 */
export function spliceTrackToNode(verts, oldPos, newPos, { radius = 1 } = {}) {
  const idx = nearestVertexIndex(verts, oldPos);
  if (idx < 0) return verts.slice(); // 멤버가 track 밖 — 건드리지 않음
  const moved = verts.map((v, i) => (i === idx ? { x: newPos.x, y: newPos.y } : { x: v.x, y: v.y }));
  const lo = Math.max(0, idx - radius);
  const hi = Math.min(moved.length - 1, idx + radius);
  const local = octilinearPolyline(moved.slice(lo, hi + 1));
  return [...moved.slice(0, lo), ...local, ...moved.slice(hi + 1)];
}

/** 한 그룹 수렴: 캡슐 타깃 → 각 노선 track splice.
 * tracksByLine = Map(lineId → [{trackIndex, verts}]).
 * 반환: { positionUpdates:[{stationId,lineId,x,y}], trackUpdates:[{lineId,trackIndex,verts}] }
 */
export function convergeGroup(group, oracle, tracksByLine) {
  const { target } = classifyGroup(group, oracle);
  const axis = capsuleAxis(group.members);
  const targets = capsuleTargets(group.members, target, axis);
  const targetByLine = new Map(targets.map((t) => [t.lineId, t]));
  const positionUpdates = targets.map((t) => ({
    stationId: group.stationId,
    lineId: t.lineId,
    x: Math.round(t.x),
    y: Math.round(t.y),
  }));
  const trackUpdates = [];
  for (const m of group.members) {
    const nt = targetByLine.get(m.lineId);
    for (const trk of tracksByLine.get(m.lineId) ?? []) {
      const spliced = spliceTrackToNode(trk.verts, { x: m.x, y: m.y }, { x: nt.x, y: nt.y });
      if (JSON.stringify(spliced) !== JSON.stringify(trk.verts)) {
        trackUpdates.push({ lineId: m.lineId, trackIndex: trk.trackIndex, verts: spliced });
      }
    }
  }
  return { positionUpdates, trackUpdates };
}

function parseArgs(argv) {
  const o = {
    pack: "apps/mobile/assets/datapacks/capital.sqlite.gz",
    index: "apps/mobile/assets/datapacks/index.json",
    region: "수도권",
    oracle: "tools/route-map/oracle-transfer-spans.json",
    tiers: "mild,mid,large",
    check: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === "--pack") o.pack = argv[++i];
    else if (a === "--index") o.index = argv[++i];
    else if (a === "--region") o.region = argv[++i];
    else if (a === "--oracle") o.oracle = argv[++i];
    else if (a === "--tiers") o.tiers = argv[++i];
    else if (a === "--check") o.check = true;
  }
  return o;
}

function main() {
  const o = parseArgs(process.argv.slice(2));
  let oracle;
  try {
    oracle = JSON.parse(readFileSync(o.oracle, "utf8")).spanP90ByMemberCount;
  } catch (e) {
    console.error(`oracle 파일을 읽을 수 없음: ${o.oracle} (${e.message}) — oracle-metrics.mjs로 먼저 생성하세요`);
    process.exit(1);
  }
  const selected = new Set(o.tiers.split(","));
  const { db, dir, sqlitePath, packPath } = openPack(o.pack, "splice-conv-");
  try {
    const posRows = db
      .prepare("SELECT station_id, line_id, x, y FROM route_map_positions WHERE region=?")
      .all(o.region);
    const trackRows = db
      .prepare(
        "SELECT line_id, track_index, path FROM route_map_line_tracks WHERE region=? ORDER BY line_id, track_index",
      )
      .all(o.region);
    const tracksByLine = new Map();
    for (const t of trackRows) {
      if (!tracksByLine.has(t.line_id)) tracksByLine.set(t.line_id, []);
      tracksByLine.get(t.line_id).push({ trackIndex: t.track_index, verts: parsePathVertices(t.path) });
    }
    const groups = transferGroups(posRows);
    let applied = 0;
    const posU = db.prepare(
      "UPDATE route_map_positions SET x=?, y=? WHERE region=? AND station_id=? AND line_id=?",
    );
    const trkU = db.prepare(
      "UPDATE route_map_line_tracks SET path=? WHERE region=? AND line_id=? AND track_index=?",
    );
    if (!o.check) db.exec("BEGIN");
    const tierCount = { mild: 0, mid: 0, large: 0, extreme: 0 };
    for (const g of groups) {
      const { tier } = classifyGroup(g, oracle);
      tierCount[tier] += 1;
      if (!selected.has(tier)) continue;
      const { positionUpdates, trackUpdates } = convergeGroup(g, oracle, tracksByLine);
      applied += 1;
      if (o.check) continue;
      for (const p of positionUpdates)
        posU.run(p.x, p.y, o.region, p.stationId, p.lineId);
      for (const tu of trackUpdates)
        trkU.run(
          verticesToPath(tu.verts.map((v) => ({ x: Math.round(v.x), y: Math.round(v.y) }))),
          o.region,
          tu.lineId,
          tu.trackIndex,
        );
    }
    console.log(
      `[${o.region}] 환승 ${groups.length} · 티어 ${JSON.stringify(tierCount)} · 적용(${o.tiers}) ${applied}`,
    );
    if (o.check) {
      console.log("(--check: 미기록)");
      db.close();
      return;
    }
    db.exec("COMMIT");
    db.exec("VACUUM");
    db.close();
    const { byteSize } = writePack({ sqlitePath, packPath, packRelPath: o.pack, indexRelPath: o.index });
    console.log(`팩 갱신 (byteSize ${byteSize})`);
  } finally {
    cleanupPackDir(dir);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) main();
