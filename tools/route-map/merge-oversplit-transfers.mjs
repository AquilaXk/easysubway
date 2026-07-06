#!/usr/bin/env node
// #1789 Phase 0 (P0.1b 확장): 부역명에 가려졌던 환승역 오분리 병합. 준지리형
// 소스가 한 물리 환승역의 노선들을 별도 station_id로 쪼갰는데, 한쪽만 부역명이
// 붙어 name_ko가 달라 audit(동명 근접)가 못 잡았다. P0.2가 부역명을 name_sub로
// 떼어내며 두 id의 name_ko가 같아져 노출됐다. 전부 공식 환승역(같은 물리역)이라
// 단일 노드로 병합한다.
//
// ⛔ 사실 확정은 공식 출처(서울열린데이터광장 환승역 목록). audit 병합의심은
//   탐지 힌트. 신촌·양평(108/382px 별개역)과 달리 이들은 <60px 동일역.
//
// id 정책: 대표 id = 노선 많은 쪽(동수면 번호 호선 우선) 유지, 흡수 id의 노선
// 멤버십을 대표로 재지정 후 고아 삭제. 부역명은 병합 후 대표에 보존
// (대표가 비면 흡수분에서 가져옴).
//
// 사용: node tools/route-map/merge-oversplit-transfers.mjs [--pack …] [--check]
import { cleanupPackDir, openPack, writePack } from "./pack-io.mjs";
import { planMerge } from "./merge-alias-stations.mjs";

/** 병합 대상. keepId=대표(노선 많은/번호 호선), dropId=흡수, expectedSub=병합 후 부역명. */
export const MERGES = [
  { name: "온수", keepId: "station-0fe1a97dd89c", dropId: "station-8a825f7102fc", expectedSub: "성공회대입구", evidence: "1호선·7호선 환승역(성공회대입구)" },
  { name: "별내", keepId: "station-6f6328bd8ba0", dropId: "station-8dbfb267f86a", expectedSub: "삼육대학교", evidence: "8호선·경춘선 환승역(삼육대학교)" },
  { name: "복정", keepId: "station-0da713fa586e", dropId: "station-b0d79168d9e1", expectedSub: "동서울대학", evidence: "8호선·수인분당선 환승역(동서울대학)" },
  { name: "성신여대입구", keepId: "station-d490bb686722", dropId: "station-768d93d8b4c1", expectedSub: "돈암", evidence: "4호선·우이신설선 환승역(돈암)" },
  { name: "종로3가", keepId: "station-1c24eb757f3c", dropId: "station-839e725421e8", expectedSub: "탑골공원", evidence: "1·3·5호선 환승역(탑골공원)" },
  { name: "청량리", keepId: "station-b819702fa7d9", dropId: "station-b3a9b7ff1478", expectedSub: "서울시립대입구", evidence: "1호선·경의중앙·경춘·수인분당 환승역(서울시립대입구)" },
  { name: "이촌", keepId: "station-b90e3daa23a1", dropId: "station-bef6478fc602", expectedSub: "국립중앙박물관", evidence: "4호선·경의중앙 환승역(국립중앙박물관)" },
];

/** 순수: 병합 후 부역명 = 대표 우선, 없으면 흡수분. */
export function reconcileNameSub(keepSub, dropSub) {
  return keepSub && keepSub.length > 0 ? keepSub : dropSub ?? "";
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
  const keep = db.prepare("SELECT id, name_sub FROM stations WHERE id=?").get(spec.keepId);
  const drop = db.prepare("SELECT id, name_sub FROM stations WHERE id=?").get(spec.dropId);
  if (!keep) throw new Error(`${spec.name}: 대표 역 없음 ${spec.keepId}`);
  if (!drop) return { name: spec.name, skipped: "이미 병합됨" };
  const dropLines = db
    .prepare("SELECT * FROM station_lines WHERE station_id=? ORDER BY line_id")
    .all(spec.dropId);
  const plan = planMerge(spec.dropId, dropLines.map((r) => r.line_id), spec.keepId);
  // FK 순서(route_map_positions.(station_id,line_id)→station_lines): 대표로 복제→
  // positions 재지정→흡수 행 삭제.
  for (const sl of dropLines) {
    const dup = db
      .prepare("SELECT 1 FROM station_lines WHERE station_id=? AND line_id=?")
      .get(spec.keepId, sl.line_id);
    if (dup) throw new Error(`${spec.name}: 대표가 이미 ${sl.line_id} 멤버 — 수동 확인`);
    const cols = Object.keys(sl);
    db.prepare(
      `INSERT INTO station_lines (${cols.join(",")}) VALUES (${cols.map(() => "?").join(",")})`,
    ).run(...cols.map((c) => (c === "station_id" ? spec.keepId : sl[c])));
    db.prepare(
      "UPDATE route_map_positions SET station_id=? WHERE station_id=? AND line_id=?",
    ).run(spec.keepId, spec.dropId, sl.line_id);
    db.prepare("DELETE FROM station_lines WHERE station_id=? AND line_id=?").run(spec.dropId, sl.line_id);
  }
  // 부역명 보존
  const mergedSub = reconcileNameSub(keep.name_sub, drop.name_sub);
  db.prepare("UPDATE stations SET name_sub=? WHERE id=?").run(mergedSub, spec.keepId);
  db.prepare("DELETE FROM stations WHERE id=?").run(plan.deleteStationId);
  const memberCount = db
    .prepare("SELECT COUNT(*) c FROM station_lines WHERE station_id=?")
    .get(spec.keepId).c;
  return { name: spec.name, keepId: spec.keepId, dropId: spec.dropId, mergedSub, memberCount };
}

function main() {
  const o = parseArgs(process.argv.slice(2));
  const { db, dir, sqlitePath, packPath } = openPack(o.pack, "merge-oversplit-");
  try {
    if (o.check) {
      for (const spec of MERGES) {
        const drop = db.prepare("SELECT name_ko FROM stations WHERE id=?").get(spec.dropId);
        console.log(`(--check) ${spec.name}: ${spec.dropId}(${drop?.name_ko ?? "없음"}) → ${spec.keepId} · 부역명 ${spec.expectedSub} (${spec.evidence})`);
      }
      return;
    }
    db.exec("BEGIN");
    const results = MERGES.map((spec) => applyMerge(db, spec));
    db.exec("COMMIT");
    for (const r of results) {
      if (r.skipped) console.log(`${r.name}: ${r.skipped}`);
      else console.log(`${r.name}: ${r.dropId} → ${r.keepId} · 멤버 ${r.memberCount} · 부역명 "${r.mergedSub}"`);
    }
    db.close();
    const { byteSize } = writePack({ sqlitePath, packPath, packRelPath: o.pack, indexRelPath: o.index });
    console.log(`팩 갱신 (byteSize ${byteSize})`);
  } finally {
    cleanupPackDir(dir);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
