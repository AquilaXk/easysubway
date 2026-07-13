import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
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

test("validate는 nested auth credential 값도 거부한다", () => {
  const operation = validOperation();
  operation.auth.tokenValue = "actual-secret-value";
  const invalid = candidate("a", { operation });

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

test("공식 OD fare source는 재현 가능한 operation과 조회 명령을 고정한다", async () => {
  const candidates = JSON.parse(
    await readFile(new URL("./source-candidates.json", import.meta.url), "utf8"),
  );
  const runbook = JSON.parse(
    await readFile(new URL("./source-admission-runbook.json", import.meta.url), "utf8"),
  );
  const fare = candidates.candidates.find(
    (entry) => entry.id === "seoul-metro-official-od-fares",
  );

  assert.deepEqual(fare.operation.auth, {
    env: "DATA_GO_KR_SERVICE_KEY",
    placement: "query",
    parameter: "serviceKey",
  });
  assert.deepEqual(fare.operation.requiredParameters, [
    "serviceKey",
    "pageNo",
    "numOfRows",
    "dataType",
    "dptreStnNm",
    "arvlStnNm",
  ]);
  assert.equal(fare.operation.responseEnvelope, "response.body.items.item");
  assert.deepEqual(fare.operation.runner, {
    command: "node tools/datapack/probe-seoul-fare-api.mjs",
    requiredEnv: ["DATA_GO_KR_SERVICE_KEY", "FARE_API_PROBE_OUTPUT"],
  });
  assert.equal(
    runbook.operationLookupCommand,
    "node tools/api/api-catalog.mjs show provider:<sourceId>",
  );
});
