import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

const resourceKeys = [
  "platform/deployment-contract.json",
  "platform/k3s-activation-contract.json",
  "platform/k3s-runtime-contract.json",
  "platform/k3s-runtime-contract.schema.json",
  "platform/k3s-activation-receipt.schema.json",
];

test("platform contract bundle v1.0.0은 기존 공개 바이트를 변경하지 않는다", async () => {
  const bytes = await readFile("contracts/bundles/platform-contracts-v1.0.0.json");
  const bundle = JSON.parse(bytes);

  assert.equal(sha256(bytes), "a4cc96ac0944ef7cbcba9470a3eb29e473e8f9e6076e729c4b020b1d5428a209");
  assert.equal(bundle.bundleVersion, "1.0.0");
  assert.deepEqual(Object.keys(bundle.resources), ["platform/deployment-contract.json"]);
});

test("platform contract bundle v1.1.0은 Platform #130 merge의 5개 resource 바이트를 고정한다", async () => {
  const bundle = JSON.parse(await readFile("contracts/bundles/platform-contracts-v1.1.0.json", "utf8"));
  const deploymentContract = await readFile("contracts/release/platform-deployment-contract.json", "utf8");
  const componentSchema = await readFile("contracts/release/component-manifest.schema.json");
  const issueRefSchema = await readFile("contracts/release/issue-ref.schema.json");

  assert.deepEqual(Object.keys(bundle), [
    "schemaVersion", "bundleVersion", "componentManifestSchemaSha256", "issueRefSchemaSha256", "resources",
  ]);
  assert.equal(bundle.schemaVersion, 1);
  assert.equal(bundle.bundleVersion, "1.1.0");
  assert.equal(bundle.componentManifestSchemaSha256, sha256(componentSchema));
  assert.equal(bundle.issueRefSchemaSha256, sha256(issueRefSchema));
  assert.deepEqual(Object.keys(bundle.resources), resourceKeys);
  assert.equal(bundle.resources["platform/deployment-contract.json"], deploymentContract);
  assert.equal(sha256(bundle.resources["platform/k3s-activation-contract.json"]), "5e5cc0aec2423e5568acc25d92ca47fb81ab314b390372d5b068d8178c4b54e2");
  assert.equal(sha256(bundle.resources["platform/k3s-runtime-contract.json"]), "ce226499224b3a3279d6bf1e41a181fc2a47afe100d9230411e3d782de36220b");
  assert.equal(sha256(bundle.resources["platform/k3s-runtime-contract.schema.json"]), "9b7a6d208d826a7046a80bab99d2c6856f4e59f15b923f9081926c95a8c88bdd");
  assert.equal(sha256(bundle.resources["platform/k3s-activation-receipt.schema.json"]), "bb4d9e3e57e52186f29a651cd514c095790cb10b36ddb60dfa490e80c16fe8b4");

  const activation = JSON.parse(bundle.resources["platform/k3s-activation-contract.json"]);
  const runtime = JSON.parse(bundle.resources["platform/k3s-runtime-contract.json"]);
  const runtimeSchema = JSON.parse(bundle.resources["platform/k3s-runtime-contract.schema.json"]);
  const receiptSchema = JSON.parse(bundle.resources["platform/k3s-activation-receipt.schema.json"]);
  assert.equal(activation.foundation.runtimeContract, "contracts/release/platform-k3s-runtime-contract.json");
  assert.equal(activation.receipt.schema, "contracts/release/platform-k3s-activation-receipt.schema.json");
  assert.equal(activation.trafficCommit.linearizationPoint, "SERVICE_RESOURCE_VERSION_CAS");
  assert.equal(activation.rollback.policy, "FORBIDDEN");
  assert.equal(activation.fallback.policy, "FORBIDDEN");
  assert.deepEqual(runtimeSchema.const, runtime);
  assert.deepEqual(receiptSchema.oneOf, [{ $ref: "#/$defs/success" }, { $ref: "#/$defs/failure" }]);
});
