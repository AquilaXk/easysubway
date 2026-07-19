#!/usr/bin/env node
import { pathToFileURL } from "node:url";

const DEFAULT_BASE_URL = "https://apis.data.go.kr/1613000/TrainInfo/";

function requiredServiceKey(value) {
  const trimmed = String(value ?? "").trim();
  if (!trimmed) throw new Error("EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY env is required");
  if (!/%[0-9a-f]{2}/i.test(trimmed)) return trimmed;
  try {
    return decodeURIComponent(trimmed);
  } catch {
    throw new Error("EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY encoding is invalid");
  }
}

function rows(payload) {
  const item = payload?.response?.body?.items?.item;
  const values = Array.isArray(item) ? item : item && typeof item === "object" ? [item] : [];
  if (values.length === 0 || values.some((row) => (
    typeof row.citycode !== "string" || row.citycode.trim() === ""
      || typeof row.cityname !== "string" || row.cityname.trim() === ""
  ))) {
    throw new Error("provider city catalog schema was invalid");
  }
  return values;
}

export async function probeTagoTrainProvider({
  serviceKey,
  baseUrl = DEFAULT_BASE_URL,
  timeoutMs = 10_000,
} = {}) {
  const key = requiredServiceKey(serviceKey);
  const url = new URL("GetCtyCodeList", baseUrl);
  url.searchParams.set("serviceKey", key);
  url.searchParams.set("_type", "json");
  url.searchParams.set("numOfRows", "100");
  url.searchParams.set("pageNo", "1");

  const deadline = Date.now() + timeoutMs;
  for (let attempt = 0; attempt < 2; attempt += 1) {
    const controller = new AbortController();
    const remaining = deadline - Date.now();
    if (remaining <= 0) throw new Error("provider credential probe timed out");
    const timer = setTimeout(() => controller.abort(), remaining);
    try {
      const response = await fetch(url, { signal: controller.signal });
      if (!response.ok) {
        if (attempt === 0 && [408, 429, 500, 502, 503, 504].includes(response.status)) continue;
        throw new Error(`provider HTTP status was ${response.status}`);
      }
      let payload;
      try {
        payload = await response.json();
      } catch {
        throw new Error("provider response was not valid JSON");
      }
      if (payload?.response?.header?.resultCode !== "00") {
        throw new Error("provider resultCode was not 00");
      }
      const validRows = rows(payload).length;
      return { result: "PASS", operation: "GetCtyCodeList", validRows };
    } catch (error) {
      if (error?.name === "AbortError") throw new Error("provider credential probe timed out");
      if (attempt === 0 && error instanceof TypeError) continue;
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }
  throw new Error("provider credential probe failed");
}

async function main() {
  const result = await probeTagoTrainProvider({
    serviceKey: process.env.EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY,
  });
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
