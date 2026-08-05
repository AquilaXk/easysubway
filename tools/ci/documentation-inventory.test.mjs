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
  writeFileSync(join(root, `doc-${index}.json`), "{}\n");
  writeFileSync(join(root, "ignored-link"), "target\n");
  run("/usr/bin/git", ["add", "."], root);
  run("/usr/bin/git", ["commit", "-qm", "fixture"], root);
  const gitSha = run("/usr/bin/git", ["rev-parse", "HEAD"], root);
  const blobOid = run("/usr/bin/git", ["rev-parse", `HEAD:doc-${index}.json`], root);
  return { gitSha, blobOid };
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
    const { gitSha, blobOid } = createRepository(root, index);
    return { repository, root, gitSha, discoveryRoots: [`doc-${index}.json`], records: [record({ repository, sha: gitSha, blobOid, path: `doc-${index}.json`, family: FAMILIES[index] })] };
  });
  const surfaceRecords = SURFACES.slice(1).map((surface, index) => record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "unused", family: FAMILIES[index + 5], surface }));
  const workspace = { schemaVersion: 1, repositories, surfaceRecords };
  const first = invoke(workspace, join(temp, "first"));
  assert.equal(first.status, 0, first.stderr);
  const output = JSON.parse(readFileSync(join(temp, "first", "inventory.json"), "utf8"));
  assert.deepEqual(Object.keys(output), ["coverage", "gaps", "gates", "producer", "records", "repositories", "schemaVersion"]);
  assert.equal(output.records.length, 8);
  assert.deepEqual(Object.keys(output.coverage.documentationFamilies), [...FAMILIES].sort());
  assert.deepEqual(Object.keys(output.coverage.repositories), [...REPOSITORIES].sort());
  assert.deepEqual(Object.keys(output.coverage.sourceSurfaces), [...SURFACES].sort());
  assert.equal(output.gaps.filter(({ code }) => code === "NO_DOCUMENTATION_FAMILY_RESOURCE").length, 3);
  const second = invoke(workspace, join(temp, "second"));
  assert.equal(second.status, 0, second.stderr);
  assert.equal(readFileSync(join(temp, "first", "inventory.json"), "utf8"), readFileSync(join(temp, "second", "inventory.json"), "utf8"));
  assert.notEqual(invoke(workspace, join(temp, "first")).status, 0, "기존 output은 덮어쓰지 않아야 한다");
  for (const mutate of [
    (input) => input.repositories[0].records.pop(),
    (input) => input.repositories[0].records.push(record({ repository: REPOSITORIES[0], sha: input.repositories[0].gitSha, path: "extra.json", family: FAMILIES[0] })),
    (input) => { input.repositories[0].records[0].canonicalIdentity = "git:bad"; },
    (input) => { input.repositories[0].gitSha = "f".repeat(40); },
    (input) => { input.repositories[0].discoveryRoots = ["../escape"]; },
    (input) => { input.repositories[0].discoveryRoots = ["missing.json"]; },
    (input) => { input.repositories[0].records[0].duplicateGroup = "dup"; },
    (input) => { input.repositories[0].records[0].status = "INVALIDATED"; },
    (input) => { input.repositories[0].records[0].sensitivity = "SECRET"; },
    (input) => { input.repositories[0].records[0].orchestrationProfile = "KUBERNETES_ACTIVE"; },
  ]) {
    const input = structuredClone(workspace); mutate(input);
    assert.notEqual(invoke(input, join(temp, `bad-${Math.random()}`)).status, 0);
  }
  symlinkSync("doc-0.json", join(repositories[0].root, "linked.json"));
  assert.notEqual(invoke({ ...workspace, repositories: repositories.map((entry, index) => index === 0 ? { ...entry, discoveryRoots: ["linked.json"] } : entry) }, join(temp, "symlink")).status, 0);
});
