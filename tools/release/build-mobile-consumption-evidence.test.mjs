import assert from "node:assert/strict";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { gzipSync } from "node:zlib";
import { DatabaseSync } from "node:sqlite";

import { buildMobileConsumptionEvidence } from "./build-mobile-consumption-evidence.mjs";

const identity = {
  gitSha: "1".repeat(40),
  appVersionName: "1.0.4",
  versionCode: "10005",
};

const ITX_LINE_ID = "line-54a7b980b7c3";
const NO_GENERIC_BADGE_TEST_NAME = "RIDE ITX_CHEONGCHUN/EXPRESS leg은 generic 급행 배지를 만들지 않는다";

function candidate(overrides = {}) {
  return { phase: "CANDIDATE", issue: 2056, releaseCandidateIdentity: identity, ...overrides };
}

function writeFixtureDatapack(root, lineNameKo) {
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE lines (id TEXT PRIMARY KEY, name_ko TEXT)");
  db.prepare("INSERT INTO lines (id, name_ko) VALUES (?, ?)").run(ITX_LINE_ID, lineNameKo);
  const sqliteBytes = db.serialize();
  db.close();
  return writeFile(
    path.join(root, "apps/mobile/assets/datapacks/capital.sqlite.gz"),
    gzipSync(Buffer.from(sqliteBytes)),
  );
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
  routeSearchTestNames = [NO_GENERIC_BADGE_TEST_NAME],
  itxLineNameKo = null,
} = {}) {
  const root = await mkdtemp(path.join(tmpdir(), "easysubway-mobile-evidence-"));
  await mkdir(path.join(root, "apps/mobile/test"), { recursive: true });
  await mkdir(path.join(root, "apps/mobile/lib"), { recursive: true });
  await mkdir(path.join(root, "apps/mobile/assets/datapacks"), { recursive: true });
  await writeFile(
    path.join(root, "apps/mobile/test/widget_test.dart"),
    widgetTestNames.map((name) => `testWidgets('${name}', (tester) async {});\n`).join(""),
  );
  await writeFile(
    path.join(root, "apps/mobile/test/route_search_request_test.dart"),
    requestTestNames.map((name) => `test('${name}', () {});\n`).join(""),
  );
  await writeFile(
    path.join(root, "apps/mobile/test/route_search_test.dart"),
    routeSearchTestNames.map((name) => `test('${name}', () {});\n`).join(""),
  );
  await writeFile(path.join(root, "apps/mobile/lib/route_search.dart"), requestClassBody);
  if (itxLineNameKo !== null) {
    await writeFixtureDatapack(root, itxLineNameKo);
  }
  return root;
}

test("E1/E7/E8 tracked test·source가 모두 있으면 SATISFIED와 PASS matrix를 산출한다", async () => {
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

test("E9는 번들 datapack의 line name이 ITX-청춘을 식별하지 않으면 FAIL한다(datapack 없음)", async () => {
  const repoRoot = await fixtureRepoRoot();
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E9, "FAIL");
  assert.equal(evidence.scenarioEvidence.E9.lineDisplay.pass, false);
  assert.match(evidence.scenarioEvidence.E9.reasonKo, /ITX/);
});

test("E9는 번들 datapack의 line name이 '경춘'처럼 ITX와 무관해도 fail closed한다(과거 false negative 방지)", async () => {
  const repoRoot = await fixtureRepoRoot({ itxLineNameKo: "수도권 경춘" });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E9, "FAIL");
  assert.equal(evidence.scenarioEvidence.E9.lineDisplay.lineNameKo, "수도권 경춘");
  assert.equal(evidence.scenarioEvidence.E9.lineDisplay.pass, false);
});

test("E9는 번들 datapack의 line name이 ITX-청춘을 식별하고 generic 배지 회귀 test가 있으면 PASS한다", async () => {
  const repoRoot = await fixtureRepoRoot({ itxLineNameKo: "ITX-청춘" });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E9, "PASS");
  assert.equal(evidence.scenarioEvidence.E9.lineDisplay.pass, true);
  assert.equal(evidence.scenarioEvidence.E9.noGenericBadge.pass, true);
});

test("E9는 line name이 ITX-청춘이어도 generic 배지 회귀 test가 없으면 FAIL한다", async () => {
  const repoRoot = await fixtureRepoRoot({ itxLineNameKo: "ITX-청춘", routeSearchTestNames: ["무관한 테스트"] });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E9, "FAIL");
  assert.equal(evidence.scenarioEvidence.E9.lineDisplay.pass, true);
  assert.equal(evidence.scenarioEvidence.E9.noGenericBadge.pass, false);
});

test("E1/E7 test 이름이 tracked 파일에 없으면 FAIL로 fail closed한다", async () => {
  const repoRoot = await fixtureRepoRoot({ widgetTestNames: ["다른 무관한 테스트"] });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E1, "FAIL");
  assert.equal(evidence.integrationScenarios.E7, "FAIL");
  assert.equal(evidence.status, "BLOCKED_MOBILE_SCENARIO_EVIDENCE");
});

test("E8은 request 직렬화에 servicePattern/expressOnly 등 금지 필드가 있으면 FAIL한다", async () => {
  const repoRoot = await fixtureRepoRoot({
    requestClassBody: "class RouteSearchRequest {\n  Map<String, Object?> toV2Json() => {'servicePattern': 'EXPRESS'};\n}\n",
  });
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E8, "FAIL");
  assert.deepEqual(evidence.scenarioEvidence.E8.forbiddenFieldsFound, ["servicePattern"]);
});

test("CANDIDATE context가 아니면 거부한다", async () => {
  const repoRoot = await fixtureRepoRoot();
  assert.throws(
    () => buildMobileConsumptionEvidence({ candidate: { phase: "FINAL", issue: 2056, releaseCandidateIdentity: identity }, repoRoot }),
    /CANDIDATE context/,
  );
});

test("실제 저장소 tracked source·번들 datapack에 대해 실행하면 E1/E7/E8 PASS, E9 FAIL(line name='수도권 경춘')을 재현한다", () => {
  const repoRoot = path.resolve(import.meta.dirname, "../..");
  const evidence = buildMobileConsumptionEvidence({ candidate: candidate(), repoRoot });

  assert.equal(evidence.integrationScenarios.E1, "PASS");
  assert.equal(evidence.integrationScenarios.E7, "PASS");
  assert.equal(evidence.integrationScenarios.E8, "PASS");
  assert.equal(evidence.scenarioEvidence.E9.lineDisplay.lineNameKo, "수도권 경춘");
  assert.equal(evidence.scenarioEvidence.E9.noGenericBadge.pass, true);
  assert.equal(evidence.integrationScenarios.E9, "FAIL");
});
