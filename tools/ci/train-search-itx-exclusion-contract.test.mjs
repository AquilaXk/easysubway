import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";

const read = (path) => readFileSync(path, "utf8");
const readJson = (path) => JSON.parse(read(path));
const readYaml = (path) => JSON.parse(execFileSync("ruby", [
  "-rjson",
  "-ryaml",
  "-e",
  "puts JSON.generate(YAML.safe_load(File.read(ARGV.fetch(0)), permitted_classes: [], aliases: false))",
  path,
], { encoding: "utf8" }));

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
  const openapi = readYaml("contracts/api/train-api.openapi.yaml");
  const stations = openapi.paths["/api/v1/trains/stations"].get;
  const search = openapi.paths["/api/v1/trains/search"].get;
  const parameters = (operation) => Object.fromEntries(operation.parameters.map((parameter) => [parameter.name, parameter]));
  const stationParameters = parameters(stations);
  const searchParameters = parameters(search);

  assert.deepEqual(Object.keys(stationParameters), ["query", "trainType"]);
  assert.equal(stationParameters.query.required, true);
  assert.equal(stationParameters.trainType.required, false);
  assert.equal(stationParameters.query.schema.minLength, 2);
  assert.deepEqual(Object.keys(searchParameters), [
    "departureStationId", "arrivalStationId", "departureDate", "returnDate", "trainType",
  ]);
  for (const required of ["departureStationId", "arrivalStationId", "departureDate"]) {
    assert.equal(searchParameters[required].required, true);
  }
  assert.equal(searchParameters.returnDate.required, false);
  assert.equal(searchParameters.trainType.required, false);
  assert.deepEqual(Object.keys(stations.responses), ["200", "304", "400", "422", "429", "502", "503"]);
  assert.deepEqual(Object.keys(search.responses), ["200", "304", "400", "422", "429", "502", "503"]);
  for (const operation of [stations, search]) {
    for (const status of ["200", "304"]) {
      assert.deepEqual(Object.keys(operation.responses[status].headers), ["ETag", "Cache-Control"]);
    }
  }
  assert.equal(stations.responses["200"].content["application/json"].schema.$ref,
    "#/components/schemas/StationSearchEnvelope");
  assert.equal(search.responses["200"].content["application/json"].schema.$ref,
    "#/components/schemas/TrainSearchEnvelope");
  assert.equal(stations.responses["400"].$ref, "#/components/responses/UnsupportedTrainType");
  assert.equal(search.responses["400"].content["application/json"].schema.$ref,
    "#/components/schemas/TrainSearchErrorEnvelope");
  for (const schema of ["TrainType", "StationSearchEnvelope", "TrainSearchEnvelope", "Station", "Journey", "TrainSearchResult"]) {
    assert.ok(openapi.components.schemas[schema]);
  }
  assert.deepEqual(openapi.components.schemas.TrainType.enum, supportedTrainTypes);
  for (const response of ["UnsupportedTrainType", "InvalidArgument", "RateLimited", "ProviderFailure", "TrainSearchUnavailable"]) {
    assert.ok(openapi.components.responses[response]);
  }
  assert.equal(openapi.components.responses.UnsupportedTrainType.content["application/json"].example.data.code,
    "TRAIN_SEARCH_UNSUPPORTED_TRAIN_TYPE");
  assert.equal(openapi.components.responses.InvalidArgument.content["application/json"].example.data.code,
    "TRAIN_SEARCH_INVALID_ARGUMENT");
  assert.equal(openapi.components.responses.RateLimited.content["application/json"].example.data.code,
    "TRAIN_SEARCH_RATE_LIMITED");
  assert.deepEqual(
    Object.values(openapi.components.responses.ProviderFailure.content["application/json"].examples)
      .map(({ value }) => value.data.code),
    ["TRAIN_SEARCH_PROVIDER_ERROR", "TRAIN_SEARCH_NO_VALID_ROWS"],
  );
  assert.equal(openapi.components.responses.TrainSearchUnavailable.content["application/json"].example.data.code,
    "TRAIN_SEARCH_UNAVAILABLE");
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
  assert.equal(report.issue2094RoadmapRequiredForThisGate, true);
  assert.equal(report.runtimeImplementationStatus, "SATISFIED_BY_2094");
  assert.equal(report.providerLiveCallPerformed, true);
  assert.equal(report.issue2094RuntimeEvidence.provider.itxCheongchunRows, 0);
  assert.equal(report.issue2094RuntimeEvidence.backend.itxCheongchunRows, 0);
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
