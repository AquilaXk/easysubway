#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { validateBusanRouteMapPositionsSnapshot } from "./collect-busan-route-map-positions.mjs";

const SOURCE_ID = "busan-transportation-route-map-positions";
const TOPOLOGY_SOURCE_ID = "busan-transportation-route-topology";
const PACK_ID = "nationwide-busan-route-map";
const OPERATOR_ID = "busan-transportation";

export function materializeBusanRouteMapPositions({ baseFixture, snapshot, topologySnapshot, inventory, now = new Date() }) {
  validateBusanRouteMapPositionsSnapshot(snapshot);
  const source = requiredSource(inventory, snapshot, topologySnapshot, now);
  const fixture = structuredClone(baseFixture);
  const pack = fixture.packs?.[0];
  if (!pack || fixture.packs.length !== 1 || pack.artifactKind !== "production") {
    throw new Error("Busan route map positions require one cumulative production pack");
  }
  if (pack.sourceInventory.some(({ id }) => id === SOURCE_ID)) throw new Error(`${SOURCE_ID} already exists`);
  validateTopologyLineage(pack, snapshot, topologySnapshot);
  const stations = canonicalStations(pack, topologySnapshot);
  const byLine = Map.groupBy(snapshot.positions, ({ lineId }) => lineId);
  const rows = [];
  for (const lineId of snapshot.lineIds) {
    const linePositions = [...(byLine.get(lineId) ?? [])].sort(
      (left, right) => Number(left.stationCode) - Number(right.stationCode),
    );
    for (let index = 0; index < linePositions.length; index += 1) {
      const position = linePositions[index];
      const stationId = stations.get(`${lineId}:${position.stationCode}`);
      if (!stationId) throw new Error(`Busan route map canonical station scope missing: ${lineId}:${position.stationCode}`);
      const previous = linePositions[index - 1];
      const next = linePositions[index + 1];
      rows.push({
        stationId,
        lineId,
        region: "부산권",
        x: position.x,
        y: position.y,
        labelDx: position.labelDx,
        labelDy: position.labelDy,
        labelPolygon: structuredClone(position.labelPolygon),
        upPath: next ? segmentPath(next, position) : "",
        downPath: previous ? segmentPath(previous, position) : "",
        sourceId: SOURCE_ID,
        sourceName: "부산교통공사 사이버스테이션 노선도",
        sourceUrl: snapshot.sourceUrl,
        sourceSha256: snapshot.rawSha256,
        license: source.license.name,
        licenseStatus: "redistributable",
        commercialUseAllowed: true,
        attributionRequired: false,
        derivationKind: "OFFICIAL",
        provenanceKind: "OFFICIAL_SOURCE",
        sourceSnapshotId: source.routeMapAdmissionEvidence.snapshotId,
        providerRecordHash: sha256(JSON.stringify(position)),
        evidenceHash: snapshot.positionsSha256,
        sourceLabel: position.stationName,
        reviewedAt: snapshot.capturedAt,
        updatedAt: snapshot.capturedAt,
      });
    }
  }
  if (rows.length !== 114 || new Set(rows.map(({ stationId, lineId }) => `${stationId}:${lineId}`)).size !== 114) {
    throw new Error("Busan route map materialized row count mismatch");
  }

  pack.sourceInventory.push(packSource(source, snapshot));
  pack.routeMapPositions.push(...rows);
  pack.minimumTableRows = { ...pack.minimumTableRows, route_map_positions: pack.routeMapPositions.length };
  const version = source.routeMapAdmissionEvidence.snapshotId.slice(-8);
  pack.id = `${PACK_ID}-${materializedBusanRouteMapPackContentHash(pack, version)}`;
  pack.version = version;
  pack.url = `https://objectstorage.ap-seoul-1.oraclecloud.com/n/axvym6vk8g7i/b/easysubway-datapacks/o/catalog/${pack.id}-v${version}.sqlite.gz`;
  fixture.manifest.activePack = { id: pack.id, version };
  return fixture;
}

export function materializedBusanRouteMapPackContentHash(pack, version) {
  const content = { ...pack };
  delete content.id;
  delete content.version;
  delete content.url;
  return sha256(JSON.stringify({ version, content }));
}

function requiredSource(inventory, snapshot, topologySnapshot, now) {
  const source = inventory?.sources?.find(({ id }) => id === SOURCE_ID);
  const evidence = source?.routeMapAdmissionEvidence;
  const observedNow = now instanceof Date ? now.getTime() : Number.NaN;
  if (source?.productionUseAllowed !== true || source.license?.redistributionAllowed !== true
    || source.license.commercialUseAllowed !== true || source.license.derivativeWorkAllowed !== true
    || evidence?.issue !== 2379
    || evidence.materializer !== "tools/datapack/materialize-busan-route-map-positions.mjs"
    || evidence.verificationTest !== "tools/datapack/materialize-busan-route-map-positions.test.mjs"
    || evidence.snapshotId !== "busan-transportation-route-map-positions-20260720"
    || evidence.snapshotPath !== "tools/datapack/sources/busan-transportation-route-map-positions-20260720.json"
    || evidence.capturedAt !== snapshot.capturedAt || evidence.stationCount !== snapshot.stationCount
    || evidence.htmlSha256 !== snapshot.htmlSha256 || evidence.cssSha256 !== snapshot.cssSha256
    || evidence.rawSha256 !== snapshot.rawSha256 || evidence.positionsSha256 !== snapshot.positionsSha256
    || evidence.topologySourceId !== snapshot.topologySourceId
    || evidence.topologySnapshotId !== snapshot.topologySnapshotId
    || evidence.topologyContentSha256 !== snapshot.topologyContentSha256
    || !Number.isFinite(observedNow) || observedNow < Date.parse(snapshot.capturedAt)) {
    throw new Error(`${SOURCE_ID} inventory evidence does not match snapshot`);
  }
  if (topologySnapshot?.sourceId !== TOPOLOGY_SOURCE_ID
    || topologySnapshot.contentSha256 !== snapshot.topologyContentSha256
    || topologySnapshot.stationCount !== snapshot.stationCount
    || JSON.stringify(source.coverageScope) !== JSON.stringify({
      regionIds: ["busan"],
      operatorIds: [OPERATOR_ID],
      lineIds: snapshot.lineIds,
      sourceDomains: ["route_map_positions"],
    }) || JSON.stringify(source.fieldsProvided) !== JSON.stringify(snapshot.fieldsProvided)) {
    throw new Error(`${SOURCE_ID} topology or coverage scope mismatch`);
  }
  return source;
}

function validateTopologyLineage(pack, snapshot, topologySnapshot) {
  if (!pack.sourceInventory.some(({ id }) => id === TOPOLOGY_SOURCE_ID)
    || pack.networkEdges.filter(({ sourceId }) => sourceId === TOPOLOGY_SOURCE_ID).length !== 220
    || topologySnapshot.contentSha256 !== snapshot.topologyContentSha256) {
    throw new Error("Busan route map topology lineage mismatch");
  }
}

function canonicalStations(pack, topologySnapshot) {
  const expected = new Set(topologySnapshot.scope.map(({ lineId, stationCode }) => `${lineId}:${stationCode}`));
  const stations = new Map();
  for (const stationLine of pack.stationLines) {
    const key = `${stationLine.lineId}:${stationLine.stationCode}`;
    if (!expected.has(key)) continue;
    if (stations.has(key)) throw new Error(`Busan route map duplicate canonical station: ${key}`);
    stations.set(key, stationLine.stationId);
  }
  if (stations.size !== 114) throw new Error(`Busan route map canonical station scope mismatch: ${stations.size}`);
  return stations;
}

function packSource(source, snapshot) {
  return {
    id: source.id,
    owner: source.owner,
    url: source.datasetUrl,
    sourceSha256: snapshot.rawSha256,
    license: source.license.name,
    licenseStatus: "redistributable",
    redistributionAllowed: true,
    updateFrequency: source.updateFrequency,
    updatedAt: snapshot.capturedAt,
    fields: [...source.fieldsProvided],
    coverageScope: structuredClone(source.coverageScope),
  };
}

function segmentPath(from, to) {
  return `M ${from.x} ${from.y} L ${to.x} ${to.y}`;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function parseArgs(argv) {
  const expected = ["--base-fixture", "--snapshot", "--topology-snapshot", "--inventory", "--output"];
  if (argv.length !== expected.length * 2 || expected.some((flag, index) => argv[index * 2] !== flag)
    || !path.isAbsolute(argv.at(-1))) {
    throw new Error("usage: materialize-busan-route-map-positions.mjs --base-fixture <json> --snapshot <json> --topology-snapshot <json> --inventory <json> --output <absolute.json>");
  }
  return Object.fromEntries(expected.map((flag, index) => [flag.slice(2), argv[index * 2 + 1]]));
}

async function main(argv) {
  const args = parseArgs(argv);
  const [baseFixture, snapshot, topologySnapshot, inventory] = await Promise.all([
    readFile(args["base-fixture"], "utf8").then(JSON.parse),
    readFile(args.snapshot, "utf8").then(JSON.parse),
    readFile(args["topology-snapshot"], "utf8").then(JSON.parse),
    readFile(args.inventory, "utf8").then(JSON.parse),
  ]);
  const fixture = materializeBusanRouteMapPositions({ baseFixture, snapshot, topologySnapshot, inventory });
  await writeFile(args.output, `${JSON.stringify(fixture, null, 2)}\n`);
  console.log(`Busan route map positions materialized: stations=${snapshot.stationCount}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    await main(process.argv.slice(2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Busan route map position materialization failed");
    process.exitCode = 1;
  }
}
