#!/usr/bin/env node
import { createHash } from "node:crypto";
import { lstat, readFile, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { validateBackendObservationArtifact } from "./collect-train-search-backend-observation.mjs";

const expectedWorkloads = ["repeated", "unique"];
const arguments_ = process.argv.slice(2);
if (arguments_[0] === "--preflight-output-dir") {
  if (arguments_.length !== 2) fail("expected one output directory");
  await validateOutputDirectory(arguments_[1]);
  console.log("train-search capacity output directory PASS");
  process.exit(0);
}
const { candidateGitSha, apiOrigin, evidencePaths } = parseEvidenceArguments(arguments_);
const evidenceFiles = await validatedEvidenceFiles(evidencePaths);

for (const [index, file] of evidenceFiles.slice(0, 2).entries()) {
  let summary;
  try {
    summary = JSON.parse(await readFile(file, "utf8"));
  } catch {
    fail(`${expectedWorkloads[index]} summary was unreadable`);
  }
  if (summary?.workload !== expectedWorkloads[index]
    || summary?.candidateGitSha !== candidateGitSha
    || summary?.apiOrigin !== apiOrigin
    || !validCollectedAt(summary?.collectedAt)
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
  const observation = validateBackendObservationArtifact(JSON.parse(await readFile(evidenceFiles[2], "utf8")));
  if (observation.candidateGitSha !== candidateGitSha || observation.apiOrigin !== apiOrigin) {
    fail("backend observation did not match the requested candidate and origin");
  }
} catch {
  fail("backend observation failed its evidence contract");
}

try {
  validateCandidateBindingArtifact(
    JSON.parse(await readFile(evidenceFiles[3], "utf8")),
    candidateGitSha,
    apiOrigin,
  );
} catch {
  fail("candidate deployment binding failed its evidence contract");
}

console.log("train-search capacity summaries and backend observation PASS");

function parseEvidenceArguments(values) {
  if (values.length !== 8 || values[0] !== "--candidate-sha" || values[2] !== "--api-origin") {
    fail("expected --candidate-sha, --api-origin, and four absolute evidence paths");
  }
  if (!/^[0-9a-f]{40}$/u.test(values[1])) fail("candidate SHA must be a full lowercase Git SHA");
  if (values[3] !== "https://easysubway-api.aquilaxk.site") fail("API origin must be production");
  return { candidateGitSha: values[1], apiOrigin: values[3], evidencePaths: values.slice(4) };
}

export async function validateOutputDirectory(value) {
  if (!path.isAbsolute(value ?? "")) fail("output directory must be absolute");
  const requestedTarget = path.resolve(value);
  const rootMappings = await Promise.all([process.cwd(), tmpdir(), "/tmp"].map(async (input) => ({
    input: path.resolve(input),
    real: await realpath(input),
  })));
  const mapping = rootMappings.find(({ input }) => pathInside(input, requestedTarget));
  if (!mapping) fail("output directory is outside the allowed roots");
  const root = mapping.real;
  const target = path.join(root, path.relative(mapping.input, requestedTarget));
  const relative = path.relative(root, target);
  let current = root;
  for (const segment of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);
    let metadata;
    try {
      metadata = await lstat(current);
    } catch (error) {
      if (error?.code === "ENOENT") break;
      throw error;
    }
    if (!metadata.isDirectory() || metadata.isSymbolicLink()) {
      fail("output directory path must contain only real directories");
    }
  }
  for (const name of ["repeated.json", "unique.json", "backend-observation.json", "candidate-binding.json"]) {
    try {
      const metadata = await lstat(path.join(target, name));
      if (!metadata.isFile() || metadata.isSymbolicLink()) {
        fail("existing evidence outputs must be regular files");
      }
    } catch (error) {
      if (error?.code !== "ENOENT") throw error;
    }
  }
}

async function validatedEvidenceFiles(arguments_) {
  const expectedNames = ["repeated.json", "unique.json", "backend-observation.json", "candidate-binding.json"];
  if (arguments_.length !== expectedNames.length
    || arguments_.some((value) => !path.isAbsolute(value))) {
    fail("expected four absolute evidence paths");
  }
  const directory = path.dirname(arguments_[0]);
  if (arguments_.some((value, index) => (
    path.dirname(value) !== directory || path.basename(value) !== expectedNames[index]
  ))) {
    fail("evidence paths must use the canonical names in one directory");
  }
  await validateOutputDirectory(directory);
  const allowedRoots = [await realpath(process.cwd()), await realpath(tmpdir()), await realpath("/tmp")];
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

function validateCandidateBindingArtifact(artifact, candidateGitSha, apiOrigin) {
  if (!artifact || typeof artifact !== "object") throw new Error("candidate binding was invalid");
  const { evidenceSha256, ...unsigned } = artifact;
  if (artifact.schemaVersion !== 1
    || artifact.artifactKind !== "train-search-live-smoke"
    || artifact.candidateGitSha !== candidateGitSha
    || artifact.provider !== null
    || artifact.credentialRedacted !== true
    || artifact.backend?.deployedGitSha !== candidateGitSha
    || artifact.backend?.origin !== apiOrigin
    || artifact.backend?.deployment?.deployedGitSha !== candidateGitSha
    || artifact.backend?.deployment?.conclusion !== "success"
    || artifact.backend?.currentDeployment?.sha !== candidateGitSha
    || !validUtcTimestamp(artifact.backend?.observedAt)
    || !validUtcTimestamp(artifact.backend?.currentDeployment?.succeededAt)
    || Date.parse(artifact.backend?.observedAt) < Date.parse(artifact.backend?.currentDeployment?.succeededAt)
    || !validCollectedAt(artifact.backend?.collectedAt)
    || !/^[0-9a-f]{64}$/u.test(evidenceSha256 ?? "")
    || sha256(JSON.stringify(unsigned)) !== evidenceSha256) {
    throw new Error("candidate binding failed validation");
  }
}

function validUtcTimestamp(value) {
  return typeof value === "string"
    && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/u.test(value)
    && Number.isFinite(Date.parse(value));
}

function pathInside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

function validCollectedAt(value) {
  return typeof value === "string"
    && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/u.test(value)
    && Number.isFinite(Date.parse(value));
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
