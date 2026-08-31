#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { gunzipSync } from "node:zlib";

import { isMainModule } from "../lib/is-main-module.mjs";
import { parseArgs, requireArg } from "./lib/ledger-admission-cli.mjs";

const FULL_EVIDENCE_KIND = "nationwide-candidate-coverage-gate-evidence";
const EVIDENCE_PATH = "tools/datapack/reports/nationwide-candidate-coverage-gate.json";
const ASSET_PATH = "apps/mobile/assets/datapacks/capital.sqlite.gz";
const INDEX_PATH = "apps/mobile/assets/datapacks/index.json";
const INPUT_PATHS = Object.freeze({
  inheritedPack: "tools/datapack/release/capital-production-reviewed-pack.json",
  inventory: "tools/datapack/source-inventory.json",
  resolutionPlan: "tools/datapack/release/nationwide-public-api-coverage-search-plan-20260725.json",
  resolutions: "tools/datapack/release/nationwide-public-api-coverage-resolutions-20260725.json",
  spec: "tools/datapack/nationwide-candidate-pack-spec.json",
  targets: "tools/datapack/nationwide-coverage-targets.json",
});
const DEPLOYED_BUILD_SPEC_PATH = "tools/datapack/release/candidate-build-spec.json";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

export function assertNationwideCoveragePublicationReady(evidence) {
  if (evidence?.artifactKind !== FULL_EVIDENCE_KIND) {
    throw new Error(
      `production publication requires ${FULL_EVIDENCE_KIND}; got ${evidence?.artifactKind ?? "missing"}`,
    );
  }
  if (evidence.regeneration?.evidencePath !== EVIDENCE_PATH
    || evidence.deployedArtifact?.packId !== "capital"
    || evidence.deployedArtifact?.verifierPath !== "tools/datapack/verify-production-pack-artifact-identity.mjs"
    || !evidence.variants?.baseline
    || !evidence.variants?.lineScoped
    || !Array.isArray(evidence.transitions)) {
    throw new Error("production publication requires complete nationwide coverage evidence");
  }
}

export async function verifyNationwideCoveragePublicationReady(
  evidence,
  repositoryRoot,
  { currentTime = new Date() } = {},
) {
  assertNationwideCoveragePublicationReady(evidence);
  for (const [name, relativePath] of Object.entries(INPUT_PATHS)) {
    const bytes = await readFile(path.join(repositoryRoot, relativePath));
    if (evidence.inputs?.[name]?.path !== relativePath || evidence.inputs[name].sha256 !== sha256(bytes)) {
      throw new Error(`production publication nationwide coverage input mismatch: ${name}`);
    }
  }

  const assetBytes = await readFile(path.join(repositoryRoot, ASSET_PATH));
  const sqliteSha256 = sha256(gunzipSync(assetBytes));
  const deployed = evidence.deployedArtifact;
  await verifyDeployedBuildSpecFreshness({ deployed, repositoryRoot, currentTime });
  if (deployed.gzipSha256 !== sha256(assetBytes)
    || deployed.sqliteSha256 !== sqliteSha256
    || deployed.byteSize !== assetBytes.length) {
    throw new Error("production publication nationwide coverage deployed artifact mismatch");
  }

  const index = JSON.parse(await readFile(path.join(repositoryRoot, INDEX_PATH), "utf8"));
  const packs = index.packs?.filter(({ id }) => id === "capital") ?? [];
  const pack = packs[0];
  if (packs.length !== 1
    || pack.asset !== "assets/datapacks/capital.sqlite.gz"
    || pack.sha256 !== deployed.gzipSha256
    || pack.sqliteSha256 !== deployed.sqliteSha256
    || pack.byteSize !== deployed.byteSize) {
    throw new Error("production publication nationwide coverage index mismatch");
  }
}

async function verifyDeployedBuildSpecFreshness({ deployed, repositoryRoot, currentTime }) {
  if (!(currentTime instanceof Date) || !Number.isFinite(currentTime.getTime())) {
    throw new Error("production publication currentTime must be a valid Date");
  }
  const buildSpecInput = deployed?.inputs?.buildSpec;
  if (buildSpecInput?.path !== DEPLOYED_BUILD_SPEC_PATH
    || typeof buildSpecInput.sha256 !== "string"
    || !/^[0-9a-f]{64}$/.test(buildSpecInput.sha256)) {
    throw new Error("production publication nationwide coverage deployed build spec identity mismatch");
  }
  const buildSpecBytes = await readFile(path.join(repositoryRoot, DEPLOYED_BUILD_SPEC_PATH));
  if (sha256(buildSpecBytes) !== buildSpecInput.sha256) {
    throw new Error("production publication nationwide coverage deployed build spec identity mismatch");
  }
  let buildSpec;
  try {
    buildSpec = JSON.parse(buildSpecBytes);
  } catch {
    throw new Error("production publication nationwide coverage deployed build spec identity mismatch");
  }
  if (buildSpec?.artifactKind !== "datapack-candidate-build-spec"
    || !Array.isArray(buildSpec.sourceSnapshots)
    || buildSpec.sourceSnapshots.length === 0
    || !Array.isArray(buildSpec.sourceSnapshotIds)
    || buildSpec.sourceSnapshotIds.length !== buildSpec.sourceSnapshots.length) {
    throw new Error("production publication nationwide coverage deployed build spec identity mismatch");
  }
  const snapshotIds = new Set();
  for (const snapshot of buildSpec.sourceSnapshots) {
    if (typeof snapshot?.sourceId !== "string" || snapshot.sourceId.length === 0
      || typeof snapshot.snapshotId !== "string" || snapshot.snapshotId.length === 0
      || snapshotIds.has(snapshot.snapshotId)
      || typeof snapshot.rawSha256 !== "string" || !/^[0-9a-f]{64}$/.test(snapshot.rawSha256)
      || !isCanonicalUtcTimestamp(snapshot.freshnessExpiresAt)) {
      throw new Error("production publication nationwide coverage deployed build spec identity mismatch");
    }
    snapshotIds.add(snapshot.snapshotId);
    if (Date.parse(snapshot.freshnessExpiresAt) <= currentTime.getTime()) {
      throw new Error(
        `production publication nationwide coverage deployed source snapshot expired: ${snapshot.snapshotId}`,
      );
    }
  }
  if (buildSpec.sourceSnapshotIds.some((snapshotId, index) => snapshotId !== buildSpec.sourceSnapshots[index].snapshotId)) {
    throw new Error("production publication nationwide coverage deployed build spec identity mismatch");
  }
}

function isCanonicalUtcTimestamp(value) {
  return typeof value === "string"
    && Number.isFinite(Date.parse(value))
    && new Date(value).toISOString() === value;
}

async function main(argv) {
  const args = parseArgs(argv);
  const evidencePath = requireArg(args, "evidence");
  const evidence = JSON.parse(await readFile(evidencePath, "utf8"));
  await verifyNationwideCoveragePublicationReady(evidence, path.resolve(import.meta.dirname, "../.."));
}

if (isMainModule(import.meta.url)) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
