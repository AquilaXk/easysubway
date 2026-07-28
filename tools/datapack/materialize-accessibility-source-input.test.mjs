import assert from "node:assert/strict";
import test from "node:test";
import { materializeAccessibilitySourceInput } from "./materialize-accessibility-source-input.mjs";

test("fresh KRIC codes와 Seoul status만 production source input으로 materialize한다", () => {
  const input = {
    sourceIds: [],
    stationMappings: [{ sourceId: "molit-urban-rail-full-route", sourceStationCode: "MOLIT-L-1", lineId: "line-1", stationId: "station-a" }],
    stationLineRows: [{ stationCode: "1", lineId: "line-1", stationNameKo: "가" }],
    routeEdges: [{ id: "edge-a", sourceId: "seoul-metro-accessibility", edgeType: "ENTRY", to: { sourceStationCode: "1" } }],
    supportedV1Scope: { includedStationIds: ["station-a"] },
    minimumProductionCoverage: { facilities: 3 },
    coverageEvidence: [{ sourceDomain: "accessibility_facilities", sourceIds: ["old"] }],
  };
  const kricSnapshot = {
    sourceId: "kric-station-convenience-standard", snapshotId: "kric-1", observedAt: "2026-07-28T00:00:00Z", capturedAt: "2026-07-28T00:00:00Z",
    queries: [{ stationId: "station-a", lineId: "line-1", railOprIsttCd: "S1", lnCd: "1", stinCd: "1", providerRecordHash: "a".repeat(64), rows: [{ gubun: "EV", stinFlor: 1, dtlLoc: "대합실" }, { gubun: "ELEC", stinFlor: 1, dtlLoc: "충전" }] }],
  };
  const seoulSnapshot = {
    sourceId: "seoul-metro-accessibility", snapshotId: "seoul-1", observedAt: "2026-07-28T00:00:00Z", capturedAt: "2026-07-28T00:00:00Z",
    stations: [{ stationName: "가", lineName: "1호선", facilities: [{ operational: true }] }],
  };

  const output = materializeAccessibilitySourceInput({ input, kricSnapshot, seoulSnapshot });

  assert.deepEqual(output.facilityRows.map(({ type }) => type), ["ELEVATOR"]);
  assert.deepEqual(output.accessibilityStatusEvidence.map(({ facilityType, evidenceKind }) => [facilityType, evidenceKind]), [
    ["ESCALATOR", "NOT_EXISTS"], ["WHEELCHAIR_LIFT", "NOT_EXISTS"], ["ACCESSIBILITY_STATUS_PROBE", "EXISTS"],
  ]);
  assert.equal(output.accessibilityStatusEvidence.at(-1).operationalStatus, "AVAILABLE");
  assert.deepEqual(output.accessibilityStatusEvidence.map(({ strictRouteEligibleReason }) => strictRouteEligibleReason), [
    "FACILITY_NOT_INSTALLED", "FACILITY_NOT_INSTALLED", "OPERATION_STATUS_NOT_AVAILABLE",
  ]);
  assert.equal(output.routeEdges[0].accessibilityStatus, "UNKNOWN");
  assert.equal(output.routeEdges[0].verificationStatus, "NOT_VERIFIED");
});
