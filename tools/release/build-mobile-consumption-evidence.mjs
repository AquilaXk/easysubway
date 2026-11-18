#!/usr/bin/env node

// #1414 route/datapack 통합 판정의 #2099 fragment. Mobile이 실제로 소비한 RC identity와
// E1(노선도 control 부재)/E7(mixed timetable 급행 배지)/E8(request 필드 0건)/E9(ITX 표시) 시나리오
// 근거를 tracked source·test 참조로 결합한다. UI 렌더링/길찾기 로직을 재구현하지 않고, 이미
// tracked된 위젯 test 이름과 request 직렬화 소스의 존재·내용만 정적으로 검증한다.

import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { runCandidateContextEvidenceCli } from "./lib/candidate-context-evidence-cli.mjs";

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

// E9: ITX-청춘 서비스 식별은 datapack 노선명이 아니라 전용 배지로 구현되는 설계다
// (#1414 fix/1414-e9-itx-service-display, 551a57ab에서 제안됨). 이 브랜치가 아직 병합되지
// 않았으면 아래 마커가 없어 fail-closed FAIL로 남는 것이 정상이다. fix 병합 후 PASS가
// 되려면 다음이 모두 성립해야 한다:
// - service_pattern_badge.dart에 `ServicePatternBadge.itxCheongchun` 생성자(key
//   `servicePatternItxCheongchunBadge`)가 존재해야 한다.
// - route_search.dart의 `RouteSearchStep.isItxCheongchun`(serviceClass=='ITX_CHEONGCHUN')
//   getter가 ride leg 렌더 조건(`step.isItxCheongchun`)에 실제로 연결돼야 한다.
// - "ITX-청춘 표시 1회 + generic 급행 배지 0건 + TalkBack semantics 1회"를 검증하는
//   widget test가 존재해야 한다.
// 소스·test 중 하나라도 없으면 fail closed FAIL이다.
const E9_BADGE_SOURCE_FILE = "apps/mobile/lib/features/stations/presentation/service_pattern_badge.dart";
// 각 마커는 "선언 prefix + 핵심 토큰" 결합으로 주석·설명 텍스트만으로는 우연히 매칭되지 않게 한다
// (완전한 Dart 파서는 과도하므로 만들지 않는다). Key(...)는 실제 소스가 여러 줄로 감싸므로
// 정규식으로 개행을 허용한다.
const E9_BADGE_SOURCE_MARKERS = [
  /const\s+ServicePatternBadge\.itxCheongchun\(/,
  /Key\(\s*'servicePatternItxCheongchunBadge'/,
];
const E9_STEP_SOURCE_FILE = "apps/mobile/lib/route_search.dart";
const E9_STEP_SOURCE_MARKERS = [
  "bool get isItxCheongchun => serviceClass == 'ITX_CHEONGCHUN'",
  "step.stepType == 'ride' && step.isItxCheongchun",
  "ServicePatternBadge.itxCheongchun(",
];
const E9_WIDGET_TEST = {
  testFile: "apps/mobile/test/widget_test.dart",
  testNames: ["길찾기 ITX-청춘 승차 leg은 선택 UI 없이 ITX-청춘 서비스 식별을 표시한다"],
};

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// //, /* */ 주석을 제거해 "주석에만 선언 문구가 있는" 오탐(예: TODO 주석에 실제 호출
// syntax를 그대로 적어 둔 경우)을 막는다. 문자열 리터럴 안의 `//`(URL 등)는 못 걸러내는
// 단순 근사치이지만, 이 저장소가 검사하는 파일들의 관련 문자열에는 `//`가 없어 실무적으로
// 충분하다 — 완전한 Dart 토크나이저/파서는 만들지 않는다.
function stripDartComments(source) {
  return source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "");
}

function matchesMarker(source, marker) {
  return marker instanceof RegExp ? marker.test(source) : source.includes(marker);
}

function markerLabel(marker) {
  return marker instanceof RegExp ? marker.source : marker;
}

// repoRoot/file을 utf8로 읽어 markers 전부가 (주석 제외) 원문에 등장하는지 확인한다.
// route_search.dart는 바이너리 오인 바이트가 있어 grep -a가 필요하므로(coordinator 지적),
// grep 대신 Node readFileSync로 직접 검사해 이 문제를 피한다.
function checkSourceMarkers(repoRoot, file, markers) {
  const filePath = path.join(repoRoot, file);
  if (!existsSync(filePath)) {
    return { pass: false, missing: markers.map(markerLabel), filePath: file };
  }
  const source = stripDartComments(readFileSync(filePath, "utf8"));
  const missing = markers.filter((marker) => !matchesMarker(source, marker)).map(markerLabel);
  return { pass: missing.length === 0, missing, filePath: file };
}

function buildE9MobileAttestation(repoRoot) {
  const badgeSource = checkSourceMarkers(repoRoot, E9_BADGE_SOURCE_FILE, E9_BADGE_SOURCE_MARKERS);
  const stepSource = checkSourceMarkers(repoRoot, E9_STEP_SOURCE_FILE, E9_STEP_SOURCE_MARKERS);
  const widgetTest = checkTestNamesExist(repoRoot, E9_WIDGET_TEST.testFile, E9_WIDGET_TEST.testNames);
  // 세 조건 모두 필요하다: (1) 배지 위젯 소스, (2) ride leg 렌더 연결, (3) 이를 검증하는
  // widget test. 하나라도 없으면 "ITX-청춘 표시"가 실제로 있다고 단정하지 않는다.
  const pass = badgeSource.pass && stepSource.pass && widgetTest.pass;
  const reasonKo = pass
    ? `ITX-청춘 서비스 식별 배지가 소스에 존재하고(${E9_BADGE_SOURCE_FILE}) `
      + `ride leg 렌더에 연결되며(${E9_STEP_SOURCE_FILE}), ${E9_WIDGET_TEST.testFile}의 `
      + `"${E9_WIDGET_TEST.testNames[0]}" 테스트가 표시 1회·급행 0건을 검증한다.`
    : `ITX-청춘 서비스 식별 배지 구현이 불완전하다: `
      + `${E9_BADGE_SOURCE_FILE} 누락 마커=${JSON.stringify(badgeSource.missing)}, `
      + `${E9_STEP_SOURCE_FILE} 누락 마커=${JSON.stringify(stepSource.missing)}, `
      + `${E9_WIDGET_TEST.testFile} 누락 test=${JSON.stringify(widgetTest.missing)}.`;
  return {
    result: pass ? "PASS" : "FAIL",
    reasonKo,
    checkedFiles: [E9_BADGE_SOURCE_FILE, E9_STEP_SOURCE_FILE, E9_WIDGET_TEST.testFile],
    badgeSource,
    stepSource,
    widgetTest,
  };
}

// test 이름이 실제 test(...)/testWidgets(...) 선언에 쓰였는지 확인한다. 단순
// `source.includes("'name'")`는 주석·설명 문구에 같은 문자열이 있어도 오탐 PASS를
// 낸다 — `test(`/`testWidgets(` 선언 prefix와 결합해야만 매칭되도록 강화한다(완전한
// Dart 파서는 과도하므로 만들지 않는다).
function checkTestNamesExist(repoRoot, testFile, testNames) {
  const filePath = path.join(repoRoot, testFile);
  if (!existsSync(filePath)) {
    return { pass: false, missing: testNames, filePath: testFile };
  }
  const source = stripDartComments(readFileSync(filePath, "utf8"));
  const missing = testNames.filter((name) => {
    const declarationPattern = new RegExp(`\\btest(Widgets)?\\(\\s*'${escapeRegExp(name)}'`);
    return !declarationPattern.test(source);
  });
  return { pass: missing.length === 0, missing, filePath: testFile };
}

// E8 소스 레벨 검증: RouteSearchRequest 클래스 본문(다음 top-level class 선언 전까지)에
// FORBIDDEN_REQUEST_FIELDS 중 어느 것도 quoted map key로 등장하지 않는지 확인한다. Dart는
// single/double quote 문자열을 모두 허용하므로("expressOnly"도 유효한 map key literal)
// 양쪽 quote 스타일을 모두 검사해야 quote 스타일만 바꿔 우회하는 경우를 막는다.
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
  const found = FORBIDDEN_REQUEST_FIELDS.filter(
    (field) => classBody.includes(`'${field}'`) || classBody.includes(`"${field}"`),
  );
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
        badgeSource: e9.badgeSource,
        stepSource: e9.stepSource,
        widgetTest: e9.widgetTest,
      },
    },
    checks: scenarioChecks,
  };
}

runCandidateContextEvidenceCli(import.meta.url, buildMobileConsumptionEvidence);
