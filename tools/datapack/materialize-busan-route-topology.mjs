#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { admitBusanRouteTopology } from "./collect-busan-route-topology.mjs";

const SOURCE_ID = "busan-transportation-route-topology";
const OPERATOR_ID = "busan-transportation";
const PACK_ID = "nationwide-busan-topology";
const LINE_METADATA = new Map([
  ["line-ab1a041f6266", { nameKo: "부산 1호선", color: "#f06a00" }],
  ["line-d74614a04530", { nameKo: "부산 3호선", color: "#bb8c00" }],
  ["line-d812a5bc1e5f", { nameKo: "부산 4호선", color: "#217dc1" }],
  ["line-eb7b47920390", { nameKo: "부산 2호선", color: "#81bf48" }],
]);

export function materializeBusanRouteTopology({ baseFixture, snapshot, inventory, now = new Date() }) {
  admitBusanRouteTopology(snapshot, { now });
  const source = requiredSource(inventory, snapshot);
  const fixture = structuredClone(baseFixture);
  if (!Array.isArray(fixture.packs) || fixture.packs.length !== 1 || fixture.packs[0].artifactKind !== "production") {
    throw new Error("base fixture must contain exactly one production pack");
  }

  const pack = fixture.packs[0];
  const version = /-(\d{8})$/.exec(source.topologyAdmissionEvidence.snapshotId)?.[1];
  if (!version) throw new Error(`${SOURCE_ID} snapshotId must end with YYYYMMDD`);
  pack.id = PACK_ID;
  pack.version = version;
  pack.url = `https://objectstorage.ap-seoul-1.oraclecloud.com/n/axvym6vk8g7i/b/easysubway-datapacks/o/catalog/${PACK_ID}-v${version}.sqlite.gz`;
  fixture.manifest.activePack = { id: pack.id, version: pack.version };
  fixture.manifest.releaseSequence = Number(version);
  fixture.manifest.publishedAt = snapshot.capturedAt;
  fixture.manifest.expiresAt = snapshot.freshUntil;

  if (pack.sourceInventory.some(({ id }) => id === SOURCE_ID)) {
    throw new Error(`${SOURCE_ID} already exists in base fixture`);
  }
  pack.sourceInventory.push(packSource(source, snapshot));
  pack.operators.push({ id: OPERATOR_ID, nameKo: "부산교통공사", nameEn: "Busan Transportation Corporation" });
  pack.lines.push(...snapshot.lineIds.map((lineId) => {
    const metadata = LINE_METADATA.get(lineId);
    if (!metadata) throw new Error(`unsupported Busan line: ${lineId}`);
    return { id: lineId, operatorId: OPERATOR_ID, nameKo: metadata.nameKo, nameEn: "", color: metadata.color };
  }));

  const scopeByKey = new Map();
  const stationById = new Map();
  const stationLines = [];
  for (const lineId of snapshot.lineIds) {
    const lineScope = snapshot.scope
      .filter((station) => station.lineId === lineId)
      .sort((left, right) => Number(left.stationCode) - Number(right.stationCode));
    lineScope.forEach((station, index) => {
      const key = `${lineId}:${station.stationCode}`;
      if (scopeByKey.has(key)) throw new Error(`duplicate Busan station scope: ${key}`);
      const stationId = stationIdFor(station.stationName);
      scopeByKey.set(key, { ...station, stationId });
      stationById.set(stationId, {
        id: stationId,
        nameKo: station.stationName,
        nameEn: "",
        normalizedName: station.stationName.normalize("NFKC"),
        region: "부산권",
        latitude: null,
        longitude: null,
        dataQualityLevel: "LEVEL_2",
        dataSourceType: "OFFICIAL_API",
        sourceId: SOURCE_ID,
        derivationKind: "OFFICIAL",
        lastVerifiedAt: snapshot.capturedAt,
      });
      stationLines.push({
        stationId,
        lineId,
        stationCode: station.stationCode,
        lineSequence: index + 1,
        platformInfo: "",
        sourceId: SOURCE_ID,
        derivationKind: "OFFICIAL",
        lastVerifiedAt: snapshot.capturedAt,
      });
    });
  }

  const snapshotId = source.topologyAdmissionEvidence.snapshotId;
  const networkEdges = snapshot.edges.map((edge) => {
    const from = scopeByKey.get(`${edge.lineId}:${edge.fromStationCode}`);
    const to = scopeByKey.get(`${edge.lineId}:${edge.toStationCode}`);
    if (!from || !to) throw new Error(`Busan edge station scope missing: ${edge.edgeId}`);
    return {
      id: `edge-${edge.edgeId.replaceAll(":", "-")}`,
      fromNodeId: `${from.stationId}:${edge.lineId}`,
      toNodeId: `${to.stationId}:${edge.lineId}`,
      durationSeconds: edge.durationSeconds,
      distanceMeters: edge.distanceMeters,
      edgeType: "RIDE",
      servicePattern: "LOCAL",
      serviceClass: "SUBWAY",
      includesStairs: false,
      stairAccessState: "UNKNOWN",
      accessibilityStatus: "UNKNOWN",
      reliabilityScore: 100,
      sourceId: SOURCE_ID,
      sourceSnapshotId: snapshotId,
      providerRecordHash: sha256(JSON.stringify(edge)),
      provenanceKind: "OFFICIAL_SOURCE",
      derivationKind: "OFFICIAL",
      verificationStatus: "VERIFIED",
      lastVerifiedAt: snapshot.capturedAt,
      evidenceHash: snapshot.contentSha256,
    };
  });

  pack.stations.push(...stationById.values());
  pack.stationLines.push(...stationLines);
  pack.networkEdges.push(...networkEdges);
  pack.minimumTableRows = {
    ...pack.minimumTableRows,
    stations: pack.stations.length,
    station_lines: pack.stationLines.length,
    network_edges: pack.networkEdges.length,
  };
  return fixture;
}

function requiredSource(inventory, snapshot) {
  const source = inventory?.sources?.find(({ id }) => id === SOURCE_ID);
  if (!source || source.productionUseAllowed !== true || source.license?.redistributionAllowed !== true) {
    throw new Error(`${SOURCE_ID} is not admitted for production use`);
  }
  const evidence = source.topologyAdmissionEvidence;
  if (!evidence || evidence.contentSha256 !== snapshot.contentSha256 || evidence.rawSha256 !== snapshot.rawSha256
    || evidence.capturedAt !== snapshot.capturedAt || evidence.freshUntil !== snapshot.freshUntil
    || evidence.stationCount !== snapshot.stationCount || evidence.edgeCount !== snapshot.edgeCount
    || evidence.excludedTransferCount !== snapshot.excludedTransferCount) {
    throw new Error(`${SOURCE_ID} inventory evidence does not match snapshot`);
  }
  return source;
}

function packSource(source, snapshot) {
  return {
    id: source.id,
    owner: source.owner,
    url: source.datasetUrl,
    license: source.license.name,
    licenseStatus: "redistributable",
    redistributionAllowed: true,
    updateFrequency: source.updateFrequency,
    updatedAt: snapshot.capturedAt,
    fields: [...source.fieldsProvided],
    coverageScope: structuredClone(source.coverageScope),
  };
}

function stationIdFor(stationName) {
  return `station-${createHash("sha1").update(`부산권:${stationName.normalize("NFKC")}`).digest("hex").slice(0, 12)}`;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function parseArgs(argv) {
  if (argv.length !== 8 || argv[0] !== "--base-fixture" || argv[2] !== "--snapshot"
    || argv[4] !== "--inventory" || argv[6] !== "--output" || !path.isAbsolute(argv[7])) {
    throw new Error("usage: materialize-busan-route-topology.mjs --base-fixture <json> --snapshot <json> --inventory <json> --output <absolute.json>");
  }
  return { baseFixture: argv[1], snapshot: argv[3], inventory: argv[5], output: argv[7] };
}

async function main(argv) {
  const args = parseArgs(argv);
  const [baseFixture, snapshot, inventory] = await Promise.all([
    readFile(args.baseFixture, "utf8").then(JSON.parse),
    readFile(args.snapshot, "utf8").then(JSON.parse),
    readFile(args.inventory, "utf8").then(JSON.parse),
  ]);
  const fixture = materializeBusanRouteTopology({ baseFixture, snapshot, inventory });
  await writeFile(args.output, `${JSON.stringify(fixture, null, 2)}\n`);
  console.log(`Busan route topology materialized: stations=${snapshot.stationCount} edges=${snapshot.edgeCount}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error instanceof Error ? error.message : "Busan route topology materialization failed");
    process.exitCode = 1;
  });
}
