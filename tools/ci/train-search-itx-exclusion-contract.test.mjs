import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(path, "utf8");
const readJson = (path) => JSON.parse(read(path));

const supportedTrainTypes = [
  "KTX",
  "KTX_SANCHEON",
  "SRT",
  "ITX_MAUM",
  "ITX_SAEMAEUL",
  "SAEMAEUL",
  "MUGUNGHWA",
  "NURIRO",
];

test("train-search canonical allowlist와 OpenAPI enum은 ITX-청춘을 제외한다", () => {
  const targets = readJson("tools/datapack/nationwide-coverage-targets.json");
  const scope = targets.railProductScope.trainSearchOnly;
  const openapi = read("contracts/api/train-api.openapi.yaml");
  const trainTypeSchema = openapi.match(/\n    TrainType:\n([\s\S]*?)(?=\n    [A-Z][A-Za-z]+:|$)/)?.[1];

  assert.deepEqual(scope.services, supportedTrainTypes);
  assert.equal(scope.exclusionContract, "apps/mobile/release/train-search-itx-exclusion-gate.json");
  assert.ok(trainTypeSchema);
  for (const trainType of supportedTrainTypes) {
    assert.match(trainTypeSchema, new RegExp(`- ${trainType}(?:\\n|$)`));
  }
  assert.doesNotMatch(trainTypeSchema, /ITX_CHEONGCHUN/);
});

test("OpenAPI는 역검색·왕복검색 성공 envelope와 안정 오류 계약을 공개한다", () => {
  const openapi = read("contracts/api/train-api.openapi.yaml");

  for (const parameter of [
    "query",
    "departureStationId",
    "arrivalStationId",
    "departureDate",
    "returnDate",
    "trainType",
  ]) {
    assert.match(openapi, new RegExp(`- name: ${parameter}(?:\\n|\\r\\n)`));
  }
  for (const schema of [
    "StationSearchEnvelope",
    "TrainSearchEnvelope",
    "Station",
    "Journey",
    "TrainSearchResult",
  ]) {
    assert.match(openapi, new RegExp(`\\n    ${schema}:\\n`));
  }
  for (const status of ["200", "400", "422", "429", "502", "503"]) {
    assert.match(openapi, new RegExp(`        "${status}":`));
  }
  for (const code of [
    "TRAIN_SEARCH_INVALID_ARGUMENT",
    "TRAIN_SEARCH_UNSUPPORTED_TRAIN_TYPE",
    "TRAIN_SEARCH_RATE_LIMITED",
    "TRAIN_SEARCH_PROVIDER_ERROR",
    "TRAIN_SEARCH_NO_VALID_ROWS",
    "TRAIN_SEARCH_UNAVAILABLE",
  ]) {
    assert.match(openapi, new RegExp(`(?:- |code: )${code}(?:\\n|,|\\])`));
  }
  assert.match(openapi, /name: query[\s\S]*?required: true[\s\S]*?minLength: 2/);
  assert.match(openapi, /name: departureStationId[\s\S]*?required: true/);
  assert.match(openapi, /name: arrivalStationId[\s\S]*?required: true/);
  assert.match(openapi, /name: departureDate[\s\S]*?required: true/);
  assert.match(openapi, /headers:[\s\S]*?ETag:[\s\S]*?Cache-Control:/);
});

test("backend·Mobile allowlist는 canonical 열차종과 drift하지 않는다", () => {
  const java = read("backend/src/main/java/com/easysubway/train/domain/TrainSearchScopePolicy.java");
  const dart = read("apps/mobile/lib/features/train_search/domain/train_search_scope_policy.dart");
  const javaAllowlist = java.match(/SUPPORTED_TRAIN_TYPES = Set\.of\(([\s\S]*?)\n\t\);/)?.[1];
  const dartAllowlist = dart.match(/enum TrainSearchTrainType \{([\s\S]*?)\n\n  const/)?.[1];

  assert.ok(javaAllowlist);
  assert.ok(dartAllowlist);
  const javaTypes = [...javaAllowlist.matchAll(/\"([A-Z][A-Z_]+)\"/g)].map((match) => match[1]);
  const dartTypes = [...dartAllowlist.matchAll(/'([A-Z][A-Z_]+)'/g)].map((match) => match[1]);

  assert.deepEqual(javaTypes, supportedTrainTypes);
  assert.deepEqual(dartTypes, supportedTrainTypes);
  assert.doesNotMatch(java, /\"ITX_CHEONGCHUN\"/);
  assert.doesNotMatch(dart, /'ITX_CHEONGCHUN'/);
});

test("negative report는 request·provider·cache·catalog·Mobile에서 ITX 0건과 대전 KTX를 증명한다", () => {
  const report = readJson("apps/mobile/release/train-search-itx-exclusion-gate.json");

  assert.equal(report.sourceIssue, 2136);
  assert.equal(report.status, "SATISFIED");
  assert.deepEqual(report.supportedTrainTypes, supportedTrainTypes);
  assert.deepEqual(report.excludedTrainTypes, ["ITX_CHEONGCHUN"]);
  assert.deepEqual(report.rejectionContract, {
    endpoints: ["/api/v1/trains/stations", "/api/v1/trains/search"],
    httpStatus: 400,
    code: "TRAIN_SEARCH_UNSUPPORTED_TRAIN_TYPE",
  });
  assert.deepEqual(report.negativeCounts, {
    currentProviderRowsReturned: 0,
    legacyYongsanDaejeonRowsReturned: 0,
    cacheRows: 0,
    stationCatalogRows: 0,
    mobileFilterEntries: 0,
  });
  assert.equal(report.daejeonSupportedTrainType, "KTX");
  assert.equal(report.daejeonSupportedTrainTypePreserved, true);
  assert.equal(report.routeV2ItxConsumerUnchanged, true);
  assert.equal(report.issue2135ArtifactConsumedByTrainSearch, false);
  assert.equal(report.issue2094RoadmapRequiredForThisGate, false);
  assert.equal(report.verification.backend, "./backend/gradlew -p backend test --tests '*TrainSearch*'");
  assert.equal(report.verification.mobile, "cd apps/mobile && flutter test test/features/train_search");
});

test("수도권 Route V2 ITX consumer는 train-search exclusion과 독립적으로 유지된다", () => {
  const targets = readJson("tools/datapack/nationwide-coverage-targets.json");
  const itxRouteScope = targets.railProductScope.routeMapAndRouting
    .find(({ serviceId }) => serviceId === "ITX_CHEONGCHUN");
  const backendRoute = read("backend/src/main/java/com/easysubway/route/adapter/out/persistence/JdbcRouteTimetableRepository.java");

  assert.ok(itxRouteScope);
  assert.equal(itxRouteScope.metropolitanRouteSearchCoverage,
    "CANONICAL_OD_STATIONS_IN_CAPITAL_METROPOLITAN_NETWORK");
  assert.match(backendRoute, /ITX_CHEONGCHUN/);
});
