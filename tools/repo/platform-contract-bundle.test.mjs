import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

test("platform contract bundle은 digest deployment 입력과 schema identity만 고정한다", async () => {
  const bundle = JSON.parse(await readFile("contracts/bundles/platform-contracts-v1.0.0.json", "utf8"));
  const deploymentContract = await readFile("contracts/release/platform-deployment-contract.json", "utf8");
  const componentSchema = await readFile("contracts/release/component-manifest.schema.json");
  const issueRefSchema = await readFile("contracts/release/issue-ref.schema.json");

  assert.deepEqual(Object.keys(bundle), [
    "schemaVersion", "bundleVersion", "componentManifestSchemaSha256", "issueRefSchemaSha256", "resources",
  ]);
  assert.equal(bundle.schemaVersion, 1);
  assert.equal(bundle.bundleVersion, "1.0.0");
  assert.equal(bundle.componentManifestSchemaSha256, sha256(componentSchema));
  assert.equal(bundle.issueRefSchemaSha256, sha256(issueRefSchema));
  assert.deepEqual(Object.keys(bundle.resources), ["platform/deployment-contract.json"]);
  assert.equal(bundle.resources["platform/deployment-contract.json"], deploymentContract);

  const contract = JSON.parse(deploymentContract);
  assert.deepEqual(contract.allowedProducerRepositories, ["AquilaXk/easysubway", "AquilaXk/easysubway-backend"]);
  assert.equal(contract.imageRepository, "ghcr.io/aquilaxk/easysubway-backend");
  assert.equal(contract.platformRepository, "AquilaXk/easysubway-platform");
  assert.deepEqual(contract.forbiddenInputs, ["branch", "buildContext", "sourceDirectory", "mutableImageTag"]);
});
