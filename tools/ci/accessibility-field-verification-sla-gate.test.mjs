import assert from "node:assert/strict";
import test from "node:test";

import {
  ACCESSIBILITY_FIELD_SLA_POLICY,
  AccessibilityFieldVerificationError,
  CLAIM_RECONCILIATION_OUTCOMES,
  MOBILITY_COHORT_IDS,
  classifyClaimFromFieldFinding,
  evaluateAccessibilityFieldVerificationCampaign,
  validateAccessibilityFieldSlaPolicy,
} from "./accessibility-field-verification-sla-gate.mjs";

const EVALUATED_AT = "2026-11-10T12:00:00.000Z";

function hex64(char) {
  return char.repeat(64);
}

function buildValidCampaign(overrides = {}) {
  const observations = [
    {
      observationId: "obs-wheelchair-01",
      cohort: "WHEELCHAIR",
      stationOrCorridorId: "corridor:sadang-line2-to-line4",
      appVersion: "1.2.0",
      datapackVersion: "2026.11.08.1",
      serverRouteBundleDigest: hex64("a"),
      mapCatalogDigest: hex64("b"),
      observedWindowStart: "2026-11-08T10:00:00.000Z",
      observedWindowEnd: "2026-11-08T10:45:00.000Z",
    },
    {
      observationId: "obs-stroller-01",
      cohort: "STROLLER",
      stationOrCorridorId: "corridor:sangnoksu-exit-1",
      appVersion: "1.2.0",
      datapackVersion: "2026.11.08.1",
      serverRouteBundleDigest: hex64("a"),
      mapCatalogDigest: hex64("b"),
      observedWindowStart: "2026-11-08T11:00:00.000Z",
      observedWindowEnd: "2026-11-08T11:30:00.000Z",
    },
    {
      observationId: "obs-walking-aid-01",
      cohort: "WALKING_AID",
      stationOrCorridorId: "corridor:sindorim-transfer-hall",
      appVersion: "1.2.0",
      datapackVersion: "2026.11.08.1",
      serverRouteBundleDigest: hex64("a"),
      mapCatalogDigest: hex64("b"),
      observedWindowStart: "2026-11-08T13:00:00.000Z",
      observedWindowEnd: "2026-11-08T13:40:00.000Z",
    },
    {
      observationId: "obs-older-adult-01",
      cohort: "OLDER_ADULT",
      stationOrCorridorId: "corridor:jongno3ga-line1-to-line3",
      appVersion: "1.2.0",
      datapackVersion: "2026.11.08.1",
      serverRouteBundleDigest: hex64("a"),
      mapCatalogDigest: hex64("b"),
      observedWindowStart: "2026-11-08T14:00:00.000Z",
      observedWindowEnd: "2026-11-08T14:50:00.000Z",
    },
    {
      observationId: "obs-vision-wayfinding-01",
      cohort: "VISION_WAYFINDING",
      stationOrCorridorId: "corridor:seoul-station-tactile-path",
      appVersion: "1.2.0",
      datapackVersion: "2026.11.08.1",
      serverRouteBundleDigest: hex64("a"),
      mapCatalogDigest: hex64("b"),
      observedWindowStart: "2026-11-08T15:00:00.000Z",
      observedWindowEnd: "2026-11-08T15:35:00.000Z",
    },
    {
      observationId: "obs-wheelchair-reval-02",
      cohort: "WHEELCHAIR",
      stationOrCorridorId: "corridor:sadang-line2-to-line4",
      appVersion: "1.2.1",
      datapackVersion: "2026.11.09.1",
      serverRouteBundleDigest: hex64("c"),
      mapCatalogDigest: hex64("d"),
      observedWindowStart: "2026-11-09T16:00:00.000Z",
      observedWindowEnd: "2026-11-09T16:30:00.000Z",
    },
  ];

  const findings = [
    {
      findingId: "finding-sadang-elevator-outage",
      observationId: "obs-wheelchair-01",
      findingType: "APP_VS_FIELD_MISMATCH",
      mismatchCategory: "ELEVATOR_OUTAGE_UNREFLECTED",
      affectedClaimId: "PRODUCT_CLAIM_ACCESSIBILITY_PILOT",
      severity: "CRITICAL_SAFETY_BARRIER",
      status: "CLOSED",
      reconciledClaimStatus: "SUPPORTED",
      containmentHours: 6,
      resolutionHours: 32,
      fieldRevalidated: true,
      revalidatedObservationId: "obs-wheelchair-reval-02",
    },
    {
      findingId: "finding-jongno3ga-ramp-slope",
      observationId: "obs-older-adult-01",
      findingType: "APP_VS_FIELD_MISMATCH",
      mismatchCategory: "STEP_OR_RAMP_BARRIER_MISMATCH",
      affectedClaimId: "PRODUCT_CLAIM_PRODUCT_PRINCIPLE",
      severity: "MODERATE_DISCLOSURE_GAP",
      status: "CONTAINED_OPEN",
      reconciledClaimStatus: "LIMITED_WITH_DISCLOSURE",
      containmentHours: 12,
      resolutionHours: 48,
      fieldRevalidated: false,
      revalidatedObservationId: null,
    },
  ];

  return {
    campaignId: "field-campaign-2026-11-seoul-metro",
    evaluatedAt: EVALUATED_AT,
    participantProtocol: {
      voluntaryInformedConsentVerified: true,
      compensationTermsDisclosedAndHonored: true,
      deidentifiedRecordsOnly: true,
      containsRawPiiOrBiometricMedia: false,
    },
    observations,
    findings,
    ...overrides,
  };
}

test("ACCESSIBILITY_FIELD_SLA_POLICY defines all 5 mobility cohorts, 5 claim outcomes, 24h containment SLA, and 72h resolution SLA", () => {
  const validation = validateAccessibilityFieldSlaPolicy(ACCESSIBILITY_FIELD_SLA_POLICY);
  assert.equal(validation.valid, true);
  assert.match(validation.policySha256, /^[a-f0-9]{64}$/);
  assert.deepEqual([...ACCESSIBILITY_FIELD_SLA_POLICY.requiredCohorts], [...MOBILITY_COHORT_IDS]);
  assert.deepEqual([...ACCESSIBILITY_FIELD_SLA_POLICY.claimOutcomes], [...CLAIM_RECONCILIATION_OUTCOMES]);
  assert.equal(ACCESSIBILITY_FIELD_SLA_POLICY.maxContainmentHours, 24);
  assert.equal(ACCESSIBILITY_FIELD_SLA_POLICY.maxResolutionHours, 72);
  assert.equal(ACCESSIBILITY_FIELD_SLA_POLICY.requireFieldRevalidationBeforeClose, true);
});

test("classifyClaimFromFieldFinding maps field observations deterministically across all 5 claim reconciliation outcomes", () => {
  assert.equal(
    classifyClaimFromFieldFinding({
      findingType: "FIELD_MATCH_CONFIRMED",
      severity: "NONE",
      fieldRevalidated: true,
    }),
    "SUPPORTED",
  );
  assert.equal(
    classifyClaimFromFieldFinding({
      findingType: "APP_VS_FIELD_MISMATCH",
      severity: "MODERATE_DISCLOSURE_GAP",
      fieldRevalidated: false,
    }),
    "LIMITED_WITH_DISCLOSURE",
  );
  assert.equal(
    classifyClaimFromFieldFinding({
      findingType: "APP_VS_FIELD_MISMATCH",
      severity: "MAJOR_ROUTING_MISMATCH",
      fieldRevalidated: false,
    }),
    "CORRECTION_REQUIRED",
  );
  assert.equal(
    classifyClaimFromFieldFinding({
      findingType: "APP_VS_FIELD_MISMATCH",
      severity: "CRITICAL_SAFETY_BARRIER",
      unmitigableStructuralBarrier: true,
      fieldRevalidated: false,
    }),
    "REMOVE_CLAIM",
  );
  assert.equal(
    classifyClaimFromFieldFinding({
      findingType: "APP_VS_FIELD_MISMATCH",
      severity: "EXPLORATORY_OBSERVATION",
      fieldRevalidated: false,
    }),
    "RESEARCH_ONLY",
  );
});

test("evaluateAccessibilityFieldVerificationCampaign verifies cohort coverage, artifact bindings, SLAs, and deterministic digest", () => {
  const campaignA = buildValidCampaign();
  const campaignB = buildValidCampaign({
    observations: [...campaignA.observations].reverse(),
    findings: [...campaignA.findings].reverse(),
  });

  const resultA = evaluateAccessibilityFieldVerificationCampaign(campaignA);
  const resultB = evaluateAccessibilityFieldVerificationCampaign(campaignB);

  assert.equal(resultA.valid, true);
  assert.equal(resultA.slaCompliant, true);
  assert.deepEqual(resultA.coveredCohorts, [...MOBILITY_COHORT_IDS].sort());
  assert.equal(resultA.evaluationSha256, resultB.evaluationSha256);
});

test("evaluateAccessibilityFieldVerificationCampaign rejects participant protocol violations or un-bound artifact digests", () => {
  const badProtocol = buildValidCampaign({
    participantProtocol: {
      voluntaryInformedConsentVerified: false,
      compensationTermsDisclosedAndHonored: true,
      deidentifiedRecordsOnly: true,
      containsRawPiiOrBiometricMedia: false,
    },
  });

  assert.throws(
    () => evaluateAccessibilityFieldVerificationCampaign(badProtocol),
    (err) =>
      err instanceof AccessibilityFieldVerificationError &&
      err.code === "E_A11Y_PARTICIPANT_PROTOCOL_VIOLATION",
  );

  const missingBundleDigest = buildValidCampaign();
  missingBundleDigest.observations[0] = {
    ...missingBundleDigest.observations[0],
    serverRouteBundleDigest: "invalid-digest",
  };

  assert.throws(
    () => evaluateAccessibilityFieldVerificationCampaign(missingBundleDigest),
    (err) =>
      err instanceof AccessibilityFieldVerificationError &&
      err.code === "E_A11Y_ARTIFACT_BINDING_INVALID",
  );
});

test("evaluateAccessibilityFieldVerificationCampaign rejects 24h containment breach, 72h resolution breach, or closing without field revalidation", () => {
  const containmentBreached = buildValidCampaign();
  containmentBreached.findings[0] = {
    ...containmentBreached.findings[0],
    containmentHours: 25,
  };

  assert.throws(
    () => evaluateAccessibilityFieldVerificationCampaign(containmentBreached),
    (err) =>
      err instanceof AccessibilityFieldVerificationError &&
      err.code === "E_A11Y_CONTAINMENT_SLA_BREACHED",
  );

  const resolutionBreached = buildValidCampaign();
  resolutionBreached.findings[0] = {
    ...resolutionBreached.findings[0],
    resolutionHours: 73,
  };

  assert.throws(
    () => evaluateAccessibilityFieldVerificationCampaign(resolutionBreached),
    (err) =>
      err instanceof AccessibilityFieldVerificationError &&
      err.code === "E_A11Y_RESOLUTION_SLA_BREACHED",
  );

  const closedWithoutRevalidation = buildValidCampaign();
  closedWithoutRevalidation.findings[0] = {
    ...closedWithoutRevalidation.findings[0],
    status: "CLOSED",
    fieldRevalidated: false,
    revalidatedObservationId: null,
  };

  assert.throws(
    () => evaluateAccessibilityFieldVerificationCampaign(closedWithoutRevalidation),
    (err) =>
      err instanceof AccessibilityFieldVerificationError &&
      err.code === "E_A11Y_CLOSED_WITHOUT_FIELD_REVALIDATION",
  );

  const unsafeSupportedOnOpenMismatch = buildValidCampaign();
  unsafeSupportedOnOpenMismatch.findings[1] = {
    ...unsafeSupportedOnOpenMismatch.findings[1],
    severity: "CRITICAL_SAFETY_BARRIER",
    status: "CONTAINED_OPEN",
    reconciledClaimStatus: "SUPPORTED",
  };

  assert.throws(
    () => evaluateAccessibilityFieldVerificationCampaign(unsafeSupportedOnOpenMismatch),
    (err) =>
      err instanceof AccessibilityFieldVerificationError &&
      err.code === "E_A11Y_UNSAFE_SUPPORTED_CLAIM_ON_MISMATCH",
  );
});
