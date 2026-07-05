#!/usr/bin/env node
// #1789 재간격 감사: 간격 분포(p95/p5)·교차 증가·8선형 위반을 기계 판정한다.
// 인접 판정은 line_sequence가 아니라 track arc-length(Task 4 chains) 기준이라
// 1호선 분기의 가짜 인접쌍(오산—인천 등)이 원천 배제된다.
import { writeFileSync, readFileSync } from "node:fs";
import path from "node:path";
import { buildRespaceGraph, parsePathPoints } from "./respace-route-map.mjs";
import { cleanupPackDir, openPack, repoRoot } from "./pack-io.mjs";

/** hasStationEnds chain arc length 분포 (nearest-rank 분위수). */
export function chainLengthStats(graph) {
  const lens = graph.chains
    .filter((c) => c.hasStationEnds)
    .map((c) => {
      let s = 0;
      for (let i = 1; i < c.nodeIds.length; i += 1) {
        const a = graph.nodes[c.nodeIds[i - 1]];
        const b = graph.nodes[c.nodeIds[i]];
        s += Math.hypot(a.x - b.x, a.y - b.y);
      }
      return s;
    })
    .sort((a, b) => a - b);
  const n = lens.length;
  if (n === 0) {
    return { count: 0, p5: 0, p25: 0, median: 0, p75: 0, p95: 0, max: 0, p95OverP5: 0 };
  }
  const pct = (q) => lens[Math.max(0, Math.min(n - 1, Math.ceil(q * n) - 1))];
  const p5 = pct(0.05);
  const p95 = pct(0.95);
  return {
    count: n,
    p5,
    p25: pct(0.25),
    median: pct(0.5),
    p75: pct(0.75),
    p95,
    max: lens[n - 1],
    p95OverP5: p5 > 0 ? p95 / p5 : 0,
  };
}

function orient(a, b, c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

function properIntersect(p1, p2, p3, p4) {
  const d1 = orient(p3, p4, p1);
  const d2 = orient(p3, p4, p2);
  const d3 = orient(p1, p2, p3);
  const d4 = orient(p1, p2, p4);
  return (
    ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
    ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
  );
}

/** 서로 다른 폴리라인 간 순수 교차 수(공유 끝점·collinear 접촉 제외). */
export function segmentCrossingCount(tracksPoints) {
  const segs = [];
  for (let ti = 0; ti < tracksPoints.length; ti += 1) {
    const pts = tracksPoints[ti];
    for (let i = 1; i < pts.length; i += 1) {
      segs.push({ ti, a: pts[i - 1], b: pts[i] });
    }
  }
  let count = 0;
  for (let i = 0; i < segs.length; i += 1) {
    for (let j = i + 1; j < segs.length; j += 1) {
      if (segs[i].ti === segs[j].ti) continue;
      const shared = [segs[i].a, segs[i].b].some((p) =>
        [segs[j].a, segs[j].b].some(
          (q) => Math.hypot(p.x - q.x, p.y - q.y) < 1e-6,
        ),
      );
      if (shared) continue;
      if (properIntersect(segs[i].a, segs[i].b, segs[j].a, segs[j].b)) {
        count += 1;
      }
    }
  }
  return count;
}

/** 45° 배수에서 tolerance 초과 이탈한 선분 목록(0-길이 무시). segIdx는 선분 index. */
export function octolinearityViolations(tracksPoints, { toleranceDeg = 0.5 } = {}) {
  const out = [];
  for (let ti = 0; ti < tracksPoints.length; ti += 1) {
    const pts = tracksPoints[ti];
    for (let i = 1; i < pts.length; i += 1) {
      const dx = pts[i].x - pts[i - 1].x;
      const dy = pts[i].y - pts[i - 1].y;
      if (Math.hypot(dx, dy) === 0) continue;
      const ang = (Math.atan2(dy, dx) * 180) / Math.PI;
      const mod = ((ang % 45) + 45) % 45;
      const dev = Math.min(mod, 45 - mod);
      if (dev > toleranceDeg) {
        out.push({ trackIdx: ti, segIdx: i - 1, angleDeg: ang });
      }
    }
  }
  return out;
}

function parseArgs(argv) {
  const o = {
    pack: "apps/mobile/assets/datapacks/capital.sqlite.gz",
    region: "수도권",
    json: null,
    compare: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    switch (argv[i]) {
      case "--pack": o.pack = argv[++i]; break;
      case "--region": o.region = argv[++i]; break;
      case "--json": o.json = argv[++i]; break;
      case "--compare": o.compare = argv[++i]; break;
    }
  }
  return o;
}

function main() {
  const o = parseArgs(process.argv.slice(2));
  const { db, dir } = openPack(o.pack, "audit-spacing-");
  try {
    const trackRows = db
      .prepare(
        "SELECT line_id, track_index, path FROM route_map_line_tracks " +
          "WHERE region = ? ORDER BY line_id, track_index",
      )
      .all(o.region);
    const posRows = db
      .prepare(
        "SELECT station_id, line_id, x, y FROM route_map_positions WHERE region = ?",
      )
      .all(o.region);
    const tracks = trackRows.map((r) => ({
      lineId: r.line_id,
      trackIndex: r.track_index,
      points: parsePathPoints(r.path),
    }));
    const graph = buildRespaceGraph({
      tracks,
      positions: posRows.map((r) => ({
        stationId: r.station_id,
        lineId: r.line_id,
        x: r.x,
        y: r.y,
      })),
    });
    const tracksPoints = tracks.map((t) => t.points);
    const report = {
      region: o.region,
      spacing: chainLengthStats(graph),
      crossings: segmentCrossingCount(tracksPoints),
      octoViolations: octolinearityViolations(tracksPoints).length,
      warnings: graph.warnings.length,
    };
    const s = report.spacing;
    console.log(
      `[${o.region}] 간격 chain ${s.count} · median ${Math.round(s.median)} · ` +
        `p5 ${Math.round(s.p5)} · p95 ${Math.round(s.p95)} · p95/p5 ${s.p95OverP5.toFixed(1)}`,
    );
    console.log(
      `교차 ${report.crossings} · 8선형 위반 ${report.octoViolations} · 투영 경고 ${report.warnings}`,
    );
    if (o.json) {
      writeFileSync(
        path.isAbsolute(o.json) ? o.json : path.join(repoRoot, o.json),
        JSON.stringify(report, null, 2) + "\n",
      );
    }
    if (o.compare) {
      const before = JSON.parse(
        readFileSync(
          path.isAbsolute(o.compare) ? o.compare : path.join(repoRoot, o.compare),
          "utf8",
        ),
      );
      const fails = [];
      if (report.crossings > before.crossings) {
        fails.push(`교차 증가 ${before.crossings}→${report.crossings}`);
      }
      if (report.octoViolations > before.octoViolations) {
        fails.push(`8선형 위반 증가 ${before.octoViolations}→${report.octoViolations}`);
      }
      if (report.spacing.p95OverP5 > 3) {
        fails.push(`간격 p95/p5 ${report.spacing.p95OverP5.toFixed(1)} > 3`);
      }
      if (fails.length) {
        console.error("감사 실패: " + fails.join(" · "));
        process.exit(1);
      }
      console.log("감사 통과 (교차·8선형·간격 균일도 안전).");
    }
  } finally {
    cleanupPackDir(dir);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
