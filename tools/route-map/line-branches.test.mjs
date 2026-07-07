import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { gunzipSync } from "node:zlib";

const root = path.resolve(import.meta.dirname, "../..");

// #1793 분기 데이터 정본(line-branches.json)이 실제 팩과 정합하는지 계약으로 고정한다.
// junction·spur 역명이 해당 노선에 존재해야 octolinearize 분기가 올바로 그려진다.
const branches = JSON.parse(
  readFileSync(path.join(root, "tools/route-map/line-branches.json"), "utf8"),
);

function openCapital() {
  const index = JSON.parse(readFileSync(path.join(root, "apps/mobile/assets/datapacks/index.json"), "utf8"));
  const pack = index.packs.find((p) => p.id === "capital");
  const bytes = gunzipSync(readFileSync(path.join(root, "apps/mobile", pack.asset)));
  const dir = mkdtempSync(path.join(tmpdir(), "line-branches-"));
  const sqlitePath = path.join(dir, "capital.sqlite");
  writeFileSync(sqlitePath, bytes);
  return { db: new DatabaseSync(sqlitePath, { readOnly: true }), cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

test("line-branches 메타·구조", () => {
  assert.equal(branches.artifactKind, "route-map-line-branches");
  assert.equal(branches.issue, 1793);
  assert.ok(branches.linesByRegion && typeof branches.linesByRegion === "object");
});

test("junction·spur 역명이 해당 노선에 존재하고 spur는 비어있지 않다", () => {
  const { db, cleanup } = openCapital();
  try {
    for (const [region, lines] of Object.entries(branches.linesByRegion)) {
      for (const [lineName, specs] of Object.entries(lines)) {
        const line = db.prepare("SELECT id FROM lines WHERE name_ko = ?").get(lineName);
        assert.ok(line, `${lineName} 노선이 있어야 함`);
        const stationsOnLine = new Set(
          db.prepare(`SELECT s.name_ko AS n FROM route_map_positions rmp JOIN stations s ON s.id = rmp.station_id WHERE rmp.region = ? AND rmp.line_id = ?`).all(region, line.id).map((r) => r.n),
        );
        for (const spec of specs) {
          assert.ok(stationsOnLine.has(spec.junction), `${lineName} junction '${spec.junction}' 존재`);
          assert.ok(spec.spur.length > 0, `${lineName} ${spec.name} spur 비어있지 않음`);
          for (const st of spec.spur) {
            assert.ok(stationsOnLine.has(st), `${lineName} spur '${st}' 존재`);
          }
        }
      }
    }
  } finally {
    cleanup();
  }
});
