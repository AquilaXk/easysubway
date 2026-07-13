import assert from "node:assert/strict";
import test from "node:test";
import { assertTemporaryReleaseDecisionsCurrent } from "./validate-production-readiness-evidence.mjs";

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
