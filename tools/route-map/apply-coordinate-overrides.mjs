#!/usr/bin/env node
// #1789 P2.2: C2 수동 오버라이드 테이블(route-map-coordinate-overrides.json)로 B-국소가
// 극단 티어로 미룬 환승 7건을 오라클 캡슐에 손배치한다. B-국소 splice 기계 재사용,
// 그룹별 maxDist 상향으로 대변위(신사 102px) 부착. 자동 수렴 경로 기본값은 불변.
// ⛔ 가드레일: 테이블은 targetSpan·axis만(좌표 없음). 좌표는 여기서 8선형으로 도출.
import { readFileSync } from "node:fs";
import { capsuleAxis, capsuleTargets, spliceTrackToNode, transferGroups } from "./splice-transfer-convergence.mjs";
import { parsePathVertices, verticesToPath } from "./audit-octolinearity.mjs";
import { cleanupPackDir, openPack, writePack } from "./pack-io.mjs";

/** 한 그룹을 override(targetSpan·axis·maxDist)로 수렴. convergeGroup과 동형·maxDist 전달. */
export function applyOverrideGroup(group, override, tracksByLine) {
  const axis = override.axis === "auto" || !override.axis ? capsuleAxis(group.members) : override.axis;
  const targets = capsuleTargets(group.members, override.targetSpan, axis);
  const targetByLine = new Map(targets.map((t) => [t.lineId, t]));
  const positionUpdates = [];
  const trackUpdates = [];
  for (const m of group.members) {
    const nt = targetByLine.get(m.lineId);
    const newPos = { x: Math.round(nt.x), y: Math.round(nt.y) };
    let attachedAny = false;
    for (const trk of tracksByLine.get(m.lineId) ?? []) {
      const { verts, attached } = spliceTrackToNode(trk.verts, { x: m.x, y: m.y }, newPos, { maxDist: override.maxDist });
      if (attached) {
        attachedAny = true;
        if (JSON.stringify(verts) !== JSON.stringify(trk.verts)) {
          trackUpdates.push({ lineId: m.lineId, trackIndex: trk.trackIndex, verts });
        }
      }
    }
    if (attachedAny) positionUpdates.push({ stationId: group.stationId, lineId: m.lineId, x: newPos.x, y: newPos.y });
  }
  return { positionUpdates, trackUpdates };
}
