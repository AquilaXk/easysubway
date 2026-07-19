import http from "k6/http";
import { check } from "k6";
import exec from "k6/execution";
import { Counter, Rate } from "k6/metrics";

const fiveXx = new Counter("train_search_5xx");
const fourXx = new Counter("train_search_4xx");
const rateLimited = new Counter("train_search_429");
const success = new Rate("train_search_success");

const workload = __ENV.TRAIN_SEARCH_WORKLOAD;
if (!new Set(["repeated", "unique"]).has(workload)) {
  throw new Error("TRAIN_SEARCH_WORKLOAD must be repeated or unique");
}

const rate = Number(__ENV.TRAIN_SEARCH_RATE || 1);
const duration = __ENV.TRAIN_SEARCH_DURATION || "12s";
if (!Number.isInteger(rate) || rate < 1 || rate > 4) throw new Error("TRAIN_SEARCH_RATE must be 1 through 4");
const durationMatch = /^([1-9][0-9]*)s$/.exec(duration);
if (!durationMatch) throw new Error("TRAIN_SEARCH_DURATION must be whole seconds");
const durationSeconds = Number(durationMatch[1]);
const expectedRequestCount = Math.floor((rate * durationSeconds) / 2);
if (expectedRequestCount < 1) throw new Error("TRAIN_SEARCH_DURATION scheduled no requests");

export const options = {
  scenarios: {
    train_search: {
      executor: "constant-arrival-rate",
      rate,
      timeUnit: "2s",
      duration,
      preAllocatedVUs: rate * 2,
      maxVUs: rate * 4,
    },
  },
  thresholds: {
    http_req_duration: ["p(95)<8000"],
    http_req_failed: ["rate<0.01"],
    checks: ["rate>0.99"],
    train_search_5xx: ["count==0"],
    train_search_4xx: ["count==0"],
    train_search_429: ["count==0"],
    train_search_success: ["rate>0.99"],
    dropped_iterations: ["count==0"],
  },
};

const trainTypes = ["KTX", "KTX_SANCHEON", "SRT", "ITX_MAUM"];

function shiftedDate(value, days) {
  const date = new Date(`${value}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

export default function () {
  const parameters = {
    departureStationId: __ENV.TRAIN_SEARCH_DEPARTURE_ID,
    arrivalStationId: __ENV.TRAIN_SEARCH_ARRIVAL_ID,
  };
  if (workload === "unique") {
    const iteration = exec.scenario.iterationInTest;
    parameters.departureDate = shiftedDate(
      __ENV.TRAIN_SEARCH_DATE,
      Math.floor(iteration / trainTypes.length),
    );
    parameters.trainType = trainTypes[iteration % trainTypes.length];
  } else {
    parameters.departureDate = __ENV.TRAIN_SEARCH_DATE;
    parameters.trainType = "KTX";
  }
  const query = Object.entries(parameters)
    .map(([name, value]) => `${encodeURIComponent(name)}=${encodeURIComponent(value)}`)
    .join("&");
  const origin = __ENV.TRAIN_SEARCH_BASE_URL.replace(/\/$/, "");
  const response = http.get(`${origin}/api/v1/trains/search?${query}`, { tags: { workload } });
  fiveXx.add(response.status >= 500 && response.status <= 599);
  fourXx.add(response.status >= 400 && response.status <= 499);
  rateLimited.add(response.status === 429);
  const passed = check(response, {
    "HTTP 200": (value) => value.status === 200,
    "success envelope": (value) => {
      try {
        const payload = value.json();
        return payload?.success === true
          && Array.isArray(payload?.data?.outbound)
          && payload.data.outbound.every((row) => row.trainType !== "ITX_CHEONGCHUN");
      } catch {
        return false;
      }
    },
  });
  success.add(passed);
}

export function handleSummary(data) {
  const failedChecks = data.metrics.checks?.values?.fails ?? 0;
  const fiveXxCount = data.metrics.train_search_5xx?.values?.count ?? 0;
  const fourXxCount = data.metrics.train_search_4xx?.values?.count ?? 0;
  const rateLimitedCount = data.metrics.train_search_429?.values?.count ?? 0;
  const droppedIterationCount = data.metrics.dropped_iterations?.values?.count ?? 0;
  const requestCount = data.metrics.http_reqs?.values?.count ?? 0;
  const p95Ms = data.metrics.http_req_duration?.values?.["p(95)"] ?? null;
  const failureRate = data.metrics.http_req_failed?.values?.rate ?? null;
  const summary = {
    schemaVersion: 1,
    workload,
    status: requestCount >= expectedRequestCount && p95Ms !== null && failureRate === 0
      && failedChecks === 0 && fiveXxCount === 0 && fourXxCount === 0 && rateLimitedCount === 0
      && droppedIterationCount === 0
      ? "PASS"
      : "FAIL",
    requestCount,
    expectedRequestCount,
    p95Ms,
    failureRate,
    fiveXxCount,
    fourXxCount,
    rateLimitedCount,
    droppedIterationCount,
  };
  return {
    stdout: `train-search ${workload}: ${summary.status} requests=${summary.requestCount} p95Ms=${summary.p95Ms}\n`,
    [__ENV.TRAIN_SEARCH_SUMMARY_PATH]: `${JSON.stringify(summary, null, 2)}\n`,
  };
}
