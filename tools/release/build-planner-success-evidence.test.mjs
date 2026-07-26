import assert from "node:assert/strict";
import test from "node:test";

import {
  buildPlannerSuccessEvidence,
  evaluateRouteV2RegressionFixtures,
  verifySeedRejectsUnknownServicePattern,
} from "./build-planner-success-evidence.mjs";

const identity = {
  gitSha: "1".repeat(40),
  aabSha256: "2".repeat(64),
  aabPayloadSha256: "3".repeat(64),
  backendArtifactSha256: "4".repeat(64),
  dataPackArtifactSha256: "b".repeat(64),
};

function canary() {
  const step = (serviceClass, tripId, trainNo = null) => ({
    stepType: "ride",
    tripId,
    trainNo,
    serviceClass,
    servicePattern: serviceClass === "SUBWAY" ? "LOCAL" : "EXPRESS",
    plannedDepartureTime: "2026-07-17T09:00:00+09:00",
    plannedArrivalTime: "2026-07-17T09:10:00+09:00",
  });
  const itinerary = (objectiveTags, steps, adultFareWon) => ({
    objectiveTags,
    steps,
    officialFare: {
      adultFareWon,
      currency: "KRW",
      policy: "SUM_OF_OFFICIAL_RIDE_OD_FARES",
      sourceIds: ["official"],
      sourceSnapshotIds: ["snapshot"],
    },
  });
  return {
    schemaVersion: 1,
    artifactKind: "route-v2-planner-canary-result",
    sourceIssue: 2098,
    transportScope: "SUBWAY_AND_ITX_CHEONGCHUN",
    objective: "FASTEST",
    plan: {
      source: "TIMETABLE_RAPTOR",
      statuses: ["FOUND"],
      timetableArtifactId: "snapshot-1",
      plannerIdentity: {
        timetableSnapshotSha256: "a".repeat(64),
        canonicalPackSha256: "b".repeat(64),
        canonicalPackSqliteSha256: "c".repeat(64),
        canonicalStationVersion: `sha256:${"d".repeat(64)}`,
        canonicalStationSetSha256: "d".repeat(64),
        sourceLineageSha256: "e".repeat(64),
        evidenceHash: "f".repeat(64),
      },
      itineraries: [
        itinerary(["FASTEST"], [step("SUBWAY", "subway-1"), step("ITX_CHEONGCHUN", "itx-1", "2001")], 2500),
        itinerary(["FEWEST_TRANSFERS"], [step("SUBWAY", "subway-2")], 2000),
      ],
    },
  };
}

test("planner canary를 signed RC candidate identity의 #2098 success fragment로 결합한다", () => {
  const evidence = buildPlannerSuccessEvidence({
    candidate: { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity },
    canary: canary(),
    generatedAt: "2026-07-17T00:00:00.000Z",
  });

  assert.equal(evidence.status, "SATISFIED");
  assert.deepEqual(evidence.releaseCandidateIdentity, identity);
  assert.equal(evidence.checks.signedReleaseCandidate, "SATISFIED");
  assert.match(evidence.canaryResultSha256, /^[0-9a-f]{64}$/);
});

test("AAB identity가 없는 backend-only candidate는 signed RC 성공으로 승격하지 않는다", () => {
  const evidence = buildPlannerSuccessEvidence({
    candidate: {
      phase: "CANDIDATE",
      issue: 2056,
      releaseCandidateIdentity: { ...identity, aabSha256: null, aabPayloadSha256: null },
    },
    canary: canary(),
  });

  assert.equal(evidence.status, "BLOCKED_SIGNED_RC_IDENTITY");
  assert.equal(evidence.checks.signedReleaseCandidate, "BLOCKED");
});

test("official fare나 typed ITX RIDE가 없는 canary는 거부한다", () => {
  const invalid = canary();
  invalid.plan.itineraries[0].officialFare = null;

  assert.throws(() => buildPlannerSuccessEvidence({
    candidate: { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity },
    canary: invalid,
  }), /official fare/);
});

test("#2560 무단차 대안을 포함한 3건 canary는 수락하고 alternativeCount 상한 초과(4건)는 거부한다", () => {
  const stepFree = canary();
  const stepFreeItinerary = {
    ...stepFree.plan.itineraries[1],
    objectiveTags: ["STEP_FREE_PREFERRED"],
  };
  stepFree.plan.itineraries = [...stepFree.plan.itineraries, stepFreeItinerary];

  const evidence = buildPlannerSuccessEvidence({
    candidate: { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity },
    canary: stepFree,
  });

  assert.equal(evidence.status, "SATISFIED");

  const overflow = canary();
  overflow.plan.itineraries = [...overflow.plan.itineraries, stepFreeItinerary, stepFreeItinerary];

  assert.throws(() => buildPlannerSuccessEvidence({
    candidate: { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity },
    canary: overflow,
  }), /planner canary result contract is invalid/);
});

test("#2560 알려지지 않은 objective 태그를 단 후보는 거부한다", () => {
  const unknownTag = canary();
  unknownTag.plan.itineraries = [
    ...unknownTag.plan.itineraries,
    { ...unknownTag.plan.itineraries[1], objectiveTags: ["STEP_FREE"] },
  ];

  assert.throws(() => buildPlannerSuccessEvidence({
    candidate: { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity },
    canary: unknownTag,
  }), /planner objective tag vocabulary is invalid/);
});

test("provenance는 기본 final-candidate이며 unknownPatternDefaultedToLocal은 false를 명시한다", () => {
  const evidence = buildPlannerSuccessEvidence({
    candidate: { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity },
    canary: canary(),
  });

  assert.equal(evidence.provenance, "final-candidate");
  assert.equal(evidence.checks.unknownPatternDefaultedToLocal, false);
  // 하드코딩 주장이 아니라 tracked build-backend-timetable-seed.mjs를 실제로 undefined
  // pattern으로 호출해 예외가 실제로 발생함을 재현한 결과여야 한다.
  assert.equal(evidence.seedPatternGuardProbe.rejected, true);
  assert.match(
    evidence.seedPatternGuardProbe.errorMessage,
    /service_pattern must be explicitly LOCAL or EXPRESS/,
  );
  // E9는 regressionEvidence 없이도 canary 자체의 ITX_CHEONGCHUN/EXPRESS ride 존재로 attest된다.
  assert.deepEqual(evidence.integrationScenarios, { E9: "PASS" });
  assert.equal(evidence.regression1228, null);
});

test("E9는 canary에 ITX_CHEONGCHUN/EXPRESS ride가 없으면 FAIL로 attest한다", () => {
  const noItxCanary = canary();
  noItxCanary.plan.itineraries[0].steps = noItxCanary.plan.itineraries[0].steps.map((step) =>
    step.serviceClass === "ITX_CHEONGCHUN" ? { ...step, servicePattern: "LOCAL" } : step);

  const evidence = buildPlannerSuccessEvidence({
    candidate: { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity },
    canary: noItxCanary,
  });

  assert.equal(evidence.integrationScenarios.E9, "FAIL");
});

test("provenance는 override 가능하다(fixture-only 판정 테스트용)", () => {
  const evidence = buildPlannerSuccessEvidence({
    candidate: { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity },
    canary: canary(),
    provenance: "fixture",
  });

  assert.equal(evidence.provenance, "fixture");
});

test("regressionEvidence가 주어지면 E2~E6 integrationScenarios와 #1228 checks로 매핑한다", () => {
  const evidence = buildPlannerSuccessEvidence({
    candidate: { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity },
    canary: canary(),
    regressionEvidence: {
      scenarios: { E2: true, E3: true, E4: false, E5: true, E6: true },
      regression1228: { expressSkip: true, expressFaster: true, localFasterWhenWaiting: false, shortTurn: true, unmatchedRealtime: true },
      fixturesSha256: "a".repeat(64),
    },
  });

  assert.deepEqual(evidence.integrationScenarios, { E2: "PASS", E3: "PASS", E4: "FAIL", E5: "PASS", E6: "PASS", E9: "PASS" });
  assert.equal(evidence.regression1228.localFasterWhenWaiting, "FAILED");
  assert.equal(evidence.regressionFixturesSha256, "a".repeat(64));
});

test("evaluateRouteV2RegressionFixtures는 tracked #1228 fixture를 실제로 재실행해 전부 PASS를 산출한다", async () => {
  const result = await evaluateRouteV2RegressionFixtures();

  assert.deepEqual(result.scenarios, { E2: true, E3: true, E4: true, E5: true, E6: true });
  assert.deepEqual(result.regression1228, {
    expressSkip: true,
    expressFaster: true,
    localFasterWhenWaiting: true,
    shortTurn: true,
    unmatchedRealtime: true,
  });
  assert.match(result.fixturesSha256, /^[0-9a-f]{64}$/);
});

test("verifySeedRejectsUnknownServicePattern은 tracked seed builder를 실제로 호출해 undefined pattern 거부를 재현한다", () => {
  const result = verifySeedRejectsUnknownServicePattern();

  assert.equal(result.rejected, true);
  assert.match(result.errorMessage, /service_pattern must be explicitly LOCAL or EXPRESS/);
});
