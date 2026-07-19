#!/usr/bin/env node
import { createHash } from "node:crypto";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const PROVIDER_BASE = "https://apis.data.go.kr/1613000/TrainInfo/";
const PAGE_SIZE = 100;
const MAX_PAGES = 100;
const TIMEOUT_MS = 10_000;
const PROVIDER_OPERATIONS = Object.freeze([
  "GetCtyCodeList",
  "GetCtyAcctoTrainSttnList",
  "GetVhcleKndList",
  "GetStrtpntAlocFndTrainInfo",
]);
const SUPPORTED_TRAIN_TYPES = Object.freeze([
  "KTX",
  "KTX_SANCHEON",
  "SRT",
  "ITX_MAUM",
  "ITX_SAEMAEUL",
  "SAEMAEUL",
  "MUGUNGHWA",
  "NURIRO",
]);

const TRAIN_TYPE_BY_NORMALIZED_NAME = new Map([
  ["KTX", "KTX"],
  ["KTX산천", "KTX_SANCHEON"],
  ["SRT", "SRT"],
  ["ITX마음", "ITX_MAUM"],
  ["ITX새마을", "ITX_SAEMAEUL"],
  ["ITX청춘", "ITX_CHEONGCHUN"],
  ["새마을", "SAEMAEUL"],
  ["새마을호", "SAEMAEUL"],
  ["무궁화", "MUGUNGHWA"],
  ["무궁화호", "MUGUNGHWA"],
  ["누리로", "NURIRO"],
]);

export function normalizeProviderTrainType(value) {
  const normalized = requiredString(value, "provider train type")
    .replace(/[^0-9A-Za-z가-힣]/gu, "")
    .toUpperCase();
  if (normalized.startsWith("KTX산천")) return "KTX_SANCHEON";
  return TRAIN_TYPE_BY_NORMALIZED_NAME.get(normalized) ?? normalized;
}

export function validateProviderEnvelope(payload, {
  operation,
  paginated,
  pageNo = 1,
  pageSize = PAGE_SIZE,
} = {}) {
  if (!payload || typeof payload !== "object") throw new Error(`${operation} payload was not an object`);
  const response = payload.response;
  if (!response || typeof response !== "object") throw new Error(`${operation} response schema was invalid`);
  if (String(response.header?.resultCode ?? "") !== "00") {
    throw new Error(`${operation} provider resultCode was not 00`);
  }
  const body = response.body;
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new Error(`${operation} body schema was invalid`);
  }
  itemRows(body, operation);
  if (paginated) {
    if (integer(body.pageNo, `${operation}.pageNo`) !== pageNo
      || integer(body.numOfRows, `${operation}.numOfRows`) !== pageSize
      || integer(body.totalCount, `${operation}.totalCount`) < 0) {
      throw new Error(`${operation} pagination schema was invalid`);
    }
  }
  return body;
}

export function validateBackendSearchEnvelope(payload, {
  departureStationId,
  arrivalStationId,
  trainType,
  departureDate,
} = {}) {
  if (payload?.success !== true || !payload.data || typeof payload.data !== "object") {
    throw new Error("backend train search envelope was invalid");
  }
  const { observedAt, outbound, inbound } = payload.data;
  if (!validDateTime(observedAt) || !Array.isArray(outbound) || !Array.isArray(inbound) || inbound.length !== 0) {
    throw new Error("backend train search result schema was invalid");
  }
  const rows = [...outbound, ...inbound];
  const itxCheongchunRowCount = rows.filter((row) => row?.trainType === "ITX_CHEONGCHUN").length;
  if (itxCheongchunRowCount !== 0) {
    throw new Error("backend train search returned ITX_CHEONGCHUN rows");
  }
  for (const [index, row] of rows.entries()) validateJourney(row, `journey[${index}]`);
  requireDate(departureDate);
  if (outbound.some((row) => (
    row.departureStationId !== departureStationId
      || row.arrivalStationId !== arrivalStationId
      || row.trainType !== trainType
      || koreaServiceDate(row.departureAt) !== departureDate
  ))) {
    throw new Error("backend outbound row did not match the requested leg");
  }
  return {
    observedAt,
    rowCount: outbound.length,
    fareRowCount: outbound.filter((row) => Number.isInteger(row.adultFareWon) && row.adultFareWon >= 0).length,
    itxCheongchunRowCount,
  };
}

export function addProviderStation(stations, id, name) {
  const existing = stations.get(id);
  if (existing !== undefined && existing !== name) {
    throw new Error(`TAGO station ID conflict: ${id}`);
  }
  if (existing === undefined) stations.set(id, name);
}

export async function collectProviderEvidence({
  serviceKey,
  departureDate,
  departureStationId,
  arrivalStationId,
  fetchImpl = fetch,
  now = new Date(),
} = {}) {
  const key = decodedServiceKey(requiredString(serviceKey, "DATA_GO_KR_SERVICE_KEY"));
  requireDate(departureDate);
  const operations = [];
  const gradesResult = await providerRows("GetVhcleKndList", {}, key, fetchImpl, false);
  operations.push(gradesResult.evidence);
  const citiesResult = await providerRows("GetCtyCodeList", {}, key, fetchImpl, false);
  operations.push(citiesResult.evidence);

  const grades = gradesResult.rows.map((row, index) => ({
    code: requiredString(row?.vehiclekndid, `grade[${index}].vehiclekndid`),
    name: requiredString(row?.vehiclekndnm, `grade[${index}].vehiclekndnm`),
    trainType: normalizeProviderTrainType(row?.vehiclekndnm),
  }));
  const supportedTrainTypes = [...new Set(grades
    .map(({ trainType }) => trainType)
    .filter((trainType) => SUPPORTED_TRAIN_TYPES.includes(trainType)))].sort();
  const expectedTypes = [...SUPPORTED_TRAIN_TYPES].sort();
  if (JSON.stringify(supportedTrainTypes) !== JSON.stringify(expectedTypes)) {
    throw new Error(`TAGO supported train types were incomplete: ${supportedTrainTypes.join(",")}`);
  }

  const stations = new Map();
  for (const [index, city] of citiesResult.rows.entries()) {
    const cityCode = requiredString(city?.citycode, `city[${index}].citycode`);
    requiredString(city?.cityname, `city[${index}].cityname`);
    const result = await providerRows("GetCtyAcctoTrainSttnList", { cityCode }, key, fetchImpl, true);
    operations.push(result.evidence);
    for (const [stationIndex, row] of result.rows.entries()) {
      const id = requiredString(row?.nodeid, `station[${stationIndex}].nodeid`);
      const name = requiredString(row?.nodename, `station[${stationIndex}].nodename`);
      addProviderStation(stations, id, name);
    }
  }
  const departureName = stations.get(requiredString(departureStationId, "departureStationId"));
  const arrivalName = stations.get(requiredString(arrivalStationId, "arrivalStationId"));
  if (!departureName || !arrivalName) throw new Error("TAGO station catalog did not contain both requested stations");

  const ktxCodes = grades.filter(({ trainType }) => trainType === "KTX").map(({ code }) => code).sort();
  if (ktxCodes.length === 0) throw new Error("TAGO KTX provider grade was missing");
  const scheduleRows = [];
  for (const trainGradeCode of ktxCodes) {
    const result = await providerRows("GetStrtpntAlocFndTrainInfo", {
      depPlaceId: departureStationId,
      arrPlaceId: arrivalStationId,
      depPlandTime: departureDate.replaceAll("-", ""),
      trainGradeCode,
    }, key, fetchImpl, true);
    operations.push(result.evidence);
    scheduleRows.push(...result.rows);
  }
  const journeys = scheduleRows.map((row, index) => providerJourney(row, index, {
    departureStationId,
    departureStationName: departureName,
    arrivalStationId,
    arrivalStationName: arrivalName,
    departureDate,
  }));
  const fareRows = journeys.filter((row) => row.trainType === "KTX" && row.adultFareWon >= 0);
  if (fareRows.length === 0) throw new Error("TAGO Seoul-Daejeon KTX fare row was missing");
  const itxCheongchunRowCount = journeys.filter((row) => row.trainType === "ITX_CHEONGCHUN").length;
  if (itxCheongchunRowCount !== 0) throw new Error("TAGO KTX query returned ITX_CHEONGCHUN rows");
  const observedOperations = new Set(operations.map(({ operation }) => operation));
  if (!PROVIDER_OPERATIONS.every((operation) => observedOperations.has(operation))) {
    throw new Error("TAGO operation evidence was incomplete");
  }

  return {
    observedAt: now.toISOString(),
    httpSuccess: true,
    resultCode: "00",
    schemaStatus: "EXPECTED",
    operations: PROVIDER_OPERATIONS,
    operationEvidence: operations,
    supportedTrainTypes: SUPPORTED_TRAIN_TYPES,
    gradeNames: grades.map(({ name }) => name).sort((left, right) => left.localeCompare(right, "ko")),
    stationCount: stations.size,
    stationConflictCount: 0,
    departureStation: { id: departureStationId, name: departureName },
    arrivalStation: { id: arrivalStationId, name: arrivalName },
    scheduleRowCount: journeys.length,
    fareRowCount: fareRows.length,
    itxCheongchunRowCount,
    credentialRedacted: true,
  };
}

export async function collectBackendEvidence({
  baseUrl,
  candidateGitSha,
  deploymentRunUrl,
  departureDate,
  departureQuery = "서울",
  arrivalQuery = "대전",
  fetchImpl = fetch,
  now = new Date(),
} = {}) {
  const origin = publicHttpsOrigin(baseUrl);
  const candidateSha = requireSha(candidateGitSha);
  const deployment = await deploymentEvidence(deploymentRunUrl, candidateSha, fetchImpl);
  requireDate(departureDate);
  const departure = await backendStation(origin, departureQuery, fetchImpl);
  const arrival = await backendStation(origin, arrivalQuery, fetchImpl);
  const searchUrl = new URL("/api/v1/trains/search", origin);
  searchUrl.searchParams.set("departureStationId", departure.id);
  searchUrl.searchParams.set("arrivalStationId", arrival.id);
  searchUrl.searchParams.set("departureDate", departureDate);
  searchUrl.searchParams.set("trainType", "KTX");
  const first = await fetchWithTimeout(searchUrl, {}, fetchImpl);
  requireBackendSuccessHeaders(first, "train search");
  const search = validateBackendSearchEnvelope(await responseJson(first, "train search"), {
    departureStationId: departure.id,
    arrivalStationId: arrival.id,
    trainType: "KTX",
    departureDate,
  });
  if (search.fareRowCount === 0 || search.itxCheongchunRowCount !== 0) {
    throw new Error("backend KTX fare or ITX exclusion evidence failed");
  }
  const etag = first.headers.get("etag");
  const conditional = await fetchWithTimeout(searchUrl, { headers: { "if-none-match": etag } }, fetchImpl);
  if (conditional.status !== 304) throw new Error(`train search conditional request returned HTTP ${conditional.status}`);

  const unsupportedStations = new URL("/api/v1/trains/stations", origin);
  unsupportedStations.searchParams.set("query", departureQuery);
  unsupportedStations.searchParams.set("trainType", "ITX_CHEONGCHUN");
  await requireUnsupported(unsupportedStations, fetchImpl);
  const unsupportedSearch = new URL(searchUrl);
  unsupportedSearch.searchParams.set("trainType", "ITX_CHEONGCHUN");
  await requireUnsupported(unsupportedSearch, fetchImpl);

  return {
    observedAt: now.toISOString(),
    deployedGitSha: deployment.deployedGitSha,
    deployment,
    origin: origin.origin,
    stationQueries: [departureQuery, arrivalQuery],
    departureStationId: departure.id,
    arrivalStationId: arrival.id,
    seoulDaejeonKtxFareRows: search.fareRowCount,
    itxCheongchunRows: search.itxCheongchunRowCount,
    conditionalEtagStatus: 304,
    errorCacheControl: "no-store",
    schemaStatus: "EXPECTED",
  };
}

async function backendStation(origin, query, fetchImpl) {
  const url = new URL("/api/v1/trains/stations", origin);
  url.searchParams.set("query", query);
  url.searchParams.set("trainType", "KTX");
  const response = await fetchWithTimeout(url, {}, fetchImpl);
  requireBackendSuccessHeaders(response, `${query} station search`);
  const payload = await responseJson(response, `${query} station search`);
  if (payload?.success !== true || !Array.isArray(payload.data)) {
    throw new Error(`${query} station search schema was invalid`);
  }
  const station = payload.data.find((row) => row?.name === query && typeof row?.id === "string" && row.id !== "");
  if (!station) throw new Error(`${query} station search did not return the exact station`);
  return { id: station.id, name: station.name };
}

async function requireUnsupported(url, fetchImpl) {
  const response = await fetchWithTimeout(url, {}, fetchImpl);
  if (response.status !== 400 || response.headers.get("cache-control") !== "no-store") {
    throw new Error(`ITX_CHEONGCHUN rejection returned HTTP ${response.status}`);
  }
  const payload = await responseJson(response, "ITX_CHEONGCHUN rejection");
  if (payload?.success !== false || payload?.data?.code !== "TRAIN_SEARCH_UNSUPPORTED_TRAIN_TYPE") {
    throw new Error("ITX_CHEONGCHUN rejection schema was invalid");
  }
}

function requireBackendSuccessHeaders(response, label) {
  if (response.status !== 200) throw new Error(`${label} returned HTTP ${response.status}`);
  const etag = response.headers.get("etag") ?? "";
  if (!/^(W\/)?"[0-9a-f]{64}"$/.test(etag)) {
    throw new Error(`${label} ETag was invalid: ${JSON.stringify(etag)}`);
  }
  if (!(response.headers.get("cache-control") ?? "").includes("max-age=")) {
    throw new Error(`${label} Cache-Control was invalid`);
  }
}

async function providerRows(operation, parameters, key, fetchImpl, paginated) {
  const rows = [];
  const rawHashes = [];
  let pageNo = 1;
  let totalCount;
  let requestCount = 0;
  for (;;) {
    const query = paginated ? { pageNo: String(pageNo), numOfRows: String(PAGE_SIZE), ...parameters } : parameters;
    const url = new URL(operation, PROVIDER_BASE);
    for (const [name, value] of Object.entries({ serviceKey: key, _type: "json", ...query })) {
      url.searchParams.set(name, value);
    }
    const response = await fetchWithRetry(url, fetchImpl);
    requestCount += response.attempts;
    if (!response.value.ok) throw new Error(`${operation} returned HTTP ${response.value.status}`);
    const text = await response.value.text();
    rawHashes.push(sha256(text));
    let payload;
    try { payload = JSON.parse(text); } catch { throw new Error(`${operation} returned invalid JSON`); }
    const body = validateProviderEnvelope(payload, { operation, paginated, pageNo, pageSize: PAGE_SIZE });
    const pageRows = itemRows(body, operation);
    if (!paginated) {
      rows.push(...pageRows);
      totalCount = pageRows.length;
      break;
    }
    const reportedTotal = integer(body.totalCount, `${operation}.totalCount`);
    if (totalCount === undefined) totalCount = reportedTotal;
    if (reportedTotal !== totalCount) throw new Error(`${operation} totalCount changed during pagination`);
    const expectedRows = Math.min(PAGE_SIZE, Math.max(0, totalCount - rows.length));
    if (pageRows.length !== expectedRows) throw new Error(`${operation} page row count was invalid`);
    rows.push(...pageRows);
    if (rows.length === totalCount) break;
    pageNo += 1;
    if (pageNo > MAX_PAGES) throw new Error(`${operation} exceeded the pagination limit`);
  }
  return {
    rows,
    evidence: {
      operation,
      endpoint: new URL(operation, PROVIDER_BASE).toString(),
      httpSuccess: true,
      providerResultCode: "00",
      schemaStatus: "EXPECTED",
      pageCount: rawHashes.length,
      requestCount,
      totalCount,
      rawResponseSha256: sha256(rawHashes.join("|")),
    },
  };
}

async function fetchWithRetry(url, fetchImpl) {
  let lastError;
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    try {
      const value = await fetchWithTimeout(url, {}, fetchImpl);
      if (attempt === 1 && (value.status === 408 || value.status === 429 || value.status >= 500)) continue;
      return { value, attempts: attempt };
    } catch (error) {
      lastError = error;
      if (attempt === 2) break;
    }
  }
  throw new Error(`provider transport failed: ${lastError instanceof Error ? lastError.name : "unknown"}`);
}

async function fetchWithTimeout(url, options, fetchImpl) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    return await fetchImpl(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

export function providerJourney(row, index, {
  departureStationId,
  departureStationName,
  arrivalStationId,
  arrivalStationName,
  departureDate,
}) {
  const departureAt = requiredString(row?.depplandtime, `journey[${index}].depplandtime`);
  const arrivalAt = requiredString(row?.arrplandtime, `journey[${index}].arrplandtime`);
  if (!/^\d{14}$/.test(departureAt) || !/^\d{14}$/.test(arrivalAt) || arrivalAt <= departureAt) {
    throw new Error(`journey[${index}] time was invalid`);
  }
  const fare = integer(row?.adultcharge, `journey[${index}].adultcharge`);
  if (fare < 0) throw new Error(`journey[${index}] fare was invalid`);
  const actualDepartureName = requiredString(row?.depplacename, `journey[${index}].depplacename`);
  const actualArrivalName = requiredString(row?.arrplacename, `journey[${index}].arrplacename`);
  if (normalizeStationName(actualDepartureName) !== normalizeStationName(departureStationName)
    || normalizeStationName(actualArrivalName) !== normalizeStationName(arrivalStationName)
    || departureAt.slice(0, 8) !== departureDate.replaceAll("-", "")) {
    throw new Error(`journey[${index}] provider journey OD or date mismatch`);
  }
  return {
    trainNumber: requiredString(row?.trainno, `journey[${index}].trainno`),
    trainType: normalizeProviderTrainType(row?.traingradename),
    departureStationId,
    departureStationName: actualDepartureName,
    departureAt,
    arrivalStationId,
    arrivalStationName: actualArrivalName,
    arrivalAt,
    adultFareWon: fare,
  };
}

export function validateDeploymentRun(run, jobsPayload, { candidateGitSha, deploymentRunUrl }) {
  const url = deploymentUrl(deploymentRunUrl);
  const runId = Number(url.pathname.split("/").at(-1));
  if (run?.id !== runId
    || run?.name !== "CD"
    || run?.head_sha !== candidateGitSha
    || run?.status !== "completed"
    || run?.conclusion !== "success"
    || run?.html_url !== url.toString()
    || run?.repository?.full_name !== "AquilaXk/easysubway") {
    throw new Error("deployment workflow run did not match the candidate");
  }
  const requiredJobs = ["CD Deploy", "Post-deploy smoke", "CD Record deployment"];
  if (!Array.isArray(jobsPayload?.jobs)
    || requiredJobs.some((name) => !jobsPayload.jobs.some((job) => (
      job?.name === name && job?.conclusion === "success"
    )))) {
    throw new Error("deployment workflow jobs were incomplete");
  }
  return {
    runId,
    runUrl: url.toString(),
    workflowName: run.name,
    deployedGitSha: run.head_sha,
    conclusion: run.conclusion,
    requiredJobs,
  };
}

async function deploymentEvidence(value, candidateGitSha, fetchImpl) {
  const runUrl = deploymentUrl(value);
  const runId = runUrl.pathname.split("/").at(-1);
  const apiBase = `https://api.github.com/repos/AquilaXk/easysubway/actions/runs/${runId}`;
  const headers = {
    accept: "application/vnd.github+json",
    "user-agent": "easysubway-train-search-evidence",
  };
  const runResponse = await fetchWithTimeout(apiBase, { headers }, fetchImpl);
  if (!runResponse.ok) throw new Error(`deployment workflow run returned HTTP ${runResponse.status}`);
  const jobsResponse = await fetchWithTimeout(`${apiBase}/jobs?per_page=100`, { headers }, fetchImpl);
  if (!jobsResponse.ok) throw new Error(`deployment workflow jobs returned HTTP ${jobsResponse.status}`);
  return validateDeploymentRun(
    await responseJson(runResponse, "deployment workflow run"),
    await responseJson(jobsResponse, "deployment workflow jobs"),
    { candidateGitSha, deploymentRunUrl: runUrl.toString() },
  );
}

function deploymentUrl(value) {
  const url = new URL(requiredString(value, "--deployment-run-url"));
  if (url.protocol !== "https:"
    || url.hostname !== "github.com"
    || !/^\/AquilaXk\/easysubway\/actions\/runs\/[1-9][0-9]*$/u.test(url.pathname)
    || url.search
    || url.hash
    || url.username
    || url.password) {
    throw new Error("--deployment-run-url must identify the EasySubway GitHub Actions run");
  }
  return url;
}

function normalizeStationName(value) {
  return requiredString(value, "station name").replace(/[^0-9A-Za-z가-힣]/gu, "").toUpperCase();
}

function koreaServiceDate(value) {
  const korea = new Date(Date.parse(value) + (9 * 60 * 60 * 1_000));
  if (korea.getUTCHours() < 3) korea.setUTCDate(korea.getUTCDate() - 1);
  return korea.toISOString().slice(0, 10);
}

function validateJourney(row, label) {
  const requiredText = [
    "trainNumber", "trainType", "departureStationId", "departureStationName",
    "departureAt", "arrivalStationId", "arrivalStationName", "arrivalAt",
  ];
  for (const field of requiredText) requiredString(row?.[field], `${label}.${field}`);
  if (!SUPPORTED_TRAIN_TYPES.includes(row.trainType)) throw new Error(`${label}.trainType was unsupported`);
  if (!validDateTime(row.departureAt) || !validDateTime(row.arrivalAt)
    || Date.parse(row.arrivalAt) <= Date.parse(row.departureAt)
    || !Number.isInteger(row.durationMinutes) || row.durationMinutes <= 0
    || !Number.isInteger(row.adultFareWon) || row.adultFareWon < 0) {
    throw new Error(`${label} time or fare was invalid`);
  }
}

function itemRows(body, operation) {
  const item = body.items?.item;
  if (item === undefined || item === null || item === "") return [];
  if (Array.isArray(item)) return item;
  if (typeof item === "object") return [item];
  throw new Error(`${operation} item schema was invalid`);
}

async function responseJson(response, label) {
  try { return await response.json(); } catch { throw new Error(`${label} returned invalid JSON`); }
}

function decodedServiceKey(value) {
  const trimmed = value.trim();
  return /%[0-9A-Fa-f]{2}/.test(trimmed) ? decodeURIComponent(trimmed) : trimmed;
}

function publicHttpsOrigin(value) {
  const url = new URL(requiredString(value, "--base-url"));
  if (url.origin !== "https://easysubway-api.aquilaxk.site"
    || url.username || url.password || url.search || url.hash || url.pathname !== "/") {
    throw new Error("--base-url must be the EasySubway production HTTPS origin");
  }
  return url;
}

function requireSha(value) {
  const text = requiredString(value, "--candidate-sha");
  if (!/^[0-9a-f]{40}$/.test(text)) throw new Error("--candidate-sha must be a full Git SHA");
  return text;
}

function requireDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value ?? "") || Number.isNaN(Date.parse(`${value}T00:00:00Z`))) {
    throw new Error("--date must be YYYY-MM-DD");
  }
  return value;
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`${label} is required`);
  return value.trim();
}

function integer(value, label) {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isInteger(parsed)) throw new Error(`${label} was not an integer`);
  return parsed;
}

function validDateTime(value) {
  if (typeof value !== "string") return false;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/u.exec(value);
  if (!match) return false;
  const [year, month, day, hour, minute, second] = match.slice(1, 7).map(Number);
  const maxDay = [31, leapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
  if (month < 1 || month > 12 || day < 1 || day > maxDay
    || hour > 23 || minute > 59 || second > 59) return false;
  if (match[7] !== "Z") {
    const [offsetHour, offsetMinute] = match[7].slice(1).split(":").map(Number);
    if (offsetHour > 23 || offsetMinute > 59) return false;
  }
  return true;
}

function leapYear(year) {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    if (!flag?.startsWith("--") || argv[index + 1] === undefined) throw new Error("arguments must be --name value pairs");
    result[flag.slice(2)] = argv[index + 1];
  }
  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const output = requiredString(args.output, "--output");
  if (!path.isAbsolute(output)) throw new Error("--output must be absolute");
  const mode = args.mode ?? "both";
  if (!new Set(["provider", "backend", "both"]).has(mode)) {
    throw new Error("--mode must be provider, backend, or both");
  }
  const provider = mode === "backend" ? null : await collectProviderEvidence({
    serviceKey: process.env.DATA_GO_KR_SERVICE_KEY,
    departureDate: args.date,
    departureStationId: requiredString(args["departure-station-id"], "--departure-station-id"),
    arrivalStationId: requiredString(args["arrival-station-id"], "--arrival-station-id"),
  });
  const backend = mode === "provider" ? null : await collectBackendEvidence({
    baseUrl: args["base-url"],
    candidateGitSha: args["candidate-sha"],
    deploymentRunUrl: args["deployment-run-url"],
    departureDate: args.date,
  });
  const artifact = {
    schemaVersion: 1,
    artifactKind: "train-search-live-smoke",
    candidateGitSha: args["candidate-sha"] ? requireSha(args["candidate-sha"]) : null,
    provider,
    backend,
    credentialRedacted: true,
  };
  artifact.evidenceSha256 = sha256(JSON.stringify(artifact));
  await writeFile(output, `${JSON.stringify(artifact, null, 2)}\n`, { mode: 0o600 });
  console.log(`train-search live smoke PASS: provider=${provider ? "PASS" : "SKIPPED"} backend=${backend ? "PASS" : "SKIPPED"}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "train-search live smoke failed");
    process.exitCode = 1;
  });
}
