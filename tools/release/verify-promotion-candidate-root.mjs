#!/usr/bin/env node
import { fileURLToPath } from "node:url";
import path from "node:path";

import { parseArgs } from "./validate-promotion-request.mjs";
import { verifyPromotionCandidateRoot } from "./build-promotion-request.mjs";

async function main() {
  const args = parseArgs(process.argv.slice(2), ["root", "workflow-run-id", "git-sha"]);
  await verifyPromotionCandidateRoot(
    args.get("root"), "--root", args.get("workflow-run-id"), args.get("git-sha"),
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`verify-promotion-candidate-root: ${error.message}\n`);
    process.exitCode = 1;
  });
}
