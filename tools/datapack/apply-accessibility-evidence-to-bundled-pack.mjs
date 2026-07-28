#!/usr/bin/env node
import { createHash, randomUUID } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { DatabaseSync } from "node:sqlite";
import { gunzipSync, gzipSync, constants as zlibConstants } from "node:zlib";

import { addCadence } from "./freshness-policy.mjs";
import { deriveRawRetentionExpiresAt } from "./source-governance-policy.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const stationIds = ["station-sadang", "station-sangnoksu"];
const facilityTypes = ["ELEVATOR", "ESCALATOR", "WHEELCHAIR_LIFT", "ACCESSIBILITY_STATUS_PROBE"];
const replacedSourceIds = new Set([
  "kric-station-elevator",
  "kric-station-escalator",
  "kric-wheelchair-lift-location",
  "seoul-metro-accessibility",
]);

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
    database.prepare(`DELETE FROM facilities WHERE station_id IN (${placeholders}) AND (type IN ('ELEVATOR','ESCALATOR','WHEELCHAIR_LIFT') OR source_id IN (${[...replacedSourceIds].map(() => "?").join(",")}))`).run(...stationIds, ...replacedSourceIds);
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
    const staleFacility = database.prepare(`SELECT count(*) AS count FROM facilities WHERE station_id IN (?,?) AND source_id IN (${[...replacedSourceIds].map(() => "?").join(",")})`).get(...stationIds, ...replacedSourceIds).count;
    if (staleFacility !== 0) throw new Error("bundled accessibility facility source is stale");
  } finally {
    database.close();
  }
}

function syncCanonicalFixture(canonical, reviewedPack) {
  const pack = canonical.packs?.find(({ id }) => id === "capital");
  if (!pack) throw new Error("canonical capital pack is missing");
  pack.facilities = (pack.facilities ?? [])
    .filter(({ stationId, type, sourceId }) => !stationIds.includes(stationId)
      || (!facilityTypes.includes(type)
        && !replacedSourceIds.has(sourceId)
        && sourceId !== "kric-station-convenience-standard"))
    .concat(reviewedPack.facilities);
  pack.stationFacilityEvidence = (pack.stationFacilityEvidence ?? [])
    .filter(({ stationId, facilityType }) => !stationIds.includes(stationId) || !facilityTypes.includes(facilityType))
    .concat(reviewedPack.stationFacilityEvidence);
  const freshSources = reviewedPack.sourceInventory.filter(({ id }) =>
    ["kric-station-convenience-standard", "seoul-metro-accessibility"].includes(id));
  pack.sourceInventory = pack.sourceInventory
    .filter(({ id }) => !replacedSourceIds.has(id) && id !== "kric-station-convenience-standard")
    .concat(freshSources);
  pack.minimumTableRows.facilities = pack.facilities.length;
  pack.minimumTableRows.station_facility_evidence = pack.stationFacilityEvidence.length;
  return canonical;
}

function assertCanonicalFixture(canonical, reviewedPack) {
  const expected = syncCanonicalFixture(structuredClone(canonical), reviewedPack);
  if (JSON.stringify(expected) !== JSON.stringify(canonical)) {
    throw new Error("canonical accessibility fixture is stale");
  }
}

async function stripLegacyCore({ check }) {
  const packPath = path.join(root, "apps/mobile/assets/datapacks/core.sqlite.gz");
  const indexPath = path.join(root, "apps/mobile/assets/datapacks/index.json");
  const directory = await mkdtemp(path.join(os.tmpdir(), `accessibility-core-${randomUUID()}-`));
  try {
    const sqlitePath = path.join(directory, "core.sqlite");
    const currentGzipBytes = await readFile(packPath);
    await writeFile(sqlitePath, gunzipSync(currentGzipBytes));
    const database = new DatabaseSync(sqlitePath);
    const count = database.prepare("SELECT count(*) AS count FROM facilities").get().count;
    if (check && count !== 0) throw new Error("legacy core accessibility claims are stale");
    if (!check && count !== 0) database.exec("DELETE FROM facilities; VACUUM");
    database.close();
    if (!check && count === 0) return;
    const sqliteBytes = await readFile(sqlitePath);
    if (check) {
      const index = JSON.parse(await readFile(indexPath, "utf8"));
      const entry = index.packs.find(({ id }) => id === "core");
      if (!entry) throw new Error("core pack index entry is missing");
      if (entry.sha256 !== sha256(currentGzipBytes)
        || entry.sqliteSha256 !== sha256(sqliteBytes)
        || entry.byteSize !== currentGzipBytes.length) {
        throw new Error("core pack index identity is stale");
      }
      return;
    }
    const gzipBytes = gzipSync(sqliteBytes, { level: 9, mtime: 0 });
    gzipBytes[9] = 255;
    const index = JSON.parse(await readFile(indexPath, "utf8"));
    const entry = index.packs.find(({ id }) => id === "core");
    if (!entry) throw new Error("core pack index entry is missing");
    Object.assign(entry, { sha256: sha256(gzipBytes), sqliteSha256: sha256(sqliteBytes), byteSize: gzipBytes.length });
    await Promise.all([
      writeFile(packPath, gzipBytes),
      writeFile(indexPath, `${JSON.stringify(index, null, 2)}\n`),
    ]);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

async function syncReleaseEvidence({ check }) {
  const paths = {
    spec: path.join(root, "tools/datapack/release/candidate-build-spec.json"),
    snapshots: path.join(root, "tools/datapack/release/source-snapshots.json"),
    inventory: path.join(root, "tools/datapack/source-inventory.json"),
    request: path.join(root, "tools/datapack/release/release-request.json"),
    hashes: path.join(root, "tools/datapack/release/hash-evidence.json"),
    canonical: path.join(root, "tools/datapack/release/capital-production-canonical-pack.json"),
    governance: path.join(root, "tools/datapack/source-governance-policy.json"),
    freshness: path.join(root, "apps/mobile/release/datapack-freshness-sla.json"),
  };
  const [specBytes, snapshotBytes, inventoryBytes, requestBytes, hashBytes, canonicalBytes, governanceBytes, freshnessBytes] = await Promise.all(
    Object.values(paths).map((file) => readFile(file)),
  );
  const spec = JSON.parse(specBytes);
  const snapshots = JSON.parse(snapshotBytes);
  const inventory = JSON.parse(inventoryBytes);
  const request = JSON.parse(requestBytes);
  const hashes = JSON.parse(hashBytes);
  const governance = JSON.parse(governanceBytes);
  const freshness = JSON.parse(freshnessBytes);
  const inventoryBySource = new Map(inventory.sources.map((entry) => [entry.id, entry]));
  spec.sourceSnapshotIds = snapshots.map(({ snapshotId }) => snapshotId);
  spec.sourceSnapshots = snapshots.map((snapshot) => {
    const source = inventoryBySource.get(snapshot.sourceId);
    const adminReviewRecordHash = source?.admissionEvidence?.adminReviewRecordHash;
    if (!/^[0-9a-f]{64}$/.test(adminReviewRecordHash ?? "")) throw new Error(`admin review hash missing: ${snapshot.sourceId}`);
    const sourceClass = freshness.sourceClasses.find(({ sourceIds }) => sourceIds.includes(snapshot.sourceId));
    if (!sourceClass) throw new Error(`freshness class missing: ${snapshot.sourceId}`);
    const basisAt = snapshot[sourceClass.basisField];
    let freshnessExpiresAt = addCadence(
      Date.parse(basisAt),
      sourceClass.reverificationCadence ?? sourceClass.maximumReverificationCadence,
    );
    if (sourceClass.providerValidityEndField) {
      freshnessExpiresAt = Math.min(freshnessExpiresAt, Date.parse(snapshot[sourceClass.providerValidityEndField]));
    }
    return {
      snapshotId: snapshot.snapshotId,
      sourceId: snapshot.sourceId,
      rawObjectUri: snapshot.rawObjectUri,
      rawSha256: snapshot.rawSha256,
      redactedRequestFingerprint: snapshot.redactedRequestFingerprint,
      schemaFingerprint: snapshot.schemaFingerprint,
      licenseStatus: snapshot.licenseStatus,
      redistributionAllowed: snapshot.redistributionAllowed,
      adminReviewRecordHash,
      snapshotStatus: snapshot.snapshotStatus,
      credentialRedacted: snapshot.credentialRedacted,
      freshnessExpiresAt: new Date(freshnessExpiresAt).toISOString(),
      rawRetentionExpiresAt: deriveRawRetentionExpiresAt({
        policy: governance,
        sourceId: snapshot.sourceId,
        retrievedAt: snapshot.retrievedAt,
      }),
      governancePolicyVersion: governance.policyVersion,
      governancePolicySha256: sha256(governanceBytes),
    };
  });
  spec.sourceSnapshotSetHash = sha256(JSON.stringify(snapshots));
  spec.sourceInventorySha256 = sha256(JSON.stringify(inventory));
  spec.itxTopologyEvidenceSha256 = sha256(await readFile(path.resolve(root, spec.itxTopologyEvidencePath)));
  spec.networkEdgeEvidence.sourceInventory.sha256 = sha256(inventoryBytes);
  const nextSpecBytes = Buffer.from(`${JSON.stringify(spec, null, 2)}\n`);
  request.buildSpecSha256 = sha256(nextSpecBytes);
  request.sourceSnapshotSetHash = spec.sourceSnapshotSetHash;
  hashes.truthfulnessRule = "모든 값은 tracked canonical fixture·inventory·official snapshot에서 결정적으로 재산출한다. 2026-07-28 신규 KRIC standard·서울 snapshot을 소비 claim에 결속하고 route 가용성은 추론하지 않는다.";
  hashes.sourceSnapshotSetHash.value = spec.sourceSnapshotSetHash;
  hashes.sourceSnapshotSetHash.contract = `source-snapshots.json ${snapshots.length}종의 byte-ordered JSON hash와 build spec·release request가 일치해야 한다.`;
  hashes.sourceInventorySha256.value = spec.sourceInventorySha256;
  hashes.fixturePath.sha256 = sha256(canonicalBytes);
  hashes.sourceSnapshots.note = "기존 release source 중 movement·timetable·network identity는 유지하고, detailed location 3종을 KRIC stationCnvFacl standard로 교체했다. 서울 accessibility는 2026-07-28 full snapshot으로 교체했다.";
  hashes.sourceSnapshots.order = `release snapshot 순서: ${snapshots.map(({ sourceId }) => sourceId).join(" → ")}`;
  hashes.perSourceEvidence = snapshots.map((snapshot) => ({
    sourceId: snapshot.sourceId,
    snapshotId: snapshot.snapshotId,
    rawSha256: snapshot.rawSha256,
    adminReviewRecordHash: inventoryBySource.get(snapshot.sourceId).admissionEvidence.adminReviewRecordHash,
    perSourceSnapshotSetHash: sha256(JSON.stringify([snapshot])),
  }));
  const nextRequestBytes = Buffer.from(`${JSON.stringify(request, null, 2)}\n`);
  const nextHashBytes = Buffer.from(`${JSON.stringify(hashes, null, 2)}\n`);
  if (check) {
    for (const [label, actual, expected] of [
      ["candidate build spec", specBytes, nextSpecBytes],
      ["release request", requestBytes, nextRequestBytes],
      ["hash evidence", hashBytes, nextHashBytes],
    ]) if (!actual.equals(expected)) throw new Error(`${label} is stale`);
    return { spec, inventory };
  }
  await Promise.all([
    writeFile(paths.spec, nextSpecBytes),
    writeFile(paths.request, nextRequestBytes),
    writeFile(paths.hashes, nextHashBytes),
  ]);
  return { spec, inventory };
}

export function accessibilityIndexMetadata(pack, spec, inventory, currentFreshnessExpiresAt) {
  const evidenceBySource = new Map(inventory.sources.map((source) => [source.id, source.accessibilityAdmissionEvidence]));
  const snapshotBySource = new Map(spec.sourceSnapshots.map((snapshot) => [snapshot.sourceId, snapshot]));
  const consumed = new Map();
  for (const { sourceId, sourceSnapshotId } of [...pack.facilities, ...pack.stationFacilityEvidence]) {
    if (consumed.has(sourceId) && consumed.get(sourceId) !== sourceSnapshotId) {
      throw new Error(`accessibility snapshot mismatch: ${sourceId}`);
    }
    consumed.set(sourceId, sourceSnapshotId);
  }
  const accessibilityFreshnessExpiresAt = [...consumed].map(([sourceId, snapshotId]) => {
    const evidence = evidenceBySource.get(sourceId);
    if (evidence?.snapshotId !== snapshotId
      || !Number.isFinite(Date.parse(evidence.observedAt))
      || !Number.isFinite(Date.parse(evidence.freshUntil))) {
      throw new Error(`accessibility admission evidence missing: ${sourceId}`);
    }
    const snapshot = snapshotBySource.get(sourceId);
    if (snapshot?.snapshotId !== snapshotId) throw new Error(`accessibility snapshot mismatch: ${sourceId}`);
    if (!Number.isFinite(Date.parse(snapshot.freshnessExpiresAt))) {
      throw new Error(`accessibility snapshot freshness missing: ${sourceId}`);
    }
    return snapshot.freshnessExpiresAt;
  }).sort().at(0);
  const qualityAsOf = [...consumed.keys()].map((sourceId) => evidenceBySource.get(sourceId).observedAt).sort().at(-1);
  const currentFreshnessMillis = Date.parse(currentFreshnessExpiresAt);
  const accessibilityFreshnessMillis = Date.parse(accessibilityFreshnessExpiresAt);
  if (!Number.isFinite(currentFreshnessMillis)) throw new Error("bundled pack freshness missing");
  if (!Number.isFinite(accessibilityFreshnessMillis)) throw new Error("accessibility snapshot freshness missing");
  return {
    builtAt: candidateBuildNow().toISOString(),
    qualityAsOf,
    // ponytail: accessibility refresh may tighten, never extend another domain's pack expiry; the identity test owns extension.
    freshnessExpiresAt: new Date(Math.min(currentFreshnessMillis, accessibilityFreshnessMillis)).toISOString(),
    sourceSnapshotSetHash: spec.sourceSnapshotSetHash,
  };
}

async function main() {
  if (process.argv.includes("--core-only")) {
    await stripLegacyCore({ check: process.argv.includes("--check") });
    return;
  }
  const packPath = path.resolve(root, option("--pack", "apps/mobile/assets/datapacks/capital.sqlite.gz"));
  const indexPath = path.resolve(root, option("--index", "apps/mobile/assets/datapacks/index.json"));
  const fixturePath = path.resolve(root, option("--fixture", "tools/datapack/release/capital-production-reviewed-pack.json"));
  const canonicalPath = path.resolve(root, option("--canonical-fixture", "tools/datapack/release/capital-production-canonical-pack.json"));
  const pack = JSON.parse(await readFile(fixturePath, "utf8")).packs?.find(({ id }) => id === "capital");
  if (!pack || pack.facilities?.length !== 4 || pack.stationFacilityEvidence?.length !== 8) {
    throw new Error("reviewed capital accessibility evidence must contain 4 facilities and 8 evidence rows");
  }
  const canonical = JSON.parse(await readFile(canonicalPath, "utf8"));
  if (process.argv.includes("--check")) assertCanonicalFixture(canonical, pack);
  else await writeFile(canonicalPath, `${JSON.stringify(syncCanonicalFixture(canonical, pack))}\n`);
  const releaseEvidence = await syncReleaseEvidence({ check: process.argv.includes("--check") });
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
      const metadata = accessibilityIndexMetadata(
        pack,
        releaseEvidence.spec,
        releaseEvidence.inventory,
        index.freshnessExpiresAt,
      );
      if (index.qualityAsOf !== metadata.qualityAsOf
        || index.freshnessExpiresAt !== metadata.freshnessExpiresAt
        || index.sourceSnapshotSetHash !== metadata.sourceSnapshotSetHash
        || Date.parse(index.builtAt) < Date.parse(metadata.qualityAsOf)) {
        throw new Error("bundled accessibility pack metadata is stale");
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
    Object.assign(index, accessibilityIndexMetadata(
      pack,
      releaseEvidence.spec,
      releaseEvidence.inventory,
      index.freshnessExpiresAt,
    ));
    await writeFile(packPath, gzipBytes);
    await writeFile(indexPath, `${JSON.stringify(index, null, 2)}\n`);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function candidateBuildNow() {
  const value = process.env.EASYSUBWAY_DATAPACK_BUILD_NOW;
  const date = value ? new Date(value) : new Date();
  if ((value && !value.endsWith("Z")) || !Number.isFinite(date.getTime())) {
    throw new Error("EASYSUBWAY_DATAPACK_BUILD_NOW must be UTC ISO-8601");
  }
  return date;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => { process.stderr.write(`${error.stack ?? error.message}\n`); process.exitCode = 1; });
}
