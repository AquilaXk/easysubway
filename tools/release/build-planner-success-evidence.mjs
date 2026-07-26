#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadFixtures, runRangeRaptor, runTimeDependentDijkstra } from "../routes/prototype-route-v2.mjs";
import { buildBackendTimetableSeed } from "../datapack/build-backend-timetable-seed.mjs";

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

// 이슈 #1414 NO_GO #2("final seed의 missing/unknown pattern을 LOCAL로 default함")를 방지하는
// backend 증거 참조(보조 정보 — 아래 verifySeedRejectsUnknownServicePattern이 실측하는
// seed-authoring-time guard와는 다른 계층이다). TimetableSeedLoader는 로드 시 service_pattern이
// LOCAL/EXPRESS가 아닌 trip이 하나라도 있으면 활성화를 fail-closed로 거부한다.
const SEED_PATTERN_GUARD = {
  assertionSourceFile: "backend/src/main/java/com/easysubway/route/adapter/out/persistence/TimetableSeedLoader.java",
  assertionLabel: "trip service pattern identity",
  verifiedByTest: "backend/src/test/java/com/easysubway/route/adapter/out/persistence/TimetableSeedLoaderTest.java::trackedCompleteSnapshotLoadsWithExactEvidenceCounts",
};

// checks.unknownPatternDefaultedToLocal을 하드코딩 주장이 아니라 실제 실행으로 검증한다.
// tools/datapack/build-backend-timetable-seed.mjs의 buildBackendTimetableSeed는 production
// backend seed SQL을 만드는 데도 쓰이는 동일 함수이며, 내부 validateTrips가 servicePattern이
// 명시적으로 LOCAL/EXPRESS가 아니면 예외를 던진다(tools/datapack/build-backend-timetable-seed.test.mjs
// :91 "final seed는 모든 trip의 explicit LOCAL/EXPRESS servicePattern을 요구한다"가 이를 고정).
// 여기서는 그 test를 재작성하지 않고, undefined pattern으로 이 tracked 함수를 실제 호출해
// 예외가 실제로 나는지 동적으로 재현한다.
export function verifySeedRejectsUnknownServicePattern() {
  const probeTrip = {
    id: "evidence-probe-trip",
    routeId: "evidence-probe-route",
    serviceId: "evidence-probe-service",
    tripHeadsign: "evidence-probe-headsign",
    directionId: "up",
    servicePattern: undefined,
  };
  try {
    buildBackendTimetableSeed({ transitTrips: [probeTrip] });
    return { rejected: false, errorMessage: null };
  } catch (error) {
    const rejected = /service_pattern must be explicitly LOCAL or EXPRESS/.test(error.message);
    return { rejected, errorMessage: error.message };
  }
}

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
  const seedPatternGuardProbe = verifySeedRejectsUnknownServicePattern();
  const checks = {
    deterministicRepresentativeRanking: "SATISFIED",
    officialFare: "SATISFIED",
    exactPlannedTimes: "SATISFIED",
    typedRideMetadata: "SATISFIED",
    topologyTimetableLinkage: "SATISFIED",
    candidateTopologyIdentity: topologyBound ? "SATISFIED" : "BLOCKED",
    signedReleaseCandidate: signedRcBound ? "SATISFIED" : "BLOCKED",
  };
  // seedPatternGuardProbe.rejected가 실제로 true일 때만(즉 tracked seed builder를 방금 실행해
  // undefined pattern이 실제로 거부됨을 확인했을 때만) false를 채운다. 예상과 다르게 거부되지
  // 않으면(가드가 깨졌거나 에러 메시지가 바뀜) 안전하다고 단정하지 않고 필드를 비워
  // verdict가 "attestation 없음"으로 fail-closed 처리하게 한다.
  if (seedPatternGuardProbe.rejected) {
    checks.unknownPatternDefaultedToLocal = false;
  }
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
    seedPatternGuardProbe,
    checks,
  };
}

function hasItxExpressRide(canary) {
  return (canary.plan.itineraries ?? []).some((itinerary) =>
    (itinerary.steps ?? []).some(
      (step) => step.stepType === "ride" && step.serviceClass === "ITX_CHEONGCHUN" && step.servicePattern === "EXPRESS",
    ));
}

// canary 후보 수 상한은 요청 계약(RouteV2SearchUseCase.SearchRouteV2Command의 alternativeCount
// 1..3)과 같은 3이다. #2560 이후 PREFER_STEP_FREE 응답은 objective 대표 2건에 더해 무단차 대안
// 1건을 남는 자리에 담을 수 있으므로, 게이트가 2로 고정돼 있으면 계약상 유효한 응답을 거부한다.
// 상한을 계약값에 맞추되 lower bound(>=1)와 objective 대표 태그 요구는 그대로 둔다. 상한 완화로
// 느슨해지는 후보 수 회귀 탐지력은 아래 태그 어휘 검증이 상계한다 — 알려지지 않은 태그를 단 후보가
// 늘어나면 여전히 fail closed한다.
const CANARY_ITINERARY_LIMIT = 3;
const KNOWN_OBJECTIVE_TAGS = new Set(["FASTEST", "FEWEST_TRANSFERS", "STEP_FREE_PREFERRED"]);

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
    || itineraries.length > CANARY_ITINERARY_LIMIT) {
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
  for (const tag of objectiveTags) {
    if (!KNOWN_OBJECTIVE_TAGS.has(tag)) {
      throw new Error("planner objective tag vocabulary is invalid");
    }
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
