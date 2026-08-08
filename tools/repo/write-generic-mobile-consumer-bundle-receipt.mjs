import { createHash } from "node:crypto";
import { constants } from "node:fs";
import { link, lstat, mkdir, open, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildGenericMobileConsumerBundle } from "./build-generic-mobile-consumer-bundle.mjs";

const producerRepository = "AquilaXk/easysubway";
const producerSha = "604a2ae525cc20b3bdcd3cbe2e22f93de19fefc3";
const bundleFileName = "generic-mobile-consumer-bundle-v1.json";
const receiptFileName = "generic-mobile-consumer-publication-receipt-v1.json";
const outputDirectory = "release-artifacts/mobile-contracts";
const artifactName = `easysubway-generic-mobile-consumer-bundle-1.0.0-${producerSha}`;
const expectedResources = [
  ["errors/error-codes.json", "7527a60514a7000ae8df0c958516a856dfdc288b6e085e4efbde9e3ce61d4bf9", "AquilaXk/easysubway", 2747, "contracts/error-codes.json", null],
  ["product/mobility-profile-policy.json", "5a63a03ff9ec9b61e0366d947251ee9294ebd48777b28b1ad6e2bdbe2d3fcc50", "AquilaXk/easysubway", 2747, "release/product-gates/mobility-profile-policy.json", 1],
];

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const canonicalJson = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`; // NOSONAR: canonical JSON requires raw locale-independent JavaScript string ordering.
  return JSON.stringify(value);
};
const exactKeys = (value, keys, label) => {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).join(",") !== keys.join(",")) throw new Error(`${label} has unknown, missing, or unordered keys`);
};
const safePath = (value) => typeof value === "string" && value.length > 0 && !value.includes("\\") && !path.posix.isAbsolute(value) && path.posix.normalize(value) === value && value.split("/").every((part) => part !== "" && part !== "." && part !== "..");

async function regularDirectory(directory, label) {
  const stat = await lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`${label} must be a regular directory`);
}

async function readRegularFile(root, target, label) {
  const relative = path.relative(root, target);
  if (!safePath(relative)) throw new Error(`${label} path is unsafe`);
  let current = root;
  await regularDirectory(current, "repositoryRoot");
  for (const [index, part] of relative.split("/").entries()) {
    current = path.join(current, part);
    const stat = await lstat(current);
    if (stat.isSymbolicLink()) throw new Error(`${label} must not contain a symlink`);
    if (index < relative.split("/").length - 1 && !stat.isDirectory()) throw new Error(`${label} parent must be a directory`);
    if (index === relative.split("/").length - 1 && !stat.isFile()) throw new Error(`${label} must be a regular file`);
  }
  const handle = await open(target, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    if (!stat.isFile()) throw new Error(`${label} must be a regular file`);
    return handle.readFile();
  } finally {
    await handle.close();
  }
}

function validateBundle(bytes) {
  const bundle = JSON.parse(bytes);
  exactKeys(bundle, ["schemaVersion", "artifactKind", "component", "bundleVersion", "producer", "resources", "resourceInventorySha256", "payloadSha256"], "bundle");
  if (bundle.schemaVersion !== 1 || bundle.artifactKind !== "generic-mobile-consumer-bundle" || bundle.component !== "mobile" || bundle.bundleVersion !== "1.0.0" || !/^[0-9a-f]{64}$/.test(bundle.resourceInventorySha256) || !/^[0-9a-f]{64}$/.test(bundle.payloadSha256)) throw new Error("bundle does not match the closed contract");
  exactKeys(bundle.producer, ["repository", "gitSha"], "bundle producer");
  if (bundle.producer.repository !== producerRepository || bundle.producer.gitSha !== producerSha || !Array.isArray(bundle.resources) || bundle.resources.length !== expectedResources.length) throw new Error("bundle producer or resources do not match the closed contract");
  for (const [index, resource] of bundle.resources.entries()) {
    exactKeys(resource, ["resourceId", "mediaType", "schemaVersion", "ownerRepository", "ownerIssue", "sourcePath", "contentBase64", "rawSha256", "sizeBytes"], `bundle resource ${index}`);
    const [resourceId, rawSha256, ownerRepository, ownerIssue, sourcePath, schemaVersion] = expectedResources[index];
    if (resource.resourceId !== resourceId || resource.mediaType !== "application/json" || resource.schemaVersion !== schemaVersion || resource.ownerRepository !== ownerRepository || resource.ownerIssue !== ownerIssue || resource.sourcePath !== sourcePath || resource.rawSha256 !== rawSha256 || !Number.isSafeInteger(resource.sizeBytes) || resource.sizeBytes < 0 || typeof resource.contentBase64 !== "string") throw new Error("bundle resource does not match the closed contract");
    const raw = Buffer.from(resource.contentBase64, "base64");
    if (raw.toString("base64") !== resource.contentBase64 || raw.length !== resource.sizeBytes || sha256(raw) !== resource.rawSha256) throw new Error("bundle resource digest or base64 is invalid");
  }
  const inventoryProjection = bundle.resources.map(({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }) => ({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }));
  const payloadProjection = bundle.resources.map(({ resourceId, sizeBytes, rawSha256 }) => ({ resourceId, sizeBytes, rawSha256 }));
  if (sha256(canonicalJson(inventoryProjection)) !== bundle.resourceInventorySha256 || sha256(canonicalJson(payloadProjection)) !== bundle.payloadSha256) throw new Error("bundle digest does not match resources");
  return bundle;
}

const positiveDecimal = (value) => typeof value === "string" && /^[1-9][0-9]*$/.test(value);
const isoTimestamp = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value) && Number.isFinite(Date.parse(value));

export function validateGenericMobileConsumerBundleArtifactMetadata({ metadata, artifactId, artifactDigest, workflowRunId, repositoryId, headSha }) {
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata) || !positiveDecimal(artifactId) || !/^[0-9a-f]{64}$/.test(artifactDigest) || !positiveDecimal(workflowRunId) || !positiveDecimal(repositoryId) || !/^[0-9a-f]{40}$/.test(headSha)) throw new Error("artifact metadata validation input is invalid");
  const expectedArchiveUrl = `https://api.github.com/repos/${producerRepository}/actions/artifacts/${artifactId}/zip`;
  const workflowRun = metadata.workflow_run;
  if (String(metadata.id) !== artifactId || metadata.name !== artifactName || metadata.expired !== false || metadata.digest !== `sha256:${artifactDigest}` || metadata.archive_download_url !== expectedArchiveUrl || !workflowRun || typeof workflowRun !== "object" || Array.isArray(workflowRun) || String(workflowRun.id) !== workflowRunId || workflowRun.head_branch !== "main" || workflowRun.head_sha !== headSha || String(workflowRun.repository_id) !== repositoryId || String(workflowRun.head_repository_id) !== repositoryId) throw new Error("artifact metadata does not match the closed publication contract");
  if (!isoTimestamp(metadata.created_at) || !isoTimestamp(metadata.expires_at) || Date.parse(metadata.expires_at) - Date.parse(metadata.created_at) !== 90 * 24 * 60 * 60 * 1000) throw new Error("artifact metadata retention is not exactly 90 days");
}

async function ensureOutputDirectory(root, output) {
  const expectedDirectory = path.join(root, outputDirectory);
  if (path.dirname(output) !== expectedDirectory || path.basename(output) !== receiptFileName) throw new Error("output must be confined to release-artifacts/mobile-contracts");
  await regularDirectory(root, "repositoryRoot");
  for (const relativeDirectory of ["release-artifacts", outputDirectory]) {
    const directory = path.join(root, relativeDirectory);
    try {
      await mkdir(directory);
    } catch (error) {
      if (error?.code !== "EEXIST") throw error;
    }
    await regularDirectory(directory, "output directory");
  }
  try {
    await lstat(output);
    throw new Error("output already exists");
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
}

export async function writeGenericMobileConsumerBundleReceipt({ repositoryRoot, bundlePath, outputPath, testHook } = {}) {
  if (typeof repositoryRoot !== "string" || typeof bundlePath !== "string" || typeof outputPath !== "string") throw new Error("repositoryRoot, bundlePath, and outputPath must be strings");
  if (testHook !== undefined && (process.env.NODE_ENV !== "test" || typeof testHook !== "function")) throw new Error("testHook is only available as a function when NODE_ENV=test");
  const root = path.resolve(repositoryRoot);
  const bundleTarget = path.resolve(bundlePath);
  const output = path.resolve(outputPath);
  if (path.basename(bundleTarget) !== bundleFileName) throw new Error("bundle filename does not match the closed contract");
  const bundleBytes = await readRegularFile(root, bundleTarget, "bundle");
  const expectedBundleBytes = await buildGenericMobileConsumerBundle({ repositoryRoot: root, producerSha });
  if (!bundleBytes.equals(expectedBundleBytes)) throw new Error("bundle bytes do not match the closed producer output");
  const bundle = validateBundle(bundleBytes);
  await ensureOutputDirectory(root, output);
  const receipt = {
    schemaVersion: 1,
    artifactKind: "generic-mobile-consumer-publication-receipt",
    component: "mobile",
    bundleVersion: "1.0.0",
    producer: { repository: producerRepository, gitSha: producerSha },
    bundle: { fileName: bundleFileName, rawSha256: sha256(bundleBytes), sizeBytes: bundleBytes.length, resourceInventorySha256: bundle.resourceInventorySha256, payloadSha256: bundle.payloadSha256 },
    resources: bundle.resources.map(({ resourceId, rawSha256, sizeBytes }) => ({ resourceId, rawSha256, sizeBytes })),
    publication: { repository: producerRepository, workflowPath: ".github/workflows/generic-mobile-consumer-bundle-publish.yml", artifactName, transport: "github-actions-artifact-v4", retentionDays: 90, overwrite: false },
  };
  const temporary = path.join(path.dirname(output), `.${receiptFileName}.${process.pid}.${Date.now()}.tmp`);
  const bytes = Buffer.from(`${JSON.stringify(receipt, null, 2)}\n`, "utf8");
  try {
    await writeFile(temporary, bytes, { flag: "wx", mode: 0o600 });
    if (testHook) await testHook({ temporaryPath: temporary, bytes });
    await link(temporary, output);
  } finally {
    await rm(temporary, { force: true });
  }
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 12 && args[0] === "--artifact-metadata" && args[2] === "--artifact-id" && args[4] === "--artifact-digest" && args[6] === "--workflow-run-id" && args[8] === "--repository-id" && args[10] === "--head-sha") {
    const metadataPath = path.resolve(args[1]);
    const metadataBytes = await readRegularFile(path.dirname(metadataPath), metadataPath, "artifact metadata");
    validateGenericMobileConsumerBundleArtifactMetadata({ metadata: JSON.parse(metadataBytes), artifactId: args[3], artifactDigest: args[5], workflowRunId: args[7], repositoryId: args[9], headSha: args[11] });
    return;
  }
  if (args.length !== 4 || args[0] !== "--bundle" || args[2] !== "--output") throw new Error("usage: --bundle <generic-mobile-consumer-bundle-v1.json> --output <release-artifacts/mobile-contracts/generic-mobile-consumer-publication-receipt-v1.json>");
  await writeGenericMobileConsumerBundleReceipt({ repositoryRoot: process.cwd(), bundlePath: args[1], outputPath: args[3] });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
