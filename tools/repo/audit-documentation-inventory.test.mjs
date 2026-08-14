import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import {
  AuditIncomplete,
  auditDocumentationInventory,
  collectLive,
  gh,
  runAuditCli,
  validateDocumentationInventoryAuditReport,
  validateDocumentationInventoryAuditScope,
  verifyFragment,
} from "./audit-documentation-inventory.mjs";

const auditModule = await import("./audit-documentation-inventory.mjs");

const REPOSITORIES = [
  "AquilaXk/easysubway",
  "AquilaXk/easysubway-backend",
  "AquilaXk/easysubway-data",
  "AquilaXk/easysubway-mobile",
  "AquilaXk/easysubway-platform",
];
const PATH = "contracts/documentation/documentation-fragment.json";
const SCOPE = {
  schemaVersion: 1,
  repositories: REPOSITORIES.map((repository) => ({ repository, defaultBranch: "main", fragmentPath: PATH, requiredStatus: "ACTIVE" })),
  dods: ["D01", "D02", "D03", "D04", "D05"],
};
const SHA = "a".repeat(40);
const SOURCE_SHA = "e".repeat(40);
const WATERMARK = "b".repeat(64);
const DOCUMENTATION_FRAGMENT_SCHEMA_URI =
  "https://raw.githubusercontent.com/AquilaXk/easysubway/32ce139789b97ce1f0c9bb059966cfc19f497480/contracts/documentation/documentation-fragment.schema.json";

function record(repository, overrides = {}) {
  const path = `contracts/${repository.split("/").at(-1)}.json`;
  const canonicalIdentity = `git:${SHA}:${path}:${"c".repeat(40)}`;
  return {
    resource: `${repository}:${path}`,
    resourceClass: "CANONICAL_RESOURCE",
    documentationFamily: "ARCHITECTURE",
    kindCandidate: "DOCUMENTATION_RESOURCE",
    sourceSurface: "TRACKED",
    canonicalIdentity,
    status: "ACTIVE",
    ownerRepository: repository,
    ownerIssue: `https://github.com/${repository}/issues/1`,
    currentConsumers: ["consumer:documentation"],
    releaseReachability: "NONE",
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
    reviewPolicyId: "EVENT_ONLY",
    reviewTrigger: ["event:change"],
    lastVerifiedAt: "2026-08-11T00:00:00.000Z",
    lastVerifiedIdentity: canonicalIdentity,
    verificationMethod: "contract-test",
    verificationEvidence: ["evidence:fixture"],
    nextReviewAtOrSemanticExpiry: null,
    implementationPlan: repository === "AquilaXk/easysubway" ? "PLAN-DOC" : "PLAN-JOURNEY",
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
    ...overrides,
  };
}

function fragment(repository, resources = [record(repository)], overrides = {}) {
  return {
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI,
    schemaVersion: 1,
    repository,
    sourceSha: SHA,
    status: "ACTIVE",
    lastVerifiedAt: "2026-08-11T00:00:00.000Z",
    verificationEvidence: ["evidence:fixture"],
    resources,
    ...overrides,
  };
}

function ready(repository, resources) {
  return { repository, headSha: SHA, state: "READY", fragmentStatus: "ACTIVE", fragmentBlobSha: "d".repeat(40), fragment: fragment(repository, resources), resourceCount: resources.length, activeResourceCount: resources.filter(({ status }) => status === "ACTIVE").length };
}

test("documentation inventory audit validates exact scope and preserves missing fragments as PENDING", () => {
  assert.deepEqual(validateDocumentationInventoryAuditScope(SCOPE), []);
  for (const mutate of [
    (scope) => scope.repositories.pop(),
    (scope) => scope.repositories.reverse(),
    (scope) => { scope.repositories[0].fragmentPath = "../fragment.json"; },
    (scope) => { scope.repositories[0].requiredStatus = "PROPOSED"; },
    (scope) => scope.dods.pop(),
  ]) {
    const invalid = structuredClone(SCOPE);
    mutate(invalid);
    assert.notDeepEqual(validateDocumentationInventoryAuditScope(invalid), []);
  }
  const malformed = structuredClone(SCOPE);
  malformed.repositories[0] = null;
  assert.doesNotThrow(() => validateDocumentationInventoryAuditScope(malformed));
  assert.notDeepEqual(validateDocumentationInventoryAuditScope(malformed), []);
  const repositories = REPOSITORIES.map((repository) => ({ repository, headSha: SHA, state: "PENDING", fragmentStatus: "MISSING", fragmentBlobSha: null, fragment: null, resourceCount: 0, activeResourceCount: 0 }));
  const report = auditDocumentationInventory({ scope: SCOPE, sourceSha: SHA, observedAt: "2026-08-11T00:00:00.000Z", repositories, stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK });
  assert.deepEqual([report.status, report.summary.pending, report.summary.ready, report.summary.findings, report.summary.incomplete], ["COMPLETE", 5, 0, 0, 0]);
  assert.deepEqual(report.dods.map(({ id, status }) => [id, status]), SCOPE.dods.map((id) => [id, "PENDING"]));
  assert.deepEqual(validateDocumentationInventoryAuditReport(report), []);
});

test("documentation inventory audit proves D01-D05 only for five exact ACTIVE fragments", () => {
  const repositories = REPOSITORIES.map((repository) => ready(repository, [record(repository)]));
  const report = auditDocumentationInventory({ scope: SCOPE, sourceSha: SHA, observedAt: "2026-08-11T00:00:00.000Z", repositories, stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK });
  assert.deepEqual([report.summary.pending, report.summary.ready, report.summary.activeResources, report.summary.findings], [0, 5, 5, 0]);
  assert.deepEqual(report.dods.map(({ id, status, findings }) => [id, status, findings]), SCOPE.dods.map((id) => [id, "PROVEN", 0]));

  const invalid = structuredClone(repositories);
  invalid[0].fragment.resources[0].implementationPlan = "PLAN-JOURNEY";
  invalid[1].fragment.resources[0].ownerIssue = null;
  invalid[2].fragment.resources[0].duplicateGroup = "duplicate:shared";
  invalid[3].fragment.resources[0].duplicateGroup = "duplicate:shared";
  const contradicted = auditDocumentationInventory({ scope: SCOPE, sourceSha: SHA, observedAt: "2026-08-11T00:00:00.000Z", repositories: invalid, stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK });
  assert.deepEqual(contradicted.findings.map(({ dod, code }) => [dod, code]), [
    ["D02", "ACTIVE_OWNER_ISSUE_MISSING"],
    ["D03", "DUPLICATE_CANONICAL_COUNT"],
    ["D05", "HUB_TARGET_PLAN_ACTIVE_COPY"],
  ]);
  assert.deepEqual(contradicted.dods.map(({ id, status }) => [id, status]), [
    ["D01", "PROVEN"], ["D02", "CONTRADICTED"], ["D03", "CONTRADICTED"], ["D04", "PROVEN"], ["D05", "CONTRADICTED"],
  ]);
});

test("documentation inventory audit verifies tracked fragment blobs and rejects malformed input", async () => {
  const candidate = fragment(REPOSITORIES[0]);
  const readContent = async (_repository, path, _sha) => path === PATH
    ? { type: "file", sha: "d".repeat(40), encoding: "base64", content: Buffer.from(JSON.stringify(candidate)).toString("base64") }
    : { type: "file", sha: "c".repeat(40), encoding: "base64", content: Buffer.from("{}").toString("base64") };
  const verified = await verifyFragment(SCOPE.repositories[0], SHA, { readContent });
  assert.deepEqual([verified.state, verified.fragmentStatus, verified.resourceCount, verified.activeResourceCount], ["READY", "ACTIVE", 1, 1]);
  await assert.rejects(() => verifyFragment(SCOPE.repositories[0], SHA, { readContent: async () => ({ type: "file", sha: "d".repeat(40), encoding: "base64", content: "%%%" }) }), (error) => error instanceof AuditIncomplete && error.code === "FRAGMENT_DECODE_INVALID");
  const missing = await verifyFragment(SCOPE.repositories[0], SHA, { readContent: async () => { throw Object.assign(new Error("missing"), { status: 404 }); } });
  assert.deepEqual([missing.state, missing.fragmentStatus, missing.fragmentBlobSha], ["PENDING", "MISSING", null]);
});

test("documentation inventory audit accepts source-bound resources without self-head identity", async () => {
  const canonicalIdentity = `git:${SOURCE_SHA}:contracts/easysubway.json:${"c".repeat(40)}`;
  const candidate = fragment(REPOSITORIES[0], [record(REPOSITORIES[0], {
    canonicalIdentity,
    lastVerifiedIdentity: canonicalIdentity,
  })]);
  candidate.sourceSha = SOURCE_SHA;
  const readContent = async (_repository, path, sha) => path === PATH
    ? { type: "file", sha: "d".repeat(40), encoding: "base64", content: Buffer.from(JSON.stringify(candidate)).toString("base64") }
    : [SOURCE_SHA, SHA].includes(sha)
      ? { type: "file", sha: "c".repeat(40), encoding: "base64", content: Buffer.from("{}").toString("base64") }
      : Promise.reject(Object.assign(new Error("missing"), { status: 404 }));
  const verified = await verifyFragment(SCOPE.repositories[0], SHA, { readContent });
  assert.deepEqual(
    [verified.state, verified.fragmentStatus, verified.resourceCount, verified.verificationFindings],
    ["READY", "ACTIVE", 1, []],
  );

  const payload = Buffer.from("{}");
  const payloadSha256 = createHash("sha256").update(payload).digest("hex");
  const sha256Identity = `git:${SOURCE_SHA}:contracts/easysubway.json:${payloadSha256}`;
  const sha256Candidate = fragment(REPOSITORIES[0], [record(REPOSITORIES[0], {
    canonicalIdentity: sha256Identity,
    lastVerifiedIdentity: sha256Identity,
  })], { sourceSha: SOURCE_SHA });
  const sha256Verified = await verifyFragment(SCOPE.repositories[0], SHA, {
    readContent: async (_repository, path) => path === PATH
      ? { type: "file", sha: "d".repeat(40), encoding: "base64", content: Buffer.from(JSON.stringify(sha256Candidate)).toString("base64") }
      : { type: "file", sha: "c".repeat(40), encoding: "base64", content: payload.toString("base64") },
  });
  assert.deepEqual(
    [sha256Verified.state, sha256Verified.fragmentStatus, sha256Verified.resourceCount, sha256Verified.verificationFindings],
    ["READY", "ACTIVE", 1, []],
  );

  const currentMismatch = await verifyFragment(SCOPE.repositories[0], SHA, {
    readContent: async (_repository, path, sha) => path === PATH
      ? { type: "file", sha: "d".repeat(40), encoding: "base64", content: Buffer.from(JSON.stringify(candidate)).toString("base64") }
      : { type: "file", sha: sha === SOURCE_SHA ? "c".repeat(40) : "f".repeat(40), encoding: "base64", content: Buffer.from("{}").toString("base64") },
  });
  assert.deepEqual(currentMismatch.verificationFindings, [{
    dod: "D01",
    code: "TRACKED_RESOURCE_CURRENT_BLOB_MISMATCH",
    identity: candidate.resources[0].resource,
  }]);

  const currentMissing = await verifyFragment(SCOPE.repositories[0], SHA, {
    readContent: async (_repository, path, sha) => {
      if (path === PATH) return { type: "file", sha: "d".repeat(40), encoding: "base64", content: Buffer.from(JSON.stringify(candidate)).toString("base64") };
      if (sha === SOURCE_SHA) return { type: "file", sha: "c".repeat(40), encoding: "base64", content: Buffer.from("{}").toString("base64") };
      throw Object.assign(new Error("missing"), { status: 404 });
    },
  });
  assert.deepEqual(currentMissing.verificationFindings, [{
    dod: "D01",
    code: "TRACKED_RESOURCE_CURRENT_MISSING",
    identity: candidate.resources[0].resource,
  }]);

  await assert.rejects(
    () => verifyFragment(SCOPE.repositories[0], SHA, {
      readContent: async (_repository, path, sha) => {
        if (path === PATH) return { type: "file", sha: "d".repeat(40), encoding: "base64", content: Buffer.from(JSON.stringify(candidate)).toString("base64") };
        if (sha === SOURCE_SHA) throw Object.assign(new Error("missing"), { status: 404 });
        return { type: "file", sha: "c".repeat(40), encoding: "base64", content: Buffer.from("{}").toString("base64") };
      },
    }),
    (error) => error instanceof AuditIncomplete && error.code === "TRACKED_RESOURCE_SOURCE_MISSING",
  );

  const legacy = structuredClone(candidate);
  legacy.gitSha = legacy.sourceSha;
  delete legacy.sourceSha;
  await assert.rejects(
    () => verifyFragment(SCOPE.repositories[0], SHA, {
      readContent: async (_repository, path) => path === PATH
        ? { type: "file", sha: "d".repeat(40), encoding: "base64", content: Buffer.from(JSON.stringify(legacy)).toString("base64") }
        : { type: "file", sha: "c".repeat(40), encoding: "base64", content: Buffer.from("{}").toString("base64") },
    }),
    (error) => error instanceof AuditIncomplete && error.code === "FRAGMENT_SCHEMA_INVALID",
  );
});

test("documentation inventory audit rejects state drift and writes schema-valid fallback without overwriting", async () => {
  const pending = REPOSITORIES.map((repository) => ({ repository, headSha: SHA, state: "PENDING", fragmentStatus: "MISSING", fragmentBlobSha: null, fragment: null, resourceCount: 0, activeResourceCount: 0 }));
  let snapshot = 0;
  await assert.rejects(() => collectLive(SCOPE, {
    sourceSha: SHA,
    collectSnapshot: async () => ({ repositories: pending, watermark: `${++snapshot}`.padStart(64, "0") }),
  }), (error) => error instanceof AuditIncomplete && error.code === "STATE_WATERMARK_DRIFT");

  const directory = mkdtempSync(join(tmpdir(), "documentation-inventory-audit-"));
  const output = join(directory, "report.json");
  const scopeSchema = readFileSync("contracts/documentation/documentation-inventory-audit-scope.schema.json", "utf8");
  const reportSchema = readFileSync("contracts/documentation/documentation-inventory-audit-report.schema.json", "utf8");
  const argv = ["--scope", "scope", "--scope-schema", "scope-schema", "--report-schema", "report-schema", "--source-sha", SHA, "--observed-at", "2026-08-11T00:00:00.000Z", "--repository-root", join(directory, "repositories"), "--output", output];
  try {
    const result = await runAuditCli({ argv, read: async (path) => ({ scope: "{", "scope-schema": scopeSchema, "report-schema": reportSchema })[path], collect: async () => { throw new Error("must not collect"); } });
    const report = JSON.parse(readFileSync(output, "utf8"));
    assert.equal(result.exitCode, 2);
    assert.equal(validateSchema(JSON.parse(reportSchema), report).ok, true);
    assert.deepEqual([report.status, report.summary.pending, report.summary.ready, report.summary.incomplete], ["AUDIT_INCOMPLETE", 5, 0, 1]);
    const malformedScope = structuredClone(SCOPE);
    malformedScope.repositories[0] = null;
    const malformedOutput = join(directory, "malformed-scope.json");
    const malformedArgv = [...argv.slice(0, -1), malformedOutput];
    const malformedResult = await runAuditCli({ argv: malformedArgv, read: async (path) => ({ scope: JSON.stringify(malformedScope), "scope-schema": scopeSchema, "report-schema": reportSchema })[path], collect: async () => { throw new Error("must not collect"); } });
    const malformedReport = JSON.parse(readFileSync(malformedOutput, "utf8"));
    assert.equal(malformedResult.exitCode, 2);
    assert.equal(validateSchema(JSON.parse(reportSchema), malformedReport).ok, true);
    assert.deepEqual([malformedReport.status, malformedReport.summary.incomplete], ["AUDIT_INCOMPLETE", 1]);
    writeFileSync(join(directory, "existing.json"), "existing\n");
    const existingArgv = [...argv.slice(0, -1), join(directory, "existing.json")];
    assert.equal((await runAuditCli({ argv: existingArgv, read: async (path) => ({ scope: JSON.stringify(SCOPE), "scope-schema": scopeSchema, "report-schema": reportSchema })[path], collect: async () => ({ repositories: pending, stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK }) })).exitCode, 2);
    assert.equal(readFileSync(join(directory, "existing.json"), "utf8"), "existing\n");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("documentation inventory audit retries transient structured GitHub responses and preserves structured 404", async () => {
  const endpoint = `repos/AquilaXk/easysubway/contents/${PATH}?ref=${SHA}`;
  const response = (status, body) => `HTTP/2.0 ${status}\nContent-Type: application/json\n\n${JSON.stringify(body)}`;
  const delays = [];
  let attempts = 0;
  const execute = async () => {
    attempts += 1;
    if (attempts < 3) throw Object.assign(new Error("transient"), { stdout: response("500 Internal Server Error", { message: "unavailable" }), stderr: "provider unavailable" });
    return { stdout: response("200 OK", { type: "file" }), stderr: "" };
  };
  assert.equal(JSON.parse(await gh(["api", endpoint], execute, async (delay) => delays.push(delay))).type, "file");
  assert.deepEqual([attempts, delays], [3, [250, 500]]);
  await assert.rejects(
    () => gh(["api", endpoint], async () => { throw Object.assign(new Error("missing"), { stdout: response("404 Not Found", { message: "Not Found" }), stderr: "localized stderr" }); }),
    (error) => error?.status === 404,
  );
});

test("documentation inventory audit retries rate-limited GitHub responses", async () => {
  const endpoint = `repos/AquilaXk/easysubway/contents/${PATH}?ref=${SHA}`;
  const response = (status, body, headers = {}) => [
    `HTTP/2.0 ${status}`,
    ...Object.entries(headers).map(([name, value]) => `${name}: ${value}`),
    "Content-Type: application/json",
    "",
    JSON.stringify(body),
  ].join("\n");

  let attempts = 0;
  const delays = [];
  const rateLimitedThenReady = async () => {
    attempts += 1;
    if (attempts === 1) throw Object.assign(new Error("secondary rate limit"), {
      stdout: response("403 Forbidden", { message: "You have exceeded a secondary rate limit." }, { "Retry-After": "2" }),
    });
    return { stdout: response("200 OK", { type: "file" }), stderr: "" };
  };
  assert.equal(JSON.parse(await gh(["api", endpoint], rateLimitedThenReady, async (delay) => delays.push(delay))).type, "file");
  assert.deepEqual([attempts, delays], [2, [2_000]]);

  attempts = 0;
  delays.length = 0;
  const resetThenReady = async () => {
    attempts += 1;
    if (attempts === 1) throw Object.assign(new Error("primary rate limit"), {
      stdout: response("403 Forbidden", { message: "API rate limit exceeded" }, {
        "X-RateLimit-Remaining": "0",
        "X-RateLimit-Reset": "1700000002",
      }),
    });
    return { stdout: response("200 OK", { type: "file" }), stderr: "" };
  };
  assert.equal(JSON.parse(await gh(["api", endpoint], resetThenReady, async (delay) => delays.push(delay), () => 1_700_000_000_000)).type, "file");
  assert.deepEqual([attempts, delays], [2, [2_000]]);

  attempts = 0;
  delays.length = 0;
  await assert.rejects(
    () => gh(["api", endpoint], async () => {
      attempts += 1;
      throw Object.assign(new Error("forbidden"), { stdout: response("403 Forbidden", { message: "Resource not accessible by integration" }) });
    }, async (delay) => delays.push(delay)),
    (error) => !(error instanceof AuditIncomplete),
  );
  assert.deepEqual([attempts, delays], [1, []]);

  attempts = 0;
  delays.length = 0;
  await assert.rejects(
    () => gh(["api", endpoint], async () => {
      attempts += 1;
      throw Object.assign(new Error("secondary rate limit"), {
        stdout: response("429 Too Many Requests", { message: "You have exceeded a secondary rate limit." }),
      });
    }, async (delay) => delays.push(delay)),
    (error) => error instanceof AuditIncomplete && error.code === "PROVIDER_RATE_LIMITED",
  );
  assert.deepEqual([attempts, delays], [3, [60_000, 120_000]]);

  for (const retryAfter of ["invalid", "121"]) {
    attempts = 0;
    delays.length = 0;
    await assert.rejects(
      () => gh(["api", endpoint], async () => {
        attempts += 1;
        throw Object.assign(new Error("secondary rate limit"), {
          stdout: response("429 Too Many Requests", { message: "You have exceeded a secondary rate limit." }, { "Retry-After": retryAfter }),
        });
      }, async (delay) => delays.push(delay)),
      (error) => error instanceof AuditIncomplete && error.code === "PROVIDER_RATE_LIMITED",
    );
    assert.deepEqual([attempts, delays], [1, []]);
  }
});

test("documentation inventory audit memoizes immutable content", async () => {
  const headReads = new Map();
  const contentReads = new Map();
  const readHead = async (repository) => {
    headReads.set(repository, (headReads.get(repository) ?? 0) + 1);
    return SHA;
  };
  const readContent = async (repository, path, sha) => {
    const key = JSON.stringify([repository, path, sha]);
    contentReads.set(key, (contentReads.get(key) ?? 0) + 1);
    if (path === PATH) return {
      type: "file",
      sha: "d".repeat(40),
      encoding: "base64",
      content: Buffer.from(JSON.stringify(fragment(repository))).toString("base64"),
    };
    return { type: "file", sha: "c".repeat(40), encoding: "base64", content: Buffer.from("{}").toString("base64") };
  };

  const result = await collectLive(SCOPE, { sourceSha: SHA, readHead, readContent });
  assert.equal(result.stateBeginSha256, result.stateEndSha256);
  assert.deepEqual([...headReads.values()], [2, 2, 2, 2, 2]);
  assert.equal(contentReads.size, 10);
  assert.deepEqual([...contentReads.values()], Array(10).fill(1));
});

test("documentation inventory audit uses canonical public Git provider", async () => {
  assert.equal(typeof auditModule.createDocumentationInventoryGitProvider, "function");
  const directory = mkdtempSync(join(tmpdir(), "documentation-inventory-git-provider-"));
  const repositoryRoot = join(directory, "repositories");
  const calls = [];
  let commitIdentity = SHA;
  let objectType = "blob";
  const execute = async (executable, arguments_, options) => {
    calls.push({ executable, arguments_, options });
    if (arguments_[0] === "clone") {
      mkdirSync(arguments_.at(-1));
      return { stdout: "", stderr: "" };
    }
    if (arguments_.includes("fetch")) return { stdout: "", stderr: "" };
    if (arguments_.includes("refs/remotes/origin/main^{commit}")) return { stdout: `${SHA}\n`, stderr: "" };
    if (arguments_.includes(`${SHA}^{commit}`)) return { stdout: `${commitIdentity}\n`, stderr: "" };
    if (arguments_.includes("rev-parse")) return { stdout: `${"c".repeat(40)}\n`, stderr: "" };
    if (arguments_.includes("-t")) return { stdout: `${objectType}\n`, stderr: "" };
    if (arguments_.includes("cat-file")) return { stdout: Buffer.from("{}"), stderr: Buffer.alloc(0) };
    if (arguments_.includes("show")) return { stdout: Buffer.from("{}"), stderr: Buffer.alloc(0) };
    throw new Error("unexpected Git command");
  };

  try {
    const provider = await auditModule.createDocumentationInventoryGitProvider(SCOPE, { repositoryRoot, execute });
    await provider.refresh();
    assert.equal(await provider.readHead(REPOSITORIES[0], "main"), SHA);
    assert.deepEqual(await provider.readContent(REPOSITORIES[0], PATH, SHA), {
      type: "file",
      sha: "c".repeat(40),
      encoding: "base64",
      content: Buffer.from("{}").toString("base64"),
    });
    const showCount = calls.filter(({ arguments_ }) => arguments_.includes("show")).length;
    objectType = "tree";
    await assert.rejects(
      () => provider.readContent(REPOSITORIES[0], PATH, SHA),
      (error) => error instanceof AuditIncomplete && error.code === "RESOURCE_PROVIDER_MALFORMED",
    );
    assert.equal(calls.filter(({ arguments_ }) => arguments_.includes("show")).length, showCount);
    objectType = "blob";
    commitIdentity = "b".repeat(40);
    await assert.rejects(
      () => provider.readContent(REPOSITORIES[0], PATH, SHA),
      (error) => error instanceof AuditIncomplete && error.code === "GIT_PROVIDER_COMMIT_MISSING",
    );
    const clones = calls.filter(({ arguments_ }) => arguments_[0] === "clone");
    const fetches = calls.filter(({ arguments_ }) => arguments_.includes("fetch"));
    assert.equal(clones.length, 5);
    assert.equal(fetches.length, 5);
    assert.deepEqual(clones.map(({ arguments_ }) => arguments_.slice(0, -1)), REPOSITORIES.map((repository) => [
      "clone", "--no-checkout", "--single-branch", "--branch", "main", "--no-tags", `https://github.com/${repository}.git`,
    ]));
    assert.deepEqual(fetches.map(({ arguments_ }) => arguments_.slice(2)), REPOSITORIES.map((repository) => [
      "fetch", "--no-tags", `https://github.com/${repository}.git`, "+refs/heads/main:refs/remotes/origin/main",
    ]));
    for (const { executable, options } of calls) {
      assert.equal(executable, "/usr/bin/git");
      assert.equal(options.shell, false);
      assert.equal(options.env.GIT_TERMINAL_PROMPT, "0");
      assert.equal(options.env.GIT_CONFIG_GLOBAL, "/dev/null");
      assert.equal(Object.hasOwn(options.env, "GH_TOKEN"), false);
      assert.equal(Object.hasOwn(options.env, "GITHUB_TOKEN"), false);
      assert.equal(Object.hasOwn(options.env, "GIT_ASKPASS"), false);
    }

    let refreshCount = 0;
    let snapshotCount = 0;
    const pending = () => REPOSITORIES.map((repository) => ({
      repository,
      headSha: repository === REPOSITORIES[0] && snapshotCount === 2 ? SOURCE_SHA : SHA,
      state: "PENDING",
      fragmentStatus: "MISSING",
      fragmentBlobSha: null,
      fragment: null,
      resourceCount: 0,
      activeResourceCount: 0,
    }));
    await assert.rejects(() => collectLive(SCOPE, {
      sourceSha: SHA,
      refresh: async () => { refreshCount += 1; },
      collectSnapshot: async () => {
        snapshotCount += 1;
        return { repositories: pending(), watermark: `${snapshotCount}`.padStart(64, "0") };
      },
    }), (error) => error instanceof AuditIncomplete && error.code === "STATE_WATERMARK_DRIFT");
    assert.deepEqual([refreshCount, snapshotCount], [2, 2]);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("documentation inventory audit rejects unsafe Git provider inputs", async () => {
  assert.equal(typeof auditModule.createDocumentationInventoryGitProvider, "function");
  const invalidScope = structuredClone(SCOPE);
  invalidScope.repositories[0].repository = "AquilaXk/unowned";
  await assert.rejects(
    () => auditModule.createDocumentationInventoryGitProvider(invalidScope, { repositoryRoot: "/tmp/documentation-inventory-invalid" }),
    (error) => error instanceof AuditIncomplete && error.code === "GIT_PROVIDER_INPUT_INVALID",
  );
  await assert.rejects(
    () => auditModule.createDocumentationInventoryGitProvider(SCOPE, { repositoryRoot: "relative" }),
    (error) => error instanceof AuditIncomplete && error.code === "GIT_PROVIDER_INPUT_INVALID",
  );
  const directory = mkdtempSync(join(tmpdir(), "documentation-inventory-git-provider-invalid-"));
  const repositoryRoot = join(directory, "repositories");
  try {
    const provider = await auditModule.createDocumentationInventoryGitProvider(SCOPE, {
      repositoryRoot,
      execute: async (_executable, arguments_) => {
        if (arguments_[0] === "clone") {
          mkdirSync(arguments_.at(-1));
          return { stdout: "", stderr: "" };
        }
        throw new Error("must reject before Git read");
      },
    });
    await assert.rejects(
      () => provider.readHead(REPOSITORIES[0], "release"),
      (error) => error instanceof AuditIncomplete && error.code === "GIT_PROVIDER_INPUT_INVALID",
    );
    await assert.rejects(
      () => provider.readContent("AquilaXk/unowned", PATH, SHA),
      (error) => error instanceof AuditIncomplete && error.code === "GIT_PROVIDER_INPUT_INVALID",
    );
    await assert.rejects(
      () => provider.readContent(REPOSITORIES[0], "../secret", SHA),
      (error) => error instanceof AuditIncomplete && error.code === "GIT_PROVIDER_INPUT_INVALID",
    );
    await assert.rejects(
      () => auditModule.createDocumentationInventoryGitProvider(SCOPE, { repositoryRoot }),
      (error) => error instanceof AuditIncomplete && error.code === "GIT_PROVIDER_INPUT_INVALID",
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("documentation inventory audit workflow uses canonical public Git provider", () => {
  const workflow = readFileSync(".github/workflows/documentation-inventory-audit.yml", "utf8");
  assert.doesNotMatch(workflow, /GH_TOKEN:\s*\$\{\{ github\.token \}\}/);
  assert.match(workflow, /--repository-root "\$\{RUNNER_TEMP\}\/documentation-inventory-repositories-\$\{GITHUB_RUN_ID\}-\$\{GITHUB_RUN_ATTEMPT\}"/);
});
