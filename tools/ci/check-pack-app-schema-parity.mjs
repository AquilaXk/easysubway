#!/usr/bin/env node
// 팩↔앱 카탈로그 스키마 테이블·인덱스 집합 정합 게이트(#2527).
//
// 왜 필요한가:
//   번들 데이터팩의 `PRAGMA user_version`과 앱의 `catalogDatabaseSchemaVersion`이 같으면
//   drift는 onCreate도 onUpgrade도 실행하지 않는다. 즉 팩에 없는 테이블은 앱이 만들 기회를
//   영원히 얻지 못하고, 조회는 `_tableExists` 가드에 막혀 예외 없이 조용히 비활성화된다.
//   이 게이트는 그 결측을 CI에서 이름 단위로 드러낸다.
//
// 판정 두 가지:
//   ① 팩이 담은 테이블 집합 ⊇ 앱 drift 선언 테이블 집합
//   ② 팩이 담은 명시 인덱스 집합 ⊇ 팩 스키마 원본(catalog-schema.sql) 선언 인덱스 집합
//
// 왜 tools/ci에 두는가:
//   `contracts/boundaries.json`이 `tools/datapack` → `apps/mobile/lib` 참조를 금지한다
//   ("datapack 도구는 앱 구현을 모른다"). 이 게이트는 앱의 drift 선언을 읽어야 하므로
//   datapack 도구가 될 수 없다. 앱 자산을 읽는 기존 선례(tools/ci/audit-mobile-datapack-assets.mjs)와
//   같은 영역에 둔다.
//
// 왜 drift 선언을 생성 산출물에서 읽는가:
//   하드코딩 목록은 앱이 테이블을 추가해도 조용히 낡는다. 대안은 앱이 빈 DB를 만들어
//   sqlite_master를 덤프하는 방식인데, 그러려면 이 레인에 Flutter/Dart 툴체인이 필요해
//   Node 전용 레인의 실행 비용과 의존성이 커진다. `catalog_database.g.dart`는 저장소에
//   커밋된 생성 산출물이고 drift가 실제로 쓰는 선언 그 자체이므로, 이를 구조적으로 파싱하면
//   추가 툴체인 없이 같은 진실을 얻는다. 파싱이 앵커를 잃으면 조용히 넘어가지 않고 예외로
//   멈춘다(fail closed).
//
// 예외 처리:
//   의도한 결측은 `contracts/datapack/pack-app-schema-parity-allowlist.json`에만 둔다.
//   항목마다 사유가 필수이고, 등재되지 않은 결측은 실패한다. 쓰이지 않는 항목(stale)도
//   실패시켜 팩이 고쳐지면 allowlist가 반드시 줄어들게 한다.
//
// 사용:
//   node tools/ci/check-pack-app-schema-parity.mjs
//   node tools/ci/check-pack-app-schema-parity.mjs --allowlist <경로>
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { gunzipSync } from "node:zlib";

import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";

export const ALLOWLIST_PATH = "contracts/datapack/pack-app-schema-parity-allowlist.json";
export const DRIFT_GENERATED_PATH = "apps/mobile/lib/core/database/catalog/catalog_database.g.dart";
export const CATALOG_DATABASE_PATH = "apps/mobile/lib/core/database/catalog/catalog_database.dart";
export const CATALOG_OPENER_PATH = "apps/mobile/lib/core/database/catalog/catalog_database_opener.dart";
export const PACK_SCHEMA_PATH = "tools/datapack/schema/catalog-schema.sql";
export const DATAPACK_INDEX_PATH = "apps/mobile/assets/datapacks/index.json";
export const DATAPACK_ASSET_ROOT = "apps/mobile";

export const REPOSITORY_ROOT = path.resolve(import.meta.dirname, "../..");

export const TABLE_DISPOSITIONS = Object.freeze(["APP_RESCUE"]);
export const INDEX_DISPOSITIONS = Object.freeze(["MISSING_TABLE_DEPENDENT", "PACK_REBUILD_PENDING"]);

/** drift `@DriftDatabase(tables: [...])`가 선언한 SQL 테이블 이름을 생성 산출물에서 읽는다. */
export function parseDriftDeclaredTables(generatedSource) {
  const entities = /^  List<DatabaseSchemaEntity> get allSchemaEntities => \[([\s\S]*?)^  \];$/m
    .exec(generatedSource);
  if (entities == null) {
    throw new Error(`${DRIFT_GENERATED_PATH}: allSchemaEntities 선언을 찾지 못했다`);
  }
  const getters = entities[1]
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0);
  if (getters.length === 0) {
    throw new Error(`${DRIFT_GENERATED_PATH}: allSchemaEntities가 비어 있다`);
  }

  const getterToClass = new Map();
  const fieldPattern = /late final \$([A-Za-z0-9_]+)\s+([A-Za-z0-9_]+)\s*=\s*\$([A-Za-z0-9_]+)\(\s*this,?\s*\);/g;
  for (const [, declaredClass, getter, constructedClass] of generatedSource.matchAll(fieldPattern)) {
    if (declaredClass !== constructedClass) continue;
    getterToClass.set(getter, declaredClass);
  }

  const classToTable = parseGeneratedTableNames(generatedSource);
  const tables = [];
  for (const getter of getters) {
    const className = getterToClass.get(getter);
    if (className === undefined) {
      throw new Error(`${DRIFT_GENERATED_PATH}: '${getter}' 테이블 필드 선언을 찾지 못했다`);
    }
    const tableName = classToTable.get(className);
    if (tableName === undefined) {
      throw new Error(`${DRIFT_GENERATED_PATH}: '${className}'의 실제 테이블 이름을 찾지 못했다`);
    }
    tables.push(tableName);
  }
  return [...new Set(tables)].sort(codepointCompare);
}

function parseGeneratedTableNames(generatedSource) {
  const classToTable = new Map();
  for (const segment of generatedSource.split(/^class /m).slice(1)) {
    const header = /^\$([A-Za-z0-9_]+)\b/.exec(segment);
    if (header == null) continue;
    const name = /^  static const String \$name = '([a-z0-9_]+)';$/m.exec(segment);
    if (name == null) continue;
    classToTable.set(header[1], name[1]);
  }
  return classToTable;
}

/** 팩 스키마 원본이 선언한 인덱스와 그 대상 테이블을 읽는다. */
export function parsePackSchemaIndexes(schemaSql) {
  const indexes = new Map();
  const pattern = /CREATE\s+INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-z0-9_]+)\s+ON\s+([a-z0-9_]+)\s*\(/gi;
  for (const [, indexName, tableName] of schemaSql.matchAll(pattern)) {
    indexes.set(indexName, tableName);
  }
  if (indexes.size === 0) {
    throw new Error(`${PACK_SCHEMA_PATH}: CREATE INDEX 선언을 찾지 못했다`);
  }
  return indexes;
}

/** 앱이 선언한 카탈로그 스키마 버전. */
export function parseAppSchemaVersion(catalogDatabaseSource) {
  const match = /^const catalogDatabaseSchemaVersion = (\d+);$/m.exec(catalogDatabaseSource);
  if (match == null) {
    throw new Error(`${CATALOG_DATABASE_PATH}: catalogDatabaseSchemaVersion 선언을 찾지 못했다`);
  }
  return Number(match[1]);
}

/** 앱이 "빈 테이블로 구제한다"고 선언한 테이블 목록. allowlist의 APP_RESCUE와 대조한다. */
export function parseRescuableTableNames(catalogDatabaseSource) {
  const match = /^const rescuableCatalogTableNames = <String>\{([\s\S]*?)^\};$/m
    .exec(catalogDatabaseSource);
  if (match == null) {
    throw new Error(`${CATALOG_DATABASE_PATH}: rescuableCatalogTableNames 선언을 찾지 못했다`);
  }
  const names = [...match[1].matchAll(/'([a-z0-9_]+)'/g)].map(([, name]) => name);
  if (names.length === 0) {
    throw new Error(`${CATALOG_DATABASE_PATH}: rescuableCatalogTableNames가 비어 있다`);
  }
  return new Set(names);
}

/** 앱이 카탈로그 DB로 여는 번들 팩 id. 여러 개거나 없으면 판정 대상이 모호하므로 멈춘다. */
export function parseCatalogPackId(openerSource) {
  const ids = new Set(
    [...openerSource.matchAll(/datapackDirectory\.path\s*,\s*'([a-z0-9_]+)\.sqlite'/g)]
      .map(([, id]) => id),
  );
  if (ids.size !== 1) {
    throw new Error(`${CATALOG_OPENER_PATH}: 카탈로그로 여는 팩 id를 하나로 특정하지 못했다 (${ids.size}건)`);
  }
  return [...ids][0];
}

/** sqlite 파일에서 테이블·명시 인덱스·user_version을 읽는다. */
export function readPackSchema(sqlitePath) {
  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  try {
    const tables = database
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
      .all()
      .map((row) => row.name)
      .sort(codepointCompare);
    const indexes = database
      .prepare("SELECT name FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL")
      .all()
      .map((row) => row.name)
      .sort(codepointCompare);
    const [userVersion] = database.prepare("PRAGMA user_version").all().map((row) => row.user_version);
    return { tables, indexes, userVersion };
  } finally {
    database.close();
  }
}

/** allowlist 문서의 형식을 검사하고 팩별 항목으로 정리한다. 사유는 필수다. */
export function normalizeAllowlist(allowlist) {
  const errors = [];
  if (allowlist == null || typeof allowlist !== "object" || Array.isArray(allowlist)) {
    return { entriesByPackId: new Map(), errors: [`${ALLOWLIST_PATH}: 객체가 아니다`] };
  }
  if (allowlist.schemaVersion !== 1) {
    errors.push(`${ALLOWLIST_PATH}: schemaVersion은 1이어야 한다`);
  }
  const entriesByPackId = new Map();
  const packs = Array.isArray(allowlist.packs) ? allowlist.packs : [];
  for (const [index, pack] of packs.entries()) {
    const at = `${ALLOWLIST_PATH}: $.packs.${index}`;
    if (pack == null || typeof pack !== "object" || Array.isArray(pack)) {
      errors.push(`${at}: 객체가 아니다`);
      continue;
    }
    if (typeof pack.packId !== "string" || pack.packId.trim() === "") {
      errors.push(`${at}.packId: 필수 문자열`);
      continue;
    }
    if (entriesByPackId.has(pack.packId)) {
      errors.push(`${at}.packId: '${pack.packId}' 중복 등재`);
      continue;
    }
    entriesByPackId.set(pack.packId, {
      packId: pack.packId,
      assetPath: typeof pack.assetPath === "string" ? pack.assetPath : "",
      missingTables: normalizeEntries(pack.missingTables, TABLE_DISPOSITIONS, `${at}.missingTables`, errors),
      missingIndexes: normalizeEntries(pack.missingIndexes, INDEX_DISPOSITIONS, `${at}.missingIndexes`, errors),
    });
  }
  return { entriesByPackId, errors };
}

function normalizeEntries(rawEntries, dispositions, at, errors) {
  const entries = new Map();
  if (rawEntries === undefined) return entries;
  if (!Array.isArray(rawEntries)) {
    errors.push(`${at}: 배열이어야 한다`);
    return entries;
  }
  for (const [index, entry] of rawEntries.entries()) {
    const entryAt = `${at}.${index}`;
    if (entry == null || typeof entry !== "object" || Array.isArray(entry)) {
      errors.push(`${entryAt}: 객체가 아니다`);
      continue;
    }
    if (typeof entry.name !== "string" || entry.name.trim() === "") {
      errors.push(`${entryAt}.name: 필수 문자열`);
      continue;
    }
    if (typeof entry.reason !== "string" || entry.reason.trim() === "") {
      errors.push(`${entryAt}.reason: 사유는 필수다`);
      continue;
    }
    if (!dispositions.includes(entry.disposition)) {
      errors.push(`${entryAt}.disposition: ${dispositions.join(" | ")} 중 하나여야 한다`);
      continue;
    }
    if (entries.has(entry.name)) {
      errors.push(`${entryAt}.name: '${entry.name}' 중복 등재`);
      continue;
    }
    entries.set(entry.name, entry);
  }
  return entries;
}

/**
 * 팩 하나의 정합을 판정한다. 순수 함수이므로 합성 입력으로 회귀를 고정할 수 있다.
 */
export function evaluatePackAppSchemaParity({
  packId,
  assetPath,
  packTables,
  packIndexes,
  packUserVersion,
  appSchemaVersion,
  driftTables,
  schemaIndexes,
  rescuableTables,
  allowlistEntry,
}) {
  const packTableSet = new Set(packTables);
  const packIndexSet = new Set(packIndexes);
  const missingTables = driftTables.filter((name) => !packTableSet.has(name)).sort(codepointCompare);
  const missingIndexes = [...schemaIndexes.keys()]
    .filter((name) => !packIndexSet.has(name))
    .sort(codepointCompare);

  const allowedTables = allowlistEntry?.missingTables ?? new Map();
  const allowedIndexes = allowlistEntry?.missingIndexes ?? new Map();
  const allowlistErrors = [];

  if (allowlistEntry != null && allowlistEntry.assetPath !== assetPath) {
    allowlistErrors.push(
      `allowlist의 assetPath가 실제 자산 경로와 다르다: '${allowlistEntry.assetPath}' != '${assetPath}'`,
    );
  }

  for (const [name, entry] of allowedTables) {
    if (entry.disposition === "APP_RESCUE" && !rescuableTables.has(name)) {
      allowlistErrors.push(
        `'${name}'은 APP_RESCUE로 등재됐지만 앱의 rescuableCatalogTableNames에 없다`,
      );
    }
  }
  for (const [name, entry] of allowedIndexes) {
    const targetTable = schemaIndexes.get(name);
    if (targetTable === undefined) {
      allowlistErrors.push(`'${name}'은 팩 스키마 원본이 선언하지 않은 인덱스다`);
      continue;
    }
    if (entry.disposition === "MISSING_TABLE_DEPENDENT" && packTableSet.has(targetTable)) {
      allowlistErrors.push(
        `'${name}'은 MISSING_TABLE_DEPENDENT로 등재됐지만 대상 테이블 '${targetTable}'은 팩에 있다`,
      );
    }
    if (entry.disposition === "PACK_REBUILD_PENDING" && !packTableSet.has(targetTable)) {
      allowlistErrors.push(
        `'${name}'은 PACK_REBUILD_PENDING로 등재됐지만 대상 테이블 '${targetTable}'이 팩에 없다`,
      );
    }
  }

  const unallowedMissingTables = missingTables.filter((name) => !allowedTables.has(name));
  const unallowedMissingIndexes = missingIndexes.filter((name) => !allowedIndexes.has(name));
  const missingTableSet = new Set(missingTables);
  const missingIndexSet = new Set(missingIndexes);
  const staleAllowedTables = [...allowedTables.keys()]
    .filter((name) => !missingTableSet.has(name))
    .sort(codepointCompare);
  const staleAllowedIndexes = [...allowedIndexes.keys()]
    .filter((name) => !missingIndexSet.has(name))
    .sort(codepointCompare);

  const failures = [];
  if (packUserVersion > appSchemaVersion) {
    failures.push(
      `팩 user_version(${packUserVersion})이 앱 catalogDatabaseSchemaVersion(${appSchemaVersion})보다 높다`,
    );
  }
  if (unallowedMissingTables.length > 0) {
    failures.push(`allowlist에 없는 결측 테이블 ${unallowedMissingTables.length}건`);
  }
  if (unallowedMissingIndexes.length > 0) {
    failures.push(`allowlist에 없는 결측 인덱스 ${unallowedMissingIndexes.length}건`);
  }
  if (staleAllowedTables.length > 0) {
    failures.push(`더 이상 결측이 아닌 allowlist 테이블 항목 ${staleAllowedTables.length}건`);
  }
  if (staleAllowedIndexes.length > 0) {
    failures.push(`더 이상 결측이 아닌 allowlist 인덱스 항목 ${staleAllowedIndexes.length}건`);
  }
  failures.push(...allowlistErrors);

  return {
    packId,
    assetPath,
    packUserVersion,
    appSchemaVersion,
    // 팩 버전이 앱보다 낮으면 drift onUpgrade가 일부 결측을 메울 수 있다. 어느 단계가 도는지는
    // 정적으로 확정할 수 없으므로 판정은 완화하지 않고 사실만 기록한다.
    migrationMayRun: packUserVersion < appSchemaVersion,
    packTableCount: packTables.length,
    packIndexCount: packIndexes.length,
    driftTableCount: driftTables.length,
    schemaIndexCount: schemaIndexes.size,
    missingTables,
    missingIndexes,
    unallowedMissingTables,
    unallowedMissingIndexes,
    staleAllowedTables,
    staleAllowedIndexes,
    allowlistErrors,
    failures,
    ok: failures.length === 0,
  };
}

export function formatReport({ results, skippedPackIds, allowlistPath }) {
  const lines = ["데이터팩↔앱 카탈로그 스키마 정합 게이트 (#2527)", `  allowlist: ${allowlistPath}`];
  for (const result of results) {
    lines.push(`  카탈로그 팩: ${result.packId} (${result.assetPath})`);
    lines.push(
      `    PRAGMA user_version = ${result.packUserVersion} / 앱 catalogDatabaseSchemaVersion = ${result.appSchemaVersion}`
      + (result.migrationMayRun ? " (팩이 낮다 — 일부 마이그레이션이 돌 수 있다)" : " (동일 — 마이그레이션이 결측을 메우지 않는다)"),
    );
    lines.push(
      `    팩 테이블 ${result.packTableCount}개 / 앱 drift 선언 테이블 ${result.driftTableCount}개`,
    );
    lines.push(
      `    팩 명시 인덱스 ${result.packIndexCount}개 / 팩 스키마 원본 선언 인덱스 ${result.schemaIndexCount}개`,
    );
    lines.push(...nameBlock("결측 테이블", result.missingTables));
    lines.push(...nameBlock("결측 인덱스", result.missingIndexes));
    lines.push(...nameBlock("allowlist에 없는 결측 테이블", result.unallowedMissingTables));
    lines.push(...nameBlock("allowlist에 없는 결측 인덱스", result.unallowedMissingIndexes));
    lines.push(...nameBlock("더 이상 결측이 아닌 allowlist 테이블 항목", result.staleAllowedTables));
    lines.push(...nameBlock("더 이상 결측이 아닌 allowlist 인덱스 항목", result.staleAllowedIndexes));
    for (const error of result.allowlistErrors) {
      lines.push(`    allowlist 오류: ${error}`);
    }
  }
  if (skippedPackIds.length > 0) {
    lines.push(`  평가 제외 팩(앱이 카탈로그 DB로 열지 않음): ${skippedPackIds.join(", ")}`);
  }
  return lines.join("\n");
}

function nameBlock(label, names) {
  if (names.length === 0) return [`    ${label} 0개`];
  return [`    ${label} ${names.length}개:`, ...names.map((name) => `      - ${name}`)];
}

export async function checkPackAppSchemaParity({
  root = REPOSITORY_ROOT,
  allowlistPath = ALLOWLIST_PATH,
} = {}) {
  const read = (relative) => readFile(path.resolve(root, relative), "utf8");
  const driftTables = parseDriftDeclaredTables(await read(DRIFT_GENERATED_PATH));
  const catalogDatabaseSource = await read(CATALOG_DATABASE_PATH);
  const appSchemaVersion = parseAppSchemaVersion(catalogDatabaseSource);
  const rescuableTables = parseRescuableTableNames(catalogDatabaseSource);
  const schemaIndexes = parsePackSchemaIndexes(await read(PACK_SCHEMA_PATH));
  const catalogPackId = parseCatalogPackId(await read(CATALOG_OPENER_PATH));
  const index = JSON.parse(await read(DATAPACK_INDEX_PATH));
  const { entriesByPackId, errors: allowlistErrors } = normalizeAllowlist(
    JSON.parse(await readFile(path.resolve(root, allowlistPath), "utf8")),
  );

  const packs = Array.isArray(index.packs) ? index.packs : [];
  const catalogPacks = packs.filter((pack) => pack.id === catalogPackId);
  if (catalogPacks.length !== 1) {
    throw new Error(`${DATAPACK_INDEX_PATH}: 카탈로그 팩 '${catalogPackId}' 항목이 하나가 아니다`);
  }
  const skippedPackIds = packs
    .filter((pack) => pack.id !== catalogPackId)
    .map((pack) => String(pack.id))
    .sort(codepointCompare);

  const workDirectory = await mkdtemp(path.join(tmpdir(), "easysubway-pack-schema-parity-"));
  const results = [];
  try {
    for (const pack of catalogPacks) {
      const assetPath = path.posix.join(DATAPACK_ASSET_ROOT, String(pack.asset));
      const sqlitePath = path.join(workDirectory, `${pack.id}.sqlite`);
      await writeFile(sqlitePath, gunzipSync(await readFile(path.resolve(root, assetPath))));
      const packSchema = readPackSchema(sqlitePath);
      results.push(evaluatePackAppSchemaParity({
        packId: String(pack.id),
        assetPath,
        packTables: packSchema.tables,
        packIndexes: packSchema.indexes,
        packUserVersion: packSchema.userVersion,
        appSchemaVersion,
        driftTables,
        schemaIndexes,
        rescuableTables,
        allowlistEntry: entriesByPackId.get(String(pack.id)),
      }));
    }
  } finally {
    await rm(workDirectory, { recursive: true, force: true });
  }

  const unknownPackIds = [...entriesByPackId.keys()]
    .filter((packId) => !catalogPacks.some((pack) => String(pack.id) === packId))
    .sort(codepointCompare);
  const documentErrors = [
    ...allowlistErrors,
    ...unknownPackIds.map((packId) => `${allowlistPath}: 카탈로그 팩이 아닌 '${packId}' 항목`),
  ];

  return {
    allowlistPath,
    results,
    skippedPackIds,
    documentErrors,
    ok: documentErrors.length === 0 && results.every((result) => result.ok),
  };
}

function parseCliArgs(argv) {
  const args = { allowlistPath: ALLOWLIST_PATH };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--allowlist" && index + 1 < argv.length) {
      args.allowlistPath = argv[index + 1];
      index += 1;
      continue;
    }
    throw new Error(`알 수 없는 인자: ${argv[index]}`);
  }
  return args;
}

if (isMainModule(import.meta.url)) {
  const { allowlistPath } = parseCliArgs(process.argv.slice(2));
  const report = await checkPackAppSchemaParity({ allowlistPath });
  console.log(formatReport(report));
  for (const error of report.documentErrors) {
    console.error(`allowlist 오류: ${error}`);
  }
  if (!report.ok) {
    const failures = [
      ...report.documentErrors,
      ...report.results.flatMap((result) => result.failures),
    ];
    console.error(`게이트 실패: ${failures.join(" / ")}`);
    process.exit(1);
  }
  console.log("게이트 통과");
}
