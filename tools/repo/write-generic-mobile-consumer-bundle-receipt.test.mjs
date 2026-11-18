import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { lstat, mkdir, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { buildGenericMobileConsumerBundle } from "./build-generic-mobile-consumer-bundle.mjs";
import { validateGenericMobileConsumerBundleArtifactMetadata, writeGenericMobileConsumerBundleReceipt } from "./write-generic-mobile-consumer-bundle-receipt.mjs";

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

test("receipt는 인증된 bundle의 닫힌 header, resource와 digest 변조를 output 없이 거절한다", async (t) => {
  const root = await fixtureRoot(t);
  const bundlePath = await writeBundle(root);
  const original = JSON.parse(await readFile(bundlePath, "utf8"));
  const outputPath = path.join(root, "release-artifacts/mobile-contracts/generic-mobile-consumer-publication-receipt-v1.json");
  const mutations = [
    ["extra top key", (bundle) => { bundle.extra = true; }],
    ["component", (bundle) => { bundle.component = "other"; }],
    ["version", (bundle) => { bundle.bundleVersion = "2.0.0"; }],
    ["producer", (bundle) => { bundle.producer.gitSha = "0".repeat(40); }],
    ["resource order", (bundle) => { bundle.resources.reverse(); }],
    ["resource owner", (bundle) => { bundle.resources[0].ownerRepository = "AquilaXk/other"; }],
    ["resource raw digest", (bundle) => { bundle.resources[0].rawSha256 = "0".repeat(64); }],
    ["resource content", (bundle) => { bundle.resources[0].contentBase64 = Buffer.from("{}\n").toString("base64"); }],
    ["resource size", (bundle) => { bundle.resources[0].sizeBytes += 1; }],
    ["resource inventory digest", (bundle) => { bundle.resourceInventorySha256 = "0".repeat(64); }],
    ["payload digest", (bundle) => { bundle.payloadSha256 = "0".repeat(64); }],
  ];
  for (const [label, mutate] of mutations) {
    const bundle = structuredClone(original);
    mutate(bundle);
    const mutationDirectory = path.join(root, "mutations", label.replaceAll(" ", "-"));
    const mutationPath = path.join(mutationDirectory, "generic-mobile-consumer-bundle-v1.json");
    await mkdir(mutationDirectory, { recursive: true });
    await writeFile(mutationPath, `${JSON.stringify(bundle)}\n`, { flag: "wx" });
    await assert.rejects(writeGenericMobileConsumerBundleReceipt({ repositoryRoot: root, bundlePath: mutationPath, outputPath }), /bundle|contract|digest|keys|resource/i, label);
    await assert.rejects(lstat(outputPath), { code: "ENOENT" }, label);
  }
});

test("receipt는 semantic parse 전에 whitespace, numeric spelling, duplicate key raw drift를 거절한다", async (t) => {
  const root = await fixtureRoot(t);
  const bundlePath = await writeBundle(root);
  const original = await readFile(bundlePath, "utf8");
  const outputPath = path.join(root, "release-artifacts/mobile-contracts/generic-mobile-consumer-publication-receipt-v1.json");
  const drifts = [
    ["leading whitespace", ` ${original}`],
    ["numeric 1.0", original.replace('"schemaVersion": 1', '"schemaVersion": 1.0')],
    ["duplicate component", original.replace('"component": "mobile",', '"component": "mobile",\n  "component": "mobile",')],
  ];
  for (const [label, bytes] of drifts) {
    const directory = path.join(root, "raw-drifts", label.replaceAll(" ", "-"));
    const driftPath = path.join(directory, "generic-mobile-consumer-bundle-v1.json");
    await mkdir(directory, { recursive: true });
    await writeFile(driftPath, bytes, { flag: "wx" });
    await assert.rejects(writeGenericMobileConsumerBundleReceipt({ repositoryRoot: root, bundlePath: driftPath, outputPath }), /bytes/i, label);
    await assert.rejects(lstat(outputPath), { code: "ENOENT" }, label);
  }
});

test("artifact metadata는 exact ID, digest, origin 및 90일 보존만 허용한다", () => {
  const artifactId = "123";
  const artifactDigest = "a".repeat(64);
  const metadata = {
    id: 123,
    name: "easysubway-generic-mobile-consumer-bundle-1.0.0-604a2ae525cc20b3bdcd3cbe2e22f93de19fefc3",
    expired: false,
    digest: `sha256:${artifactDigest}`,
    archive_download_url: "https://api.github.com/repos/AquilaXk/easysubway/actions/artifacts/123/zip",
    created_at: "2026-01-01T00:00:00Z",
    expires_at: "2026-04-01T00:00:00Z",
    workflow_run: { id: 456, repository_id: 789, head_repository_id: 789, head_branch: "main", head_sha: producerSha },
  };
  const input = { metadata, artifactId, artifactDigest, workflowRunId: "456", repositoryId: "789", headSha: producerSha };
  assert.doesNotThrow(() => validateGenericMobileConsumerBundleArtifactMetadata(input));
  const requestToServerSkew = structuredClone(input);
  requestToServerSkew.metadata.expires_at = "2026-03-31T23:59:30Z";
  assert.doesNotThrow(() => validateGenericMobileConsumerBundleArtifactMetadata(requestToServerSkew));
  for (const mutate of [
    (value) => { delete value.metadata.digest; },
    (value) => { value.metadata.expires_at = "2026-01-31T00:00:00Z"; },
    (value) => { value.metadata.expires_at = "2026-03-31T23:54:59Z"; },
    (value) => { value.metadata.expires_at = "2026-04-01T00:00:01Z"; },
    (value) => { value.metadata.workflow_run.head_branch = "feature"; },
  ]) {
    const invalid = structuredClone(input);
    mutate(invalid);
    assert.throws(() => validateGenericMobileConsumerBundleArtifactMetadata(invalid), /metadata|retention/i);
  }
});

test("receipt 부분쓰기 hook은 test 환경에서만 허용되고 임시 파일까지 정리한다", async (t) => {
  const root = await fixtureRoot(t);
  const bundlePath = await writeBundle(root);
  const outputDirectory = path.join(root, "release-artifacts/mobile-contracts");
  const outputPath = path.join(outputDirectory, "generic-mobile-consumer-publication-receipt-v1.json");
  await assert.rejects(writeGenericMobileConsumerBundleReceipt({ repositoryRoot: root, bundlePath, outputPath, testHook: () => {} }), /NODE_ENV=test/);
  const previousNodeEnv = process.env.NODE_ENV;
  process.env.NODE_ENV = "test";
  try {
    await assert.rejects(writeGenericMobileConsumerBundleReceipt({
      repositoryRoot: root,
      bundlePath,
      outputPath,
      testHook: async ({ temporaryPath }) => {
        await writeFile(temporaryPath, "{", { flag: "w" });
        throw new Error("simulated partial write");
      },
    }), /simulated partial write/);
  } finally {
    if (previousNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = previousNodeEnv;
  }
  await assert.rejects(lstat(outputPath), { code: "ENOENT" });
  assert.deepEqual(await readdir(outputDirectory), []);
});

test("publication workflow는 main에서만 닫힌 producer와 정확히 두 파일을 artifact v4로 게시한다", async () => {
  const workflow = await readFile(".github/workflows/generic-mobile-consumer-bundle-publish.yml", "utf8");
  assert.match(workflow, /^on:\n  workflow_dispatch:\n$/m);
  assert.doesNotMatch(workflow, /\n  (push|pull_request|schedule):/);
  assert.match(workflow, /permissions:\n  actions: read\n  contents: read/);
  assert.match(workflow, /GITHUB_REF}" != "refs\/heads\/main"[\s\S]*exit 1/);
  assert.match(workflow, /actions\/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd[\s\S]*persist-credentials: false/);
  assert.doesNotMatch(workflow, /ref: 604a2ae525cc20b3bdcd3cbe2e22f93de19fefc3/);
  assert.match(workflow, /actions\/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e[\s\S]*node-version: 24\.19\.0/);
  assert.equal((workflow.match(/build-generic-mobile-consumer-bundle\.mjs --producer-sha 604a2ae525cc20b3bdcd3cbe2e22f93de19fefc3/g) ?? []).length, 2);
  assert.match(workflow, /cmp -- "\$\{bundle\}" "\$\{comparison_bundle\}"/);
  assert.match(workflow, /actions\/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02/);
  assert.match(workflow, /name: easysubway-generic-mobile-consumer-bundle-1\.0\.0-604a2ae525cc20b3bdcd3cbe2e22f93de19fefc3/);
  assert.match(workflow, /path: \|\n            release-artifacts\/mobile-contracts\/generic-mobile-consumer-bundle-v1\.json\n            release-artifacts\/mobile-contracts\/generic-mobile-consumer-publication-receipt-v1\.json/);
  assert.match(workflow, /retention-days: 90\n          overwrite: false/);
  assert.match(workflow, /set -euo pipefail/);
  assert.match(workflow, /artifact_id="\$\{\{ steps\.upload\.outputs\.artifact-id \}\}"[\s\S]*\^\[1-9\]\[0-9\]\*\$/);
  assert.match(workflow, /artifact_digest="\$\{\{ steps\.upload\.outputs\.artifact-digest \}\}"[\s\S]*\^\[0-9a-f\]\{64\}\$/);
  assert.match(workflow, /GITHUB_RUN_ID.*\^\[1-9\]\[0-9\]\*\$/);
  assert.match(workflow, /GITHUB_SHA.*\^\[0-9a-f\]\{40\}\$/);
  assert.match(workflow, /expected_artifact_url="https:\/\/github\.com\/AquilaXk\/easysubway\/actions\/runs\/\$\{GITHUB_RUN_ID\}\/artifacts\/\$\{artifact_id\}"/);
  assert.match(workflow, /artifact_url}" != "\$\{expected_artifact_url\}"/);
  assert.match(workflow, /workflow-path=\.github\/workflows\/generic-mobile-consumer-bundle-publish\.yml[\s\S]*workflow-run-id=.*workflow-head-sha=.*artifact-id=.*artifact-name=.*artifact-digest=.*artifact-url=.*retention-days=90/s);
  assert.match(workflow, /GH_TOKEN: \$\{\{ github\.token \}\}[\s\S]*gh api --method GET "repos\/\$\{GITHUB_REPOSITORY\}\/actions\/artifacts\/\$\{artifact_id\}" > "\$\{metadata\}"/);
  assert.match(workflow, /--artifact-metadata "\$\{metadata\}" --artifact-id "\$\{artifact_id\}" --artifact-digest "\$\{artifact_digest\}" --workflow-run-id "\$\{GITHUB_RUN_ID\}" --repository-id "\$\{GITHUB_REPOSITORY_ID\}" --head-sha "\$\{GITHUB_SHA\}"/);
  assert.match(workflow, /actions\/download-artifact@d3f86a106a0bac45b974a628896c90dbdf5c8093[\s\S]*artifact-ids: \$\{\{ steps\.upload\.outputs\.artifact-id \}\}\n          merge-multiple: true/);
  assert.match(workflow, /\[\[ -e "\$\{download_directory\}" \|\| -L "\$\{download_directory\}" \]\][\s\S]*artifact download path already exists[\s\S]*exit 1/);
  assert.doesNotMatch(workflow, /rm -rf/);
  assert.match(workflow, /mapfile -t entries[\s\S]*"\$\{#entries\[@\]\}" -ne 2[\s\S]*generic-mobile-consumer-bundle-v1\.json[\s\S]*generic-mobile-consumer-publication-receipt-v1\.json/s);
  assert.equal((workflow.match(/cmp -- /g) ?? []).length, 3);
  assert.ok(workflow.indexOf("Verify downloaded artifact bytes") < workflow.indexOf("Validate and log artifact locator"));
  assert.doesNotMatch(workflow, /continue-on-error|fallback/i);
});
