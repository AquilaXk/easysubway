import { spawn } from "node:child_process";
import { open, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { DETECTORS, REPOSITORIES, collectArtifactCatalog, scanArtifactArchive, validateReceipt } from "./audit-public-sensitivity.mjs";

const OUTPUT_LIMIT = 2 * 1024 * 1024;
const BINARY_OUTPUT_LIMIT = 16 * 1024 * 1024;
const POLICY = "public-sensitivity-v1";

export async function produceOwnerReceipt({ repository, gitSha, observedAt, evidenceLocator, evidence, expectedEvidenceDigest, evidenceArtifact, execGh = githubGet }) {
  if (!REPOSITORIES.includes(repository) || !/^[0-9a-f]{40}$/.test(gitSha) || !canonicalUtc(observedAt)) throw new Error("INVALID_INPUT");
  const transport = normalizeArtifact(evidenceArtifact);
  if (transport == null || !/^[0-9a-f]{64}$/.test(expectedEvidenceDigest ?? "") || transport.digest !== `sha256:${expectedEvidenceDigest}` || locator(repository, transport) !== evidenceLocator || transport.expired || instant(transport.createdAt) <= instant(observedAt)) throw new Error("EVIDENCE_TRANSPORT_INVALID");
  const receipt = { ...evidence, evidenceLocator };
  if (!validEvidenceShape(evidence) || validateReceipt(receipt, { repository, gitSha, observedAt, detectorPolicyVersion: POLICY }).length) throw new Error("EVIDENCE_SNAPSHOT_INVALID");
  const catalog = await collectArtifactCatalog({ repository, execGh });
  if (catalog.incomplete.length || !catalog.catalog.some((artifact) => sameArtifact(artifact, transport))) throw new Error("EVIDENCE_TRANSPORT_INVALID");
  return { evidence, receipt };
}

export async function produceOwnerEvidence({ repository, gitSha, observedAt, execGh = githubGet, execAlerts = alertGet }) {
  if (!REPOSITORIES.includes(repository) || !/^[0-9a-f]{40}$/.test(gitSha) || !canonicalUtc(observedAt)) throw new Error("INVALID_INPUT");
  const [security, refs, alertResult] = await Promise.all([
    securitySettings({ repository, execAlerts }),
    reachableRefs({ repository, gitSha, execGh }),
    enumerateAlerts({ repository, execAlerts }),
  ]).catch(() => { throw new Error("ALERT_CAPABILITY_UNAVAILABLE"); });
  const begin = await collectArtifactCatalog({ repository, execGh });
  if (begin.incomplete.length) throw new Error("PUBLIC_ARTIFACT_INCOMPLETE");
  const publicArtifacts = await scanEligibleArtifacts({ repository, observedAt, catalog: begin.catalog, execGh });
  const end = await collectArtifactCatalog({ repository, execGh });
  if (end.incomplete.length || begin.watermark !== end.watermark) throw new Error("PUBLIC_ARTIFACT_INCOMPLETE");
  return {
      schemaVersion: 1, repository, gitSha, observedAt, detectorPolicyVersion: POLICY,
      secretScanningEnabled: security.secretScanningEnabled, pushProtectionEnabled: security.pushProtectionEnabled,
      reachableRefAuditComplete: refs, alertEnumerationComplete: alertResult.complete,
      locationEnumerationComplete: alertResult.complete, openAlertCount: alertResult.openAlertCount,
      unresolvedAlertCount: alertResult.unresolvedAlertCount, publicArtifactEnumerationComplete: true,
      publicArtifacts,
  };
}

async function securitySettings({ repository, execAlerts }) {
  const settings = await execAlerts({ method: "GET", endpoint: `repos/${repository}` });
  if (settings?.security_and_analysis?.secret_scanning?.status !== "enabled" || settings?.security_and_analysis?.secret_scanning_push_protection?.status !== "enabled") throw new Error("ALERT_CAPABILITY_UNAVAILABLE");
  return { secretScanningEnabled: true, pushProtectionEnabled: true };
}

async function reachableRefs({ repository, gitSha, execGh }) {
  const ref = await execGh({ method: "GET", endpoint: `repos/${repository}/git/ref/heads/main` });
  if (ref?.ref !== "refs/heads/main" || ref?.object?.sha !== gitSha) throw new Error("REACHABLE_REF_AUDIT_INCOMPLETE");
  return true;
}

async function enumerateAlerts({ repository, execAlerts }) {
  const alerts = await pages({ repository, endpoint: `repos/${repository}/secret-scanning/alerts?state=open&per_page=100&page=`, exec: execAlerts, identity: (entry) => entry?.number });
  for (const alert of alerts) {
    if (!Number.isSafeInteger(alert?.number) || alert.number < 1) throw new Error("ALERT_CAPABILITY_UNAVAILABLE");
    await pages({ repository, endpoint: `repos/${repository}/secret-scanning/alerts/${alert.number}/locations?per_page=100&page=`, exec: execAlerts, identity: locationIdentity });
  }
  return { complete: true, openAlertCount: alerts.length, unresolvedAlertCount: alerts.length };
}

async function pages({ repository, endpoint, exec, identity }) {
  const result = []; const ids = new Set();
  for (let page = 1; page <= 1000; page += 1) {
    const body = await exec({ method: "GET", endpoint: `${endpoint}${page}` });
    if (!Array.isArray(body) || body.length > 100) throw new Error("PAGINATION_INCOMPLETE");
    for (const entry of body) {
      const itemIdentity = identity(entry);
      if ((typeof itemIdentity !== "number" && typeof itemIdentity !== "string") || itemIdentity === "" || ids.has(itemIdentity)) throw new Error("PAGINATION_INCOMPLETE");
      ids.add(itemIdentity); result.push(entry);
    }
    if (body.length < 100) return result;
  }
  throw new Error(`PAGINATION_INCOMPLETE:${repository}`);
}
function locationIdentity(entry) { return entry != null && typeof entry === "object" && !Array.isArray(entry) ? JSON.stringify(entry) : ""; }

async function scanEligibleArtifacts({ repository, observedAt, catalog, execGh }) {
  const eligible = catalog.filter((artifact) => !artifact.expired && instant(artifact.createdAt) <= instant(observedAt));
  const output = [];
  for (const artifact of eligible) {
    const run = await execGh({ method: "GET", endpoint: `repos/${repository}/actions/runs/${artifact.workflow_run.id}` });
    if (!safeWorkflow(run?.path)) throw new Error("PUBLIC_ARTIFACT_INCOMPLETE");
    const bytes = await execGh({ method: "GET", endpoint: `repos/${repository}/actions/artifacts/${artifact.id}/zip`, binary: true });
    const scanned = scanArtifactArchive({ repository, artifactId: String(artifact.id), bytes, scope: { detectors: DETECTORS } });
    if (scanned.incomplete.length) throw new Error("PUBLIC_ARTIFACT_INCOMPLETE");
    output.push({ artifactId: String(artifact.id), artifactName: artifact.name, workflowPath: run.path, runId: String(artifact.workflow_run.id), archiveDigest: artifact.digest, createdAt: artifact.createdAt, expiresAt: artifact.expiresAt, detectorPolicyVersion: POLICY, scanStatus: "COMPLETE", scanReceiptLocator: locator(repository, artifact) });
  }
  return output.sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right), "en"));
}

export async function runOwnerReceiptCli(args = process.argv.slice(2)) {
  try {
    const parsed = parseArgs(args);
    const result = parsed.mode === "evidence"
      ? await produceOwnerEvidence(parsed)
      : (await produceOwnerReceipt({ ...parsed, evidence: JSON.parse(await readFile(parsed.evidenceInput, "utf8")), evidenceArtifact: JSON.parse(await readFile(parsed.evidenceArtifact, "utf8")) })).receipt;
    const file = await open(parsed.output, "wx");
    try { await file.writeFile(`${JSON.stringify(result, null, 2)}\n`); } finally { await file.close(); }
    return 0;
  } catch { process.stderr.write("OWNER_RECEIPT_INCOMPLETE\n"); return 2; }
}

function parseArgs(args) {
  if (args.length === 8 && args[0] === "--repository" && args[2] === "--git-sha" && args[4] === "--observed-at" && args[6] === "--evidence-output") return { mode: "evidence", repository: args[1], gitSha: args[3], observedAt: args[5], output: args[7] };
  if (args.length !== 16 || args[0] !== "--repository" || args[2] !== "--git-sha" || args[4] !== "--observed-at" || args[6] !== "--evidence-locator" || args[8] !== "--evidence-digest" || args[10] !== "--evidence-input" || args[12] !== "--evidence-artifact" || args[14] !== "--output") throw new Error("INVALID_INPUT");
  return { repository: args[1], gitSha: args[3], observedAt: args[5], evidenceLocator: args[7], expectedEvidenceDigest: args[9], evidenceInput: args[11], evidenceArtifact: args[13], output: args[15] };
}

function validEvidenceShape(evidence) {
  const keys = ["alertEnumerationComplete", "detectorPolicyVersion", "gitSha", "locationEnumerationComplete", "observedAt", "openAlertCount", "publicArtifactEnumerationComplete", "publicArtifacts", "pushProtectionEnabled", "reachableRefAuditComplete", "repository", "schemaVersion", "secretScanningEnabled", "unresolvedAlertCount"];
  return evidence != null && !Array.isArray(evidence) && JSON.stringify(Object.keys(evidence).sort()) === JSON.stringify(keys);
}

function normalizeArtifact(raw) {
  const createdAt = normalizeTimestamp(raw?.created_at); const expiresAt = normalizeTimestamp(raw?.expires_at);
  if (!Number.isSafeInteger(raw?.id) || raw.id < 0 || raw?.expired !== false || createdAt == null || expiresAt == null || instant(expiresAt) <= instant(createdAt) || !/^[A-Za-z0-9][A-Za-z0-9._ -]{0,127}$/.test(raw?.name ?? "") || !Number.isSafeInteger(raw?.workflow_run?.id) || raw.workflow_run.id < 0 || !/^sha256:[0-9a-f]{64}$/.test(raw?.digest ?? "")) return null;
  return { id: raw.id, expired: raw.expired, createdAt, expiresAt, name: raw.name, digest: raw.digest, workflow_run: { id: raw.workflow_run.id } };
}
function sameArtifact(left, right) { return left.id === right.id && left.createdAt === right.createdAt && left.expiresAt === right.expiresAt && left.name === right.name && left.digest === right.digest && left.workflow_run.id === right.workflow_run.id; }
function locator(repository, artifact) { return `https://github.com/${repository}/actions/runs/${artifact.workflow_run.id}/artifacts/${artifact.id}`; }
function safeWorkflow(value) { return /^\.github\/workflows\/[A-Za-z0-9._/-]+\.ya?ml$/.test(value ?? "") && !value.includes(".."); }
function canonicalUtc(value) { return /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value ?? "") && new Date(value).toISOString() === value; }
function normalizeTimestamp(value) { const parsed = Date.parse(value ?? ""); return Number.isFinite(parsed) && /(?:Z|[+-]\d\d:\d\d)$/.test(value ?? "") ? new Date(parsed).toISOString() : null; }
function instant(value) { const parsed = Date.parse(value); return Number.isFinite(parsed) ? parsed : NaN; }
function boundedGet({ token, method, endpoint, binary = false }) {
  if (method !== "GET" || !/^repos\/AquilaXk\/easysubway(?:-(?:backend|data|mobile|platform))?(?:\/|$)/.test(endpoint) || !safeToken(token)) return Promise.reject(new Error("provider unavailable"));
  return new Promise((resolve, reject) => {
    const child = spawn("gh", ["api", "--method", "GET", endpoint], { env: { ...process.env, GH_TOKEN: token }, stdio: ["ignore", "pipe", "ignore"] }); const chunks = []; let size = 0; const limit = binary ? BINARY_OUTPUT_LIMIT : OUTPUT_LIMIT; const timer = setTimeout(() => child.kill("SIGTERM"), 30_000);
    child.stdout.on("data", (chunk) => { chunks.push(chunk); size += chunk.length; if (size > limit) child.kill("SIGTERM"); });
    child.on("error", reject); child.on("close", (code) => { clearTimeout(timer); if (code !== 0 || size > limit) reject(new Error("provider unavailable")); else try { const output = Buffer.concat(chunks); resolve(binary ? output : JSON.parse(output.toString("utf8"))); } catch { reject(new Error("provider unavailable")); } });
  });
}
function safeToken(value) { return typeof value === "string" && value.length > 0 && value.length <= 4096 && !/[\0-\x1f\x7f]/.test(value); }
function githubGet(request) { return boundedGet({ token: process.env.GH_TOKEN, ...request }); }
function alertGet(request) { return boundedGet({ token: process.env.D20_SECRET_SCANNING_ALERTS_READ_TOKEN, ...request }); }
if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = await runOwnerReceiptCli();
