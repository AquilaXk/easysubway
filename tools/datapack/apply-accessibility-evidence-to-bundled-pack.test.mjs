import assert from "node:assert/strict";
import test from "node:test";

import { accessibilityIndexMetadata } from "./apply-accessibility-evidence-to-bundled-pack.mjs";

test("metadata requires admission for facilities-only sources and uses the build clock hook", (t) => {
  const previousBuildNow = process.env.EASYSUBWAY_DATAPACK_BUILD_NOW;
  process.env.EASYSUBWAY_DATAPACK_BUILD_NOW = "2026-07-28T16:00:00.000Z";
  t.after(() => {
    if (previousBuildNow === undefined) delete process.env.EASYSUBWAY_DATAPACK_BUILD_NOW;
    else process.env.EASYSUBWAY_DATAPACK_BUILD_NOW = previousBuildNow;
  });
  const pack = {
    facilities: [{ sourceId: "facility-source", sourceSnapshotId: "facility-snapshot" }],
    stationFacilityEvidence: [{ sourceId: "status-source", sourceSnapshotId: "status-snapshot" }],
  };
  const spec = { sourceSnapshotSetHash: "a".repeat(64), sourceSnapshots: [
    { sourceId: "facility-source", snapshotId: "facility-snapshot", freshnessExpiresAt: "2026-08-10T00:00:00.000Z" },
    { sourceId: "status-source", snapshotId: "status-snapshot", freshnessExpiresAt: "2026-08-09T00:00:00.000Z" },
  ] };
  const inventory = { sources: [
    { id: "facility-source", accessibilityAdmissionEvidence: { snapshotId: "facility-snapshot", observedAt: "2026-07-28T14:00:00.000Z", freshUntil: "2026-07-29T14:00:00.000Z" } },
    { id: "status-source", accessibilityAdmissionEvidence: { snapshotId: "status-snapshot", observedAt: "2026-07-28T15:00:00.000Z", freshUntil: "2026-07-29T15:00:00.000Z" } },
  ] };

  assert.deepEqual(accessibilityIndexMetadata(pack, spec, inventory, "2026-08-08T00:00:00.000Z"), {
    builtAt: "2026-07-28T16:00:00.000Z",
    qualityAsOf: "2026-07-28T15:00:00.000Z",
    freshnessExpiresAt: "2026-08-08T00:00:00.000Z",
    sourceSnapshotSetHash: "a".repeat(64),
  });
});

test("metadata fails closed when a consumed source lacks admission evidence", () => {
  assert.throws(() => accessibilityIndexMetadata(
    { facilities: [{ sourceId: "missing", sourceSnapshotId: "snapshot" }], stationFacilityEvidence: [] },
    { sourceSnapshotSetHash: "a".repeat(64), sourceSnapshots: [{ sourceId: "missing", snapshotId: "snapshot", freshnessExpiresAt: "2026-08-01T00:00:00.000Z" }] },
    { sources: [] },
    "2026-08-01T00:00:00.000Z",
  ), /accessibility admission evidence missing: missing/);
});
