import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import {
  assertRouteMapAdmissionFreshness,
  CURRENT_ROUTE_MAP_REVERIFICATION_CADENCE,
  HISTORICAL_ROUTE_MAP_REVERIFICATION_CADENCE,
  routeMapReverificationCadence,
} from "./route-map-admission-freshness.mjs";

const root = path.resolve(import.meta.dirname, "../../..");
const currentSourceId = "seoul-metro-route-map-positions";
const currentEvidence = {
  capturedAt: "2024-02-29T12:00:00.000Z",
  freshUntil: "2024-05-29T12:00:00.000Z",
};
const historicalSourceId = "seoulmetro-cyberstation-route-map";
const historicalEvidence = {
  capturedAt: "2024-02-29T12:00:00.000Z",
  freshUntil: "2025-03-01T12:00:00.000Z",
};

test("route-map admission은 active P90D와 historical P1Y selector를 구분한다", async () => {
  const policy = JSON.parse(await readFile(
    path.join(root, "release/product-gates/datapack-freshness-sla.json"),
    "utf8",
  ));
  assert.equal(
    policy.sourceClasses.find(({ id }) => id === "route_map_positions")?.reverificationCadence,
    CURRENT_ROUTE_MAP_REVERIFICATION_CADENCE,
  );
  assert.equal(
    policy.sourceClasses.find(({ id }) => id === "route_map_asset_historical")?.reverificationCadence,
    HISTORICAL_ROUTE_MAP_REVERIFICATION_CADENCE,
  );
  assert.equal(routeMapReverificationCadence(currentSourceId), CURRENT_ROUTE_MAP_REVERIFICATION_CADENCE);
  assert.equal(routeMapReverificationCadence(historicalSourceId), HISTORICAL_ROUTE_MAP_REVERIFICATION_CADENCE);
  assert.doesNotThrow(() => assertRouteMapAdmissionFreshness(
    currentEvidence, new Date(currentEvidence.capturedAt), currentSourceId,
  ));
  assert.doesNotThrow(() => assertRouteMapAdmissionFreshness(
    historicalEvidence, new Date(historicalEvidence.capturedAt), historicalSourceId,
  ));
  for (const invalidEvidence of [
    { ...currentEvidence, freshUntil: "2024-05-28T12:00:00.000Z" },
    { ...currentEvidence, freshUntil: "invalid" },
    { capturedAt: currentEvidence.capturedAt },
  ]) {
    assert.throws(() => assertRouteMapAdmissionFreshness(
      invalidEvidence, new Date(currentEvidence.capturedAt), currentSourceId,
    ));
  }
  assert.throws(() => assertRouteMapAdmissionFreshness(
    currentEvidence, new Date("2024-02-29T11:59:59.999Z"), currentSourceId,
  ));
  assert.throws(() => assertRouteMapAdmissionFreshness(
    currentEvidence, new Date(currentEvidence.freshUntil), currentSourceId,
  ));
});
