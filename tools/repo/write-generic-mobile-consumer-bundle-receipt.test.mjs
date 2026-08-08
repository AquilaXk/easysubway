import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { lstat, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { buildGenericMobileConsumerBundle } from "./build-generic-mobile-consumer-bundle.mjs";
import { writeGenericMobileConsumerBundleReceipt } from "./write-generic-mobile-consumer-bundle-receipt.mjs";

const producerSha = "604a2ae525cc20b3bdcd3cbe2e22f93de19fefc3";
const sourceRoot = process.cwd();
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

async function fixtureRoot(t) {
  const root = await mkdtemp(path.join(tmpdir(), "generic-mobile-receipt-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const relativePath of [
    "contracts/mobile/generic-mobile-resource-inventory.json",
    "contracts/mobile/generic-mobile-consumer-bundle.schema.json",
    "contracts/api/fixtures/report-status.ok.json",
    "contracts/api/fixtures/report-upload-intent.created.json",
    "backend/src/main/resources/messages.properties",
    "contracts/datapack/canonical-number-contract.json",
    "contracts/error-codes.json",
    "release/product-gates/mobility-profile-policy.json",
  ]) {
    const target = path.join(root, relativePath);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, await readFile(path.join(sourceRoot, relativePath)));
  }
  return root;
}

async function writeBundle(root) {
  const bundle = await buildGenericMobileConsumerBundle({ repositoryRoot: root, producerSha });
  const bundlePath = path.join(root, "generic-mobile-consumer-bundle-v1.json");
  await writeFile(bundlePath, bundle, { flag: "wx" });
  return bundlePath;
}

test("receipt는 검증된 bundle을 닫힌 publication 계약으로 원자적으로 기록한다", async (t) => {
  const root = await fixtureRoot(t);
  const bundlePath = await writeBundle(root);
  const outputPath = path.join(root, "release-artifacts/mobile-contracts/generic-mobile-consumer-publication-receipt-v1.json");
  await writeGenericMobileConsumerBundleReceipt({ repositoryRoot: root, bundlePath, outputPath });
  const receiptBytes = await readFile(outputPath);
  const receipt = JSON.parse(receiptBytes);
  const bundleBytes = await readFile(bundlePath);
  const bundle = JSON.parse(bundleBytes);

  assert.deepEqual(Object.keys(receipt), ["schemaVersion", "artifactKind", "component", "bundleVersion", "producer", "bundle", "resources", "publication"]);
  assert.deepEqual(receipt, {
    schemaVersion: 1,
    artifactKind: "generic-mobile-consumer-publication-receipt",
    component: "mobile",
    bundleVersion: "1.0.0",
    producer: { repository: "AquilaXk/easysubway", gitSha: producerSha },
    bundle: {
      fileName: "generic-mobile-consumer-bundle-v1.json",
      rawSha256: sha256(bundleBytes),
      sizeBytes: bundleBytes.length,
      resourceInventorySha256: bundle.resourceInventorySha256,
      payloadSha256: bundle.payloadSha256,
    },
    resources: bundle.resources.map(({ resourceId, rawSha256, sizeBytes }) => ({ resourceId, rawSha256, sizeBytes })),
    publication: {
      repository: "AquilaXk/easysubway",
      workflowPath: ".github/workflows/generic-mobile-consumer-bundle-publish.yml",
      artifactName: `easysubway-generic-mobile-consumer-bundle-1.0.0-${producerSha}`,
      transport: "github-actions-artifact-v4",
      retentionDays: 90,
      overwrite: false,
    },
  });
  assert.equal((await lstat(outputPath)).isSymbolicLink(), false);
});

test("receipt는 변조·symlink·경로 이탈·기존 output을 fail closed한다", async (t) => {
  const root = await fixtureRoot(t);
  const bundlePath = await writeBundle(root);
  const outputPath = path.join(root, "release-artifacts/mobile-contracts/generic-mobile-consumer-publication-receipt-v1.json");
  await writeFile(bundlePath, "{}\n");
  await assert.rejects(writeGenericMobileConsumerBundleReceipt({ repositoryRoot: root, bundlePath, outputPath }), /bundle|contract|digest/i);
  await writeFile(bundlePath, await buildGenericMobileConsumerBundle({ repositoryRoot: root, producerSha }));
  const linkDirectory = path.join(root, "linked");
  await mkdir(linkDirectory);
  const linkPath = path.join(linkDirectory, "generic-mobile-consumer-bundle-v1.json");
  await symlink(bundlePath, linkPath);
  await assert.rejects(writeGenericMobileConsumerBundleReceipt({ repositoryRoot: root, bundlePath: linkPath, outputPath }), /regular|symlink/i);
  await assert.rejects(writeGenericMobileConsumerBundleReceipt({ repositoryRoot: root, bundlePath, outputPath: path.join(root, "outside.json") }), /confined|output/i);
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, "old", { flag: "wx" });
  await assert.rejects(writeGenericMobileConsumerBundleReceipt({ repositoryRoot: root, bundlePath, outputPath }), /exists|output/i);
  assert.equal(await readFile(outputPath, "utf8"), "old");
});
