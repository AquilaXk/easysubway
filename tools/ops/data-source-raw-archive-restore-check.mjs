#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, lstatSync, readFileSync, realpathSync, statSync } from "node:fs";
import path from "node:path";

const archiveDir = path.resolve(process.argv[2] ?? "");
assert.ok(process.argv[2], "usage: data-source-raw-archive-restore-check.mjs <archive-dir>");

const collectionRuns = parseCsv(readFileSync(path.join(archiveDir, "collection-runs.csv"), "utf8"));
const rawArchives = parseCsv(readFileSync(path.join(archiveDir, "raw-archives.csv"), "utf8"));
const manifest = JSON.parse(readFileSync(path.join(archiveDir, "payload-manifest.json"), "utf8"));
assert.equal(manifest.schemaVersion, 1);
assert.ok(manifest.materialized.length > 0, "source archive must contain at least one materialized payload");

const collectionHeader = collectionRuns.shift();
const rawHeader = rawArchives.shift();
const collectionRunIndex = collectionHeader.indexOf("run_id");
const rawIndex = Object.fromEntries(rawHeader.map((name, column) => [name, column]));
assert.ok(collectionRunIndex >= 0, "collection-runs.csv missing run_id");
for (const name of ["archive_id", "run_id", "payload_sha256"]) {
  assert.ok(Number.isInteger(rawIndex[name]), `raw-archives.csv missing ${name}`);
}
const runIds = new Set(collectionRuns.map((row) => row[collectionRunIndex]));
const archives = new Map(rawArchives.map((row) => [row[rawIndex.archive_id], row]));
assert.equal(archives.size, rawArchives.length, "raw archive IDs must be unique");
const materializedArchiveIds = manifest.materialized.map((record) => record.archiveId);
assert.equal(
  new Set(materializedArchiveIds).size,
  materializedArchiveIds.length,
  "materialized archive IDs must be unique",
);
assert.equal(
  manifest.materialized.length,
  rawArchives.length,
  "every raw archive row must have a materialized payload",
);
assert.deepEqual(materializedArchiveIds.toSorted(), [...archives.keys()].toSorted());
const realArchiveDir = realpathSync(archiveDir);

for (const record of manifest.materialized) {
  const row = archives.get(record.archiveId);
  assert.ok(row, `materialized archive missing from raw-archives.csv: ${record.archiveId}`);
  assert.ok(runIds.has(record.runId), `materialized archive run missing from collection-runs.csv: ${record.runId}`);
  assert.equal(row[rawIndex.run_id], record.runId);
  assert.equal(row[rawIndex.payload_sha256], record.sha256);
  assertSafeRelativePath(record.objectPath);
  const objectPath = path.resolve(archiveDir, record.objectPath);
  assert.ok(objectPath.startsWith(`${archiveDir}${path.sep}`));
  assert.ok(existsSync(objectPath), `materialized payload missing: ${record.objectPath}`);
  const objectStatus = lstatSync(objectPath);
  assert.equal(objectStatus.isSymbolicLink(), false, `materialized payload must not be a symlink: ${record.objectPath}`);
  assert.equal(objectStatus.isFile(), true, `materialized payload must be a regular file: ${record.objectPath}`);
  const realObjectPath = realpathSync(objectPath);
  assert.ok(realObjectPath.startsWith(`${realArchiveDir}${path.sep}`), "materialized payload must stay inside archive");
  assert.equal(statSync(realObjectPath).size, record.sizeBytes);
  assert.equal(createHash("sha256").update(readFileSync(realObjectPath)).digest("hex"), record.sha256);
}
console.log(`data source archive restore rehearsal ok: ${manifest.materialized.length} payload(s)`);

function assertSafeRelativePath(value) {
  assert.equal(path.isAbsolute(value), false, "objectPath must be relative");
  assert.equal(value.split(/[\\/]/).includes(".."), false, "objectPath must not contain traversal");
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let quoted = false;
  for (let offset = 0; offset < text.length; offset += 1) {
    const character = text[offset];
    if (quoted) {
      if (character === '"' && text[offset + 1] === '"') {
        field += '"';
        offset += 1;
      } else if (character === '"') {
        quoted = false;
      } else {
        field += character;
      }
    } else if (character === '"') {
      quoted = true;
    } else if (character === ",") {
      row.push(field);
      field = "";
    } else if (character === "\n") {
      row.push(field.replace(/\r$/, ""));
      if (row.some((value) => value !== "")) rows.push(row);
      row = [];
      field = "";
    } else {
      field += character;
    }
  }
  if (field !== "" || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  assert.equal(quoted, false, "unterminated quoted CSV field");
  return rows;
}
