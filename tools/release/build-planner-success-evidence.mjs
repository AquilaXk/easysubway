#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadFixtures, runRangeRaptor, runTimeDependentDijkstra } from "../routes/prototype-route-v2.mjs";

const API_CATALOG_ID = "internal:POST:/api/v2/routes/search:com.easysubway.route.adapter.in.web.RouteSearchController#searchRouteV2";
const SHA256 = /^[0-9a-f]{64}$/;

// #1414 E2~E6 통합 시나리오를 tools/routes/route-v2-fixtures.json의 #1228 회귀 fixture id에 연결한다.
// prototype-route-v2.mjs(추적된 RAPTOR/Dijkstra 참조 구현)를 재실행해 실제 시나리오 결과를 재검증하며,
// planner 알고리즘 자체를 재구현하지 않는다.
const SCENARIO_FIXTURE_IDS = {
  E2: "express_beats_local",
  E3: "express_skips_intermediate_stop",
  E4: "missed_express_makes_local_faster",
  E5: "provider_realtime_stale",
  E6: "unmatched_realtime_express_does_not_override_planned_local",
};

// #1228 회귀 5종(express-skip, express-faster, local-faster-when-waiting, short-turn, unmatched-realtime).
const REGRESSION_1228_FIXTURE_IDS = {
  expressSkip: "express_skips_intermediate_stop",
  expressFaster: "express_beats_local",
  localFasterWhenWaiting: "missed_express_makes_local_faster",
  shortTurn: "short_turn_does_not_route_past_terminal",
  unmatchedRealtime: "unmatched_realtime_express_does_not_override_planned_local",
};

// 이슈 #1414 NO_GO #2("final seed의 missing/unknown pattern을 LOCAL로 default함")를 구조적으로
// 방지하는 backend 증거 참조. TimetableSeedLoader는 로드 시 service_pattern이 LOCAL/EXPRESS가
// 아닌 trip이 하나라도 있으면 활성화를 fail-closed로 거부한다(defaulting이 아니라 거부).
const SEED_PATTERN_GUARD = {
  assertionSourceFile: "backend/src/main/java/com/easysubway/route/adapter/out/persistence/TimetableSeedLoader.java",
  assertionLabel: "trip service pattern identity",
  verifiedByTest: "backend/src/test/java/com/easysubway/route/adapter/out/persistence/TimetableSeedLoaderTest.java::trackedCompleteSnapshotLoadsWithExactEvidenceCounts",
};

function fixtureResultMatches(query, result) {
  if (query.expectedArrival === null) return result === null;
  if (!result) return false;
  if (result.arrival !== query.expectedArrival) return false;
  if (query.expectedDurationSeconds !== undefined && result.durationSeconds !== query.expectedDurationSeconds) return false;
  if (result.transferCount !== query.expectedTransfers) return false;
  if (JSON.stringify(result.tripIds) !== JSON.stringify(query.expectedTripIds)) return false;
  const rideSteps = (result.path ?? []).filter((step) => step.type === "ride");
  const checks = [
    ["expectedServicePatterns", rideSteps.map((step) => step.servicePattern)],
    ["expectedHeadsigns", rideSteps.map((step) => step.headsign)],
    ["expectedDirections", rideSteps.map((step) => step.directionId)],
    ["expectedDestinationStationIds", rideSteps.map((step) => step.destinationStationId)],
    ["expectedStopPatterns", rideSteps.map((step) => step.stopPattern)],
    ["expectedRealtimeMatchLevels", rideSteps.map((step) => step.realtimeMatchLevel)],
  ];
  for (const [field, actual] of checks) {
    if (query[field] === undefined) continue;
    if (JSON.stringify(actual) !== JSON.stringify(query[field])) return false;
  }
  return true;
}

function passesFixture(fixtures, fixtureId) {
  const query = fixtures.queries.find((candidate) => candidate.id === fixtureId);
  if (!query) throw new Error(`missing route-v2 regression fixture: ${fixtureId}`);
  return [runRangeRaptor, runTimeDependentDijkstra].every(
    (runner) => fixtureResultMatches(query, runner(fixtures, query)[0] ?? null),
  );
}

// #2098 fragment의 E2~E6 attestation과 #1228 회귀 checks를 tracked fixture 재실행으로 산출한다.
export async function evaluateRouteV2RegressionFixtures(fixturesPath) {
  const fixtures = await loadFixtures(fixturesPath);
  const scenarios = Object.fromEntries(
    Object.entries(SCENARIO_FIXTURE_IDS).map(([scenarioId, fixtureId]) => [
      scenarioId,
      passesFixture(fixtures, fixtureId),
    ]),
  );
  const regression1228 = Object.fromEntries(
    Object.entries(REGRESSION_1228_FIXTURE_IDS).map(([key, fixtureId]) => [key, passesFixture(fixtures, fixtureId)]),
  );
  return {
    scenarios,
    regression1228,
    fixturesSha256: sha256(Buffer.from(JSON.stringify(fixtures))),
  };
}

export function buildPlannerSuccessEvidence({
  candidate,
  canary,
  generatedAt = new Date().toISOString(),
  provenance = "final-candidate",
  regressionEvidence = null,
}) {
  const identity = candidate?.releaseCandidateIdentity;
  if (candidate?.phase !== "CANDIDATE" || candidate?.issue !== 2056 || !identity) {
    throw new Error("planner evidence requires the #2056 CANDIDATE context");
  }
  validateCanary(canary);
  const signedRcBound = SHA256.test(identity.aabSha256 ?? "")
    && SHA256.test(identity.aabPayloadSha256 ?? "")
    && (SHA256.test(identity.backendArtifactSha256 ?? "") || SHA256.test(identity.backendImageDigest ?? ""));
  const topologyBound = SHA256.test(identity.dataPackArtifactSha256 ?? "")
    && canary.plan.plannerIdentity.canonicalPackSha256 === identity.dataPackArtifactSha256;
  const canarySha256 = sha256(Buffer.from(JSON.stringify(canary)));
  // #1414 route integration verdict가 소비하는 필드: same-RC provenance와 E2~E6 scenario attestation.
  const integrationScenarios = regressionEvidence
    ? Object.fromEntries(
      Object.entries(regressionEvidence.scenarios).map(([scenarioId, passed]) => [scenarioId, passed ? "PASS" : "FAIL"]),
    )
    : {};
  // E9는 route-v2-fixtures.json에 ITX 시나리오가 없어 regressionEvidence로 attest할 수 없다.
  // 이미 validateCanary가 강제한 실제 canary RIDE leg 내용에서 ITX_CHEONGCHUN/EXPRESS 존재를
  // 직접 재확인한다(별도 알고리즘 재구현이 아니라 이미 검증된 canary 데이터의 필드 스캔).
  integrationScenarios.E9 = hasItxExpressRide(canary) ? "PASS" : "FAIL";
  const regression1228Checks = regressionEvidence
    ? Object.fromEntries(
      Object.entries(regressionEvidence.regression1228).map(([key, passed]) => [key, passed ? "SATISFIED" : "FAILED"]),
    )
    : null;
  return {
    schemaVersion: 1,
    artifactKind: "route-v2-planner-success-evidence",
    sourceIssue: 2098,
    consumerIssue: 2056,
    generatedAt,
    provenance,
    status: signedRcBound && topologyBound
      ? "SATISFIED"
      : signedRcBound ? "BLOCKED_CANDIDATE_TOPOLOGY_IDENTITY" : "BLOCKED_SIGNED_RC_IDENTITY",
    releaseCandidateIdentity: identity,
    apiContract: { catalogId: API_CATALOG_ID, contractVersion: "ROUTE_SEARCH_V2" },
    plannerIdentity: canary.plan.plannerIdentity,
    timetableArtifactId: canary.plan.timetableArtifactId,
    canaryResultSha256: canarySha256,
    canaryResult: canary,
    integrationScenarios,
    regression1228: regression1228Checks,
    regressionFixturesSha256: regressionEvidence?.fixturesSha256 ?? null,
    seedPatternGuard: SEED_PATTERN_GUARD,
    checks: {
      deterministicRepresentativeRanking: "SATISFIED",
      officialFare: "SATISFIED",
      exactPlannedTimes: "SATISFIED",
      typedRideMetadata: "SATISFIED",
      topologyTimetableLinkage: "SATISFIED",
      candidateTopologyIdentity: topologyBound ? "SATISFIED" : "BLOCKED",
      signedReleaseCandidate: signedRcBound ? "SATISFIED" : "BLOCKED",
      // canary의 모든 RIDE leg가 LOCAL/EXPRESS 중 하나로 명시된다(validateCanary가 이를 강제하므로
      // 이 함수에 도달했다는 것 자체가 unknown pattern이 관측되지 않았다는 증거다). backend seed
      // loader는 이를 defaulting이 아니라 fail-closed 거부로 구조적으로 보장한다(SEED_PATTERN_GUARD).
      unknownPatternDefaultedToLocal: false,
    },
  };
}

function hasItxExpressRide(canary) {
  return (canary.plan.itineraries ?? []).some((itinerary) =>
    (itinerary.steps ?? []).some(
      (step) => step.stepType === "ride" && step.serviceClass === "ITX_CHEONGCHUN" && step.servicePattern === "EXPRESS",
    ));
}

function validateCanary(canary) {
  const plan = canary?.plan;
  const itineraries = plan?.itineraries;
  if (canary?.schemaVersion !== 1
    || canary.artifactKind !== "route-v2-planner-canary-result"
    || canary.sourceIssue !== 2098
    || canary.transportScope !== "SUBWAY_AND_ITX_CHEONGCHUN"
    || plan?.source !== "TIMETABLE_RAPTOR"
    || !plan.statuses?.includes("FOUND")
    || typeof plan.timetableArtifactId !== "string"
    || !Array.isArray(itineraries)
    || itineraries.length < 1
    || itineraries.length > 2) {
    throw new Error("planner canary result contract is invalid");
  }
  for (const value of Object.values(plan.plannerIdentity ?? {})) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error("planner topology/timetable identity is incomplete");
    }
  }
  const objectiveTags = new Set(itineraries.flatMap(({ objectiveTags }) => objectiveTags ?? []));
  if (!objectiveTags.has("FASTEST") || !objectiveTags.has("FEWEST_TRANSFERS")) {
    throw new Error("planner objective representatives are incomplete");
  }
  const rideClasses = new Set();
  for (const itinerary of itineraries) {
    const fare = itinerary.officialFare;
    if (!Number.isInteger(fare?.adultFareWon) || fare.adultFareWon <= 0
      || fare.currency !== "KRW"
      || fare.policy !== "SUM_OF_OFFICIAL_RIDE_OD_FARES"
      || !fare.sourceIds?.length
      || !fare.sourceSnapshotIds?.length) {
      throw new Error("planner official fare is incomplete");
    }
    for (const step of itinerary.steps ?? []) {
      if (!validTimestamp(step.plannedDepartureTime) || !validTimestamp(step.plannedArrivalTime)) {
        throw new Error("planner exact planned times are incomplete");
      }
      if (step.stepType !== "ride") continue;
      if (typeof step.tripId !== "string" || step.tripId.length === 0
        || !["SUBWAY", "ITX_CHEONGCHUN"].includes(step.serviceClass)
        || !["LOCAL", "EXPRESS"].includes(step.servicePattern)
        || (step.serviceClass === "ITX_CHEONGCHUN" && !step.trainNo)) {
        throw new Error("planner typed RIDE metadata is incomplete");
      }
      rideClasses.add(step.serviceClass);
    }
  }
  if (!rideClasses.has("SUBWAY") || !rideClasses.has("ITX_CHEONGCHUN")) {
    throw new Error("planner canary must cover SUBWAY and ITX_CHEONGCHUN");
  }
}

function validTimestamp(value) {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function argument(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index < 0 ? null : process.argv[index + 1];
}

const entry = process.argv[1] ? path.resolve(process.argv[1]) : null;
if (entry === fileURLToPath(import.meta.url)) {
  const candidatePath = argument("candidate-context");
  const canaryPath = argument("canary-result");
  const outputPath = argument("output");
  if (!candidatePath || !canaryPath || !outputPath) {
    throw new Error("--candidate-context, --canary-result and --output are required");
  }
  const provenance = argument("provenance") ?? "final-candidate";
  const skipRegression = argument("skip-regression-fixtures") === "true";
  const regressionEvidence = skipRegression
    ? null
    : await evaluateRouteV2RegressionFixtures(argument("regression-fixtures") ?? undefined);
  const evidence = buildPlannerSuccessEvidence({
    candidate: JSON.parse(readFileSync(candidatePath, "utf8")),
    canary: JSON.parse(readFileSync(canaryPath, "utf8")),
    provenance,
    regressionEvidence,
  });
  writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`);
}
