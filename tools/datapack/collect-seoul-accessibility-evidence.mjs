#!/usr/bin/env node
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const PILOT_STATIONS = ["상록수", "사당"];
const DEFAULT_ENDPOINT = "https://apis.data.go.kr/B553766/wksn/getWksnElvtr";

export function normalizeAccessibilityRows(rows) {
  return rows.map(({ stnNm, oprYn, instlPstn, oprtngSitu, dtlPstn }) => ({
    stationName: stnNm,
    operational: ["Y", "M"].includes(oprYn ?? oprtngSitu),
    pathDescription: instlPstn ?? dtlPstn,
  }));
}

export function buildAccessibilitySnapshot(rows, retrievedAt) {
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
  return normalizeAccessibilityRows((await response.json()).response.body.items.item);
}

async function main() {
  if (process.argv.length !== 4 || process.argv[2] !== "--output") {
    throw new Error("usage: collect-seoul-accessibility-evidence.mjs --output <path>");
  }
  const serviceKey = process.env.DATA_GO_KR_SERVICE_KEY;
  if (!serviceKey) {
    throw new Error("DATA_GO_KR_SERVICE_KEY env is required");
  }
  const rows = await collectSeoulAccessibility({ endpoint: DEFAULT_ENDPOINT, serviceKey });
  const snapshot = buildAccessibilitySnapshot(rows, new Date().toISOString());
  const output = resolve(process.argv[3]);
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify(snapshot, null, 2)}\n`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : "accessibility collection failed"}\n`);
    process.exitCode = 1;
  });
}
