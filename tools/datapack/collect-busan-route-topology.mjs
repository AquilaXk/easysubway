#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { scanXmlStructure } from "./lib/source-candidate-evidence-collector.mjs";

const ENDPOINT = "http://data.humetro.busan.kr/voc/api/open_api_distance.tnn"; // NOSONAR -- provider contract is HTTP-only
const DETAIL_URL = "https://www.data.go.kr/data/15001019/openapi.do";
const FIELDS = ["startSn", "startSc", "endSn", "endSc", "dist", "time", "stoppingTime", "exchange"];
const LINE_IDS = Object.freeze({
  1: "line-ab1a041f6266",
  2: "line-eb7b47920390",
  3: "line-d74614a04530",
  4: "line-d812a5bc1e5f",
});
const EXPECTED_LINE_IDS = Object.values(LINE_IDS).sort((left, right) => left.localeCompare(right, "en"));
const XML_CONTENT_TYPES = new Set(["application/xml", "text/xml"]);
const FRESHNESS_MILLIS = 24 * 60 * 60 * 1000;

export async function collectBusanRouteTopology({
  serviceKey,
  stationCode = null,
  stationScopes = null,
  fetchImpl = fetch,
  now = new Date(),
  concurrency = 4,
} = {}) {
  const capturedAt = validDate(now, "now");
  const key = decodedServiceKey(requiredValue(serviceKey, "DATA_GO_KR_SERVICE_KEY"));
  const scope = stationScopes == null ? null : validateStationScopes(stationScopes);
  if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 4) throw new Error("concurrency is invalid");
  const requestCodes = scope ? scope.map(({ stationCode: code }) => code) : [stationCode];
  const responses = new Array(requestCodes.length);
  let next = 0;
  let aborted = false;
  const failures = [];
  const worker = async () => {
    while (!aborted && next < requestCodes.length) {
      const index = next;
      next += 1;
      try {
        responses[index] = await collectResponse({ key, stationCode: requestCodes[index], fetchImpl });
      } catch (error) {
        aborted = true;
        failures.push(error);
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, requestCodes.length) }, () => worker()));
  if (failures.length > 0) throw failures[0];
  const edges = responses.flatMap((response) => response.edges)
    .sort((left, right) => left.edgeId.localeCompare(right.edgeId, "en"));
  const duplicate = edges.find((edge, index) => index > 0 && edges[index - 1].edgeId === edge.edgeId);
  if (duplicate) throw new Error(`Busan route topology schema mismatch: duplicate edge ${duplicate.edgeId}`);
  if (scope) validateEdgesAgainstScope(edges, scope);
  const lineIds = [...new Set(edges.map(({ lineId }) => lineId))].sort((left, right) => left.localeCompare(right, "en"));
  const rawSha256 = sha256(JSON.stringify(responses.map((response, index) => ({
    stationCode: requestCodes[index],
    rawSha256: response.rawSha256,
  }))));
  if (JSON.stringify(lineIds) !== JSON.stringify(EXPECTED_LINE_IDS)) {
    throw new Error(`Busan route topology schema mismatch: line scope: lines=${lineIds.join(",") || "none"}; `
      + `edges=${edges.length}; rawSha256=${rawSha256}`);
  }
  return {
    schemaVersion: 1,
    artifactKind: "busan-route-topology-snapshot",
    sourceId: "busan-transportation-route-topology",
    detailUrl: DETAIL_URL,
    endpoint: ENDPOINT,
    capturedAt: capturedAt.toISOString(),
    freshUntil: new Date(capturedAt.getTime() + FRESHNESS_MILLIS).toISOString(),
    official: true,
    fixture: false,
    credentialRedacted: true,
    requestCount: responses.length,
    excludedTransferCount: responses.reduce((sum, response) => sum + response.excludedTransferCount, 0),
    stationCount: scope?.length ?? new Set(edges.flatMap(({ fromStationCode, toStationCode }) => [fromStationCode, toStationCode])).size,
    rowCount: edges.length,
    edgeCount: edges.length,
    lineIds,
    fieldsProvided: ["network_edges", "duration_seconds", "distance_meters"],
    license: {
      type: "KOGL-1",
      attribution: "부산교통공사, 공공누리 제1유형(출처표시); 제3자 권리 포함 저작권 표시",
      redistributionAllowed: true,
      evidenceUrl: DETAIL_URL,
    },
    scope,
    scopeSha256: scope ? sha256(JSON.stringify(scope)) : null,
    rawSha256,
    contentSha256: contentHash(edges, scope),
    edges,
  };
}

async function collectResponse({ key, stationCode, fetchImpl }) {
  const url = new URL(ENDPOINT);
  url.searchParams.set("serviceKey", key);
  url.searchParams.set("act", "xml");
  if (stationCode != null) {
    if (!lineIdForStationCode(stationCode)) throw new Error("stationCode must be an admitted Busan station code");
    url.searchParams.set("scode", stationCode);
  }
  const response = await fetchWithRetry(url, fetchImpl);
  const raw = await response.text();
  const rawEvidence = `rawBytes=${Buffer.byteLength(raw)}; rawSha256=${sha256(raw)}`;
  if (!response.ok) throw new Error(`Busan route topology HTTP ${response.status}; ${rawEvidence}`);
  const contentType = response.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase() ?? "";
  if (!XML_CONTENT_TYPES.has(contentType)) {
    throw new Error(`Busan route topology schema mismatch: content-type ${safeToken(contentType || "missing")}; ${rawEvidence}`);
  }
  const providerResultCode = scalar(raw, "resultCode");
  if (providerResultCode && !new Set(["0", "00", "SUCCESS"]).has(providerResultCode.toUpperCase())) {
    const resultMessage = scalar(raw, "resultMsg") ?? "";
    throw new Error(`Busan route topology provider resultCode ${safeToken(providerResultCode)}; `
      + `classification=${classifyProviderFailure(resultMessage)}; ${rawEvidence}`);
  }
  let parsed;
  try {
    parsed = parseEdges(raw);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Busan route topology schema mismatch";
    throw new Error(`${message}; requestScope=${stationCode ?? "all"}; stationPairs=${stationPairs(raw)}; `
      + `tags=${scanXmlStructure(raw).tagSummary}; ${rawEvidence}`);
  }
  if (stationCode != null && parsed.edges.some(({ fromStationCode }) => fromStationCode !== stationCode)) {
    throw new Error(`Busan route topology schema mismatch: request scope ${stationCode}; ${rawEvidence}`);
  }
  return { ...parsed, rawSha256: sha256(raw) };
}

export function parseBusanRouteTopologyScope(html) {
  if (typeof html !== "string" || html.length === 0) throw new Error("Busan route topology scope HTML is required");
  const stations = new Map();
  for (const match of html.matchAll(/one_point\(\s*'(\d{2,3})'\s*,\s*'([1-4])'\s*,\s*'([^']{1,100})'/g)) {
    const [, stationCode, lineCode, encodedName] = match;
    if (lineIdForStationCode(stationCode) !== LINE_IDS[lineCode]) {
      throw new Error(`Busan route topology scope station line mismatch: ${stationCode}`);
    }
    if (stations.has(stationCode)) throw new Error(`Busan route topology scope duplicate station: ${stationCode}`);
    stations.set(stationCode, {
      stationCode,
      stationName: decodeXml(encodedName.trim()),
      lineId: LINE_IDS[lineCode],
      neighbors: new Set(),
    });
  }
  for (const match of html.matchAll(/<div\s+class="l(\d{2,3})-(\d{2,3})\s+l(\d{2,3})-(\d{2,3})\b[^"]*"/g)) {
    const [, from, to, reverseFrom, reverseTo] = match;
    if (from !== reverseTo || to !== reverseFrom) throw new Error(`Busan route topology scope asymmetric edge: ${from}:${to}`);
    const fromStation = stations.get(from);
    const toStation = stations.get(to);
    if (!fromStation && !toStation) continue;
    if (!fromStation || !toStation) throw new Error(`Busan route topology scope unmatched edge: ${from}:${to}`);
    if (fromStation.lineId !== toStation.lineId) throw new Error(`Busan route topology scope cross-line edge: ${from}:${to}`);
    fromStation.neighbors.add(to);
    toStation.neighbors.add(from);
  }
  const scope = [...stations.values()].map(({ neighbors, ...station }) => {
    if (neighbors.size === 0) throw new Error(`Busan route topology scope isolated station: ${station.stationCode}`);
    return { ...station, neighborCodes: [...neighbors].sort((left, right) => left.localeCompare(right, "en")) };
  }).sort((left, right) => left.stationCode.localeCompare(right.stationCode, "en"));
  return validateStationScopes(scope);
}

function validateStationScopes(scopes) {
  if (!Array.isArray(scopes) || scopes.length === 0) throw new Error("Busan route topology station scopes are required");
  const byCode = new Map();
  for (const entry of scopes) {
    const stationCode = requiredValue(entry?.stationCode, "station scope.stationCode");
    const lineId = requiredValue(entry?.lineId, `station scope ${stationCode}.lineId`);
    if (lineIdForStationCode(stationCode) !== lineId) {
      throw new Error(`Busan route topology station scope line mismatch: ${stationCode}`);
    }
    if (byCode.has(stationCode)) throw new Error(`Busan route topology station scope duplicate station: ${stationCode}`);
    const neighborCodes = entry.neighborCodes;
    if (!Array.isArray(neighborCodes) || neighborCodes.length === 0
      || neighborCodes.some((code) => !lineIdForStationCode(code))
      || new Set(neighborCodes).size !== neighborCodes.length) {
      throw new Error(`Busan route topology station scope neighbors are invalid: ${stationCode}`);
    }
    byCode.set(stationCode, {
      stationCode,
      stationName: requiredValue(entry.stationName, `station scope ${stationCode}.stationName`),
      lineId,
      neighborCodes: [...neighborCodes].sort((left, right) => left.localeCompare(right, "en")),
    });
  }
  for (const station of byCode.values()) {
    for (const neighborCode of station.neighborCodes) {
      const neighbor = byCode.get(neighborCode);
      if (!neighbor || neighbor.lineId !== station.lineId || !neighbor.neighborCodes.includes(station.stationCode)) {
        throw new Error(`Busan route topology station scope adjacency mismatch: ${station.stationCode}:${neighborCode}`);
      }
    }
  }
  const lineIds = [...new Set([...byCode.values()].map(({ lineId }) => lineId))].sort((left, right) => left.localeCompare(right, "en"));
  if (JSON.stringify(lineIds) !== JSON.stringify(EXPECTED_LINE_IDS)) {
    throw new Error("Busan route topology station scope line set is incomplete");
  }
  return [...byCode.values()].sort((left, right) => left.stationCode.localeCompare(right.stationCode, "en"));
}

function validateEdgesAgainstScope(edges, scope) {
  const actual = new Map(scope.map(({ stationCode }) => [stationCode, []]));
  for (const edge of edges) {
    if (!actual.has(edge.fromStationCode) || !actual.has(edge.toStationCode)) {
      throw new Error(`Busan route topology adjacency scope has unmatched edge: ${edge.edgeId}`);
    }
    actual.get(edge.fromStationCode).push(edge.toStationCode);
  }
  for (const station of scope) {
    const observed = actual.get(station.stationCode).sort((left, right) => left.localeCompare(right, "en"));
    if (JSON.stringify(observed) !== JSON.stringify(station.neighborCodes)) {
      throw new Error(`Busan route topology adjacency scope mismatch: ${station.stationCode}`);
    }
  }
}

export function admitBusanRouteTopology(snapshot, { now = new Date() } = {}) {
  const current = validDate(now, "now");
  if (snapshot?.schemaVersion !== 1 || snapshot.artifactKind !== "busan-route-topology-snapshot"
    || snapshot.sourceId !== "busan-transportation-route-topology" || snapshot.official !== true) {
    throw new Error("Busan route topology admission identity is invalid");
  }
  if (snapshot.fixture !== false) throw new Error("Busan route topology admission rejects fixture evidence");
  if (snapshot.license?.type !== "KOGL-1" || snapshot.license.redistributionAllowed !== true) {
    throw new Error("Busan route topology admission license is invalid");
  }
  if (JSON.stringify(snapshot.lineIds) !== JSON.stringify(EXPECTED_LINE_IDS)) {
    throw new Error("Busan route topology admission line scope is incomplete");
  }
  const scope = validateStationScopes(snapshot.scope);
  if (snapshot.stationCount !== scope.length || snapshot.requestCount !== scope.length
    || snapshot.scopeSha256 !== sha256(JSON.stringify(scope))) {
    throw new Error("Busan route topology admission station scope is invalid");
  }
  if (!Array.isArray(snapshot.edges) || snapshot.edges.length === 0
    || snapshot.edgeCount !== snapshot.edges.length || snapshot.rowCount !== snapshot.edges.length
    || snapshot.edges.some(({ lineId }) => !EXPECTED_LINE_IDS.includes(lineId))) {
    throw new Error("Busan route topology admission partial snapshot is invalid");
  }
  validateEdgesAgainstScope(snapshot.edges, scope);
  if (snapshot.contentSha256 !== contentHash(snapshot.edges, scope)) {
    throw new Error("Busan route topology admission content hash mismatch");
  }
  if (!/^[a-f0-9]{64}$/.test(snapshot.rawSha256 ?? "")) {
    throw new Error("Busan route topology admission raw hash is invalid");
  }
  const capturedAt = validDate(new Date(snapshot.capturedAt), "snapshot.capturedAt");
  if (current.getTime() < capturedAt.getTime() || current.getTime() - capturedAt.getTime() >= FRESHNESS_MILLIS) {
    throw new Error("Busan route topology admission stale snapshot is rejected");
  }
  return {
    status: "ADMITTED",
    issue: 2319,
    admittedAt: current.toISOString(),
    sourceId: snapshot.sourceId,
    contentSha256: snapshot.contentSha256,
    lineIds: snapshot.lineIds,
    edgeCount: snapshot.edgeCount,
  };
}

export function busanRouteTopologyCoverageRecords(snapshot) {
  admitBusanRouteTopology(snapshot, { now: new Date(snapshot.capturedAt) });
  return snapshot.lineIds.flatMap((lineId) => snapshot.fieldsProvided.map((field) => ({
    entityType: "source-snapshot",
    entityId: `${snapshot.sourceId}:${snapshot.contentSha256}:${lineId}:${field}`,
    field,
    sourceId: snapshot.sourceId,
    coverageScope: {
      regionIds: ["busan"],
      operatorIds: ["busan-transportation"],
      lineIds: [lineId],
      sourceDomains: ["route_graph_topology"],
    },
    derivationKind: "OFFICIAL",
    verifiedAt: snapshot.capturedAt,
  })));
}

function parseEdges(raw) {
  if (typeof raw !== "string" || !/^\s*<\?xml\b/i.test(raw) || /<!DOCTYPE|<!ENTITY/i.test(raw)) {
    throw new Error("Busan route topology schema mismatch: XML document");
  }
  const items = [...raw.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)];
  if (items.length === 0) throw new Error("Busan route topology schema mismatch: XML items");
  const seen = new Set();
  let excludedTransferCount = 0;
  const edges = items.map(([, item], index) => {
    const values = Object.fromEntries(FIELDS.map((field) => [field, scalar(item, field)]));
    if (FIELDS.some((field) => values[field] == null)) {
      throw new Error(`Busan route topology schema mismatch: item[${index}] fields`);
    }
    const { startSc, endSc } = values;
    const lineId = lineIdForStationCode(startSc);
    if (!new Set(["", "Y", "N"]).has(values.exchange)) {
      throw new Error(`Busan route topology schema mismatch: item[${index}].exchange`);
    }
    const endLineId = lineIdForStationCode(endSc);
    if (values.exchange === "Y") {
      const externalTransfer = /^[89]\d{2}$/.test(endSc);
      if (!lineId || (!endLineId && !externalTransfer) || endLineId === lineId) {
        throw new Error(`Busan route topology schema mismatch: item[${index}] transfer scope`);
      }
      excludedTransferCount += 1;
      return null;
    }
    if (!lineId || endLineId !== lineId) {
      throw new Error(`Busan route topology schema mismatch: item[${index}] station scope`);
    }
    const distanceUnits = unsignedInteger(values.dist, 1, 100_000, `item[${index}].dist`);
    const durationSeconds = unsignedInteger(values.time, 1, 86_400, `item[${index}].time`);
    const stoppingSeconds = unsignedInteger(values.stoppingTime, 0, 3_600, `item[${index}].stoppingTime`);
    const lineCode = Object.keys(LINE_IDS).find((code) => LINE_IDS[code] === lineId);
    const edgeId = `busan:${lineCode}:${startSc}:${endSc}`;
    if (seen.has(edgeId)) throw new Error(`Busan route topology schema mismatch: duplicate edge ${edgeId}`);
    seen.add(edgeId);
    return {
      edgeId,
      lineId,
      fromStationCode: startSc,
      fromStationName: requiredText(values.startSn, `item[${index}].startSn`),
      toStationCode: endSc,
      toStationName: requiredText(values.endSn, `item[${index}].endSn`),
      distanceMeters: distanceUnits * 100,
      durationSeconds,
      stoppingSeconds,
      exchange: values.exchange || null,
    };
  }).filter(Boolean);
  return {
    edges: edges.sort((left, right) => left.edgeId.localeCompare(right.edgeId, "en")),
    excludedTransferCount,
  };
}

async function fetchWithRetry(url, fetchImpl) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const response = await fetchImpl(url, {
        redirect: "error",
        signal: AbortSignal.timeout(15_000),
        headers: { accept: "application/xml,text/xml" },
      });
      const retryable = response.status === 408 || response.status === 429 || response.status >= 500;
      if (!retryable || attempt === 1) return response;
      await response.body?.cancel().catch(() => {});
    } catch (error) {
      if (attempt === 1) throw new Error("Busan route topology transport failure", { cause: error });
    }
  }
  throw new Error("Busan route topology transport failure");
}

function scalar(raw, field) {
  const match = new RegExp(`<${field}\\b[^>]*>([^<]{0,512})<\\/${field}>`, "i").exec(raw);
  return match ? decodeXml(match[1].trim()) : null;
}

function stationPairs(raw) {
  const pairs = [...raw.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)].map(([, item]) => {
    const start = scalar(item, "startSc");
    const end = scalar(item, "endSc");
    const exchange = scalar(item, "exchange");
    return /^\d{2,3}$/.test(start ?? "") && /^\d{2,3}$/.test(end ?? "")
      ? `${start}:${end}:${exchange || "-"}` : "invalid";
  });
  return pairs.slice(0, 8).join(",") || "none";
}

function decodeXml(value) {
  return value.replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'").replaceAll("&amp;", "&").replace(/[\u0000-\u001f\u007f-\u009f]/g, " ");
}

function unsignedInteger(value, minimum, maximum, label) {
  if (!/^\d+$/.test(value ?? "")) throw new Error(`Busan route topology schema mismatch: ${label}`);
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < minimum || number > maximum) {
    throw new Error(`Busan route topology schema mismatch: ${label}`);
  }
  return number;
}

function requiredText(value, label) {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`Busan route topology schema mismatch: ${label}`);
  return value.trim();
}

function requiredValue(value, label) {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`${label} is required`);
  return value;
}

function lineIdForStationCode(stationCode) {
  if (!/^\d{2,3}$/.test(stationCode ?? "")) return null;
  const code = Number(stationCode);
  if (code >= 95 && code <= 134) return LINE_IDS[1];
  if (code >= 201 && code <= 243) return LINE_IDS[2];
  if (code >= 301 && code <= 317) return LINE_IDS[3];
  if (code >= 401 && code <= 414) return LINE_IDS[4];
  return null;
}

function decodedServiceKey(value) {
  if (!/%[0-9a-f]{2}/i.test(value)) return value;
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function validDate(value, label) {
  if (!(value instanceof Date) || Number.isNaN(value.getTime())) throw new Error(`${label} is invalid`);
  return value;
}

function contentHash(edges, scope) {
  return sha256(JSON.stringify({ scope, edges }));
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function safeToken(value) {
  return /^[A-Za-z0-9._/+:-]{1,64}$/.test(value) ? value : "UNKNOWN";
}

function classifyProviderFailure(message) {
  if (/(?:authorization|auth(?:entication)?|service\s*key|api\s*key|서비스\s*키|인증|권한|등록되지\s*않)/i.test(message)) {
    return "authorization";
  }
  if (/(?:parameter|param|파라미터|매개변수|요청\s*(?:값|변수).*잘못)/i.test(message)) return "invalid-parameter";
  if (/(?:no[\s_-]*data|데이터.*없|결과.*없|조회.*없)/i.test(message)) return "no-data";
  return "unknown";
}

function parseArgs(argv) {
  if (argv.length !== 4 || argv[0] !== "--output" || !path.isAbsolute(argv[1])
    || !["--scope-html", "--scode"].includes(argv[2])) {
    throw new Error("usage: collect-busan-route-topology.mjs --output <absolute.json> (--scope-html <path> | --scode <station-code>)");
  }
  return { output: argv[1], scopeHtml: argv[2] === "--scope-html" ? argv[3] : null, stationCode: argv[2] === "--scode" ? argv[3] : null };
}

async function main(argv) {
  const { output, scopeHtml, stationCode } = parseArgs(argv);
  const stationScopes = scopeHtml ? parseBusanRouteTopologyScope(await readFile(scopeHtml, "utf8")) : null;
  const snapshot = await collectBusanRouteTopology({ serviceKey: process.env.DATA_GO_KR_SERVICE_KEY, stationCode, stationScopes });
  if (stationCode) throw new Error(`diagnostic station response is not admissible: scode=${stationCode}; edges=${snapshot.edgeCount}`);
  const admission = admitBusanRouteTopology(snapshot);
  await writeFile(output, `${JSON.stringify({ ...snapshot, admission }, null, 2)}\n`, { mode: 0o600 });
  console.log(`sanitized Busan route topology ready: lines=${snapshot.lineIds.length} edges=${snapshot.edgeCount}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error instanceof Error ? error.message : "Busan route topology collection failed");
    process.exitCode = 1;
  });
}
