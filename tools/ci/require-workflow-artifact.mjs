#!/usr/bin/env node

import { readFile } from "node:fs/promises";

const [responsePath, expectedName, expectedRunIdInput, expectedSha] = process.argv.slice(2);
const expectedRunId = Number(expectedRunIdInput);

if (
  !responsePath ||
  !/^[A-Za-z0-9_.-]+$/.test(expectedName ?? "") ||
  !Number.isSafeInteger(expectedRunId) ||
  expectedRunId <= 0 ||
  !/^[a-f0-9]{40}$/.test(expectedSha ?? "")
) {
  console.error(
    "usage: require-workflow-artifact.mjs <response.json> <artifact-name> <run-id> <sha>",
  );
  process.exit(2);
}

let payload;
try {
  payload = JSON.parse(await readFile(responsePath, "utf8"));
} catch {
  console.error("workflow artifacts response is not valid JSON");
  process.exit(1);
}

const matches = Array.isArray(payload?.artifacts)
  ? payload.artifacts.filter((artifact) =>
      artifact?.name === expectedName &&
      artifact?.expired === false &&
      Number.isSafeInteger(artifact?.id) &&
      artifact?.workflow_run?.id === expectedRunId &&
      artifact?.workflow_run?.head_sha === expectedSha)
  : [];

if (matches.length !== 1) {
  console.error("required workflow artifact was not found");
  process.exit(1);
}

console.log(`validated_artifact_id=${matches[0].id}`);
