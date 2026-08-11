import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import test from "node:test";

import { validateSchema } from "./lib/json-schema-lite.mjs";
import { validateOwnerContract } from "../repo/audit-clean-checkout-reproducibility.mjs";

const ENGINE_SHA = "c84a23f981516640a530ab3119152c239597b6c6";
const TOOLCHAIN_DIGEST = "2bafa62df07a90cbc8501e2cc9c7f7abdcbb99069462893ab7f0c2ce02b31ac1";
const ENTRYPOINT = "tools/ci/run-clean-checkout-reproducibility-phase.mjs";
const CONTRACT_PATH = "contracts/documentation/clean-checkout-reproducibility-owner-contract.json";

const expectedContract = {
  schemaVersion: 1,
  repository: "AquilaXk/easysubway",
  variants: [{
    variantId: "hub-documentation-contracts",
    runnerImage: "ubuntu-24.04",
    toolchainDigest: TOOLCHAIN_DIGEST,
    phases: [
      phase("SETUP", ["setup", "24", TOOLCHAIN_DIGEST], "NONE", 60),
      phase("BUILD", ["build"], "NONE", 120),
      phase("TEST", ["test"], "NONE", 300),
      phase("DEBUG", ["debug"], "LOCAL_ONLY", 60),
    ],
  }],
};

const expectedWorkflow = `name: D13 Hub Clean Checkout Owner Receipt

on:
  workflow_dispatch:

permissions: {}

jobs:
  owner-receipt:
    permissions:
      contents: read
    uses: AquilaXk/easysubway/.github/workflows/clean-checkout-reproducibility-owner-receipt.yml@${ENGINE_SHA}
    with:
      contract_path: ${CONTRACT_PATH}
`;

test("Hub owner contract pins the exact four reproducibility phases and current toolchain lock", async () => {
  const [contractText, schemaText, lockBytes, entrypointStat] = await Promise.all([
    readFile(new URL(`../../${CONTRACT_PATH}`, import.meta.url), "utf8"),
    readFile(new URL("../../contracts/documentation/clean-checkout-reproducibility-owner-contract.schema.json", import.meta.url), "utf8"),
    readFile(new URL("../../tools/qa/package-lock.json", import.meta.url)),
    stat(new URL(`../../${ENTRYPOINT}`, import.meta.url)),
  ]);
  const contract = JSON.parse(contractText);
  const schema = JSON.parse(schemaText);
  const liteSchema = structuredClone(schema);
  delete liteSchema.properties.variants.items.properties.phases.items.properties.timeoutSeconds.maximum;

  assert.deepEqual(contract, expectedContract);
  assert.equal(validateSchema(liteSchema, contract).ok, true);
  assert.deepEqual(validateOwnerContract(contract), []);
  assert.equal(createHash("sha256").update(lockBytes).digest("hex"), TOOLCHAIN_DIGEST);
  assert.notEqual(entrypointStat.mode & 0o111, 0);
});

test("Hub caller is dispatch-only and invokes the immutable reusable producer without secrets", async () => {
  const text = await readFile(
    new URL("../../.github/workflows/clean-checkout-reproducibility-owner-receipt-caller.yml", import.meta.url),
    "utf8",
  );
  assert.equal(text, expectedWorkflow);
  for (const mutation of [
    expectedWorkflow.replace("workflow_dispatch:", "push:"),
    expectedWorkflow.replace("permissions: {}", "permissions:\n  actions: write"),
    expectedWorkflow.replace("      contents: read", "      contents: write"),
    expectedWorkflow.replace(`@${ENGINE_SHA}`, "@main"),
    expectedWorkflow.replace(`@${ENGINE_SHA}`, "@b89f4ddd50e98b2cff5a2a4cee0e0245a59a383a"),
    expectedWorkflow.replace(`contract_path: ${CONTRACT_PATH}`, "contract_path: contracts/other.json"),
    expectedWorkflow.replace("    with:\n", "    secrets: inherit\n    with:\n"),
    `${expectedWorkflow}  extra:\n    runs-on: ubuntu-latest\n`,
  ]) assert.equal(validateCaller(mutation), false);
});

test("phase entrypoint maps only the four approved commands and fails closed", async () => {
  const { runHubReproducibilityPhase } = await import("./run-clean-checkout-reproducibility-phase.mjs");
  const lockBytes = await readFile(new URL("../../tools/qa/package-lock.json", import.meta.url));
  const calls = [];
  const spawnProcess = (executable, arguments_, options) => {
    calls.push({ executable, arguments_, options });
    return { status: 0, error: undefined };
  };
  const base = {
    nodeVersion: "24.19.0",
    repositoryRoot: "/workspace",
    lockBytes,
    spawnProcess,
  };

  assert.equal(runHubReproducibilityPhase(["setup", "24", TOOLCHAIN_DIGEST], base), 0);
  assert.equal(runHubReproducibilityPhase(["build"], base), 0);
  assert.equal(runHubReproducibilityPhase(["test"], base), 0);
  assert.equal(runHubReproducibilityPhase(["debug"], base), 0);
  assert.deepEqual(calls.map(({ arguments_ }) => arguments_), [
    ["tools/ci/check-contracts.mjs", "--workspace", "contracts/workspaces/hub.json", "--current-only"],
    ["--test", "tools/repo/audit-clean-checkout-reproducibility.test.mjs", "tools/repo/produce-clean-checkout-reproducibility-owner-receipt.test.mjs"],
    ["tools/ci/api-catalog.mjs", "list"],
  ]);
  assert.equal(calls.every(({ executable, options }) => executable === process.execPath
    && options.cwd === "/workspace"
    && options.shell === false
    && options.stdio === "ignore"), true);

  for (const arguments_ of [[], ["unknown"], ["build", "extra"], ["setup", "23", TOOLCHAIN_DIGEST]]) {
    assert.throws(() => runHubReproducibilityPhase(arguments_, base), /D13_HUB_PHASE_INVALID/);
  }
  assert.throws(() => runHubReproducibilityPhase(["setup", "24", "0".repeat(64)], base), /D13_HUB_TOOLCHAIN_MISMATCH/);
  assert.throws(() => runHubReproducibilityPhase(["setup", "24", TOOLCHAIN_DIGEST], { ...base, nodeVersion: "23.0.0" }), /D13_HUB_NODE_MISMATCH/);
  for (const command of ["build", "test", "debug"]) {
    assert.throws(() => runHubReproducibilityPhase([command], { ...base, nodeVersion: "23.0.0" }), /D13_HUB_NODE_MISMATCH/);
    assert.throws(() => runHubReproducibilityPhase([command], { ...base, lockBytes: Buffer.from("mismatch") }), /D13_HUB_TOOLCHAIN_MISMATCH/);
  }
  assert.equal(calls.length, 3);
  assert.throws(() => runHubReproducibilityPhase(["build"], { ...base, spawnProcess: () => ({ status: 1 }) }), /D13_HUB_PHASE_NONZERO/);
  assert.throws(() => runHubReproducibilityPhase(["build"], { ...base, spawnProcess: () => ({ error: new Error("raw") }) }), /D13_HUB_PHASE_START_FAILED/);
});

function phase(name, arguments_, networkPolicy, timeoutSeconds) {
  return {
    phase: name,
    entrypoint: ENTRYPOINT,
    arguments: arguments_,
    workingDirectory: ".",
    requiredEnvironment: [],
    networkPolicy,
    timeoutSeconds,
    expectedExitCode: 0,
  };
}

function validateCaller(value) {
  return value === expectedWorkflow;
}
