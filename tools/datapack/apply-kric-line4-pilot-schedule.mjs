#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const SOURCE_ID = "kric-subway-timetable";
const SOURCE_ARTIFACT_IDS = new Set([SOURCE_ID, "kric-subway-route-info"]);
const MEMBERSHIP_SOURCE_ID = "molit-urban-rail-full-route";
const ROUTE_MAP_SOURCE_ID = "easysubway-owner-route-map-capital";
const LINE_ID = "seoul-4";
const START_DATE = "20260101";
const END_DATE = "20261231";
const EXPECTED_REQUEST_COUNT = 153;
const EXPECTED_INTERMEDIATE_ROW_COUNT = 33062;
const EXPECTED_TRANSIT_TRIP_COUNT = 895;
const EXPECTED_TRANSIT_STOP_TIME_COUNT = 33062;
const EXPECTED_PILOT_TRANSIT_TRIP_COUNT = 466;
const EXPECTED_PILOT_TRANSIT_STOP_TIME_COUNT = 932;
const STATION_MAP = {
  "station-seoul-4-433": { stationId: "station-sadang", stationCode: "433", nameKo: "사당" },
  "station-seoul-4-448": { stationId: "station-sangnoksu", stationCode: "448", nameKo: "상록수" },
};
const CALENDAR_DAYS = {
  "weekday-kric": { monday: true, tuesday: true, wednesday: true, thursday: true, friday: true, saturday: false, sunday: false },
  "saturday-kric": { monday: false, tuesday: false, wednesday: false, thursday: false, friday: false, saturday: true, sunday: false },
  "holiday-kric": { monday: false, tuesday: false, wednesday: false, thursday: false, friday: false, saturday: true, sunday: true },
};
const WEEKDAY_HOLIDAY_DATES_2026 = [
  "20260101",
  "20260216",
  "20260217",
  "20260218",
  "20260302",
  "20260505",
  "20260525",
  "20260603",
  "20260817",
  "20260924",
  "20260925",
  "20261005",
  "20261009",
  "20261225",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const input = JSON.parse(await readFile(requireArg(args, "input"), "utf8"));
  const artifactBytes = await readFile(requireArg(args, "artifact"));
  const artifact = JSON.parse(artifactBytes.toString("utf8"));
  const outputPath = requireArg(args, "output");

  let transformed = applySchedule(input, artifact, artifactBytes);
  const rosterPath = args.get("roster");
  const geometryPath = args.get("geometry");
  if (rosterPath || geometryPath) {
    if (!rosterPath || !geometryPath) {
      throw new Error("--roster and --geometry must be provided together");
    }
    const roster = JSON.parse(await readFile(rosterPath, "utf8"));
    const geometry = JSON.parse(await readFile(geometryPath, "utf8"));
    transformed = applyLine4RoutingGraph(transformed, artifact, roster, geometry);
  }
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(transformed, null, 2)}\n`);
}

export function applySchedule(input, artifact, artifactBytes = Buffer.from(JSON.stringify(artifact))) {
  validateArtifact(artifact);
  const tripsById = new Map((artifact.transitTrips ?? []).map((trip) => [trip.id, trip]));
  const stopTimesByTrip = new Map();
  for (const stopTime of artifact.transitStopTimes ?? []) {
    if (!STATION_MAP[stopTime.stationId]) continue;
    const rows = stopTimesByTrip.get(stopTime.tripId) ?? [];
    rows.push(stopTime);
    stopTimesByTrip.set(stopTime.tripId, rows);
  }

  const transitTrips = [];
  const transitStopTimes = [];
  for (const [tripId, rows] of [...stopTimesByTrip.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    if (rows.length !== 2) continue;
    const trip = tripsById.get(tripId);
    if (!trip) continue;
    const ordered = rows.toSorted((left, right) => left.stopSequence - right.stopSequence);
    transitTrips.push({
      id: trip.id,
      routeId: trip.routeId,
      serviceId: trip.serviceId,
      tripHeadsign: STATION_MAP[ordered.at(-1).stationId].nameKo,
      directionId: trip.directionId,
      servicePattern: trip.servicePattern ?? "LOCAL",
    });
    ordered.forEach((row, index) => {
      transitStopTimes.push({
        tripId,
        stopSequence: index + 1,
        stationId: STATION_MAP[row.stationId].stationId,
        lineId: row.lineId,
        arrivalSeconds: row.arrivalSeconds,
        departureSeconds: row.departureSeconds,
      });
    });
  }
  if (transitTrips.length === 0) {
    throw new Error("KRIC pilot schedule has no paired Sangnoksu-Sadang trips");
  }
  requireEqual(transitTrips.length, EXPECTED_PILOT_TRANSIT_TRIP_COUNT, "pairedTransitTripCount");
  requireEqual(transitStopTimes.length, EXPECTED_PILOT_TRANSIT_STOP_TIME_COUNT, "pairedTransitStopTimeCount");

  const serviceCalendars = [...new Set(transitTrips.map((trip) => trip.serviceId))]
    .sort((left, right) => left.localeCompare(right))
    .map((serviceId) => ({ serviceId, ...requireCalendar(serviceId), startDate: START_DATE, endDate: END_DATE }));

  return {
    ...input,
    sourceIds: unique([...(input.sourceIds ?? []), SOURCE_ID]),
    stationMappings: uniqueBy(
      [
        ...(input.stationMappings ?? []),
        ...Object.values(STATION_MAP).map((station) => ({
          sourceId: SOURCE_ID,
          sourceStationCode: station.stationCode,
          lineId: LINE_ID,
          stationId: station.stationId,
          stationLineId: `${station.stationId}:${LINE_ID}`,
          mappingStatus: "active",
        })),
      ],
      (row) => `${row.sourceId}:${row.sourceStationCode}:${row.lineId}`,
    ),
    stationLineRows: uniqueBy(
      [
        ...(input.stationLineRows ?? []),
        ...Object.values(STATION_MAP).map((station) => ({
          ...stationLineTemplate(input, station.stationCode),
          sourceId: SOURCE_ID,
          sourceStationCode: station.stationCode,
          lastVerifiedAt: `${artifact.capturedAt ?? "2026-07-09"}T00:00:00.000Z`,
        })),
      ],
      (row) => `${row.sourceId}:${row.sourceStationCode}:${row.lineId}`,
    ),
    coverageEvidence: uniqueBy(
      [
        ...(input.coverageEvidence ?? []),
        {
          regionId: "capital",
          operatorId: "seoul-metro",
          sourceDomain: "schedule_timetable",
          sourceIds: [SOURCE_ID],
          evidence: "KRIC subwayTimetableExp 4호선 상록수-사당 pilot 수집 및 trip/stop sequence 재구성 evidence",
        },
      ],
      (row) => `${row.regionId}:${row.operatorId}:${row.sourceDomain}`,
    ),
    scheduleProvenance: {
      sourceId: SOURCE_ID,
      sourceSnapshotId: `kric-subway-timetable-snapshot-${String(artifact.capturedAt ?? "20260709").replaceAll("-", "")}`,
      providerRecordHash: sha256(artifactBytes),
      evidenceHash: sha256(`kric-line4-pilot-schedule:${sha256(artifactBytes)}`),
      retrievedAt: `${artifact.capturedAt ?? "2026-07-09"}T00:00:00.000Z`,
    },
    serviceCalendars,
    serviceCalendarDates: holidayExceptionDates(),
    transitRoutes: [
      {
        id: "route-seoul-4-up",
        lineId: LINE_ID,
        routeShortName: "4",
        routeLongName: "수도권 4호선 상록수 방면",
        directionName: "상록수 방면",
      },
      {
        id: "route-seoul-4-down",
        lineId: LINE_ID,
        routeShortName: "4",
        routeLongName: "수도권 4호선 사당 방면",
        directionName: "사당 방면",
      },
    ],
    transitTrips,
    transitStopTimes,
    transitFeedInfo: [{ feedEndDate: END_DATE }],
  };
}

export function applyLine4RoutingGraph(input, artifact, roster, geometry) {
  const stations = line4CorridorStations(roster);
  const stationByArtifactId = new Map(
    stations.map((station) => [`station-${LINE_ID}-${station.stinCd}`, corridorStation(station)]),
  );
  const stationById = new Map([...stationByArtifactId.values()].map((station) => [station.stationId, station]));
  const stopTimesByTrip = new Map();
  for (const stopTime of artifact.transitStopTimes ?? []) {
    if (!stationByArtifactId.has(stopTime.stationId)) continue;
    const rows = stopTimesByTrip.get(stopTime.tripId) ?? [];
    rows.push(stopTime);
    stopTimesByTrip.set(stopTime.tripId, rows);
  }
  const tripsById = new Map((artifact.transitTrips ?? []).map((trip) => [trip.id, trip]));
  const transitTrips = [];
  const transitStopTimes = [];
  for (const [tripId, rows] of [...stopTimesByTrip.entries()].sort(([left], [right]) => left.localeCompare(right))) {
    const ordered = rows.toSorted((left, right) => left.stopSequence - right.stopSequence);
    const mapped = ordered.map((row) => ({ row, station: stationByArtifactId.get(row.stationId) }));
    if (!isCompleteCorridorTrip(mapped, stations.length)) continue;
    const trip = tripsById.get(tripId);
    if (!trip) continue;
    transitTrips.push({
      ...trip,
      tripHeadsign: mapped.at(-1).station.nameKo,
      servicePattern: trip.servicePattern ?? "LOCAL",
    });
    mapped.forEach(({ row, station }, index) => {
      transitStopTimes.push({
        tripId,
        stopSequence: index + 1,
        stationId: station.stationId,
        lineId: LINE_ID,
        arrivalSeconds: row.arrivalSeconds,
        departureSeconds: row.departureSeconds,
      });
    });
  }
  if (transitTrips.length !== EXPECTED_PILOT_TRANSIT_TRIP_COUNT) {
    throw new Error(
      `KRIC line 4 routing graph trip count mismatch: ${transitTrips.length} !== ${EXPECTED_PILOT_TRANSIT_TRIP_COUNT}`,
    );
  }
  const expectedStopTimeCount = EXPECTED_PILOT_TRANSIT_TRIP_COUNT * stations.length;
  if (transitStopTimes.length !== expectedStopTimeCount) {
    throw new Error(
      `KRIC line 4 routing graph stop time count mismatch: ${transitStopTimes.length} !== ${expectedStopTimeCount}`,
    );
  }

  const verifiedAt = `${artifact.capturedAt ?? "2026-07-12"}T00:00:00.000Z`;
  const stationMappings = [
    ...(input.stationMappings ?? []).filter((row) => row.sourceId !== "seoulmetro-cyberstation-route-map"),
    ...stations.flatMap((station) => {
      const normalized = corridorStation(station);
      return [
        stationMapping(MEMBERSHIP_SOURCE_ID, `MOLIT-SEOUL-4-${station.stinCd}`, normalized),
        stationMapping(SOURCE_ID, station.stinCd, normalized),
        stationMapping(ROUTE_MAP_SOURCE_ID, `capital-v2:${station.stinNm}`, normalized),
      ];
    }),
  ];
  const stationLineRows = [
    ...(input.stationLineRows ?? []),
    ...stations.flatMap((station) => {
      const normalized = corridorStation(station);
      const existing = (input.stationLineRows ?? []).find((row) => row.stationCode === station.stinCd);
      const base = {
        lineId: LINE_ID,
        stationNameKo: station.stinNm,
        stationNameEn: existing?.stationNameEn ?? "",
        normalizedName: station.stinNm,
        region: "수도권",
        latitude: existing?.latitude ?? null,
        longitude: existing?.longitude ?? null,
        stationCode: station.stinCd,
        lineSequence: station.stinConsOrdr,
        platformInfo: existing?.platformInfo ?? "",
        lastVerifiedAt: verifiedAt,
      };
      return [
        { ...base, sourceId: MEMBERSHIP_SOURCE_ID, sourceStationCode: `MOLIT-SEOUL-4-${station.stinCd}` },
        { ...base, sourceId: SOURCE_ID, sourceStationCode: station.stinCd },
      ];
    }),
  ];
  const routeEdges = [
    ...(input.routeEdges ?? []).filter((edge) => edge.edgeType !== "RIDE"),
    ...corridorRideEdges(transitStopTimes, stationById, input.scheduleProvenance, verifiedAt),
  ];
  const routeMapPositions = corridorRouteMapPositions(stations, geometry, verifiedAt);
  const publicStationIds = new Set(input.supportedV1Scope?.includedStationIds ?? []);
  const transitPassThroughStationIds = stations
    .map((station) => corridorStation(station).stationId)
    .filter((stationId) => !publicStationIds.has(stationId));

  return {
    ...input,
    sourceIds: unique([
      ...(input.sourceIds ?? []).filter((sourceId) => sourceId !== "seoulmetro-cyberstation-route-map"),
      ROUTE_MAP_SOURCE_ID,
    ]),
    supportedV1Scope: {
      ...input.supportedV1Scope,
      transitPassThroughStationIds,
    },
    stationMappings: uniqueBy(
      stationMappings,
      (row) => `${row.sourceId}:${row.sourceStationCode}:${row.lineId}`,
    ),
    stationLineRows: uniqueBy(
      stationLineRows,
      (row) => `${row.sourceId}:${row.sourceStationCode}:${row.lineId}`,
    ),
    routeEdges,
    routeMapPositions,
    routeGraphTopologyPolicy: {
      ...(input.routeGraphTopologyPolicy ?? {}),
      summaryRideEdges: "fixture-only",
    },
    coverageEvidence: (input.coverageEvidence ?? []).map((entry) =>
      entry.sourceDomain === "route_map_positions"
        ? {
            ...entry,
            sourceIds: [ROUTE_MAP_SOURCE_ID],
            evidence: "오너 자작 수도권 v2 도식에서 추출한 구조화 station node·label polygon 좌표",
          }
        : entry,
    ),
    minimumProductionCoverage: {
      ...input.minimumProductionCoverage,
      stations: stations.length,
      stationLines: stations.length,
      routeEdges: routeEdges.length,
    },
    transitTrips,
    transitStopTimes,
  };
}

function line4CorridorStations(roster) {
  const rows = [...(roster?.stations ?? [])]
    .filter((station) => station.lnCd == null || String(station.lnCd) === "4")
    .sort((left, right) => left.stinConsOrdr - right.stinConsOrdr);
  const start = rows.findIndex((station) => station.stinCd === "433");
  const end = rows.findIndex((station) => station.stinCd === "448");
  if (start < 0 || end < start) {
    throw new Error("KRIC line 4 roster must contain ordered corridor endpoints 433..448");
  }
  const corridor = rows.slice(start, end + 1);
  if (corridor.some((station, index) => index > 0 && station.stinConsOrdr !== corridor[index - 1].stinConsOrdr + 1)) {
    throw new Error("KRIC line 4 corridor station sequence must be contiguous");
  }
  return corridor;
}

function corridorStation(station) {
  const endpoint = STATION_MAP[`station-${LINE_ID}-${station.stinCd}`];
  return {
    stationId: endpoint?.stationId ?? `station-${LINE_ID}-${station.stinCd}`,
    stationCode: station.stinCd,
    lineSequence: station.stinConsOrdr,
    nameKo: station.stinNm,
  };
}

function stationMapping(sourceId, sourceStationCode, station) {
  return {
    sourceId,
    sourceStationCode,
    lineId: LINE_ID,
    stationId: station.stationId,
    stationLineId: `${station.stationId}:${LINE_ID}`,
    mappingStatus: "active",
  };
}

function isCompleteCorridorTrip(mapped, expectedStationCount) {
  if (mapped.length !== expectedStationCount || new Set(mapped.map(({ station }) => station.stationId)).size !== expectedStationCount) {
    return false;
  }
  return mapped.every(
    ({ station }, index) => index === 0 || Math.abs(station.lineSequence - mapped[index - 1].station.lineSequence) === 1,
  );
}

function corridorRideEdges(stopTimes, stationById, scheduleProvenance, verifiedAt) {
  const byTrip = new Map();
  for (const stopTime of stopTimes) {
    const rows = byTrip.get(stopTime.tripId) ?? [];
    rows.push(stopTime);
    byTrip.set(stopTime.tripId, rows);
  }
  const samples = new Map();
  for (const rows of byTrip.values()) {
    const ordered = rows.toSorted((left, right) => left.stopSequence - right.stopSequence);
    for (let index = 0; index + 1 < ordered.length; index += 1) {
      const from = ordered[index];
      const to = ordered[index + 1];
      const seconds = to.arrivalSeconds - from.departureSeconds;
      if (seconds <= 0) continue;
      const key = `${from.stationId}|${to.stationId}`;
      const sample = samples.get(key) ?? { fromStationId: from.stationId, toStationId: to.stationId, durations: [] };
      sample.durations.push(seconds);
      samples.set(key, sample);
    }
  }
  const edges = [...samples.values()]
    .sort((left, right) => `${left.fromStationId}|${left.toStationId}`.localeCompare(`${right.fromStationId}|${right.toStationId}`))
    .map((sample) => {
      const from = stationById.get(sample.fromStationId);
      const to = stationById.get(sample.toStationId);
      if (!from || !to || Math.abs(from.lineSequence - to.lineSequence) !== 1) {
        throw new Error(`KRIC line 4 timetable segment is not adjacent: ${sample.fromStationId}->${sample.toStationId}`);
      }
      const direction = from.lineSequence < to.lineSequence ? "up" : "down";
      const providerRecordHash = sha256(JSON.stringify({
        fromStationId: from.stationId,
        toStationId: to.stationId,
        durations: sample.durations.toSorted((left, right) => left - right),
      }));
      return {
        id: `edge-${LINE_ID}-${from.stationCode}-${to.stationCode}-${direction}`,
        sourceId: SOURCE_ID,
        from: { sourceId: SOURCE_ID, sourceStationCode: from.stationCode, lineId: LINE_ID, nodeSuffix: direction },
        to: { sourceId: SOURCE_ID, sourceStationCode: to.stationCode, lineId: LINE_ID, nodeSuffix: direction },
        durationSeconds: medianSeconds(sample.durations),
        distanceMeters: 0,
        edgeType: "RIDE",
        servicePattern: "LOCAL",
        includesStairs: false,
        stairAccessState: "UNKNOWN",
        accessibilityStatus: "UNKNOWN",
        reliabilityScore: 90,
        provenanceKind: "OFFICIAL_SOURCE",
        verificationStatus: "VERIFIED",
        lastVerifiedAt: verifiedAt,
        sourceSnapshotId: scheduleProvenance?.sourceSnapshotId,
        providerRecordHash,
        evidenceHash: sha256(`${scheduleProvenance?.evidenceHash ?? ""}:${providerRecordHash}`),
      };
    });
  const expectedEdgeCount = (stationById.size - 1) * 2;
  if (edges.length !== expectedEdgeCount) {
    throw new Error(`KRIC line 4 adjacent RIDE edge count mismatch: ${edges.length} !== ${expectedEdgeCount}`);
  }
  return edges;
}

function medianSeconds(values) {
  const sorted = values.toSorted((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return Math.round(sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]);
}

function corridorRouteMapPositions(stations, geometry, verifiedAt) {
  return stations.map((station) => {
    const node = (geometry?.stationNodes ?? []).find(
      (candidate) =>
        candidate.dataStation === station.stinNm &&
        (String(candidate.dataLine) === "4" || String(candidate.transferLines ?? "").split(/\s+/).includes("4")),
    );
    if (!node) throw new Error(`self-drawn route map station node missing: ${station.stinNm}`);
    const labels = (geometry?.labels ?? []).filter((candidate) => candidate.normalizedText === station.stinNm);
    const label = labels.toSorted((left, right) => labelDistance(left, node) - labelDistance(right, node))[0];
    if (!label?.bounds || !Array.isArray(label.polygon)) {
      throw new Error(`self-drawn route map station label missing: ${station.stinNm}`);
    }
    return {
      sourceId: ROUTE_MAP_SOURCE_ID,
      station: {
        sourceId: ROUTE_MAP_SOURCE_ID,
        sourceStationCode: `capital-v2:${station.stinNm}`,
        lineId: LINE_ID,
      },
      region: "수도권",
      x: Math.round(node.x),
      y: Math.round(node.y),
      labelDx: Math.round(label.bounds.minX - node.x),
      labelDy: Math.round(label.bounds.minY - node.y),
      labelPolygon: label.polygon,
      sourceName: "오너 자작 수도권 v2 노선도",
      sourceUrl: "https://github.com/AquilaXk/easysubway/blob/main/tools/route-map/route-map-defs/svg-sources/easy-subway-sma-v2.svg",
      sourceSha256: geometry.sourceSvgSha256,
      license: "오너 자작 저작물",
      licenseStatus: "owner-authored-commercial-use",
      commercialUseAllowed: true,
      attributionRequired: false,
      sourceLabel: station.stinNm,
      reviewedAt: verifiedAt,
      updatedAt: verifiedAt,
    };
  });
}

function labelDistance(label, node) {
  const centerX = (label.bounds.minX + label.bounds.maxX) / 2;
  const centerY = (label.bounds.minY + label.bounds.maxY) / 2;
  return (centerX - node.x) ** 2 + (centerY - node.y) ** 2;
}

function holidayExceptionDates() {
  return WEEKDAY_HOLIDAY_DATES_2026.flatMap((date) => [
    { serviceId: "holiday-kric", date, exceptionType: 1 },
    { serviceId: "weekday-kric", date, exceptionType: 2 },
  ]);
}

function stationLineTemplate(input, stationCode) {
  const row = (input.stationLineRows ?? []).find((candidate) => candidate.stationCode === stationCode);
  if (!row) {
    throw new Error(`production input missing stationLineRows stationCode: ${stationCode}`);
  }
  return row;
}

function requireCalendar(serviceId) {
  const days = CALENDAR_DAYS[serviceId];
  if (!days) {
    throw new Error(`unknown KRIC serviceId: ${serviceId}`);
  }
  return days;
}

function unique(values) {
  return [...new Set(values)];
}

function uniqueBy(rows, keyFn) {
  return [...new Map(rows.map((row) => [keyFn(row), row])).values()];
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function validateArtifact(artifact) {
  if (!artifact || typeof artifact !== "object" || Array.isArray(artifact)) {
    throw new Error("KRIC pilot artifact must be an object");
  }
  requireEqual(artifact.artifactKind, "kric-line4-timetable-collection", "artifactKind");
  if (artifact.sourceId && !SOURCE_ARTIFACT_IDS.has(artifact.sourceId)) {
    throw new Error(`KRIC pilot artifact sourceId mismatch: ${artifact.sourceId}`);
  }
  requireEqual(artifact.lineId, LINE_ID, "lineId");
  requireEqual(artifact.requestCount, EXPECTED_REQUEST_COUNT, "requestCount");
  requireEqual(artifact.failedRequestCount, 0, "failedRequestCount");
  requireEqual(artifact.intermediateRowCount, EXPECTED_INTERMEDIATE_ROW_COUNT, "intermediateRowCount");
  requireEqual(artifact.transitTripCount, EXPECTED_TRANSIT_TRIP_COUNT, "transitTripCount");
  requireEqual(artifact.transitStopTimeCount, EXPECTED_TRANSIT_STOP_TIME_COUNT, "transitStopTimeCount");
  if (!Array.isArray(artifact.transitTrips) || !Array.isArray(artifact.transitStopTimes)) {
    throw new TypeError("KRIC pilot artifact missing transit rows");
  }
  requireEqual(artifact.transitTrips.length, EXPECTED_TRANSIT_TRIP_COUNT, "transitTrips.length");
  requireEqual(artifact.transitStopTimes.length, EXPECTED_TRANSIT_STOP_TIME_COUNT, "transitStopTimes.length");
}

function requireEqual(actual, expected, field) {
  if (actual !== expected) {
    throw new Error(`KRIC pilot artifact ${field} mismatch: ${actual} !== ${expected}`);
  }
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined || value.startsWith("--")) {
      throw new Error(`invalid argument near ${key ?? "<end>"}`);
    }
    args.set(key.slice(2), value);
  }
  return args;
}

function requireArg(args, name) {
  const value = args.get(name);
  if (!value) {
    throw new Error(`missing required argument: --${name}`);
  }
  return value;
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
