import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import {
  collectContractErrors,
  loadJson,
  validateCompatibilityMatrixPayload,
  validateDatapackIndex,
  validateDatapackManifest,
  validateJson,
} from "./check-contracts.mjs";
import { validateSchema } from "./lib/json-schema-lite.mjs";

test("번들 datapack index 실물이 계약 스키마를 통과한다", () => {
  const schema = loadJson("contracts/datapack/datapack-index.schema.json");
  const index = loadJson("apps/mobile/assets/datapacks/index.json");

  assert.deepEqual(validateSchema(schema, index).errors, []);
});

test("번들 datapack index는 실재하지 않는 UTC 시각을 거부한다", () => {
  const errors = [];

  validateDatapackIndex({
    builtAt: "2026-02-31T00:00:00.000Z",
    qualityAsOf: "2026-07-12T25:00:00.000Z",
    freshnessExpiresAt: "2026-08-11T00:00:00.000Z",
  }, "index.json", errors);

  assert.deepEqual(errors, [
    "index.json: builtAt은 유효한 UTC 시각이어야 한다",
    "index.json: qualityAsOf은 유효한 UTC 시각이어야 한다",
  ]);
});

test("번들 source-inventory 실물이 계약 스키마를 통과한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");

  assert.deepEqual(validateSchema(schema, inventory).errors, []);
});

test("inventory provenance 전용 source는 production 사용 금지만 선언할 수 있다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const provenanceOnlySource = inventory.sources.find((source) => source.productionUseAllowed === false);

  assert.ok(provenanceOnlySource, "production 사용 금지 source fixture가 필요하다");
  assert.deepEqual(validateSchema(schema, inventory).errors, []);

  provenanceOnlySource.productionUseAllowed = true;
  assert.deepEqual(
    validateSchema(schema, inventory).errors,
    [`$.sources.${inventory.sources.indexOf(provenanceOnlySource)}.productionUseAllowed: const false 불일치`],
  );
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

test("필수 계약 입력 파일이 없으면 실패한다", () => {
  const errors = [];

  validateJson("contracts/missing.schema.json", "contracts/missing-value.json", errors);

  assert.deepEqual(errors, ["contracts/missing.schema.json 누락", "contracts/missing-value.json 누락"]);
});

test("v1 datapack manifest는 activePack을 요구하고 v2는 생략할 수 있다", () => {
  const errors = [];

  validateDatapackManifest({ ttlSeconds: 1, packs: [] }, "manifest-v1.json", errors);
  validateDatapackManifest(minimalV2Manifest(), "manifest-v2.json", errors);

  assert.deepEqual(errors, ["manifest-v1.json: manifestVersion 1은 activePack이 필요하다"]);
});

test("v2 datapack manifest는 envelope 필드를 요구한다", () => {
  const errors = [];

  validateDatapackManifest({ manifestVersion: 2, ttlSeconds: 1, packs: [] }, "manifest-v2.json", errors);

  assert.deepEqual(errors, [
    "manifest-v2.json: manifestVersion 2는 signature이 필요하다",
    "manifest-v2.json: manifestVersion 2는 keyId이 필요하다",
    "manifest-v2.json: manifestVersion 2는 channel이 필요하다",
    "manifest-v2.json: manifestVersion 2는 releaseSequence이 필요하다",
    "manifest-v2.json: manifestVersion 2는 publishedAt이 필요하다",
    "manifest-v2.json: manifestVersion 2는 expiresAt이 필요하다",
  ]);
});

test("datapack manifest rollout percentage는 100을 넘을 수 없다", () => {
  const errors = [];

  validateDatapackManifest(
    {
      ttlSeconds: 1,
      activePack: { id: "capital", version: "1" },
      rollout: { percentage: 101 },
      packs: [],
    },
    "manifest-v1.json",
    errors,
  );

  assert.deepEqual(errors, ["manifest-v1.json: rollout.percentage는 100 이하여야 한다"]);
});

test("datapack manifest 스키마는 production URL과 RSA 서명을 허용한다", () => {
  const schema = loadJson("contracts/datapack/datapack-manifest.schema.json");
  const manifest = {
    ttlSeconds: 1,
    activePack: { id: "capital", version: "1" },
    packs: [
      {
        id: "capital",
        version: "1",
        artifactKind: "production",
        url: "https://cdn.easysubway.kr/releases/catalog/capital-v1.sqlite.gz",
        sha256: "a".repeat(64),
        sqliteSha256: "b".repeat(64),
        sizeBytes: 1,
        signature: {
          algorithm: "rsa-sha256-pack-manifest-v1",
          value: "rsaSha256PackSignature_1",
        },
        schemaVersion: "1",
        sourceInventory: [{ id: "official-source", licenseStatus: "redistributable", updatedAt: "2026-07-07" }],
        regionalQualityMetrics: {},
        representativeRouteRegressions: [],
        representativeRouteRegressionSignature: {
          algorithm: "rsa-sha256-route-regression-v1",
          value: "rsaSha256RouteSignature_1",
        },
        requiredTables: ["stations"],
        minimumTableRows: { stations: 1 },
      },
    ],
  };

  assert.deepEqual(validateSchema(schema, manifest).errors, []);
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

test("datapack compatibility matrix는 현재 번들을 지원하는 mobile 행 하나를 요구한다", () => {
  const errors = [];

  validateCompatibilityMatrixPayload(
    {
      mobile: [
        { appVersionRange: "<1.0.0", acceptsIndexSchemaVersions: [0] },
        { appVersionRange: ">=1.0.0", acceptsIndexSchemaVersions: [1] },
      ],
    },
    { schemaVersion: 1 },
    errors,
  );

  assert.deepEqual(errors, []);
});

test("gate-index가 apps/mobile/release 실물과 1:1 대응한다", () => {
  const errors = collectContractErrors().filter((error) => error.includes("gate-index"));

  assert.deepEqual(errors, []);
});

test("env-scope-map이 .env.example 키와 1:1 대응한다", () => {
  const errors = collectContractErrors().filter((error) => error.includes("env-scope-map"));

  assert.deepEqual(errors, []);
});

function minimalV2Manifest() {
  return {
    manifestVersion: 2,
    ttlSeconds: 1,
    signature: { algorithm: "sha256-manifest-v2", value: "a".repeat(64) },
    keyId: "fixture",
    channel: "stable",
    releaseSequence: 1,
    publishedAt: "2026-07-07T00:00:00.000Z",
    expiresAt: "2026-07-08T00:00:00.000Z",
    packs: [],
  };
}
