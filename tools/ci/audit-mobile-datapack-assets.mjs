#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { gunzipSync } from "node:zlib";

const minimumRows = {
  station_exits: 1,
  facilities: 1,
  data_quality_records: 1,
};

const args = parseArgs(process.argv.slice(2));
const indexPath = path.resolve(requiredArg(args, "index"));
const root = path.resolve(requiredArg(args, "root"));
const index = JSON.parse(await readFile(indexPath, "utf8"));
const temporaryDir = await mkdtemp(path.join(tmpdir(), "easysubway-mobile-datapack-audit-"));

try {
  const packs = [];
  for (const pack of index.packs ?? []) {
    const id = requiredString(pack.id, "pack.id");
    assertNoFixtureManifestMetadata(pack, id);
    const compressedPath = path.join(root, requiredString(pack.asset, "pack.asset"));
    const compressedBytes = await readFile(compressedPath);
    const sqliteBytes = gunzipSync(compressedBytes);
    const sqlitePath = path.join(temporaryDir, `${id}.sqlite`);
    await writeFile(sqlitePath, sqliteBytes);
    packs.push(auditPack(sqlitePath, pack, compressedBytes, sqliteBytes));
  }
  const report = {
    artifactKind: "mobile-datapack-asset-audit",
    auditedAt: new Date().toISOString(),
    packs,
  };
  console.log(JSON.stringify(report, null, 2));
} finally {
  await rm(temporaryDir, { recursive: true, force: true });
}

function assertNoFixtureManifestMetadata(pack, packId) {
  if (String(pack.artifactKind ?? "").toLowerCase() === "fixture") {
    throw new Error(`${packId} manifest artifactKind must not be fixture`);
  }
  for (const source of pack.sourceInventory ?? []) {
    const sourceText = [
      source.id,
      source.license,
      source.licenseStatus,
      source.license_status,
    ]
      .filter((value) => typeof value === "string")
      .join(" ")
      .toLowerCase();
    if (sourceText.includes("fixture") || sourceText.includes("review-required")) {
      throw new Error(`${packId} sourceInventory contains review-only source: ${source.id ?? "unknown"}`);
    }
  }
}

function auditPack(sqlitePath, pack, compressedBytes, sqliteBytes) {
  const id = requiredString(pack.id, "pack.id");
  if (pack.sha256 && pack.sha256 !== sha256(compressedBytes)) {
    throw new Error(`${id} compressed checksum mismatch`);
  }
  if (pack.sqliteSha256 && pack.sqliteSha256 !== sha256(sqliteBytes)) {
    throw new Error(`${id} sqlite checksum mismatch`);
  }

  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  try {
    const metadata = Object.fromEntries(
      database.prepare("SELECT key, value FROM catalog_metadata").all().map((row) => [row.key, row.value]),
    );
    if (String(metadata.artifactKind ?? "").toLowerCase() === "fixture") {
      throw new Error(`${id} artifactKind must not be fixture`);
    }

    const rowCounts = {};
    for (const [tableName, minimum] of Object.entries(minimumRows)) {
      rowCounts[tableName] = tableCount(database, tableName);
      if (rowCounts[tableName] < minimum) {
        throw new Error(`${id} ${tableName} row count ${rowCounts[tableName]} is below ${minimum}`);
      }
    }
    assertNoFixtureSourceInventory(database, id);
    return {
      id,
      artifactKind: metadata.artifactKind ?? "unspecified",
      schemaVersion: metadata.schemaVersion ?? "unknown",
      rowCounts,
    };
  } finally {
    database.close();
  }
}

function tableCount(database, tableName) {
  const table = database
    .prepare("SELECT name FROM sqlite_schema WHERE type = 'table' AND name = ?")
    .get(tableName);
  if (!table) {
    return 0;
  }
  return database.prepare(`SELECT COUNT(*) AS count FROM ${tableName}`).get().count;
}

function assertNoFixtureSourceInventory(database, packId) {
  const table = database
    .prepare("SELECT name FROM sqlite_schema WHERE type = 'table' AND name = 'source_inventory'")
    .get();
  if (!table) {
    return;
  }
  const source = database
    .prepare(`
      SELECT id
      FROM source_inventory
      WHERE LOWER(COALESCE(id, '')) LIKE '%fixture%'
         OR LOWER(COALESCE(license, '')) LIKE '%fixture%'
         OR LOWER(COALESCE(license_status, '')) LIKE '%fixture%'
      LIMIT 1
    `)
    .get();
  if (source) {
    throw new Error(`${packId} sourceInventory contains fixture source: ${source.id}`);
  }
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith("--")) {
      throw new Error(`unexpected argument: ${value}`);
    }
    parsed[value.slice(2)] = values[index + 1];
    index += 1;
  }
  return parsed;
}

function requiredArg(args, name) {
  return requiredString(args[name], `--${name}`);
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} is required`);
  }
  return value.trim();
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}
