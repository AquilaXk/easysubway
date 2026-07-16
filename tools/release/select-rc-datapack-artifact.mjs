#!/usr/bin/env node

import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  selectEffectiveDataPack,
  selectFallbackDataPack,
  stagedPackPath,
} from "../datapack/lib/manifest-validation.mjs";

export async function selectRcDataPackArtifact(artifactRoot, outputRoot) {
  const root = path.resolve(artifactRoot);
  const decisionSource = path.join(root, "final-release-decision.json");
  const decision = await readJson(decisionSource);
  validateFinalDecision(decision);

  const manifestSource = decision.outcome === "PUBLISHED_AND_VERIFIED"
    ? path.join(root, "catalog/current.json")
    : path.join(root, "current-production.json");
  const manifestBytes = await readFile(manifestSource);
  const manifest = JSON.parse(manifestBytes.toString("utf8"));
  validateSelectedManifest(manifest);
  if (
    sha256(manifestBytes) !== decision.selectedManifestSha256
    || manifest.releaseSequence !== decision.selectedReleaseSequence
  ) {
    throw new Error("selected manifest does not match the final release decision");
  }
  const activePack = selectEffectiveDataPack(manifest);
  const fallbackPack = selectFallbackDataPack(manifest);
  if (!activePack) throw new Error("selected production manifest must identify exactly one active pack");
  if (!fallbackPack) throw new Error("selected production manifest must identify exactly one fallback pack");
  validateSelectedPack(activePack);
  validateSelectedPack(fallbackPack);
  const activeArtifact = await verifiedStagedPack(root, activePack);
  const fallbackArtifact = await verifiedStagedPack(root, fallbackPack);

  const output = path.resolve(outputRoot);
  await mkdir(output, { recursive: true });
  const manifestPath = path.join(output, "current.json");
  const artifactPath = path.join(output, "active.sqlite.gz");
  const fallbackArtifactPath = path.join(output, "fallback.sqlite.gz");
  const decisionPath = path.join(output, "release-decision.json");
  await copyFile(manifestSource, manifestPath);
  await copyFile(activeArtifact.file, artifactPath);
  await copyFile(fallbackArtifact.file, fallbackArtifactPath);
  await copyFile(decisionSource, decisionPath);
  return { outcome: decision.outcome, manifestPath, artifactPath, fallbackArtifactPath, decisionPath };
}

async function verifiedStagedPack(root, pack) {
  const file = path.join(root, stagedPackPath(pack));
  const bytes = await readFile(file);
  if (bytes.length !== pack.sizeBytes || sha256(bytes) !== pack.sha256) {
    throw new Error("staged pack does not match the selected production manifest identity");
  }
  return { file, bytes };
}

function validateFinalDecision(decision) {
  const published = decision?.outcome === "PUBLISHED_AND_VERIFIED";
  const noChange = decision?.outcome === "NO_CHANGE_VALID";
  if (
    decision?.schemaVersion !== 1
    || decision.artifactKind !== "datapack-release-decision"
    || (!published && !noChange)
    || decision.strictValidationPassed !== true
    || decision.remoteValidationPassed !== true
    || !/^[a-f0-9]{64}$/.test(decision.sourceSnapshotSetHash ?? "")
    || !/^[a-f0-9]{64}$/.test(decision.selectedManifestSha256 ?? "")
    || !Number.isSafeInteger(decision.selectedReleaseSequence)
    || decision.selectedReleaseSequence < 1
    || !Array.isArray(decision.reasonCodes)
    || decision.reasonCodes.length !== 0
    || decision.publishAttempted !== published
    || decision.productionWriteAllowed !== published
  ) {
    throw new Error("final data pack release decision is not RC eligible");
  }
}

function validateSelectedManifest(manifest) {
  if (manifest?.manifestVersion !== 2 || manifest.channel !== "production" || !Array.isArray(manifest.packs)) {
    throw new Error("selected data pack manifest must be production manifestVersion 2");
  }
}

function validateSelectedPack(pack) {
  if (!/^[a-f0-9]{64}$/.test(pack?.sha256 ?? "") || !Number.isSafeInteger(pack?.sizeBytes) || pack.sizeBytes <= 0) {
    throw new Error("selected production manifest active pack identity is invalid");
  }
}

async function readJson(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!name?.startsWith("--") || !value || value.startsWith("--")) {
      throw new Error(`invalid argument near ${name ?? "<end>"}`);
    }
    args.set(name.slice(2), value);
  }
  return args;
}

function required(args, name) {
  const value = args.get(name);
  if (!value) throw new Error(`--${name} is required`);
  return value;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    const args = parseArgs(process.argv.slice(2));
    const result = await selectRcDataPackArtifact(
      required(args, "artifact-root"),
      required(args, "output-root"),
    );
    console.log(`selected ${result.outcome} data pack`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
