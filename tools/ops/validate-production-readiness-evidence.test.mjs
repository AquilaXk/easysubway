import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";
import { assertTemporaryReleaseDecisionsCurrent } from "./validate-production-readiness-evidence.mjs";

test("production readiness validator module은 argv 없는 ESM import를 허용한다", () => {
  const moduleUrl = new URL("./validate-production-readiness-evidence.mjs", import.meta.url).href;
  assert.doesNotThrow(() => execFileSync(
    process.execPath,
    ["--input-type=module", "-e", `import(${JSON.stringify(moduleUrl)})`],
    { stdio: "pipe" },
  ));
});

function evidenceWithUntilDate(untilDate) {
  const commonDecision = {
    owner: "AquilaXk",
    untilDate,
    risk: "temporary risk",
    mitigation: "temporary mitigation",
    followUpIssue: 1020,
  };
  return {
    backendControlPlane: {
      latestQaEvidenceStatus: {
        status: "SATISFIED",
        temporaryReleaseDecisions: {
          adminAuthTransition: { ...commonDecision },
          operatorTenantScope: { ...commonDecision },
          singleInstanceAbuseControl: {
            backendReplicaCountOneEvidence: "PASS",
            scaleOutProhibitedRunbook: "no scale out",
            owner: "AquilaXk",
            untilDate,
            postLaunchAbuseMonitoringThreshold: "monitor",
            distributedLimiterFollowUpIssue: 1022,
          },
        },
      },
      adminAuthTransition: {
        oidcMfaSsoDeferredExceptionRequired: true,
        temporaryExceptionRequiredFields: ["owner", "untilDate", "risk", "mitigation", "followUpIssue"],
      },
      operatorTenantScope: {
        releaseExceptionRequired: true,
        requiredDecisionFields: ["owner", "untilDate", "risk", "mitigation", "followUpIssue"],
      },
      abuseControlReleaseException: {
        distributedStorePreferred: true,
        singleInstanceExceptionRequiredFields: [
          "backendReplicaCountOneEvidence",
          "scaleOutProhibitedRunbook",
          "owner",
          "untilDate",
          "postLaunchAbuseMonitoringThreshold",
          "distributedLimiterFollowUpIssue",
        ],
      },
    },
  };
}

test("production readiness validator는 유효기간 안의 임시 예외를 허용한다", () => {
  assert.doesNotThrow(() => assertTemporaryReleaseDecisionsCurrent(
    evidenceWithUntilDate("2026-10-13"),
    new Date("2026-10-13T23:59:59.999+09:00"),
  ));
});

test("production readiness validator는 만료된 임시 예외의 SATISFIED 상태를 거부한다", () => {
  assert.throws(
    () => assertTemporaryReleaseDecisionsCurrent(
      evidenceWithUntilDate("2026-10-13"),
      new Date("2026-10-14T00:00:00.000+09:00"),
    ),
    /temporary release decision expired:/,
  );
});

test("production readiness validator는 존재하지 않는 달력 날짜를 거부한다", () => {
  assert.throws(
    () => assertTemporaryReleaseDecisionsCurrent(
      evidenceWithUntilDate("2026-02-31"),
      new Date("2026-02-01T00:00:00.000+09:00"),
    ),
    /\.untilDate must be valid/,
  );
});

test("production readiness validator는 필수 임시 예외 decision 누락을 거부한다", () => {
  const evidence = evidenceWithUntilDate("2026-10-13");
  delete evidence.backendControlPlane.latestQaEvidenceStatus.temporaryReleaseDecisions.adminAuthTransition;
  assert.throws(
    () => assertTemporaryReleaseDecisionsCurrent(evidence, new Date("2026-07-13T00:00:00.000+09:00")),
    /required temporary release decision missing: adminAuthTransition/,
  );
});

test("추적 중인 operations-release-evidence.json은 현재 시점 임시 예외 유효성과 post-launch sha256 결속을 만족한다", () => {
  const evidenceUrl = new URL("../../release/product-gates/operations-release-evidence.json", import.meta.url);
  const postLaunchUrl = new URL("../../release/product-gates/post-launch-operations-review-gate.json", import.meta.url);
  const rawEvidence = readFileSync(evidenceUrl);
  const evidence = JSON.parse(rawEvidence.toString("utf8"));
  assert.doesNotThrow(() => assertTemporaryReleaseDecisionsCurrent(
    evidence,
    new Date("2026-10-14T00:00:00.000+09:00"),
  ));

  const actualSha256 = createHash("sha256").update(rawEvidence).digest("hex");
  const postLaunchGate = JSON.parse(readFileSync(postLaunchUrl, "utf8"));
  const operationsBinding = postLaunchGate.preLaunchReadiness?.finalRcBinding?.refreshBindings
    ?.find((entry) => entry.refreshOn === "operations-contract-change")
    ?.files?.find((file) => file.path === "release/product-gates/operations-release-evidence.json");
  assert.equal(operationsBinding?.sha256, actualSha256);
});
