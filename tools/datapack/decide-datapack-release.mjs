#!/usr/bin/env node
import { createHash } from "node:crypto";
import { appendFile, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { decideScheduledRun } from "./freshness-policy.mjs";

export function evaluateReleaseDecision({
  candidateManifest,
  currentManifest,
  buildSpec,
  buildSpecSha256,
  releaseRequest,
  strictValidationPassed,
  publishAttempted,
  remoteValidationPassed,
  evaluationAt,
}) {
  const evaluatedMillis = requiredInstant(evaluationAt, "evaluationAt");
  const materialChange = currentManifest == null
    || stableManifestIdentity(candidateManifest) !== stableManifestIdentity(currentManifest);
  const currentExpired = currentManifest != null
    && evaluatedMillis >= requiredInstant(currentManifest.expiresAt, "currentManifest.expiresAt");
  const publishRequired = materialChange || currentExpired;
  const approvalValid = validApproval({ buildSpec, buildSpecSha256, releaseRequest });
  const sequenceValid = !publishRequired || currentManifest == null
    || (Number.isInteger(candidateManifest.releaseSequence)
      && Number.isInteger(currentManifest.releaseSequence)
      && candidateManifest.releaseSequence > currentManifest.releaseSequence);
  const sequenceRequiredAndInvalid = approvalValid && !sequenceValid;
  const effectiveStrictValidationPassed = strictValidationPassed && !sequenceRequiredAndInvalid;
  const scheduled = decideScheduledRun({
    materialChange,
    approvalValid,
    strictValidationPassed: effectiveStrictValidationPassed,
    publishRequired,
    publishAttempted,
    remoteValidationPassed,
  });
  const reasonCodes = [];
  if (currentExpired) reasonCodes.push("PACK_PUBLISH_FRESHNESS_EXPIRED");
  if (sequenceRequiredAndInvalid) reasonCodes.push("PUBLISH_SEQUENCE_NOT_INCREASING");
  if (materialChange && !approvalValid) reasonCodes.push("MATERIAL_CHANGE_UNAPPROVED");
  if (scheduled.outcome === "PUBLISH_REQUIRED") reasonCodes.push("PUBLISH_REQUIRED_NOT_COMPLETED");
  if (publishAttempted && !remoteValidationPassed) reasonCodes.push("POST_PUBLISH_REMOTE_VALIDATION_FAILED");

  return {
    schemaVersion: 1,
    artifactKind: "datapack-release-decision",
    ...scheduled,
    materialChange,
    approvalValid,
    strictValidationPassed: effectiveStrictValidationPassed,
    publishRequired,
    publishAttempted,
    remoteValidationPassed,
    sourceSnapshotSetHash: buildSpec?.sourceSnapshotSetHash ?? "-",
    reasonCodes,
    evaluationAt: new Date(evaluatedMillis).toISOString(),
  };
}

function stableManifestIdentity(manifest) {
  if (!manifest || !Array.isArray(manifest.packs) || manifest.packs.length === 0) {
    throw new Error("manifest.packs must be a non-empty array");
  }
  const packs = manifest.packs.map((pack) => ({
    id: requiredString(pack.id, "pack.id"),
    version: requiredString(String(pack.version ?? ""), "pack.version"),
    sha256: requiredSha256(pack.sha256, "pack.sha256"),
    sqliteSha256: requiredSha256(pack.sqliteSha256, "pack.sqliteSha256"),
    schemaVersion: requiredString(String(pack.schemaVersion ?? ""), "pack.schemaVersion"),
    sourceInventory: (pack.sourceInventory ?? []).map((source) => ({
      id: requiredString(source.id, "source.id"),
      updatedAt: requiredString(source.updatedAt, "source.updatedAt"),
      fields: [...(source.fields ?? [])].sort(),
    })).sort((left, right) => left.id.localeCompare(right.id)),
  })).sort((left, right) => left.id.localeCompare(right.id) || left.version.localeCompare(right.version));
  return JSON.stringify(packs);
}

function validApproval({ buildSpec, buildSpecSha256, releaseRequest }) {
  if (!buildSpec || !releaseRequest) return false;
  return releaseRequest.artifactKind === "datapack-release-request"
    && releaseRequest.targetChannel === "production"
    && typeof releaseRequest.approvalId === "string"
    && releaseRequest.approvalId.length > 0
    && requiredNonEmptyPair(releaseRequest.requestedBy, releaseRequest.approvedBy)
    && isSha256(buildSpecSha256)
    && isSha256(buildSpec.sourceSnapshotSetHash)
    && isSha256(buildSpec.approvedAliasLedgerHash)
    && releaseRequest.candidateId === buildSpec.candidateId
    && releaseRequest.buildSpecSha256 === buildSpecSha256
    && releaseRequest.sourceSnapshotSetHash === buildSpec.sourceSnapshotSetHash
    && releaseRequest.approvedLedgerHash === buildSpec.approvedAliasLedgerHash;
}

function isSha256(value) {
  return /^[a-f0-9]{64}$/.test(value ?? "");
}

function requiredNonEmptyPair(requestedBy, approvedBy) {
  return typeof requestedBy === "string" && requestedBy.length > 0
    && typeof approvedBy === "string" && approvedBy.length > 0
    && requestedBy !== approvedBy;
}

async function main(argv) {
  const args = parseArgs(argv);
  const currentManifest = await optionalJson(args.get("current-manifest"));
  const alertOnly = args.has("alert-only");
  const candidateManifest = alertOnly
    ? currentManifest
    : await requiredJson(args, "candidate-manifest");
  if (!candidateManifest) throw new Error("--current-manifest is required with --alert-only");

  const buildSpecPath = args.get("build-spec");
  const buildSpecBytes = buildSpecPath ? await readFile(buildSpecPath) : null;
  const buildSpec = buildSpecBytes ? JSON.parse(buildSpecBytes.toString("utf8")) : null;
  const releaseRequest = await optionalJson(args.get("release-request"));
  const evaluationAt = args.get("evaluation-at") ?? new Date().toISOString();
  const strictValidationPassed = alertOnly || args.get("strict-validation-status") === "PASS";
  const publishAttempted = args.get("publish-attempted") === "true";
  const remoteValidationPassed = args.get("remote-validation-status") === "PASS";
  const decision = evaluateReleaseDecision({
    candidateManifest,
    currentManifest,
    buildSpec,
    buildSpecSha256: buildSpecBytes ? sha256(buildSpecBytes) : null,
    releaseRequest,
    strictValidationPassed,
    publishAttempted,
    remoteValidationPassed,
    evaluationAt,
  });

  const outputPath = requiredArg(args, "output");
  await mkdir(path.dirname(path.resolve(outputPath)), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(decision, null, 2)}\n`);
  const githubOutput = args.get("github-output");
  if (githubOutput) {
    await appendFile(githubOutput, [
      `outcome=${decision.outcome}`,
      `productionWriteAllowed=${decision.productionWriteAllowed}`,
      `materialChange=${decision.materialChange}`,
      `approvalValid=${decision.approvalValid}`,
      `publishRequired=${decision.publishRequired}`,
      `sourceSnapshotSetHash=${decision.sourceSnapshotSetHash}`,
      `reasonCodes=${decision.reasonCodes.join(",") || "NONE"}`,
    ].join("\n") + "\n");
  }
}

function parseArgs(argv) {
  const flags = new Set(["alert-only"]);
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token?.startsWith("--")) throw new Error(`invalid argument: ${token ?? "<end>"}`);
    const name = token.slice(2);
    if (args.has(name)) throw new Error(`duplicate argument: ${token}`);
    if (flags.has(name)) {
      args.set(name, true);
      continue;
    }
    const value = argv[++index];
    if (value == null || value.startsWith("--")) throw new Error(`missing value: ${token}`);
    args.set(name, value);
  }
  return args;
}

async function requiredJson(args, name) {
  return JSON.parse(await readFile(requiredArg(args, name), "utf8"));
}

async function optionalJson(file) {
  return file ? JSON.parse(await readFile(file, "utf8")) : null;
}

function requiredArg(args, name) {
  const value = args.get(name);
  if (typeof value !== "string" || value.length === 0) throw new Error(`--${name} is required`);
  return value;
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.length === 0) throw new Error(`${label} must be a non-empty string`);
  return value;
}

function requiredSha256(value, label) {
  if (!isSha256(value)) throw new Error(`${label} must be sha256`);
  return value;
}

function requiredInstant(value, label) {
  if (typeof value !== "string" || !value.endsWith("Z")) throw new Error(`${label} must be an RFC 3339 UTC timestamp`);
  const millis = Date.parse(value);
  if (!Number.isFinite(millis)) throw new Error(`${label} must be an RFC 3339 UTC timestamp`);
  return millis;
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
