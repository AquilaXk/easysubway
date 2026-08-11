#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const NODE_MAJOR = "24";
const TOOLCHAIN_LOCK_PATH = "tools/qa/package-lock.json";
const TOOLCHAIN_DIGEST = "2bafa62df07a90cbc8501e2cc9c7f7abdcbb99069462893ab7f0c2ce02b31ac1";

const COMMANDS = new Map([
  ["build", ["tools/ci/check-contracts.mjs", "--workspace", "contracts/workspaces/hub.json", "--current-only"]],
  ["test", ["--test", "tools/repo/audit-clean-checkout-reproducibility.test.mjs", "tools/repo/produce-clean-checkout-reproducibility-owner-receipt.test.mjs"]],
  ["debug", ["tools/ci/api-catalog.mjs", "list"]],
]);

export function runHubReproducibilityPhase(arguments_, {
  nodeVersion = process.versions.node,
  repositoryRoot = process.cwd(),
  lockBytes,
  spawnProcess = spawnSync,
} = {}) {
  if (!Array.isArray(arguments_)) fail("D13_HUB_PHASE_INVALID");
  if (arguments_[0] === "setup") {
    if (arguments_.length !== 3 || arguments_[1] !== NODE_MAJOR) fail("D13_HUB_PHASE_INVALID");
    if (arguments_[2] !== TOOLCHAIN_DIGEST) fail("D13_HUB_TOOLCHAIN_MISMATCH");
    verifyToolchain({ nodeVersion, repositoryRoot, lockBytes });
    return 0;
  }

  if (arguments_.length !== 1 || !COMMANDS.has(arguments_[0])) fail("D13_HUB_PHASE_INVALID");
  verifyToolchain({ nodeVersion, repositoryRoot, lockBytes });
  const result = spawnProcess(process.execPath, COMMANDS.get(arguments_[0]), {
    cwd: repositoryRoot,
    env: process.env,
    shell: false,
    stdio: "ignore",
  });
  if (result?.error) fail("D13_HUB_PHASE_START_FAILED");
  if (result?.status !== 0) fail("D13_HUB_PHASE_NONZERO");
  return 0;
}

function verifyToolchain({ nodeVersion, repositoryRoot, lockBytes }) {
  if (nodeVersion.split(".", 1)[0] !== NODE_MAJOR) fail("D13_HUB_NODE_MISMATCH");
  const bytes = lockBytes ?? readToolchainLock(repositoryRoot);
  if (createHash("sha256").update(bytes).digest("hex") !== TOOLCHAIN_DIGEST) {
    fail("D13_HUB_TOOLCHAIN_MISMATCH");
  }
}

function readToolchainLock(repositoryRoot) {
  try {
    return readFileSync(path.join(repositoryRoot, TOOLCHAIN_LOCK_PATH));
  } catch {
    fail("D13_HUB_TOOLCHAIN_UNAVAILABLE");
  }
}

function fail(code) {
  throw new Error(code);
}

function isMain() {
  return process.argv[1] != null && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
}

if (isMain()) {
  try {
    runHubReproducibilityPhase(process.argv.slice(2));
  } catch (error) {
    const code = typeof error?.message === "string" && /^D13_HUB_[A-Z_]+$/.test(error.message)
      ? error.message
      : "D13_HUB_PHASE_FAILED";
    process.stderr.write(`${code}\n`);
    process.exitCode = 1;
  }
}
