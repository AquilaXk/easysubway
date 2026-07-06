#!/usr/bin/env node
// #1789 Phase 0 (P0.2): 부역명 필드 분리. 카탈로그의 name_ko가 "역명(부역명)"
// 합성이라(예: "가야대(삼계)") 라벨이 길고 데이터가 뭉쳐 있다. name_sub 컬럼을
// 더해 name_ko=역명 / name_sub=부역명으로 가른다. 라벨은 name_ko(이미
// routeMapStationLabel이 괄호 축약), 검색은 name_sub도 히트(앱 matches()), 상세/탭은
// name_sub 표기.
//
// 이 도구는 커밋 팩(capital)의 stations를 마이그레이션한다: name_sub 컬럼 추가(없으면)
// 후 괄호 역들을 populate. 스키마 정의(catalog-schema.sql·build-datapack.mjs·drift
// catalog_tables.dart)와 drift onUpgrade는 별도로 갱신한다. 데이터팩 전송 schemaVersion은
// 범프하지 않는다(번들 팩을 같은 PR에서 갱신, 앱 drift가 열 때 컬럼 정합).
//
// 사용: node tools/datapack/split-station-subnames.mjs [--pack …] [--check]
import { cleanupPackDir, openPack, writePack } from "../route-map/pack-io.mjs";

/**
 * 순수: "역명(부역명)" → { nameKo: 역명, nameSub: 부역명 }.
 * '('가 없거나 맨 앞이면 부역명은 빈 문자열(원문 유지). 첫 '(' 이전을 역명으로
 * 취해 라벨 축약(routeMapStationLabel)과 base가 일치한다. 부역명은 첫 '('와 마지막
 * ')' 사이(점·영문·숫자 보존).
 */
export function splitStationName(nameKo) {
  const open = nameKo.indexOf("(");
  if (open <= 0) {
    return { nameKo: nameKo.trim(), nameSub: "" };
  }
  const close = nameKo.lastIndexOf(")");
  const base = nameKo.slice(0, open).trim();
  const sub = (close > open ? nameKo.slice(open + 1, close) : nameKo.slice(open + 1)).trim();
  return { nameKo: base, nameSub: sub };
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

function main() {
  const o = parseArgs(process.argv.slice(2));
  const { db, dir, sqlitePath, packPath } = openPack(o.pack, "split-subnames-");
  try {
    const cols = db.prepare("PRAGMA table_info(stations)").all().map((c) => c.name);
    const rows = db
      .prepare("SELECT id, name_ko FROM stations WHERE name_ko LIKE '%(%'")
      .all();
    if (o.check) {
      console.log(
        `(--check) name_sub 컬럼 ${cols.includes("name_sub") ? "있음" : "추가 예정"} · 괄호 역 ${rows.length}건 분리 예정`,
      );
      for (const r of rows.slice(0, 5)) {
        const { nameKo, nameSub } = splitStationName(r.name_ko);
        console.log(`    "${r.name_ko}" → "${nameKo}" + "${nameSub}"`);
      }
      return;
    }
    if (!cols.includes("name_sub")) {
      db.exec("ALTER TABLE stations ADD COLUMN name_sub TEXT NOT NULL DEFAULT ''");
    }
    db.exec("BEGIN");
    let n = 0;
    const upd = db.prepare("UPDATE stations SET name_ko=?, name_sub=? WHERE id=?");
    for (const r of rows) {
      const { nameKo, nameSub } = splitStationName(r.name_ko);
      if (nameSub) {
        upd.run(nameKo, nameSub, r.id);
        n += 1;
      }
    }
    db.exec("COMMIT");
    console.log(`name_sub 컬럼 확보 · ${n}개 역 부역명 분리`);
    db.close();
    const { byteSize } = writePack({
      sqlitePath,
      packPath,
      packRelPath: o.pack,
      indexRelPath: o.index,
    });
    console.log(`팩 갱신 (byteSize ${byteSize})`);
  } finally {
    cleanupPackDir(dir);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
