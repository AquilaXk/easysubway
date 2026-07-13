import assert from "node:assert/strict";
import test from "node:test";
import { assertTemporaryReleaseDecisionsCurrent } from "./validate-production-readiness-evidence.mjs";

function evidenceWithUntilDate(untilDate) {
  return {
    backendControlPlane: {
      latestQaEvidenceStatus: {
        status: "SATISFIED",
        temporaryReleaseDecisions: {
          operatorTenantScope: { untilDate },
          singleInstanceAbuseControl: { untilDate },
        },
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
    /temporary release decision expired: operatorTenantScope/,
  );
});

test("production readiness validator는 존재하지 않는 달력 날짜를 거부한다", () => {
  assert.throws(
    () => assertTemporaryReleaseDecisionsCurrent(
      evidenceWithUntilDate("2026-02-31"),
      new Date("2026-02-01T00:00:00.000+09:00"),
    ),
    /operatorTenantScope\.untilDate must be valid/,
  );
});
