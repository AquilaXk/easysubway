import { createHash } from "node:crypto";
import { constants } from "node:fs";
import { lstat, open, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const inventoryPath = "contracts/mobile/generic-mobile-resource-inventory.json";
const schemaPath = "contracts/mobile/generic-mobile-consumer-bundle.schema.json";
const producerRepository = "AquilaXk/easysubway";
const inventorySha256 = "84238dab7ff8146394f5de1b4c1510a49498b52ec042b24f08cacd479e4e5a70";
const schemaSha256 = "0ee451e24ef2ff217b16f65501c1e2812abefbf9f936ef99f3eb02cec995bc63";
const expectedCandidates = new Map([
  ["api/report-status.ok.json", ["contracts/api/fixtures/report-status.ok.json", "1ea9a8511b290acb8092f87d7d087e16636013b5cd950157d4782b4437da17fe", "AquilaXk/easysubway-backend", 37, "OTHER_TARGET_RESOURCE", "EXCLUDE_BACKEND_OWNED"]],
  ["api/report-upload-intent.created.json", ["contracts/api/fixtures/report-upload-intent.created.json", "351ed8d5021c825751eaadaf97a3a76621480ea8f5e8ae522e028a416fcc655d", "AquilaXk/easysubway-backend", 37, "OTHER_TARGET_RESOURCE", "EXCLUDE_BACKEND_OWNED"]],
  ["backend/messages.properties", ["backend/src/main/resources/messages.properties", "c3f6f3e8d13806dc6a3f10ce5e900b5477f8f866c04225f9eca85d278597bb31", "AquilaXk/easysubway-backend", 48, "OTHER_TARGET_RESOURCE", "EXCLUDE_BACKEND_OWNED"]],
  ["datapack/canonical-number-contract.json", ["contracts/datapack/canonical-number-contract.json", "b2eef2284186a12e18ac06de1d339c0feca2194c5d556db8628e84287536d7e0", "AquilaXk/easysubway-data", 38, "DATA_ARTIFACT_OR_SCHEMA", "EXCLUDE_DATA_OWNED"]],
  ["errors/error-codes.json", ["contracts/error-codes.json", "7527a60514a7000ae8df0c958516a856dfdc288b6e085e4efbde9e3ce61d4bf9", producerRepository, 2747, "HUB_GENERIC_MOBILE_RESOURCE", "INCLUDE"]],
  ["product/mobility-profile-policy.json", ["release/product-gates/mobility-profile-policy.json", "5a63a03ff9ec9b61e0366d947251ee9294ebd48777b28b1ad6e2bdbe2d3fcc50", producerRepository, 2747, "HUB_GENERIC_MOBILE_RESOURCE", "INCLUDE"]],
]);

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const exactKeys = (value, keys, label) => {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).join(",") !== keys.join(",")) {
    throw new Error(`${label} has unknown, missing, or unordered keys`);
  }
};
const safePath = (value) => typeof value === "string" && value.length > 0 && !value.includes("\\") && !path.posix.isAbsolute(value) && path.posix.normalize(value) === value && value.split("/").every((part) => part !== "" && part !== "." && part !== "..");
const canonicalJson = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};

function validateSchema(schema, bytes) {
  exactKeys(schema, ["$schema", "$id", "type", "additionalProperties", "required", "properties"], "schema");
  if (schema.type !== "object" || schema.additionalProperties !== false || !Array.isArray(schema.required) || !schema.properties) {
    throw new Error("schema is invalid");
  }
  if (sha256(bytes) !== schemaSha256) throw new Error("schema nested trust boundary changed");
}

function validateInventory(inventory, producerSha, bytes) {
  exactKeys(inventory, ["schemaVersion", "artifactKind", "component", "bundleVersion", "producerRepository", "producerGitSha", "candidates"], "inventory");
  if (inventory.schemaVersion !== 1 || inventory.artifactKind !== "generic-mobile-resource-inventory" || inventory.component !== "mobile" || inventory.bundleVersion !== "1.0.0" || inventory.producerRepository !== producerRepository || inventory.producerGitSha !== producerSha || !Array.isArray(inventory.candidates) || inventory.candidates.length !== expectedCandidates.size) {
    throw new Error("inventory does not match the closed producer contract");
  }
  const seen = new Set();
  for (const candidate of inventory.candidates) {
    exactKeys(candidate, ["resourceId", "sourcePath", "rawSha256", "purposeKo", "canonicalProducerRepository", "canonicalProducerIssue", "mobileConsumerPaths", "productionUse", "ownerDisposition", "terminalBundleDisposition"], "candidate");
    if (!safePath(candidate.resourceId) || !safePath(candidate.sourcePath) || seen.has(candidate.resourceId)) throw new Error("inventory contains an unsafe or duplicate resource");
    seen.add(candidate.resourceId);
    const expected = expectedCandidates.get(candidate.resourceId);
    if (!expected || [candidate.sourcePath, candidate.rawSha256, candidate.canonicalProducerRepository, candidate.canonicalProducerIssue, candidate.ownerDisposition, candidate.terminalBundleDisposition].some((value, index) => value !== expected[index]) || typeof candidate.purposeKo !== "string" || candidate.purposeKo.length === 0 || !Array.isArray(candidate.mobileConsumerPaths) || candidate.mobileConsumerPaths.length === 0 || candidate.mobileConsumerPaths.some((consumerPath) => !safePath(consumerPath))) {
      throw new Error("inventory contains an unknown or changed owner/resource");
    }
  }
  if (sha256(bytes) !== inventorySha256) throw new Error("inventory exact contract changed");
}

async function readRegularFile(repositoryRoot, relativePath) {
  if (!safePath(relativePath)) throw new Error("source path is unsafe");
  const root = path.resolve(repositoryRoot);
  const rootStat = await lstat(root);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) throw new Error("repositoryRoot must be a regular directory");
  let source = root;
  const parts = relativePath.split("/");
  for (const [index, part] of parts.entries()) {
    source = path.join(source, part);
    const stat = await lstat(source);
    if (stat.isSymbolicLink()) throw new Error("source input must not contain a symlink");
    if (index === parts.length - 1 && !stat.isFile()) throw new Error("source input must be a regular file");
  }
  const handle = await open(source, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    if (!stat.isFile()) throw new Error("source input must be a regular file");
    return handle.readFile();
  } finally {
    await handle.close();
  }
}

export async function buildGenericMobileConsumerBundle({ repositoryRoot, producerSha }) {
  if (typeof repositoryRoot !== "string" || !/^[0-9a-f]{40}$/.test(producerSha)) throw new Error("repositoryRoot and producerSha must be valid");
  const root = path.resolve(repositoryRoot);
  const [inventoryBytes, schemaBytes] = await Promise.all([readRegularFile(root, inventoryPath), readRegularFile(root, schemaPath)]);
  const inventory = JSON.parse(inventoryBytes);
  validateSchema(JSON.parse(schemaBytes), schemaBytes);
  validateInventory(inventory, producerSha, inventoryBytes);
  const resources = [];
  for (const candidate of inventory.candidates) {
    const bytes = await readRegularFile(root, candidate.sourcePath);
    if (sha256(bytes) !== candidate.rawSha256) throw new Error(`rawSha256 drift for ${candidate.resourceId}`);
    if (candidate.terminalBundleDisposition === "INCLUDE") {
      resources.push({
        resourceId: candidate.resourceId,
        mediaType: "application/json",
        schemaVersion: candidate.resourceId === "errors/error-codes.json" ? null : 1,
        ownerRepository: candidate.canonicalProducerRepository,
        ownerIssue: candidate.canonicalProducerIssue,
        sourcePath: candidate.sourcePath,
        contentBase64: bytes.toString("base64"),
        rawSha256: candidate.rawSha256,
        sizeBytes: bytes.length,
      });
    }
  }
  resources.sort((left, right) => left.resourceId < right.resourceId ? -1 : left.resourceId > right.resourceId ? 1 : 0);
  const resourceInventorySha256 = sha256(canonicalJson(resources.map(({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }) => ({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }))));
  const payloadSha256 = sha256(canonicalJson(resources.map(({ resourceId, sizeBytes, rawSha256 }) => ({ resourceId, sizeBytes, rawSha256 }))));
  const bundle = { schemaVersion: 1, artifactKind: "generic-mobile-consumer-bundle", component: "mobile", bundleVersion: inventory.bundleVersion, producer: { repository: producerRepository, gitSha: producerSha }, resources, resourceInventorySha256, payloadSha256 };
  return Buffer.from(`${JSON.stringify(bundle, null, 2)}\n`, "utf8");
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length !== 4 || args[0] !== "--producer-sha" || args[2] !== "--output" || !/^[0-9a-f]{40}$/.test(args[1])) throw new Error("usage: --producer-sha <40-lower-hex> --output <non-existing-path>");
  const output = path.resolve(args[3]);
  try { await lstat(output); throw new Error("output already exists"); } catch (error) { if (error?.code !== "ENOENT") throw error; }
  const bundle = await buildGenericMobileConsumerBundle({ repositoryRoot: process.cwd(), producerSha: args[1] });
  await writeFile(output, bundle, { flag: "wx" });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
