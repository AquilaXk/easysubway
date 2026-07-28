import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { gzipSync } from "node:zlib";

import {
  buildAccessibilitySourceCoverageReport,
  loadAccessibilityAdmissionSnapshots,
  loadSelectableAccessibilityArtifacts,
} from "./build-accessibility-source-coverage-report.mjs";

const EVALUATED_AT = "2026-07-28T00:00:00.000Z";

test("selectable artifact의 모든 claim이 fresh official snapshot에 결속되면 GO다", () => {
  const input = validInput();

  const report = buildAccessibilitySourceCoverageReport(input);

  assert.equal(report.decision, "GO");
  assert.deepEqual(report.artifacts, [
    { artifactId: "bundled-capital", sqliteSha256: hash("sqlite-a"), searchableStationCount: 1, claimCount: 1 },
    { artifactId: "remote-capital", sqliteSha256: hash("sqlite-b"), searchableStationCount: 1, claimCount: 1 },
  ]);
  assert.deepEqual(report.providerDomainMatrix, [{
    sourceId: "official-accessibility",
    domain: "STATION_FACILITY_EVIDENCE",
    artifactIds: ["bundled-capital", "remote-capital"],
    claimCount: 2,
    status: "ADMITTED",
  }]);
  assert.deepEqual(report.violations, emptyViolations());
});

test("미승인 source는 provider-domain matrix에서도 BLOCKED다", () => {
  const input = validInput();
  input.inventory.sources[0].accessibilityAdmissionEvidence.decision = "PENDING";

  const report = buildAccessibilitySourceCoverageReport(input);

  assert.equal(report.decision, "NO_GO");
  assert.equal(report.providerDomainMatrix[0].status, "BLOCKED");
});

test("tracked snapshot bytes와 inventory file SHA가 일치해야 한다", async (t) => {
  const repositoryRoot = await mkdtemp(path.join(tmpdir(), "easysubway-accessibility-snapshot-"));
  t.after(() => rm(repositoryRoot, { recursive: true, force: true }));
  const snapshotPath = "official-accessibility-20260728.json";
  const snapshot = {
    sourceId: "official-accessibility",
    snapshotId: "official-accessibility-20260728",
    capturedAt: "2026-07-27T23:00:00.000Z",
    observedAt: "2026-07-27T23:00:00.000Z",
    freshUntil: "2026-07-29T23:00:00.000Z",
    rawSha256: hash("raw"),
    contentSha256: hash("content"),
    schemaFingerprint: hash("schema"),
  };
  const bytes = `${JSON.stringify(snapshot)}\n`;
  await writeFile(path.join(repositoryRoot, snapshotPath), bytes);
  const sources = [{
    id: snapshot.sourceId,
    accessibilityAdmissionEvidence: { snapshotPath, snapshotFileSha256: hashBytes(bytes) },
  }];

  const [loaded] = await loadAccessibilityAdmissionSnapshots({
    sources,
    referencedSourceIds: new Set([snapshot.sourceId]),
    repositoryRoot,
  });

  assert.equal(loaded.snapshotFileSha256, hashBytes(bytes));
  assert.equal(loaded.snapshotId, snapshot.snapshotId);
});

test("remote manifest URL과 bundled index가 같은 gzip SQLite를 가리키면 artifact 하나로 읽는다", async (t) => {
  const directory = await mkdtemp(path.join(tmpdir(), "easysubway-accessibility-source-report-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const sqlitePath = path.join(directory, "capital.sqlite");
  const gzipPath = path.join(directory, "catalog", "capital.sqlite.gz");
  await mkdir(path.dirname(gzipPath));
  const database = new DatabaseSync(sqlitePath);
  database.exec(`
    CREATE TABLE stations (id TEXT PRIMARY KEY);
    CREATE TABLE station_lines (station_id TEXT, line_id TEXT);
    CREATE TABLE station_facility_evidence (
      station_id TEXT, line_id TEXT, facility_type TEXT, evidence_kind TEXT,
      source_id TEXT, source_snapshot_id TEXT, provider_record_hash TEXT, evidence_hash TEXT
    );
    CREATE TABLE facilities (
      id TEXT, station_id TEXT, type TEXT, source_id TEXT, source_snapshot_id TEXT,
      provider_record_hash TEXT, evidence_hash TEXT
    );
    CREATE TABLE network_edges (
      id TEXT, from_node_id TEXT, to_node_id TEXT, edge_type TEXT,
      accessibility_status TEXT, stair_access_state TEXT, source_id TEXT,
      source_snapshot_id TEXT, provider_record_hash TEXT, evidence_hash TEXT
    );
    CREATE TABLE internal_route_edges (
      id TEXT, from_node_id TEXT, to_node_id TEXT, edge_type TEXT,
      accessibility_status TEXT, source_id TEXT, source_snapshot_id TEXT,
      provider_record_hash TEXT, evidence_hash TEXT
    );
  `);
  database.prepare("INSERT INTO stations VALUES (?)").run("station-a");
  database.prepare("INSERT INTO station_lines VALUES (?, ?)").run("station-a", "line-a");
  database.prepare("INSERT INTO station_facility_evidence VALUES (?, ?, ?, ?, ?, ?, ?, ?)").run(
    "station-a", "line-a", "ELEVATOR", "VERIFIED_PRESENT", "official-accessibility",
    "official-accessibility-20260728", hash("record"), hash("evidence"),
  );
  database.prepare("INSERT INTO facilities VALUES (?, ?, ?, ?, ?, ?, ?)").run(
    "facility-a", "station-a", "ELEVATOR", "official-accessibility",
    "official-accessibility-20260728", hash("facility-record"), hash("facility-evidence"),
  );
  database.prepare("INSERT INTO facilities VALUES (?, ?, ?, ?, ?, ?, ?)").run(
    "facility-without-provenance", "station-a", "ESCALATOR", "", "", "", "",
  );
  database.prepare("INSERT INTO network_edges VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").run(
    "edge-entry-a", "station-a", "station-a:line-a", "ENTRY", "UNKNOWN", "UNKNOWN",
    "official-accessibility", "official-accessibility-20260728", hash("edge-record"), hash("edge-evidence"),
  );
  database.prepare("INSERT INTO network_edges VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)").run(
    "edge-without-provenance", "station-a", "station-a:line-a", "EXIT", "UNKNOWN", "UNKNOWN",
    "", "", "", "",
  );
  database.prepare("INSERT INTO internal_route_edges VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)").run(
    "internal-edge-without-provenance", "station-a", "station-a:line-a", "WALK", "AVAILABLE",
    "", "", "", "",
  );
  database.prepare("INSERT INTO internal_route_edges VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)").run(
    "internal-edge-unknown", "station-a", "station-a:line-a", "WALK", "UNKNOWN",
    "", "", "", "",
  );
  database.close();
  const sqliteBytes = await readFile(sqlitePath);
  await writeFile(gzipPath, gzipSync(sqliteBytes));
  const index = {
    packs: [{
      id: "capital",
      asset: "catalog/capital.sqlite.gz",
      sqliteSha256: hashBytes(sqliteBytes),
    }],
  };
  const manifest = {
    packs: [{
      id: "capital",
      url: "https://datapack.example/catalog/capital.sqlite.gz",
      sqliteSha256: hashBytes(sqliteBytes),
    }],
  };

  const artifacts = await loadSelectableAccessibilityArtifacts({
    manifest,
    manifestRoot: directory,
    bundledIndex: index,
    bundledRoot: directory,
  });

  assert.deepEqual(artifacts, [{
    artifactId: "bundled-capital",
    sqliteSha256: hashBytes(sqliteBytes),
    searchableStationIds: ["station-a"],
    claims: [{
      stationId: "station-a",
      lineId: "line-a",
      facilityType: "ELEVATOR",
      domain: "STATION_FACILITY_EVIDENCE",
      evidenceKind: "VERIFIED_PRESENT",
      sourceId: "official-accessibility",
      sourceSnapshotId: "official-accessibility-20260728",
      providerRecordHash: hash("record"),
      evidenceHash: hash("evidence"),
    }, {
      claimId: "facility-a",
      stationId: "station-a",
      lineId: "",
      facilityType: "ELEVATOR",
      domain: "FACILITY",
      evidenceKind: "EXISTS",
      sourceId: "official-accessibility",
      sourceSnapshotId: "official-accessibility-20260728",
      providerRecordHash: hash("facility-record"),
      evidenceHash: hash("facility-evidence"),
    }, {
      claimId: "facility-without-provenance",
      stationId: "station-a",
      lineId: "",
      facilityType: "ESCALATOR",
      domain: "FACILITY",
      evidenceKind: "EXISTS",
      sourceId: "",
      sourceSnapshotId: "",
      providerRecordHash: "",
      evidenceHash: "",
    }, {
      claimId: "edge-entry-a",
      stationId: "station-a",
      lineId: "line-a",
      facilityType: "ENTRY",
      domain: "NETWORK_EDGE",
      evidenceKind: "EXISTS",
      sourceId: "official-accessibility",
      sourceSnapshotId: "official-accessibility-20260728",
      providerRecordHash: hash("edge-record"),
      evidenceHash: hash("edge-evidence"),
    }, {
      claimId: "edge-without-provenance",
      stationId: "station-a",
      lineId: "line-a",
      facilityType: "EXIT",
      domain: "NETWORK_EDGE",
      evidenceKind: "EXISTS",
      sourceId: "",
      sourceSnapshotId: "",
      providerRecordHash: "",
      evidenceHash: "",
    }, {
      claimId: "internal-edge-without-provenance",
      stationId: "station-a",
      lineId: "line-a",
      facilityType: "WALK",
      domain: "NETWORK_EDGE",
      evidenceKind: "EXISTS",
      sourceId: "",
      sourceSnapshotId: "",
      providerRecordHash: "",
      evidenceHash: "",
    }],
  }]);
});

test("서로 다른 facility type의 위반은 고유 claim ID를 가진다", () => {
  const input = validInput();
  input.artifacts = [input.artifacts[0]];
  input.artifacts[0].claims = ["ELEVATOR", "ESCALATOR"].map((facilityType) => ({
    ...input.artifacts[0].claims[0],
    facilityType,
    sourceId: "",
  }));

  const report = buildAccessibilitySourceCoverageReport(input);

  assert.equal(new Set(report.violations.provenance).size, 2);
});

test("nullable Seoul line identity는 예외 대신 NO_GO로 판정한다", () => {
  const input = validInput();
  input.artifacts = [input.artifacts[0]];
  const claim = input.artifacts[0].claims[0];
  claim.lineId = null;
  claim.stationName = "사당";
  input.snapshots[0].artifactKind = "seoul-accessibility-snapshot";
  input.snapshots[0].stations = [{ stationName: "사당", lineName: "4호선", facilities: [] }];
  delete input.snapshots[0].claimBindings;

  const report = buildAccessibilitySourceCoverageReport(input);

  assert.equal(report.decision, "NO_GO");
  assert.ok(report.violations.provenance.some((violation) => violation.endsWith("CLAIM_SNAPSHOT_BINDING_MISMATCH")));
});

test("snapshot content에서 재계산할 수 없는 임의 claim hash는 NO_GO다", () => {
  const input = validInput();
  input.artifacts[0].claims[0].evidenceHash = hash("arbitrary-but-shaped");

  const report = buildAccessibilitySourceCoverageReport(input);

  assert.equal(report.decision, "NO_GO");
  assert.deepEqual(report.violations.provenance, [
    "bundled-capital:station-a|line-a|ELEVATOR|STATION_FACILITY_EVIDENCE:CLAIM_SNAPSHOT_BINDING_MISMATCH",
  ]);
});

test("Seoul snapshot에 존재하는 역·노선은 NOT_EXISTS로 위조할 수 없다", () => {
  const input = validInput();
  const sourceId = "seoul-metro-accessibility";
  const snapshotId = "seoul-metro-accessibility-20260728";
  const claim = input.artifacts[0].claims[0];
  input.artifacts = [input.artifacts[0]];
  Object.assign(claim, {
    stationId: "station-sadang",
    stationName: "사당",
    lineId: "seoul-4",
    evidenceKind: "NOT_EXISTS",
    sourceId,
    sourceSnapshotId: snapshotId,
  });
  claim.providerRecordHash = hash(JSON.stringify({
    stationId: claim.stationId,
    lineName: "4호선",
    status: "NOT_COVERED",
  }));
  claim.evidenceHash = hash(JSON.stringify({
    snapshotId,
    stationId: claim.stationId,
    lineId: claim.lineId,
    providerRecordHash: claim.providerRecordHash,
  }));
  Object.assign(input.inventory.sources[0], { id: sourceId });
  Object.assign(input.inventory.sources[0].accessibilityAdmissionEvidence, {
    snapshotId,
    absenceEvidenceMode: "EXHAUSTIVE_LIST",
  });
  Object.assign(input.snapshots[0], {
    artifactKind: "seoul-accessibility-snapshot",
    sourceId,
    snapshotId,
    stations: [{ stationName: "사당", lineName: "4호선", facilities: [] }],
  });
  delete input.snapshots[0].claimBindings;

  const report = buildAccessibilitySourceCoverageReport(input);

  assert.equal(report.decision, "NO_GO");
  assert.deepEqual(report.violations.provenance, [
    "bundled-capital:station-sadang|seoul-4|ELEVATOR|STATION_FACILITY_EVIDENCE:CLAIM_SNAPSHOT_BINDING_MISMATCH",
  ]);
});

for (const { name, mutate, partition, expected } of [
  {
    name: "expired snapshot",
    mutate: (input) => { input.sourceSnapshotPolicies[0].freshnessExpiresAt = EVALUATED_AT; },
    partition: "freshness",
    expected: "official-accessibility:SNAPSHOT_STALE",
  },
  {
    name: "missing redistribution permission",
    mutate: (input) => { input.inventory.sources[0].license.redistributionAllowed = false; },
    partition: "license",
    expected: "official-accessibility:LICENSE_NOT_REDISTRIBUTABLE",
  },
  {
    name: "snapshot digest mismatch",
    mutate: (input) => { input.snapshots[0].rawSha256 = hash("different-raw"); },
    partition: "snapshot",
    expected: "official-accessibility:SNAPSHOT_IDENTITY_MISMATCH",
  },
  {
    name: "snapshot file digest mismatch",
    mutate: (input) => { input.snapshots[0].snapshotFileSha256 = hash("different-file"); },
    partition: "snapshot",
    expected: "official-accessibility:SNAPSHOT_IDENTITY_MISMATCH",
  },
  {
    name: "snapshot policy identity mismatch",
    mutate: (input) => { input.sourceSnapshotPolicies[0].snapshotId = "other-snapshot"; },
    partition: "snapshot",
    expected: "official-accessibility:SNAPSHOT_POLICY_MISMATCH",
  },
  {
    name: "claim provenance missing",
    mutate: (input) => { input.artifacts[0].claims[0].sourceId = ""; },
    partition: "provenance",
    expected: "bundled-capital:station-a|line-a|ELEVATOR|STATION_FACILITY_EVIDENCE:PROVENANCE_MISSING",
  },
  {
    name: "accessibility admission not approved",
    mutate: (input) => { input.inventory.sources[0].accessibilityAdmissionEvidence.decision = "PENDING"; },
    partition: "provenance",
    expected: "official-accessibility:ACCESSIBILITY_ADMISSION_NOT_APPROVED",
  },
  {
    name: "row absence without completeness evidence",
    mutate: (input) => {
      input.artifacts[0].claims[0].evidenceKind = "NOT_EXISTS";
      delete input.inventory.sources[0].accessibilityAdmissionEvidence.absenceEvidenceMode;
    },
    partition: "absenceEvidence",
    expected: "bundled-capital:station-a|line-a|ELEVATOR|STATION_FACILITY_EVIDENCE:ABSENCE_EVIDENCE_MISSING",
  },
  {
    name: "placeholder evidence hash",
    mutate: (input) => { input.artifacts[0].claims[0].evidenceHash = "a".repeat(64); },
    partition: "placeholder",
    expected: "bundled-capital:station-a|line-a|ELEVATOR|STATION_FACILITY_EVIDENCE:EVIDENCE_HASH_PLACEHOLDER",
  },
  {
    name: "duplicate artifact identity",
    mutate: (input) => { input.artifacts[1].artifactId = "bundled-capital"; },
    partition: "artifactIdentity",
    expected: "bundled-capital:DUPLICATE_ARTIFACT_ID",
  },
]) {
  test(`${name}는 ${partition} violation으로 NO_GO다`, () => {
    const input = validInput();
    mutate(input);

    const report = buildAccessibilitySourceCoverageReport(input);

    assert.equal(report.decision, "NO_GO");
    assert.deepEqual(report.violations[partition], [expected]);
  });
}

test("expired live admission remains valid while its locked snapshot policy is fresh", () => {
  const input = validInput();
  input.inventory.sources[0].accessibilityAdmissionEvidence.freshUntil = EVALUATED_AT;
  input.snapshots[0].freshUntil = EVALUATED_AT;

  const report = buildAccessibilitySourceCoverageReport(input);

  assert.equal(report.decision, "GO");
  assert.deepEqual(report.violations.freshness, []);
});

function validInput() {
  const rawSha256 = hash("raw-snapshot");
  const contentSha256 = hash("normalized-snapshot");
  const schemaFingerprint = hash("schema");
  const snapshotFileSha256 = hash("snapshot-file");
  const snapshotId = "official-accessibility-20260728";
  const sourceId = "official-accessibility";
  const claim = (stationId) => ({
    stationId,
    lineId: "line-a",
    facilityType: "ELEVATOR",
    domain: "STATION_FACILITY_EVIDENCE",
    evidenceKind: "VERIFIED_PRESENT",
    sourceId,
    sourceSnapshotId: snapshotId,
    providerRecordHash: hash(`${stationId}-record`),
    evidenceHash: hash(`${stationId}-evidence`),
  });
  return {
    evaluatedAt: EVALUATED_AT,
    artifacts: [
      {
        artifactId: "bundled-capital",
        sqliteSha256: hash("sqlite-a"),
        searchableStationIds: ["station-a"],
        claims: [claim("station-a")],
      },
      {
        artifactId: "remote-capital",
        sqliteSha256: hash("sqlite-b"),
        searchableStationIds: ["station-b"],
        claims: [claim("station-b")],
      },
    ],
    inventory: {
      sources: [{
        id: sourceId,
        productionUseAllowed: true,
        license: { redistributionAllowed: true, attribution: "공식 제공기관" },
        accessibilityAdmissionEvidence: {
          decision: "APPROVED",
          productionUseAllowed: true,
          snapshotId,
          snapshotPath: "tools/datapack/sources/official-accessibility-20260728.json",
          capturedAt: "2026-07-27T23:00:00.000Z",
          observedAt: "2026-07-27T23:00:00.000Z",
          freshUntil: "2026-07-29T23:00:00.000Z",
          rawSha256,
          contentSha256,
          schemaFingerprint,
          snapshotFileSha256,
          absenceEvidenceMode: "EXPLICIT_ZERO",
        },
      }],
    },
    snapshots: [{
      sourceId,
      snapshotId,
      snapshotPath: "tools/datapack/sources/official-accessibility-20260728.json",
      capturedAt: "2026-07-27T23:00:00.000Z",
      observedAt: "2026-07-27T23:00:00.000Z",
      freshUntil: "2026-07-29T23:00:00.000Z",
      rawSha256,
      contentSha256,
      schemaFingerprint,
      snapshotFileSha256,
      claimBindings: ["station-a", "station-b"].map((stationId) => ({
        stationId,
        lineId: "line-a",
        facilityType: "ELEVATOR",
        providerRecordHash: hash(`${stationId}-record`),
        evidenceHash: hash(`${stationId}-evidence`),
      })),
    }],
    sourceSnapshotPolicies: [{
      sourceId,
      snapshotId,
      snapshotStatus: "LOCKED",
      fetchStatus: "SUCCESS",
      schemaStatus: "PASS",
      licenseStatus: "PASS",
      freshnessExpiresAt: "2026-10-26T23:00:00.000Z",
    }],
  };
}

function emptyViolations() {
  return {
    freshness: [],
    license: [],
    provenance: [],
    snapshot: [],
    absenceEvidence: [],
    placeholder: [],
    artifactIdentity: [],
  };
}

function hash(value) {
  return createHash("sha256").update(value).digest("hex");
}

function hashBytes(value) {
  return createHash("sha256").update(value).digest("hex");
}
