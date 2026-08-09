import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { lstat, open, readFile, realpath } from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateRawSync } from "node:zlib";

import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { REPOSITORIES, runAuditCli, validateReceipt, validateScope } from "./audit-public-sensitivity.mjs";

const OUTPUT_LIMIT = 2 * 1024 * 1024;
const BINARY_OUTPUT_LIMIT = 16 * 1024 * 1024;
const POLICY = "public-sensitivity-v1";
const RECEIPT_SCHEMA = JSON.parse(await readFile(new URL("../../contracts/documentation/public-sensitivity-owner-receipt.schema.json", import.meta.url), "utf8"));
const SCOPE_SCHEMA = JSON.parse(await readFile(new URL("../../contracts/documentation/public-sensitivity-audit-scope.schema.json", import.meta.url), "utf8"));

export function assembleOwnerReceipts({ observedAt, heads, handoffs }) {
  if (!canonicalUtc(observedAt) || !heads || !Array.isArray(handoffs) || handoffs.length !== REPOSITORIES.length) throw new Error("RECEIPT_SET_INCOMPLETE");
  const receipts = []; const repositories = new Set();
  for (const handoff of handoffs) {
    const repository = locatorRepository(handoff?.locator);
    if (repository == null || repositories.has(repository) || !Array.isArray(handoff.files) || handoff.files.length !== 1 || handoff.files[0]?.name !== "receipt.json" || typeof handoff.files[0]?.text !== "string") throw new Error("HANDOFF_INVALID");
    let receipt; try { receipt = JSON.parse(handoff.files[0].text); } catch { throw new Error("HANDOFF_INVALID"); }
    const expected = { repository, gitSha: heads[repository], observedAt, detectorPolicyVersion: POLICY };
    if (!/^[0-9a-f]{40}$/.test(expected.gitSha ?? "") || !validateSchema(RECEIPT_SCHEMA, receipt).ok || validateReceipt(receipt, expected).length) throw new Error("RECEIPT_IDENTITY_MISMATCH");
    repositories.add(repository); receipts.push(receipt);
  }
  if (repositories.size !== REPOSITORIES.length || REPOSITORIES.some((repository) => !repositories.has(repository))) throw new Error("RECEIPT_SET_INCOMPLETE");
  return receipts.sort((left, right) => codepointCompare(left.repository, right.repository));
}

export async function downloadOwnerHandoffs({ observedAt, inputs, execGh = publicAuditGet }) {
  if (!canonicalUtc(observedAt) || !Array.isArray(inputs) || inputs.length !== REPOSITORIES.length) throw new Error("RECEIPT_SET_INCOMPLETE");
  const handoffs = [];
  for (const input of inputs) {
    const parsed = parseLocator(input?.locator);
    if (parsed == null || parsed.repository !== input?.repository || !/^[0-9a-f]{40}$/.test(input?.gitSha ?? "")) throw new Error("HANDOFF_INVALID");
    const artifact = normalizeArtifact(await execGh({ method: "GET", endpoint: `repos/${parsed.repository}/actions/artifacts/${parsed.artifactId}` }));
    if (artifact == null || artifact.id !== parsed.artifactId || artifact.workflowRunId !== parsed.runId || artifact.expired || instant(artifact.createdAt) <= instant(observedAt) || artifact.name !== handoffName(parsed.repository, input.gitSha)) throw new Error("HANDOFF_INVALID");
    const bytes = await execGh({ method: "GET", endpoint: `repos/${parsed.repository}/actions/artifacts/${parsed.artifactId}/zip`, binary: true });
    if (!Buffer.isBuffer(bytes) || `sha256:${digest(bytes)}` !== artifact.digest) throw new Error("HANDOFF_INVALID");
    handoffs.push({ locator: input.locator, files: [readSingleZipJson(bytes, "receipt.json")] });
  }
  return handoffs;
}

export async function verifyOwnerEvidence({ receipts, observedAt, execGh = publicAuditGet }) {
  for (const receipt of receipts) {
    const parsed = parseLocator(receipt.evidenceLocator);
    if (parsed == null || parsed.repository !== receipt.repository) throw new Error("EVIDENCE_INVALID");
    const artifact = normalizeArtifact(await execGh({ method: "GET", endpoint: `repos/${parsed.repository}/actions/artifacts/${parsed.artifactId}` }));
    if (artifact == null || artifact.id !== parsed.artifactId || artifact.workflowRunId !== parsed.runId || artifact.expired || instant(artifact.createdAt) <= instant(observedAt) || artifact.name !== evidenceName(receipt.repository, receipt.gitSha)) throw new Error("EVIDENCE_INVALID");
    const bytes = await execGh({ method: "GET", endpoint: `repos/${parsed.repository}/actions/artifacts/${parsed.artifactId}/zip`, binary: true });
    if (!Buffer.isBuffer(bytes) || `sha256:${digest(bytes)}` !== artifact.digest) throw new Error("EVIDENCE_INVALID");
    const evidence = JSON.parse(readSingleZipJson(bytes, "evidence.json").text);
    const receiptCore = Object.fromEntries(Object.entries(receipt).filter(([key]) => key !== "evidenceLocator"));
    if (stableJson(evidence) !== stableJson(receiptCore)) throw new Error("EVIDENCE_INVALID");
  }
}

export async function runFanInCli(args = process.argv.slice(2), { execGh = publicAuditGet, auditCli = runAuditCli } = {}) {
  let parsed; let root; let resolvedReceipts;
  try {
    parsed = parseArgs(args);
    if (!canonicalUtc(parsed.observedAt)) throw new Error("INVALID_OBSERVED_AT");
    root = await realpath(parsed.root);
    await containedInput(root, parsed.scope);
    const manifestPath = await containedInput(root, parsed.ownerReceipts);
    const outputPath = await containedOutput(root, parsed.output);
    resolvedReceipts = relative(root, resolve(dirname(outputPath), "resolved-owner-receipts.json"));
    const scope = JSON.parse(await readFile(await containedInput(root, parsed.scope), "utf8"));
    if (!validateSchema(SCOPE_SCHEMA, scope).ok || validateScope(scope).length) throw new Error("INVALID_SCOPE");
    const inputs = JSON.parse(await readFile(manifestPath, "utf8"));
    if (!validInputs(inputs)) throw new Error("RECEIPT_SET_INCOMPLETE");
    const hub = inputs.find(({ repository }) => repository === "AquilaXk/easysubway");
    if (hub?.gitSha !== parsed.runnerSha) throw new Error("STALE_RUNNER_HEAD");
    const handoffs = await downloadOwnerHandoffs({ observedAt: parsed.observedAt, inputs, execGh });
    const heads = Object.fromEntries(inputs.map(({ repository, gitSha }) => [repository, gitSha]));
    const receipts = assembleOwnerReceipts({ observedAt: parsed.observedAt, heads, handoffs });
    await verifyOwnerEvidence({ receipts, observedAt: parsed.observedAt, execGh });
    await writeOnce(resolve(root, resolvedReceipts), receipts);
  } catch {
    if (parsed == null) { process.stderr.write("AUDIT_INCOMPLETE\n"); return 2; }
    try {
      root ??= await realpath(parsed.root);
      const outputPath = await containedOutput(root, parsed.output);
      resolvedReceipts ??= relative(root, resolve(dirname(outputPath), "resolved-owner-receipts.json"));
      await writeOnce(resolve(root, resolvedReceipts), []);
    } catch { process.stderr.write("AUDIT_INCOMPLETE\n"); return 2; }
  }
  const auditObservedAt = canonicalUtc(parsed.observedAt) ? parsed.observedAt : "1970-01-01T00:00:00.000Z";
  return auditCli(["--scope", parsed.scope, "--owner-receipts", resolvedReceipts, "--observed-at", auditObservedAt, "--repository-root", root, "--output", parsed.output]);
}

function parseArgs(args) {
  if (args.length !== 12 || args[0] !== "--scope" || args[2] !== "--owner-receipts" || args[4] !== "--observed-at" || args[6] !== "--runner-sha" || args[8] !== "--repository-root" || args[10] !== "--output" || !/^[0-9a-f]{40}$/.test(args[7])) throw new Error("INVALID_INPUT");
  return { scope: args[1], ownerReceipts: args[3], observedAt: args[5], runnerSha: args[7], root: args[9], output: args[11] };
}

function parseLocator(value) { const match = /^https:\/\/github\.com\/(AquilaXk\/easysubway(?:-(?:backend|data|mobile|platform))?)\/actions\/runs\/(\d+)\/artifacts\/(\d+)$/.exec(value ?? ""); return match == null ? null : { repository: match[1], runId: Number(match[2]), artifactId: Number(match[3]) }; }
function locatorRepository(value) { return parseLocator(value)?.repository ?? null; }
function normalizeArtifact(raw) {
  const createdAt = normalizeTimestamp(raw?.created_at); const expiresAt = normalizeTimestamp(raw?.expires_at);
  if (!Number.isSafeInteger(raw?.id) || raw.id < 0 || raw?.expired !== false || createdAt == null || expiresAt == null || instant(expiresAt) <= instant(createdAt) || !Number.isSafeInteger(raw?.workflow_run?.id) || raw.workflow_run.id < 0 || !/^[A-Za-z0-9][A-Za-z0-9._ -]{0,127}$/.test(raw?.name ?? "") || !/^sha256:[0-9a-f]{64}$/.test(raw?.digest ?? "")) return null;
  return { id: raw.id, name: raw.name, digest: raw.digest, workflowRunId: raw.workflow_run.id, expired: raw.expired, createdAt, expiresAt };
}

function readSingleZipJson(bytes, expectedName) {
  try {
    if (!Buffer.isBuffer(bytes) || bytes.length < 22 || bytes.length > BINARY_OUTPUT_LIMIT) throw new Error();
    let eocd = -1;
    for (let offset = bytes.length - 22; offset >= Math.max(0, bytes.length - 65_557); offset -= 1) if (bytes.readUInt32LE(offset) === 0x06054b50) { eocd = offset; break; }
    if (eocd < 0 || eocd + 22 + bytes.readUInt16LE(eocd + 20) !== bytes.length || bytes.readUInt16LE(eocd + 4) !== 0 || bytes.readUInt16LE(eocd + 6) !== 0 || bytes.readUInt16LE(eocd + 8) !== 1 || bytes.readUInt16LE(eocd + 10) !== 1) throw new Error();
    const centralSize = bytes.readUInt32LE(eocd + 12); const centralOffset = bytes.readUInt32LE(eocd + 16);
    if (centralOffset + centralSize !== eocd || centralSize < 46 || bytes.readUInt32LE(centralOffset) !== 0x02014b50) throw new Error();
    const flags = bytes.readUInt16LE(centralOffset + 8); const method = bytes.readUInt16LE(centralOffset + 10); const crc = bytes.readUInt32LE(centralOffset + 16); const compressed = bytes.readUInt32LE(centralOffset + 20); const size = bytes.readUInt32LE(centralOffset + 24); const nameLength = bytes.readUInt16LE(centralOffset + 28); const extraLength = bytes.readUInt16LE(centralOffset + 30); const commentLength = bytes.readUInt16LE(centralOffset + 32); const external = bytes.readUInt32LE(centralOffset + 38); const localOffset = bytes.readUInt32LE(centralOffset + 42);
    const centralEnd = centralOffset + 46 + nameLength + extraLength + commentLength;
    if ((flags & ~0x0800) !== 0 || ![0, 8].includes(method) || compressed > BINARY_OUTPUT_LIMIT || size > OUTPUT_LIMIT || centralEnd !== eocd || Math.floor(external / 65_536) >> 12 === 0xa || localOffset + 30 > centralOffset || bytes.readUInt32LE(localOffset) !== 0x04034b50) throw new Error();
    const centralName = bytes.subarray(centralOffset + 46, centralOffset + 46 + nameLength); const name = new TextDecoder("utf-8", { fatal: true }).decode(centralName);
    const localNameLength = bytes.readUInt16LE(localOffset + 26); const localExtraLength = bytes.readUInt16LE(localOffset + 28); const localName = bytes.subarray(localOffset + 30, localOffset + 30 + localNameLength);
    if (name !== expectedName || !localName.equals(centralName) || bytes.readUInt16LE(localOffset + 6) !== flags || bytes.readUInt16LE(localOffset + 8) !== method || bytes.readUInt32LE(localOffset + 14) !== crc || bytes.readUInt32LE(localOffset + 18) !== compressed || bytes.readUInt32LE(localOffset + 22) !== size) throw new Error();
    const dataOffset = localOffset + 30 + localNameLength + localExtraLength; const data = bytes.subarray(dataOffset, dataOffset + compressed);
    if (data.length !== compressed || dataOffset + compressed !== centralOffset) throw new Error();
    const decoded = method === 0 ? data : inflateRawSync(data, { maxOutputLength: OUTPUT_LIMIT });
    if (decoded.length !== size || crc32(decoded) !== crc) throw new Error();
    return { name, text: new TextDecoder("utf-8", { fatal: true }).decode(decoded) };
  } catch { throw new Error("HANDOFF_INVALID"); }
}

function repositoryCode(repository) { return repository === "AquilaXk/easysubway" ? "hub" : repository.slice("AquilaXk/easysubway-".length); }
function handoffName(repository, gitSha) { return `d20-public-sensitivity-owner-receipt-${repositoryCode(repository)}-${gitSha}`; }
function evidenceName(repository, gitSha) { return `d20-public-sensitivity-evidence-${repositoryCode(repository)}-${gitSha}`; }
function stableJson(value) { if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`; if (value != null && typeof value === "object") return `{${Object.keys(value).sort(codepointCompare).map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`; return JSON.stringify(value); }
function validInputs(inputs) { return Array.isArray(inputs) && inputs.length === REPOSITORIES.length && JSON.stringify([...inputs].map(({ repository }) => repository).sort(codepointCompare)) === JSON.stringify([...REPOSITORIES].sort(codepointCompare)) && inputs.every((input) => JSON.stringify(Object.keys(input ?? {}).sort(codepointCompare)) === JSON.stringify(["gitSha", "locator", "repository"]) && /^[0-9a-f]{40}$/.test(input.gitSha) && parseLocator(input.locator)?.repository === input.repository); }
function canonicalUtc(value) { return /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value ?? "") && new Date(value).toISOString() === value; }
function normalizeTimestamp(value) { const parsed = Date.parse(value ?? ""); return Number.isFinite(parsed) && /(?:Z|[+-]\d\d:\d\d)$/.test(value ?? "") ? new Date(parsed).toISOString() : null; }
function instant(value) { const parsed = Date.parse(value); return Number.isFinite(parsed) ? parsed : NaN; }
function digest(bytes) { return createHash("sha256").update(bytes).digest("hex"); }
function crc32(bytes) { let crc = 0xffffffff; for (const byte of bytes) { crc ^= byte; for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); } return (crc ^ 0xffffffff) >>> 0; }
function codepointCompare(left, right) { return left < right ? -1 : left > right ? 1 : 0; }
function safeToken(value) { return typeof value === "string" && value.length > 0 && value.length <= 4096 && !/[\0-\x1f\x7f]/.test(value); }
function publicAuditGet(request) { return boundedGet({ token: process.env.D20_FIVE_REPO_PUBLIC_AUDIT_READ_TOKEN, ...request }); }
function boundedGet({ token, method, endpoint, binary = false }) {
  if (method !== "GET" || !safeToken(token) || !/^repos\/AquilaXk\/easysubway(?:-(?:backend|data|mobile|platform))?(?:\/|$)/.test(endpoint)) return Promise.reject(new Error("provider unavailable"));
  return new Promise((resolvePromise, reject) => {
    const child = spawn("gh", ["api", "--method", "GET", endpoint], { env: { ...process.env, GH_TOKEN: token }, stdio: ["ignore", "pipe", "ignore"] }); const chunks = []; let size = 0; const limit = binary ? BINARY_OUTPUT_LIMIT : OUTPUT_LIMIT; const timer = setTimeout(() => child.kill("SIGTERM"), 30_000);
    child.stdout.on("data", (chunk) => { chunks.push(chunk); size += chunk.length; if (size > limit) child.kill("SIGTERM"); });
    child.on("error", reject); child.on("close", (code) => { clearTimeout(timer); if (code !== 0 || size > limit) reject(new Error("provider unavailable")); else try { const output = Buffer.concat(chunks); resolvePromise(binary ? output : JSON.parse(output.toString("utf8"))); } catch { reject(new Error("provider unavailable")); } });
  });
}

function safePathToken(value) { return typeof value === "string" && value.length > 0 && !isAbsolute(value) && !value.split(/[\\/]/).includes(".."); }
async function containedInput(root, candidate) { if (!safePathToken(candidate)) throw new Error("unsafe path"); const path = resolve(root, candidate); if (relative(root, path).startsWith("..") || (await realpath(path)) !== path || (await lstat(path)).isSymbolicLink()) throw new Error("unsafe path"); return path; }
async function containedOutput(root, candidate) { if (!safePathToken(candidate)) throw new Error("unsafe path"); const path = resolve(root, candidate); if (relative(root, path).startsWith("..")) throw new Error("unsafe path"); const parent = await realpath(dirname(path)); if (parent !== dirname(path) || (parent !== root && !parent.startsWith(`${root}/`))) throw new Error("unsafe path"); let cursor = root; for (const part of relative(root, parent).split("/").filter(Boolean)) { cursor = resolve(cursor, part); if ((await lstat(cursor)).isSymbolicLink()) throw new Error("unsafe path"); } return path; }
async function writeOnce(path, value) { const file = await open(path, "wx"); try { await file.writeFile(`${JSON.stringify(value, null, 2)}\n`); } finally { await file.close(); } }

if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = await runFanInCli();
