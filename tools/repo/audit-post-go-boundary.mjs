#!/usr/bin/env node
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { open, readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { isMainModule } from "../lib/is-main-module.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { codepointCompare } from "../lib/codepoint-compare.mjs";

const REPOSITORY = "AquilaXk/easysubway";
const BLOCKED_MARKERS = {
  fieldResearch: ["stable public release      NOT_PROVEN", "activation                 NOT_PROVEN"],
  privacyMetrics: ["Mobile #36 terminal        NOT_PROVEN", "stable public release      NOT_PROVEN", "exact product question     NOT_PROVEN", "activation                 NOT_PROVEN"],
};
const execFileAsync = promisify(execFile);

export class AuditIncomplete extends Error { constructor(code, identity) { super(code); this.code = code; this.identity = identity; } }

export function validatePostGoBoundaryScope(scope, errors = []) {
  if (scope?.schemaVersion !== 1 || scope?.repository !== REPOSITORY) errors.push("scope header mismatch");
  if (scope?.releaseDecision?.repository !== REPOSITORY || scope?.releaseDecision?.number !== 1020) errors.push("release decision mismatch");
  if (scope?.mobilePrivacyGate?.repository !== "AquilaXk/easysubway-mobile" || scope?.mobilePrivacyGate?.number !== 36) errors.push("mobile privacy gate mismatch");
  for (const [name, number, marker] of [["fieldResearch", 2766, "activation      Hub #1020 GO + stable public release scope"], ["privacyMetrics", 2768, "activation      Mobile #36 terminal + public release + exact product question"]]) {
    const parent = scope?.parents?.[name];
    if (parent?.repository !== REPOSITORY || parent?.number !== number || parent?.activationMarker !== marker || JSON.stringify(parent?.blockedMarkers) !== JSON.stringify(BLOCKED_MARKERS[name])) errors.push(`parent mismatch:${name}`);
  }
  if (!Array.isArray(scope?.declaredJitChildren) || scope.declaredJitChildren.length !== 0) errors.push("declared JIT child inventory mismatch");
  return errors;
}

function exactCount(body, expression) { return [...String(body).matchAll(expression)].length; }
function currentDecision(body) {
  const blocks = [...String(body).matchAll(/^## Current decision record\s*\n+```text\s*\n([\s\S]*?)\n```/gm)];
  const finals = blocks.length === 1 ? [...blocks[0][1].matchAll(/^FINAL = (NO_GO|GO)$/gm)] : [];
  if (finals.length !== 1) throw new AuditIncomplete("MARKER_AMBIGUOUS", "releaseDecision");
  return finals[0][1];
}
function issue(live, name, expected) {
  const value = live?.issues?.[name];
  if (value?.repository !== expected.repository || value?.number !== expected.number || !["OPEN", "CLOSED"].includes(value?.state) || typeof value?.body !== "string") throw new AuditIncomplete("PROVIDER_MALFORMED", `issue:${expected.number}`);
  return value;
}

export function auditPostGoBoundary({ scope, sourceSha, live }) {
  if (live?.defaultHead !== sourceSha) throw new AuditIncomplete("DEFAULT_HEAD_DRIFT", "default-head");
  const release = issue(live, "releaseDecision", scope.releaseDecision);
  const mobile = issue(live, "mobilePrivacy", scope.mobilePrivacyGate);
  if (release.state !== "OPEN" || mobile.state !== "OPEN" || currentDecision(release.body) !== "NO_GO") throw new AuditIncomplete("POST_GO_ACTIVATION_CONTRACT_NOT_CONFIGURED", "activation");
  const lanes = [];
  for (const name of ["fieldResearch", "privacyMetrics"]) {
    const parent = scope.parents[name]; const observed = issue(live, name, parent);
    if (observed.state !== "OPEN") throw new AuditIncomplete("POST_GO_ACTIVATION_CONTRACT_NOT_CONFIGURED", name);
    if (!roleActivationMarkerMatches(observed.body, parent.activationMarker) || !blockedMarkerBlockMatches(observed.body, parent.blockedMarkers)) throw new AuditIncomplete("MARKER_AMBIGUOUS", name);
    lanes.push({ parent: name, status: "START_BLOCKED", declaredJitChildren: 0 });
  }
  const children = live.declaredChildren;
  if (!Array.isArray(children)) throw new AuditIncomplete("PROVIDER_PARTIAL", "relations");
  const findings = [];
  for (const child of children) {
    if (!child || !["fieldResearch", "privacyMetrics"].includes(child.parent) || child.relation !== "JIT_CHILD" || !Number.isInteger(child.number) || child.number < 1 || typeof child.repository !== "string") throw new AuditIncomplete("PROVIDER_MALFORMED", "relations");
    const lane = lanes.find((value) => value.parent === child.parent); lane.declaredJitChildren += 1;
    if (lane.status === "START_BLOCKED") findings.push({ code: "JIT_CHILD_CREATED_BEFORE_ACTIVATION", identity: `${child.parent}:${child.repository}:${child.number}` });
  }
  return findings.sort((a, b) => codepointCompare(a.identity, b.identity));
}
function escapeRegExp(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
function roleActivationMarkerMatches(body, marker) { const text = String(body); const headings = [...text.matchAll(/^## 판정·역할\s*$/gm)]; if (headings.length !== 1) return false; const start = headings[0].index; const remainder = text.slice(start + headings[0][0].length); const next = remainder.search(/\n## /); const section = next < 0 ? remainder : remainder.slice(0, next); const blocks = [...section.matchAll(/```text\s*\n([\s\S]*?)\n```/gm)]; return blocks.length === 1 && exactCount(blocks[0][1], new RegExp(`^${escapeRegExp(marker)}$`, "gm")) === 1; }
function blockedMarkerBlockMatches(body, markers) { const blocks = [...String(body).matchAll(/^## activation evidence audit\s*\n+```text\s*\n([\s\S]*?)\n```/gm)]; if (blocks.length !== 1) return false; const lines = blocks[0][1].split("\n"); return markers.every((marker) => { const key = marker.split(/\s{2,}/)[0]; const keyed = lines.filter((line) => line.startsWith(key)); return keyed.length === 1 && keyed[0] === marker; }); }

export function createPostGoBoundaryReport({ scope, scopeText, sourceSha, observedAt, live = null, findings = [], incomplete = [] }) {
  const normalized = incomplete.map(({ stage, code, affectedIdentity }) => ({ stage: String(stage).replace(/[^a-z0-9-]/g, "-") || "unknown", code: String(code).replace(/[^A-Z0-9_]/g, "_"), affectedIdentity: String(affectedIdentity).replace(/[^A-Za-z0-9:._/-]/g, "_") }));
  const lanes = ["fieldResearch", "privacyMetrics"].map((parent) => ({ parent, status: live == null ? "NOT_PROVEN" : "START_BLOCKED", declaredJitChildren: (live?.declaredChildren ?? []).filter((child) => child.parent === parent).length }));
  return { schemaVersion: 1, status: normalized.length ? "AUDIT_INCOMPLETE" : "COMPLETE", observedAt, inputs: { sourceSha, scopeSha256: createHash("sha256").update(scopeText).digest("hex"), repository: REPOSITORY, stateBeginSha256: live?.stateBeginSha256 ?? null, stateEndSha256: live?.stateEndSha256 ?? null }, summary: { declaredJitChildren: (live?.declaredChildren ?? []).length, findings: findings.length, incomplete: normalized.length }, lanes, findings, incomplete: normalized };
}
export function validatePostGoBoundaryReport(report) { const lanes = report?.lanes; if (!Array.isArray(lanes) || lanes.length !== 2 || new Set(lanes.map((lane) => lane?.parent)).size !== 2 || !["fieldResearch", "privacyMetrics"].every((parent) => lanes.some((lane) => lane.parent === parent))) return false; if (report?.summary?.findings !== report.findings?.length || report?.summary?.incomplete !== report.incomplete?.length || report?.summary?.declaredJitChildren !== lanes.reduce((sum, lane) => sum + lane.declaredJitChildren, 0)) return false; return report.status === "COMPLETE" ? report.incomplete.length === 0 && lanes.every((lane) => lane.status === "START_BLOCKED") && /^[0-9a-f]{64}$/.test(report.inputs?.stateBeginSha256) && report.inputs.stateBeginSha256 === report.inputs.stateEndSha256 : report.status === "AUDIT_INCOMPLETE" && report.incomplete.length > 0 && lanes.every((lane) => lane.status === "NOT_PROVEN"); }

async function collectSnapshot({ scope, execGh, execGraphql }) {
  const repository = parseJson(await execGh(REPOSITORY, ""), "default-head");
  if (typeof repository?.default_branch !== "string" || !/^[A-Za-z0-9._/-]+$/.test(repository.default_branch)) throw new AuditIncomplete("PROVIDER_MALFORMED", "default-head");
  const [headText, releaseDecision, fieldResearch, privacyMetrics, mobilePrivacy, fieldChildren, privacyChildren] = await Promise.all([
    execGh(REPOSITORY, `commits/${repository.default_branch}`), execGh(REPOSITORY, `issues/${scope.releaseDecision.number}`), execGh(REPOSITORY, `issues/${scope.parents.fieldResearch.number}`), execGh(REPOSITORY, `issues/${scope.parents.privacyMetrics.number}`), execGh("AquilaXk/easysubway-mobile", `issues/${scope.mobilePrivacyGate.number}`), collectSubIssues(scope.parents.fieldResearch.number, "fieldResearch", execGraphql), collectSubIssues(scope.parents.privacyMetrics.number, "privacyMetrics", execGraphql),
  ]);
  const head = parseJson(headText, "default-head");
  if (!/^[0-9a-f]{40}$/.test(head?.sha ?? "")) throw new AuditIncomplete("PROVIDER_MALFORMED", "default-head");
  return { defaultHead: head.sha, issues: { releaseDecision: parseIssue(releaseDecision), fieldResearch: parseIssue(fieldResearch), privacyMetrics: parseIssue(privacyMetrics), mobilePrivacy: parseIssue(mobilePrivacy) }, declaredChildren: [...fieldChildren, ...privacyChildren] };
}
export async function collectPostGoBoundaryLive({ scope, sourceSha, execGh = runGh, execGraphql = runGraphql }) {
  const begin = normalizeSnapshot(await collectSnapshot({ scope, execGh, execGraphql }));
  const stateBeginSha256 = createHash("sha256").update(JSON.stringify(begin)).digest("hex");
  const end = normalizeSnapshot(await collectSnapshot({ scope, execGh, execGraphql }));
  const stateEndSha256 = createHash("sha256").update(JSON.stringify(end)).digest("hex");
  if (begin.defaultHead !== sourceSha || end.defaultHead !== sourceSha || stateBeginSha256 !== stateEndSha256) throw new AuditIncomplete("STATE_WATERMARK_DRIFT", "snapshot");
  return { ...begin, stateBeginSha256, stateEndSha256 };
}
function normalizeSnapshot(snapshot) { return { ...snapshot, declaredChildren: [...snapshot.declaredChildren].sort((left, right) => codepointCompare(`${left.parent}\0${left.repository}\0${left.number}`, `${right.parent}\0${right.repository}\0${right.number}`)) }; }
function parseJson(text, identity) { try { return JSON.parse(text); } catch { throw new AuditIncomplete("PROVIDER_MALFORMED", identity); } }
function parseIssue(text) { const value = parseJson(text, "issue"); if (typeof value?.repository_url !== "string" || !Number.isInteger(value?.number) || !["open", "closed"].includes(value?.state) || typeof value?.body !== "string") throw new AuditIncomplete("PROVIDER_MALFORMED", "issue"); return { repository: value.repository_url.split("/repos/")[1], number: value.number, state: value.state.toUpperCase(), body: value.body }; }
export async function runGh(repository, suffix, execute = execFileAsync) { if (![REPOSITORY, "AquilaXk/easysubway-mobile"].includes(repository) || !/^$|^(?:issues\/\d+|commits\/[A-Za-z0-9._/-]+)$/.test(suffix)) throw new Error("gh read-only allowlist violation"); const { stdout } = await execute("gh", ["api", `repos/${repository}${suffix ? `/${suffix}` : ""}`], { encoding: "utf8", timeout: 30000, killSignal: "SIGTERM" }); return stdout; }
const SUB_ISSUES_QUERY = "query($number:Int!,$cursor:String){repository(owner:\"AquilaXk\",name:\"easysubway\"){issue(number:$number){subIssues(first:100,after:$cursor){totalCount pageInfo{hasNextPage endCursor} nodes{number repository{nameWithOwner}}}}}}";
async function collectSubIssues(number, parent, execGraphql) { const values = []; let cursor = null; let frozenTotal = null; for (let page = 0; page < 31; page += 1) { const response = parseJson(await execGraphql(number, cursor), `relations:${number}`); const connection = response?.data?.repository?.issue?.subIssues; if (Array.isArray(response?.errors) && response.errors.length || !Number.isInteger(connection?.totalCount) || connection.totalCount < 0 || !Array.isArray(connection?.nodes) || typeof connection?.pageInfo?.hasNextPage !== "boolean" || frozenTotal != null && frozenTotal !== connection.totalCount) throw new AuditIncomplete("PROVIDER_PARTIAL", `relations:${number}`); frozenTotal = connection.totalCount; for (const node of connection.nodes) { const identity = `${node?.repository?.nameWithOwner}:${node?.number}`; if (!Number.isInteger(node?.number) || node.number < 1 || typeof node?.repository?.nameWithOwner !== "string" || values.some((value) => `${value.repository}:${value.number}` === identity)) throw new AuditIncomplete("PROVIDER_MALFORMED", `relations:${number}`); values.push({ repository: node.repository.nameWithOwner, number: node.number, parent, relation: "JIT_CHILD" }); } if (values.length > frozenTotal || values.length > 3000) throw new AuditIncomplete("PROVIDER_PARTIAL", `relations:${number}`); if (!connection.pageInfo.hasNextPage) { if (values.length !== frozenTotal) throw new AuditIncomplete("PROVIDER_PARTIAL", `relations:${number}`); return values; } if (typeof connection.pageInfo.endCursor !== "string" || connection.nodes.length !== 100) throw new AuditIncomplete("PROVIDER_PARTIAL", `relations:${number}`); cursor = connection.pageInfo.endCursor; } throw new AuditIncomplete("PROVIDER_PARTIAL", `relations:${number}`); }
export async function runGraphql(number, cursor, execute = execFileAsync) { if (!Number.isInteger(number) || number < 1 || (cursor != null && typeof cursor !== "string")) throw new Error("gh GraphQL allowlist violation"); const args = ["api", "graphql", "-f", `query=${SUB_ISSUES_QUERY}`, "-F", `number=${number}`]; if (cursor != null) args.push("-f", `cursor=${cursor}`); const { stdout } = await execute("gh", args, { encoding: "utf8", timeout: 30000, killSignal: "SIGTERM" }); return stdout; }

export function parseArguments(argv) { const names = { "--scope": "scopePath", "--scope-schema": "scopeSchemaPath", "--report-schema": "reportSchemaPath", "--source-sha": "sourceSha", "--observed-at": "observedAt", "--output": "outputPath" }; const values = {}; for (let i = 0; i < argv.length; i += 1) { const key = names[argv[i]]; const value = argv[++i]; if (!key || !value || value.startsWith("--") || values[key]) throw new Error("invalid arguments"); values[key] = value; } if (Object.keys(values).length !== Object.keys(names).length || !/^[0-9a-f]{40}$/.test(values.sourceSha) || new Date(values.observedAt).toISOString() !== values.observedAt) throw new Error("invalid arguments"); return values; }
export async function runAuditCli({ argv, collectLive = collectPostGoBoundaryLive, read = readFile, openFile = open } = {}) { let args; let scope = { repository: REPOSITORY }; let scopeText = "{}"; let report; let reportSchema; let exitCode = 2; try { args = parseArguments(argv); scopeText = await read(args.scopePath, "utf8"); scope = JSON.parse(scopeText); const [scopeSchema, reportSchemaText] = await Promise.all([read(args.scopeSchemaPath, "utf8"), read(args.reportSchemaPath, "utf8")]); reportSchema = JSON.parse(reportSchemaText); if (!validateSchema(JSON.parse(scopeSchema), scope).ok || validatePostGoBoundaryScope(scope).length) throw new AuditIncomplete("SCOPE_INVALID", "scope"); const live = await collectLive({ scope, sourceSha: args.sourceSha }); const findings = auditPostGoBoundary({ scope, sourceSha: args.sourceSha, live }); report = createPostGoBoundaryReport({ scope, scopeText, sourceSha: args.sourceSha, observedAt: args.observedAt, live, findings }); if (!validateSchema(reportSchema, report).ok || !validatePostGoBoundaryReport(report)) throw new AuditIncomplete("REPORT_INVALID", "report"); exitCode = findings.length ? 1 : 0; } catch (error) { if (args) report = createPostGoBoundaryReport({ scope, scopeText, sourceSha: args.sourceSha, observedAt: args.observedAt, incomplete: [{ stage: "github", code: error instanceof AuditIncomplete ? error.code : "AUDIT_FAILURE", affectedIdentity: error instanceof AuditIncomplete ? error.identity : "audit" }] }); } if (!args || !report || reportSchema != null && (!validateSchema(reportSchema, report).ok || !validatePostGoBoundaryReport(report))) return { exitCode: 2, report: null, outputWritten: false }; try { const handle = await openFile(args.outputPath, "wx"); await handle.writeFile(`${JSON.stringify(report)}\n`); await handle.close(); } catch { return { exitCode: 2, report: null, outputWritten: false }; } return { exitCode, report, outputWritten: true }; }
if (isMainModule(import.meta.url)) process.exitCode = (await runAuditCli({ argv: process.argv.slice(2) })).exitCode;
