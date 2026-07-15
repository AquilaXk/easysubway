import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

import {
  assertRepositoryRelativePath,
  validateSourceSnapshotFreshness,
} from "./validate-source-snapshot-freshness.mjs";

const evaluationAt = "2026-07-15T00:00:00.000Z";
const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const policy = {
  clockSkewSeconds: 300,
  sourceClasses: [{
    id: "static_network_metadata",
    sourceIds: ["source-a"],
    basisField: "retrievedAt",
    reverificationCadence: "P30D",
  }],
};

function input(overrides = {}) {
  const snapshots = [{
    snapshotId: "snapshot-a",
    sourceId: "source-a",
    rawObjectUri: "s3://bucket/snapshot-a.json",
    rawSha256: "a".repeat(64),
    redactedRequestFingerprint: "b".repeat(64),
    schemaFingerprint: "c".repeat(64),
    licenseStatus: "PASS",
    redistributionAllowed: true,
    snapshotStatus: "LOCKED",
    credentialRedacted: true,
    retrievedAt: "2026-07-12T00:00:00Z",
    sourceUpdatedAt: null,
    rowCount: 10,
    coverageCount: 10,
    previousSnapshotId: null,
    diffSummary: null,
    freshnessExpiresAt: "2026-08-11T00:00:00Z",
    rawRetentionExpiresAt: "2026-10-10T00:00:00.000Z",
    governancePolicyVersion: "2026-07-15",
    governancePolicySha256: "d".repeat(64),
    ...overrides,
  }];
  return {
    snapshots,
    buildSpec: {
      sourceSnapshotIds: ["snapshot-a"],
      sourceSnapshots: snapshots.map((snapshot) => ({
        snapshotId: snapshot.snapshotId,
        sourceId: snapshot.sourceId,
        rawObjectUri: snapshot.rawObjectUri,
        rawSha256: snapshot.rawSha256,
        redactedRequestFingerprint: snapshot.redactedRequestFingerprint,
        schemaFingerprint: snapshot.schemaFingerprint,
        licenseStatus: snapshot.licenseStatus,
        redistributionAllowed: snapshot.redistributionAllowed,
        snapshotStatus: snapshot.snapshotStatus,
        credentialRedacted: snapshot.credentialRedacted,
        freshnessExpiresAt: snapshot.freshnessExpiresAt,
        rawRetentionExpiresAt: snapshot.rawRetentionExpiresAt,
        governancePolicyVersion: snapshot.governancePolicyVersion,
        governancePolicySha256: snapshot.governancePolicySha256,
      })),
      sourceSnapshotSetHash: createHash("sha256").update(JSON.stringify(snapshots)).digest("hex"),
    },
    policy,
    evaluationAt,
  };
}

test("source snapshot ID·hash·policy 파생 freshness가 맞으면 통과한다", () => {
  const result = validateSourceSnapshotFreshness(input());

  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].status, "FRESH");
});

test("선택한 head만 freshness를 판정하고 만료된 이전 snapshot은 lineage로만 검증한다", () => {
  const value = input();
  const previous = {
    ...value.snapshots[0],
    snapshotId: "snapshot-a-1",
    retrievedAt: "2026-05-01T00:00:00Z",
    freshnessExpiresAt: "2026-05-31T00:00:00Z",
    previousSnapshotId: null,
    diffSummary: null,
  };
  const head = {
    ...value.snapshots[0],
    snapshotId: "snapshot-a-2",
    previousSnapshotId: previous.snapshotId,
    diffSummary: {
      status: "NO_CHANGE",
      rawHashChanged: false,
      schemaHashChanged: false,
      requestHashChanged: false,
      sourceUpdatedAtChanged: false,
      rowDelta: 0,
      coverageDelta: 0,
    },
  };
  value.snapshots = [previous, head];
  value.buildSpec.sourceSnapshotIds = [head.snapshotId];
  value.buildSpec.sourceSnapshots = value.buildSpec.sourceSnapshots.map((snapshot) => ({
    ...snapshot,
    snapshotId: head.snapshotId,
  }));
  value.buildSpec.sourceSnapshotSetHash = createHash("sha256")
    .update(JSON.stringify([head]))
    .digest("hex");

  const result = validateSourceSnapshotFreshness(value);

  assert.deepEqual(result.results.map((entry) => entry.snapshotId), [head.snapshotId]);
});

test("lineage head가 아닌 이전 snapshot을 release 대상으로 선택하면 거부한다", () => {
  const value = input();
  const previous = {
    ...value.snapshots[0],
    snapshotId: "snapshot-a-1",
    previousSnapshotId: null,
    diffSummary: null,
  };
  const head = {
    ...value.snapshots[0],
    snapshotId: "snapshot-a-2",
    retrievedAt: "2026-07-13T00:00:00Z",
    previousSnapshotId: previous.snapshotId,
    diffSummary: {
      status: "NO_CHANGE",
      rawHashChanged: false,
      schemaHashChanged: false,
      requestHashChanged: false,
      sourceUpdatedAtChanged: false,
      rowDelta: 0,
      coverageDelta: 0,
    },
  };
  value.snapshots = [previous, head];
  value.buildSpec.sourceSnapshotIds = [previous.snapshotId];
  value.buildSpec.sourceSnapshots = value.buildSpec.sourceSnapshots.map((snapshot) => ({
    ...snapshot,
    snapshotId: previous.snapshotId,
  }));
  value.buildSpec.sourceSnapshotSetHash = createHash("sha256")
    .update(JSON.stringify([previous]))
    .digest("hex");

  assert.throws(
    () => validateSourceSnapshotFreshness(value),
    /SOURCE_LINEAGE_BROKEN: selected snapshot is not source head/,
  );
});

test("production 필수 source가 build snapshot에서 빠지면 governance GO를 거부한다", () => {
  const value = input();
  value.inventory = {
    sources: [
      { id: "source-a", requiredForProductionPack: true },
      { id: "source-b", requiredForProductionPack: true },
    ],
  };
  value.governancePolicy = {};
  value.governancePolicySha256 = "d".repeat(64);

  assert.throws(
    () => validateSourceSnapshotFreshness(value),
    /SOURCE_FRESHNESS_POLICY_MISSING: required production source source-b/,
  );
});

test("실제 release build spec은 governance 계약으로 freshness를 통과한다", async () => {
  const { stdout } = await execFileAsync(process.execPath, [
    "tools/datapack/validate-source-snapshot-freshness.mjs",
    "--build-spec", "tools/datapack/release/candidate-build-spec.json",
    "--policy", "apps/mobile/release/datapack-freshness-sla.json",
    "--governance-policy", "tools/datapack/source-governance-policy.json",
    "--inventory", "tools/datapack/source-inventory.json",
    "--evaluation-at", evaluationAt,
  ], { cwd: root });

  assert.equal(JSON.parse(stdout).governanceDecision, "GO");
});

test("승인 allowlist 밖의 unbound snapshot은 build spec policy로 backfill할 수 없다", () => {
  const value = input();
  delete value.snapshots[0].governancePolicyVersion;
  delete value.snapshots[0].governancePolicySha256;
  value.buildSpec.sourceSnapshotSetHash = createHash("sha256")
    .update(JSON.stringify(value.snapshots))
    .digest("hex");
  value.governancePolicy = {};
  value.inventory = { sources: [] };
  value.governancePolicySha256 = "d".repeat(64);

  assert.throws(
    () => validateSourceSnapshotFreshness(value),
    /SOURCE_FRESHNESS_POLICY_MISSING: governance policy binding/,
  );
});

test("승인 legacy snapshot ID를 재사용해도 exact evidence hash가 다르면 backfill할 수 없다", () => {
  const value = input({
    snapshotId: "kric-subway-timetable-line4-pilot-20260709",
  });
  delete value.snapshots[0].governancePolicyVersion;
  delete value.snapshots[0].governancePolicySha256;
  value.buildSpec.sourceSnapshotIds = [value.snapshots[0].snapshotId];
  value.buildSpec.sourceSnapshots[0].snapshotId = value.snapshots[0].snapshotId;
  value.buildSpec.sourceSnapshotSetHash = createHash("sha256")
    .update(JSON.stringify(value.snapshots))
    .digest("hex");
  value.governancePolicy = {};
  value.inventory = { sources: [] };
  value.governancePolicySha256 = "d".repeat(64);

  assert.throws(
    () => validateSourceSnapshotFreshness(value),
    /SOURCE_FRESHNESS_POLICY_MISSING: governance policy binding/,
  );
});

test("governance 입력이 없으면 provenance의 governance binding도 선택 사항이다", () => {
  const value = input();
  delete value.snapshots[0].governancePolicyVersion;
  delete value.snapshots[0].governancePolicySha256;
  delete value.buildSpec.sourceSnapshots[0].governancePolicyVersion;
  delete value.buildSpec.sourceSnapshots[0].governancePolicySha256;
  value.buildSpec.sourceSnapshotSetHash = createHash("sha256")
    .update(JSON.stringify(value.snapshots))
    .digest("hex");

  assert.doesNotThrow(() => validateSourceSnapshotFreshness(value));
});

test("source snapshot evidence의 absolute relative-result를 거부한다", () => {
  assert.throws(
    () => assertRepositoryRelativePath("/other-drive/snapshots.json"),
    /must stay within the repository/,
  );
});

test("저장된 far-future expiry는 fail closed한다", () => {
  assert.throws(
    () => validateSourceSnapshotFreshness(input({ freshnessExpiresAt: "2099-08-01T00:00:00Z" })),
    /SOURCE_FRESHNESS_DERIVATION_MISMATCH/,
  );
});

test("build spec의 snapshot ID와 evidence가 다르면 fail closed한다", () => {
  const value = input();
  value.buildSpec.sourceSnapshotIds = ["snapshot-other"];

  assert.throws(() => validateSourceSnapshotFreshness(value), /source snapshot IDs/);
});

test("build provenance와 검증 evidence의 snapshot 내용이 다르면 fail closed한다", () => {
  const value = input();
  value.buildSpec.sourceSnapshots[0].rawObjectUri = "s3://bucket/other.json";

  assert.throws(
    () => validateSourceSnapshotFreshness(value),
    /source snapshot provenance/,
  );
});

test("build admission hash와 canonical snapshot hash는 의미가 달라도 freshness를 검증한다", () => {
  const value = input();
  value.buildSpec.sourceSnapshots[0].rawSha256 = "d".repeat(64);
  value.buildSpec.sourceSnapshots[0].schemaFingerprint = "e".repeat(64);

  const result = validateSourceSnapshotFreshness(value);

  assert.equal(result.results[0].status, "FRESH");
});
