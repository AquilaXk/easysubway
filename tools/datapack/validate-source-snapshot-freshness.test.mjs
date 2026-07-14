import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import { validateSourceSnapshotFreshness } from "./validate-source-snapshot-freshness.mjs";

const evaluationAt = "2026-07-15T00:00:00.000Z";
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
    retrievedAt: "2026-07-12T00:00:00Z",
    freshnessExpiresAt: "2026-08-11T00:00:00Z",
    ...overrides,
  }];
  return {
    snapshots,
    buildSpec: {
      sourceSnapshotIds: ["snapshot-a"],
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
