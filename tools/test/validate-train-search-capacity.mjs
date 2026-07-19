#!/usr/bin/env node
import { createHash } from "node:crypto";
import { lstat, readFile, realpath } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { validateBackendObservationArtifact } from "./collect-train-search-backend-observation.mjs";

const expectedWorkloads = ["repeated", "unique"];
const requiredCiJobs = [
  "Repository CI",
  "Android CI",
  "Release Gate Consistency",
  "Mobile App CI",
  "Backend CI",
  "Admin QA Gates",
];
const requiredDeploymentJobs = ["CD Deploy", "Post-deploy smoke", "CD Record deployment"];
const arguments_ = process.argv.slice(2);
if (arguments_[0] === "--preflight-output-dir") {
  if (arguments_.length !== 2) fail("expected one output directory");
  await validateOutputDirectory(arguments_[1]);
  console.log("train-search capacity output directory PASS");
  process.exit(0);
}
const {
  candidateGitSha,
  apiOrigin,
  departureStationId,
  arrivalStationId,
  departureDate,
  evidencePaths,
} = parseEvidenceArguments(arguments_);
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
    || summary?.departureStationId !== departureStationId
    || summary?.arrivalStationId !== arrivalStationId
    || summary?.departureDate !== departureDate
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
    departureStationId,
    arrivalStationId,
    departureDate,
  );
} catch {
  fail("candidate deployment binding failed its evidence contract");
}

console.log("train-search capacity summaries and backend observation PASS");

function parseEvidenceArguments(values) {
  if (values.length !== 14
    || values[0] !== "--candidate-sha"
    || values[2] !== "--api-origin"
    || values[4] !== "--departure-id"
    || values[6] !== "--arrival-id"
    || values[8] !== "--date") {
    fail("expected candidate, origin, OD, date, and four absolute evidence paths");
  }
  if (!/^[0-9a-f]{40}$/u.test(values[1])) fail("candidate SHA must be a full lowercase Git SHA");
  if (values[3] !== "https://easysubway-api.aquilaxk.site") fail("API origin must be production");
  if (!/^[A-Za-z0-9_-]+$/u.test(values[5]) || !/^[A-Za-z0-9_-]+$/u.test(values[7])) {
    fail("station IDs are invalid");
  }
  if (!validDate(values[9])) fail("date is invalid");
  return {
    candidateGitSha: values[1],
    apiOrigin: values[3],
    departureStationId: values[5],
    arrivalStationId: values[7],
    departureDate: values[9],
    evidencePaths: values.slice(10),
  };
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

function validateCandidateBindingArtifact(
  artifact,
  candidateGitSha,
  apiOrigin,
  departureStationId,
  arrivalStationId,
  departureDate,
) {
  if (!artifact || typeof artifact !== "object") throw new Error("candidate binding was invalid");
  const { evidenceSha256, ...unsigned } = artifact;
  if (artifact.schemaVersion !== 1
    || artifact.artifactKind !== "train-search-live-smoke"
    || artifact.candidateGitSha !== candidateGitSha
    || artifact.provider !== null
    || artifact.credentialRedacted !== true
    || artifact.backend?.deployedGitSha !== candidateGitSha
    || artifact.backend?.origin !== apiOrigin
    || artifact.backend?.departureStationId !== departureStationId
    || artifact.backend?.arrivalStationId !== arrivalStationId
    || artifact.backend?.departureDate !== departureDate
    || artifact.backend?.deployment?.deployedGitSha !== candidateGitSha
    || artifact.backend?.deployment?.workflowName !== "CD"
    || artifact.backend?.deployment?.conclusion !== "success"
    || !Number.isInteger(artifact.backend?.deployment?.runId)
    || artifact.backend.deployment.runId < 1
    || artifact.backend?.deployment?.runUrl
      !== `https://github.com/AquilaXk/easysubway/actions/runs/${artifact.backend.deployment.runId}`
    || !Array.isArray(artifact.backend?.deployment?.requiredJobs)
    || artifact.backend.deployment.requiredJobs.length !== requiredDeploymentJobs.length
    || requiredDeploymentJobs.some((job, index) => artifact.backend.deployment.requiredJobs[index] !== job)
    || artifact.backend?.requiredCi?.candidateGitSha !== candidateGitSha
    || artifact.backend?.requiredCi?.workflowName !== "CI"
    || artifact.backend?.requiredCi?.conclusion !== "success"
    || !Number.isInteger(artifact.backend?.requiredCi?.runId)
    || artifact.backend.requiredCi.runId < 1
    || artifact.backend?.requiredCi?.runUrl
      !== `https://github.com/AquilaXk/easysubway/actions/runs/${artifact.backend.requiredCi.runId}`
    || !Array.isArray(artifact.backend?.requiredCi?.requiredJobs)
    || artifact.backend.requiredCi.requiredJobs.length !== requiredCiJobs.length
    || requiredCiJobs.some((job, index) => artifact.backend.requiredCi.requiredJobs[index] !== job)
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

function validDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/u.test(value ?? "")) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
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
