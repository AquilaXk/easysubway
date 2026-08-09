import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { open, readFile, realpath, lstat } from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateRawSync } from "node:zlib";

import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

export const REPOSITORIES = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
export const SURFACES = ["REPOSITORY_SECURITY_RECEIPT", "ISSUE_TITLE", "ISSUE_BODY", "ISSUE_COMMENT", "PR_TITLE", "PR_BODY", "PR_COMMENT", "PR_REVIEW_BODY", "PR_REVIEW_COMMENT", "COMMIT_COMMENT", "RELEASE_METADATA", "PUBLIC_ARTIFACT"];
export const DETECTORS = ["PRIVATE_KEY_BLOCK", "KNOWN_TOKEN_FORMAT", "AUTHORIZATION_VALUE", "SIGNED_URL_QUERY", "PRIVATE_ABSOLUTE_PATH", "RAW_PROVIDER_PAYLOAD", "RAW_USER_PAYLOAD"];
const PAGE_LIMIT = 1000;
const OUTPUT_LIMIT = 2 * 1024 * 1024;
const BINARY_OUTPUT_LIMIT = 16 * 1024 * 1024;

export function validateScope(scope, errors = []) {
  if (scope?.schemaVersion !== 1) errors.push("INVALID_SCOPE");
  if (JSON.stringify(scope?.repositories?.map(({ repository }) => repository)) !== JSON.stringify(REPOSITORIES)) errors.push("INVALID_REPOSITORIES");
  if (JSON.stringify(scope?.surfaces) !== JSON.stringify(SURFACES) || JSON.stringify(scope?.detectors) !== JSON.stringify(DETECTORS)) errors.push("INVALID_ENUM_INVENTORY");
  for (const entry of scope?.repositories ?? []) if (!Array.isArray(entry?.publicEvidencePaths) || entry.publicEvidencePaths.some((path) => !safePathToken(path))) errors.push("INVALID_EVIDENCE_PATH");
  let previous = "";
  for (const disposition of scope?.falsePositiveDispositions ?? []) {
    const keys = Object.keys(disposition ?? {}).sort(codepointCompare);
    if (JSON.stringify(keys) !== JSON.stringify(["detectorId", "expiresAt", "locationFingerprint", "owner", "reason", "verifiedAt"])) errors.push("INVALID_DISPOSITION_SHAPE");
    const identity = `${disposition?.locationFingerprint}\u0000${disposition?.detectorId}`;
    if (identity <= previous) errors.push("INVALID_DISPOSITION_ORDER");
    previous = identity;
    const verifiedAt = instant(disposition?.verifiedAt); const expiresAt = instant(disposition?.expiresAt);
    if (verifiedAt == null || expiresAt == null || verifiedAt >= expiresAt) errors.push("INVALID_DISPOSITION_TIME");
  }
  return errors;
}

export function validateReceipt(receipt, expected, errors = []) {
  if (receipt?.repository !== expected.repository || receipt?.gitSha !== expected.gitSha || receipt?.observedAt !== expected.observedAt || receipt?.detectorPolicyVersion !== expected.detectorPolicyVersion) errors.push("RECEIPT_IDENTITY_MISMATCH");
  for (const field of ["secretScanningEnabled", "pushProtectionEnabled", "reachableRefAuditComplete", "alertEnumerationComplete", "locationEnumerationComplete", "publicArtifactEnumerationComplete"]) if (receipt?.[field] !== true) errors.push("RECEIPT_INCOMPLETE");
  if (!Number.isInteger(receipt?.openAlertCount) || !Number.isInteger(receipt?.unresolvedAlertCount) || receipt.openAlertCount !== 0 || receipt.unresolvedAlertCount !== 0 || !safeLocatorForRepository(receipt?.evidenceLocator, expected.repository)) errors.push("RECEIPT_INVALID");
  let previous = "";
  if (!canonicalUtc(receipt?.observedAt)) errors.push("RECEIPT_INVALID_TIME");
  for (const artifact of receipt?.publicArtifacts ?? []) {
    const identity = artifactIdentity(artifact);
    if (identity <= previous || !safeArtifactFields(artifact) || artifact?.detectorPolicyVersion !== expected.detectorPolicyVersion || !canonicalUtc(artifact?.expiresAt) || artifact.expiresAt <= expected.observedAt || !safeArtifactLocator(receipt?.repository, artifact)) errors.push("RECEIPT_ARTIFACT_INVALID");
    previous = identity;
  }
  if (!Array.isArray(receipt?.publicArtifacts)) errors.push("RECEIPT_ARTIFACTS_MISSING");
  return errors;
}

export async function collectPublicMetadata({ repository, execGh = boundedGh }) {
  const routes = [
    ["ISSUE_COMMENT", `repos/${repository}/issues/comments?per_page=100&page=`],
    ["PR_REVIEW_COMMENT", `repos/${repository}/pulls/comments?per_page=100&page=`],
    ["COMMIT_COMMENT", `repos/${repository}/comments?per_page=100&page=`],
    ["RELEASE_METADATA", `repos/${repository}/releases?per_page=100&page=`],
  ];
  const incomplete = []; const items = [];
  for (const [surface, base] of routes) {
    const result = await collectPages({ endpoint: base, repository, surface, execGh });
    items.push(...result.items); incomplete.push(...result.incomplete);
  }
  const issueResult = await collectPages({ endpoint: `repos/${repository}/issues?state=all&per_page=100&page=`, repository, surface: "ISSUE", execGh });
  const issueKinds = new Map();
  for (const issue of issueResult.items) {
    issueKinds.set(issue.raw.number, issue.raw.pull_request == null ? "ISSUE" : "PR");
    const target = issue.raw?.pull_request == null ? ["ISSUE_TITLE", "ISSUE_BODY"] : ["PR_TITLE", "PR_BODY"];
    for (const surface of target) items.push(publicItem({ repository, surface, id: issue.raw.id, revision: issue.raw.updated_at, text: surface.endsWith("TITLE") ? issue.raw.title : issue.raw.body }));
  }
  for (const comment of items.filter((item) => item.surface === "ISSUE_COMMENT")) {
    const match = typeof comment.raw?.issue_url === "string" ? comment.raw.issue_url.match(new RegExp(`^https://api\\.github\\.com/repos/${repository}/issues/(\\d+)$`)) : null;
    const kind = match == null ? null : issueKinds.get(Number(match[1]));
    if (kind == null) { incomplete.push(incompleteEntry("metadata", "MALFORMED_COMMENT_PARENT", repository)); continue; }
    const surface = kind === "PR" ? "PR_COMMENT" : "ISSUE_COMMENT";
    Object.assign(comment, publicItem({ repository, surface, id: comment.raw.id, revision: comment.raw.updated_at, text: comment.raw.body }), { raw: comment.raw });
  }
  incomplete.push(...issueResult.incomplete);
  const pullResult = await collectPages({ endpoint: `repos/${repository}/pulls?state=all&per_page=100&page=`, repository, surface: "PR", execGh });
  for (const pull of pullResult.items) {
    if (!Number.isInteger(pull.raw.number)) { incomplete.push(incompleteEntry("provider", "MALFORMED_RESPONSE", repository)); continue; }
    const reviews = await collectPages({ endpoint: `repos/${repository}/pulls/${pull.raw.number}/reviews?per_page=100&page=`, repository, surface: "PR_REVIEW_BODY", execGh });
    items.push(...reviews.items); incomplete.push(...reviews.incomplete);
  }
  const releases = items.filter((item) => item.surface === "RELEASE_METADATA");
  for (const release of releases) for (const [field, text] of [["name", release.raw.name], ["tag", release.raw.tag_name], ["body", release.raw.body]]) items.push(publicItem({ repository, surface: "RELEASE_METADATA", id: `${release.raw.id}:${field}`, revision: release.raw.updated_at, text }));
  for (const release of releases) items.splice(items.indexOf(release), 1);
  incomplete.push(...pullResult.incomplete);
  return { items: dedupe(items), incomplete: dedupe(incomplete) };
}

async function collectPages({ endpoint, repository, surface, execGh }) {
  const items = []; const incomplete = []; const seenIds = new Set(); let page = 1;
  while (page <= PAGE_LIMIT) {
    let response;
    try { response = await execGh({ method: "GET", endpoint: `${endpoint}${page}` }); } catch { incomplete.push(incompleteEntry("provider", "PROVIDER_UNAVAILABLE", repository)); break; }
    const unpacked = unpackPage(response);
    if (!unpacked) { incomplete.push(incompleteEntry("provider", "MALFORMED_RESPONSE", repository)); break; }
    const { body, next, expectedCount } = unpacked;
    if (expectedCount != null && (!Number.isInteger(expectedCount) || expectedCount < body.length)) incomplete.push(incompleteEntry("pagination", "COUNT_MISMATCH", repository));
    for (const raw of body) {
      if (!safeId(raw?.id) || seenIds.has(raw.id)) { incomplete.push(incompleteEntry("pagination", "DUPLICATE_OR_INVALID_ID", repository)); continue; }
      const revision = raw.updated_at ?? raw.submitted_at ?? raw.published_at;
      if (!canonicalUtc(revision)) { incomplete.push(incompleteEntry("metadata", "MALFORMED_REVISION", repository)); continue; }
      seenIds.add(raw.id); items.push({ ...publicItem({ repository, surface, id: surface === "PR_REVIEW_COMMENT" && validSha(raw.commit_id) ? `${raw.id}:${raw.commit_id}` : raw.id, revision, text: raw.body ?? raw.name ?? raw.tag_name ?? "" }), raw });
    }
    if (!next && body.length < 100) break;
    if (!next && body.length === 100 && !Array.isArray(response)) { incomplete.push(incompleteEntry("pagination", "MISSING_NEXT_PAGE", repository)); break; }
    if (body.length === 0) { incomplete.push(incompleteEntry("pagination", "EMPTY_NEXT_PAGE", repository)); break; }
    page += 1;
  }
  if (page > PAGE_LIMIT) incomplete.push(incompleteEntry("pagination", "PAGE_UPPER_BOUND", repository));
  return { items, incomplete };
}

export async function auditPublicSensitivity({ scope, receipts, observedAt, execGh = boundedGh, sourceBytes = {} }) {
  const incomplete = []; const candidates = []; const inputs = []; let scannedSurfaces = 0; let scannedArtifacts = 0;
  const receiptMap = new Map();
  for (const receipt of Array.isArray(receipts) ? receipts : []) { if (receiptMap.has(receipt?.repository)) incomplete.push(incompleteEntry("receipt", "DUPLICATE_RECEIPT", receipt?.repository ?? "unknown")); receiptMap.set(receipt?.repository, receipt); }
  if (receiptMap.size !== REPOSITORIES.length) incomplete.push(incompleteEntry("receipt", "RECEIPT_SET_INCOMPLETE", "five-repositories"));
  for (const repository of REPOSITORIES) {
    let first; let last; let metadata = { items: [], incomplete: [] };
    let finalMetadata;
    try { first = await repositoryIdentity(repository, execGh); metadata = await collectPublicMetadata({ repository, execGh }); last = await repositoryIdentity(repository, execGh); finalMetadata = await collectPublicMetadata({ repository, execGh }); } catch { incomplete.push(incompleteEntry("provider", "PROVIDER_UNAVAILABLE", repository)); continue; }
    const receipt = receiptMap.get(repository); const receiptErrors = validateReceipt(receipt, { repository, gitSha: first.gitSha, observedAt, detectorPolicyVersion: scope?.detectorPolicyVersion });
    if (receiptErrors.length) incomplete.push(incompleteEntry("receipt", "INVALID_RECEIPT", repository));
    if (receipt != null) {
      scannedSurfaces += 1;
      candidates.push(...detect(JSON.stringify(receipt), { repository, surface: "REPOSITORY_SECURITY_RECEIPT", immutableSourceIdentity: `receipt:${repository}:${validSha(receipt.gitSha) ? receipt.gitSha : "invalid"}:${canonicalUtc(receipt.observedAt) ? receipt.observedAt : "invalid"}` }, scope));
    }
    const beginDigest = metadataDigest(metadata.items); const endDigest = metadataDigest(finalMetadata.items);
    if (first.gitSha !== last.gitSha || first.defaultBranch !== last.defaultBranch || beginDigest !== endDigest) incomplete.push(incompleteEntry("watermark", "WATERMARK_DRIFT", repository));
    incomplete.push(...metadata.incomplete, ...finalMetadata.incomplete);
    for (const item of metadata.items) { scannedSurfaces += 1; candidates.push(...detect(item.text, item, scope)); }
    const evidence = await collectEvidenceBlobs({ repository, gitSha: first.gitSha, paths: scope?.repositories?.find((entry) => entry?.repository === repository)?.publicEvidencePaths ?? [], execGh });
    incomplete.push(...evidence.incomplete);
    for (const item of evidence.items) { scannedArtifacts += 1; candidates.push(...detect(item.text, item, scope)); }
    const artifacts = await collectActionsArtifacts({ repository, execGh, receiptArtifacts: receipt?.publicArtifacts ?? [], observedAt, detectorPolicyVersion: scope?.detectorPolicyVersion });
    incomplete.push(...artifacts.incomplete);
    scannedArtifacts += artifacts.scannedArtifacts; candidates.push(...artifacts.findings);
    inputs.push({ repository, defaultBranch: first.defaultBranch, gitSha: first.gitSha, beginWatermark: beginDigest, endWatermark: endDigest, receiptLocator: safeLocatorForRepository(receipt?.evidenceLocator, repository) ? receipt.evidenceLocator : safeReceiptLocator(repository) });
  }
  const dispositionKeys = new Set(candidates.map((item) => `${item.locationFingerprint}\u0000${item.detectorId}`));
  const observed = instant(observedAt);
  for (const entry of scope?.falsePositiveDispositions ?? []) { const verified = instant(entry?.verifiedAt); const expires = instant(entry?.expiresAt); if (observed == null || verified == null || expires == null || verified > observed || expires <= observed || !dispositionKeys.has(`${entry?.locationFingerprint}\u0000${entry?.detectorId}`)) incomplete.push(incompleteEntry("disposition", "INVALID_FALSE_POSITIVE_DISPOSITION", safeFingerprint(entry?.locationFingerprint))); }
  return { inputs: { policyDigest: digestBytes(sourceBytes.scope ?? JSON.stringify(scope)), schemaDigest: digestBytes(sourceBytes.schema ?? ""), runnerDigest: digestBytes(sourceBytes.runner ?? ""), repositories: sorted(inputs) }, findings: dedupe(candidates.filter((item) => !disposed(item, scope?.falsePositiveDispositions ?? [], observedAt))), incomplete: dedupe(incomplete), scannedSurfaces, scannedArtifacts };
}

async function repositoryIdentity(repository, execGh) {
  const metadata = await execGh({ method: "GET", endpoint: `repos/${repository}` });
  const defaultBranch = metadata?.default_branch;
  const ref = await execGh({ method: "GET", endpoint: `repos/${repository}/git/ref/heads/${defaultBranch}` });
  if (!safeBranch(defaultBranch) || !validSha(ref?.object?.sha)) throw new Error("invalid identity");
  return { defaultBranch, gitSha: ref.object.sha, metadataDigest: digestBytes(JSON.stringify({ repository, defaultBranch, gitSha: ref.object.sha })) };
}

async function collectEvidenceBlobs({ repository, gitSha, paths, execGh }) {
  const incomplete = []; const items = [];
  try {
    const tree = await execGh({ method: "GET", endpoint: `repos/${repository}/git/trees/${gitSha}?recursive=1` });
    if (tree?.truncated === true || !Array.isArray(tree?.tree)) return { items, incomplete: [incompleteEntry("tree", "TREE_UNAVAILABLE", repository)] };
    for (const node of tree.tree.filter((entry) => paths.some((path) => entry?.path === path || entry?.path?.startsWith(`${path}/`)))) {
      if (node?.type === "tree") continue;
      if (node?.type !== "blob" || node?.mode !== "100644" || !validSha(node?.sha)) { incomplete.push(incompleteEntry("tree", "UNSUPPORTED_BLOB", repository)); continue; }
      const blob = await execGh({ method: "GET", endpoint: `repos/${repository}/git/blobs/${node.sha}` });
      if (blob?.encoding !== "base64" || typeof blob?.content !== "string") { incomplete.push(incompleteEntry("blob", "UNSUPPORTED_ENCODING", repository)); continue; }
      let text; try { const bytes = Buffer.from(blob.content, "base64"); if (bytes.toString("base64") !== blob.content.replace(/\n/g, "")) throw new Error("base64"); text = new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch { incomplete.push(incompleteEntry("blob", "UNSUPPORTED_ENCODING", repository)); continue; }
      items.push(publicItem({ repository, surface: "PUBLIC_ARTIFACT", id: node.sha, text }));
    }
  } catch { incomplete.push(incompleteEntry("tree", "PROVIDER_UNAVAILABLE", repository)); }
  return { items, incomplete };
}

export async function collectActionsArtifacts({ repository, execGh, receiptArtifacts, observedAt, detectorPolicyVersion }) {
  const incomplete = []; const findings = []; let scannedArtifacts = 0;
  try {
    const catalog = []; const ids = new Set(); let expectedTotal = null; let page = 1;
    while (page <= PAGE_LIMIT) {
      const response = await execGh({ method: "GET", endpoint: `repos/${repository}/actions/artifacts?per_page=100&page=${page}` });
      if (!Array.isArray(response?.artifacts) || !Number.isInteger(response?.total_count) || response.total_count < 0 || (expectedTotal != null && expectedTotal !== response.total_count)) return { findings, scannedArtifacts, incomplete: [incompleteEntry("artifacts", "ARTIFACT_CATALOG_INCOMPLETE", repository)] };
      expectedTotal ??= response.total_count;
      for (const artifact of response.artifacts) { if (!Number.isInteger(artifact?.id) || ids.has(artifact.id)) return { findings, scannedArtifacts, incomplete: [incompleteEntry("artifacts", "ARTIFACT_CATALOG_INCOMPLETE", repository)] }; ids.add(artifact.id); catalog.push(artifact); }
      if (catalog.length === expectedTotal) break;
      if (response.artifacts.length < 100 || catalog.length > expectedTotal) return { findings, scannedArtifacts, incomplete: [incompleteEntry("artifacts", "ARTIFACT_CATALOG_INCOMPLETE", repository)] };
      page += 1;
    }
    if (page > PAGE_LIMIT || catalog.length !== expectedTotal) return { findings, scannedArtifacts, incomplete: [incompleteEntry("artifacts", "ARTIFACT_CATALOG_INCOMPLETE", repository)] };
    if (catalog.some((artifact) => typeof artifact?.expired !== "boolean")) incomplete.push(incompleteEntry("artifacts", "ARTIFACT_CATALOG_INCOMPLETE", repository));
    const current = catalog.filter((artifact) => artifact?.expired === false);
    if (current.length !== receiptArtifacts.length || JSON.stringify(current.map((artifact) => String(artifact.id)).sort()) !== JSON.stringify(receiptArtifacts.map((artifact) => artifact.artifactId).sort())) incomplete.push(incompleteEntry("artifacts", "ARTIFACT_CATALOG_MISMATCH", repository));
    const runs = new Map();
    for (const artifact of current) {
      const receipt = receiptArtifacts.find((entry) => entry.artifactId === String(artifact.id));
      if (receipt == null || receipt.detectorPolicyVersion !== detectorPolicyVersion || receipt.scanStatus !== "COMPLETE" || receipt.expiresAt <= observedAt || receipt.expiresAt !== artifact.expires_at) { incomplete.push(incompleteEntry("artifacts", "ARTIFACT_CATALOG_MISMATCH", repository)); continue; }
      const runId = artifact.workflow_run?.id; let run = runs.get(runId);
      if (run == null) { run = await execGh({ method: "GET", endpoint: `repos/${repository}/actions/runs/${runId}` }); runs.set(runId, run); }
      if (receipt.workflowPath !== run?.path || receipt.runId !== String(artifact.workflow_run?.id) || receipt.artifactName !== artifact.name || receipt.archiveDigest !== artifact.digest) { incomplete.push(incompleteEntry("artifacts", "ARTIFACT_CATALOG_MISMATCH", repository)); continue; }
      const bytes = await execGh({ method: "GET", endpoint: `repos/${repository}/actions/artifacts/${artifact.id}/zip`, binary: true });
      if (!Buffer.isBuffer(bytes) || `sha256:${digestBytes(bytes)}` !== receipt.archiveDigest) { incomplete.push(incompleteEntry("artifacts", "ARCHIVE_DIGEST_MISMATCH", repository)); continue; }
      const scanned = scanArtifactArchive({ repository, artifactId: String(artifact.id), bytes, scope: { detectors: DETECTORS } });
      scannedArtifacts += 1; findings.push(...scanned.findings); incomplete.push(...scanned.incomplete);
    }
  } catch { incomplete.push(incompleteEntry("artifacts", "PROVIDER_UNAVAILABLE", repository)); }
  return { findings, scannedArtifacts, incomplete };
}

export function scanArtifactArchive({ repository, artifactId, bytes, scope }) {
  const incomplete = []; const findings = [];
  try {
    if (!Buffer.isBuffer(bytes) || bytes.length > 16 * 1024 * 1024) throw new Error("ARCHIVE_BOUNDS");
    let eocd = -1;
    for (let offset = bytes.length - 22; offset >= Math.max(0, bytes.length - 65_557); offset -= 1) if (bytes.readUInt32LE(offset) === 0x06054b50) { eocd = offset; break; }
    if (eocd < 0 || eocd + 22 > bytes.length) throw new Error("ARCHIVE_MALFORMED");
    if (bytes.readUInt16LE(eocd + 4) !== 0 || bytes.readUInt16LE(eocd + 6) !== 0 || bytes.readUInt16LE(eocd + 8) !== bytes.readUInt16LE(eocd + 10)) throw new Error("ARCHIVE_MALFORMED");
    const entries = bytes.readUInt16LE(eocd + 10); const centralSize = bytes.readUInt32LE(eocd + 12); let offset = bytes.readUInt32LE(eocd + 16);
    if (entries > 256 || centralSize > 4 * 1024 * 1024 || offset + centralSize !== eocd) throw new Error("ARCHIVE_BOUNDS");
    const centralEnd = offset + centralSize; let total = 0;
    for (let ordinal = 1; ordinal <= entries; ordinal += 1) {
      if (offset + 46 > bytes.length || bytes.readUInt32LE(offset) !== 0x02014b50) throw new Error("ARCHIVE_MALFORMED");
      const flags = bytes.readUInt16LE(offset + 8); const method = bytes.readUInt16LE(offset + 10); const crc = bytes.readUInt32LE(offset + 16); const compressed = bytes.readUInt32LE(offset + 20); const uncompressed = bytes.readUInt32LE(offset + 24); const nameLength = bytes.readUInt16LE(offset + 28); const extraLength = bytes.readUInt16LE(offset + 30); const commentLength = bytes.readUInt16LE(offset + 32); const localOffset = bytes.readUInt32LE(offset + 42);
      if ((flags & 1) !== 0 || ![0, 8].includes(method) || compressed > 4 * 1024 * 1024 || uncompressed > 4 * 1024 * 1024 || total + uncompressed > 8 * 1024 * 1024) throw new Error("ARCHIVE_UNSUPPORTED");
      const name = bytes.subarray(offset + 46, offset + 46 + nameLength); new TextDecoder("utf-8", { fatal: true }).decode(name);
      if (localOffset + 30 > bytes.length || bytes.readUInt32LE(localOffset) !== 0x04034b50 || bytes.readUInt16LE(localOffset + 6) !== flags || bytes.readUInt16LE(localOffset + 8) !== method || bytes.readUInt32LE(localOffset + 14) !== crc || bytes.readUInt32LE(localOffset + 18) !== compressed || bytes.readUInt32LE(localOffset + 22) !== uncompressed) throw new Error("ARCHIVE_MALFORMED");
      const dataOffset = localOffset + 30 + bytes.readUInt16LE(localOffset + 26) + bytes.readUInt16LE(localOffset + 28);
      if (!bytes.subarray(localOffset + 30, localOffset + 30 + bytes.readUInt16LE(localOffset + 26)).equals(name)) throw new Error("ARCHIVE_MALFORMED");
      if (dataOffset + compressed > bytes.length) throw new Error("ARCHIVE_BOUNDS");
      const data = bytes.subarray(dataOffset, dataOffset + compressed); const decoded = method === 0 ? data : inflateRawSync(data, { maxOutputLength: 4 * 1024 * 1024 });
      if (decoded.length !== uncompressed || crc32(decoded) !== crc) throw new Error("ARCHIVE_MALFORMED");
      total += decoded.length;
      const text = new TextDecoder("utf-8", { fatal: true }).decode(decoded);
      findings.push(...detect(text, { repository, surface: "PUBLIC_ARTIFACT", immutableSourceIdentity: `artifact:${artifactId}:${ordinal}` }, scope));
      offset += 46 + nameLength + extraLength + commentLength;
    }
    if (offset !== centralEnd) throw new Error("ARCHIVE_MALFORMED");
  } catch (error) { incomplete.push(incompleteEntry("archive", error instanceof Error && /^ARCHIVE_/.test(error.message) ? error.message : "ARCHIVE_UNAVAILABLE", repository)); }
  return { findings: dedupe(findings), incomplete: dedupe(incomplete) };
}

export function createReport({ observedAt, inputs = {}, findings = [], incomplete = [], scannedSurfaces = 0, scannedArtifacts = 0 }) {
  const normalizedFindings = dedupe(findings); const normalizedIncomplete = dedupe(incomplete);
  return { schemaVersion: 1, status: normalizedIncomplete.length ? "AUDIT_INCOMPLETE" : "COMPLETE", observedAt, inputs: { policyDigest: inputs.policyDigest ?? digestBytes(""), schemaDigest: inputs.schemaDigest ?? digestBytes(""), runnerDigest: inputs.runnerDigest ?? digestBytes(""), repositories: sorted(inputs.repositories ?? []) }, summary: { scannedSurfaces, scannedArtifacts, detectors: DETECTORS.length, findings: normalizedFindings.length, incomplete: normalizedIncomplete.length }, findings: normalizedFindings, incomplete: normalizedIncomplete };
}

export function validateReport(report, errors = []) {
  const repositories = Array.isArray(report?.inputs?.repositories) ? report.inputs.repositories : [];
  const findings = Array.isArray(report?.findings) ? report.findings : [];
  const incomplete = Array.isArray(report?.incomplete) ? report.incomplete : [];
  if (!canonicalUtc(report?.observedAt) || !["COMPLETE", "AUDIT_INCOMPLETE"].includes(report?.status)) errors.push("INVALID_REPORT_STATUS");
  if (![report?.inputs?.policyDigest, report?.inputs?.schemaDigest, report?.inputs?.runnerDigest].every((value) => /^[0-9a-f]{64}$/.test(value ?? ""))
    || JSON.stringify(repositories.map(({ repository }) => repository)) !== JSON.stringify(REPOSITORIES)
    || repositories.some((entry) => !safeBranch(entry?.defaultBranch) || !validSha(entry?.gitSha) || !/^[0-9a-f]{64}$/.test(entry?.beginWatermark) || !/^[0-9a-f]{64}$/.test(entry?.endWatermark) || !safeLocatorForRepository(entry?.receiptLocator, entry?.repository))) errors.push("INVALID_REPORT_INPUTS");
  if ((report?.status === "COMPLETE") !== (incomplete.length === 0)) errors.push("STATUS_INCOMPLETE_PARITY");
  const summaryValues = [report?.summary?.findings, report?.summary?.incomplete, report?.summary?.detectors, report?.summary?.scannedSurfaces, report?.summary?.scannedArtifacts];
  if (!summaryValues.every((value) => Number.isInteger(value) && value >= 0) || report?.summary?.detectors !== DETECTORS.length || report?.summary?.findings !== findings.length || report?.summary?.incomplete !== incomplete.length) errors.push("SUMMARY_MISMATCH");
  if (!sortedUnique(findings) || !sortedUnique(incomplete)) errors.push("REPORT_ORDER");
  for (const finding of findings) if (finding?.code !== "SENSITIVE_RAW_EVIDENCE" || !DETECTORS.includes(finding?.detectorId) || !REPOSITORIES.includes(finding?.repository) || !SURFACES.includes(finding?.surface) || !safeIdentity(finding?.immutableSourceIdentity) || !/^[0-9a-f]{64}$/.test(finding?.locationFingerprint)) errors.push("INVALID_FINDING");
  return errors;
}

function detect(text, identity, scope) {
  const rules = [["PRIVATE_KEY_BLOCK", /-----BEGIN (?:[A-Z ]*PRIVATE KEY)-----/g], ["KNOWN_TOKEN_FORMAT", /(?:gh[opsu]_|github_pat_|sk-)[A-Za-z0-9_-]{16,}/g], ["AUTHORIZATION_VALUE", /authorization\s*:\s*(?:bearer|basic)\s+\S+/gi], ["SIGNED_URL_QUERY", /[?&](?:X-Amz-Signature|Signature|sig|token)=[^\s&#]+/gi], ["PRIVATE_ABSOLUTE_PATH", /(?:\/Users\/|\/home\/|[A-Za-z]:\\Users\\)/g], ["RAW_PROVIDER_PAYLOAD", /"(?:access_token|client_secret|private_key)"\s*:/gi], ["RAW_USER_PAYLOAD", /"(?:password|authorization)"\s*:/gi]];
  const findings = [];
  for (const [detectorId, pattern] of rules) { if (!scope?.detectors?.includes(detectorId)) continue; let match; let ordinal = 0; while ((match = pattern.exec(text)) != null) { ordinal += 1; findings.push({ code: "SENSITIVE_RAW_EVIDENCE", detectorId, repository: identity.repository, surface: identity.surface, immutableSourceIdentity: identity.immutableSourceIdentity, locationFingerprint: digestBytes(`${identity.repository}\u0000${identity.surface}\u0000${identity.immutableSourceIdentity}\u0000${detectorId}\u0000${ordinal}\u0000${match.index}`) }); if (match[0] === "") break; } }
  return findings;
}

function publicItem({ repository, surface, id, revision = null, text }) { return { repository, surface, immutableSourceIdentity: `github:${repository}:${surface}:${String(id)}${revision == null ? "" : `:${revision}`}`, text: typeof text === "string" ? text : "" }; }
function metadataDigest(items) { return digestBytes(JSON.stringify([...items.map(({ repository, surface, immutableSourceIdentity, text }) => ({ repository, surface, immutableSourceIdentity, contentDigest: digestBytes(text) }))].sort((left, right) => codepointCompare(JSON.stringify(left), JSON.stringify(right))))); }
function unpackPage(response) { if (Array.isArray(response)) return { body: response, next: false, expectedCount: null }; if (!response || !Array.isArray(response.body)) return null; return { body: response.body, next: response.next === true, expectedCount: response.totalCount ?? null }; }
function disposed(finding, entries, observedAt) { const observed = instant(observedAt); return entries.some((entry) => { const verified = instant(entry.verifiedAt); const expires = instant(entry.expiresAt); return entry.locationFingerprint === finding.locationFingerprint && entry.detectorId === finding.detectorId && observed != null && verified != null && expires != null && verified <= observed && expires > observed; }); }
function artifactIdentity(item) { return [item?.artifactId, item?.artifactName, item?.workflowPath, item?.runId, item?.archiveDigest, item?.expiresAt, item?.detectorPolicyVersion, item?.scanStatus, item?.scanReceiptLocator].join("\u0000"); }
function incompleteEntry(stage, code, affectedIdentity) { return { stage, code, affectedIdentity: safeIdentity(affectedIdentity) ? affectedIdentity : "redacted" }; }
function safeLocator(value) { return /^https:\/\/github\.com\/AquilaXk\/easysubway(?:-(?:backend|data|mobile|platform))?\/actions\/runs\/\d+\/artifacts\/\d+$/.test(value ?? ""); }
function safeLocatorForRepository(value, repository) { return safeLocator(value) && value.startsWith(`https://github.com/${repository}/actions/runs/`); }
function safeArtifactFields(artifact) { return /^\d+$/.test(artifact?.artifactId ?? "") && /^\d+$/.test(artifact?.runId ?? "") && typeof artifact?.artifactName === "string" && /^[A-Za-z0-9][A-Za-z0-9._ -]{0,127}$/.test(artifact.artifactName) && typeof artifact?.workflowPath === "string" && /^\.github\/workflows\/[A-Za-z0-9._/-]+\.ya?ml$/.test(artifact.workflowPath) && !artifact.workflowPath.includes("..") && /^sha256:[0-9a-f]{64}$/.test(artifact?.archiveDigest ?? "") && artifact?.scanStatus === "COMPLETE"; }
function safeArtifactLocator(repository, artifact) { return artifact?.scanReceiptLocator === `https://github.com/${repository}/actions/runs/${artifact.runId}/artifacts/${artifact.artifactId}`; }
function safeReceiptLocator(repository) { return `https://github.com/${repository}/actions/runs/0/artifacts/0`; }
function safeIdentity(value) { return typeof value === "string" && /^[A-Za-z0-9:._/-]+$/.test(value) && !value.startsWith("/") && !value.includes("..") && !value.includes("/Users/") && !value.includes("/home/") && !value.includes("?") && !value.includes("#") && value.length <= 512; }
function safeFingerprint(value) { return /^[0-9a-f]{64}$/.test(value ?? "") ? value : "redacted"; }
function safeId(value) { return Number.isInteger(value) && value >= 0; }
function safeBranch(value) { return typeof value === "string" && /^[A-Za-z0-9._/-]+$/.test(value) && !value.includes(".."); }
function safePathToken(value) { return typeof value === "string" && value.length > 0 && !isAbsolute(value) && !value.split(/[\\/]/).includes(".."); }
function validSha(value) { return /^[0-9a-f]{40}$/.test(value ?? ""); }
function canonicalUtc(value) { if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value ?? "")) return false; try { return new Date(value).toISOString() === value; } catch { return false; } }
function instant(value) { if (typeof value !== "string") return null; const parsed = Date.parse(value); return Number.isFinite(parsed) ? parsed : null; }
function digestBytes(value) { return createHash("sha256").update(value).digest("hex"); }
function crc32(bytes) { let crc = 0xffffffff; for (const byte of bytes) { crc ^= byte; for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1)); } return (crc ^ 0xffffffff) >>> 0; }
function sorted(items) { return [...items].sort((left, right) => codepointCompare(left.repository ?? JSON.stringify(left), right.repository ?? JSON.stringify(right))); }
function dedupe(items) { return [...new Map(items.map((item) => [JSON.stringify(item), item])).values()].sort((left, right) => codepointCompare(JSON.stringify(left), JSON.stringify(right))); }
function sortedUnique(items) { return Array.isArray(items) && items.every((item, index) => index === 0 || JSON.stringify(items[index - 1]) < JSON.stringify(item)); }
function codepointCompare(left, right) { return left < right ? -1 : left > right ? 1 : 0; }

async function boundedGh({ method, endpoint, binary = false }) { if (method !== "GET" || !/^repos\/AquilaXk\/easysubway(?:-(?:backend|data|mobile|platform))?(?:\/|$)/.test(endpoint)) throw new Error("invalid provider request"); return new Promise((resolvePromise, reject) => { const child = spawn("gh", ["api", "--method", "GET", endpoint], { stdio: ["ignore", "pipe", "ignore"] }); const chunks = []; let length = 0; const limit = binary ? BINARY_OUTPUT_LIMIT : OUTPUT_LIMIT; const timer = setTimeout(() => child.kill(), 30_000); child.stdout.on("data", (chunk) => { chunks.push(chunk); length += chunk.length; if (length > limit) child.kill(); }); child.on("error", reject); child.on("close", (code) => { clearTimeout(timer); if (code !== 0 || length > limit) reject(new Error("provider unavailable")); else { const output = Buffer.concat(chunks); try { resolvePromise(binary ? output : JSON.parse(output.toString("utf8"))); } catch { reject(new Error("malformed response")); } } }); }); }

async function readContracts() {
  const [scopeSchemaText, receiptSchemaText, reportSchemaText, runnerText] = await Promise.all([
    readFile(new URL("../../contracts/documentation/public-sensitivity-audit-scope.schema.json", import.meta.url), "utf8"),
    readFile(new URL("../../contracts/documentation/public-sensitivity-owner-receipt.schema.json", import.meta.url), "utf8"),
    readFile(new URL("../../contracts/documentation/public-sensitivity-audit-report.schema.json", import.meta.url), "utf8"),
    readFile(new URL(import.meta.url), "utf8"),
  ]);
  return { scopeSchemaText, receiptSchemaText, reportSchemaText, runnerText };
}

async function writeReport(output, report, reportSchemaText) {
  if (!validateSchema(JSON.parse(reportSchemaText), report).ok || validateReport(report).length) throw new Error("report invalid");
  const file = await open(output, "wx");
  try { await file.writeFile(`${JSON.stringify(report, null, 2)}\n`); } finally { await file.close(); }
}

async function writeFailureReport({ output, observedAt, scopeText, scopeSchemaText, receiptSchemaText, reportSchemaText, runnerText }) {
  const report = createReport({
    observedAt: observedAt ?? "1970-01-01T00:00:00.000Z",
    inputs: failureInputs(scopeText, `${scopeSchemaText}${receiptSchemaText}${reportSchemaText}`, runnerText),
    incomplete: [incompleteEntry("audit", "AUDIT_FAILURE", "audit")],
  });
  await writeReport(output, report, reportSchemaText);
}

export async function runAuditCli(args = process.argv.slice(2)) {
  let parsed; let output;
  let scopeText = ""; let scopeSchemaText = ""; let receiptSchemaText = ""; let reportSchemaText = ""; let runnerText = "";
  try {
    parsed = parseArgs(args);
    const root = await realpath(parsed.root);
    output = await containedPath(root, parsed.output, true);
    ({ scopeSchemaText, receiptSchemaText, reportSchemaText, runnerText } = await readContracts());
    const [loadedScopeText, receiptText] = await Promise.all([
      readFile(await containedPath(root, parsed.scope), "utf8"),
      readFile(await containedPath(root, parsed.receipts), "utf8"),
    ]);
    scopeText = loadedScopeText;
    const scope = JSON.parse(scopeText); const receipts = JSON.parse(receiptText);
    const errors = [
      ...validateSchema(JSON.parse(scopeSchemaText), scope).errors,
      ...validateScope(scope),
      ...(Array.isArray(receipts) ? receipts : [null]).flatMap((receipt) => validateSchema(JSON.parse(receiptSchemaText), receipt).errors),
    ];
    const schemaText = `${scopeSchemaText}${receiptSchemaText}${reportSchemaText}`;
    const audit = errors.length
      ? { inputs: failureInputs(scopeText, schemaText, runnerText), findings: [], incomplete: errors.map((_, index) => incompleteEntry("contract", "INVALID_CONTRACT", `contract-${index + 1}`)) }
      : await auditPublicSensitivity({ scope, receipts, observedAt: parsed.observedAt, sourceBytes: { scope: scopeText, schema: schemaText, runner: runnerText } });
    const report = createReport({ observedAt: parsed.observedAt, ...audit });
    await writeReport(output, report, reportSchemaText);
    return report.status === "AUDIT_INCOMPLETE" ? 2 : report.findings.length ? 1 : 0;
  } catch {
    process.stderr.write("AUDIT_INCOMPLETE\n");
    if (output != null && reportSchemaText !== "") {
      try { await writeFailureReport({ output, observedAt: parsed?.observedAt, scopeText, scopeSchemaText, receiptSchemaText, reportSchemaText, runnerText }); }
      catch { process.stderr.write("AUDIT_INCOMPLETE_REPORT_UNAVAILABLE\n"); }
    }
    return 2;
  }
}
function failureInputs(scopeText, schemaText, runnerText) { return { policyDigest: digestBytes(scopeText), schemaDigest: digestBytes(schemaText), runnerDigest: digestBytes(runnerText), repositories: REPOSITORIES.map((repository) => ({ repository, defaultBranch: "main", gitSha: "0".repeat(40), beginWatermark: "0".repeat(64), endWatermark: "0".repeat(64), receiptLocator: safeReceiptLocator(repository) })) }; }
function parseArgs(args) { if (args.length !== 10 || args[0] !== "--scope" || args[2] !== "--owner-receipts" || args[4] !== "--observed-at" || args[6] !== "--repository-root" || args[8] !== "--output" || !canonicalUtc(args[5])) throw new Error("invalid arguments"); return { scope: args[1], receipts: args[3], observedAt: args[5], root: args[7], output: args[9] }; }
async function containedPath(root, candidate, output = false) { if (!safePathToken(candidate)) throw new Error("unsafe path"); const path = resolve(root, candidate); if (relative(root, path).startsWith("..")) throw new Error("unsafe path"); const boundary = output ? dirname(path) : path; const real = await realpath(boundary); if (real !== root && !real.startsWith(`${root}/`)) throw new Error("unsafe path"); const parts = relative(root, boundary).split("/").filter(Boolean); let cursor = root; for (const part of parts) { cursor = resolve(cursor, part); if ((await lstat(cursor)).isSymbolicLink()) throw new Error("unsafe path"); } if (!output && (await lstat(path)).isSymbolicLink()) throw new Error("unsafe path"); return path; }
if (process.argv[1] === fileURLToPath(import.meta.url)) process.exitCode = await runAuditCli();
