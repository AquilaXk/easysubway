#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { isDeepStrictEqual } from "node:util";
import {
  buildLaunchDenominatorReport,
  canonicalScopeHash,
} from "./build-launch-denominator-report.mjs";

const SHA256 = /^[a-f0-9]{64}$/;
const STATUSES = new Set(["PASS", "FAIL", "BLOCKED_EXTERNAL"]);
// 필드별 허용 status set의 단일 소스. DEFERRED가 포함된 필드는 곧 deferred 허용 필드다
// (headway는 evidence 미도래, route_graph_topology는 capital pilot의 deferred domain — pilot targets의
// knownSourceDomains에만 존재). deferred domain 위반은 게시를 차단하지 않고 DEFERRED로 정직 기록하되,
// 위반 수치는 routeGraphTopologyViolationCount와 topology report SHA로 evidence에 전량 남긴다(은폐 금지).
// 이 맵 하나에서 allowedStatusesFor와 DEFERRED 허용 여부를 함께 파생한다(중복 상수 제거).
const DEFERRABLE_STATUSES = new Set([...STATUSES, "DEFERRED"]);
const FIELD_STATUS_SETS = new Map([
  ["headwayReportStatus", DEFERRABLE_STATUSES],
  ["routeGraphTopologyStatus", DEFERRABLE_STATUSES],
]);

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
  return FIELD_STATUS_SETS.get(field) ?? STATUSES;
}

function validateStatus(bundle, field, requirePass) {
  const value = requireField(bundle, field);
  const allowedStatuses = allowedStatusesFor(field);
  if (!allowedStatuses.has(value)) {
    throw new Error(`${field} must be a release gate status`);
  }
  if (requirePass && value !== "PASS" && !(allowedStatuses.has("DEFERRED") && value === "DEFERRED")) {
    throw new Error(`${field} must be PASS for publish`);
  }
}

function validateNonNegativeInteger(bundle, field) {
  const value = requireField(bundle, field);
  if (!Number.isInteger(value) || value < 0) {
    throw new Error(`${field} must be a non-negative integer`);
  }
  return value;
}

// route_graph_topology의 status와 위반 수치는 워크플로에서 함께 파생된다:
// violationCount === 0 이면 PASS, 위반이 있으면 deferred scope에서 DEFERRED(그 외 FAIL/BLOCKED_EXTERNAL).
// 손 조립 bundle에서 이 정합이 깨진 조합(예: DEFERRED + violationCount 0 → 위반 은폐)을 런타임에서 차단한다.
function validateRouteGraphTopologyIntegrity(bundle) {
  const violationCount = validateNonNegativeInteger(bundle, "routeGraphTopologyViolationCount");
  const status = bundle.routeGraphTopologyStatus;
  if (status === "DEFERRED" && violationCount === 0) {
    throw new Error(
      "routeGraphTopologyStatus DEFERRED requires routeGraphTopologyViolationCount > 0 (위반 은폐 차단)",
    );
  }
  if (status === "PASS" && violationCount !== 0) {
    throw new Error("routeGraphTopologyStatus PASS requires routeGraphTopologyViolationCount 0");
  }
}

function validateLaunchDenominatorReport(bundle, report, reportRaw, scope, requirePass) {
  const scopeBindings = [
    [
      "verified accessibility",
      report.scopes?.verifiedAccessibilityScope,
      scope.verifiedAccessibilityScope,
      "verifiedAccessibilityScopeId",
      "verifiedAccessibilityScopeSha256",
    ],
    [
      "routing",
      report.scopes?.routingLaunchScope,
      scope.routingLaunchScope,
      "launchScopeId",
      "launchScopeSha256",
    ],
    [
      "nationwide roadmap",
      report.scopes?.nationwideRoadmapScope,
      scope.nationwideRoadmapScope,
      "nationwideRoadmapScopeId",
      "nationwideRoadmapScopeSha256",
    ],
  ];
  for (const [label, reportScope, canonicalScope, idField, hashField] of scopeBindings) {
    if (
      reportScope?.id !== canonicalScope?.id
      || reportScope?.sha256 !== canonicalScopeHash(canonicalScope)
    ) {
      throw new Error(`launch denominator report ${label} scope identity mismatch`);
    }
    if (bundle[idField] !== reportScope.id || bundle[hashField] !== reportScope.sha256) {
      throw new Error(`launch denominator report ${label} scope binding mismatch`);
    }
  }
  if (bundle.scopeId !== report.scopes.verifiedAccessibilityScope.id) {
    throw new Error("scopeId must match launch denominator verified accessibility scope");
  }
  const matrixSha256 = canonicalScopeHash(scope.identityMatrix);
  if (
    report.identityLinkage?.matrixSha256 !== matrixSha256
    || bundle.identityLinkageMatrixSha256 !== report.identityLinkage.matrixSha256
  ) {
    throw new Error("launch denominator report identity linkage matrix mismatch");
  }
  if (
    report.nationwideBlocksV1 !== false
    || report.coverage?.nationwide?.blocksV1 !== false
    || scope.nationwideRoadmapScope?.blocksRoutingLaunch !== false
  ) {
    throw new Error("nationwide roadmap must remain nonblocking for v1 launch");
  }
  const canonicalReport = buildLaunchDenominatorReport(scope, report.evaluatorInput);
  if (!isDeepStrictEqual(report, canonicalReport)) {
    throw new Error("launch denominator report must match canonical evaluator output");
  }
  if (bundle.launchDenominatorDecision !== report.decision) {
    throw new Error("launch denominator report decision must match bundle");
  }
  const reportSha256 = createHash("sha256").update(reportRaw).digest("hex");
  if (bundle.launchDenominatorReportSha256 !== reportSha256) {
    throw new Error("launch denominator report sha256 mismatch");
  }
  if (requirePass && report.decision !== "GO") {
    throw new Error("launch denominator decision must be GO for publish");
  }
}

async function main() {
  const args = process.argv.slice(2);
  const bundlePath = argValue(args, "--bundle");
  const scopePath = argValue(args, "--scope") ?? "apps/mobile/release/production-datapack-scope.json";
  const launchReportPath = argValue(args, "--launch-report")
    ?? "tools/datapack/reports/android-v1-launch-denominator-20260715.json";
  const requirePass = args.includes("--require-pass");
  if (!bundlePath) {
    throw new Error("--bundle is required");
  }

  const bundle = JSON.parse(await readFile(bundlePath, "utf8"));
  const scope = JSON.parse(await readFile(scopePath, "utf8"));
  const launchReportRaw = await readFile(launchReportPath, "utf8");
  const launchReport = JSON.parse(launchReportRaw);
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
    "verifiedAccessibilityScopeId",
    "launchScopeId",
    "nationwideRoadmapScopeId",
    "launchDenominatorDecision",
    "releaseRequestId",
    "builderGitSha",
    "createdAt",
    "workflowRunUrl",
  ]) {
    requireField(bundle, field);
  }
  validateLaunchDenominatorReport(bundle, launchReport, launchReportRaw, scope, requirePass);
  for (const field of [
    "verifiedAccessibilityScopeSha256",
    "launchScopeSha256",
    "nationwideRoadmapScopeSha256",
    "identityLinkageMatrixSha256",
    "launchDenominatorReportSha256",
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
    "itxCheongchunCoverageSha256",
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

  validateRouteGraphTopologyIntegrity(bundle);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
