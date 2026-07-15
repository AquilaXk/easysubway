#!/usr/bin/env node

import { readFile } from "node:fs/promises";

const [responsePath, expectedSha, expectedName, expectedEvent, expectedBranch] =
  process.argv.slice(2);

if (
  !responsePath ||
  !/^[0-9a-f]{40}$/.test(expectedSha ?? "") ||
  !expectedName ||
  !expectedEvent ||
  !expectedBranch
) {
  console.error(
    "usage: require-successful-workflow-run.mjs <response.json> <sha> <name> <event> <branch>",
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

const matchingRun = payload.workflow_runs.find(
  (run) =>
    run?.name === expectedName &&
    run?.head_sha === expectedSha &&
    run?.head_branch === expectedBranch &&
    run?.event === expectedEvent &&
    run?.status === "completed" &&
    run?.conclusion === "success" &&
    Number.isSafeInteger(run?.id),
);

if (!matchingRun) {
  console.error("required successful workflow run was not found");
  process.exit(1);
}

console.log(`validated_workflow_run_id=${matchingRun.id}`);
