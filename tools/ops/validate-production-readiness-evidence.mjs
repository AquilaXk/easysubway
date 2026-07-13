#!/usr/bin/env node
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

export function assertTemporaryReleaseDecisionsCurrent(evidence, now = new Date()) {
  const latestStatus = evidence.backendControlPlane?.latestQaEvidenceStatus;
  assert.ok(latestStatus, "backendControlPlane.latestQaEvidenceStatus is required");
  if (latestStatus.status !== "SATISFIED") return;

  const decisions = latestStatus.temporaryReleaseDecisions;
  assert.ok(decisions && typeof decisions === "object", "temporaryReleaseDecisions is required for SATISFIED");
  const requirements = [
    {
      id: "adminAuthTransition",
      required: evidence.backendControlPlane.adminAuthTransition?.oidcMfaSsoDeferredExceptionRequired,
      fields: evidence.backendControlPlane.adminAuthTransition?.temporaryExceptionRequiredFields,
    },
    {
      id: "operatorTenantScope",
      required: evidence.backendControlPlane.operatorTenantScope?.releaseExceptionRequired,
      fields: evidence.backendControlPlane.operatorTenantScope?.requiredDecisionFields,
    },
    {
      id: "singleInstanceAbuseControl",
      required: evidence.backendControlPlane.abuseControlReleaseException?.distributedStorePreferred,
      fields: evidence.backendControlPlane.abuseControlReleaseException?.singleInstanceExceptionRequiredFields,
    },
  ];
  for (const requirement of requirements.filter(({ required }) => required)) {
    const decision = decisions[requirement.id];
    assert.ok(decision, `required temporary release decision missing: ${requirement.id}`);
    assert.ok(Array.isArray(requirement.fields), `required decision fields missing: ${requirement.id}`);
    for (const field of requirement.fields) {
      assert.ok(hasValue(decision[field]), `${requirement.id}.${field} is required`);
    }
  }
  for (const [decisionId, decision] of Object.entries(decisions)) {
    assert.match(decision.untilDate ?? "", /^\d{4}-\d{2}-\d{2}$/, `${decisionId}.untilDate must be YYYY-MM-DD`);
    assert.equal(isValidCalendarDate(decision.untilDate), true, `${decisionId}.untilDate must be valid`);
    const expiresAt = new Date(`${decision.untilDate}T23:59:59.999+09:00`);
    if (now.getTime() > expiresAt.getTime()) {
      throw new Error(`temporary release decision expired: ${decisionId} (${decision.untilDate})`);
    }
  }
}

function hasValue(value) {
  return value !== undefined && value !== null && (typeof value !== "string" || value.trim() !== "");
}

function isValidCalendarDate(value) {
  const [year, month, day] = value.split("-").map(Number);
  const leapYear = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const daysInMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth[month - 1];
}

async function main() {
  const args = process.argv.slice(2);
  const evidenceIndex = args.indexOf("--evidence");
  const evidencePath = evidenceIndex >= 0 ? args[evidenceIndex + 1] : undefined;
  assert.ok(evidencePath, "--evidence is required");
  const evidence = JSON.parse(await readFile(evidencePath, "utf8"));
  assertTemporaryReleaseDecisionsCurrent(evidence);
  console.log("production readiness temporary decisions valid");
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
