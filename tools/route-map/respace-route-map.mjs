#!/usr/bin/env node
// #1789 재간격(schematic respacing): 준지리형 수도권 기하의 인접 역 간격을
// 8선형 방향 보존 아래 [min,max]로 정규화한다(도심 확대·외곽 압축 — 카카오·
// 서울시 신형 노선도의 준균일 간격 문법). 스펙:
// docs/superpowers/specs/2026-07-06-route-map-respacing-design.md

const round3 = (v) => Math.round(v * 1000) / 1000;
const EPS = 1e-6;
const REUSE_DIST = 0.5; // 이 거리 내면 기존 정점 재사용(중복 삽입 방지).
const WARN_DIST = 2.0; // 투영 거리가 이보다 크면 데이터 의심 경고.

/** 점 p를 선분 (a,b)에 투영 — 삽입 정렬에 필요한 매개변수 t 포함. */
function projectWithParam(p, a, b) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const lenSq = dx * dx + dy * dy;
  if (lenSq === 0) {
    return { x: a.x, y: a.y, t: 0, dist: Math.hypot(p.x - a.x, p.y - a.y) };
  }
  const t = Math.max(
    0,
    Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq),
  );
  const x = a.x + t * dx;
  const y = a.y + t * dy;
  return { x, y, t, dist: Math.hypot(p.x - x, p.y - y) };
}

export function parsePathPoints(path) {
  const nums = [...String(path).matchAll(/-?\d+(?:\.\d+)?/g)].map((m) =>
    Number(m[0]),
  );
  const points = [];
  for (let i = 0; i + 1 < nums.length; i += 2) {
    const p = { x: nums[i], y: nums[i + 1] };
    const last = points[points.length - 1];
    if (!last || last.x !== p.x || last.y !== p.y) {
      points.push(p);
    }
  }
  return points;
}

export function serializePathPoints(points) {
  return points
    .map((p, i) => `${i === 0 ? "M" : "L"} ${round3(p.x)} ${round3(p.y)}`)
    .join(" ");
}

/**
 * track polyline과 역 투영점을 하나의 그래프로 만든다. 역을 선분 위 정점으로
 * 삽입하고, 역-역 chain·환승 cluster를 산출한다(스펙 R1 Task 4).
 */
export function buildRespaceGraph({ tracks, positions }) {
  const posByLine = new Map();
  for (const p of positions) {
    if (!posByLine.has(p.lineId)) posByLine.set(p.lineId, []);
    posByLine.get(p.lineId).push(p);
  }

  const nodes = [];
  const outTracks = [];
  const stationNodes = [];
  const chains = [];
  const warnings = [];
  const clusterAcc = new Map(); // stationId → [{nodeId, point}]

  for (let ti = 0; ti < tracks.length; ti += 1) {
    const track = tracks[ti];
    const pts = track.points;
    if (pts.length === 0) {
      outTracks.push({
        lineId: track.lineId,
        trackIndex: track.trackIndex,
        nodeIds: [],
        closed: false,
      });
      continue;
    }
    const closed =
      pts.length >= 2 &&
      Math.abs(pts[0].x - pts[pts.length - 1].x) < EPS &&
      Math.abs(pts[0].y - pts[pts.length - 1].y) < EPS;
    // 닫힌 track은 중복 끝점을 떼고(뒤에서 alias) 순환 세그먼트로 다룬다.
    const verts = closed ? pts.slice(0, pts.length - 1) : pts.slice();
    const segCount = closed ? verts.length : verts.length - 1;

    // 이 노선 역을 최근접 세그먼트에 투영 → 기존 정점 재사용 or 삽입 예약.
    const insertions = new Map(); // segIndex → [{t, station, x, y}]
    const exactVertex = []; // {station, vertexIndex}
    for (const st of posByLine.get(track.lineId) ?? []) {
      let best = null;
      for (let s = 0; s < segCount; s += 1) {
        const a = verts[s];
        const b = verts[(s + 1) % verts.length];
        const pr = projectWithParam(st, a, b);
        if (best === null || pr.dist < best.dist) best = { ...pr, seg: s };
      }
      if (best === null) continue;
      if (best.dist > WARN_DIST) {
        warnings.push(`${st.stationId} 투영거리 ${round3(best.dist)}`);
      }
      const a = verts[best.seg];
      const b = verts[(best.seg + 1) % verts.length];
      if (Math.hypot(st.x - a.x, st.y - a.y) < REUSE_DIST) {
        exactVertex.push({ station: st, vertexIndex: best.seg });
      } else if (Math.hypot(st.x - b.x, st.y - b.y) < REUSE_DIST) {
        exactVertex.push({
          station: st,
          vertexIndex: (best.seg + 1) % verts.length,
        });
      } else {
        if (!insertions.has(best.seg)) insertions.set(best.seg, []);
        insertions.get(best.seg).push({
          t: best.t,
          station: st,
          x: best.x,
          y: best.y,
        });
      }
    }

    // 삽입을 반영한 새 정점 배열 + 역→새 정점 index 매핑.
    const newVerts = [];
    const oldToNew = new Array(verts.length);
    const stationToVertex = new Map();
    for (let vi = 0; vi < verts.length; vi += 1) {
      oldToNew[vi] = newVerts.length;
      newVerts.push(verts[vi]);
      const ins = insertions.get(vi);
      if (ins) {
        ins.sort((p, q) => p.t - q.t);
        for (const it of ins) {
          stationToVertex.set(it.station, newVerts.length);
          newVerts.push({ x: it.x, y: it.y });
        }
      }
    }
    for (const ev of exactVertex) {
      stationToVertex.set(ev.station, oldToNew[ev.vertexIndex]);
    }

    // 노드 등록(트랙 간 비공유). 닫힌 트랙은 끝에 첫 노드 alias.
    const baseNodeId = nodes.length;
    for (const v of newVerts) nodes.push({ x: v.x, y: v.y });
    const nodeIds = newVerts.map((_, i) => baseNodeId + i);
    if (closed) nodeIds.push(baseNodeId);
    outTracks.push({
      lineId: track.lineId,
      trackIndex: track.trackIndex,
      nodeIds,
      closed,
    });

    // stationNodes + cluster 누적. (positions 순서 보존을 위해 순회 순서 유지.)
    const stationVertexIndices = [];
    for (const st of posByLine.get(track.lineId) ?? []) {
      if (!stationToVertex.has(st)) continue;
      const vIndex = stationToVertex.get(st);
      const nodeId = baseNodeId + vIndex;
      stationNodes.push({
        stationId: st.stationId,
        lineId: st.lineId,
        nodeId,
      });
      if (!clusterAcc.has(st.stationId)) clusterAcc.set(st.stationId, []);
      clusterAcc.get(st.stationId).push({
        nodeId,
        point: { x: nodes[nodeId].x, y: nodes[nodeId].y },
      });
      stationVertexIndices.push(vIndex);
    }

    // chains: 트랙 정점열을 역 정점에서 절단.
    const stIdx = [...new Set(stationVertexIndices)].sort((p, q) => p - q);
    const stSet = new Set(stIdx);
    if (!closed) {
      const bounds = [
        ...new Set([0, newVerts.length - 1, ...stIdx]),
      ].sort((p, q) => p - q);
      for (let i = 0; i + 1 < bounds.length; i += 1) {
        const lo = bounds[i];
        const hi = bounds[i + 1];
        chains.push({
          trackIdx: ti,
          nodeIds: nodeIds.slice(lo, hi + 1),
          hasStationEnds: stSet.has(lo) && stSet.has(hi),
        });
      }
    } else if (stIdx.length >= 2) {
      for (let i = 0; i < stIdx.length; i += 1) {
        const lo = stIdx[i];
        const hi = stIdx[(i + 1) % stIdx.length];
        const seq = [nodeIds[lo]];
        let k = lo;
        while (k !== hi) {
          k = (k + 1) % newVerts.length;
          seq.push(nodeIds[k]);
        }
        chains.push({ trackIdx: ti, nodeIds: seq, hasStationEnds: true });
      }
    }
  }

  const clusters = [];
  for (const [stationId, members] of clusterAcc) {
    if (members.length < 2) continue;
    const mx = members.reduce((s, m) => s + m.point.x, 0) / members.length;
    const my = members.reduce((s, m) => s + m.point.y, 0) / members.length;
    clusters.push({
      stationId,
      members: members.map((m) => ({
        nodeId: m.nodeId,
        offset: { x: m.point.x - mx, y: m.point.y - my },
      })),
    });
  }

  return { nodes, tracks: outTracks, stationNodes, chains, clusters, warnings };
}

function dist2(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function chainLength(nodes, nodeIds) {
  let sum = 0;
  for (let i = 1; i < nodeIds.length; i += 1) {
    sum += dist2(nodes[nodeIds[i - 1]], nodes[nodeIds[i]]);
  }
  return sum;
}

/** hasStationEnds chain 길이의 중앙값 (재간격 단위 unit 기본값). */
export function medianStationChainLength(graph) {
  const lengths = graph.chains
    .filter((c) => c.hasStationEnds)
    .map((c) => chainLength(graph.nodes, c.nodeIds))
    .sort((a, b) => a - b);
  return lengths.length ? lengths[Math.floor(lengths.length / 2)] : 0;
}

/**
 * 방향 고정·길이 목표의 위치 기반 반복 완화(PBD식 Gauss–Seidel). 역-역 chain은
 * [minRatio,maxRatio]·unit으로 클램프해 도심 확대·외곽 압축하고, 방향(원본 8선형)
 * 은 마무리 폴리싱으로 정확 복원한다. 환승 cluster는 강체 결합으로 offset 유지.
 */
export function respaceGraph(graph, options) {
  const {
    unit,
    minRatio = 1.0,
    maxRatio = 2.5,
    iterations = 800,
    tolerance = 0.01,
    polishSweeps = 50,
  } = options;
  const orig = graph.nodes;
  const clampLen = (v) =>
    Math.max(minRatio * unit, Math.min(maxRatio * unit, v));

  // 세그먼트 목표 길이(chain scale) + 원본 방향(고정).
  const segTargetByKey = new Map();
  for (const chain of graph.chains) {
    const ids = chain.nodeIds;
    const cur = chainLength(orig, ids);
    const target = chain.hasStationEnds ? clampLen(cur) : cur;
    const scale = cur > 0 ? target / cur : 1;
    for (let i = 1; i < ids.length; i += 1) {
      const ol = dist2(orig[ids[i - 1]], orig[ids[i]]);
      segTargetByKey.set(`${ids[i - 1]},${ids[i]}`, ol * scale);
    }
  }
  const segments = [];
  for (const track of graph.tracks) {
    const ids = track.nodeIds;
    for (let i = 1; i < ids.length; i += 1) {
      const a = ids[i - 1];
      const b = ids[i];
      const ol = dist2(orig[a], orig[b]);
      const dir =
        ol > 0
          ? { x: (orig[b].x - orig[a].x) / ol, y: (orig[b].y - orig[a].y) / ol }
          : { x: 0, y: 0 };
      const key = `${a},${b}`;
      segments.push({
        a,
        b,
        dir,
        target: segTargetByKey.has(key) ? segTargetByKey.get(key) : ol,
      });
    }
  }

  const positions = orig.map((n) => ({ x: n.x, y: n.y }));
  const anchor = 0; // nodes[0] 원좌표 고정(병진 자유도 제거).

  const resyncClusters = () => {
    for (const cluster of graph.clusters) {
      let mx = 0;
      let my = 0;
      for (const m of cluster.members) {
        mx += positions[m.nodeId].x - m.offset.x;
        my += positions[m.nodeId].y - m.offset.y;
      }
      mx /= cluster.members.length;
      my /= cluster.members.length;
      for (const m of cluster.members) {
        positions[m.nodeId] = { x: mx + m.offset.x, y: my + m.offset.y };
      }
    }
  };

  const sweep = (perpendicularOnly) => {
    let maxCorrection = 0;
    for (const seg of segments) {
      const pa = positions[seg.a];
      const pb = positions[seg.b];
      let ex = pb.x - pa.x - seg.dir.x * seg.target;
      let ey = pb.y - pa.y - seg.dir.y * seg.target;
      if (perpendicularOnly) {
        const along = ex * seg.dir.x + ey * seg.dir.y;
        ex -= along * seg.dir.x;
        ey -= along * seg.dir.y;
      }
      const mag = Math.hypot(ex, ey);
      if (mag > maxCorrection) maxCorrection = mag;
      if (seg.a === anchor && seg.b === anchor) continue;
      if (seg.a === anchor) {
        positions[seg.b] = { x: pb.x - ex, y: pb.y - ey };
      } else if (seg.b === anchor) {
        positions[seg.a] = { x: pa.x + ex, y: pa.y + ey };
      } else {
        positions[seg.a] = { x: pa.x + ex / 2, y: pa.y + ey / 2 };
        positions[seg.b] = { x: pb.x - ex / 2, y: pb.y - ey / 2 };
      }
    }
    return maxCorrection;
  };

  let sweeps = 0;
  let maxResidual = 0;
  for (let it = 0; it < iterations; it += 1) {
    maxResidual = sweep(false);
    resyncClusters();
    sweeps += 1;
    if (maxResidual < tolerance) break;
  }
  for (let it = 0; it < polishSweeps; it += 1) {
    maxResidual = sweep(true);
    resyncClusters();
    sweeps += 1;
  }
  return { positions, report: { sweeps, maxResidual } };
}
