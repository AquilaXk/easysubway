import assert from "node:assert/strict";
import test from "node:test";
import { DatabaseSync } from "node:sqlite";
import { parsePackArgs, reparentLine } from "./station-surgery.mjs";

test("parsePackArgs는 기본값과 --pack/--index/--check를 파싱한다", () => {
  assert.deepEqual(parsePackArgs([]), {
    pack: "apps/mobile/assets/datapacks/capital.sqlite.gz",
    index: "apps/mobile/assets/datapacks/index.json",
    check: false,
  });
  const o = parsePackArgs(["--pack", "p.gz", "--index", "i.json", "--check"]);
  assert.equal(o.pack, "p.gz");
  assert.equal(o.index, "i.json");
  assert.equal(o.check, true);
});

function seedDb() {
  const db = new DatabaseSync(":memory:");
  db.exec("PRAGMA foreign_keys=ON");
  db.exec(`CREATE TABLE stations (id TEXT PRIMARY KEY, name_ko TEXT NOT NULL);`);
  db.exec(
    `CREATE TABLE station_lines (station_id TEXT, line_id TEXT, station_code TEXT DEFAULT '',
      PRIMARY KEY (station_id, line_id), FOREIGN KEY (station_id) REFERENCES stations(id));`,
  );
  db.exec(
    `CREATE TABLE route_map_positions (station_id TEXT, line_id TEXT, x INTEGER,
      PRIMARY KEY (station_id, line_id), FOREIGN KEY (station_id, line_id) REFERENCES station_lines(station_id, line_id));`,
  );
  db.exec(
    `INSERT INTO stations VALUES ('a','역'),('b','역');
     INSERT INTO station_lines VALUES ('a','L1','7'),('b','L2','3');
     INSERT INTO route_map_positions VALUES ('a','L1',10),('b','L2',20);`,
  );
  return db;
}

test("reparentLine은 노선의 station_lines·positions를 from→to로 옮긴다(FK 무결)", () => {
  const db = seedDb();
  reparentLine(db, { fromStationId: "a", toStationId: "b", lineId: "L1", label: "온수" });
  assert.equal(db.prepare("PRAGMA foreign_key_check").all().length, 0);
  assert.equal(
    db.prepare("SELECT station_id FROM station_lines WHERE line_id='L1'").get().station_id,
    "b",
  );
  assert.equal(
    db.prepare("SELECT station_id FROM route_map_positions WHERE line_id='L1'").get().station_id,
    "b",
  );
  // 대표 b는 이제 L1·L2 둘 다
  assert.equal(db.prepare("SELECT COUNT(*) c FROM station_lines WHERE station_id='b'").get().c, 2);
});

test("reparentLine은 대상이 이미 그 노선을 가지면 예외", () => {
  const db = seedDb();
  db.exec("INSERT INTO station_lines VALUES ('b','L1','9')");
  assert.throws(
    () => reparentLine(db, { fromStationId: "a", toStationId: "b", lineId: "L1" }),
    /PK 충돌/,
  );
});
