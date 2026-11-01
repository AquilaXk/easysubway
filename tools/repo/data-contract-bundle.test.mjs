import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { buildDataContractBundle } from "./build-data-contract-bundle.mjs";

const resources = new Map([
  ["datapack/mobility-profile-policy.json", "release/product-gates/mobility-profile-policy.json"],
  ["datapack/datapack-freshness-sla.json", "release/product-gates/datapack-freshness-sla.json"],
  ["datapack/source-governance-policy.json", "tools/datapack/source-governance-policy.json"],
  ["datapack/datapack-manifest-acceptance-policy.json", "apps/mobile/release/datapack-manifest-acceptance-policy.json"],
  ["datapack/production-datapack-scope.json", "release/product-gates/production-datapack-scope.json"],
  ["datapack/train-search-itx-exclusion-gate.json", "release/product-gates/train-search-itx-exclusion-gate.json"],
]);
// 거버넌스 원장에서 퇴역한 KRIC 접근성 원천 5건이다(AquilaXk/easysubway-data tools/datapack/lib/retired-sources.mjs와 같은 목록).
// Hub 계약 어디에도 다시 들어오면 안 된다. 옛 데이터팩 잔재가 production surface로 되돌아오는 것을 막는 fail-closed 방어 목록이다.
const retiredSourceIds = [
  "kric-station-elevator",
  "kric-station-elevator-movement",
  "kric-station-escalator",
  "kric-wheelchair-lift-location",
  "kric-wheelchair-lift-movement",
];
const requiredProductionSourceIds = [
  "incheon-transit-accessibility",
  "molit-urban-rail-full-route",
  "seoulmetro-station-line-info",
  "seoul-metro-accessibility",
  "seoul-metro-route-map-positions",
  "kric-station-convenience-standard",
  "kric-subway-timetable",
  "seoul-metro-transfer-distance-duration",
];
// data 레포 신선도 정책에는 있지만 Hub governance·inventory 사본에는 없는 원천의 닫힌 목록이다.
// - 인천 원천 3개: governance 등록(라이선스 검토)이 아직 없다(easysubway-data#868).
// - seoul-metro-transfer-car-door-duration: Hub inventory 계약(check-contracts 2129-2141)이 data 항목
//   (productionUseAllowed:true, domain evidence 없음)을 거부한다. 정합은 easysubway-data#888에서 처리한다.
// - kric-subway-timetable-station-lines: data 레포 등록(easysubway-data#903) 전이라 Hub 사본에 아직 없다.
// - kric-station-escalator-detailed: data 레포 등록(easysubway-data#1460) 전이라 Hub 사본에 아직 없다.
const dataRepositoryOnlyFreshnessSourceIds = [
  "incheon-line1-train-timetable",
  "incheon-line2-train-timetable",
  "incheon-transit-station-info",
  "kric-station-escalator-detailed",
  "kric-subway-timetable-station-lines",
  "seoul-metro-transfer-car-door-duration",
];
// candidate가 production inventory 항목을 가리키는데 Hub inventory 사본에 아직 없는 원천의 닫힌 목록이다.
// seoul-metro-transfer-car-door-duration: Hub inventory 계약이 data 항목을 거부한다(위 dataRepositoryOnlyFreshnessSourceIds와 같은 사유).
const dataRepositoryOnlyInventoryReferenceIds = ["seoul-metro-transfer-car-door-duration", "kric-station-escalator-detailed"];
const externalSourceRegistrations = [
  {
    sourceId: "incheon-transit-accessibility",
    registrationRepository: "AquilaXk/easysubway-data",
    registrationIssue: 622,
    snapshotId: "incheon-transit-accessibility-20260828T043356000Z",
    decision: "APPROVED",
    productionUseAllowed: true,
  },
  {
    sourceId: "seoul-metro-transfer-distance-duration",
    registrationRepository: "AquilaXk/easysubway-data",
    registrationIssue: 350,
    snapshotId: "seoul-metro-transfer-distance-duration-20260815T094038817Z",
    decision: "APPROVED",
    productionUseAllowed: true,
  },
  {
    sourceId: "seoul-metro-route-map-positions",
    registrationRepository: "AquilaXk/easysubway-data",
    registrationIssue: 447,
    snapshotId: "seoul-metro-route-map-positions-current-20260824T114822985Z",
    decision: "APPROVED",
    productionUseAllowed: true,
  },
];

test("data contract bundle은 target producer 입력만 exact bytes로 고정한다", async () => {
  const bundle = JSON.parse(await readFile("contracts/bundles/data-contracts-v1.0.0.json", "utf8"));

  assert.deepEqual(Object.keys(bundle), ["schemaVersion", "bundleVersion", "resources"]);
  assert.equal(bundle.schemaVersion, 1);
  assert.equal(bundle.bundleVersion, "1.0.0");
  assert.deepEqual(Object.keys(bundle.resources), [...resources.keys()]);
  for (const [resource, source] of resources) {
    assert.equal(bundle.resources[resource], await readFile(source, "utf8"));
  }
});

test("data contract bundle generator는 닫힌 resource set의 현재 바이트만 재생성한다", async () => {
  const [generated, existing] = await Promise.all([
    buildDataContractBundle({ repositoryRoot: process.cwd() }),
    readFile("contracts/bundles/data-contracts-v1.0.0.json"),
  ]);

  assert.deepEqual(generated, existing);
});

test("data contract bundle v1.1.0은 갱신된 Datapack 스키마를 포함하여 exact bytes로 고정한다", async () => {
  const bundle = JSON.parse(await readFile("contracts/bundles/data-contracts-v1.1.0.json", "utf8"));

  assert.deepEqual(Object.keys(bundle), ["schemaVersion", "bundleVersion", "resources"]);
  assert.equal(bundle.schemaVersion, 1);
  assert.equal(bundle.bundleVersion, "1.1.0");
  const expectedKeys = [...resources.keys(), "datapack/source-inventory.schema.json"];
  assert.deepEqual(Object.keys(bundle.resources), expectedKeys);
  for (const [resource, source] of resources) {
    assert.equal(bundle.resources[resource], await readFile(source, "utf8"));
  }
  assert.equal(
    bundle.resources["datapack/source-inventory.schema.json"],
    await readFile("contracts/datapack/source-inventory.schema.json", "utf8"),
  );

  const generated = await buildDataContractBundle({ repositoryRoot: process.cwd(), version: "1.1.0" });
  const existing = await readFile("contracts/bundles/data-contracts-v1.1.0.json");
  assert.deepEqual(generated, existing);
});

test("data contract bundle --write는 output symlink와 그 referent를 거부한다", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "data-contract-bundle-output-"));
  const outputPath = path.join(directory, "contracts/bundles/data-contracts-v1.0.0.json");
  const referentPath = path.join(directory, "outside-referent.json");
  try {
    for (const sourcePath of resources.values()) {
      const target = path.join(directory, sourcePath);
      mkdirSync(path.dirname(target), { recursive: true });
      writeFileSync(target, readFileSync(sourcePath));
    }
    mkdirSync(path.dirname(outputPath), { recursive: true });
    writeFileSync(referentPath, "outside bytes\n");
    symlinkSync(referentPath, outputPath);

    const result = spawnSync(process.execPath, [
      path.resolve("tools/repo/build-data-contract-bundle.mjs"),
      "--write",
    ], { cwd: directory, encoding: "utf8" });

    assert.equal(result.status, 1);
    assert.match(result.stderr, /data contract bundle output must not contain a symlink/);
    assert.equal(readFileSync(referentPath, "utf8"), "outside bytes\n");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("data bundle은 current governance를 고정하고 backend bundle은 historical bytes를 보존한다", async () => {
  const [dataBundle, backendBundle, governance] = await Promise.all([
    readFile("contracts/bundles/data-contracts-v1.0.0.json", "utf8").then(JSON.parse),
    readFile("contracts/bundles/backend-contracts-v1.0.0.json", "utf8").then(JSON.parse),
    readFile("tools/datapack/source-governance-policy.json", "utf8"),
  ]);

  assert.equal(dataBundle.resources["datapack/source-governance-policy.json"], governance);
  const historicalGovernance = backendBundle.resources["datapack/source-governance-policy.json"];
  assert.notEqual(historicalGovernance, governance);
  const sources = new Map(JSON.parse(governance).sources.map((source) => [source.sourceId, source]));
  const historicalSources = new Map(JSON.parse(historicalGovernance).sources.map((source) => [source.sourceId, source]));
  assert.equal(sources.get("seoul-metro-route-map-positions").sourceClassId, "route_map_positions");
  assert.equal(sources.get("seoulmetro-cyberstation-route-map").sourceClassId, "route_map_asset_historical");
  assert.equal(historicalSources.get("seoul-metro-route-map-positions").sourceClassId, "route_map_positions");
  assert.equal(historicalSources.get("seoulmetro-cyberstation-route-map").sourceClassId, "route_map_asset_historical");
  assert.equal(sources.has("incheon-transit-accessibility"), true);
  assert.equal(historicalSources.has("incheon-transit-accessibility"), false);
});

test("current route-map source admission license evidence는 승인된 governance terms와 일치한다", async () => {
  const [inventory, governance] = await Promise.all([
    readFile("apps/mobile/assets/datapacks/source-inventory.json", "utf8").then(JSON.parse),
    readFile("tools/datapack/source-governance-policy.json", "utf8").then(JSON.parse),
  ]);
  const source = inventory.sources.find((candidate) => candidate.id === "seoul-metro-route-map-positions");
  const policy = governance.sources.find((candidate) => candidate.sourceId === source.id);

  assert.equal(source.admissionEvidence?.licenseEvidenceHash, policy.licenseReview.termsHash);
});

test("staged freshness와 governance는 annual official source binding 및 license evidence를 정확히 공유한다", async () => {
  const [freshness, governance, inventory, mobileInventory] = await Promise.all([
    readFile("release/product-gates/datapack-freshness-sla.json", "utf8").then(JSON.parse),
    readFile("tools/datapack/source-governance-policy.json", "utf8").then(JSON.parse),
    readFile("tools/datapack/source-inventory.json", "utf8").then(JSON.parse),
    readFile("apps/mobile/assets/datapacks/source-inventory.json", "utf8").then(JSON.parse),
  ]);
  const governanceBySource = new Map(governance.sources.map((source) => [source.sourceId, source]));
  const freshnessSourceIds = freshness.sourceClasses.flatMap((sourceClass) => sourceClass.sourceIds).sort();

  // data release는 이 번들의 freshness로 governance 결속을 판정하므로 class 등록은 Hub에 있어야 한다
  // (easysubway-data#876). governance owner 없는 freshness 원천은 닫힌 예외 목록만 허용한다.
  assert.deepEqual(
    freshnessSourceIds.filter((sourceId) => !governanceBySource.has(sourceId)),
    dataRepositoryOnlyFreshnessSourceIds,
  );
  assert.deepEqual(
    [...governanceBySource.keys()].sort(),
    freshnessSourceIds.filter((sourceId) => !dataRepositoryOnlyFreshnessSourceIds.includes(sourceId)),
  );
  for (const [sourceId, entry] of governanceBySource) {
    const sourceClass = freshness.sourceClasses.find((candidate) => candidate.id === entry.sourceClassId);
    assert.ok(sourceClass?.sourceIds.includes(sourceId), `${sourceId}: governance class binding`);
  }
  for (const sourceId of ["incheon-transit-accessibility", "molit-railway-transfer-movement", "seoul-metro-transfer-distance-duration"]) {
    const source = inventory.sources.find((candidate) => candidate.id === sourceId);
    const mobileSource = mobileInventory.sources.find((candidate) => candidate.id === sourceId);
    assert.equal(source.admissionEvidence?.licenseEvidenceHash, governanceBySource.get(sourceId).licenseReview.termsHash);
    assert.equal(mobileSource.admissionEvidence?.licenseEvidenceHash, governanceBySource.get(sourceId).licenseReview.termsHash);
  }
});

test("datapack freshness SLA는 current public route-map position과 연간 공식 환승 파일 정책을 고정한다", async () => {
  const policy = JSON.parse(await readFile("release/product-gates/datapack-freshness-sla.json", "utf8"));
  const classes = new Map(policy.sourceClasses.map((sourceClass) => [sourceClass.id, sourceClass]));

  assert.deepEqual(
    policy.sourceClasses.map((sourceClass) => sourceClass.id),
    [
      "static_network_metadata",
      "static_accessibility_facility",
      "planned_timetable",
      "route_map_positions",
      "route_map_asset_historical",
      "annual_official_file",
      "realtime_overlay",
      "route_graph_topology",
      "official_static_timetable_confirmation",
      "daejeon_timetable_observation",
      "busan_timetable_observation",
      "daegu_timetable_observation",
      "incheon_timetable_observation",
    ],
  );
  assert.deepEqual(classes.get("route_map_positions"), {
    id: "route_map_positions",
    sourceIds: ["seoul-metro-route-map-positions"],
    examples: ["official public station code/name/latitude/longitude", "versioned deterministic route-map layout"],
    basisField: "retrievedAt",
    reverificationCadence: "P90D",
    offlinePackEligible: true,
    eventTriggers: ["official public data revision", "new station opening", "line extension opening"],
    changePublishSla: "P3D",
    freshnessMetric: "routeMapPositionFreshnessRatio",
  });
  assert.equal(classes.has("route_map_asset"), false);
  assert.deepEqual(classes.get("route_map_asset_historical"), {
    id: "route_map_asset_historical",
    sourceIds: ["seoulmetro-cyberstation-route-map"],
    examples: ["historical web route-map diagnostic only"],
    basisField: "retrievedAt",
    reverificationCadence: "P1Y",
    offlinePackEligible: false,
    eventTriggers: ["historical evidence review"],
    changePublishSla: "not-applicable",
    freshnessMetric: "routeMapPositionFreshnessRatio",
  });
  assert.deepEqual(classes.get("annual_official_file"), {
    id: "annual_official_file",
    sourceIds: [
      "molit-railway-transfer-movement",
      "seoul-metro-transfer-distance-duration",
      "seoul-metro-transfer-car-door-duration",
    ],
    examples: ["official annual railway transfer movement CSV"],
    basisField: "observedAt",
    reverificationCadence: "P1Y",
    offlinePackEligible: true,
    eventTriggers: ["official file revision", "station transfer path revision", "line or station opening"],
    changePublishSla: "P14D",
    freshnessMetric: "freshnessValidRatio",
  });
  assert.equal(classes.get("planned_timetable").unchangedReverificationBasisField, "reverifiedUnchangedAt");
  assert.ok(classes.get("route_graph_topology").sourceIds.includes("incheon-transit-station-info"));
  // QA 승인(2026-10-02): 노선 topology는 이벤트 기반 갱신이고, 재검증 실패가 일주일 이어지면 만료로 막는 P7D 안전망을 둔다.
  // 일일 재확인 주기(monitoring·scheduledPipeline P1D)는 그대로 유지한다(#870).
  assert.equal(classes.get("route_graph_topology").reverificationCadence, "P7D");
  assert.equal(policy.monitoring.manualCheckCadence, "P1D");
  assert.equal(policy.scheduledPipeline.cadence, "P1D");
  for (const version of ["1.0.0", "1.1.0"]) {
    const bundle = JSON.parse(await readFile(`contracts/bundles/data-contracts-v${version}.json`, "utf8"));
    const bundled = JSON.parse(bundle.resources["datapack/datapack-freshness-sla.json"]);
    assert.equal(
      bundled.sourceClasses.find((sourceClass) => sourceClass.id === "route_graph_topology").reverificationCadence,
      "P7D",
      `data-contracts-v${version} route_graph_topology cadence`,
    );
  }
  // QA 승인(2026-10-03, data#903): KRIC 역별 시간표(GTX-A·에버라인·의정부·김포골드·부산김해)는
  // 같은 KRIC subwayTimetable 계획 시간표 원천을 새 sourceId로 등록하므로 planned_timetable 기준을 그대로 따른다.
  assert.deepEqual(classes.get("planned_timetable").sourceIds, [
    "korail-metropolitan-planned-timetable",
    "kric-subway-timetable",
    "kric-subway-timetable-station-lines",
  ]);
  for (const version of ["1.0.0", "1.1.0"]) {
    const bundle = JSON.parse(await readFile(`contracts/bundles/data-contracts-v${version}.json`, "utf8"));
    const bundled = JSON.parse(bundle.resources["datapack/datapack-freshness-sla.json"]);
    assert.ok(
      bundled.sourceClasses.find((sourceClass) => sourceClass.id === "planned_timetable").sourceIds.includes("kric-subway-timetable-station-lines"),
      `data-contracts-v${version} planned_timetable station-lines source`,
    );
  }
  // QA 승인(2026-10-23, 에픽 #3036 7-34행): KRIC 역 에스컬레이터 상세(stationEscalator)를 재채택한다.
  // 위치·설비 정적 접근성 원천이므로 static_accessibility_facility 기준을 그대로 따른다(data#1460).
  assert.equal(classes.get("static_accessibility_facility").sourceIds.at(-1), "kric-station-escalator-detailed");
  for (const version of ["1.0.0", "1.1.0"]) {
    const bundle = JSON.parse(await readFile(`contracts/bundles/data-contracts-v${version}.json`, "utf8"));
    const bundled = JSON.parse(bundle.resources["datapack/datapack-freshness-sla.json"]);
    assert.ok(
      bundled.sourceClasses.find((sourceClass) => sourceClass.id === "static_accessibility_facility").sourceIds.includes("kric-station-escalator-detailed"),
      `data-contracts-v${version} static_accessibility_facility escalator-detailed source`,
    );
  }
  assert.deepEqual(classes.get("incheon_timetable_observation"), {
    id: "incheon_timetable_observation",
    sourceIds: ["incheon-line1-train-timetable", "incheon-line2-train-timetable"],
    basisField: "capturedAt",
    reverificationCadence: "P30D",
    futureBasisAllowed: false,
    providerValidityEndField: null,
    eventTriggers: ["official timetable revision"],
  });
});

test("production datapack은 retired movement source를 required·selected·coverage·candidate·direct-route 성공 surface에 포함하지 않는다", async () => {
  const readJson = async (file) => JSON.parse(await readFile(file, "utf8"));
  const [scope, bundle, input, candidate, reviewed, canonical, inventory, mobileInventory] = await Promise.all([
    readJson("release/product-gates/production-datapack-scope.json"),
    readJson("contracts/bundles/data-contracts-v1.0.0.json"),
    readJson("tools/datapack/inputs/capital-pilot-production-source-input.json"),
    readJson("tools/datapack/release/candidate-build-spec.json"),
    readJson("tools/datapack/release/capital-production-reviewed-pack.json"),
    readJson("tools/datapack/release/capital-production-canonical-pack.json"),
    readJson("tools/datapack/source-inventory.json"),
    readJson("apps/mobile/assets/datapacks/source-inventory.json"),
  ]);
  const bundledScope = JSON.parse(bundle.resources["datapack/production-datapack-scope.json"]);
  const packs = [reviewed, canonical].flatMap((fixture) => fixture.packs ?? []);

  assert.deepEqual(scope.productionSourceSet.requiredSourceIds, requiredProductionSourceIds);
  assert.deepEqual(bundledScope.productionSourceSet.requiredSourceIds, requiredProductionSourceIds);
  assert.deepEqual(
    scope.productionSourceSet.externalSourceRegistrations,
    externalSourceRegistrations,
  );
  assert.deepEqual(
    bundledScope.productionSourceSet.externalSourceRegistrations,
    externalSourceRegistrations,
  );

  for (const sourceId of retiredSourceIds) {
    assert.ok(!scope.productionSourceSet.requiredSourceIds.includes(sourceId), `${sourceId}: required`);
    assert.ok(!bundledScope.productionSourceSet.requiredSourceIds.includes(sourceId), `${sourceId}: bundled required`);
    assert.ok(!input.sourceIds.includes(sourceId), `${sourceId}: selected input`);
    assert.ok(!input.coverageEvidence.flatMap(({ sourceIds }) => sourceIds).includes(sourceId), `${sourceId}: input coverage`);
    assert.ok(!input.movementPathCandidates.some((candidate) => candidate.sourceId === sourceId), `${sourceId}: input candidate`);
    assert.ok(!candidate.sourceSnapshots.some((snapshot) => snapshot.sourceId === sourceId), `${sourceId}: candidate snapshot`);
    for (const pack of packs) {
      assert.ok(!pack.sourceInventory.some((source) => source.id === sourceId), `${sourceId}: pack selected`);
      assert.ok(!JSON.parse(pack.metadata.productionCoverageEvidence).some((entry) => entry.sourceIds.includes(sourceId)), `${sourceId}: pack coverage`);
      assert.ok(!pack.movementPathCandidates.some((candidate) => candidate.sourceId === sourceId), `${sourceId}: pack candidate`);
      assert.ok(!pack.networkEdges.some((edge) => edge.sourceId === sourceId && edge.accessibilityStatus === "AVAILABLE"), `${sourceId}: direct-route success`);
    }
    for (const sourceInventory of [inventory, mobileInventory]) {
      assert.ok(!sourceInventory.sources.some((source) => source.id === sourceId), `${sourceId}: retired from inventory`);
    }
  }
  assert.deepEqual(mobileInventory, inventory, "mobile inventory must match generated Hub inventory");
});

test("퇴역한 원천 5건은 freshness SLA, governance 사본, inventory 사본, 번들 어디에도 다시 들어오지 못한다", async () => {
  const readJson = async (file) => JSON.parse(await readFile(file, "utf8"));
  const [freshness, governance, inventory, mobileInventory] = await Promise.all([
    readJson("release/product-gates/datapack-freshness-sla.json"),
    readJson("tools/datapack/source-governance-policy.json"),
    readJson("tools/datapack/source-inventory.json"),
    readJson("apps/mobile/assets/datapacks/source-inventory.json"),
  ]);
  const surfaces = new Map([
    ["freshness SLA", freshness.sourceClasses.flatMap(({ sourceIds }) => sourceIds)],
    ["governance 사본", governance.sources.map(({ sourceId }) => sourceId)],
    ["Hub inventory 사본", inventory.sources.map(({ id }) => id)],
    ["모바일 inventory 사본", mobileInventory.sources.map(({ id }) => id)],
  ]);
  for (const version of ["1.0.0", "1.1.0"]) {
    const { resources } = await readJson(`contracts/bundles/data-contracts-v${version}.json`);
    const bundledFreshness = JSON.parse(resources["datapack/datapack-freshness-sla.json"]);
    const bundledGovernance = JSON.parse(resources["datapack/source-governance-policy.json"]);
    const bundledScope = JSON.parse(resources["datapack/production-datapack-scope.json"]);
    surfaces.set(`번들 ${version} freshness SLA`, bundledFreshness.sourceClasses.flatMap(({ sourceIds }) => sourceIds));
    surfaces.set(`번들 ${version} governance`, bundledGovernance.sources.map(({ sourceId }) => sourceId));
    surfaces.set(`번들 ${version} production scope`, bundledScope.productionSourceSet.requiredSourceIds);
  }
  for (const [surface, sourceIds] of surfaces) {
    assert.ok(sourceIds.length > 0, `${surface}: 비어 있지 않아야 비교가 의미 있다`);
    assert.deepEqual(sourceIds.filter((sourceId) => retiredSourceIds.includes(sourceId)), [], surface);
  }
});

test("미러된 source candidate가 가리키는 inventory 항목은 Hub inventory 사본에 존재한다", async () => {
  const [{ candidates }, inventory] = await Promise.all([
    readFile("tools/datapack/source-candidates.json", "utf8").then(JSON.parse),
    readFile("tools/datapack/source-inventory.json", "utf8").then(JSON.parse),
  ]);
  const inventoryIds = new Set(inventory.sources.map(({ id }) => id));
  const referenced = candidates.map(({ productionInventoryReferenceId }) => productionInventoryReferenceId).filter((id) => id != null);
  assert.ok(referenced.length > 0);
  assert.deepEqual(referenced.filter((id) => !inventoryIds.has(id)), dataRepositoryOnlyInventoryReferenceIds);
});
