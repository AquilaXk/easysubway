import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";

import {
  accessibilityIndexMetadata,
  applyEvidenceIfStale,
  assertAccessibilityEdges,
  stripLegacyCoreClaims,
  syncAccessibilityEdges,
  syncCanonicalFixture,
} from "./apply-accessibility-evidence-to-bundled-pack.mjs";

test("core-only strips facility quality targets and check rejects leftovers", () => {
  const database = new DatabaseSync(":memory:");
  database.exec(`
    CREATE TABLE facilities (id TEXT PRIMARY KEY);
    CREATE TABLE data_quality_records (id TEXT PRIMARY KEY, target_type TEXT, target_id TEXT);
    INSERT INTO facilities VALUES ('legacy-facility');
    INSERT INTO data_quality_records VALUES
      ('facility-quality', 'facility', 'legacy-facility'),
      ('exit-quality', 'station_exit', 'exit-1');
  `);

  assert.throws(() => stripLegacyCoreClaims(database, { check: true }), /legacy core accessibility claims are stale/);
  assert.equal(stripLegacyCoreClaims(database, { check: false }), true);
  assert.deepEqual(
    database.prepare("SELECT target_type AS targetType FROM data_quality_records").all()
      .map((row) => ({ ...row })),
    [{ targetType: "station_exit" }],
  );
  assert.doesNotThrow(() => stripLegacyCoreClaims(database, { check: true }));

  database.prepare("INSERT INTO data_quality_records VALUES ('dangling', 'facility', 'missing')").run();
  assert.throws(() => stripLegacyCoreClaims(database, { check: true }), /legacy core accessibility claims are stale/);
  database.close();
});

test("stale refresh does not mask structural SQLite errors", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "easysubway-accessibility-structural-"));
  const sqlitePath = path.join(directory, "malformed.sqlite");
  const database = new DatabaseSync(sqlitePath);
  database.exec("CREATE TABLE facilities (id TEXT, station_id TEXT)");
  database.close();
  try {
    assert.throws(
      () => applyEvidenceIfStale(sqlitePath, { facilities: [], stationFacilityEvidence: [], networkEdges: [] }),
      /no such column: exit_id/,
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

const reviewedEdge = {
  id: "edge-entry-sadang-seoul-4",
  fromNodeId: "station-sadang",
  toNodeId: "station-sadang:seoul-4",
  durationSeconds: 90,
  distanceMeters: 0,
  edgeType: "ENTRY",
  servicePattern: "",
  includesStairs: false,
  stairAccessState: "UNKNOWN",
  accessibilityStatus: "UNKNOWN",
  reliabilityScore: 90,
  sourceId: "seoul-metro-accessibility",
  sourceSnapshotId: "seoul-metro-accessibility-20260728",
  providerRecordHash: "a".repeat(64),
  provenanceKind: "OFFICIAL_SOURCE",
  verificationStatus: "NOT_VERIFIED",
  lastVerifiedAt: "2026-07-28T15:35:25.704Z",
  evidenceHash: "b".repeat(64),
};

test("canonical and SQLite refresh the reviewed ENTRY/EXIT identity together", () => {
  const reviewedPack = {
    networkEdges: [reviewedEdge],
    metadata: { productionCoverageEvidence: "reviewed-accessibility-sources" },
  };
  const officialOdFareQuotes = [{ originStationId: "station-sadang", destinationStationId: "station-sangnoksu" }];
  const routeServiceArtifactEvidence = [{ serviceClass: "ITX_CHEONGCHUN", admissionStatus: "MISSING" }];
  const canonical = { packs: [{
    id: "capital",
    facilities: [
      { id: "legacy-elevator", stationId: "station-sadang", type: "ELEVATOR", sourceId: "kric-station-elevator" },
      { id: "surviving-toilet", stationId: "station-sadang", type: "ACCESSIBLE_TOILET", sourceId: "other" },
    ],
    dataQualityRecords: [
      { targetType: "facility", targetId: "legacy-elevator", qualityLevel: "FIELD_VERIFIED" },
      { targetType: "facility", targetId: "surviving-toilet", qualityLevel: "FIELD_STALE" },
      { targetType: "station_exit", targetId: "exit-sadang-1", qualityLevel: "FIELD_VERIFIED" },
    ],
    networkEdges: [{ ...reviewedEdge, sourceSnapshotId: "stale" }],
    sourceInventory: [{ id: "seoul-metro-official-od-fares" }],
    officialOdFareQuotes,
    routeServiceArtifactEvidence,
    metadata: { productionCoverageEvidence: "retired-accessibility-sources" },
    minimumTableRows: {},
  }] };
  const synced = syncCanonicalFixture(structuredClone(canonical), {
    ...reviewedPack,
    facilities: [],
    stationFacilityEvidence: [],
    sourceInventory: [],
  });
  assert.deepEqual(synced.packs[0].networkEdges, [reviewedEdge]);
  assert.deepEqual(synced.packs[0].officialOdFareQuotes, officialOdFareQuotes);
  assert.deepEqual(synced.packs[0].routeServiceArtifactEvidence, routeServiceArtifactEvidence);
  assert.deepEqual(synced.packs[0].sourceInventory, [{ id: "seoul-metro-official-od-fares" }]);
  assert.deepEqual(synced.packs[0].dataQualityRecords, [
    { targetType: "facility", targetId: "surviving-toilet", qualityLevel: "FIELD_STALE" },
    { targetType: "station_exit", targetId: "exit-sadang-1", qualityLevel: "FIELD_VERIFIED" },
  ]);
  assert.equal(synced.packs[0].metadata.productionCoverageEvidence, "reviewed-accessibility-sources");

  const database = new DatabaseSync(":memory:");
  database.exec(`
    CREATE TABLE network_edges (
      id TEXT PRIMARY KEY, from_node_id TEXT, to_node_id TEXT, duration_seconds INTEGER,
      distance_meters INTEGER, edge_type TEXT, service_pattern TEXT, service_class TEXT,
      includes_stairs INTEGER, stair_access_state TEXT, accessibility_status TEXT,
      reliability_score INTEGER, source_id TEXT, source_snapshot_id TEXT,
      provider_record_hash TEXT, provenance_kind TEXT, verification_status TEXT,
      facility_id TEXT, last_verified_at INTEGER, evidence_hash TEXT
    );
    INSERT INTO network_edges VALUES (
      'stale-edge', 'station-sadang', 'station-sadang:seoul-4', 1, 1, 'ENTRY', '', 'SUBWAY',
      0, 'UNKNOWN', 'UNKNOWN', 1, 'seoul-metro-accessibility', 'stale', '',
      'OFFICIAL_SOURCE', 'NOT_VERIFIED', NULL, 1, ''
    );
  `);
  syncAccessibilityEdges(database, reviewedPack);
  assert.doesNotThrow(() => assertAccessibilityEdges(database, reviewedPack));
  assert.deepEqual(
    database.prepare("SELECT id, source_snapshot_id AS sourceSnapshotId, evidence_hash AS evidenceHash FROM network_edges")
      .all().map((row) => ({ ...row })),
    [{ id: reviewedEdge.id, sourceSnapshotId: reviewedEdge.sourceSnapshotId, evidenceHash: reviewedEdge.evidenceHash }],
  );
  database.prepare("UPDATE network_edges SET source_snapshot_id = 'stale'").run();
  assert.throws(() => assertAccessibilityEdges(database, reviewedPack), /bundled accessibility edge is stale/);
  database.close();
});

test("metadata requires admission for facilities-only sources and uses the build clock hook", (t) => {
  const previousBuildNow = process.env.EASYSUBWAY_DATAPACK_BUILD_NOW;
  process.env.EASYSUBWAY_DATAPACK_BUILD_NOW = "2026-07-28T16:00:00.000Z";
  t.after(() => {
    if (previousBuildNow === undefined) delete process.env.EASYSUBWAY_DATAPACK_BUILD_NOW;
    else process.env.EASYSUBWAY_DATAPACK_BUILD_NOW = previousBuildNow;
  });
  const pack = {
    facilities: [{ sourceId: "facility-source", sourceSnapshotId: "facility-snapshot" }],
    stationFacilityEvidence: [{ sourceId: "status-source", sourceSnapshotId: "status-snapshot" }],
  };
  const spec = { sourceSnapshotSetHash: "a".repeat(64), sourceSnapshots: [
    { sourceId: "facility-source", snapshotId: "facility-snapshot", freshnessExpiresAt: "2026-08-10T00:00:00.000Z" },
    { sourceId: "status-source", snapshotId: "status-snapshot", freshnessExpiresAt: "2026-08-09T00:00:00.000Z" },
  ] };
  const inventory = { sources: [
    { id: "facility-source", accessibilityAdmissionEvidence: { snapshotId: "facility-snapshot", observedAt: "2026-07-28T14:00:00.000Z", freshUntil: "2026-07-29T14:00:00.000Z" } },
    { id: "status-source", accessibilityAdmissionEvidence: { snapshotId: "status-snapshot", observedAt: "2026-07-28T15:00:00.000Z", freshUntil: "2026-07-29T15:00:00.000Z" } },
  ] };

  assert.deepEqual(accessibilityIndexMetadata(pack, spec, inventory, "2026-08-08T00:00:00.000Z"), {
    builtAt: "2026-07-28T16:00:00.000Z",
    qualityAsOf: "2026-07-28T15:00:00.000Z",
    freshnessExpiresAt: "2026-08-08T00:00:00.000Z",
    sourceSnapshotSetHash: "a".repeat(64),
  });
});

test("metadata fails closed when a consumed source lacks admission evidence", () => {
  assert.throws(() => accessibilityIndexMetadata(
    { facilities: [{ sourceId: "missing", sourceSnapshotId: "snapshot" }], stationFacilityEvidence: [] },
    { sourceSnapshotSetHash: "a".repeat(64), sourceSnapshots: [{ sourceId: "missing", snapshotId: "snapshot", freshnessExpiresAt: "2026-08-01T00:00:00.000Z" }] },
    { sources: [] },
    "2026-08-01T00:00:00.000Z",
  ), /accessibility admission evidence missing: missing/);

  assert.throws(() => accessibilityIndexMetadata(
    { facilities: [{ sourceId: "source", sourceSnapshotId: "snapshot" }], stationFacilityEvidence: [] },
    { sourceSnapshotSetHash: "a".repeat(64), sourceSnapshots: [{ sourceId: "source", snapshotId: "snapshot", freshnessExpiresAt: "2026-08-01T00:00:00.000Z" }] },
    { sources: [{ id: "source", accessibilityAdmissionEvidence: { snapshotId: "snapshot", observedAt: "2026-07-28T00:00:00.000Z", freshUntil: "2026-07-29T00:00:00.000Z" } }] },
    undefined,
  ), /bundled pack freshness missing/);
});
