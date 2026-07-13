#!/usr/bin/env node
// KRIC 4호선 시각표 수집+재구성 러너 (③b→③c 연결).
// 로스터(subwayRouteInfo 캡처) → 계획(plan-kric-line4-collection) → KRIC 라이브 호출 →
// normalizer(#1803) → 재구성 코어(#1797) → transitTrips/transitStopTimes 산출물.
//
// 실행: KRIC_SERVICE_KEY=... node collect-kric-line4-timetables.mjs \
//         --roster tools/datapack/sources/kric-line4-route-roster-20260706.json \
//         --line-id seoul-4 --output <out.json> [--day-cds 8,7,9] [--no-express]
//
// serviceKey는 URL 로그·산출물에 남기지 않는다(#1397 공통 규칙).
import { readFile, writeFile } from "node:fs/promises";
import { buildKricLine4CollectionPlan } from "./plan-kric-line4-collection.mjs";
import { normalizeKricSubwayTimetable } from "./normalize-kric-timetable.mjs";
import { reconstructTransitTrips } from "./reconstruct-transit-trips.mjs";

const SERVICE_ID_BY_DAY_CD = { "8": "weekday-kric", "7": "saturday-kric", "9": "holiday-kric" };
const RAW_ARCHIVE_FIELDS = [
  "railOprIsttCd",
  "trnNo",
  "dayCd",
  "dayNm",
  "stinCd",
  "lnCd",
  "arvTm",
  "dptTm",
  "exptCd",
];

export function credentialFreeRawArchiveRows(rows) {
  return rows.map((row) => {
    if (!row || typeof row !== "object" || Array.isArray(row)) {
      throw new Error("KRIC raw archive row must be an object");
    }
    return Object.fromEntries(
      RAW_ARCHIVE_FIELDS
        .filter((field) => Object.hasOwn(row, field))
        .map((field) => [field, row[field]]),
    );
  });
}

export function successfulKricRows(payload) {
  const code = String(payload?.header?.resultCode ?? "");
  if (code !== "00") {
    const message = String(payload?.header?.resultMsg ?? "unknown");
    throw new Error(`KRIC provider failure: resultCode=${code || "missing"}, resultMsg=${message}`);
  }
  if (!Array.isArray(payload.body)) {
    throw new Error("KRIC provider success body must be an array");
  }
  return payload.body;
}

export function assertCompleteCollection(failed, requestCount) {
  if (failed > 0) {
    throw new Error(`KRIC collection incomplete: ${failed}/${requestCount} requests failed`);
  }
}

export function buildCollectionContext(roster, lineId) {
  const stationIdByProviderStation = {};
  const lineIdByProviderLine = {};
  const lineSequenceByStationLine = {};
  for (const station of roster.stations) {
    const stationId = `station-${lineId}-${station.stinCd}`;
    stationIdByProviderStation[`${station.railOprIsttCd}|${roster.lnCd}|${station.stinCd}`] = stationId;
    lineIdByProviderLine[`${station.railOprIsttCd}|${roster.lnCd}`] = lineId;
    lineSequenceByStationLine[`${stationId}|${lineId}`] = station.stinConsOrdr;
  }
  return {
    stationIdByProviderStation,
    lineIdByProviderLine,
    lineSequenceByStationLine,
    routeIdByLineDirection: { [`${lineId}|up`]: `route-${lineId}-up`, [`${lineId}|down`]: `route-${lineId}-down` },
    serviceIdByDayCd: SERVICE_ID_BY_DAY_CD,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const roster = JSON.parse(await readFile(args.roster, "utf8"));
  const lineId = args["line-id"] ?? "seoul-4";
  const key = process.env.KRIC_SERVICE_KEY;
  if (!key) {
    throw new Error("KRIC_SERVICE_KEY env is required");
  }
  const plan = buildKricLine4CollectionPlan(roster, {
    dayCds: args["day-cds"] ? args["day-cds"].split(",") : undefined,
    includeExpress: args.express !== "false",
  });
  const context = buildCollectionContext(roster, lineId);

  const intermediate = [];
  const rawArchiveRows = [];
  const perRequest = [];
  let failed = 0;
  for (const request of plan.requests) {
    const url = `${request.endpoint}?serviceKey=${encodeURIComponent(key)}&format=json&railOprIsttCd=${request.params.railOprIsttCd}&dayCd=${request.params.dayCd}&lnCd=${request.params.lnCd}&stinCd=${request.params.stinCd}`;
    try {
      const payload = JSON.parse(await fetchWithRetry(url));
      const rows = successfulKricRows(payload);
      // servicePattern은 normalizer가 row별 exptCd로 도출한다(급행 표시 시각표).
      const successfulRows = credentialFreeRawArchiveRows(rows);
      const normalized = normalizeKricSubwayTimetable(rows, context);
      rawArchiveRows.push(...successfulRows);
      intermediate.push(...normalized);
      perRequest.push({ requestKey: request.requestKey, resultCode: "00", rows: rows.length, normalized: normalized.length });
    } catch (error) {
      failed += 1;
      perRequest.push({ requestKey: request.requestKey, error: redactKey(String(error.message), key) });
    }
  }

  const { transitTrips, transitStopTimes } = reconstructTransitTrips(intermediate, context);
  const artifact = {
    artifactKind: "kric-line4-timetable-collection",
    sourceId: "kric-subway-route-info",
    lineId,
    capturedAt: new Date().toISOString().slice(0, 10),
    requestCount: plan.requestCount,
    failedRequestCount: failed,
    intermediateRowCount: intermediate.length,
    transitTripCount: transitTrips.length,
    transitStopTimeCount: transitStopTimes.length,
    perRequest,
    transitTrips,
    transitStopTimes,
  };
  if (args.output) {
    await writeFile(args.output, `${JSON.stringify(artifact, null, 2)}\n`);
  }
  assertCompleteCollection(failed, plan.requestCount);
  if (args["raw-output"]) {
    await writeFile(args["raw-output"], `${JSON.stringify(rawArchiveRows, null, 2)}\n`);
  }
  const { transitTrips: _t, transitStopTimes: _s, perRequest: _p, ...summary } = artifact;
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (!flag.startsWith("--")) {
      throw new Error(`unexpected argument: ${flag}`);
    }
    if (flag === "--no-express") {
      args.express = "false";
      continue;
    }
    args[flag.slice(2)] = argv[index + 1];
    index += 1;
  }
  return args;
}

// transient 네트워크 오류(DNS ENOTFOUND 등)에 소폭 재시도한다. KRIC quota 무제한이라 재시도 비용 무해.
export async function fetchWithRetry(
  url,
  attempts = 3,
  fetchImpl = fetch,
  timeoutMs = 15000,
  retryDelayMs = 500,
) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await (
        await fetchImpl(url, { signal: AbortSignal.timeout(timeoutMs) })
      ).text();
    } catch (error) {
      lastError = error;
      if (attempt < attempts) {
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs * attempt));
      }
    }
  }
  throw lastError;
}

function redactKey(text, key) {
  return key && key.length > 6 ? text.split(key).join("[KEY]") : text;
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exit(1);
  });
}
