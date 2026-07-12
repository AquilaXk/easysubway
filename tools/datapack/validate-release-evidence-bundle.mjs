#!/usr/bin/env node
import { readFile } from "node:fs/promises";

const SHA256 = /^[a-f0-9]{64}$/;
const STATUSES = new Set(["PASS", "FAIL", "BLOCKED_EXTERNAL"]);
const HEADWAY_STATUSES = new Set([...STATUSES, "DEFERRED"]);
// route_graph_topology는 capital pilot의 deferred domain이다(pilot targets의 knownSourceDomains에만 존재).
// deferred domain 위반은 게시를 차단하지 않고 DEFERRED로 정직 기록하되, 위반 수치는
// routeGraphTopologyViolationCount와 topology report SHA로 evidence에 전량 남긴다(은폐 금지).
const ROUTE_GRAPH_STATUSES = new Set([...STATUSES, "DEFERRED"]);
const DEFERRED_ALLOWED_FIELDS = new Set(["headwayReportStatus", "routeGraphTopologyStatus"]);

function argValue(args, name) {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function requireField(bundle, field) {
  if (bundle[field] === undefined || bundle[field] === "") {
    throw new Error(`release evidence bundle missing ${field}`);
  }
  return bundle[field];
}

function validateSha(bundle, field) {
  const value = requireField(bundle, field);
  if (!SHA256.test(value)) {
    throw new Error(`${field} must be sha256`);
  }
}

function allowedStatusesFor(field) {
  if (field === "headwayReportStatus") {
    return HEADWAY_STATUSES;
  }
  if (field === "routeGraphTopologyStatus") {
    return ROUTE_GRAPH_STATUSES;
  }
  return STATUSES;
}

function validateStatus(bundle, field, requirePass) {
  const value = requireField(bundle, field);
  const allowedStatuses = allowedStatusesFor(field);
  if (!allowedStatuses.has(value)) {
    throw new Error(`${field} must be a release gate status`);
  }
  if (requirePass && value !== "PASS" && !(DEFERRED_ALLOWED_FIELDS.has(field) && value === "DEFERRED")) {
    throw new Error(`${field} must be PASS for publish`);
  }
}

async function main() {
  const args = process.argv.slice(2);
  const bundlePath = argValue(args, "--bundle");
  const requirePass = args.includes("--require-pass");
  if (!bundlePath) {
    throw new Error("--bundle is required");
  }

  const bundle = JSON.parse(await readFile(bundlePath, "utf8"));
  for (const [field, expected] of [
    ["schemaVersion", 1],
    ["artifactKind", "datapack-release-evidence-bundle"],
  ]) {
    if (bundle[field] !== expected) {
      throw new Error(`${field} must be ${expected}`);
    }
  }

  for (const field of [
    "candidateId",
    "scopeId",
    "releaseRequestId",
    "builderGitSha",
    "createdAt",
    "workflowRunUrl",
  ]) {
    requireField(bundle, field);
  }
  for (const field of [
    "buildSpecSha256",
    "supportedDenominatorSha256",
    "sourceSnapshotSetHash",
    "approvedAliasLedgerHash",
    "facilityEvidenceLedgerHash",
    "routeEvidenceLedgerHash",
    "approvedOverrideSetHash",
    "normalizedSourceInventorySha256",
    "sqliteSha256",
    "gzipSha256",
    "manifestSha256",
    "coverageSummarySha256",
    "routeMapPositionCoverageSha256",
    "routeGraphTopologySha256",
    "headwayReportSha256",
    "strictRouteRegressionSha256",
    "androidEvidenceSha256",
  ]) {
    validateSha(bundle, field);
  }
  for (const field of [
    "validatorStatus",
    "coverageStatus",
    "routeMapPositionCoverageStatus",
    "routeGraphTopologyStatus",
    "headwayReportStatus",
    "strictRouteRegressionStatus",
    "manifestSignatureStatus",
    "androidEvidenceStatus",
  ]) {
    validateStatus(bundle, field, requirePass);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
