import assert from "node:assert/strict";
import test from "node:test";

import { findCatalogEntry, listCatalog, validateCatalog } from "./api-catalog.mjs";

const provider = (overrides) => ({
  id: "provider:sample",
  kind: "provider",
  endpoint: "https://provider.example/api",
  operation: { method: "GET" },
  operationValidationError: null,
  providerApprovalValidationError: null,
  sampleUrl: null,
  ...overrides,
});

test("정본 AGGREGATE_SOURCE_SET provider는 단일 요청 URL 없이 통과한다(#3016)", () => {
  assert.doesNotThrow(() => validateCatalog([
    provider({ endpoint: null, operation: { kind: "AGGREGATE_SOURCE_SET", method: "GET" } }),
  ]));
});

test("일반 provider는 endpoint가 없으면 거부한다(#3016)", () => {
  assert.throws(
    () => validateCatalog([provider({ endpoint: null })]),
    /provider:sample: invalid provider endpoint/,
  );
});

test("AGGREGATE_SOURCE_SET이라도 잘못된 endpoint 문자열은 거부한다(#3016)", () => {
  assert.throws(
    () => validateCatalog([
      provider({ endpoint: "not-a-url", operation: { kind: "AGGREGATE_SOURCE_SET", method: "GET" } }),
    ]),
    /provider:sample: invalid provider endpoint/,
  );
});

test("listCatalog와 findCatalogEntry는 캐시된 색인으로 대소문자 무시 검색과 O(1) 조회를 수행한다", () => {
  const catalog = [
    provider({ id: "provider:seoul-elevator", notes: "엘리베이터 실시간 가동" }),
    { id: "contract:journey-v3", kind: "contract", path: "contracts/api/journey-v3.openapi.yaml" },
  ];
  assert.equal(listCatalog(catalog, { query: "엘리베이터" }).length, 1);
  assert.equal(listCatalog(catalog, { query: "JOURNEY-V3" }).length, 1);
  assert.equal(listCatalog(catalog, { kind: "contract", query: "seoul" }).length, 0);
  assert.equal(findCatalogEntry(catalog, "contract:journey-v3").path, "contracts/api/journey-v3.openapi.yaml");
  assert.throws(() => findCatalogEntry(catalog, "provider:missing"), /not found/);
});
