#!/usr/bin/env node
import { existsSync, lstatSync, readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";

const GIT = "/usr/bin/git";
const REPOSITORIES = ["AquilaXk/easysubway", "AquilaXk/easysubway-data", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
const FAMILIES = ["PRODUCT", "ARCHITECTURE", "API_CONTRACT", "DATA_KNOWLEDGE", "ENGINEERING", "QUALITY_TEST", "RELEASE_CHANGE", "OPERATIONS_RELIABILITY", "SECURITY_PRIVACY", "USER_SUPPORT_LEGAL_PUBLIC", "GOVERNANCE_EVIDENCE"];
const SURFACES = ["TRACKED", "PUBLIC", "LOCAL_ONLY", "EXTERNAL"];
const STATUSES = ["PROPOSED", "ACTIVE", "SUPERSEDED", "REVOKED", "HISTORICAL", "INVALIDATED"];
const ENUMS = {
  resourceClass: ["CANONICAL_RESOURCE", "HUMAN_CONTEXT", "EXECUTABLE_COMPANION", "EVIDENCE", "HUMAN_VIEW"], documentationFamily: FAMILIES, sourceSurface: SURFACES, status: STATUSES,
  releaseReachability: ["NONE", "BUILD", "RUNTIME", "DEPLOY", "PUBLIC", "EVIDENCE"], assertionState: ["CURRENTLY_IMPLEMENTED_AND_EVIDENCED", "CURRENT_EXTERNAL_OR_DATA_BLOCKER", "REQUIRED_FINAL_PRODUCTION_BEHAVIOR", "HISTORICAL_OR_SUPERSEDED"],
  sensitivity: ["PUBLIC", "INTERNAL", "RESTRICTED", "LOCAL_ONLY"], disposition: ["RETAIN_CANONICAL", "MIGRATE_REFERENCE", "GENERATE_VIEW", "SUPERSEDE", "DELETE_AFTER_HANDOFF", "HISTORICAL", "UNKNOWN_FINDING"],
  mutationPolicy: ["CURRENT_STATE_WITH_CHANGE", "DECISION_APPEND_ONLY", "EVIDENCE_IMMUTABLE", "PLAN_LIVING_BUT_NON_EVIDENCE", "GENERATED_VIEW_DERIVED"], reviewPolicyId: ["EVENT_ONLY", "RELEASE_BOUND", "OPERATIONAL_CRITICAL", "OPERATIONAL_STANDARD", "DATA_FRESHNESS_BOUND", "TOOLCHAIN_BOUND"], verificationMethod: ["contract-test", "runtime-check", "drill", "release-audit", "owner-review"],
  implementationPlan: ["PLAN-DOC", "PLAN-REPO", "PLAN-JOURNEY"], workloadClass: ["STATELESS_SERVICE", "ONE_SHOT_JOB", "SCHEDULED_JOB", "EXTERNAL_MANAGED_STATE"], orchestrationProfile: ["COMPOSE_CURRENT", "KUBERNETES_CANDIDATE", "KUBERNETES_ACTIVE"], stateClass: ["NONE", "EPHEMERAL_CACHE", "SHARED_DURABLE", "ATOMIC_RELEASE_IDENTITY"], configurationDelivery: ["IMMUTABLE_ENV", "IMMUTABLE_FILE", "EXTERNAL_SECRET_REFERENCE"],
};
const FIELDS = ["resource", "resourceClass", "documentationFamily", "kindCandidate", "sourceSurface", "canonicalIdentity", "status", "ownerRepository", "ownerIssue", "currentConsumers", "releaseReachability", "publicSurfaceReachability", "assertionState", "sensitivity", "duplicateGroup", "disposition", "deletePrerequisite", "supersedes", "supersededBy", "invalidatedBy", "invalidationReason", "invalidationEvidence", "mutationPolicy", "reviewPolicyId", "reviewTrigger", "lastVerifiedAt", "lastVerifiedIdentity", "verificationMethod", "verificationEvidence", "nextReviewAtOrSemanticExpiry", "implementationPlan", "workloadClass", "orchestrationProfile", "stateClass", "configurationDelivery", "healthContract", "availabilityContract", "securityContract", "releaseContract", "portabilityOwner", "portabilityEvidence", "portabilityGap"];
const ARRAY_FIELDS = new Set(["currentConsumers", "publicSurfaceReachability", "deletePrerequisite", "supersedes", "invalidationEvidence", "reviewTrigger", "verificationEvidence", "portabilityEvidence", "portabilityGap"]);
const NULLABLE = new Set(["ownerIssue", "duplicateGroup", "supersededBy", "invalidatedBy", "invalidationReason", "nextReviewAtOrSemanticExpiry", "workloadClass", "orchestrationProfile", "stateClass", "configurationDelivery", "healthContract", "availabilityContract", "securityContract", "releaseContract", "portabilityOwner"]);
const cmp = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const fail = (message) => { throw new Error(`documentation inventory: ${message}`); };
const exactKeys = (value, keys, label) => { if (value == null || typeof value !== "object" || Array.isArray(value) || [...Object.keys(value)].sort(cmp).join("\0") !== [...keys].sort(cmp).join("\0")) fail(`${label} keys are invalid`); };
const safe = (value) => typeof value === "string" && value.length > 0 && !/[\x00-\x1f\\]/.test(value) && !isAbsolute(value) && !value.includes("..") && !/(token|secret|password|credential)/i.test(value);
const safeUrl = (value) => { try { const url = new URL(value); return url.protocol === "https:" && !url.username && !url.password && !url.search && !url.hash; } catch { return false; } };
const sortedStrings = (value, label) => { if (!Array.isArray(value) || value.some((item) => !safe(item) && !safeUrl(item)) || value.some((item, i) => i && cmp(value[i - 1], item) >= 0)) fail(`${label} must be sorted unique sanitized identifiers`); };
function git(root, args) { try { return execFileSync(GIT, ["-C", root, ...args], { encoding: "buffer", stdio: ["ignore", "pipe", "pipe"] }); } catch { fail(`git verification failed`); } }
function tree(root, sha) {
  if (!/^[0-9a-f]{40}$/.test(sha)) fail("gitSha is invalid");
  if (!existsSync(root) || !lstatSync(root).isDirectory()) fail("repository root is invalid");
  if (git(root, ["cat-file", "-t", sha]).toString("utf8").trim() !== "commit") fail("gitSha is not a commit");
  const entries = new Map();
  for (const item of git(root, ["ls-tree", "-r", "-z", sha]).toString("utf8").split("\0")) {
    if (!item) continue; const [meta, path] = item.split("\t"); const [mode, type, oid] = meta.split(" "); entries.set(path, { mode, type, oid });
  } return entries;
}
function validateRecord(record, tracked, repository, sha, entries) {
  exactKeys(record, FIELDS, "record");
  for (const [field, values] of Object.entries(ENUMS)) if (record[field] !== null && !values.includes(record[field])) fail(`${field} is invalid`);
  if (!/^[A-Z][A-Z0-9_]*$/.test(record.kindCandidate)) fail("kindCandidate is invalid");
  for (const field of ARRAY_FIELDS) sortedStrings(record[field], field);
  for (const field of NULLABLE) if (record[field] !== null && (!safe(record[field]) && !safeUrl(record[field]))) fail(`${field} is invalid`);
  if (!safe(record.resource) || !safe(record.canonicalIdentity) || record.lastVerifiedIdentity !== record.canonicalIdentity || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(record.lastVerifiedAt) || Number.isNaN(Date.parse(record.lastVerifiedAt))) fail("record identity or timestamp is invalid");
  if (!REPOSITORIES.includes(record.ownerRepository) || (record.ownerIssue !== null && !new RegExp(`^https://github\\.com/${record.ownerRepository}/issues/\\d+$`).test(record.ownerIssue))) fail("owner is invalid");
  if (record.status === "INVALIDATED" && record.resourceClass !== "EVIDENCE") fail("INVALIDATED requires EVIDENCE");
  if (record.status === "UNKNOWN" || record.disposition === "UNKNOWN_FINDING") fail("unknown terminal value");
  if (["REVOKED", "INVALIDATED"].includes(record.status) && (!["NONE", "EVIDENCE"].includes(record.releaseReachability) || record.publicSurfaceReachability.length || record.currentConsumers.some((item) => !item.startsWith("evidence:")))) fail("revoked lifecycle reachability is invalid");
  if ((record.sourceSurface === "PUBLIC" || record.publicSurfaceReachability.length) && (record.sensitivity !== "PUBLIC" || record.assertionState !== "CURRENTLY_IMPLEMENTED_AND_EVIDENCED")) fail("public surface gate failed");
  if (record.orchestrationProfile === "KUBERNETES_ACTIVE" && record.portabilityEvidence.length === 0) fail("KUBERNETES_ACTIVE requires portability evidence");
  if (tracked) {
    const prefix = `${repository}:`; if (!record.resource.startsWith(prefix)) fail("tracked resource is invalid"); const path = record.resource.slice(prefix.length); const entry = entries.get(path);
    if (!entry || entry.mode === "120000" || entry.type !== "blob" || record.canonicalIdentity !== `git:${sha}:${path}:${entry.oid}`) fail("tracked record does not match git tree");
  } else if (!/^sha256:[0-9a-f]{64}$/.test(record.canonicalIdentity) || (record.sourceSurface === "LOCAL_ONLY" && !/^local-evidence:sha256:[0-9a-f]{64}$/.test(record.resource))) fail("surface identity is invalid");
}
function stable(value) { if (Array.isArray(value)) return value.map(stable); if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort(cmp).map((key) => [key, stable(value[key])])); return value; }
function parseArguments(args) { if (args.length !== 4 || args[0] !== "--workspace" || args[2] !== "--output" || !isAbsolute(args[1]) || !isAbsolute(args[3])) fail("usage: documentation-inventory.mjs --workspace <local-json> --output <new-json>"); return { workspace: args[1], output: args[3] }; }
export function generateInventory(workspace) {
  exactKeys(workspace, ["schemaVersion", "repositories", "surfaceRecords"], "workspace"); if (workspace.schemaVersion !== 1 || !Array.isArray(workspace.repositories) || workspace.repositories.length !== 5 || !Array.isArray(workspace.surfaceRecords)) fail("workspace is invalid");
  const records = [], seenRepositories = new Set(), trackedResources = new Set();
  for (const entry of workspace.repositories) {
    exactKeys(entry, ["repository", "root", "gitSha", "discoveryRoots", "records"], "repository entry");
    if (!REPOSITORIES.includes(entry.repository) || seenRepositories.has(entry.repository) || !isAbsolute(entry.root) || !Array.isArray(entry.discoveryRoots) || !Array.isArray(entry.records)) fail("repository entry is invalid"); seenRepositories.add(entry.repository);
    if (entry.discoveryRoots.some((root) => !safe(root)) || entry.discoveryRoots.some((root, i) => i && cmp(entry.discoveryRoots[i - 1], root) >= 0)) fail("discoveryRoots are invalid");
    const entries = tree(entry.root, entry.gitSha); const expected = new Set();
    for (const root of entry.discoveryRoots) {
      const discovered = [...entries].filter(([path]) => path === root || path.startsWith(`${root}/`));
      if (discovered.length === 0) fail("discovery root is missing");
      for (const [path, info] of discovered) if (info.mode !== "120000" && info.type === "blob") expected.add(path);
    }
    for (const record of entry.records) { if (record.sourceSurface !== "TRACKED") fail("repository records must be TRACKED"); validateRecord(record, true, entry.repository, entry.gitSha, entries); const path = record.resource.slice(entry.repository.length + 1); if (trackedResources.has(record.resource) || !expected.delete(path)) fail("extra or duplicate tracked record"); trackedResources.add(record.resource); records.push(record); }
    if (expected.size) fail("missing tracked classification");
  }
  if (seenRepositories.size !== 5) fail("exactly five repositories required");
  for (const record of workspace.surfaceRecords) { if (record.sourceSurface === "TRACKED") fail("surface record cannot be TRACKED"); validateRecord(record, false); records.push(record); }
  const groups = new Map(); for (const record of records) if (record.duplicateGroup !== null) groups.set(record.duplicateGroup, [...(groups.get(record.duplicateGroup) ?? []), record]);
  for (const group of groups.values()) if (group.length < 2 || group.filter(({ disposition }) => disposition === "RETAIN_CANONICAL").length !== 1 || group.some((record) => !record.currentConsumers.length || (record.disposition !== "RETAIN_CANONICAL" && !record.deletePrerequisite.length))) fail("duplicate group gate failed");
  records.sort((a, b) => cmp(a.canonicalIdentity, b.canonicalIdentity));
  const count = (values, key) => Object.fromEntries(values.slice().sort(cmp).map((value) => [value, records.filter((record) => record[key] === value).length]));
  const documentationFamilies = count(FAMILIES, "documentationFamily"), repositories = Object.fromEntries(REPOSITORIES.slice().sort(cmp).map((repository) => [repository, records.filter((record) => record.ownerRepository === repository).length])), sourceSurfaces = count(SURFACES, "sourceSurface"), statuses = count(STATUSES, "status");
  const gaps = [...FAMILIES.filter((family) => !documentationFamilies[family]).map((documentationFamily) => ({ code: "NO_DOCUMENTATION_FAMILY_RESOURCE", documentationFamily })), ...[...new Set(records.flatMap(({ portabilityGap }) => portabilityGap))].sort(cmp).map((identity) => ({ code: "PORTABILITY_GAP", identity }))].sort((a, b) => cmp(JSON.stringify(a), JSON.stringify(b)));
  return stable({ schemaVersion: 1, producer: { id: "tools/ci/documentation-inventory.mjs", version: 1 }, repositories: workspace.repositories.map(({ repository, gitSha }) => ({ repository, gitSha })).sort((a, b) => cmp(a.repository, b.repository)), records, coverage: { documentationFamilies, repositories, sourceSurfaces, statuses }, gaps, gates: { activeUnclassified: 0, statusUnclassified: 0, ownerUnknown: 0, releaseReachabilityUnknown: 0, publicSurfaceReachabilityUnknown: 0, mutationPolicyUnknown: 0, reviewPolicyUnknown: 0, duplicateViolations: 0, sensitivityViolations: 0, kubernetesPortabilityViolations: 0 } });
}
function main() { const { workspace, output } = parseArguments(process.argv.slice(2)); if (existsSync(output) || !existsSync(workspace)) fail("output must be new and workspace must exist"); const result = generateInventory(JSON.parse(readFileSync(workspace, "utf8"))); writeFileSync(output, `${JSON.stringify(result)}\n`, { encoding: "utf8", flag: "wx" }); }
if (process.argv[1] === new URL(import.meta.url).pathname) { try { main(); } catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; } }
