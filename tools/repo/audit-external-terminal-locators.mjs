#!/usr/bin/env node
import { createHash } from "node:crypto";
import { open, readFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

const EXPECTED = [
  ["AquilaXk/easysubway", 2764, "PLAN-REPO"], ["AquilaXk/easysubway", 2767, "PLAN-REPO"], ["AquilaXk/easysubway-platform", 29, "PLAN-REPO"], ["AquilaXk/easysubway-platform", 30, "PLAN-REPO"], ["AquilaXk/easysubway-platform", 31, "PLAN-REPO"], ["AquilaXk/easysubway-mobile", 84, "PLAN-REPO"], ["AquilaXk/easysubway", 2765, "PLAN-JOURNEY"], ["AquilaXk/easysubway-data", 87, "PLAN-JOURNEY"],
];
const REPOSITORY = "AquilaXk/easysubway";
const APPROVED_REPOSITORIES = new Set(EXPECTED.map(([repository]) => repository));
const SHA = /^[0-9a-f]{40}$/;
const DIGEST = /^sha256:[0-9a-f]{64}$/;
const SAFE_PATH = /^(?!\/)(?!.*(?:^|\/)\.{1,2}(?:\/|$))(?!.*[?#])[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const SAFE_OCI_PATH = /^[a-z0-9][a-z0-9._-]*(?:\/[a-z0-9][a-z0-9._-]*)*$/;
const WORKFLOW_PATH = /^(?!\/)(?!.*(?:^|\/)\.{1,2}(?:\/|$))(?!.*[?#])\.github\/workflows\/[A-Za-z0-9][A-Za-z0-9._\/-]*\.ya?ml$/;
const OCI_ACCEPT = "application/vnd.oci.image.manifest.v1+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json";
const execFileAsync = promisify(execFile);

export class AuditIncomplete extends Error {
  constructor(code, identity, inputs = {}) { super(code); this.code = code; this.identity = identity; this.inputs = inputs; }
}

const key = (slot) => `${slot.ownerRepository}#${slot.ownerIssue}`;
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const compareFinding = (left, right) => codepointCompare(`${left.code}\0${left.identity}`, `${right.code}\0${right.identity}`);
const compareIncomplete = (left, right) => codepointCompare(`${left.stage}\0${left.code}\0${left.affectedIdentity}`, `${right.stage}\0${right.code}\0${right.affectedIdentity}`);
const exactKeys = (value, keys) => value != null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
const canonicalUtc = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
const canonicalProviderUtc = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === (value.includes(".") ? value : value.replace(/Z$/, ".000Z"));
const safePath = (value) => typeof value === "string" && SAFE_PATH.test(value);
const safeWorkflowPath = (value) => typeof value === "string" && WORKFLOW_PATH.test(value);
const fallbackScope = () => ({ schemaVersion: 1, slots: EXPECTED.map(([ownerRepository, ownerIssue, accountablePlan]) => ({ ownerRepository, ownerIssue, accountablePlan, state: "PENDING", terminalLocator: null })) });

function locatorErrors(slot, locator) {
  const errors = [];
  if (locator == null || typeof locator !== "object" || Array.isArray(locator)) return ["locator missing"];
  if (locator.kind === "GIT_BLOB") {
    if (!exactKeys(locator, ["kind", "repository", "commitSha", "path", "blobSha"]) || !APPROVED_REPOSITORIES.has(locator.repository) || !SHA.test(locator.commitSha) || !safePath(locator.path) || !SHA.test(locator.blobSha)) errors.push("Git locator mismatch");
  } else if (locator.kind === "OCI_DIGEST") {
    if (!exactKeys(locator, ["kind", "registry", "repositoryPath", "digest"]) || locator.registry !== "ghcr.io" || !SAFE_OCI_PATH.test(locator.repositoryPath) || !DIGEST.test(locator.digest)) errors.push("OCI locator mismatch");
  } else if (locator.kind === "ACTIONS_ARTIFACT") {
    if (!exactKeys(locator, ["kind", "repository", "runId", "artifactId", "artifactName", "archiveDigest", "workflowPath", "headSha", "createdAt", "expiresAt"])
      || !APPROVED_REPOSITORIES.has(locator.repository) || !Number.isInteger(locator.runId) || locator.runId < 1 || !Number.isInteger(locator.artifactId) || locator.artifactId < 1 || typeof locator.artifactName !== "string" || locator.artifactName.length === 0 || !DIGEST.test(locator.archiveDigest) || !safeWorkflowPath(locator.workflowPath) || !SHA.test(locator.headSha) || !canonicalProviderUtc(locator.createdAt) || !canonicalProviderUtc(locator.expiresAt) || Date.parse(locator.createdAt) >= Date.parse(locator.expiresAt)) errors.push("Actions locator mismatch");
  } else errors.push("locator kind mismatch");
  return errors;
}

export function validateExternalTerminalLocatorScope(scope, errors = []) {
  if (scope?.schemaVersion !== 1 || !Array.isArray(scope?.slots) || scope.slots.length !== EXPECTED.length) return [...errors, "slot inventory count mismatch"];
  const identities = scope.slots.map(key);
  if (new Set(identities).size !== EXPECTED.length) errors.push("duplicate slot");
  const actual = new Map(scope.slots.map((slot) => [key(slot), slot]));
  for (const [ownerRepository, ownerIssue, accountablePlan] of EXPECTED) {
    const identity = `${ownerRepository}#${ownerIssue}`; const slot = actual.get(identity);
    if (slot?.accountablePlan !== accountablePlan || !exactKeys(slot, ["ownerRepository", "ownerIssue", "accountablePlan", "state", "terminalLocator"])) { errors.push(`slot mapping mismatch:${identity}`); continue; }
    if (slot.state === "PENDING" && slot.terminalLocator !== null) errors.push(`state locator mismatch:${identity}`);
    if (slot.state === "READY" && locatorErrors(slot, slot.terminalLocator).length !== 0) errors.push(`locator mismatch:${identity}`);
    if (slot.state !== "PENDING" && slot.state !== "READY") errors.push(`state mismatch:${identity}`);
  }
  return errors;
}

function assertCompleteIdentities(items, expected, itemKey, code, identity) {
  const values = items.map(itemKey);
  const expectedSet = new Set(expected);
  if (values.length !== expected.length || new Set(values).size !== values.length || values.some((value) => !expectedSet.has(value)) || expected.some((value) => !values.includes(value))) throw new AuditIncomplete(code, identity);
}

export function auditExternalTerminalLocators({ scope, sourceSha, observedAt, issues = [], providerResults = [], stateBeginSha256 = null, stateEndSha256 = null, scopeText = JSON.stringify(scope) }) {
  const identities = scope.slots.map(key);
  assertCompleteIdentities(issues, identities, (issue) => `${issue?.repository}#${issue?.number}`, "ISSUE_RESULT_IDENTITY", "issues");
  const readyIdentities = scope.slots.filter(({ state }) => state === "READY").map(key);
  assertCompleteIdentities(providerResults, readyIdentities, (result) => result?.identity, "PROVIDER_RESULT_IDENTITY", "providers");
  const byIssue = new Map(issues.map((issue) => [`${issue.repository}#${issue.number}`, issue]));
  const byProvider = new Map(providerResults.map((result) => [result.identity, result]));
  const findings = [];
  for (const slot of scope.slots) {
    const identity = key(slot); const issue = byIssue.get(identity);
    if (!["OPEN", "CLOSED"].includes(issue.state)) throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    if (slot.state === "READY") {
      if (issue.state !== "CLOSED") findings.push({ code: "OWNER_ISSUE_NOT_TERMINAL", identity });
      const result = byProvider.get(identity);
      if (result?.ok !== true) findings.push({ code: validCode(result?.code) ? result.code : "LOCATOR_NOT_VERIFIED", identity });
    }
  }
  const slots = scope.slots.map((slot) => ({ ...slot, issueState: byIssue.get(key(slot)).state }));
  const pending = slots.filter(({ state }) => state === "PENDING").length;
  return { schemaVersion: 1, status: "COMPLETE", observedAt, inputs: { sourceSha, scopeSha256: sha256(scopeText), stateBeginSha256, stateEndSha256 }, summary: { pending, ready: slots.length - pending, findings: findings.length, incomplete: 0 }, slots, findings: findings.sort(compareFinding), incomplete: [] };
}

function providerFailure(error, identity, prefix = "PROVIDER") {
  if (error instanceof AuditIncomplete) throw error;
  const source = String(error?.code ?? error?.name ?? "UNAVAILABLE").toUpperCase().replace(/[^A-Z0-9_]/g, "_");
  throw new AuditIncomplete(validCode(`${prefix}_${source}`) ? `${prefix}_${source}` : `${prefix}_UNAVAILABLE`, identity);
}

function parseProviderJson(text, identity) {
  try { return JSON.parse(text); } catch { throw new AuditIncomplete("PROVIDER_MALFORMED", identity); }
}

export async function collectLiveIssues(scope, runGh = gh) {
  const issues = [];
  for (const slot of scope.slots) {
    const identity = key(slot); let issue;
    try { issue = parseProviderJson(await runGh(["api", "-H", "Authorization:", `repos/${slot.ownerRepository}/issues/${slot.ownerIssue}`]), identity); } catch (error) { providerFailure(error, identity); }
    if (issue?.number !== slot.ownerIssue || issue?.repository_url !== `https://api.github.com/repos/${slot.ownerRepository}` || !["open", "closed"].includes(issue?.state)) throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    issues.push({ repository: slot.ownerRepository, number: slot.ownerIssue, state: issue.state.toUpperCase() });
  }
  return issues;
}

export async function verifyReadyLocator({ slot, ghGet, fetchImpl = fetch, downloadArtifact, now = new Date().toISOString() }) {
  const locator = slot.terminalLocator; const identity = key(slot);
  if (locator?.kind === "GIT_BLOB") {
    let blob; try { blob = await ghGet(`repos/${locator.repository}/contents/${locator.path}?ref=${locator.commitSha}`); } catch (error) { if (error?.status === 404) return { identity, ok: false, code: "GIT_BLOB_MISMATCH" }; providerFailure(error, identity, "GIT_BLOB"); }
    if (typeof blob?.sha !== "string" || !SHA.test(blob.sha)) throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    return blob.sha === locator.blobSha ? { identity, ok: true } : { identity, ok: false, code: "GIT_BLOB_MISMATCH" };
  }
  if (locator?.kind === "OCI_DIGEST") {
    const manifestUrl = `https://ghcr.io/v2/${locator.repositoryPath}/manifests/${locator.digest}`;
    const request = (authorization = null) => fetchImpl(manifestUrl, { method: "HEAD", headers: authorization == null ? { Accept: OCI_ACCEPT } : { Accept: OCI_ACCEPT, Authorization: authorization }, redirect: "error", signal: AbortSignal.timeout(30_000) });
    let response; try { response = await request(); } catch (error) { providerFailure(error, identity, "OCI"); }
    if (!Number.isInteger(response?.status) || typeof response.headers?.get !== "function") throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    if (response.status === 401) {
      const challenge = response.headers.get("WWW-Authenticate");
      const expectedScope = `repository:${locator.repositoryPath}:pull`;
      const match = /^Bearer realm="([^"]+)",service="([^"]+)",scope="([^"]+)"$/.exec(challenge ?? "");
      if (match == null || match[1] !== "https://ghcr.io/token" || match[2] !== "ghcr.io" || match[3] !== expectedScope) throw new AuditIncomplete("OCI_AUTH_CHALLENGE_INVALID", identity);
      const tokenUrl = new URL(match[1]);
      if (tokenUrl.origin !== "https://ghcr.io" || tokenUrl.pathname !== "/token" || tokenUrl.search !== "") throw new AuditIncomplete("OCI_AUTH_CHALLENGE_INVALID", identity);
      tokenUrl.search = new URLSearchParams({ service: match[2], scope: match[3] }).toString();
      let tokenResponse; try { tokenResponse = await fetchImpl(tokenUrl.toString(), { method: "GET", redirect: "error", signal: AbortSignal.timeout(30_000) }); } catch (error) { providerFailure(error, identity, "OCI_AUTH"); }
      if (!Number.isInteger(tokenResponse?.status) || typeof tokenResponse?.json !== "function") throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
      if (tokenResponse.status !== 200) throw new AuditIncomplete(`OCI_AUTH_HTTP_${tokenResponse.status}`, identity);
      let token; try { token = await tokenResponse.json(); } catch { throw new AuditIncomplete("OCI_AUTH_MALFORMED", identity); }
      if (typeof token?.token !== "string" || token.token.length === 0) throw new AuditIncomplete("OCI_AUTH_MALFORMED", identity);
      try { response = await request(`Bearer ${token.token}`); } catch (error) { providerFailure(error, identity, "OCI"); }
      if (!Number.isInteger(response?.status) || typeof response.headers?.get !== "function") throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    }
    if (response.status === 404) return { identity, ok: false, code: "OCI_DIGEST_MISMATCH" };
    if (response.status !== 200) throw new AuditIncomplete(`OCI_HTTP_${response.status}`, identity);
    const contentDigest = response.headers.get("Docker-Content-Digest");
    if (typeof contentDigest !== "string" || !DIGEST.test(contentDigest)) throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    return contentDigest === locator.digest ? { identity, ok: true } : { identity, ok: false, code: "OCI_DIGEST_MISMATCH" };
  }
  if (locator?.kind === "ACTIONS_ARTIFACT") {
    let run; let artifact;
    try { [run, artifact] = await Promise.all([ghGet(`repos/${locator.repository}/actions/runs/${locator.runId}`), ghGet(`repos/${locator.repository}/actions/artifacts/${locator.artifactId}`)]); } catch (error) { providerFailure(error, identity, "ACTIONS"); }
    if (typeof run?.conclusion !== "string" || typeof run?.path !== "string" || typeof run?.head_sha !== "string" || !SHA.test(run.head_sha) || !Number.isInteger(artifact?.id) || typeof artifact?.name !== "string" || typeof artifact?.expired !== "boolean" || !canonicalProviderUtc(artifact?.created_at) || !canonicalProviderUtc(artifact?.expires_at) || typeof artifact?.digest !== "string" || !Number.isInteger(artifact?.workflow_run?.id) || typeof artifact?.workflow_run?.head_sha !== "string" || !SHA.test(artifact.workflow_run.head_sha)) throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    if (run.conclusion !== "success" || run.path !== locator.workflowPath || run.head_sha !== locator.headSha) return { identity, ok: false, code: "ACTIONS_RUN_MISMATCH" };
    if (artifact.id !== locator.artifactId || artifact.name !== locator.artifactName || artifact.expired !== false || new Date(artifact.created_at).toISOString() !== new Date(locator.createdAt).toISOString() || new Date(artifact.expires_at).toISOString() !== new Date(locator.expiresAt).toISOString() || artifact.digest !== locator.archiveDigest || artifact.workflow_run.id !== locator.runId || artifact.workflow_run.head_sha !== locator.headSha || Date.parse(locator.expiresAt) <= Date.parse(now)) return { identity, ok: false, code: "ACTIONS_ARTIFACT_MISMATCH" };
    let bytes; try { bytes = await downloadArtifact(locator.repository, locator.artifactId); } catch (error) { providerFailure(error, identity, "ACTIONS_ARCHIVE"); }
    if (!(bytes instanceof Uint8Array)) throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    return `sha256:${createHash("sha256").update(bytes).digest("hex")}` === locator.archiveDigest ? { identity, ok: true } : { identity, ok: false, code: "ACTIONS_ARCHIVE_DIGEST_MISMATCH" };
  }
  throw new AuditIncomplete("LOCATOR_INVALID", identity);
}

export async function collectSourceHead(runGh = gh) {
  let repository; let ref;
  try { repository = parseProviderJson(await runGh(["api", `repos/${REPOSITORY}`]), REPOSITORY); ref = parseProviderJson(await runGh(["api", `repos/${REPOSITORY}/git/ref/heads/main`]), REPOSITORY); } catch (error) { providerFailure(error, REPOSITORY); }
  if (repository?.default_branch !== "main" || !SHA.test(ref?.object?.sha)) throw new AuditIncomplete("PROVIDER_MALFORMED", REPOSITORY);
  return ref.object.sha;
}

export async function collectLiveSnapshot(scope, { runGh = gh, fetchImpl = fetch, downloadArtifact = ghArtifactDownload, now } = {}) {
  const issues = await collectLiveIssues(scope, runGh); const providerResults = [];
  for (const slot of scope.slots) if (slot.state === "READY") providerResults.push(await verifyReadyLocator({ slot, ghGet: async (endpoint) => parseProviderJson(await runGh(["api", endpoint]), key(slot)), fetchImpl, downloadArtifact, now }));
  return { issues, providerResults };
}

function normalizedSnapshot(scope, live) {
  const identities = scope.slots.map(key); const ready = scope.slots.filter(({ state }) => state === "READY").map(key);
  assertCompleteIdentities(live?.issues ?? [], identities, (issue) => `${issue?.repository}#${issue?.number}`, "ISSUE_RESULT_IDENTITY", "issues");
  assertCompleteIdentities(live?.providerResults ?? [], ready, (result) => result?.identity, "PROVIDER_RESULT_IDENTITY", "providers");
  const providers = new Map(live.providerResults.map((result) => [result.identity, { ok: result.ok === true, code: result.ok === true ? null : (validCode(result.code) ? result.code : "LOCATOR_NOT_VERIFIED") }]));
  return identities.sort(codepointCompare).map((identity) => {
    const issue = live.issues.find((candidate) => `${candidate.repository}#${candidate.number}` === identity);
    if (!["OPEN", "CLOSED"].includes(issue.state)) throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    return { identity, issueState: issue.state, provider: providers.get(identity) ?? null };
  });
}

export async function collectLive(scope, { sourceSha, runGh = gh, fetchImpl = fetch, downloadArtifact = ghArtifactDownload, now, getSourceHead = null, collectSnapshot = null } = {}) {
  const sourceHead = getSourceHead ?? (() => collectSourceHead(runGh));
  const snapshot = collectSnapshot ?? (() => collectLiveSnapshot(scope, { runGh, fetchImpl, downloadArtifact, now }));
  const beginHead = await sourceHead(); const begin = await snapshot(); const end = await snapshot(); const endHead = await sourceHead();
  const stateBeginSha256 = sha256(JSON.stringify(normalizedSnapshot(scope, begin)));
  const stateEndSha256 = sha256(JSON.stringify(normalizedSnapshot(scope, end)));
  if (beginHead !== sourceSha || endHead !== sourceSha || stateBeginSha256 !== stateEndSha256) throw new AuditIncomplete("STATE_WATERMARK_DRIFT", REPOSITORY, { stateBeginSha256, stateEndSha256 });
  return { ...begin, stateBeginSha256, stateEndSha256 };
}

export async function gh(args, execute = execFileAsync) {
  const anonymousIssueRead = args?.length === 4 && args[0] === "api" && args[1] === "-H" && args[2] === "Authorization:";
  const endpoint = anonymousIssueRead ? args[3] : args?.[1];
  const contentPath = "(?:[A-Za-z0-9][A-Za-z0-9._/-]*)";
  const repo = "AquilaXk/easysubway(?:-(?:platform|mobile|data))?";
  const allowed = new RegExp(`^repos/${repo}(?:$|/issues/[1-9]\\d*$|/contents/${contentPath}\\?ref=[0-9a-f]{40}$|/actions/runs/[1-9]\\d*$|/actions/artifacts/[1-9]\\d*$|/git/ref/heads/main$)`);
  const contentStart = typeof endpoint === "string" ? endpoint.indexOf("/contents/") : -1;
  if (contentStart >= 0) {
    const refStart = endpoint.indexOf("?ref=", contentStart);
    if (refStart < 0 || !safePath(endpoint.slice(contentStart + "/contents/".length, refStart))) throw new Error("gh read-only allowlist violation");
  }
  const publicIssue = new RegExp(`^repos/${repo}/issues/[1-9]\\d*$`);
  if (args?.[0] !== "api" || !allowed.test(endpoint) || (anonymousIssueRead && !publicIssue.test(endpoint)) || (!anonymousIssueRead && args?.length !== 2)) throw new Error("gh read-only allowlist violation");
  try { return (await execute("gh", args, { encoding: "utf8", timeout: 30_000, killSignal: "SIGTERM", maxBuffer: 1024 * 1024 })).stdout; } catch (error) {
    if (/(?:^|\D)HTTP 404(?:\D|$)/.test(String(error?.stderr ?? ""))) throw Object.assign(new Error("gh API returned HTTP 404"), { status: 404 });
    throw error;
  }
}

export async function ghArtifactDownload(repository, artifactId, execute = execFileAsync) {
  if (!APPROVED_REPOSITORIES.has(repository) || !Number.isInteger(artifactId) || artifactId < 1) throw new Error("gh artifact read-only allowlist violation");
  const { stdout } = await execute("gh", ["api", `repos/${repository}/actions/artifacts/${artifactId}/zip`], { encoding: null, timeout: 30_000, killSignal: "SIGTERM", maxBuffer: 256 * 1024 * 1024 });
  if (!Buffer.isBuffer(stdout) && !(stdout instanceof Uint8Array)) throw new AuditIncomplete("ACTIONS_ARCHIVE_UNAVAILABLE", `${repository}#${artifactId}`);
  return new Uint8Array(stdout);
}

export function parseArguments(argv) {
  const names = { "--scope": "scopePath", "--scope-schema": "scopeSchemaPath", "--report-schema": "reportSchemaPath", "--source-sha": "sourceSha", "--observed-at": "observedAt", "--output": "outputPath" }; const values = {};
  for (let index = 0; index < argv.length; index += 1) { const name = names[argv[index]]; const value = argv[++index]; if (name == null || value == null || value.startsWith("--") || values[name] != null) throw new Error("unsupported or duplicate argument"); values[name] = value; }
  if (Object.keys(values).length !== Object.keys(names).length || !SHA.test(values.sourceSha) || !canonicalUtc(values.observedAt)) throw new Error("invalid audit arguments"); return values;
}

function validCode(value) { return typeof value === "string" && /^[A-Z][A-Z0-9_]*$/.test(value); }
function sanitizeIncomplete(error, fallbackInputs = {}) { return { stage: error instanceof AuditIncomplete && error.code === "SCOPE_INVALID" ? "scope" : error instanceof AuditIncomplete && error.code === "REPORT_SCHEMA_INVALID" ? "schema" : "provider", code: validCode(error?.code) ? error.code : "AUDIT_FAILURE", affectedIdentity: String(error?.identity ?? "audit").replace(/[^A-Za-z0-9:._/-]/g, "_") || "audit", inputs: error instanceof AuditIncomplete ? error.inputs : fallbackInputs }; }
function createFallbackReport({ sourceSha, observedAt, scopeText, scope: validatedScope = null, error }) {
  const scope = validatedScope ?? fallbackScope(); const slots = scope.slots.map((slot) => ({ ...slot, issueState: "UNAVAILABLE" })); const incomplete = sanitizeIncomplete(error); const pending = slots.filter(({ state }) => state === "PENDING").length;
  return { schemaVersion: 1, status: "AUDIT_INCOMPLETE", observedAt, inputs: { sourceSha, scopeSha256: sha256(scopeText), stateBeginSha256: incomplete.inputs.stateBeginSha256 ?? null, stateEndSha256: incomplete.inputs.stateEndSha256 ?? null }, summary: { pending, ready: slots.length - pending, findings: 0, incomplete: 1 }, slots, findings: [], incomplete: [{ stage: incomplete.stage, code: incomplete.code, affectedIdentity: incomplete.affectedIdentity }] };
}

export function validateExternalTerminalLocatorReport(report, errors = []) {
  if (!exactKeys(report, ["schemaVersion", "status", "observedAt", "inputs", "summary", "slots", "findings", "incomplete"]) || report.schemaVersion !== 1 || !["COMPLETE", "AUDIT_INCOMPLETE"].includes(report.status) || !canonicalUtc(report.observedAt)) errors.push("report header mismatch");
  if (!exactKeys(report?.inputs, ["sourceSha", "scopeSha256", "stateBeginSha256", "stateEndSha256"]) || !SHA.test(report.inputs?.sourceSha) || !/^[0-9a-f]{64}$/.test(report.inputs?.scopeSha256) || ![report.inputs?.stateBeginSha256, report.inputs?.stateEndSha256].every((value) => value === null || /^[0-9a-f]{64}$/.test(value))) errors.push("report inputs mismatch");
  if (!exactKeys(report?.summary, ["pending", "ready", "findings", "incomplete"]) || !["pending", "ready", "findings", "incomplete"].every((field) => Number.isInteger(report.summary?.[field]) && report.summary[field] >= 0)) errors.push("report summary shape mismatch");
  const reportScope = { schemaVersion: 1, slots: Array.isArray(report?.slots) ? report.slots.map(({ issueState, ...slot }) => slot) : [] };
  errors.push(...validateExternalTerminalLocatorScope(reportScope));
  if (!Array.isArray(report?.slots) || report.slots.some((slot) => !exactKeys(slot, ["ownerRepository", "ownerIssue", "accountablePlan", "state", "terminalLocator", "issueState"]) || !["OPEN", "CLOSED", "UNAVAILABLE"].includes(slot.issueState))) errors.push("report issue state mismatch");
  if (!Array.isArray(report?.findings) || !Array.isArray(report?.incomplete)) errors.push("report result arrays mismatch");
  else {
    const findingKeys = report.findings.map((finding) => `${finding?.code}\0${finding?.identity}`); const incompleteKeys = report.incomplete.map((entry) => `${entry?.stage}\0${entry?.code}\0${entry?.affectedIdentity}`);
    if (new Set(findingKeys).size !== findingKeys.length || report.findings.some((finding) => !exactKeys(finding, ["code", "identity"]) || !validCode(finding.code) || !/^[A-Za-z0-9:._/-]+$/.test(finding.identity))) errors.push("report findings mismatch");
    if (new Set(incompleteKeys).size !== incompleteKeys.length || report.incomplete.some((entry) => !exactKeys(entry, ["stage", "code", "affectedIdentity"]) || !/^[a-z][a-z0-9-]*$/.test(entry.stage) || !validCode(entry.code) || !/^[A-Za-z0-9:._/-]+$/.test(entry.affectedIdentity))) errors.push("report incomplete mismatch");
  }
  const pending = Array.isArray(report?.slots) ? report.slots.filter(({ state }) => state === "PENDING").length : -1; const ready = Array.isArray(report?.slots) ? report.slots.length - pending : -1;
  if (report?.summary?.pending !== pending || report?.summary?.ready !== ready || report?.summary?.findings !== report?.findings?.length || report?.summary?.incomplete !== report?.incomplete?.length || (report?.status === "COMPLETE" && (report?.incomplete?.length !== 0 || !/^[0-9a-f]{64}$/.test(report.inputs?.stateBeginSha256) || report.inputs.stateBeginSha256 !== report.inputs.stateEndSha256)) || (report?.status === "AUDIT_INCOMPLETE" && report?.incomplete?.length < 1)) errors.push("report parity mismatch");
  return errors;
}

function reportSchemaIsStrict(schema) {
  const properties = schema?.properties;
  const locator = properties?.slots?.items?.properties?.terminalLocator;
  return schema?.type === "object" && schema?.additionalProperties === false && JSON.stringify(schema?.required) === JSON.stringify(["schemaVersion", "status", "observedAt", "inputs", "summary", "slots", "findings", "incomplete"])
    && properties?.inputs?.properties?.stateBeginSha256?.pattern === "^[0-9a-f]{64}$" && properties?.inputs?.properties?.stateEndSha256?.pattern === "^[0-9a-f]{64}$" && properties?.slots?.items?.properties?.issueState?.enum?.join(",") === "OPEN,CLOSED,UNAVAILABLE" && Array.isArray(locator?.oneOf) && locator.oneOf.length === 4 && locator.oneOf[1]?.properties?.path?.pattern === "^(?!/)(?!.*(?:^|/)\\.{1,2}(?:/|$))(?!.*[?#])[A-Za-z0-9][A-Za-z0-9._/-]*$" && locator.oneOf[2]?.properties?.repositoryPath?.pattern === "^[a-z0-9][a-z0-9._-]*(?:/[a-z0-9][a-z0-9._-]*)*$" && locator.oneOf[3]?.properties?.workflowPath?.pattern === "^(?!/)(?!.*(?:^|/)\\.{1,2}(?:/|$))(?!.*[?#])\\.github/workflows/[A-Za-z0-9][A-Za-z0-9._/-]*\\.ya?ml$" && properties?.findings?.uniqueItems === true && properties?.incomplete?.uniqueItems === true
    && locator.oneOf[3]?.properties?.createdAt?.pattern === "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{3})?Z$" && locator.oneOf[3]?.properties?.expiresAt?.pattern === "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{3})?Z$" && schema?.oneOf?.[0]?.properties?.inputs?.properties?.stateBeginSha256?.type === "string" && schema?.oneOf?.[0]?.properties?.inputs?.properties?.stateEndSha256?.type === "string";
}

export async function runAuditCli({ argv, collectIssues = collectLive, read = readFile, openFile = open } = {}) {
  let args; let scopeText = ""; let scope = null; let report = null; let exitCode = 2;
  try {
    args = parseArguments(argv);
    try { scopeText = await read(args.scopePath, "utf8"); } catch { throw new AuditIncomplete("SCOPE_INVALID", "scope"); }
    let parsedScope; try { parsedScope = JSON.parse(scopeText); } catch { throw new AuditIncomplete("SCOPE_INVALID", "scope"); }
    let scopeSchema; try { scopeSchema = JSON.parse(await read(args.scopeSchemaPath, "utf8")); } catch { throw new AuditIncomplete("SCOPE_INVALID", "scope"); }
    let reportSchema; try { reportSchema = JSON.parse(await read(args.reportSchemaPath, "utf8")); } catch { throw new AuditIncomplete("REPORT_SCHEMA_INVALID", "report"); }
    if (!validateSchema(scopeSchema, parsedScope).ok || validateExternalTerminalLocatorScope(parsedScope).length !== 0) throw new AuditIncomplete("SCOPE_INVALID", "scope");
    scope = parsedScope;
    if (!reportSchemaIsStrict(reportSchema)) throw new AuditIncomplete("REPORT_SCHEMA_INVALID", "report");
    const live = await collectIssues(scope, { sourceSha: args.sourceSha });
    report = auditExternalTerminalLocators({ scope, scopeText, sourceSha: args.sourceSha, observedAt: args.observedAt, ...live });
    if (!validateSchema(reportSchema, report).ok || validateExternalTerminalLocatorReport(report).length !== 0) throw new AuditIncomplete("REPORT_INVALID", "report");
    exitCode = report.summary.findings === 0 ? 0 : 1;
  } catch (error) {
    if (args != null) { report = createFallbackReport({ sourceSha: args.sourceSha, observedAt: args.observedAt, scopeText, scope, error }); if (validateExternalTerminalLocatorReport(report).length !== 0) return { exitCode: 2, report: null, outputWritten: false }; }
  }
  if (args == null || report == null) return { exitCode: 2, report: null, outputWritten: false };
  try { const handle = await openFile(args.outputPath, "wx"); try { await handle.writeFile(`${JSON.stringify(report)}\n`); } finally { await handle.close(); } } catch { return { exitCode: 2, report: null, outputWritten: false }; }
  return { exitCode, report, outputWritten: true };
}

if (isMainModule(import.meta.url)) process.exitCode = (await runAuditCli({ argv: process.argv.slice(2) })).exitCode;
