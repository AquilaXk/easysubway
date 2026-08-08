#!/usr/bin/env node
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { lstat, open, readFile, realpath } from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { promisify } from "node:util";
import { isMainModule } from "../lib/is-main-module.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { validateAmendments, validateLedger } from "./issue-migration-ledger.mjs";

const REPOSITORIES = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
const REFERENCE_CLASSES = ["ARTIFACT_IMMUTABLE_REFERENCE", "EXTERNAL_INPUT_PENDING_REFERENCE", "ISSUE_CURRENT_OWNER", "ISSUE_NONCLOSING_DEPENDENCY", "ISSUE_PARENT_OR_COORDINATOR", "ISSUE_TERMINAL_IMPLEMENTATION", "PATH_CANONICAL_CURRENT", "PATH_HISTORICAL_OR_SUPERSEDED", "PR_EVIDENCE_ONLY", "PR_IMPLEMENTATION"];
const GH_TIMEOUT_MS = 30_000;
const GH_MAX_BUFFER = 64 * 1024 * 1024;
const PLAN_OWNERS = new Set(["PLAN-DOC", "PLAN-REPO", "PLAN-JOURNEY"]);
const BARE_REFERENCE_EXTENSIONS = new Set([".json", ".md", ".yaml", ".yml"]);
const QUALIFIED_REPOSITORIES = new Map([
  ["Hub", "AquilaXk/easysubway"], ["Data", "AquilaXk/easysubway-data"],
  ["Backend", "AquilaXk/easysubway-backend"], ["Mobile", "AquilaXk/easysubway-mobile"],
  ["Platform", "AquilaXk/easysubway-platform"],
]);
const execFileAsync = promisify(execFile);

export function parseArguments(argv) {
  const names = { "--scope": "scopePath", "--repository-root": "repositoryRoot", "--source-sha": "sourceSha", "--ledger": "ledgerPath", "--amendments": "amendmentsPath", "--observed-at": "observedAt", "--output": "outputPath" };
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = names[argv[index]];
    const value = argv[++index];
    if (key === undefined || value === undefined || value.startsWith("--") || values[key] !== undefined) throw new Error("unsupported or duplicate argument");
    values[key] = value;
  }
  if (Object.keys(values).length !== Object.keys(names).length) throw new Error("all audit arguments are required");
  if (!/^[0-9a-f]{40}$/.test(values.sourceSha)) throw new Error("source-sha must be 40 lowercase hex");
  if (canonicalUtc(values.observedAt) !== values.observedAt) throw new Error("observed-at must be canonical UTC milliseconds");
  return values;
}

export function canonicalUtc(value) {
  if (typeof value !== "string" || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value)) return null;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) && date.toISOString() === value ? value : null;
}

export function validateScope(scope) {
  const errors = [];
  const repositories = scope?.repositories;
  if (!Array.isArray(repositories) || repositories.length !== REPOSITORIES.length) return ["repositories must contain exactly five entries"];
  const names = repositories.map(({ repository }) => repository);
  if (JSON.stringify(names) !== JSON.stringify(REPOSITORIES)) errors.push("repositories must be codepoint sorted exact inventory");
  for (const entry of repositories) {
    if (!Array.isArray(entry?.trackedDiscoveryRoots) || entry.trackedDiscoveryRoots.length === 0) errors.push(`${entry?.repository}: trackedDiscoveryRoots required`);
    for (const root of entry?.trackedDiscoveryRoots ?? []) if (!safeRepositoryPath(root)) errors.push(`${entry.repository}: unsafe discovery root`);
  }
  const classes = scope?.referenceClasses;
  if (!Array.isArray(classes) || JSON.stringify(classes) !== JSON.stringify(REFERENCE_CLASSES)) errors.push("referenceClasses must be exact codepoint sorted inventory");
  const classification = scope?.contentClassification;
  if (scope?.schemaVersion !== 2) errors.push("schemaVersion must be 2");
  if (JSON.stringify(classification?.knownBinaryExtensions) !== JSON.stringify([".gz", ".png"]) || JSON.stringify(classification?.bareReferenceExtensions) !== JSON.stringify([...BARE_REFERENCE_EXTENSIONS])) errors.push("contentClassification must be exact known binary and bare reference extension inventories");
  return errors;
}

export function safeRepositoryPath(path) {
  return typeof path === "string" && path !== "" && !isAbsolute(path) && !path.split("/").includes("..") && !path.includes("\\") && !path.startsWith("./");
}

export function resolveLatestEffectiveRecord({ ledger, amendments, sourceIssue }) {
  const snapshot = (ledger?.issues ?? []).find((entry) => entry.sourceIssue === sourceIssue);
  const amendment = (amendments?.amendments ?? []).find((entry) => entry.sourceIssue === sourceIssue);
  if (snapshot != null && amendment != null) throw new Error(`source issue ${sourceIssue} is duplicated`);
  const entry = amendment ?? snapshot;
  if (entry == null) return null;
  const origin = amendment == null ? "snapshot" : "amendments";
  if (entry.disposition === "TRANSFER") {
    const target = parseIssueUrl(entry.targetUrl);
    return { origin, disposition: "TRANSFER", canonicalRepository: target?.repository ?? "AquilaXk/easysubway", canonicalNumber: target?.number ?? sourceIssue, pendingTransfer: target == null };
  }
  if (entry.disposition === "SPLIT_CHILDREN") return {
    origin, disposition: "SPLIT_CHILDREN", canonicalRepository: "AquilaXk/easysubway", canonicalNumber: sourceIssue,
    childIssues: Object.entries(entry.childIssueUrls ?? {}).map(([repository, url]) => ({ repository, ...parseIssueUrl(url) })).sort(compareSerializable), pendingTransfer: false,
  };
  return { origin, disposition: "KEEP_HUB", canonicalRepository: "AquilaXk/easysubway", canonicalNumber: sourceIssue, pendingTransfer: false };
}

export function resolveSplitChildRecord({ ledger, target }) {
  for (const entry of ledger?.issues ?? []) {
    if (entry.disposition !== "SPLIT_CHILDREN") continue;
    const effective = resolveLatestEffectiveRecord({ ledger, amendments: { amendments: [] }, sourceIssue: entry.sourceIssue });
    if (effective?.childIssues?.some((child) => child.repository === target.repository && child.number === target.number)) return effective;
  }
  return null;
}

export function parseIssueUrl(value) {
  const match = typeof value === "string" ? /^https:\/\/github\.com\/([^/]+\/[^/]+)\/issues\/([1-9]\d*)$/.exec(value) : null;
  return match == null ? null : { repository: match[1], number: Number(match[2]) };
}

export function createReport({ observedAt, sourceSha, scopeText, ledgerText, amendmentsText, repositories = [], findings = [], incomplete = [], discovered = 0, validated = 0 }) {
  const sortedFindings = [...findings].sort(compareSerializable);
  const sortedIncomplete = [...incomplete].map(sanitizeIncomplete).sort(compareSerializable);
  return {
    schemaVersion: 2, status: sortedIncomplete.length === 0 ? "COMPLETE" : "AUDIT_INCOMPLETE", observedAt,
    inputs: {
      repositories: [...repositories].sort((a, b) => codepointCompare(a.repository, b.repository)),
      migration: { ledgerSha256: sha256(ledgerText), amendmentsSha256: sha256(amendmentsText) }, scopeSha256: sha256(scopeText), sourceSha,
    },
    summary: { discovered, validated, finding: sortedFindings.length, incomplete: sortedIncomplete.length },
    findings: sortedFindings, incomplete: sortedIncomplete,
  };
}

export function validateReport(report) {
  const errors = [];
  if (canonicalUtc(report?.observedAt) !== report?.observedAt) errors.push("observedAt must be canonical UTC milliseconds");
  const repositories = report?.inputs?.repositories ?? [];
  if (repositories.map(({ repository }) => repository).join("\0") !== [...repositories].map(({ repository }) => repository).sort((a, b) => codepointCompare(a, b)).join("\0")) errors.push("repositories must be sorted");
  if (new Set(repositories.map(({ repository }) => repository)).size !== repositories.length) errors.push("repositories must be unique");
  for (const list of [report?.findings, report?.incomplete]) {
    if (!Array.isArray(list) || list.some((item, index) => index > 0 && compareSerializable(list[index - 1], item) >= 0)) errors.push("report arrays must be sorted unique");
  }
  return errors;
}

export function sanitizeIncomplete({ stage, code, affectedIdentity }) {
  return { stage: String(stage ?? "unknown").replace(/[^A-Za-z0-9_.:-]/g, "_"), code: String(code ?? "UNKNOWN").replace(/[^A-Za-z0-9_.:-]/g, "_"), affectedIdentity: String(affectedIdentity ?? "unknown").replace(/[^A-Za-z0-9_./:-]/g, "_") };
}

export async function execGh(args, execute = execFileAsync) {
  const allowed = Array.isArray(args) && args.length === 2 && args[0] === "api" && typeof args[1] === "string" && /^repos\/AquilaXk\/easysubway(?:-(?:backend|data|mobile|platform))?(?:\/|$)/.test(args[1]);
  if (!allowed) throw new Error("gh argument is not read-only allowlisted");
  const { stdout } = await execute("gh", args, { encoding: "utf8", timeout: GH_TIMEOUT_MS, killSignal: "SIGTERM", maxBuffer: GH_MAX_BUFFER });
  return stdout;
}

export async function discoverRepository({ repository, roots, contentClassification = { knownBinaryExtensions: [] }, execGh: runGh }) {
  const details = parseJson(await runGh(["api", `repos/${repository}`]));
  const branch = details.default_branch;
  if (typeof branch !== "string" || branch === "") throw new Error("invalid default branch");
  const ref = parseJson(await runGh(["api", `repos/${repository}/git/ref/heads/${branch}`]));
  const sha = ref?.object?.sha;
  if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error("invalid ref sha");
  const tree = parseJson(await runGh(["api", `repos/${repository}/git/trees/${sha}?recursive=1`]));
  if (!Array.isArray(tree?.tree) || tree.truncated === true) throw new Error("invalid or truncated Git tree");
  const selected = [];
  for (const root of roots) {
    const matched = tree.tree.filter((entry) => entry.path === root || entry.path.startsWith(`${root}/`));
    if (matched.length === 0) throw new Error("missing configured root");
    const blobs = matched.filter((entry) => entry.type === "blob" && entry.mode !== "120000");
    if (blobs.length === 0 || matched.some((entry) => entry.type === "commit" || entry.mode === "160000" || entry.mode === "120000")) throw new Error("configured root has non-blob entry");
    selected.push(...blobs);
  }
  if (selected.some((entry) => !/^[0-9a-f]{40}$/.test(entry.sha))) throw new Error("invalid selected blob");
  return { repository, defaultBranch: branch, gitSha: sha, selected: [...new Map(selected.map(({ path, sha: blobSha }) => [path, { path, blobSha, contentClass: contentClassForPath(path, contentClassification.knownBinaryExtensions) }])).values()].sort((a, b) => codepointCompare(a.path, b.path)) };
}

export async function collectCurrentInputs({ scope, execGh: runGh }) {
  const repositories = [];
  const incomplete = [];
  for (const entry of scope.repositories) {
    try { repositories.push(await discoverRepository({ repository: entry.repository, roots: entry.trackedDiscoveryRoots, contentClassification: scope.contentClassification, execGh: runGh })); }
    catch (error) { incomplete.push({ stage: "github", code: errorCode(error), affectedIdentity: entry.repository }); }
  }
  return { repositories, incomplete };
}

export function extractReferences(text, source) {
  const normalizedSource = source?.kind == null && typeof source?.path === "string" && typeof source?.blobSha === "string"
    ? { kind: "PATH", ...source } : source;
  const { repository } = normalizedSource;
  const references = [];
  for (const line of String(text).split(/\r?\n/)) {
    const markers = parseMarkers(line);
    const occupied = [];
    const add = (start, end, locator, target) => {
      if (occupied.some(([left, right]) => start < right && end > left)) return;
      occupied.push([start, end]);
      references.push({ source: { ...normalizedSource, locator }, target, markers, displayedTitle: displayedTitleFor(line, locator, target) });
    };
    const parseUrl = (value) => {
      const match = /^https:\/\/github\.com\/([^/]+\/[^/]+)\/(issues|pull)\/([1-9]\d*)(?![A-Za-z0-9_])(?:#[A-Za-z0-9_.:-]+)?$/.exec(value);
      return match == null ? null : { repository: match[1], type: match[2] === "pull" ? "PR" : "ISSUE", number: Number(match[3]) };
    };
    for (const match of line.matchAll(/\[[^\]]*\]\((https:\/\/github\.com\/[^\s)]+)\)/g)) {
      const locator = match[1]; const target = parseUrl(locator);
      if (target != null) add(match.index, match.index + match[0].length, locator, target);
    }
    for (const match of line.matchAll(/https:\/\/github\.com\/[^\s)]+/g)) {
      const locator = match[0].replace(/[.,;:]+$/, "");
      const target = parseUrl(locator);
      if (target != null) add(match.index, match.index + match[0].length, locator, target);
    }
    for (const match of line.matchAll(/\b(?:(Hub|Data|Backend|Mobile|Platform)\s+(?:(Issue|PR)\s+)?|(Issue|PR)\s+)#([1-9]\d*)(?![A-Za-z0-9_])/g)) {
      const kind = match[2] ?? match[3] ?? "Issue";
      add(match.index, match.index + match[0].length, match[0], { repository: match[1] == null ? repository : QUALIFIED_REPOSITORIES.get(match[1]), type: kind === "PR" ? "PR" : "ISSUE", number: Number(match[4]) });
    }
    if (allowsBareReferences(normalizedSource) || Object.keys(markers).length > 0) {
      for (const match of line.matchAll(/(?<![A-Za-z0-9_/])#([1-9]\d*)(?![A-Za-z0-9_])/g)) {
        add(match.index, match.index + match[0].length, match[0], { repository, type: "ISSUE_OR_PR", number: Number(match[1]) });
      }
    }
  }
  return references;
}

function contentClassForPath(path, knownBinaryExtensions) {
  return (knownBinaryExtensions ?? []).some((extension) => path.endsWith(extension)) ? "NON_REFERENCE_BINARY" : "AUDITABLE_TEXT";
}

function allowsBareReferences(source) {
  if (["ISSUE", "PR"].includes(source?.kind)) return true;
  const path = source?.kind === "PATH" ? source.path : null;
  return typeof path === "string" && [...BARE_REFERENCE_EXTENSIONS].some((extension) => path.endsWith(extension));
}

export function parseMarkers(line) {
  const values = {};
  for (const [, key, value] of String(line).matchAll(/\[(REFERENCE_CLASS|STATE|STATE_REASON|PRIORITY|MILESTONE|PLAN_OWNER|PARENT_STATE|COPIED_STATE|NO_FALLBACK_OWNER|REVIEW_FALLBACK):([^\]]+)\]/g)) {
    if (values[key] !== undefined) values[key] = "__OVERLAP__";
    else values[key] = value;
  }
  return values;
}

export function classifyImmutableLocator(locator, referenceClass = "ARTIFACT_IMMUTABLE_REFERENCE") {
  const value = String(locator);
  const immutable = parseGitBlobLocator(value) != null || isOciDigest(value);
  if (immutable) return null;
  if (referenceClass === "ARTIFACT_IMMUTABLE_REFERENCE") return { code: "ARTIFACT_LOCATOR_MUTABLE_OR_UNVERIFIED", referenceClass, reason: "artifact locator is not an immutable standard blob or OCI digest" };
  if (/github\.com\/[^/]+\/[^/]+\/(?:blob|git\/blobs)\//.test(value) || /\/(?:main|raw|refs\/heads|refs\/tags)\//.test(value) || /@(?!sha256:)/.test(value)) return { code: "CANONICAL_PATH_OR_ARTIFACT_DRIFT", referenceClass, reason: "mutable or nonstandard artifact locator" };
  return null;
}

export function extractArtifactFindings(text, source) {
  const findings = [];
  for (const line of String(text).split(/\r?\n/)) {
    const markers = parseMarkers(line);
    const referenceClass = markers.REFERENCE_CLASS;
    if (!["ARTIFACT_IMMUTABLE_REFERENCE", "PATH_CANONICAL_CURRENT", "PATH_HISTORICAL_OR_SUPERSEDED"].includes(referenceClass)) continue;
    const parsedLocator = markerLocatorText(line);
    const locator = parsedLocator === "" ? line.trim() : parsedLocator;
    const ownerInvalid = markers.PLAN_OWNER !== undefined && !PLAN_OWNERS.has(markers.PLAN_OWNER);
    const valid = referenceClass === "ARTIFACT_IMMUTABLE_REFERENCE" ? parseGitBlobLocator(parsedLocator) != null || isOciDigest(parsedLocator) : parseGitBlobLocator(parsedLocator) != null;
    if (ownerInvalid) findings.push({ code: "PLAN_OWNER_OVERLAP", referenceClass, source: { ...source, locator }, target: { repository: source.repository, type: "ARTIFACT", locator }, referenced: null, latestEffective: null, directOwner: null, consumerRoute: null, reason: "PLAN_OWNER must be an exact known plan route" });
    else if (!valid) {
      const result = classifyImmutableLocator(locator, referenceClass);
      findings.push({ ...(result ?? { code: "CANONICAL_PATH_OR_ARTIFACT_DRIFT", referenceClass, reason: "path marker requires an exact immutable GitHub blob locator" }), source: { ...source, locator }, target: { repository: parseArtifactRepository(locator) ?? source.repository, type: "ARTIFACT", locator }, referenced: null, latestEffective: null, directOwner: null, consumerRoute: consumerRouteFor(markers.PLAN_OWNER) });
    }
  }
  return findings;
}

export function extractCanonicalPathFindings(text, source, repositories) {
  const findings = [];
  for (const line of String(text).split(/\r?\n/)) {
    const markers = parseMarkers(line);
    if (markers.REFERENCE_CLASS !== "PATH_CANONICAL_CURRENT" || (markers.PLAN_OWNER !== undefined && !PLAN_OWNERS.has(markers.PLAN_OWNER))) continue;
    const locator = markerLocatorText(line);
    const match = parseGitBlobLocator(locator);
    if (match == null) continue;
    const { repository, sha, path } = match;
    const input = repositories.find((candidate) => candidate.repository === repository);
    const selected = input?.selected.find((candidate) => candidate.path === path);
    if (input == null || sha !== input.gitSha || selected == null) findings.push({ code: "CANONICAL_PATH_OR_ARTIFACT_DRIFT", referenceClass: "PATH_CANONICAL_CURRENT", source: { ...source, locator }, target: { repository, type: "ARTIFACT", locator, path, blobSha: selected?.blobSha ?? null }, referenced: null, latestEffective: null, directOwner: null, consumerRoute: consumerRouteFor(markers.PLAN_OWNER), reason: "canonical path must identify a collected current head, selected path, and tree blob" });
  }
  return findings;
}

function displayedTitleFor(line, locator, target) {
  const escaped = locator.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const expression = new RegExp(`\\[${escapeRegExp(target.repository)}#${target.number} — ([^\\]]+)\\]\\(${escaped}\\)`);
  return expression.exec(line)?.[1] ?? null;
}

export function classifyReference(reference, { ledger, amendments, openHubIssues = new Set(), referenceClass = "ISSUE_NONCLOSING_DEPENDENCY", item = null }) {
  const { source, target } = reference;
  const explicitClass = REFERENCE_CLASSES.includes(reference.markers?.REFERENCE_CLASS);
  referenceClass = explicitClass ? reference.markers.REFERENCE_CLASS : defaultReferenceClass(reference, referenceClass);
  if (reference.markers?.REFERENCE_CLASS !== undefined && !explicitClass) return makeFinding("UNKNOWN_OR_INVALID", referenceClass, reference, item, null, "REFERENCE_CLASS is unknown or overlapping");
  if (reference.markers?.PLAN_OWNER !== undefined && !PLAN_OWNERS.has(reference.markers.PLAN_OWNER)) return makeFinding("PLAN_OWNER_OVERLAP", referenceClass, reference, item, null, "PLAN_OWNER must be an exact known plan route");
  if (explicitClass && reference.markers?.PLAN_OWNER === "__OVERLAP__") return makeFinding("PLAN_OWNER_OVERLAP", referenceClass, reference, item, null, "multiple plan owner markers");
  if (item == null) return makeFinding("BROKEN_OR_UNRESOLVED_REFERENCE", referenceClass, reference, null, null, "referenced item is missing");
  if (target.type === "ISSUE_OR_PR") target.type = item.type;
  if (item.type !== target.type) return makeFinding("ISSUE_PR_TYPE_CONFUSION", referenceClass, reference, item, null, "referenced item type differs");
  if (explicitClass && reference.displayedTitle != null && reference.displayedTitle !== item.title) return makeFinding("DISPLAYED_TITLE_DRIFT", referenceClass, reference, item, null, "displayed title differs");
  for (const [marker, field, code] of [["STATE", "state", "DIRECT_OWNER_BODY_STATE_DRIFT"], ["STATE_REASON", "stateReason", "DIRECT_OWNER_BODY_STATE_DRIFT"], ["PRIORITY", "priority", "PRIORITY_LABEL_MILESTONE_DRIFT"], ["MILESTONE", "milestone", "PRIORITY_LABEL_MILESTONE_DRIFT"]]) {
    const expected = reference.markers?.[marker];
    if (expected !== undefined && expected !== "__OVERLAP__" && String(item[field] ?? "null") !== expected) return makeFinding(code, referenceClass, reference, item, null, `${marker} differs`);
  }
  if (explicitClass && ((referenceClass.startsWith("PR_") && item.type !== "PR") || (referenceClass.startsWith("ISSUE_") && item.type !== "ISSUE"))) return makeFinding("ISSUE_PR_TYPE_CONFUSION", referenceClass, reference, item, null, "reference class and target type differ");
  if (["PR_EVIDENCE_ONLY", "PATH_HISTORICAL_OR_SUPERSEDED"].includes(referenceClass)) return null;
  if (explicitClass && item.state !== "OPEN" && reference.markers?.STATE !== "CLOSED") return makeFinding("CLOSED_NOT_PLANNED_USED_AS_ACTIVE", referenceClass, reference, item, null, "closed item is used as active reference");
  if (reference.markers?.PARENT_STATE !== undefined && reference.markers.PARENT_STATE !== "__OVERLAP__" && item.state !== reference.markers.PARENT_STATE) return makeFinding("PARENT_CHILD_STATE_DRIFT", referenceClass, reference, item, null, "PARENT_STATE differs");
  if (reference.markers?.COPIED_STATE !== undefined && reference.markers.COPIED_STATE !== "__OVERLAP__" && item.state !== reference.markers.COPIED_STATE) return makeFinding("PARENT_CHILD_STATE_DRIFT", referenceClass, reference, item, null, "COPIED_STATE differs");
  if (!ownerClass(referenceClass) || target.type !== "ISSUE") return null;
  const effective = target.repository === "AquilaXk/easysubway"
    ? resolveLatestEffectiveRecord({ ledger, amendments, sourceIssue: target.number })
    : resolveSplitChildRecord({ ledger, target });
  if (target.repository === "AquilaXk/easysubway" && openHubIssues.has(target.number) && effective == null) {
    return makeFinding("UNKNOWN_OR_INVALID", referenceClass, reference, item, null, "open Hub issue is absent from snapshot and amendments");
  }
  if (effective?.pendingTransfer && ["ISSUE_TERMINAL_IMPLEMENTATION", "ISSUE_CURRENT_OWNER"].includes(referenceClass)) return makeFinding("WRONG_REPOSITORY_OR_OWNER", referenceClass, reference, item, effective, "pending transfer cannot satisfy terminal/current-owner claim");
  if (reference.markers?.NO_FALLBACK_OWNER !== undefined && reference.markers.NO_FALLBACK_OWNER !== "__OVERLAP__" && reference.markers.NO_FALLBACK_OWNER !== (effective?.canonicalRepository ?? target.repository)) return makeFinding("NO_FALLBACK_OWNER_OR_POLICY_DRIFT", referenceClass, reference, item, effective, "NO_FALLBACK_OWNER differs from canonical owner");
  if (reference.markers?.REVIEW_FALLBACK !== undefined && !["CODERABBIT", "CODEX_CLI_FALLBACK"].includes(reference.markers.REVIEW_FALLBACK)) return makeFinding("REVIEW_FALLBACK_CLASSIFICATION_DRIFT", referenceClass, reference, item, effective, "REVIEW_FALLBACK is not an exact supported class");
  if (effective?.disposition === "SPLIT_CHILDREN") {
    const isParent = target.repository === effective.canonicalRepository && target.number === effective.canonicalNumber;
    const isChild = effective.childIssues.some((child) => child.repository === target.repository && child.number === target.number);
    if (["ISSUE_PARENT_OR_COORDINATOR"].includes(referenceClass) && !isParent) return makeFinding("WRONG_REPOSITORY_OR_OWNER", referenceClass, reference, item, effective, "split parent/coordinator must use the Hub parent issue");
    if (["ISSUE_CURRENT_OWNER", "ISSUE_TERMINAL_IMPLEMENTATION"].includes(referenceClass) && !isChild) return makeFinding("WRONG_REPOSITORY_OR_OWNER", referenceClass, reference, item, effective, "split current/terminal owner must use an exact child issue");
    if (isParent || isChild) return null;
    return makeFinding("WRONG_REPOSITORY_OR_OWNER", referenceClass, reference, item, effective, "reference is not a split parent or exact child issue");
  }
  if (effective != null && (effective.canonicalRepository !== target.repository || effective.canonicalNumber !== target.number)) {
    return makeFinding("WRONG_REPOSITORY_OR_OWNER", referenceClass, reference, item, effective, "reference is not latest-effective canonical owner");
  }
  return null;
}

function defaultReferenceClass(reference, fallback) {
  return reference.source?.kind === "PATH" && allowsBareReferences(reference.source) && reference.source.locator?.startsWith("#")
    ? "ISSUE_CURRENT_OWNER" : fallback;
}

function ownerClass(referenceClass) {
  return ["ISSUE_CURRENT_OWNER", "ISSUE_TERMINAL_IMPLEMENTATION", "ISSUE_PARENT_OR_COORDINATOR"].includes(referenceClass);
}

function makeFinding(code, referenceClass, reference, referenced, latestEffective, reason) {
  const splitChild = latestEffective?.disposition === "SPLIT_CHILDREN"
    && latestEffective.childIssues.some((child) => child.repository === reference.target.repository && child.number === reference.target.number);
  return { code, referenceClass, source: reference.source, target: reference.target, referenced: metadataView(referenced), latestEffective: latestEffective ?? null, directOwner: splitChild ? reference.target.repository : latestEffective?.canonicalRepository ?? reference.target.repository, consumerRoute: consumerRouteFor(reference.markers?.PLAN_OWNER), reason };
}

function metadataView(item) {
  if (item == null) return null;
  const { repository, number, type, title, state, stateReason, labels, priority, milestone, parentOwner } = item;
  return { repository, number, type, title, state, stateReason, labels, priority, milestone, parentOwner };
}

function consumerRouteFor(value) { return PLAN_OWNERS.has(value) ? value : null; }

function markerLocatorText(line) {
  return String(line).replace(/\[(?:REFERENCE_CLASS|STATE|STATE_REASON|PRIORITY|MILESTONE|PLAN_OWNER|PARENT_STATE|COPIED_STATE|NO_FALLBACK_OWNER|REVIEW_FALLBACK):[^\]]*\]/g, "").trim();
}
function parseGitBlobLocator(value) {
  const match = /^https:\/\/github\.com\/([^/\s]+\/[^/\s]+)\/blob\/([0-9a-f]{40})\/([^\s/]+(?:\/[^\s/]+)*)$/.exec(String(value));
  if (match == null || match[3].split("/").some((segment) => segment === "." || segment === "..")) return null;
  return { repository: match[1], sha: match[2], path: match[3] };
}
function isOciDigest(value) { return /^[a-z0-9][a-z0-9._/-]*@sha256:[0-9a-f]{64}$/.test(String(value)); }
function parseArtifactRepository(value) { return /^https:\/\/github\.com\/([^/]+\/[^/]+)\//.exec(String(value))?.[1] ?? null; }

export function normalizeItem(repository, item) {
  if (!Number.isInteger(item?.number) || typeof item?.title !== "string" || !["open", "closed"].includes(item?.state)) throw new Error("invalid item metadata");
  const labels = (item.labels ?? []).map((label) => typeof label === "string" ? label : label?.name).filter((label) => typeof label === "string").sort(codepointCompare);
  return { repository, number: item.number, type: item.pull_request == null ? "ISSUE" : "PR", title: item.title, body: typeof item.body === "string" ? item.body : "", state: item.state.toUpperCase(), stateReason: item.state_reason ?? null, labels, priority: labels.map((label) => /^p[0-3]$/i.test(label) ? label.toUpperCase() : label).find((label) => /^P[0-3]$/.test(label)) ?? null, milestone: item.milestone?.title ?? null, parentOwner: item.parent_issue?.url ?? null };
}

export async function readItem(repository, number, runGh) {
  try { return normalizeItem(repository, parseJson(await runGh(["api", `repos/${repository}/issues/${number}`]))); }
  catch (error) { if (error?.status === 404 || error?.code === 404 || /HTTP 404/.test(String(error?.stderr ?? ""))) return null; throw error; }
}

export async function listOpenItems(repository, runGh) {
  const items = [];
  for (let page = 1; page <= 10; page += 1) {
    const pageItems = parseJson(await runGh(["api", `repos/${repository}/issues?state=open&per_page=100&page=${page}`]));
    if (!Array.isArray(pageItems)) throw new Error("invalid GitHub list response");
    items.push(...pageItems);
    if (pageItems.length < 100) return items;
  }
  throw new Error("GitHub list is truncated");
}

export async function readBlob(repository, blobSha, runGh) {
  const blob = parseJson(await runGh(["api", `repos/${repository}/git/blobs/${blobSha}`]));
  if (blob?.encoding !== "base64" || typeof blob.content !== "string") throw new Error("invalid blob response");
  const canonical = blob.content.replace(/\s/g, "");
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(canonical)) throw new Error("invalid base64 blob");
  const bytes = Buffer.from(canonical, "base64");
  if (bytes.toString("base64") !== canonical) throw new Error("noncanonical base64 blob");
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

export async function auditReferences({ scope, ledger, amendments, repositories, execGh: runGh }) {
  const findings = [];
  const incomplete = [];
  const metadata = new Map();
  const lookup = new Map();
  const readCachedItem = async (repository, number) => {
    const key = `${repository}#${number}`;
    if (!lookup.has(key)) lookup.set(key, readItem(repository, number, runGh));
    return lookup.get(key);
  };
  const hubOpenIssues = new Set();
  try {
    for (const repository of REPOSITORIES) {
      const items = await listOpenItems(repository, runGh);
      for (const item of items) {
        const normalized = normalizeItem(repository, item);
        metadata.set(`${repository}#${normalized.number}`, normalized);
        if (repository === "AquilaXk/easysubway" && normalized.type === "ISSUE") hubOpenIssues.add(normalized.number);
      }
    }
  } catch (error) { return { findings, incomplete: [{ stage: "github-metadata", code: errorCode(error), affectedIdentity: "open-items" }], discovered: 0, validated: 0 }; }
  for (const number of [...hubOpenIssues].sort((left, right) => left - right)) {
    const effective = resolveLatestEffectiveRecord({ ledger, amendments, sourceIssue: number });
    if (effective == null) {
      const item = metadata.get(`AquilaXk/easysubway#${number}`);
      const reference = { source: itemSource(item, "inventory"), target: { repository: item.repository, type: "ISSUE", number }, markers: { REFERENCE_CLASS: "ISSUE_CURRENT_OWNER" }, displayedTitle: null };
      findings.push(makeFinding("UNKNOWN_OR_INVALID", "ISSUE_CURRENT_OWNER", reference, item, null, "open Hub issue is absent from snapshot and amendments"));
    }
  }
  let discovered = 0;
  let validated = 0;
  const planOwners = new Map();
  const collectPlanOwner = (reference) => {
    const owner = reference.markers?.PLAN_OWNER;
    if (owner == null || owner === "__OVERLAP__") return;
    const effective = reference.target.type !== "ISSUE" ? null
      : reference.target.repository === "AquilaXk/easysubway"
        ? resolveLatestEffectiveRecord({ ledger, amendments, sourceIssue: reference.target.number })
        : resolveSplitChildRecord({ ledger, target: reference.target });
    const identity = effective == null ? `${reference.target.repository}#${reference.target.number}` : `${effective.canonicalRepository}#${effective.canonicalNumber}`;
    const owners = planOwners.get(identity) ?? new Map();
    owners.set(owner, reference); planOwners.set(identity, owners);
  };
  for (const input of repositories) {
    for (const selected of input.selected) {
      if (selected.contentClass === "NON_REFERENCE_BINARY") continue;
      try {
        const text = await readBlob(input.repository, selected.blobSha, runGh);
        findings.push(...extractArtifactFindings(text, { kind: "PATH", repository: input.repository, path: selected.path, blobSha: selected.blobSha }));
        findings.push(...extractCanonicalPathFindings(text, { kind: "PATH", repository: input.repository, path: selected.path, blobSha: selected.blobSha }, repositories));
        for (const reference of extractReferences(text, { repository: input.repository, path: selected.path, blobSha: selected.blobSha })) {
          discovered += 1;
          const key = `${reference.target.repository}#${reference.target.number}`;
          let item = metadata.get(key);
          if (item == null) item = await readCachedItem(reference.target.repository, reference.target.number);
          const finding = classifyReference(reference, { ledger, amendments, openHubIssues: hubOpenIssues, item });
          if (finding != null) findings.push(finding);
          else validated += 1;
          collectPlanOwner(reference);
        }
      } catch (error) {
        incomplete.push({ stage: "reference-discovery", code: errorCode(error), affectedIdentity: `${input.repository}:${input.gitSha ?? "unknown"}:${selected.path}:${selected.blobSha}` });
      }
    }
  }
  for (const item of [...metadata.values()].sort((left, right) => codepointCompare(`${left.repository}#${left.number}`, `${right.repository}#${right.number}`))) {
    for (const [kind, text] of [["title", item.title], ["body", item.body]]) {
      for (const reference of extractReferences(text, itemSource(item, kind))) {
        discovered += 1;
        const target = metadata.get(`${reference.target.repository}#${reference.target.number}`) ?? await readCachedItem(reference.target.repository, reference.target.number);
        const finding = classifyReference(reference, { ledger, amendments, openHubIssues: hubOpenIssues, item: target });
        if (finding != null) findings.push(finding); else validated += 1;
        collectPlanOwner(reference);
      }
    }
  }
  for (const [identity, owners] of planOwners) if (owners.size > 1) {
    const [owner, reference] = [...owners].sort(([left], [right]) => codepointCompare(left, right))[0];
    findings.push(makeFinding("PLAN_OWNER_OVERLAP", reference.markers.REFERENCE_CLASS ?? "ISSUE_NONCLOSING_DEPENDENCY", reference, null, null, `conflicting PLAN_OWNER for ${identity}`));
  }
  return { findings: dedupeFindings(findings), incomplete, discovered, validated };
}

function itemSource(item, locator) {
  return { kind: item.type, repository: item.repository, number: item.number, locator: `https://github.com/${item.repository}/${item.type === "PR" ? "pull" : "issues"}/${item.number}${locator === "title" ? "#title" : locator === "body" ? "#body" : "#inventory"}` };
}

export function dedupeFindings(findings) {
  return [...new Map(findings.map((finding) => [JSON.stringify(finding), finding])).values()].sort(compareSerializable);
}

async function main() {
  let arguments_; let root; let outputPath; let scopeText = ""; let ledgerText = ""; let amendmentsText = "";
  try {
    arguments_ = parseArguments(process.argv.slice(2));
    root = await realpath(resolve(arguments_.repositoryRoot));
    outputPath = await safePath(root, arguments_.outputPath, { output: true });
    const [scopePath, ledgerPath, amendmentsPath] = await Promise.all([safePath(root, arguments_.scopePath), safePath(root, arguments_.ledgerPath), safePath(root, arguments_.amendmentsPath)]);
    [scopeText, ledgerText, amendmentsText] = await Promise.all([
      readFile(scopePath, "utf8"), readFile(ledgerPath, "utf8"), readFile(amendmentsPath, "utf8"),
    ]);
    const [scopeSchemaText, ledgerSchemaText, amendmentSchemaText, reportSchemaText] = await Promise.all([
      readFile(new URL("../../contracts/documentation/reference-audit-scope.schema.json", import.meta.url), "utf8"), readFile(new URL("../../contracts/repository-split-issues.schema.json", import.meta.url), "utf8"), readFile(new URL("../../contracts/repository-split-issue-amendments.schema.json", import.meta.url), "utf8"), readFile(new URL("../../contracts/documentation/reference-audit-report.schema.json", import.meta.url), "utf8"),
    ]);
    const scope = parseJson(scopeText); const ledger = parseJson(ledgerText); const amendments = parseJson(amendmentsText);
    const validation = [...validateSchema(parseJson(scopeSchemaText), scope).errors, ...validateScope(scope), ...validateSchema(parseJson(ledgerSchemaText), ledger).errors, ...validateLedger(ledger), ...validateSchema(parseJson(amendmentSchemaText), amendments).errors, ...validateAmendments(amendments, { ledger })];
    const collected = validation.length === 0 ? await collectCurrentInputs({ scope, execGh }) : { repositories: [], incomplete: validation.map((_, index) => ({ stage: "offline", code: "INVALID_CONTRACT", affectedIdentity: `validation-${index + 1}` })) };
    const hubSha = collected.repositories.find(({ repository }) => repository === "AquilaXk/easysubway")?.gitSha;
    if (hubSha != null && hubSha !== arguments_.sourceSha) collected.incomplete.push({ stage: "source-identity", code: "SOURCE_SHA_MISMATCH", affectedIdentity: "AquilaXk/easysubway" });
    const audit = collected.incomplete.length === 0 ? await auditReferences({ scope, ledger, amendments, repositories: collected.repositories, execGh }) : { findings: [], incomplete: [], discovered: 0, validated: 0 };
    const report = createReport({ observedAt: arguments_.observedAt, sourceSha: arguments_.sourceSha, scopeText, ledgerText, amendmentsText, repositories: collected.repositories, findings: audit.findings, incomplete: [...collected.incomplete, ...audit.incomplete], discovered: audit.discovered, validated: audit.validated });
    const reportValidation = [...validateSchema(parseJson(reportSchemaText), report).errors, ...validateReport(report)];
    if (reportValidation.length) throw new Error("report schema validation failed");
    const output = await open(outputPath, "wx");
    await output.writeFile(`${JSON.stringify(report, null, 2)}\n`); await output.close();
    process.exitCode = report.status === "AUDIT_INCOMPLETE" ? 2 : report.findings.length === 0 ? 0 : 1;
  } catch (error) {
    if (arguments_ != null && root != null && outputPath != null) {
      try {
        const report = createReport({ observedAt: arguments_.observedAt, sourceSha: arguments_.sourceSha, scopeText, ledgerText, amendmentsText, incomplete: [{ stage: "audit", code: errorCode(error), affectedIdentity: "audit-input" }] });
        const output = await open(outputPath, "wx");
        await output.writeFile(`${JSON.stringify(report, null, 2)}\n`); await output.close();
      } catch { /* the valid output boundary itself is unavailable */ }
    }
    console.error(`reference audit was not completed: ${errorCode(error)}`); process.exitCode = 2;
  }
}

async function safePath(root, candidate, { output = false } = {}) {
  if (typeof candidate !== "string" || candidate === "" || isAbsolute(candidate) || candidate.split(/[\\/]/).includes("..")) throw new Error("paths must remain under repository-root");
  const path = resolve(root, candidate);
  if (relative(root, path).startsWith("..")) throw new Error("paths must remain under repository-root");
  const parent = output ? dirname(path) : path;
  const parentReal = await realpath(parent);
  if (parentReal !== root && !parentReal.startsWith(`${root}/`)) throw new Error("path escapes repository-root");
  const segments = relative(root, parent).split("/").filter(Boolean);
  let cursor = root;
  for (const segment of segments) {
    cursor = resolve(cursor, segment);
    if ((await lstat(cursor)).isSymbolicLink()) throw new Error("symlink path component is not allowed");
  }
  if (!output && (await lstat(path)).isSymbolicLink()) throw new Error("symlink input is not allowed");
  return path;
}

function parseJson(value) { return JSON.parse(value); }
function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
function escapeRegExp(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }
function codepointCompare(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
function compareSerializable(a, b) { return codepointCompare(JSON.stringify(a), JSON.stringify(b)); }
function errorCode(error) { return error?.code === "ETIMEDOUT" ? "TIMEOUT" : error?.code === "ENOENT" ? "NOT_FOUND" : "INVALID_OR_UNAVAILABLE"; }

if (isMainModule(import.meta.url)) await main();
