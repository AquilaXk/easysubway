#!/usr/bin/env node
// 재구성 artifact(collect-kric-line4-timetables 산출물) → 백엔드 Flyway DB용 timetable seed SQL.
// 백엔드 RAPTOR 플래너(JdbcRouteTimetableRepository)가 읽는 transit_routes/service_calendars/
// transit_trips/transit_stop_times를 채운다. station_lines·station 행은 백엔드 스키마에 없어 불필요.
//
// 실행: node build-backend-timetable-seed.mjs --input <artifact.json> --line-id seoul-4 --output <seed.sql>
//
// 출력 SQL은 H2(PostgreSQL 모드)·실제 postgresql 양립. 지금은 백엔드 테스트 리소스, 나중에 Flyway
// 데이터 마이그레이션 본체로 재활용(dual-use). FK 순서: calendars→routes→trips→stop_times.
//
// 전체 재생성(4호선 51역 전량):
//   KRIC_SERVICE_KEY=... node collect-kric-line4-timetables.mjs \
//     --roster sources/kric-line4-route-roster-20260706.json --line-id seoul-4 --output <artifact.json>
//   node build-backend-timetable-seed.mjs --input <artifact.json> --line-id seoul-4 --output <seed.sql>
// 실증(2026-07-06): 895 trip·33,062 stop_times가 V29 제약을 전량 통과, H2 적재 후 RAPTOR PLANNED 산출.
// 커밋된 것은 코리도 슬라이스 테스트 리소스뿐. **전량 seed의 prod Flyway 마이그레이션 = 실제 go-live(출시게이트)**로
// 별도 단계다(feed_end_date 미설정 시 STALE 아님=즉시 PLANNED 활성이므로 게이팅 필수).
import { readFile, writeFile } from "node:fs/promises";

const SECONDS_LIMIT_EXCLUSIVE = 108000; // V29 CHECK: arrival/departure BETWEEN 0 AND 107999

// KRIC dayCd 매핑(collect-kric의 SERVICE_ID_BY_DAY_CD와 정합). 토요일→휴일: 4호선은 dayCd=7(토) 무응답이라
// 토요일 다이어가 휴일(holiday-kric)로 흡수된다 → holiday-kric에 saturday=true.
const SERVICE_CALENDAR_DAY_MAP = {
  "weekday-kric": { monday: true, tuesday: true, wednesday: true, thursday: true, friday: true, saturday: false, sunday: false },
  "saturday-kric": { monday: false, tuesday: false, wednesday: false, thursday: false, friday: false, saturday: true, sunday: false },
  "holiday-kric": { monday: false, tuesday: false, wednesday: false, thursday: false, friday: false, saturday: true, sunday: true },
};

const DEFAULT_START_DATE = "20260101";
const DEFAULT_END_DATE = "20261231";
const DEFAULT_TIMEZONE = "Asia/Seoul";

export function buildBackendTimetableSeed(artifact, options = {}) {
  const trips = artifact?.transitTrips ?? [];
  const stopTimes = artifact?.transitStopTimes ?? [];
  const lineId = options.lineId ?? null;
  const startDate = options.startDate ?? DEFAULT_START_DATE;
  const endDate = options.endDate ?? DEFAULT_END_DATE;
  const dayMap = options.serviceCalendarDayMap ?? SERVICE_CALENDAR_DAY_MAP;

  validateStopTimes(stopTimes);

  const calendars = deriveCalendars(trips, dayMap, startDate, endDate);
  const routes = deriveRoutes(trips, lineId);

  const statements = [
    ...calendars.map(calendarInsert),
    ...routes.map(routeInsert),
    ...trips.map(tripInsert),
    ...stopTimes.map(stopTimeInsert),
  ];
  const sql = `${statements.join("\n")}\n`;

  return { sql, statements, calendars, routes, tripCount: trips.length, stopTimeCount: stopTimes.length };
}

function validateStopTimes(stopTimes) {
  for (const row of stopTimes) {
    const arrival = requireInteger(row.arrivalSeconds, "arrivalSeconds");
    const departure = requireInteger(row.departureSeconds, "departureSeconds");
    if (arrival < 0 || arrival >= SECONDS_LIMIT_EXCLUSIVE || departure < 0 || departure >= SECONDS_LIMIT_EXCLUSIVE) {
      throw new Error(`transit_stop_times seconds out of range [0,${SECONDS_LIMIT_EXCLUSIVE}): ${row.tripId}:${row.stopSequence}`);
    }
    if (arrival > departure) {
      throw new Error(`transit_stop_times arrival must be <= departure: ${row.tripId}:${row.stopSequence}`);
    }
    if (requireInteger(row.stopSequence, "stopSequence") < 1) {
      throw new Error(`transit_stop_times stop_sequence must be >= 1: ${row.tripId}`);
    }
  }
}

function deriveCalendars(trips, dayMap, startDate, endDate) {
  const serviceIds = [...new Set(trips.map((trip) => requireString(trip.serviceId, "transitTrips.serviceId")))].sort(
    (left, right) => left.localeCompare(right),
  );
  return serviceIds.map((serviceId) => {
    const days = dayMap[serviceId];
    if (!days) {
      throw new Error(`service_calendar mapping missing for serviceId: ${serviceId}`);
    }
    return { serviceId, startDate, endDate, timezone: DEFAULT_TIMEZONE, ...days };
  });
}

function deriveRoutes(trips, lineId) {
  const byId = new Map();
  for (const trip of trips) {
    const id = requireString(trip.routeId, "transitTrips.routeId");
    if (!byId.has(id)) {
      byId.set(id, {
        id,
        lineId: lineId ?? deriveLineIdFromRouteId(id),
        directionName: trip.directionId ?? "",
        shortName: "",
        longName: "",
        timezone: DEFAULT_TIMEZONE,
      });
    }
  }
  return [...byId.values()].sort((left, right) => left.id.localeCompare(right.id));
}

function deriveLineIdFromRouteId(routeId) {
  // route-<lineId>-<direction> 관례에서 lineId 도출(옵션 미지정 시 방어적).
  const match = /^route-(.+)-(up|down)$/.exec(routeId);
  return match ? match[1] : routeId;
}

function calendarInsert(c) {
  return (
    "INSERT INTO service_calendars (service_id, start_date, end_date, timezone, monday, tuesday, wednesday, thursday, friday, saturday, sunday) VALUES (" +
    `${quote(c.serviceId)}, ${quote(c.startDate)}, ${quote(c.endDate)}, ${quote(c.timezone)}, ` +
    `${bool(c.monday)}, ${bool(c.tuesday)}, ${bool(c.wednesday)}, ${bool(c.thursday)}, ${bool(c.friday)}, ${bool(c.saturday)}, ${bool(c.sunday)});`
  );
}

function routeInsert(r) {
  return (
    "INSERT INTO transit_routes (id, timezone, line_id, route_short_name, route_long_name, direction_name) VALUES (" +
    `${quote(r.id)}, ${quote(r.timezone)}, ${quote(r.lineId)}, ${quote(r.shortName)}, ${quote(r.longName)}, ${quote(r.directionName)});`
  );
}

function tripInsert(t) {
  return (
    "INSERT INTO transit_trips (id, route_id, service_id, service_pattern, service_day_start_seconds, trip_headsign, direction_id) VALUES (" +
    `${quote(requireString(t.id, "transitTrips.id"))}, ${quote(requireString(t.routeId, "transitTrips.routeId"))}, ` +
    `${quote(requireString(t.serviceId, "transitTrips.serviceId"))}, ${quote(t.servicePattern ?? "LOCAL")}, ` +
    `${t.serviceDayStartSeconds ?? 0}, ${quote(t.tripHeadsign ?? "")}, ${quote(t.directionId ?? "")});`
  );
}

function stopTimeInsert(s) {
  return (
    "INSERT INTO transit_stop_times (trip_id, stop_sequence, station_id, line_id, pickup_type, drop_off_type, arrival_seconds, departure_seconds) VALUES (" +
    `${quote(requireString(s.tripId, "transitStopTimes.tripId"))}, ${requireInteger(s.stopSequence, "stopSequence")}, ` +
    `${quote(requireString(s.stationId, "transitStopTimes.stationId"))}, ${quote(requireString(s.lineId, "transitStopTimes.lineId"))}, ` +
    `${s.pickupType ?? 0}, ${s.dropOffType ?? 0}, ${requireInteger(s.arrivalSeconds, "arrivalSeconds")}, ${requireInteger(s.departureSeconds, "departureSeconds")});`
  );
}

function quote(value) {
  return `'${String(value).split("'").join("''")}'`;
}

function bool(value) {
  return value ? "TRUE" : "FALSE";
}

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} must be a non-empty string`);
  }
  return value;
}

function requireInteger(value, label) {
  if (!Number.isInteger(value)) {
    throw new Error(`${label} must be an integer`);
  }
  return value;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const artifact = JSON.parse(await readFile(args.input, "utf8"));
  const seed = buildBackendTimetableSeed(artifact, {
    lineId: args["line-id"],
    startDate: args["start-date"],
    endDate: args["end-date"],
  });
  if (args.output) {
    await writeFile(args.output, seed.sql);
  }
  process.stdout.write(
    `${JSON.stringify({ calendars: seed.calendars.length, routes: seed.routes.length, trips: seed.tripCount, stopTimes: seed.stopTimeCount }, null, 2)}\n`,
  );
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (!flag.startsWith("--")) {
      throw new Error(`unexpected argument: ${flag}`);
    }
    args[flag.slice(2)] = argv[index + 1];
    index += 1;
  }
  return args;
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  });
}
