import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import test from "node:test";
import { promisify } from "node:util";

import {
  buildCatalog,
  findCatalogEntry,
  listCatalog,
  loadCatalogPolicy,
  loadProjectCatalog,
  validateCatalog,
  validateCatalogPolicy,
} from "./api-catalog.mjs";

const execFileAsync = promisify(execFile);

function fixtureCatalog() {
  return buildCatalog({
    internalDocument: {
      operations: [
        {
          id: "internal:GET:/api/v1/stations:example.StationController#list",
          method: "GET",
          path: "/api/v1/stations",
          surface: "PUBLIC_API",
          handlerClass: "example.StationController",
          javaMethod: "list",
        },
      ],
    },
    providerDocument: {
      candidates: [
        {
          id: "official-stations",
          requestUrl: "https://provider.example/stations",
          admissionStatus: "admitted_to_production_inventory",
        },
        {
          id: "official-route-map-reference",
          requestUrl: "https://provider.example/route-map",
          apiCatalog: false,
          admissionStatus: "admitted_to_production_inventory",
        },
      ],
    },
    integrationsDocument: {
      operations: [
        {
          id: "integration:datapack-manifest",
          method: "GET",
          endpointRef: "config:EASYSUBWAY_DATA_PACK_BASE_URL/catalog/current.json",
          auth: "signed-manifest-verification",
          source: "apps/mobile/lib/core/datapack/data_pack_client.dart",
        },
      ],
    },
    contractDocuments: ["contracts/api/report-api.openapi.yaml"],
  });
}

test("catalog는 internal/provider/integration/OpenAPI reference를 한 목록으로 합친다", () => {
  const catalog = fixtureCatalog();

  assert.deepEqual(
    catalog.map((entry) => entry.kind),
    ["contract", "integration", "internal", "provider"],
  );
  assert.equal(
    findCatalogEntry(catalog, "provider:official-stations").endpoint,
    "https://provider.example/stations",
  );
  assert.equal(catalog.some((entry) => entry.id === "provider:official-route-map-reference"), false);
});

test("list는 kind와 query로 검색한다", () => {
  const catalog = fixtureCatalog();

  assert.deepEqual(
    listCatalog(catalog, { kind: "internal", query: "stations" }).map(
      (entry) => entry.id,
    ),
    ["internal:GET:/api/v1/stations:example.StationController#list"],
  );
  assert.deepEqual(
    listCatalog(catalog, { query: "datapack" }).map((entry) => entry.id),
    ["integration:datapack-manifest"],
  );
});

test("validate는 secret 값과 runtime catalog endpoint를 거부한다", () => {
  const catalog = fixtureCatalog();
  for (const [field, value] of [
    ["tokenValue", "actual-token"],
    ["token", "actual-token"],
    ["apiKey", "actual-api-key"],
    ["client_secret", "actual-client-secret"],
    ["refresh_token", "actual-refresh-token"],
    ["secret", "actual-secret"],
    ["x-api-key", "actual-header-api-key"],
  ]) {
    assert.throws(
      () =>
        validateCatalog([
          ...catalog,
          {
            id: `integration:bad-${field}`,
            kind: "integration",
            method: "GET",
            endpointRef: "config:EXAMPLE_API",
            auth: "env:EXAMPLE_API_TOKEN",
            source: "example.java",
            [field]: value,
          },
        ]),
      /secret-like values are forbidden/,
    );
  }
  assert.throws(
    () =>
      validateCatalog([
        {
          id: "internal:GET:/api/catalog:example.CatalogController#get",
          kind: "internal",
          method: "GET",
          path: "/api/catalog",
          surface: "PUBLIC_API",
        },
      ]),
    /runtime catalog endpoint is forbidden/,
  );
  for (const path of ["/admin/api/catalog", "/operator/api/catalog/v1"]) {
    assert.throws(
      () =>
        validateCatalog([
          {
            id: `internal:GET:${path}:example.CatalogController#get`,
            kind: "internal",
            method: "GET",
            path,
            surface: "ADMIN_API",
          },
        ]),
      /runtime catalog endpoint is forbidden/,
    );
  }
  assert.throws(
    () =>
      validateCatalog([
        {
          id: "internal:GET:/api/catalog/v1:example.CatalogController#get",
          kind: "internal",
          method: "GET",
          path: "/api/catalog/v1",
          surface: "PUBLIC_API",
        },
      ]),
    /runtime catalog endpoint is forbidden/,
  );
  for (const leaked of [
    {
      id: "integration:leaked-query-token",
      kind: "integration",
      method: "GET",
      endpointRef: "constant:https://api.example/x?token=actual-secret",
      source: "example.java",
    },
    {
      id: "provider:leaked-service-key",
      kind: "provider",
      endpoint: "https://api.example/x?serviceKey=actual-secret",
    },
    {
      id: "provider:leaked-client-secret",
      kind: "provider",
      endpoint: "https://api.example/x?client_secret=actual-secret",
    },
    {
      id: "provider:leaked-userinfo",
      kind: "provider",
      endpoint: "https://user:password@api.example/x",
    },
    {
      id: "provider:leaked-path-key",
      kind: "provider",
      endpoint: "https://api.example/{serviceKey}/items",
      sampleUrl: "https://api.example/actual-secret/items",
    },
    {
      id: "provider:leaked-generic-key",
      kind: "provider",
      endpoint: "https://api.example/items?key=actual-secret",
    },
    {
      id: "provider:leaked-signed-query",
      kind: "provider",
      endpoint: "https://api.example/items",
      sampleUrl: "https://api.example/items?X-Amz-Security-Token=actual-secret",
    },
    {
      id: "provider:leaked-authorization",
      kind: "provider",
      endpoint: "https://api.example/x",
      authorization: "Basic dXNlcjpwYXNzd29yZA==",
    },
  ]) {
    assert.throws(
      () => validateCatalog([leaked]),
      /secret-like values are forbidden/,
    );
  }
  for (const endpoint of ["https://", "http:// not-a-host", "ftp://api.example/items"]) {
    assert.throws(
      () => validateCatalog([{ id: "provider:bad-url", kind: "provider", endpoint }]),
      /invalid provider endpoint/,
    );
  }
});

test("validate는 격리된 provider operation 오류를 거부한다", () => {
  assert.throws(
    () => validateCatalog([{
      id: "provider:invalid-operation",
      kind: "provider",
      endpoint: "https://provider.example/invalid",
      operation: { method: "GET" },
      operationValidationError: "invalid-operation.operation.auth must be an object",
    }]),
    /provider operation contract is invalid/,
  );
});

test("integration auth는 credential reference 표현만 허용한다", () => {
  for (const auth of [
    "Basic dXNlcjpwYXNzd29yZA==",
    "AWS4-HMAC-SHA256 Credential=AKIAEXAMPLE/20260713/ap-northeast-2/s3/aws4_request",
  ]) {
    assert.throws(
      () =>
        validateCatalog([
          {
            id: `integration:bad-auth-${auth.slice(0, 5)}`,
            kind: "integration",
            method: "GET",
            endpointRef: "config:EXAMPLE_API",
            auth,
            source: "example.java",
          },
        ]),
      /secret-like values are forbidden|integration auth is invalid/,
    );
  }
});

test("CLI list는 provider operation method를 표시한다", async () => {
  const { stdout } = await execFileAsync(process.execPath, [
    "tools/ci/api-catalog.mjs",
    "list",
    "--kind",
    "provider",
    "--query",
    "seoul-metro-official-od-fares",
  ]);

  assert.match(
    stdout,
    /^provider:seoul-metro-official-od-fares\tprovider\tGET\thttps:\/\/apis\.data\.go\.kr\//,
  );
});

test("CLI show는 기본 human 출력과 --json 출력을 구분한다", async () => {
  const args = [
    "tools/ci/api-catalog.mjs",
    "show",
    "provider:seoul-metro-official-od-fares",
  ];
  const human = await execFileAsync(process.execPath, args);
  const json = await execFileAsync(process.execPath, [...args, "--json"]);

  assert.match(human.stdout, /^id: provider:seoul-metro-official-od-fares$/m);
  assert.match(human.stdout, /^method: GET$/m);
  assert.doesNotMatch(human.stdout, /^\{$/m);
  assert.equal(JSON.parse(json.stdout).id, "provider:seoul-metro-official-od-fares");
});

test("프로젝트 catalog는 주요 API 종류를 모두 찾고 검증한다", async () => {
  const catalog = await loadProjectCatalog();

  validateCatalog(catalog);
  assert.ok(catalog.some((entry) => entry.kind === "internal"));
  assert.ok(catalog.some((entry) => entry.id === "provider:seoul-topis-realtime-station-arrival"));
  const publicDataSearch = findCatalogEntry(catalog, "provider:public-data-portal-search");
  assert.equal(publicDataSearch.operation.method, "POST");
  assert.equal(publicDataSearch.operation.auth.env, "DATA_GO_KR_SERVICE_KEY");
  assert.deepEqual(publicDataSearch.responseFields, [
    "sum",
    "dataCount",
    "dataName",
    "dataDescription",
    "organization",
    "keywords",
    "dataType",
    "detailPageUrl",
  ]);
  for (const [id, method, authEnv] of [
    ["provider:daejeon-train-timetable", "GET", "DATA_GO_KR_SERVICE_KEY"],
    ["provider:daejeon-station-distance-fare", "GET", "DATA_GO_KR_SERVICE_KEY"],
    ["provider:daejeon-braille-guide-map", "GET", "DATA_GO_KR_SERVICE_KEY"],
  ]) {
    const entry = findCatalogEntry(catalog, id);
    assert.equal(entry.operation.method, method);
    assert.equal(entry.operation.auth.env, authEnv);
    assert.equal(entry.operation.runner.command, "node tools/datapack/probe-daejeon-coverage-api.mjs");
  }
  const daejeonSearchIds = new Set(listCatalog(catalog, { kind: "provider", query: "대전" }).map(({ id }) => id));
  for (const id of [
    "provider:daejeon-braille-guide-map",
    "provider:daejeon-station-distance-fare",
    "provider:daejeon-train-timetable",
  ]) assert.ok(daejeonSearchIds.has(id));
  assert.deepEqual(
    listCatalog(catalog, { kind: "provider", query: "ITX-청춘" })
      .map(({ id }) => id)
      .filter((id) => id.startsWith("provider:tago-train-") || id.startsWith("provider:kric-")),
    [
      "provider:kric-station-timetable",
      "provider:kric-subway-route-info",
      "provider:kric-subway-timetable",
      "provider:kric-subway-timetable-exp",
      "provider:tago-train-city-codes",
      "provider:tago-train-grades",
      "provider:tago-train-schedule-fares",
      "provider:tago-train-stations",
    ],
  );
  for (const [id, fields, status] of [
    ["provider:korail-train-operation-codes", ["code", "type", "value"], "admitted_as_code_mapping"],
    ["provider:korail-traveler-train-run-plan", [
      "run_ymd", "trn_no", "dptre_stn_cd", "dptre_stn_nm", "arvl_stn_cd", "arvl_stn_nm",
      "trn_plan_dptre_dt", "trn_plan_arvl_dt",
    ], "admitted_as_train_endpoint_plan"],
    ["provider:korail-traveler-train-run-info", [
      "run_ymd", "trn_no", "trn_run_sn", "stn_cd", "stn_nm", "mrnt_cd", "mrnt_nm",
      "uppln_dn_se_cd", "stop_se_cd", "stop_se_nm", "trn_dptre_dt", "trn_arvl_dt",
    ], "admitted_for_station_sequence_timetable_values_missing"],
  ]) {
    const entry = findCatalogEntry(catalog, id);
    assert.equal(entry.documentationStatus, "reproducible-operation");
    assert.equal(entry.status, status);
    assert.deepEqual(entry.responseFields, fields);
    assert.equal(entry.operation.method, "GET");
    assert.equal(entry.operation.runner.command, "node tools/datapack/probe-korail-train-operation-api.mjs");
  }
  const kricStationTimetable = findCatalogEntry(catalog, "provider:kric-station-timetable");
  assert.equal(kricStationTimetable.status, "validated_live_sample_non_itx_urban_rail_only");
  assert.ok(kricStationTimetable.searchTerms.includes("ITX_CHEONGCHUN"));
  assert.equal(
    findCatalogEntry(catalog, "provider:busan-transportation-official-od-fares").operation.method,
    "POST",
  );
  assert.equal(
    findCatalogEntry(catalog, "provider:busan-transportation-official-fare-table").operation.method,
    "GET",
  );
  assert.ok(catalog.some((entry) => entry.id === "integration:github-datapack-workflow-dispatch"));
  assert.ok(catalog.some((entry) => entry.id === "integration:mobile-ad-creative-image"));
  assert.ok(catalog.some((entry) => entry.id === "integration:mobile-report-photo-upload"));
  assert.ok(catalog.some((entry) => entry.id === "contract:report-api"));
  assert.equal(
    findCatalogEntry(catalog, "integration:github-datapack-workflow-dispatch").endpointRef,
    "config:easysubway.datapack.github-api-base-url(default=https://api.github.com)/repos/AquilaXk/easysubway/actions/workflows/datapack-release.yml/dispatches",
  );
});

test("프로젝트 provider catalog는 비API source를 제외하고 모든 호출 계약을 제공한다", async () => {
  const providers = (await loadProjectCatalog()).filter((entry) => entry.kind === "provider");

  assert.equal(providers.length, 41);
  assert.equal(providers.some((entry) => entry.documentationStatus === "metadata-only"), false);
  assert.equal(providers.some((entry) => entry.id === "provider:molit-urban-rail-full-route"), false);
  assert.equal(providers.some((entry) => entry.id === "provider:seoulmetro-cyberstation-route-map"), false);

  const kricElevator = providers.find((entry) => entry.id === "provider:kric-station-elevator");
  assert.equal(kricElevator.endpoint, "https://openapi.kric.go.kr/openapi/convenientInfo/stationElevator");
  assert.match(kricElevator.sampleUrl, /^https:\/\/openapi\.kric\.go\.kr\/openapi\/convenientInfo\/stationElevator\?/);
  assert.deepEqual(kricElevator.responseFields, [
    "dtlLoc", "exitNo", "grndDvNmFr", "grndDvNmTo", "lnCd", "railOprIsttCd",
    "rglnPsno", "rglnWgt", "runStinFlorFr", "runStinFlorTo", "stinCd",
  ]);

  const stationLine = providers.find((entry) => entry.id === "provider:seoulmetro-station-line-info");
  assert.deepEqual(stationLine.operation.requiredParameters, [
    "serviceKey", "startIndex", "endIndex", "stationCode", "stationName", "lineName",
  ]);
  assert.match(stationLine.sampleUrl, /\/1\/5\/\/\/4호선$/);

  assert.deepEqual(
    providers.find((entry) => entry.id === "provider:seoul-topis-realtime-station-arrival").responseFields,
    ["arvlCd", "arvlMsg2", "arvlMsg3", "barvlDt", "bstatnNm", "btrainNo", "recptnDt", "statnId", "statnNm", "subwayId", "trainLineNm", "updnLine"],
  );
});

test("프로젝트 catalog는 KRIC 승인과 shell 없는 key 전달 양식을 제공한다", async () => {
  const catalog = await loadProjectCatalog();
  const entry = findCatalogEntry(catalog, "provider:kric-transfer-movement-standard");

  assert.deepEqual(entry.providerApproval, {
    status: "APPROVED",
    approvalScope: "API_CREDENTIAL",
    termsStatus: "REVIEW_REQUIRED",
    quotaStatus: "REVIEW_REQUIRED",
    productionUseAllowed: false,
    serviceId: "handicapped",
    operationId: "transferMovement",
    validFrom: "2026-07-06",
    validTo: "2027-07-06",
    renewalNoticeDays: 30,
    evidenceReferences: [{
      type: "OWNER_CONFIRMATION",
      url: "https://github.com/AquilaXk/easysubway/issues/1397#issuecomment-4956908695",
    }],
    recordedAt: "2026-07-13",
  });
  assert.equal(entry.operation.auth.env, "KRIC_SERVICE_KEY");
  assert.equal(entry.operation.auth.parameter, "serviceKey");
  assert.equal(entry.operation.auth.valueEncoding, "url-search-params-once");
  assert.equal(entry.operation.auth.loadPolicy, "process-env-no-shell-parsing");
  assert.deepEqual(entry.operation.runner.arguments, ["--candidate", "kric-transfer-movement-standard"]);
  const { stdout } = await execFileAsync(process.execPath, [
    "tools/ci/api-catalog.mjs",
    "show",
    "provider:kric-transfer-movement-standard",
  ]);
  assert.match(
    stdout,
    /^runner: node tools\/datapack\/collect-kric-source-candidate-evidence\.mjs --candidate kric-transfer-movement-standard$/m,
  );
  assert.match(stdout, /^runner env: KRIC_SERVICE_KEY, RUNNER_TEMP$/m);
  assert.match(stdout, /^provider credential: APPROVED$/m);
  assert.match(stdout, /^provider approval scope: API_CREDENTIAL$/m);
  assert.match(stdout, /^provider terms: REVIEW_REQUIRED$/m);
  assert.match(stdout, /^provider quota: REVIEW_REQUIRED$/m);
  assert.match(stdout, /^provider production use: not allowed$/m);
});

test("catalog 운영 계약은 repository-local 전용과 source-of-truth 경계를 고정한다", async () => {
  const policy = await loadCatalogPolicy();

  validateCatalogPolicy(policy);
  assert.equal(policy.runtimeExposure, "forbidden");
  assert.equal(policy.commands.validate, "node tools/ci/api-catalog.mjs validate");
  assert.deepEqual(policy.sources, [
    "spring-request-mappings",
    "openapi-contracts",
    "external-provider-metadata",
    "outbound-runtime-integrations",
  ]);
});
