import assert from "node:assert/strict";
import test from "node:test";

import {
  FORBIDDEN_METRIC_FIELDS,
  METRIC_CLASSIFICATIONS,
  PRIVACY_OUTCOME_METRICS_POLICY,
  PrivacyOutcomeMetricsError,
  evaluatePrivacyOutcomeMetricProposal,
  validatePrivacyOutcomeMetricsPolicy,
} from "./privacy-outcome-metrics-policy-gate.mjs";

function buildValidServerAggregateProposal(overrides = {}) {
  return {
    proposalId: "metric-journey-step-free-success-bucket",
    productQuestion: "광역권 주간 무단차 경로 안내 완료 비율이 임계치 이하로 하락했는가?",
    nonCollectionAlternativeSufficient: false,
    collectionScope: "SERVER_AGGREGATE",
    proposedFields: ["regionCode", "isoWeekBucket", "stepFreeCompletionCountBucket"],
    bufferingWhenDisabled: false,
    laterUploadWhenDeclined: false,
    minKAnonymityCellSize: 64,
    retentionDays: 14,
    storeDataSafetyDeclarationAligned: true,
    autoPromoteProductClaim: false,
    crossSessionLinkable: false,
    includesMobilityAidProfileWithRoute: false,
    ...overrides,
  };
}

test("PRIVACY_OUTCOME_METRICS_POLICY defines all 5 classifications, k-anonymity >= 50, retention <= 30 days, and forbidden fields", () => {
  const validation = validatePrivacyOutcomeMetricsPolicy(PRIVACY_OUTCOME_METRICS_POLICY);
  assert.equal(validation.valid, true);
  assert.match(validation.policySha256, /^[a-f0-9]{64}$/);
  assert.deepEqual([...PRIVACY_OUTCOME_METRICS_POLICY.classifications], [...METRIC_CLASSIFICATIONS]);
  assert.equal(PRIVACY_OUTCOME_METRICS_POLICY.minKAnonymityCellSize, 50);
  assert.equal(PRIVACY_OUTCOME_METRICS_POLICY.maxRetentionDays, 30);
  assert.equal(FORBIDDEN_METRIC_FIELDS.includes("originStationId"), true);
  assert.equal(FORBIDDEN_METRIC_FIELDS.includes("destinationStationId"), true);
  assert.equal(FORBIDDEN_METRIC_FIELDS.includes("reportPhotoBytes"), true);
});

test("evaluatePrivacyOutcomeMetricProposal returns NO_COLLECTION_PREFERRED when a non-collection alternative suffices", () => {
  const decision = evaluatePrivacyOutcomeMetricProposal(
    buildValidServerAggregateProposal({
      proposalId: "metric-datapack-freshness-check",
      productQuestion: "공공 원천 데이터팩 갱신 주기가 SLA 이내인가?",
      nonCollectionAlternativeSufficient: true,
    }),
  );

  assert.equal(decision.classification, "NO_COLLECTION_PREFERRED");
  assert.equal(decision.collectionAllowed, false);
  assert.match(decision.evaluatedSha256, /^[a-f0-9]{64}$/);
});

test("evaluatePrivacyOutcomeMetricProposal deterministically classifies LOCAL_AGGREGATE_ONLY, SERVER_BOUNDED_AGGREGATE, and OPT_IN_FIELD_RESEARCH", () => {
  const localDecision = evaluatePrivacyOutcomeMetricProposal(
    buildValidServerAggregateProposal({
      proposalId: "metric-local-ui-font-scale",
      collectionScope: "LOCAL_DEVICE_ONLY",
      proposedFields: ["fontScaleBucket"],
    }),
  );
  assert.equal(localDecision.classification, "LOCAL_AGGREGATE_ONLY");
  assert.equal(localDecision.collectionAllowed, true);

  const serverDecision = evaluatePrivacyOutcomeMetricProposal(buildValidServerAggregateProposal());
  assert.equal(serverDecision.classification, "SERVER_BOUNDED_AGGREGATE");
  assert.equal(serverDecision.collectionAllowed, true);

  const researchDecision = evaluatePrivacyOutcomeMetricProposal(
    buildValidServerAggregateProposal({
      proposalId: "metric-opt-in-corridor-study",
      collectionScope: "OPT_IN_FIELD_STUDY",
      explicitInformedConsent: true,
      participantRevocationSupported: true,
      proposedFields: ["studyCorridorBucket", "observedBarrierCode"],
    }),
  );
  assert.equal(researchDecision.classification, "OPT_IN_FIELD_RESEARCH");
  assert.equal(researchDecision.collectionAllowed, true);
});

test("evaluatePrivacyOutcomeMetricProposal blocks forbidden fields and simple hashes of high-risk identifiers with E_PRIVACY_FORBIDDEN_FIELD", () => {
  const forbiddenSamples = [
    "originStationId",
    "destinationStationId",
    "rawLat",
    "rawLng",
    "searchQueryText",
    "reportPhotoBytes",
    "requestId",
    "journeyId",
    "sessionId",
    "clientIp",
    "userAgent",
    "deviceId",
    "adId",
    "fileSystemPath",
    "sha256_device_id",
    "hashedClientIp",
    "md5SessionId",
  ];

  for (const field of forbiddenSamples) {
    assert.throws(
      () =>
        evaluatePrivacyOutcomeMetricProposal(
          buildValidServerAggregateProposal({
            proposedFields: ["regionCode", field],
          }),
        ),
      (err) =>
        err instanceof PrivacyOutcomeMetricsError &&
        err.code === "E_PRIVACY_FORBIDDEN_FIELD" &&
        err.classification === "DISALLOWED",
    );
  }
});

test("evaluatePrivacyOutcomeMetricProposal enforces zero buffering when disabled, k >= 50, retention <= 30, Store Data Safety alignment, and no auto claim promotion", () => {
  assert.throws(
    () =>
      evaluatePrivacyOutcomeMetricProposal(
        buildValidServerAggregateProposal({
          bufferingWhenDisabled: true,
        }),
      ),
    (err) =>
      err instanceof PrivacyOutcomeMetricsError &&
      err.code === "E_PRIVACY_DISABLED_BUFFERING_OR_UPLOAD_FORBIDDEN",
  );

  assert.throws(
    () =>
      evaluatePrivacyOutcomeMetricProposal(
        buildValidServerAggregateProposal({
          laterUploadWhenDeclined: true,
        }),
      ),
    (err) =>
      err instanceof PrivacyOutcomeMetricsError &&
      err.code === "E_PRIVACY_DISABLED_BUFFERING_OR_UPLOAD_FORBIDDEN",
  );

  assert.throws(
    () =>
      evaluatePrivacyOutcomeMetricProposal(
        buildValidServerAggregateProposal({
          minKAnonymityCellSize: 49,
        }),
      ),
    (err) =>
      err instanceof PrivacyOutcomeMetricsError &&
      err.code === "E_PRIVACY_K_ANONYMITY_TOO_SMALL",
  );

  assert.throws(
    () =>
      evaluatePrivacyOutcomeMetricProposal(
        buildValidServerAggregateProposal({
          retentionDays: 31,
        }),
      ),
    (err) =>
      err instanceof PrivacyOutcomeMetricsError &&
      err.code === "E_PRIVACY_RETENTION_EXCEEDED",
  );

  assert.throws(
    () =>
      evaluatePrivacyOutcomeMetricProposal(
        buildValidServerAggregateProposal({
          storeDataSafetyDeclarationAligned: false,
        }),
      ),
    (err) =>
      err instanceof PrivacyOutcomeMetricsError &&
      err.code === "E_PRIVACY_STORE_DATA_SAFETY_MISALIGNED",
  );

  assert.throws(
    () =>
      evaluatePrivacyOutcomeMetricProposal(
        buildValidServerAggregateProposal({
          autoPromoteProductClaim: true,
        }),
      ),
    (err) =>
      err instanceof PrivacyOutcomeMetricsError &&
      err.code === "E_PRIVACY_AUTO_CLAIM_PROMOTION_FORBIDDEN",
  );
});

test("evaluatePrivacyOutcomeMetricProposal rejects oversized untrusted field lists Fail-Closed", () => {
  const oversizedFields = Array.from({ length: 80 }, (_, idx) => `safeBucketField_${idx}`);
  assert.throws(
    () =>
      evaluatePrivacyOutcomeMetricProposal(
        buildValidServerAggregateProposal({
          proposedFields: oversizedFields,
        }),
      ),
    (err) =>
      err instanceof PrivacyOutcomeMetricsError &&
      err.code === "E_PRIVACY_BUDGET_EXCEEDED",
  );
});
