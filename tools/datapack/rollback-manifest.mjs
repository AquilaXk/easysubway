#!/usr/bin/env node
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { buildRescueManifest } from "./build-rescue-manifest.mjs";
import { signingPrivateKey } from "./lib/manifest-signing.mjs";
import { validateManifest } from "./lib/manifest-validation.mjs";
import {
  objectUrl,
  putCurrentAndVerify,
  putImmutableAndVerify,
  request,
  sha256,
  validateReferencedPacksForRescue,
} from "./lib/object-storage-publish.mjs";

async function main() {
  const startedAtMs = Date.now();
  const args = parseArgs(process.argv.slice(2));
  const targetSequence = positiveInteger(Number(requiredArg(args, "target-sequence")), "--target-sequence");
  const failedSequence = positiveInteger(Number(requiredArg(args, "failed-sequence")), "--failed-sequence");
  const channel = requiredArg(args, "channel");
  const baseUrl = new URL(requiredArg(args, "base-url"));
  const approval = JSON.parse(await readFile(path.resolve(requiredArg(args, "approval")), "utf8"));
  const catalogInput = JSON.parse(await readFile(path.resolve(requiredArg(args, "catalog-sequences")), "utf8"));
  const catalogSequences = Array.isArray(catalogInput) ? catalogInput : catalogInput.sequences;
  const evidenceOutput = path.resolve(requiredArg(args, "evidence-output"));
  const dryRun = args.has("dry-run");

  const currentResponse = await getRequiredObject(baseUrl, "catalog/current.json");
  const currentBytes = currentResponse.body;
  const current = JSON.parse(currentBytes.toString("utf8"));
  validateManifest(current, { requireProduction: channel === "production" });
  if (current.channel !== channel) throw new Error(`current channel mismatch: ${current.channel} != ${channel}`);

  const releaseKey = `catalog/releases/${targetSequence}.json`;
  const knownGoodResponse = await getRequiredObject(baseUrl, releaseKey);
  const knownGoodBytes = knownGoodResponse.body;
  const knownGood = JSON.parse(knownGoodBytes.toString("utf8"));
  validateManifest(knownGood, { requireProduction: channel === "production", releasesTarget: true });
  if (knownGood.channel !== channel) throw new Error(`known-good channel mismatch: ${knownGood.channel} != ${channel}`);
  await validateReferencedPacksForRescue(baseUrl, knownGood);

  if (isSameApprovedRescue(current, approval, targetSequence)) {
    const replayCatalogSequences = validatedCatalogSequences(catalogSequences);
    if (Math.max(...replayCatalogSequences) > current.releaseSequence) {
      throw new Error("immutable catalog advanced beyond the idempotent rescue");
    }
    if (sha256(knownGoodBytes) !== current.rollbackProvenance.knownGoodManifestSha256) {
      throw new Error("idempotent rescue known-good manifest identity mismatch");
    }
    const immutable = await getRequiredObject(baseUrl, `catalog/releases/${current.releaseSequence}.json`);
    if (sha256(immutable.body) !== sha256(currentBytes)) {
      throw new Error("idempotent rescue immutable/current identity mismatch");
    }
    const report = buildReport({
      current,
      currentBytes,
      knownGood,
      knownGoodBytes,
      rescue: current,
      rescueBytes: currentBytes,
      approval,
      baseUrl,
      dryRun,
      manifestLastStatus: "PASS",
      startedAtMs,
      idempotentReplay: true,
    });
    await writeEvidence(evidenceOutput, report);
    process.stdout.write(`${JSON.stringify(report)}\n`);
    return;
  }

  if (current.releaseSequence !== failedSequence) {
    throw new Error("failedSequence must match current manifest releaseSequence");
  }
  const result = buildRescueManifest({
    currentManifest: current,
    currentManifestBytes: currentBytes,
    failedSequence,
    knownGoodManifest: knownGood,
    knownGoodManifestBytes: knownGoodBytes,
    catalogSequences,
    approval,
    publishedAt: requiredArg(args, "published-at"),
    expiresAt: requiredArg(args, "expires-at"),
    privateKey: signingPrivateKey(),
  });

  let manifestLastStatus = "NOT_EXECUTED";
  if (!dryRun) {
    const rescueKey = `catalog/releases/${result.manifest.releaseSequence}.json`;
    await putImmutableAndVerify(baseUrl, rescueKey, result.manifestBytes);
    await putCurrentAndVerify(baseUrl, result.manifestBytes, sha256(currentBytes));
    manifestLastStatus = "PASS";
  }
  const report = {
    ...result.evidence,
    status: "PASS",
    validatorStatus: "PASS",
    manifestLastStatus,
    dryRun,
    productionExecuted: !dryRun && channel === "production" && !isLoopback(baseUrl.hostname),
    executionEnvironment: isLoopback(baseUrl.hostname) ? "LOCAL_FIXTURE" : channel === "production" ? "PRODUCTION" : "NON_PRODUCTION",
    idempotentReplay: false,
    startedAt: new Date(startedAtMs).toISOString(),
    completedAt: new Date().toISOString(),
    recoveryDurationSeconds: Math.max(0, Math.ceil((Date.now() - startedAtMs) / 1000)),
  };
  await writeEvidence(evidenceOutput, report);
  process.stdout.write(`${JSON.stringify(report)}\n`);
}

function buildReport({ current, currentBytes, knownGood, knownGoodBytes, rescue, rescueBytes, approval, baseUrl, dryRun, manifestLastStatus, startedAtMs, idempotentReplay }) {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-rollback-rescue-evidence",
    releaseRequestId: approval.releaseRequestId,
    approvedByRole: approval.approvedByRole,
    approvedAt: approval.approvedAt,
    reasonCode: approval.reasonCode,
    from: {
      channel: rescue.channel,
      releaseSequence: rescue.rollbackProvenance.currentReleaseSequence,
      manifestSha256: rescue.rollbackProvenance.failedManifestSha256,
    },
    failed: {
      channel: rescue.rollbackProvenance.currentReleaseSequence === current.releaseSequence ? current.channel : rescue.channel,
      releaseSequence: rescue.rollbackProvenance.failedReleaseSequence,
      manifestSha256: rescue.rollbackProvenance.failedManifestSha256,
    },
    knownGood: {
      ...identity(knownGood, knownGoodBytes),
      packs: knownGood.packs.map((pack) => ({ id: pack.id, version: pack.version, sha256: pack.sha256, sqliteSha256: pack.sqliteSha256 })),
    },
    rescue: identity(rescue, rescueBytes),
    status: "PASS",
    validatorStatus: "PASS",
    manifestLastStatus,
    dryRun,
    productionExecuted: !dryRun && rescue.channel === "production" && !isLoopback(baseUrl.hostname),
    executionEnvironment: isLoopback(baseUrl.hostname) ? "LOCAL_FIXTURE" : rescue.channel === "production" ? "PRODUCTION" : "NON_PRODUCTION",
    idempotentReplay,
    startedAt: new Date(startedAtMs).toISOString(),
    completedAt: new Date().toISOString(),
    recoveryDurationSeconds: Math.max(0, Math.ceil((Date.now() - startedAtMs) / 1000)),
  };
}

function isSameApprovedRescue(current, approval, targetSequence) {
  const provenance = current.rollbackProvenance;
  return provenance?.kind === "MONOTONIC_RESCUE"
    && provenance.releaseRequestId === approval.releaseRequestId
    && provenance.approvedByRole === approval.approvedByRole
    && provenance.approvedAt === approval.approvedAt
    && provenance.reasonCode === approval.reasonCode
    && provenance.knownGoodReleaseSequence === targetSequence;
}

function identity(manifest, bytes) {
  return { channel: manifest.channel, releaseSequence: manifest.releaseSequence, manifestSha256: sha256(bytes) };
}

async function getRequiredObject(baseUrl, key) {
  const response = await request(objectUrl(baseUrl, key), "GET");
  if (response.statusCode !== 200) throw new Error(`${key} not found (HTTP ${response.statusCode})`);
  return response;
}

async function writeEvidence(outputPath, report) {
  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(report, null, 2)}\n`);
}

function isLoopback(hostname) {
  return hostname === "localhost" || hostname === "127.0.0.1" || hostname === "::1" || hostname === "[::1]";
}

function positiveInteger(value, label) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${label} must be a positive integer`);
  return value;
}

function validatedCatalogSequences(value) {
  if (!Array.isArray(value) || value.length === 0) throw new Error("catalog sequences must be a non-empty array");
  const result = value.map((sequence) => positiveInteger(sequence, "catalog sequence"));
  if (new Set(result).size !== result.length) throw new Error("catalog sequences must not contain duplicates");
  return result;
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (key === "--dry-run") {
      if (args.has("dry-run")) throw new Error("duplicate argument: --dry-run");
      args.set("dry-run", "true");
      continue;
    }
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined || value.startsWith("--")) {
      throw new Error(`invalid argument near ${key ?? "<end>"}`);
    }
    const name = key.slice(2);
    if (args.has(name)) throw new Error(`duplicate argument: ${key}`);
    args.set(name, value);
    index += 1;
  }
  return args;
}

function requiredArg(args, name) {
  const value = args.get(name);
  if (typeof value !== "string" || value.trim() === "") throw new Error(`missing required argument: --${name}`);
  return value.trim();
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
