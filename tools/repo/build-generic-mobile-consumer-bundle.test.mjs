import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { buildGenericMobileConsumerBundle } from "./build-generic-mobile-consumer-bundle.mjs";

const producerSha = "604a2ae525cc20b3bdcd3cbe2e22f93de19fefc3";
const sourceRoot = process.cwd();
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const canonicalJson = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};
const candidates = [
  ["api/report-status.ok.json", "contracts/api/fixtures/report-status.ok.json", "1ea9a8511b290acb8092f87d7d087e16636013b5cd950157d4782b4437da17fe", "시설 신고 상태 API Mobile 테스트 fixture", "AquilaXk/easysubway-backend", 37, ["apps/mobile/test/fixtures/contracts/api/report-status.ok.json", "apps/mobile/test/contract/facility_report_fixture_test.dart"], "MOBILE_TEST_FIXTURE", "OTHER_TARGET_RESOURCE", "EXCLUDE_BACKEND_OWNED"],
  ["api/report-upload-intent.created.json", "contracts/api/fixtures/report-upload-intent.created.json", "351ed8d5021c825751eaadaf97a3a76621480ea8f5e8ae522e028a416fcc655d", "시설 신고 업로드 의도 API Mobile 테스트 fixture", "AquilaXk/easysubway-backend", 37, ["apps/mobile/test/fixtures/contracts/api/report-upload-intent.created.json", "apps/mobile/test/contract/facility_report_fixture_test.dart"], "MOBILE_TEST_FIXTURE", "OTHER_TARGET_RESOURCE", "EXCLUDE_BACKEND_OWNED"],
  ["backend/messages.properties", "backend/src/main/resources/messages.properties", "c3f6f3e8d13806dc6a3f10ce5e900b5477f8f866c04225f9eca85d278597bb31", "Backend 오류 메시지 Mobile 런타임 미러 계약", "AquilaXk/easysubway-backend", 48, ["apps/mobile/test/fixtures/contracts/backend/messages.properties", "apps/mobile/test/core/error/error_codes_contract_test.dart"], "MOBILE_RUNTIME_MIRROR_CONTRACT", "OTHER_TARGET_RESOURCE", "EXCLUDE_BACKEND_OWNED"],
  ["datapack/canonical-number-contract.json", "contracts/datapack/canonical-number-contract.json", "b2eef2284186a12e18ac06de1d339c0feca2194c5d556db8628e84287536d7e0", "Data canonical number Mobile datapack 검증 계약", "AquilaXk/easysubway-data", 38, ["apps/mobile/test/fixtures/contracts/datapack/canonical-number-contract.json", "apps/mobile/test/core/datapack/canonical_number_contract_test.dart", "apps/mobile/test/core/datapack/data_pack_manifest_production_signature_test.dart"], "MOBILE_DATAPACK_VALIDATION_CONTRACT", "DATA_ARTIFACT_OR_SCHEMA", "EXCLUDE_DATA_OWNED"],
  ["errors/error-codes.json", "contracts/error-codes.json", "7527a60514a7000ae8df0c958516a856dfdc288b6e085e4efbde9e3ce61d4bf9", "공통 오류 코드 Mobile 런타임 미러 계약", "AquilaXk/easysubway", 2747, ["apps/mobile/test/fixtures/contracts/error-codes.json", "apps/mobile/test/core/error/error_codes_contract_test.dart"], "MOBILE_RUNTIME_MIRROR_CONTRACT", "HUB_GENERIC_MOBILE_RESOURCE", "INCLUDE"],
  ["product/mobility-profile-policy.json", "release/product-gates/mobility-profile-policy.json", "5a63a03ff9ec9b61e0366d947251ee9294ebd48777b28b1ad6e2bdbe2d3fcc50", "이동 유형 정책 Mobile 런타임 미러 계약", "AquilaXk/easysubway", 2747, ["apps/mobile/test/fixtures/contracts/product/mobility-profile-policy.json", "apps/mobile/test/features/mobility_profile/mobility_profile_policy_test.dart"], "MOBILE_RUNTIME_MIRROR_CONTRACT", "HUB_GENERIC_MOBILE_RESOURCE", "INCLUDE"],
];

async function fixtureRoot(t) {
  const root = await mkdtemp(path.join(tmpdir(), "generic-mobile-bundle-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  await Promise.all(candidates.map(async ([, sourcePath]) => {
    const target = path.join(root, sourcePath);
    await mkdir(path.dirname(target), { recursive: true });
    await cp(path.join(sourceRoot, sourcePath), target);
  }));
  await mkdir(path.join(root, "contracts/mobile"), { recursive: true });
  await cp(path.join(sourceRoot, "contracts/mobile/generic-mobile-resource-inventory.json"), path.join(root, "contracts/mobile/generic-mobile-resource-inventory.json"));
  await cp(path.join(sourceRoot, "contracts/mobile/generic-mobile-consumer-bundle.schema.json"), path.join(root, "contracts/mobile/generic-mobile-consumer-bundle.schema.json"));
  return root;
}

test("closed inventory와 schema는 여섯 후보 및 두 Hub payload만 정확히 고정한다", async () => {
  const inventory = JSON.parse(await readFile("contracts/mobile/generic-mobile-resource-inventory.json", "utf8"));
  const schema = JSON.parse(await readFile("contracts/mobile/generic-mobile-consumer-bundle.schema.json", "utf8"));
  assert.deepEqual(Object.keys(inventory), ["schemaVersion", "artifactKind", "component", "bundleVersion", "producerRepository", "producerGitSha", "candidates"]);
  assert.deepEqual(Object.keys(schema), ["$schema", "$id", "type", "additionalProperties", "required", "properties"]);
  assert.equal(inventory.producerGitSha, producerSha);
  assert.equal(schema.properties.bundleVersion.const, "1.0.0");
  assert.equal(schema.properties.producer.properties.repository.const, "AquilaXk/easysubway");
  assert.equal(schema.properties.producer.properties.gitSha.const, producerSha);
  assert.equal(schema.properties.resources.minItems, 2);
  assert.equal(schema.properties.resources.maxItems, 2);
  assert.equal(schema.properties.resources.items, false);
  assert.equal(schema.properties.resources.prefixItems.length, 2);
  assert.equal(schema.properties.resources.prefixItems[0].properties.contentBase64.const, (await readFile("contracts/error-codes.json")).toString("base64"));
  assert.equal(schema.properties.resources.prefixItems[1].properties.contentBase64.const, (await readFile("release/product-gates/mobility-profile-policy.json")).toString("base64"));
  assert.deepEqual(inventory.candidates.map(({ resourceId, sourcePath, rawSha256, purposeKo, canonicalProducerRepository, canonicalProducerIssue, mobileConsumerPaths, productionUse, ownerDisposition, terminalBundleDisposition }) => [resourceId, sourcePath, rawSha256, purposeKo, canonicalProducerRepository, canonicalProducerIssue, mobileConsumerPaths, productionUse, ownerDisposition, terminalBundleDisposition]), candidates);
});

test("producer는 두 Hub resource의 raw bytes와 canonical digest를 결정론적으로 묶는다", async (t) => {
  const repositoryRoot = await fixtureRoot(t);
  const first = await buildGenericMobileConsumerBundle({ repositoryRoot, producerSha });
  const second = await buildGenericMobileConsumerBundle({ repositoryRoot, producerSha });
  assert.deepEqual(first, second);
  const bundle = JSON.parse(first);
  const schema = JSON.parse(await readFile("contracts/mobile/generic-mobile-consumer-bundle.schema.json", "utf8"));
  assert.deepEqual(Object.keys(bundle), ["schemaVersion", "artifactKind", "component", "bundleVersion", "producer", "resources", "resourceInventorySha256", "payloadSha256"]);
  assert.equal(bundle.component, "mobile");
  assert.deepEqual(bundle.resources.map((resource) => resource.resourceId), ["errors/error-codes.json", "product/mobility-profile-policy.json"]);
  for (const resource of bundle.resources) {
    const raw = await readFile(path.join(repositoryRoot, resource.sourcePath));
    assert.equal(resource.rawSha256, sha256(raw));
    assert.equal(resource.sizeBytes, raw.length);
    assert.deepEqual(Buffer.from(resource.contentBase64, "base64"), raw);
  }
  assert.match(bundle.resourceInventorySha256, /^[0-9a-f]{64}$/);
  assert.match(bundle.payloadSha256, /^[0-9a-f]{64}$/);
  const inventoryProjection = bundle.resources.map(({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }) => ({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }));
  const payloadProjection = bundle.resources.map(({ resourceId, sizeBytes, rawSha256 }) => ({ resourceId, sizeBytes, rawSha256 }));
  assert.equal(bundle.resourceInventorySha256, sha256(canonicalJson(inventoryProjection)));
  assert.equal(bundle.payloadSha256, sha256(canonicalJson(payloadProjection)));
  const [errorSchema, policySchema] = schema.properties.resources.prefixItems;
  const matchesExactResource = (resource, resourceSchema) => Object.entries(resourceSchema.properties).every(([key, constraint]) => constraint.const === undefined || resource[key] === constraint.const);
  assert.ok(bundle.resources.every((resource, index) => matchesExactResource(resource, [errorSchema, policySchema][index])));
  assert.equal(bundle.resources.slice().reverse().every((resource, index) => matchesExactResource(resource, [errorSchema, policySchema][index])), false);
  assert.equal(matchesExactResource({ ...bundle.resources[0], contentBase64: "" }, errorSchema), false);
});

test("producer는 drift, unsafe source, symlink와 invalid CLI output을 fail closed한다", async (t) => {
  const repositoryRoot = await fixtureRoot(t);
  await writeFile(path.join(repositoryRoot, "contracts/error-codes.json"), "{}\n");
  await assert.rejects(buildGenericMobileConsumerBundle({ repositoryRoot, producerSha }), /rawSha256|drift/i);
  await cp(path.join(sourceRoot, "contracts/error-codes.json"), path.join(repositoryRoot, "contracts/error-codes.json"));
  await rm(path.join(repositoryRoot, "release/product-gates/mobility-profile-policy.json"));
  await symlink("../../../contracts/error-codes.json", path.join(repositoryRoot, "release/product-gates/mobility-profile-policy.json"));
  await assert.rejects(buildGenericMobileConsumerBundle({ repositoryRoot, producerSha }), /regular|symlink/i);
  const output = path.join(repositoryRoot, "bundle.json");
  await writeFile(output, "old");
  const result = spawnSync(process.execPath, ["tools/repo/build-generic-mobile-consumer-bundle.mjs", "--producer-sha", producerSha, "--output", output], { cwd: sourceRoot, encoding: "utf8" });
  assert.notEqual(result.status, 0);
  assert.equal(await readFile(output, "utf8"), "old");
});

test("inventory와 nested schema mutation은 output 없이 fail closed한다", async (t) => {
  const repositoryRoot = await fixtureRoot(t);
  const inventoryFile = path.join(repositoryRoot, "contracts/mobile/generic-mobile-resource-inventory.json");
  const schemaFile = path.join(repositoryRoot, "contracts/mobile/generic-mobile-consumer-bundle.schema.json");
  const rejectInventory = async (mutate) => {
    const inventory = JSON.parse(await readFile(inventoryFile, "utf8"));
    mutate(inventory);
    await writeFile(inventoryFile, `${JSON.stringify(inventory, null, 2)}\n`);
    await assert.rejects(buildGenericMobileConsumerBundle({ repositoryRoot, producerSha }));
    await cp(path.join(sourceRoot, "contracts/mobile/generic-mobile-resource-inventory.json"), inventoryFile);
  };
  await rejectInventory((inventory) => { inventory.candidates[0].sourcePath = "contracts//api/fixtures/report-status.ok.json"; });
  await rejectInventory((inventory) => { inventory.candidates[0].resourceId = "./api/report-status.ok.json"; });
  await rejectInventory((inventory) => { inventory.candidates.push(structuredClone(inventory.candidates[0])); });
  await rejectInventory((inventory) => { inventory.candidates[1].resourceId = inventory.candidates[0].resourceId; });
  await rejectInventory((inventory) => { inventory.candidates[3].ownerDisposition = "UNKNOWN_OWNER"; });
  await rejectInventory((inventory) => { inventory.candidates[0].terminalBundleDisposition = "INCLUDE"; });
  await rejectInventory((inventory) => { inventory.producerGitSha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; });
  for (const mutate of [
    (schema) => { delete schema.properties.resources.prefixItems[0].required; },
    (schema) => { schema.properties.resources.prefixItems[0].properties.sourcePath = { type: "number" }; },
    (schema) => { schema.properties.resources.prefixItems[0].properties.contentBase64 = { type: "number" }; },
    (schema) => { schema.properties.payloadSha256.pattern = ".*"; },
  ]) {
    const schema = JSON.parse(await readFile(schemaFile, "utf8"));
    mutate(schema);
    await writeFile(schemaFile, `${JSON.stringify(schema, null, 2)}\n`);
    await assert.rejects(buildGenericMobileConsumerBundle({ repositoryRoot, producerSha }));
    await cp(path.join(sourceRoot, "contracts/mobile/generic-mobile-consumer-bundle.schema.json"), schemaFile);
  }
});

test("producer는 ancestor symlink repository input을 fail closed한다", async (t) => {
  const repositoryRoot = await fixtureRoot(t);
  await rm(path.join(repositoryRoot, "contracts"), { recursive: true });
  await symlink(path.join(sourceRoot, "contracts"), path.join(repositoryRoot, "contracts"));
  await assert.rejects(buildGenericMobileConsumerBundle({ repositoryRoot, producerSha }), /regular|symlink/i);
});

test("producer는 POSIX FIFO source를 block 없이 fail closed한다", async (t) => {
  const repositoryRoot = await fixtureRoot(t);
  const fifo = path.join(repositoryRoot, "contracts/error-codes.json");
  await rm(fifo);
  const result = spawnSync("mkfifo", [fifo], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  await assert.rejects(buildGenericMobileConsumerBundle({ repositoryRoot, producerSha }), /regular/i);
});

test("CLI는 closed options, source SHA, current failure와 existing output을 fail closed한다", async (t) => {
  const repositoryRoot = await fixtureRoot(t);
  const script = path.join(sourceRoot, "tools/repo/build-generic-mobile-consumer-bundle.mjs");
  const output = path.join(repositoryRoot, "bundle.json");
  const run = (...args) => spawnSync(process.execPath, [script, ...args], { cwd: repositoryRoot, encoding: "utf8" });
  const apiBytes = await buildGenericMobileConsumerBundle({ repositoryRoot, producerSha });
  assert.equal(run("--producer-sha", producerSha, "--output", output).status, 0);
  assert.deepEqual(await readFile(output), apiBytes);
  await rm(output);
  assert.notEqual(run().status, 0);
  assert.notEqual(run("--producer-sha", producerSha, "--producer-sha", producerSha, "--output", output).status, 0);
  assert.notEqual(run("--producer-sha", producerSha, "--unknown", "x", "--output", output).status, 0);
  assert.notEqual(run("--producer-sha", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "--output", output).status, 0);
  await writeFile(path.join(repositoryRoot, "contracts/error-codes.json"), "{}\n");
  assert.notEqual(run("--producer-sha", producerSha, "--output", output).status, 0);
  await assert.rejects(readFile(output));
  await writeFile(output, "old");
  assert.notEqual(run("--producer-sha", producerSha, "--output", output).status, 0);
  assert.equal(await readFile(output, "utf8"), "old");
});
