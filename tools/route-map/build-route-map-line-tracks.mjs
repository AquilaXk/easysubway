#!/usr/bin/env node
// SVG track geometry(extract-svg-geometry v2의 strokes)를 노선별 실제 track
// polyline으로 변환한다. 핵심 통찰:
//
//   1. route_map_positions.x,y는 라벨 위치라 track 위 마커가 아니다 → 역을 track에
//      직접 snap할 수 없다. 대신 track polyline 자체가 이미 실제 노선 모양이므로
//      그대로 노선 geometry로 쓴다(역별 down_path 재생성 불필요).
//   2. SVG stroke 색은 노선의 실제 식별자다(CSS 클래스 = 노선). 색 종류 수 = 노선
//      수이며, 색↔line_id는 완전 1:1이다. greedy 다수결은 환승 밀집/평행 노선에서
//      중복·오류를 내므로, 색×line_id 근접 표수 행렬 위에서 최대가중 완전매칭
//      (Hungarian)으로 전역 최적 1:1 배정을 구한다.
//
// 렌더 색은 여기서 정하지 않는다 — pack lines.color(apply-route-map-line-colors로
// 반영된 공식 색)를 렌더러가 쓴다. 이 스크립트는 track geometry와 색↔line_id
// 매핑만 산출한다.
import { readFile, writeFile } from "node:fs/promises";
import { gunzipSync } from "node:zlib";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { mkdtemp, rm, writeFile as writeTemp } from "node:fs/promises";
import { tmpdir } from "node:os";

// 역 라벨을 track에 근접 배정할 때의 반경(root px). 라벨은 track에서 20~35px
// 떨어져 있어(폰트 높이 근처) 이보다 크면 이웃 노선까지 삼킨다.
const SNAP_RADIUS = 35;

function usage() {
  return `Usage: node tools/route-map/build-route-map-line-tracks.mjs --geometry <geom.json> --pack <capital.sqlite[.gz]> --region <name> [--out <tracks.json>] [--check] [--snap-radius <px>]

extract-svg-geometry v2 결과의 노선 track(polyline/path)을 색↔line_id 최적매칭으로
region 노선별 track geometry로 변환한다. --check는 파일을 쓰지 않고 무결성만 검증한다.
`;
}

function parseArgs(argv) {
  const options = { geometry: null, pack: null, region: null, out: null, check: false, snapRadius: SNAP_RADIUS };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--help":
      case "-h":
        return { help: true };
      case "--geometry": options.geometry = argv[++index] ?? null; break;
      case "--pack": options.pack = argv[++index] ?? null; break;
      case "--region": options.region = argv[++index] ?? null; break;
      case "--out": options.out = argv[++index] ?? null; break;
      case "--check": options.check = true; break;
      case "--snap-radius": options.snapRadius = Number.parseFloat(argv[++index] ?? ""); break;
      default:
        if (arg.startsWith("--")) throw new Error(`Unknown option: ${arg}`);
    }
  }
  if (!options.geometry) throw new Error("--geometry is required.");
  if (!options.pack) throw new Error("--pack is required.");
  if (!options.region) throw new Error("--region is required.");
  if (!Number.isFinite(options.snapRadius) || options.snapRadius <= 0) throw new Error("--snap-radius must be a positive number.");
  return options;
}

// 점 p에서 선분 ab까지 최단거리.
function distanceToSegment(p, a, b) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lengthSquared = dx * dx + dy * dy;
  if (lengthSquared === 0) return Math.hypot(p.x - a.x, p.y - a.y);
  let t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

// 역 p에서 track(정점열들의 묶음)까지 최단거리.
function distanceToTracks(p, tracks) {
  let best = Infinity;
  for (const track of tracks) {
    for (let index = 1; index < track.points.length; index += 1) {
      const distance = distanceToSegment(p, track.points[index - 1], track.points[index]);
      if (distance < best) best = distance;
    }
  }
  return best;
}

// 최대가중 완전 이분매칭 (Hungarian, O(n^3)). weight[i][j] 최대화. 정사각 확장.
function maximumWeightMatching(weight, rowCount, columnCount) {
  const n = Math.max(rowCount, columnCount);
  const cost = Array.from({ length: n }, (_, i) => Array.from({ length: n }, (_, j) => -(weight[i]?.[j] ?? 0)));
  const INF = Number.POSITIVE_INFINITY;
  const u = new Array(n + 1).fill(0);
  const v = new Array(n + 1).fill(0);
  const p = new Array(n + 1).fill(0);
  const way = new Array(n + 1).fill(0);
  for (let i = 1; i <= n; i += 1) {
    p[0] = i;
    let j0 = 0;
    const minv = new Array(n + 1).fill(INF);
    const used = new Array(n + 1).fill(false);
    do {
      used[j0] = true;
      const i0 = p[j0];
      let delta = INF;
      let j1 = -1;
      for (let j = 1; j <= n; j += 1) {
        if (used[j]) continue;
        const current = cost[i0 - 1][j - 1] - u[i0] - v[j];
        if (current < minv[j]) { minv[j] = current; way[j] = j0; }
        if (minv[j] < delta) { delta = minv[j]; j1 = j; }
      }
      for (let j = 0; j <= n; j += 1) {
        if (used[j]) { u[p[j]] += delta; v[j] -= delta; }
        else minv[j] -= delta;
      }
      j0 = j1;
    } while (p[j0] !== 0);
    do {
      const j1 = way[j0];
      p[j0] = p[j1];
      j0 = j1;
    } while (j0);
  }
  // p[j]는 열 j에 매칭된 행. 호출부는 행(색)→열(노선)을 원하므로 뒤집어 반환한다.
  const columnForRow = new Array(rowCount).fill(-1);
  for (let j = 1; j <= n; j += 1) {
    const row = p[j] - 1;
    const column = j - 1;
    if (row >= 0 && row < rowCount && column < columnCount) columnForRow[row] = column;
  }
  return columnForRow;
}

async function openPack(packPath) {
  const resolved = path.resolve(packPath);
  const raw = await readFile(resolved);
  if (resolved.endsWith(".gz")) {
    const tempDir = await mkdtemp(path.join(tmpdir(), "easysubway-line-tracks-"));
    const tempFile = path.join(tempDir, "pack.sqlite");
    await writeTemp(tempFile, gunzipSync(raw));
    return { db: new DatabaseSync(tempFile), tempDir };
  }
  return { db: new DatabaseSync(resolved), tempDir: null };
}

function number(value) {
  return Math.round(value * 1000) / 1000;
}

// track 정점열 → "M x y L x y ..." (parseRouteMapPolyline 호환).
function pathString(points) {
  return points
    .map((point, index) => `${index === 0 ? "M" : "L"} ${number(point.x)} ${number(point.y)}`)
    .join(" ");
}

async function buildLineTracks({ geometry, pack, region, snapRadius }) {
  const geom = JSON.parse(await readFile(path.resolve(geometry), "utf8"));
  const strokes = (geom.strokes ?? []).filter((stroke) => stroke.tag !== "line" && !stroke.dashed);
  if (strokes.length === 0) throw new Error("geometry에 노선 track(polyline/path stroke)이 없다. extract-svg-geometry v2 결과인지 확인.");

  const { db, tempDir } = await openPack(pack);
  let stations;
  try {
    stations = db
      .prepare("SELECT station_id, line_id, x, y FROM route_map_positions WHERE region = ?")
      .all(region)
      .map((row) => ({ lineId: row.line_id, x: row.x, y: row.y }));
  } finally {
    db.close();
    if (tempDir) await rm(tempDir, { recursive: true, force: true });
  }
  if (stations.length === 0) throw new Error(`region '${region}'의 route_map_positions가 비어 있다.`);

  // 색별 track 묶음.
  const tracksByColor = new Map();
  for (const stroke of strokes) {
    if (!tracksByColor.has(stroke.stroke)) tracksByColor.set(stroke.stroke, []);
    tracksByColor.get(stroke.stroke).push(stroke);
  }
  const colors = [...tracksByColor.keys()];
  const lineIds = [...new Set(stations.map((station) => station.lineId))];

  // 색×line_id 근접 표수: 각 역을 "가장 가까운 색"에 투표(snapRadius 이내일 때만).
  const weight = colors.map(() => new Array(lineIds.length).fill(0));
  const lineIndex = new Map(lineIds.map((id, index) => [id, index]));
  for (const station of stations) {
    let bestColor = -1;
    let bestDistance = Infinity;
    colors.forEach((color, colorIndex) => {
      const distance = distanceToTracks(station, tracksByColor.get(color));
      if (distance < bestDistance) { bestDistance = distance; bestColor = colorIndex; }
    });
    if (bestColor >= 0 && bestDistance <= snapRadius) {
      weight[bestColor][lineIndex.get(station.lineId)] += 1;
    }
  }

  // 색↔line_id 전역 최적 1:1 매칭.
  const lineForColor = maximumWeightMatching(weight, colors.length, lineIds.length);
  const stationCountByLine = new Map();
  for (const station of stations) stationCountByLine.set(station.lineId, (stationCountByLine.get(station.lineId) ?? 0) + 1);

  const lines = [];
  const warnings = [];
  const colorToLineId = {};
  colors.forEach((color, colorIndex) => {
    const matchedLineIndex = lineForColor[colorIndex];
    const lineId = matchedLineIndex >= 0 ? lineIds[matchedLineIndex] : null;
    const votes = matchedLineIndex >= 0 ? weight[colorIndex][matchedLineIndex] : 0;
    const bestVotes = Math.max(0, ...weight[colorIndex]);
    if (!lineId) {
      warnings.push(`색 ${color}: 매칭된 노선 없음(track ${tracksByColor.get(color).length}개).`);
      return;
    }
    colorToLineId[color] = lineId;
    if (votes === 0) warnings.push(`색 ${color} → ${lineId}: 근접 역 0표(소거법 배정). 위치 검수 필요.`);
    else if (votes !== bestVotes) warnings.push(`색 ${color} → ${lineId}: 최적매칭 표(${votes})가 국소 최다표(${bestVotes})와 다름.`);
    const paths = tracksByColor.get(color)
      .filter((track) => track.points.length >= 2)
      .map((track) => pathString(track.points));
    lines.push({
      lineId,
      svgColor: color,
      trackCount: paths.length,
      matchVotes: votes,
      stationCount: stationCountByLine.get(lineId) ?? 0,
      paths,
    });
  });

  // 미매칭 노선(track 색이 배정되지 않은 line_id).
  const matchedLineIds = new Set(lines.map((line) => line.lineId));
  const unmatchedLines = lineIds.filter((id) => !matchedLineIds.has(id));
  for (const id of unmatchedLines) warnings.push(`노선 ${id}: 대응 track 색 없음.`);

  return {
    schemaVersion: 1,
    region,
    snapRadius,
    sourceExtractorVersion: geom.extractorVersion ?? null,
    colorCount: colors.length,
    lineCount: lineIds.length,
    colorToLineId,
    lines: lines.sort((a, b) => a.lineId.localeCompare(b.lineId)),
    warnings,
  };
}

function assertIntegrity(result) {
  const problems = [];
  if (result.colorCount !== result.lineCount) {
    problems.push(`track 색 수(${result.colorCount}) ≠ 노선 수(${result.lineCount}) — 색이 노선 식별자라는 전제 위반.`);
  }
  const zeroVote = result.lines.filter((line) => line.matchVotes === 0);
  if (zeroVote.length > 0) {
    problems.push(`근접 역 0표로 배정된 노선 ${zeroVote.length}개: ${zeroVote.map((line) => line.lineId).join(", ")}`);
  }
  const emptyPaths = result.lines.filter((line) => line.trackCount === 0);
  if (emptyPaths.length > 0) {
    problems.push(`track path가 비어 있는 노선 ${emptyPaths.length}개: ${emptyPaths.map((line) => line.lineId).join(", ")}`);
  }
  return problems;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }
  const result = await buildLineTracks(options);
  const problems = assertIntegrity(result);

  process.stderr.write(`[${result.region}] 색 ${result.colorCount} / 노선 ${result.lineCount} · track 노선 ${result.lines.length} · 경고 ${result.warnings.length}\n`);
  for (const warning of result.warnings) process.stderr.write(`  ⚠ ${warning}\n`);

  if (options.check) {
    if (problems.length > 0) {
      for (const problem of problems) process.stderr.write(`  ✗ ${problem}\n`);
      process.exitCode = 1;
      return;
    }
    process.stderr.write("  ✓ 무결성 통과\n");
    return;
  }

  const output = JSON.stringify(result, null, 2);
  if (options.out) {
    await writeFile(path.resolve(options.out), `${output}\n`);
    process.stderr.write(`  → ${options.out}\n`);
  } else {
    process.stdout.write(`${output}\n`);
  }
}

main().catch((error) => {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
});
