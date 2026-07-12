#!/usr/bin/env node
import { chmod, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { sanitizeErrorMessage } from "./lib/source-candidate-evidence-collector.mjs";

const FARE_ENDPOINT = "https://apis.data.go.kr/B553766/fare2/getRltmFare2";
const SEOUL_CATALOG_ORIGIN = "http://openapi.seoul.go.kr:8088";
const SEOUL_CATALOG_SERVICE = "SearchSTNBySubwayLineInfo";
const MAX_RESPONSE_BYTES = 1_000_000;
const MAX_ATTEMPTS = 2;
const REQUIRED_FARE_FIELDS = Object.freeze([
  "gnrlCardFare",
  "gnrlCashFare",
  "yungCardFare",
  "yungCashFare",
  "childCardFare",
  "childCashFare",
]);
const EXPECTED_SAMPLE = Object.freeze({
  dptreStnCd: "0150",
  dptreStnNm: "서울역",
  arvlStnCd: "0151",
  arvlStnNm: "시청",
  gnrlCardFare: 1550,
  gnrlCashFare: 1650,
  yungCardFare: 900,
  yungCashFare: 1650,
  childCardFare: 550,
  childCashFare: 550,
});
const CANARIES = Object.freeze([
  { evidenceKey: "seoulStationLine4", stationName: "서울역", lineNumber: "4", fareCode: "0150" },
  { evidenceKey: "cityHallLine1", stationName: "시청", lineNumber: "1", fareCode: "0151" },
]);
const TARGETS = Object.freeze([
  { stationId: "station-sangnoksu", lineId: "seoul-4", stationName: "상록수", lineNumber: "4" },
  { stationId: "station-sadang", lineId: "seoul-4", stationName: "사당", lineNumber: "4" },
]);

function requiredText(value, label) {
  if (typeof value !== "string" || value.length === 0) throw new Error(`${label} is required`);
  return value;
}

function decodedServiceKey(value) {
  if (!/%[0-9a-f]{2}/i.test(value)) return value;
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function sleep(milliseconds) {
  if (milliseconds <= 0) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

export function validateFareSample(sample) {
  if (!sample || typeof sample !== "object" || Array.isArray(sample)) {
    throw new TypeError("fare API sample must be an object");
  }
  for (const [field, expected] of Object.entries(EXPECTED_SAMPLE)) {
    if (!(field in sample)) throw new Error(`fare API field missing: ${field}`);
    if (typeof sample[field] !== typeof expected) throw new TypeError(`fare API field type invalid: ${field}`);
    if (sample[field] !== expected) throw new Error(`fare API field value changed: ${field}`);
  }
}

export function sanitizeProbeError(error, secrets = []) {
  let message = error instanceof Error ? error.message : String(error);
  for (const secret of secrets) message = sanitizeErrorMessage(message, secret ?? "");
  return message;
}

function shouldRetryStatus(status) {
  return status === 429 || status >= 500;
}

async function fetchWithRetry({ fetchImpl, url, timeoutMs, retryDelayMs, label }) {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    let response;
    try {
      response = await fetchImpl(url, { signal: AbortSignal.timeout(timeoutMs) });
    } catch (error) {
      if (attempt < MAX_ATTEMPTS) {
        await sleep(retryDelayMs);
        continue;
      }
      throw error;
    }
    if (response.ok) return { attempts: attempt, response };
    if (attempt < MAX_ATTEMPTS && shouldRetryStatus(response.status)) {
      await sleep(retryDelayMs);
      continue;
    }
    throw new Error(`${label} HTTP ${response.status}`);
  }
  throw new Error(`${label} retry exhausted`);
}

function decodeXmlText(value) {
  return value
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", "\"")
    .replaceAll("&apos;", "'")
    .replaceAll("&amp;", "&");
}

function extractSingleXmlField(rowXml, field) {
  const matches = [...rowXml.matchAll(new RegExp(`<${field}>([^<]*)</${field}>`, "g"))];
  if (matches.length !== 1) throw new Error(`catalog row field invalid: ${field}`);
  return decodeXmlText(matches[0][1].trim());
}

function parseCatalogRows(raw) {
  if (typeof raw !== "string" || raw.length === 0 || Buffer.byteLength(raw) > MAX_RESPONSE_BYTES) {
    throw new Error("catalog response size invalid");
  }
  const rows = [...raw.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/gi)].map((match) => ({
    LINE_NUM: extractSingleXmlField(match[1], "LINE_NUM"),
    STATION_NM: extractSingleXmlField(match[1], "STATION_NM"),
    FR_CODE: extractSingleXmlField(match[1], "FR_CODE"),
    STATION_CD: extractSingleXmlField(match[1], "STATION_CD"),
  }));
  if (rows.length === 0) throw new Error("catalog unavailable: no station rows");
  return rows;
}

function normalizedLineNumber(value) {
  const match = /^0*([1-9][0-9]*)호선$/.exec(value.trim());
  return match?.[1] ?? null;
}

function catalogUrl({ apiKey, stationName }) {
  return new URL(
    `${SEOUL_CATALOG_ORIGIN}/${encodeURIComponent(apiKey)}/xml/${SEOUL_CATALOG_SERVICE}/1/100//${encodeURIComponent(stationName)}/`,
  );
}

async function fetchCatalogStation({ apiKey, fetchImpl, lineNumber, retryDelayMs, stationName, timeoutMs }) {
  const { response } = await fetchWithRetry({
    fetchImpl,
    url: catalogUrl({ apiKey, stationName }),
    timeoutMs,
    retryDelayMs,
    label: "station catalog",
  });
  const rows = parseCatalogRows(await response.text()).filter((row) =>
    row.STATION_NM === stationName && normalizedLineNumber(row.LINE_NUM) === lineNumber);
  if (rows.length !== 1) throw new Error(`catalog unavailable or ambiguous: ${stationName} line ${lineNumber}`);
  return rows[0];
}

function selectFareCodeField(canaryRows) {
  const matchingFields = ["FR_CODE", "STATION_CD"].filter((field) =>
    canaryRows.every(({ expected, row }) => row[field] === expected.fareCode));
  if (matchingFields.length !== 1) throw new Error("unique fare code field equivalence failed");
  return matchingFields[0];
}

function fareUrl({ fareServiceKey, origin, destination }) {
  const url = new URL(FARE_ENDPOINT);
  url.searchParams.set("serviceKey", decodedServiceKey(fareServiceKey));
  url.searchParams.set("pageNo", "1");
  url.searchParams.set("numOfRows", "10");
  url.searchParams.set("dataType", "JSON");
  url.searchParams.set("dptreStnCd", origin.fareStationCode);
  url.searchParams.set("dptreStnNm", origin.stationName);
  url.searchParams.set("arvlStnCd", destination.fareStationCode);
  url.searchParams.set("arvlStnNm", destination.stationName);
  return url;
}

function responseItems(payload) {
  const envelope = payload?.response ?? payload;
  const resultCode = String(envelope?.header?.resultCode ?? "");
  const body = envelope?.body;
  const rawItems = body?.items?.item ?? body?.items ?? body?.item;
  const items = Array.isArray(rawItems) ? rawItems : rawItems ? [rawItems] : [];
  if (resultCode !== "00") throw new Error(`fare API response rejected: resultCode=${resultCode || "missing"}`);
  return items;
}

function validatedFareItem(items, origin, destination) {
  const matching = items.filter((item) => item && typeof item === "object" && !Array.isArray(item)
    && item.dptreStnCd === origin.fareStationCode
    && item.dptreStnNm === origin.stationName
    && item.arvlStnCd === destination.fareStationCode
    && item.arvlStnNm === destination.stationName);
  if (matching.length !== 1) throw new Error("fare API response mapping is absent or ambiguous");
  const fares = {};
  for (const field of REQUIRED_FARE_FIELDS) {
    const value = matching[0][field];
    if (!Number.isSafeInteger(value) || value < 0) throw new Error(`fare API field invalid: ${field}`);
    fares[field] = value;
  }
  return fares;
}

async function fetchFareQuote({ destination, fareServiceKey, fetchImpl, origin, retryDelayMs, timeoutMs }) {
  const { attempts, response } = await fetchWithRetry({
    fetchImpl,
    url: fareUrl({ fareServiceKey, origin, destination }),
    timeoutMs,
    retryDelayMs,
    label: "fare API",
  });
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new Error("fare API returned invalid JSON");
  }
  return { attempts, fares: validatedFareItem(responseItems(payload), origin, destination) };
}

export async function probeOfficialOdFares({
  fareServiceKey,
  seoulOpenApiKey,
  outputPath,
  fetchImpl = fetch,
  retryDelayMs = 250,
  timeoutMs = 30_000,
} = {}) {
  try {
    requiredText(fareServiceKey, "DATA_GO_KR_SERVICE_KEY");
    requiredText(seoulOpenApiKey, "SEOUL_OPENAPI_KEY");
    if (!path.isAbsolute(requiredText(outputPath, "FARE_API_PROBE_OUTPUT"))) {
      throw new Error("FARE_API_PROBE_OUTPUT must be an absolute path");
    }

    const canaryRows = [];
    for (const expected of CANARIES) {
      const row = await fetchCatalogStation({
        apiKey: seoulOpenApiKey,
        fetchImpl,
        lineNumber: expected.lineNumber,
        retryDelayMs,
        stationName: expected.stationName,
        timeoutMs,
      });
      canaryRows.push({ expected, row });
    }
    const selectedFareCodeField = selectFareCodeField(canaryRows);

    const providerMappings = [];
    for (const target of TARGETS) {
      const row = await fetchCatalogStation({
        apiKey: seoulOpenApiKey,
        fetchImpl,
        lineNumber: target.lineNumber,
        retryDelayMs,
        stationName: target.stationName,
        timeoutMs,
      });
      const fareStationCode = row[selectedFareCodeField];
      if (!/^\d{4}$/.test(fareStationCode)) throw new Error(`catalog fare code invalid: ${target.stationName}`);
      providerMappings.push({
        stationId: target.stationId,
        lineId: target.lineId,
        stationName: target.stationName,
        fareStationCode,
      });
    }
    if (new Set(providerMappings.map(({ fareStationCode }) => fareStationCode)).size !== providerMappings.length) {
      throw new Error("catalog target fare codes must be distinct");
    }

    const directions = [[providerMappings[0], providerMappings[1]], [providerMappings[1], providerMappings[0]]];
    const quotes = [];
    const attemptCounts = {};
    for (const [origin, destination] of directions) {
      const { attempts, fares } = await fetchFareQuote({
        destination,
        fareServiceKey,
        fetchImpl,
        origin,
        retryDelayMs,
        timeoutMs,
      });
      const directionKey = `${origin.stationId}→${destination.stationId}`;
      attemptCounts[directionKey] = attempts;
      quotes.push({ originStationId: origin.stationId, destinationStationId: destination.stationId, fares });
    }

    const equivalence = Object.fromEntries(canaryRows.map(({ expected, row }) => [expected.evidenceKey, {
      selectedCatalogCode: row[selectedFareCodeField],
      fareCode: expected.fareCode,
      verified: true,
    }]));
    const evidence = {
      schemaVersion: 1,
      artifactKind: "official-od-fare-probe-evidence",
      catalogAvailability: "AVAILABLE",
      selectedFareCodeField,
      equivalence,
      providerMappings,
      quotes,
      fieldNames: [...REQUIRED_FARE_FIELDS].sort(),
      attemptCounts,
    };
    await writeFile(outputPath, `${JSON.stringify(evidence, null, 2)}\n`, { mode: 0o600 });
    await chmod(outputPath, 0o600);
    return evidence;
  } catch (error) {
    throw new Error(sanitizeProbeError(error, [fareServiceKey, seoulOpenApiKey]));
  }
}

async function main() {
  const evidence = await probeOfficialOdFares({
    fareServiceKey: process.env.DATA_GO_KR_SERVICE_KEY,
    seoulOpenApiKey: process.env.SEOUL_OPENAPI_KEY,
    outputPath: process.env.FARE_API_PROBE_OUTPUT,
  });
  process.stdout.write(`${JSON.stringify(evidence)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : "fare API probe failed"}\n`);
    process.exitCode = 1;
  });
}
