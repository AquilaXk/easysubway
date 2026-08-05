import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";

const REPOSITORIES = ["AquilaXk/easysubway", "AquilaXk/easysubway-data", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
const FAMILIES = ["PRODUCT", "ARCHITECTURE", "API_CONTRACT", "DATA_KNOWLEDGE", "ENGINEERING", "QUALITY_TEST", "RELEASE_CHANGE", "OPERATIONS_RELIABILITY", "SECURITY_PRIVACY", "USER_SUPPORT_LEGAL_PUBLIC", "GOVERNANCE_EVIDENCE"];
const SURFACES = ["TRACKED", "PUBLIC", "LOCAL_ONLY", "EXTERNAL"];
const ENUMS = {
  resourceClass: ["CANONICAL_RESOURCE", "HUMAN_CONTEXT", "EXECUTABLE_COMPANION", "EVIDENCE", "HUMAN_VIEW"],
  documentationFamily: FAMILIES,
  sourceSurface: SURFACES,
  status: ["PROPOSED", "ACTIVE", "SUPERSEDED", "REVOKED", "HISTORICAL", "INVALIDATED"],
  releaseReachability: ["NONE", "BUILD", "RUNTIME", "DEPLOY", "PUBLIC", "EVIDENCE"],
  assertionState: ["CURRENTLY_IMPLEMENTED_AND_EVIDENCED", "CURRENT_EXTERNAL_OR_DATA_BLOCKER", "REQUIRED_FINAL_PRODUCTION_BEHAVIOR", "HISTORICAL_OR_SUPERSEDED"],
  sensitivity: ["PUBLIC", "INTERNAL", "RESTRICTED", "LOCAL_ONLY"],
  disposition: ["RETAIN_CANONICAL", "MIGRATE_REFERENCE", "GENERATE_VIEW", "SUPERSEDE", "DELETE_AFTER_HANDOFF", "HISTORICAL"],
  mutationPolicy: ["CURRENT_STATE_WITH_CHANGE", "DECISION_APPEND_ONLY", "EVIDENCE_IMMUTABLE", "PLAN_LIVING_BUT_NON_EVIDENCE", "GENERATED_VIEW_DERIVED"],
  reviewPolicyId: ["EVENT_ONLY", "RELEASE_BOUND", "OPERATIONAL_CRITICAL", "OPERATIONAL_STANDARD", "DATA_FRESHNESS_BOUND", "TOOLCHAIN_BOUND"],
  verificationMethod: ["contract-test", "runtime-check", "drill", "release-audit", "owner-review"],
  implementationPlan: ["PLAN-DOC", "PLAN-REPO", "PLAN-JOURNEY"],
};
const NULLABLE_ENUMS = {
  workloadClass: ["STATELESS_SERVICE", "ONE_SHOT_JOB", "SCHEDULED_JOB", "EXTERNAL_MANAGED_STATE"],
  orchestrationProfile: ["COMPOSE_CURRENT", "KUBERNETES_CANDIDATE", "KUBERNETES_ACTIVE"],
  stateClass: ["NONE", "EPHEMERAL_CACHE", "SHARED_DURABLE", "ATOMIC_RELEASE_IDENTITY"],
  configurationDelivery: ["IMMUTABLE_ENV", "IMMUTABLE_FILE", "EXTERNAL_SECRET_REFERENCE"],
};
const RECORD_KEYS = ["resource", "resourceClass", "documentationFamily", "kindCandidate", "sourceSurface", "canonicalIdentity", "status", "ownerRepository", "ownerIssue", "currentConsumers", "releaseReachability", "publicSurfaceReachability", "assertionState", "sensitivity", "duplicateGroup", "disposition", "deletePrerequisite", "supersedes", "supersededBy", "invalidatedBy", "invalidationReason", "invalidationEvidence", "mutationPolicy", "reviewPolicyId", "reviewTrigger", "lastVerifiedAt", "lastVerifiedIdentity", "verificationMethod", "verificationEvidence", "nextReviewAtOrSemanticExpiry", "implementationPlan", "workloadClass", "orchestrationProfile", "stateClass", "configurationDelivery", "healthContract", "availabilityContract", "securityContract", "releaseContract", "portabilityOwner", "portabilityEvidence", "portabilityGap"];

function fail(message) { throw new Error(message); }
function codepointCompare(left, right) {
  const leftPoints = Array.from(left);
  const rightPoints = Array.from(right);
  for (let index = 0; index < Math.min(leftPoints.length, rightPoints.length); index += 1) {
    const difference = leftPoints[index].codePointAt(0) - rightPoints[index].codePointAt(0);
    if (difference !== 0) return difference;
  }
  return leftPoints.length - rightPoints.length;
}
function exactKeys(value, keys, name) {
  if (!value || typeof value !== "object" || Array.isArray(value)) fail(`${name} must be an object`);
  if (Object.keys(value).sort(codepointCompare).join("\0") !== [...keys].sort(codepointCompare).join("\0")) fail(`${name} has unexpected shape`);
}
function safeRelative(value) { return typeof value === "string" && value.length > 0 && !isAbsolute(value) && !value.split("/").includes("..") && !/[\x00-\x1f\x7f]/.test(value); }
function safeIdentifier(value) {
  if (typeof value !== "string" || value.length === 0 || /[\x00-\x1f\x7f]/.test(value) || isAbsolute(value)) return false;
  if (value.startsWith("https://")) {
    try { const url = new URL(value); return !url.username && !url.password && !url.search && !url.hash; } catch { return false; }
  }
  return !value.includes("?");
}
function sortedUnique(values, name) {
  if (!Array.isArray(values) || values.some((value) => !safeIdentifier(value))) fail(`${name} contains unsafe identifier`);
  if (values.join("\0") !== [...new Set(values)].sort(codepointCompare).join("\0")) fail(`${name} must be sorted and unique`);
}
function git(root, args) { return execFileSync("/usr/bin/git", ["-C", root, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }); }
function treeEntries(root, sha) {
  const raw = git(root, ["ls-tree", "-r", "-z", sha]);
  return raw.split("\0").filter(Boolean).map((entry) => {
    const match = /^(\d+) (\w+) ([0-9a-f]+)\t(.+)$/.exec(entry);
    if (!match) fail("invalid git tree entry");
    return { mode: match[1], type: match[2], oid: match[3], path: match[4] };
  });
}
function matchesRoot(path, root) { return path === root || path.startsWith(`${root}/`); }
function validateRecord(record, repository, sha, tracked) {
  exactKeys(record, RECORD_KEYS, "record");
  for (const [field, values] of Object.entries(ENUMS)) if (!values.includes(record[field])) fail(`invalid ${field}`);
  for (const [field, values] of Object.entries(NULLABLE_ENUMS)) if (record[field] !== null && !values.includes(record[field])) fail(`invalid ${field}`);
  if (typeof record.kindCandidate !== "string" || !/^[A-Z][A-Z0-9_]*$/.test(record.kindCandidate)) fail("invalid kindCandidate");
  if (record.ownerRepository !== repository || !REPOSITORIES.includes(repository)) fail("invalid ownerRepository");
  if (record.ownerIssue !== null && (!safeIdentifier(record.ownerIssue) || !/^https:\/\/github\.com\/AquilaXk\/(easysubway|easysubway-data|easysubway-backend|easysubway-mobile|easysubway-platform)\/issues\/\d+$/.test(record.ownerIssue))) fail("invalid ownerIssue");
  for (const field of ["currentConsumers", "publicSurfaceReachability", "deletePrerequisite", "supersedes", "invalidationEvidence", "reviewTrigger", "verificationEvidence", "portabilityEvidence", "portabilityGap"]) sortedUnique(record[field], field);
  for (const field of ["duplicateGroup", "supersededBy", "invalidatedBy", "invalidationReason", "nextReviewAtOrSemanticExpiry", "portabilityOwner", "healthContract", "availabilityContract", "securityContract", "releaseContract"]) if (record[field] !== null && !safeIdentifier(record[field])) fail(`invalid ${field}`);
  if (!Number.isFinite(Date.parse(record.lastVerifiedAt)) || !/^\d{4}-\d{2}-\d{2}T/.test(record.lastVerifiedAt)) fail("invalid lastVerifiedAt");
  if (record.lastVerifiedIdentity !== record.canonicalIdentity) fail("last verification identity mismatch");
  if (tracked) {
    if (record.sourceSurface !== "TRACKED" || !safeRelative(record.resource.split(":").slice(1).join(":"))) fail("invalid tracked resource");
    if (!new RegExp(`^git:${sha}:([^:]+):[0-9a-f]{40,64}$`).test(record.canonicalIdentity)) fail("invalid tracked identity");
  } else if (record.sourceSurface === "TRACKED" || !/^sha256:[0-9a-f]{64}$/.test(record.canonicalIdentity)) fail("invalid non-tracked identity");
  if (record.sourceSurface === "LOCAL_ONLY" && !/^local-evidence:sha256:[0-9a-f]{64}$/.test(record.resource)) fail("invalid local resource");
  if (!safeIdentifier(record.resource)) fail("unsafe resource");
  if (record.status === "INVALIDATED") {
    if (record.resourceClass !== "EVIDENCE" || !record.invalidatedBy || !record.invalidationReason || record.invalidationEvidence.length === 0 || record.mutationPolicy !== "EVIDENCE_IMMUTABLE") fail("invalid invalidation relation");
  } else if (record.invalidatedBy !== null || record.invalidationReason !== null || record.invalidationEvidence.length !== 0) fail("unexpected invalidation relation");
  if (["REVOKED", "INVALIDATED"].includes(record.status) && ( !["NONE", "EVIDENCE"].includes(record.releaseReachability) || record.publicSurfaceReachability.length !== 0 || record.currentConsumers.some((value) => !value.startsWith("evidence:")))) fail("revoked or invalidated record is reachable");
  if ((record.sourceSurface === "PUBLIC" || record.publicSurfaceReachability.length > 0) && record.status !== "REVOKED" && (record.sensitivity !== "PUBLIC" || record.assertionState !== "CURRENTLY_IMPLEMENTED_AND_EVIDENCED")) fail("invalid public claim");
  if (record.orchestrationProfile === "KUBERNETES_ACTIVE" && record.portabilityEvidence.length === 0) fail("active Kubernetes needs evidence");
}
function validateRepository(entry) {
  exactKeys(entry, ["repository", "root", "gitSha", "discoveryRoots", "records"], "repository");
  if (!REPOSITORIES.includes(entry.repository) || typeof entry.root !== "string" || !isAbsolute(entry.root) || !/^[0-9a-f]{40}$/.test(entry.gitSha)) fail("invalid repository input");
  if (!Array.isArray(entry.discoveryRoots) || entry.discoveryRoots.length === 0 || entry.discoveryRoots.some((root) => !safeRelative(root)) || entry.discoveryRoots.join("\0") !== [...new Set(entry.discoveryRoots)].sort(codepointCompare).join("\0")) fail("invalid discovery roots");
  try { if (git(entry.root, ["cat-file", "-t", entry.gitSha]).trim() !== "commit") fail("missing git commit"); } catch { fail("missing git commit"); }
  const entries = treeEntries(entry.root, entry.gitSha);
  const selected = [];
  for (const root of entry.discoveryRoots) {
    const rootEntries = entries.filter((item) => matchesRoot(item.path, root));
    if (rootEntries.length === 0 || rootEntries.some((item) => item.path === root && item.mode === "120000")) fail("missing or symlink discovery root");
    selected.push(...rootEntries);
  }
  if (selected.some((item) => item.type !== "blob" || item.mode === "120000")) fail("non-blob entry under discovery root");
  const blobs = selected;
  const uniqueBlobs = new Map(blobs.map((item) => [item.path, item]));
  if (uniqueBlobs.size !== blobs.length) fail("overlapping discovery roots");
  if (!Array.isArray(entry.records)) fail("records must be array");
  const paths = new Set();
  for (const record of entry.records) {
    validateRecord(record, entry.repository, entry.gitSha, true);
    const prefix = `${entry.repository}:`;
    if (!record.resource.startsWith(prefix)) fail("tracked resource repository mismatch");
    const path = record.resource.slice(prefix.length);
    const tree = uniqueBlobs.get(path);
    if (!tree || paths.has(path) || record.canonicalIdentity !== `git:${entry.gitSha}:${path}:${tree.oid}`) fail("tracked classification mismatch");
    paths.add(path);
  }
  if (paths.size !== uniqueBlobs.size) fail("missing tracked classification");
  return entry.records;
}
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(Object.keys(value).sort(codepointCompare).map((key) => [key, stable(value[key])]));
}
function main() {
  const args = process.argv.slice(2);
  if (args.length !== 4 || args[0] !== "--workspace" || args[2] !== "--output") fail("usage: --workspace <file> --output <new-file>");
  const [workspacePath, outputPath] = [args[1], args[3]];
  if (existsSync(outputPath)) fail("output already exists");
  const workspace = JSON.parse(readFileSync(workspacePath, "utf8"));
  exactKeys(workspace, ["schemaVersion", "repositories", "surfaceRecords"], "workspace");
  if (workspace.schemaVersion !== 1 || !Array.isArray(workspace.repositories) || !Array.isArray(workspace.surfaceRecords) || workspace.repositories.length !== REPOSITORIES.length) fail("invalid workspace");
  const seen = new Set(workspace.repositories.map((entry) => entry.repository));
  if (seen.size !== REPOSITORIES.length || REPOSITORIES.some((repository) => !seen.has(repository))) fail("repository set mismatch");
  const records = workspace.repositories.flatMap(validateRepository);
  for (const record of workspace.surfaceRecords) { validateRecord(record, record.ownerRepository, null, false); records.push(record); }
  if (new Set(records.map((record) => record.resource)).size !== records.length) fail("duplicate resource");
  const duplicateGroups = new Map();
  for (const record of records) if (record.duplicateGroup !== null) duplicateGroups.set(record.duplicateGroup, [...(duplicateGroups.get(record.duplicateGroup) ?? []), record]);
  for (const group of duplicateGroups.values()) {
    if (group.length < 2 || group.filter((record) => record.disposition === "RETAIN_CANONICAL").length !== 1 || group.some((record) => record.currentConsumers.length === 0 || record.disposition !== "RETAIN_CANONICAL" && record.deletePrerequisite.length === 0)) fail("invalid duplicate group");
  }
  const coverage = {
    documentationFamilies: Object.fromEntries(FAMILIES.map((family) => [family, records.filter((record) => record.documentationFamily === family).length])),
    repositories: Object.fromEntries(REPOSITORIES.map((repository) => [repository, records.filter((record) => record.ownerRepository === repository).length])),
    sourceSurfaces: Object.fromEntries(SURFACES.map((surface) => [surface, records.filter((record) => record.sourceSurface === surface).length])),
    statuses: Object.fromEntries(ENUMS.status.map((status) => [status, records.filter((record) => record.status === status).length])),
  };
  const gaps = [
    ...FAMILIES.filter((family) => coverage.documentationFamilies[family] === 0).map((documentationFamily) => ({ code: "NO_DOCUMENTATION_FAMILY_RESOURCE", documentationFamily })),
    ...[...new Set(records.flatMap((record) => record.portabilityGap))].sort(codepointCompare).map((identity) => ({ code: "PORTABILITY_GAP", identity })),
  ].sort((left, right) => codepointCompare(JSON.stringify(stable(left)), JSON.stringify(stable(right))));
  const output = stable({ schemaVersion: 1, producer: { id: "tools/ci/documentation-inventory.mjs", version: 1 }, repositories: workspace.repositories.map(({ repository, gitSha }) => ({ repository, gitSha })).sort((a, b) => codepointCompare(a.repository, b.repository)), records: records.sort((a, b) => codepointCompare(a.resource, b.resource)), coverage, gaps, gates: { duplicate: 0, invalidated: 0, portability: 0, public: 0, reachability: 0, unclassified: 0 } });
  writeFileSync(outputPath, `${JSON.stringify(output)}\n`, { encoding: "utf8", flag: "wx" });
}

try { main(); } catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; }
