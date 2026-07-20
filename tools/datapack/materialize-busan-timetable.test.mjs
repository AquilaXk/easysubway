import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { parseMolitDaejeonStationMappings } from "./build-molit-nationwide-fixture.mjs";
import {
  materializeBusanRouteTopology,
  parseCanonicalBusanStationMappings,
} from "./materialize-busan-route-topology.mjs";
import { materializeBusanTimetable } from "./materialize-busan-timetable.mjs";
import { materializeDaejeonTimetable } from "./materialize-daejeon-timetable.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const now = new Date("2026-07-20T09:00:00.000Z");

test("부산 공식 109140행을 3833 trip·109140 stop_time으로 materialize한다", async () => {
  const { fixture } = await inputs();
  const pack = fixture.packs[0];
  const trips = pack.transitTrips.filter(({ sourceId }) => sourceId === "busan-transportation-timetable");
  const stopTimes = pack.transitStopTimes.filter(({ sourceId }) => sourceId === "busan-transportation-timetable");
  const calendars = pack.serviceCalendars.filter(({ sourceId }) => sourceId === "busan-transportation-timetable");

  assert.match(pack.id, /^nationwide-busan-schedule-[a-f0-9]{64}$/);
  assert.deepEqual(fixture.manifest.activePack, { id: pack.id, version: "20260720" });
  assert.equal(calendars.length, 3);
  assert.equal(trips.length, 3_833);
  assert.equal(stopTimes.length, 109_140);
  assert.equal(new Set(trips.map(({ id }) => id)).size, trips.length);
  assert.ok(stopTimes.every(({ arrivalSeconds, departureSeconds }) => arrivalSeconds === departureSeconds));
  assert.ok(stopTimes.every(({ sourceSnapshotId }) =>
    sourceSnapshotId === "busan-transportation-timetable-20260720"));
  assert.deepEqual(Object.fromEntries(calendars.map(({ serviceId }) => [serviceId,
    trips.filter((trip) => trip.serviceId === serviceId).length])), {
    "busan-weekday-2026": 1_354,
    "busan-saturday-2026": 1_277,
    "busan-holiday-2026": 1_202,
  });
});

test("부산 timetable admission은 snapshot·inventory·freshness·topology lineage 변조를 fail closed한다", async () => {
  const values = await inputs({ materialize: false });
  const badSnapshot = structuredClone(values.busanTimetable);
  badSnapshot.rowsSha256 = "0".repeat(64);
  assert.throws(() => materializeBusanTimetable({
    baseFixture: values.cumulativeFixture,
    timetableSnapshot: badSnapshot,
    inventory: values.inventory,
    now,
  }), /snapshot/);

  assert.throws(() => materializeBusanTimetable({
    baseFixture: values.cumulativeFixture,
    timetableSnapshot: values.busanTimetable,
    inventory: values.inventory,
    now: new Date("2026-07-21T08:37:16.931Z"),
  }), /freshness/);

  const badInventory = structuredClone(values.inventory);
  badInventory.sources.find(({ id }) => id === "busan-transportation-timetable")
    .scheduleAdmissionEvidence.topologyContentSha256 = "0".repeat(64);
  assert.throws(() => materializeBusanTimetable({
    baseFixture: values.cumulativeFixture,
    timetableSnapshot: values.busanTimetable,
    inventory: badInventory,
    now,
  }), /topology lineage/);
});

async function inputs({ materialize = true } = {}) {
  const [baseFixture, busanTopology, busanTimetable, daejeonTimetable, daejeonTopology,
    inventory, busanMap, daejeonMap] = await Promise.all([
    readJson("tools/datapack/release/capital-production-reviewed-pack.json"),
    readJson("tools/datapack/sources/busan-transportation-route-topology-20260720.json"),
    readJson("tools/datapack/sources/busan-transportation-timetable-20260720.json"),
    readJson("tools/datapack/sources/daejeon-train-timetable-20260720.json"),
    readJson("tools/datapack/sources/daejeon-route-topology-20260720.json"),
    readJson("tools/datapack/source-inventory.json"),
    readFile(path.join(root, "tools/datapack/sources/regional-official-svg-route-map-coordinates-20260624.csv"), "utf8"),
    readFile(path.join(root, "tools/datapack/sources/molit-urban-rail-full-route-20251211.csv")),
  ]);
  const busanFixture = materializeBusanRouteTopology({
    baseFixture,
    snapshot: busanTopology,
    inventory,
    canonicalStationMappings: parseCanonicalBusanStationMappings(busanMap),
    now,
  });
  const cumulativeFixture = materializeDaejeonTimetable({
    baseFixture: busanFixture,
    timetableSnapshot: daejeonTimetable,
    topologySnapshot: daejeonTopology,
    inventory,
    canonicalStationMappings: parseMolitDaejeonStationMappings(daejeonMap),
    now,
  });
  const fixture = materialize ? materializeBusanTimetable({
    baseFixture: cumulativeFixture,
    timetableSnapshot: busanTimetable,
    inventory,
    now,
  }) : undefined;
  return { busanTimetable, cumulativeFixture, fixture, inventory };
}

async function readJson(relativePath) {
  return JSON.parse(await readFile(path.join(root, relativePath), "utf8"));
}
