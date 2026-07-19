#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import { validateBackendObservationArtifact } from "./collect-train-search-backend-observation.mjs";

const expectedWorkloads = ["repeated", "unique"];
if (process.argv.length !== 5) fail("expected repeated, unique, and backend observation paths");

for (const [index, file] of process.argv.slice(2, 4).entries()) {
  let summary;
  try {
    summary = JSON.parse(await readFile(file, "utf8"));
  } catch {
    fail(`${expectedWorkloads[index]} summary was unreadable`);
  }
  if (summary?.workload !== expectedWorkloads[index]
    || summary?.status !== "PASS"
    || !Number.isInteger(summary?.requestCount)
    || summary.requestCount < 1
    || typeof summary?.p95Ms !== "number"
    || summary.p95Ms < 0
    || summary.p95Ms >= 8_000
    || summary?.failureRate !== 0
    || summary?.fiveXxCount !== 0
    || summary?.fourXxCount !== 0
    || summary?.rateLimitedCount !== 0
    || "providerCallCount" in summary
    || "quotaVerdict" in summary) {
    fail(`${expectedWorkloads[index]} summary failed its evidence contract`);
  }
}

try {
  validateBackendObservationArtifact(JSON.parse(await readFile(process.argv[4], "utf8")));
} catch {
  fail("backend observation failed its evidence contract");
}

console.log("train-search capacity summaries and backend observation PASS");

function fail(message) {
  console.error(message);
  process.exit(1);
}
