import assert from "node:assert/strict";
import test from "node:test";

import {
  CONTROL_PLANE_CUSTODY_CATALOG,
  CustodyAndRecoveryGateError,
  REQUIRED_CONTROL_PLANE_IDS,
  REQUIRED_DRILL_SCENARIO_IDS,
  evaluateCustodyAndRecoveryDrill,
  validateControlPlaneCustodyCatalog,
} from "./custody-and-recovery-drill-gate.mjs";

const EVALUATED_AT = "2026-11-10T00:00:00.000Z";
const EXECUTED_AT = "2026-11-09T09:00:00.000Z";

function hex64(char) {
  return char.repeat(64);
}

function buildValidDrillReceipts() {
  return [
    {
      scenarioId: "PRIMARY_OWNER_UNAVAILABLE",
      controlPlaneId: "github-org-and-actions",
      executedByRoleId: "role:github-org-recovery-custodian",
      mfaFactorUsed: "FIDO2_HARDWARE_SECURITY_KEY",
      usedShortLivedOidc: true,
      usedBroadLongLivedToken: false,
      bypassedProtectedEnvironment: false,
      postRecoverySessionTokenAuditCompleted: true,
      revokedStaleSessionsAndTokens: true,
      elapsedMinutes: 28,
      executedAt: EXECUTED_AT,
      evidenceDigestSha256: hex64("1"),
    },
    {
      scenarioId: "OIDC_OR_REGISTRY_TRUST_REVOKED",
      controlPlaneId: "oci-vm-db-object-storage-registry",
      executedByRoleId: "role:oci-infra-recovery-custodian",
      mfaFactorUsed: "FIDO2_HARDWARE_SECURITY_KEY",
      usedShortLivedOidc: true,
      usedBroadLongLivedToken: false,
      bypassedProtectedEnvironment: false,
      postRecoverySessionTokenAuditCompleted: true,
      revokedStaleSessionsAndTokens: true,
      elapsedMinutes: 35,
      executedAt: EXECUTED_AT,
      evidenceDigestSha256: hex64("2"),
    },
    {
      scenarioId: "SIGNING_PUBLIC_KEY_CONFIG_LOST",
      controlPlaneId: "google-play-console-signing",
      executedByRoleId: "role:play-signing-recovery-custodian",
      mfaFactorUsed: "WEBAUTHN_HARDWARE_BOUND",
      usedShortLivedOidc: true,
      usedBroadLongLivedToken: false,
      bypassedProtectedEnvironment: false,
      postRecoverySessionTokenAuditCompleted: true,
      revokedStaleSessionsAndTokens: true,
      elapsedMinutes: 42,
      executedAt: EXECUTED_AT,
      evidenceDigestSha256: hex64("3"),
    },
    {
      scenarioId: "SECURITY_KEY_COMPROMISED_OR_CHANNEL_DOWN",
      controlPlaneId: "artifact-signing-and-support-channel",
      executedByRoleId: "role:signing-support-recovery-custodian",
      mfaFactorUsed: "FIDO2_HARDWARE_SECURITY_KEY",
      usedShortLivedOidc: true,
      usedBroadLongLivedToken: false,
      bypassedProtectedEnvironment: false,
      postRecoverySessionTokenAuditCompleted: true,
      revokedStaleSessionsAndTokens: true,
      elapsedMinutes: 50,
      executedAt: EXECUTED_AT,
      evidenceDigestSha256: hex64("4"),
    },
  ];
}

test("CONTROL_PLANE_CUSTODY_CATALOG defines all 6 critical control planes with separated custody and zero bypass allowances", () => {
  const validation = validateControlPlaneCustodyCatalog(CONTROL_PLANE_CUSTODY_CATALOG);
  assert.equal(validation.valid, true);
  assert.equal(validation.controlPlaneCount, 6);
  assert.match(validation.catalogSha256, /^[a-f0-9]{64}$/);

  const ids = CONTROL_PLANE_CUSTODY_CATALOG.controlPlanes.map((item) => item.controlPlaneId);
  assert.deepEqual(ids, [...REQUIRED_CONTROL_PLANE_IDS]);

  for (const plane of CONTROL_PLANE_CUSTODY_CATALOG.controlPlanes) {
    assert.notEqual(plane.primaryOwnerRoleId, plane.recoveryOwnerRoleId);
    assert.equal(plane.requireDistinctRecoveryPath, true);
    assert.equal(plane.requirePhishingResistantMfa, true);
    assert.equal(plane.preferShortLivedOidc, true);
    assert.equal(plane.allowBroadTokenFallback, false);
    assert.equal(plane.allowReviewOrProtectionBypass, false);
    assert.equal(plane.maxRtoMinutes > 0 && plane.maxRtoMinutes <= 240, true);
  }
});

test("validateControlPlaneCustodyCatalog rejects collapsed primary/recovery owner roles or broad token fallback allowances", () => {
  const collapsedCatalog = structuredClone(CONTROL_PLANE_CUSTODY_CATALOG);
  collapsedCatalog.controlPlanes[0].recoveryOwnerRoleId =
    collapsedCatalog.controlPlanes[0].primaryOwnerRoleId;

  assert.throws(
    () => validateControlPlaneCustodyCatalog(collapsedCatalog),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_SEPARATION_VIOLATION",
  );

  const permissiveCatalog = structuredClone(CONTROL_PLANE_CUSTODY_CATALOG);
  permissiveCatalog.controlPlanes[2].allowBroadTokenFallback = true;

  assert.throws(
    () => validateControlPlaneCustodyCatalog(permissiveCatalog),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_POLICY_VIOLATION",
  );
});

test("evaluateCustodyAndRecoveryDrill produces deterministic digest across all 4 required recovery scenarios", () => {
  const receipts = buildValidDrillReceipts();
  const resultA = evaluateCustodyAndRecoveryDrill({
    drillBatchId: "drill-2026-q4-01",
    evaluatedAt: EVALUATED_AT,
    receipts,
  });
  const resultB = evaluateCustodyAndRecoveryDrill({
    drillBatchId: "drill-2026-q4-01",
    evaluatedAt: EVALUATED_AT,
    receipts: [...receipts].reverse(),
  });

  assert.equal(resultA.valid, true);
  assert.equal(resultA.scenarioCount, REQUIRED_DRILL_SCENARIO_IDS.length);
  assert.match(resultA.summarySha256, /^[a-f0-9]{64}$/);
  assert.equal(resultA.summarySha256, resultB.summarySha256);
});

test("evaluateCustodyAndRecoveryDrill rejects plaintext email, personal account handle, secret token, or recovery code exposure", () => {
  const withEmail = buildValidDrillReceipts();
  withEmail[0].operatorNote = "Recovered by admin@easysubway.kr using backup hardware token";

  assert.throws(
    () =>
      evaluateCustodyAndRecoveryDrill({
        drillBatchId: "drill-2026-q4-email",
        evaluatedAt: EVALUATED_AT,
        receipts: withEmail,
      }),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_PII_OR_SECRET_EXPOSED",
  );

  const withPat = buildValidDrillReceipts();
  withPat[1].credentialTrace = "ghp_1234567890abcdefghijklmnopqrstuvwx";

  assert.throws(
    () =>
      evaluateCustodyAndRecoveryDrill({
        drillBatchId: "drill-2026-q4-pat",
        evaluatedAt: EVALUATED_AT,
        receipts: withPat,
      }),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_PII_OR_SECRET_EXPOSED",
  );

  const withRecoveryCodeField = buildValidDrillReceipts();
  withRecoveryCodeField[2].rawRecoveryCode = "ABCD-EFGH-1234-5678";

  assert.throws(
    () =>
      evaluateCustodyAndRecoveryDrill({
        drillBatchId: "drill-2026-q4-code",
        evaluatedAt: EVALUATED_AT,
        receipts: withRecoveryCodeField,
      }),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_PII_OR_SECRET_EXPOSED",
  );
});

test("evaluateCustodyAndRecoveryDrill rejects RTO breach, incomplete post-recovery audit, environment bypass, or broad token usage", () => {
  const rtoBreached = buildValidDrillReceipts();
  rtoBreached[0].elapsedMinutes = 180;

  assert.throws(
    () =>
      evaluateCustodyAndRecoveryDrill({
        drillBatchId: "drill-2026-q4-rto",
        evaluatedAt: EVALUATED_AT,
        receipts: rtoBreached,
      }),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_RTO_EXCEEDED",
  );

  const auditMissing = buildValidDrillReceipts();
  auditMissing[1].postRecoverySessionTokenAuditCompleted = false;

  assert.throws(
    () =>
      evaluateCustodyAndRecoveryDrill({
        drillBatchId: "drill-2026-q4-audit",
        evaluatedAt: EVALUATED_AT,
        receipts: auditMissing,
      }),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_POST_AUDIT_INCOMPLETE",
  );

  const bypassedEnv = buildValidDrillReceipts();
  bypassedEnv[2].bypassedProtectedEnvironment = true;

  assert.throws(
    () =>
      evaluateCustodyAndRecoveryDrill({
        drillBatchId: "drill-2026-q4-bypass",
        evaluatedAt: EVALUATED_AT,
        receipts: bypassedEnv,
      }),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_PROTECTION_BYPASS_FORBIDDEN",
  );

  const broadTokenUsed = buildValidDrillReceipts();
  broadTokenUsed[3].usedBroadLongLivedToken = true;

  assert.throws(
    () =>
      evaluateCustodyAndRecoveryDrill({
        drillBatchId: "drill-2026-q4-broad-token",
        evaluatedAt: EVALUATED_AT,
        receipts: broadTokenUsed,
      }),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_BROAD_TOKEN_FORBIDDEN",
  );
});

test("evaluateCustodyAndRecoveryDrill rejects missing scenario coverage or oversized untrusted input payloads", () => {
  const incompleteReceipts = buildValidDrillReceipts().slice(0, 3);

  assert.throws(
    () =>
      evaluateCustodyAndRecoveryDrill({
        drillBatchId: "drill-2026-q4-incomplete",
        evaluatedAt: EVALUATED_AT,
        receipts: incompleteReceipts,
      }),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_MISSING_SCENARIO",
  );

  const oversizedReceipts = Array.from({ length: 40 }, () => buildValidDrillReceipts()[0]);
  assert.throws(
    () =>
      evaluateCustodyAndRecoveryDrill({
        drillBatchId: "drill-2026-q4-oversized",
        evaluatedAt: EVALUATED_AT,
        receipts: oversizedReceipts,
      }),
    (err) =>
      err instanceof CustodyAndRecoveryGateError &&
      err.code === "E_CUSTODY_BUDGET_EXCEEDED",
  );
});
