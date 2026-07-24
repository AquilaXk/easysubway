import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  collectContractErrors,
  loadJson,
  validateCompatibilityMatrixPayload,
  validateDatapackIndex,
  validateDatapackManifest,
  validateJson,
  validateSourceInventory,
  validateSourceGovernanceContracts,
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
    freshnessExpiresAt: "2026-08-32T00:00:00.000Z",
  }, "index.json", errors);

  assert.deepEqual(errors, [
    "index.json: builtAt은 유효한 UTC 시각이어야 한다",
    "index.json: qualityAsOf은 유효한 UTC 시각이어야 한다",
    "index.json: freshnessExpiresAt은 유효한 UTC 시각이어야 한다",
  ]);
});

test("번들 datapack index semantic 검증은 비객체 입력에서 schema 오류를 가리지 않는다", () => {
  const directory = mkdtempSync(join(tmpdir(), "datapack-index-invalid-"));
  for (const [name, invalid] of [["null", null], ["array", []], ["string", "invalid"]]) {
    const valuePath = join(directory, `${name}.json`);
    writeFileSync(valuePath, JSON.stringify(invalid));
    const errors = [];

    assert.doesNotThrow(() => validateJson(
      "contracts/datapack/datapack-index.schema.json",
      valuePath,
      errors,
    ));
    assert.ok(errors.length > 0, `${name} 입력의 schema 오류가 필요하다`);
  }
});

test("번들 source-inventory 실물이 계약 스키마를 통과한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");

  assert.deepEqual(validateSchema(schema, inventory).errors, []);
});

test("source quota defaultDailyLimit는 허용된 scalar만 받는다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const admitted = inventory.sources.find((source) => source.admissionEvidence?.quotaEvidence != null);
  admitted.admissionEvidence.quotaEvidence.defaultDailyLimit = { unexpected: true };

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("quotaEvidence.defaultDailyLimit")
  )));
});

test("source admission evidence가 있으면 license evidence hash를 요구한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const admitted = inventory.sources.find((source) => source.admissionEvidence != null);
  delete admitted.admissionEvidence.licenseEvidenceHash;

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("admissionEvidence.licenseEvidenceHash")
  )));
});

test("source admission evidence envelope는 승인 필드 외 값을 거부하고 선택적으로 남는다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const admitted = inventory.sources.find((source) => source.admissionEvidence != null);
  admitted.admissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("admissionEvidence.serviceKey")
  )));

  delete admitted.admissionEvidence;
  assert.deepEqual(validateSchema(schema, inventory).errors, []);
});

test("inventory production 사용 승인은 domain별 admission evidence를 요구한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const admissionDomains = new Set([
    "route_graph_topology",
    "schedule_timetable",
    "station_line_membership",
    "route_map_positions",
    "accessibility_facilities",
  ]);
  const provenanceOnlySource = inventory.sources.find((source) => source.productionUseAllowed === false
    && !source.coverageScope.sourceDomains.some((domain) => admissionDomains.has(domain)));

  assert.ok(provenanceOnlySource, "production 사용 금지 source fixture가 필요하다");
  assert.deepEqual(validateSchema(schema, inventory).errors, []);

  provenanceOnlySource.productionUseAllowed = true;
  const errors = [];
  validateSourceInventory(inventory, "source-inventory.json", errors);
  assert.deepEqual(errors, [
    `source-inventory.json: $.sources.${inventory.sources.indexOf(provenanceOnlySource)}.productionUseAllowed: true는 production admission evidence가 필요하다`,
  ]);

  provenanceOnlySource.productionUseAllowed = false;
  errors.length = 0;
  const scheduleSource = inventory.sources.find((source) => source.scheduleAdmissionEvidence != null);
  scheduleSource.productionUseAllowed = false;
  validateSourceInventory(inventory, "source-inventory.json", errors);
  assert.equal(errors.at(-1),
    `source-inventory.json: $.sources.${inventory.sources.indexOf(scheduleSource)}.scheduleAdmissionEvidence: productionUseAllowed true가 필요하다`);
  assert.doesNotThrow(() => validateSourceInventory({ sources: {} }, "source-inventory.json", []));
});

test("production admission evidence는 coverage source domain과 일치해야 한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const topologySource = inventory.sources.find((source) => source.topologyAdmissionEvidence != null);
  const scheduleSource = inventory.sources.find((source) => source.scheduleAdmissionEvidence != null);
  const scheduleEvidence = structuredClone(scheduleSource.scheduleAdmissionEvidence);
  delete topologySource.topologyAdmissionEvidence;
  topologySource.scheduleAdmissionEvidence = scheduleEvidence;

  const errors = [];
  validateSourceInventory(inventory, "source-inventory.json", errors);

  assert.ok(errors.some((error) => error.includes("route_graph_topology production 승인은 topologyAdmissionEvidence가 필요하다")));
  assert.ok(errors.some((error) => error.includes("scheduleAdmissionEvidence: schedule_timetable source domain이 필요하다")));
});

test("membership production admission evidence는 domain과 production 승인을 함께 요구한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const membershipSource = inventory.sources.find((source) => source.membershipAdmissionEvidence != null);
  delete membershipSource.membershipAdmissionEvidence;

  const missingErrors = [];
  validateSourceInventory(inventory, "source-inventory.json", missingErrors);
  assert.ok(missingErrors.some((error) => error.includes(
    "station_line_membership production 승인은 membershipAdmissionEvidence가 필요하다",
  )));

  const freshInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const mismatchedSource = freshInventory.sources.find((source) => source.membershipAdmissionEvidence != null);
  mismatchedSource.coverageScope.sourceDomains = mismatchedSource.coverageScope.sourceDomains
    .filter((domain) => domain !== "station_line_membership");
  const mismatchedErrors = [];
  validateSourceInventory(freshInventory, "source-inventory.json", mismatchedErrors);
  assert.ok(mismatchedErrors.some((error) => error.includes(
    "membershipAdmissionEvidence: station_line_membership source domain이 필요하다",
  )));
});

test("route map production admission evidence는 domain과 production 승인을 함께 요구한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const routeMapSource = inventory.sources.find((source) => source.routeMapAdmissionEvidence != null);
  delete routeMapSource.routeMapAdmissionEvidence;

  const missingErrors = [];
  validateSourceInventory(inventory, "source-inventory.json", missingErrors);
  assert.ok(missingErrors.some((error) => error.includes(
    "route_map_positions production 승인은 routeMapAdmissionEvidence가 필요하다",
  )));

  const freshInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const mismatchedSource = freshInventory.sources.find((source) => source.routeMapAdmissionEvidence != null);
  mismatchedSource.coverageScope.sourceDomains = mismatchedSource.coverageScope.sourceDomains
    .filter((domain) => domain !== "route_map_positions");
  const mismatchedErrors = [];
  validateSourceInventory(freshInventory, "source-inventory.json", mismatchedErrors);
  assert.ok(mismatchedErrors.some((error) => error.includes(
    "routeMapAdmissionEvidence: route_map_positions source domain이 필요하다",
  )));

  const prohibitedInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const prohibitedSource = prohibitedInventory.sources.find((source) => source.routeMapAdmissionEvidence != null);
  prohibitedSource.productionUseAllowed = false;
  const prohibitedErrors = [];
  validateSourceInventory(prohibitedInventory, "source-inventory.json", prohibitedErrors);
  assert.ok(prohibitedErrors.some((error) => error.includes(
    "routeMapAdmissionEvidence: productionUseAllowed true가 필요하다",
  )));
});

test("accessibility production admission evidence는 domain과 production 승인을 함께 요구한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const accessibilitySource = inventory.sources.find((source) => source.accessibilityAdmissionEvidence != null);
  delete accessibilitySource.accessibilityAdmissionEvidence;

  const missingErrors = [];
  validateSourceInventory(inventory, "source-inventory.json", missingErrors);
  assert.ok(missingErrors.some((error) => error.includes(
    "accessibility_facilities production 승인은 accessibilityAdmissionEvidence가 필요하다",
  )));

  const freshInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const mismatchedSource = freshInventory.sources.find((source) => source.accessibilityAdmissionEvidence != null);
  mismatchedSource.coverageScope.sourceDomains = mismatchedSource.coverageScope.sourceDomains
    .filter((domain) => domain !== "accessibility_facilities");
  const mismatchedErrors = [];
  validateSourceInventory(freshInventory, "source-inventory.json", mismatchedErrors);
  assert.ok(mismatchedErrors.some((error) => error.includes(
    "accessibilityAdmissionEvidence: accessibility_facilities source domain이 필요하다",
  )));

  const prohibitedInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const prohibitedSource = prohibitedInventory.sources.find((source) => source.accessibilityAdmissionEvidence != null);
  prohibitedSource.productionUseAllowed = false;
  const prohibitedErrors = [];
  validateSourceInventory(prohibitedInventory, "source-inventory.json", prohibitedErrors);
  assert.ok(prohibitedErrors.some((error) => error.includes(
    "accessibilityAdmissionEvidence: productionUseAllowed true가 필요하다",
  )));
});

test("source inventory semantic 검증은 schema-invalid sourceDomains에서 오류 수집을 중단하지 않는다", () => {
  assert.doesNotThrow(() => validateSourceInventory({
    sources: [{ coverageScope: { sourceDomains: 1 } }],
  }, "source-inventory.json", []));
});

test("topology admission evidence는 승인 필드 외 값을 거부한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const topologySource = inventory.sources.find((source) => source.topologyAdmissionEvidence != null);

  topologySource.topologyAdmissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("topologyAdmissionEvidence.serviceKey")
  )));
});

test("schedule admission evidence는 승인 필드 외 값을 거부한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const scheduleSource = inventory.sources.find((source) => source.scheduleAdmissionEvidence != null);

  scheduleSource.scheduleAdmissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("scheduleAdmissionEvidence.serviceKey")
  )));
});

test("membership admission evidence는 승인 필드 외 값을 거부한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const membershipSource = inventory.sources.find((source) => source.membershipAdmissionEvidence != null);

  membershipSource.membershipAdmissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("membershipAdmissionEvidence.serviceKey")
  )));
});

test("route map admission evidence는 승인 필드 외 값을 거부한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const routeMapSource = inventory.sources.find((source) => source.routeMapAdmissionEvidence != null);

  routeMapSource.routeMapAdmissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("routeMapAdmissionEvidence.serviceKey")
  )));
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

test("check-contracts는 inventory·freshness·governance 참조를 함께 검증한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const freshnessPolicy = loadJson("apps/mobile/release/datapack-freshness-sla.json");
  const governancePolicy = loadJson("tools/datapack/source-governance-policy.json");
  governancePolicy.sources[0].retentionClassId = "missing-retention-class";
  const errors = [];

  validateSourceGovernanceContracts({ governancePolicy, inventory, freshnessPolicy }, errors);

  assert.equal(errors.length, 1);
  assert.match(errors[0], /RAW_RETENTION_OVERDUE/);
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
