import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { buildGateFragments } from "./build-datapack-prelaunch-gate-evidence.mjs";
const sha = (value) => createHash("sha256").update(value).digest("hex");
const evaluatedAt = "2026-07-17T00:00:00.000Z";
const snapshotSetIdentity = "a".repeat(64);
const manifestSha256 = "b".repeat(64);
const packSha256 = "c".repeat(64);
function fixture() {
  const rcIdentity = {
    gitSha: "d".repeat(40), appVersionName: "1.0.0", versionCode: "1",
    aabSha256: null, aabPayloadSha256: null, backendImageDigest: null,
    backendArtifactSha256: null, dataPackManifestSha256: manifestSha256,
    dataPackArtifactSha256: packSha256, dataPackFallbackArtifactSha256: packSha256,
    sourceSnapshotSetHash: snapshotSetIdentity, supportContactSetSha256: null,
    releaseSequence: 3, routeContractVersion: "route-map-contract-v1",
    realtimeContractVersion: "realtime-v1", launchScopeId: "capital",
    launchScopeSha256: "e".repeat(64), nationwideRoadmapScopeId: "nationwide",
    nationwideRoadmapScopeSha256: "f".repeat(64), identityLinkageMatrixSha256: "1".repeat(64),
  };
  const sources = ["source-a", "source-b"].map((sourceId, index) => ({
    sourceId, snapshotId: `${sourceId}-snapshot`, rawSha256: String(index + 2).repeat(64),
    licenseStatus: "PASS", redistributionAllowed: true, snapshotStatus: "LOCKED",
    credentialRedacted: true, freshnessExpiresAt: "2026-08-16T00:00:00.000Z",
    rawRetentionExpiresAt: "2026-10-16T00:00:00.000Z",
    governancePolicyVersion: "2026-07-15", governancePolicySha256: "9".repeat(64),
  }));
  const references = Object.fromEntries([
    "source", "freshness", "rollback", "android", "callback", "backend", "callbackExecution",
    "androidDevice", "conditionalPublish",
  ].map((id, index) => [id, { artifactId: `${id}-report`, sha256: String((index % 8) + 2).repeat(64) }]));
  return {
    candidate: { phase: "CANDIDATE", releaseCandidateIdentity: rcIdentity },
    buildSpec: { sourceSnapshotSetHash: snapshotSetIdentity, sourceSnapshots: sources },
    sourceReport: { status: "PASS", governanceDecision: "GO", snapshotCount: 2, sourceSnapshotSetHash: snapshotSetIdentity },
    rollbackReport: {
      from: { releaseSequence: 2 }, failed: { releaseSequence: 2, manifestSha256: "6".repeat(64) },
      knownGood: { releaseSequence: 1, manifestSha256: "7".repeat(64), packs: [{ sha256: packSha256 }] },
      knownGoodArtifactSha256: packSha256,
      failedArtifactSha256: "8".repeat(64),
      distinctFailedAndKnownGoodPayloads: true,
      rescue: { releaseSequence: 3, manifestSha256 }, status: "PASS",
      validatorStatus: "PASS", manifestLastStatus: "PASS", idempotentReplay: true,
      productionExecuted: false, executionEnvironment: "ISOLATED_PRELAUNCH",
    },
    callbackReport: {
      schemaVersion: 1, executionEnvironment: "ISOLATED_PRELAUNCH", productionExecuted: false,
      payload: {
        releaseRequestId: `prelaunch-${manifestSha256}`, releaseSequence: 3,
        manifestSha256, idempotencyKey: `prelaunch-${manifestSha256}:3:${manifestSha256}`,
      },
      delivery: {
        state: "DELIVERED", idempotencyKey: `prelaunch-${manifestSha256}:3:${manifestSha256}`,
        attempts: [{ attempt: 1, httpClass: "5XX", nextRetrySeconds: 60 }, { attempt: 2, httpClass: "2XX" }],
      },
      terminalHandoff: {
        state: "RECONCILIATION_REQUIRED", idempotencyKey: `prelaunch-${manifestSha256}:3:${manifestSha256}`,
        attempts: [
          { attempt: 1, httpClass: "5XX", nextRetrySeconds: 60 },
          { attempt: 2, httpClass: "5XX", nextRetrySeconds: 480 },
          { attempt: 3, httpClass: "5XX", nextRetrySeconds: 3600 },
          { attempt: 4, httpClass: "5XX" },
        ],
      },
      metrics: { controlPlaneConvergenceMs: 60_000, terminalDispositionMs: 4_140_000 },
    },
    conditionalPublishReport: {
      schemaVersion: 1, executionEnvironment: "ISOLATED_PRELAUNCH",
      productionExecuted: false, productionWriteCount: 0,
      noChange: { outcome: "NO_CHANGE_VALID", productionWriteAllowed: false, publishAttempted: false },
      candidatePublish: {
        outcome: "PUBLISHED_AND_VERIFIED", publishAttempted: true, remoteValidationPassed: true,
        selectedManifestSha256: manifestSha256, selectedReleaseSequence: 3,
      },
      isolatedTarget: {
        manifestSha256, artifactSha256: packSha256, immutableManifestWritten: true,
        channelManifestWrittenLast: true, readBackVerified: true,
        idempotentReplayVerified: true, immutableConflictRejected: true,
        executor: "tools/datapack/publish-object-storage.mjs",
      },
    },
    androidDeviceReport: {
      artifactKind: "android-datapack-monotonic-rescue-evidence", status: "PASS",
      rcManifestSha256: manifestSha256, rcArtifactSha256: packSha256, rescueReleaseSequence: 3,
      rcManifestBytesVerified: true, rcArtifactBytesVerified: true,
      rcSignatureVerified: true, rcSqliteIntegrityVerified: true,
      rcUpdaterReplayVerified: true,
      knownGoodManifestSha256: "7".repeat(64), knownGoodArtifactSha256: packSha256,
      failedManifestSha256: "6".repeat(64), failedArtifactSha256: "8".repeat(64),
      knownGoodContentRestored: true, idempotentReplayVerified: true,
      corruptSuccessorPreservedKnownGood: true, lowerSequenceRejected: true, recoveryElapsedMs: 125,
    },
    backendReconciliationReport: {
      artifactKind: "backend-datapack-reconciliation-evidence", status: "PASS",
      manifestSha256, releaseSequence: 3, convergedWithinTenMinutes: true,
    },
    verifiedSuites: new Set(["source", "freshness", "rollback", "android", "callback", "backend"]),
    references,
    evaluatedAt,
  };
}
test("동일 RC의 네 prelaunch gate fragment를 생성한다", () => {
  const fragments = buildGateFragments(fixture());
  assert.deepEqual(Object.keys(fragments).sort(), [
    "callback_reconciliation", "freshness_conditional_publish", "rollback_rescue", "source_governance",
  ]);
  for (const [gateId, fragment] of Object.entries(fragments)) {
    assert.equal(fragment.gateId, gateId);
    assert.equal(fragment.status, "SATISFIED");
    assert.deepEqual(fragment.reasonCodes, []);
    assert.equal(fragment.rcIdentity.dataPackManifestSha256, manifestSha256);
  }
  assert.equal(fragments.source_governance.sourceInventory.statusCounts.APPROVED, 2);
  assert.equal(fragments.rollback_rescue.result.rescueReleaseSequence, 3);
  assert.equal(fragments.callback_reconciliation.result.deliveryIdentity.idempotencyKeySha256,
    sha(`prelaunch-${manifestSha256}:3:${manifestSha256}`));
});
test("snapshot identity가 RC와 다르면 fail closed한다", () => {
  const input = fixture();
  input.sourceReport.sourceSnapshotSetHash = "0".repeat(64);
  assert.throws(() => buildGateFragments(input), /source snapshot identity mismatch/);
});
test("source gate와 inventory 만료는 실제 snapshot 최단 만료를 넘지 않는다", () => {
  const input = fixture();
  input.buildSpec.sourceSnapshots[0].freshnessExpiresAt = "2026-07-20T00:00:00.000Z";
  const fragments = buildGateFragments(input);
  assert.equal(fragments.source_governance.evidenceValidity.expiresAt, "2026-07-20T00:00:00.000Z");
  assert.equal(fragments.freshness_conditional_publish.evidenceValidity.expiresAt, "2026-07-20T00:00:00.000Z");
  assert.equal(fragments.source_governance.sourceInventory.entries[0].expiresAt, "2026-07-20T00:00:00.000Z");
  assert.equal(fragments.source_governance.sourceInventory.entries[1].expiresAt, "2026-07-31T00:00:00.000Z");
  assert.equal(fragments.rollback_rescue.evidenceValidity.expiresAt, "2026-07-31T00:00:00.000Z");
});
test("rescue identity가 RC와 다르면 fail closed한다", () => {
  const input = fixture();
  input.rollbackReport.rescue.releaseSequence = 4;
  assert.throws(() => buildGateFragments(input), /rollback rescue identity mismatch/);
});
test("필수 machine suite가 없으면 SATISFIED를 만들지 않는다", () => {
  const input = fixture();
  input.verifiedSuites.delete("android");
  assert.throws(() => buildGateFragments(input), /missing verified suite: android/);
});
test("public production 실행으로 표시된 report는 prelaunch evidence로 거부한다", () => {
  const input = fixture();
  input.rollbackReport.productionExecuted = true;
  assert.throws(() => buildGateFragments(input), /isolated prelaunch/);
});
test("동일 RC에 결속된 callback 실행 report가 없으면 fail closed한다", () => {
  const input = fixture();
  input.callbackReport.payload.manifestSha256 = "0".repeat(64);
  assert.throws(() => buildGateFragments(input), /callback execution identity mismatch/);
});
test("Android device rescue report가 RC와 다르면 fail closed한다", () => {
  const input = fixture();
  input.androidDeviceReport.rescueReleaseSequence = 4;
  assert.throws(() => buildGateFragments(input), /Android device rescue evidence/);
});
test("Android가 실제 RC bytes와 signature를 검증하지 않으면 fail closed한다", () => {
  const input = fixture();
  input.androidDeviceReport.rcSignatureVerified = false;
  assert.throws(() => buildGateFragments(input), /Android device rescue evidence/);
});
test("failed와 known-good payload가 같으면 rollback gate를 만들지 않는다", () => {
  const input = fixture();
  input.rollbackReport.failedArtifactSha256 = packSha256;
  input.androidDeviceReport.failedArtifactSha256 = packSha256;
  assert.throws(() => buildGateFragments(input), /not distinct/);
});
test("Android updater가 실제 RC를 replay하지 않으면 fail closed한다", () => {
  const input = fixture();
  input.androidDeviceReport.rcUpdaterReplayVerified = false;
  assert.throws(() => buildGateFragments(input), /Android device rescue evidence/);
});
test("conditional publish report가 실제 isolated write와 RC에 결속되지 않으면 fail closed한다", () => {
  const input = fixture();
  input.conditionalPublishReport.productionWriteCount = 1;
  assert.throws(() => buildGateFragments(input), /conditional publish rehearsal/);
});
test("실제 executor의 immutable conflict 검증이 없으면 fail closed한다", () => {
  const input = fixture();
  input.conditionalPublishReport.isolatedTarget.immutableConflictRejected = false;
  assert.throws(() => buildGateFragments(input), /conditional publish rehearsal/);
});
test("backend reconciliation report가 RC와 다르면 fail closed한다", () => {
  const input = fixture();
  input.backendReconciliationReport.manifestSha256 = "0".repeat(64);
  assert.throws(() => buildGateFragments(input), /backend reconciliation evidence/);
});
test("prelaunch Android emulator 실행 전에 KVM 권한을 활성화한다", async () => {
  const workflow = await readFile(new URL(
    "../../.github/workflows/datapack-prelaunch-gates.yml", import.meta.url,
  ), "utf8");
  const kvmStep = workflow.indexOf("      - name: Enable KVM group permissions");
  const emulatorStep = workflow.indexOf("      - name: Rehearse monotonic rescue on Android emulator");

  assert.notEqual(kvmStep, -1, "KVM 권한 활성화 단계가 필요하다");
  assert.notEqual(emulatorStep, -1, "Android emulator 단계가 필요하다");
  assert.ok(kvmStep < emulatorStep, "KVM 권한은 emulator 실행 전에 활성화해야 한다");
  assert.match(workflow, /KERNEL=="kvm", GROUP="kvm", MODE="0666"/);
  assert.match(workflow, /sudo udevadm control --reload-rules/);
  assert.match(workflow, /sudo udevadm trigger --name-match=kvm/);
});
test("prelaunch Android integration test는 mobile 작업 디렉터리에서 실행한다", async () => {
  const workflow = await readFile(new URL(
    "../../.github/workflows/datapack-prelaunch-gates.yml", import.meta.url,
  ), "utf8");
  const emulatorStart = workflow.indexOf("      - name: Rehearse monotonic rescue on Android emulator");
  const nextStep = workflow.indexOf("\n      - name:", emulatorStart + 1);
  const emulatorStep = workflow.slice(emulatorStart, nextStep);

  assert.match(emulatorStep, /working-directory:\s*apps\/mobile/);
  assert.doesNotMatch(emulatorStep, /script:\s*\|\s*\n\s*cd apps\/mobile/);
});
test("prelaunch Android integration 명령은 하나의 shell invocation으로 전달한다", async () => {
  const workflow = await readFile(new URL(
    "../../.github/workflows/datapack-prelaunch-gates.yml", import.meta.url,
  ), "utf8");
  const emulatorStart = workflow.indexOf("      - name: Rehearse monotonic rescue on Android emulator");
  const nextStep = workflow.indexOf("\n      - name:", emulatorStart + 1);
  const emulatorStep = workflow.slice(emulatorStart, nextStep);

  assert.match(emulatorStep, /script:\s*>-/);
  assert.doesNotMatch(emulatorStep, /\\\s*$/m);
});
test("prelaunch workflow는 네 gate를 같은 RC final readiness에 결속한다", async () => {
  const workflow = await readFile(new URL(
    "../../.github/workflows/datapack-prelaunch-gates.yml", import.meta.url,
  ), "utf8");
  const jobStart = workflow.indexOf("\n  rehearsal:");
  const stepsStart = workflow.indexOf("\n    steps:", jobStart);
  assert.notEqual(jobStart, -1);
  assert.notEqual(stepsStart, -1);
  assert.ok(jobStart < stepsStart);
  assert.doesNotMatch(
    workflow.slice(jobStart, stepsStart),
    /\$\{\{\s*runner\./,
    "job-level configuration cannot use runner context",
  );
  const producer = await readFile(new URL(
    "./build-datapack-prelaunch-gate-evidence.mjs", import.meta.url,
  ), "utf8");
  assert.match(workflow, /build-datapack-prelaunch-gate-evidence\.mjs --mode prepare/);
  assert.match(workflow, /build-datapack-prelaunch-gate-evidence\.mjs --mode collect/);
  assert.match(workflow, /--callback-execution-report/);
  assert.match(workflow, /integration_test\/datapack_monotonic_rescue_test\.dart/);
  assert.match(workflow, /android-rc-bundle\.json/);
  assert.match(workflow, /--android-device-report/);
  assert.match(workflow, /--conditional-publish-report/);
  assert.match(producer, /tools\/datapack\/publish-object-storage\.mjs/);
  for (const gateId of [
    "source_governance", "freshness_conditional_publish", "rollback_rescue", "callback_reconciliation",
  ]) {
    assert.match(workflow, new RegExp(gateId));
  }
  assert.doesNotMatch(workflow, /EASYSUBWAY_DATA_PACK_BASE_URL|catalog\/current\.json.*(?:curl|PUT)/);
  assert.doesNotMatch(workflow, /--release-decision|--data-pack-release-decision/);
});
