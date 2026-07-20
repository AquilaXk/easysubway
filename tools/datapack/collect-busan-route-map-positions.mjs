#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const SOURCE_ID = "busan-transportation-route-map-positions";
const SOURCE_URL = "https://www2.humetro.busan.kr/homepage/cyberstation/map.do";
const DATASET_URL = "https://www.data.go.kr/data/15054957/fileData.do";
const EXPECTED_LINE_STATION_COUNTS = Object.freeze({ "1": 40, "2": 43, "3": 17, "4": 14 });
const EXPECTED_STATION_COUNT = 114;

export function createBusanRouteMapPositionsSnapshot({ html, css, topology, capturedAt }) {
  if (!Buffer.isBuffer(html) || !Buffer.isBuffer(css)) {
    throw new Error("official Busan route map HTML/CSS bytes are required");
  }
  if (topology?.sourceId !== "busan-transportation-route-topology"
    || topology.stationCount !== EXPECTED_STATION_COUNT || topology.scope?.length !== EXPECTED_STATION_COUNT
    || !/^[a-f0-9]{64}$/.test(topology.contentSha256 ?? "")) {
    throw new Error("official Busan topology snapshot is required");
  }
  const capturedAtValue = new Date(capturedAt).toISOString();
  if (capturedAtValue !== capturedAt) throw new Error("capturedAt must be an ISO instant");

  const htmlStations = parseHtmlStations(html.toString("utf8"));
  const coordinates = parseCssPositions(css.toString("utf8"), /^\.s(\d+)$/);
  const labels = parseCssPositions(css.toString("utf8"), /^\.s(\d+) \.sta-title$/);
  const positions = topology.scope.map((station) => {
    const htmlStation = htmlStations.get(station.stationCode);
    const coordinate = coordinates.get(station.stationCode);
    if (!htmlStation || htmlStation.line !== lineFor(station.lineId)
      || normalizeStationName(htmlStation.stationName) !== normalizeStationName(station.stationName)) {
      throw new Error(`Busan route map station mismatch: ${station.lineId}:${station.stationCode}`);
    }
    if (!coordinate || coordinate.top == null || coordinate.left == null) {
      throw new Error(`Busan route map coordinate missing: ${station.stationCode}`);
    }
    const label = labels.get(station.stationCode) ?? {};
    const transfer = htmlStation.classNames.includes("trans");
    const position = {
      lineId: station.lineId,
      line: htmlStation.line,
      stationCode: station.stationCode,
      stationName: station.stationName,
      x: Math.round(coordinate.left + (transfer ? 12.5 : 5.5)),
      y: Math.round(coordinate.top + (transfer ? 13 : 5)),
      labelDx: Math.round((label.left ?? 13) - 5),
      labelDy: Math.round(label.top ?? 0),
    };
    return { ...position, labelPolygon: labelPolygonFor(position) };
  }).sort(comparePositions);

  const htmlSha256 = sha256(html);
  const cssSha256 = sha256(css);
  const snapshot = {
    schemaVersion: 1,
    artifactKind: "busan-route-map-positions-snapshot",
    sourceId: SOURCE_ID,
    official: true,
    fixture: false,
    credentialRedacted: true,
    sourceUrl: SOURCE_URL,
    datasetUrl: DATASET_URL,
    capturedAt,
    observedDataUpdatedAt: "2025-11-04",
    htmlSha256,
    cssSha256,
    rawSha256: sha256(JSON.stringify({ htmlSha256, cssSha256 })),
    topologySourceId: topology.sourceId,
    topologySnapshotId: "busan-transportation-route-topology-20260720",
    topologyContentSha256: topology.contentSha256,
    lineIds: [...new Set(positions.map(({ lineId }) => lineId))].sort(compareStrings),
    lineStationCounts: Object.fromEntries(Object.keys(EXPECTED_LINE_STATION_COUNTS).map((line) => [
      line,
      positions.filter((position) => position.line === line).length,
    ])),
    stationCount: positions.length,
    fieldsProvided: ["route_map_position", "route_map_label_polygon"],
    positionsSha256: sha256(JSON.stringify(positions)),
    positions,
  };
  return validateBusanRouteMapPositionsSnapshot(snapshot);
}

export function validateBusanRouteMapPositionsSnapshot(snapshot) {
  const positions = snapshot?.positions;
  const keys = new Set();
  const validPositions = Array.isArray(positions) && positions.length === EXPECTED_STATION_COUNT
    && positions.every((position) => {
      const key = `${position.lineId}:${position.stationCode}`;
      const valid = lineFor(position.lineId) === position.line
        && /^\d{2,3}$/.test(position.stationCode)
        && typeof position.stationName === "string" && position.stationName.length > 0
        && [position.x, position.y, position.labelDx, position.labelDy].every(Number.isInteger)
        && position.x >= 0 && position.x <= 1_680 && position.y >= 0 && position.y <= 980
        && Array.isArray(position.labelPolygon) && position.labelPolygon.length === 4
        && position.labelPolygon.every(({ x, y }) => Number.isInteger(x) && Number.isInteger(y) && x >= 0 && y >= 0)
        && !keys.has(key);
      keys.add(key);
      return valid;
    });
  if (snapshot?.schemaVersion !== 1 || snapshot.artifactKind !== "busan-route-map-positions-snapshot"
    || snapshot.sourceId !== SOURCE_ID || snapshot.official !== true || snapshot.fixture !== false
    || snapshot.credentialRedacted !== true || snapshot.sourceUrl !== SOURCE_URL
    || snapshot.datasetUrl !== DATASET_URL || Number.isNaN(Date.parse(snapshot.capturedAt))
    || snapshot.observedDataUpdatedAt !== "2025-11-04"
    || !/^[a-f0-9]{64}$/.test(snapshot.htmlSha256 ?? "")
    || !/^[a-f0-9]{64}$/.test(snapshot.cssSha256 ?? "")
    || snapshot.rawSha256 !== sha256(JSON.stringify({
      htmlSha256: snapshot.htmlSha256,
      cssSha256: snapshot.cssSha256,
    }))
    || snapshot.topologySourceId !== "busan-transportation-route-topology"
    || snapshot.topologySnapshotId !== "busan-transportation-route-topology-20260720"
    || !/^[a-f0-9]{64}$/.test(snapshot.topologyContentSha256 ?? "")
    || JSON.stringify(snapshot.lineIds) !== JSON.stringify([
      "line-ab1a041f6266", "line-d74614a04530", "line-d812a5bc1e5f", "line-eb7b47920390",
    ])
    || JSON.stringify(snapshot.lineStationCounts) !== JSON.stringify(EXPECTED_LINE_STATION_COUNTS)
    || snapshot.stationCount !== EXPECTED_STATION_COUNT
    || JSON.stringify(snapshot.fieldsProvided) !== JSON.stringify([
      "route_map_position", "route_map_label_polygon",
    ])
    || !validPositions || JSON.stringify([...positions].sort(comparePositions)) !== JSON.stringify(positions)
    || snapshot.positionsSha256 !== sha256(JSON.stringify(positions))) {
    throw new Error("invalid Busan route map positions snapshot");
  }
  return snapshot;
}

function parseHtmlStations(html) {
  const stations = new Map();
  const pattern = /<div class="([^"]*\bs(\d+)\b[^"]*)">\s*<a[^>]+one_point\('([^']+)',\s*'(\d+)',\s*'([^']+)'/g;
  let match;
  while ((match = pattern.exec(html)) !== null) {
    const [, className, classCode, stationCode, line, stationName] = match;
    if (classCode !== stationCode) throw new Error(`Busan route map station code mismatch: ${stationCode}`);
    if (stations.has(stationCode)) throw new Error(`Busan route map duplicate station: ${stationCode}`);
    stations.set(stationCode, { classNames: className.split(/\s+/), line, stationName });
  }
  return stations;
}

function parseCssPositions(css, selectorPattern) {
  const positions = new Map();
  const rulePattern = /([^{}]+)\{([^}]+)\}/g;
  let match;
  while ((match = rulePattern.exec(css)) !== null) {
    const selector = match[1].trim().split(/[\n,]/).at(-1).trim();
    const selectorMatch = selectorPattern.exec(selector);
    if (!selectorMatch) continue;
    const top = cssNumber(match[2], "top");
    const left = cssNumber(match[2], "left");
    if (top == null && left == null) continue;
    const stationCode = selectorMatch[1];
    if (positions.has(stationCode)) throw new Error(`Busan route map duplicate coordinate: ${stationCode}`);
    positions.set(stationCode, { top, left });
  }
  return positions;
}

function cssNumber(body, property) {
  const match = new RegExp(`${property}\\s*:\\s*(-?\\d+(?:\\.\\d+)?)px`).exec(body);
  return match ? Number(match[1]) : null;
}

function lineFor(lineId) {
  return {
    "line-ab1a041f6266": "1",
    "line-eb7b47920390": "2",
    "line-d74614a04530": "3",
    "line-d812a5bc1e5f": "4",
  }[lineId];
}

function normalizeStationName(value) {
  return String(value).normalize("NFKC").replace(/\s+/g, "").replace(/\([^()]*\)$/, "");
}

function labelPolygonFor(position) {
  const width = Math.max(32, [...normalizeStationName(position.stationName)].length * 13 + 12);
  const height = 22;
  const centerX = position.x + position.labelDx;
  const centerY = position.y + position.labelDy;
  const left = Math.max(0, Math.round(centerX - width / 2));
  const top = Math.max(0, Math.round(centerY - height / 2));
  const right = Math.max(0, Math.round(centerX + width / 2));
  const bottom = Math.max(0, Math.round(centerY + height / 2));
  return [
    { x: left, y: top },
    { x: right, y: top },
    { x: right, y: bottom },
    { x: left, y: bottom },
  ];
}

function comparePositions(left, right) {
  return compareStrings(left.lineId, right.lineId) || Number(left.stationCode) - Number(right.stationCode);
}

function compareStrings(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function parseArgs(argv) {
  const expected = ["--html", "--css", "--topology", "--captured-at", "--output"];
  if (argv.length !== expected.length * 2 || expected.some((flag, index) => argv[index * 2] !== flag)
    || !path.isAbsolute(argv.at(-1))) {
    throw new Error("usage: collect-busan-route-map-positions.mjs --html <path> --css <path> --topology <json> --captured-at <iso> --output <absolute.json>");
  }
  return Object.fromEntries(expected.map((flag, index) => [flag.slice(2), argv[index * 2 + 1]]));
}

async function main(argv) {
  const args = parseArgs(argv);
  const [html, css, topology] = await Promise.all([
    readFile(args.html),
    readFile(args.css),
    readFile(args.topology, "utf8").then(JSON.parse),
  ]);
  const snapshot = createBusanRouteMapPositionsSnapshot({
    html, css, topology, capturedAt: args["captured-at"],
  });
  await writeFile(args.output, `${JSON.stringify(snapshot)}\n`);
  console.log(`Busan route map positions collected: stations=${snapshot.stationCount}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    await main(process.argv.slice(2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : "Busan route map position collection failed");
    process.exitCode = 1;
  }
}
