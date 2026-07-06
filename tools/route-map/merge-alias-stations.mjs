#!/usr/bin/env node
// #1789 Phase 0 (P0.1b): 오분리 별칭 병합 — 실제로는 한 물리역(환승)이 별도
// station_id("…역" 접미 별칭)로 잘못 나뉜 것을 대표 역의 환승 그룹에 병합한다.
// 서해선 개통 데이터가 기존 환승역과 이어지지 못하고 별칭 역으로 남은 사례.
//
// ⛔ 사실 확정은 공식 출처(서울열린데이터광장 역 목록). audit-transfer-groups의
//   병합 의심(동명 정규화·근접·별개 id)은 탐지 힌트. 수도권 전 노선 전수에서
//   "…역" 접미 별칭 오분리는 아래 2건뿐이다.
//   - 김포공항: 서해선 "김포공항역" → 공항철도·5·9·김포골드 환승 그룹(대표)
//   - 부천종합운동장: 서해선 "부천종합운동장역" → 7호선 환승 그룹(대표)
//
// id 정책: 대표 id 유지, 별칭 id의 station_lines·route_map_positions 행을 대표
// id로 재지정 후 고아 별칭 stations 행 삭제. 병합 후 환승 그룹 멤버 수가 공식과
// 일치해야 한다(김포공항 5개).
//
// 사용: node tools/route-map/merge-alias-stations.mjs [--pack …] [--check]
import { cleanupPackDir, openPack, writePack } from "./pack-io.mjs";

/** 병합 대상(공식 근거 첨부). aliasId를 representativeId 그룹으로 흡수. */
export const MERGES = [
  {
    name: "김포공항",
    aliasId: "station-cbe94ebaafe2", // "김포공항역"(서해선)
    representativeId: "station-1f38f0831cb1", // "김포공항"(공항·5·9·김포골드)
    evidence: "서해선 김포공항역 = 공항철도·5·9·김포골드 환승과 동일 물리역(멤버 5)",
  },
  {
    name: "부천종합운동장",
    aliasId: "station-bf7791ea1bfd", // "부천종합운동장역"(서해선)
    representativeId: "station-28be6a80c00e", // "부천종합운동장"(7호선)
    evidence: "서해선 부천종합운동장역 = 7호선 환승과 동일 물리역(멤버 2)",
  },
];

/**
 * 순수: 별칭 id·그 노선 목록·대표 id → 병합 계획.
 * 각 노선 멤버십 행을 대표 id로 재지정(route_map_positions·station_lines 공통)
 * 하고, 흡수된 뒤 남는 별칭 stations 행을 삭제한다.
 */
export function planMerge(aliasId, aliasLineIds, representativeId) {
  return {
    deleteStationId: aliasId,
    reassignments: aliasLineIds.map((lineId) => ({
      lineId,
      fromStationId: aliasId,
      toStationId: representativeId,
    })),
  };
}

function parseArgs(argv) {
  const o = {
    pack: "apps/mobile/assets/datapacks/capital.sqlite.gz",
    index: "apps/mobile/assets/datapacks/index.json",
    check: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    switch (argv[i]) {
      case "--pack": o.pack = argv[++i]; break;
      case "--index": o.index = argv[++i]; break;
      case "--check": o.check = true; break;
    }
  }
  return o;
}

function applyMerge(db, spec) {
  const alias = db.prepare("SELECT id FROM stations WHERE id=?").get(spec.aliasId);
  const rep = db.prepare("SELECT id FROM stations WHERE id=?").get(spec.representativeId);
  if (!rep) throw new Error(`${spec.name}: 대표 역 없음 ${spec.representativeId}`);
  if (!alias) return { name: spec.name, skipped: "이미 병합됨" };
  const aliasLines = db
    .prepare("SELECT * FROM station_lines WHERE station_id=? ORDER BY line_id")
    .all(spec.aliasId);
  const plan = planMerge(
    spec.aliasId,
    aliasLines.map((r) => r.line_id),
    spec.representativeId,
  );
  // route_map_positions.(station_id,line_id) → station_lines FK 순서를 지켜:
  // 대표 id로 station_lines 복제 → positions 재지정 → 별칭 station_lines 삭제.
  for (const sl of aliasLines) {
    const dup = db
      .prepare("SELECT 1 FROM station_lines WHERE station_id=? AND line_id=?")
      .get(spec.representativeId, sl.line_id);
    if (dup) {
      throw new Error(
        `${spec.name}: 대표 id가 이미 ${sl.line_id} 멤버 — PK 충돌, 수동 확인 필요`,
      );
    }
    const cols = Object.keys(sl);
    db.prepare(
      `INSERT INTO station_lines (${cols.join(",")}) VALUES (${cols.map(() => "?").join(",")})`,
    ).run(...cols.map((c) => (c === "station_id" ? spec.representativeId : sl[c])));
    db.prepare(
      "UPDATE route_map_positions SET station_id=? WHERE station_id=? AND line_id=?",
    ).run(spec.representativeId, spec.aliasId, sl.line_id);
    db.prepare(
      "DELETE FROM station_lines WHERE station_id=? AND line_id=?",
    ).run(spec.aliasId, sl.line_id);
  }
  db.prepare("DELETE FROM stations WHERE id=?").run(plan.deleteStationId);
  const memberCount = db
    .prepare("SELECT COUNT(*) c FROM station_lines WHERE station_id=?")
    .get(spec.representativeId).c;
  return {
    name: spec.name,
    representativeId: spec.representativeId,
    merged: spec.aliasId,
    lines: plan.reassignments.map((r) => r.lineId),
    memberCount,
    evidence: spec.evidence,
  };
}

function main() {
  const o = parseArgs(process.argv.slice(2));
  const { db, dir, sqlitePath, packPath } = openPack(o.pack, "merge-alias-");
  try {
    if (o.check) {
      for (const spec of MERGES) {
        const alias = db.prepare("SELECT name_ko FROM stations WHERE id=?").get(spec.aliasId);
        console.log(
          `(--check) ${spec.name}: 별칭 ${spec.aliasId}(${alias?.name_ko ?? "없음"}) → 대표 ${spec.representativeId} (${spec.evidence})`,
        );
      }
      return;
    }
    db.exec("BEGIN");
    const results = MERGES.map((spec) => applyMerge(db, spec));
    db.exec("COMMIT");
    for (const r of results) {
      if (r.skipped) {
        console.log(`${r.name}: ${r.skipped}`);
      } else {
        console.log(
          `${r.name}: ${r.merged} → ${r.representativeId} · 노선 ${r.lines.join(",")} · 멤버 ${r.memberCount} (${r.evidence})`,
        );
      }
    }
    db.close();
    const { byteSize } = writePack({
      sqlitePath,
      packPath,
      packRelPath: o.pack,
      indexRelPath: o.index,
    });
    console.log(`팩 갱신 (byteSize ${byteSize}) — enrich 재실행으로 정합 확인 권장.`);
  } finally {
    cleanupPackDir(dir);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
