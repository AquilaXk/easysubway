#!/usr/bin/env node
import { link, lstat, mkdtemp, readdir, rm, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { isDeepStrictEqual } from "node:util";

import {
  hash,
  parseArgs,
  positiveDecimal,
  regularBytes,
  regularJson,
  reviewerFromApproval,
  validateCompatibilityEvidence,
  validatePromotionCandidate,
  validateInventory,
} from "./validate-promotion-request.mjs";

async function main() {
  const args = parseArgs(process.argv.slice(2), [
    "candidate-root-1", "candidate-root-2", "candidate-root-3", "selected-candidate-workflow-run-id",
    "candidate-workflow-run-id-1", "candidate-workflow-run-id-2", "candidate-workflow-run-id-3",
    "candidate-head-sha-1", "candidate-head-sha-2", "candidate-head-sha-3",
    "compatibility-evidence", "requested-by", "approval-evidence", "workflow-run-id", "issue-ref",
    "rebuild-parity-evidence-output", "output",
  ]);
  const candidates = await Promise.all(["candidate-root-1", "candidate-root-2", "candidate-root-3"]
    .map((name, index) => readCandidateRoot(
      args.get(name), `--${name}`,
      args.get(`candidate-workflow-run-id-${index + 1}`),
      args.get(`candidate-head-sha-${index + 1}`),
    )));
  const inventoryBytes = candidates[0].inventoryBytes;
  if (!candidates.every((candidate) => Buffer.compare(candidate.inventoryBytes, inventoryBytes) === 0)) {
    throw new Error("candidate inventories differ");
  }
  const components = candidates.map((candidate) => candidate.component)
    .sort((left, right) => BigInt(left.workflowRunId) < BigInt(right.workflowRunId) ? -1 : 1);
  const selectedCandidateWorkflowRunId = args.get("selected-candidate-workflow-run-id");
  if (!positiveDecimal(selectedCandidateWorkflowRunId)
    || new Set(components.map((component) => component.workflowRunId)).size !== 3
    || !components.some((component) => component.workflowRunId === selectedCandidateWorkflowRunId)
    || !sameIdentityExceptRun(components)) {
    throw new Error("candidate parity is invalid");
  }
  const component = components.find((candidate) => candidate.workflowRunId === selectedCandidateWorkflowRunId);

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

  const rebuildParityEvidence = {
    schemaVersion: 1,
    artifactKind: "datapack-rebuild-parity-evidence",
    selectedCandidateWorkflowRunId,
    candidates: components,
    artifactInventorySha256: hash(inventoryBytes),
    contractVersion: "datapack-rebuild-parity-v1",
    issueRef: args.get("issue-ref"),
  };
  const rebuildParityEvidenceBytes = jsonBytes(rebuildParityEvidence);
  const request = {
    schemaVersion: 1,
    artifactKind: "datapack-promotion-request",
    candidate: component,
    compatibilityEvidenceSha256: hash(compatibilityBytes),
    rebuildParityEvidenceSha256: hash(rebuildParityEvidenceBytes),
    requestedBy,
    approval: {
      workflowRunId,
      environment: "datapack-promotion",
      reviewer,
      approvalEvidenceSha256: hash(approvalBytes),
    },
    contractVersion: "datapack-promotion-v1",
    issueRef: args.get("issue-ref"),
  };
  const requestBytes = jsonBytes(request);
  await writeExclusiveJsonPair(
    args.get("rebuild-parity-evidence-output"), rebuildParityEvidenceBytes,
    args.get("output"), requestBytes,
  );
}

async function readCandidateRoot(root, label, expectedWorkflowRunId, expectedGitSha) {
  const stats = await lstat(root);
  if (!stats.isDirectory() || stats.isSymbolicLink()) {
    throw new Error(`${label} must be a regular non-symlink directory`);
  }
  const componentPath = path.join(root, "data-component-manifest.json");
  const inventoryPath = path.join(root, "data-artifact-inventory.json");
  const [component] = await regularJson(componentPath, `${label}/data-component-manifest.json`);
  const [inventory, inventoryBytes] = await regularJson(inventoryPath, `${label}/data-artifact-inventory.json`);
  validatePromotionCandidate(component);
  validateInventory(inventory);
  if (!positiveDecimal(expectedWorkflowRunId) || !/^[a-f0-9]{40}$/.test(expectedGitSha)
    || component.workflowRunId !== expectedWorkflowRunId || component.gitSha !== expectedGitSha
    || component.artifactInventorySha256 !== hash(inventoryBytes)
    || !isSameInventory(inventory.entries, await actualInventory(root))) {
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

function sameIdentityExceptRun(components) {
  const baseline = { ...components[0] };
  delete baseline.workflowRunId;
  return components.every((component) => {
    const identity = { ...component };
    delete identity.workflowRunId;
    return isDeepStrictEqual(identity, baseline);
  });
}

const jsonBytes = (value) => Buffer.from(`${JSON.stringify(value, null, 2)}\n`);

async function writeExclusiveJsonPair(evidenceFile, evidenceBytes, requestFile, requestBytes) {
  const evidenceOutput = path.resolve(evidenceFile);
  const requestOutput = path.resolve(requestFile);
  await Promise.all([evidenceOutput, requestOutput].map(assertMissing));
  const temporaryDirectory = await mkdtemp(path.join(path.dirname(requestOutput), ".promotion-request-"));
  let evidencePublished = false;
  try {
    const temporaryEvidence = path.join(temporaryDirectory, "evidence.json");
    const temporaryRequest = path.join(temporaryDirectory, "request.json");
    await writeFile(temporaryEvidence, evidenceBytes, { flag: "wx" });
    await writeFile(temporaryRequest, requestBytes, { flag: "wx" });
    try {
      await link(temporaryEvidence, evidenceOutput);
      evidencePublished = true;
      await link(temporaryRequest, requestOutput);
    } catch (error) {
      if (evidencePublished) await unlink(evidenceOutput).catch(() => {});
      throw error;
    }
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
