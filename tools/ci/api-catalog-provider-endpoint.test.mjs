import assert from "node:assert/strict";
import test from "node:test";

import { validateCatalog } from "./api-catalog.mjs";

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
