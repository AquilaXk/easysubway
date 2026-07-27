import assert from "node:assert/strict";
import test from "node:test";

import {
  assertInventoryMirrorByteParity,
  withRouteMapAdmissionFreshness,
} from "./refresh-route-map-admission-freshness.mjs";

const paths = ["canonical.json", "mobile.json"];
const inventory = JSON.stringify({
  sources: [{
    id: "route-map-source",
    routeMapAdmissionEvidence: { capturedAt: "2024-02-29T12:00:00.000Z" },
  }],
});

test("route-map freshness refresh는 mirror 불일치를 parse/write 전에 거부하고 정규화는 멱등이다", () => {
  assert.throws(() => assertInventoryMirrorByteParity([
    { bytes: Buffer.from(inventory) },
    { bytes: Buffer.from(`${inventory}\n`) },
  ]), /source inventory mirrors must be byte-identical before refresh/);
  assert.doesNotThrow(() => assertInventoryMirrorByteParity(paths.map(() => ({ bytes: Buffer.from(inventory) }))));

  const normalized = withRouteMapAdmissionFreshness(JSON.parse(inventory));
  assert.deepEqual(withRouteMapAdmissionFreshness(normalized), normalized);
  assert.equal(normalized.sources[0].routeMapAdmissionEvidence.freshUntil, "2025-03-01T12:00:00.000Z");
});
