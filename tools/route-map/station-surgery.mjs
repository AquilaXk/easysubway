// 공용 station 카탈로그 수술 헬퍼 (#1789 P0). split/merge 도구가 공유하는
// 인자 파싱·FK-safe 노선 재지정·팩 open/write 스캐폴드를 한곳에 모아 중복을 없앤다.
import { cleanupPackDir, openPack, writePack } from "./pack-io.mjs";

/** {pack,index,check} 공통 인자 파서. */
export function parsePackArgs(argv) {
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

/**
 * 한 노선의 (station_lines + route_map_positions) 행을 from→to station_id로 이전한다.
 * route_map_positions.(station_id,line_id)→station_lines FK가 걸려 있어(원행을 먼저
 * 바꾸면 positions가 순간 고아) 복제→positions 재지정→원행 삭제 순서로 무결성을
 * 유지한다. 대상 id가 이미 그 노선을 가지면 PK 충돌이므로 예외.
 */
export function reparentLine(db, { fromStationId, toStationId, lineId, label = "" }) {
  const dup = db
    .prepare("SELECT 1 FROM station_lines WHERE station_id=? AND line_id=?")
    .get(toStationId, lineId);
  if (dup) throw new Error(`${label}: 대상 id가 이미 ${lineId} 멤버 — PK 충돌, 수동 확인`);
  const sl = db
    .prepare("SELECT * FROM station_lines WHERE station_id=? AND line_id=?")
    .get(fromStationId, lineId);
  if (!sl) throw new Error(`${label}: 이동할 station_line 없음 (${fromStationId},${lineId})`);
  const cols = Object.keys(sl);
  db.prepare(
    `INSERT INTO station_lines (${cols.join(",")}) VALUES (${cols.map(() => "?").join(",")})`,
  ).run(...cols.map((c) => (c === "station_id" ? toStationId : sl[c])));
  db.prepare(
    "UPDATE route_map_positions SET station_id=? WHERE station_id=? AND line_id=?",
  ).run(toStationId, fromStationId, lineId);
  db.prepare("DELETE FROM station_lines WHERE station_id=? AND line_id=?").run(
    fromStationId,
    lineId,
  );
}

/**
 * 팩을 임시 sqlite로 열어 `run(db)`를 실행하고, check가 아니면 다시 써 넣는다.
 * `run`은 BEGIN/COMMIT과 콘솔 출력을 스스로 처리한다(check 모드는 write 생략).
 */
export function mutatePack({ pack, index, tmpPrefix, check, run }) {
  const { db, dir, sqlitePath, packPath } = openPack(pack, tmpPrefix);
  try {
    run(db);
    if (check) return;
    db.close();
    const { byteSize } = writePack({
      sqlitePath,
      packPath,
      packRelPath: pack,
      indexRelPath: index,
    });
    console.log(`팩 갱신 (byteSize ${byteSize})`);
  } finally {
    cleanupPackDir(dir);
  }
}
