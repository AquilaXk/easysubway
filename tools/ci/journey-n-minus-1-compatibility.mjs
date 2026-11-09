#!/usr/bin/env node
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { isDeepStrictEqual } from "node:util";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";

const SHA256_HEX_REGEX = /^[a-f0-9]{64}$/;
const SEMVER_CORE_REGEX = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const MAX_SCHEMA_FIELDS = 256;
const MAX_ENUM_VALUES_PER_FIELD = 128;
const MIN_DEPRECATION_NOTICE_DAYS = 30;
const MS_PER_DAY = 86_400_000;

const EXPECTED_ROLLOUT_ORDER = Object.freeze([
  "PRODUCER_FIRST_FOR_ADDITIVE",
  "DUAL_WINDOW_N_AND_N_MINUS_1",
  "CONSUMER_MINIMUM_BUMP_BEFORE_BREAKING_RETIREMENT",
]);

export class JourneyCompatibilityError extends Error {
  constructor(code, message, details = null) {
    super(`${code}: ${message}`);
    this.name = "JourneyCompatibilityError";
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

export const JOURNEY_V3_COMPATIBILITY_CONTRACT = deepFreeze({
  schemaVersion: 1,
  contractId: "journey-v3-and-3-artifact-n-minus-1-compatibility",
  apiContractVersion: "v3",
  supportedApiContractVersions: ["v3"],
  retiredApiContractVersions: ["v1", "v2"],
  errorCatalogVersion: 1,
  datapackIndexSchemaVersion: 1,
  datapackManifestSchemaVersion: 1,
  serverRouteBundleSchemaVersion: 1,
  mapCatalogSchemaVersion: 1,
  artifactSchemas: {
    datapackIndexSchemaVersion: 1,
    datapackManifestSchemaVersion: 1,
    serverRouteBundleSchemaVersion: 1,
    mapCatalogSchemaVersion: 1,
  },
  mobileAppVersionRange: ">=1.0.0",
  minimumMobileAppVersion: "1.0.0",
  platformReleaseTupleSchemaVersion: 1,
  platformReleaseTupleSchemaIdentity: "JOURNEY_RELEASE_TUPLE_V1",
  allowedSigningKeyIds: ["production-v1"],
  nMinusOneWindow: null,
  rolloutOrder: EXPECTED_ROLLOUT_ORDER,
  deprecationLifecycle: {
    minDeprecationNoticeDays: MIN_DEPRECATION_NOTICE_DAYS,
    retiredAdapterReachabilityCount: 0,
    allowImplicitFallbackToRetiredVersion: false,
    allowPartialDegradedParse: false,
    unsupportedClientOutcome: "UPGRADE_REQUIRED",
  },
  canonicalDigests: {
    "contracts/api/journey-v3.openapi.yaml":
      "a3e0a75361b6ab74cb7e57eb7b68bb49e01400a874caf4afcbdb450e35f2d0f0",
    "contracts/bundles/generic-mobile-consumer-bundle-v1.json":
      "7f666d016119591e5c958e7d55c936fffb5e753898e69ec28e4f0cb50b5555ff",
    "contracts/bundles/platform-contracts-v1.2.0.json":
      "539229491d8cf072118c8a5d658459ce51d993daac099ee6f00afd019f9059fa",
    "contracts/datapack/compatibility-matrix.json":
      "bcf8bc3f79814ad26c9bdf962e16a3ebe70678beeac7277dd8bcceec670d809d",
    "contracts/datapack/datapack-index.schema.json":
      "dca6f0a17b1c3a4b293c870dd24ec41604b686fa26eacd9e5e0c553f48eb4c99",
    "contracts/datapack/datapack-manifest.schema.json":
      "844018713dd3fe196f37959685afbdc1ebc93f932f9d8836a71dd08f71c96b16",
    "contracts/error-codes.json":
      "7527a60514a7000ae8df0c958516a856dfdc288b6e085e4efbde9e3ce61d4bf9",
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

function parseSemVerCore(versionText) {
  if (typeof versionText !== "string") return null;
  const match = SEMVER_CORE_REGEX.exec(versionText.trim());
  if (!match) return null;
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

function compareSemVerCore(leftVersion, rightVersion) {
  const left = parseSemVerCore(leftVersion);
  const right = parseSemVerCore(rightVersion);
  if (!left || !right) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_INVALID_SEMVER",
      `Invalid SemVer string: ${String(leftVersion)} vs ${String(rightVersion)}`,
    );
  }
  for (let idx = 0; idx < 3; idx += 1) {
    if (left[idx] !== right[idx]) {
      return left[idx] < right[idx] ? -1 : 1;
    }
  }
  return 0;
}

function assertPositiveInteger(value, fieldName) {
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_CONTRACT_INVALID",
      `${fieldName} must be a positive safe integer`,
    );
  }
}

export function validateJourneyCompatibilityContract(
  contract = JOURNEY_V3_COMPATIBILITY_CONTRACT,
  { repoRoot = null } = {},
) {
  if (!contract || typeof contract !== "object" || Array.isArray(contract)) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_CONTRACT_INVALID",
      "Contract must be a non-null object",
    );
  }

  if (contract.apiContractVersion !== "v3") {
    throw new JourneyCompatibilityError(
      "E_COMPAT_CONTRACT_INVALID",
      "apiContractVersion must be 'v3'",
    );
  }

  assertPositiveInteger(contract.errorCatalogVersion, "errorCatalogVersion");
  assertPositiveInteger(contract.datapackIndexSchemaVersion, "datapackIndexSchemaVersion");
  assertPositiveInteger(contract.datapackManifestSchemaVersion, "datapackManifestSchemaVersion");
  assertPositiveInteger(contract.serverRouteBundleSchemaVersion, "serverRouteBundleSchemaVersion");
  assertPositiveInteger(contract.mapCatalogSchemaVersion, "mapCatalogSchemaVersion");
  assertPositiveInteger(contract.platformReleaseTupleSchemaVersion, "platformReleaseTupleSchemaVersion");

  if (contract.mobileAppVersionRange !== ">=1.0.0" || contract.minimumMobileAppVersion !== "1.0.0") {
    throw new JourneyCompatibilityError(
      "E_COMPAT_CONTRACT_INVALID",
      "mobileAppVersionRange must be '>=1.0.0'",
    );
  }

  if (
    !Array.isArray(contract.allowedSigningKeyIds) ||
    contract.allowedSigningKeyIds.length === 0 ||
    !contract.allowedSigningKeyIds.includes("production-v1")
  ) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_CONTRACT_INVALID",
      "allowedSigningKeyIds must include 'production-v1'",
    );
  }

  if (!isDeepStrictEqual(contract.rolloutOrder, EXPECTED_ROLLOUT_ORDER)) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_ROLLOUT_ORDER_INVALID",
      "rolloutOrder must exactly match PRODUCER_FIRST_FOR_ADDITIVE -> DUAL_WINDOW_N_AND_N_MINUS_1 -> CONSUMER_MINIMUM_BUMP_BEFORE_BREAKING_RETIREMENT",
    );
  }

  const lifecycle = contract.deprecationLifecycle;
  if (
    !lifecycle ||
    typeof lifecycle !== "object" ||
    !Number.isSafeInteger(lifecycle.minDeprecationNoticeDays) ||
    lifecycle.minDeprecationNoticeDays < MIN_DEPRECATION_NOTICE_DAYS ||
    lifecycle.retiredAdapterReachabilityCount !== 0 ||
    lifecycle.allowImplicitFallbackToRetiredVersion !== false ||
    lifecycle.allowPartialDegradedParse !== false ||
    lifecycle.unsupportedClientOutcome !== "UPGRADE_REQUIRED"
  ) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_DEPRECATION_POLICY_INVALID",
      "deprecationLifecycle violates minimum notice days or zero retired reachability",
    );
  }

  const digests = contract.canonicalDigests;
  if (!digests || typeof digests !== "object" || Array.isArray(digests)) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_CONTRACT_INVALID",
      "canonicalDigests must be an object",
    );
  }

  const digestPaths = Object.keys(digests).sort(codepointCompare);
  if (digestPaths.length === 0) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_CONTRACT_INVALID",
      "canonicalDigests cannot be empty",
    );
  }

  for (const relativePath of digestPaths) {
    const expectedSha = digests[relativePath];
    if (typeof expectedSha !== "string" || !SHA256_HEX_REGEX.test(expectedSha)) {
      throw new JourneyCompatibilityError(
        "E_COMPAT_DIGEST_MISMATCH",
        `Invalid SHA-256 format for ${relativePath}`,
      );
    }
    if (repoRoot) {
      const fullPath = path.join(repoRoot, relativePath);
      if (!existsSync(fullPath)) {
        throw new JourneyCompatibilityError(
          "E_COMPAT_DIGEST_MISMATCH",
          `Tracked contract file missing: ${relativePath}`,
        );
      }
      const actualSha = createHash("sha256").update(readFileSync(fullPath)).digest("hex");
      if (actualSha !== expectedSha) {
        throw new JourneyCompatibilityError(
          "E_COMPAT_DIGEST_MISMATCH",
          `SHA-256 mismatch for ${relativePath}: expected ${expectedSha}, got ${actualSha}`,
        );
      }
    }
  }

  return {
    valid: true,
    contractSha256: sha256Canonical(contract),
  };
}

function indexNamedEntries(entries, kindLabel, keyField = "name") {
  if (!Array.isArray(entries)) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_INVALID_SPEC",
      `${kindLabel} must be an array`,
    );
  }
  if (entries.length > MAX_SCHEMA_FIELDS) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_BUDGET_EXCEEDED",
      `${kindLabel} exceeds maximum budget of ${MAX_SCHEMA_FIELDS}`,
    );
  }
  const index = new Map();
  for (const entry of entries) {
    if (!entry || typeof entry !== "object" || typeof entry[keyField] !== "string" || entry[keyField].length === 0) {
      throw new JourneyCompatibilityError(
        "E_COMPAT_INVALID_SPEC",
        `Invalid entry in ${kindLabel}`,
      );
    }
    const key = entry[keyField];
    if (index.has(key)) {
      throw new JourneyCompatibilityError(
        "E_COMPAT_INVALID_SPEC",
        `Duplicate key '${key}' in ${kindLabel}`,
      );
    }
    index.set(key, entry);
  }
  return index;
}

function compareRequestParameters(prevParams, nextParams, additiveReasons, breakingReasons) {
  const prevMap = indexNamedEntries(prevParams, "requestParameters", "name");
  const nextMap = indexNamedEntries(nextParams, "requestParameters", "name");

  for (const [name, prevParam] of prevMap.entries()) {
    const nextParam = nextMap.get(name);
    if (!nextParam) {
      breakingReasons.add("REQUEST_PARAMETER_REMOVED");
      continue;
    }
    if (prevParam.type !== nextParam.type) {
      breakingReasons.add("REQUEST_PARAMETER_INCOMPATIBLE_CHANGE");
    }
    if (!prevParam.required && Boolean(nextParam.required)) {
      breakingReasons.add("REQUEST_PARAMETER_INCOMPATIBLE_CHANGE");
    }
  }

  for (const [name, nextParam] of nextMap.entries()) {
    if (!prevMap.has(name)) {
      if (nextParam.required) {
        breakingReasons.add("REQUIRED_REQUEST_PARAMETER_ADDED");
      } else {
        additiveReasons.add("OPTIONAL_REQUEST_PARAMETER_ADDED");
      }
    }
  }
}

function compareResponseFieldEnums(prevField, nextField, additiveReasons, breakingReasons) {
  const prevEnums = prevField.enumValues ?? [];
  const nextEnums = nextField.enumValues ?? [];
  if (!Array.isArray(prevEnums) || !Array.isArray(nextEnums)) {
    throw new JourneyCompatibilityError("E_COMPAT_INVALID_SPEC", "enumValues must be an array");
  }
  if (prevEnums.length > MAX_ENUM_VALUES_PER_FIELD || nextEnums.length > MAX_ENUM_VALUES_PER_FIELD) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_BUDGET_EXCEEDED",
      `enumValues exceeds maximum budget of ${MAX_ENUM_VALUES_PER_FIELD}`,
    );
  }
  if (prevEnums.length === 0 && nextEnums.length === 0) return;

  const prevSet = new Set(prevEnums);
  const nextSet = new Set(nextEnums);

  for (const val of prevSet) {
    if (!nextSet.has(val)) {
      breakingReasons.add("ENUM_VALUE_REMOVED");
    }
  }
  for (const val of nextSet) {
    if (!prevSet.has(val)) {
      if (nextField.consumerNegotiated === true) {
        additiveReasons.add("NEGOTIATED_ENUM_VALUE_ADDED");
      } else {
        breakingReasons.add("UNNEGOTIATED_ENUM_VALUE_ADDED");
      }
    }
  }
}

function compareResponseFields(prevFields, nextFields, additiveReasons, breakingReasons) {
  const prevMap = indexNamedEntries(prevFields, "responseFields", "name");
  const nextMap = indexNamedEntries(nextFields, "responseFields", "name");

  for (const [name, prevField] of prevMap.entries()) {
    const nextField = nextMap.get(name);
    if (!nextField) {
      if (prevField.required) {
        breakingReasons.add("REQUIRED_RESPONSE_FIELD_REMOVED");
      } else {
        breakingReasons.add("OPTIONAL_RESPONSE_FIELD_REMOVED");
      }
      continue;
    }
    if (prevField.type !== nextField.type || (prevField.required && !nextField.required)) {
      breakingReasons.add("RESPONSE_FIELD_TYPE_OR_REQUIREDNESS_CHANGED");
    }
    compareResponseFieldEnums(prevField, nextField, additiveReasons, breakingReasons);
  }

  for (const [name, nextField] of nextMap.entries()) {
    if (!prevMap.has(name)) {
      if (nextField.required) {
        additiveReasons.add("NEW_RESPONSE_FIELD_ADDED");
      } else {
        additiveReasons.add("OPTIONAL_RESPONSE_FIELD_ADDED");
      }
    }
  }
}

function compareErrorCodes(prevErrors, nextErrors, additiveReasons, breakingReasons) {
  const prevMap = indexNamedEntries(prevErrors, "errorCodes", "code");
  const nextMap = indexNamedEntries(nextErrors, "errorCodes", "code");

  for (const [code, prevErr] of prevMap.entries()) {
    const nextErr = nextMap.get(code);
    if (!nextErr) {
      breakingReasons.add("ERROR_CODE_SEMANTICS_CHANGED");
      continue;
    }
    if (prevErr.httpStatus !== nextErr.httpStatus || prevErr.category !== nextErr.category) {
      breakingReasons.add("ERROR_CODE_SEMANTICS_CHANGED");
    }
  }

  for (const code of nextMap.keys()) {
    if (!prevMap.has(code)) {
      additiveReasons.add("ERROR_CODE_ADDED");
    }
  }
}

export function classifyContractDelta(previousSpec, candidateSpec) {
  if (
    !previousSpec ||
    typeof previousSpec !== "object" ||
    !candidateSpec ||
    typeof candidateSpec !== "object"
  ) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_INVALID_SPEC",
      "Both previousSpec and candidateSpec must be objects",
    );
  }

  if (
    typeof previousSpec.version !== "string" ||
    previousSpec.version.length === 0 ||
    typeof candidateSpec.version !== "string" ||
    candidateSpec.version.length === 0 ||
    typeof previousSpec.sha256 !== "string" ||
    !SHA256_HEX_REGEX.test(previousSpec.sha256) ||
    typeof candidateSpec.sha256 !== "string" ||
    !SHA256_HEX_REGEX.test(candidateSpec.sha256)
  ) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_INVALID_SPEC",
      "Spec version and 64-hex sha256 are required",
    );
  }

  const additiveReasons = new Set();
  const breakingReasons = new Set();

  if (previousSpec.version === candidateSpec.version && previousSpec.sha256 !== candidateSpec.sha256) {
    breakingReasons.add("SAME_VERSION_DIFFERENT_BYTES");
  }

  compareRequestParameters(
    previousSpec.requestParameters ?? [],
    candidateSpec.requestParameters ?? [],
    additiveReasons,
    breakingReasons,
  );
  compareResponseFields(
    previousSpec.responseFields ?? [],
    candidateSpec.responseFields ?? [],
    additiveReasons,
    breakingReasons,
  );
  compareErrorCodes(
    previousSpec.errorCodes ?? [],
    candidateSpec.errorCodes ?? [],
    additiveReasons,
    breakingReasons,
  );

  if (breakingReasons.size > 0) {
    const reasons = [...breakingReasons, ...additiveReasons].sort(codepointCompare);
    return {
      classification: "BREAKING",
      reasons,
      requiredRolloutStep: "DUAL_WINDOW_N_AND_N_MINUS_1",
      retirementPrerequisite: "CONSUMER_MINIMUM_BUMP_BEFORE_BREAKING_RETIREMENT",
    };
  }

  if (additiveReasons.size > 0) {
    const reasons = [...additiveReasons].sort(codepointCompare);
    return {
      classification: "ADDITIVE",
      reasons,
      requiredRolloutStep: "PRODUCER_FIRST_FOR_ADDITIVE",
      retirementPrerequisite: null,
    };
  }

  return {
    classification: "UNCHANGED",
    reasons: [],
    requiredRolloutStep: null,
    retirementPrerequisite: null,
  };
}

function matchesWindowN(request, contract) {
  return (
    request.apiContractVersion === contract.apiContractVersion &&
    request.errorCatalogVersion === contract.errorCatalogVersion &&
    request.datapackIndexSchemaVersion === contract.datapackIndexSchemaVersion &&
    request.datapackManifestSchemaVersion === contract.datapackManifestSchemaVersion &&
    request.serverRouteBundleSchemaVersion === contract.serverRouteBundleSchemaVersion &&
    request.mapCatalogSchemaVersion === contract.mapCatalogSchemaVersion &&
    request.signingKeyId === contract.allowedSigningKeyIds[0]
  );
}

function matchesWindowNMinusOne(request, contract) {
  const n1 = contract.nMinusOneWindow;
  if (!n1 || typeof n1 !== "object") return false;

  const announcedMs = Date.parse(n1.deprecationAnnouncedAt ?? "");
  const endsMs = Date.parse(n1.supportEndsAt ?? "");
  const evaluatedMs = Date.parse(request.evaluatedAt ?? "");
  if (
    Number.isNaN(announcedMs) ||
    Number.isNaN(endsMs) ||
    Number.isNaN(evaluatedMs) ||
    endsMs - announcedMs < contract.deprecationLifecycle.minDeprecationNoticeDays * MS_PER_DAY ||
    evaluatedMs > endsMs
  ) {
    return false;
  }

  return (
    request.apiContractVersion === n1.apiContractVersion &&
    request.datapackManifestSchemaVersion === n1.datapackManifestSchemaVersion &&
    request.serverRouteBundleSchemaVersion === n1.serverRouteBundleSchemaVersion &&
    request.mapCatalogSchemaVersion === n1.mapCatalogSchemaVersion &&
    request.signingKeyId === n1.signingKeyId
  );
}

export function evaluateJourneyAndArtifactCompatibility(
  request,
  contract = JOURNEY_V3_COMPATIBILITY_CONTRACT,
) {
  if (!request || typeof request !== "object" || Array.isArray(request)) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_REQUEST_INVALID",
      "Compatibility evaluation request must be an object",
    );
  }

  const signingKeySet = new Set(contract.allowedSigningKeyIds);
  if (typeof request.signingKeyId !== "string" || !signingKeySet.has(request.signingKeyId)) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_SIGNING_KEY_UNTRUSTED",
      `Signing key '${String(request.signingKeyId)}' is not in allowedSigningKeyIds`,
    );
  }

  const retiredApiSet = new Set(contract.retiredApiContractVersions);
  if (retiredApiSet.has(request.apiContractVersion)) {
    return {
      status: "UPGRADE_REQUIRED",
      reasonCode: "API_VERSION_RETIRED",
      minimumMobileAppVersion: contract.minimumMobileAppVersion,
      requiredApiContractVersion: contract.apiContractVersion,
      fallbackUsed: false,
      partialParseAllowed: false,
    };
  }

  const supportedApiSet = new Set(contract.supportedApiContractVersions);
  if (!supportedApiSet.has(request.apiContractVersion)) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_API_VERSION_UNKNOWN",
      `Unknown apiContractVersion: ${String(request.apiContractVersion)}`,
    );
  }

  if (compareSemVerCore(request.clientAppVersion, contract.minimumMobileAppVersion) < 0) {
    return {
      status: "UPGRADE_REQUIRED",
      reasonCode: "CLIENT_VERSION_BELOW_MINIMUM",
      minimumMobileAppVersion: contract.minimumMobileAppVersion,
      requiredApiContractVersion: contract.apiContractVersion,
      fallbackUsed: false,
      partialParseAllowed: false,
    };
  }

  if (matchesWindowN(request, contract)) {
    return {
      status: "COMPATIBLE",
      matchedWindow: "N",
      fallbackUsed: false,
      partialParseAllowed: false,
    };
  }

  if (matchesWindowNMinusOne(request, contract)) {
    return {
      status: "COMPATIBLE",
      matchedWindow: "N_MINUS_1",
      fallbackUsed: false,
      partialParseAllowed: false,
    };
  }

  throw new JourneyCompatibilityError(
    "E_COMPAT_ARTIFACT_SCHEMA_UNSUPPORTED",
    "Requested 3-artifact schema version or error catalog version does not match N or active N-1 window",
  );
}

export function validateRollbackTupleCompatibility(
  rollbackTuple,
  contract = JOURNEY_V3_COMPATIBILITY_CONTRACT,
) {
  if (!rollbackTuple || typeof rollbackTuple !== "object" || Array.isArray(rollbackTuple)) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_ROLLBACK_INVALID",
      "rollbackTuple must be an object",
    );
  }

  const signingKeySet = new Set(contract.allowedSigningKeyIds);
  if (!signingKeySet.has(rollbackTuple.signingKeyId)) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_SIGNING_KEY_UNTRUSTED",
      `Rollback tuple signing key '${String(rollbackTuple.signingKeyId)}' is not trusted`,
    );
  }

  const evaluatedMs = Date.parse(rollbackTuple.evaluatedAt ?? "");
  const expiresMs = Date.parse(rollbackTuple.freshnessExpiresAt ?? "");
  if (Number.isNaN(evaluatedMs) || Number.isNaN(expiresMs) || expiresMs <= evaluatedMs) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_ROLLBACK_EXPIRED",
      "Rollback target freshnessExpiresAt must be strictly greater than evaluatedAt",
    );
  }

  if (rollbackTuple.retiredReachabilityCount !== 0) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_ROLLBACK_RETIRED_REACHABLE",
      "Rollback target must have retiredReachabilityCount === 0",
    );
  }

  if (
    rollbackTuple.apiContractVersion !== contract.apiContractVersion ||
    rollbackTuple.datapackIndexSchemaVersion !== contract.datapackIndexSchemaVersion ||
    rollbackTuple.datapackManifestSchemaVersion !== contract.datapackManifestSchemaVersion ||
    rollbackTuple.serverRouteBundleSchemaVersion !== contract.serverRouteBundleSchemaVersion ||
    rollbackTuple.mapCatalogSchemaVersion !== contract.mapCatalogSchemaVersion ||
    rollbackTuple.platformReleaseTupleSchemaVersion !== contract.platformReleaseTupleSchemaVersion
  ) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_ROLLBACK_SCHEMA_MISMATCH",
      "Rollback tuple schema versions do not match active contract requirements",
    );
  }

  if (
    !Number.isSafeInteger(rollbackTuple.currentReleaseSequence) ||
    !Number.isSafeInteger(rollbackTuple.failedReleaseSequence) ||
    !Number.isSafeInteger(rollbackTuple.knownGoodReleaseSequence) ||
    rollbackTuple.currentReleaseSequence <= rollbackTuple.failedReleaseSequence ||
    rollbackTuple.knownGoodReleaseSequence >= rollbackTuple.failedReleaseSequence
  ) {
    throw new JourneyCompatibilityError(
      "E_COMPAT_ROLLBACK_SEQUENCE_NON_MONOTONIC",
      "Rollback sequence must satisfy knownGoodReleaseSequence < failedReleaseSequence < currentReleaseSequence",
    );
  }

  return {
    compatible: true,
    tupleDigestSha256: sha256Canonical(rollbackTuple),
  };
}

if (isMainModule(import.meta.url)) {
  const result = validateJourneyCompatibilityContract(JOURNEY_V3_COMPATIBILITY_CONTRACT, {
    repoRoot: process.cwd(),
  });
  process.stdout.write(`journey-n-minus-1-compatibility: OK ${result.contractSha256}\n`);
}
