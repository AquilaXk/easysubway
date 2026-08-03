#!/usr/bin/env node
import { fileURLToPath } from "node:url";
import path from "node:path";

import { parseArgs, regularJson } from "./validate-promotion-request.mjs";
import { verifyPromotionCandidateRoot } from "./build-promotion-request.mjs";

async function main() {
  const args = parseArgs(process.argv.slice(2), ["root", "workflow-run-id", "git-sha", "build-spec"]);
  const [buildSpec] = await regularJson(args.get("build-spec"), "--build-spec");
  if (!/^[a-f0-9]{64}$/.test(buildSpec?.sourceSnapshotSetHash ?? "")) {
    throw new Error("build spec source snapshot set hash is invalid");
  }
  const candidate = await verifyPromotionCandidateRoot(
    args.get("root"), "--root", args.get("workflow-run-id"), args.get("git-sha"),
  );
  if (candidate.component.provenance.sourceSnapshotSetHash !== buildSpec.sourceSnapshotSetHash) {
    throw new Error("candidate source snapshot set hash does not match build spec");
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`verify-promotion-candidate-root: ${error.message}\n`);
    process.exitCode = 1;
  });
}
