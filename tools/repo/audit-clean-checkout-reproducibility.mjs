#!/usr/bin/env node
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { open, readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { inflateRawSync } from "node:zlib";

import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";

export const REPOSITORIES = [
  "AquilaXk/easysubway",
  "AquilaXk/easysubway-backend",
  "AquilaXk/easysubway-data",
  "AquilaXk/easysubway-mobile",
  "AquilaXk/easysubway-platform",
];

const HUB = REPOSITORIES[0];
const REPOSITORY_SET = new Set(REPOSITORIES);
const PHASES = ["SETUP", "BUILD", "TEST", "DEBUG"];
const PHASE_SET = new Set(PHASES);
const SHA = /^[0-9a-f]{40}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const ARCHIVE_DIGEST = /^sha256:[0-9a-f]{64}$/;
const SAFE_PATH = /^(?!\/)(?!.*(?:^|\/)\.{1,2}(?:\/|$))(?!.*[?#])[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const SAFE_DIRECTORY = /^(?:\.|(?!\/)(?!.*(?:^|\/)\.{1,2}(?:\/|$))(?!.*[?#])[A-Za-z0-9][A-Za-z0-9._/-]*)$/;
const SAFE_ARGUMENT = /^(?!.*[?#])(?!.*(?:^|\/)\.\.(?:\/|$))[A-Za-z0-9._/@:+-]{1,256}$/;
const ENVIRONMENT_NAME = /^[A-Z][A-Z0-9_]{0,127}$/;
const VARIANT_ID = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const RUNNER_IMAGE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const ARTIFACT_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const WORKFLOW_PATH = /^(?!\/)(?!.*(?:^|\/)\.{1,2}(?:\/|$))(?!.*[?#])\.github\/workflows\/[A-Za-z0-9][A-Za-z0-9._/-]*\.ya?ml$/;
const CODE = /^[A-Z][A-Z0-9_]*$/;
const OUTPUT_LIMIT = 2 * 1024 * 1024;
const ARCHIVE_LIMIT = 16 * 1024 * 1024;
const ARTIFACT_PAGE_SIZE = 100;
const ARTIFACT_LIMIT = 1_000;
const RECEIPT_NAME = "clean-checkout-reproducibility-owner-receipt.json";
const execFileAsync = promisify(execFile);

export class AuditIncomplete extends Error {
  constructor(code, identity, inputs = {}) {
    super(code);
    this.code = code;
    this.identity = identity;
    this.inputs = inputs;
  }
}

const exactKeys = (value, keys) => value != null && typeof value === "object" && !Array.isArray(value)
  && Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
const canonicalUtc = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
const providerUtc = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/.test(value)
  && Number.isFinite(Date.parse(value));
const validInteger = (value, minimum = 0) => Number.isSafeInteger(value) && value >= minimum;
const compareFinding = (left, right) => codepointCompare(`${left.code}\0${left.repository}`, `${right.code}\0${right.repository}`);
const compareIncomplete = (left, right) => codepointCompare(`${left.stage}\0${left.code}\0${left.affectedIdentity}`, `${right.stage}\0${right.code}\0${right.affectedIdentity}`);
const unique = (values) => new Set(values).size === values.length;

export function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value != null && typeof value === "object") return `{${Object.keys(value).sort(codepointCompare).map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
}

function validContractLocator(locator, repository) {
  return exactKeys(locator, ["kind", "repository", "commitSha", "path", "blobSha"])
    && locator.kind === "GIT_BLOB" && locator.repository === repository && SHA.test(locator.commitSha)
    && SAFE_PATH.test(locator.path) && SHA.test(locator.blobSha);
}

function validReceiptLocator(locator, repository) {
  return exactKeys(locator, ["kind", "repository", "runId", "artifactId", "artifactName", "archiveDigest", "workflowPath", "headSha", "createdAt", "expiresAt"])
    && locator.kind === "ACTIONS_ARTIFACT" && locator.repository === repository
    && validInteger(locator.runId, 1) && validInteger(locator.artifactId, 1) && ARTIFACT_NAME.test(locator.artifactName)
    && ARCHIVE_DIGEST.test(locator.archiveDigest) && WORKFLOW_PATH.test(locator.workflowPath) && SHA.test(locator.headSha)
    && providerUtc(locator.createdAt) && providerUtc(locator.expiresAt) && Date.parse(locator.createdAt) < Date.parse(locator.expiresAt);
}

export function validateCleanCheckoutReproducibilityScope(scope, errors = []) {
  if (!exactKeys(scope, ["schemaVersion", "slots"]) || scope.schemaVersion !== 1 || !Array.isArray(scope.slots) || scope.slots.length !== REPOSITORIES.length) return [...errors, "slot inventory mismatch"];
  const repositories = scope.slots.map((slot) => slot?.repository);
  if (JSON.stringify(repositories) !== JSON.stringify(REPOSITORIES) || !unique(repositories)) errors.push("repository inventory mismatch");
  for (const slot of scope.slots) {
    const repository = slot?.repository ?? "unknown";
    if (!exactKeys(slot, ["repository", "state", "ownerIssue", "contractLocator", "receiptLocator"]) || !REPOSITORY_SET.has(repository)) { errors.push(`slot shape mismatch:${repository}`); continue; }
    if (slot.state === "PENDING") {
      if (slot.ownerIssue !== null || slot.contractLocator !== null || slot.receiptLocator !== null) errors.push(`pending slot mismatch:${repository}`);
    } else if (slot.state === "READY") {
      if (!validInteger(slot.ownerIssue, 1) || !validContractLocator(slot.contractLocator, repository) || !validReceiptLocator(slot.receiptLocator, repository)) errors.push(`ready slot mismatch:${repository}`);
    } else errors.push(`slot state mismatch:${repository}`);
  }
  return errors;
}

function validatePhase(item, errors, identity) {
  const keys = ["phase", "entrypoint", "arguments", "workingDirectory", "requiredEnvironment", "networkPolicy", "timeoutSeconds", "expectedExitCode"];
  if (!exactKeys(item, keys)) { errors.push(`phase shape mismatch:${identity}`); return; }
  if (!PHASE_SET.has(item.phase) || !SAFE_PATH.test(item.entrypoint) || !SAFE_DIRECTORY.test(item.workingDirectory)) errors.push(`phase identity mismatch:${identity}`);
  if (!Array.isArray(item.arguments) || item.arguments.length > 32 || item.arguments.some((value) => typeof value !== "string" || !SAFE_ARGUMENT.test(value))) errors.push(`phase arguments mismatch:${identity}`);
  if (!Array.isArray(item.requiredEnvironment) || item.requiredEnvironment.length > 32 || !unique(item.requiredEnvironment) || item.requiredEnvironment.some((value) => typeof value !== "string" || !ENVIRONMENT_NAME.test(value))) errors.push(`phase environment mismatch:${identity}`);
  if (!new Set(["NONE", "DEPENDENCY_FETCH", "LOCAL_ONLY"]).has(item.networkPolicy) || !validInteger(item.timeoutSeconds, 1) || item.timeoutSeconds > 3600 || item.expectedExitCode !== 0) errors.push(`phase execution mismatch:${identity}`);
  if (item.phase === "DEBUG" && (item.networkPolicy !== "LOCAL_ONLY" || item.timeoutSeconds > 300)) errors.push(`debug invariant mismatch:${identity}`);
}

export function validateOwnerContract(contract, errors = []) {
  if (!exactKeys(contract, ["schemaVersion", "repository", "sourceSha", "variants"]) || contract.schemaVersion !== 1 || !REPOSITORY_SET.has(contract.repository) || !SHA.test(contract.sourceSha ?? "") || !Array.isArray(contract.variants) || contract.variants.length < 1 || contract.variants.length > 16) return [...errors, "owner contract shape mismatch"];
  const ids = contract.variants.map((variant) => variant?.variantId);
  if (!unique(ids)) errors.push("duplicate contract variant");
  for (const variant of contract.variants) {
    const identity = `${contract.repository}:${variant?.variantId ?? "unknown"}`;
    if (!exactKeys(variant, ["variantId", "runnerImage", "toolchainDigest", "phases"]) || !VARIANT_ID.test(variant.variantId ?? "") || !RUNNER_IMAGE.test(variant.runnerImage ?? "") || !SHA256.test(variant.toolchainDigest ?? "") || !Array.isArray(variant.phases) || variant.phases.length !== PHASES.length) { errors.push(`contract variant mismatch:${identity}`); continue; }
    const phases = variant.phases.map((item) => item?.phase);
    if (!unique(phases) || PHASES.some((phase) => !phases.includes(phase))) errors.push(`contract phase set mismatch:${identity}`);
    for (const item of variant.phases) validatePhase(item, errors, `${identity}:${item?.phase ?? "unknown"}`);
  }
  return errors;
}

export function validateOwnerReceipt(receipt, errors = []) {
  if (!exactKeys(receipt, ["schemaVersion", "repository", "sourceSha", "contractSha256", "observedAt", "cleanCheckout", "variants"]) || receipt.schemaVersion !== 1 || !REPOSITORY_SET.has(receipt.repository) || !SHA.test(receipt.sourceSha ?? "") || !SHA256.test(receipt.contractSha256 ?? "") || !canonicalUtc(receipt.observedAt) || !Array.isArray(receipt.variants) || receipt.variants.length < 1 || receipt.variants.length > 16) return [...errors, "owner receipt shape mismatch"];
  const checkout = receipt.cleanCheckout;
  if (!exactKeys(checkout, ["repository", "sourceSha", "initialTrackedDiffCount", "initialUntrackedCount"]) || checkout.repository !== receipt.repository || checkout.sourceSha !== receipt.sourceSha || !validInteger(checkout.initialTrackedDiffCount) || !validInteger(checkout.initialUntrackedCount)) errors.push("clean checkout shape mismatch");
  const ids = receipt.variants.map((variant) => variant?.variantId);
  if (!unique(ids)) errors.push("duplicate receipt variant");
  for (const variant of receipt.variants) {
    const identity = `${receipt.repository}:${variant?.variantId ?? "unknown"}`;
    if (!exactKeys(variant, ["variantId", "runnerImage", "toolchainDigest", "phases"]) || !VARIANT_ID.test(variant.variantId ?? "") || !RUNNER_IMAGE.test(variant.runnerImage ?? "") || !SHA256.test(variant.toolchainDigest ?? "") || !Array.isArray(variant.phases) || variant.phases.length !== PHASES.length) { errors.push(`receipt variant mismatch:${identity}`); continue; }
    const phases = variant.phases.map((item) => item?.phase);
    if (!unique(phases) || PHASES.some((phase) => !phases.includes(phase))) errors.push(`receipt phase set mismatch:${identity}`);
    for (const item of variant.phases) {
      if (!exactKeys(item, ["phase", "commandSha256", "startedAt", "completedAt", "exitCode", "timedOut", "unexpectedProcessCount"]) || !PHASE_SET.has(item.phase) || !SHA256.test(item.commandSha256 ?? "") || !canonicalUtc(item.startedAt) || !canonicalUtc(item.completedAt) || Date.parse(item.startedAt) > Date.parse(item.completedAt) || !Number.isSafeInteger(item.exitCode) || typeof item.timedOut !== "boolean" || !validInteger(item.unexpectedProcessCount)) errors.push(`receipt phase mismatch:${identity}:${item?.phase ?? "unknown"}`);
    }
  }
  return errors;
}

function commandSha256(item) {
  return digest(Buffer.from(stableJson({ entrypoint: item.entrypoint, arguments: item.arguments, workingDirectory: item.workingDirectory })));
}

function finding(code, repository) {
  return { code, repository };
}

export function evaluateReadyEvidence({ slot, evidence, now = new Date().toISOString() }) {
  const repository = slot.repository;
  const findings = [];
  const add = (code) => { if (!findings.some((item) => item.code === code)) findings.push(finding(code, repository)); };
  if (evidence?.issueState !== "CLOSED") add("OWNER_ISSUE_NOT_TERMINAL");
  if (!SHA.test(evidence?.currentHead ?? "") || evidence.currentHead !== slot.contractLocator.commitSha || evidence.currentHead !== slot.receiptLocator.headSha) add("CURRENT_HEAD_MISMATCH");
  if (slot.contractLocator.repository !== repository || slot.receiptLocator.repository !== repository) add("OWNER_REPOSITORY_MISMATCH");
  if (evidence?.contractBlobSha !== slot.contractLocator.blobSha) add("CONTRACT_BLOB_MISMATCH");
  if (evidence?.receiptArchiveDigest !== slot.receiptLocator.archiveDigest) add("RECEIPT_ARCHIVE_DIGEST_MISMATCH");
  if (validateOwnerContract(evidence?.contract).length) add("OWNER_CONTRACT_INVALID");
  if (validateOwnerReceipt(evidence?.receipt).length) add("OWNER_RECEIPT_INVALID");
  const contract = evidence?.contract; const receipt = evidence?.receipt;
  if (contract?.repository !== repository || receipt?.repository !== repository || contract?.sourceSha !== evidence?.currentHead || receipt?.sourceSha !== evidence?.currentHead) add("OWNER_SOURCE_IDENTITY_MISMATCH");
  if (receipt?.contractSha256 !== evidence?.contractSha256) add("CONTRACT_RECEIPT_DIGEST_MISMATCH");
  if (receipt?.cleanCheckout?.repository !== repository || receipt?.cleanCheckout?.sourceSha !== evidence?.currentHead || receipt?.cleanCheckout?.initialTrackedDiffCount !== 0 || receipt?.cleanCheckout?.initialUntrackedCount !== 0) add("CLEAN_CHECKOUT_DIRTY");
  const run = evidence?.run; const artifact = evidence?.artifact;
  if (run?.conclusion !== "success" || run?.path !== slot.receiptLocator.workflowPath || run?.headSha !== evidence?.currentHead) add("ACTIONS_RUN_MISMATCH");
  const artifactCreatedAt = providerUtc(artifact?.createdAt) ? new Date(artifact.createdAt).toISOString() : null;
  const artifactExpiresAt = providerUtc(artifact?.expiresAt) ? new Date(artifact.expiresAt).toISOString() : null;
  if (artifact?.id !== slot.receiptLocator.artifactId || artifact?.name !== slot.receiptLocator.artifactName || artifact?.digest !== slot.receiptLocator.archiveDigest || artifact?.runId !== slot.receiptLocator.runId || artifact?.headSha !== evidence?.currentHead || artifact?.expired !== false || Date.parse(artifactExpiresAt ?? "") <= Date.parse(now) || artifactCreatedAt !== new Date(slot.receiptLocator.createdAt).toISOString() || artifactExpiresAt !== new Date(slot.receiptLocator.expiresAt).toISOString()) add("ACTIONS_ARTIFACT_MISMATCH");
  const catalogMatches = (evidence?.artifactCatalog ?? []).filter(({ id }) => id === slot.receiptLocator.artifactId);
  if (catalogMatches.length !== 1 || stableJson(catalogMatches[0]) !== stableJson(artifact)) add("ACTIONS_ARTIFACT_CATALOG_MISMATCH");
  if (!canonicalUtc(receipt?.observedAt) || Date.parse(receipt.observedAt) < Date.parse(run?.startedAt ?? "") || Date.parse(receipt.observedAt) > Date.parse(run?.completedAt ?? "")) add("RECEIPT_TIME_MISMATCH");
  const entrypoints = new Map((evidence?.entrypoints ?? []).map((entry) => [entry.path, entry]));
  if (evidence?.contractEntry?.mode !== "100644" && evidence?.contractEntry?.mode !== "100755" || evidence?.contractEntry?.type !== "blob") add("CONTRACT_BLOB_MISMATCH");
  for (const variant of contract?.variants ?? []) {
    const receiptVariant = (receipt?.variants ?? []).find((candidate) => candidate.variantId === variant.variantId);
    if (receiptVariant == null || receiptVariant.runnerImage !== variant.runnerImage || receiptVariant.toolchainDigest !== variant.toolchainDigest || receiptVariant.phases.length !== PHASES.length) { add("CONTRACT_RECEIPT_VARIANT_MISMATCH"); continue; }
    for (const contractPhase of variant.phases) {
      const entry = entrypoints.get(contractPhase.entrypoint);
      if (entry?.mode !== "100755" || entry?.type !== "blob") add("ENTRYPOINT_NOT_EXECUTABLE");
      const result = receiptVariant.phases.find((candidate) => candidate.phase === contractPhase.phase);
      if (result == null || result.commandSha256 !== commandSha256(contractPhase)) add("CONTRACT_RECEIPT_PHASE_MISMATCH");
      if (result == null || result.exitCode !== 0 || result.timedOut !== false || result.unexpectedProcessCount !== 0 || Date.parse(result.startedAt) > Date.parse(result.completedAt)) add("PHASE_RESULT_MISMATCH");
      if (result != null && (Date.parse(result.startedAt) < Date.parse(run?.startedAt ?? "") || Date.parse(result.completedAt) > Date.parse(run?.completedAt ?? "") || Date.parse(result.completedAt) > Date.parse(receipt?.observedAt ?? ""))) add("RECEIPT_TIME_MISMATCH");
    }
  }
  if ((receipt?.variants ?? []).length !== (contract?.variants ?? []).length) add("CONTRACT_RECEIPT_VARIANT_MISMATCH");
  return findings.sort(compareFinding);
}

function assertRecordSet(records) {
  if (!Array.isArray(records) || records.length !== REPOSITORIES.length || JSON.stringify(records.map(({ repository }) => repository)) !== JSON.stringify(REPOSITORIES) || !unique(records.map(({ repository }) => repository))) throw new AuditIncomplete("REPOSITORY_RESULT_IDENTITY", "repositories");
}

export function auditCleanCheckoutReproducibility({ scope, sourceSha, observedAt, records, stateBeginSha256 = null, stateEndSha256 = null, scopeText = JSON.stringify(scope) }) {
  assertRecordSet(records);
  const findings = records.flatMap((record) => Array.isArray(record.findings) ? record.findings : []).sort(compareFinding);
  const slots = scope.slots.map((slot, index) => {
    const record = records[index]; const recordFindings = Array.isArray(record.findings) ? record.findings : [];
    return {
      repository: slot.repository,
      state: slot.state,
      currentHead: SHA.test(record.currentHead ?? "") ? record.currentHead : null,
      ownerIssue: slot.ownerIssue,
      contractLocator: slot.contractLocator,
      receiptLocator: slot.receiptLocator,
      evidenceState: slot.state === "PENDING" ? "PENDING" : (recordFindings.length ? "FINDING" : "VERIFIED"),
    };
  });
  const pending = slots.filter(({ state }) => state === "PENDING").length;
  return {
    schemaVersion: 1,
    status: "COMPLETE",
    observedAt,
    inputs: { sourceSha, scopeSha256: digest(Buffer.from(scopeText)), stateBeginSha256, stateEndSha256 },
    summary: { pending, ready: slots.length - pending, findings: findings.length, incomplete: 0 },
    slots,
    findings,
    incomplete: [],
  };
}

export function validateCleanCheckoutReproducibilityReport(report, errors = []) {
  const top = ["schemaVersion", "status", "observedAt", "inputs", "summary", "slots", "findings", "incomplete"];
  if (!exactKeys(report, top) || report.schemaVersion !== 1 || !["COMPLETE", "AUDIT_INCOMPLETE"].includes(report.status) || !canonicalUtc(report.observedAt) || !Array.isArray(report.slots) || report.slots.length !== REPOSITORIES.length || JSON.stringify(report.slots.map(({ repository }) => repository)) !== JSON.stringify(REPOSITORIES) || !Array.isArray(report.findings) || !Array.isArray(report.incomplete)) return [...errors, "report shape mismatch"];
  if (!exactKeys(report.inputs, ["sourceSha", "scopeSha256", "stateBeginSha256", "stateEndSha256"]) || !SHA.test(report.inputs.sourceSha ?? "") || !SHA256.test(report.inputs.scopeSha256 ?? "")) errors.push("report inputs mismatch");
  if (!exactKeys(report.summary, ["pending", "ready", "findings", "incomplete"]) || !Object.values(report.summary).every((value) => validInteger(value))) errors.push("report summary mismatch");
  const pending = report.slots.filter(({ state }) => state === "PENDING").length;
  if (report.summary.pending !== pending || report.summary.ready !== REPOSITORIES.length - pending || report.summary.findings !== report.findings.length || report.summary.incomplete !== report.incomplete.length) errors.push("report count parity mismatch");
  if (report.slots.some((slot) => !exactKeys(slot, ["repository", "state", "currentHead", "ownerIssue", "contractLocator", "receiptLocator", "evidenceState"]) || !["PENDING", "READY"].includes(slot.state) || !["PENDING", "VERIFIED", "FINDING", "UNAVAILABLE"].includes(slot.evidenceState))) errors.push("report slot mismatch");
  const reportScope = { schemaVersion: 1, slots: report.slots.map(({ repository, state, ownerIssue, contractLocator, receiptLocator }) => ({ repository, state, ownerIssue, contractLocator, receiptLocator })) };
  if (validateCleanCheckoutReproducibilityScope(reportScope).length || report.slots.some((slot) => slot.state === "PENDING" ? !["PENDING", "UNAVAILABLE"].includes(slot.evidenceState) : !["VERIFIED", "FINDING", "UNAVAILABLE"].includes(slot.evidenceState))) errors.push("report slot state parity mismatch");
  if (report.findings.some((item) => !exactKeys(item, ["code", "repository"]) || !CODE.test(item.code ?? "") || !REPOSITORY_SET.has(item.repository)) || !unique(report.findings.map((item) => `${item.code}\0${item.repository}`))) errors.push("report findings mismatch");
  if (report.incomplete.some((item) => !exactKeys(item, ["stage", "code", "affectedIdentity"]) || !/^[a-z][a-z0-9-]*$/.test(item.stage ?? "") || !CODE.test(item.code ?? "") || !/^[A-Za-z0-9:._/-]+$/.test(item.affectedIdentity ?? "")) || !unique(report.incomplete.map((item) => `${item.stage}\0${item.code}\0${item.affectedIdentity}`))) errors.push("report incomplete mismatch");
  if (report.status === "COMPLETE") {
    if (report.incomplete.length !== 0 || !SHA256.test(report.inputs.stateBeginSha256 ?? "") || report.inputs.stateBeginSha256 !== report.inputs.stateEndSha256 || report.slots.some(({ currentHead, evidenceState }) => !SHA.test(currentHead ?? "") || evidenceState === "UNAVAILABLE") || report.slots[0].currentHead !== report.inputs.sourceSha) errors.push("report complete parity mismatch");
  } else if (report.incomplete.length < 1) errors.push("report incomplete status mismatch");
  return errors;
}

function normalizeSnapshot(records) {
  assertRecordSet(records);
  return records.map((record) => ({
    repository: record.repository,
    currentHead: record.currentHead,
    issueState: record.issueState ?? null,
    evidenceState: record.evidenceState,
    snapshotIdentity: record.snapshotIdentity ?? null,
    findings: (record.findings ?? []).slice().sort(compareFinding),
  }));
}

export async function collectLive(scope, { sourceSha, collectSnapshot = null, runGh = gh, now = new Date().toISOString(), ownerContractSchema = null, ownerReceiptSchema = null } = {}) {
  const snapshot = collectSnapshot ?? (() => collectLiveSnapshot(scope, { runGh, now, ownerContractSchema, ownerReceiptSchema }));
  const begin = await snapshot(); const end = await snapshot();
  const stateBeginSha256 = digest(Buffer.from(stableJson(normalizeSnapshot(begin))));
  const stateEndSha256 = digest(Buffer.from(stableJson(normalizeSnapshot(end))));
  const beginHub = begin.find(({ repository }) => repository === HUB)?.currentHead;
  const endHub = end.find(({ repository }) => repository === HUB)?.currentHead;
  if (beginHub !== sourceSha || endHub !== sourceSha || stateBeginSha256 !== stateEndSha256) throw new AuditIncomplete("STATE_WATERMARK_DRIFT", HUB, { stateBeginSha256, stateEndSha256 });
  return { records: begin, stateBeginSha256, stateEndSha256 };
}

async function collectLiveSnapshot(scope, { runGh, now, ownerContractSchema, ownerReceiptSchema }) {
  const records = [];
  for (const slot of scope.slots) {
    const currentHead = await collectRepositoryHead(slot.repository, runGh);
    if (slot.state === "PENDING") {
      records.push({ repository: slot.repository, currentHead, issueState: null, evidenceState: "PENDING", findings: [] });
      continue;
    }
    const evidence = await collectReadyEvidence(slot, { currentHead, runGh, ownerContractSchema, ownerReceiptSchema });
    const findings = evaluateReadyEvidence({ slot, evidence, now });
    records.push({
      repository: slot.repository,
      currentHead,
      issueState: evidence.issueState,
      evidenceState: findings.length ? "FINDING" : "VERIFIED",
      findings,
      snapshotIdentity: {
        issueState: evidence.issueState,
        contractBlobSha: evidence.contractBlobSha,
        contractSha256: evidence.contractSha256,
        receiptArchiveDigest: evidence.receiptArchiveDigest,
        artifact: evidence.artifact,
        artifactCatalog: evidence.artifactCatalog,
      },
    });
  }
  return records;
}

async function collectRepositoryHead(repository, runGh) {
  let metadata; let ref;
  try {
    metadata = await runGh({ endpoint: `repos/${repository}` });
    if (!/^[A-Za-z0-9._-]{1,255}$/.test(metadata?.default_branch ?? "")) throw new Error();
    ref = await runGh({ endpoint: `repos/${repository}/git/ref/heads/${metadata.default_branch}` });
  } catch (error) { providerFailure(error, "heads", repository); }
  if (ref?.ref !== `refs/heads/${metadata.default_branch}` || !SHA.test(ref?.object?.sha ?? "")) throw new AuditIncomplete("PROVIDER_MALFORMED", repository);
  return ref.object.sha;
}

async function collectReadyEvidence(slot, { currentHead, runGh, ownerContractSchema, ownerReceiptSchema }) {
  const repository = slot.repository;
  let issue; let contractResponse; let tree; let run; let artifact; let artifactCatalog; let archive;
  try {
    [issue, contractResponse, tree, run, artifact, artifactCatalog] = await Promise.all([
      runGh({ endpoint: `repos/${repository}/issues/${slot.ownerIssue}` }),
      runGh({ endpoint: `repos/${repository}/contents/${slot.contractLocator.path}?ref=${slot.contractLocator.commitSha}` }),
      runGh({ endpoint: `repos/${repository}/git/trees/${slot.contractLocator.commitSha}?recursive=1` }),
      runGh({ endpoint: `repos/${repository}/actions/runs/${slot.receiptLocator.runId}` }),
      runGh({ endpoint: `repos/${repository}/actions/artifacts/${slot.receiptLocator.artifactId}` }),
      collectArtifactCatalog(repository, slot.receiptLocator.runId, runGh),
    ]);
    archive = await runGh({ endpoint: `repos/${repository}/actions/artifacts/${slot.receiptLocator.artifactId}/zip`, binary: true });
  } catch (error) { providerFailure(error, "ready", repository); }
  if (issue?.number !== slot.ownerIssue || issue?.repository_url !== `https://api.github.com/repos/${repository}` || !["open", "closed"].includes(issue?.state)) throw new AuditIncomplete("PROVIDER_MALFORMED", repository);
  if (contractResponse?.type !== "file" || contractResponse?.encoding !== "base64" || !SHA.test(contractResponse?.sha ?? "") || typeof contractResponse?.content !== "string") throw new AuditIncomplete("PROVIDER_MALFORMED", repository);
  let contractText; let contract; let receiptText; let receipt;
  try {
    contractText = Buffer.from(contractResponse.content.replace(/\s/g, ""), "base64").toString("utf8");
    contract = JSON.parse(contractText);
    receiptText = readSingleReceiptZip(archive);
    receipt = JSON.parse(receiptText);
  } catch { throw new AuditIncomplete("OWNER_EVIDENCE_DECODE_INVALID", repository); }
  if (ownerContractSchema == null || ownerReceiptSchema == null || !validateSchema(ownerContractSchema, contract).ok || validateOwnerContract(contract).length) throw new AuditIncomplete("OWNER_CONTRACT_INVALID", repository);
  if (!validateSchema(ownerReceiptSchema, receipt).ok || validateOwnerReceipt(receipt).length) throw new AuditIncomplete("OWNER_RECEIPT_INVALID", repository);
  if (tree?.truncated !== false || !Array.isArray(tree?.tree)) throw new AuditIncomplete("PROVIDER_MALFORMED", repository);
  const paths = new Map(tree.tree.map((entry) => [entry?.path, { path: entry?.path, mode: entry?.mode, type: entry?.type }]));
  const contractEntry = paths.get(slot.contractLocator.path) ?? { path: slot.contractLocator.path, mode: null, type: null };
  const entrypoints = [...new Set(contract.variants.flatMap(({ phases }) => phases.map(({ entrypoint }) => entrypoint)))].map((path) => paths.get(path) ?? { path, mode: null, type: null });
  if (!Buffer.isBuffer(archive)) throw new AuditIncomplete("PROVIDER_MALFORMED", repository);
  const normalizedRun = normalizeRun(run, repository); const normalizedArtifact = normalizeArtifact(artifact, repository);
  return {
    repository,
    currentHead,
    issueState: issue.state.toUpperCase(),
    contract,
    contractText,
    contractBlobSha: contractResponse.sha,
    contractEntry,
    contractSha256: digest(Buffer.from(contractText)),
    receipt,
    receiptArchiveDigest: `sha256:${digest(archive)}`,
    run: normalizedRun,
    artifact: normalizedArtifact,
    artifactCatalog,
    entrypoints,
  };
}

export async function collectArtifactCatalog(repository, runId, runGh = gh) {
  if (!REPOSITORY_SET.has(repository) || !validInteger(runId, 1)) throw new AuditIncomplete("ARTIFACT_CATALOG_IDENTITY_INVALID", repository);
  const records = [];
  const ids = new Set();
  let totalCount = null;
  for (let page = 1; page <= ARTIFACT_LIMIT / ARTIFACT_PAGE_SIZE + 1; page += 1) {
    const response = await runGh({ endpoint: `repos/${repository}/actions/runs/${runId}/artifacts?per_page=${ARTIFACT_PAGE_SIZE}&page=${page}` });
    if (!validInteger(response?.total_count) || response.total_count > ARTIFACT_LIMIT || !Array.isArray(response?.artifacts) || response.artifacts.length > ARTIFACT_PAGE_SIZE) throw new AuditIncomplete("ARTIFACT_CATALOG_MALFORMED", repository);
    if (totalCount == null) totalCount = response.total_count;
    else if (response.total_count !== totalCount) throw new AuditIncomplete("ARTIFACT_CATALOG_COUNT_DRIFT", repository);
    for (const candidate of response.artifacts) {
      const normalized = normalizeArtifact(candidate, repository);
      if (ids.has(normalized.id)) throw new AuditIncomplete("ARTIFACT_CATALOG_DUPLICATE", repository);
      ids.add(normalized.id);
      records.push(normalized);
    }
    if (response.artifacts.length < ARTIFACT_PAGE_SIZE) {
      if (records.length !== totalCount) throw new AuditIncomplete("ARTIFACT_CATALOG_COUNT_MISMATCH", repository);
      return records.sort((left, right) => left.id - right.id);
    }
  }
  throw new AuditIncomplete("ARTIFACT_CATALOG_PAGE_LIMIT", repository);
}

function normalizeRun(run, repository) {
  if (typeof run?.conclusion !== "string" || typeof run?.path !== "string" || typeof run?.head_sha !== "string" || !providerUtc(run?.run_started_at) || !providerUtc(run?.updated_at)) throw new AuditIncomplete("PROVIDER_MALFORMED", repository);
  return { conclusion: run.conclusion, path: run.path, headSha: run.head_sha, startedAt: new Date(run.run_started_at).toISOString(), completedAt: new Date(run.updated_at).toISOString() };
}

function normalizeArtifact(artifact, repository) {
  if (!validInteger(artifact?.id, 1) || !ARTIFACT_NAME.test(artifact?.name ?? "") || typeof artifact?.expired !== "boolean" || !ARCHIVE_DIGEST.test(artifact?.digest ?? "") || !providerUtc(artifact?.created_at) || !providerUtc(artifact?.expires_at) || !validInteger(artifact?.workflow_run?.id, 1) || !SHA.test(artifact?.workflow_run?.head_sha ?? "")) throw new AuditIncomplete("PROVIDER_MALFORMED", repository);
  return { id: artifact.id, name: artifact.name, digest: artifact.digest, runId: artifact.workflow_run.id, headSha: artifact.workflow_run.head_sha, expired: artifact.expired, createdAt: new Date(artifact.created_at).toISOString(), expiresAt: new Date(artifact.expires_at).toISOString() };
}

function providerFailure(error, stage, identity) {
  if (error instanceof AuditIncomplete) throw error;
  const suffix = String(error?.status ?? error?.code ?? "UNAVAILABLE").toUpperCase().replace(/[^A-Z0-9_]/g, "_");
  throw new AuditIncomplete(CODE.test(`PROVIDER_${suffix}`) ? `PROVIDER_${suffix}` : "PROVIDER_UNAVAILABLE", identity, { stage });
}

export function readSingleReceiptZip(bytes) {
  try {
    if (!Buffer.isBuffer(bytes) || bytes.length < 22 || bytes.length > ARCHIVE_LIMIT) throw new Error();
    let eocd = -1;
    for (let offset = bytes.length - 22; offset >= Math.max(0, bytes.length - 65_557); offset -= 1) if (bytes.readUInt32LE(offset) === 0x06054b50) { eocd = offset; break; }
    if (eocd < 0 || eocd + 22 + bytes.readUInt16LE(eocd + 20) !== bytes.length || bytes.readUInt16LE(eocd + 4) !== 0 || bytes.readUInt16LE(eocd + 6) !== 0 || bytes.readUInt16LE(eocd + 8) !== 1 || bytes.readUInt16LE(eocd + 10) !== 1) throw new Error();
    const centralSize = bytes.readUInt32LE(eocd + 12); const centralOffset = bytes.readUInt32LE(eocd + 16);
    if (centralOffset + centralSize !== eocd || centralSize < 46 || bytes.readUInt32LE(centralOffset) !== 0x02014b50) throw new Error();
    const flags = bytes.readUInt16LE(centralOffset + 8); const method = bytes.readUInt16LE(centralOffset + 10); const crc = bytes.readUInt32LE(centralOffset + 16); const compressed = bytes.readUInt32LE(centralOffset + 20); const size = bytes.readUInt32LE(centralOffset + 24); const nameLength = bytes.readUInt16LE(centralOffset + 28); const extraLength = bytes.readUInt16LE(centralOffset + 30); const commentLength = bytes.readUInt16LE(centralOffset + 32); const external = bytes.readUInt32LE(centralOffset + 38); const localOffset = bytes.readUInt32LE(centralOffset + 42);
    if ((flags & ~0x0800) !== 0 || ![0, 8].includes(method) || compressed > ARCHIVE_LIMIT || size > OUTPUT_LIMIT || centralOffset + 46 + nameLength + extraLength + commentLength !== eocd || Math.floor(external / 65_536) >> 12 === 0xa || localOffset + 30 > centralOffset || bytes.readUInt32LE(localOffset) !== 0x04034b50) throw new Error();
    const centralName = bytes.subarray(centralOffset + 46, centralOffset + 46 + nameLength); const name = new TextDecoder("utf-8", { fatal: true }).decode(centralName);
    const localNameLength = bytes.readUInt16LE(localOffset + 26); const localExtraLength = bytes.readUInt16LE(localOffset + 28); const localName = bytes.subarray(localOffset + 30, localOffset + 30 + localNameLength);
    if (name !== RECEIPT_NAME || !localName.equals(centralName) || bytes.readUInt16LE(localOffset + 6) !== flags || bytes.readUInt16LE(localOffset + 8) !== method || bytes.readUInt32LE(localOffset + 14) !== crc || bytes.readUInt32LE(localOffset + 18) !== compressed || bytes.readUInt32LE(localOffset + 22) !== size) throw new Error();
    const dataOffset = localOffset + 30 + localNameLength + localExtraLength; const data = bytes.subarray(dataOffset, dataOffset + compressed);
    if (data.length !== compressed || dataOffset + compressed !== centralOffset) throw new Error();
    const decoded = method === 0 ? data : inflateRawSync(data, { maxOutputLength: OUTPUT_LIMIT });
    if (decoded.length !== size || crc32(decoded) !== crc) throw new Error();
    return new TextDecoder("utf-8", { fatal: true }).decode(decoded);
  } catch { throw new Error("RECEIPT_ARCHIVE_INVALID"); }
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) { crc ^= byte; for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); }
  return (crc ^ 0xffffffff) >>> 0;
}

function allowedEndpoint(endpoint, binary) {
  const repository = "AquilaXk/easysubway(?:-(?:backend|data|mobile|platform))?";
  const path = "[A-Za-z0-9][A-Za-z0-9._/-]*";
  const common = new RegExp(`^repos/${repository}(?:$|/git/ref/heads/[A-Za-z0-9._-]{1,255}$|/issues/[1-9]\\d*$|/contents/${path}\\?ref=[0-9a-f]{40}$|/git/trees/[0-9a-f]{40}\\?recursive=1$|/actions/runs/[1-9]\\d*$|/actions/runs/[1-9]\\d*/artifacts\\?per_page=100&page=[1-9]\\d*$|/actions/artifacts/[1-9]\\d*(?:/zip)?$)`);
  if (!common.test(endpoint) || endpoint.includes("..")) return false;
  return binary ? /\/actions\/artifacts\/[1-9]\d*\/zip$/.test(endpoint) : !endpoint.endsWith("/zip");
}

export async function gh({ endpoint, binary = false }, execute = execFileAsync) {
  if (typeof endpoint !== "string" || !allowedEndpoint(endpoint, binary)) throw new AuditIncomplete("PROVIDER_ENDPOINT_REJECTED", "github");
  try {
    const { stdout } = await execute("gh", ["api", "--method", "GET", endpoint], { encoding: binary ? null : "utf8", timeout: 30_000, killSignal: "SIGTERM", maxBuffer: binary ? ARCHIVE_LIMIT : OUTPUT_LIMIT });
    if (binary) return Buffer.isBuffer(stdout) ? stdout : Buffer.from(stdout);
    return JSON.parse(stdout);
  } catch (error) { providerFailure(error, "github", endpoint.split("/").slice(0, 3).join("/")); }
}

function fallbackScope() {
  return { schemaVersion: 1, slots: REPOSITORIES.map((repository) => ({ repository, state: "PENDING", ownerIssue: null, contractLocator: null, receiptLocator: null })) };
}

function incompleteReport({ scope, sourceSha, observedAt, scopeText, code, identity, stage = "audit", inputs = {} }) {
  const slots = scope.slots.map((slot) => ({ repository: slot.repository, state: slot.state, currentHead: null, ownerIssue: slot.ownerIssue, contractLocator: slot.contractLocator, receiptLocator: slot.receiptLocator, evidenceState: "UNAVAILABLE" }));
  const pending = slots.filter(({ state }) => state === "PENDING").length;
  return {
    schemaVersion: 1,
    status: "AUDIT_INCOMPLETE",
    observedAt,
    inputs: { sourceSha, scopeSha256: digest(Buffer.from(scopeText)), stateBeginSha256: inputs.stateBeginSha256 ?? null, stateEndSha256: inputs.stateEndSha256 ?? null },
    summary: { pending, ready: slots.length - pending, findings: 0, incomplete: 1 },
    slots,
    findings: [],
    incomplete: [{ stage, code: CODE.test(code ?? "") ? code : "AUDIT_FAILURE", affectedIdentity: /^[A-Za-z0-9:._/-]+$/.test(identity ?? "") ? identity : "audit" }],
  };
}

function parseArgs(argv) {
  if (argv.length !== 16 || argv[0] !== "--scope" || argv[2] !== "--scope-schema" || argv[4] !== "--owner-contract-schema" || argv[6] !== "--owner-receipt-schema" || argv[8] !== "--report-schema" || argv[10] !== "--source-sha" || argv[12] !== "--observed-at" || argv[14] !== "--output" || !SHA.test(argv[11]) || !canonicalUtc(argv[13]) || typeof argv[15] !== "string" || argv[15].length === 0) throw new AuditIncomplete("ARGUMENT_INVALID", "cli");
  return { scopePath: argv[1], scopeSchemaPath: argv[3], ownerContractSchemaPath: argv[5], ownerReceiptSchemaPath: argv[7], reportSchemaPath: argv[9], sourceSha: argv[11], observedAt: argv[13], output: argv[15] };
}

async function writeOnce(path, report) {
  const file = await open(path, "wx");
  try { await file.writeFile(`${JSON.stringify(report, null, 2)}\n`); } finally { await file.close(); }
}

export async function runAuditCli({ argv = process.argv.slice(2), read = (path) => readFile(path, "utf8"), collect = null } = {}) {
  let parsed; let scope = fallbackScope(); let scopeText = JSON.stringify(scope); let reportSchema = null; let report;
  try {
    parsed = parseArgs(argv);
    const [candidateScopeText, scopeSchemaText, ownerContractSchemaText, ownerReceiptSchemaText, reportSchemaText] = await Promise.all([read(parsed.scopePath), read(parsed.scopeSchemaPath), read(parsed.ownerContractSchemaPath), read(parsed.ownerReceiptSchemaPath), read(parsed.reportSchemaPath)]);
    let scopeSchema; let ownerContractSchema; let ownerReceiptSchema;
    try { scope = JSON.parse(candidateScopeText); scopeText = candidateScopeText; scopeSchema = JSON.parse(scopeSchemaText); ownerContractSchema = JSON.parse(ownerContractSchemaText); ownerReceiptSchema = JSON.parse(ownerReceiptSchemaText); reportSchema = JSON.parse(reportSchemaText); } catch { throw new AuditIncomplete("SCHEMA_OR_SCOPE_INVALID", "schema"); }
    if (!validateSchema(scopeSchema, scope).ok || validateCleanCheckoutReproducibilityScope(scope).length) throw new AuditIncomplete("SCOPE_INVALID", "scope");
    const collectResult = collect == null
      ? await collectLive(scope, { sourceSha: parsed.sourceSha, ownerContractSchema, ownerReceiptSchema })
      : await collect({ scope, sourceSha: parsed.sourceSha, ownerContractSchema, ownerReceiptSchema });
    report = auditCleanCheckoutReproducibility({ scope, sourceSha: parsed.sourceSha, observedAt: parsed.observedAt, records: collectResult.records, stateBeginSha256: collectResult.stateBeginSha256, stateEndSha256: collectResult.stateEndSha256, scopeText });
    if (!validateSchema(reportSchema, report).ok || validateCleanCheckoutReproducibilityReport(report).length) throw new AuditIncomplete("REPORT_INVALID", "report");
    await writeOnce(parsed.output, report);
    return { exitCode: report.findings.length ? 1 : 0, report };
  } catch (error) {
    const sourceSha = parsed?.sourceSha ?? "0".repeat(40); const observedAt = parsed?.observedAt ?? "1970-01-01T00:00:00.000Z";
    if (validateCleanCheckoutReproducibilityScope(scope).length) { scope = fallbackScope(); scopeText = JSON.stringify(scope); }
    report = incompleteReport({ scope, sourceSha, observedAt, scopeText, code: error?.code, identity: error?.identity, stage: error?.inputs?.stage ?? "audit", inputs: error?.inputs ?? {} });
    try {
      if (reportSchema != null && (!validateSchema(reportSchema, report).ok || validateCleanCheckoutReproducibilityReport(report).length)) throw new Error();
      if (parsed?.output != null) await writeOnce(parsed.output, report);
    } catch { /* preserve create-only output and sanitized failure */ }
    return { exitCode: 2, report };
  }
}

if (isMainModule(import.meta.url)) {
  const result = await runAuditCli();
  process.exitCode = result.exitCode;
}
