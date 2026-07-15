import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";
import {
  buildLaunchDenominatorReport,
  canonicalScopeHash,
} from "./build-launch-denominator-report.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");

test("release evidence bundle validator는 publish gate status와 deferred headway 예외를 검증한다", async () => {
  const outputDir = path.join(tmpdir(), `easysubway-release-evidence-${Date.now()}`);
  await rm(outputDir, { recursive: true, force: true });
  await mkdir(outputDir, { recursive: true });
  const bundlePath = path.join(outputDir, "release-evidence-bundle.json");
  const hash = "a".repeat(64);
  const scope = JSON.parse(await readFile(
    path.join(root, "apps/mobile/release/production-datapack-scope.json"),
    "utf8",
  ));
  const scopeArgs = ["--scope", "apps/mobile/release/production-datapack-scope.json"];
  const launchReportPath = path.join(outputDir, "launch-denominator-go.json");
  const currentLaunchReportPath = "tools/datapack/reports/android-v1-launch-denominator-20260715.json";
  const identity = {
    canonicalStationVersion: "station-catalog-v18",
    corridorId: "capital-gyeongchun-v1",
    serviceId: "ITX_CHEONGCHUN",
    lineageId: "launch-lineage-v1",
    schemaVersion: 1,
  };
  const admittedStationIds = [
    ...scope.routingLaunchScope.baseRoutingStationIds,
    ...scope.routingLaunchScope.requiredTransferStationIds,
  ];
  const sourceDerivedConnectionEdgeIds = ["source-edge-a"];
  const goReport = buildLaunchDenominatorReport(scope, {
    pilot: {
      coveredRowIds: scope.verifiedAccessibilityScope.includedStationIds.flatMap((stationId) =>
        scope.verifiedAccessibilityScope.requiredFacilityTypes.map((facilityType) =>
          `${stationId}|${scope.verifiedAccessibilityScope.includedLineIds[0]}|${facilityType}`)),
    },
    routing: {
      regionIds: [...scope.routingLaunchScope.regionIds],
      operatorIds: [...scope.routingLaunchScope.operatorIds],
      lineIds: [...scope.routingLaunchScope.lineIds],
      baseStationIds: [...scope.routingLaunchScope.baseRoutingStationIds],
      admittedStationIds,
      materializedStationIds: [...admittedStationIds],
      transferStationIds: [...scope.routingLaunchScope.requiredTransferStationIds],
      baseEdgeIds: [...scope.routingLaunchScope.requiredBaseEdgeIds],
      transferEdgeIds: [...scope.routingLaunchScope.requiredTransferEdgeIds],
      sourceDerivedConnectionEdgeIds: { status: "ADMITTED", ids: sourceDerivedConnectionEdgeIds },
      serviceIds: [...scope.routingLaunchScope.serviceIds],
    },
    source: {
      status: "ADMITTED",
      freshness: "FRESH",
      routingScopeHash: canonicalScopeHash(scope.routingLaunchScope),
      admittedStationIds,
      sourceDerivedConnectionEdgeIds,
      artifactHash: "a".repeat(64),
      identity,
    },
    server: { status: "ACTIVE", routingReady: true, artifactHash: "b".repeat(64), identity },
    mobile: { status: "READY", topologyReady: true, artifactHash: "c".repeat(64), identity },
    safety: { signatureValid: true, rollbackVerified: true, freshness: "FRESH", lineage: "VERIFIED" },
    claims: {
      accessibilityScopeId: scope.verifiedAccessibilityScope.id,
      routingScopeId: scope.routingLaunchScope.id,
      serviceIds: [...scope.routingLaunchScope.serviceIds],
    },
    forbiddenEvidence: [],
    forbiddenEvidenceStatus: "VERIFIED",
    nationwide: { missingCount: 270 },
  });
  assert.equal(goReport.decision, "GO");
  const goReportRaw = `${JSON.stringify(goReport, null, 2)}\n`;
  await writeFile(launchReportPath, goReportRaw);
  const reportArgs = ["--launch-report", launchReportPath];
  const validatorCommand = [
    "tools/datapack/validate-release-evidence-bundle.mjs",
    "--bundle",
    bundlePath,
    ...reportArgs,
  ];
  const bindLaunchReport = (target, report, raw) => Object.assign(target, {
    scopeId: report.scopes.verifiedAccessibilityScope.id,
    verifiedAccessibilityScopeId: report.scopes.verifiedAccessibilityScope.id,
    verifiedAccessibilityScopeSha256: report.scopes.verifiedAccessibilityScope.sha256,
    launchScopeId: report.scopes.routingLaunchScope.id,
    launchScopeSha256: report.scopes.routingLaunchScope.sha256,
    nationwideRoadmapScopeId: report.scopes.nationwideRoadmapScope.id,
    nationwideRoadmapScopeSha256: report.scopes.nationwideRoadmapScope.sha256,
    identityLinkageMatrixSha256: report.identityLinkage.matrixSha256,
    launchDenominatorDecision: report.decision,
    launchDenominatorReportSha256: createHash("sha256").update(raw).digest("hex"),
  });
  const bundle = {
    schemaVersion: 1,
    artifactKind: "datapack-release-evidence-bundle",
    candidateId: "capital@1",
    scopeId: "capital_pilot_android_v1",
    releaseRequestId: "release-request-1",
    builderGitSha: "abcdef1",
    buildSpecSha256: hash,
    supportedDenominatorSha256: hash,
    sourceSnapshotSetHash: hash,
    approvedAliasLedgerHash: hash,
    facilityEvidenceLedgerHash: hash,
    routeEvidenceLedgerHash: hash,
    approvedOverrideSetHash: hash,
    normalizedSourceInventorySha256: hash,
    sqliteSha256: hash,
    gzipSha256: hash,
    manifestSha256: hash,
    coverageSummarySha256: hash,
    itxCheongchunCoverageSha256: hash,
    routeMapPositionCoverageSha256: hash,
    routeGraphTopologySha256: hash,
    headwayReportSha256: hash,
    strictRouteRegressionSha256: hash,
    androidEvidenceSha256: hash,
    validatorStatus: "PASS",
    coverageStatus: "PASS",
    routeMapPositionCoverageStatus: "PASS",
    routeGraphTopologyStatus: "PASS",
    routeGraphTopologyViolationCount: 0,
    headwayReportStatus: "PASS",
    strictRouteRegressionStatus: "PASS",
    manifestSignatureStatus: "PASS",
    androidEvidenceStatus: "PASS",
    createdAt: "2026-06-30T00:00:00.000Z",
    workflowRunUrl: "https://github.com/AquilaXk/easysubway/actions/runs/1",
  };
  bindLaunchReport(bundle, goReport, goReportRaw);

  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await execFileAsync(
    process.execPath,
    [
      "tools/datapack/validate-release-evidence-bundle.mjs",
      "--bundle",
      bundlePath,
      ...scopeArgs,
      ...reportArgs,
      "--require-pass",
    ],
    { cwd: root },
  );

  const currentLaunchReportRaw = await readFile(path.join(root, currentLaunchReportPath), "utf8");
  const currentLaunchReport = JSON.parse(currentLaunchReportRaw);
  bindLaunchReport(bundle, currentLaunchReport, currentLaunchReportRaw);
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await execFileAsync(process.execPath, [
    "tools/datapack/validate-release-evidence-bundle.mjs",
    "--bundle",
    bundlePath,
    ...scopeArgs,
    "--launch-report",
    currentLaunchReportPath,
  ], { cwd: root });
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/datapack/validate-release-evidence-bundle.mjs",
      "--bundle",
      bundlePath,
      ...scopeArgs,
      "--launch-report",
      currentLaunchReportPath,
      "--require-pass",
    ], { cwd: root }),
    /launch denominator decision must be GO for publish/,
  );

  bundle.launchDenominatorDecision = "GO";
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/datapack/validate-release-evidence-bundle.mjs",
      "--bundle",
      bundlePath,
      ...scopeArgs,
      "--launch-report",
      currentLaunchReportPath,
    ], { cwd: root }),
    /launch denominator report decision must match bundle/,
  );

  bindLaunchReport(bundle, currentLaunchReport, currentLaunchReportRaw);
  bundle.launchDenominatorReportSha256 = "f".repeat(64);
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/datapack/validate-release-evidence-bundle.mjs",
      "--bundle",
      bundlePath,
      ...scopeArgs,
      "--launch-report",
      currentLaunchReportPath,
    ], { cwd: root }),
    /launch denominator report sha256 mismatch/,
  );

  const forgedGoReport = structuredClone(currentLaunchReport);
  forgedGoReport.decision = "GO";
  forgedGoReport.blockers = [];
  const forgedGoReportRaw = `${JSON.stringify(forgedGoReport, null, 2)}\n`;
  const forgedGoReportPath = path.join(outputDir, "launch-denominator-forged-go.json");
  await writeFile(forgedGoReportPath, forgedGoReportRaw);
  bindLaunchReport(bundle, forgedGoReport, forgedGoReportRaw);
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/datapack/validate-release-evidence-bundle.mjs",
      "--bundle",
      bundlePath,
      ...scopeArgs,
      "--launch-report",
      forgedGoReportPath,
      "--require-pass",
    ], { cwd: root }),
    /launch denominator report must match canonical evaluator output/,
  );

  const forgedEmptyIdentityReport = structuredClone(goReport);
  for (const consumer of ["source", "server", "mobile"]) {
    for (const field of ["canonicalStationVersion", "corridorId", "serviceId", "lineageId", "schemaVersion"]) {
      forgedEmptyIdentityReport.evaluatorInput[consumer].identity[field] = "";
    }
  }
  for (const field of ["canonicalStationVersion", "corridorId", "serviceId", "lineageId", "schemaVersion"]) {
    forgedEmptyIdentityReport.identityLinkage.shared[field] = "";
  }
  const forgedEmptyIdentityRaw = `${JSON.stringify(forgedEmptyIdentityReport, null, 2)}\n`;
  const forgedEmptyIdentityPath = path.join(outputDir, "launch-denominator-forged-empty-identity.json");
  await writeFile(forgedEmptyIdentityPath, forgedEmptyIdentityRaw);
  bindLaunchReport(bundle, forgedEmptyIdentityReport, forgedEmptyIdentityRaw);
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/datapack/validate-release-evidence-bundle.mjs",
      "--bundle",
      bundlePath,
      ...scopeArgs,
      "--launch-report",
      forgedEmptyIdentityPath,
      "--require-pass",
    ], { cwd: root }),
    /launch denominator report must match canonical evaluator output/,
  );

  const mismatchedReport = structuredClone(currentLaunchReport);
  mismatchedReport.scopes.routingLaunchScope.sha256 = "f".repeat(64);
  const mismatchedReportRaw = `${JSON.stringify(mismatchedReport, null, 2)}\n`;
  const mismatchedReportPath = path.join(outputDir, "launch-denominator-mismatched.json");
  await writeFile(mismatchedReportPath, mismatchedReportRaw);
  bindLaunchReport(bundle, mismatchedReport, mismatchedReportRaw);
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/datapack/validate-release-evidence-bundle.mjs",
      "--bundle",
      bundlePath,
      ...scopeArgs,
      "--launch-report",
      mismatchedReportPath,
    ], { cwd: root }),
    /launch denominator report routing scope identity mismatch/,
  );

  bindLaunchReport(bundle, goReport, goReportRaw);

  bundle.launchScopeSha256 = "f".repeat(64);
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(process.execPath, [
      "tools/datapack/validate-release-evidence-bundle.mjs",
      "--bundle",
      bundlePath,
      ...scopeArgs,
      ...reportArgs,
    ], { cwd: root }),
    /launch denominator report routing scope binding mismatch/,
  );
  bundle.launchScopeSha256 = goReport.scopes.routingLaunchScope.sha256;

  bundle.androidEvidenceStatus = "FAIL";
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [...validatorCommand, "--require-pass"],
      { cwd: root },
    ),
    /androidEvidenceStatus must be PASS for publish/,
  );

  bundle.androidEvidenceStatus = "PASS";
  bundle.headwayReportStatus = "DEFERRED";
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await execFileAsync(
    process.execPath,
    [...validatorCommand, "--require-pass"],
    { cwd: root },
  );

  bundle.headwayReportStatus = "PASS";
  // route_graph_topology는 capital pilot deferred domain이므로 위반 기록 시 DEFERRED가 publish gate를 통과한다.
  bundle.routeGraphTopologyStatus = "DEFERRED";
  bundle.routeGraphTopologyViolationCount = 4;
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await execFileAsync(
    process.execPath,
    [...validatorCommand, "--require-pass"],
    { cwd: root },
  );

  // deferred가 아닌 다른 게이트(예: routeMapPositionCoverageStatus)는 DEFERRED를 허용하지 않는다.
  bundle.routeGraphTopologyStatus = "PASS";
  bundle.routeGraphTopologyViolationCount = 0;
  bundle.routeMapPositionCoverageStatus = "DEFERRED";
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [...validatorCommand, "--require-pass"],
      { cwd: root },
    ),
    /routeMapPositionCoverageStatus must be a release gate status/,
  );

  bundle.routeMapPositionCoverageStatus = "PASS";
  bundle.validatorStatus = "DEFERRED";
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(process.execPath, validatorCommand, {
      cwd: root,
    }),
    /validatorStatus must be a release gate status/,
  );

  // route_graph_topology status와 위반 수치의 정합을 런타임에서 강제한다.
  bundle.validatorStatus = "PASS";
  // DEFERRED인데 위반 0 → 위반 은폐 모순, 거부.
  bundle.routeGraphTopologyStatus = "DEFERRED";
  bundle.routeGraphTopologyViolationCount = 0;
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [...validatorCommand, "--require-pass"],
      { cwd: root },
    ),
    /routeGraphTopologyStatus DEFERRED requires routeGraphTopologyViolationCount > 0/,
  );

  // PASS인데 위반 수치가 0이 아님 → 모순, 거부.
  bundle.routeGraphTopologyStatus = "PASS";
  bundle.routeGraphTopologyViolationCount = 4;
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [...validatorCommand, "--require-pass"],
      { cwd: root },
    ),
    /routeGraphTopologyStatus PASS requires routeGraphTopologyViolationCount 0/,
  );

  // 음수 위반 수치 거부.
  bundle.routeGraphTopologyStatus = "PASS";
  bundle.routeGraphTopologyViolationCount = -1;
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [...validatorCommand, "--require-pass"],
      { cwd: root },
    ),
    /routeGraphTopologyViolationCount must be a non-negative integer/,
  );

  // 위반 수치 누락 거부.
  bundle.routeGraphTopologyViolationCount = 0;
  delete bundle.routeGraphTopologyViolationCount;
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await assert.rejects(
    execFileAsync(
      process.execPath,
      [...validatorCommand, "--require-pass"],
      { cwd: root },
    ),
    /release evidence bundle missing routeGraphTopologyViolationCount/,
  );

  // 실데이터 경로(위반 4, DEFERRED) 정합 → 통과 유지.
  bundle.routeGraphTopologyStatus = "DEFERRED";
  bundle.routeGraphTopologyViolationCount = 4;
  await writeFile(bundlePath, `${JSON.stringify(bundle, null, 2)}\n`);
  await execFileAsync(
    process.execPath,
    [...validatorCommand, "--require-pass"],
    { cwd: root },
  );
});
