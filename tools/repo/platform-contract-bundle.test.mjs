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

test("platform contract bundle v1.2.0은 canary 대표 출발 시각 기준을 additive로 명시하고 나머지 resource는 v1.1.0과 같다", async () => {
  const v110 = JSON.parse(await readFile("contracts/bundles/platform-contracts-v1.1.0.json", "utf8"));
  const bytes = await readFile("contracts/bundles/platform-contracts-v1.2.0.json");
  const bundle = JSON.parse(bytes);

  assert.equal(sha256(bytes), "db3d4bac4d6fee8375325270a456d806e70d0e8099fa3ad1226af951c2440bae");
  assert.equal(sha256(bundle.resources["platform/k3s-activation-contract.json"]), "f44a533c2d951855d29a1127a713c94ab1c45d21b52c6a0e4a8e98cdc5f521fb");
  assert.deepEqual(Object.keys(bundle), Object.keys(v110));
  assert.equal(bundle.bundleVersion, "1.2.0");
  assert.equal(bundle.componentManifestSchemaSha256, v110.componentManifestSchemaSha256);
  assert.equal(bundle.issueRefSchemaSha256, v110.issueRefSchemaSha256);
  assert.deepEqual(Object.keys(bundle.resources), resourceKeys);
  for (const key of resourceKeys.filter((name) => name !== "platform/k3s-activation-contract.json")) {
    assert.equal(bundle.resources[key], v110.resources[key], `${key} 바이트는 바뀌지 않는다`);
  }

  const before = JSON.parse(v110.resources["platform/k3s-activation-contract.json"]);
  const after = JSON.parse(bundle.resources["platform/k3s-activation-contract.json"]);
  const { canary, ...candidateWithoutCanary } = after.candidate;
  assert.deepEqual({ ...after, candidate: candidateWithoutCanary }, before, "canary 항목 외 기존 계약 필드와 순서는 그대로다");
  assert.deepEqual(Object.keys(after), Object.keys(before));
  assert.deepEqual(after.candidate.requiredOrder, before.candidate.requiredOrder);
  assert.equal(after.fallback.policy, "FORBIDDEN");
  assert.equal(after.rollback.policy, "FORBIDDEN");

  assert.deepEqual(canary.representativeDeparture, {
    rule: "FIRST_1000_KST_IN_BUNDLE_VALIDITY_WINDOW",
    localTime: "10:00",
    timeZone: "Asia/Seoul",
    window: "[activeFrom, freshUntil)",
    noMatchFailureReason: "WINDOW_MISMATCH",
    departureIndependentOfWallClock: true,
    coverage: "SINGLE_REPRESENTATIVE_TIME_SMOKE",
    coverageLimit: "TIMETABLE_DEFECTS_AT_OTHER_TIMES_ARE_NOT_DETECTED",
  });
  assert.deepEqual(canary.executionWindowCheck, {
    rule: "EXECUTION_INSTANT_MUST_BE_INSIDE_BUNDLE_VALIDITY_WINDOW",
    window: "[activeFrom, freshUntil)",
    outsideWindowFailureReason: "WINDOW_MISMATCH",
    staleOrFutureBundleLookupFailureReason: "WINDOW_MISMATCH",
  });
  assert.deepEqual(canary.failure, {
    artifactKind: "journey-v3-candidate-canary-failure",
    reasons: ["SNAPSHOT_ERROR", "WINDOW_MISMATCH", "PLAN_ERROR", "NO_CANDIDATES"],
    probeIdField: "probeId",
    reasonField: "failureReason",
    reasonPresence: "UNAVAILABLE_RESPONSE_ONLY",
  });
});
