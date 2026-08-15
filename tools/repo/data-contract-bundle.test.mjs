import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const resources = new Map([
  ["datapack/mobility-profile-policy.json", "release/product-gates/mobility-profile-policy.json"],
  ["datapack/datapack-freshness-sla.json", "release/product-gates/datapack-freshness-sla.json"],
  ["datapack/datapack-manifest-acceptance-policy.json", "apps/mobile/release/datapack-manifest-acceptance-policy.json"],
  ["datapack/production-datapack-scope.json", "release/product-gates/production-datapack-scope.json"],
  ["datapack/train-search-itx-exclusion-gate.json", "release/product-gates/train-search-itx-exclusion-gate.json"],
]);
const productionForbiddenMovementSourceIds = [
  "kric-station-elevator-movement",
  "kric-wheelchair-lift-movement",
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

test("datapack freshness SLA는 기존 source class와 연간 공식 환승 파일 정책을 고정한다", async () => {
  const policy = JSON.parse(await readFile("release/product-gates/datapack-freshness-sla.json", "utf8"));
  const classes = new Map(policy.sourceClasses.map((sourceClass) => [sourceClass.id, sourceClass]));

  assert.deepEqual(
    policy.sourceClasses.map((sourceClass) => sourceClass.id),
    [
      "static_network_metadata",
      "static_accessibility_facility",
      "planned_timetable",
      "route_map_asset",
      "realtime_overlay",
      "annual_official_file",
    ],
  );
  assert.deepEqual(classes.get("annual_official_file"), {
    id: "annual_official_file",
    sourceIds: ["molit-railway-transfer-movement", "seoul-metro-transfer-distance-duration"],
    examples: ["official annual railway transfer movement CSV"],
    basisField: "observedAt",
    reverificationCadence: "P1Y",
    offlinePackEligible: true,
    eventTriggers: ["official file revision", "station transfer path revision", "line or station opening"],
    changePublishSla: "P14D",
    freshnessMetric: "freshnessValidRatio",
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

  for (const sourceId of productionForbiddenMovementSourceIds) {
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
      const historical = sourceInventory.sources.find((source) => source.id === sourceId);
      assert.ok(historical, `${sourceId}: historical identity`);
      assert.equal(historical.productionUseAllowed, false, `${sourceId}: production eligibility`);
    }
  }
  assert.deepEqual(mobileInventory, inventory, "mobile inventory must match generated Hub inventory");
});
