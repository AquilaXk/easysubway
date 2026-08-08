import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { auditReferences, classifyImmutableLocator, classifyReference, collectCurrentInputs, createReport, discoverRepository, execGh, extractArtifactFindings, extractCanonicalPathFindings, extractReferences, normalizeItem, readBlob, resolveLatestEffectiveRecord, validateReport, validateScope } from "./audit-active-reference-drift.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

test("executed TRANSFER는 target issue를 canonical owner로 해석한다", () => {
  const result = resolveLatestEffectiveRecord({
    ledger: { issues: [{ sourceIssue: 7, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-mobile", targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/81", transferredAt: "2026-08-08T00:00:00.000Z" }] },
    amendments: { amendments: [] },
    sourceIssue: 7,
  });
  assert.deepEqual(result, {
    origin: "snapshot", disposition: "TRANSFER", canonicalRepository: "AquilaXk/easysubway-mobile", canonicalNumber: 81, pendingTransfer: false,
  });
});

test("executed TRANSFER의 Hub reference는 wrong owner finding이다", () => {
  const finding = classifyReference({
    source: { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/current.json", blobSha: "a".repeat(40), locator: "#7" },
    target: { repository: "AquilaXk/easysubway", type: "ISSUE", number: 7 },
  }, {
    ledger: { issues: [{ sourceIssue: 7, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-mobile", targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/81", transferredAt: "2026-08-08T00:00:00.000Z" }] },
    amendments: { amendments: [] }, openHubIssues: new Set(), item: { repository: "AquilaXk/easysubway", number: 7, type: "ISSUE", title: "source", state: "OPEN", stateReason: null, labels: [], milestone: null, parentOwner: null },
  });
  assert.equal(finding.code, "WRONG_REPOSITORY_OR_OWNER");
  assert.equal(finding.latestEffective.canonicalRepository, "AquilaXk/easysubway-mobile");
});

test("SPLIT_CHILDREN은 Hub parent와 exact child identity를 class별로 구분한다", () => {
  const ledger = { issues: [{ sourceIssue: 2548, disposition: "SPLIT_CHILDREN", childIssueUrls: {
    "AquilaXk/easysubway-backend": "https://github.com/AquilaXk/easysubway-backend/issues/31",
    "AquilaXk/easysubway-mobile": "https://github.com/AquilaXk/easysubway-mobile/issues/47",
  } }] };
  const amendments = { amendments: [] };
  const metadata = (repository, number) => ({ repository, number, type: "ISSUE", title: "split", state: "OPEN", stateReason: null, labels: [], milestone: null, parentOwner: null });
  const reference = (repository, number, referenceClass) => ({
    source: { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a.json", blobSha: "a".repeat(40), locator: `#${number}` },
    target: { repository, type: "ISSUE", number }, markers: { REFERENCE_CLASS: referenceClass },
  });
  assert.equal(classifyReference(reference("AquilaXk/easysubway", 2548, "ISSUE_PARENT_OR_COORDINATOR"), { ledger, amendments, item: metadata("AquilaXk/easysubway", 2548) }), null);
  assert.equal(classifyReference(reference("AquilaXk/easysubway-mobile", 47, "ISSUE_CURRENT_OWNER"), { ledger, amendments, item: metadata("AquilaXk/easysubway-mobile", 47) }), null);
  assert.equal(classifyReference(reference("AquilaXk/easysubway-backend", 31, "ISSUE_TERMINAL_IMPLEMENTATION"), { ledger, amendments, item: metadata("AquilaXk/easysubway-backend", 31) }), null);
  assert.equal(classifyReference(reference("AquilaXk/easysubway", 2548, "ISSUE_CURRENT_OWNER"), { ledger, amendments, item: metadata("AquilaXk/easysubway", 2548) }).code, "WRONG_REPOSITORY_OR_OWNER");
  assert.equal(classifyReference(reference("AquilaXk/easysubway-mobile", 47, "ISSUE_PARENT_OR_COORDINATOR"), { ledger, amendments, item: metadata("AquilaXk/easysubway-mobile", 47) }).code, "WRONG_REPOSITORY_OR_OWNER");
});

test("scope inventory와 GitHub collector는 누락 blob을 AUDIT_INCOMPLETE로 돌린다", async () => {
  const scope = {
    schemaVersion: 2,
    repositories: [
      { repository: "AquilaXk/easysubway", trackedDiscoveryRoots: ["README.md"] },
      { repository: "AquilaXk/easysubway-backend", trackedDiscoveryRoots: ["README.md"] },
      { repository: "AquilaXk/easysubway-data", trackedDiscoveryRoots: ["README.md"] },
      { repository: "AquilaXk/easysubway-mobile", trackedDiscoveryRoots: ["README.md"] },
      { repository: "AquilaXk/easysubway-platform", trackedDiscoveryRoots: ["README.md"] },
    ], contentClassification: { knownBinaryExtensions: [".gz", ".png"], bareReferenceExtensions: [".json", ".md", ".yaml", ".yml"] }, referenceClasses: ["ARTIFACT_IMMUTABLE_REFERENCE", "EXTERNAL_INPUT_PENDING_REFERENCE", "ISSUE_CURRENT_OWNER", "ISSUE_NONCLOSING_DEPENDENCY", "ISSUE_PARENT_OR_COORDINATOR", "ISSUE_TERMINAL_IMPLEMENTATION", "PATH_CANONICAL_CURRENT", "PATH_HISTORICAL_OR_SUPERSEDED", "PR_EVIDENCE_ONLY", "PR_IMPLEMENTATION"],
  };
  assert.deepEqual(validateScope(scope), []);
  const collected = await collectCurrentInputs({ scope, execGh: async () => "{}" });
  assert.equal(collected.repositories.length, 0);
  assert.equal(collected.incomplete.length, 5);
  const report = createReport({ observedAt: "2026-08-08T00:00:00.000Z", sourceSha: "a".repeat(40), scopeText: "{}", ledgerText: "{}", amendmentsText: "{}", incomplete: collected.incomplete });
  assert.equal(report.status, "AUDIT_INCOMPLETE");
  assert.equal(report.incomplete.length, 5);
});

test("Git tree는 configured directory의 descendant blob만 선택하고 root 누락을 거부한다", async () => {
  const responses = new Map([
    ["repos/AquilaXk/easysubway", { default_branch: "main" }],
    ["repos/AquilaXk/easysubway/git/ref/heads/main", { object: { sha: "a".repeat(40) } }],
    ["repos/AquilaXk/easysubway/git/trees/" + "a".repeat(40) + "?recursive=1", { tree: [
      { path: "contracts", type: "tree", mode: "040000", sha: "b".repeat(40) },
      { path: "contracts/a.json", type: "blob", mode: "100644", sha: "c".repeat(40) },
      { path: "README.md", type: "blob", mode: "100644", sha: "d".repeat(40) },
    ] }],
  ]);
  const runGh = async ([, endpoint]) => JSON.stringify(responses.get(endpoint));
  const input = await discoverRepository({ repository: "AquilaXk/easysubway", roots: ["README.md", "contracts"], execGh: runGh });
  assert.deepEqual(input.selected.map(({ path }) => path), ["README.md", "contracts/a.json"]);
  await assert.rejects(discoverRepository({ repository: "AquilaXk/easysubway", roots: ["missing"], execGh: runGh }), /missing configured root/);
});

test("pending TRANSFER의 Hub reference는 nonclosing dependency로 허용한다", () => {
  const finding = classifyReference({ source: { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a.json", blobSha: "a".repeat(40), locator: "#8" }, target: { repository: "AquilaXk/easysubway", type: "ISSUE", number: 8 }, markers: { REFERENCE_CLASS: "ISSUE_NONCLOSING_DEPENDENCY" } }, {
    ledger: { issues: [{ sourceIssue: 8, disposition: "TRANSFER", targetUrl: null }] }, amendments: { amendments: [] }, openHubIssues: new Set([8]),
    item: { repository: "AquilaXk/easysubway", number: 8, type: "ISSUE", title: "pending", state: "OPEN", stateReason: null, labels: [], milestone: null, parentOwner: null },
  });
  assert.equal(finding, null);
});

test("closed referenced issue와 unknown Hub open issue를 finding으로 분리한다", () => {
  const reference = { source: { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a.json", blobSha: "a".repeat(40), locator: "#9" }, target: { repository: "AquilaXk/easysubway", type: "ISSUE", number: 9 }, markers: { REFERENCE_CLASS: "ISSUE_CURRENT_OWNER" } };
  const closed = classifyReference(reference, { ledger: { issues: [] }, amendments: { amendments: [] }, item: { repository: "AquilaXk/easysubway", number: 9, type: "ISSUE", title: "closed", state: "CLOSED", stateReason: "completed", labels: [], milestone: null, parentOwner: null } });
  assert.equal(closed.code, "CLOSED_NOT_PLANNED_USED_AS_ACTIVE");
  const unknown = classifyReference(reference, { ledger: { issues: [] }, amendments: { amendments: [] }, openHubIssues: new Set([9]), item: { repository: "AquilaXk/easysubway", number: 9, type: "ISSUE", title: "open", state: "OPEN", stateReason: null, labels: [], milestone: null, parentOwner: null } });
  assert.equal(unknown.code, "UNKNOWN_OR_INVALID");
});

test("report는 canonical observedAt과 deterministic sorted inputs를 강제한다", () => {
  const report = createReport({ observedAt: "2026-08-08T00:00:00.000Z", sourceSha: "a".repeat(40), scopeText: "scope", ledgerText: "ledger", amendmentsText: "amendments", repositories: [{ repository: "AquilaXk/easysubway-mobile", defaultBranch: "main", gitSha: "b".repeat(40), selected: [] }, { repository: "AquilaXk/easysubway", defaultBranch: "main", gitSha: "c".repeat(40), selected: [] }] });
  assert.deepEqual(validateReport(report), []);
  assert.equal(report.inputs.repositories[0].repository, "AquilaXk/easysubway");
  report.observedAt = "2026-08-08T00:00:00Z";
  assert.ok(validateReport(report).some((error) => error.includes("canonical UTC")));
});

test("report finding은 body 없는 strict current metadata만 허용한다", () => {
  const schema = JSON.parse(readFileSync(resolve(projectRoot(), "contracts/documentation/reference-audit-report.schema.json"), "utf8"));
  const report = createReport({ observedAt: "2026-08-08T00:00:00.000Z", sourceSha: "a".repeat(40), scopeText: "scope", ledgerText: "ledger", amendmentsText: "amendments", findings: [{ code: "UNKNOWN_OR_INVALID", referenceClass: "ISSUE_NONCLOSING_DEPENDENCY", source: { kind: "ISSUE", repository: "AquilaXk/easysubway", number: 9, locator: "https://github.com/AquilaXk/easysubway/issues/9#body" }, target: { repository: "AquilaXk/easysubway", type: "ISSUE", number: 9 }, referenced: { repository: "AquilaXk/easysubway", number: 9, type: "ISSUE", title: "x", state: "OPEN", stateReason: null, labels: [], priority: null, milestone: null, parentOwner: null }, latestEffective: null, directOwner: null, consumerRoute: null, reason: "x" }] });
  assert.equal(validateSchema(schema, report).ok, true);
  report.findings[0].referenced.body = "parser-only";
  assert.equal(validateSchema(schema, report).ok, false);
});

test("exact markdown title and same-line markers alone become expectations", () => {
  const [reference] = extractReferences("[AquilaXk/easysubway#9 — exact](https://github.com/AquilaXk/easysubway/issues/9) [STATE:OPEN] [PRIORITY:P1]", { repository: "AquilaXk/easysubway", path: "contracts/a", blobSha: "a".repeat(40) });
  assert.equal(reference.displayedTitle, "exact");
  assert.equal(reference.markers.STATE, "OPEN");
  assert.equal(reference.markers.PRIORITY, "P1");
  assert.equal(classifyImmutableLocator("https://github.com/AquilaXk/easysubway/blob/main/a" ).code, "ARTIFACT_LOCATOR_MUTABLE_OR_UNVERIFIED");
  assert.equal(classifyImmutableLocator("https://github.com/AquilaXk/easysubway/git/blobs/" + "a".repeat(40) + "/a").code, "ARTIFACT_LOCATOR_MUTABLE_OR_UNVERIFIED");
  assert.equal(classifyImmutableLocator("https://github.com/AquilaXk/easysubway/blob/" + "a".repeat(40) + "/a"), null);
  assert.equal(classifyImmutableLocator("prefix https://github.com/AquilaXk/easysubway/blob/" + "a".repeat(40) + "/a suffix").code, "ARTIFACT_LOCATOR_MUTABLE_OR_UNVERIFIED");
  assert.equal(classifyImmutableLocator("ghcr.io/x/y@sha256:" + "A".repeat(64)).code, "ARTIFACT_LOCATOR_MUTABLE_OR_UNVERIFIED");
});

test("F1/F2: open item title/body sources are typed and markerless historical references are ignored", () => {
  const item = normalizeItem("AquilaXk/easysubway", { number: 9, title: "[AquilaXk/easysubway#7](https://github.com/AquilaXk/easysubway/issues/7) [REFERENCE_CLASS:ISSUE_CURRENT_OWNER]", body: "#8 closed history", state: "open", labels: [{ name: "p2" }] });
  assert.equal(item.type, "ISSUE");
  assert.equal(item.priority, "P2");
  assert.equal(extractReferences(item.title, { kind: "ISSUE", repository: item.repository, number: item.number, locator: "issue-title" })[0].markers.REFERENCE_CLASS, "ISSUE_CURRENT_OWNER");
  assert.equal(classifyReference(extractReferences(item.body, { kind: "ISSUE", repository: item.repository, number: item.number, locator: "issue-body" })[0], { ledger: { issues: [] }, amendments: { amendments: [] }, item: { ...item, number: 8, state: "CLOSED" } }), null);
});

test("F4/F5: noncanonical blobs and extra gh flags fail closed", async () => {
  await assert.rejects(readBlob("AquilaXk/easysubway", "a".repeat(40), async () => JSON.stringify({ encoding: "base64", content: "YQ" })), /base64/);
  await assert.rejects(execGh(["api", "repos/AquilaXk/easysubway", "--method", "PATCH"], async () => ({ stdout: "{}" })), /allowlisted/);
});

test("F7: malformed scope writes a sanitized AUDIT_INCOMPLETE report", () => {
  const fixture = createCliFixture();
  try {
    writeFileSync(join(fixture.root, "scope.json"), "{");
    const result = runCliFixture(fixture, "complete", "invalid.json");
    assert.equal(result.status, 2);
    assert.equal(JSON.parse(readFileSync(join(fixture.root, "invalid.json"), "utf8")).status, "AUDIT_INCOMPLETE");
  } finally { fixture.cleanup(); }
});

test("F6: symlinked input is rejected while the valid output stays contained", () => {
  const fixture = createCliFixture();
  try {
    writeFileSync(join(fixture.root, "outside.json"), "{}");
    rmSync(join(fixture.root, "scope.json"));
    symlinkSync(join(fixture.root, "outside.json"), join(fixture.root, "scope.json"));
    const result = runCliFixture(fixture, "complete", "symlink.json");
    assert.equal(result.status, 2);
    assert.equal(JSON.parse(readFileSync(join(fixture.root, "symlink.json"), "utf8")).status, "AUDIT_INCOMPLETE");
  } finally { fixture.cleanup(); }
});

test("F8: production scope roots are the current component roots", () => {
  const scope = JSON.parse(readFileSync(resolve(projectRoot(), "contracts/documentation/reference-audit-scope.json"), "utf8"));
  assert.deepEqual(scope.repositories.map(({ trackedDiscoveryRoots }) => trackedDiscoveryRoots), [
    [".github/PULL_REQUEST_TEMPLATE", "README.md", "contracts", "release/product-gates"],
    ["README.md", "contracts", "backend/src/main/resources"], ["README.md", "contracts", "release"],
    ["README.md", "contracts", "apps/mobile/release"], ["README.md", "contracts", "infra"],
  ]);
});

test("markerless PATH와 open item body reference도 baseline owner 검증과 PLAN_OWNER 수집에 포함한다", async () => {
  const repositories = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
  const blob = "b".repeat(40);
  const result = await auditReferences({ scope: {}, repositories: [{ repository: "AquilaXk/easysubway", selected: [{ path: "contracts/a.json", blobSha: blob }] }], ledger: { issues: [{ sourceIssue: 7, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-mobile", targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/81", transferredAt: "2026-08-08T00:00:00.000Z" }] }, amendments: { amendments: [] }, execGh: async ([, endpoint]) => {
    if (endpoint.endsWith("issues?state=open&per_page=100&page=1")) return JSON.stringify(endpoint.startsWith("repos/AquilaXk/easysubway/") ? [{ number: 9, title: "#7 [PLAN_OWNER:PLAN-DOC]", body: "#7 [PLAN_OWNER:PLAN-REPO]", state: "open", labels: [] }] : []);
    if (endpoint.endsWith(`/git/blobs/${blob}`)) return JSON.stringify({ encoding: "base64", content: Buffer.from("#7 [PLAN_OWNER:PLAN-DOC]").toString("base64") });
    if (endpoint === "repos/AquilaXk/easysubway/issues/7") return JSON.stringify({ number: 7, title: "source", state: "open", labels: [] });
    throw new Error(`unexpected ${endpoint}`);
  } });
  assert.equal(result.discovered, 3);
  assert.ok(result.findings.some((finding) => finding.code === "WRONG_REPOSITORY_OR_OWNER"));
  assert.ok(result.findings.some((finding) => finding.code === "PLAN_OWNER_OVERLAP"));
});

test("invalid PLAN_OWNER marker fails closed", () => {
  const [reference] = extractReferences("#7 [PLAN_OWNER:invalid]", { repository: "AquilaXk/easysubway", path: "contracts/a", blobSha: "a".repeat(40) });
  assert.equal(classifyReference(reference, { ledger: { issues: [] }, amendments: { amendments: [] }, item: { repository: "AquilaXk/easysubway", number: 7, type: "ISSUE", title: "x", state: "OPEN", stateReason: null, labels: [], priority: null, milestone: null, parentOwner: null } }).code, "PLAN_OWNER_OVERLAP");
});

test("explicit immutable artifact marker는 digest 또는 standard blob만 허용한다", () => {
  const source = { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a", blobSha: "a".repeat(40) };
  const [finding] = extractArtifactFindings("[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] ghcr.io/x/y:latest", source);
  assert.equal(finding.code, "ARTIFACT_LOCATOR_MUTABLE_OR_UNVERIFIED");
});

test("F3 marker line은 하나의 exact locator만 허용하고 invalid PLAN_OWNER도 fail-closed 한다", () => {
  const source = { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a", blobSha: "a".repeat(40) };
  for (const text of [
    "[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE]",
    "[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] contracts/a",
    "[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] prose https://github.com/AquilaXk/easysubway/blob/" + "a".repeat(40) + "/a",
    "[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] ghcr.io/x/y@sha256:" + "a".repeat(64) + " ghcr.io/x/z@sha256:" + "b".repeat(64),
  ]) assert.equal(extractArtifactFindings(text, source).length, 1);
  assert.equal(extractArtifactFindings("[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE]", source)[0].target.locator, "[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE]");
  assert.equal(extractArtifactFindings("[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] [UNKNOWN:value] ghcr.io/x/y@sha256:" + "a".repeat(64), source).length, 1);
  assert.equal(extractArtifactFindings("[REFERENCE_CLASS:PATH_CANONICAL_CURRENT] ghcr.io/x/y@sha256:" + "a".repeat(64), source).length, 1);
  assert.equal(extractArtifactFindings("[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] ghcr.io/x/y@sha256:" + "a".repeat(64) + " [PLAN_OWNER:bad]", source)[0].code, "PLAN_OWNER_OVERLAP");
});

test("unknown REFERENCE_CLASS issue marker는 UNKNOWN_OR_INVALID이다", () => {
  const [reference] = extractReferences("#7 [REFERENCE_CLASS:UNKNOWN]", { repository: "AquilaXk/easysubway", path: "contracts/a", blobSha: "a".repeat(40) });
  assert.equal(classifyReference(reference, { ledger: { issues: [] }, amendments: { amendments: [] }, item: { repository: "AquilaXk/easysubway", number: 7, type: "ISSUE", title: "x", state: "OPEN", stateReason: null, labels: [], priority: null, milestone: null, parentOwner: null } }).code, "UNKNOWN_OR_INVALID");
});

test("PATH_CANONICAL_CURRENT는 marker line blob locator를 current tree identity와 대조한다", () => {
  const source = { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a", blobSha: "a".repeat(40) };
  const current = { repository: "AquilaXk/easysubway", gitSha: "b".repeat(40), selected: [{ path: "contracts/current.json", blobSha: "c".repeat(40) }] };
  const findings = extractCanonicalPathFindings(`[REFERENCE_CLASS:PATH_CANONICAL_CURRENT] https://github.com/AquilaXk/easysubway/blob/${"a".repeat(40)}/contracts/current.json`, source, [current]);
  assert.equal(findings.length, 1);
  assert.deepEqual(findings[0].target, { repository: "AquilaXk/easysubway", type: "ARTIFACT", locator: `https://github.com/AquilaXk/easysubway/blob/${"a".repeat(40)}/contracts/current.json`, path: "contracts/current.json", blobSha: "c".repeat(40) });
});

test("artifact extraction emits only mutable current locator drift", () => {
  const source = { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a", blobSha: "a".repeat(40) };
  assert.equal(extractArtifactFindings("[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] https://github.com/AquilaXk/easysubway/blob/main/a", source).length, 1);
  assert.equal(extractArtifactFindings("[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] registry/x@sha256:" + "b".repeat(64), source).length, 0);
  assert.equal(extractArtifactFindings("[REFERENCE_CLASS:PATH_HISTORICAL_OR_SUPERSEDED] https://github.com/AquilaXk/easysubway/blob/" + "c".repeat(40) + "/a", source).length, 0);
});

test("F9-F13 reference source preserves issue variant, boundaries, artifact owner, and class type", () => {
  const source = { kind: "PR", repository: "AquilaXk/easysubway", number: 1, locator: "issue-body" };
  assert.equal(extractReferences("https://github.com/AquilaXk/easysubway/issues/7.", source)[0].source.kind, "PR");
  assert.equal(extractReferences("#123abc #123_ #123.", { kind: "PATH", repository: "AquilaXk/easysubway", path: "a.json", blobSha: "a".repeat(40) }).length, 1);
  const artifact = extractArtifactFindings("[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] https://github.com/AquilaXk/easysubway-mobile/blob/main/x", { kind: "PATH", repository: "AquilaXk/easysubway", path: "a", blobSha: "a".repeat(40) })[0];
  assert.equal(artifact.target.repository, "AquilaXk/easysubway-mobile");
  const [reference] = extractReferences("https://github.com/AquilaXk/easysubway/pull/7 [REFERENCE_CLASS:ISSUE_CURRENT_OWNER]", { kind: "PATH", repository: "AquilaXk/easysubway", path: "a", blobSha: "a".repeat(40) });
  assert.equal(classifyReference(reference, { ledger: { issues: [] }, amendments: { amendments: [] }, item: { repository: "AquilaXk/easysubway", number: 7, type: "PR", title: "x", state: "OPEN", stateReason: null, labels: [], priority: null, milestone: null, parentOwner: null } }).code, "ISSUE_PR_TYPE_CONFUSION");
});

test("F9 source variant is preserved in a schema-valid item-body finding", () => {
  const source = { kind: "ISSUE", repository: "AquilaXk/easysubway", number: 11, locator: "issue-body" };
  const [reference] = extractReferences("#7 [REFERENCE_CLASS:ISSUE_CURRENT_OWNER]", source);
  const finding = classifyReference(reference, { ledger: { issues: [] }, amendments: { amendments: [] }, item: null });
  assert.deepEqual(finding.source, { ...source, locator: "#7" });
  const schema = JSON.parse(readFileSync(resolve(projectRoot(), "contracts/documentation/reference-audit-report.schema.json"), "utf8"));
  const report = createReport({ observedAt: "2026-08-08T00:00:00.000Z", sourceSha: "a".repeat(40), scopeText: "scope", ledgerText: "ledger", amendmentsText: "amendments", findings: [finding] });
  assert.equal(validateSchema(schema, report).ok, true);
  const [pathReference] = extractReferences("#7", { repository: "AquilaXk/easysubway", path: "contracts/a.json", blobSha: "a".repeat(40) });
  assert.deepEqual(pathReference.source, { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a.json", blobSha: "a".repeat(40), locator: "#7" });
});

test("F10-F13 exact reference boundary, artifact owner, blob null and bidirectional class mismatch", () => {
  const pathSource = { kind: "PATH", repository: "AquilaXk/easysubway", path: "a.json", blobSha: "a".repeat(40) };
  assert.equal(extractReferences("#123abc #123_ #123.", pathSource).length, 1);
  assert.equal(extractArtifactFindings("[REFERENCE_CLASS:ARTIFACT_IMMUTABLE_REFERENCE] https://github.com/AquilaXk/easysubway-mobile/blob/main/a", pathSource)[0].target.repository, "AquilaXk/easysubway-mobile");
  assert.equal(extractCanonicalPathFindings("[REFERENCE_CLASS:PATH_CANONICAL_CURRENT] https://github.com/AquilaXk/easysubway/blob/" + "b".repeat(40) + "/missing", pathSource, [{ repository: "AquilaXk/easysubway", gitSha: "b".repeat(40), selected: [] }])[0].target.blobSha, null);
  for (const [url, referenceClass, type] of [["https://github.com/AquilaXk/easysubway/pull/7", "ISSUE_CURRENT_OWNER", "PR"], ["https://github.com/AquilaXk/easysubway/issues/7", "PR_IMPLEMENTATION", "ISSUE"]]) {
    const [reference] = extractReferences(`${url} [REFERENCE_CLASS:${referenceClass}]`, pathSource);
    assert.equal(classifyReference(reference, { ledger: { issues: [] }, amendments: { amendments: [] }, item: { repository: "AquilaXk/easysubway", number: 7, type, title: "x", state: "OPEN", stateReason: null, labels: [], priority: null, milestone: null, parentOwner: null } }).code, "ISSUE_PR_TYPE_CONFUSION");
  }
});

test("reference audit v2 scope와 report selected entry는 content classification을 고정한다", () => {
  const scopeSchema = JSON.parse(readFileSync(resolve(projectRoot(), "contracts/documentation/reference-audit-scope.schema.json"), "utf8"));
  const scope = JSON.parse(readFileSync(resolve(projectRoot(), "contracts/documentation/reference-audit-scope.json"), "utf8"));
  const reportSchema = JSON.parse(readFileSync(resolve(projectRoot(), "contracts/documentation/reference-audit-report.schema.json"), "utf8"));
  assert.equal(scope.schemaVersion, 2);
  assert.deepEqual(scope.contentClassification, {
    knownBinaryExtensions: [".gz", ".png"],
    bareReferenceExtensions: [".json", ".md", ".yaml", ".yml"],
  });
  assert.equal(validateSchema(scopeSchema, scope).ok, true);
  const selected = [
    { path: "README.md", blobSha: "b".repeat(40), contentClass: "AUDITABLE_TEXT" },
    { path: "assets/network.png", blobSha: "c".repeat(40), contentClass: "NON_REFERENCE_BINARY" },
  ];
  const report = createReport({ observedAt: "2026-08-08T00:00:00.000Z", sourceSha: "a".repeat(40), scopeText: "scope", ledgerText: "ledger", amendmentsText: "amendments", repositories: [{ repository: "AquilaXk/easysubway", defaultBranch: "main", gitSha: "a".repeat(40), selected }] });
  assert.equal(validateSchema(reportSchema, report).ok, true);
  assert.deepEqual(report.inputs.repositories[0].selected, selected);
  delete report.inputs.repositories[0].selected[0].contentClass;
  assert.equal(validateSchema(reportSchema, report).ok, false);
});

test("markdown link, qualified shorthand, bare PR, fragment, and explicit class conflict parse exactly once", () => {
  const source = { kind: "PATH", repository: "AquilaXk/easysubway", path: "README.md", blobSha: "a".repeat(40) };
  const [link] = extractReferences("[Hub Issue #9](https://github.com/AquilaXk/easysubway/issues/9#fragment)", source);
  assert.equal(extractReferences("[Hub Issue #9](https://github.com/AquilaXk/easysubway/issues/9#fragment)", source).length, 1);
  assert.deepEqual(link.target, { repository: "AquilaXk/easysubway", type: "ISSUE", number: 9 });
  assert.deepEqual(extractReferences("Data PR #8; Backend Issue #7; PR #6", source).map(({ target }) => target), [
    { repository: "AquilaXk/easysubway-data", type: "PR", number: 8 },
    { repository: "AquilaXk/easysubway-backend", type: "ISSUE", number: 7 },
    { repository: "AquilaXk/easysubway", type: "PR", number: 6 },
  ]);
  assert.equal(extractReferences("#5", source)[0].target.type, "ISSUE_OR_PR");
  const [conflict] = extractReferences("https://github.com/AquilaXk/easysubway/pull/4 [REFERENCE_CLASS:ISSUE_CURRENT_OWNER]", source);
  assert.equal(classifyReference(conflict, { ledger: { issues: [] }, amendments: { amendments: [] }, item: { repository: "AquilaXk/easysubway", number: 4, type: "PR", title: "x", state: "OPEN", stateReason: null, labels: [], priority: null, milestone: null, parentOwner: null } }).code, "ISSUE_PR_TYPE_CONFUSION");
});

test("issue body shorthand keeps qualifier repository and explicit type without duplicating markdown links", () => {
  const source = { kind: "ISSUE", repository: "AquilaXk/easysubway", number: 2783, locator: "body" };
  assert.deepEqual(extractReferences("Backend #10; Backend PR #95; PR #2775; #2748", source).map(({ target }) => target), [
    { repository: "AquilaXk/easysubway-backend", type: "ISSUE", number: 10 },
    { repository: "AquilaXk/easysubway-backend", type: "PR", number: 95 },
    { repository: "AquilaXk/easysubway", type: "PR", number: 2775 },
    { repository: "AquilaXk/easysubway", type: "ISSUE_OR_PR", number: 2748 },
  ]);
});

test("GitHub URL prefix accepts JSON, path and query suffixes without fragment duplicates", () => {
  const source = { kind: "ISSUE", repository: "AquilaXk/easysubway", number: 2784, locator: "body" };
  const references = extractReferences([
    '{"url":"https://github.com/AquilaXk/easysubway/issues/7"}',
    "https://github.com/AquilaXk/easysubway/pull/7/files",
    "https://github.com/AquilaXk/easysubway/issues/8?tab=discussion",
    "https://github.com/AquilaXk/easysubway/issues/9#123",
    "https://github.com/AquilaXk/easysubway/pull/10#issuecomment-42",
    "https://github.com/AquilaXk/easysubway/issues/71abc",
  ].join("\n"), source);
  assert.deepEqual(references.map(({ target }) => target), [
    { repository: "AquilaXk/easysubway", type: "ISSUE", number: 7 },
    { repository: "AquilaXk/easysubway", type: "PR", number: 7 },
    { repository: "AquilaXk/easysubway", type: "ISSUE", number: 8 },
    { repository: "AquilaXk/easysubway", type: "ISSUE", number: 9 },
    { repository: "AquilaXk/easysubway", type: "PR", number: 10 },
  ]);
});

test("fragment-suffixed canonical Markdown label preserves displayed title without duplication", () => {
  const source = { kind: "PATH", repository: "AquilaXk/easysubway", path: "README.md", blobSha: "a".repeat(40) };
  const references = extractReferences("[AquilaXk/easysubway#9 — exact title](https://github.com/AquilaXk/easysubway/issues/9#discussion)", source);
  assert.equal(references.length, 1);
  assert.equal(references[0].displayedTitle, "exact title");
});

test("bare references are limited to structured text paths while explicit references remain auditable", () => {
  const css = { kind: "PATH", repository: "AquilaXk/easysubway", path: "assets/theme.css", blobSha: "a".repeat(40) };
  const sql = { ...css, path: "db/V1__schema.sql" };
  assert.equal(extractReferences(".color { color: #123abc; } #571", css).length, 0);
  assert.equal(extractReferences("-- sha256 #571", sql).length, 0);
  assert.equal(extractReferences("https://github.com/AquilaXk/easysubway/issues/571", css).length, 1);
  assert.equal(extractReferences("#571 [REFERENCE_CLASS:ISSUE_CURRENT_OWNER]", css).length, 1);
});

test("nonclosing prose skips ledger ownership while structured path bare references preserve wrong-owner findings", () => {
  const ledger = { issues: [
    { sourceIssue: 1016, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-mobile", targetUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/81", transferredAt: "2026-08-08T00:00:00.000Z" },
    { sourceIssue: 571, disposition: "TRANSFER", targetRepository: "AquilaXk/easysubway-backend", targetUrl: "https://github.com/AquilaXk/easysubway-backend/issues/31", transferredAt: "2026-08-08T00:00:00.000Z" },
  ] };
  const item = (number) => ({ repository: "AquilaXk/easysubway", number, type: "ISSUE", title: "x", state: "OPEN", stateReason: null, labels: [], priority: null, milestone: null, parentOwner: null });
  const prose = extractReferences("#1016", { kind: "ISSUE", repository: "AquilaXk/easysubway", number: 1, locator: "body" })[0];
  const path = extractReferences("#1016", { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a.json", blobSha: "a".repeat(40) })[0];
  assert.equal(classifyReference(prose, { ledger, amendments: { amendments: [] }, item: item(1016) }), null);
  assert.equal(classifyReference(path, { ledger, amendments: { amendments: [] }, item: item(1016) }).code, "WRONG_REPOSITORY_OR_OWNER");
  const wrongOwner571 = extractReferences("#571", { kind: "PATH", repository: "AquilaXk/easysubway", path: "contracts/a.json", blobSha: "a".repeat(40) })[0];
  assert.equal(classifyReference(wrongOwner571, { ledger, amendments: { amendments: [] }, item: item(571) }).code, "WRONG_REPOSITORY_OR_OWNER");
});

test("selected text failures are per-path incomplete, binary blobs are not fetched, and later text remains audited", async () => {
  const blob = { first: "a".repeat(40), binary: "b".repeat(40), invalid: "c".repeat(40), tail: "d".repeat(40) };
  const calls = [];
  const repository = "AquilaXk/easysubway";
  const runGh = async ([, endpoint]) => {
    calls.push(endpoint);
    if (endpoint.endsWith("issues?state=open&per_page=100&page=1")) return JSON.stringify([]);
    if (endpoint.endsWith(`/git/blobs/${blob.first}`)) return JSON.stringify({ encoding: "base64", content: Buffer.from("no references").toString("base64") });
    if (endpoint.endsWith(`/git/blobs/${blob.invalid}`)) return JSON.stringify({ encoding: "base64", content: Buffer.from([0xc3, 0x28]).toString("base64") });
    if (endpoint.endsWith(`/git/blobs/${blob.tail}`)) return JSON.stringify({ encoding: "base64", content: Buffer.from("https://github.com/AquilaXk/easysubway/issues/9").toString("base64") });
    if (endpoint === `repos/${repository}/issues/9`) return JSON.stringify({ number: 9, title: "tail", state: "open", labels: [] });
    throw new Error(endpoint);
  };
  const result = await auditReferences({ scope: {}, ledger: { issues: [] }, amendments: { amendments: [] }, repositories: [{ repository, gitSha: "e".repeat(40), selected: [
    { path: "a.md", blobSha: blob.first, contentClass: "AUDITABLE_TEXT" },
    { path: "image.png", blobSha: blob.binary, contentClass: "NON_REFERENCE_BINARY" },
    { path: "invalid.md", blobSha: blob.invalid, contentClass: "AUDITABLE_TEXT" },
    { path: "tail.md", blobSha: blob.tail, contentClass: "AUDITABLE_TEXT" },
  ] }] , execGh: runGh });
  assert.equal(calls.some((endpoint) => endpoint.endsWith(`/git/blobs/${blob.binary}`)), false);
  assert.ok(result.incomplete.some(({ affectedIdentity }) => affectedIdentity === `${repository}:${"e".repeat(40)}:invalid.md:${blob.invalid}`));
  assert.equal(result.discovered, 1);
  assert.equal(result.validated, 1);
});

test("F14 repeated missing and closed references share one direct lookup per target", async () => {
  const blob = "b".repeat(40); const calls = new Map();
  const runGh = async ([, endpoint]) => {
    calls.set(endpoint, (calls.get(endpoint) ?? 0) + 1);
    if (endpoint.endsWith("issues?state=open&per_page=100&page=1")) return JSON.stringify(endpoint.startsWith("repos/AquilaXk/easysubway/") ? [{ number: 1, title: "#7 #8", body: "#7 #8", state: "open", labels: [] }] : []);
    if (endpoint.endsWith(`/git/blobs/${blob}`)) return JSON.stringify({ encoding: "base64", content: Buffer.from("#7 #8").toString("base64") });
    if (endpoint.endsWith("/issues/7")) return JSON.stringify({ number: 7, title: "closed", state: "closed", labels: [] });
    if (endpoint.endsWith("/issues/8")) { const error = new Error("missing"); error.status = 404; throw error; }
    throw new Error(endpoint);
  };
  await auditReferences({ scope: {}, repositories: [{ repository: "AquilaXk/easysubway", selected: [{ path: "a.json", blobSha: blob }] }], ledger: { issues: [] }, amendments: { amendments: [] }, execGh: runGh });
  assert.equal(calls.get("repos/AquilaXk/easysubway/issues/7"), 1);
  assert.equal(calls.get("repos/AquilaXk/easysubway/issues/8"), 1);
});

test("CLI는 fake gh 입력에서 complete/finding/incomplete와 write-once 출력을 구분한다", () => {
  const fixture = createCliFixture();
  try {
    const complete = runCliFixture(fixture, "complete", "complete.json");
    assert.equal(complete.status, 0, complete.stderr);
    const firstOutput = readFileSync(join(fixture.root, "complete.json"), "utf8");
    const repeat = runCliFixture(fixture, "complete", "complete.json");
    assert.equal(repeat.status, 2, repeat.stderr);
    assert.equal(readFileSync(join(fixture.root, "complete.json"), "utf8"), firstOutput, "wx must not overwrite an existing report");

    const sameInput = runCliFixture(fixture, "complete", "same.json");
    assert.equal(sameInput.status, 0, sameInput.stderr);
    assert.equal(readFileSync(join(fixture.root, "same.json"), "utf8"), firstOutput, "identical observed inputs must produce byte-identical reports");

    const finding = runCliFixture(fixture, "finding", "finding.json");
    assert.equal(finding.status, 1, finding.stderr);
    const incomplete = runCliFixture(fixture, "provider-error", "incomplete.json");
    assert.equal(incomplete.status, 2, incomplete.stderr);
    assert.doesNotMatch(incomplete.stderr, /provider-secret/);
    assert.equal(JSON.parse(readFileSync(join(fixture.root, "incomplete.json"), "utf8")).status, "AUDIT_INCOMPLETE");
    assert.equal(readFileSync(join(fixture.root, "complete.json"), "utf8"), firstOutput, "a prior complete report cannot satisfy a failed run");
  } finally {
    fixture.cleanup();
  }
});

function createCliFixture() {
  const root = mkdtempSync(join(tmpdir(), "reference-audit-cli-"));
  const bin = join(root, "bin");
  const repositories = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
  cpSync(resolve(projectRoot(), "release/migrations/repository-split-issues.json"), join(root, "ledger.json"));
  cpSync(resolve(projectRoot(), "release/migrations/repository-split-issues-amendments.json"), join(root, "amendments.json"));
  mkdirSync(bin);
  writeFileSync(join(root, "scope.json"), JSON.stringify({
    schemaVersion: 2,
    repositories: repositories.map((repository) => ({ repository, trackedDiscoveryRoots: ["README.md"] })),
    contentClassification: { knownBinaryExtensions: [".gz", ".png"], bareReferenceExtensions: [".json", ".md", ".yaml", ".yml"] },
    githubDiscovery: { includeOpenIssues: true, includeOpenPullRequests: true, maxItemsPerRepository: 1000 },
    referenceClasses: ["ARTIFACT_IMMUTABLE_REFERENCE", "EXTERNAL_INPUT_PENDING_REFERENCE", "ISSUE_CURRENT_OWNER", "ISSUE_NONCLOSING_DEPENDENCY", "ISSUE_PARENT_OR_COORDINATOR", "ISSUE_TERMINAL_IMPLEMENTATION", "PATH_CANONICAL_CURRENT", "PATH_HISTORICAL_OR_SUPERSEDED", "PR_EVIDENCE_ONLY", "PR_IMPLEMENTATION"],
  }));
  writeFileSync(join(root, "bin", "gh"), `#!/usr/bin/env node
const endpoint = process.argv.at(-1);
const repositories = ${JSON.stringify(repositories)};
const sha = "${"a".repeat(40)}";
const blob = "${"b".repeat(40)}";
if (process.env.FAKE_GH_MODE === "provider-error") { process.stderr.write("provider-secret\\n"); process.exit(9); }
const repository = repositories.find((value) => endpoint === "repos/" + value || endpoint.startsWith("repos/" + value + "/"));
const response = endpoint === "repos/AquilaXk/easysubway/issues/2548" ? { number: 2548, title: "split", state: "open", labels: [] }
  : endpoint.endsWith("/issues?state=open&per_page=100&page=1") ? []
  : endpoint.endsWith("/git/blobs/" + blob) ? { encoding: "base64", content: Buffer.from(process.env.FAKE_GH_MODE === "finding" && repository === "AquilaXk/easysubway" ? "https://github.com/AquilaXk/easysubway/issues/2548 [REFERENCE_CLASS:ISSUE_CURRENT_OWNER]" : "").toString("base64") }
  : endpoint.endsWith("/git/trees/" + sha + "?recursive=1") ? { tree: [{ path: "README.md", type: "blob", mode: "100644", sha: blob }] }
  : endpoint.endsWith("/git/ref/heads/main") ? { object: { sha } }
  : repository != null && endpoint === "repos/" + repository ? { default_branch: "main" }
  : null;
if (response === null) { process.stderr.write("unexpected endpoint\\n"); process.exit(3); }
process.stdout.write(JSON.stringify(response));
`);
  chmodSync(join(root, "bin", "gh"), 0o755);
  return { root, bin, cleanup: () => rmSync(root, { recursive: true, force: true }) };
}

function runCliFixture(fixture, mode, output) {
  return spawnSync(process.execPath, [resolve(projectRoot(), "tools/repo/audit-active-reference-drift.mjs"), "--scope", "scope.json", "--repository-root", fixture.root, "--source-sha", "a".repeat(40), "--ledger", "ledger.json", "--amendments", "amendments.json", "--observed-at", "2026-08-08T00:00:00.000Z", "--output", output], {
    cwd: fixture.root, encoding: "utf8", env: { ...process.env, PATH: `${fixture.bin}:${process.env.PATH}`, FAKE_GH_MODE: mode },
  });
}

function projectRoot() { return resolve(dirname(fileURLToPath(import.meta.url)), "../.."); }
