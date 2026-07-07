import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { collectContractErrors, loadJson } from "./check-contracts.mjs";
import { validateSchema } from "./lib/json-schema-lite.mjs";

test("번들 datapack index 실물이 계약 스키마를 통과한다", () => {
  const schema = loadJson("contracts/datapack/datapack-index.schema.json");
  const index = loadJson("apps/mobile/assets/datapacks/index.json");

  assert.deepEqual(validateSchema(schema, index).errors, []);
});

test("번들 source-inventory 실물이 계약 스키마를 통과한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");

  assert.deepEqual(validateSchema(schema, inventory).errors, []);
});

test("boundaries.json이 스스로 정합하다", () => {
  const boundaries = loadJson("contracts/boundaries.json");

  assert.equal(boundaries.schemaVersion, 1);
  for (const area of boundaries.splitOrder) {
    assert.ok(area in boundaries.areas, `splitOrder의 ${area}가 areas에 없다`);
  }
});

test("check-contracts CLI 검증 오류가 없다", () => {
  assert.deepEqual(collectContractErrors(), []);
});

test("OpenAPI 문서가 golden fixture 목록과 정합하다", () => {
  if (!existsSync("contracts/api")) return;
  const reportDoc = readFileSync("contracts/api/report-api.openapi.yaml", "utf8");
  for (const apiPath of ["/api/v1/report-uploads", "/api/v1/reports", "/api/v1/reports/{reportId}"]) {
    assert.ok(reportDoc.includes(`${apiPath}:`), `OpenAPI에 ${apiPath} 누락`);
  }
  for (const fixture of ["report-upload-intent.created.json", "report-status.ok.json"]) {
    assert.ok(existsSync(`contracts/api/fixtures/${fixture}`), `${fixture} 누락`);
  }
});

test("datapack compatibility matrix가 번들 index schemaVersion을 허용한다", () => {
  const matrix = loadJson("contracts/datapack/compatibility-matrix.json");
  const index = loadJson("apps/mobile/assets/datapacks/index.json");

  assert.ok(
    matrix.mobile.some((mobile) => mobile.acceptsIndexSchemaVersions.includes(index.schemaVersion)),
    "현재 번들 index schemaVersion을 허용하는 mobile 범위가 없다",
  );
});

test("gate-index가 apps/mobile/release 실물과 1:1 대응한다", () => {
  const errors = collectContractErrors().filter((error) => error.includes("gate-index"));

  assert.deepEqual(errors, []);
});

test("env-scope-map이 .env.example 키와 1:1 대응한다", () => {
  const errors = collectContractErrors().filter((error) => error.includes("env-scope-map"));

  assert.deepEqual(errors, []);
});
