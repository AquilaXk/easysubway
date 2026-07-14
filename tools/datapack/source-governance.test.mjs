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
      "--raw-retention-expires-at", "2026-09-30T03:00:00Z",
      "--coverage-count", "1",
      "--raw-object-uri", "s3://bucket/snapshot-a-1.csv",
    ]);
    await buildSnapshot([
      "--input", secondRaw,
      "--output", secondOutput,
      "--snapshot-id", "snapshot-a-2",
      "--retrieved-at", "2026-07-01T03:00:00Z",
      "--freshness-expires-at", "2026-09-29T03:00:00Z",
      "--raw-retention-expires-at", "2026-10-01T03:00:00Z",
      "--coverage-count", "2",
      "--raw-object-uri", "s3://bucket/snapshot-a-2.csv",
      "--previous-snapshot", firstOutput,
    ]);

    const produced = JSON.parse(await readFile(secondOutput, "utf8"));
    assert.equal(produced.previousSnapshotId, "snapshot-a-1");
    assert.equal(produced.diffSummary.status, "CHANGED");
    assert.equal(produced.diffSummary.rowDelta, 1);
    assert.equal(produced.diffSummary.coverageDelta, 1);
  } finally {
    await rm(workDir, { recursive: true, force: true });
  }
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

async function buildSnapshot(args) {
  await execFileAsync(process.execPath, [
    "tools/datapack/build-source-snapshot.mjs",
    ...args,
    "--source-id", "kric-station-elevator",
    "--provider", "국가철도공단",
    "--source-class-id", "static_accessibility_facility",
  ], { cwd: root });
}
