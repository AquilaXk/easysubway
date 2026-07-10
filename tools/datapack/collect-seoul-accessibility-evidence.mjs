#!/usr/bin/env node
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const PILOT_STATIONS = ["상록수", "사당"];
const DEFAULT_ENDPOINT = "https://apis.data.go.kr/B553766/wksn/getWksnElvtr";
const INVALID_RESPONSE = "Seoul accessibility API response invalid";

export function normalizeAccessibilityRows(rows) {
  if (!Array.isArray(rows)) {
    throw new Error(INVALID_RESPONSE);
  }
  return rows.map((row) => {
    if (!row || typeof row !== "object" || Array.isArray(row)) {
      throw new Error(INVALID_RESPONSE);
    }
    const { stnNm, oprYn, instlPstn, oprtngSitu, dtlPstn } = row;
    const status = oprYn ?? oprtngSitu;
    const pathDescription = instlPstn ?? dtlPstn;
    if (
      typeof stnNm !== "string" ||
      stnNm.trim() === "" ||
      typeof pathDescription !== "string" ||
      pathDescription.trim() === "" ||
      status !== "Y"
    ) {
      throw new Error(INVALID_RESPONSE);
    }
    return { stationName: stnNm, operational: true, pathDescription };
  });
}

export function buildAccessibilitySnapshot(rows, retrievedAt) {
  if (
    !Array.isArray(rows) ||
    rows.some(
      (row) =>
        !row ||
        typeof row.stationName !== "string" ||
        row.stationName.trim() === "" ||
        typeof row.operational !== "boolean" ||
        typeof row.pathDescription !== "string" ||
        row.pathDescription.trim() === "",
    )
  ) {
    throw new Error(INVALID_RESPONSE);
  }
  const stations = PILOT_STATIONS.map((stationName) => ({
    stationName,
    facilities: rows
      .filter((row) => row.stationName === stationName)
      .map(({ operational, pathDescription }) => ({ operational, pathDescription })),
  }));
  const missing = stations.find(({ facilities }) => facilities.length === 0);
  if (missing) {
    throw new Error(`accessibility evidence missing for ${missing.stationName}`);
  }
  return { sourceId: "seoul-metro-accessibility", retrievedAt, stations };
}

export async function collectSeoulAccessibility({ endpoint, serviceKey, fetchImpl = fetch }) {
  const url = new URL(endpoint);
  if (url.protocol !== "https:") {
    throw new Error("HTTPS endpoint is required");
  }
  url.searchParams.set("serviceKey", serviceKey);
  url.searchParams.set("pageNo", "1");
  url.searchParams.set("numOfRows", "1000");
  url.searchParams.set("dataType", "JSON");
  let response;
  try {
    response = await fetchImpl(url);
  } catch {
    throw new Error("Seoul accessibility API request failed");
  }
  if (!response.ok) {
    throw new Error(`Seoul accessibility API HTTP ${response.status}`);
  }
  let payload;
  try {
    payload = await response.json();
  } catch {
    throw new Error(INVALID_RESPONSE);
  }
  if (payload?.response?.header?.resultCode !== "00") {
    throw new Error(INVALID_RESPONSE);
  }
  const rows = payload.response?.body?.items?.item;
  if (!Array.isArray(rows)) {
    throw new Error(INVALID_RESPONSE);
  }
  return normalizeAccessibilityRows(rows);
}

export async function writeSeoulAccessibilityEvidence({
  endpoint,
  serviceKey,
  output,
  fetchImpl = fetch,
  retrievedAt = new Date().toISOString(),
}) {
  const rows = await collectSeoulAccessibility({ endpoint, serviceKey, fetchImpl });
  const snapshot = buildAccessibilitySnapshot(rows, retrievedAt);
  const outputPath = resolve(output);
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(snapshot, null, 2)}\n`);
  return snapshot;
}

async function main() {
  if (process.argv.length !== 4 || process.argv[2] !== "--output") {
    throw new Error("usage: collect-seoul-accessibility-evidence.mjs --output <path>");
  }
  const serviceKey = process.env.DATA_GO_KR_SERVICE_KEY;
  if (!serviceKey) {
    throw new Error("DATA_GO_KR_SERVICE_KEY env is required");
  }
  await writeSeoulAccessibilityEvidence({ endpoint: DEFAULT_ENDPOINT, serviceKey, output: process.argv[3] });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : "accessibility collection failed"}\n`);
    process.exitCode = 1;
  });
}
