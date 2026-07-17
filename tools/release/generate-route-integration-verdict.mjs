#!/usr/bin/env node

// #1414 route/datapack 통합 출시 판정 producer.
// #2068 route-map, #2098 planner, #2099 Mobile, #1400 topology, #2145 timetable evidence를
// 같은 RC identity로 결합해 E1~E9 통합 matrix와 same-RC identity 판정을 산출한다.
// 이 producer는 evidence를 새로 만들지 않고 조합 안전성만 fail-closed로 판정한다.

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ISSUE_TRACKER_BASE = "https://github.com/AquilaXk/easysubway/issues";
export const ROUTE_SEARCH_CATALOG_ID =
  "internal:POST:/api/v2/routes/search:com.easysubway.route.adapter.in.web.RouteSearchController#searchRouteV2";
const ROUTE_SEARCH_CONTRACT_VERSION = "ROUTE_SEARCH_V2";

// 같은 RC identity 판정에 사용하는 필드. 서로 다른 producer evidence가 같은 후보를 소비했는지 검증한다.
const RC_IDENTITY_FIELDS = [
  "gitSha",
  "appVersionName",
  "versionCode",
  "backendImageDigest",
  "backendArtifactSha256",
  "dataPackManifestSha256",
  "dataPackArtifactSha256",
  "routeContractVersion",
  "realtimeContractVersion",
];
// 최소한 값이 있어야 하는(fail-closed) 앵커 필드.
const RC_IDENTITY_ANCHOR_FIELDS = ["gitSha", "versionCode", "dataPackArtifactSha256"];

const VALID_PROVENANCE = new Set(["final-candidate", "production", "manual-observation"]);

// E1~E9 통합 시나리오 카탈로그. 각 시나리오를 실존 producer evidence·test에 연결한다.
// owner: 시나리오 결과의 attestation을 소유한 evidence 입력.
export const ROUTE_INTEGRATION_SCENARIOS = [
  {
    id: "E1",
    titleKo: "LOCAL/EXPRESS가 함께 있는 지역 노선도에 일반/급행 control 0건, 전체 topology 표시",
    producerIssue: 2068,
    owner: "routeMap",
    evidenceTests: [
      "apps/mobile/test/widget_test.dart::노선도는 노선별 보기 우회 sheet를 노출하지 않는다",
      "docs/2099-qa/item4_routemap_no_express_toggle.png",
      "docs/2099-qa/item5_talkback_dump.xml",
    ],
    guardsNoGo: ["route_map_local_express_control_present"],
  },
  {
    id: "E2",
    titleKo: "EXPRESS가 OD 모두 정차하고 실제 도착이 더 빠르면 EXPRESS 선택, 급행 정보 표시",
    producerIssue: 2098,
    owner: "planner",
    evidenceTests: [
      "tools/routes/prototype-route-v2.test.mjs::express_beats_local",
      "tools/routes/prototype-route-v2.test.mjs::direct_timetable_route",
    ],
    guardsNoGo: ["ride_leg_missing_service_metadata"],
  },
  {
    id: "E3",
    titleKo: "EXPRESS가 목적역 통과 시 EXPRESS 승하차 후보 0건, 유효 LOCAL 선택",
    producerIssue: 2098,
    owner: "planner",
    evidenceTests: [
      "tools/routes/prototype-route-v2.test.mjs::express_skips_intermediate_stop",
    ],
    guardsNoGo: ["express_skip_stop_boardable"],
  },
  {
    id: "E4",
    titleKo: "EXPRESS 출발 대기로 LOCAL이 먼저 도착하면 LOCAL 선택, 급행 배지 0건",
    producerIssue: 2098,
    owner: "planner",
    evidenceTests: [
      "tools/routes/prototype-route-v2.test.mjs::missed_express_makes_local_faster",
      "backend/src/test/java/com/easysubway/route/application/service/RouteTimetableRaptorPlannerGoldenOdTest.java::od3_missedExpressAnchorsToNextLocalTrain",
    ],
    guardsNoGo: [],
  },
  {
    id: "E5",
    titleKo: "matched EXPRESS realtime는 같은 trip/direction/pattern 시각만 보정, 급행 배지 유지",
    producerIssue: 2098,
    owner: "planner",
    evidenceTests: [
      "tools/routes/prototype-route-v2.test.mjs::provider_realtime_stale",
      "backend/src/test/java/com/easysubway/route/domain/RealtimeEtaOverlayTest.java::freshRealtimeCandidateCanMatchCanonicalServicePattern",
    ],
    guardsNoGo: ["realtime_mismatch_overrides_planned"],
  },
  {
    id: "E6",
    titleKo: "pattern mismatch 또는 unmatched realtime는 planned trip/pattern 보존, 운행종별 치환 0건",
    producerIssue: 2098,
    owner: "planner",
    evidenceTests: [
      "tools/routes/prototype-route-v2.test.mjs::unmatched_realtime_express_does_not_override_planned_local",
      "backend/src/test/java/com/easysubway/route/domain/RealtimeEtaOverlayTest.java::freshRealtimeCandidateRequiresMatchingServicePattern",
    ],
    guardsNoGo: ["realtime_mismatch_overrides_planned"],
  },
  {
    id: "E7",
    titleKo: "mixed station timetable에서 LOCAL/EXPRESS 모두 시각순 표시, EXPRESS 행만 급행",
    producerIssue: 2099,
    owner: "mobile",
    evidenceTests: [
      "backend/src/test/java/com/easysubway/route/adapter/out/persistence/TimetableSeedLoaderTest.java",
      "docs/2099-qa/item3_express_badge_timetable.png",
      "docs/2099-qa/item5_talkback_dump.xml",
    ],
    guardsNoGo: [],
  },
  {
    id: "E8",
    titleKo: "Route V2 request/network trace에 일반/급행 선택 필드 0건",
    producerIssue: 2099,
    owner: "mobile",
    evidenceTests: [
      "apps/mobile/test/route_search_request_test.dart",
    ],
    guardsNoGo: [],
  },
  {
    id: "E9",
    titleKo: "ITX_CHEONGCHUN/EXPRESS는 ITX-청춘으로 표시, generic 급행 중복 0건",
    producerIssue: 2098,
    owner: "planner",
    evidenceTests: [
      "apps/mobile/test/route_v2_ingress_test.dart::ITX_TIMETABLE_UNAVAILABLE을 SUBWAY로 자동 강등하지 않는다",
    ],
    guardsNoGo: ["itx_shown_as_generic_or_local_badged"],
  },
];

// NO_GO 조건 카탈로그(이슈 본문 7개 + fixture-only fail-closed).
const NO_GO_CONDITIONS = [
  "route_map_local_express_control_present",
  "unknown_pattern_defaulted_to_local",
  "ride_leg_missing_service_metadata",
  "express_skip_stop_boardable",
  "itx_shown_as_generic_or_local_badged",
  "realtime_mismatch_overrides_planned",
  "mixed_rc_or_artifact_identity",
  "fixture_only_evidence",
];

function issueUrl(issue) {
  return `${ISSUE_TRACKER_BASE}/${issue}`;
}

function readIdentity(source) {
  if (!source || typeof source !== "object") return null;
  return source.releaseCandidateIdentity ?? source.rcIdentity ?? null;
}

// 두 identity가 같은 RC를 가리키는지 비교한다. 불일치 필드 목록을 반환한다(빈 배열이면 일치).
function identityMismatchFields(canonical, candidate) {
  const mismatches = [];
  for (const field of RC_IDENTITY_FIELDS) {
    const left = canonical?.[field] ?? null;
    const right = candidate?.[field] ?? null;
    if (left !== right) mismatches.push(field);
  }
  return mismatches;
}

function anchorIncomplete(identity) {
  return RC_IDENTITY_ANCHOR_FIELDS.filter(
    (field) => identity?.[field] === undefined || identity?.[field] === null || identity?.[field] === "",
  );
}

// planner canary itinerary의 모든 RIDE step이 serviceClass/servicePattern을 갖는지 검사한다(NO_GO #3).
// 반환: { rideLegs, missingMetadata, expressSkipBoardable, hasItxExpress }
function inspectPlannerRideMetadata(plannerEvidence) {
  const result = { rideLegs: 0, missingMetadata: false, hasItxExpress: false };
  const itineraries = plannerEvidence?.canaryResult?.plan?.itineraries;
  if (!Array.isArray(itineraries)) {
    // planner evidence가 있는데 itinerary 구조가 없으면 fail-closed.
    return { ...result, missingMetadata: true, structureMissing: true };
  }
  for (const itinerary of itineraries) {
    for (const step of itinerary?.steps ?? []) {
      if (step?.stepType !== "ride") continue;
      result.rideLegs += 1;
      const serviceClass = step?.serviceClass ?? null;
      const servicePattern = step?.servicePattern ?? null;
      if (!serviceClass || !servicePattern) {
        result.missingMetadata = true;
      }
      if (serviceClass === "ITX_CHEONGCHUN" && servicePattern === "EXPRESS") {
        result.hasItxExpress = true;
      }
    }
  }
  return result;
}

function scenarioAttestation(ownerEvidence, scenarioId) {
  const attestations = ownerEvidence?.integrationScenarios;
  if (!attestations || typeof attestations !== "object") return undefined;
  return attestations[scenarioId];
}

// 개별 evidence 입력의 identity·provenance를 canonical과 비교한다.
function evaluateEvidenceInput(name, evidence, canonicalIdentity, allowFixtureProvenance) {
  if (!evidence) return { name, present: false };
  const identity = readIdentity(evidence);
  const mismatchFields = identity ? identityMismatchFields(canonicalIdentity, identity) : RC_IDENTITY_FIELDS;
  const provenance = evidence.provenance ?? null;
  const fixtureOnly = provenance === "fixture" || evidence.fixtureOnly === true;
  const provenanceValid = allowFixtureProvenance ? true : VALID_PROVENANCE.has(provenance);
  return {
    name,
    present: true,
    identity,
    identityMatches: identity !== null && mismatchFields.length === 0,
    mismatchFields,
    provenance,
    fixtureOnly,
    provenanceValid,
    sourceIssue: evidence.sourceIssue ?? null,
    testRunUrl: evidence.testRunUrl ?? null,
  };
}

export function buildRouteIntegrationVerdict(inputs) {
  const {
    rcManifest,
    plannerEvidence = null,
    mobileEvidence = null,
    routeMapEvidence = null,
    timetableEvidence = null,
    generatedAt = new Date().toISOString(),
    allowFixtureProvenance = false,
  } = inputs;

  if (!rcManifest) throw new Error("rcManifest is required");
  const canonicalIdentity = readIdentity(rcManifest);
  if (!canonicalIdentity) throw new Error("rcManifest must expose releaseCandidateIdentity or rcIdentity");

  const evidenceByOwner = {
    planner: plannerEvidence,
    mobile: mobileEvidence,
    routeMap: routeMapEvidence,
    timetable: timetableEvidence,
  };
  const evaluations = Object.fromEntries(
    Object.entries(evidenceByOwner).map(([name, evidence]) => [
      name,
      evaluateEvidenceInput(name, evidence, canonicalIdentity, allowFixtureProvenance),
    ]),
  );

  const plannerRide = plannerEvidence ? inspectPlannerRideMetadata(plannerEvidence) : null;

  // NO_GO 조건 판정. triggered=true면 판정을 NO_GO로 만든다. unresolved=증거 부족으로 GO 확정 불가.
  const noGo = new Map(NO_GO_CONDITIONS.map((id) => [id, { id, triggered: false, unresolved: false, reasons: [] }]));
  const trip = (id, reason) => {
    const entry = noGo.get(id);
    entry.triggered = true;
    entry.reasons.push(reason);
  };
  const unresolved = (id, reason) => {
    const entry = noGo.get(id);
    entry.unresolved = true;
    entry.reasons.push(reason);
  };

  // #7 mixed RC/artifact identity.
  for (const evaluation of Object.values(evaluations)) {
    if (!evaluation.present) continue;
    if (!evaluation.identityMatches) {
      trip(
        "mixed_rc_or_artifact_identity",
        `${evaluation.name} identity mismatch: ${(evaluation.mismatchFields ?? []).join(", ") || "missing identity"}`,
      );
    }
  }
  const canonicalAnchorGaps = anchorIncomplete(canonicalIdentity);
  if (canonicalAnchorGaps.length > 0) {
    trip("mixed_rc_or_artifact_identity", `canonical identity missing anchor fields: ${canonicalAnchorGaps.join(", ")}`);
  }
  // planner artifact identity linkage: canonicalPackSha256이 datapack artifact와 일치해야 한다.
  if (plannerEvidence) {
    const canonicalPackSha256 = plannerEvidence?.plannerIdentity?.canonicalPackSha256 ?? null;
    if (canonicalPackSha256 !== (canonicalIdentity.dataPackArtifactSha256 ?? null)) {
      trip(
        "mixed_rc_or_artifact_identity",
        "planner canonicalPackSha256 does not match RC dataPackArtifactSha256",
      );
    }
  }

  // fixture-only fail-closed.
  for (const evaluation of Object.values(evaluations)) {
    if (!evaluation.present) continue;
    if (evaluation.fixtureOnly && !allowFixtureProvenance) {
      trip("fixture_only_evidence", `${evaluation.name} evidence is fixture-only`);
    } else if (!evaluation.provenanceValid) {
      unresolved(
        "fixture_only_evidence",
        `${evaluation.name} evidence provenance is not one of ${[...VALID_PROVENANCE].join(", ")}`,
      );
    }
  }

  // #3 ride leg가 serviceClass/servicePattern 없이 성공 응답.
  if (plannerEvidence) {
    if (plannerRide.structureMissing) {
      unresolved("ride_leg_missing_service_metadata", "planner evidence has no canary itinerary structure");
    } else if (plannerRide.rideLegs === 0) {
      unresolved("ride_leg_missing_service_metadata", "planner evidence exposes no RIDE legs");
    } else if (plannerRide.missingMetadata) {
      trip("ride_leg_missing_service_metadata", "a planner RIDE leg is missing serviceClass or servicePattern");
    }
  } else {
    unresolved("ride_leg_missing_service_metadata", "planner evidence not provided");
  }

  // scenario matrix 판정.
  const scenarioMatrix = ROUTE_INTEGRATION_SCENARIOS.map((scenario) => {
    const evaluation = evaluations[scenario.owner];
    const reasons = [];
    let result;
    if (!evaluation.present) {
      result = "PENDING";
      reasons.push(`${scenario.owner} evidence not provided`);
    } else if (!evaluation.identityMatches) {
      result = "FAIL";
      reasons.push(`${scenario.owner} evidence identity does not match the RC candidate`);
    } else if (evaluation.fixtureOnly && !allowFixtureProvenance) {
      result = "FAIL";
      reasons.push(`${scenario.owner} evidence is fixture-only`);
    } else if (!evaluation.provenanceValid) {
      result = "PENDING";
      reasons.push(`${scenario.owner} evidence provenance is not a releasable source`);
    } else {
      const attestation = scenarioAttestation(evidenceByOwner[scenario.owner], scenario.id);
      if (attestation === "PASS") {
        result = "PASS";
      } else if (attestation === "FAIL") {
        result = "FAIL";
        reasons.push(`${scenario.owner} evidence attests ${scenario.id} as FAIL`);
      } else {
        result = "PENDING";
        reasons.push(`${scenario.owner} evidence does not attest ${scenario.id}`);
      }
    }

    // 구조적 override: E3는 planner ride metadata 결손 시 FAIL(NO_GO #3와 연동).
    if (scenario.id === "E3" && plannerRide && plannerRide.missingMetadata && result === "PASS") {
      result = "FAIL";
      reasons.push("planner RIDE metadata is incomplete");
    }
    // 구조적 override: E9는 planner canary에 ITX_CHEONGCHUN/EXPRESS ride가 있어야 PASS 유지.
    if (scenario.id === "E9" && plannerRide && !plannerRide.hasItxExpress && result === "PASS") {
      result = "FAIL";
      reasons.push("planner canary has no ITX_CHEONGCHUN EXPRESS RIDE leg");
    }

    // scenario 결과를 연결된 NO_GO 조건으로 전파.
    for (const conditionId of scenario.guardsNoGo) {
      if (result === "FAIL") {
        trip(conditionId, `${scenario.id} failed`);
      } else if (result !== "PASS") {
        unresolved(conditionId, `${scenario.id} is ${result}`);
      }
    }

    return {
      id: scenario.id,
      titleKo: scenario.titleKo,
      producerIssue: scenario.producerIssue,
      producerIssueUrl: issueUrl(scenario.producerIssue),
      owner: scenario.owner,
      evidenceTests: scenario.evidenceTests,
      testRunUrl: evaluation.present ? evaluation.testRunUrl : null,
      guardsNoGo: scenario.guardsNoGo,
      artifactIdentity: evaluation.present ? evaluation.identity : null,
      result,
      reasons,
    };
  });

  // 판정 조건: seed의 unknown pattern default(#2)는 planner evidence의 명시 attestation을 요구한다.
  const seedPatternAttestation = plannerEvidence?.checks?.unknownPatternDefaultedToLocal;
  if (!plannerEvidence) {
    unresolved("unknown_pattern_defaulted_to_local", "planner evidence not provided");
  } else if (seedPatternAttestation === true) {
    trip("unknown_pattern_defaulted_to_local", "planner seed defaults unknown pattern to LOCAL");
  } else if (seedPatternAttestation !== false) {
    unresolved("unknown_pattern_defaulted_to_local", "planner evidence does not attest seed pattern handling");
  }

  const noGoConditions = NO_GO_CONDITIONS.map((id) => noGo.get(id));
  const blockers = [];
  for (const condition of noGoConditions) {
    if (condition.triggered) {
      blockers.push({ id: `no_go_${condition.id}`, severity: "P0", reasons: condition.reasons });
    } else if (condition.unresolved) {
      blockers.push({ id: `unresolved_${condition.id}`, severity: "P0", reasons: condition.reasons });
    }
  }
  for (const scenario of scenarioMatrix) {
    if (scenario.result !== "PASS") {
      blockers.push({
        id: `scenario_${scenario.id.toLowerCase()}_${scenario.result.toLowerCase()}`,
        severity: "P0",
        reasons: scenario.reasons,
      });
    }
  }

  const decision = blockers.length === 0 ? "GO" : "NO_GO";

  const verdict = {
    schemaVersion: 1,
    releaseGate: "route-integration-verdict",
    issue: 1414,
    producerVersion: 1,
    applicationId: "easysubway",
    androidApplicationId: "com.easysubway.app",
    generatedAt,
    apiContract: {
      catalogId: ROUTE_SEARCH_CATALOG_ID,
      contractVersion: ROUTE_SEARCH_CONTRACT_VERSION,
    },
    releaseCandidateIdentity: canonicalIdentity,
    rcIdentity: canonicalIdentity,
    evidenceInputs: Object.values(evaluations).map((evaluation) => ({
      name: evaluation.name,
      present: evaluation.present,
      sourceIssue: evaluation.present ? evaluation.sourceIssue : null,
      identityMatches: evaluation.present ? evaluation.identityMatches : false,
      mismatchFields: evaluation.present ? evaluation.mismatchFields ?? [] : [],
      provenance: evaluation.present ? evaluation.provenance : null,
      fixtureOnly: evaluation.present ? evaluation.fixtureOnly : false,
    })),
    artifactIdentityLinkage: {
      backendImageDigest: canonicalIdentity.backendImageDigest ?? null,
      backendArtifactSha256: canonicalIdentity.backendArtifactSha256 ?? null,
      dataPackManifestSha256: canonicalIdentity.dataPackManifestSha256 ?? null,
      topologyPackSha256: canonicalIdentity.dataPackArtifactSha256 ?? null,
      timetableSnapshotSha256: plannerEvidence?.plannerIdentity?.timetableSnapshotSha256 ?? null,
      canonicalStationSetSha256: plannerEvidence?.plannerIdentity?.canonicalStationSetSha256 ?? null,
      sourceLineageSha256: plannerEvidence?.plannerIdentity?.sourceLineageSha256 ?? null,
    },
    scenarioMatrix,
    noGoConditions: noGoConditions.map((condition) => ({
      id: condition.id,
      triggered: condition.triggered,
      unresolved: condition.unresolved,
      reasons: condition.reasons,
    })),
    blockers,
    decision,
    readiness: {
      status: decision,
      gateStatus: decision === "GO" ? "SATISFIED" : "BLOCKED_ROUTE_INTEGRATION",
    },
  };

  verdict.summaryArtifactDigest = createHash("sha256")
    .update(JSON.stringify(verdict))
    .digest("hex");

  return verdict;
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const name = argv[index];
    if (!name?.startsWith("--")) throw new Error(`invalid argument: ${name}`);
    const key = name.slice(2);
    const next = argv[index + 1];
    if (key === "allow-fixture-provenance") {
      args.set(key, "true");
      continue;
    }
    if (next === undefined || next.startsWith("--")) throw new Error(`missing value for --${key}`);
    args.set(key, next);
    index += 1;
  }
  return args;
}

function readJsonArg(args, key, { required = false } = {}) {
  const value = args.get(key);
  if (!value) {
    if (required) throw new Error(`--${key} is required`);
    return null;
  }
  const resolved = path.resolve(process.cwd(), value);
  if (!existsSync(resolved)) {
    if (required) throw new Error(`--${key} file does not exist: ${value}`);
    return null;
  }
  return JSON.parse(readFileSync(resolved, "utf8"));
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const output = args.get("output");
  if (!output) throw new Error("--output is required");
  const verdict = buildRouteIntegrationVerdict({
    rcManifest: readJsonArg(args, "rc-manifest", { required: true }),
    plannerEvidence: readJsonArg(args, "planner-evidence"),
    mobileEvidence: readJsonArg(args, "mobile-evidence"),
    routeMapEvidence: readJsonArg(args, "route-map-evidence"),
    timetableEvidence: readJsonArg(args, "timetable-evidence"),
    generatedAt: args.get("now") ?? new Date().toISOString(),
    allowFixtureProvenance: args.get("allow-fixture-provenance") === "true",
  });
  const outputPath = path.resolve(process.cwd(), output);
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(verdict, null, 2)}\n`);
  console.log(`route integration verdict: ${verdict.decision}`);
  if (args.get("fail-on-no-go") === "true" && verdict.decision !== "GO") {
    process.exitCode = 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
