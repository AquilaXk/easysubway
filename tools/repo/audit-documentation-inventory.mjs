#!/usr/bin/env node
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { open, readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { validateDocumentationRecord, validateDocumentationRelations } from "../ci/documentation-inventory.mjs";

const EXPECTED_REPOSITORIES = [
  "AquilaXk/easysubway",
  "AquilaXk/easysubway-backend",
  "AquilaXk/easysubway-data",
  "AquilaXk/easysubway-mobile",
  "AquilaXk/easysubway-platform",
];
const EXPECTED_DODS = ["D01", "D02", "D03", "D04", "D05"];
const FRAGMENT_PATH = "contracts/documentation/documentation-fragment.json";
const SHA = /^[0-9a-f]{40}$/;
const DIGEST = /^[0-9a-f]{64}$/;
const execFileAsync = promisify(execFile);
const FRAGMENT_SCHEMA = JSON.parse(await readFile(new URL("../../contracts/documentation/documentation-fragment.schema.json", import.meta.url), "utf8"));
const RESOURCE_SCHEMA = JSON.parse(await readFile(new URL("../../contracts/documentation/documentation-resource.schema.json", import.meta.url), "utf8"));

export class AuditIncomplete extends Error {
  constructor(code, identity, stage = "provider") {
    super(code);
    this.code = code;
    this.identity = identity;
    this.stage = stage;
  }
}

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const canonicalUtc = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
const exactKeys = (value, keys) => value != null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
const safePath = (value) => typeof value === "string" && /^(?!\/)(?!.*(?:^|\/)\.{1,2}(?:\/|$))(?!.*[?#])[A-Za-z0-9][A-Za-z0-9._/-]*$/.test(value);
const fallbackScope = () => ({ schemaVersion: 1, repositories: EXPECTED_REPOSITORIES.map((repository) => ({ repository, defaultBranch: "main", fragmentPath: FRAGMENT_PATH, requiredStatus: "ACTIVE" })), dods: [...EXPECTED_DODS] });

export function validateDocumentationInventoryAuditScope(scope, errors = []) {
  if (scope?.schemaVersion !== 1 || !Array.isArray(scope.repositories) || !Array.isArray(scope.dods)) return [...errors, "scope shape mismatch"];
  const repositories = scope.repositories.map(({ repository }) => repository);
  if (JSON.stringify(repositories) !== JSON.stringify(EXPECTED_REPOSITORIES)) errors.push("repository inventory mismatch");
  if (JSON.stringify(scope.dods) !== JSON.stringify(EXPECTED_DODS)) errors.push("DoD inventory mismatch");
  for (const entry of scope.repositories) {
    if (!exactKeys(entry, ["repository", "defaultBranch", "fragmentPath", "requiredStatus"]) || entry.defaultBranch !== "main" || entry.fragmentPath !== FRAGMENT_PATH || !safePath(entry.fragmentPath) || entry.requiredStatus !== "ACTIVE") errors.push(`repository contract mismatch:${entry?.repository ?? "unknown"}`);
  }
  return errors;
}

function decodeBase64(value, identity) {
  if (typeof value !== "string") throw new AuditIncomplete("FRAGMENT_DECODE_INVALID", identity, "fragment");
  const normalized = value.replace(/\s/g, "");
  if (normalized.length === 0 || normalized.length % 4 !== 0 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(normalized)) throw new AuditIncomplete("FRAGMENT_DECODE_INVALID", identity, "fragment");
  const bytes = Buffer.from(normalized, "base64");
  if (bytes.toString("base64") !== normalized) throw new AuditIncomplete("FRAGMENT_DECODE_INVALID", identity, "fragment");
  return bytes;
}

function parseJson(bytes, identity) {
  try { return JSON.parse(bytes.toString("utf8")); } catch { throw new AuditIncomplete("FRAGMENT_JSON_INVALID", identity, "fragment"); }
}

function validateFragment(fragment, entry, headSha) {
  const errors = validateSchema(FRAGMENT_SCHEMA, fragment).errors;
  if (errors.length !== 0) throw new AuditIncomplete("FRAGMENT_SCHEMA_INVALID", entry.repository, "fragment");
  if (fragment.repository !== entry.repository || fragment.gitSha !== headSha) throw new AuditIncomplete("FRAGMENT_HEAD_MISMATCH", entry.repository, "fragment");
  if (fragment.status === "ACTIVE" && (fragment.verificationEvidence.length === 0 || !canonicalUtc(fragment.lastVerifiedAt))) throw new AuditIncomplete("FRAGMENT_SEMANTIC_INVALID", entry.repository, "fragment");
  const resourceIds = fragment.resources.map(({ resource }) => resource);
  if (resourceIds.some((resource) => typeof resource !== "string") || JSON.stringify(resourceIds) !== JSON.stringify([...new Set(resourceIds)].sort(codepointCompare))) throw new AuditIncomplete("FRAGMENT_SEMANTIC_INVALID", entry.repository, "fragment");
  for (const record of fragment.resources) {
    if (!validateSchema(RESOURCE_SCHEMA, record).ok) throw new AuditIncomplete("RESOURCE_SCHEMA_INVALID", entry.repository, "fragment");
    try { validateDocumentationRecord(record, { ownerRepository: entry.repository, gitSha: headSha, tracked: record.sourceSurface === "TRACKED" }); }
    catch { throw new AuditIncomplete("RESOURCE_SEMANTIC_INVALID", entry.repository, "fragment"); }
  }
}

function trackedIdentity(record) {
  return /^git:([0-9a-f]{40}):([^:]+):([0-9a-f]{40}|[0-9a-f]{64})$/.exec(record.canonicalIdentity);
}

export async function verifyFragment(entry, headSha, { readContent = collectContent } = {}) {
  let content;
  try { content = await readContent(entry.repository, entry.fragmentPath, headSha); }
  catch (error) {
    if (error?.status === 404) return { repository: entry.repository, headSha, state: "PENDING", fragmentStatus: "MISSING", fragmentBlobSha: null, fragment: null, resourceCount: 0, activeResourceCount: 0, verificationFindings: [] };
    throw error instanceof AuditIncomplete ? error : new AuditIncomplete("PROVIDER_UNAVAILABLE", entry.repository);
  }
  if (content?.type !== "file" || !SHA.test(content?.sha) || content?.encoding !== "base64") throw new AuditIncomplete("FRAGMENT_PROVIDER_MALFORMED", entry.repository, "fragment");
  const fragment = parseJson(decodeBase64(content.content, entry.repository), entry.repository);
  validateFragment(fragment, entry, headSha);
  if (fragment.status !== entry.requiredStatus) return { repository: entry.repository, headSha, state: "PENDING", fragmentStatus: fragment.status, fragmentBlobSha: content.sha, fragment: null, resourceCount: 0, activeResourceCount: 0, verificationFindings: [] };
  const verificationFindings = [];
  for (const record of fragment.resources.filter(({ sourceSurface }) => sourceSurface === "TRACKED")) {
    const identity = trackedIdentity(record);
    if (identity == null || identity[1] !== headSha) throw new AuditIncomplete("RESOURCE_IDENTITY_INVALID", record.resource, "fragment");
    let tracked;
    try { tracked = await readContent(entry.repository, identity[2], headSha); }
    catch (error) {
      if (error?.status === 404) { verificationFindings.push({ dod: "D01", code: "TRACKED_RESOURCE_MISSING", identity: record.resource }); continue; }
      throw error instanceof AuditIncomplete ? error : new AuditIncomplete("PROVIDER_UNAVAILABLE", record.resource);
    }
    if (tracked?.type !== "file" || !SHA.test(tracked?.sha) || tracked?.encoding !== "base64") throw new AuditIncomplete("RESOURCE_PROVIDER_MALFORMED", record.resource, "fragment");
    const bytes = decodeBase64(tracked.content, record.resource);
    const actual = identity[3].length === 40 ? tracked.sha : sha256(bytes);
    if (actual !== identity[3]) verificationFindings.push({ dod: "D01", code: "TRACKED_RESOURCE_BLOB_MISMATCH", identity: record.resource });
  }
  return { repository: entry.repository, headSha, state: "READY", fragmentStatus: "ACTIVE", fragmentBlobSha: content.sha, fragment, resourceCount: fragment.resources.length, activeResourceCount: fragment.resources.filter(({ status }) => status === "ACTIVE").length, verificationFindings };
}

function findingCompare(left, right) { return codepointCompare(`${left.dod}\0${left.code}\0${left.identity}`, `${right.dod}\0${right.code}\0${right.identity}`); }

function repositoryParity(scope, repositories) {
  const actual = repositories.map(({ repository }) => repository);
  if (JSON.stringify(actual) !== JSON.stringify(scope.repositories.map(({ repository }) => repository))) throw new AuditIncomplete("REPOSITORY_RESULT_IDENTITY", "repositories", "audit");
}

export function auditDocumentationInventory({ scope, sourceSha, observedAt, repositories, stateBeginSha256 = null, stateEndSha256 = null, scopeText = JSON.stringify(scope) }) {
  repositoryParity(scope, repositories);
  const findings = repositories.flatMap(({ verificationFindings = [] }) => verificationFindings);
  const readyEntries = repositories.filter(({ state }) => state === "READY");
  const pending = repositories.length - readyEntries.length;
  const records = readyEntries.flatMap(({ fragment }) => fragment?.resources ?? []);
  if (pending === 0) {
    for (const entry of readyEntries) if ((entry.fragment?.resources.length ?? 0) === 0) findings.push({ dod: "D01", code: "ACTIVE_CLASSIFICATION_EMPTY", identity: entry.repository });
    for (const record of records.filter(({ status, ownerIssue }) => status === "ACTIVE" && ownerIssue === null)) findings.push({ dod: "D02", code: "ACTIVE_OWNER_ISSUE_MISSING", identity: record.resource });
    const resourceIds = records.map(({ resource }) => resource);
    for (const resource of [...new Set(resourceIds.filter((value, index) => resourceIds.indexOf(value) !== index))].sort(codepointCompare)) findings.push({ dod: "D03", code: "RESOURCE_ID_DUPLICATE", identity: resource });
    const groups = new Map();
    for (const record of records.filter(({ status, duplicateGroup }) => status === "ACTIVE" && duplicateGroup !== null)) groups.set(record.duplicateGroup, [...(groups.get(record.duplicateGroup) ?? []), record]);
    for (const [identity, group] of groups) {
      if (group.length < 2 || group.filter(({ disposition }) => disposition === "RETAIN_CANONICAL").length !== 1) findings.push({ dod: "D03", code: "DUPLICATE_CANONICAL_COUNT", identity });
      else if (group.some((record) => record.currentConsumers.length === 0 || record.disposition !== "RETAIN_CANONICAL" && record.deletePrerequisite.length === 0)) findings.push({ dod: "D03", code: "DUPLICATE_HANDOFF_INCOMPLETE", identity });
    }
    if (!findings.some(({ dod }) => dod === "D03")) {
      try { validateDocumentationRelations(records); } catch { findings.push({ dod: "D03", code: "AGGREGATE_RELATION_INVALID", identity: "five-fragment-aggregate" }); }
    }
    for (const record of records.filter(({ ownerRepository, status, implementationPlan }) => ownerRepository === "AquilaXk/easysubway" && status === "ACTIVE" && implementationPlan !== "PLAN-DOC")) findings.push({ dod: "D05", code: "HUB_TARGET_PLAN_ACTIVE_COPY", identity: record.resource });
  }
  findings.sort(findingCompare);
  const dods = scope.dods.map((id) => {
    const count = findings.filter(({ dod }) => dod === id).length;
    return { id, status: pending > 0 ? "PENDING" : count === 0 ? "PROVEN" : "CONTRADICTED", findings: count };
  });
  return {
    schemaVersion: 1,
    status: "COMPLETE",
    observedAt,
    inputs: { sourceSha, scopeSha256: sha256(scopeText), stateBeginSha256, stateEndSha256 },
    summary: { pending, ready: readyEntries.length, activeResources: records.filter(({ status }) => status === "ACTIVE").length, findings: findings.length, incomplete: 0 },
    repositories: repositories.map(({ repository, headSha, state, fragmentStatus, fragmentBlobSha, resourceCount, activeResourceCount }) => ({ repository, headSha, state, fragmentStatus, fragmentBlobSha, resourceCount, activeResourceCount })),
    dods,
    findings,
    incomplete: [],
  };
}

export function validateDocumentationInventoryAuditReport(report, errors = []) {
  if (report?.schemaVersion !== 1 || !canonicalUtc(report?.observedAt) || !["COMPLETE", "AUDIT_INCOMPLETE"].includes(report?.status)) return [...errors, "report shape mismatch"];
  if (!Array.isArray(report.repositories) || !Array.isArray(report.dods) || !Array.isArray(report.findings) || !Array.isArray(report.incomplete)) return [...errors, "report collection mismatch"];
  if (JSON.stringify(report.repositories.map(({ repository }) => repository)) !== JSON.stringify(EXPECTED_REPOSITORIES)) errors.push("repository parity mismatch");
  if (JSON.stringify(report.dods.map(({ id }) => id)) !== JSON.stringify(EXPECTED_DODS)) errors.push("DoD parity mismatch");
  const pending = report.repositories.filter(({ state }) => state !== "READY").length;
  const ready = report.repositories.length - pending;
  const activeResources = report.repositories.filter(({ state }) => state === "READY").reduce((sum, { activeResourceCount }) => sum + activeResourceCount, 0);
  if (report.summary?.pending !== pending || report.summary?.ready !== ready || report.summary?.activeResources !== activeResources || report.summary?.findings !== report.findings.length || report.summary?.incomplete !== report.incomplete.length) errors.push("summary parity mismatch");
  for (const dod of report.dods) {
    const count = report.findings.filter(({ dod: id }) => id === dod.id).length;
    const expected = report.status === "AUDIT_INCOMPLETE" ? "INCOMPLETE" : pending > 0 ? "PENDING" : count === 0 ? "PROVEN" : "CONTRADICTED";
    if (dod.findings !== count || dod.status !== expected) errors.push(`DoD status mismatch:${dod.id}`);
  }
  if (report.status === "COMPLETE" && (report.incomplete.length !== 0 || !DIGEST.test(report.inputs?.stateBeginSha256) || report.inputs.stateBeginSha256 !== report.inputs.stateEndSha256)) errors.push("complete watermark mismatch");
  if (report.status === "AUDIT_INCOMPLETE" && report.incomplete.length === 0) errors.push("incomplete detail missing");
  const hub = report.repositories.find(({ repository }) => repository === "AquilaXk/easysubway");
  if (report.status === "COMPLETE" && hub?.headSha !== report.inputs?.sourceSha) errors.push("source identity mismatch");
  return errors;
}

function snapshotWatermark(repositories) {
  return sha256(JSON.stringify(repositories.map(({ repository, headSha, state, fragmentStatus, fragmentBlobSha, resourceCount, activeResourceCount, verificationFindings = [] }) => ({ repository, headSha, state, fragmentStatus, fragmentBlobSha, resourceCount, activeResourceCount, verificationFindings }))));
}

export async function collectSnapshot(scope, { readHead = collectHead, readContent = collectContent } = {}) {
  const repositories = [];
  for (const entry of scope.repositories) {
    const headSha = await readHead(entry.repository, entry.defaultBranch);
    if (!SHA.test(headSha)) throw new AuditIncomplete("HEAD_PROVIDER_MALFORMED", entry.repository);
    repositories.push(await verifyFragment(entry, headSha, { readContent }));
  }
  return { repositories, watermark: snapshotWatermark(repositories) };
}

export async function collectLive(scope, { sourceSha, collectSnapshot: snapshot = () => collectSnapshot(scope) } = {}) {
  const begin = await snapshot();
  const end = await snapshot();
  const beginHub = begin.repositories.find(({ repository }) => repository === "AquilaXk/easysubway")?.headSha;
  const endHub = end.repositories.find(({ repository }) => repository === "AquilaXk/easysubway")?.headSha;
  if (beginHub !== sourceSha || endHub !== sourceSha || begin.watermark !== end.watermark) throw new AuditIncomplete("STATE_WATERMARK_DRIFT", "five-fragment-state", "watermark");
  return { repositories: begin.repositories, stateBeginSha256: begin.watermark, stateEndSha256: end.watermark };
}

function providerJson(text, identity) {
  try { return JSON.parse(text); } catch { throw new AuditIncomplete("PROVIDER_MALFORMED", identity); }
}

export async function collectHead(repository, branch = "main", runGh = gh) {
  const ref = providerJson(await runGh(["api", `repos/${repository}/git/ref/heads/${branch}`]), repository);
  if (!SHA.test(ref?.object?.sha)) throw new AuditIncomplete("HEAD_PROVIDER_MALFORMED", repository);
  return ref.object.sha;
}

export async function collectContent(repository, path, sha, runGh = gh) {
  return providerJson(await runGh(["api", `repos/${repository}/contents/${path}?ref=${sha}`]), `${repository}:${path}`);
}

export async function gh(args, execute = execFileAsync) {
  const endpoint = args?.[1];
  const repositories = "AquilaXk/easysubway(?:-(?:backend|data|mobile|platform))?";
  const allowed = new RegExp(`^repos/${repositories}(?:/git/ref/heads/main|/contents/[A-Za-z0-9][A-Za-z0-9._/-]*\\?ref=[0-9a-f]{40})$`);
  if (args?.length !== 2 || args[0] !== "api" || typeof endpoint !== "string" || !allowed.test(endpoint)) throw new Error("gh read-only allowlist violation");
  const contentIndex = endpoint.indexOf("/contents/");
  if (contentIndex >= 0) {
    const refIndex = endpoint.indexOf("?ref=", contentIndex);
    if (refIndex < 0 || !safePath(endpoint.slice(contentIndex + "/contents/".length, refIndex))) throw new Error("gh read-only allowlist violation");
  }
  try { return (await execute("gh", args, { encoding: "utf8", timeout: 30_000, killSignal: "SIGTERM", maxBuffer: 8 * 1024 * 1024 })).stdout; }
  catch (error) {
    if (/(?:^|\D)HTTP 404(?:\D|$)/.test(String(error?.stderr ?? ""))) throw Object.assign(new Error("not found"), { status: 404 });
    throw error;
  }
}

function parseArguments(argv) {
  const names = { "--scope": "scope", "--scope-schema": "scopeSchema", "--report-schema": "reportSchema", "--source-sha": "sourceSha", "--observed-at": "observedAt", "--output": "output" };
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    const key = names[argv[index]];
    if (key == null || argv[index + 1] == null || result[key] != null) throw new Error("unsupported or duplicate argument");
    result[key] = argv[index + 1];
  }
  if (Object.keys(result).length !== Object.keys(names).length || !SHA.test(result.sourceSha) || !canonicalUtc(result.observedAt)) throw new Error("invalid arguments");
  return result;
}

function fallbackReport({ sourceSha, observedAt, scope, incomplete }) {
  return {
    schemaVersion: 1,
    status: "AUDIT_INCOMPLETE",
    observedAt,
    inputs: { sourceSha, scopeSha256: sha256(JSON.stringify(scope)), stateBeginSha256: null, stateEndSha256: null },
    summary: { pending: 5, ready: 0, activeResources: 0, findings: 0, incomplete: 1 },
    repositories: EXPECTED_REPOSITORIES.map((repository) => ({ repository, headSha: null, state: "UNAVAILABLE", fragmentStatus: "UNAVAILABLE", fragmentBlobSha: null, resourceCount: 0, activeResourceCount: 0 })),
    dods: EXPECTED_DODS.map((id) => ({ id, status: "INCOMPLETE", findings: 0 })),
    findings: [],
    incomplete: [incomplete],
  };
}

async function writeExclusive(path, report) {
  const file = await open(path, "wx");
  try { await file.writeFile(`${JSON.stringify(report, null, 2)}\n`); } finally { await file.close(); }
}

export async function runAuditCli({ argv = process.argv.slice(2), read = (path) => readFile(path, "utf8"), collect = null } = {}) {
  let args;
  let scope = fallbackScope();
  let reportSchema = null;
  let report;
  let exitCode = 2;
  try {
    args = parseArguments(argv);
    const [scopeText, scopeSchemaText, reportSchemaText] = await Promise.all([read(args.scope), read(args.scopeSchema), read(args.reportSchema)]);
    scope = JSON.parse(scopeText);
    const scopeSchema = JSON.parse(scopeSchemaText);
    reportSchema = JSON.parse(reportSchemaText);
    const scopeErrors = [...validateSchema(scopeSchema, scope).errors, ...validateDocumentationInventoryAuditScope(scope)];
    if (scopeErrors.length !== 0) throw new AuditIncomplete("SCOPE_INVALID", "scope", "scope");
    const live = await (collect ?? (() => collectLive(scope, { sourceSha: args.sourceSha })))();
    report = auditDocumentationInventory({ scope, sourceSha: args.sourceSha, observedAt: args.observedAt, ...live, scopeText });
    const reportErrors = [...validateSchema(reportSchema, report).errors, ...validateDocumentationInventoryAuditReport(report)];
    if (reportErrors.length !== 0) throw new AuditIncomplete("REPORT_INVALID", "report", "report");
    exitCode = report.summary.pending === 0 && report.summary.findings === 0 ? 0 : 1;
  } catch (error) {
    const sourceSha = args?.sourceSha ?? argv[argv.indexOf("--source-sha") + 1] ?? "0".repeat(40);
    const observedAt = args?.observedAt ?? argv[argv.indexOf("--observed-at") + 1] ?? "1970-01-01T00:00:00.000Z";
    const code = error instanceof AuditIncomplete ? error.code : "AUDIT_INVALID_OR_UNAVAILABLE";
    const stage = error instanceof AuditIncomplete ? error.stage : "audit";
    const identity = error instanceof AuditIncomplete ? error.identity : "audit-input";
    report = fallbackReport({ sourceSha: SHA.test(sourceSha) ? sourceSha : "0".repeat(40), observedAt: canonicalUtc(observedAt) ? observedAt : "1970-01-01T00:00:00.000Z", scope: validateDocumentationInventoryAuditScope(scope).length === 0 ? scope : fallbackScope(), incomplete: { stage, code, affectedIdentity: identity } });
    if (reportSchema != null && (!validateSchema(reportSchema, report).ok || validateDocumentationInventoryAuditReport(report).length !== 0)) report = fallbackReport({ sourceSha: SHA.test(sourceSha) ? sourceSha : "0".repeat(40), observedAt: canonicalUtc(observedAt) ? observedAt : "1970-01-01T00:00:00.000Z", scope: fallbackScope(), incomplete: { stage: "report", code: "REPORT_SCHEMA_INVALID", affectedIdentity: "report-schema" } });
  }
  try { if (args?.output != null) await writeExclusive(args.output, report); } catch { exitCode = 2; return { exitCode, report }; }
  return { exitCode, report };
}

if (isMainModule(import.meta.url)) {
  const result = await runAuditCli();
  process.exitCode = result.exitCode;
}
