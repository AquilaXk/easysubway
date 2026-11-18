#!/usr/bin/env node
import { createHash } from "node:crypto";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";

const SHA256_HEX_REGEX = /^[a-f0-9]{64}$/;
const ROLE_ID_REGEX = /^role:[a-z0-9]+(?:-[a-z0-9]+)+$/;
const DRILL_BATCH_ID_REGEX = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;

const MAX_DRILL_RECEIPTS = 32;
const MAX_OBJECT_DEPTH = 16;
const MAX_TOTAL_NODES = 2048;
const MAX_STRING_LENGTH = 4096;
const MAX_RTO_MINUTES_UPPER_BOUND = 240;
const MS_PER_DAY = 86_400_000;

export const REQUIRED_CONTROL_PLANE_IDS = Object.freeze([
  "github-org-and-actions",
  "google-play-console-signing",
  "firebase-cloud-project",
  "dns-registrar-and-tls",
  "oci-vm-db-object-storage-registry",
  "artifact-signing-and-support-channel",
]);
const REQUIRED_CONTROL_PLANE_SET = new Set(REQUIRED_CONTROL_PLANE_IDS);

export const REQUIRED_DRILL_SCENARIO_IDS = Object.freeze([
  "PRIMARY_OWNER_UNAVAILABLE",
  "OIDC_OR_REGISTRY_TRUST_REVOKED",
  "SIGNING_PUBLIC_KEY_CONFIG_LOST",
  "SECURITY_KEY_COMPROMISED_OR_CHANNEL_DOWN",
]);
const REQUIRED_DRILL_SCENARIO_SET = new Set(REQUIRED_DRILL_SCENARIO_IDS);

const ALLOWED_MFA_FACTORS = Object.freeze([
  "FIDO2_HARDWARE_SECURITY_KEY",
  "WEBAUTHN_HARDWARE_BOUND",
]);
const ALLOWED_MFA_FACTOR_SET = new Set(ALLOWED_MFA_FACTORS);

const FORBIDDEN_SECRET_OR_PII_FIELD_NAMES = new Set([
  "rawemail",
  "personalemail",
  "owneremail",
  "recoveryemail",
  "accountusername",
  "personalusername",
  "password",
  "accountpassword",
  "rawrecoverycode",
  "recoverycodeplaintext",
  "recoverycodes",
  "privatekey",
  "privatekeypem",
  "secretaccesskey",
  "personalaccesstoken",
  "githubpat",
  "refresh_token",
  "refreshtoken",
  "phonenumber",
  "rawphonenumber",
]);

const EXPOSED_PII_OR_SECRET_PATTERNS = Object.freeze([
  {
    id: "EMAIL_ADDRESS",
    regex: /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/,
  },
  {
    id: "GITHUB_PERSONAL_OR_OAUTH_TOKEN",
    regex: /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b/,
  },
  {
    id: "PEM_PRIVATE_KEY",
    regex: /-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED |)PRIVATE KEY-----/,
  },
  {
    id: "CLOUD_API_KEY_OR_BEARER",
    regex: /\bAIza[0-9A-Za-z_-]{35}\b|\bAKIA[0-9A-Z]{16}\b|\bBearer\s+[A-Za-z0-9._~+/=-]{16,}\b/i,
  },
  {
    id: "PLAINTEXT_RECOVERY_CODE",
    regex: /\b(?:recovery[-_ ]?code|backup[-_ ]?code)\s*[:=]\s*[A-Za-z0-9-]{6,}/i,
  },
]);

export class CustodyAndRecoveryGateError extends Error {
  constructor(code, message, details = null) {
    super(`${code}: ${message}`);
    this.name = "CustodyAndRecoveryGateError";
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

export const CONTROL_PLANE_CUSTODY_CATALOG = deepFreeze({
  schemaVersion: 1,
  catalogId: "easysubway-control-plane-custody-and-recovery-catalog",
  maxDrillAgeDays: 90,
  allowedMfaFactors: ALLOWED_MFA_FACTORS,
  controlPlanes: [
    {
      controlPlaneId: "github-org-and-actions",
      primaryOwnerRoleId: "role:github-org-primary-custodian",
      recoveryOwnerRoleId: "role:github-org-recovery-custodian",
      requireDistinctRecoveryPath: true,
      requirePhishingResistantMfa: true,
      preferShortLivedOidc: true,
      allowBroadTokenFallback: false,
      allowReviewOrProtectionBypass: false,
      maxRtoMinutes: 45,
    },
    {
      controlPlaneId: "google-play-console-signing",
      primaryOwnerRoleId: "role:play-signing-primary-custodian",
      recoveryOwnerRoleId: "role:play-signing-recovery-custodian",
      requireDistinctRecoveryPath: true,
      requirePhishingResistantMfa: true,
      preferShortLivedOidc: true,
      allowBroadTokenFallback: false,
      allowReviewOrProtectionBypass: false,
      maxRtoMinutes: 60,
    },
    {
      controlPlaneId: "firebase-cloud-project",
      primaryOwnerRoleId: "role:firebase-cloud-primary-custodian",
      recoveryOwnerRoleId: "role:firebase-cloud-recovery-custodian",
      requireDistinctRecoveryPath: true,
      requirePhishingResistantMfa: true,
      preferShortLivedOidc: true,
      allowBroadTokenFallback: false,
      allowReviewOrProtectionBypass: false,
      maxRtoMinutes: 60,
    },
    {
      controlPlaneId: "dns-registrar-and-tls",
      primaryOwnerRoleId: "role:dns-tls-primary-custodian",
      recoveryOwnerRoleId: "role:dns-tls-recovery-custodian",
      requireDistinctRecoveryPath: true,
      requirePhishingResistantMfa: true,
      preferShortLivedOidc: true,
      allowBroadTokenFallback: false,
      allowReviewOrProtectionBypass: false,
      maxRtoMinutes: 45,
    },
    {
      controlPlaneId: "oci-vm-db-object-storage-registry",
      primaryOwnerRoleId: "role:oci-infra-primary-custodian",
      recoveryOwnerRoleId: "role:oci-infra-recovery-custodian",
      requireDistinctRecoveryPath: true,
      requirePhishingResistantMfa: true,
      preferShortLivedOidc: true,
      allowBroadTokenFallback: false,
      allowReviewOrProtectionBypass: false,
      maxRtoMinutes: 60,
    },
    {
      controlPlaneId: "artifact-signing-and-support-channel",
      primaryOwnerRoleId: "role:signing-support-primary-custodian",
      recoveryOwnerRoleId: "role:signing-support-recovery-custodian",
      requireDistinctRecoveryPath: true,
      requirePhishingResistantMfa: true,
      preferShortLivedOidc: true,
      allowBroadTokenFallback: false,
      allowReviewOrProtectionBypass: false,
      maxRtoMinutes: 60,
    },
  ],
  drillScenarios: [
    {
      scenarioId: "PRIMARY_OWNER_UNAVAILABLE",
      maxRtoMinutes: 45,
      requiresPostRecoverySessionTokenAudit: true,
    },
    {
      scenarioId: "OIDC_OR_REGISTRY_TRUST_REVOKED",
      maxRtoMinutes: 60,
      requiresPostRecoverySessionTokenAudit: true,
    },
    {
      scenarioId: "SIGNING_PUBLIC_KEY_CONFIG_LOST",
      maxRtoMinutes: 60,
      requiresPostRecoverySessionTokenAudit: true,
    },
    {
      scenarioId: "SECURITY_KEY_COMPROMISED_OR_CHANNEL_DOWN",
      maxRtoMinutes: 60,
      requiresPostRecoverySessionTokenAudit: true,
    },
  ],
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

function normalizeFieldKey(key) {
  return key.toLowerCase().replace(/[^a-z0-9]/g, "");
}

export function scanForExposedPiiOrSecrets(rootValue, rootPath = "$") {
  let visitedNodes = 0;
  const stack = [{ value: rootValue, path: rootPath, depth: 0 }];

  while (stack.length > 0) {
    const current = stack.pop();
    visitedNodes += 1;
    if (visitedNodes > MAX_TOTAL_NODES) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_BUDGET_EXCEEDED",
        `Input graph exceeds maximum node budget (${MAX_TOTAL_NODES})`,
        { path: current.path },
      );
    }
    if (current.depth > MAX_OBJECT_DEPTH) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_BUDGET_EXCEEDED",
        `Input nesting depth exceeds maximum budget (${MAX_OBJECT_DEPTH})`,
        { path: current.path },
      );
    }

    const val = current.value;
    if (typeof val === "string") {
      if (val.length > MAX_STRING_LENGTH) {
        throw new CustodyAndRecoveryGateError(
          "E_CUSTODY_BUDGET_EXCEEDED",
          `String value at '${current.path}' exceeds maximum length (${MAX_STRING_LENGTH})`,
          { path: current.path },
        );
      }
      for (const pattern of EXPOSED_PII_OR_SECRET_PATTERNS) {
        if (pattern.regex.test(val)) {
          throw new CustodyAndRecoveryGateError(
            "E_CUSTODY_PII_OR_SECRET_EXPOSED",
            `Forbidden ${pattern.id} pattern detected at '${current.path}'`,
            { path: current.path, patternId: pattern.id },
          );
        }
      }
      continue;
    }

    if (!val || typeof val !== "object") {
      continue;
    }

    if (Array.isArray(val)) {
      for (let idx = val.length - 1; idx >= 0; idx -= 1) {
        stack.push({
          value: val[idx],
          path: `${current.path}[${idx}]`,
          depth: current.depth + 1,
        });
      }
      continue;
    }

    const keys = Object.keys(val);
    for (let idx = keys.length - 1; idx >= 0; idx -= 1) {
      const key = keys[idx];
      const normalizedKey = normalizeFieldKey(key);
      if (FORBIDDEN_SECRET_OR_PII_FIELD_NAMES.has(normalizedKey)) {
        throw new CustodyAndRecoveryGateError(
          "E_CUSTODY_PII_OR_SECRET_EXPOSED",
          `Forbidden PII or secret field '${key}' present at '${current.path}.${key}'`,
          { path: `${current.path}.${key}`, field: key },
        );
      }
      stack.push({
        value: val[key],
        path: `${current.path}.${key}`,
        depth: current.depth + 1,
      });
    }
  }
}

export function validateControlPlaneCustodyCatalog(catalog = CONTROL_PLANE_CUSTODY_CATALOG) {
  if (!catalog || typeof catalog !== "object" || Array.isArray(catalog)) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_CATALOG_INVALID",
      "Custody catalog must be a non-null object",
    );
  }

  scanForExposedPiiOrSecrets(catalog, "catalog");

  if (!Array.isArray(catalog.controlPlanes) || catalog.controlPlanes.length !== REQUIRED_CONTROL_PLANE_IDS.length) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_CATALOG_INVALID",
      `Catalog must define all ${REQUIRED_CONTROL_PLANE_IDS.length} required control planes`,
    );
  }

  const seenPlanes = new Set();
  const seenPrimaryRoles = new Set();

  for (const plane of catalog.controlPlanes) {
    if (
      !plane ||
      typeof plane !== "object" ||
      typeof plane.controlPlaneId !== "string" ||
      !REQUIRED_CONTROL_PLANE_SET.has(plane.controlPlaneId)
    ) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_CATALOG_INVALID",
        `Unknown or invalid controlPlaneId '${String(plane?.controlPlaneId)}'`,
      );
    }
    if (seenPlanes.has(plane.controlPlaneId)) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_CATALOG_INVALID",
        `Duplicate controlPlaneId '${plane.controlPlaneId}'`,
      );
    }
    seenPlanes.add(plane.controlPlaneId);

    if (
      typeof plane.primaryOwnerRoleId !== "string" ||
      typeof plane.recoveryOwnerRoleId !== "string" ||
      !ROLE_ID_REGEX.test(plane.primaryOwnerRoleId) ||
      !ROLE_ID_REGEX.test(plane.recoveryOwnerRoleId) ||
      plane.primaryOwnerRoleId === plane.recoveryOwnerRoleId ||
      plane.requireDistinctRecoveryPath !== true
    ) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_SEPARATION_VIOLATION",
        `Control plane '${plane.controlPlaneId}' must separate abstract primaryOwnerRoleId and recoveryOwnerRoleId`,
      );
    }

    seenPrimaryRoles.add(plane.primaryOwnerRoleId);

    if (
      plane.requirePhishingResistantMfa !== true ||
      plane.preferShortLivedOidc !== true ||
      plane.allowBroadTokenFallback !== false ||
      plane.allowReviewOrProtectionBypass !== false
    ) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_POLICY_VIOLATION",
        `Control plane '${plane.controlPlaneId}' violates MFA, OIDC, or zero-bypass custody invariants`,
      );
    }

    if (
      !Number.isInteger(plane.maxRtoMinutes) ||
      plane.maxRtoMinutes <= 0 ||
      plane.maxRtoMinutes > MAX_RTO_MINUTES_UPPER_BOUND
    ) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_POLICY_VIOLATION",
        `Control plane '${plane.controlPlaneId}' has invalid maxRtoMinutes`,
      );
    }
  }

  if (!Array.isArray(catalog.drillScenarios) || catalog.drillScenarios.length !== REQUIRED_DRILL_SCENARIO_IDS.length) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_CATALOG_INVALID",
      `Catalog must define all ${REQUIRED_DRILL_SCENARIO_IDS.length} required drill scenarios`,
    );
  }

  const seenScenarios = new Set();
  for (const scenario of catalog.drillScenarios) {
    if (
      !scenario ||
      typeof scenario.scenarioId !== "string" ||
      !REQUIRED_DRILL_SCENARIO_SET.has(scenario.scenarioId) ||
      seenScenarios.has(scenario.scenarioId)
    ) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_CATALOG_INVALID",
        `Invalid or duplicate drill scenario '${String(scenario?.scenarioId)}'`,
      );
    }
    if (
      !Number.isInteger(scenario.maxRtoMinutes) ||
      scenario.maxRtoMinutes <= 0 ||
      scenario.maxRtoMinutes > MAX_RTO_MINUTES_UPPER_BOUND ||
      scenario.requiresPostRecoverySessionTokenAudit !== true
    ) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_POLICY_VIOLATION",
        `Drill scenario '${scenario.scenarioId}' has invalid RTO or post-audit policy`,
      );
    }
    seenScenarios.add(scenario.scenarioId);
  }

  return {
    valid: true,
    controlPlaneCount: seenPlanes.size,
    scenarioCount: seenScenarios.size,
    catalogSha256: sha256Canonical(catalog),
  };
}

function validateReceiptEntry(receipt, controlPlanesById, scenariosById, evaluatedMs, maxDrillAgeDays) {
  if (!receipt || typeof receipt !== "object" || Array.isArray(receipt)) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_INVALID_INPUT",
      "Each drill receipt must be an object",
    );
  }

  const scenario = scenariosById.get(receipt.scenarioId);
  if (!scenario) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_UNKNOWN_SCENARIO",
      `Unknown drill scenarioId '${String(receipt.scenarioId)}'`,
    );
  }

  const controlPlane = controlPlanesById.get(receipt.controlPlaneId);
  if (!controlPlane) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_UNKNOWN_CONTROL_PLANE",
      `Unknown controlPlaneId '${String(receipt.controlPlaneId)}'`,
    );
  }

  if (
    typeof receipt.executedByRoleId !== "string" ||
    receipt.executedByRoleId !== controlPlane.recoveryOwnerRoleId ||
    receipt.executedByRoleId === controlPlane.primaryOwnerRoleId
  ) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_SEPARATION_VIOLATION",
      `Scenario '${receipt.scenarioId}' must be executed by distinct recovery role '${controlPlane.recoveryOwnerRoleId}'`,
    );
  }

  if (!ALLOWED_MFA_FACTOR_SET.has(receipt.mfaFactorUsed)) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_MFA_POLICY_VIOLATION",
      `Scenario '${receipt.scenarioId}' must use phishing-resistant hardware MFA`,
    );
  }

  if (receipt.usedShortLivedOidc !== true) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_OIDC_REQUIRED",
      `Scenario '${receipt.scenarioId}' must use short-lived OIDC or bounded delegation`,
    );
  }

  if (receipt.usedBroadLongLivedToken !== false) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_BROAD_TOKEN_FORBIDDEN",
      `Scenario '${receipt.scenarioId}' used a forbidden broad long-lived token fallback`,
    );
  }

  if (receipt.bypassedProtectedEnvironment !== false) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_PROTECTION_BYPASS_FORBIDDEN",
      `Scenario '${receipt.scenarioId}' bypassed a protected branch or environment gate`,
    );
  }

  if (
    receipt.postRecoverySessionTokenAuditCompleted !== true ||
    receipt.revokedStaleSessionsAndTokens !== true
  ) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_POST_AUDIT_INCOMPLETE",
      `Scenario '${receipt.scenarioId}' did not complete post-recovery session/token revocation and audit`,
    );
  }

  const effectiveMaxRtoMinutes = Math.min(controlPlane.maxRtoMinutes, scenario.maxRtoMinutes);
  if (
    typeof receipt.elapsedMinutes !== "number" ||
    !Number.isFinite(receipt.elapsedMinutes) ||
    receipt.elapsedMinutes <= 0 ||
    receipt.elapsedMinutes > effectiveMaxRtoMinutes
  ) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_RTO_EXCEEDED",
      `Scenario '${receipt.scenarioId}' elapsedMinutes (${String(receipt.elapsedMinutes)}) exceeded maxRtoMinutes (${effectiveMaxRtoMinutes})`,
    );
  }

  if (typeof receipt.evidenceDigestSha256 !== "string" || !SHA256_HEX_REGEX.test(receipt.evidenceDigestSha256)) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_INVALID_DIGEST",
      `Scenario '${receipt.scenarioId}' evidenceDigestSha256 must be a 64-character hex SHA-256`,
    );
  }

  const executedMs = Date.parse(receipt.executedAt ?? "");
  const maxAgeMs = maxDrillAgeDays * MS_PER_DAY;
  if (
    Number.isNaN(executedMs) ||
    executedMs > evaluatedMs ||
    evaluatedMs - executedMs > maxAgeMs
  ) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_STALE_OR_INVALID_TIMESTAMP",
      `Scenario '${receipt.scenarioId}' executedAt timestamp is invalid, in the future, or older than ${maxDrillAgeDays} days`,
    );
  }

  return {
    scenarioId: receipt.scenarioId,
    controlPlaneId: receipt.controlPlaneId,
    executedByRoleId: receipt.executedByRoleId,
    mfaFactorUsed: receipt.mfaFactorUsed,
    elapsedMinutes: receipt.elapsedMinutes,
    maxRtoMinutes: effectiveMaxRtoMinutes,
    postRecoverySessionTokenAuditCompleted: true,
    bypassedProtectedEnvironment: false,
    usedBroadLongLivedToken: false,
    executedAt: receipt.executedAt,
    evidenceDigestSha256: receipt.evidenceDigestSha256,
  };
}

export function evaluateCustodyAndRecoveryDrill(
  input,
  catalog = CONTROL_PLANE_CUSTODY_CATALOG,
) {
  const catalogValidation = validateControlPlaneCustodyCatalog(catalog);

  if (!input || typeof input !== "object" || Array.isArray(input)) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_INVALID_INPUT",
      "Drill evaluation input must be a non-null object",
    );
  }

  if (!Array.isArray(input.receipts)) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_INVALID_INPUT",
      "receipts must be an array",
    );
  }

  if (input.receipts.length > MAX_DRILL_RECEIPTS) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_BUDGET_EXCEEDED",
      `receipts length (${input.receipts.length}) exceeds maximum budget (${MAX_DRILL_RECEIPTS})`,
    );
  }

  scanForExposedPiiOrSecrets(input, "drillInput");

  if (typeof input.drillBatchId !== "string" || !DRILL_BATCH_ID_REGEX.test(input.drillBatchId)) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_INVALID_INPUT",
      "drillBatchId must be a valid non-empty identifier",
    );
  }

  const evaluatedMs = Date.parse(input.evaluatedAt ?? "");
  if (Number.isNaN(evaluatedMs)) {
    throw new CustodyAndRecoveryGateError(
      "E_CUSTODY_INVALID_INPUT",
      "evaluatedAt must be a valid ISO-8601 timestamp",
    );
  }

  const controlPlanesById = new Map(
    catalog.controlPlanes.map((entry) => [entry.controlPlaneId, entry]),
  );
  const scenariosById = new Map(
    catalog.drillScenarios.map((entry) => [entry.scenarioId, entry]),
  );

  const seenScenarioIds = new Set();
  const normalizedReceipts = [];

  for (const receipt of input.receipts) {
    const normalized = validateReceiptEntry(
      receipt,
      controlPlanesById,
      scenariosById,
      evaluatedMs,
      catalog.maxDrillAgeDays ?? 90,
    );
    if (seenScenarioIds.has(normalized.scenarioId)) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_DUPLICATE_SCENARIO",
        `Duplicate drill receipt for scenario '${normalized.scenarioId}'`,
      );
    }
    seenScenarioIds.add(normalized.scenarioId);
    normalizedReceipts.push(normalized);
  }

  for (const requiredScenarioId of REQUIRED_DRILL_SCENARIO_IDS) {
    if (!seenScenarioIds.has(requiredScenarioId)) {
      throw new CustodyAndRecoveryGateError(
        "E_CUSTODY_MISSING_SCENARIO",
        `Missing required recovery drill scenario receipt: '${requiredScenarioId}'`,
      );
    }
  }

  normalizedReceipts.sort((left, right) => codepointCompare(left.scenarioId, right.scenarioId));

  const summaryPayload = {
    schemaVersion: 1,
    artifactKind: "custody-and-recovery-drill-summary",
    drillBatchId: input.drillBatchId,
    evaluatedAt: input.evaluatedAt,
    catalogSha256: catalogValidation.catalogSha256,
    scenarioCount: normalizedReceipts.length,
    receipts: normalizedReceipts,
  };

  return {
    valid: true,
    ...summaryPayload,
    summarySha256: sha256Canonical(summaryPayload),
  };
}

if (isMainModule(import.meta.url)) {
  const result = validateControlPlaneCustodyCatalog(CONTROL_PLANE_CUSTODY_CATALOG);
  process.stdout.write(`custody-and-recovery-drill-gate: OK ${result.catalogSha256}\n`);
}
