#!/usr/bin/env node
import { execFile, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import {
  lstat,
  open,
  readFile,
  realpath,
  readdir,
  unlink,
} from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

import {
  validateCleanCheckoutReproducibilityOwnerContractSchema,
  validateCleanCheckoutReproducibilityOwnerReceiptSchema,
} from "../ci/check-contracts.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";
import {
  REPOSITORIES,
  commandSha256,
  validateOwnerContract,
  validateOwnerReceipt,
} from "./audit-clean-checkout-reproducibility.mjs";

const execFileAsync = promisify(execFile);
const REPOSITORY_SET = new Set(REPOSITORIES);
const PHASES = ["SETUP", "BUILD", "TEST", "DEBUG"];
const SAFE_PATH = /^(?!\/)(?!.*(?:^|\/)\.{1,2}(?:\/|$))(?!.*[?#])[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const SHA = /^[0-9a-f]{40}$/;
const RUNNER_IMAGE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const CODE = /^[A-Z][A-Z0-9_]*$/;
const INPUT_LIMIT = 2 * 1024 * 1024;
const GIT_OUTPUT_LIMIT = 2 * 1024 * 1024;
const TERMINATION_GRACE_MS = 250;

export class OwnerReceiptFailure extends Error {
  constructor(code) {
    super(code);
    this.code = code;
  }
}

function failure(code) {
  throw new OwnerReceiptFailure(code);
}

function parseArguments(argv) {
  if (argv.length !== 16
    || argv[0] !== "--owner-root"
    || argv[2] !== "--contract"
    || argv[4] !== "--contract-schema"
    || argv[6] !== "--receipt-schema"
    || argv[8] !== "--repository"
    || argv[10] !== "--source-sha"
    || argv[12] !== "--runner-image"
    || argv[14] !== "--output") failure("ARGUMENT_INVALID");
  const parsed = {
    ownerRoot: argv[1],
    contractPath: argv[3],
    contractSchemaPath: argv[5],
    receiptSchemaPath: argv[7],
    repository: argv[9],
    sourceSha: argv[11],
    runnerImage: argv[13],
    outputPath: argv[15],
  };
  if (!path.isAbsolute(parsed.ownerRoot)
    || !SAFE_PATH.test(parsed.contractPath)
    || !path.isAbsolute(parsed.contractSchemaPath)
    || !path.isAbsolute(parsed.receiptSchemaPath)
    || !REPOSITORY_SET.has(parsed.repository)
    || !SHA.test(parsed.sourceSha)
    || !RUNNER_IMAGE.test(parsed.runnerImage)
    || !path.isAbsolute(parsed.outputPath)) failure(SAFE_PATH.test(parsed.contractPath ?? "") ? "ARGUMENT_INVALID" : "CONTRACT_PATH_INVALID");
  return parsed;
}

async function assertOutputAbsent(outputPath) {
  try {
    await lstat(outputPath);
    failure("OUTPUT_EXISTS");
  } catch (error) {
    if (error instanceof OwnerReceiptFailure) throw error;
    if (error?.code !== "ENOENT") failure("OUTPUT_INVALID");
  }
}

async function readBounded(filePath, code) {
  let entry;
  try { entry = await lstat(filePath); } catch { failure(code); }
  if (!entry.isFile() || entry.isSymbolicLink() || entry.size > INPUT_LIMIT) failure(code);
  try { return await readFile(filePath, "utf8"); } catch { failure(code); }
}

async function resolveOwnerRoot(candidate) {
  const absolute = path.resolve(candidate);
  let entry; let resolved;
  try {
    entry = await lstat(absolute);
    resolved = await realpath(absolute);
  } catch { failure("OWNER_ROOT_INVALID"); }
  if (!entry.isDirectory() || entry.isSymbolicLink()) failure("OWNER_ROOT_INVALID");
  return resolved;
}

async function resolveOwnedPath(ownerRoot, relativePath, { directory = false, executable = false, code }) {
  const safeDirectory = relativePath === ".";
  if (!safeDirectory && (!SAFE_PATH.test(relativePath) || path.posix.normalize(relativePath) !== relativePath)) failure(code);
  const segments = safeDirectory ? [] : relativePath.split("/");
  let candidate = ownerRoot;
  for (const segment of segments) {
    candidate = path.join(candidate, segment);
    let entry;
    try { entry = await lstat(candidate); } catch { failure(code); }
    if (entry.isSymbolicLink()) failure(code);
  }
  let entry; let resolved;
  try {
    entry = await lstat(candidate);
    resolved = await realpath(candidate);
  } catch { failure(code); }
  if (resolved !== candidate || !resolved.startsWith(`${ownerRoot}${path.sep}`) && resolved !== ownerRoot) failure(code);
  if (directory ? !entry.isDirectory() : !entry.isFile()) failure(code);
  if (executable && (entry.mode & 0o111) === 0) failure(code);
  return candidate;
}

async function runGit(ownerRoot, arguments_) {
  try {
    const { stdout } = await execFileAsync("git", arguments_, {
      cwd: ownerRoot,
      encoding: null,
      timeout: 30_000,
      killSignal: "SIGTERM",
      maxBuffer: GIT_OUTPUT_LIMIT,
    });
    return Buffer.isBuffer(stdout) ? stdout : Buffer.from(stdout);
  } catch { failure("GIT_STATE_INVALID"); }
}

function nulEntries(bytes) {
  if (bytes.length === 0) return [];
  const values = bytes.toString("utf8").split("\0");
  if (values.at(-1) !== "") failure("GIT_STATE_INVALID");
  values.pop();
  return values;
}

async function collectCleanCheckout(ownerRoot, repository, sourceSha) {
  const [headBytes, unstagedBytes, stagedBytes, untrackedBytes] = await Promise.all([
    runGit(ownerRoot, ["rev-parse", "--verify", "HEAD"]),
    runGit(ownerRoot, ["diff", "--name-only", "-z", "--no-ext-diff", "--"]),
    runGit(ownerRoot, ["diff", "--cached", "--name-only", "-z", "--no-ext-diff", "--"]),
    runGit(ownerRoot, ["ls-files", "--others", "--exclude-standard", "-z"]),
  ]);
  const head = headBytes.toString("utf8").trim();
  if (!SHA.test(head) || head !== sourceSha) failure("OWNER_SOURCE_IDENTITY_MISMATCH");
  const tracked = new Set([...nulEntries(unstagedBytes), ...nulEntries(stagedBytes)]);
  const untracked = nulEntries(untrackedBytes);
  if (tracked.size !== 0 || untracked.length !== 0) failure("CHECKOUT_DIRTY");
  return {
    repository,
    sourceSha,
    initialTrackedDiffCount: tracked.size,
    initialUntrackedCount: untracked.length,
  };
}

function timestamp(now) {
  const value = now();
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) failure("CLOCK_INVALID");
  return date.toISOString();
}

function processGroupExists(pid) {
  if (!Number.isSafeInteger(pid) || pid < 1) return false;
  try { process.kill(-pid, 0); return true; } catch (error) {
    if (error?.code === "ESRCH") return false;
    return true;
  }
}

function signalProcessGroup(pid, signal) {
  try { process.kill(-pid, signal); } catch (error) {
    if (error?.code !== "ESRCH") return false;
  }
  return true;
}

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function snapshotLinuxProcesses() {
  if (process.platform !== "linux") return null;
  let entries;
  try { entries = await readdir("/proc", { withFileTypes: true }); } catch { failure("PROCESS_ISOLATION_UNAVAILABLE"); }
  const currentUid = process.getuid();
  const snapshot = new Map();
  for (const entry of entries) {
    if (!entry.isDirectory() || !/^[1-9][0-9]*$/.test(entry.name)) continue;
    const pid = Number(entry.name);
    if (!Number.isSafeInteger(pid)) continue;
    try {
      const [status, stat] = await Promise.all([
        readFile(`/proc/${pid}/status`, "utf8"),
        readFile(`/proc/${pid}/stat`, "utf8"),
      ]);
      const uid = Number(/^Uid:\s+([0-9]+)/m.exec(status)?.[1]);
      if (uid !== currentUid) continue;
      const close = stat.lastIndexOf(")");
      const startTime = close === -1 ? null : stat.slice(close + 2).trim().split(/\s+/)[19];
      if (!/^[0-9]+$/.test(startTime ?? "")) failure("PROCESS_ISOLATION_UNAVAILABLE");
      snapshot.set(pid, startTime);
    } catch (error) {
      if (error instanceof OwnerReceiptFailure) throw error;
      if (!["ENOENT", "EACCES", "EPERM"].includes(error?.code)) failure("PROCESS_ISOLATION_UNAVAILABLE");
    }
  }
  return snapshot;
}

function unexpectedProcesses(baseline, current) {
  if (baseline == null || current == null) return [];
  return [...current].filter(([pid, startTime]) => pid !== process.pid && baseline.get(pid) !== startTime);
}

function signalProcesses(processes, signal) {
  for (const [pid] of processes) {
    try { process.kill(pid, signal); } catch (error) {
      if (error?.code !== "ESRCH") return false;
    }
  }
  return true;
}

async function cleanProcessScope(pid, baseline, snapshotProcesses) {
  const groupExists = processGroupExists(pid);
  let unexpected = unexpectedProcesses(baseline, await snapshotProcesses());
  const unexpectedProcessCount = Math.max(groupExists ? 1 : 0, unexpected.length);
  if (unexpectedProcessCount === 0) return 0;
  if (groupExists) signalProcessGroup(pid, "SIGTERM");
  signalProcesses(unexpected, "SIGTERM");
  await delay(TERMINATION_GRACE_MS);
  unexpected = unexpectedProcesses(baseline, await snapshotProcesses());
  if (processGroupExists(pid)) signalProcessGroup(pid, "SIGKILL");
  signalProcesses(unexpected, "SIGKILL");
  if (processGroupExists(pid) || unexpected.length !== 0) {
    await delay(TERMINATION_GRACE_MS);
  }
  if (processGroupExists(pid) || unexpectedProcesses(baseline, await snapshotProcesses()).length !== 0) failure("PHASE_CLEANUP_FAILED");
  return unexpectedProcessCount;
}

export async function executeOwnerPhase({ entrypoint, arguments_, workingDirectory, timeoutSeconds, environment, now = () => new Date(), spawnProcess = spawn, snapshotProcesses = snapshotLinuxProcesses }) {
  const processBaseline = await snapshotProcesses();
  const startedAt = timestamp(now);
  const execution = await new Promise((resolve, reject) => {
    let timedOut = false;
    let forceTimer;
    let child;
    try {
      child = spawnProcess(entrypoint, arguments_, {
        cwd: workingDirectory,
        env: environment,
        shell: false,
        detached: true,
        stdio: ["ignore", "ignore", "ignore"],
      });
    } catch { reject(new OwnerReceiptFailure("PHASE_START_FAILED")); return; }
    const timeoutTimer = setTimeout(() => {
      timedOut = true;
      signalProcessGroup(child.pid, "SIGTERM");
      forceTimer = setTimeout(() => signalProcessGroup(child.pid, "SIGKILL"), TERMINATION_GRACE_MS);
    }, timeoutSeconds * 1_000);
    child.once("error", () => {
      clearTimeout(timeoutTimer);
      clearTimeout(forceTimer);
      reject(new OwnerReceiptFailure("PHASE_START_FAILED"));
    });
    child.once("close", async (code) => {
      clearTimeout(timeoutTimer);
      clearTimeout(forceTimer);
      try {
        const unexpectedProcessCount = await cleanProcessScope(child.pid, processBaseline, snapshotProcesses);
        resolve({
          exitCode: Number.isInteger(code) ? code : -1,
          timedOut,
          unexpectedProcessCount,
        });
      } catch { reject(new OwnerReceiptFailure("PHASE_PROCESS_LEAK")); }
    });
  });
  const completedAt = timestamp(now);
  return { startedAt, completedAt, ...execution };
}

async function fileSha256(filePath) {
  return new Promise((resolve, reject) => {
    const hash = createHash("sha256");
    const input = createReadStream(filePath);
    input.on("data", (chunk) => hash.update(chunk));
    input.once("error", reject);
    input.once("end", () => resolve(hash.digest("hex")));
  });
}

async function snapshotEntrypoint(ownerRoot, relativePath) {
  const resolvedPath = await resolveOwnedPath(ownerRoot, relativePath, { executable: true, code: "ENTRYPOINT_INVALID" });
  let entry; let sha256;
  try {
    entry = await lstat(resolvedPath);
    sha256 = await fileSha256(resolvedPath);
  } catch { failure("ENTRYPOINT_INVALID"); }
  return { path: resolvedPath, mode: entry.mode & 0o777, sha256 };
}

async function snapshotWorkingDirectory(ownerRoot, relativePath) {
  const resolvedPath = await resolveOwnedPath(ownerRoot, relativePath, { directory: true, code: "WORKING_DIRECTORY_INVALID" });
  let entry;
  try { entry = await lstat(resolvedPath); } catch { failure("WORKING_DIRECTORY_INVALID"); }
  return { path: resolvedPath, device: entry.dev, inode: entry.ino };
}

async function prepareContract({ ownerRoot, contractPath, contractSchemaPath, receiptSchemaPath, repository, runnerImage }) {
  const resolvedContractPath = await resolveOwnedPath(ownerRoot, contractPath, { code: "CONTRACT_PATH_INVALID" });
  const [contractText, contractSchemaText, receiptSchemaText] = await Promise.all([
    readBounded(resolvedContractPath, "OWNER_CONTRACT_INVALID"),
    readBounded(contractSchemaPath, "CONTRACT_SCHEMA_INVALID"),
    readBounded(receiptSchemaPath, "RECEIPT_SCHEMA_INVALID"),
  ]);
  let contract; let contractSchema; let receiptSchema;
  try { contract = JSON.parse(contractText); } catch { failure("OWNER_CONTRACT_INVALID"); }
  try { contractSchema = JSON.parse(contractSchemaText); } catch { failure("CONTRACT_SCHEMA_INVALID"); }
  try { receiptSchema = JSON.parse(receiptSchemaText); } catch { failure("RECEIPT_SCHEMA_INVALID"); }
  if (validateCleanCheckoutReproducibilityOwnerContractSchema(contractSchema).length) failure("CONTRACT_SCHEMA_INVALID");
  if (validateCleanCheckoutReproducibilityOwnerReceiptSchema(receiptSchema).length) failure("RECEIPT_SCHEMA_INVALID");
  const liteContractSchema = structuredClone(contractSchema);
  delete liteContractSchema.properties.variants.items.properties.phases.items.properties.timeoutSeconds.maximum;
  if (!validateSchema(liteContractSchema, contract).ok || validateOwnerContract(contract).length) failure("OWNER_CONTRACT_INVALID");
  if (contract.repository !== repository) failure("OWNER_CONTRACT_IDENTITY_MISMATCH");
  if (contract.variants.some((variant) => variant.runnerImage !== runnerImage)) failure("OWNER_RUNNER_IDENTITY_MISMATCH");

  const preparedVariants = [];
  for (const variant of contract.variants) {
    const preparedPhases = [];
    for (const phaseName of PHASES) {
      const phase = variant.phases.find(({ phase: candidate }) => candidate === phaseName);
      preparedPhases.push({
        contract: phase,
        entrypoint: await snapshotEntrypoint(ownerRoot, phase.entrypoint),
        workingDirectory: await snapshotWorkingDirectory(ownerRoot, phase.workingDirectory),
      });
    }
    preparedVariants.push({ contract: variant, phases: preparedPhases });
  }
  return { contract, contractText, receiptSchema, preparedVariants };
}

export async function produceOwnerReceipt({
  ownerRoot: ownerRootInput,
  contractPath,
  contractSchemaPath,
  receiptSchemaPath,
  repository,
  sourceSha,
  runnerImage,
  outputPath,
  environment = process.env,
  now = () => new Date(),
  executePhase = executeOwnerPhase,
}) {
  await assertOutputAbsent(outputPath);
  const ownerRoot = await resolveOwnerRoot(ownerRootInput);
  const resolvedOutput = path.resolve(outputPath);
  if (resolvedOutput === ownerRoot || resolvedOutput.startsWith(`${ownerRoot}${path.sep}`)) failure("OUTPUT_INVALID");
  const cleanCheckout = await collectCleanCheckout(ownerRoot, repository, sourceSha);
  const { contract, contractText, receiptSchema, preparedVariants } = await prepareContract({ ownerRoot, contractPath, contractSchemaPath, receiptSchemaPath, repository, runnerImage });
  for (const { phases: preparedPhases } of preparedVariants) {
    for (const { contract: phase } of preparedPhases) {
      if (phase.requiredEnvironment.some((name) => !Object.hasOwn(environment, name))) failure("REQUIRED_ENVIRONMENT_MISSING");
    }
  }

  const variants = [];
  let previousCompletedAt = null;
  for (const { contract: variant, phases: preparedPhases } of preparedVariants) {
    const phaseResults = [];
    for (const prepared of preparedPhases) {
      const currentEntrypoint = await snapshotEntrypoint(ownerRoot, prepared.contract.entrypoint);
      if (currentEntrypoint.path !== prepared.entrypoint.path
        || currentEntrypoint.mode !== prepared.entrypoint.mode
        || currentEntrypoint.sha256 !== prepared.entrypoint.sha256) failure("ENTRYPOINT_CHANGED");
      const currentWorkingDirectory = await snapshotWorkingDirectory(ownerRoot, prepared.contract.workingDirectory);
      if (currentWorkingDirectory.path !== prepared.workingDirectory.path
        || currentWorkingDirectory.device !== prepared.workingDirectory.device
        || currentWorkingDirectory.inode !== prepared.workingDirectory.inode) failure("WORKING_DIRECTORY_INVALID");
      const result = await executePhase({
        entrypoint: currentEntrypoint.path,
        arguments_: prepared.contract.arguments,
        workingDirectory: currentWorkingDirectory.path,
        timeoutSeconds: prepared.contract.timeoutSeconds,
        environment,
        now,
      });
      if (Date.parse(result.startedAt) > Date.parse(result.completedAt)
        || previousCompletedAt != null && Date.parse(result.startedAt) < Date.parse(previousCompletedAt)) failure("CLOCK_INVALID");
      previousCompletedAt = result.completedAt;
      if (result.timedOut) failure("PHASE_TIMEOUT");
      if (result.unexpectedProcessCount !== 0) failure("PHASE_PROCESS_LEAK");
      if (result.exitCode !== prepared.contract.expectedExitCode) failure("PHASE_NONZERO");
      phaseResults.push({
        phase: prepared.contract.phase,
        commandSha256: commandSha256(prepared.contract),
        startedAt: result.startedAt,
        completedAt: result.completedAt,
        exitCode: result.exitCode,
        timedOut: result.timedOut,
        unexpectedProcessCount: result.unexpectedProcessCount,
      });
    }
    variants.push({
      variantId: variant.variantId,
      runnerImage: variant.runnerImage,
      toolchainDigest: variant.toolchainDigest,
      phases: phaseResults,
    });
  }
  const observedAt = timestamp(now);
  if (previousCompletedAt != null && Date.parse(observedAt) < Date.parse(previousCompletedAt)) failure("CLOCK_INVALID");
  const receipt = {
    schemaVersion: 1,
    repository,
    sourceSha,
    contractSha256: createHash("sha256").update(contractText).digest("hex"),
    observedAt,
    cleanCheckout,
    variants,
  };
  if (!validateSchema(receiptSchema, receipt).ok || validateOwnerReceipt(receipt).length) failure("OWNER_RECEIPT_INVALID");

  let output;
  try {
    output = await open(outputPath, "wx");
  } catch (error) { failure(error?.code === "EEXIST" ? "OUTPUT_EXISTS" : "OUTPUT_INVALID"); }
  try {
    await output.writeFile(`${JSON.stringify(receipt, null, 2)}\n`);
    await output.sync();
  } catch {
    try { await output.close(); } catch { /* sanitized cleanup */ }
    try { await unlink(outputPath); } catch { /* task-owned partial output only */ }
    failure("OUTPUT_INVALID");
  }
  await output.close();
  return receipt;
}

export async function runOwnerReceiptCli({ argv = process.argv.slice(2), env = process.env, now = () => new Date() } = {}) {
  try {
    const parsed = parseArguments(argv);
    const receipt = await produceOwnerReceipt({ ...parsed, environment: env, now });
    return { exitCode: 0, errorCode: null, outputWritten: true, receipt };
  } catch (error) {
    const errorCode = error instanceof OwnerReceiptFailure && CODE.test(error.code) ? error.code : "PRODUCER_FAILURE";
    return { exitCode: 2, errorCode, outputWritten: false, receipt: null };
  }
}

if (isMainModule(import.meta.url)) {
  const result = await runOwnerReceiptCli();
  if (result.exitCode !== 0) process.stderr.write(`D13_OWNER_RECEIPT_${result.errorCode}\n`);
  process.exitCode = result.exitCode;
}
