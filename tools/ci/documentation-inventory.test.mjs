import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

const SCRIPT = new URL("./documentation-inventory.mjs", import.meta.url).pathname;
const REPOSITORIES = ["AquilaXk/easysubway", "AquilaXk/easysubway-data", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
const FAMILIES = ["PRODUCT", "ARCHITECTURE", "API_CONTRACT", "DATA_KNOWLEDGE", "ENGINEERING", "QUALITY_TEST", "RELEASE_CHANGE", "OPERATIONS_RELIABILITY", "SECURITY_PRIVACY", "USER_SUPPORT_LEGAL_PUBLIC", "GOVERNANCE_EVIDENCE"];
const SURFACES = ["TRACKED", "PUBLIC", "LOCAL_ONLY", "EXTERNAL"];

function run(command, args, cwd) {
  return execFileSync(command, args, { cwd, encoding: "utf8" }).trim();
}

function createRepository(root, index) {
  mkdirSync(root, { recursive: true });
  run("/usr/bin/git", ["init", "-q"], root);
  run("/usr/bin/git", ["config", "user.email", "test@example.invalid"], root);
  run("/usr/bin/git", ["config", "user.name", "Test"], root);
  mkdirSync(join(root, "docs"));
  writeFileSync(join(root, "docs", `doc-${index}.json`), "{}\n");
  if (index === 0) writeFileSync(join(root, "docs", "duplicate.json"), "{}\n");
  symlinkSync(`doc-${index}.json`, join(root, "docs", "linked.json"));
  run("/usr/bin/git", ["add", "."], root);
  run("/usr/bin/git", ["commit", "-qm", "fixture"], root);
  const gitSha = run("/usr/bin/git", ["rev-parse", "HEAD"], root);
  const blobOid = run("/usr/bin/git", ["rev-parse", `HEAD:docs/doc-${index}.json`], root);
  const duplicateBlobOid = index === 0 ? run("/usr/bin/git", ["rev-parse", "HEAD:docs/duplicate.json"], root) : null;
  assert.match(run("/usr/bin/git", ["ls-tree", "HEAD", "docs/linked.json"], root), /^120000 /, "fixture symlink must be committed");
  return { gitSha, blobOid, duplicateBlobOid };
}

function record({ repository, sha, path, family, surface = "TRACKED", blobOid = "a".repeat(64), overrides = {} }) {
  const oid = surface === "TRACKED" ? blobOid : "a".repeat(64);
  return {
    resource: surface === "TRACKED" ? `${repository}:${path}` : surface === "LOCAL_ONLY" ? `local-evidence:sha256:${"b".repeat(64)}` : `surface:sha256:${"b".repeat(64)}`,
    resourceClass: "CANONICAL_RESOURCE", documentationFamily: family, kindCandidate: "DOCUMENT",
    sourceSurface: surface, canonicalIdentity: surface === "TRACKED" ? `git:${sha}:${path}:${oid}` : `sha256:${oid}`,
    status: "ACTIVE", ownerRepository: repository, ownerIssue: null, currentConsumers: ["consumer:current"],
    releaseReachability: "NONE", publicSurfaceReachability: [], assertionState: "CURRENTLY_IMPLEMENTED_AND_EVIDENCED",
    sensitivity: surface === "PUBLIC" ? "PUBLIC" : "INTERNAL", duplicateGroup: null, disposition: "RETAIN_CANONICAL",
    deletePrerequisite: [], supersedes: [], supersededBy: null, invalidatedBy: null, invalidationReason: null, invalidationEvidence: [],
    mutationPolicy: "CURRENT_STATE_WITH_CHANGE", reviewPolicyId: "EVENT_ONLY", reviewTrigger: ["event:change"],
    lastVerifiedAt: "2026-08-05T00:00:00.000Z", lastVerifiedIdentity: surface === "TRACKED" ? `git:${sha}:${path}:${oid}` : `sha256:${oid}`,
    verificationMethod: "owner-review", verificationEvidence: ["evidence:fixture"], nextReviewAtOrSemanticExpiry: null,
    implementationPlan: "PLAN-DOC", workloadClass: null, orchestrationProfile: null, stateClass: null, configurationDelivery: null,
    healthContract: null, availabilityContract: null, securityContract: null, releaseContract: null,
    portabilityOwner: null, portabilityEvidence: [], portabilityGap: [], ...overrides,
  };
}

function invoke(workspace, output) {
  mkdirSync(output, { recursive: true });
  const workspacePath = join(output, "workspace.json");
  writeFileSync(workspacePath, `${JSON.stringify(workspace)}\n`);
  return spawnSync(process.execPath, [SCRIPT, "--workspace", workspacePath, "--output", join(output, "inventory.json")], { encoding: "utf8" });
}

test("문서 인벤토리: 5개 저장소·11개 군·4개 surface를 결정적으로 검증하고 fail closed한다", () => {
  const temp = mkdtempSync(join(tmpdir(), "documentation-inventory-"));
  const repositories = REPOSITORIES.map((repository, index) => {
    const root = join(temp, `repo-${index}`);
    const { gitSha, blobOid, duplicateBlobOid } = createRepository(root, index);
    const records = [record({ repository, sha: gitSha, blobOid, path: `docs/doc-${index}.json`, family: FAMILIES[index] })];
    if (index === 0) {
      records.push(record({
        repository, sha: gitSha, blobOid: duplicateBlobOid, path: "docs/duplicate.json", family: FAMILIES[5],
        overrides: { duplicateGroup: "duplicate:product", disposition: "DELETE_AFTER_HANDOFF", deletePrerequisite: ["handoff:canonical"] },
      }));
      records[0].duplicateGroup = "duplicate:product";
    }
    return { repository, root, gitSha, discoveryRoots: ["docs"], records };
  });
  const surfaceRecords = [
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "public", family: FAMILIES[6], surface: "PUBLIC", overrides: { resource: "https://public.example.invalid/release", publicSurfaceReachability: ["https://public.example.invalid/release"] } }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "local", family: FAMILIES[7], surface: "LOCAL_ONLY" }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "external", family: FAMILIES[8], surface: "EXTERNAL" }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "external-z", family: FAMILIES[8], surface: "EXTERNAL", overrides: { resource: "surface:z", canonicalIdentity: `sha256:${"c".repeat(64)}`, lastVerifiedIdentity: `sha256:${"c".repeat(64)}` } }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "external-e", family: FAMILIES[8], surface: "EXTERNAL", overrides: { resource: "surface:é", canonicalIdentity: `sha256:${"d".repeat(64)}`, lastVerifiedIdentity: `sha256:${"d".repeat(64)}` } }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "revoked", family: FAMILIES[9], surface: "PUBLIC", overrides: { status: "REVOKED", currentConsumers: [], publicSurfaceReachability: [] } }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "invalidated", family: FAMILIES[10], surface: "LOCAL_ONLY", overrides: { resourceClass: "EVIDENCE", status: "INVALIDATED", currentConsumers: [], invalidatedBy: "evidence:replacement", invalidationReason: "reason:replaced", invalidationEvidence: ["evidence:replacement"], mutationPolicy: "EVIDENCE_IMMUTABLE" } }),
  ];
  const workspace = { schemaVersion: 1, repositories, surfaceRecords };
  const first = invoke(workspace, join(temp, "first"));
  assert.equal(first.status, 0, first.stderr);
  const output = JSON.parse(readFileSync(join(temp, "first", "inventory.json"), "utf8"));
  assert.deepEqual(Object.keys(output), ["coverage", "gaps", "gates", "producer", "records", "repositories", "schemaVersion"]);
  assert.equal(output.records.length, 13);
  assert.deepEqual(output.records.filter(({ resource }) => ["surface:z", "surface:é"].includes(resource)).map(({ resource }) => resource), ["surface:z", "surface:é"]);
  assert.deepEqual(Object.keys(output.coverage.documentationFamilies), [...FAMILIES].sort());
  assert.deepEqual(Object.keys(output.coverage.repositories), [...REPOSITORIES].sort());
  assert.deepEqual(Object.keys(output.coverage.sourceSurfaces), [...SURFACES].sort());
  assert.equal(output.gaps.filter(({ code }) => code === "NO_DOCUMENTATION_FAMILY_RESOURCE").length, 0);
  const second = invoke(workspace, join(temp, "second"));
  assert.equal(second.status, 0, second.stderr);
  assert.equal(readFileSync(join(temp, "first", "inventory.json"), "utf8"), readFileSync(join(temp, "second", "inventory.json"), "utf8"));
  assert.notEqual(invoke(workspace, join(temp, "first")).status, 0, "기존 output은 덮어쓰지 않아야 한다");
  for (const mutate of [
    (input) => input.repositories[0].records.pop(),
    (input) => input.repositories[0].records.push(record({ repository: REPOSITORIES[0], sha: input.repositories[0].gitSha, path: "docs/extra.json", family: FAMILIES[0] })),
    (input) => { input.repositories[0].records[0].resourceClass = null; },
    (input) => { input.repositories[0].records[0].canonicalIdentity = "git:bad"; },
    (input) => { input.repositories[0].gitSha = "f".repeat(40); },
    (input) => { input.repositories[0].discoveryRoots = ["../escape"]; },
    (input) => { input.repositories[0].discoveryRoots = ["missing.json"]; },
    (input) => { input.repositories[0].records[1].deletePrerequisite = []; },
    (input) => { input.surfaceRecords[6].invalidationEvidence = []; },
    (input) => { input.surfaceRecords[5].releaseReachability = "PUBLIC"; },
    (input) => { input.surfaceRecords[0].sensitivity = "INTERNAL"; },
    (input) => { input.surfaceRecords[0].assertionState = "REQUIRED_FINAL_PRODUCTION_BEHAVIOR"; },
    (input) => { input.surfaceRecords[0].resource = "https://public.example.invalid/release?page=1"; },
    (input) => { input.surfaceRecords[1].verificationEvidence = ["/private/evidence"]; },
    (input) => { input.repositories[0].records[0].orchestrationProfile = "KUBERNETES_ACTIVE"; },
  ]) {
    const input = structuredClone(workspace); mutate(input);
    assert.notEqual(invoke(input, join(temp, `bad-${Math.random()}`)).status, 0);
  }
  assert.equal(output.records.find(({ status }) => status === "INVALIDATED").resourceClass, "EVIDENCE");
  assert.notEqual(invoke({ ...workspace, repositories: repositories.map((entry, index) => index === 0 ? { ...entry, discoveryRoots: ["docs/linked.json"], records: [] } : entry) }, join(temp, "symlink")).status, 0, "committed symlink discovery root must fail closed");
});
