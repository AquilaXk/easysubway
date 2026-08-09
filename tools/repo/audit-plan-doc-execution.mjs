#!/usr/bin/env node
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { open, readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

const REPOSITORY = "AquilaXk/easysubway";
const PAGE_SIZE = 100;
const MAX_ITEMS = 3000;
const GH_TIMEOUT_MS = 30_000;
const GH_MAX_BUFFER = 64 * 1024 * 1024;
const execFileAsync = promisify(execFile);
const EXPECTED_RECORDS = new Map([
  [2749, [2748, "5ad660a7f07563999c1c076790614e7e717e0ea7", "COORDINATOR_FOLLOWUP"]], [2755, [2754, "0568c2195ccac35f0d46f6bb3594093471310977", "CLOSES"]], [2757, [2756, "2b102c1b50f495d628617e61ae95f81944b69c20", "CLOSES"]], [2759, [2758, "00c6109bf91e052fc0d9944a84fde1601c1c50c1", "CLOSES"]], [2761, [2760, "decc1072aa8c8facbfa0143fa1f8fe7646bc016d", "CLOSES"]], [2763, [2762, "560e07239e9ef99b3bfea2ab4bf758b5115acb43", "CLOSES"]], [2730, [2729, "4ccf78d8bf60db2d25233d6fe744daf805c7b0ac", "COORDINATOR_FOLLOWUP"]], [2775, [2733, "96119c4d723d9c60fcd8999da8e58af0731b0847", "CLOSES"]], [2782, [2781, "6194860b5cb13334b91410374fd2504ee056684c", "CLOSES"]], [2784, [2783, "3ea7ef2929ce680268783a1a14476138beb2b521", "CLOSES"]], [2787, [2785, "79bcd0b8e05eb90907c411bdde9b30e24592ce53", "CLOSES"]], [2788, [2729, "a44259fcbdd5538586f4aabaa9a6cb844a41dc03", "COORDINATOR_FOLLOWUP"]], [2789, [2748, "90a169d9b35e4845bfd03d518522544b66dd189f", "COORDINATOR_FOLLOWUP"]], [2791, [2790, "40d1bb13906a6a96a3c7342b0923ad180d290234", "CLOSES"]], [2793, [2792, "3d1590baa98c929ceabd0d2d44414cebcc643c6f", "CLOSES"]], [2796, [2795, "b853fe6101c7848a8d556bf21b882b3f0e3060a9", "CLOSES"]],
]);

export class AuditIncomplete extends Error {
  constructor(code, identity) { super(code); this.code = code; this.identity = identity; }
}

export function validatePlanDocExecutionScope(scope, errors = []) {
  if (scope?.schemaVersion !== 1 || scope?.executionRepository !== REPOSITORY || scope?.planOwner !== "PLAN-DOC") errors.push("scope header mismatch");
  if (JSON.stringify(scope?.forbiddenTargetPathPrefixes) !== JSON.stringify(["apps/mobile/", "backend/", "infra/", "tools/datapack/", "tools/ops/", "tools/release/"])) errors.push("forbidden target prefix mismatch");
  if (scope?.self?.issueNumber !== 2797 || scope?.self?.planOwner !== "PLAN-DOC") errors.push("self binding mismatch");
  const records = scope?.historical;
  if (!Array.isArray(records) || records.length !== EXPECTED_RECORDS.size) return [...errors, "historical inventory count mismatch"];
  const actual = new Map(records.map((record) => [record?.prNumber, record]));
  if (actual.size !== EXPECTED_RECORDS.size) errors.push("duplicate historical PR");
  for (const [prNumber, [issueNumber, mergeSha, relation]] of EXPECTED_RECORDS) {
    const record = actual.get(prNumber);
    if (record?.issueNumber !== issueNumber || record?.mergeSha !== mergeSha || record?.relation !== relation || record?.planOwner !== "PLAN-DOC" || record?.changedPathClass !== "HUB_GOVERNANCE_ONLY") errors.push(`historical record mismatch:${prNumber}`);
  }
  if (new Set(records.map(({ mergeSha }) => mergeSha)).size !== records.length) errors.push("duplicate historical merge SHA");
  return errors;
}

export function auditPlanDocExecution({ scope, sourceSha, live }) {
  const findings = [];
  const add = (code, identity) => findings.push({ code, identity });
  const records = scope.historical ?? [];
  const duplicatePr = duplicateValues(records.map(({ prNumber }) => prNumber));
  for (const value of duplicatePr) add("DUPLICATE_PR", `pr:${value}`);
  const duplicateSha = duplicateValues(records.map(({ mergeSha }) => mergeSha));
  for (const value of duplicateSha) add("DUPLICATE_MERGE_SHA", `sha:${value}`);
  const liveByPr = new Map((live?.records ?? []).map((record) => [record.prNumber, record]));
  for (const record of records) {
    const observed = liveByPr.get(record.prNumber);
    if (observed == null) { add("EXECUTION_REPOSITORY_MISMATCH", `pr:${record.prNumber}`); continue; }
    if (observed.repository !== scope.executionRepository) add("EXECUTION_REPOSITORY_MISMATCH", `pr:${record.prNumber}`);
    if (observed.mergeSha !== record.mergeSha) add("MERGE_SHA_MISMATCH", `pr:${record.prNumber}`);
    if (!relationMatches(record, observed)) add("RELATION_MISMATCH", `pr:${record.prNumber}`);
    for (const path of observed.changedFiles ?? []) if (scope.forbiddenTargetPathPrefixes.some((prefix) => path.startsWith(prefix))) add("TARGET_PATH_MODIFICATION", `pr:${record.prNumber}:${path}`);
  }
  const self = live?.self;
  if (self?.mergeSha !== sourceSha) add("SELF_SOURCE_SHA_MISMATCH", `issue:${scope.self.issueNumber}`);
  if (!relationMatches({ issueNumber: scope.self.issueNumber, relation: "CLOSES" }, self ?? {})) add("SELF_CLOSING_ISSUE_MISMATCH", `issue:${scope.self.issueNumber}`);
  for (const path of self?.changedFiles ?? []) if (scope.forbiddenTargetPathPrefixes.some((prefix) => path.startsWith(prefix))) add("TARGET_PATH_MODIFICATION", `pr:${self.prNumber}:${path}`);
  return findings.sort(compare);
}

function relationMatches(record, observed) {
  const number = record.issueNumber;
  const exactCloses = new RegExp(`(?:^|\\n)\\s*(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\\s+#${number}\\s*(?:$|\\n)`, "im").test(observed.relationText ?? "");
  const exactRefs = new RegExp(`(?:^|\\n)\\s*Refs\\s+#${number}\\s*(?:$|\\n)`, "m").test(observed.relationText ?? "");
  return record.relation === "CLOSES" ? exactCloses && observed.closedByMerge === true : exactRefs && observed.closedByMerge === false;
}

function duplicateValues(values) { return [...new Set(values.filter((value, index) => values.indexOf(value) !== index))].sort((a, b) => codepointCompare(String(a), String(b))); }
function compare(left, right) { return codepointCompare(`${left.code}\0${left.identity}`, `${right.code}\0${right.identity}`); }

export async function collectPlanDocExecutionLive({ scope, sourceSha, execGh = runGh }) {
  const records = [];
  for (const record of scope.historical) records.push(await collectRecord({ issueNumber: record.issueNumber, prNumber: record.prNumber, execGh }));
  const associated = parseJson(await execGh(["api", `repos/${REPOSITORY}/commits/${sourceSha}/pulls`]), `sha:${sourceSha}`);
  if (!Array.isArray(associated) || associated.length !== 1 || !Number.isInteger(associated[0]?.number)) throw new AuditIncomplete("ASSOCIATION_AMBIGUOUS", `sha:${sourceSha}`);
  const self = await collectRecord({ issueNumber: scope.self.issueNumber, prNumber: associated[0].number, execGh });
  return { records, self };
}

async function collectRecord({ issueNumber, prNumber, execGh }) {
  const pr = parseJson(await execGh(["api", `repos/${REPOSITORY}/pulls/${prNumber}`]), `pr:${prNumber}`);
  if (pr?.number !== prNumber || pr?.merged !== true || !/^[0-9a-f]{40}$/.test(pr?.merge_commit_sha) || pr?.base?.repo?.full_name !== REPOSITORY || !Number.isInteger(pr?.changed_files) || pr.changed_files < 0 || pr.changed_files > MAX_ITEMS) throw new AuditIncomplete("PROVIDER_MALFORMED", `pr:${prNumber}`);
  const changedFileEntries = await collectPages(`repos/${REPOSITORY}/pulls/${prNumber}/files`, `pr:${prNumber}:files`, execGh, (entry) => typeof entry?.filename === "string" && entry.filename !== "" && (entry.previous_filename == null || (typeof entry.previous_filename === "string" && entry.previous_filename !== "")), (entry) => entry.filename);
  if (changedFileEntries.length !== pr.changed_files) throw new AuditIncomplete("PROVIDER_PARTIAL", `pr:${prNumber}:files`);
  const changedFiles = [...new Set(changedFileEntries.flatMap(({ filename, previous_filename: previousFilename }) => previousFilename == null ? [filename] : [previousFilename, filename]))].sort(codepointCompare);
  const events = await collectPages(`repos/${REPOSITORY}/issues/${issueNumber}/events`, `issue:${issueNumber}:events`, execGh, (entry) => typeof entry?.event === "string", (entry) => JSON.stringify(entry));
  return { issueNumber, prNumber, repository: pr.base.repo.full_name, mergeSha: pr.merge_commit_sha, mergedAt: pr.merged_at, changedFiles, relationText: String(pr.body ?? ""), closedByMerge: events.some((event) => event.event === "closed" && event.commit_id === pr.merge_commit_sha) };
}

async function collectPages(base, identity, execGh, valid, key) {
  const values = []; const seen = new Set();
  for (let page = 1; page <= Math.ceil(MAX_ITEMS / PAGE_SIZE) + 1; page += 1) {
    const pageValues = parseJson(await execGh(["api", `${base}?per_page=${PAGE_SIZE}&page=${page}`]), identity);
    if (!Array.isArray(pageValues) || !pageValues.every(valid)) throw new AuditIncomplete("PROVIDER_MALFORMED", identity);
    for (const value of pageValues) { const identityKey = key(value); if (seen.has(identityKey)) throw new AuditIncomplete("PROVIDER_PARTIAL", identity); seen.add(identityKey); values.push(value); }
    if (values.length > MAX_ITEMS) throw new AuditIncomplete("PROVIDER_PARTIAL", identity);
    if (pageValues.length < PAGE_SIZE) return values;
  }
  throw new AuditIncomplete("PROVIDER_PARTIAL", identity);
}

function parseJson(text, identity) { try { return JSON.parse(text); } catch { throw new AuditIncomplete("PROVIDER_MALFORMED", identity); } }

export function createPlanDocExecutionReport({ scope, scopeText, sourceSha, observedAt, live = null, findings = [], incomplete = [] }) {
  const normalizedIncomplete = incomplete.map(sanitizeIncomplete).sort(compareIncomplete);
  const records = live == null ? [] : [...live.records.map((record) => reportRecord("HISTORICAL", record)), reportRecord("SELF", live.self)].sort((a, b) => a.prNumber - b.prNumber);
  const sortedFindings = [...findings].sort(compare);
  return { schemaVersion: 1, status: normalizedIncomplete.length === 0 ? "COMPLETE" : "AUDIT_INCOMPLETE", observedAt, inputs: { sourceSha, scopeSha256: sha256(scopeText), executionRepository: REPOSITORY }, summary: { records: records.length, findings: sortedFindings.length, incomplete: normalizedIncomplete.length }, records, findings: sortedFindings, incomplete: normalizedIncomplete };
}
function reportRecord(kind, record) { return { kind, issueNumber: record.issueNumber, prNumber: record.prNumber, repository: record.repository, mergeSha: record.mergeSha, changedFiles: [...record.changedFiles].sort(codepointCompare) }; }
function sanitizeIncomplete({ stage, code, affectedIdentity }) { return { stage: String(stage).replace(/[^a-z0-9-]/g, "-").replace(/^-+|-+$/g, "") || "unknown", code: String(code).replace(/[^A-Z0-9_]/g, "_"), affectedIdentity: String(affectedIdentity).replace(/[^A-Za-z0-9:._/-]/g, "_") }; }
function compareIncomplete(a, b) { return codepointCompare(`${a.stage}\0${a.code}\0${a.affectedIdentity}`, `${b.stage}\0${b.code}\0${b.affectedIdentity}`); }
function sha256(value) { return createHash("sha256").update(value).digest("hex"); }

export async function runGh(args, execute = execFileAsync) {
  if (!Array.isArray(args) || args.length !== 2 || args[0] !== "api" || typeof args[1] !== "string" || !new RegExp(`^repos/${REPOSITORY}/(?:pulls/[1-9]\\d*(?:/files)?|issues/[1-9]\\d*/events|commits/[0-9a-f]{40}/pulls)(?:\\?|$)`).test(args[1])) throw new Error("gh read-only allowlist violation");
  const { stdout } = await execute("gh", args, { encoding: "utf8", timeout: GH_TIMEOUT_MS, killSignal: "SIGTERM", maxBuffer: GH_MAX_BUFFER });
  return stdout;
}

export function parseArguments(argv) {
  const names = { "--scope": "scopePath", "--scope-schema": "scopeSchemaPath", "--report-schema": "reportSchemaPath", "--source-sha": "sourceSha", "--observed-at": "observedAt", "--output": "outputPath" }; const values = {};
  for (let index = 0; index < argv.length; index += 1) { const key = names[argv[index]]; const value = argv[++index]; if (key == null || value == null || value.startsWith("--") || values[key] != null) throw new Error("unsupported or duplicate argument"); values[key] = value; }
  if (Object.keys(values).length !== Object.keys(names).length || !/^[0-9a-f]{40}$/.test(values.sourceSha) || new Date(values.observedAt).toISOString() !== values.observedAt) throw new Error("invalid audit arguments"); return values;
}

export async function runAuditCli({ argv, collectLive = collectPlanDocExecutionLive, read = readFile, openFile = open } = {}) {
  let args; let scope = { executionRepository: REPOSITORY }; let scopeText = "{}"; let report; let exitCode = 2;
  try {
    args = parseArguments(argv); [scopeText] = await Promise.all([read(args.scopePath, "utf8")]); scope = JSON.parse(scopeText);
    const [scopeSchemaText, reportSchemaText] = await Promise.all([read(args.scopeSchemaPath, "utf8"), read(args.reportSchemaPath, "utf8")]);
    const scopeErrors = [...validateSchema(JSON.parse(scopeSchemaText), scope).errors, ...validatePlanDocExecutionScope(scope)]; if (scopeErrors.length !== 0) throw new AuditIncomplete("SCOPE_INVALID", "scope");
    const live = await collectLive({ scope, sourceSha: args.sourceSha }); const findings = auditPlanDocExecution({ scope, sourceSha: args.sourceSha, live }); report = createPlanDocExecutionReport({ scope, scopeText, sourceSha: args.sourceSha, observedAt: args.observedAt, live, findings });
    if (!validateSchema(JSON.parse(reportSchemaText), report).ok) throw new AuditIncomplete("REPORT_INVALID", "report"); exitCode = findings.length === 0 ? 0 : 1;
  } catch (error) { const incomplete = error instanceof AuditIncomplete ? [{ stage: "github", code: error.code, affectedIdentity: error.identity }] : [{ stage: "runner", code: "AUDIT_FAILURE", affectedIdentity: "audit" }]; if (args != null) report = createPlanDocExecutionReport({ scope, scopeText, sourceSha: args.sourceSha, observedAt: args.observedAt, incomplete }); }
  if (args == null || report == null) return { exitCode: 2, report: null, outputWritten: false };
  try { const handle = await openFile(args.outputPath, "wx"); try { await handle.writeFile(`${JSON.stringify(report)}\n`); } finally { await handle.close(); } } catch { return { exitCode: 2, report: null, outputWritten: false }; }
  return { exitCode, report, outputWritten: true };
}
async function main() { process.exitCode = (await runAuditCli({ argv: process.argv.slice(2) })).exitCode; }
if (isMainModule(import.meta.url)) await main();
