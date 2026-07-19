#!/usr/bin/env node
import { readFile } from "node:fs/promises";

const expectedWorkloads = ["repeated", "unique"];
if (process.argv.length !== 4) fail("expected repeated and unique summary paths");

for (const [index, file] of process.argv.slice(2).entries()) {
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
    || summary?.providerCallCount !== 1
    || summary?.quotaVerdict !== "PASS") {
    fail(`${expectedWorkloads[index]} summary failed its evidence contract`);
  }
}

console.log("train-search capacity summaries PASS");

function fail(message) {
  console.error(message);
  process.exit(1);
}
