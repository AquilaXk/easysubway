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
