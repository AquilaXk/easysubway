import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  DOCUMENTATION_FAMILIES,
  DOCUMENTATION_REPOSITORIES,
  DOCUMENTATION_RESOURCE_CLASSES,
  validateDocumentationRecord,
  validateDocumentationRelations,
} from "./documentation-inventory.mjs";

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
  if (index === 0) writeFileSync(join(root, "docs", "\uE000.json"), "{}\n");
  if (index === 0) writeFileSync(join(root, "docs", "😀.json"), "{}\n");
  if (index === 4) writeFileSync(join(root, "[literal].json"), "{}\n");
  run("/usr/bin/git", ["add", "."], root);
  run("/usr/bin/git", ["commit", "-qm", "fixture"], root);
  const gitSha = run("/usr/bin/git", ["rev-parse", "HEAD"], root);
  const blobOid = run("/usr/bin/git", ["rev-parse", `HEAD:docs/doc-${index}.json`], root);
  const duplicateBlobOid = index === 0 ? run("/usr/bin/git", ["rev-parse", "HEAD:docs/duplicate.json"], root) : null;
  const puaBlobOid = index === 0 ? run("/usr/bin/git", ["rev-parse", "HEAD:docs/\uE000.json"], root) : null;
  const astralBlobOid = index === 0 ? run("/usr/bin/git", ["rev-parse", "HEAD:docs/😀.json"], root) : null;
  const literalBlobOid = index === 4 ? run("/usr/bin/git", ["rev-parse", "HEAD:[literal].json"], root) : null;
  return { gitSha, blobOid, duplicateBlobOid, puaBlobOid, astralBlobOid, literalBlobOid };
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
    const { gitSha, blobOid, duplicateBlobOid, puaBlobOid, astralBlobOid, literalBlobOid } = createRepository(root, index);
    const records = [record({ repository, sha: gitSha, blobOid, path: `docs/doc-${index}.json`, family: FAMILIES[index] })];
    if (index === 0) {
      records.push(record({
        repository, sha: gitSha, blobOid: duplicateBlobOid, path: "docs/duplicate.json", family: FAMILIES[5],
        overrides: { duplicateGroup: "duplicate:product", disposition: "DELETE_AFTER_HANDOFF", deletePrerequisite: ["handoff:canonical"] },
      }));
      records.push(record({ repository, sha: gitSha, blobOid: puaBlobOid, path: "docs/\uE000.json", family: FAMILIES[0] }));
      records.push(record({ repository, sha: gitSha, blobOid: astralBlobOid, path: "docs/😀.json", family: FAMILIES[0] }));
      records[0].duplicateGroup = "duplicate:product";
    }
    if (index === 4) records.push(record({ repository, sha: gitSha, blobOid: literalBlobOid, path: "[literal].json", family: FAMILIES[4] }));
    return { repository, root, gitSha, discoveryRoots: index === 0 ? ["docs/doc-0.json", "docs/duplicate.json", "docs/\uE000.json", "docs/😀.json"] : index === 4 ? ["[literal].json", "docs"] : ["docs"], records };
  });
  const surfaceRecords = [
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "public", family: FAMILIES[6], surface: "PUBLIC", overrides: { resource: "https://public.example.invalid/release", ownerIssue: "https://github.com/AquilaXk/easysubway/issues/2756", publicSurfaceReachability: ["https://public.example.invalid/release"], healthContract: "contract:health", availabilityContract: "contract:availability", securityContract: "contract:security", releaseContract: "contract:release" } }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "local", family: FAMILIES[7], surface: "LOCAL_ONLY" }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "external", family: FAMILIES[8], surface: "EXTERNAL" }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "external-e000", family: FAMILIES[8], surface: "EXTERNAL", overrides: { resource: "surface:\uE000", canonicalIdentity: `sha256:${"c".repeat(64)}`, lastVerifiedIdentity: `sha256:${"c".repeat(64)}` } }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "external-grinning", family: FAMILIES[8], surface: "EXTERNAL", overrides: { resource: "surface:😀", canonicalIdentity: `sha256:${"d".repeat(64)}`, lastVerifiedIdentity: `sha256:${"d".repeat(64)}` } }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "revoked", family: FAMILIES[9], surface: "PUBLIC", overrides: { resource: "https://public.example.invalid/revoked", canonicalIdentity: `sha256:${"f".repeat(64)}`, lastVerifiedIdentity: `sha256:${"f".repeat(64)}`, status: "REVOKED", currentConsumers: [], publicSurfaceReachability: [] } }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "invalidated", family: FAMILIES[10], surface: "LOCAL_ONLY", overrides: { resource: `local-evidence:sha256:${"e".repeat(64)}`, canonicalIdentity: `sha256:${"e".repeat(64)}`, lastVerifiedIdentity: `sha256:${"e".repeat(64)}`, resourceClass: "EVIDENCE", status: "INVALIDATED", currentConsumers: ["evidence:audit"], invalidatedBy: `local-evidence:sha256:${"f".repeat(64)}`, invalidationReason: "reason:replaced", invalidationEvidence: ["evidence:replacement"], mutationPolicy: "EVIDENCE_IMMUTABLE" } }),
    record({ repository: REPOSITORIES[0], sha: repositories[0].gitSha, path: "replacement", family: FAMILIES[10], surface: "LOCAL_ONLY", overrides: { resource: `local-evidence:sha256:${"f".repeat(64)}`, canonicalIdentity: `sha256:${"f".repeat(64)}`, lastVerifiedIdentity: `sha256:${"f".repeat(64)}`, resourceClass: "EVIDENCE", mutationPolicy: "EVIDENCE_IMMUTABLE", supersedes: [`local-evidence:sha256:${"e".repeat(64)}`] } }),
  ];
  const workspace = { schemaVersion: 1, repositories, surfaceRecords };
  const first = invoke(workspace, join(temp, "first"));
  assert.equal(first.status, 0, first.stderr);
  const output = JSON.parse(readFileSync(join(temp, "first", "inventory.json"), "utf8"));
  assert.deepEqual(Object.keys(output), ["coverage", "gaps", "gates", "producer", "records", "repositories", "schemaVersion"]);
  assert.equal(output.records.length, 17);
  assert.deepEqual(DOCUMENTATION_REPOSITORIES, REPOSITORIES);
  assert.deepEqual(DOCUMENTATION_FAMILIES, FAMILIES);
  assert.ok(DOCUMENTATION_RESOURCE_CLASSES.includes("EVIDENCE"));
  assert.doesNotThrow(() => validateDocumentationRelations(output.records));
  assert.doesNotThrow(() => validateDocumentationRecord(output.records[0], {
    ownerRepository: output.records[0].ownerRepository,
    gitSha: output.repositories.find(({ repository }) => repository === output.records[0].ownerRepository).gitSha,
    tracked: true,
  }));
  assert.throws(() => validateDocumentationRecord(output.records[0], {
    ownerRepository: output.records[0].ownerRepository,
    gitSha: ".*",
    tracked: true,
  }), /invalid gitSha/);
  assert.throws(() => validateDocumentationRelations([
    { resource: "resource:old", status: "SUPERSEDED", supersededBy: "resource:new", supersedes: [], duplicateGroup: null },
    { resource: "resource:new", status: "ACTIVE", supersededBy: null, supersedes: [], duplicateGroup: null },
  ]), /reciprocal successor/);
  assert.throws(() => validateDocumentationRelations([
    { resource: "resource:a", status: "SUPERSEDED", supersededBy: "resource:b", supersedes: ["resource:b"], duplicateGroup: null },
    { resource: "resource:b", status: "SUPERSEDED", supersededBy: "resource:a", supersedes: ["resource:a"], duplicateGroup: null },
  ]), /supersession cycle/);
  assert.deepEqual(output.records.filter(({ resource }) => ["surface:\uE000", "surface:😀"].includes(resource)).map(({ resource }) => resource), ["surface:\uE000", "surface:😀"]);
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
    (input) => { input.repositories[0].records[1].duplicateGroup = null; },
    (input) => { input.repositories[0].records[1].currentConsumers = []; },
    (input) => { input.surfaceRecords.find(({ status }) => status === "INVALIDATED").invalidationEvidence = []; },
    (input) => { input.surfaceRecords.find(({ status }) => status === "INVALIDATED").invalidatedBy = "evidence:missing"; },
    (input) => { input.surfaceRecords[5].releaseReachability = "PUBLIC"; },
    (input) => { input.surfaceRecords[5].currentConsumers = ["runtime:mobile"]; },
    (input) => { input.surfaceRecords[0].sensitivity = "INTERNAL"; },
    (input) => { input.surfaceRecords[0].assertionState = "REQUIRED_FINAL_PRODUCTION_BEHAVIOR"; },
    (input) => { input.surfaceRecords[0].healthContract = {}; },
    (input) => { input.surfaceRecords[0].availabilityContract = "/private/availability"; },
    (input) => { input.surfaceRecords[0].securityContract = "https://public.example.invalid/security?page=1"; },
    (input) => { input.surfaceRecords[0].releaseContract = { id: "release" }; },
    (input) => { input.surfaceRecords[2].publicSurfaceReachability = ["https://public.example.invalid/external"]; },
    (input) => { input.surfaceRecords.push(structuredClone(input.surfaceRecords[2])); },
    (input) => { input.surfaceRecords[0].resource = "https://public.example.invalid/release?page=1"; },
    (input) => { input.surfaceRecords[0].resource = "HTTPS://user:password@public.example.invalid/release"; },
    (input) => { input.surfaceRecords[1].verificationEvidence = [" http://example.invalid/evidence"]; },
    (input) => { input.surfaceRecords[0].ownerIssue = "https://github.com/AquilaXk/easysubway-mobile/issues/2756"; },
    (input) => { input.surfaceRecords[0].lastVerifiedAt = "2026-02-31T00:00:00.000Z"; },
    (input) => { input.surfaceRecords[0].verificationEvidence = []; },
    (input) => { input.surfaceRecords[1].verificationEvidence = ["C:\\Users\\owner\\secret.txt"]; },
    (input) => { input.surfaceRecords[1].verificationEvidence = ["\\\\server\\share\\secret.txt"]; },
    (input) => { input.surfaceRecords[1].verificationEvidence = ["../private/evidence"]; },
    (input) => { input.surfaceRecords[1].verificationEvidence = ["..\\private\\evidence"]; },
    (input) => { input.surfaceRecords[1].verificationEvidence = ["/private/evidence"]; },
    (input) => { input.repositories[0].records[0].orchestrationProfile = "KUBERNETES_ACTIVE"; },
  ]) {
    const input = structuredClone(workspace); mutate(input);
    assert.notEqual(invoke(input, join(temp, `bad-${Math.random()}`)).status, 0);
  }
  assert.equal(output.records.find(({ status }) => status === "INVALIDATED").resourceClass, "EVIDENCE");
  const gapWorkspace = structuredClone(workspace);
  gapWorkspace.surfaceRecords = [];
  const gapRun = invoke(gapWorkspace, join(temp, "gaps"));
  assert.equal(gapRun.status, 0, gapRun.stderr);
  assert.deepEqual(JSON.parse(readFileSync(join(temp, "gaps", "inventory.json"), "utf8")).gaps.map(({ documentationFamily }) => documentationFamily), ["GOVERNANCE_EVIDENCE", "OPERATIONS_RELIABILITY", "RELEASE_CHANGE", "SECURITY_PRIVACY", "USER_SUPPORT_LEGAL_PUBLIC"]);
  const tagWorkspace = structuredClone(workspace);
  const tagRepository = tagWorkspace.repositories[1];
  const tagOriginalSha = tagRepository.gitSha;
  run("/usr/bin/git", ["tag", "-a", "inventory-annotated", "-m", "annotated fixture"], repositories[1].root);
  tagRepository.gitSha = run("/usr/bin/git", ["rev-parse", "inventory-annotated"], repositories[1].root);
  for (const tracked of tagRepository.records) {
    tracked.canonicalIdentity = tracked.canonicalIdentity.replace(`git:${tagOriginalSha}:`, `git:${tagRepository.gitSha}:`);
    tracked.lastVerifiedIdentity = tracked.canonicalIdentity;
  }
  assert.notEqual(invoke(tagWorkspace, join(temp, "annotated-tag")).status, 0, "annotated tag object must not be accepted as gitSha");
  const symlinkWorkspace = structuredClone(workspace);
  const symlinkRepository = symlinkWorkspace.repositories[0];
  const originalSha = symlinkRepository.gitSha;
  symlinkRepository.discoveryRoots = ["docs"];
  symlinkSync("doc-0.json", join(repositories[0].root, "docs", "linked.json"));
  run("/usr/bin/git", ["add", "docs/linked.json"], repositories[0].root);
  run("/usr/bin/git", ["commit", "-qm", "nested symlink"], repositories[0].root);
  symlinkRepository.gitSha = run("/usr/bin/git", ["rev-parse", "HEAD"], repositories[0].root);
  for (const tracked of symlinkRepository.records) {
    tracked.canonicalIdentity = tracked.canonicalIdentity.replace(`git:${originalSha}:`, `git:${symlinkRepository.gitSha}:`);
    tracked.lastVerifiedIdentity = tracked.canonicalIdentity;
  }
  assert.match(run("/usr/bin/git", ["ls-tree", "HEAD", "docs/linked.json"], repositories[0].root), /^120000 /, "nested symlink must be committed");
  assert.notEqual(invoke(symlinkWorkspace, join(temp, "symlink")).status, 0, "committed nested symlink under discovery root must fail closed");
  const gitlinkWorkspace = structuredClone(workspace);
  const gitlinkRepository = gitlinkWorkspace.repositories[0];
  const gitlinkOriginalSha = gitlinkRepository.gitSha;
  run("/usr/bin/git", ["rm", "--cached", "docs/linked.json"], repositories[0].root);
  run("/usr/bin/git", ["update-index", "--add", "--cacheinfo", `160000,${workspace.repositories[0].gitSha},docs/gitlink`], repositories[0].root);
  run("/usr/bin/git", ["commit", "-qm", "gitlink fixture"], repositories[0].root);
  gitlinkRepository.gitSha = run("/usr/bin/git", ["rev-parse", "HEAD"], repositories[0].root);
  gitlinkRepository.discoveryRoots = ["docs"];
  for (const tracked of gitlinkRepository.records) {
    tracked.canonicalIdentity = tracked.canonicalIdentity.replace(`git:${gitlinkOriginalSha}:`, `git:${gitlinkRepository.gitSha}:`);
    tracked.lastVerifiedIdentity = tracked.canonicalIdentity;
  }
  assert.match(run("/usr/bin/git", ["ls-tree", "HEAD", "docs/gitlink"], repositories[0].root), /^160000 commit /, "gitlink must be committed");
  assert.notEqual(invoke(gitlinkWorkspace, join(temp, "gitlink")).status, 0, "gitlink under discovery root must fail closed");
});
