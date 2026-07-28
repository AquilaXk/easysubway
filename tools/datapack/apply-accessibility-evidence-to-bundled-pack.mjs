#!/usr/bin/env node
import { createHash, randomUUID } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { gunzipSync, gzipSync, constants as zlibConstants } from "node:zlib";

const root = path.resolve(import.meta.dirname, "../..");
const stationIds = ["station-sadang", "station-sangnoksu"];
const facilityTypes = ["ELEVATOR", "ESCALATOR", "WHEELCHAIR_LIFT", "ACCESSIBILITY_STATUS_PROBE"];

function option(name, fallback) {
  const index = process.argv.indexOf(name);
  return index < 0 ? fallback : process.argv[index + 1];
}

function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
function epoch(value) { return Math.floor(Date.parse(value) / 1000); }

function applyEvidence(sqlitePath, pack) {
  const database = new DatabaseSync(sqlitePath);
  database.exec("PRAGMA foreign_keys = ON; BEGIN IMMEDIATE");
  try {
    const placeholders = stationIds.map(() => "?").join(",");
    database.prepare(`DELETE FROM facilities WHERE station_id IN (${placeholders}) AND type IN ('ELEVATOR','ESCALATOR','WHEELCHAIR_LIFT')`).run(...stationIds);
    const insertFacility = database.prepare(`
      INSERT INTO facilities (
        id, station_id, exit_id, type, name, status, floor_from, floor_to, description,
        source_id, source_snapshot_id, provider_facility_ref, provider_record_hash,
        provenance_kind, verified_at, retrieved_at, evidence_hash, status_meaning,
        operational_status, installation_status, confidence
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    `);
    for (const row of pack.facilities) insertFacility.run(
      row.id, row.stationId, row.exitId, row.type, row.name, row.status, row.floorFrom, row.floorTo,
      row.description, row.sourceId, row.sourceSnapshotId, row.providerFacilityRef, row.providerRecordHash,
      row.provenanceKind, epoch(row.verifiedAt), epoch(row.retrievedAt), row.evidenceHash, row.statusMeaning,
      row.operationalStatus, row.installationStatus, row.confidence,
    );

    database.prepare(`DELETE FROM station_facility_evidence WHERE station_id IN (${placeholders}) AND facility_type IN (${facilityTypes.map(() => "?").join(",")})`).run(...stationIds, ...facilityTypes);
    const insertEvidence = database.prepare(`
      INSERT INTO station_facility_evidence (
        station_id, line_id, facility_type, evidence_kind, source_id, source_snapshot_id,
        provider_record_hash, evidence_hash, provenance_kind, installation_status,
        operational_status, status_meaning, confidence, verified_at, retrieved_at,
        strict_route_eligible, strict_route_eligible_reason
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    `);
    for (const row of pack.stationFacilityEvidence) insertEvidence.run(
      row.stationId, row.lineId, row.facilityType, row.evidenceKind, row.sourceId,
      row.sourceSnapshotId, row.providerRecordHash, row.evidenceHash, row.provenanceKind,
      row.installationStatus, row.operationalStatus, row.statusMeaning, row.confidence,
      epoch(row.verifiedAt), epoch(row.retrievedAt), row.strictRouteEligible ? 1 : 0,
      row.strictRouteEligibleReason,
    );

    database.exec("COMMIT");
  } catch (error) {
    database.exec("ROLLBACK");
    throw error;
  } finally {
    database.close();
  }
}

function assertEvidence(sqlitePath, pack) {
  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  try {
    if (database.prepare("PRAGMA integrity_check").get().integrity_check !== "ok") throw new Error("bundled datapack integrity_check failed");
    const facilityCount = database.prepare("SELECT count(*) AS count FROM facilities WHERE station_id IN (?,?) AND type IN ('ELEVATOR','ESCALATOR','WHEELCHAIR_LIFT')").get(...stationIds).count;
    const evidenceCount = database.prepare(`SELECT count(*) AS count FROM station_facility_evidence WHERE station_id IN (?,?) AND facility_type IN (${facilityTypes.map(() => "?").join(",")})`).get(...stationIds, ...facilityTypes).count;
    if (facilityCount !== pack.facilities.length || evidenceCount !== pack.stationFacilityEvidence.length) {
      throw new Error(`bundled accessibility evidence is stale: facilities=${facilityCount} evidence=${evidenceCount}`);
    }
    const snapshotIds = [...new Set(pack.stationFacilityEvidence.map(({ sourceSnapshotId }) => sourceSnapshotId))];
    const stale = database.prepare(`SELECT count(*) AS count FROM station_facility_evidence WHERE station_id IN (?,?) AND source_snapshot_id NOT IN (${snapshotIds.map(() => "?").join(",")})`).get(...stationIds, ...snapshotIds).count;
    if (stale !== 0) throw new Error("bundled accessibility source snapshot is stale");
  } finally {
    database.close();
  }
}

async function main() {
  const packPath = path.resolve(root, option("--pack", "apps/mobile/assets/datapacks/capital.sqlite.gz"));
  const indexPath = path.resolve(root, option("--index", "apps/mobile/assets/datapacks/index.json"));
  const fixturePath = path.resolve(root, option("--fixture", "tools/datapack/release/capital-production-reviewed-pack.json"));
  const pack = JSON.parse(await readFile(fixturePath, "utf8")).packs?.find(({ id }) => id === "capital");
  if (!pack || pack.facilities?.length !== 4 || pack.stationFacilityEvidence?.length !== 8) {
    throw new Error("reviewed capital accessibility evidence must contain 4 facilities and 8 evidence rows");
  }
  const directory = await mkdtemp(path.join(os.tmpdir(), `accessibility-pack-${randomUUID()}-`));
  try {
    const sqlitePath = path.join(directory, "capital.sqlite");
    const currentGzipBytes = await readFile(packPath);
    await writeFile(sqlitePath, gunzipSync(currentGzipBytes));
    if (process.argv.includes("--check")) {
      assertEvidence(sqlitePath, pack);
      const sqliteBytes = await readFile(sqlitePath);
      const index = JSON.parse(await readFile(indexPath, "utf8"));
      const entry = index.packs.find(({ id }) => id === "capital");
      if (!entry || entry.sha256 !== sha256(currentGzipBytes) || entry.sqliteSha256 !== sha256(sqliteBytes) || entry.byteSize !== currentGzipBytes.length) {
        throw new Error("bundled accessibility pack index is stale");
      }
      return;
    }
    applyEvidence(sqlitePath, pack);
    assertEvidence(sqlitePath, pack);
    const sqliteBytes = await readFile(sqlitePath);
    const gzipBytes = gzipSync(sqliteBytes, { level: 9, mtime: 0, strategy: zlibConstants.Z_RLE });
    gzipBytes[9] = 255;
    const index = JSON.parse(await readFile(indexPath, "utf8"));
    const entry = index.packs.find(({ id }) => id === "capital");
    if (!entry) throw new Error("capital pack index entry is missing");
    Object.assign(entry, { sha256: sha256(gzipBytes), sqliteSha256: sha256(sqliteBytes), byteSize: gzipBytes.length });
    await writeFile(packPath, gzipBytes);
    await writeFile(indexPath, `${JSON.stringify(index, null, 2)}\n`);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
