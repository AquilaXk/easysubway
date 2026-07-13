import assert from "node:assert/strict";
import test from "node:test";

import {
  listOperations,
  operationSummary,
  validateOperation,
} from "./source-operation.mjs";

function candidate(id, overrides = {}) {
  return {
    id,
    admissionStatus: "admitted_to_production_inventory",
    requestUrl: `https://provider.example/${id}`,
    evidence: {
      outputFields: ["fieldA"],
      sampleUrl: `https://provider.example/${id}?serviceKey=[서비스키값]`,
    },
    ...overrides,
  };
}

function validOperation(overrides = {}) {
  return {
    method: "GET",
    endpoint: "https://provider.example/a",
    auth: {
      env: "PROVIDER_SERVICE_KEY",
      placement: "query",
      parameter: "serviceKey",
    },
    requiredParameters: ["serviceKey"],
    responseEnvelope: "response.body.items.item",
    runner: {
      command: "node tools/datapack/probe-provider.mjs",
      requiredEnv: ["PROVIDER_SERVICE_KEY"],
    },
    secretPolicy: "env-only-redacted-output",
    ...overrides,
  };
}

test("list는 requestUrl이 있는 source를 ID 순으로 반환한다", () => {
  const document = {
    candidates: [candidate("b"), { id: "local-file" }, candidate("a")],
  };

  assert.deepEqual(
    listOperations(document).map((row) => row.id),
    ["a", "b"],
  );
});

test("show는 operation이 없어도 기존 endpoint와 response fields를 반환한다", () => {
  const summary = operationSummary(candidate("a"));

  assert.equal(summary.endpoint, "https://provider.example/a");
  assert.equal(
    summary.sampleUrl,
    "https://provider.example/a?serviceKey=[서비스키값]",
  );
  assert.deepEqual(summary.responseFields, ["fieldA"]);
  assert.equal(summary.operation, null);
});

test("validate는 credential 값을 거부한다", () => {
  const invalid = candidate("a", {
    operation: validOperation({ credentialValue: "actual-secret-value" }),
  });

  assert.throws(
    () => validateOperation(invalid),
    /credential values are forbidden/,
  );
});

test("validate는 operation endpoint mismatch를 거부한다", () => {
  const invalid = candidate("a", {
    operation: validOperation({ endpoint: "https://provider.example/wrong" }),
  });

  assert.throws(
    () => validateOperation(invalid),
    /endpoint must match requestUrl/,
  );
});
