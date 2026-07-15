import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

import {
  buildSnapshotDiff,
  validateLineage,
} from "./source-snapshot-policy.mjs";
import {
  buildGovernanceSummary,
  deriveRawRetentionExpiresAt,
  evaluateSourceGovernance,
  validateSourceGovernancePolicy,
} from "./source-governance-policy.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");

const first = snapshot({ snapshotId: "snapshot-a-1" });
const second = snapshot({
  snapshotId: "snapshot-a-2",
  previousSnapshotId: first.snapshotId,
  retrievedAt: "2026-07-02T00:00:00Z",
});
second.diffSummary = buildSnapshotDiff(first, second);

test("완전한 snapshot chain은 source head까지 추적한다", () => {
  const result = validateLineage([second, first]);

  assert.equal(result.headsBySource["source-a"], second.snapshotId);
  assert.deepEqual(result.chainsBySource["source-a"], [first.snapshotId, second.snapshotId]);
});

test("두 번째 snapshot의 null previousSnapshotId를 거부한다", () => {
  assert.throws(
    () => validateLineage([first, { ...second, previousSnapshotId: null }]),
    /SOURCE_LINEAGE_BROKEN/,
  );
});

test("root snapshot에 diff가 있으면 거부한다", () => {
  assert.throws(
    () => validateLineage([{ ...first, diffSummary: buildSnapshotDiff(first, first) }]),
    /SOURCE_DIFF_MISSING/,
  );
});

test("orphan과 cross-source previous snapshot을 거부한다", () => {
  assert.throws(
    () => validateLineage([first, { ...second, previousSnapshotId: "missing" }]),
    /SOURCE_LINEAGE_BROKEN/,
  );
  assert.throws(
    () => validateLineage([first, snapshot({
      snapshotId: "snapshot-b-1",
      sourceId: "source-b",
      previousSnapshotId: first.snapshotId,
      diffSummary: buildSnapshotDiff(first, second),
    })]),
    /SOURCE_LINEAGE_BROKEN/,
  );
});

test("후속 snapshot retrievedAt은 parent보다 엄격히 이후여야 한다", () => {
  for (const retrievedAt of [first.retrievedAt, "2026-06-30T23:59:59Z"]) {
    const child = snapshot({
      snapshotId: `snapshot-a-${retrievedAt}`,
      previousSnapshotId: first.snapshotId,
      retrievedAt,
    });
    child.diffSummary = buildSnapshotDiff(first, child);

    assert.throws(
      () => validateLineage([first, child]),
      /SOURCE_LINEAGE_BROKEN: retrievedAt order/,
    );
  }
});

test("cycle과 기존 head에서 갈라지는 fork를 거부한다", () => {
  const cycleA = snapshot({ snapshotId: "cycle-a", previousSnapshotId: "cycle-b" });
  const cycleB = snapshot({ snapshotId: "cycle-b", previousSnapshotId: "cycle-a" });
  cycleA.diffSummary = buildSnapshotDiff(cycleB, cycleA);
  cycleB.diffSummary = buildSnapshotDiff(cycleA, cycleB);
  assert.throws(() => validateLineage([cycleA, cycleB]), /SOURCE_LINEAGE_BROKEN/);

  const fork = { ...second, snapshotId: "snapshot-a-3" };
  assert.throws(() => validateLineage([first, second, fork]), /SOURCE_LINEAGE_BROKEN/);
});

test("실제 raw hash 변경을 NO_CHANGE로 기록하면 거부한다", () => {
  const changed = {
    ...second,
    rawSha256: "d".repeat(64),
    diffSummary: { ...second.diffSummary, status: "NO_CHANGE", rawHashChanged: false },
  };

  assert.throws(() => validateLineage([first, changed]), /SOURCE_DIFF_MISSING/);
});

test("snapshot diff는 hash·시각·row·coverage 변화를 결정적으로 기록한다", () => {
  const changed = snapshot({
    snapshotId: "snapshot-a-2",
    previousSnapshotId: first.snapshotId,
    rawSha256: "d".repeat(64),
    sourceUpdatedAt: "2026-07-02T00:00:00Z",
    rowCount: 12,
    coverageCount: 11,
  });

  assert.deepEqual(buildSnapshotDiff(first, changed), {
    status: "CHANGED",
    rawHashChanged: true,
    schemaHashChanged: false,
    requestHashChanged: false,
    sourceUpdatedAtChanged: true,
    rowDelta: 2,
    coverageDelta: 3,
  });
});

test("sourceUpdatedAt은 표기가 달라도 같은 UTC instant면 변경이 아니다", () => {
  const sameInstant = snapshot({
    snapshotId: "snapshot-a-2",
    previousSnapshotId: first.snapshotId,
    retrievedAt: "2026-07-02T00:00:00Z",
    sourceUpdatedAt: "2026-07-01T00:00:00.000Z",
  });

  assert.deepEqual(buildSnapshotDiff(first, sameInstant), {
    status: "NO_CHANGE",
    rawHashChanged: false,
    schemaHashChanged: false,
    requestHashChanged: false,
    sourceUpdatedAtChanged: false,
    rowDelta: 0,
    coverageDelta: 0,
  });
});

test("lineage diff는 JSON 속성 순서가 달라도 같은 구조와 값이면 통과한다", () => {
  const reordered = {
    ...second,
    diffSummary: Object.fromEntries(Object.entries(second.diffSummary).reverse()),
  };

  assert.doesNotThrow(() => validateLineage([first, reordered]));
});

test("snapshot diff와 lineage는 필수 hash·sourceUpdatedAt 형식을 검증한다", () => {
  for (const invalid of [
    { rawSha256: undefined },
    { schemaFingerprint: "invalid" },
    { redactedRequestFingerprint: "A".repeat(64) },
    { sourceUpdatedAt: "2026-02-31T00:00:00Z" },
    { coverageCount: undefined },
  ]) {
    assert.throws(() => buildSnapshotDiff(first, { ...second, ...invalid }), /SOURCE_DIFF_MISSING/);
    assert.throws(() => validateLineage([first, { ...second, ...invalid }]), /SOURCE_DIFF_MISSING/);
  }
});

test("snapshot producer는 previous snapshot에서 diff를 직접 생성한다", async () => {
  const workDir = path.join(tmpdir(), `easysubway-source-lineage-${process.pid}-${Date.now()}`);
  const firstRaw = path.join(workDir, "first.csv");
  const secondRaw = path.join(workDir, "second.csv");
  const firstOutput = path.join(workDir, "first.json");
  const secondOutput = path.join(workDir, "second.json");
  await mkdir(workDir, { recursive: true });
  await writeFile(firstRaw, "station\nSadang\n");
  await writeFile(secondRaw, "station\nSadang\nSangnoksu\n");

  try {
    await buildSnapshot([
      "--input", firstRaw,
      "--output", firstOutput,
      "--snapshot-id", "snapshot-a-1",
      "--retrieved-at", "2026-06-30T03:00:00Z",
      "--freshness-expires-at", "2026-09-28T03:00:00Z",
      "--raw-retention-expires-at", "2026-09-28T03:00:00Z",
      "--coverage-count", "1",
      "--raw-object-uri", "s3://bucket/snapshot-a-1.csv",
    ]);
    await buildSnapshot([
      "--input", secondRaw,
      "--output", secondOutput,
      "--snapshot-id", "snapshot-a-2",
      "--retrieved-at", "2026-07-01T03:00:00Z",
      "--freshness-expires-at", "2026-09-29T03:00:00Z",
      "--raw-retention-expires-at", "2026-09-29T03:00:00Z",
      "--coverage-count", "2",
      "--raw-object-uri", "s3://bucket/snapshot-a-2.csv",
      "--previous-snapshot", firstOutput,
    ]);

    const produced = JSON.parse(await readFile(secondOutput, "utf8"));
    assert.equal(produced.previousSnapshotId, "snapshot-a-1");
    assert.equal(produced.diffSummary.status, "CHANGED");
    assert.equal(produced.diffSummary.rowDelta, 1);
    assert.equal(produced.diffSummary.coverageDelta, 1);
    assert.equal(produced.rawRetentionExpiresAt, "2026-09-29T03:00:00.000Z");
    assert.equal(produced.governancePolicyVersion, "2026-07-15");
    assert.match(produced.governancePolicySha256, /^[0-9a-f]{64}$/);

    await assert.rejects(
      buildSnapshot([
        "--input", secondRaw,
        "--output", secondOutput,
        "--snapshot-id", "snapshot-a-out-of-order",
        "--retrieved-at", "2026-06-30T03:00:00Z",
        "--freshness-expires-at", "2026-09-28T03:00:00Z",
        "--raw-retention-expires-at", "2026-09-28T03:00:00Z",
        "--coverage-count", "2",
        "--raw-object-uri", "s3://bucket/snapshot-a-out-of-order.csv",
        "--previous-snapshot", firstOutput,
      ]),
      /SOURCE_LINEAGE_BROKEN: retrievedAt order/,
    );
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }
});

test("legacy root는 rowCount를 결정적 coverage로 migration해 lineage를 연장한다", () => {
  const legacyRoot = { ...first };
  delete legacyRoot.coverageCount;
  const child = snapshot({
    snapshotId: "snapshot-a-legacy-child",
    previousSnapshotId: legacyRoot.snapshotId,
    retrievedAt: "2026-07-02T00:00:00Z",
    coverageCount: 11,
  });
  child.diffSummary = buildSnapshotDiff(legacyRoot, child);

  assert.equal(child.diffSummary.coverageDelta, 1);
  assert.doesNotThrow(() => validateLineage([legacyRoot, child]));
});

test("tracked production legacy root는 승인 bytes를 바꾸지 않고 검증한다", async () => {
  const snapshots = JSON.parse(await readFile(
    path.join(root, "tools/datapack/release/source-snapshots.json"),
    "utf8",
  ));

  assert.equal(snapshots.filter((entry) => entry.coverageCount == null).length, 9);
  assert.doesNotThrow(() => validateLineage(snapshots));
});

test("governance policy는 production source별 freshness·retention·책임 역할을 요구한다", () => {
  const inventory = { sources: [source()] };
  const policy = governancePolicy();
  const freshnessPolicy = freshnessPolicyFixture();

  assert.doesNotThrow(() => validateSourceGovernancePolicy({ policy, inventory, freshnessPolicy }));
  assert.throws(
    () => validateSourceGovernancePolicy({
      policy: { ...policy, sources: [{ ...policy.sources[0], ownerRole: "" }] },
      inventory,
      freshnessPolicy,
    }),
    /SOURCE_GOVERNANCE_OWNER_MISSING/,
  );
  assert.throws(
    () => validateSourceGovernancePolicy({ policy: { ...policy, sources: [] }, inventory, freshnessPolicy }),
    /SOURCE_GOVERNANCE_OWNER_MISSING/,
  );
  assert.throws(
    () => validateSourceGovernancePolicy({
      policy: { ...policy, policyVersion: "2026-99-99" },
      inventory,
      freshnessPolicy,
    }),
    /policyVersion/,
  );
  assert.throws(
    () => validateSourceGovernancePolicy({
      policy,
      inventory: { sources: [source({ admissionEvidence: {} })] },
      freshnessPolicy,
    }),
    /LICENSE_REVIEW_REQUIRED/,
  );
  assert.throws(
    () => validateSourceGovernancePolicy({
      policy,
      inventory: { sources: [source(), source()] },
      freshnessPolicy,
    }),
    /duplicate inventory source/,
  );
});

test("raw retention 만료는 policy retentionDays에서 결정론적으로 파생한다", () => {
  assert.equal(
    deriveRawRetentionExpiresAt({
      policy: governancePolicy(),
      sourceId: "source-a",
      retrievedAt: "2026-07-01T00:00:00Z",
    }),
    "2026-09-29T00:00:00.000Z",
  );
});

test("freshness 임의 미래값과 expiry 동일 경계는 release를 차단한다", () => {
  const input = governanceInput();
  assert.deepEqual(
    evaluateSourceGovernance({
      ...input,
      snapshot: { ...input.snapshot, freshnessExpiresAt: "2099-01-01T00:00:00Z" },
    }).reasonCodes,
    ["SOURCE_FRESHNESS_POLICY_MISSING"],
  );
  assert.deepEqual(
    evaluateSourceGovernance({ ...input, evaluationAt: "2026-07-31T00:00:00Z" }).reasonCodes,
    ["SOURCE_SNAPSHOT_EXPIRED"],
  );
});

test("license review 기한·terms/provider/endpoint 변경을 REVIEW_REQUIRED로 만든다", () => {
  const input = governanceInput();
  assert.deepEqual(
    evaluateSourceGovernance({ ...input, evaluationAt: "2027-07-01T00:00:00Z" }).reasonCodes,
    ["LICENSE_REVIEW_REQUIRED", "RAW_RETENTION_OVERDUE", "SOURCE_SNAPSHOT_EXPIRED"],
  );
  for (const changedSource of [
    { ...input.source, provider: "changed-provider" },
    { ...input.source, datasetUrl: "https://example.invalid/changed" },
    {
      ...input.source,
      admissionEvidence: { ...input.source.admissionEvidence, licenseEvidenceHash: "f".repeat(64) },
    },
  ]) {
    assert.ok(evaluateSourceGovernance({ ...input, source: changedSource }).reasonCodes.includes("LICENSE_REVIEW_REQUIRED"));
  }
  const futureReviewPolicy = governancePolicy();
  futureReviewPolicy.sources[0].licenseReview.reviewedAt = "2026-07-20T00:00:00Z";
  assert.ok(evaluateSourceGovernance({
    ...input,
    policy: futureReviewPolicy,
  }).reasonCodes.includes("LICENSE_REVIEW_REQUIRED"));
});

test("재배포 권한이 확인되지 않으면 release를 차단한다", () => {
  const input = governanceInput();
  const result = evaluateSourceGovernance({
    ...input,
    snapshot: { ...input.snapshot, redistributionAllowed: false },
  });

  assert.deepEqual(result.reasonCodes, ["REDISTRIBUTION_NOT_APPROVED"]);
  assert.equal(result.decision, "NO_GO");
});

test("legal hold는 역할·사유 코드·유한한 만료시각을 요구하고 유효할 때만 purge를 보호한다", () => {
  const input = governanceInput();
  const expiredSnapshot = {
    ...input.snapshot,
    retrievedAt: "2026-04-16T00:00:00Z",
    rawRetentionExpiresAt: "2026-07-15T00:00:00.000Z",
  };
  const validHold = {
    sourceId: "source-a",
    snapshotId: expiredSnapshot.snapshotId,
    ownerRole: "datapack-source-owner",
    reasonCode: "REGULATORY_AUDIT",
    createdAt: "2026-07-02T00:00:00Z",
    expiresAt: "2026-07-20T00:00:00Z",
  };
  assert.ok(evaluateSourceGovernance({
    ...input,
    snapshot: expiredSnapshot,
    legalHold: { ...validHold, expiresAt: "2026-07-15T00:00:00Z" },
  }).reasonCodes.includes("LEGAL_HOLD_INVALID"));
  assert.ok(evaluateSourceGovernance({
    ...input,
    snapshot: expiredSnapshot,
    legalHold: { ...validHold, createdAt: "2026-07-16T00:00:00Z" },
  }).reasonCodes.includes("LEGAL_HOLD_INVALID"));
  assert.ok(evaluateSourceGovernance({
    ...input,
    snapshot: expiredSnapshot,
    legalHold: { ...validHold, ownerRole: "person-name" },
  }).reasonCodes.includes("LEGAL_HOLD_INVALID"));
  assert.ok(!evaluateSourceGovernance({
    ...input,
    snapshot: expiredSnapshot,
    legalHold: validHold,
  }).reasonCodes.includes("RAW_RETENTION_OVERDUE"));
});

test("같은 입력은 byte-identical governance summary와 hash를 만든다", () => {
  const input = governanceInput();
  const firstSummary = buildGovernanceSummary({ entries: [input], evaluationAt: input.evaluationAt });
  const secondSummary = buildGovernanceSummary({ entries: [input], evaluationAt: input.evaluationAt });

  assert.equal(JSON.stringify(firstSummary), JSON.stringify(secondSummary));
  assert.match(firstSummary.summarySha256, /^[0-9a-f]{64}$/);
  assert.equal(firstSummary.decision, "GO");
});

function snapshot(overrides = {}) {
  return {
    snapshotId: "snapshot-a-1",
    sourceId: "source-a",
    previousSnapshotId: null,
    retrievedAt: "2026-07-01T00:00:00Z",
    sourceUpdatedAt: "2026-07-01T00:00:00Z",
    rawSha256: "a".repeat(64),
    schemaFingerprint: "b".repeat(64),
    redactedRequestFingerprint: "c".repeat(64),
    rowCount: 10,
    coverageCount: 8,
    diffSummary: null,
    ...overrides,
  };
}

function source(overrides = {}) {
  return {
    id: "source-a",
    provider: "provider-a",
    datasetUrl: "https://example.invalid/source-a",
    requiredForProductionPack: true,
    license: { redistributionAllowed: true },
    admissionEvidence: { licenseEvidenceHash: "e".repeat(64) },
    ...overrides,
  };
}

function governancePolicy() {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-source-governance-policy",
    policyVersion: "2026-07-15",
    retentionClasses: [{ id: "standard-90d", retentionDays: 90 }],
    reasonCodeEscalations: [{
      reasonCodes: [
        "SOURCE_LINEAGE_BROKEN",
        "SOURCE_DIFF_MISSING",
        "SOURCE_FRESHNESS_POLICY_MISSING",
        "SOURCE_SNAPSHOT_EXPIRED",
        "RAW_RETENTION_OVERDUE",
        "LEGAL_HOLD_INVALID",
        "LICENSE_REVIEW_REQUIRED",
        "REDISTRIBUTION_NOT_APPROVED",
        "SOURCE_GOVERNANCE_OWNER_MISSING",
      ],
      responsibleRole: "datapack-source-owner",
      alertRoute: "github:area-datapack",
      escalationHours: 4,
    }],
    sources: [{
      sourceId: "source-a",
      sourceClassId: "static_network",
      retentionClassId: "standard-90d",
      ownerRole: "datapack-source-owner",
      stewardRole: "datapack-data-steward",
      approvalRole: "datapack-release-approver",
      escalationHours: 24,
      alertRoute: "github:area-datapack",
      licenseReview: {
        status: "APPROVED",
        termsHash: "e".repeat(64),
        reviewedAt: "2026-07-01T00:00:00Z",
        nextReviewAt: "2027-07-01T00:00:00Z",
        termsUrl: "https://example.invalid/source-a",
        reviewedProvider: "provider-a",
        reviewedDatasetUrl: "https://example.invalid/source-a",
        redistributionScopes: ["DERIVED_DATAPACK"],
        approvedByRole: "datapack-release-approver",
      },
    }],
  };
}

function freshnessPolicyFixture() {
  return {
    clockSkewSeconds: 0,
    sourceClasses: [{
      id: "static_network",
      sourceIds: ["source-a"],
      basisField: "retrievedAt",
      reverificationCadence: "P30D",
    }],
  };
}

function governanceInput() {
  return {
    source: source(),
    snapshot: {
      ...snapshot(),
      freshnessExpiresAt: "2026-07-31T00:00:00Z",
      rawRetentionExpiresAt: "2026-09-29T00:00:00.000Z",
      redistributionAllowed: true,
    },
    policy: governancePolicy(),
    freshnessPolicy: freshnessPolicyFixture(),
    evaluationAt: "2026-07-15T00:00:00Z",
  };
}

async function buildSnapshot(args) {
  await execFileAsync(process.execPath, [
    "tools/datapack/build-source-snapshot.mjs",
    ...args,
    "--source-id", "kric-station-elevator",
    "--provider", "국가철도공단",
    "--source-class-id", "static_accessibility_facility",
    "--governance-policy", "tools/datapack/source-governance-policy.json",
  ], { cwd: root });
}
