#!/usr/bin/env node
import { link, lstat, mkdtemp, readdir, rm, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";
import { selectEffectiveDataPack, stagedPackPath, validateManifest } from "../datapack/lib/manifest-validation.mjs";

import {
  hash,
  parseArgs,
  positiveDecimal,
  regularBytes,
  regularJson,
  readCandidateExecutionEvidence,
  reviewerFromApproval,
  validateCandidateExecutionEvidence,
  validateCompatibilityEvidence,
  validatePromotionCandidate,
  validateInventory,
} from "./validate-promotion-request.mjs";

async function main() {
  const args = parseArgs(process.argv.slice(2), [
    "candidate-root", "candidate-workflow-run-id", "candidate-head-sha",
    "candidate-execution-evidence-root",
    "compatibility-evidence", "requested-by", "approval-evidence", "workflow-run-id", "issue-ref",
    "output",
  ]);
  const { component, inventoryBytes } = await verifyPromotionCandidateRoot(
    args.get("candidate-root"), "--candidate-root",
    args.get("candidate-workflow-run-id"), args.get("candidate-head-sha"),
  );
  const executionEvidence = await readCandidateExecutionEvidence(
    args.get("candidate-execution-evidence-root"),
  );
  validateCandidateExecutionEvidence({ ...executionEvidence, component });

  const [compatibility, compatibilityBytes] = await regularJson(
    args.get("compatibility-evidence"),
    "--compatibility-evidence",
  );
  validateCompatibilityEvidence(compatibility, component);
  const approvalBytes = await regularBytes(args.get("approval-evidence"), "--approval-evidence");
  const reviewer = reviewerFromApproval(approvalBytes);
  const workflowRunId = args.get("workflow-run-id");
  const requestedBy = args.get("requested-by");
  if (!positiveDecimal(workflowRunId) || requestedBy.trim() === ""
    || args.get("issue-ref") !== "AquilaXk/easysubway#2705") {
    throw new Error("request arguments are invalid");
  }

  const request = {
    schemaVersion: 1,
    artifactKind: "datapack-promotion-request",
    candidate: component,
    compatibilityEvidenceSha256: hash(compatibilityBytes),
    candidateExecutionEvidence: {
      releaseEvidenceBundleSha256: hash(executionEvidence.releaseEvidenceBundleBytes),
      releaseDecisionSha256: hash(executionEvidence.releaseDecisionBytes),
    },
    requestedBy,
    approval: {
      workflowRunId,
      environment: "datapack-promotion",
      reviewer,
      approvalEvidenceSha256: hash(approvalBytes),
    },
    contractVersion: "datapack-promotion-v2",
    issueRef: args.get("issue-ref"),
  };
  const requestBytes = jsonBytes(request);
  await writeExclusiveJson(args.get("output"), requestBytes);
}

export async function verifyPromotionCandidateRoot(root, label, expectedWorkflowRunId, expectedGitSha) {
  if (!process.env.EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM?.trim()
    || !process.env.EASYSUBWAY_DATAPACK_SIGNING_KEY_ID?.trim()) {
    throw new Error("candidate signature validation key is required");
  }
  const stats = await lstat(root);
  if (!stats.isDirectory() || stats.isSymbolicLink()) {
    throw new Error(`${label} must be a regular non-symlink directory`);
  }
  const componentPath = path.join(root, "data-component-manifest.json");
  const inventoryPath = path.join(root, "data-artifact-inventory.json");
  const manifestPath = path.join(root, "catalog", "current.json");
  const provenancePath = path.join(root, "current.provenance.json");
  const [component] = await regularJson(componentPath, `${label}/data-component-manifest.json`);
  const [inventory, inventoryBytes] = await regularJson(inventoryPath, `${label}/data-artifact-inventory.json`);
  const [manifest, manifestBytes] = await regularJson(manifestPath, `${label}/catalog/current.json`);
  const [provenance] = await regularJson(provenancePath, `${label}/current.provenance.json`);
  validateManifest(manifest, { requireProduction: true });
  const activePack = selectEffectiveDataPack(manifest);
  const actualEntries = await actualInventory(root);
  const declaredPackPaths = new Set(manifest.packs.map(stagedPackPath));
  const actualPackPaths = new Set(actualEntries.filter((entry) => entry.path.endsWith(".sqlite.gz")).map((entry) => entry.path));
  const actualEntriesByPath = new Map(actualEntries.map((entry) => [entry.path, entry]));
  validatePromotionCandidate(component);
  validateInventory(inventory);
  if (!positiveDecimal(expectedWorkflowRunId) || !/^[a-f0-9]{40}$/.test(expectedGitSha)
    || component.workflowRunId !== expectedWorkflowRunId || component.gitSha !== expectedGitSha
    || component.artifactInventorySha256 !== hash(inventoryBytes)
    || manifest.manifestVersion !== 2 || !activePack
    || component.manifestSha256 !== hash(manifestBytes)
    || component.dataVersion !== activePack.version || component.releaseSequence !== manifest.releaseSequence
    || component.provenance.sourceSnapshotSetHash !== provenance?.candidateBuild?.sourceSnapshotSetHash
    || !/^[a-f0-9]{64}$/.test(provenance?.candidateBuild?.sourceSnapshotSetHash ?? "")
    || declaredPackPaths.size !== actualPackPaths.size
    || ![...declaredPackPaths].every((packPath) => actualPackPaths.has(packPath))
    || !manifest.packs.every((pack) => {
      const entry = actualEntriesByPath.get(stagedPackPath(pack));
      return entry?.sizeBytes === pack.sizeBytes && entry.sha256 === pack.sha256;
    })
    || !isSameInventory(inventory.entries, actualEntries)) {
    throw new Error("candidate inventory is invalid");
  }
  return { component, inventoryBytes };
}

async function actualInventory(root, relative = "") {
  const entries = [];
  for (const entry of await readdir(path.join(root, relative), { withFileTypes: true })) {
    const child = relative ? `${relative}/${entry.name}` : entry.name;
    const diskPath = path.join(root, child);
    const stats = await lstat(diskPath);
    if (stats.isSymbolicLink()) throw new Error("candidate inventory contains symlink");
    if (stats.isDirectory()) entries.push(...await actualInventory(root, child));
    else if (stats.isFile()) {
      if (relative === "" && (entry.name === "data-component-manifest.json" || entry.name === "data-artifact-inventory.json")) continue;
      const bytes = await regularBytes(diskPath, "candidate inventory entry");
      entries.push({ path: child, sizeBytes: bytes.length, sha256: hash(bytes) });
    } else throw new Error("candidate inventory contains non-file");
  }
  return entries.sort((left, right) => Buffer.compare(Buffer.from(left.path), Buffer.from(right.path)));
}

function isSameInventory(left, right) {
  return isDeepStrictEqual(left, right);
}

const jsonBytes = (value) => Buffer.from(`${JSON.stringify(value, null, 2)}\n`);

async function writeExclusiveJson(requestFile, requestBytes) {
  const requestOutput = path.resolve(requestFile);
  await assertMissing(requestOutput);
  const temporaryDirectory = await mkdtemp(path.join(path.dirname(requestOutput), ".promotion-request-"));
  try {
    const temporaryRequest = path.join(temporaryDirectory, "request.json");
    await writeFile(temporaryRequest, requestBytes, { flag: "wx" });
    await link(temporaryRequest, requestOutput);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

async function assertMissing(file) {
  try {
    await lstat(file);
    throw new Error("output must not exist");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`build-promotion-request: ${error.message}\n`);
    process.exitCode = 1;
  });
}
