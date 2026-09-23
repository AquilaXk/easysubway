import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  parseArgs,
  refreshDocumentationFragment,
  runCli,
} from "./refresh-documentation-fragment.mjs";
import { validateDocumentationRecord } from "../ci/documentation-inventory.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

const FRAGMENT_SCHEMA = JSON.parse(
  readFileSync(
    new URL(
      "../../contracts/documentation/documentation-fragment.schema.json",
      import.meta.url,
    ),
    "utf8",
  ),
);

function createMockGitRepo() {
  const dir = mkdtempSync(join(tmpdir(), "refresh-doc-test-"));
  execFileSync("git", ["init", "-b", "main"], { cwd: dir });
  execFileSync("git", ["config", "user.name", "Test Agent"], { cwd: dir });
  execFileSync("git", ["config", "user.email", "agent@test.local"], { cwd: dir });

  // Create tracked files
  mkdirSync(join(dir, "docs"), { recursive: true });
  mkdirSync(join(dir, "contracts/documentation"), { recursive: true });
  writeFileSync(join(dir, "README.md"), "# Initial Readme\n", "utf8");
  writeFileSync(join(dir, "docs/guide.md"), "# Guide Content\n", "utf8");

  execFileSync("git", ["add", "."], { cwd: dir });
  execFileSync("git", ["commit", "-m", "Initial commit"], { cwd: dir });

  const initialCommitSha = execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: dir,
    encoding: "utf8",
  }).trim();

  const readmeBlob = execFileSync(
    "git",
    ["rev-parse", `HEAD:README.md`],
    { cwd: dir, encoding: "utf8" },
  ).trim();

  const guideBlob = execFileSync(
    "git",
    ["rev-parse", `HEAD:docs/guide.md`],
    { cwd: dir, encoding: "utf8" },
  ).trim();

  const fragment = {
    $schema:
      "https://raw.githubusercontent.com/AquilaXk/easysubway/32ce139789b97ce1f0c9bb059966cfc19f497480/contracts/documentation/documentation-fragment.schema.json",
    schemaVersion: 1,
    repository: "AquilaXk/easysubway",
    sourceSha: initialCommitSha,
    status: "ACTIVE",
    lastVerifiedAt: "2026-08-01T00:00:00.000Z",
    verificationEvidence: ["https://github.com/AquilaXk/easysubway/issues/2748"],
    resources: [
      {
        resource: "AquilaXk/easysubway:README.md",
        resourceClass: "CANONICAL_RESOURCE",
        documentationFamily: "PRODUCT",
        kindCandidate: "PRODUCT_README",
        sourceSurface: "TRACKED",
        canonicalIdentity: `git:${initialCommitSha}:README.md:${readmeBlob}`,
        status: "ACTIVE",
        ownerRepository: "AquilaXk/easysubway",
        ownerIssue: "https://github.com/AquilaXk/easysubway/issues/2748",
        currentConsumers: ["consumer:product"],
        releaseReachability: "PUBLIC",
        publicSurfaceReachability: [],
        assertionState: "CURRENTLY_IMPLEMENTED_AND_EVIDENCED",
        sensitivity: "INTERNAL",
        duplicateGroup: null,
        disposition: "RETAIN_CANONICAL",
        deletePrerequisite: [],
        supersedes: [],
        supersededBy: null,
        invalidatedBy: null,
        invalidationReason: null,
        invalidationEvidence: [],
        mutationPolicy: "CURRENT_STATE_WITH_CHANGE",
        reviewPolicyId: "RELEASE_BOUND",
        reviewTrigger: ["event:change"],
        lastVerifiedAt: "2026-08-01T00:00:00.000Z",
        lastVerifiedIdentity: `git:${initialCommitSha}:README.md:${readmeBlob}`,
        verificationMethod: "contract-test",
        verificationEvidence: ["https://github.com/AquilaXk/easysubway/issues/2748"],
        nextReviewAtOrSemanticExpiry: null,
        implementationPlan: "PLAN-DOC",
        workloadClass: null,
        orchestrationProfile: null,
        stateClass: null,
        configurationDelivery: null,
        healthContract: null,
        availabilityContract: null,
        securityContract: null,
        releaseContract: null,
        portabilityOwner: null,
        portabilityEvidence: [],
        portabilityGap: [],
      },
      {
        resource: "AquilaXk/easysubway:docs/guide.md",
        resourceClass: "CANONICAL_RESOURCE",
        documentationFamily: "ARCHITECTURE",
        kindCandidate: "ARCHITECTURE_DECISION",
        sourceSurface: "TRACKED",
        canonicalIdentity: `git:${initialCommitSha}:docs/guide.md:${guideBlob}`,
        status: "ACTIVE",
        ownerRepository: "AquilaXk/easysubway",
        ownerIssue: "https://github.com/AquilaXk/easysubway/issues/2748",
        currentConsumers: ["consumer:architecture"],
        releaseReachability: "BUILD",
        publicSurfaceReachability: [],
        assertionState: "CURRENTLY_IMPLEMENTED_AND_EVIDENCED",
        sensitivity: "INTERNAL",
        duplicateGroup: null,
        disposition: "RETAIN_CANONICAL",
        deletePrerequisite: [],
        supersedes: [],
        supersededBy: null,
        invalidatedBy: null,
        invalidationReason: null,
        invalidationEvidence: [],
        mutationPolicy: "CURRENT_STATE_WITH_CHANGE",
        reviewPolicyId: "RELEASE_BOUND",
        reviewTrigger: ["event:change"],
        lastVerifiedAt: "2026-08-01T00:00:00.000Z",
        lastVerifiedIdentity: `git:${initialCommitSha}:docs/guide.md:${guideBlob}`,
        verificationMethod: "contract-test",
        verificationEvidence: ["https://github.com/AquilaXk/easysubway/issues/2748"],
        nextReviewAtOrSemanticExpiry: null,
        implementationPlan: "PLAN-DOC",
        workloadClass: null,
        orchestrationProfile: null,
        stateClass: null,
        configurationDelivery: null,
        healthContract: null,
        availabilityContract: null,
        securityContract: null,
        releaseContract: null,
        portabilityOwner: null,
        portabilityEvidence: [],
        portabilityGap: [],
      },
    ],
  };

  const fragPath = join(dir, "contracts/documentation/documentation-fragment.json");
  writeFileSync(fragPath, JSON.stringify(fragment, null, 2) + "\n", "utf8");

  return { dir, initialCommitSha, readmeBlob, guideBlob, fragPath };
}

test("parseArgs parses flags and rejects unknown options", () => {
  const args = parseArgs([
    "--check",
    "--worktree",
    "--quiet",
    "--head",
    "a".repeat(40),
    "--observed-at",
    "2026-09-23T00:00:00.000Z",
    "--fragment",
    "custom/path.json",
    "--repo-root",
    "/custom/root",
  ]);

  assert.equal(args.check, true);
  assert.equal(args.worktree, true);
  assert.equal(args.quiet, true);
  assert.equal(args.headSha, "a".repeat(40));
  assert.equal(args.observedAt, "2026-09-23T00:00:00.000Z");
  assert.equal(args.fragmentPath, "custom/path.json");
  assert.equal(args.repoRoot, "/custom/root");

  assert.throws(() => parseArgs(["--invalid-flag"]), /Unknown option/);
});

test("refreshDocumentationFragment detects in-sync state without modifications", () => {
  const { dir, initialCommitSha } = createMockGitRepo();
  try {
    const checkResult = refreshDocumentationFragment({
      repoRoot: dir,
      check: true,
    });

    assert.equal(checkResult.driftCount, 0);
    assert.equal(checkResult.sourceShaChanged, false);
    assert.equal(checkResult.updated, false);
    assert.equal(checkResult.headSha, initialCommitSha);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("refreshDocumentationFragment detects drift in --check mode after commit without mutating fragment", () => {
  const { dir, fragPath, initialCommitSha } = createMockGitRepo();
  try {
    // Modify README and commit
    writeFileSync(join(dir, "README.md"), "# Updated Readme Header\n", "utf8");
    execFileSync("git", ["add", "README.md"], { cwd: dir });
    execFileSync("git", ["commit", "-m", "Update README"], { cwd: dir });

    const newCommitSha = execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: dir,
      encoding: "utf8",
    }).trim();

    const beforeCheck = readFileSync(fragPath, "utf8");

    const checkResult = refreshDocumentationFragment({
      repoRoot: dir,
      check: true,
    });

    const afterCheck = readFileSync(fragPath, "utf8");

    // File must NOT be modified in check mode
    assert.equal(beforeCheck, afterCheck);
    assert.equal(checkResult.sourceShaChanged, true);
    assert.equal(checkResult.previousSourceSha, initialCommitSha);
    assert.equal(checkResult.headSha, newCommitSha);
    assert.equal(checkResult.driftCount, 2); // both README and guide (due to commitSha change)
    const readmeDrift = checkResult.drift.find((d) => d.path === "README.md");
    assert.ok(readmeDrift);
    assert.equal(readmeDrift.blobChanged, true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("refreshDocumentationFragment refreshes fragment to match Git HEAD and validates against schemas", () => {
  const { dir, fragPath } = createMockGitRepo();
  try {
    // Modify both files and commit
    writeFileSync(join(dir, "README.md"), "# Brand New Content\n", "utf8");
    writeFileSync(join(dir, "docs/guide.md"), "# Updated Guide Steps\n", "utf8");
    execFileSync("git", ["add", "."], { cwd: dir });
    execFileSync("git", ["commit", "-m", "Update docs"], { cwd: dir });

    const newCommitSha = execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: dir,
      encoding: "utf8",
    }).trim();

    const newReadmeBlob = execFileSync(
      "git",
      ["rev-parse", "HEAD:README.md"],
      { cwd: dir, encoding: "utf8" },
    ).trim();

    const newGuideBlob = execFileSync(
      "git",
      ["rev-parse", "HEAD:docs/guide.md"],
      { cwd: dir, encoding: "utf8" },
    ).trim();

    const refreshResult = refreshDocumentationFragment({
      repoRoot: dir,
      observedAt: "2026-09-23T12:00:00.000Z",
    });

    assert.equal(refreshResult.updated, true);
    assert.equal(refreshResult.headSha, newCommitSha);

    const updatedFragment = JSON.parse(readFileSync(fragPath, "utf8"));
    assert.equal(updatedFragment.sourceSha, newCommitSha);
    assert.equal(updatedFragment.lastVerifiedAt, "2026-09-23T12:00:00.000Z");

    const readmeRecord = updatedFragment.resources.find(
      (r) => r.resource === "AquilaXk/easysubway:README.md",
    );
    assert.equal(
      readmeRecord.canonicalIdentity,
      `git:${newCommitSha}:README.md:${newReadmeBlob}`,
    );
    assert.equal(readmeRecord.lastVerifiedIdentity, readmeRecord.canonicalIdentity);
    assert.equal(readmeRecord.lastVerifiedAt, "2026-09-23T12:00:00.000Z");

    const guideRecord = updatedFragment.resources.find(
      (r) => r.resource === "AquilaXk/easysubway:docs/guide.md",
    );
    assert.equal(
      guideRecord.canonicalIdentity,
      `git:${newCommitSha}:docs/guide.md:${newGuideBlob}`,
    );

    // Validate fragment schema
    const schemaValidation = validateSchema(FRAGMENT_SCHEMA, updatedFragment);
    assert.equal(schemaValidation.ok, true, `Schema errors: ${schemaValidation.errors.join("; ")}`);

    // Validate resource semantic rules
    for (const record of updatedFragment.resources) {
      validateDocumentationRecord(record, {
        ownerRepository: updatedFragment.repository,
        gitSha: updatedFragment.sourceSha,
        tracked: true,
      });
    }

    // Running check now must return in-sync
    const postCheck = refreshDocumentationFragment({
      repoRoot: dir,
      check: true,
    });
    assert.equal(postCheck.driftCount, 0);
    assert.equal(postCheck.sourceShaChanged, false);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("refreshDocumentationFragment supports --worktree hashing", () => {
  const { dir, fragPath, initialCommitSha } = createMockGitRepo();
  try {
    // Uncommitted change in README
    writeFileSync(join(dir, "README.md"), "# Uncommitted Change\n", "utf8");

    const worktreeBlob = execFileSync(
      "git",
      ["hash-object", "README.md"],
      { cwd: dir, encoding: "utf8" },
    ).trim();

    const result = refreshDocumentationFragment({
      repoRoot: dir,
      worktree: true,
      headSha: initialCommitSha,
      observedAt: "2026-09-23T12:00:00.000Z",
    });

    assert.equal(result.updated, true);
    const updatedFragment = JSON.parse(readFileSync(fragPath, "utf8"));
    const readmeRecord = updatedFragment.resources.find(
      (r) => r.resource === "AquilaXk/easysubway:README.md",
    );
    assert.equal(
      readmeRecord.canonicalIdentity,
      `git:${initialCommitSha}:README.md:${worktreeBlob}`,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("refreshDocumentationFragment throws when a tracked resource is deleted", () => {
  const { dir } = createMockGitRepo();
  try {
    execFileSync("git", ["rm", "docs/guide.md"], { cwd: dir });
    execFileSync("git", ["commit", "-m", "Delete guide"], { cwd: dir });

    assert.throws(
      () => refreshDocumentationFragment({ repoRoot: dir }),
      /does not exist in commit/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("runCli returns 0 on in-sync and 1 on drift in check mode", () => {
  const { dir } = createMockGitRepo();
  try {
    const inSyncCode = runCli(["--repo-root", dir, "--check", "--quiet"]);
    assert.equal(inSyncCode, 0);

    // Make a commit to cause drift
    writeFileSync(join(dir, "README.md"), "# Drifted\n", "utf8");
    execFileSync("git", ["commit", "-am", "drift"], { cwd: dir });

    const driftCode = runCli(["--repo-root", dir, "--check", "--quiet"]);
    assert.equal(driftCode, 1);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
