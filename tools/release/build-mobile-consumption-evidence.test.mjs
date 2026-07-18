import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { buildMobileConsumptionEvidence } from "./build-mobile-consumption-evidence.mjs";

const identity = {
  gitSha: "1".repeat(40),
  appVersionName: "1.0.4",
  versionCode: "10005",
};

const ITX_WIDGET_TEST_NAME = "길찾기 ITX-청춘 승차 leg은 선택 UI 없이 ITX-청춘 서비스 식별을 표시한다";

// #1414 fix/1414-e9-itx-service-display(551a57ab)가 실제로 추가한 소스 형태를 재현한 fixture.
const ITX_BADGE_SOURCE_FULL = `
class ServicePatternBadge extends StatelessWidget {
  const ServicePatternBadge.itxCheongchun({super.key})
    : departure = null,
      _forcedLabel = 'ITX-청춘',
      _badgeKey = _itxCheongchunBadgeKey;

  static const Key _itxCheongchunBadgeKey = Key(
    'servicePatternItxCheongchunBadge',
  );
}
`;

const ITX_STEP_SOURCE_FULL = `
  bool get isItxCheongchun => serviceClass == 'ITX_CHEONGCHUN';

  Widget _buildItxBadge(RouteSearchStep step) {
    if (step.stepType == 'ride' && step.isItxCheongchun) {
      return const ServicePatternBadge.itxCheongchun();
    }
    return const SizedBox.shrink();
  }
`;

function candidate(overrides = {}) {
  return { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity, ...overrides };
}

async function fixtureRepoRoot({
  widgetTestNames = [
    "노선도 첫 화면은 하단 광고 위에 지도 조작을 유지한다",
    "급행 운행 정보는 선택 UI 없이 시간표와 길찾기에 표시된다",
    "역 시간표 화면은 일반·급행을 한 목록에 시각순으로 표시하고 급행 행에만 배지를 단다",
  ],
  requestTestNames = [
    "toV2Json은 mobilityPreset이 있으면 body에 싣고 mobilityType도 함께 보낸다",
    "toV2Json은 mobilityPreset이 없으면 키를 넣지 않는다",
  ],
  requestClassBody = "class RouteSearchRequest {\n  Map<String, Object?> toV2Json() => {};\n}\n",
  itxStepSource = "",
  itxBadgeSource = "",
  itxWidgetTestNames = [],
} = {}) {
  const root = await mkdtemp(path.join(tmpdir(), "easysubway-mobile-evidence-"));
  await mkdir(path.join(root, "apps/mobile/test"), { recursive: true });
  await mkdir(path.join(root, "apps/mobile/lib/features/stations/presentation"), { recursive: true });
  await writeFile(
    path.join(root, "apps/mobile/test/widget_test.dart"),
    [...widgetTestNames, ...itxWidgetTestNames]
      .map((name) => `testWidgets('${name}', (tester) async {});\n`)
      .join(""),
  );
  await writeFile(
    path.join(root, "apps/mobile/test/route_search_request_test.dart"),
    requestTestNames.map((name) => `test('${name}', () {});\n`).join(""),
  );
  await writeFile(
    path.join(root, "apps/mobile/lib/route_search.dart"),
    requestClassBody + itxStepSource,
  );
  await writeFile(
    path.join(root, "apps/mobile/lib/features/stations/presentation/service_pattern_badge.dart"),
    itxBadgeSource,
  );
  return root;
}

test("E1/E7/E8 tracked test·source가 모두 있으면 SATISFIED와 PASS matrix를 산출한다(E9는 ITX 배지 미구현 시 FAIL)", async () => {
  const repoRoot = await fixtureRepoRoot();
  const evidence = buildMobileConsumptionEvidence({
    candidate: candidate(),
    repoRoot,
    generatedAt: "2026-07-18T00:00:00.000Z",
  });

  assert.equal(evidence.schemaVersion, 1);
  assert.equal(evidence.artifactKind, "route-v2-mobile-consumption-evidence");
  assert.equal(evidence.sourceIssue, 2099);
  assert.equal(evidence.status, "SATISFIED");
  assert.deepEqual(evidence.releaseCandidateIdentity, identity);
  assert.deepEqual(evidence.integrationScenarios, { E1: "PASS", E7: "PASS", E8: "PASS", E9: "FAIL" });
  assert.equal(evidence.provenance, "final-candidate");
});

test("E9는 배지 소스·ride leg 연결·widget test가 모두 있으면 PASS한다", async () => {
  const repoRoot = await fixtureRepoRoot({
    itxBadgeSource: ITX_BADGE_SOURCE_FULL,
    itxStepSource: ITX_STEP_SOURCE_FULL,
    itxWidgetTestNames: [ITX_WIDGET_TEST_NAME],
  });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E9, "PASS");
  assert.equal(evidence.scenarioEvidence.E9.badgeSource.pass, true);
  assert.equal(evidence.scenarioEvidence.E9.stepSource.pass, true);
  assert.equal(evidence.scenarioEvidence.E9.widgetTest.pass, true);
});

test("E9는 배지 소스가 없으면 fail closed FAIL한다(getter·widget test만 있어도)", async () => {
  const repoRoot = await fixtureRepoRoot({
    itxStepSource: ITX_STEP_SOURCE_FULL,
    itxWidgetTestNames: [ITX_WIDGET_TEST_NAME],
  });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E9, "FAIL");
  assert.equal(evidence.scenarioEvidence.E9.badgeSource.pass, false);
  assert.ok(evidence.scenarioEvidence.E9.badgeSource.missing.length > 0);
});

test("E9는 ride leg 렌더 연결이 없으면 fail closed FAIL한다(배지·getter만 있어도)", async () => {
  const repoRoot = await fixtureRepoRoot({
    itxBadgeSource: ITX_BADGE_SOURCE_FULL,
    itxStepSource: "\n  bool get isItxCheongchun => serviceClass == 'ITX_CHEONGCHUN';\n",
    itxWidgetTestNames: [ITX_WIDGET_TEST_NAME],
  });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E9, "FAIL");
  assert.equal(evidence.scenarioEvidence.E9.stepSource.pass, false);
  assert.ok(
    evidence.scenarioEvidence.E9.stepSource.missing.includes(
      "step.stepType == 'ride' && step.isItxCheongchun",
    ),
  );
});

test("E9는 소스가 모두 있어도 widget test가 없으면 fail closed FAIL한다", async () => {
  const repoRoot = await fixtureRepoRoot({
    itxBadgeSource: ITX_BADGE_SOURCE_FULL,
    itxStepSource: ITX_STEP_SOURCE_FULL,
  });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E9, "FAIL");
  assert.equal(evidence.scenarioEvidence.E9.widgetTest.pass, false);
});

test("E1/E7 test 이름이 tracked 파일에 없으면 FAIL로 fail closed한다", async () => {
  const repoRoot = await fixtureRepoRoot({ widgetTestNames: ["다른 무관한 테스트"] });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E1, "FAIL");
  assert.equal(evidence.integrationScenarios.E7, "FAIL");
  assert.equal(evidence.status, "BLOCKED_MOBILE_SCENARIO_EVIDENCE");
});

test("test 이름이 testWidgets(...) 선언이 아니라 주석에만 있으면 FAIL로 fail closed한다(오탐 회귀 가드)", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "easysubway-mobile-evidence-"));
  await mkdir(path.join(root, "apps/mobile/test"), { recursive: true });
  await mkdir(path.join(root, "apps/mobile/lib/features/stations/presentation"), { recursive: true });
  // 실제 testWidgets() 호출이 아니라 코멘트에만 테스트명 문자열이 등장한다 —
  // 예전 단순 substring 매칭이었다면 이 상태에서도 오탐 PASS했을 것이다.
  await writeFile(
    path.join(root, "apps/mobile/test/widget_test.dart"),
    "// TODO: add testWidgets('노선도 첫 화면은 하단 광고 위에 지도 조작을 유지한다', ...) later\n",
  );
  await writeFile(path.join(root, "apps/mobile/test/route_search_request_test.dart"), "");
  await writeFile(path.join(root, "apps/mobile/lib/route_search.dart"), "class RouteSearchRequest {}\n");
  await writeFile(path.join(root, "apps/mobile/lib/features/stations/presentation/service_pattern_badge.dart"), "");

  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot: root });

  assert.equal(evidence.integrationScenarios.E1, "FAIL");
  assert.ok(evidence.scenarioEvidence.E1.testNames.length > 0);
});

test("E9 배지 마커가 주석에만 있으면 FAIL로 fail closed한다(오탐 회귀 가드)", async () => {
  const repoRoot = await fixtureRepoRoot({
    // 실제 생성자 선언이 아니라 설명 주석에만 문자열이 등장한다.
    itxBadgeSource: "// ServicePatternBadge.itxCheongchun( 생성자를 여기에 추가할 예정\n"
      + "// key: 'servicePatternItxCheongchunBadge'\n",
    itxStepSource: ITX_STEP_SOURCE_FULL,
    itxWidgetTestNames: [ITX_WIDGET_TEST_NAME],
  });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E9, "FAIL");
  assert.equal(evidence.scenarioEvidence.E9.badgeSource.pass, false);
});

test("E8은 request 직렬화에 servicePattern/expressOnly 등 금지 필드가 있으면 FAIL한다", async () => {
  const repoRoot = await fixtureRepoRoot({
    requestClassBody: "class RouteSearchRequest {\n  Map<String, Object?> toV2Json() => {'servicePattern': 'EXPRESS'};\n}\n",
  });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E8, "FAIL");
  assert.deepEqual(evidence.scenarioEvidence.E8.forbiddenFieldsFound, ["servicePattern"]);
});

test("E8은 double-quote로 직렬화된 금지 필드도 우회 없이 FAIL한다(quote 스타일 회귀 가드)", async () => {
  const repoRoot = await fixtureRepoRoot({
    // Dart는 single/double quote 문자열 리터럴을 모두 허용한다 — double quote만 써서
    // single-quote 전용 검사를 우회할 수 있었던 과거 결함의 회귀 가드.
    requestClassBody: "class RouteSearchRequest {\n  Map<String, Object?> toV2Json() => {\"expressOnly\": true};\n}\n",
  });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E8, "FAIL");
  assert.deepEqual(evidence.scenarioEvidence.E8.forbiddenFieldsFound, ["expressOnly"]);
});

test("CANDIDATE context가 아니면 거부한다", async () => {
  const repoRoot = await fixtureRepoRoot();
  assert.throws(
    () => buildMobileConsumptionEvidence({ candidate: { phase: "FINAL", issue: 2056, releaseCandidateIdentity: identity }, repoRoot }),
    /CANDIDATE context/,
  );
});

test("현재 작업 브랜치 tracked source에 대해 실행하면 E1/E7/E8/E9 모두 PASS를 재현한다(ITX 배지 fix #2245가 main에 병합됨, 4c5c93ef)", () => {
  const repoRoot = path.resolve(import.meta.dirname, "../..");
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E1, "PASS");
  assert.equal(evidence.integrationScenarios.E7, "PASS");
  assert.equal(evidence.integrationScenarios.E8, "PASS");
  assert.equal(evidence.integrationScenarios.E9, "PASS");
  assert.equal(evidence.status, "SATISFIED");
});
