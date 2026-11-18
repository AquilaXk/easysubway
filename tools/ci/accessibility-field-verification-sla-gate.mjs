#!/usr/bin/env node
import { createHash } from "node:crypto";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";

const SHA256_HEX_REGEX = /^[a-f0-9]{64}$/;
const SEMVER_CORE_REGEX = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const DATAPACK_VERSION_REGEX = /^[A-Za-z0-9][A-Za-z0-9._-]{1,63}$/;
const IDENTIFIER_REGEX = /^[A-Za-z0-9][A-Za-z0-9:._-]{1,127}$/;

const MAX_OBSERVATION_RECORDS = 256;
const MAX_MISMATCH_FINDINGS = 256;
const MAX_CONTAINMENT_HOURS = 24;
const MAX_RESOLUTION_HOURS = 72;

export const MOBILITY_COHORT_IDS = Object.freeze([
  "WHEELCHAIR",
  "STROLLER",
  "WALKING_AID",
  "OLDER_ADULT",
  "VISION_WAYFINDING",
]);
const MOBILITY_COHORT_SET = new Set(MOBILITY_COHORT_IDS);

export const CLAIM_RECONCILIATION_OUTCOMES = Object.freeze([
  "SUPPORTED",
  "LIMITED_WITH_DISCLOSURE",
  "CORRECTION_REQUIRED",
  "REMOVE_CLAIM",
  "RESEARCH_ONLY",
]);
const CLAIM_RECONCILIATION_OUTCOME_SET = new Set(CLAIM_RECONCILIATION_OUTCOMES);

export const MISMATCH_CATEGORIES = Object.freeze([
  "ELEVATOR_OUTAGE_UNREFLECTED",
  "STEP_OR_RAMP_BARRIER_MISMATCH",
  "TRANSFER_CORRIDOR_CLOSED_OR_BLOCKED",
  "WHEELCHAIR_LIFT_UNSAFE_OR_UNSTAFFED",
  "TACTILE_OR_AUDIO_WAYFINDING_BROKEN",
  "SIGNAGE_OR_EXIT_NUMBER_MISMATCH",
]);
const MISMATCH_CATEGORY_SET = new Set(MISMATCH_CATEGORIES);

const FORBIDDEN_PARTICIPANT_PII_KEYS = new Set([
  "participantname",
  "participantemail",
  "participantphone",
  "rawfacevideo",
  "rawvoiceaudio",
  "nationalid",
  "homeaddress",
]);

export class AccessibilityFieldVerificationError extends Error {
  constructor(code, message, details = null) {
    super(`${code}: ${message}`);
    this.name = "AccessibilityFieldVerificationError";
    this.code = code;
    this.details = details;
  }
}

function deepFreeze(value) {
  if (!value || typeof value !== "object" || Object.isFrozen(value)) {
    return value;
  }
  for (const key of Object.keys(value)) {
    deepFreeze(value[key]);
  }
  return Object.freeze(value);
}

export const ACCESSIBILITY_FIELD_SLA_POLICY = deepFreeze({
  schemaVersion: 1,
  policyId: "easysubway-accessibility-field-verification-and-sla-policy",
  requiredCohorts: MOBILITY_COHORT_IDS,
  claimOutcomes: CLAIM_RECONCILIATION_OUTCOMES,
  mismatchCategories: MISMATCH_CATEGORIES,
  maxContainmentHours: MAX_CONTAINMENT_HOURS,
  maxResolutionHours: MAX_RESOLUTION_HOURS,
  requireFieldRevalidationBeforeClose: true,
  participantProtocol: {
    requireVoluntaryInformedConsent: true,
    requireFairCompensationOrVoluntaryAck: true,
    requireDeidentifiedObservationRecords: true,
    forbidRawFaceVoiceOrBiometricMedia: true,
  },
});

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const keys = Object.keys(value).sort(codepointCompare);
    return `{${keys.map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function sha256Canonical(value) {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

function normalizeKey(key) {
  return key.toLowerCase().replace(/[^a-z0-9]/g, "");
}

export function validateAccessibilityFieldSlaPolicy(policy = ACCESSIBILITY_FIELD_SLA_POLICY) {
  if (!policy || typeof policy !== "object" || Array.isArray(policy)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_POLICY_INVALID",
      "Accessibility field SLA policy must be a non-null object",
    );
  }

  if (
    !Array.isArray(policy.requiredCohorts) ||
    policy.requiredCohorts.length !== MOBILITY_COHORT_IDS.length ||
    !policy.requiredCohorts.every((cohort) => MOBILITY_COHORT_SET.has(cohort))
  ) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_POLICY_INVALID",
      "Policy must declare all 5 canonical mobility cohorts",
    );
  }

  if (
    !Array.isArray(policy.claimOutcomes) ||
    policy.claimOutcomes.length !== CLAIM_RECONCILIATION_OUTCOMES.length ||
    !policy.claimOutcomes.every((outcome) => CLAIM_RECONCILIATION_OUTCOME_SET.has(outcome))
  ) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_POLICY_INVALID",
      "Policy must declare all 5 canonical claim reconciliation outcomes",
    );
  }

  if (
    policy.maxContainmentHours !== MAX_CONTAINMENT_HOURS ||
    policy.maxResolutionHours !== MAX_RESOLUTION_HOURS ||
    policy.requireFieldRevalidationBeforeClose !== true ||
    policy.participantProtocol?.requireVoluntaryInformedConsent !== true ||
    policy.participantProtocol?.requireFairCompensationOrVoluntaryAck !== true ||
    policy.participantProtocol?.requireDeidentifiedObservationRecords !== true ||
    policy.participantProtocol?.forbidRawFaceVoiceOrBiometricMedia !== true
  ) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_POLICY_INVALID",
      "Policy SLA thresholds or participant ethics protocol invariants are invalid",
    );
  }

  return {
    valid: true,
    policySha256: sha256Canonical(policy),
  };
}

export function classifyClaimFromFieldFinding(finding) {
  if (!finding || typeof finding !== "object") {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_FINDING",
      "Finding must be a non-null object",
    );
  }

  if (finding.findingType === "FIELD_MATCH_CONFIRMED") {
    return "SUPPORTED";
  }

  if (finding.findingType !== "APP_VS_FIELD_MISMATCH") {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_FINDING",
      `Unsupported findingType '${String(finding.findingType)}'`,
    );
  }

  if (finding.fieldRevalidated === true && finding.status === "CLOSED") {
    return "SUPPORTED";
  }

  if (finding.severity === "EXPLORATORY_OBSERVATION") {
    return "RESEARCH_ONLY";
  }

  if (finding.severity === "MODERATE_DISCLOSURE_GAP") {
    return "LIMITED_WITH_DISCLOSURE";
  }

  if (finding.severity === "MAJOR_ROUTING_MISMATCH") {
    return "CORRECTION_REQUIRED";
  }

  if (finding.severity === "CRITICAL_SAFETY_BARRIER") {
    return finding.unmitigableStructuralBarrier === true
      ? "REMOVE_CLAIM"
      : "CORRECTION_REQUIRED";
  }

  throw new AccessibilityFieldVerificationError(
    "E_A11Y_INVALID_FINDING",
    `Unrecognized mismatch severity '${String(finding.severity)}'`,
  );
}

function validateParticipantProtocol(protocol) {
  if (
    !protocol ||
    typeof protocol !== "object" ||
    protocol.voluntaryInformedConsentVerified !== true ||
    protocol.compensationTermsDisclosedAndHonored !== true ||
    protocol.deidentifiedRecordsOnly !== true ||
    protocol.containsRawPiiOrBiometricMedia !== false
  ) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_PARTICIPANT_PROTOCOL_VIOLATION",
      "Field campaign must verify voluntary consent, fair compensation disclosure, de-identification, and zero raw biometric media",
    );
  }
}

function validateObservationRecord(obs, evaluatedMs) {
  if (!obs || typeof obs !== "object" || Array.isArray(obs)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_OBSERVATION",
      "Each observation record must be an object",
    );
  }

  for (const key of Object.keys(obs)) {
    if (FORBIDDEN_PARTICIPANT_PII_KEYS.has(normalizeKey(key))) {
      throw new AccessibilityFieldVerificationError(
        "E_A11Y_PARTICIPANT_PROTOCOL_VIOLATION",
        `Observation record contains forbidden participant PII key '${key}'`,
      );
    }
  }

  if (typeof obs.observationId !== "string" || !IDENTIFIER_REGEX.test(obs.observationId)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_OBSERVATION",
      `Invalid observationId '${String(obs.observationId)}'`,
    );
  }

  if (typeof obs.cohort !== "string" || !MOBILITY_COHORT_SET.has(obs.cohort)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_COHORT",
      `Observation '${obs.observationId}' has unsupported mobility cohort '${String(obs.cohort)}'`,
    );
  }

  if (typeof obs.stationOrCorridorId !== "string" || !IDENTIFIER_REGEX.test(obs.stationOrCorridorId)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_OBSERVATION",
      `Observation '${obs.observationId}' must bind a valid stationOrCorridorId`,
    );
  }

  if (
    typeof obs.appVersion !== "string" ||
    !SEMVER_CORE_REGEX.test(obs.appVersion) ||
    typeof obs.datapackVersion !== "string" ||
    !DATAPACK_VERSION_REGEX.test(obs.datapackVersion) ||
    typeof obs.serverRouteBundleDigest !== "string" ||
    !SHA256_HEX_REGEX.test(obs.serverRouteBundleDigest) ||
    typeof obs.mapCatalogDigest !== "string" ||
    !SHA256_HEX_REGEX.test(obs.mapCatalogDigest)
  ) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_ARTIFACT_BINDING_INVALID",
      `Observation '${obs.observationId}' must bind exact appVersion, datapackVersion, serverRouteBundleDigest, and mapCatalogDigest`,
    );
  }

  const startMs = Date.parse(obs.observedWindowStart ?? "");
  const endMs = Date.parse(obs.observedWindowEnd ?? "");
  if (
    Number.isNaN(startMs) ||
    Number.isNaN(endMs) ||
    startMs > endMs ||
    endMs > evaluatedMs
  ) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_OBSERVATION_WINDOW_INVALID",
      `Observation '${obs.observationId}' has an invalid or future observation time window`,
    );
  }

  return {
    observationId: obs.observationId,
    cohort: obs.cohort,
    stationOrCorridorId: obs.stationOrCorridorId,
    appVersion: obs.appVersion,
    datapackVersion: obs.datapackVersion,
    serverRouteBundleDigest: obs.serverRouteBundleDigest,
    mapCatalogDigest: obs.mapCatalogDigest,
    observedWindowStart: obs.observedWindowStart,
    observedWindowEnd: obs.observedWindowEnd,
    endMs,
  };
}

function validateMismatchFinding(finding, observationsById, policy) {
  if (!finding || typeof finding !== "object" || Array.isArray(finding)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_FINDING",
      "Each finding entry must be an object",
    );
  }

  if (typeof finding.findingId !== "string" || !IDENTIFIER_REGEX.test(finding.findingId)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_FINDING",
      `Invalid findingId '${String(finding.findingId)}'`,
    );
  }

  const sourceObs = observationsById.get(finding.observationId);
  if (!sourceObs) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_UNKNOWN_OBSERVATION_REF",
      `Finding '${finding.findingId}' references unknown observationId '${String(finding.observationId)}'`,
    );
  }

  if (finding.findingType !== "APP_VS_FIELD_MISMATCH") {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_FINDING",
      `Finding '${finding.findingId}' must have findingType 'APP_VS_FIELD_MISMATCH'`,
    );
  }

  if (!MISMATCH_CATEGORY_SET.has(finding.mismatchCategory)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_FINDING",
      `Finding '${finding.findingId}' has unsupported mismatchCategory '${String(finding.mismatchCategory)}'`,
    );
  }

  if (typeof finding.affectedClaimId !== "string" || finding.affectedClaimId.trim().length === 0) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_FINDING",
      `Finding '${finding.findingId}' must specify affectedClaimId`,
    );
  }

  if (!CLAIM_RECONCILIATION_OUTCOME_SET.has(finding.reconciledClaimStatus)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_FINDING",
      `Finding '${finding.findingId}' has invalid reconciledClaimStatus '${String(finding.reconciledClaimStatus)}'`,
    );
  }

  if (
    typeof finding.containmentHours !== "number" ||
    !Number.isFinite(finding.containmentHours) ||
    finding.containmentHours < 0 ||
    finding.containmentHours > policy.maxContainmentHours
  ) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_CONTAINMENT_SLA_BREACHED",
      `Finding '${finding.findingId}' containmentHours (${String(finding.containmentHours)}) exceeded ${policy.maxContainmentHours}h SLA`,
    );
  }

  if (
    typeof finding.resolutionHours !== "number" ||
    !Number.isFinite(finding.resolutionHours) ||
    finding.resolutionHours < 0 ||
    finding.resolutionHours > policy.maxResolutionHours
  ) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_RESOLUTION_SLA_BREACHED",
      `Finding '${finding.findingId}' resolutionHours (${String(finding.resolutionHours)}) exceeded ${policy.maxResolutionHours}h SLA`,
    );
  }

  const isClosed = finding.status === "CLOSED";
  if (isClosed) {
    if (finding.fieldRevalidated !== true || typeof finding.revalidatedObservationId !== "string") {
      throw new AccessibilityFieldVerificationError(
        "E_A11Y_CLOSED_WITHOUT_FIELD_REVALIDATION",
        `Finding '${finding.findingId}' cannot be closed without fieldRevalidated=true and a bound revalidatedObservationId`,
      );
    }
    const revalObs = observationsById.get(finding.revalidatedObservationId);
    if (
      !revalObs ||
      revalObs.observationId === sourceObs.observationId ||
      revalObs.cohort !== sourceObs.cohort ||
      revalObs.stationOrCorridorId !== sourceObs.stationOrCorridorId ||
      revalObs.endMs < sourceObs.endMs
    ) {
      throw new AccessibilityFieldVerificationError(
        "E_A11Y_CLOSED_WITHOUT_FIELD_REVALIDATION",
        `Finding '${finding.findingId}' revalidatedObservationId '${finding.revalidatedObservationId}' does not match cohort/corridor or is not newer than original observation`,
      );
    }
  } else {
    if (finding.reconciledClaimStatus === "SUPPORTED") {
      throw new AccessibilityFieldVerificationError(
        "E_A11Y_UNSAFE_SUPPORTED_CLAIM_ON_MISMATCH",
        `Finding '${finding.findingId}' is not closed/revalidated and cannot keep claim '${finding.affectedClaimId}' as SUPPORTED`,
      );
    }
  }

  return {
    findingId: finding.findingId,
    observationId: finding.observationId,
    cohort: sourceObs.cohort,
    stationOrCorridorId: sourceObs.stationOrCorridorId,
    mismatchCategory: finding.mismatchCategory,
    affectedClaimId: finding.affectedClaimId,
    severity: finding.severity,
    status: finding.status,
    reconciledClaimStatus: finding.reconciledClaimStatus,
    containmentHours: finding.containmentHours,
    resolutionHours: finding.resolutionHours,
    fieldRevalidated: Boolean(finding.fieldRevalidated),
    revalidatedObservationId: finding.revalidatedObservationId ?? null,
  };
}

export function evaluateAccessibilityFieldVerificationCampaign(
  campaign,
  policy = ACCESSIBILITY_FIELD_SLA_POLICY,
) {
  const policyValidation = validateAccessibilityFieldSlaPolicy(policy);

  if (!campaign || typeof campaign !== "object" || Array.isArray(campaign)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_CAMPAIGN",
      "Campaign input must be a non-null object",
    );
  }

  if (typeof campaign.campaignId !== "string" || !IDENTIFIER_REGEX.test(campaign.campaignId)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_CAMPAIGN",
      "campaignId must be a valid non-empty identifier",
    );
  }

  const evaluatedMs = Date.parse(campaign.evaluatedAt ?? "");
  if (Number.isNaN(evaluatedMs)) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_CAMPAIGN",
      "evaluatedAt must be a valid ISO-8601 timestamp",
    );
  }

  validateParticipantProtocol(campaign.participantProtocol);

  if (!Array.isArray(campaign.observations) || campaign.observations.length === 0) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_INVALID_CAMPAIGN",
      "observations must be a non-empty array",
    );
  }

  if (campaign.observations.length > MAX_OBSERVATION_RECORDS) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_FIELD_BUDGET_EXCEEDED",
      `observations length (${campaign.observations.length}) exceeds maximum budget (${MAX_OBSERVATION_RECORDS})`,
    );
  }

  const findingsInput = campaign.findings ?? [];
  if (!Array.isArray(findingsInput) || findingsInput.length > MAX_MISMATCH_FINDINGS) {
    throw new AccessibilityFieldVerificationError(
      "E_A11Y_FIELD_BUDGET_EXCEEDED",
      `findings must be an array within maximum budget (${MAX_MISMATCH_FINDINGS})`,
    );
  }

  const observationsById = new Map();
  const coveredCohortsSet = new Set();
  const normalizedObservations = [];

  for (const rawObs of campaign.observations) {
    const normalizedObs = validateObservationRecord(rawObs, evaluatedMs);
    if (observationsById.has(normalizedObs.observationId)) {
      throw new AccessibilityFieldVerificationError(
        "E_A11Y_DUPLICATE_OBSERVATION",
        `Duplicate observationId '${normalizedObs.observationId}'`,
      );
    }
    observationsById.set(normalizedObs.observationId, normalizedObs);
    coveredCohortsSet.add(normalizedObs.cohort);
    normalizedObservations.push({
      observationId: normalizedObs.observationId,
      cohort: normalizedObs.cohort,
      stationOrCorridorId: normalizedObs.stationOrCorridorId,
      appVersion: normalizedObs.appVersion,
      datapackVersion: normalizedObs.datapackVersion,
      serverRouteBundleDigest: normalizedObs.serverRouteBundleDigest,
      mapCatalogDigest: normalizedObs.mapCatalogDigest,
      observedWindowStart: normalizedObs.observedWindowStart,
      observedWindowEnd: normalizedObs.observedWindowEnd,
    });
  }

  if (campaign.requireAllCohortsCovered !== false) {
    for (const requiredCohort of policy.requiredCohorts) {
      if (!coveredCohortsSet.has(requiredCohort)) {
        throw new AccessibilityFieldVerificationError(
          "E_A11Y_MISSING_COHORT_COVERAGE",
          `Field verification campaign is missing required mobility cohort '${requiredCohort}'`,
        );
      }
    }
  }

  const seenFindingIds = new Set();
  const normalizedFindings = [];

  for (const rawFinding of findingsInput) {
    const normalizedFinding = validateMismatchFinding(rawFinding, observationsById, policy);
    if (seenFindingIds.has(normalizedFinding.findingId)) {
      throw new AccessibilityFieldVerificationError(
        "E_A11Y_DUPLICATE_FINDING",
        `Duplicate findingId '${normalizedFinding.findingId}'`,
      );
    }
    seenFindingIds.add(normalizedFinding.findingId);
    normalizedFindings.push(normalizedFinding);
  }

  normalizedObservations.sort((left, right) =>
    codepointCompare(left.observationId, right.observationId),
  );
  normalizedFindings.sort((left, right) =>
    codepointCompare(left.findingId, right.findingId),
  );
  const coveredCohorts = [...coveredCohortsSet].sort(codepointCompare);

  const summaryPayload = {
    schemaVersion: 1,
    artifactKind: "accessibility-field-verification-campaign-summary",
    campaignId: campaign.campaignId,
    evaluatedAt: campaign.evaluatedAt,
    policySha256: policyValidation.policySha256,
    slaCompliant: true,
    coveredCohorts,
    observationCount: normalizedObservations.length,
    mismatchCount: normalizedFindings.length,
    observations: normalizedObservations,
    findings: normalizedFindings,
  };

  return {
    valid: true,
    ...summaryPayload,
    evaluationSha256: sha256Canonical(summaryPayload),
  };
}

if (isMainModule(import.meta.url)) {
  const result = validateAccessibilityFieldSlaPolicy(ACCESSIBILITY_FIELD_SLA_POLICY);
  process.stdout.write(`accessibility-field-verification-sla-gate: OK ${result.policySha256}\n`);
}
