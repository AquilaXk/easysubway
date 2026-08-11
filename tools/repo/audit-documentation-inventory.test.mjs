import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import {
  AuditIncomplete,
  auditDocumentationInventory,
  collectLive,
  runAuditCli,
  validateDocumentationInventoryAuditReport,
  validateDocumentationInventoryAuditScope,
  verifyFragment,
} from "./audit-documentation-inventory.mjs";

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
const WATERMARK = "b".repeat(64);

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
    $schema: "./documentation-fragment.schema.json",
    schemaVersion: 1,
    repository,
    gitSha: SHA,
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

test("documentation inventory audit verifies tracked fragment blobs and rejects malformed or cross-head input", async () => {
  const candidate = fragment(REPOSITORIES[0]);
  const readContent = async (_repository, path, _sha) => path === PATH
    ? { type: "file", sha: "d".repeat(40), encoding: "base64", content: Buffer.from(JSON.stringify(candidate)).toString("base64") }
    : { type: "file", sha: "c".repeat(40), encoding: "base64", content: Buffer.from("{}").toString("base64") };
  const verified = await verifyFragment(SCOPE.repositories[0], SHA, { readContent });
  assert.deepEqual([verified.state, verified.fragmentStatus, verified.resourceCount, verified.activeResourceCount], ["READY", "ACTIVE", 1, 1]);
  await assert.rejects(() => verifyFragment(SCOPE.repositories[0], "b".repeat(40), { readContent }), (error) => error instanceof AuditIncomplete && error.code === "FRAGMENT_HEAD_MISMATCH");
  await assert.rejects(() => verifyFragment(SCOPE.repositories[0], SHA, { readContent: async () => ({ type: "file", sha: "d".repeat(40), encoding: "base64", content: "%%%" }) }), (error) => error instanceof AuditIncomplete && error.code === "FRAGMENT_DECODE_INVALID");
  const missing = await verifyFragment(SCOPE.repositories[0], SHA, { readContent: async () => { throw Object.assign(new Error("missing"), { status: 404 }); } });
  assert.deepEqual([missing.state, missing.fragmentStatus, missing.fragmentBlobSha], ["PENDING", "MISSING", null]);
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
  const argv = ["--scope", "scope", "--scope-schema", "scope-schema", "--report-schema", "report-schema", "--source-sha", SHA, "--observed-at", "2026-08-11T00:00:00.000Z", "--output", output];
  try {
    const result = await runAuditCli({ argv, read: async (path) => ({ scope: "{", "scope-schema": scopeSchema, "report-schema": reportSchema })[path], collect: async () => { throw new Error("must not collect"); } });
    const report = JSON.parse(readFileSync(output, "utf8"));
    assert.equal(result.exitCode, 2);
    assert.equal(validateSchema(JSON.parse(reportSchema), report).ok, true);
    assert.deepEqual([report.status, report.summary.pending, report.summary.ready, report.summary.incomplete], ["AUDIT_INCOMPLETE", 5, 0, 1]);
    writeFileSync(join(directory, "existing.json"), "existing\n");
    const existingArgv = [...argv.slice(0, -1), join(directory, "existing.json")];
    assert.equal((await runAuditCli({ argv: existingArgv, read: async (path) => ({ scope: JSON.stringify(SCOPE), "scope-schema": scopeSchema, "report-schema": reportSchema })[path], collect: async () => ({ repositories: pending, stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK }) })).exitCode, 2);
    assert.equal(readFileSync(join(directory, "existing.json"), "utf8"), "existing\n");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
