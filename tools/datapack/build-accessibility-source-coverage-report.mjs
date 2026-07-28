#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { pathToFileURL } from "node:url";
import { gunzipSync } from "node:zlib";

const VIOLATION_KEYS = Object.freeze([
  "freshness",
  "license",
  "provenance",
  "snapshot",
  "absenceEvidence",
  "placeholder",
  "artifactIdentity",
]);
const ABSENCE_EVIDENCE_MODES = new Set(["EXPLICIT_ZERO", "EXHAUSTIVE_LIST"]);

export function buildAccessibilitySourceCoverageReport({
  artifacts,
  inventory,
  snapshots,
  evaluatedAt,
}) {
  const evaluatedMillis = Date.parse(evaluatedAt);
  if (!Number.isFinite(evaluatedMillis)) throw new TypeError("evaluatedAt must be an ISO instant");
  if (!Array.isArray(artifacts) || !Array.isArray(inventory?.sources) || !Array.isArray(snapshots)) {
    throw new TypeError("artifacts, inventory.sources, and snapshots must be arrays");
  }

  const violations = Object.fromEntries(VIOLATION_KEYS.map((key) => [key, []]));
  const sources = new Map(inventory.sources.map((source) => [source.id, source]));
  const snapshotsByIdentity = new Map(snapshots.map((snapshot) => [
    `${snapshot.sourceId}\0${snapshot.snapshotId}`,
    snapshot,
  ]));
  const artifactIds = new Set();
  const providerDomains = new Map();
  const referencedSourceIds = new Set(
    artifacts.flatMap((artifact) => artifact.claims ?? []).map((claim) => claim.sourceId).filter(Boolean),
  );

  for (const source of inventory.sources) {
    if (referencedSourceIds.has(source.id)) {
      validateSource(source, snapshotsByIdentity, evaluatedMillis, violations);
    }
  }

  for (const artifact of artifacts) {
    if (artifactIds.has(artifact.artifactId)) {
      violations.artifactIdentity.push(`${artifact.artifactId}:DUPLICATE_ARTIFACT_ID`);
    }
    artifactIds.add(artifact.artifactId);
    if (!sha256(artifact.sqliteSha256)) {
      violations.artifactIdentity.push(`${artifact.artifactId}:SQLITE_SHA256_INVALID`);
    }
    for (const claim of artifact.claims ?? []) {
      validateClaim(artifact, claim, sources, snapshotsByIdentity, violations);
      if (!claim.sourceId) continue;
      const key = `${claim.sourceId}\0${claim.domain}`;
      const entry = providerDomains.get(key) ?? {
        sourceId: claim.sourceId,
        domain: claim.domain,
        artifactIds: new Set(),
        claimCount: 0,
      };
      entry.artifactIds.add(artifact.artifactId);
      entry.claimCount += 1;
      providerDomains.set(key, entry);
    }
  }

  for (const values of Object.values(violations)) values.sort(compareStrings);
  const blockedSources = new Set(
    [violations.freshness, violations.license, violations.snapshot, violations.provenance]
      .flat()
      .filter((value) => value.split(":").length === 2)
      .map((value) => value.split(":", 1)[0]),
  );
  const providerDomainMatrix = [...providerDomains.values()]
    .map((entry) => ({
      sourceId: entry.sourceId,
      domain: entry.domain,
      artifactIds: [...entry.artifactIds].sort(compareStrings),
      claimCount: entry.claimCount,
      status: blockedSources.has(entry.sourceId) ? "BLOCKED" : "ADMITTED",
    }))
    .sort((left, right) => compareStrings(`${left.sourceId}\0${left.domain}`, `${right.sourceId}\0${right.domain}`));
  const artifactSummaries = artifacts
    .map((artifact) => ({
      artifactId: artifact.artifactId,
      sqliteSha256: artifact.sqliteSha256,
      searchableStationCount: new Set(artifact.searchableStationIds ?? []).size,
      claimCount: artifact.claims?.length ?? 0,
    }))
    .sort((left, right) => compareStrings(left.artifactId, right.artifactId));

  return {
    schemaVersion: 1,
    artifactKind: "accessibility-source-coverage-report",
    evaluatedAt,
    artifacts: artifactSummaries,
    providerDomainMatrix,
    violations,
    decision: Object.values(violations).every((values) => values.length === 0) ? "GO" : "NO_GO",
  };
}

export async function loadSelectableAccessibilityArtifacts({
  manifest,
  manifestRoot,
  bundledIndex,
  bundledRoot,
}) {
  const temporaryDirectory = await mkdtemp(path.join(tmpdir(), "easysubway-accessibility-source-report-"));
  try {
    const artifacts = [];
    const seenHashes = new Set();
    for (const [kind, document, root] of [
      ["bundled", bundledIndex, bundledRoot],
      ["manifest", manifest, manifestRoot],
    ]) {
      for (const pack of document?.packs ?? []) {
        const compressedPath = resolvePackPath(root, pack);
        const sqliteBytes = gunzipSync(await readFile(compressedPath));
        const sqliteSha256 = digest(sqliteBytes);
        if (sqliteSha256 !== pack.sqliteSha256) {
          throw new Error(`${kind}-${pack.id}:SQLITE_SHA256_MISMATCH`);
        }
        if (seenHashes.has(sqliteSha256)) continue;
        seenHashes.add(sqliteSha256);
        const sqlitePath = path.join(temporaryDirectory, `${artifacts.length}.sqlite`);
        await writeFile(sqlitePath, sqliteBytes);
        artifacts.push(readAccessibilityArtifact(sqlitePath, `${kind}-${pack.id}`, sqliteSha256));
      }
    }
    return artifacts;
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

export async function loadAccessibilityAdmissionSnapshots({ sources, referencedSourceIds, repositoryRoot }) {
  return Promise.all(sources.filter(({ id }) => referencedSourceIds.has(id)).map(async (source) => {
    const evidence = source.accessibilityAdmissionEvidence;
    if (!evidence?.snapshotPath) return { sourceId: source.id };
    const bytes = await readFile(path.resolve(repositoryRoot, evidence.snapshotPath));
    const snapshot = JSON.parse(bytes);
    return {
      ...snapshot,
      sourceId: snapshot.sourceId,
      snapshotPath: evidence.snapshotPath,
      snapshotFileSha256: digest(bytes),
    };
  }));
}

function readAccessibilityArtifact(sqlitePath, artifactId, sqliteSha256) {
  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  try {
    const stationNames = tableHasColumns(database, "stations", ["name_ko"])
      ? new Map(database.prepare("SELECT id, name_ko FROM stations").all().map(({ id, name_ko }) => [id, name_ko]))
      : new Map();
    const searchableStationIds = database.prepare(`
      SELECT DISTINCT stations.id
      FROM stations
      JOIN station_lines ON station_lines.station_id = stations.id
      ORDER BY stations.id
    `).all().map(({ id }) => id);
    const evidenceClaims = tableExists(database, "station_facility_evidence")
      ? database.prepare(`
          SELECT station_id, line_id, facility_type, evidence_kind, source_id, source_snapshot_id,
                 provider_record_hash, evidence_hash
          FROM station_facility_evidence
          ORDER BY station_id, line_id, facility_type
        `).all().map((row) => ({
          stationId: row.station_id,
          lineId: row.line_id,
          facilityType: row.facility_type,
          domain: "STATION_FACILITY_EVIDENCE",
          evidenceKind: row.evidence_kind,
          sourceId: row.source_id,
          sourceSnapshotId: row.source_snapshot_id,
          providerRecordHash: row.provider_record_hash,
          evidenceHash: row.evidence_hash,
        }))
      : [];
    const facilityClaims = tableExists(database, "facilities")
      ? database.prepare(tableHasColumns(database, "facilities", ["source_id", "source_snapshot_id", "provider_record_hash", "evidence_hash"])
        ? `
          SELECT id, station_id, type, source_id, source_snapshot_id,
                 provider_record_hash, evidence_hash
          FROM facilities
          WHERE source_id <> ''
          ORDER BY station_id, type, id
        `
        : `SELECT id, station_id, type, '' AS source_id, '' AS source_snapshot_id,
                  '' AS provider_record_hash, '' AS evidence_hash
           FROM facilities ORDER BY station_id, type, id`).all().map((row) => ({
          claimId: row.id,
          stationId: row.station_id,
          lineId: "",
          facilityType: row.type,
          domain: "FACILITY",
          evidenceKind: "EXISTS",
          sourceId: row.source_id,
          sourceSnapshotId: row.source_snapshot_id,
          providerRecordHash: row.provider_record_hash,
          evidenceHash: row.evidence_hash,
        }))
      : [];
    const edgeClaims = tableExists(database, "network_edges")
      ? database.prepare(tableHasColumns(database, "network_edges", ["source_id", "source_snapshot_id", "provider_record_hash", "evidence_hash"])
        ? `
          SELECT id, from_node_id, to_node_id, edge_type, accessibility_status,
                 source_id, source_snapshot_id, provider_record_hash, evidence_hash
          FROM network_edges
          WHERE source_id <> '' AND edge_type <> 'RIDE'
          ORDER BY id
        `
        : `SELECT id, from_node_id, to_node_id, edge_type, accessibility_status,
                  '' AS source_id, '' AS source_snapshot_id, '' AS provider_record_hash,
                  '' AS evidence_hash
           FROM network_edges WHERE edge_type <> 'RIDE' ORDER BY id`).all().map((row) => {
          const nodeId = [row.from_node_id, row.to_node_id].find((value) => String(value).includes(":"))
            ?? row.from_node_id;
          return {
            claimId: row.id,
            stationId: String(nodeId).split(":")[0],
            lineId: String(nodeId).split(":")[1] ?? "",
            facilityType: row.edge_type,
            domain: "NETWORK_EDGE",
            evidenceKind: row.accessibility_status === "NO_OFFICIAL_FEED" ? "NOT_EXISTS" : "EXISTS",
            sourceId: row.source_id,
            sourceSnapshotId: row.source_snapshot_id,
            providerRecordHash: row.provider_record_hash,
            evidenceHash: row.evidence_hash,
          };
        })
      : [];
    const claims = [...evidenceClaims, ...facilityClaims, ...edgeClaims].map((claim) => {
      const stationName = stationNames.get(claim.stationId);
      return stationName ? { ...claim, stationName } : claim;
    });
    return { artifactId, sqliteSha256, searchableStationIds, claims };
  } finally {
    database.close();
  }
}

function tableExists(database, table) {
  return Boolean(database.prepare("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(table));
}

function tableHasColumns(database, table, columns) {
  const available = new Set(database.prepare(`PRAGMA table_info(${table})`).all().map(({ name }) => name));
  return columns.every((column) => available.has(column));
}

function resolvePackPath(root, pack) {
  const relativePath = pack.asset ?? pack.path ?? localManifestAsset(pack.url);
  if (typeof relativePath !== "string" || relativePath === "") {
    throw new Error(`pack ${pack.id ?? "<unknown>"} has no local asset`);
  }
  return path.resolve(root, relativePath);
}

function localManifestAsset(url) {
  try {
    const name = path.basename(new URL(url).pathname);
    return name ? path.join("catalog", name) : undefined;
  } catch {
    return undefined;
  }
}

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function validateSource(source, snapshotsByIdentity, evaluatedMillis, violations) {
  const evidence = source.accessibilityAdmissionEvidence;
  if (source.productionUseAllowed !== true
    || source.license?.redistributionAllowed !== true
    || typeof source.license?.attribution !== "string"
    || source.license.attribution.trim() === "") {
    violations.license.push(`${source.id}:LICENSE_NOT_REDISTRIBUTABLE`);
  }
  if (!evidence) {
    violations.snapshot.push(`${source.id}:SNAPSHOT_IDENTITY_MISSING`);
    return;
  }
  if (evidence.decision !== "APPROVED" || evidence.productionUseAllowed !== true) {
    violations.provenance.push(`${source.id}:ACCESSIBILITY_ADMISSION_NOT_APPROVED`);
  }
  const capturedMillis = Date.parse(evidence.capturedAt);
  const observedMillis = Date.parse(evidence.observedAt);
  const freshUntilMillis = Date.parse(evidence.freshUntil);
  if (!Number.isFinite(capturedMillis)
    || !Number.isFinite(observedMillis)
    || !Number.isFinite(freshUntilMillis)
    || capturedMillis > evaluatedMillis
    || observedMillis > evaluatedMillis
    || evaluatedMillis >= freshUntilMillis) {
    violations.freshness.push(`${source.id}:SNAPSHOT_STALE`);
  }
  const snapshot = snapshotsByIdentity.get(`${source.id}\0${evidence.snapshotId}`);
  if (!snapshot || [
    "snapshotPath",
    "capturedAt",
    "observedAt",
    "freshUntil",
    "rawSha256",
    "contentSha256",
    "schemaFingerprint",
    "snapshotFileSha256",
  ].some((key) => snapshot[key] !== evidence[key])
    || !sha256(evidence.rawSha256)
    || !sha256(evidence.contentSha256)) {
    violations.snapshot.push(`${source.id}:SNAPSHOT_IDENTITY_MISMATCH`);
  }
}

function validateClaim(artifact, claim, sources, snapshotsByIdentity, violations) {
  const claimId = `${artifact.artifactId}:${claim.stationId}|${claim.lineId}|${claim.domain}`;
  const source = sources.get(claim.sourceId);
  const evidence = source?.accessibilityAdmissionEvidence;
  const provenanceMissing = !source
    || !claim.sourceId
    || claim.sourceSnapshotId !== evidence?.snapshotId
    || !sha256(claim.providerRecordHash)
    || !sha256(claim.evidenceHash);
  if (provenanceMissing) {
    violations.provenance.push(`${claimId}:PROVENANCE_MISSING`);
  } else {
    const snapshot = snapshotsByIdentity.get(`${claim.sourceId}\0${claim.sourceSnapshotId}`);
    if (!claimMatchesSnapshot(snapshot, claim)) {
      violations.provenance.push(`${claimId}:CLAIM_SNAPSHOT_BINDING_MISMATCH`);
    }
  }
  if (placeholderHash(claim.providerRecordHash) || placeholderHash(claim.evidenceHash)) {
    violations.placeholder.push(`${claimId}:EVIDENCE_HASH_PLACEHOLDER`);
  }
  if (claim.evidenceKind === "NOT_EXISTS"
    && !ABSENCE_EVIDENCE_MODES.has(evidence?.absenceEvidenceMode)) {
    violations.absenceEvidence.push(`${claimId}:ABSENCE_EVIDENCE_MISSING`);
  }
}

function claimMatchesSnapshot(snapshot, claim) {
  if (!snapshot) return false;
  if (Array.isArray(snapshot.claimBindings)) {
    return snapshot.claimBindings.some((binding) => [
      "stationId", "lineId", "facilityType", "providerRecordHash", "evidenceHash",
    ].every((field) => binding[field] === claim[field]));
  }
  if (snapshot.artifactKind === "kric-accessibility-snapshot") {
    const code = { ELEVATOR: "EV", ESCALATOR: "ES", WHEELCHAIR_LIFT: "WCLF" }[claim.facilityType];
    if (!code) return false;
    return (snapshot.queries ?? []).filter((query) => query.stationId === claim.stationId
      && (!claim.lineId || query.lineId === claim.lineId)).some((query) => {
      const tuple = { railOprIsttCd: query.railOprIsttCd, lnCd: query.lnCd, stinCd: query.stinCd };
      const rows = (query.rows ?? []).filter(({ gubun }) => gubun === code);
      if (rows.length > 0) return rows.some((row) => {
        const providerRecordHash = digest(JSON.stringify(row));
        return providerRecordHash === claim.providerRecordHash
          && digest(JSON.stringify({ snapshotId: snapshot.snapshotId, query: tuple, providerRecordHash })) === claim.evidenceHash;
      });
      return claim.evidenceKind === "NOT_EXISTS"
        && query.providerRecordHash === claim.providerRecordHash
        && digest(JSON.stringify({
          snapshotId: snapshot.snapshotId,
          query: tuple,
          type: claim.facilityType,
          evidenceKind: "NOT_EXISTS",
        })) === claim.evidenceHash;
    });
  }
  if (snapshot.artifactKind === "seoul-accessibility-snapshot") {
    const lineNumber = claim.lineId.match(/(\d+)$/)?.[1];
    const lineName = lineNumber ? `${lineNumber}호선` : null;
    const matchingStations = lineName && claim.stationName
      ? (snapshot.stations ?? []).filter((station) => normalizeStationName(station.stationName) === normalizeStationName(claim.stationName)
        && station.lineName === lineName)
      : [];
    const absentHash = lineNumber
      ? digest(JSON.stringify({ stationId: claim.stationId, lineName, status: "NOT_COVERED" }))
      : null;
    if (claim.evidenceKind === "NOT_EXISTS") {
      if (!claim.stationName || matchingStations.length > 0 || claim.providerRecordHash !== absentHash) return false;
    } else if (!matchingStations.some((station) => digest(JSON.stringify(station)) === claim.providerRecordHash)) {
      return false;
    }
    const expectedEvidenceHash = claim.domain === "NETWORK_EDGE"
      ? digest(JSON.stringify({
        edgeId: claim.claimId,
        sourceSnapshotId: snapshot.snapshotId,
        providerRecordHash: claim.providerRecordHash,
      }))
      : digest(JSON.stringify({
        snapshotId: snapshot.snapshotId,
        stationId: claim.stationId,
        lineId: claim.lineId,
        providerRecordHash: claim.providerRecordHash,
      }));
    return expectedEvidenceHash === claim.evidenceHash;
  }
  return false;
}

function normalizeStationName(value) {
  return String(value ?? "").normalize("NFKC").replace(/역$/u, "").replace(/[^\p{L}\p{N}]+/gu, "");
}

function sha256(value) {
  return typeof value === "string" && /^[0-9a-f]{64}$/.test(value);
}

function placeholderHash(value) {
  return typeof value === "string" && /^([0-9a-f])\1{63}$/.test(value);
}

function compareStrings(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

async function main(argv) {
  const args = parseArgs(argv);
  for (const name of ["manifest", "bundled-index", "inventory", "evaluation-at", "output"]) {
    if (!args[name]) throw new Error(`missing --${name}`);
  }
  const [manifest, bundledIndex, inventory] = await Promise.all([
    readJson(args.manifest),
    readJson(args["bundled-index"]),
    readJson(args.inventory),
  ]);
  const artifacts = await loadSelectableAccessibilityArtifacts({
    manifest,
    manifestRoot: args["manifest-root"] ?? packAssetRoot(args.manifest),
    bundledIndex,
    bundledRoot: args["bundled-root"] ?? packAssetRoot(args["bundled-index"]),
  });
  const referencedSourceIds = new Set(
    artifacts.flatMap(({ claims }) => claims).map(({ sourceId }) => sourceId).filter(Boolean),
  );
  const snapshots = await loadAccessibilityAdmissionSnapshots({
    sources: inventory.sources,
    referencedSourceIds,
    repositoryRoot: path.resolve(path.dirname(args.inventory), "../.."),
  });
  const report = buildAccessibilitySourceCoverageReport({
    artifacts,
    inventory,
    snapshots,
    evaluatedAt: args["evaluation-at"],
  });
  await mkdir(path.dirname(args.output), { recursive: true });
  await writeFile(args.output, `${JSON.stringify(report, null, 2)}\n`);
  if (report.decision !== "GO") process.exitCode = 1;
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    if (!name?.startsWith("--") || argv[index + 1] === undefined) throw new Error("invalid arguments");
    args[name.slice(2)] = argv[index + 1];
  }
  return args;
}

async function readJson(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

function packAssetRoot(indexPath) {
  return path.resolve(path.dirname(indexPath), "../..");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
