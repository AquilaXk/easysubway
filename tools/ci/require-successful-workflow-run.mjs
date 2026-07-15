#!/usr/bin/env node

import { readFile } from "node:fs/promises";

const [
  responsePath,
  expectedSha,
  expectedName,
  expectedEvent,
  expectedBranch,
  maxAgeSecondsInput,
] = process.argv.slice(2);
const maxAgeSeconds = Number(maxAgeSecondsInput);

if (
  !responsePath ||
  !/^[0-9a-f]{40}$/.test(expectedSha ?? "") ||
  !expectedName ||
  !expectedEvent ||
  !expectedBranch ||
  !Number.isSafeInteger(maxAgeSeconds) ||
  maxAgeSeconds <= 0
) {
  console.error(
    "usage: require-successful-workflow-run.mjs <response.json> <sha> <name> <event> <branch> <max-age-seconds>",
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

if (!Array.isArray(payload?.workflow_runs)) {
  console.error("workflow runs response is missing workflow_runs");
  process.exit(1);
}

const now = Date.now();
const maxFutureSkewMs = 5 * 60 * 1000;
const matchingRun = payload.workflow_runs.find((run) => {
  const updatedAt = Date.parse(run?.updated_at ?? "");
  const ageMs = now - updatedAt;
  return (
    run?.name === expectedName &&
    run?.head_sha === expectedSha &&
    run?.head_branch === expectedBranch &&
    run?.event === expectedEvent &&
    run?.status === "completed" &&
    run?.conclusion === "success" &&
    Number.isSafeInteger(run?.id) &&
    Number.isFinite(updatedAt) &&
    ageMs >= -maxFutureSkewMs &&
    ageMs <= maxAgeSeconds * 1000
  );
});

if (!matchingRun) {
  console.error("required successful workflow run was not found");
  process.exit(1);
}

console.log(`validated_workflow_run_id=${matchingRun.id}`);
