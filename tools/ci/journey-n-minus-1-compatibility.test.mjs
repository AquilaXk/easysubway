import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  JOURNEY_V3_COMPATIBILITY_CONTRACT,
  JourneyCompatibilityError,
  classifyContractDelta,
  evaluateJourneyAndArtifactCompatibility,
  validateJourneyCompatibilityContract,
  validateRollbackTupleCompatibility,
} from "./journey-n-minus-1-compatibility.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../..");

test("JOURNEY_V3_COMPATIBILITY_CONTRACT pins exact current versions, digests, rollout order, and deprecation policy", () => {
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.apiContractVersion, "v3");
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.errorCatalogVersion, 1);
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.datapackIndexSchemaVersion, 1);
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.datapackManifestSchemaVersion, 1);
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.serverRouteBundleSchemaVersion, 1);
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.mapCatalogSchemaVersion, 1);
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.mobileAppVersionRange, ">=1.0.0");
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.platformReleaseTupleSchemaVersion, 1);
  assert.deepEqual(JOURNEY_V3_COMPATIBILITY_CONTRACT.allowedSigningKeyIds, ["production-v1"]);
  assert.deepEqual(JOURNEY_V3_COMPATIBILITY_CONTRACT.rolloutOrder, [
    "PRODUCER_FIRST_FOR_ADDITIVE",
    "DUAL_WINDOW_N_AND_N_MINUS_1",
    "CONSUMER_MINIMUM_BUMP_BEFORE_BREAKING_RETIREMENT",
  ]);
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.deprecationLifecycle.minDeprecationNoticeDays, 30);
  assert.equal(JOURNEY_V3_COMPATIBILITY_CONTRACT.deprecationLifecycle.retiredAdapterReachabilityCount, 0);

  const validation = validateJourneyCompatibilityContract(JOURNEY_V3_COMPATIBILITY_CONTRACT, {
    repoRoot: REPO_ROOT,
  });
  assert.equal(validation.valid, true);
  assert.match(validation.contractSha256, /^[a-f0-9]{64}$/);
});

test("validateJourneyCompatibilityContract fails closed on digest mismatch, invalid rollout order, or nonzero retired reachability", () => {
  assert.throws(
    () =>
      validateJourneyCompatibilityContract(
        {
          ...JOURNEY_V3_COMPATIBILITY_CONTRACT,
          canonicalDigests: {
            ...JOURNEY_V3_COMPATIBILITY_CONTRACT.canonicalDigests,
            "contracts/api/journey-v3.openapi.yaml": "0".repeat(64),
          },
        },
        { repoRoot: REPO_ROOT },
      ),
    (err) => err instanceof JourneyCompatibilityError && err.code === "E_COMPAT_DIGEST_MISMATCH",
  );

  assert.throws(
    () =>
      validateJourneyCompatibilityContract({
        ...JOURNEY_V3_COMPATIBILITY_CONTRACT,
        rolloutOrder: ["PRODUCER_FIRST_FOR_ADDITIVE"],
      }),
    (err) => err instanceof JourneyCompatibilityError && err.code === "E_COMPAT_ROLLOUT_ORDER_INVALID",
  );

  assert.throws(
    () =>
      validateJourneyCompatibilityContract({
        ...JOURNEY_V3_COMPATIBILITY_CONTRACT,
        deprecationLifecycle: {
          ...JOURNEY_V3_COMPATIBILITY_CONTRACT.deprecationLifecycle,
          minDeprecationNoticeDays: 14,
        },
      }),
    (err) => err instanceof JourneyCompatibilityError && err.code === "E_COMPAT_DEPRECATION_POLICY_INVALID",
  );

  assert.throws(
    () =>
      validateJourneyCompatibilityContract({
        ...JOURNEY_V3_COMPATIBILITY_CONTRACT,
        deprecationLifecycle: {
          ...JOURNEY_V3_COMPATIBILITY_CONTRACT.deprecationLifecycle,
          retiredAdapterReachabilityCount: 1,
        },
      }),
    (err) => err instanceof JourneyCompatibilityError && err.code === "E_COMPAT_DEPRECATION_POLICY_INVALID",
  );
});

test("classifyContractDelta distinguishes ADDITIVE vs BREAKING changes deterministically", () => {
  const baseSpec = {
    version: "v3",
    sha256: "a".repeat(64),
    requestParameters: [
      { name: "originStationId", type: "string", required: true },
      { name: "destinationStationId", type: "string", required: true },
      { name: "mobilityProfile", type: "string", required: false },
    ],
    responseFields: [
      { name: "journeyId", type: "string", required: true },
      {
        name: "transferDifficulty",
        type: "string",
        required: false,
        enumValues: ["EASY", "MODERATE"],
        consumerNegotiated: true,
      },
    ],
    errorCodes: [
      { code: "INVALID_REQUEST", httpStatus: 400, category: "USER" },
      { code: "ROUTE_SCOPE_INVALID", httpStatus: 422, category: "USER" },
    ],
  };

  // Optional response field + negotiated enum value -> ADDITIVE
  const additiveCandidate = {
    ...baseSpec,
    version: "v3.1",
    sha256: "b".repeat(64),
    responseFields: [
      ...baseSpec.responseFields.slice(0, 1),
      {
        name: "transferDifficulty",
        type: "string",
        required: false,
        enumValues: ["EASY", "MODERATE", "STEEP_RAMP"],
        consumerNegotiated: true,
      },
      { name: "elevatorOutageAdvisory", type: "object", required: false },
    ],
  };

  const additiveResult = classifyContractDelta(baseSpec, additiveCandidate);
  assert.equal(additiveResult.classification, "ADDITIVE");
  assert.equal(additiveResult.requiredRolloutStep, "PRODUCER_FIRST_FOR_ADDITIVE");
  assert.equal(additiveResult.reasons.includes("OPTIONAL_RESPONSE_FIELD_ADDED"), true);
  assert.equal(additiveResult.reasons.includes("NEGOTIATED_ENUM_VALUE_ADDED"), true);

  // Same version with different bytes -> BREAKING (SAME_VERSION_DIFFERENT_BYTES)
  const sameVersionMutated = {
    ...baseSpec,
    sha256: "c".repeat(64),
  };
  const sameVersionResult = classifyContractDelta(baseSpec, sameVersionMutated);
  assert.equal(sameVersionResult.classification, "BREAKING");
  assert.equal(sameVersionResult.reasons.includes("SAME_VERSION_DIFFERENT_BYTES"), true);

  // Required response field removed -> BREAKING
  const removedRequiredField = {
    ...baseSpec,
    version: "v4",
    sha256: "d".repeat(64),
    responseFields: [baseSpec.responseFields[1]],
  };
  const removedFieldResult = classifyContractDelta(baseSpec, removedRequiredField);
  assert.equal(removedFieldResult.classification, "BREAKING");
  assert.equal(removedFieldResult.reasons.includes("REQUIRED_RESPONSE_FIELD_REMOVED"), true);

  // New required request parameter added -> BREAKING
  const addedRequiredParam = {
    ...baseSpec,
    version: "v4",
    sha256: "e".repeat(64),
    requestParameters: [
      ...baseSpec.requestParameters,
      { name: "strictWheelchairMode", type: "boolean", required: true },
    ],
  };
  const addedParamResult = classifyContractDelta(baseSpec, addedRequiredParam);
  assert.equal(addedParamResult.classification, "BREAKING");
  assert.equal(addedParamResult.reasons.includes("REQUIRED_REQUEST_PARAMETER_ADDED"), true);

  // Error code semantics changed -> BREAKING
  const changedErrorCode = {
    ...baseSpec,
    version: "v4",
    sha256: "f".repeat(64),
    errorCodes: [
      { code: "INVALID_REQUEST", httpStatus: 422, category: "USER" },
      { code: "ROUTE_SCOPE_INVALID", httpStatus: 422, category: "USER" },
    ],
  };
  const changedErrorResult = classifyContractDelta(baseSpec, changedErrorCode);
  assert.equal(changedErrorResult.classification, "BREAKING");
  assert.equal(changedErrorResult.reasons.includes("ERROR_CODE_SEMANTICS_CHANGED"), true);
});

test("evaluateJourneyAndArtifactCompatibility returns COMPATIBLE for N/N-1, UPGRADE_REQUIRED for retired client/API, and fails closed on unknown versions", () => {
  const compatibleResult = evaluateJourneyAndArtifactCompatibility({
    clientAppVersion: "1.2.0",
    apiContractVersion: "v3",
    errorCatalogVersion: 1,
    datapackIndexSchemaVersion: 1,
    datapackManifestSchemaVersion: 1,
    serverRouteBundleSchemaVersion: 1,
    mapCatalogSchemaVersion: 1,
    signingKeyId: "production-v1",
  });
  assert.equal(compatibleResult.status, "COMPATIBLE");
  assert.equal(compatibleResult.matchedWindow, "N");
  assert.equal(compatibleResult.fallbackUsed, false);
  assert.equal(compatibleResult.partialParseAllowed, false);

  // Explicit N-1 window support when configured in contract
  const dualWindowContract = {
    ...JOURNEY_V3_COMPATIBILITY_CONTRACT,
    nMinusOneWindow: {
      apiContractVersion: "v3",
      datapackManifestSchemaVersion: 1,
      serverRouteBundleSchemaVersion: 1,
      mapCatalogSchemaVersion: 1,
      signingKeyId: "production-v0",
      deprecationAnnouncedAt: "2026-09-01T00:00:00.000Z",
      supportEndsAt: "2026-10-15T00:00:00.000Z",
    },
    allowedSigningKeyIds: ["production-v1", "production-v0"],
  };
  const nMinusOneResult = evaluateJourneyAndArtifactCompatibility(
    {
      clientAppVersion: "1.0.0",
      apiContractVersion: "v3",
      errorCatalogVersion: 1,
      datapackIndexSchemaVersion: 1,
      datapackManifestSchemaVersion: 1,
      serverRouteBundleSchemaVersion: 1,
      mapCatalogSchemaVersion: 1,
      signingKeyId: "production-v0",
      evaluatedAt: "2026-10-01T00:00:00.000Z",
    },
    dualWindowContract,
  );
  assert.equal(nMinusOneResult.status, "COMPATIBLE");
  assert.equal(nMinusOneResult.matchedWindow, "N_MINUS_1");
  assert.equal(nMinusOneResult.fallbackUsed, false);

  // Outdated mobile client (< 1.0.0) gets explicit UPGRADE_REQUIRED without fallback
  const outdatedClientResult = evaluateJourneyAndArtifactCompatibility({
    clientAppVersion: "0.9.5",
    apiContractVersion: "v3",
    errorCatalogVersion: 1,
    datapackIndexSchemaVersion: 1,
    datapackManifestSchemaVersion: 1,
    serverRouteBundleSchemaVersion: 1,
    mapCatalogSchemaVersion: 1,
    signingKeyId: "production-v1",
  });
  assert.equal(outdatedClientResult.status, "UPGRADE_REQUIRED");
  assert.equal(outdatedClientResult.reasonCode, "CLIENT_VERSION_BELOW_MINIMUM");
  assert.equal(outdatedClientResult.fallbackUsed, false);
  assert.equal(outdatedClientResult.partialParseAllowed, false);

  // Retired route API version (v2) gets explicit UPGRADE_REQUIRED without legacy fallback
  const retiredApiResult = evaluateJourneyAndArtifactCompatibility({
    clientAppVersion: "1.0.0",
    apiContractVersion: "v2",
    errorCatalogVersion: 1,
    datapackIndexSchemaVersion: 1,
    datapackManifestSchemaVersion: 1,
    serverRouteBundleSchemaVersion: 1,
    mapCatalogSchemaVersion: 1,
    signingKeyId: "production-v1",
  });
  assert.equal(retiredApiResult.status, "UPGRADE_REQUIRED");
  assert.equal(retiredApiResult.reasonCode, "API_VERSION_RETIRED");
  assert.equal(retiredApiResult.fallbackUsed, false);

  // Unknown artifact schema version or untrusted signing key fails closed
  assert.throws(
    () =>
      evaluateJourneyAndArtifactCompatibility({
        clientAppVersion: "1.0.0",
        apiContractVersion: "v3",
        errorCatalogVersion: 1,
        datapackIndexSchemaVersion: 1,
        datapackManifestSchemaVersion: 99,
        serverRouteBundleSchemaVersion: 1,
        mapCatalogSchemaVersion: 1,
        signingKeyId: "production-v1",
      }),
    (err) => err instanceof JourneyCompatibilityError && err.code === "E_COMPAT_ARTIFACT_SCHEMA_UNSUPPORTED",
  );

  assert.throws(
    () =>
      evaluateJourneyAndArtifactCompatibility({
        clientAppVersion: "1.0.0",
        apiContractVersion: "v3",
        errorCatalogVersion: 1,
        datapackIndexSchemaVersion: 1,
        datapackManifestSchemaVersion: 1,
        serverRouteBundleSchemaVersion: 1,
        mapCatalogSchemaVersion: 1,
        signingKeyId: "untrusted-key-v9",
      }),
    (err) => err instanceof JourneyCompatibilityError && err.code === "E_COMPAT_SIGNING_KEY_UNTRUSTED",
  );
});

test("validateRollbackTupleCompatibility enforces active signing key, freshness, schema parity, and zero retired reachability", () => {
  const validRollbackTuple = {
    apiContractVersion: "v3",
    datapackIndexSchemaVersion: 1,
    datapackManifestSchemaVersion: 1,
    serverRouteBundleSchemaVersion: 1,
    mapCatalogSchemaVersion: 1,
    platformReleaseTupleSchemaVersion: 1,
    signingKeyId: "production-v1",
    evaluatedAt: "2026-11-09T12:00:00.000Z",
    freshnessExpiresAt: "2026-11-16T12:00:00.000Z",
    retiredReachabilityCount: 0,
    currentReleaseSequence: 116,
    failedReleaseSequence: 115,
    knownGoodReleaseSequence: 114,
  };

  const ok = validateRollbackTupleCompatibility(validRollbackTuple);
  assert.equal(ok.compatible, true);
  assert.match(ok.tupleDigestSha256, /^[a-f0-9]{64}$/);

  // Expired rollback target must fail closed
  assert.throws(
    () =>
      validateRollbackTupleCompatibility({
        ...validRollbackTuple,
        freshnessExpiresAt: "2026-11-09T11:59:59.000Z",
      }),
    (err) => err instanceof JourneyCompatibilityError && err.code === "E_COMPAT_ROLLBACK_EXPIRED",
  );

  // Non-zero retired reachability must fail closed
  assert.throws(
    () =>
      validateRollbackTupleCompatibility({
        ...validRollbackTuple,
        retiredReachabilityCount: 1,
      }),
    (err) => err instanceof JourneyCompatibilityError && err.code === "E_COMPAT_ROLLBACK_RETIRED_REACHABLE",
  );
});

test("classifyContractDelta rejects oversized untrusted arrays fail-closed", () => {
  const oversized = {
    version: "v3",
    sha256: "a".repeat(64),
    requestParameters: Array.from({ length: 300 }, (_, idx) => ({
      name: `param${idx}`,
      type: "string",
      required: false,
    })),
    responseFields: [],
    errorCodes: [],
  };
  assert.throws(
    () => classifyContractDelta(oversized, oversized),
    (err) => err instanceof JourneyCompatibilityError && err.code === "E_COMPAT_BUDGET_EXCEEDED",
  );
});
