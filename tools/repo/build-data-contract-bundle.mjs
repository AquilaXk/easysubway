import path from "node:path";
import { fileURLToPath } from "node:url";
import { isSafeRelativePath, readRegularFile, replaceRegularFileAtomically } from "../lib/read-regular-file.mjs";

const bundlePath = "contracts/bundles/data-contracts-v1.0.0.json";
const resources = [
  ["datapack/mobility-profile-policy.json", "release/product-gates/mobility-profile-policy.json"],
  ["datapack/datapack-freshness-sla.json", "release/product-gates/datapack-freshness-sla.json"],
  ["datapack/source-governance-policy.json", "tools/datapack/source-governance-policy.json"],
  ["datapack/datapack-manifest-acceptance-policy.json", "apps/mobile/release/datapack-manifest-acceptance-policy.json"],
  ["datapack/production-datapack-scope.json", "release/product-gates/production-datapack-scope.json"],
  ["datapack/train-search-itx-exclusion-gate.json", "release/product-gates/train-search-itx-exclusion-gate.json"],
];
const requiredProductionSourceIds = [
  "incheon-transit-accessibility",
  "molit-urban-rail-full-route",
  "seoulmetro-station-line-info",
  "seoul-metro-accessibility",
  "seoul-metro-route-map-positions",
  "kric-station-convenience-standard",
  "kric-subway-timetable",
  "seoul-metro-transfer-distance-duration",
];
const externalSourceRegistrations = [
  {
    sourceId: "incheon-transit-accessibility",
    registrationRepository: "AquilaXk/easysubway-data",
    registrationIssue: 622,
    snapshotId: "incheon-transit-accessibility-20260828T043356000Z",
    decision: "APPROVED",
    productionUseAllowed: true,
  },
  {
    sourceId: "seoul-metro-transfer-distance-duration",
    registrationRepository: "AquilaXk/easysubway-data",
    registrationIssue: 350,
    snapshotId: "seoul-metro-transfer-distance-duration-20260815T094038817Z",
    decision: "APPROVED",
    productionUseAllowed: true,
  },
  {
    sourceId: "seoul-metro-route-map-positions",
    registrationRepository: "AquilaXk/easysubway-data",
    registrationIssue: 447,
    snapshotId: "seoul-metro-route-map-positions-current-20260824T114822985Z",
    decision: "APPROVED",
    productionUseAllowed: true,
  },
];

function exactKeys(value, keys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)
      || Object.keys(value).join(",") !== keys.join(",")) {
    throw new Error(`${label} has unknown, missing, or unordered keys`);
  }
}

function validateClosedResources() {
  const resourceIds = new Set();
  const sourcePaths = new Set();
  for (const [resourceId, sourcePath] of resources) {
    if (!isSafeRelativePath(resourceId) || !isSafeRelativePath(sourcePath) || resourceIds.has(resourceId) || sourcePaths.has(sourcePath)) {
      throw new Error("data contract bundle resource identity is unsafe, duplicate, or unknown");
    }
    resourceIds.add(resourceId);
    sourcePaths.add(sourcePath);
  }
  if (resources.length !== 6) throw new Error("data contract bundle resource set is incomplete or unexpected");
}

function validateProductionScope(scope) {
  if (!scope || typeof scope !== "object" || Array.isArray(scope) || !scope.productionSourceSet) {
    throw new Error("production datapack scope is invalid");
  }
  const sourceSet = scope.productionSourceSet;
  if (!Array.isArray(sourceSet.requiredSourceIds)
      || sourceSet.requiredSourceIds.length !== requiredProductionSourceIds.length
      || sourceSet.requiredSourceIds.some((sourceId, index) => sourceId !== requiredProductionSourceIds[index])) {
    throw new Error("production datapack required source identity is incomplete, duplicate, or unexpected");
  }
  if (!Array.isArray(sourceSet.externalSourceRegistrations)
      || sourceSet.externalSourceRegistrations.length !== externalSourceRegistrations.length
      || JSON.stringify(sourceSet.externalSourceRegistrations) !== JSON.stringify(externalSourceRegistrations)) {
    throw new Error("production datapack external source registration identity is incomplete, duplicate, or unexpected");
  }
}

export async function buildDataContractBundle({ repositoryRoot }) {
  if (typeof repositoryRoot !== "string") throw new Error("repositoryRoot is required");
  validateClosedResources();
  const root = path.resolve(repositoryRoot);
  const entries = await Promise.all(resources.map(async ([resourceId, sourcePath]) => [resourceId, await readRegularFile(root, sourcePath, { label: "source input" })]));
  const scopeBytes = entries.find(([resourceId]) => resourceId === "datapack/production-datapack-scope.json")?.[1];
  if (scopeBytes == null) throw new Error("production datapack scope resource is missing");
  validateProductionScope(JSON.parse(scopeBytes));
  return Buffer.from(`${JSON.stringify({
    schemaVersion: 1,
    bundleVersion: "1.0.0",
    resources: Object.fromEntries(entries.map(([resourceId, bytes]) => [resourceId, bytes.toString("utf8")])),
  }, null, 2)}\n`, "utf8");
}

async function main() {
  const [mode] = process.argv.slice(2);
  if (!["--check", "--write"].includes(mode) || process.argv.length !== 3) {
    throw new Error("usage: --check | --write");
  }
  const root = process.cwd();
  const generated = await buildDataContractBundle({ repositoryRoot: root });
  if (mode === "--check") {
    const existing = await readRegularFile(root, bundlePath, { label: "data contract bundle" });
    if (!generated.equals(existing)) throw new Error("data contract bundle is not generated from current closed inputs");
    return;
  }
  await replaceRegularFileAtomically(root, bundlePath, generated, { label: "data contract bundle output" });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    await main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
