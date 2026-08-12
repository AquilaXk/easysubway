import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { deflateRawSync } from "node:zlib";

import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import {
  AuditIncomplete,
  auditCleanCheckoutReproducibility,
  collectArtifactCatalog,
  collectCurrentHeadWorkflowRuns,
  collectLive,
  evaluateReadyEvidence,
  readSingleReceiptZip,
  runAuditCli,
  selectCurrentHeadWorkflowRun,
  stableJson,
  validateCleanCheckoutReproducibilityReport,
  validateCleanCheckoutReproducibilityScope,
  validateOwnerContract,
  validateOwnerReceipt,
} from "./audit-clean-checkout-reproducibility.mjs";

const REPOSITORIES = [
  "AquilaXk/easysubway",
  "AquilaXk/easysubway-backend",
  "AquilaXk/easysubway-data",
  "AquilaXk/easysubway-mobile",
  "AquilaXk/easysubway-platform",
];
const SOURCE_SHA = "a".repeat(40);
const CONTRACT_DIGEST = "b".repeat(64);
const ARCHIVE_DIGEST = `sha256:${"c".repeat(64)}`;
const OBSERVED_AT = "2026-08-10T00:05:00.000Z";
const WATERMARK = "d".repeat(64);

const SCOPE = {
  schemaVersion: 2,
  slots: REPOSITORIES.map((repository) => ({
    repository,
    state: "PENDING",
    ownerIssue: null,
    evidenceSource: null,
  })),
};

const phase = (name, overrides = {}) => ({
  phase: name,
  entrypoint: `tools/repro/${name.toLowerCase()}.sh`,
  arguments: ["--ci"],
  workingDirectory: ".",
  requiredEnvironment: [],
  networkPolicy: name === "DEBUG" ? "LOCAL_ONLY" : "NONE",
  timeoutSeconds: name === "DEBUG" ? 120 : 600,
  expectedExitCode: 0,
  ...overrides,
});

const ownerContract = (repository = REPOSITORIES[0]) => ({
  schemaVersion: 1,
  repository,
  variants: [{
    variantId: "linux-default",
    runnerImage: "ubuntu-24.04",
    toolchainDigest: "e".repeat(64),
    phases: ["SETUP", "BUILD", "TEST", "DEBUG"].map((name) => phase(name)),
  }],
});

const commandDigest = (item) => createHash("sha256").update(stableJson({
  entrypoint: item.entrypoint,
  arguments: item.arguments,
  workingDirectory: item.workingDirectory,
})).digest("hex");

const ownerReceipt = (contract = ownerContract()) => ({
  schemaVersion: 1,
  repository: contract.repository,
  sourceSha: SOURCE_SHA,
  contractSha256: CONTRACT_DIGEST,
  observedAt: OBSERVED_AT,
  cleanCheckout: {
    repository: contract.repository,
    sourceSha: SOURCE_SHA,
    initialTrackedDiffCount: 0,
    initialUntrackedCount: 0,
  },
  variants: contract.variants.map((variant) => ({
    variantId: variant.variantId,
    runnerImage: variant.runnerImage,
    toolchainDigest: variant.toolchainDigest,
    phases: variant.phases.map((item, index) => ({
      phase: item.phase,
      commandSha256: commandDigest(item),
      startedAt: `2026-08-10T00:0${index}:00.000Z`,
      completedAt: `2026-08-10T00:0${index}:30.000Z`,
      exitCode: 0,
      timedOut: false,
      unexpectedProcessCount: 0,
    })),
  })),
});

const readySlot = (repository = REPOSITORIES[0]) => ({
  repository,
  state: "READY",
  ownerIssue: 123,
  evidenceSource: {
    contractPath: "contracts/reproducibility.json",
    workflowPath: ".github/workflows/reproducibility.yml",
    artifactNamePrefix: "clean-checkout-reproducibility-",
  },
});

const verifiedEvidence = (contract = ownerContract(), receipt = ownerReceipt(contract)) => ({
  repository: contract.repository,
  currentHead: SOURCE_SHA,
  issueState: "CLOSED",
  contractLocator: {
    kind: "GIT_BLOB",
    repository: contract.repository,
    commitSha: SOURCE_SHA,
    path: "contracts/reproducibility.json",
    blobSha: "f".repeat(40),
  },
  receiptLocator: {
    kind: "ACTIONS_ARTIFACT",
    repository: contract.repository,
    runId: 456,
    artifactId: 789,
    artifactName: `clean-checkout-reproducibility-${SOURCE_SHA}`,
    archiveDigest: ARCHIVE_DIGEST,
    workflowPath: ".github/workflows/reproducibility.yml",
    headSha: SOURCE_SHA,
    createdAt: "2026-08-10T00:00:00Z",
    expiresAt: "2026-08-24T00:00:00Z",
  },
  contract,
  contractText: JSON.stringify(contract),
  contractEntry: { path: "contracts/reproducibility.json", mode: "100644", type: "blob" },
  contractBlobSha: "f".repeat(40),
  contractSha256: CONTRACT_DIGEST,
  receipt,
  receiptArchiveDigest: ARCHIVE_DIGEST,
  run: {
    id: 456,
    conclusion: "success",
    path: ".github/workflows/reproducibility.yml",
    headSha: SOURCE_SHA,
    startedAt: "2026-08-10T00:00:00.000Z",
    completedAt: "2026-08-10T00:10:00.000Z",
  },
  artifact: {
    id: 789,
    name: `clean-checkout-reproducibility-${SOURCE_SHA}`,
    digest: ARCHIVE_DIGEST,
    runId: 456,
    headSha: SOURCE_SHA,
    expired: false,
    createdAt: "2026-08-10T00:00:00.000Z",
    expiresAt: "2026-08-24T00:00:00.000Z",
  },
  artifactCatalog: [{
    id: 789,
    name: `clean-checkout-reproducibility-${SOURCE_SHA}`,
    digest: ARCHIVE_DIGEST,
    runId: 456,
    headSha: SOURCE_SHA,
    expired: false,
    createdAt: "2026-08-10T00:00:00.000Z",
    expiresAt: "2026-08-24T00:00:00.000Z",
  }],
  entrypoints: contract.variants.flatMap((variant) => variant.phases.map((item) => ({ path: item.entrypoint, mode: "100755", type: "blob" }))),
});

test("clean checkout reproducibility audit accepts exact PENDING and owner contract shapes", () => {
  assert.deepEqual(validateCleanCheckoutReproducibilityScope(SCOPE), []);
  assert.deepEqual(validateOwnerContract(ownerContract()), []);
  const contractSchema = JSON.parse(readFileSync("contracts/documentation/clean-checkout-reproducibility-owner-contract.schema.json", "utf8"));
  assert.deepEqual(contractSchema.required, ["schemaVersion", "repository", "variants"]);
  assert.equal(Object.keys(contractSchema.properties).length, 3);
  assert.equal(["schemaVersion", "repository", "variants"].every((key) => Object.hasOwn(contractSchema.properties, key)), true);
  assert.equal(contractSchema.additionalProperties, false);
  const legacySelfReferentialContract = { ...ownerContract(), sourceSha: SOURCE_SHA };
  assert.notDeepEqual(validateOwnerContract(legacySelfReferentialContract), []);
  assert.deepEqual(validateOwnerReceipt(ownerReceipt()), []);
  const invalidScope = structuredClone(SCOPE);
  invalidScope.slots[0].ownerIssue = 123;
  assert.notDeepEqual(validateCleanCheckoutReproducibilityScope(invalidScope), []);
  const ready = structuredClone(SCOPE);
  ready.slots[0] = readySlot();
  assert.deepEqual(validateCleanCheckoutReproducibilityScope(ready), []);
  ready.slots[0].evidenceSource.artifactNamePrefix = "../receipt-";
  assert.notDeepEqual(validateCleanCheckoutReproducibilityScope(ready), []);
});

test("clean checkout reproducibility audit rejects phase, token, environment and DEBUG weakening", () => {
  for (const mutate of [
    (contract) => { contract.variants[0].phases[3].phase = "TEST"; },
    (contract) => { contract.variants[0].phases[0].entrypoint = "../setup.sh"; },
    (contract) => { contract.variants[0].phases[0].arguments = ["$(secret)"]; },
    (contract) => { contract.variants[0].phases[0].requiredEnvironment = ["TOKEN=value"]; },
    (contract) => { contract.variants[0].phases[3].networkPolicy = "DEPENDENCY_FETCH"; },
    (contract) => { contract.variants[0].phases[3].timeoutSeconds = 301; },
  ]) {
    const candidate = ownerContract();
    mutate(candidate);
    assert.notDeepEqual(validateOwnerContract(candidate), []);
  }
});

test("clean checkout reproducibility audit verifies one READY evidence path and reports completed mismatches", () => {
  const slot = readySlot();
  assert.deepEqual(evaluateReadyEvidence({ slot, evidence: verifiedEvidence(), now: "2026-08-10T12:00:00.000Z" }), []);
  for (const [mutate, code] of [
    [(evidence) => { evidence.issueState = "OPEN"; }, "OWNER_ISSUE_NOT_TERMINAL"],
    [(evidence) => { evidence.currentHead = "1".repeat(40); }, "CURRENT_HEAD_MISMATCH"],
    [(evidence) => { evidence.contractBlobSha = "1".repeat(40); }, "CONTRACT_BLOB_MISMATCH"],
    [(evidence) => { evidence.contractEntry.mode = "120000"; }, "CONTRACT_BLOB_MISMATCH"],
    [(evidence) => { evidence.receipt.cleanCheckout.initialTrackedDiffCount = 1; }, "CLEAN_CHECKOUT_DIRTY"],
    [(evidence) => { evidence.receipt.variants[0].phases[0].exitCode = 1; }, "PHASE_RESULT_MISMATCH"],
    [(evidence) => { evidence.receiptArchiveDigest = `sha256:${"0".repeat(64)}`; }, "RECEIPT_ARCHIVE_DIGEST_MISMATCH"],
    [(evidence) => { evidence.artifactCatalog = []; }, "ACTIONS_ARTIFACT_CATALOG_MISMATCH"],
    [(evidence) => { evidence.entrypoints[0].mode = "100644"; }, "ENTRYPOINT_NOT_EXECUTABLE"],
    [(evidence) => { evidence.run.conclusion = "failure"; }, "ACTIONS_RUN_MISMATCH"],
    [(evidence) => { evidence.run.id = 457; }, "ACTIONS_RUN_MISMATCH"],
    [(evidence) => { evidence.contractSha256 = "9".repeat(64); }, "CONTRACT_RECEIPT_DIGEST_MISMATCH"],
    [(evidence) => { evidence.receipt.observedAt = "2026-08-10T00:20:00.000Z"; }, "RECEIPT_TIME_MISMATCH"],
    [(evidence) => { evidence.receipt.variants[0].phases[0].commandSha256 = "9".repeat(64); }, "CONTRACT_RECEIPT_PHASE_MISMATCH"],
  ]) {
    const evidence = verifiedEvidence();
    mutate(evidence);
    assert.ok(evaluateReadyEvidence({ slot, evidence, now: "2026-08-10T12:00:00.000Z" }).some((finding) => finding.code === code), code);
  }
});

test("clean checkout reproducibility audit emits a complete five-PENDING report without claiming READY", () => {
  const records = REPOSITORIES.map((repository) => ({ repository, currentHead: SOURCE_SHA, issueState: null, evidenceState: "PENDING" }));
  const report = auditCleanCheckoutReproducibility({
    scope: SCOPE,
    sourceSha: SOURCE_SHA,
    observedAt: OBSERVED_AT,
    records,
    stateBeginSha256: WATERMARK,
    stateEndSha256: WATERMARK,
    scopeText: JSON.stringify(SCOPE),
  });
  assert.deepEqual([report.status, report.summary.pending, report.summary.ready, report.summary.findings, report.summary.incomplete], ["COMPLETE", 5, 0, 0, 0]);
  assert.deepEqual(report.slots.map(({ state, evidenceState }) => [state, evidenceState]), Array.from({ length: 5 }, () => ["PENDING", "PENDING"]));
  assert.deepEqual(validateCleanCheckoutReproducibilityReport(report), []);
});

test("clean checkout reproducibility audit accepts an exact five-READY provider-shaped result", () => {
  const scope = { schemaVersion: 2, slots: REPOSITORIES.map((repository) => readySlot(repository)) };
  const records = scope.slots.map((slot) => {
    const contract = ownerContract(slot.repository);
    const evidence = verifiedEvidence(contract, ownerReceipt(contract));
    const findings = evaluateReadyEvidence({ slot, evidence, now: "2026-08-10T12:00:00.000Z" });
    assert.deepEqual(findings, []);
    return { repository: slot.repository, currentHead: SOURCE_SHA, issueState: "CLOSED", evidenceState: "VERIFIED", findings, contractLocator: evidence.contractLocator, receiptLocator: evidence.receiptLocator };
  });
  const report = auditCleanCheckoutReproducibility({ scope, sourceSha: SOURCE_SHA, observedAt: OBSERVED_AT, records, stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK, scopeText: JSON.stringify(scope) });
  assert.deepEqual([report.status, report.summary.pending, report.summary.ready, report.summary.findings], ["COMPLETE", 0, 5, 0]);
  assert.deepEqual(validateCleanCheckoutReproducibilityReport(report), []);
  const missingEvidenceSource = structuredClone(report);
  missingEvidenceSource.slots[0].evidenceSource = null;
  assert.notDeepEqual(validateCleanCheckoutReproducibilityReport(missingEvidenceSource), []);
});

test("clean checkout reproducibility audit reports a missing current-head receipt without a circular locator", () => {
  const scope = structuredClone(SCOPE);
  scope.slots[0] = readySlot();
  const evidence = verifiedEvidence();
  const records = REPOSITORIES.map((repository, index) => index === 0 ? {
    repository,
    currentHead: SOURCE_SHA,
    issueState: "CLOSED",
    evidenceState: "FINDING",
    contractLocator: evidence.contractLocator,
    receiptLocator: null,
    findings: [{ code: "CURRENT_HEAD_RECEIPT_MISSING", repository }],
  } : { repository, currentHead: SOURCE_SHA, issueState: null, evidenceState: "PENDING", findings: [] });
  const report = auditCleanCheckoutReproducibility({ scope, sourceSha: SOURCE_SHA, observedAt: OBSERVED_AT, records, stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK, scopeText: JSON.stringify(scope) });
  const schema = JSON.parse(readFileSync("contracts/documentation/clean-checkout-reproducibility-audit-report.schema.json", "utf8"));
  assert.equal(validateSchema(schema, report).ok, true);
  assert.deepEqual(validateCleanCheckoutReproducibilityReport(report), []);
  assert.deepEqual([report.summary.ready, report.summary.findings, report.slots[0].receiptLocator, report.slots[0].evidenceState], [1, 1, null, "FINDING"]);
});

test("clean checkout reproducibility audit discovers only exact current-head successful workflow runs", async () => {
  const workflowPath = readySlot().evidenceSource.workflowPath;
  const rawRun = (id) => ({
    id,
    head_sha: SOURCE_SHA,
    path: workflowPath,
    event: "workflow_dispatch",
    status: "completed",
    conclusion: "success",
    run_started_at: "2026-08-10T00:00:00Z",
    updated_at: "2026-08-10T00:10:00Z",
  });
  const endpoints = [];
  const runs = await collectCurrentHeadWorkflowRuns(REPOSITORIES[0], {
    branch: "main",
    workflowPath,
    headSha: SOURCE_SHA,
  }, async ({ endpoint }) => {
    endpoints.push(endpoint);
    return { total_count: 1, workflow_runs: [rawRun(456)] };
  });
  assert.deepEqual(runs.map(({ id }) => id), [456]);
  assert.match(endpoints[0], /actions\/workflows\/reproducibility\.yml\/runs\?branch=main&event=workflow_dispatch&status=success&head_sha=a{40}&per_page=100&page=1$/);
  assert.equal(selectCurrentHeadWorkflowRun([], REPOSITORIES[0]), null);
  assert.throws(() => selectCurrentHeadWorkflowRun([runs[0], { ...runs[0], id: 457 }], REPOSITORIES[0]), (error) => error instanceof AuditIncomplete && error.code === "WORKFLOW_RUN_AMBIGUOUS");
  await assert.rejects(
    () => collectCurrentHeadWorkflowRuns(REPOSITORIES[0], { branch: "main", workflowPath, headSha: SOURCE_SHA }, async () => ({ total_count: 2, workflow_runs: [rawRun(456)] })),
    (error) => error instanceof AuditIncomplete && error.code === "WORKFLOW_RUN_CATALOG_COUNT_MISMATCH",
  );
  await assert.rejects(
    () => collectCurrentHeadWorkflowRuns(REPOSITORIES[0], { branch: "main", workflowPath, headSha: SOURCE_SHA }, async () => ({ total_count: 1, workflow_runs: [{ ...rawRun(456), event: "push" }] })),
    (error) => error instanceof AuditIncomplete && error.code === "WORKFLOW_RUN_IDENTITY_MISMATCH",
  );
});

test("clean checkout reproducibility audit freezes bounded artifact catalog pagination", async () => {
  const rawArtifact = (id) => ({
    id,
    name: `artifact-${id}`,
    digest: `sha256:${id.toString(16).padStart(64, "0")}`,
    expired: false,
    created_at: "2026-08-10T00:00:00Z",
    expires_at: "2026-08-24T00:00:00Z",
    workflow_run: { id: 456, head_sha: SOURCE_SHA },
  });
  const page = (number) => number === 1
    ? { total_count: 101, artifacts: Array.from({ length: 100 }, (_, index) => rawArtifact(index + 1)) }
    : { total_count: 101, artifacts: [rawArtifact(101)] };
  assert.equal((await collectArtifactCatalog(REPOSITORIES[0], 456, async ({ endpoint }) => page(Number(new URLSearchParams(endpoint.split("?")[1]).get("page"))))).length, 101);
  await assert.rejects(
    () => collectArtifactCatalog(REPOSITORIES[0], 456, async ({ endpoint }) => Number(new URLSearchParams(endpoint.split("?")[1]).get("page")) === 1
      ? { total_count: 101, artifacts: Array.from({ length: 100 }, (_, index) => rawArtifact(index + 1)) }
      : { total_count: 101, artifacts: [rawArtifact(100)] }),
    (error) => error instanceof AuditIncomplete && error.code === "ARTIFACT_CATALOG_DUPLICATE",
  );
  await assert.rejects(
    () => collectArtifactCatalog(REPOSITORIES[0], 456, async () => ({ total_count: 2, artifacts: [rawArtifact(1)] })),
    (error) => error instanceof AuditIncomplete && error.code === "ARTIFACT_CATALOG_COUNT_MISMATCH",
  );
});

test("clean checkout reproducibility audit detects source and normalized snapshot drift", async () => {
  let call = 0;
  await assert.rejects(
    () => collectLive(SCOPE, {
      sourceSha: SOURCE_SHA,
      collectSnapshot: async () => REPOSITORIES.map((repository, index) => ({ repository, currentHead: call++ === 0 || index !== 0 ? SOURCE_SHA : "1".repeat(40), issueState: null, evidenceState: "PENDING" })),
    }),
    (error) => error instanceof AuditIncomplete && error.code === "STATE_WATERMARK_DRIFT",
  );
});

test("clean checkout reproducibility audit decodes one exact receipt JSON ZIP entry", () => {
  const receipt = ownerReceipt();
  assert.deepEqual(JSON.parse(readSingleReceiptZip(zip("clean-checkout-reproducibility-owner-receipt.json", JSON.stringify(receipt)))), receipt);
  assert.deepEqual(JSON.parse(readSingleReceiptZip(zip("clean-checkout-reproducibility-owner-receipt.json", JSON.stringify(receipt), { dataDescriptor: true }))), receipt);
  assert.throws(() => readSingleReceiptZip(zip("other.json", JSON.stringify(receipt))), /RECEIPT_ARCHIVE_INVALID/);
});

test("clean checkout reproducibility audit CLI writes schema-valid exit 0, 1 and 2 reports and refuses overwrite", async () => {
  const directory = mkdtempSync(join(tmpdir(), "clean-checkout-reproducibility-"));
  const scopeSchema = readFileSync("contracts/documentation/clean-checkout-reproducibility-audit-scope.schema.json", "utf8");
  const reportSchema = readFileSync("contracts/documentation/clean-checkout-reproducibility-audit-report.schema.json", "utf8");
  const ownerContractSchema = readFileSync("contracts/documentation/clean-checkout-reproducibility-owner-contract.schema.json", "utf8");
  const ownerReceiptSchema = readFileSync("contracts/documentation/clean-checkout-reproducibility-owner-receipt.schema.json", "utf8");
  const parsedReportSchema = JSON.parse(reportSchema);
  const argv = (name) => [
    "--scope", "scope",
    "--scope-schema", "scope-schema",
    "--owner-contract-schema", "owner-contract-schema",
    "--owner-receipt-schema", "owner-receipt-schema",
    "--report-schema", "report-schema",
    "--source-sha", SOURCE_SHA,
    "--observed-at", OBSERVED_AT,
    "--output", join(directory, name),
  ];
  const read = async (path) => ({
    scope: JSON.stringify(SCOPE),
    "scope-schema": scopeSchema,
    "owner-contract-schema": ownerContractSchema,
    "owner-receipt-schema": ownerReceiptSchema,
    "report-schema": reportSchema,
  })[path];
  const pendingRecords = REPOSITORIES.map((repository) => ({ repository, currentHead: SOURCE_SHA, issueState: null, evidenceState: "PENDING" }));
  try {
    const success = await runAuditCli({ argv: argv("success.json"), read, collect: async () => ({ records: pendingRecords, stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK }) });
    assert.equal(success.exitCode, 0);
    assert.equal(validateSchema(parsedReportSchema, JSON.parse(readFileSync(join(directory, "success.json"), "utf8"))).ok, true);

    const finding = await runAuditCli({ argv: argv("finding.json"), read, collect: async () => ({ records: pendingRecords.map((record, index) => index === 0 ? { ...record, findings: [{ code: "CURRENT_HEAD_MISMATCH", repository: record.repository }] } : record), stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK }) });
    assert.equal(finding.exitCode, 1);

    const incomplete = await runAuditCli({ argv: argv("incomplete.json"), read, collect: async () => { throw new AuditIncomplete("PROVIDER_TIMEOUT", REPOSITORIES[0]); } });
    assert.equal(incomplete.exitCode, 2);
    assert.equal(validateSchema(parsedReportSchema, JSON.parse(readFileSync(join(directory, "incomplete.json"), "utf8"))).ok, true);

    const existing = join(directory, "existing.json");
    writeFileSync(existing, "existing\n");
    assert.equal((await runAuditCli({ argv: argv("existing.json"), read, collect: async () => ({ records: pendingRecords, stateBeginSha256: WATERMARK, stateEndSha256: WATERMARK }) })).exitCode, 2);
    assert.equal(readFileSync(existing, "utf8"), "existing\n");
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

function zip(name, text, { dataDescriptor = false } = {}) {
  const nameBytes = Buffer.from(name);
  const data = Buffer.from(text);
  const payload = dataDescriptor ? deflateRawSync(data) : data;
  const crc = crc32(data);
  const flags = 0x0800 | (dataDescriptor ? 0x0008 : 0);
  const method = dataDescriptor ? 8 : 0;
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(flags, 6); local.writeUInt16LE(method, 8);
  local.writeUInt32LE(dataDescriptor ? 0 : crc, 14); local.writeUInt32LE(dataDescriptor ? 0 : payload.length, 18); local.writeUInt32LE(dataDescriptor ? 0 : data.length, 22); local.writeUInt16LE(nameBytes.length, 26);
  const descriptor = dataDescriptor ? Buffer.alloc(16) : Buffer.alloc(0);
  if (dataDescriptor) {
    descriptor.writeUInt32LE(0x08074b50, 0); descriptor.writeUInt32LE(crc, 4); descriptor.writeUInt32LE(payload.length, 8); descriptor.writeUInt32LE(data.length, 12);
  }
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6); central.writeUInt16LE(flags, 8); central.writeUInt16LE(method, 10);
  central.writeUInt32LE(crc, 16); central.writeUInt32LE(payload.length, 20); central.writeUInt32LE(data.length, 24); central.writeUInt16LE(nameBytes.length, 28); central.writeUInt32LE(0o100644 * 65_536, 38);
  const centralOffset = local.length + nameBytes.length + payload.length + descriptor.length;
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0); eocd.writeUInt16LE(1, 8); eocd.writeUInt16LE(1, 10); eocd.writeUInt32LE(central.length + nameBytes.length, 12); eocd.writeUInt32LE(centralOffset, 16);
  return Buffer.concat([local, nameBytes, payload, descriptor, central, nameBytes, eocd]);
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return (crc ^ 0xffffffff) >>> 0;
}
