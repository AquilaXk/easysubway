#!/usr/bin/env node
import { createHash } from "node:crypto";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";

const PROPOSAL_ID_REGEX = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const FIELD_NAME_REGEX = /^[A-Za-z][A-Za-z0-9_]{0,127}$/;

const MAX_PROPOSED_FIELDS = 64;
const MAX_STRING_LENGTH = 1024;
const MIN_K_ANONYMITY_CELL_SIZE = 50;
const MAX_RETENTION_DAYS = 30;

export const METRIC_CLASSIFICATIONS = Object.freeze([
  "NO_COLLECTION_PREFERRED",
  "LOCAL_AGGREGATE_ONLY",
  "SERVER_BOUNDED_AGGREGATE",
  "OPT_IN_FIELD_RESEARCH",
  "DISALLOWED",
]);
const METRIC_CLASSIFICATION_SET = new Set(METRIC_CLASSIFICATIONS);

export const FORBIDDEN_METRIC_FIELDS = Object.freeze([
  "originStationId",
  "destinationStationId",
  "originDestinationPair",
  "rawLat",
  "rawLng",
  "fineLocation",
  "coarseLocationTrace",
  "searchQueryText",
  "recentSearches",
  "favoritesList",
  "reportPhotoBytes",
  "reportPhotoExif",
  "freeTextReportBody",
  "requestId",
  "journeyId",
  "sessionId",
  "clientIp",
  "userAgent",
  "deviceId",
  "adId",
  "androidId",
  "installationId",
  "pushToken",
  "accountId",
  "email",
  "phoneNumber",
  "fileSystemPath",
  "preciseTimestampMs",
]);

function normalizeFieldIdentifier(name) {
  return name.toLowerCase().replace(/[^a-z0-9]/g, "");
}

const FORBIDDEN_FIELD_NORMALIZED_SET = new Set(
  FORBIDDEN_METRIC_FIELDS.map(normalizeFieldIdentifier),
);

const SIMPLE_IDENTIFIER_HASH_REGEX =
  /(?:^|_)(?:sha256|sha1|sha512|md5|blake2|murmur|fnv|hash|hashed)_?(?:device|ip|clientip|session|request|journey|ad|adid|androidid|installation|user|useragent|account|email|phone|origin|destination|stationpair|route|lat|lng|location)|(?:device|ip|clientip|session|request|journey|adid|useragent|account|email|phone|origin|destination)_?(?:hash|sha256|sha1|md5)$/i;

export class PrivacyOutcomeMetricsError extends Error {
  constructor(code, message, classification = "DISALLOWED", details = null) {
    super(`${code}: ${message}`);
    this.name = "PrivacyOutcomeMetricsError";
    this.code = code;
    this.classification = classification;
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

export const PRIVACY_OUTCOME_METRICS_POLICY = deepFreeze({
  schemaVersion: 1,
  policyId: "easysubway-privacy-preserving-outcome-metrics-policy",
  classifications: METRIC_CLASSIFICATIONS,
  forbiddenFields: FORBIDDEN_METRIC_FIELDS,
  forbidSimpleHashOfHighRiskIdentifiers: true,
  minKAnonymityCellSize: MIN_K_ANONYMITY_CELL_SIZE,
  maxRetentionDays: MAX_RETENTION_DAYS,
  requireZeroBufferingWhenDisabled: true,
  requireZeroLaterUploadWhenDeclined: true,
  requireStoreDataSafetyAlignment: true,
  forbidAutoPromoteProductClaim: true,
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

function isForbiddenOrHashedIdentifierField(fieldEntry) {
  let rawName = "";
  if (typeof fieldEntry === "string") {
    rawName = fieldEntry;
  } else if (fieldEntry && typeof fieldEntry === "object" && typeof fieldEntry.name === "string") {
    if (fieldEntry.isSimpleIdentifierHash === true) {
      return { forbidden: true, field: fieldEntry.name, reason: "SIMPLE_IDENTIFIER_HASH" };
    }
    if (
      typeof fieldEntry.sourceField === "string" &&
      FORBIDDEN_FIELD_NORMALIZED_SET.has(normalizeFieldIdentifier(fieldEntry.sourceField))
    ) {
      return { forbidden: true, field: fieldEntry.name, reason: "DERIVED_FROM_FORBIDDEN_FIELD" };
    }
    rawName = fieldEntry.name;
  } else {
    return { forbidden: true, field: String(fieldEntry), reason: "MALFORMED_FIELD_ENTRY" };
  }

  if (!FIELD_NAME_REGEX.test(rawName)) {
    return { forbidden: true, field: rawName, reason: "INVALID_FIELD_IDENTIFIER" };
  }

  const normalized = normalizeFieldIdentifier(rawName);
  if (FORBIDDEN_FIELD_NORMALIZED_SET.has(normalized)) {
    return { forbidden: true, field: rawName, reason: "FORBIDDEN_RAW_FIELD" };
  }

  if (SIMPLE_IDENTIFIER_HASH_REGEX.test(rawName) || SIMPLE_IDENTIFIER_HASH_REGEX.test(normalized)) {
    return { forbidden: true, field: rawName, reason: "SIMPLE_IDENTIFIER_HASH" };
  }

  return { forbidden: false, field: rawName, reason: null };
}

export function validatePrivacyOutcomeMetricsPolicy(policy = PRIVACY_OUTCOME_METRICS_POLICY) {
  if (!policy || typeof policy !== "object" || Array.isArray(policy)) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_POLICY_INVALID",
      "Privacy outcome metrics policy must be a non-null object",
    );
  }

  if (
    !Array.isArray(policy.classifications) ||
    policy.classifications.length !== METRIC_CLASSIFICATIONS.length ||
    !policy.classifications.every((item) => METRIC_CLASSIFICATION_SET.has(item))
  ) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_POLICY_INVALID",
      "Policy must declare all 5 canonical metric classifications",
    );
  }

  if (
    !Array.isArray(policy.forbiddenFields) ||
    policy.forbiddenFields.length < FORBIDDEN_METRIC_FIELDS.length
  ) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_POLICY_INVALID",
      "Policy must include all canonical forbidden metric fields",
    );
  }

  const policyForbiddenSet = new Set(policy.forbiddenFields);
  for (const requiredForbidden of FORBIDDEN_METRIC_FIELDS) {
    if (!policyForbiddenSet.has(requiredForbidden)) {
      throw new PrivacyOutcomeMetricsError(
        "E_PRIVACY_POLICY_INVALID",
        `Policy is missing required forbidden field '${requiredForbidden}'`,
      );
    }
  }

  if (
    !Number.isInteger(policy.minKAnonymityCellSize) ||
    policy.minKAnonymityCellSize < MIN_K_ANONYMITY_CELL_SIZE ||
    !Number.isInteger(policy.maxRetentionDays) ||
    policy.maxRetentionDays <= 0 ||
    policy.maxRetentionDays > MAX_RETENTION_DAYS ||
    policy.forbidSimpleHashOfHighRiskIdentifiers !== true ||
    policy.requireZeroBufferingWhenDisabled !== true ||
    policy.requireZeroLaterUploadWhenDeclined !== true ||
    policy.requireStoreDataSafetyAlignment !== true ||
    policy.forbidAutoPromoteProductClaim !== true
  ) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_POLICY_INVALID",
      "Policy thresholds violate minimum k-anonymity, retention, buffering, or claim safety rules",
    );
  }

  return {
    valid: true,
    policySha256: sha256Canonical(policy),
  };
}

export function evaluatePrivacyOutcomeMetricProposal(
  proposal,
  policy = PRIVACY_OUTCOME_METRICS_POLICY,
) {
  const policyValidation = validatePrivacyOutcomeMetricsPolicy(policy);

  if (!proposal || typeof proposal !== "object" || Array.isArray(proposal)) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_INVALID_PROPOSAL",
      "Metric proposal must be a non-null object",
    );
  }

  if (typeof proposal.proposalId !== "string" || !PROPOSAL_ID_REGEX.test(proposal.proposalId)) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_INVALID_PROPOSAL",
      "proposalId must be a valid non-empty identifier",
    );
  }

  if (
    typeof proposal.productQuestion !== "string" ||
    proposal.productQuestion.trim().length === 0 ||
    proposal.productQuestion.length > MAX_STRING_LENGTH
  ) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_MISSING_PRODUCT_QUESTION",
      "productQuestion must be a non-empty bounded string",
    );
  }

  const proposedFields = proposal.proposedFields ?? [];
  if (!Array.isArray(proposedFields)) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_INVALID_PROPOSAL",
      "proposedFields must be an array",
    );
  }

  if (proposedFields.length > MAX_PROPOSED_FIELDS) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_BUDGET_EXCEEDED",
      `proposedFields length (${proposedFields.length}) exceeds maximum budget (${MAX_PROPOSED_FIELDS})`,
    );
  }

  const normalizedFieldNames = [];
  const seenFields = new Set();

  for (const entry of proposedFields) {
    const check = isForbiddenOrHashedIdentifierField(entry);
    if (check.forbidden) {
      throw new PrivacyOutcomeMetricsError(
        "E_PRIVACY_FORBIDDEN_FIELD",
        `Forbidden or high-risk identifier field '${check.field}' (${check.reason}) is disallowed`,
        "DISALLOWED",
        { field: check.field, reason: check.reason },
      );
    }
    if (!seenFields.has(check.field)) {
      seenFields.add(check.field);
      normalizedFieldNames.push(check.field);
    }
  }

  if (
    proposal.crossSessionLinkable === true ||
    proposal.includesMobilityAidProfileWithRoute === true
  ) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_FORBIDDEN_FIELD",
      "Cross-session linking or combining mobility aid profile with route telemetry is disallowed",
      "DISALLOWED",
    );
  }

  if (proposal.nonCollectionAlternativeSufficient === true) {
    const noCollectionPayload = {
      schemaVersion: 1,
      proposalId: proposal.proposalId,
      classification: "NO_COLLECTION_PREFERRED",
      collectionAllowed: false,
      reasonCode: "NON_COLLECTION_ALTERNATIVE_SUFFICIENT",
      policySha256: policyValidation.policySha256,
    };
    return {
      ...noCollectionPayload,
      evaluatedSha256: sha256Canonical(noCollectionPayload),
    };
  }

  if (proposal.bufferingWhenDisabled !== false || proposal.laterUploadWhenDeclined !== false) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_DISABLED_BUFFERING_OR_UPLOAD_FORBIDDEN",
      "Local buffering while disabled or deferred upload after decline is strictly forbidden",
      "DISALLOWED",
    );
  }

  if (proposal.storeDataSafetyDeclarationAligned !== true) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_STORE_DATA_SAFETY_MISALIGNED",
      "Metric proposal must align with Google Play Data Safety and privacy policy declarations",
      "DISALLOWED",
    );
  }

  if (proposal.autoPromoteProductClaim !== false) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_AUTO_CLAIM_PROMOTION_FORBIDDEN",
      "Metrics must not automatically promote marketing or product claims without independent field/system evidence",
      "DISALLOWED",
    );
  }

  if (
    !Number.isInteger(proposal.minKAnonymityCellSize) ||
    proposal.minKAnonymityCellSize < policy.minKAnonymityCellSize
  ) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_K_ANONYMITY_TOO_SMALL",
      `minKAnonymityCellSize (${String(proposal.minKAnonymityCellSize)}) must be an integer >= ${policy.minKAnonymityCellSize}`,
      "DISALLOWED",
    );
  }

  if (
    !Number.isInteger(proposal.retentionDays) ||
    proposal.retentionDays <= 0 ||
    proposal.retentionDays > policy.maxRetentionDays
  ) {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_RETENTION_EXCEEDED",
      `retentionDays (${String(proposal.retentionDays)}) must be between 1 and ${policy.maxRetentionDays}`,
      "DISALLOWED",
    );
  }

  let classification = "DISALLOWED";
  if (proposal.collectionScope === "LOCAL_DEVICE_ONLY") {
    classification = "LOCAL_AGGREGATE_ONLY";
  } else if (proposal.collectionScope === "SERVER_AGGREGATE") {
    classification = "SERVER_BOUNDED_AGGREGATE";
  } else if (proposal.collectionScope === "OPT_IN_FIELD_STUDY") {
    if (
      proposal.explicitInformedConsent !== true ||
      proposal.participantRevocationSupported !== true
    ) {
      throw new PrivacyOutcomeMetricsError(
        "E_PRIVACY_CONSENT_REQUIRED",
        "OPT_IN_FIELD_STUDY requires explicitInformedConsent and participantRevocationSupported",
        "DISALLOWED",
      );
    }
    classification = "OPT_IN_FIELD_RESEARCH";
  } else {
    throw new PrivacyOutcomeMetricsError(
      "E_PRIVACY_DISALLOWED_COLLECTION_SCOPE",
      `Unsupported or disallowed collectionScope '${String(proposal.collectionScope)}'`,
      "DISALLOWED",
    );
  }

  normalizedFieldNames.sort(codepointCompare);

  const decisionPayload = {
    schemaVersion: 1,
    proposalId: proposal.proposalId,
    classification,
    collectionAllowed: true,
    approvedFields: normalizedFieldNames,
    minKAnonymityCellSize: proposal.minKAnonymityCellSize,
    retentionDays: proposal.retentionDays,
    bufferingWhenDisabled: false,
    laterUploadWhenDeclined: false,
    storeDataSafetyDeclarationAligned: true,
    autoPromoteProductClaim: false,
    policySha256: policyValidation.policySha256,
  };

  return {
    ...decisionPayload,
    evaluatedSha256: sha256Canonical(decisionPayload),
  };
}

if (isMainModule(import.meta.url)) {
  const result = validatePrivacyOutcomeMetricsPolicy(PRIVACY_OUTCOME_METRICS_POLICY);
  process.stdout.write(`privacy-outcome-metrics-policy-gate: OK ${result.policySha256}\n`);
}
