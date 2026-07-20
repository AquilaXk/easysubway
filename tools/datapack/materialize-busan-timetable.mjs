#!/usr/bin/env node
import { createHash } from "node:crypto";

const SOURCE_ID = "busan-transportation-timetable";
const TOPOLOGY_SOURCE_ID = "busan-transportation-route-topology";
const PACK_ID = "nationwide-busan-schedule";
const EXPECTED_ROW_COUNT = 109_140;
const EXPECTED_TRIP_COUNT = 3_833;
const FRESHNESS_MILLIS = 24 * 60 * 60 * 1_000;
const LINE_IDS = Object.freeze({
  "1": "line-ab1a041f6266",
  "2": "line-eb7b47920390",
  "3": "line-d74614a04530",
  "4": "line-d812a5bc1e5f",
});
const SERVICES = Object.freeze({
  "1": "busan-weekday-2026",
  "2": "busan-saturday-2026",
  "3": "busan-holiday-2026",
});
const HOLIDAYS_2026 = Object.freeze([
  "20260101", "20260216", "20260217", "20260218", "20260302", "20260505", "20260525",
  "20260603", "20260817", "20260924", "20260925", "20261005", "20261009", "20261225",
]);

export function materializeBusanTimetable({ baseFixture, timetableSnapshot, inventory, now = new Date() }) {
  const rows = validateSnapshot(timetableSnapshot);
  const source = requiredSource(inventory, timetableSnapshot, now);
  const fixture = structuredClone(baseFixture);
  const pack = fixture.packs?.[0];
  if (!pack || fixture.packs.length !== 1) throw new Error("Busan timetable requires one cumulative pack");
  if (pack.sourceInventory.some(({ id }) => id === SOURCE_ID)) throw new Error(`${SOURCE_ID} already exists`);
  validateTopologyLineage(pack, source.scheduleAdmissionEvidence);
  const stations = canonicalStations(pack);
  const provenance = scheduleProvenance(source, timetableSnapshot);
  const groups = Map.groupBy(rows, (row) => [row.line, row.day, row.trainno, row.updown, row.endcode].join(":"));
  if (groups.size !== EXPECTED_TRIP_COUNT) throw new Error(`Busan timetable trip count mismatch: ${groups.size}`);

  pack.sourceInventory.push(packSource(source, timetableSnapshot));
  addCalendars(pack, provenance);
  addRoutes(pack, provenance);
  const tripIds = new Set();
  for (const [key, group] of [...groups].sort(([left], [right]) => left.localeCompare(right, "en"))) {
    const [line, day, trainno, updown, endcode] = key.split(":");
    const lineId = LINE_IDS[line];
    const destination = stations.get(`${lineId}:${endcode}`);
    if (!destination || group.length < 2) throw new Error(`Busan timetable trip scope mismatch: ${key}`);
    const ordered = group.map((row) => ({ row, seconds: Number(row.hour) * 3_600 + Number(row.time) * 60 }))
      .sort((left, right) => left.seconds - right.seconds || Number(left.row.scode) - Number(right.row.scode));
    if (new Set(ordered.map(({ row }) => row.scode)).size !== ordered.length) {
      throw new Error(`Busan timetable duplicate trip stop: ${key}`);
    }
    const id = `trip-busan-${line}-${day}-${trainno}-${updown}-${endcode}`;
    if (tripIds.has(id)) throw new Error(`duplicate Busan timetable trip id: ${id}`);
    tripIds.add(id);
    const recordHash = sha256(JSON.stringify(group));
    pack.transitTrips.push(withProvenance({
      id,
      routeId: `route-busan-${line}-${updown}`,
      serviceId: SERVICES[day],
      tripHeadsign: destination.stationName,
      directionId: updown === "0" ? "up" : "down",
      servicePattern: "LOCAL",
      serviceClass: "SUBWAY",
      serviceDayStartSeconds: 0,
    }, { ...provenance, providerRecordHash: recordHash }));
    ordered.forEach(({ row, seconds }, index) => {
      const station = stations.get(`${lineId}:${row.scode}`);
      if (!station) throw new Error(`Busan timetable canonical station missing: ${lineId}:${row.scode}`);
      pack.transitStopTimes.push(withProvenance({
        tripId: id,
        stopSequence: index + 1,
        stationId: station.stationId,
        lineId,
        arrivalSeconds: seconds,
        departureSeconds: seconds,
        pickupType: index === ordered.length - 1 ? 1 : 0,
        dropOffType: index === 0 ? 1 : 0,
      }, { ...provenance, providerRecordHash: recordHash }));
    });
  }
  if (tripIds.size !== EXPECTED_TRIP_COUNT
    || pack.transitStopTimes.filter(({ sourceId }) => sourceId === SOURCE_ID).length !== EXPECTED_ROW_COUNT) {
    throw new Error("Busan timetable materialized row counts are invalid");
  }
  pack.minimumTableRows = {
    ...pack.minimumTableRows,
    service_calendars: pack.serviceCalendars.length,
    service_calendar_dates: pack.serviceCalendarDates.length,
    transit_routes: pack.transitRoutes.length,
    transit_trips: pack.transitTrips.length,
    transit_stop_times: pack.transitStopTimes.length,
    transit_feed_info: pack.transitFeedInfo.length,
  };
  const version = compactSeoulDate(timetableSnapshot.capturedAt);
  const composition = sha256(JSON.stringify({
    previousPackId: pack.id,
    snapshotId: source.scheduleAdmissionEvidence.snapshotId,
    rowsSha256: timetableSnapshot.rowsSha256,
    source,
    contentSha256: materializedPackContentHash(pack, version),
  }));
  pack.id = `${PACK_ID}-${composition}`;
  pack.version = version;
  pack.url = `https://objectstorage.ap-seoul-1.oraclecloud.com/n/axvym6vk8g7i/b/easysubway-datapacks/o/catalog/${pack.id}-v${version}.sqlite.gz`;
  fixture.manifest.activePack = { id: pack.id, version };
  return fixture;
}

export function materializedPackContentHash(pack, version) {
  const { id: _id, version: _version, url: _url, ...content } = pack;
  return sha256(JSON.stringify({ version, content }));
}

function validateSnapshot(snapshot) {
  if (snapshot?.schemaVersion !== 1 || snapshot.artifactKind !== "busan-timetable-snapshot"
    || snapshot.sourceId !== SOURCE_ID || snapshot.official !== true || snapshot.fixture !== false
    || snapshot.credentialRedacted !== true || snapshot.requestCount !== 342 || snapshot.stationCount !== 114
    || snapshot.rowCount !== EXPECTED_ROW_COUNT || snapshot.rows?.length !== EXPECTED_ROW_COUNT
    || snapshot.rowsSha256 !== sha256(JSON.stringify(snapshot.rows))
    || !/^[a-f0-9]{64}$/.test(snapshot.rawSha256 ?? "")
    || JSON.stringify(snapshot.dayTypes) !== JSON.stringify(["1", "2", "3"])
    || JSON.stringify(snapshot.lineIds) !== JSON.stringify(Object.values(LINE_IDS).sort())) {
    throw new Error("invalid Busan timetable snapshot");
  }
  const keys = new Set();
  for (const row of snapshot.rows) {
    const key = [row.line, row.day, row.trainno, row.updown, row.endcode, row.scode].join(":");
    if (!LINE_IDS[row.line] || !SERVICES[row.day] || !/^\d{1,8}$/.test(row.trainno)
      || !new Set(["0", "1"]).has(row.updown) || !/^\d{2,3}$/.test(row.scode)
      || !/^\d{2,3}$/.test(row.endcode) || !/^\d{2}$/.test(row.hour)
      || !/^\d{2}$/.test(row.time) || Number(row.hour) > 29 || Number(row.time) > 59 || keys.has(key)) {
      throw new Error(`invalid Busan timetable row: ${key}`);
    }
    keys.add(key);
  }
  return snapshot.rows;
}

function requiredSource(inventory, snapshot, now) {
  const source = inventory?.sources?.find(({ id }) => id === SOURCE_ID);
  const evidence = source?.scheduleAdmissionEvidence;
  if (source?.productionUseAllowed !== true || source.license?.redistributionAllowed !== true
    || source.capabilities?.schedule?.productionUseAllowed !== true || evidence?.issue !== 2368
    || evidence.materializer !== "tools/datapack/materialize-busan-timetable.mjs"
    || evidence.verificationTest !== "tools/datapack/materialize-busan-timetable.test.mjs"
    || evidence.snapshotId !== "busan-transportation-timetable-20260720"
    || evidence.capturedAt !== snapshot.capturedAt || evidence.freshUntil !== snapshot.freshUntil
    || evidence.rowCount !== EXPECTED_ROW_COUNT || evidence.departureCount !== EXPECTED_ROW_COUNT
    || evidence.tripCount !== EXPECTED_TRIP_COUNT || evidence.stopTimeCount !== EXPECTED_ROW_COUNT
    || evidence.rawSha256 !== snapshot.rawSha256 || evidence.rowsSha256 !== snapshot.rowsSha256
    || evidence.topologySourceId !== TOPOLOGY_SOURCE_ID) {
    throw new Error(`${SOURCE_ID} inventory evidence does not match snapshot`);
  }
  const capturedAt = Date.parse(evidence.capturedAt);
  const freshUntil = Date.parse(evidence.freshUntil);
  const observedNow = now instanceof Date ? now.getTime() : Number.NaN;
  if (!Number.isFinite(capturedAt) || freshUntil !== capturedAt + FRESHNESS_MILLIS
    || !Number.isFinite(observedNow) || observedNow < capturedAt || observedNow >= freshUntil) {
    throw new Error(`${SOURCE_ID} evidence freshness is invalid`);
  }
  return source;
}

function validateTopologyLineage(pack, evidence) {
  const topology = pack.sourceInventory.find(({ id }) => id === TOPOLOGY_SOURCE_ID);
  const edges = pack.networkEdges.filter(({ sourceId }) => sourceId === TOPOLOGY_SOURCE_ID);
  if (!topology || edges.length !== 220 || edges.some(({ sourceSnapshotId, evidenceHash }) =>
    sourceSnapshotId !== evidence.topologySnapshotId || evidenceHash !== evidence.topologyContentSha256)) {
    throw new Error("Busan timetable topology lineage mismatch");
  }
}

function canonicalStations(pack) {
  const names = new Map(pack.stations.map(({ id, nameKo }) => [id, nameKo]));
  const stations = new Map();
  for (const row of pack.stationLines) {
    if (!Object.values(LINE_IDS).includes(row.lineId)) continue;
    const key = `${row.lineId}:${row.stationCode}`;
    if (stations.has(key)) throw new Error(`duplicate Busan station mapping: ${key}`);
    stations.set(key, { stationId: row.stationId, stationName: names.get(row.stationId) });
  }
  if (stations.size !== 114) throw new Error(`Busan timetable canonical station count mismatch: ${stations.size}`);
  return stations;
}

function addCalendars(pack, provenance) {
  pack.serviceCalendars.push(
    withProvenance({
      serviceId: SERVICES["1"], monday: true, tuesday: true, wednesday: true, thursday: true, friday: true,
      saturday: false, sunday: false, startDate: "20260101", endDate: "20261231",
    }, provenance),
    withProvenance({
      serviceId: SERVICES["2"], monday: false, tuesday: false, wednesday: false, thursday: false, friday: false,
      saturday: true, sunday: false, startDate: "20260101", endDate: "20261231",
    }, provenance),
    withProvenance({
      serviceId: SERVICES["3"], monday: false, tuesday: false, wednesday: false, thursday: false, friday: false,
      saturday: false, sunday: true, startDate: "20260101", endDate: "20261231",
    }, provenance),
  );
  pack.serviceCalendarDates.push(...HOLIDAYS_2026.flatMap((date) => {
    const day = new Date(`${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6)}T00:00:00+09:00`).getDay();
    return [
      withProvenance({ serviceId: SERVICES["3"], date, exceptionType: 1 }, provenance, "GENERATED"),
      withProvenance({ serviceId: day === 6 ? SERVICES["2"] : SERVICES["1"], date, exceptionType: 2 }, provenance, "GENERATED"),
    ];
  }));
}

function addRoutes(pack, provenance) {
  for (const [line, lineId] of Object.entries(LINE_IDS)) {
    for (const updown of ["0", "1"]) {
      const direction = updown === "0" ? "상행선" : "하행선";
      pack.transitRoutes.push(withProvenance({
        id: `route-busan-${line}-${updown}`,
        lineId,
        routeShortName: line,
        routeLongName: `부산 ${line}호선 ${direction}`,
        directionName: direction,
      }, provenance));
    }
  }
}

function scheduleProvenance(source, snapshot) {
  return {
    sourceId: SOURCE_ID,
    sourceSnapshotId: source.scheduleAdmissionEvidence.snapshotId,
    providerRecordHash: snapshot.rowsSha256,
    evidenceHash: sha256(JSON.stringify({
      rowsSha256: snapshot.rowsSha256,
      topologyContentSha256: source.scheduleAdmissionEvidence.topologyContentSha256,
    })),
    updatedAt: snapshot.capturedAt,
  };
}

function withProvenance(row, provenance, derivationKind = "OFFICIAL") {
  return {
    ...row,
    sourceId: provenance.sourceId,
    sourceSnapshotId: provenance.sourceSnapshotId,
    providerRecordHash: provenance.providerRecordHash,
    evidenceHash: provenance.evidenceHash,
    provenanceKind: "OFFICIAL_SOURCE",
    derivationKind,
    updatedAt: provenance.updatedAt,
  };
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

function compactSeoulDate(value) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en", {
    timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date(value)).map(({ type, value: part }) => [type, part]));
  return `${parts.year}${parts.month}${parts.day}`;
}

function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
