import assert from "node:assert/strict";
import test from "node:test";

import {
  buildCatalog,
  findCatalogEntry,
  listCatalog,
  loadCatalogPolicy,
  loadProjectCatalog,
  validateCatalog,
  validateCatalogPolicy,
} from "../api/api-catalog.mjs";

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
      ],
    },
    integrationsDocument: {
      operations: [
        {
          id: "integration:datapack-manifest",
          method: "GET",
          endpointRef: "config:EASYSUBWAY_DATA_PACK_BASE_URL/catalog/current.json",
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
  assert.throws(
    () =>
      validateCatalog([
        ...catalog,
        {
          id: "integration:bad-secret",
          kind: "integration",
          method: "GET",
          endpointRef: "config:EXAMPLE_API",
          source: "example.java",
          tokenValue: "actual-token",
        },
      ]),
    /secret-like values are forbidden/,
  );
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
});

test("프로젝트 catalog는 주요 API 종류를 모두 찾고 검증한다", async () => {
  const catalog = await loadProjectCatalog();

  validateCatalog(catalog);
  assert.ok(catalog.some((entry) => entry.kind === "internal"));
  assert.ok(catalog.some((entry) => entry.id === "provider:seoul-topis-realtime-station-arrival"));
  assert.ok(catalog.some((entry) => entry.id === "integration:github-datapack-workflow-dispatch"));
  assert.ok(catalog.some((entry) => entry.id === "contract:report-api"));
});

test("catalog 운영 계약은 repository-local 전용과 source-of-truth 경계를 고정한다", async () => {
  const policy = await loadCatalogPolicy();

  validateCatalogPolicy(policy);
  assert.equal(policy.runtimeExposure, "forbidden");
  assert.equal(policy.commands.validate, "node tools/api/api-catalog.mjs validate");
  assert.deepEqual(policy.sources, [
    "spring-request-mappings",
    "openapi-contracts",
    "external-provider-metadata",
    "outbound-runtime-integrations",
  ]);
});
