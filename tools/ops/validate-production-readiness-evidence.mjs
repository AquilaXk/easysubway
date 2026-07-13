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
  for (const [decisionId, decision] of Object.entries(decisions)) {
    assert.match(decision.untilDate ?? "", /^\d{4}-\d{2}-\d{2}$/, `${decisionId}.untilDate must be YYYY-MM-DD`);
    const expiresAt = new Date(`${decision.untilDate}T23:59:59.999+09:00`);
    assert.equal(Number.isNaN(expiresAt.getTime()), false, `${decisionId}.untilDate must be valid`);
    if (now.getTime() > expiresAt.getTime()) {
      throw new Error(`temporary release decision expired: ${decisionId} (${decision.untilDate})`);
    }
  }
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
