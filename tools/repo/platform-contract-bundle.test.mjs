import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

test("platform contract bundle은 immutable deployment 및 K3s 계약 입력과 schema identity를 고정한다", async () => {
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
  assert.deepEqual(Object.keys(bundle.resources), [
    "platform/deployment-contract.json",
    "platform/k3s-activation-contract.json",
    "platform/k3s-runtime-contract.json",
    "platform/k3s-runtime-contract.schema.json",
    "platform/k3s-activation-receipt.schema.json",
  ]);
  assert.equal(bundle.resources["platform/deployment-contract.json"], deploymentContract);
  assert.equal(sha256(bundle.resources["platform/k3s-activation-contract.json"]), "5e5cc0aec2423e5568acc25d92ca47fb81ab314b390372d5b068d8178c4b54e2");
  assert.equal(sha256(bundle.resources["platform/k3s-runtime-contract.json"]), "ce226499224b3a3279d6bf1e41a181fc2a47afe100d9230411e3d782de36220b");
  assert.equal(sha256(bundle.resources["platform/k3s-runtime-contract.schema.json"]), "9b7a6d208d826a7046a80bab99d2c6856f4e59f15b923f9081926c95a8c88bdd");
  assert.equal(sha256(bundle.resources["platform/k3s-activation-receipt.schema.json"]), "150b0d16273dee3c939d03a89d615200b3fe06cbd3846f66b604ba3e357e2061");

  const activation = JSON.parse(bundle.resources["platform/k3s-activation-contract.json"]);
  const runtime = JSON.parse(bundle.resources["platform/k3s-runtime-contract.json"]);
  const runtimeSchema = JSON.parse(bundle.resources["platform/k3s-runtime-contract.schema.json"]);
  const receiptSchema = JSON.parse(bundle.resources["platform/k3s-activation-receipt.schema.json"]);
  assert.equal(activation.foundation.runtimeContract, "contracts/release/platform-k3s-runtime-contract.json");
  assert.equal(activation.receipt.schema, "contracts/release/platform-k3s-activation-receipt.schema.json");
  assert.deepEqual(activation.receipt.bundleAcquisitionEvidence, {
    field: "bundleAcquisitionEvidenceDigest",
    digestMeaning: "DIRECT_SHA256_OF_CREATE_ONLY_CANONICAL_BUNDLE_ACQUISITION_EVIDENCE",
    requiredForV1: false,
  });
  assert.equal(activation.trafficCommit.linearizationPoint, "SERVICE_RESOURCE_VERSION_CAS");
  assert.equal(activation.rollback.policy, "FORBIDDEN");
  assert.equal(activation.fallback.policy, "FORBIDDEN");
  assert.deepEqual(runtimeSchema.const, runtime);
  assert.equal(receiptSchema.$schema, "https://json-schema.org/draft/2020-12/schema");
  assert.equal(receiptSchema.title, "EasySubway source-free K3s activation terminal receipt");
  assert.deepEqual(receiptSchema.oneOf, [{ $ref: "#/$defs/success" }, { $ref: "#/$defs/failure" }]);
  for (const terminalKind of ["success", "failure"]) {
    const terminalReceipt = receiptSchema.$defs[terminalKind];
    assert.deepEqual(terminalReceipt.properties.bundleAcquisitionEvidenceDigest, { $ref: "#/$defs/digest" });
    assert.equal(terminalReceipt.required.includes("bundleAcquisitionEvidenceDigest"), false);
  }

  const contract = JSON.parse(deploymentContract);
  assert.deepEqual(contract.allowedProducerRepositories, ["AquilaXk/easysubway", "AquilaXk/easysubway-backend"]);
  assert.equal(contract.imageRepository, "ghcr.io/aquilaxk/easysubway-backend");
  assert.equal(contract.platformRepository, "AquilaXk/easysubway-platform");
  assert.equal(contract.issueRefPattern, JSON.parse(issueRefSchema).pattern);
  assert.deepEqual(contract.forbiddenInputs, ["branch", "buildContext", "sourceDirectory", "mutableImageTag"]);
});
