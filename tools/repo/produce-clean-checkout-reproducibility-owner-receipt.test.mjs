import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import {
  commandSha256,
  validateOwnerReceipt,
} from "./audit-clean-checkout-reproducibility.mjs";
import {
  runOwnerReceiptCli,
} from "./produce-clean-checkout-reproducibility-owner-receipt.mjs";

const execFileAsync = promisify(execFile);
const root = process.cwd();
const producerPath = path.join(root, "tools/repo/produce-clean-checkout-reproducibility-owner-receipt.mjs");
const contractSchemaPath = path.join(root, "contracts/documentation/clean-checkout-reproducibility-owner-contract.schema.json");
const receiptSchemaPath = path.join(root, "contracts/documentation/clean-checkout-reproducibility-owner-receipt.schema.json");
const repository = "AquilaXk/easysubway";
const runnerImage = "ubuntu-24.04";
const phases = ["SETUP", "BUILD", "TEST", "DEBUG"];
const requiredEnvironment = "D13_TEST_REQUIRED";

const phaseScript = `#!/usr/bin/env node
import { spawn } from "node:child_process";
import { renameSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";

const [phase, literal] = process.argv.slice(2);
if (literal !== \`literal-\${phase}\` || path.basename(process.cwd()) !== "work" || !Object.hasOwn(process.env, "D13_TEST_REQUIRED")) process.exit(41);
if (process.env.D13_PHASE_EXIT === phase) {
  process.stderr.write(process.env.D13_TEST_SECRET ?? "private-diagnostic");
  process.exit(9);
}
if (process.env.D13_PHASE_TIMEOUT === phase) setInterval(() => {}, 1_000);
if (process.env.D13_PHASE_LEFTOVER === phase) {
  const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { stdio: "ignore" });
  child.unref();
}
if (process.env.D13_PHASE_DETACHED_LEFTOVER === phase) {
  const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], { detached: true, env: { PATH: process.env.PATH ?? "" }, stdio: "ignore" });
  child.unref();
}
if (process.env.D13_PHASE_MUTATE_ENTRYPOINT === phase) {
  writeFileSync(path.resolve(process.cwd(), "../ci/phase.mjs"), "#!/usr/bin/env node\\n");
}
if (process.env.D13_PHASE_MUTATE_WORKDIR === phase) {
  const current = process.cwd();
  const moved = \`\${current}-moved\`;
  renameSync(current, moved);
  symlinkSync(path.basename(moved), current, "dir");
}
`;

function contractFixture() {
  return {
    schemaVersion: 1,
    repository,
    variants: [{
      variantId: "ubuntu-node24",
      runnerImage,
      toolchainDigest: "a".repeat(64),
      phases: phases.map((phase) => ({
        phase,
        entrypoint: "ci/phase.mjs",
        arguments: [phase, `literal-${phase}`],
        workingDirectory: "work",
        requiredEnvironment: [requiredEnvironment],
        networkPolicy: phase === "DEBUG" ? "LOCAL_ONLY" : "NONE",
        timeoutSeconds: phase === "DEBUG" ? 2 : 5,
        expectedExitCode: 0,
      })),
    }],
  };
}

async function createFixture({
  mutateContract = () => {},
  malformedContract = false,
  contractSymlink = false,
  entrypointSymlink = false,
  executable = true,
} = {}) {
  const temporaryRoot = await mkdtemp(path.join(tmpdir(), "d13-owner-receipt-"));
  const ownerRoot = path.join(temporaryRoot, "owner");
  await mkdir(path.join(ownerRoot, "ci"), { recursive: true });
  await mkdir(path.join(ownerRoot, "work"));
  const actualEntrypoint = entrypointSymlink
    ? path.join(ownerRoot, "ci", "phase-real.mjs")
    : path.join(ownerRoot, "ci", "phase.mjs");
  await writeFile(actualEntrypoint, phaseScript);
  await chmod(actualEntrypoint, executable ? 0o755 : 0o644);
  if (entrypointSymlink) await symlink("phase-real.mjs", path.join(ownerRoot, "ci", "phase.mjs"));

  const contract = contractFixture();
  mutateContract(contract);
  const contractText = malformedContract ? "{private-contract-body" : `${JSON.stringify(contract, null, 2)}\n`;
  const contractPath = "contracts/clean-checkout-reproducibility-owner-contract.json";
  await mkdir(path.join(ownerRoot, "contracts"));
  if (contractSymlink) {
    await writeFile(path.join(ownerRoot, "contracts", "actual-contract.json"), contractText);
    await symlink("actual-contract.json", path.join(ownerRoot, contractPath));
  } else {
    await writeFile(path.join(ownerRoot, contractPath), contractText);
  }

  await execFileAsync("git", ["init", "-q"], { cwd: ownerRoot });
  await execFileAsync("git", ["add", "."], { cwd: ownerRoot });
  await execFileAsync("git", [
    "-c", "user.name=EasySubway D13 Test",
    "-c", "user.email=d13-test@easysubway.local",
    "commit", "-q", "-m", "fixture",
  ], { cwd: ownerRoot });
  const { stdout } = await execFileAsync("git", ["rev-parse", "HEAD"], { cwd: ownerRoot, encoding: "utf8" });
  return {
    temporaryRoot,
    ownerRoot,
    contract,
    contractText,
    contractPath,
    sourceSha: stdout.trim(),
    outputPath: path.join(temporaryRoot, "clean-checkout-reproducibility-owner-receipt.json"),
    async cleanup() { await rm(temporaryRoot, { recursive: true, force: true }); },
  };
}

function argvFor(fixture, overrides = {}) {
  return [
    "--owner-root", fixture.ownerRoot,
    "--contract", overrides.contractPath ?? fixture.contractPath,
    "--contract-schema", contractSchemaPath,
    "--receipt-schema", receiptSchemaPath,
    "--repository", overrides.repository ?? repository,
    "--source-sha", overrides.sourceSha ?? fixture.sourceSha,
    "--runner-image", overrides.runnerImage ?? runnerImage,
    "--output", overrides.outputPath ?? fixture.outputPath,
  ];
}

async function runFixture(fixture, { overrides, env = {} } = {}) {
  return runOwnerReceiptCli({
    argv: argvFor(fixture, overrides),
    env: { ...process.env, [requiredEnvironment]: "", ...env },
  });
}

async function absent(file) {
  try { await lstat(file); return false; } catch (error) { if (error?.code === "ENOENT") return true; throw error; }
}

test("valid clean fixture produces one schema-valid deterministic four-phase receipt", async (t) => {
  const fixture = await createFixture();
  t.after(() => fixture.cleanup());
  const result = await runFixture(fixture);
  assert.equal(result.exitCode, 0);
  assert.equal(result.outputWritten, true);
  assert.equal(result.errorCode, null);

  const receiptText = await readFile(fixture.outputPath, "utf8");
  const receipt = JSON.parse(receiptText);
  const receiptSchema = JSON.parse(await readFile(receiptSchemaPath, "utf8"));
  assert.equal(validateSchema(receiptSchema, receipt).ok, true);
  assert.deepEqual(validateOwnerReceipt(receipt), []);
  assert.equal(receipt.repository, repository);
  assert.equal(receipt.sourceSha, fixture.sourceSha);
  assert.equal(receipt.contractSha256, createHash("sha256").update(fixture.contractText).digest("hex"));
  assert.deepEqual(receipt.cleanCheckout, {
    repository,
    sourceSha: fixture.sourceSha,
    initialTrackedDiffCount: 0,
    initialUntrackedCount: 0,
  });
  assert.deepEqual(receipt.variants.map(({ variantId }) => variantId), ["ubuntu-node24"]);
  assert.deepEqual(receipt.variants[0].phases.map(({ phase }) => phase), phases);
  assert.deepEqual(
    receipt.variants[0].phases.map(({ commandSha256: value }) => value),
    phases.map((phase) => commandSha256(fixture.contract.variants[0].phases.find((item) => item.phase === phase))),
  );
  assert.equal(receipt.variants[0].phases.every((phase) => phase.exitCode === 0 && phase.timedOut === false && phase.unexpectedProcessCount === 0), true);
  assert.equal(receipt.variants[0].phases.every((phase, index, list) => index === 0 || Date.parse(list[index - 1].completedAt) <= Date.parse(phase.startedAt)), true);
  assert.equal(Date.parse(receipt.variants[0].phases.at(-1).completedAt) <= Date.parse(receipt.observedAt), true);
});

test("dirty tracked, staged, and untracked owner checkouts fail before execution", async (t) => {
  for (const state of ["tracked", "staged", "untracked"]) {
    await t.test(state, async (t) => {
      const fixture = await createFixture();
      t.after(() => fixture.cleanup());
      if (state === "untracked") await writeFile(path.join(fixture.ownerRoot, "private-untracked"), "secret");
      else {
        await writeFile(path.join(fixture.ownerRoot, "work", "dirty"), "secret");
        await execFileAsync("git", ["add", "work/dirty"], { cwd: fixture.ownerRoot });
        if (state === "tracked") await writeFile(path.join(fixture.ownerRoot, "work", "dirty"), "changed-secret");
      }
      const result = await runFixture(fixture);
      assert.equal(result.exitCode, 2);
      assert.equal(result.errorCode, "CHECKOUT_DIRTY");
      assert.equal(await absent(fixture.outputPath), true);
    });
  }
});

test("contract identity, schema, path, symlink, and executable failures are fail-closed", async (t) => {
  const cases = [
    ["malformed contract", { malformedContract: true }, {}, "OWNER_CONTRACT_INVALID"],
    ["wrong repository", { mutateContract: (contract) => { contract.repository = "AquilaXk/easysubway-data"; } }, {}, "OWNER_CONTRACT_IDENTITY_MISMATCH"],
    ["wrong source SHA", {}, { sourceSha: "f".repeat(40) }, "OWNER_SOURCE_IDENTITY_MISMATCH"],
    ["wrong runner", {}, { runnerImage: "ubuntu-22.04" }, "OWNER_RUNNER_IDENTITY_MISMATCH"],
    ["unsafe contract path", {}, { contractPath: "../private-contract.json" }, "CONTRACT_PATH_INVALID"],
    ["contract symlink", { contractSymlink: true }, {}, "CONTRACT_PATH_INVALID"],
    ["unsafe entrypoint", { mutateContract: (contract) => { contract.variants[0].phases[0].entrypoint = "../phase.mjs"; } }, {}, "OWNER_CONTRACT_INVALID"],
    ["entrypoint symlink", { entrypointSymlink: true }, {}, "ENTRYPOINT_INVALID"],
    ["non-executable entrypoint", { executable: false }, {}, "ENTRYPOINT_INVALID"],
    ["timeout above schema maximum", { mutateContract: (contract) => { contract.variants[0].phases[0].timeoutSeconds = 3601; } }, {}, "OWNER_CONTRACT_INVALID"],
  ];
  for (const [name, fixtureOptions, overrides, errorCode] of cases) {
    await t.test(name, async (t) => {
      const fixture = await createFixture(fixtureOptions);
      t.after(() => fixture.cleanup());
      const result = await runFixture(fixture, { overrides });
      assert.equal(result.exitCode, 2);
      assert.equal(result.errorCode, errorCode);
      assert.equal(await absent(fixture.outputPath), true);
    });
  }
});

test("missing environment, nonzero, timeout, and leftover process never create a receipt", async (t) => {
  const cases = [
    ["missing required environment", { [requiredEnvironment]: undefined }, "REQUIRED_ENVIRONMENT_MISSING"],
    ["nonzero exit", { D13_PHASE_EXIT: "BUILD", D13_TEST_SECRET: "provider-secret-value" }, "PHASE_NONZERO"],
    ["timeout", { D13_PHASE_TIMEOUT: "DEBUG" }, "PHASE_TIMEOUT"],
    ["leftover process", { D13_PHASE_LEFTOVER: "TEST" }, "PHASE_PROCESS_LEAK"],
    ["entrypoint replaced by an earlier phase", { D13_PHASE_MUTATE_ENTRYPOINT: "SETUP" }, "ENTRYPOINT_CHANGED"],
    ["working directory replaced by an earlier phase", { D13_PHASE_MUTATE_WORKDIR: "SETUP" }, "WORKING_DIRECTORY_INVALID"],
  ];
  for (const [name, env, errorCode] of cases) {
    await t.test(name, async (t) => {
      const fixture = await createFixture();
      t.after(() => fixture.cleanup());
      const inherited = { ...process.env, ...env };
      if (env[requiredEnvironment] === undefined && Object.hasOwn(env, requiredEnvironment)) delete inherited[requiredEnvironment];
      else inherited[requiredEnvironment] = "";
      const result = await runOwnerReceiptCli({ argv: argvFor(fixture), env: inherited });
      assert.equal(result.exitCode, 2);
      assert.equal(result.errorCode, errorCode);
      assert.equal(await absent(fixture.outputPath), true);
      assert.doesNotMatch(JSON.stringify(result), /provider-secret-value|private-diagnostic|d13-owner-receipt-/);
    });
  }

  await t.test("detached leftover process", { skip: process.platform !== "linux" ? "production workflow is Linux; live detached-process regression runs in CI" : false }, async (t) => {
    const fixture = await createFixture();
    t.after(() => fixture.cleanup());
    const result = await runFixture(fixture, { env: { D13_PHASE_DETACHED_LEFTOVER: "TEST" } });
    assert.equal(result.exitCode, 2);
    assert.equal(result.errorCode, "PHASE_PROCESS_LEAK");
    assert.equal(await absent(fixture.outputPath), true);
  });
});

test("CLI diagnostics are sanitized and an existing output remains unaltered", async (t) => {
  const fixture = await createFixture();
  t.after(() => fixture.cleanup());
  await writeFile(fixture.outputPath, "owner-marker\n");
  const existing = await runFixture(fixture);
  assert.equal(existing.exitCode, 2);
  assert.equal(existing.errorCode, "OUTPUT_EXISTS");
  assert.equal(await readFile(fixture.outputPath, "utf8"), "owner-marker\n");

  await rm(fixture.outputPath);
  await assert.rejects(
    execFileAsync(process.execPath, [producerPath, ...argvFor(fixture)], {
      cwd: root,
      encoding: "utf8",
      env: {
        ...process.env,
        [requiredEnvironment]: "",
        D13_PHASE_EXIT: "SETUP",
        D13_TEST_SECRET: "provider-secret-value",
      },
    }),
    (error) => {
      assert.equal(error.code, 2);
      assert.match(error.stderr, /^D13_OWNER_RECEIPT_PHASE_NONZERO\n$/);
      assert.equal(error.stdout, "");
      assert.doesNotMatch(`${error.stdout}${error.stderr}`, /provider-secret-value|private-diagnostic|\/Volumes\/|\/tmp\//);
      return true;
    },
  );
  assert.equal(await absent(fixture.outputPath), true);
});

test("reusable workflow and composite action freeze the dual-checkout single-artifact boundary", async () => {
  const action = await readFile(path.join(root, ".github/actions/clean-checkout-reproducibility-owner-receipt/action.yml"), "utf8");
  const workflow = await readFile(path.join(root, ".github/workflows/clean-checkout-reproducibility-owner-receipt.yml"), "utf8");
  assert.match(action, /^name: Clean Checkout Reproducibility Owner Receipt$/m);
  assert.match(action, /^inputs:\n  owner-root:\n    description: [^\n]+\n    required: true\n  contract-path:\n    description: [^\n]+\n    required: true\n  repository:\n    description: [^\n]+\n    required: true\n  source-sha:\n    description: [^\n]+\n    required: true\n  runner-image:\n    description: [^\n]+\n    required: true\n  output:\n    description: [^\n]+\n    required: true$/m);
  assert.match(action, /^runs:\n  using: composite$/m);
  assert.match(action, /node "\$\{GITHUB_ACTION_PATH\}\/\.\.\/\.\.\/\.\.\/tools\/repo\/produce-clean-checkout-reproducibility-owner-receipt\.mjs"/);
  assert.match(action, /--contract-schema "\$\{GITHUB_ACTION_PATH\}\/\.\.\/\.\.\/\.\.\/contracts\/documentation\/clean-checkout-reproducibility-owner-contract\.schema\.json"/);
  assert.match(action, /--receipt-schema "\$\{GITHUB_ACTION_PATH\}\/\.\.\/\.\.\/\.\.\/contracts\/documentation\/clean-checkout-reproducibility-owner-receipt\.schema\.json"/);
  assert.doesNotMatch(action, /secrets|inherit|cache|continue-on-error|curl|gh api/i);

  assert.match(workflow, /^on:\n  workflow_call:\n    inputs:\n      contract_path:\n        required: true\n        type: string$/m);
  assert.match(workflow, /^permissions: \{\}$/m);
  assert.match(workflow, /permissions:\n      contents: read/);
  assert.match(workflow, /runs-on: ubuntu-24\.04/);
  assert.match(workflow, /repository: \$\{\{ github\.repository \}\}\n          ref: \$\{\{ github\.sha \}\}\n          path: owner-source\n          persist-credentials: false/);
  assert.match(workflow, /repository: \$\{\{ fromJSON\(toJSON\(job\)\)\[format\('workflow_\{0\}', 'repository'\)\] \}\}\n          ref: \$\{\{ fromJSON\(toJSON\(job\)\)\[format\('workflow_\{0\}', 'sha'\)\] \}\}\n          path: d13-engine\n          persist-credentials: false/);
  assert.match(workflow, /uses: \.\/d13-engine\/\.github\/actions\/clean-checkout-reproducibility-owner-receipt/);
  assert.match(workflow, /contract-path: \$\{\{ inputs\.contract_path \}\}/);
  assert.match(workflow, /repository: \$\{\{ github\.repository \}\}/);
  assert.match(workflow, /source-sha: \$\{\{ github\.sha \}\}/);
  assert.match(workflow, /runner-image: ubuntu-24\.04/);
  assert.equal((workflow.match(/actions\/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02/g) ?? []).length, 1);
  assert.match(workflow, /name: clean-checkout-reproducibility-owner-receipt-\$\{\{ github\.sha \}\}/);
  assert.match(workflow, /path: \$\{\{ runner\.temp \}\}\/clean-checkout-reproducibility-owner-receipt\.json/);
  assert.match(workflow, /if-no-files-found: error/);
  assert.match(workflow, /overwrite: false/);
  assert.match(workflow, /retention-days: 14/);
  assert.doesNotMatch(workflow, /secrets:|secrets\.|inherit|actions\/cache|continue-on-error|previous|fallback|git (?:add|commit|push)/i);
  const producer = await readFile(producerPath, "utf8");
  assert.match(producer, /snapshotLinuxProcesses/);
  assert.match(producer, /readFile\(`\/proc\/\$\{pid\}\/status`, "utf8"\)/);
  assert.match(producer, /readFile\(`\/proc\/\$\{pid\}\/stat`, "utf8"\)/);
  assert.match(producer, /await snapshotEntrypoint\(ownerRoot, prepared\.contract\.entrypoint\)/);
  assert.match(producer, /await snapshotWorkingDirectory\(ownerRoot, prepared\.contract\.workingDirectory\)/);
});
