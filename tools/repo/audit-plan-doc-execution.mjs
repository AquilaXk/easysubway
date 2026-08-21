#!/usr/bin/env node
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { open, readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

export const REPOSITORIES = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
const PAGE_SIZE = 100;
const MAX_ITEMS = 3000;
const execFileAsync = promisify(execFile);
const CLOSING_ISSUES_QUERY = `query($owner: String!, $name: String!, $number: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { number merged mergeCommit { oid } closingIssuesReferences(first: 100) { totalCount pageInfo { hasNextPage } nodes { number state repository { nameWithOwner } } } } } }`;
const SELF_FILES = ["contracts/documentation/plan-doc-execution-audit-scope.json", "tools/ci/check-contracts.mjs", "tools/ci/check-contracts.test.mjs", "tools/repo/audit-plan-doc-execution.mjs", "tools/repo/audit-plan-doc-execution.test.mjs"];
const EXPECTED_SCOPE_CANONICAL_SHA256 = "ce21d16db5bef06fa16688c19243d0eb846675405507a6e9b784a5b5be1396e3";

export class AuditIncomplete extends Error { constructor(code, identity) { super(code); this.code = code; this.identity = identity; } }

export function validatePlanDocExecutionScope(scope, errors = []) {
  if (scope?.schemaVersion !== 2 || scope?.planOwner !== "PLAN-DOC" || JSON.stringify(scope?.repositories) !== JSON.stringify(REPOSITORIES)) errors.push("scope header mismatch");
  const records = scope?.historical;
  if (!Array.isArray(records) || records.length !== 73) return [...errors, "historical inventory count mismatch"];
  const key = (record, field) => `${record?.repository}:${record?.[field]}`;
  if (new Set(records.map((record) => key(record, "prNumber"))).size !== 73) errors.push("duplicate historical record identity");
  if (new Set(records.map((record) => key(record, "mergeSha"))).size !== 73) errors.push("duplicate historical merge identity");
  for (const record of records) {
    if (!REPOSITORIES.includes(record?.repository) || !Number.isInteger(record?.issueNumber) || !Number.isInteger(record?.prNumber) || !/^[0-9a-f]{40}$/.test(record?.mergeSha) || !["CLOSES", "COORDINATOR_FOLLOWUP"].includes(record?.relation) || record?.planOwner !== "PLAN-DOC" || !["HUB_GOVERNANCE_ONLY", "PLAN_DOC_CI_RECOVERY", "TARGET_DOCUMENTATION_FRAGMENT", "TARGET_PUBLIC_DOCUMENTATION"].includes(record?.changedPathClass) || !sortedUniquePaths(record?.allowedChangedFiles)) errors.push(`historical record malformed:${record?.repository}:${record?.prNumber}`);
  }
  const recovery = records.find((record) => record.repository === "AquilaXk/easysubway" && record.prNumber === 2852);
  if (recovery?.issueNumber !== 2851 || recovery?.mergeSha !== "2620ea1832b500bfe5836a409894113df50dad4b" || recovery?.changedPathClass !== "PLAN_DOC_CI_RECOVERY" || JSON.stringify(recovery?.allowedChangedFiles) !== JSON.stringify([".github/workflows/ci.yml", "apps/mobile/pubspec.lock", "apps/mobile/pubspec.yaml", "tools/ci/repository-contract.test.mjs"])) errors.push("CI recovery binding mismatch");
  const coordinator = records.find((record) => record.repository === "AquilaXk/easysubway" && record.prNumber === 2878);
  if (coordinator?.issueNumber !== 2729 || coordinator?.relation !== "COORDINATOR_FOLLOWUP") errors.push("coordinator relation binding mismatch");
  const self = scope?.self;
  if (self?.repository !== "AquilaXk/easysubway" || self?.issueNumber !== 2894 || self?.planOwner !== "PLAN-DOC" || self?.changedPathClass !== "HUB_GOVERNANCE_ONLY" || JSON.stringify(self?.allowedChangedFiles) !== JSON.stringify(SELF_FILES)) errors.push("self binding mismatch");
  if (sha256(JSON.stringify(scope)) !== EXPECTED_SCOPE_CANONICAL_SHA256) errors.push("historical frozen inventory mismatch");
  return errors;
}

function sortedUniquePaths(paths) { return Array.isArray(paths) && paths.length > 0 && paths.every((path) => typeof path === "string" && /^(?!\/)(?!.*(?:^|\/)\.{1,2}(?:\/|$))[A-Za-z0-9._/-]+$/.test(path)) && new Set(paths).size === paths.length && paths.every((path, index) => index === 0 || codepointCompare(paths[index - 1], path) < 0); }
function identity(record) { return `${record.repository}:${record.prNumber}`; }
function mergeIdentity(record) { return `${record.repository}:${record.mergeSha}`; }
function compare(left, right) { return codepointCompare(`${left.code}\0${left.identity}`, `${right.code}\0${right.identity}`); }

export function auditPlanDocExecution({ scope, sourceSha, live }) {
  const findings = [];
  const add = (code, value) => findings.push({ code, identity: value });
  const records = scope?.historical ?? [];
  for (const duplicate of duplicateValues(records, identity)) add("DUPLICATE_RECORD_IDENTITY", duplicate);
  for (const duplicate of duplicateValues(records, mergeIdentity)) add("DUPLICATE_MERGE_IDENTITY", duplicate);
  const liveByIdentity = new Map((live?.records ?? []).map((record) => [identity(record), record]));
  for (const record of records) {
    const observed = liveByIdentity.get(identity(record));
    if (observed == null || observed.repository !== record.repository) { add("EXECUTION_REPOSITORY_MISMATCH", identity(record)); continue; }
    if (observed.mergeSha !== record.mergeSha) add("MERGE_SHA_MISMATCH", identity(record));
    if (!relationMatches(record, observed)) add("RELATION_MISMATCH", identity(record));
    if (!samePaths(record.allowedChangedFiles, observed.changedFiles)) add("MERGE_DELTA_MISMATCH", identity(record));
  }
  const self = live?.self;
  if (self?.repository !== scope?.self?.repository || self?.mergeSha !== sourceSha) add("SELF_SOURCE_SHA_MISMATCH", `issue:${scope?.self?.issueNumber}`);
  if (!relationMatches({ issueNumber: scope?.self?.issueNumber, relation: "CLOSES" }, self ?? {})) add("SELF_CLOSING_ISSUE_MISMATCH", `issue:${scope?.self?.issueNumber}`);
  if (!samePaths(scope?.self?.allowedChangedFiles, self?.changedFiles)) add("MERGE_DELTA_MISMATCH", `self:${scope?.self?.repository}:${self?.prNumber ?? "unknown"}`);
  return findings.sort(compare);
}

function duplicateValues(records, toKey) { const seen = new Set(); const duplicates = new Set(); for (const record of records) { const key = toKey(record); if (seen.has(key)) duplicates.add(key); seen.add(key); } return [...duplicates].sort(codepointCompare); }
function samePaths(expected, observed) { return JSON.stringify(expected) === JSON.stringify([...(observed ?? [])].sort(codepointCompare)); }
function relationMatches(record, observed) {
  const number = record.issueNumber;
  const body = String(observed.relationText ?? "");
  const closes = new RegExp(`(?:^|\\n)\\s*Closes\\s+#${number}\\s*(?:$|\\n)`, "m").test(body);
  const refs = new RegExp(`(?:^|\\n)Refs #${number}(?: +[—–\\-:][^\\r\\n]*)?(?=$|\\r?\\n(?![ \\t]*[—–\\-:]))`).test(body);
  const closingIssues = observed.closingIssues ?? [];
  return record.relation === "CLOSES"
    ? closes && closingIssues.length === 1 && closingIssues[0]?.number === number && closingIssues[0]?.state === "CLOSED"
    : refs && closingIssues.length === 0;
}

export async function collectPlanDocExecutionLive({ scope, sourceSha, execGh = runGh, execGraphql = runClosingIssuesGraphql }) {
  const records = [];
  for (const record of scope.historical) records.push(await collectRecord({ record, execGh, execGraphql }));
  const selfRepository = scope.self.repository;
  const associated = parseJson(await execGh(["api", `repos/${selfRepository}/commits/${sourceSha}/pulls`]), `sha:${sourceSha}`);
  if (!Array.isArray(associated) || associated.length !== 1 || !Number.isInteger(associated[0]?.number)) throw new AuditIncomplete("ASSOCIATION_AMBIGUOUS", `sha:${sourceSha}`);
  const self = await collectRecord({ record: { ...scope.self, prNumber: associated[0].number, mergeSha: sourceSha, relation: "CLOSES" }, execGh, execGraphql });
  return { records, self };
}

async function collectRecord({ record, execGh, execGraphql }) {
  const id = identity(record);
  const pr = parseJson(await execGh(["api", `repos/${record.repository}/pulls/${record.prNumber}`]), id);
  if (pr?.number !== record.prNumber || pr?.merged !== true || pr?.base?.repo?.full_name !== record.repository || !/^[0-9a-f]{40}$/.test(pr?.merge_commit_sha)) throw new AuditIncomplete("PROVIDER_MALFORMED", id);
  const changedFiles = await collectCommitDelta(record.repository, pr.merge_commit_sha, id, execGh);
  const closingIssues = parseClosingIssues(await execGraphql(record.repository, record.prNumber), record.repository, record.prNumber, pr.merge_commit_sha);
  return { issueNumber: record.issueNumber, prNumber: record.prNumber, repository: record.repository, mergeSha: pr.merge_commit_sha, changedFiles, relationText: String(pr.body ?? ""), closingIssues };
}

async function collectCommitDelta(repository, mergeSha, id, execGh) {
  const files = []; const seen = new Set();
  for (let page = 1; page <= Math.ceil(MAX_ITEMS / PAGE_SIZE) + 1; page += 1) {
    const commit = parseJson(await execGh(["api", `repos/${repository}/commits/${mergeSha}?per_page=${PAGE_SIZE}&page=${page}`]), `${id}:commit`);
    if (commit?.sha !== mergeSha || !Array.isArray(commit?.parents) || commit.parents.length !== 1 || !Array.isArray(commit?.files)) throw new AuditIncomplete("COMMIT_MALFORMED", `${id}:commit`);
    if (page > 1 && commit.files.length === 0) throw new AuditIncomplete("PROVIDER_PARTIAL", `${id}:commit`);
    for (const file of commit.files) {
      if (typeof file?.filename !== "string" || file.filename === "" || file.previous_filename != null || file.status === "renamed" || seen.has(file.filename)) throw new AuditIncomplete(file?.previous_filename != null || file?.status === "renamed" ? "COMMIT_RENAME_UNSUPPORTED" : "PROVIDER_PARTIAL", `${id}:commit`);
      seen.add(file.filename); files.push(file.filename);
    }
    if (files.length > MAX_ITEMS) throw new AuditIncomplete("PROVIDER_PARTIAL", `${id}:commit`);
    if (commit.files.length < PAGE_SIZE) return files.sort(codepointCompare);
  }
  throw new AuditIncomplete("PROVIDER_PARTIAL", `${id}:commit`);
}

export function parseClosingIssues(text, repository, prNumber, mergeSha) {
  const response = parseJson(text, `${repository}:${prNumber}:closing-issues`);
  const pr = response?.data?.repository?.pullRequest; const refs = pr?.closingIssuesReferences;
  if ((response?.errors != null && (!Array.isArray(response.errors) || response.errors.length !== 0)) || pr?.number !== prNumber || pr?.merged !== true || pr?.mergeCommit?.oid !== mergeSha || !Number.isInteger(refs?.totalCount) || refs.totalCount < 0 || refs.totalCount > PAGE_SIZE || refs?.pageInfo?.hasNextPage !== false || !Array.isArray(refs?.nodes) || refs.nodes.length !== refs.totalCount) throw new AuditIncomplete("PROVIDER_PARTIAL", `${repository}:${prNumber}:closing-issues`);
  if (!refs.nodes.every((node) => Number.isInteger(node?.number) && node.number > 0 && node.state === "CLOSED" && node.repository?.nameWithOwner === repository) || new Set(refs.nodes.map((node) => node.number)).size !== refs.nodes.length) throw new AuditIncomplete("PROVIDER_MALFORMED", `${repository}:${prNumber}:closing-issues`);
  return refs.nodes.map(({ number, state }) => ({ number, state })).sort((left, right) => left.number - right.number);
}

function parseJson(text, id) { try { return JSON.parse(text); } catch { throw new AuditIncomplete("PROVIDER_MALFORMED", id); } }

export function createPlanDocExecutionReport({ scope, scopeText, sourceSha, observedAt, live = null, findings = [], incomplete = [] }) {
  const normalizedIncomplete = incomplete.map(sanitizeIncomplete).sort(compareIncomplete);
  const records = live == null ? [] : [...live.records.map((record) => reportRecord("HISTORICAL", record)), reportRecord("SELF", live.self)].sort((left, right) => codepointCompare(`${left.repository}\0${left.prNumber}`, `${right.repository}\0${right.prNumber}`));
  const sortedFindings = [...findings].sort(compare);
  return { schemaVersion: 2, status: normalizedIncomplete.length === 0 ? "COMPLETE" : "AUDIT_INCOMPLETE", observedAt, inputs: { sourceSha, scopeSha256: sha256(scopeText), repositories: REPOSITORIES }, summary: { records: records.length, findings: sortedFindings.length, incomplete: normalizedIncomplete.length }, records, findings: sortedFindings, incomplete: normalizedIncomplete };
}
function reportRecord(kind, record) { return { kind, repository: record.repository, issueNumber: record.issueNumber, prNumber: record.prNumber, mergeSha: record.mergeSha, changedFiles: [...record.changedFiles].sort(codepointCompare) }; }
function sanitizeIncomplete({ stage, code, affectedIdentity }) { return { stage: String(stage).replace(/[^a-z0-9-]/g, "-").replace(/^-+|-+$/g, "") || "unknown", code: String(code).replace(/[^A-Z0-9_]/g, "_"), affectedIdentity: String(affectedIdentity).replace(/[^A-Za-z0-9:._/-]/g, "_") }; }
function compareIncomplete(a, b) { return codepointCompare(a.stage, b.stage) || codepointCompare(a.code, b.code) || codepointCompare(a.affectedIdentity, b.affectedIdentity); }
function sha256(value) { return createHash("sha256").update(value).digest("hex"); }

export async function runGh(args, execute = execFileAsync) {
  const endpoint = args?.[1];
  const repo = "(?:AquilaXk/easysubway|AquilaXk/easysubway-backend|AquilaXk/easysubway-data|AquilaXk/easysubway-mobile|AquilaXk/easysubway-platform)";
  if (!Array.isArray(args) || args.length !== 2 || args[0] !== "api" || typeof endpoint !== "string" || !new RegExp(`^repos/${repo}/(?:pulls/[1-9]\\d*|commits/[0-9a-f]{40}(?:/pulls)?)(?:\\?(?:per_page=100&page=[1-9]\\d*)?)?$`).test(endpoint)) throw new Error("gh read-only allowlist violation");
  const { stdout } = await execute("gh", args, { encoding: "utf8", timeout: 30_000, killSignal: "SIGTERM", maxBuffer: 64 * 1024 * 1024 }); return stdout;
}
export async function runClosingIssuesGraphql(repository, prNumber, execute = execFileAsync) {
  if (!REPOSITORIES.includes(repository) || !Number.isInteger(prNumber) || prNumber < 1) throw new Error("gh GraphQL allowlist violation");
  const [owner, name] = repository.split("/"); const { stdout } = await execute("gh", ["api", "graphql", "-f", `query=${CLOSING_ISSUES_QUERY}`, "-F", `owner=${owner}`, "-F", `name=${name}`, "-F", `number=${prNumber}`], { encoding: "utf8", timeout: 30_000, killSignal: "SIGTERM", maxBuffer: 64 * 1024 * 1024 }); return stdout;
}

export function parseArguments(argv) { const names = { "--scope": "scopePath", "--scope-schema": "scopeSchemaPath", "--report-schema": "reportSchemaPath", "--source-sha": "sourceSha", "--observed-at": "observedAt", "--output": "outputPath" }; const values = {}; for (let index = 0; index < argv.length; index += 1) { const key = names[argv[index]]; const value = argv[++index]; if (key == null || value == null || value.startsWith("--") || values[key] != null) throw new Error("unsupported or duplicate argument"); values[key] = value; } if (Object.keys(values).length !== Object.keys(names).length || !/^[0-9a-f]{40}$/.test(values.sourceSha) || new Date(values.observedAt).toISOString() !== values.observedAt) throw new Error("invalid audit arguments"); return values; }
export async function runAuditCli({ argv, collectLive = collectPlanDocExecutionLive, read = readFile, openFile = open } = {}) { let args; let scope = { repositories: REPOSITORIES }; let scopeText = "{}"; let report; let exitCode = 2; try { args = parseArguments(argv); [scopeText] = await Promise.all([read(args.scopePath, "utf8")]); scope = JSON.parse(scopeText); const [scopeSchemaText, reportSchemaText] = await Promise.all([read(args.scopeSchemaPath, "utf8"), read(args.reportSchemaPath, "utf8")]); const scopeErrors = [...validateSchema(JSON.parse(scopeSchemaText), scope).errors, ...validatePlanDocExecutionScope(scope)]; if (scopeErrors.length !== 0) throw new AuditIncomplete("SCOPE_INVALID", "scope"); const live = await collectLive({ scope, sourceSha: args.sourceSha }); const findings = auditPlanDocExecution({ scope, sourceSha: args.sourceSha, live }); report = createPlanDocExecutionReport({ scope, scopeText, sourceSha: args.sourceSha, observedAt: args.observedAt, live, findings }); if (!validateSchema(JSON.parse(reportSchemaText), report).ok) throw new AuditIncomplete("REPORT_INVALID", "report"); exitCode = findings.length === 0 ? 0 : 1; } catch (error) { const incomplete = error instanceof AuditIncomplete ? [{ stage: "github", code: error.code, affectedIdentity: error.identity }] : [{ stage: "runner", code: "AUDIT_FAILURE", affectedIdentity: "audit" }]; if (args != null) report = createPlanDocExecutionReport({ scope, scopeText, sourceSha: args.sourceSha, observedAt: args.observedAt, incomplete }); } if (args == null || report == null) return { exitCode: 2, report: null, outputWritten: false }; try { const handle = await openFile(args.outputPath, "wx"); try { await handle.writeFile(`${JSON.stringify(report)}\n`); } finally { await handle.close(); } } catch { return { exitCode: 2, report: null, outputWritten: false }; } return { exitCode, report, outputWritten: true }; }
async function main() { process.exitCode = (await runAuditCli({ argv: process.argv.slice(2) })).exitCode; }
if (isMainModule(import.meta.url)) await main();
