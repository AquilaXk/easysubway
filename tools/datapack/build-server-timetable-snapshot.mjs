#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync, gzipSync } from "node:zlib";

import { buildBackendTimetableSeed } from "./build-backend-timetable-seed.mjs";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const ARTIFACT_KIND = "server-timetable-snapshot-evidence";
const SCHEMA_IDENTITY = "backend-timetable-snapshot-v1";

export function buildServerTimetableSnapshot({
  baselineGzipBytes,
  contractBytes,
  sourceBytes,
  completenessBytes,
  buildNow = new Date(),
}) {
  const baselineSql = normalizeBaselineSql(baselineGzipBytes);
  const contract = parseJson(contractBytes, "coverage contract");
  const source = parseJson(sourceBytes, "source artifact");
  const completeness = parseJson(completenessBytes, "completeness evidence");
  const canonicalPackIdentity = validateAdmission({
    contract,
    source,
    sourceBytes,
    completeness,
    completenessBytes,
    buildNow,
  });
  const existingCalendarIds = insertedIds(baselineSql, "service_calendars");
  const sortedTrips = [...source.transitTrips]
    .map((trip) => ({ ...trip, serviceClass: "ITX_CHEONGCHUN" }))
    .sort((left, right) => left.id.localeCompare(right.id));
  const sortedStopTimes = [...source.transitStopTimes]
    .sort((left, right) => left.tripId.localeCompare(right.tripId)
      || left.stopSequence - right.stopSequence);
  const routeServiceArtifactEvidence = [{
    serviceClass: "ITX_CHEONGCHUN",
    timetableArtifactId: source.artifactId,
    timetableArtifactSha256: sha256(sourceBytes),
    canonicalPackId: canonicalPackIdentity.id,
    canonicalPackSha256: canonicalPackIdentity.sha256,
    canonicalPackSqliteSha256: canonicalPackIdentity.sqliteSha256,
    admissionStatus: "ADMITTED",
    admissionEligible: true,
    freshUntil: source.freshUntil,
    sourceIssue: 2135,
  }];
  const itxSeed = buildBackendTimetableSeed({
    ...source,
    transitTrips: sortedTrips,
    transitStopTimes: sortedStopTimes,
    routeServiceArtifactEvidence,
  }, {
    includeFeedInfo: false,
    excludeServiceCalendarIds: existingCalendarIds,
    startDate: earliestServiceDate(source.selectedServiceDates),
    endDate: latestServiceDate(source.selectedServiceDates),
    buildNow,
    timetableArtifactSha256: sha256(sourceBytes),
    canonicalPackIdentity,
  });
  assertNoIdentityCollisions(baselineSql, itxSeed);
  const sql = `${baselineSql}${itxSeed.sql}`;
  const sqlBytes = Buffer.from(sql);
  const gzipBytes = gzipSync(sqlBytes, { level: 9, mtime: 0 });
  const snapshotSha256 = sha256(sqlBytes);
  const canonicalStationIds = canonicalStationSet(source);
  const canonicalStationSetHash = sha256(Buffer.from(JSON.stringify(canonicalStationIds)));
  const baselineCounts = statementCounts(baselineSql);
  const evidenceWithoutHash = {
    schemaVersion: 1,
    artifactKind: ARTIFACT_KIND,
    schemaIdentity: SCHEMA_IDENTITY,
    snapshotId: `server-timetable-snapshot-${snapshotSha256.slice(0, 16)}`,
    snapshotSha256,
    snapshotSqlByteSize: sqlBytes.length,
    snapshotGzipSha256: sha256(gzipBytes),
    snapshotGzipByteSize: gzipBytes.length,
    freshUntil: source.freshUntil,
    sourceArtifact: {
      id: source.artifactId,
      sha256: sha256(sourceBytes),
      completenessEvidenceSha256: sha256(completenessBytes),
    },
    canonicalPackIdentity,
    canonicalStationSet: {
      version: `sha256:${canonicalStationSetHash}`,
      sha256: canonicalStationSetHash,
      memberCount: canonicalStationIds.length,
    },
    sourceLineageSha256: sha256(Buffer.from(JSON.stringify(
      [...source.sourceLineage].sort((left, right) => left.dayCd.localeCompare(right.dayCd)),
    ))),
    rowCounts: {
      calendars: baselineCounts.calendars + itxSeed.calendars.length,
      routes: baselineCounts.routes + itxSeed.routes.length,
      trips: baselineCounts.trips + itxSeed.tripCount,
      stopTimes: baselineCounts.stopTimes + itxSeed.stopTimeCount,
      subwayTrips: baselineCounts.trips,
      subwayStopTimes: baselineCounts.stopTimes,
      itxTrips: itxSeed.tripCount,
      itxStopTimes: itxSeed.stopTimeCount,
      routeServiceEvidence: 1,
    },
  };
  const evidence = {
    ...evidenceWithoutHash,
    evidenceHash: sha256(Buffer.from(JSON.stringify(evidenceWithoutHash))),
  };
  return {
    sql,
    gzipBytes,
    evidence,
    evidenceBytes: Buffer.from(`${JSON.stringify(evidence, null, 2)}\n`),
  };
}

function validateAdmission({
  contract,
  source,
  sourceBytes,
  completeness,
  completenessBytes,
  buildNow,
}) {
  const reference = contract?.sourceTimetableArtifact;
  if (contract?.schemaVersion !== 2
    || contract.artifactKind !== "itx-cheongchun-coverage-contract"
    || contract.serviceId !== "ITX_CHEONGCHUN"
    || !contract.allowedConsumerIssues?.includes("#2145")
    || reference?.status !== "ADMITTED"
    || reference.admissionEligible !== true
    || reference.schemaVersion !== 1) {
    throw new Error("#2145 requires the canonical #2135 ADMITTED source contract");
  }
  if (reference.sha256 !== sha256(sourceBytes)) {
    throw new Error("source artifact SHA-256 mismatch");
  }
  if (reference.completenessEvidenceSha256 !== sha256(completenessBytes)) {
    throw new Error("completeness evidence SHA-256 mismatch");
  }
  const { evidenceHash: sourceEvidenceHash, ...sourceWithoutEvidenceHash } = source;
  const { evidenceHash: completenessEvidenceHash, ...completenessWithoutEvidenceHash } = completeness;
  if (source?.schemaVersion !== 1
    || source.artifactKind !== "itx-cheongchun-source-timetable"
    || source.artifactId !== reference.artifactId
    || source.serviceId !== "ITX_CHEONGCHUN"
    || source.validationStatus !== "SUPPORTED"
    || source.freshUntil !== reference.freshUntil
    || source.completenessEvidenceSha256 !== reference.completenessEvidenceSha256
    || sourceEvidenceHash !== sha256(Buffer.from(JSON.stringify(sourceWithoutEvidenceHash)))) {
    throw new Error("source artifact schema or lineage mismatch");
  }
  if (completeness?.schemaVersion !== 2
    || completeness.artifactKind !== "korail-itx-cheongchun-completeness-evidence"
    || completeness.serviceId !== "ITX_CHEONGCHUN"
    || completeness.validationStatus !== "SUPPORTED"
    || completeness.materialization?.status !== "SUPPORTED"
    || completeness.credentialRedacted !== true
    || completenessEvidenceHash !== sha256(Buffer.from(JSON.stringify(completenessWithoutEvidenceHash)))) {
    throw new Error("completeness evidence schema or lineage mismatch");
  }
  const freshUntil = Date.parse(source.freshUntil);
  if (!Number.isFinite(freshUntil) || freshUntil <= buildNow.getTime()) {
    throw new Error("source artifact is stale");
  }
  if (!Array.isArray(source.transitTrips) || source.transitTrips.length === 0
    || !Array.isArray(source.transitStopTimes) || source.transitStopTimes.length === 0
    || !Array.isArray(source.sourceLineage) || source.sourceLineage.length !== 3) {
    throw new Error("source artifact must contain complete timetable and lineage rows");
  }
  const canonical = contract?.officialEvidence?.korailCompletenessAdmission?.canonicalPackIdentity;
  if (canonical?.id !== "capital"
    || !lowercaseSha(canonical.sha256)
    || !lowercaseSha(canonical.sqliteSha256)
    || source.canonicalPackIdentity?.sha256 !== canonical.sha256) {
    throw new Error("canonical pack identity mismatch");
  }
  return { id: canonical.id, sha256: canonical.sha256, sqliteSha256: canonical.sqliteSha256 };
}

function normalizeBaselineSql(baselineGzipBytes) {
  let sql;
  try {
    sql = gunzipSync(baselineGzipBytes).toString("utf8");
  } catch {
    throw new Error("subway baseline must be gzip-compressed SQL");
  }
  const statements = sql.lines ? sql.lines() : sql.split(/\r?\n/);
  const normalized = statements.map((line) => line.trim()).filter(Boolean);
  if (normalized.length === 0 || normalized.some((line) => !line.endsWith(";"))) {
    throw new Error("subway baseline must contain one complete SQL statement per line");
  }
  const value = `${normalized.join("\n")}\n`;
  if (/ITX_CHEONGCHUN|route_service_artifact_evidence/.test(value)) {
    throw new Error("subway baseline must not contain additive ITX rows or evidence");
  }
  return value;
}

function assertNoIdentityCollisions(baselineSql, itxSeed) {
  const baselineRoutes = insertedIds(baselineSql, "transit_routes");
  const baselineTrips = insertedIds(baselineSql, "transit_trips");
  for (const route of itxSeed.routes) {
    if (baselineRoutes.has(route.id)) throw new Error(`complete seed duplicate route id: ${route.id}`);
  }
  for (const statement of itxSeed.statements.filter((value) => value.startsWith("INSERT INTO transit_trips"))) {
    const [tripId] = values(statement);
    if (baselineTrips.has(tripId)) throw new Error(`complete seed duplicate trip id: ${tripId}`);
  }
}

function statementCounts(sql) {
  const count = (table) => (sql.match(new RegExp(`INSERT INTO ${table} \\(`, "g")) ?? []).length;
  return {
    calendars: count("service_calendars"),
    routes: count("transit_routes"),
    trips: count("transit_trips"),
    stopTimes: count("transit_stop_times"),
  };
}

function insertedIds(sql, table) {
  const ids = new Set();
  for (const line of sql.split("\n").filter((value) => value.startsWith(`INSERT INTO ${table} `))) {
    ids.add(values(line)[0]);
  }
  return ids;
}

function values(statement) {
  const marker = " VALUES (";
  const start = statement.indexOf(marker);
  if (start < 0 || !statement.endsWith(");")) throw new Error("unsupported seed statement shape");
  const input = statement.slice(start + marker.length, -2);
  const result = [];
  let token = "";
  let quoted = false;
  for (let index = 0; index < input.length; index += 1) {
    const character = input[index];
    if (character === "'") {
      if (quoted && input[index + 1] === "'") {
        token += "'";
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === "," && !quoted) {
      result.push(token.trim());
      token = "";
    } else {
      token += character;
    }
  }
  if (quoted) throw new Error("unterminated SQL string");
  result.push(token.trim());
  return result;
}

function canonicalStationSet(source) {
  return [...new Set(source.stationRosters.flatMap(({ stations }) => stations)
    .map(({ canonicalStationId, lineId }) => `${canonicalStationId}:${lineId}`))].sort();
}

function earliestServiceDate(selectedServiceDates) {
  return Object.values(selectedServiceDates).sort()[0];
}

function latestServiceDate(selectedServiceDates) {
  return Object.values(selectedServiceDates).sort().at(-1);
}

function parseJson(bytes, label) {
  try {
    return JSON.parse(bytes);
  } catch (error) {
    throw new Error(`${label} must be valid JSON`, { cause: error });
  }
}

function lowercaseSha(value) {
  return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const baselinePath = path.resolve(root, args.baseline
    ?? "backend/src/main/resources/timetable/line4-subway-timetable-seed.sql.gz");
  const contractPath = path.resolve(root, args.contract
    ?? "tools/datapack/itx-cheongchun-coverage-contract.json");
  const outputPath = path.resolve(root, args.output
    ?? "backend/src/main/resources/timetable/line4-timetable-seed.sql.gz");
  const evidencePath = path.resolve(root, args.evidence
    ?? "tools/datapack/server-timetable-snapshot-evidence.json");
  const contractBytes = await readFile(contractPath);
  const contract = parseJson(contractBytes, "coverage contract");
  const result = buildServerTimetableSnapshot({
    baselineGzipBytes: await readFile(baselinePath),
    contractBytes,
    sourceBytes: await readFile(path.resolve(root, contract.sourceTimetableArtifact.artifactPath)),
    completenessBytes: await readFile(path.resolve(
      root,
      contract.sourceTimetableArtifact.completenessEvidencePath,
    )),
    buildNow: buildClock(),
  });
  if (args.check) {
    const [storedSnapshot, storedEvidence] = await Promise.all([
      readFile(outputPath),
      readFile(evidencePath),
    ]);
    if (!storedSnapshot.equals(result.gzipBytes) || !storedEvidence.equals(result.evidenceBytes)) {
      throw new Error("server timetable snapshot is stale");
    }
  } else {
    await Promise.all([
      writeFile(outputPath, result.gzipBytes),
      writeFile(evidencePath, result.evidenceBytes),
    ]);
  }
  process.stdout.write(`${JSON.stringify({
    snapshotId: result.evidence.snapshotId,
    snapshotSha256: result.evidence.snapshotSha256,
    rowCounts: result.evidence.rowCounts,
  }, null, 2)}\n`);
}

function buildClock() {
  const value = process.env.EASYSUBWAY_TIMETABLE_SNAPSHOT_BUILD_NOW;
  if (value == null) return new Date();
  if (!value.endsWith("Z")) throw new Error("EASYSUBWAY_TIMETABLE_SNAPSHOT_BUILD_NOW must be UTC ISO-8601");
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error("EASYSUBWAY_TIMETABLE_SNAPSHOT_BUILD_NOW must be UTC ISO-8601");
  return date;
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (flag === "--check") {
      args.check = true;
      continue;
    }
    if (!flag.startsWith("--") || argv[index + 1] == null || argv[index + 1].startsWith("--")) {
      throw new Error(`invalid argument: ${flag}`);
    }
    args[flag.slice(2)] = argv[index + 1];
    index += 1;
  }
  return args;
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
