#!/usr/bin/env node
import { lstat, readFile, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { validateBackendObservationArtifact } from "./collect-train-search-backend-observation.mjs";

const expectedWorkloads = ["repeated", "unique"];
const evidenceFiles = await validatedEvidenceFiles(process.argv.slice(2));

for (const [index, file] of evidenceFiles.slice(0, 2).entries()) {
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
    || !Number.isInteger(summary?.expectedRequestCount)
    || summary.expectedRequestCount < 1
    || summary.requestCount < summary.expectedRequestCount
    || typeof summary?.p95Ms !== "number"
    || summary.p95Ms < 0
    || summary.p95Ms >= 8_000
    || summary?.failureRate !== 0
    || summary?.fiveXxCount !== 0
    || summary?.fourXxCount !== 0
    || summary?.rateLimitedCount !== 0
    || summary?.droppedIterationCount !== 0
    || "providerCallCount" in summary
    || "quotaVerdict" in summary) {
    fail(`${expectedWorkloads[index]} summary failed its evidence contract`);
  }
}

try {
  validateBackendObservationArtifact(JSON.parse(await readFile(evidenceFiles[2], "utf8")));
} catch {
  fail("backend observation failed its evidence contract");
}

console.log("train-search capacity summaries and backend observation PASS");

async function validatedEvidenceFiles(arguments_) {
  const expectedNames = ["repeated.json", "unique.json", "backend-observation.json"];
  if (arguments_.length !== expectedNames.length
    || arguments_.some((value) => !path.isAbsolute(value))) {
    fail("expected three absolute evidence paths");
  }
  const directory = path.dirname(arguments_[0]);
  if (arguments_.some((value, index) => (
    path.dirname(value) !== directory || path.basename(value) !== expectedNames[index]
  ))) {
    fail("evidence paths must use the canonical names in one directory");
  }
  const allowedRoots = [await realpath(process.cwd()), await realpath(tmpdir())];
  if (!allowedRoots.some((root) => pathInside(root, directory))) {
    fail("evidence directory is outside the allowed roots");
  }
  const realDirectory = await realpath(directory);
  if (!allowedRoots.some((root) => pathInside(root, realDirectory))) {
    fail("evidence directory resolves outside the allowed roots");
  }
  const files = expectedNames.map((name) => path.join(realDirectory, name));
  const metadata = await Promise.all(files.map((file) => lstat(file)));
  if (metadata.some((value) => !value.isFile() || value.isSymbolicLink())) {
    fail("evidence inputs must be regular files");
  }
  return files;
}

function pathInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
