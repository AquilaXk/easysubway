import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { promisify } from "node:util";
import { gunzipSync, gzipSync } from "node:zlib";

import {
  ALLOWLIST_PATH,
  CATALOG_DATABASE_PATH,
  CATALOG_OPENER_PATH,
  DRIFT_GENERATED_PATH,
  PACK_SCHEMA_PATH,
  RAW_SQL_TABLES_PATH,
  REPOSITORY_ROOT,
  checkPackAppSchemaParity,
  evaluatePackAppSchemaParity,
  evaluateRawSqlTableContract,
  normalizeAllowlist,
  parseAppSchemaVersion,
  parseCatalogPackId,
  parseDartStringSetConstant,
  parseDriftDeclaredTables,
  parsePackSchemaIndexes,
  parseRescuableTableNames,
  scanRawSqlTableTokens,
} from "./check-pack-app-schema-parity.mjs";

const execFileAsync = promisify(execFile);
const read = (relative) => readFile(path.resolve(REPOSITORY_ROOT, relative), "utf8");

async function incompletePackFixture(directory) {
  const sqlitePath = path.join(directory, "capital.sqlite");
  await writeFile(sqlitePath, gunzipSync(await readFile(path.join(
    REPOSITORY_ROOT,
    "apps/mobile/assets/datapacks/capital.sqlite.gz",
  ))));
  const database = new DatabaseSync(sqlitePath);
  database.exec("DROP TABLE station_facility_evidence");
  database.close();
  const packPath = `${sqlitePath}.gz`;
  await writeFile(packPath, gzipSync(await readFile(sqlitePath), { level: 9, mtime: 0 }));
  return packPath;
}

test("앱 drift 선언 테이블을 생성 산출물에서 읽는다", async () => {
  const tables = parseDriftDeclaredTables(await read(DRIFT_GENERATED_PATH));

  assert.equal(tables.length, 33);
  assert.ok(tables.includes("fare_zones"));
  assert.ok(tables.includes("station_facility_evidence"));
  assert.ok(tables.includes("transfer_rules"));
  // 팩에만 있고 drift 선언에는 없는 테이블은 판정 대상이 아니다(DP-04 반례).
  assert.ok(!tables.includes("transit_feed_info"));
});

test("drift 선언 파서는 앵커를 잃으면 조용히 넘어가지 않는다", () => {
  assert.throws(
    () => parseDriftDeclaredTables("class Foo {}\n"),
    /allSchemaEntities 선언을 찾지 못했다/,
  );
});

test("팩 스키마 원본 인덱스와 대상 테이블을 읽는다", async () => {
  const indexes = parsePackSchemaIndexes(await read(PACK_SCHEMA_PATH));

  assert.equal(indexes.size, 18);
  assert.equal(indexes.get("idx_route_map_line_tracks_region_line"), "route_map_line_tracks");
  // 줄바꿈으로 나뉜 CREATE INDEX도 읽어야 한다.
  assert.equal(indexes.get("idx_facility_status_snapshots_facility"), "facility_status_snapshots");
});

test("앱 스키마 버전과 구제 대상 테이블 선언을 읽는다", async () => {
  const source = await read(CATALOG_DATABASE_PATH);

  assert.equal(parseAppSchemaVersion(source), 18);
  const rescuable = parseRescuableTableNames(source);
  assert.equal(rescuable.size, 11);
  assert.ok(rescuable.has("facility_status_snapshots"));
  assert.ok(rescuable.has("route_map_positions"));
  // 빈 테이블 생성이 시간표를 전부 지우는 반례는 구제 목록에 없어야 한다.
  assert.ok(!rescuable.has("transit_feed_info"));
  assert.ok(
    parseDartStringSetConstant(source, "absenceTolerantCatalogTableNames").has("transit_feed_info"),
  );
});

test("앱이 카탈로그로 여는 팩 id를 opener에서 읽는다", async () => {
  assert.equal(parseCatalogPackId(await read(CATALOG_OPENER_PATH)), "capital");
});

test("카탈로그 팩 id가 모호하면 멈춘다", () => {
  assert.throws(
    () => parseCatalogPackId(
      "p.join(datapackDirectory.path, 'capital.sqlite');"
      + "p.join(datapackDirectory.path, 'core.sqlite');",
    ),
    /하나로 특정하지 못했다/,
  );
});

test("현행 번들 팩은 schema 결측 없이 게이트를 통과한다", async () => {
  const report = await checkPackAppSchemaParity();

  assert.equal(report.ok, true);
  assert.deepEqual(report.documentErrors, []);
  assert.equal(report.results.length, 1);
  const [capital] = report.results;
  assert.equal(capital.packId, "capital");
  assert.equal(capital.packUserVersion, capital.appSchemaVersion);
  assert.equal(capital.missingTables.length, 0);
  assert.equal(capital.missingIndexes.length, 0);
  assert.deepEqual(capital.unallowedMissingTables, []);
  assert.deepEqual(capital.unallowedMissingIndexes, []);
  assert.deepEqual(report.skippedPackIds, ["core"]);
});

test("결측 pack은 빈 allowlist에서 테이블·인덱스를 이름으로 보고하고 실패한다", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "easysubway-parity-empty-"));
  try {
    const allowlistPath = path.join(directory, "allowlist.json");
    await writeFile(allowlistPath, JSON.stringify({
      schemaVersion: 1,
      artifactKind: "pack-app-schema-parity-allowlist",
      packs: [],
    }));
    const packPath = await incompletePackFixture(directory);
    const report = await checkPackAppSchemaParity({ allowlistPath, packPath });

    assert.equal(report.ok, false);
    const [capital] = report.results;
    assert.deepEqual(capital.unallowedMissingTables, capital.missingTables);
    assert.deepEqual(capital.unallowedMissingIndexes, capital.missingIndexes);
    assert.deepEqual(capital.unallowedMissingTables, ["station_facility_evidence"]);
    assert.deepEqual(capital.unallowedMissingIndexes, ["idx_station_facility_evidence_station"]);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("CLI는 위반 시 결측 이름을 출력하고 비영점 종료한다", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "easysubway-parity-cli-"));
  try {
    const allowlistPath = path.join(directory, "allowlist.json");
    await writeFile(allowlistPath, JSON.stringify({
      schemaVersion: 1,
      artifactKind: "pack-app-schema-parity-allowlist",
      packs: [],
    }));
    const packPath = await incompletePackFixture(directory);
    await assert.rejects(
      execFileAsync(
        process.execPath,
        [
          "tools/ci/check-pack-app-schema-parity.mjs",
          "--allowlist", allowlistPath,
          "--pack", packPath,
        ],
        { cwd: REPOSITORY_ROOT },
      ),
      (error) => {
        assert.equal(error.code, 1);
        assert.match(error.stdout, /- station_facility_evidence/);
        assert.match(error.stdout, /- idx_station_facility_evidence_station/);
        assert.match(error.stderr, /게이트 실패/);
        return true;
      },
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("CLI는 tracked allowlist로 영점 종료한다", async () => {
  const { stdout } = await execFileAsync(
    process.execPath,
    ["tools/ci/check-pack-app-schema-parity.mjs"],
    { cwd: REPOSITORY_ROOT },
  );

  assert.match(stdout, /게이트 통과/);
  assert.match(stdout, new RegExp(ALLOWLIST_PATH.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
});

const baseInput = Object.freeze({
  packId: "capital",
  assetPath: "apps/mobile/assets/datapacks/capital.sqlite.gz",
  packTables: ["catalog_metadata", "stations", "route_map_line_tracks"],
  packIndexes: ["idx_stations_normalized_name"],
  packUserVersion: 18,
  appSchemaVersion: 18,
  driftTables: ["catalog_metadata", "stations", "fare_zones"],
  schemaIndexes: new Map([
    ["idx_stations_normalized_name", "stations"],
    ["idx_route_map_line_tracks_region_line", "route_map_line_tracks"],
    ["idx_fare_zones_region", "fare_zones"],
  ]),
  rescuableTables: new Set(["fare_zones"]),
  allowlistEntry: undefined,
});

function allowlistEntryOf(missingTables, missingIndexes) {
  return {
    packId: "capital",
    assetPath: "apps/mobile/assets/datapacks/capital.sqlite.gz",
    missingTables: new Map(missingTables.map((entry) => [entry.name, entry])),
    missingIndexes: new Map(missingIndexes.map((entry) => [entry.name, entry])),
  };
}

test("allowlist에 없는 결측은 실패한다", () => {
  const result = evaluatePackAppSchemaParity(baseInput);

  assert.equal(result.ok, false);
  assert.deepEqual(result.unallowedMissingTables, ["fare_zones"]);
  assert.deepEqual(result.unallowedMissingIndexes, [
    "idx_fare_zones_region",
    "idx_route_map_line_tracks_region_line",
  ]);
});

test("더 이상 결측이 아닌 allowlist 항목은 실패시킨다", () => {
  const result = evaluatePackAppSchemaParity({
    ...baseInput,
    allowlistEntry: allowlistEntryOf(
      [
        { name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" },
        { name: "stations", disposition: "APP_RESCUE", reason: "이미 팩에 있다" },
      ],
      [
        { name: "idx_fare_zones_region", disposition: "MISSING_TABLE_DEPENDENT", reason: "결측 테이블" },
        { name: "idx_route_map_line_tracks_region_line", disposition: "PACK_REBUILD_PENDING", reason: "단독 누락" },
      ],
    ),
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.staleAllowedTables, ["stations"]);
  assert.deepEqual(result.staleAllowedIndexes, []);
});

test("APP_RESCUE 등재는 앱 구제 목록에 실제로 있어야 한다", () => {
  const result = evaluatePackAppSchemaParity({
    ...baseInput,
    rescuableTables: new Set(),
    allowlistEntry: allowlistEntryOf(
      [{ name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" }],
      [
        { name: "idx_fare_zones_region", disposition: "MISSING_TABLE_DEPENDENT", reason: "결측 테이블" },
        { name: "idx_route_map_line_tracks_region_line", disposition: "PACK_REBUILD_PENDING", reason: "단독 누락" },
      ],
    ),
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.allowlistErrors, [
    "'fare_zones'은 APP_RESCUE로 등재됐지만 앱의 rescuableCatalogTableNames에 없다",
  ]);
});

test("MISSING_TABLE_DEPENDENT는 대상 테이블이 팩에 있으면 실패한다", () => {
  const result = evaluatePackAppSchemaParity({
    ...baseInput,
    allowlistEntry: allowlistEntryOf(
      [{ name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" }],
      [
        { name: "idx_fare_zones_region", disposition: "MISSING_TABLE_DEPENDENT", reason: "결측 테이블" },
        {
          name: "idx_route_map_line_tracks_region_line",
          disposition: "MISSING_TABLE_DEPENDENT",
          reason: "잘못된 분류",
        },
      ],
    ),
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.allowlistErrors, [
    "'idx_route_map_line_tracks_region_line'은 MISSING_TABLE_DEPENDENT로 등재됐지만"
    + " 대상 테이블 'route_map_line_tracks'은 팩에 있다",
  ]);
});

test("정확한 allowlist는 통과한다", () => {
  const result = evaluatePackAppSchemaParity({
    ...baseInput,
    allowlistEntry: allowlistEntryOf(
      [{ name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" }],
      [
        { name: "idx_fare_zones_region", disposition: "MISSING_TABLE_DEPENDENT", reason: "결측 테이블" },
        { name: "idx_route_map_line_tracks_region_line", disposition: "PACK_REBUILD_PENDING", reason: "단독 누락" },
      ],
    ),
  });

  assert.equal(result.ok, true);
  assert.deepEqual(result.failures, []);
});

test("앱보다 높은 팩 user_version은 실패한다", () => {
  const result = evaluatePackAppSchemaParity({
    ...baseInput,
    packUserVersion: 19,
    allowlistEntry: allowlistEntryOf(
      [{ name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" }],
      [
        { name: "idx_fare_zones_region", disposition: "MISSING_TABLE_DEPENDENT", reason: "결측 테이블" },
        { name: "idx_route_map_line_tracks_region_line", disposition: "PACK_REBUILD_PENDING", reason: "단독 누락" },
      ],
    ),
  });

  assert.equal(result.ok, false);
  assert.match(result.failures[0], /팩 user_version\(19\)이 앱 catalogDatabaseSchemaVersion\(18\)보다 높다/);
});

test("사유가 없는 allowlist 항목은 거부한다", () => {
  const { errors } = normalizeAllowlist({
    schemaVersion: 1,
    packs: [{
      packId: "capital",
      assetPath: "apps/mobile/assets/datapacks/capital.sqlite.gz",
      missingTables: [{ name: "fare_zones", disposition: "APP_RESCUE" }],
    }],
  });

  assert.deepEqual(errors, [`${ALLOWLIST_PATH}: $.packs.0.missingTables.0.reason: 사유는 필수다`]);
});

test("알 수 없는 disposition은 거부한다", () => {
  const { errors } = normalizeAllowlist({
    schemaVersion: 1,
    packs: [{
      packId: "capital",
      assetPath: "apps/mobile/assets/datapacks/capital.sqlite.gz",
      missingIndexes: [{ name: "idx_x", disposition: "IGNORE", reason: "무시하고 싶다" }],
    }],
  });

  assert.equal(errors.length, 1);
  assert.match(errors[0], /disposition/);
});

test("allowlist의 assetPath가 실제 자산 경로와 다르면 실패한다", () => {
  const result = evaluatePackAppSchemaParity({
    ...baseInput,
    allowlistEntry: {
      ...allowlistEntryOf(
        [{ name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" }],
        [
          { name: "idx_fare_zones_region", disposition: "MISSING_TABLE_DEPENDENT", reason: "결측 테이블" },
          { name: "idx_route_map_line_tracks_region_line", disposition: "PACK_REBUILD_PENDING", reason: "단독 누락" },
        ],
      ),
      assetPath: "apps/mobile/assets/datapacks/other.sqlite.gz",
    },
  });

  assert.equal(result.ok, false);
  assert.ok(result.allowlistErrors.some((error) => /assetPath가 실제 자산 경로와 다르다/.test(error)));
});

test("PACK_REBUILD_PENDING인데 대상 테이블이 팩에 없으면 실패한다", () => {
  const result = evaluatePackAppSchemaParity({
    ...baseInput,
    allowlistEntry: allowlistEntryOf(
      [{ name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" }],
      [
        { name: "idx_fare_zones_region", disposition: "PACK_REBUILD_PENDING", reason: "잘못된 분류" },
        { name: "idx_route_map_line_tracks_region_line", disposition: "PACK_REBUILD_PENDING", reason: "단독 누락" },
      ],
    ),
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.allowlistErrors, [
    "'idx_fare_zones_region'은 PACK_REBUILD_PENDING로 등재됐지만 대상 테이블 'fare_zones'이 팩에 없다",
  ]);
});

test("팩 스키마 원본이 선언하지 않은 인덱스 등재는 실패한다", () => {
  const result = evaluatePackAppSchemaParity({
    ...baseInput,
    allowlistEntry: allowlistEntryOf(
      [{ name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" }],
      [
        { name: "idx_fare_zones_region", disposition: "MISSING_TABLE_DEPENDENT", reason: "결측 테이블" },
        { name: "idx_route_map_line_tracks_region_line", disposition: "PACK_REBUILD_PENDING", reason: "단독 누락" },
        { name: "idx_unknown_index", disposition: "PACK_REBUILD_PENDING", reason: "원본에 없는 인덱스" },
      ],
    ),
  });

  assert.equal(result.ok, false);
  assert.ok(result.allowlistErrors.includes("'idx_unknown_index'은 팩 스키마 원본이 선언하지 않은 인덱스다"));
});

test("앱 구제 목록에 필수 테이블 밖의 이름이 있으면 실패한다", () => {
  const result = evaluatePackAppSchemaParity({
    ...baseInput,
    rescuableTables: new Set(["fare_zones", "fare_zone_typo"]),
    allowlistEntry: allowlistEntryOf(
      [{ name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" }],
      [
        { name: "idx_fare_zones_region", disposition: "MISSING_TABLE_DEPENDENT", reason: "결측 테이블" },
        { name: "idx_route_map_line_tracks_region_line", disposition: "PACK_REBUILD_PENDING", reason: "단독 누락" },
      ],
    ),
  });

  assert.equal(result.ok, false);
  assert.deepEqual(result.allowlistErrors, [
    "앱의 rescuableCatalogTableNames 'fare_zone_typo'이 필수 테이블 집합(drift 선언 ∪ raw SQL)에 없다",
  ]);
});

test("raw SQL 필수 테이블 결측도 판정 대상이다", () => {
  const withRawSql = evaluatePackAppSchemaParity({
    ...baseInput,
    rawSqlTables: ["route_map_positions"],
    allowlistEntry: allowlistEntryOf(
      [{ name: "fare_zones", disposition: "APP_RESCUE", reason: "구제" }],
      [
        { name: "idx_fare_zones_region", disposition: "MISSING_TABLE_DEPENDENT", reason: "결측 테이블" },
        { name: "idx_route_map_line_tracks_region_line", disposition: "PACK_REBUILD_PENDING", reason: "단독 누락" },
      ],
    ),
  });

  assert.equal(withRawSql.requiredTableCount, 4);
  assert.deepEqual(withRawSql.unallowedMissingTables, ["route_map_positions"]);
  assert.equal(withRawSql.ok, false);
});

test("카탈로그 팩이 아닌 allowlist 항목은 실패한다", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "easysubway-parity-unknown-"));
  try {
    const allowlistPath = path.join(directory, "allowlist.json");
    const tracked = JSON.parse(await read(ALLOWLIST_PATH));
    tracked.packs.push({
      packId: "core",
      assetPath: "apps/mobile/assets/datapacks/core.sqlite.gz",
      missingTables: [],
      missingIndexes: [],
    });
    await writeFile(allowlistPath, JSON.stringify(tracked));
    const report = await checkPackAppSchemaParity({ allowlistPath });

    assert.equal(report.ok, false);
    assert.ok(report.documentErrors.some((error) => /카탈로그 팩이 아닌 'core' 항목/.test(error)));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("중복 packId와 중복 항목 이름은 거부한다", () => {
  const { errors } = normalizeAllowlist({
    schemaVersion: 1,
    packs: [
      {
        packId: "capital",
        assetPath: "apps/mobile/assets/datapacks/capital.sqlite.gz",
        missingTables: [
          { name: "fare_zones", disposition: "APP_RESCUE", reason: "구제한다" },
          { name: "fare_zones", disposition: "APP_RESCUE", reason: "중복 등재" },
        ],
      },
      { packId: "capital", assetPath: "apps/mobile/assets/datapacks/capital.sqlite.gz" },
    ],
  });

  assert.deepEqual(errors, [
    `${ALLOWLIST_PATH}: $.packs.0.missingTables.1.name: 'fare_zones' 중복 등재`,
    `${ALLOWLIST_PATH}: $.packs.1.packId: 'capital' 중복 등재`,
  ]);
});

test("raw SQL 스캔은 주석을 빼고 테이블 토큰만 모은다", () => {
  const tokens = scanRawSqlTableTokens([
    {
      path: "a.dart",
      text: "// FROM commented_out\n/* JOIN block_commented */\n"
        + "final q = 'SELECT 1 FROM route_map_positions JOIN station_lines';",
    },
  ]);

  assert.deepEqual([...tokens.keys()].sort(), ["route_map_positions", "station_lines"]);
  assert.deepEqual([...tokens.get("route_map_positions")], ["a.dart"]);
});

test("계약에 없는 raw SQL 테이블·낡은 항목·낡은 무시 토큰을 모두 실패시킨다", () => {
  const { errors } = evaluateRawSqlTableContract({
    tokens: new Map([
      ["stations", new Set(["a.dart"])],
      ["route_map_positions", new Set(["a.dart"])],
      ["brand_new_table", new Set(["b.dart"])],
      ["in", new Set(["c.dart"])],
    ]),
    driftTables: ["stations"],
    userDriftTables: [],
    contractTables: ["route_map_positions", "gone_table"],
    ignoredTokens: ["in", "never_seen"],
  });

  assert.equal(errors.length, 3);
  assert.match(errors[0], /'brand_new_table'이 계약에 없다/);
  assert.match(errors[1], /'gone_table'을 raw SQL로 읽는 코드가 더 이상 없다/);
  assert.match(errors[2], /ignoredTokens 'never_seen'이 더 이상 오탐으로 나타나지 않는다/);
});

test("현행 저장소의 raw SQL 계약은 앱 소스·앱 상수와 일치한다", async () => {
  const report = await checkPackAppSchemaParity();
  const contract = JSON.parse(await read(RAW_SQL_TABLES_PATH));
  const declared = parseDartStringSetConstant(
    await read(CATALOG_DATABASE_PATH),
    "rawSqlCatalogTableNames",
  );

  assert.deepEqual(report.documentErrors, []);
  assert.deepEqual(
    contract.tables.map((entry) => entry.name).sort(),
    [...declared].sort(),
  );
  assert.deepEqual([...declared].sort(), [
    "route_map_line_tracks",
    "route_map_positions",
    "transit_feed_info",
  ]);
  assert.equal(report.results[0].requiredTableCount, 36);
});

test("Dart 문자열 집합 상수 파서는 앵커를 잃으면 멈춘다", () => {
  assert.throws(
    () => parseDartStringSetConstant("const other = <String>{};\n", "rawSqlCatalogTableNames"),
    /rawSqlCatalogTableNames 선언을 찾지 못했다/,
  );
});

test("drift 파서 실패 메시지는 복구 방법을 알려 준다", () => {
  assert.throws(
    () => parseDriftDeclaredTables("class Foo {}\n"),
    /build_runner build/,
  );
});
