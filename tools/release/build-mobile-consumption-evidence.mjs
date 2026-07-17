#!/usr/bin/env node

// #1414 route/datapack 통합 판정의 #2099 fragment. Mobile이 실제로 소비한 RC identity와
// E1(노선도 control 부재)/E7(mixed timetable 급행 배지)/E8(request 필드 0건)/E9(ITX 표시) 시나리오
// 근거를 tracked source·test 참조로 결합한다. UI 렌더링/길찾기 로직을 재구현하지 않고, 이미
// tracked된 위젯 test 이름과 request 직렬화 소스의 존재·내용만 정적으로 검증한다.

import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";
import { DatabaseSync } from "node:sqlite";

const API_CATALOG_ID = "internal:POST:/api/v2/routes/search:com.easysubway.route.adapter.in.web.RouteSearchController#searchRouteV2";

// E8: 요청 serialization에 있으면 안 되는 일반/급행 선택 필드 이름.
const FORBIDDEN_REQUEST_FIELDS = [
  "servicePattern",
  "serviceClass",
  "expressOnly",
  "localOnly",
  "expressPreference",
  "transportPattern",
  "routePreference",
];

const MOBILE_SCENARIO_EVIDENCE = {
  E1: {
    testFile: "apps/mobile/test/widget_test.dart",
    testNames: ["노선도 첫 화면은 하단 광고 위에 지도 조작을 유지한다"],
    localEvidencePaths: [
      "docs/2099-qa/item4_routemap_no_express_toggle.png",
      "docs/2099-qa/item5_talkback_dump.xml",
    ],
  },
  E7: {
    testFile: "apps/mobile/test/widget_test.dart",
    testNames: [
      "급행 운행 정보는 선택 UI 없이 시간표와 길찾기에 표시된다",
      "역 시간표 화면은 일반·급행을 한 목록에 시각순으로 표시하고 급행 행에만 배지를 단다",
    ],
    localEvidencePaths: [
      "docs/2099-qa/item3_express_badge_timetable.png",
      "docs/2099-qa/item5_talkback_dump.xml",
    ],
  },
  E8: {
    testFile: "apps/mobile/test/route_search_request_test.dart",
    testNames: [
      "toV2Json은 mobilityPreset이 있으면 body에 싣고 mobilityType도 함께 보낸다",
      "toV2Json은 mobilityPreset이 없으면 키를 넣지 않는다",
    ],
    requestSourceFile: "apps/mobile/lib/route_search.dart",
    requestClassMarker: "class RouteSearchRequest {",
  },
};

// E9: online V2 leg 라벨은 하드코딩이 아니라 데이터 주도다. 코드 경로 실측:
// RouteSearchV2Leg.fromJson(serviceClass/servicePattern 파싱, route_search.dart:1032)
// -> RouteSearchStep.fromV2(lineName은 leg.lineId placeholder, route_search.dart:2097)
// -> OnlineFirstRouteSearchRepository.searchRoute(local_route_repository.dart:1049)가
// localRepository.resolveDisplayLabels(onlineResult) 호출(local_route_repository.dart:1057)
// -> resolveDisplayLabels 확장이 catalog.lineName(step.lineId)로 lineName을 실제 채운다
// (local_route_repository.dart:1093, lineName lookup은 2023행 catalog.lineName).
// 급행 배지는 serviceClass=='SUBWAY'만 대상이라(service_pattern_badge.dart의 isExpress,
// route_search.dart:6083 주석이 "ITX-청춘·LOCAL은 배지 없음"을 명시) ITX leg 식별은 이
// line name 하나에 전적으로 의존한다.
//
// 이 line name의 실제 값은 하드코딩이 아니라 번들 datapack(lines.name_ko)에서 나오므로,
// PASS/FAIL을 정적 문자열이 아니라 tracked datapack 실측으로 판정한다(checkItxLineDisplayIdentity).
// generic 급행 배지 미부착은 route_search_test.dart:1586(#2099 WP2)로 이미 검증되지만, 그것만으로는
// "ITX-청춘 표시"를 충족하지 않는다 — line name 식별과 배지 부재를 모두 요구한다.
const ITX_CANONICAL_LINE_ID = "line-54a7b980b7c3"; // korail-itx-cheongchun-station-sequence-20260713.json의 canonicalLineId
const BUNDLED_DATAPACK_ASSET = "apps/mobile/assets/datapacks/capital.sqlite.gz";
const ITX_DISPLAY_CHECK_FILES = [
  "apps/mobile/lib/route_search.dart",
  "apps/mobile/lib/features/routes/data/local_route_repository.dart",
  "apps/mobile/lib/features/stations/presentation/service_pattern_badge.dart",
];
// 급행 배지가 SUBWAY/EXPRESS에만 붙고 ITX_CHEONGCHUN에는 generic 배지를 만들지 않음을
// 검증하는 실존 unit test(route_search_test.dart:1586, #2099 WP2).
const E9_NO_GENERIC_BADGE_TEST = {
  testFile: "apps/mobile/test/route_search_test.dart",
  testNames: ["RIDE ITX_CHEONGCHUN/EXPRESS leg은 generic 급행 배지를 만들지 않는다"],
};

// 번들 production datapack의 lines.name_ko를 직접 질의해 online ITX leg이 실제로
// "ITX-청춘"으로 식별되는지 실측한다(문자열 comment가 아니라 tracked 산출물 재질의).
function checkItxLineDisplayIdentity(repoRoot) {
  const assetPath = path.join(repoRoot, BUNDLED_DATAPACK_ASSET);
  if (!existsSync(assetPath)) {
    return { pass: false, lineId: ITX_CANONICAL_LINE_ID, lineNameKo: null, assetPath: BUNDLED_DATAPACK_ASSET };
  }
  const sqliteBytes = gunzipSync(readFileSync(assetPath));
  const workDir = mkdtempSync(path.join(tmpdir(), "easysubway-mobile-evidence-datapack-"));
  const sqlitePath = path.join(workDir, "capital.sqlite");
  writeFileSync(sqlitePath, sqliteBytes);
  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  try {
    const row = database.prepare("SELECT name_ko FROM lines WHERE id = ?").get(ITX_CANONICAL_LINE_ID);
    const lineNameKo = typeof row?.name_ko === "string" ? row.name_ko : null;
    const identifiesAsItx = lineNameKo !== null
      && (lineNameKo.includes("ITX") || lineNameKo.includes("청춘"));
    return { pass: identifiesAsItx, lineId: ITX_CANONICAL_LINE_ID, lineNameKo, assetPath: BUNDLED_DATAPACK_ASSET };
  } finally {
    database.close();
    rmSync(workDir, { recursive: true, force: true });
  }
}

function buildE9MobileAttestation(repoRoot) {
  const lineDisplay = checkItxLineDisplayIdentity(repoRoot);
  const noGenericBadge = checkTestNamesExist(
    repoRoot,
    E9_NO_GENERIC_BADGE_TEST.testFile,
    E9_NO_GENERIC_BADGE_TEST.testNames,
  );
  // 두 조건 모두 필요하다: (1) online ITX leg의 line name이 실제로 ITX-청춘을 식별하고,
  // (2) generic 급행 배지가 붙지 않음을 실존 test가 지킨다. (1)이 false면 (2)만으로는
  // "ITX-청춘으로 표시"를 충족하지 못한다 — 무표시와 무배지를 혼동하지 않는다.
  const pass = lineDisplay.pass && noGenericBadge.pass;
  const reasonKo = lineDisplay.pass
    ? `online ITX leg은 catalog 기반 line name으로 ITX-청춘으로 식별된다(${BUNDLED_DATAPACK_ASSET}의 `
      + `lines.name_ko='${lineDisplay.lineNameKo}'), generic 급행 배지 미부착은 `
      + `${E9_NO_GENERIC_BADGE_TEST.testFile}로 검증됨`
    : `online ITX leg의 line name은 catalog 기반이지만(하드코딩 아님) ITX-청춘을 식별하지 않는다: `
      + `${BUNDLED_DATAPACK_ASSET}의 lines.id='${lineDisplay.lineId}' name_ko='${lineDisplay.lineNameKo}'. `
      + `serviceClass=='SUBWAY'만 급행 배지 대상이라(service_pattern_badge.dart, route_search.dart:6083 `
      + `주석 "ITX-청춘·LOCAL은 배지 없음") ITX leg은 이 line name 외에 보조 표시가 없다 `
      + `(generic 급행 배지 미부착은 검증되지만 그것만으로 "ITX-청춘 표시"를 충족하지 않음).`;
  return {
    result: pass ? "PASS" : "FAIL",
    reasonKo,
    checkedFiles: [...ITX_DISPLAY_CHECK_FILES, E9_NO_GENERIC_BADGE_TEST.testFile],
    lineDisplay,
    noGenericBadge,
  };
}

function checkTestNamesExist(repoRoot, testFile, testNames) {
  const filePath = path.join(repoRoot, testFile);
  if (!existsSync(filePath)) {
    return { pass: false, missing: testNames, filePath: testFile };
  }
  const source = readFileSync(filePath, "utf8");
  const missing = testNames.filter((name) => !source.includes(`'${name}'`));
  return { pass: missing.length === 0, missing, filePath: testFile };
}

// E8 소스 레벨 검증: RouteSearchRequest 클래스 본문(다음 top-level class 선언 전까지)에
// FORBIDDEN_REQUEST_FIELDS 중 어느 것도 quoted map key로 등장하지 않는지 확인한다.
function checkRequestFieldAbsence(repoRoot, requestSourceFile, requestClassMarker) {
  const filePath = path.join(repoRoot, requestSourceFile);
  if (!existsSync(filePath)) {
    return { pass: false, missing: ["<file-not-found>"], filePath: requestSourceFile };
  }
  const source = readFileSync(filePath, "utf8");
  const classStart = source.indexOf(requestClassMarker);
  if (classStart === -1) {
    return { pass: false, missing: ["<class-not-found>"], filePath: requestSourceFile };
  }
  const nextClassStart = source.indexOf("\nclass ", classStart + requestClassMarker.length);
  const classBody = nextClassStart === -1 ? source.slice(classStart) : source.slice(classStart, nextClassStart);
  const found = FORBIDDEN_REQUEST_FIELDS.filter((field) => classBody.includes(`'${field}'`));
  return { pass: found.length === 0, found, filePath: requestSourceFile };
}

export function buildMobileConsumptionEvidence({
  candidate,
  repoRoot = process.cwd(),
  generatedAt = new Date().toISOString(),
  provenance = "final-candidate",
}) {
  const identity = candidate?.releaseCandidateIdentity;
  if (candidate?.phase !== "CANDIDATE" || candidate?.issue !== 2056 || !identity) {
    throw new Error("mobile consumption evidence requires the #2056 CANDIDATE context");
  }

  const e1 = checkTestNamesExist(repoRoot, MOBILE_SCENARIO_EVIDENCE.E1.testFile, MOBILE_SCENARIO_EVIDENCE.E1.testNames);
  const e7 = checkTestNamesExist(repoRoot, MOBILE_SCENARIO_EVIDENCE.E7.testFile, MOBILE_SCENARIO_EVIDENCE.E7.testNames);
  const e8Tests = checkTestNamesExist(repoRoot, MOBILE_SCENARIO_EVIDENCE.E8.testFile, MOBILE_SCENARIO_EVIDENCE.E8.testNames);
  const e8Fields = checkRequestFieldAbsence(
    repoRoot,
    MOBILE_SCENARIO_EVIDENCE.E8.requestSourceFile,
    MOBILE_SCENARIO_EVIDENCE.E8.requestClassMarker,
  );
  const e8Pass = e8Tests.pass && e8Fields.pass;
  const e9 = buildE9MobileAttestation(repoRoot);

  const scenarioChecks = {
    E1: e1,
    E7: e7,
    E8: { pass: e8Pass, tests: e8Tests, requestFields: e8Fields },
    E9: e9,
  };

  const integrationScenarios = {
    E1: e1.pass ? "PASS" : "FAIL",
    E7: e7.pass ? "PASS" : "FAIL",
    E8: e8Pass ? "PASS" : "FAIL",
    E9: e9.result,
  };

  const coreScenariosSatisfied = e1.pass && e7.pass && e8Pass;

  return {
    schemaVersion: 1,
    artifactKind: "route-v2-mobile-consumption-evidence",
    sourceIssue: 2099,
    consumerIssue: 2056,
    generatedAt,
    provenance,
    status: coreScenariosSatisfied ? "SATISFIED" : "BLOCKED_MOBILE_SCENARIO_EVIDENCE",
    releaseCandidateIdentity: identity,
    apiContract: { catalogId: API_CATALOG_ID, contractVersion: "ROUTE_SEARCH_V2" },
    integrationScenarios,
    scenarioEvidence: {
      E1: {
        testFile: MOBILE_SCENARIO_EVIDENCE.E1.testFile,
        testNames: MOBILE_SCENARIO_EVIDENCE.E1.testNames,
        localEvidencePaths: MOBILE_SCENARIO_EVIDENCE.E1.localEvidencePaths,
        result: integrationScenarios.E1,
      },
      E7: {
        testFile: MOBILE_SCENARIO_EVIDENCE.E7.testFile,
        testNames: MOBILE_SCENARIO_EVIDENCE.E7.testNames,
        localEvidencePaths: MOBILE_SCENARIO_EVIDENCE.E7.localEvidencePaths,
        result: integrationScenarios.E7,
      },
      E8: {
        testFile: MOBILE_SCENARIO_EVIDENCE.E8.testFile,
        testNames: MOBILE_SCENARIO_EVIDENCE.E8.testNames,
        requestSourceFile: MOBILE_SCENARIO_EVIDENCE.E8.requestSourceFile,
        forbiddenFieldsChecked: FORBIDDEN_REQUEST_FIELDS,
        forbiddenFieldsFound: e8Fields.found ?? [],
        result: integrationScenarios.E8,
      },
      E9: {
        result: integrationScenarios.E9,
        reasonKo: e9.reasonKo,
        checkedFiles: e9.checkedFiles,
        lineDisplay: e9.lineDisplay,
        noGenericBadge: e9.noGenericBadge,
      },
    },
    checks: scenarioChecks,
  };
}

function argument(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index < 0 ? null : process.argv[index + 1];
}

const entry = process.argv[1] ? path.resolve(process.argv[1]) : null;
if (entry === fileURLToPath(import.meta.url)) {
  const candidatePath = argument("candidate-context");
  const outputPath = argument("output");
  if (!candidatePath || !outputPath) {
    throw new Error("--candidate-context and --output are required");
  }
  const repoRoot = argument("repo-root") ? path.resolve(argument("repo-root")) : process.cwd();
  const provenance = argument("provenance") ?? "final-candidate";
  const evidence = buildMobileConsumptionEvidence({
    candidate: JSON.parse(readFileSync(candidatePath, "utf8")),
    repoRoot,
    provenance,
  });
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`);
}
