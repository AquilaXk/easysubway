#!/usr/bin/env node

import { readFile } from "node:fs/promises";

const [
  responsePath,
  expectedSha,
  expectedName,
  expectedEventsInput,
  expectedBranch,
  maxAgeSecondsInput,
] = process.argv.slice(2);
const maxAgeSeconds = Number(maxAgeSecondsInput);
const expectedEvents = expectedEventsInput?.split(",") ?? [];

if (
  !responsePath ||
  !/^[0-9a-f]{40}$/.test(expectedSha ?? "") ||
  !expectedName ||
  expectedEvents.length === 0 ||
  expectedEvents.some((event) => !/^[a-z_]+$/.test(event)) ||
  !expectedBranch ||
  !Number.isSafeInteger(maxAgeSeconds) ||
  maxAgeSeconds <= 0
) {
  console.error(
    "usage: require-successful-workflow-run.mjs <response.json> <sha> <name> <events> <branch> <max-age-seconds>",
  );
  process.exit(2);
}

let payload;
try {
  payload = JSON.parse(await readFile(responsePath, "utf8"));
} catch {
  console.error("workflow runs response is not valid JSON");
  process.exit(1);
}

if (
  !Number.isSafeInteger(payload?.total_count) ||
  payload.total_count < 0 ||
  !Array.isArray(payload?.workflow_runs) ||
  payload.total_count !== payload.workflow_runs.length
) {
  console.error("workflow runs response is inconsistent");
  process.exit(1);
}

const now = Date.now();
const maxFutureSkewMs = 5 * 60 * 1000;
const runs = payload.workflow_runs.map((run) => {
  const updatedAt = Date.parse(run?.updated_at ?? "");
  const ageMs = now - updatedAt;
  if (
    run?.name !== expectedName ||
    run?.head_sha !== expectedSha ||
    run?.head_branch !== expectedBranch ||
    !expectedEvents.includes(run?.event) ||
    run?.status !== "completed" ||
    run?.conclusion !== "success" ||
    !Number.isSafeInteger(run?.id) ||
    run.id <= 0 ||
    !Number.isFinite(updatedAt) ||
    ageMs < -maxFutureSkewMs
  ) {
    console.error("workflow runs response is inconsistent");
    process.exit(1);
  }
  return { run, ageMs };
});

const matchingRun = runs.find(({ ageMs }) => ageMs <= maxAgeSeconds * 1000)?.run;
if (!matchingRun) {
  console.error("required successful workflow run is unavailable");
  process.exit(3);
}

console.log(`validated_workflow_run_id=${matchingRun.id}`);
