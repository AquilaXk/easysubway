#!/usr/bin/env node
import { link, lstat, mkdtemp, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  hash,
  parseArgs,
  positiveDecimal,
  regularBytes,
  regularJson,
  reviewerFromApproval,
  validateCompatibilityEvidence,
  validateComponent,
  validateInventory,
} from "./validate-promotion-request.mjs";

async function main() {
  const args = parseArgs(process.argv.slice(2), [
    "component", "inventory", "compatibility-evidence", "requested-by", "approval-evidence",
    "workflow-run-id", "issue-ref", "output",
  ]);
  const [component] = await regularJson(args.get("component"), "--component");
  validateComponent(component);
  const [inventory, inventoryBytes] = await regularJson(args.get("inventory"), "--inventory");
  validateInventory(inventory);
  if (component.artifactInventorySha256 !== hash(inventoryBytes)) {
    throw new Error("inventory hash mismatch");
  }

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
    || args.get("issue-ref") !== "AquilaXk/easysubway#2699") {
    throw new Error("request arguments are invalid");
  }

  const request = {
    schemaVersion: 1,
    artifactKind: "datapack-promotion-request",
    candidate: component,
    compatibilityEvidenceSha256: hash(compatibilityBytes),
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
  await writeExclusiveJson(args.get("output"), request);
}

async function writeExclusiveJson(file, value) {
  const output = path.resolve(file);
  try {
    await lstat(output);
    throw new Error("--output must not exist");
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }

  const temporaryDirectory = await mkdtemp(path.join(path.dirname(output), ".promotion-request-"));
  try {
    const temporaryOutput = path.join(temporaryDirectory, "request.json");
    await writeFile(temporaryOutput, `${JSON.stringify(value, null, 2)}\n`, { flag: "wx" });
    await link(temporaryOutput, output);
  } finally {
    await rm(temporaryDirectory, { recursive: true, force: true });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`build-promotion-request: ${error.message}\n`);
    process.exitCode = 1;
  });
}
