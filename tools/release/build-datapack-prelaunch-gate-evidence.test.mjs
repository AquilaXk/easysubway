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
    "source", "freshness", "rollback", "android", "callback", "backend",
  ].map((id, index) => [id, { artifactId: `${id}-report`, sha256: String(index + 2).repeat(64) }]));
  return {
    candidate: { phase: "CANDIDATE", releaseCandidateIdentity: rcIdentity },
    buildSpec: { sourceSnapshotSetHash: snapshotSetIdentity, sourceSnapshots: sources },
    sourceReport: { status: "PASS", governanceDecision: "GO", snapshotCount: 2, sourceSnapshotSetHash: snapshotSetIdentity },
    rollbackReport: {
      from: { releaseSequence: 2 }, failed: { releaseSequence: 2 },
      knownGood: { releaseSequence: 1, packs: [{ sha256: packSha256 }] },
      rescue: { releaseSequence: 3, manifestSha256 }, status: "PASS",
      validatorStatus: "PASS", manifestLastStatus: "PASS", idempotentReplay: true,
      productionExecuted: false, executionEnvironment: "ISOLATED_PRELAUNCH",
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

test("prelaunch workflow는 네 gate를 같은 RC final readiness에 결속한다", async () => {
  const workflow = await readFile(new URL(
    "../../.github/workflows/datapack-prelaunch-gates.yml", import.meta.url,
  ), "utf8");
  assert.match(workflow, /build-datapack-prelaunch-gate-evidence\.mjs --mode prepare/);
  assert.match(workflow, /build-datapack-prelaunch-gate-evidence\.mjs --mode collect/);
  for (const gateId of [
    "source_governance", "freshness_conditional_publish", "rollback_rescue", "callback_reconciliation",
  ]) {
    assert.match(workflow, new RegExp(gateId));
  }
  assert.doesNotMatch(workflow, /EASYSUBWAY_DATA_PACK_BASE_URL|catalog\/current\.json.*(?:curl|PUT)/);
});
