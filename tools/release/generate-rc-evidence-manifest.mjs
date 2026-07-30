#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import {
  closeSync, existsSync, lstatSync, mkdirSync, mkdtempSync, openSync, readFileSync, realpathSync, renameSync,
  rmSync, statSync, writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { canonicalScopeHash } from "../datapack/build-launch-denominator-report.mjs";
import { selectEffectiveDataPack, selectFallbackDataPack, validateManifest } from "../datapack/lib/manifest-validation.mjs";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isSemVer } from "./lib/semver.mjs";
import { selectSystemReleaseDecision, validateSystemReleaseManifest } from "./validate-system-release-manifest.mjs";

const SUCCESSFUL_FRESHNESS_REASON_CODES = new Set([
  "PACK_PUBLISH_FRESHNESS_EXPIRED",
  "PACK_PUBLISH_FRESHNESS_EXPIRING",
]);

const args = parseArgs(process.argv.slice(2));
const cwd = process.cwd();
const requestedPhase = arg("phase") ?? "FINAL";
if (!["CANDIDATE", "FINAL"].includes(requestedPhase)) {
  fail("--phase must be CANDIDATE or FINAL");
}
const repoRoot = resolvePath(arg("repoRoot", "repo-root") ?? ".");
const appRoot = resolvePath(arg("appRoot", "app-root") ?? path.join(repoRoot, "apps/mobile"));
const outputPath = args.output ? resolvePath(args.output) : null;

if (!outputPath) {
  fail("--output is required");
}

const nowArg = arg("now");
const generatedAtMillis = nowArg === undefined ? Date.now() : Date.parse(nowArg);
if (!Number.isFinite(generatedAtMillis)) {
  fail("--now must be a valid timestamp");
}
const generatedAt = new Date(generatedAtMillis).toISOString();
const testedAt = arg("testedAt", "tested-at") ?? generatedAt;
const evidenceRoot = normalizeEvidenceRoot(
  arg("evidenceRoot", "evidence-root") ?? ".codex/evidence/release/rc-evidence-manifest/<rc-or-run>/",
);
const appVersion = readFlutterVersion(path.join(appRoot, "pubspec.yaml"));
const dataPackManifestPath = resolvePath(
  arg("dataPackManifest", "data-pack-manifest") ?? path.join(appRoot, "assets/datapacks/index.json"),
);
const dataPackManifest = readJsonIfExists(dataPackManifestPath);
const dataPackArtifactArg = arg("dataPackArtifact", "data-pack-artifact");
const dataPackArtifactPath = dataPackArtifactArg ? resolvePath(dataPackArtifactArg) : null;
const dataPackArtifactBytes = dataPackArtifactPath && existsSync(dataPackArtifactPath)
  ? statSync(dataPackArtifactPath).size
  : null;
const dataPackFallbackArtifactArg = arg("dataPackFallbackArtifact", "data-pack-fallback-artifact");
const dataPackFallbackArtifactPath = dataPackFallbackArtifactArg
  ? resolvePath(dataPackFallbackArtifactArg)
  : dataPackArtifactPath;
const dataPackFallbackArtifactBytes = dataPackFallbackArtifactPath && existsSync(dataPackFallbackArtifactPath)
  ? statSync(dataPackFallbackArtifactPath).size
  : null;
const requestedProductionDataPackBinding = booleanArg(
  "requireProductionDataPackBinding",
  "require-production-data-pack-binding",
);
const requirePrePlayUploadReady = booleanArg(
  "requirePrePlayUploadReady",
  "require-pre-play-upload-ready",
);
const failOnBlocked = booleanArg("failOnBlocked", "fail-on-blocked");
const dataPackReleaseDecisionPath = arg("dataPackReleaseDecision", "data-pack-release-decision");
const requireProductionDataPackBinding = requestedProductionDataPackBinding
  || (requestedPhase === "FINAL" && Boolean(dataPackReleaseDecisionPath));
const dataPackReleaseDecision = readFinalDataPackReleaseDecision(
  dataPackReleaseDecisionPath,
  requireProductionDataPackBinding,
);
const dataPackRehearsalBindingPath = arg("dataPackRehearsalBinding", "data-pack-rehearsal-binding");
if (dataPackReleaseDecisionPath && dataPackRehearsalBindingPath) {
  fail("production decision and prelaunch rehearsal binding are mutually exclusive");
}
const dataPackRehearsalBinding = readDataPackRehearsalBinding(
  dataPackRehearsalBindingPath,
  dataPackManifestPath,
  dataPackManifest,
  dataPackArtifactPath,
);
if (
  dataPackManifest?.sourceSnapshotSetHash !== undefined
  && !/^[a-f0-9]{64}$/.test(dataPackManifest.sourceSnapshotSetHash)
) {
  fail("data pack manifest sourceSnapshotSetHash must be a SHA-256 digest");
}
const sourceSnapshotSetHash = dataPackReleaseDecision?.sourceSnapshotSetHash
  ?? dataPackRehearsalBinding?.sourceSnapshotSetHash
  ?? dataPackManifest?.sourceSnapshotSetHash
  ?? null;
if (requireProductionDataPackBinding) {
  validateProductionDataPackBinding(
    dataPackManifest,
    dataPackArtifactPath,
    dataPackArtifactBytes,
    dataPackFallbackArtifactPath,
    dataPackFallbackArtifactBytes,
    dataPackReleaseDecision,
    generatedAtMillis,
  );
}
const backendIdentity = readBackendIdentity(args);
const providedGateStatuses = parsePairs(arg("gateStatus", "gate-status"));
const gateEvidencePaths = parsePairs(arg("gateEvidence", "gate-evidence"));
const evidenceStatuses = parsePairs(arg("evidenceStatus", "evidence-status"));
const evidencePaths = parsePairs(arg("evidencePath", "evidence-path"));
const datapackGateStatuses = parsePairs(arg("datapackGateStatus", "datapack-gate-status"));
const datapackGateEvidencePaths = parsePairs(arg("datapackGateEvidence", "datapack-gate-evidence"));
const issueStates = parsePairs(arg("issueState", "issue-state"));
const expectedValues = parsePairs(args.expect);
const androidReleaseMetadata = readKeyValueFileIfExists(arg("androidReleaseMetadata", "android-release-metadata"));
const suppliedGitSha = arg("gitSha", "git-sha");
const verifyGithubSha = arg("verifyGithubSha", "verify-github-sha") === "true";
const checkoutGitSha = currentGitSha(repoRoot);
if (verifyGithubSha && (!suppliedGitSha || !process.env.GITHUB_SHA)) {
  fail("--verify-github-sha requires --git-sha and GITHUB_SHA");
}
if (verifyGithubSha && suppliedGitSha !== process.env.GITHUB_SHA) {
  fail("GITHUB_SHA does not match --git-sha");
}
const gitSha = suppliedGitSha ?? process.env.GITHUB_SHA ?? checkoutGitSha;
if (!/^[a-f0-9]{40}$/.test(gitSha) || gitSha !== checkoutGitSha) {
  fail("--git-sha must match the current checkout HEAD");
}
const rcEvidenceContractPath = resolvePath(
  arg("rcEvidenceContract", "rc-evidence-contract")
    ?? path.join(repoRoot, "release/product-gates/rc-evidence-manifest-contract.json"),
);
const rcEvidenceContract = projectRcEvidenceContract(readJsonIfExists(rcEvidenceContractPath));
if (!Array.isArray(rcEvidenceContract?.requiredEvidenceEntries)) {
  fail("RC evidence manifest contract with requiredEvidenceEntries is required");
}
if (!Array.isArray(rcEvidenceContract.requiredDatapackGates)) {
  fail("RC evidence manifest contract with requiredDatapackGates is required");
}
if (!Array.isArray(rcEvidenceContract.requiredGateStatuses)) {
  fail("RC evidence manifest contract with requiredGateStatuses is required");
}
if (!rcEvidenceContract.requiredGateChecks || typeof rcEvidenceContract.requiredGateChecks !== "object") {
  fail("RC evidence manifest contract with requiredGateChecks is required");
}
if (
  !rcEvidenceContract.phaseConsumers
  || !Array.isArray(rcEvidenceContract.phaseConsumers.CANDIDATE)
  || !Array.isArray(rcEvidenceContract.phaseConsumers.FINAL)
) {
  fail("RC evidence manifest contract with phaseConsumers is required");
}
if (!Array.isArray(rcEvidenceContract.requiredFinalFragmentIssues)) {
  fail("RC evidence manifest contract with requiredFinalFragmentIssues is required");
}
const finalFragmentEntries = rcEvidenceContract.requiredEvidenceEntries.filter(({ sourceIssue }) => (
  rcEvidenceContract.requiredFinalFragmentIssues.includes(sourceIssue)
));
if (
  new Set(rcEvidenceContract.requiredFinalFragmentIssues).size !== rcEvidenceContract.requiredFinalFragmentIssues.length
  || finalFragmentEntries.length !== rcEvidenceContract.requiredFinalFragmentIssues.length
  || finalFragmentEntries.map(({ sourceIssue }) => sourceIssue).sort((left, right) => left - right).join(",")
    !== [...rcEvidenceContract.requiredFinalFragmentIssues].sort((left, right) => left - right).join(",")
) {
  fail("requiredFinalFragmentIssues must exactly match required evidence entries");
}
if (!Array.isArray(rcEvidenceContract.activeBlockerIssues)) {
  fail("RC evidence manifest contract with activeBlockerIssues is required");
}
validateIssueDag(rcEvidenceContract.activeBlockerIssues, issueStates);
const launchScope = readJsonIfExists(path.join(repoRoot, "release/product-gates/production-datapack-scope.json"));
if (!launchScope?.routingLaunchScope || !launchScope?.identityMatrix) {
  fail("production routing launch scope and identity matrix are required");
}
if (!launchScope?.nationwideRoadmapScope) {
  fail("production nationwide roadmap scope is required");
}

const identity = {
  gitSha,
  appVersionName: appVersion.name,
  versionCode: appVersion.code,
  aabSha256: sha256FileIfExists(args.aab),
  aabPayloadSha256: aabPayloadSha256IfExists(args.aab),
  backendImageDigest: backendIdentity.backendImageDigest,
  backendArtifactSha256: backendIdentity.backendArtifactSha256,
  dataPackManifestSha256: sha256FileIfExists(dataPackManifestPath),
  dataPackArtifactSha256: sha256FileIfExists(dataPackArtifactPath),
  dataPackFallbackArtifactSha256: sha256FileIfExists(dataPackFallbackArtifactPath),
  sourceSnapshotSetHash,
  supportContactSetSha256: arg("supportContactSetSha256", "support-contact-set-sha256")
    ?? androidReleaseMetadata.supportContactSetSha256
    ?? null,
  releaseSequence: normalizeReleaseSequence(
    arg("releaseSequence", "release-sequence"),
    dataPackManifest?.releaseSequence,
  ),
  routeContractVersion: arg("routeContractVersion", "route-contract-version") ?? "route-map-contract-v1",
  realtimeContractVersion: arg("realtimeContractVersion", "realtime-contract-version") ?? readRealtimeContractVersion(repoRoot),
  launchScopeId: launchScope.routingLaunchScope.id,
  launchScopeSha256: canonicalScopeHash(launchScope.routingLaunchScope),
  nationwideRoadmapScopeId: launchScope.nationwideRoadmapScope.id,
  nationwideRoadmapScopeSha256: canonicalScopeHash(launchScope.nationwideRoadmapScope),
  identityLinkageMatrixSha256: canonicalScopeHash(launchScope.identityMatrix),
};
if (requirePrePlayUploadReady) {
  if (requestedPhase !== "FINAL") {
    fail("pre-Play upload readiness is only valid for FINAL manifests");
  }
  validatePrePlayUploadReadiness(
    identity,
    androidReleaseMetadata,
    requireProductionDataPackBinding,
    dataPackReleaseDecision,
  );
}
const producerVersion = 2;
const releaseCandidateIdentity = identity;
const candidateContext = {
  schemaVersion: 1, releaseGate: "rc-evidence-manifest", issue: 2056, producerVersion, phase: "CANDIDATE",
  applicationId: "easysubway",
  androidApplicationId: "com.easysubway.app",
  generatedAt, releaseCandidateIdentity,
  rcIdentity: releaseCandidateIdentity,
  requiredGateStatuses: [...rcEvidenceContract.requiredGateStatuses],
  requiredEvidenceEntries: rcEvidenceContract.requiredEvidenceEntries.map(({ id, sourceIssue }) => ({ id, sourceIssue })),
  requiredDatapackGates: rcEvidenceContract.requiredDatapackGates.map(({ id, sourceIssue }) => ({ id, sourceIssue })),
  consumerIssues: rcEvidenceContract.phaseConsumers.CANDIDATE,
  activeBlockerIssues: rcEvidenceContract.activeBlockerIssues,
  sourceManifests: {
    androidRcEvidenceManifest: "apps/mobile/release/android-rc-store-evidence.json",
    signedReleaseArtifactGate: "apps/mobile/release/signed-release-artifact-gate.json",
    releaseGovernanceGate: "release/product-gates/release-governance-gate.json",
    dataPackManifest: path.relative(repoRoot, dataPackManifestPath),
  },
};

if (requestedPhase === "CANDIDATE") {
  writeManifest(outputPath, candidateContext, "--output");
  process.exit(0);
}

const candidateContextPath = arg("candidateContext", "candidate-context");
if (requestedPhase === "FINAL" && !candidateContextPath) {
  fail("FINAL phase requires --candidate-context");
}
if (candidateContextPath) {
  validateCandidateContext(readJsonIfExists(resolvePath(candidateContextPath)), candidateContext);
}
const systemReleaseInputs = arg("systemReleaseOutput", "system-release-output")
  ? readSystemReleaseInputs()
  : null;

const gateEntries = requiredGateEntries(
  rcEvidenceContract.requiredGateStatuses, rcEvidenceContract.requiredGateChecks,
  providedGateStatuses, gateEvidencePaths, identity, generatedAt,
  { identity, repoRoot, androidApplicationId: "com.easysubway.app" },
);
const gateStatuses = Object.fromEntries(gateEntries.map(({ id, status }) => [id, status]));

const evidenceEntries = requiredEvidenceEntries(
  testedAt, evidenceRoot, args.device, arg("androidVersion", "android-version"),
  evidenceStatuses, evidencePaths, generatedAt, rcEvidenceContract.requiredEvidenceEntries,
  { identity, repoRoot, androidApplicationId: "com.easysubway.app" },
);
const datapackGates = requiredDatapackGates(
  rcEvidenceContract.requiredDatapackGates, datapackGateStatuses, datapackGateEvidencePaths,
  identity, generatedAt, dataPackArtifactPath, dataPackArtifactBytes,
  launchScope.productionSourceSet?.requiredSourceIds,
);
const sourceInventory = buildSourceInventory(datapackGates, generatedAt, producerVersion);
const identityLinkage = readIdentityLinkage(
  arg("identityLinkageEvidence", "identity-linkage-evidence"), identity, launchScope.identityMatrix, generatedAt,
);
const openAndroidP0Count = requiredOpenP0Count(arg("openAndroidP0Count", "open-android-p0-count"));
const blockers = [
  ...identityBlockers(identity),
  ...androidReleaseMetadataMismatchBlockers(identity, androidReleaseMetadata),
  ...expectedMismatchBlockers(identity, expectedValues),
  ...gateStatusBlockers(gateStatuses),
  ...openP0Blockers(openAndroidP0Count),
  ...evidenceBlockers(evidenceEntries),
  ...datapackGateBlockers(datapackGates),
  ...identityLinkageBlockers(identityLinkage),
  ...activeIssueBlockers(rcEvidenceContract.activeBlockerIssues),
];
const summaryArtifactDigest = createHash("sha256")
  .update(JSON.stringify({
    producerVersion,
    releaseCandidateIdentity,
    gateEntries,
    evidenceEntries: evidenceEntries.map((entry) => ({
      id: entry.id, sourceIssue: entry.sourceIssue, device: entry.device,
      androidVersion: entry.androidVersion, status: entry.status,
      evidenceSha256: entry.evidenceSha256,
      testedAt: entry.status === "SATISFIED" ? entry.testedAt : null,
      expiresWhen: entry.status === "SATISFIED" ? entry.expiresWhen : null,
    })),
    datapackGates,
    sourceInventory: sourceInventory && {
      inventoryAsOf: sourceInventory.inventoryAsOf, producerVersion: sourceInventory.producerVersion,
      statusCounts: sourceInventory.statusCounts, entries: sourceInventory.entries,
      snapshotSetIdentity: sourceInventory.snapshotSetIdentity,
    },
    identityLinkage,
    consumerIssues: rcEvidenceContract.phaseConsumers.FINAL,
    activeBlockerIssues: rcEvidenceContract.activeBlockerIssues,
    openAndroidP0Count,
    blockers,
  }))
  .digest("hex");

const workflowRunUrl = arg("workflowRunUrl", "workflow-run-url")
  ?? githubWorkflowRunUrl(process.env)
  ?? null;

const manifest = {
  schemaVersion: 1, releaseGate: "rc-evidence-manifest", issue: 1020, producerVersion, phase: "FINAL",
  evaluatedAt: generatedAt, releaseCandidateIdentity, summaryArtifactDigest,
  decision: blockers.length === 0 ? "GO" : "NO_GO",
  applicationId: "easysubway", androidApplicationId: "com.easysubway.app", generatedAt,
  ...identity,
  rcIdentity: releaseCandidateIdentity,
  evidenceEntries, datapackGates, gateEntries, sourceInventory, identityLinkage,
  consumerIssues: rcEvidenceContract.phaseConsumers.FINAL,
  activeBlockerIssues: rcEvidenceContract.activeBlockerIssues,
  closureEvidence: {
    releaseCandidateIdentity, summaryArtifactDigest,
    producerCommand: "node tools/release/generate-rc-evidence-manifest.mjs",
    workflowRunUrl,
  },
  readiness: {
    status: blockers.length === 0 ? "GO" : "NO_GO",
    gateStatus: blockers.length === 0 ? "SATISFIED" : "BLOCKED_RC_EVIDENCE",
    blockers, openAndroidP0Count, gateStatuses,
  },
  sourceManifests: {
    androidRcEvidenceManifest: "apps/mobile/release/android-rc-store-evidence.json",
    signedReleaseArtifactGate: "apps/mobile/release/signed-release-artifact-gate.json",
    releaseGovernanceGate: "release/product-gates/release-governance-gate.json",
    dataPackManifest: path.relative(repoRoot, dataPackManifestPath),
  },
};

const systemReleaseManifest = systemReleaseInputs
  ? buildSystemReleaseManifest(manifest, systemReleaseInputs)
  : null;
writeManifest(outputPath, manifest, "--output");
if (systemReleaseInputs) {
  writeManifest(systemReleaseInputs.outputPath, systemReleaseManifest, "--system-release-output");
}

if (failOnBlocked && blockers.length > 0) {
  fail(`RC evidence manifest is blocked: ${blockers.map((blocker) => blocker.id).join(", ")}`);
}

function outputDestination(filePath, label) {
  const parent = path.dirname(filePath);
  mkdirSync(parent, { recursive: true });
  const existing = lstatSync(filePath, { throwIfNoEntry: false });
  if (existing?.isSymbolicLink()) fail(`${label} must not be a symlink`);
  return { canonicalPath: path.join(realpathSync(parent), path.basename(filePath)), existing };
}

function writeManifest(filePath, value, label) {
  outputDestination(filePath, label);
  const parent = path.dirname(filePath);
  let descriptor;
  let temporaryPath;
  for (let attempt = 0; attempt < 100; attempt += 1) {
    temporaryPath = path.join(parent, `.${path.basename(filePath)}.tmp-${process.pid}-${attempt}`);
    try {
      descriptor = openSync(temporaryPath, "wx", 0o600);
      break;
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
    }
  }
  if (descriptor === undefined) fail(`${label} temporary file is unavailable`);
  try {
    writeFileSync(descriptor, `${JSON.stringify(value, null, 2)}\n`);
    closeSync(descriptor);
    descriptor = undefined;
    renameSync(temporaryPath, filePath);
  } catch (error) {
    if (descriptor !== undefined) {
      try {
        closeSync(descriptor);
      } catch {}
    }
    rmSync(temporaryPath, { force: true });
    throw error;
  }
}

function readSystemReleaseInputs() {
  const required = [
    ["mobile", "mobileComponentManifest", "mobile-component-manifest"],
    ["backend", "backendComponentManifest", "backend-component-manifest"],
    ["data", "dataComponentManifest", "data-component-manifest"],
    ["platform", "platformComponentManifest", "platform-component-manifest"],
  ];
  const components = Object.fromEntries(required.map(([slot, camelName, kebabName]) => {
    const rawPath = arg(camelName, kebabName);
    if (!rawPath) fail(`FINAL phase requires --${kebabName}`);
    return [slot, readRequiredJson(resolvePath(rawPath), `${slot} component manifest`)];
  }));
  const contractsPath = arg("contractsIdentity", "contracts-identity");
  if (!contractsPath) fail("FINAL phase requires --contracts-identity");
  const contracts = readRequiredJson(resolvePath(contractsPath), "contracts identity");
  if (
    !contracts || typeof contracts !== "object" || Array.isArray(contracts)
    || Object.keys(contracts).length !== 2
    || !Object.hasOwn(contracts, "version") || !Object.hasOwn(contracts, "sha256")
    || !isSemVer(contracts.version) || !/^[a-f0-9]{64}$/.test(contracts.sha256)
  ) {
    fail("contracts identity must be exactly {version,sha256}");
  }
  const output = arg("systemReleaseOutput", "system-release-output");
  if (!output) fail("FINAL phase requires --system-release-output");
  const systemReleaseOutputPath = resolvePath(output);
  const legacyOutput = outputDestination(outputPath, "--output");
  const systemOutput = outputDestination(systemReleaseOutputPath, "--system-release-output");
  if (legacyOutput.canonicalPath.toLowerCase() === systemOutput.canonicalPath.toLowerCase()) {
    fail("--system-release-output must differ from --output");
  }
  if (
    legacyOutput.existing?.isFile() && systemOutput.existing?.isFile()
    && legacyOutput.existing.dev === systemOutput.existing.dev
    && legacyOutput.existing.ino === systemOutput.existing.ino
  ) {
    fail("--system-release-output must not alias --output");
  }
  const productReleaseId = arg("productReleaseId", "product-release-id");
  if (!productReleaseId) fail("FINAL phase requires --product-release-id");
  const schemas = Object.fromEntries([
    ["componentSchema", "component-manifest.schema.json"],
    ["systemSchema", "system-release-manifest.schema.json"],
    ["issueRefSchema", "issue-ref.schema.json"],
  ].map(([key, file]) => [key, readRequiredJson(path.join(repoRoot, "contracts/release", file), `release contract ${file}`)]));
  return { components, contracts, outputPath: systemReleaseOutputPath, productReleaseId, schemas };
}

function buildSystemReleaseManifest(legacyManifest, inputs) {
  assertComponentCandidateIdentity(inputs.components, legacyManifest.releaseCandidateIdentity);
  const issueRefs = [];
  for (const component of [inputs.components.mobile, inputs.components.backend, inputs.components.data, inputs.components.platform]) {
    for (const issueRef of component.issueRefs ?? []) if (!issueRefs.includes(issueRef)) issueRefs.push(issueRef);
  }
  const base = {
    schemaVersion: 2,
    productReleaseId: inputs.productReleaseId,
    phase: "FINAL",
    decision: "NO_GO",
    generatedAt,
    issueRefs,
    contracts: inputs.contracts,
    ...inputs.components,
  };
  const manifest = {
    ...base,
    decision: selectSystemReleaseDecision({ legacyDecision: legacyManifest.decision, manifest: base, ...inputs.schemas }),
  };
  const errors = validateSystemReleaseManifest({ manifest, ...inputs.schemas });
  if (errors.length > 0) fail(`system release manifest validation failed: ${errors.join(", ")}`);
  return manifest;
}

function assertComponentCandidateIdentity(components, candidate) {
  const comparisons = [
    ["mobile", "appVersionName", components.mobile?.artifactIdentity?.versionName],
    ["mobile", "versionCode", components.mobile?.artifactIdentity?.versionCode],
    ["mobile", "aabSha256", components.mobile?.artifactIdentity?.aabSha256],
    ["mobile", "dataPackManifestSha256", components.mobile?.artifactIdentity?.bundledDataManifestSha256],
    ["backend", "backendImageDigest", components.backend?.artifactIdentity?.imageDigest],
    ["data", "dataPackManifestSha256", components.data?.artifactIdentity?.manifestSha256],
    ["data", "sourceSnapshotSetHash", components.data?.artifactIdentity?.sourceSnapshotSetHash],
    ["data", "releaseSequence", components.data?.artifactIdentity?.releaseSequence],
    ["platform", "backendImageDigest", components.platform?.artifactIdentity?.deployedImageDigest],
  ];
  const integerFields = new Set(["versionCode", "releaseSequence"]);
  for (const [component, field, value] of comparisons) {
    const candidateValue = candidate?.[field];
    const matches = integerFields.has(field)
      ? Number.isSafeInteger(value) && value >= 0 && normalizeCandidateIdentityInteger(candidateValue) === value
      : candidateValue === value;
    if (
      !candidate || typeof candidate !== "object" || Array.isArray(candidate)
      || !Object.hasOwn(candidate, field) || candidateValue === null || value === undefined || value === null || !matches
    ) {
      fail(`${component} component manifest drifts from candidate context`);
    }
  }
}

function normalizeCandidateIdentityInteger(value) {
  if (typeof value === "string") {
    if (!isDigits(value) || (value !== "0" && value[0] === "0")) return null;
    value = Number(value);
  }
  return Number.isSafeInteger(value) && value >= 0 ? value : null;
}

function readRequiredJson(filePath, label) {
  try {
    return JSON.parse(readFileSync(filePath, "utf8"));
  } catch {
    fail(`${label} is unreadable or invalid JSON`);
  }
}

function isDigits(value) {
  return value.length > 0 && [...value].every((character) => character >= "0" && character <= "9");
}

function projectRcEvidenceContract(contract) {
  const sourceIssue = (issueRef) => {
    const match = typeof issueRef === "string" && issueRef.match(/^AquilaXk\/easysubway#([1-9][0-9]*)$/);
    if (!match) fail(`Invalid EasySubway issue reference: ${issueRef}`);
    return Number(match[1]);
  };
  return {
    ...contract,
    issue: sourceIssue(contract?.issueRef),
    parentIssues: contract.parentIssueRefs.map(sourceIssue),
    linkedEvidenceIssues: contract.linkedEvidenceIssueRefs.map(sourceIssue),
    phaseConsumers: Object.fromEntries(
      Object.entries(contract.phaseConsumers ?? {}).map(([phase, issueRefs]) => [phase, issueRefs.map(sourceIssue)]),
    ),
    requiredFinalFragmentIssues: contract.requiredFinalFragmentIssueRefs.map(sourceIssue),
    activeBlockerIssues: contract.activeBlockerIssueRefs.map(sourceIssue),
    requiredEvidenceEntryFields: contract.requiredEvidenceEntryFields.map(
      (field) => field === "issueRef" ? "sourceIssue" : field,
    ),
    requiredEvidenceEntries: contract.requiredEvidenceEntries.map(({ issueRef, ...entry }) => ({
      ...entry, sourceIssue: sourceIssue(issueRef),
    })),
    requiredDatapackGates: contract.requiredDatapackGates.map(({ issueRef, ...gate }) => ({
      ...gate, sourceIssue: sourceIssue(issueRef),
    })),
  };
}

function validateCandidateContext(candidate, expected) {
  if (
    candidate?.schemaVersion !== 1
    || candidate.phase !== "CANDIDATE"
    || candidate.producerVersion !== expected.producerVersion
    || Object.hasOwn(candidate, "readiness")
    || Object.hasOwn(candidate, "decision")
    || Object.hasOwn(candidate, "summaryArtifactDigest")
    || Object.hasOwn(candidate, "finalReleaseIdentity")
  ) {
    fail("--candidate-context must be a CANDIDATE artifact without readiness or decision fields");
  }
  if (!sameRcIdentity(candidate.releaseCandidateIdentity, expected.releaseCandidateIdentity)) {
    fail("FINAL releaseCandidateIdentity does not match --candidate-context");
  }
  for (const field of ["requiredGateStatuses", "requiredEvidenceEntries", "requiredDatapackGates", "consumerIssues"]) {
    if (JSON.stringify(candidate[field]) !== JSON.stringify(expected[field])) {
      fail(`--candidate-context ${field} does not match the current contract`);
    }
  }
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const raw = values[index];
    if (!raw.startsWith("--")) {
      fail(`Unexpected argument: ${raw}`);
    }
    const withoutPrefix = raw.slice(2);
    const equalsIndex = withoutPrefix.indexOf("=");
    const key = equalsIndex === -1 ? withoutPrefix : withoutPrefix.slice(0, equalsIndex);
    const value = equalsIndex === -1 ? values[++index] : withoutPrefix.slice(equalsIndex + 1);
    if (value === undefined || value.startsWith("--")) {
      fail(`Missing value for --${key}`);
    }
    if (parsed[key] === undefined) {
      parsed[key] = value;
    } else if (Array.isArray(parsed[key])) {
      parsed[key].push(value);
    } else {
      parsed[key] = [parsed[key], value];
    }
  }
  return parsed;
}

function resolvePath(value) {
  return path.resolve(cwd, value);
}

function arg(camelName, kebabName) {
  return args[camelName] ?? args[kebabName];
}

function booleanArg(camelName, kebabName) {
  const value = arg(camelName, kebabName);
  if (value === undefined) return false;
  if (value !== "true" && value !== "false") {
    fail(`--${kebabName} must be true or false`);
  }
  return value === "true";
}

function readFlutterVersion(pubspecPath) {
  const pubspec = readFileSync(pubspecPath, "utf8");
  const match = pubspec.match(/^version:\s*([0-9A-Za-z.+-]+)\s*$/m);
  if (!match) {
    fail(`version not found in ${pubspecPath}`);
  }
  const [name, code] = match[1].split("+");
  if (!name || !code) {
    fail(`Flutter version must include build number: ${match[1]}`);
  }
  return { name, code };
}

function sha256FileIfExists(filePath) {
  if (!filePath) {
    return null;
  }
  const resolved = resolvePath(filePath);
  if (!existsSync(resolved)) {
    return null;
  }
  return createHash("sha256").update(readFileSync(resolved)).digest("hex");
}

function aabPayloadSha256IfExists(filePath) {
  if (!filePath) return null;
  const resolved = resolvePath(filePath);
  if (!existsSync(resolved)) return null;
  try {
    const digest = execFileSync(process.execPath, [
      path.join(repoRoot, "tools/release/hash-android-bundle-payload.mjs"),
      "--aab",
      resolved,
    ], { encoding: "utf8", maxBuffer: 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] }).trim();
    return /^[0-9a-f]{64}$/.test(digest) ? digest : null;
  } catch {
    return null;
  }
}

function readJsonIfExists(filePath) {
  if (!filePath || !existsSync(filePath)) {
    return null;
  }
  return JSON.parse(readFileSync(filePath, "utf8"));
}

function validateProductionDataPackBinding(
  manifest, artifactPath, artifactBytes, fallbackArtifactPath, fallbackArtifactBytes,
  releaseDecision, evaluatedAtMillis,
) {
  if (!artifactPath || !existsSync(artifactPath) || !Number.isSafeInteger(artifactBytes) || artifactBytes <= 0) {
    fail("production data pack binding requires an existing non-empty artifact");
  }
  try {
    validateManifest(manifest, { requireProduction: true });
  } catch (error) {
    fail(`production data pack manifest schema validation failed: ${error.message}`);
  }
  if (manifest.manifestVersion !== 2 || manifest.channel !== "production") {
    fail("production data pack manifest must be manifestVersion 2 on the production channel");
  }
  if (Date.parse(manifest.expiresAt) <= evaluatedAtMillis) {
    fail("production data pack manifest is expired");
  }
  const activePack = selectEffectiveDataPack(manifest);
  const fallbackPack = selectFallbackDataPack(manifest);
  if (!activePack) {
    fail("production data pack manifest must identify exactly one active pack");
  }
  const artifactSha256 = createHash("sha256").update(readFileSync(artifactPath)).digest("hex");
  if (activePack.sha256 !== artifactSha256) {
    fail("production data pack manifest sha256 does not match the supplied artifact");
  }
  if (activePack.sizeBytes !== artifactBytes) {
    fail("production data pack manifest sizeBytes does not match the supplied artifact");
  }
  if (!fallbackPack || !fallbackArtifactPath || !existsSync(fallbackArtifactPath)) {
    fail("production data pack binding requires an existing fallback artifact");
  }
  const fallbackArtifactSha256 = createHash("sha256").update(readFileSync(fallbackArtifactPath)).digest("hex");
  if (fallbackPack.sha256 !== fallbackArtifactSha256 || fallbackPack.sizeBytes !== fallbackArtifactBytes) {
    fail("production data pack fallback does not match the selected manifest");
  }
  const manifestSha256 = createHash("sha256").update(readFileSync(dataPackManifestPath)).digest("hex");
  if (
    releaseDecision?.selectedManifestSha256 !== manifestSha256
    || releaseDecision?.selectedReleaseSequence !== manifest.releaseSequence
  ) {
    fail("production data pack manifest does not match the finalized release decision");
  }
}

function readFinalDataPackReleaseDecision(filePath, required) {
  if (!filePath) {
    if (required) fail("production data pack binding requires a finalized release decision");
    return null;
  }
  const decision = readJsonIfExists(resolvePath(filePath));
  const published = decision?.outcome === "PUBLISHED_AND_VERIFIED";
  const noChange = decision?.outcome === "NO_CHANGE_VALID";
  if (
    decision?.schemaVersion !== 1
    || decision.artifactKind !== "datapack-release-decision"
    || (!published && !noChange)
    || decision.productionWriteAllowed !== published
    || decision.strictValidationPassed !== true
    || decision.publishAttempted !== published
    || decision.remoteValidationPassed !== true
    || invalidFinalReasonCodes(decision.reasonCodes, published)
    || !/^[a-f0-9]{64}$/.test(decision.sourceSnapshotSetHash ?? "")
    || !/^[a-f0-9]{64}$/.test(decision.selectedManifestSha256 ?? "")
    || !Number.isSafeInteger(decision.selectedReleaseSequence)
    || decision.selectedReleaseSequence < 1
  ) {
    fail("data pack release decision is not finalized or has invalid sourceSnapshotSetHash");
  }
  return decision;
}

function readDataPackRehearsalBinding(filePath, manifestPath, manifest, artifactPath) {
  if (!filePath) return null;
  const binding = readJsonIfExists(resolvePath(filePath));
  const manifestSha256 = sha256FileIfExists(manifestPath);
  const artifactSha256 = sha256FileIfExists(artifactPath);
  if (
    binding?.schemaVersion !== 1
    || binding.artifactKind !== "datapack-prelaunch-rehearsal-binding"
    || binding.executionEnvironment !== "ISOLATED_PRELAUNCH"
    || binding.productionExecuted !== false
    || !/^[a-f0-9]{64}$/.test(binding.sourceSnapshotSetHash ?? "")
    || binding.selectedManifestSha256 !== manifestSha256
    || binding.selectedArtifactSha256 !== artifactSha256
    || !Number.isSafeInteger(binding.selectedReleaseSequence)
    || binding.selectedReleaseSequence < 1
    || binding.selectedReleaseSequence !== manifest?.releaseSequence
  ) {
    fail("data pack prelaunch rehearsal binding is invalid");
  }
  return binding;
}

function validatePrePlayUploadReadiness(identity, metadata, productionBindingRequested, releaseDecision) {
  const requiredIdentityFields = [
    "gitSha",
    "appVersionName",
    "versionCode",
    "aabSha256",
    "aabPayloadSha256",
    "dataPackManifestSha256",
    "dataPackArtifactSha256",
    "dataPackFallbackArtifactSha256",
    "sourceSnapshotSetHash",
    "supportContactSetSha256",
    "releaseSequence",
  ];
  const expectedMetadata = {
    gitSha: identity.gitSha,
    storeReadyCandidate: "true",
    signingKeyType: "production-upload-key",
    packageId: "com.easysubway.app",
    versionName: String(identity.appVersionName),
    versionCode: String(identity.versionCode),
    aabSha256: identity.aabSha256,
    aabPayloadSha256: identity.aabPayloadSha256,
    supportContactSetSha256: identity.supportContactSetSha256,
  };
  const missingIdentity = requiredIdentityFields.filter((field) => !identity[field]);
  const invalidMetadata = Object.entries(expectedMetadata)
    .filter(([field, expected]) => String(metadata[field] ?? "") !== String(expected))
    .map(([field]) => field);
  const missingSigningIdentity = ["uploadKeySha256Fingerprint", "appSigningKeySha256Fingerprint"]
    .filter((field) => typeof metadata[field] !== "string" || metadata[field].trim().length === 0);
  if (
    !productionBindingRequested
    || !releaseDecision
    || missingIdentity.length > 0
    || invalidMetadata.length > 0
    || missingSigningIdentity.length > 0
  ) {
    fail(`pre-Play upload readiness failed: ${[
      ...missingIdentity.map((field) => `identity.${field}`),
      ...invalidMetadata.map((field) => `metadata.${field}`),
      ...missingSigningIdentity.map((field) => `metadata.${field}`),
      ...(!productionBindingRequested || !releaseDecision ? ["productionDataPackBinding"] : []),
    ].join(", ")}`);
  }
}

function invalidFinalReasonCodes(reasonCodes, published) {
  if (!Array.isArray(reasonCodes) || new Set(reasonCodes).size !== reasonCodes.length) return true;
  const allowed = published ? SUCCESSFUL_FRESHNESS_REASON_CODES : new Set();
  return reasonCodes.some((reasonCode) => !allowed.has(reasonCode));
}

function readKeyValueFileIfExists(filePath) {
  if (!filePath) return {};
  const resolved = resolvePath(filePath);
  if (!existsSync(resolved)) return {};
  return Object.fromEntries(readFileSync(resolved, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => {
      const separatorIndex = line.indexOf("=");
      return separatorIndex === -1
        ? [line, ""]
        : [line.slice(0, separatorIndex), line.slice(separatorIndex + 1)];
    }));
}

function readBackendIdentity(parsedArgs) {
  const backendImageDigest = arg("backendImageDigest", "backend-image-digest");
  const backendArtifact = arg("backendArtifact", "backend-artifact");
  const backendImageInspect = arg("backendImageInspect", "backend-image-inspect");
  if (backendImageDigest) {
    return { backendImageDigest, backendArtifactSha256: null };
  }
  if (backendArtifact) {
    return { backendImageDigest: null, backendArtifactSha256: sha256FileIfExists(backendArtifact) };
  }
  if (!backendImageInspect) {
    return { backendImageDigest: null, backendArtifactSha256: null };
  }

  const inspectPath = resolvePath(backendImageInspect);
  if (!existsSync(inspectPath)) {
    return { backendImageDigest: null, backendArtifactSha256: null };
  }
  const inspect = JSON.parse(readFileSync(inspectPath, "utf8"));
  const firstImage = Array.isArray(inspect) ? inspect[0] : inspect;
  const repoDigest = firstImage?.RepoDigests?.find((digest) => digest.includes("@sha256:"));
  const imageId = typeof firstImage?.Id === "string" && firstImage.Id.startsWith("sha256:")
    ? firstImage.Id
    : null;
  return {
    backendImageDigest: repoDigest?.split("@").at(-1) ?? imageId,
    backendArtifactSha256: repoDigest || imageId ? null : sha256FileIfExists(inspectPath),
  };
}

function readRealtimeContractVersion(rootDir) {
  const contract = readJsonIfExists(path.join(rootDir, "tools/realtime/seoul-topis-provider-contract.json"));
  if (!contract) {
    return "realtime-contract-v1";
  }
  return `${contract.providerId ?? "realtime"}-schema-v${contract.schemaVersion ?? 1}`;
}

function parsePairs(value) {
  const values = value === undefined ? [] : Array.isArray(value) ? value : [value];
  const pairs = {};
  for (const entry of values) {
    const separatorIndex = entry.indexOf("=");
    if (separatorIndex === -1) {
      fail(`Expected key=value pair: ${entry}`);
    }
    const key = entry.slice(0, separatorIndex);
    if (Object.hasOwn(pairs, key)) fail(`Duplicate key=value pair: ${key}`);
    pairs[key] = entry.slice(separatorIndex + 1);
  }
  return pairs;
}

function sameRcIdentity(evidenceIdentity, currentIdentity) {
  if (!evidenceIdentity || typeof evidenceIdentity !== "object" || Array.isArray(evidenceIdentity)) return false;
  const expectedKeys = Object.keys(currentIdentity).sort(codepointCompare);
  const actualKeys = Object.keys(evidenceIdentity).sort(codepointCompare);
  return expectedKeys.length === actualKeys.length
    && expectedKeys.every((key, index) => key === actualKeys[index] && evidenceIdentity[key] === currentIdentity[key]);
}

function requiredGateEntries(requiredIds, requiredChecksById, provided, paths, identity, generatedAt, validationContext) {
  if (
    Object.keys(requiredChecksById).sort(codepointCompare).join(",")
      !== [...requiredIds].sort(codepointCompare).join(",")
    || requiredIds.some((id) => !Array.isArray(requiredChecksById[id]) || requiredChecksById[id].length === 0)
  ) {
    fail("requiredGateChecks must exactly cover requiredGateStatuses");
  }
  const duplicateId = requiredIds.find((id, index) => requiredIds.indexOf(id) !== index);
  if (duplicateId) fail(`Duplicate required gate status in contract: ${duplicateId}`);
  const knownIds = new Set(requiredIds);
  for (const id of [...Object.keys(provided), ...Object.keys(paths)]) {
    if (!knownIds.has(id)) fail(`Unknown gate status: ${id}`);
  }
  return requiredIds.map((id) => {
    const status = provided[id] ?? "BLOCKED_EXTERNAL";
    if (!["SATISFIED", "BLOCKED_EXTERNAL"].includes(status)) {
      fail(`Invalid gate status for ${id}: ${status}`);
    }
    if (status !== "SATISFIED") {
      return {
        id, status, reasonCodes: ["EVIDENCE_NOT_PROVIDED"],
        evidenceSha256: null, evaluatedAt: null, expiresAt: null, rcIdentity: identity,
      };
    }
    const evidencePath = paths[id];
    if (!evidencePath || !existsSync(resolvePath(evidencePath))) {
      fail(`SATISFIED gate requires existing --gate-evidence: ${id}`);
    }
    const evidenceBytes = readFileSync(resolvePath(evidencePath));
    const evidence = JSON.parse(evidenceBytes);
    const canonicalEnvelope = evidence.schemaVersion === 1
      && evidence.gateId === id
      && evidence.status === "SATISFIED"
      && Array.isArray(evidence.reasonCodes)
      && evidence.reasonCodes.length === 0
      && sameRcIdentity(evidence.rcIdentity, identity);
    if (!canonicalEnvelope && id !== "postLaunchOperations") {
      fail(`SATISFIED gate evidence identity or status mismatch: ${id}`);
    }
    if (id === "postLaunchOperations") {
      validateSatisfiedEvidence("post_launch_operations", 1019, evidencePath, generatedAt, validationContext);
    } else {
      requireResultSchema(evidence.result, id);
      requirePassingChecks(id, evidence.result.checks, requiredChecksById[id]);
      normalizeEvidenceReferences(id, evidence.result.evidenceReferences);
    }
    const evaluatedAt = evidence.evidenceValidity?.evaluatedAt ?? evidence.evidenceValidity?.testedAt;
    const expiresAt = evidence.evidenceValidity?.expiresAt ?? evidence.evidenceValidity?.expiresWhen;
    if (
      !Number.isFinite(Date.parse(evaluatedAt))
      || !Number.isFinite(Date.parse(expiresAt))
      || Date.parse(evaluatedAt) > Date.parse(generatedAt)
      || Date.parse(expiresAt) < Date.parse(generatedAt)
      || Date.parse(expiresAt) < Date.parse(evaluatedAt)
      || Date.parse(expiresAt) > Date.parse(addDays(evaluatedAt, 14))
    ) {
      fail(`SATISFIED gate has invalid, future, expired, or overlong evidenceValidity: ${id}`);
    }
    return {
      id, status, reasonCodes: [],
      evidenceSha256: createHash("sha256").update(evidenceBytes).digest("hex"),
      evaluatedAt: new Date(evaluatedAt).toISOString(), expiresAt: new Date(expiresAt).toISOString(),
      rcIdentity: identity,
    };
  });
}

function validateIssueDag(activeBlockerIssues, states) {
  const duplicateIssue = activeBlockerIssues.find(
    (issue, index) => activeBlockerIssues.indexOf(issue) !== index,
  );
  if (duplicateIssue !== undefined) fail(`Duplicate active blocker issue in contract: ${duplicateIssue}`);
  if (activeBlockerIssues.some((issue) => !Number.isInteger(issue) || issue <= 0)) {
    fail("activeBlockerIssues must contain positive issue numbers");
  }
  for (const [issue, state] of Object.entries(states)) {
    if (!/^[1-9]\d*$/.test(issue) || !["OPEN", "CLOSED"].includes(state)) {
      fail(`Invalid issue state: ${issue}=${state}`);
    }
  }
  for (const issue of activeBlockerIssues) {
    if (states[issue] === "CLOSED") {
      fail(`Closed issue is still referenced as an active blocker: ${issue}`);
    }
  }
}

function requiredEvidenceEntries(
  baseTestedAt, rootPath, device, androidVersion, statuses,
  paths, generatedAt, contractEntries, validationContext,
) {
  const knownIds = new Set(contractEntries.map(({ id }) => id));
  for (const id of [...Object.keys(statuses), ...Object.keys(paths)]) {
    if (!knownIds.has(id)) fail(`Unknown evidence entry: ${id}`);
  }
  for (const [id, status] of Object.entries(statuses)) {
    if (!["SATISFIED", "BLOCKED_EXTERNAL", "PENDING_LOCAL_EVIDENCE"].includes(status)) {
      fail(`Invalid evidence status for ${id}: ${status}`);
    }
    if (status === "SATISFIED" && !paths[id]) {
      fail(`SATISFIED evidence entry requires --evidence-path: ${id}`);
    }
    if (status === "SATISFIED" && !existsSync(resolvePath(paths[id]))) {
      fail(`SATISFIED evidence path does not exist for ${id}: ${paths[id]}`);
    }
  }
  return contractEntries.map(({ id, sourceIssue, expiresAfterDays, requiredChecks }) => {
    if (!id || !Number.isInteger(sourceIssue) || !Number.isInteger(expiresAfterDays) || expiresAfterDays <= 0) {
      fail(`Invalid RC evidence contract entry: ${id ?? "<missing>"}`);
    }
    const evidencePaths = [`${rootPath}${id}/`];
    if (paths[id]) evidencePaths.push(paths[id]);
    const evidenceBytes = statuses[id] === "SATISFIED" ? readFileSync(resolvePath(paths[id])) : null;
    const evidence = evidenceBytes ? JSON.parse(evidenceBytes) : null;
    if (statuses[id] === "SATISFIED" && (
      evidence?.evidenceValidity?.testedAt === undefined
      || evidence?.evidenceValidity?.expiresWhen === undefined
    )) {
      fail(`SATISFIED evidence entry requires evidenceValidity.testedAt and evidenceValidity.expiresWhen: ${id}`);
    }
    const evidenceTestedAt = evidence?.evidenceValidity?.testedAt ?? baseTestedAt;
    const evidenceExpiresWhen = evidence?.evidenceValidity?.expiresWhen ?? addDays(baseTestedAt, expiresAfterDays);
    const maxEvidenceExpiresWhen = addDays(evidenceTestedAt, expiresAfterDays);
    if (statuses[id] === "SATISFIED" && (
      !Number.isFinite(Date.parse(evidenceTestedAt))
      || !Number.isFinite(Date.parse(evidenceExpiresWhen))
      || Date.parse(evidenceTestedAt) > Date.parse(generatedAt)
      || Date.parse(evidenceExpiresWhen) < Date.parse(generatedAt)
      || Date.parse(evidenceExpiresWhen) < Date.parse(baseTestedAt)
      || Date.parse(evidenceExpiresWhen) < Date.parse(evidenceTestedAt)
    )) {
      fail(`SATISFIED evidence entry has invalid, future, or expired evidenceValidity: ${id}`);
    }
    if (statuses[id] === "SATISFIED" && Date.parse(evidenceExpiresWhen) > Date.parse(maxEvidenceExpiresWhen)) {
      fail(`SATISFIED evidence entry exceeds the ${expiresAfterDays}-day evidence lifetime: ${id}`);
    }
    if (statuses[id] === "SATISFIED") {
      validateSatisfiedEvidence(id, sourceIssue, paths[id], generatedAt, validationContext, requiredChecks);
    }
    return {
      id, sourceIssue,
      device: device ?? "local_android_emulator",
      androidVersion: androidVersion ?? "android-15-or-16",
      testedAt: evidenceTestedAt, evidencePaths,
      evidenceSha256: evidenceBytes
        ? createHash("sha256").update(evidenceBytes).digest("hex")
        : null,
      expiresWhen: evidenceExpiresWhen, status: statuses[id] ?? "PENDING_LOCAL_EVIDENCE",
    };
  });
}

function requiredDatapackGates(
  contractGates, statuses, paths, identity, generatedAt,
  dataPackArtifactPath, dataPackArtifactBytes, requiredSourceIds,
) {
  const contractIds = contractGates.map(({ id }) => id);
  const duplicateId = contractIds.find((id, index) => contractIds.indexOf(id) !== index);
  if (duplicateId) fail(`Duplicate datapack gate in contract: ${duplicateId}`);
  const knownIds = new Set(contractIds);
  for (const id of [...Object.keys(statuses), ...Object.keys(paths)]) {
    if (!knownIds.has(id)) fail(`Unknown datapack gate: ${id}`);
  }

  return contractGates.map(({ id, sourceIssue, expiresAfterDays }) => {
    validateDatapackGateContract(id, sourceIssue, expiresAfterDays);
    const status = requiredDatapackGateStatus(statuses, id);
    if (status !== "SATISFIED") {
      return {
        id, sourceIssue, status, reasonCodes: ["EVIDENCE_NOT_PROVIDED"],
        evidenceSha256: null, evaluatedAt: null, expiresAt: null, rcIdentity: identity,
      };
    }

    const evidencePath = paths[id];
    if (!evidencePath || !existsSync(resolvePath(evidencePath))) {
      fail(`SATISFIED datapack gate requires existing --datapack-gate-evidence: ${id}`);
    }
    const evidenceBytes = readFileSync(resolvePath(evidencePath));
    const evidence = JSON.parse(evidenceBytes);
    if (evidence.schemaVersion !== 1) {
      fail(`SATISFIED datapack gate has unsupported schemaVersion: ${id}`);
    }
    if (evidence.gateId !== id || evidence.sourceIssue !== sourceIssue || evidence.status !== "SATISFIED") {
      fail(`SATISFIED datapack gate identity mismatch: ${id}`);
    }
    if (!sameRcIdentity(evidence.rcIdentity, identity)) {
      fail(`SATISFIED datapack gate RC identity mismatch: ${id}`);
    }
    if (!Array.isArray(evidence.reasonCodes) || evidence.reasonCodes.some((reason) => typeof reason !== "string")) {
      fail(`SATISFIED datapack gate reasonCodes must be a string array: ${id}`);
    }
    if (evidence.reasonCodes.length > 0) {
      fail(`SATISFIED datapack gate reasonCodes must be empty: ${id}`);
    }
    const evaluatedAt = evidence.evidenceValidity?.evaluatedAt;
    const expiresAt = evidence.evidenceValidity?.expiresAt;
    if (
      !Number.isFinite(Date.parse(evaluatedAt))
      || !Number.isFinite(Date.parse(expiresAt))
      || Date.parse(evaluatedAt) > Date.parse(generatedAt)
      || Date.parse(expiresAt) < Date.parse(generatedAt)
      || Date.parse(expiresAt) < Date.parse(evaluatedAt)
    ) {
      fail(`SATISFIED datapack gate has invalid, future, or expired evidenceValidity: ${id}`);
    }
    if (Date.parse(expiresAt) > Date.parse(addDays(evaluatedAt, expiresAfterDays))) {
      fail(`SATISFIED datapack gate exceeds the ${expiresAfterDays}-day evidence lifetime: ${id}`);
    }
    const normalized = {
      id, sourceIssue, status,
      reasonCodes: [...evidence.reasonCodes].sort(codepointCompare),
      evidenceSha256: createHash("sha256").update(evidenceBytes).digest("hex"),
      evaluatedAt: new Date(evaluatedAt).toISOString(), expiresAt: new Date(expiresAt).toISOString(),
      rcIdentity: identity,
    };
    if (["source_admission", "source_governance", "freshness_conditional_publish"].includes(id)) {
      if (!/^[a-f0-9]{64}$/.test(evidence.snapshotSetIdentity ?? "")) {
        fail(`SATISFIED source datapack gate requires snapshotSetIdentity: ${id}`);
      }
      if (evidence.snapshotSetIdentity !== identity.sourceSnapshotSetHash) {
        fail(`source datapack gate snapshotSetIdentity does not match RC sourceSnapshotSetHash: ${id}`);
      }
      normalized.snapshotSetIdentity = evidence.snapshotSetIdentity;
    }
    if (id === "source_governance") {
      normalized.sourceInventory = normalizeSourceInventory(
        evidence.sourceInventory,
        generatedAt,
        expiresAt,
        requiredSourceIds,
      );
    }
    const gateResult = normalizeDatapackGateResult(
      id,
      evidence,
      identity,
      dataPackArtifactPath,
      dataPackArtifactBytes,
    );
    if (gateResult) normalized.gateResult = gateResult;
    return normalized;
  });
}

function validateDatapackGateContract(id, sourceIssue, expiresAfterDays) {
  if (!id || !Number.isInteger(sourceIssue) || !Number.isInteger(expiresAfterDays) || expiresAfterDays <= 0) {
    fail(`Invalid datapack gate contract entry: ${id ?? "<missing>"}`);
  }
}

function requiredDatapackGateStatus(statuses, id) {
  const status = statuses[id] ?? "BLOCKED_EXTERNAL";
  if (!["SATISFIED", "BLOCKED_EXTERNAL"].includes(status)) {
    fail(`Invalid datapack gate status for ${id}: ${status}`);
  }
  return status;
}

function normalizeDatapackGateResult(id, evidence, identity, dataPackArtifactPath, dataPackArtifactBytes) {
  if (["source_admission", "source_governance", "freshness_conditional_publish"].includes(id)) {
    return normalizeSourceGateResult(id, evidence.result, evidence.snapshotSetIdentity);
  }
  if (id === "rollback_rescue") return normalizeRollbackRescueResult(evidence.result, identity);
  if (id === "device_performance") {
    return normalizeDevicePerformanceResult(
      evidence.result,
      identity,
      dataPackArtifactPath,
      dataPackArtifactBytes,
    );
  }
  if (id === "callback_reconciliation") {
    return normalizeCallbackReconciliationResult(evidence.result, identity);
  }
  return null;
}

function normalizeSourceGateResult(gateId, result, snapshotSetIdentity) {
  const requiredChecks = {
    source_admission: ["schemaValidated", "licenseApproved", "redistributionApproved", "credentialRedacted", "snapshotLocked"],
    source_governance: ["inventoryComplete", "freshnessCurrent", "retentionPolicyCurrent", "rawPurgeAccounted", "credentialsRedacted"],
    freshness_conditional_publish: ["freshnessValidated", "materialChangeClassified", "approvalPolicyApplied", "monotonicSequenceVerified", "noChangeHandled"],
  };
  requireResultSchema(result, gateId);
  if (result.snapshotSetIdentity !== snapshotSetIdentity) {
    fail(`${gateId} result snapshotSetIdentity does not match the gate evidence`);
  }
  return {
    schemaVersion: 1, snapshotSetIdentity,
    checks: requirePassingChecks(gateId, result.checks, requiredChecks[gateId]),
    evidenceReferences: normalizeEvidenceReferences(gateId, result.evidenceReferences),
  };
}

function normalizeRollbackRescueResult(result, identity) {
  const gateId = "rollback_rescue";
  requireResultSchema(result, gateId);
  const sequenceFields = [
    "currentReleaseSequence", "failedReleaseSequence", "catalogMaxReleaseSequence", "rescueReleaseSequence",
  ];
  for (const field of sequenceFields) requirePositiveSafeInteger(result[field], `${gateId}.${field}`);
  if (result.currentReleaseSequence !== result.failedReleaseSequence) {
    fail(`${gateId} currentReleaseSequence must equal failedReleaseSequence`);
  }
  if (result.rescueReleaseSequence <= Math.max(
    result.currentReleaseSequence,
    result.failedReleaseSequence,
    result.catalogMaxReleaseSequence,
  )) {
    fail(`${gateId} rescueReleaseSequence must exceed current, failed, and catalog maximum sequences`);
  }
  requireSha256(result.knownGoodPackSha256, `${gateId}.knownGoodPackSha256`);
  if (![identity.dataPackArtifactSha256, identity.dataPackFallbackArtifactSha256]
    .includes(result.knownGoodPackSha256)) {
    fail(`${gateId} knownGoodPackSha256 does not match the RC identity`);
  }
  requireSha256(result.failedPackSha256, `${gateId}.failedPackSha256`);
  if (result.failedPackSha256 === result.knownGoodPackSha256) {
    fail(`${gateId} failedPackSha256 must differ from knownGoodPackSha256`);
  }
  requireSha256(result.rescueManifestSha256, `${gateId}.rescueManifestSha256`);
  if (result.rescueReleaseSequence !== identity.releaseSequence
    || result.rescueManifestSha256 !== identity.dataPackManifestSha256) {
    fail(`${gateId} result does not match the RC identity`);
  }
  const checks = requirePassingChecks(gateId, result.checks, [
    "monotonicSequence", "signatureVerified", "sqliteIntegrityVerified", "immutableCatalogWritten",
    "channelManifestPublishedLast", "idempotentRetryVerified", "androidReplayRecoveryVerified",
    "productionPreservedOnFailure", "secretRedactionVerified",
  ]);
  return {
    schemaVersion: 1,
    ...Object.fromEntries(sequenceFields.map((field) => [field, result[field]])),
    knownGoodPackSha256: result.knownGoodPackSha256,
    failedPackSha256: result.failedPackSha256,
    rescueManifestSha256: result.rescueManifestSha256,
    checks,
    evidenceReferences: normalizeEvidenceReferences(gateId, result.evidenceReferences),
  };
}

function normalizeDevicePerformanceResult(
  result,
  identity,
  dataPackArtifactPath,
  dataPackArtifactBytes,
) {
  const gateId = "device_performance";
  requireResultSchema(result, gateId);
  const profile = result.deviceProfile;
  if (
    typeof profile?.model !== "string" || profile.model.trim().length === 0
    || !Number.isSafeInteger(profile.ramBytes) || profile.ramBytes <= 0 || profile.ramBytes > 4 * 1024 * 1024 * 1024
    || !Number.isSafeInteger(profile.androidApiLevel) || profile.androidApiLevel <= 0
    || typeof profile.osBuild !== "string" || profile.osBuild.trim().length === 0
    || !Number.isSafeInteger(profile.repetitions) || profile.repetitions <= 0
  ) {
    fail(`${gateId} requires an exact device profile and positive repetition count`);
  }
  const artifact = result.artifact;
  requireSha256(artifact?.sha256, `${gateId}.artifact.sha256`);
  if (artifact.sha256 !== identity.dataPackArtifactSha256) {
    fail(`${gateId} artifact.sha256 does not match the RC identity`);
  }
  requirePositiveSafeInteger(artifact?.compressedBytes, `${gateId}.artifact.compressedBytes`);
  requirePositiveSafeInteger(artifact?.uncompressedBytes, `${gateId}.artifact.uncompressedBytes`);
  if (artifact.compressedBytes !== dataPackArtifactBytes) {
    fail(`${gateId} compressedBytes does not match the supplied data pack artifact`);
  }
  if (artifact.compressedBytes > 250 * 1024 * 1024) {
    fail(`${gateId} compressed artifact exceeds the 250 MiB cap`);
  }
  const actualUncompressedBytes = dataPackUncompressedBytes(dataPackArtifactPath, gateId);
  if (artifact.uncompressedBytes !== actualUncompressedBytes) {
    fail(`${gateId} uncompressedBytes does not match the supplied data pack artifact`);
  }
  const metrics = result.metrics;
  const metricLimits = {
    manifestFetchP95Ms: 3_000, downloadChunkIdleMaxMs: 20_000, decompressP95Ms: 30_000,
    hashSignatureP95Ms: 10_000, sqliteValidationP95Ms: 15_000, activationP95Ms: 2_000,
    peakRssIncreaseBytes: 256 * 1024 * 1024,
  };
  for (const [field, limit] of Object.entries(metricLimits)) {
    requirePositiveFiniteNumber(metrics?.[field], `${gateId}.metrics.${field}`);
    if (metrics[field] > limit) fail(`${gateId}.${field} exceeds its release SLO`);
  }
  for (const field of ["coldLoadP50Ms", "coldLoadP95Ms", "routeSearchP50Ms", "routeSearchP95Ms"]) {
    requirePositiveFiniteNumber(metrics?.[field], `${gateId}.metrics.${field}`);
  }
  if (metrics.coldLoadP95Ms < metrics.coldLoadP50Ms || metrics.routeSearchP95Ms < metrics.routeSearchP50Ms) {
    fail(`${gateId} requires P95 metrics to be greater than or equal to P50 metrics`);
  }
  for (const field of ["temporaryStorageBytes", "temporaryStorageLimitBytes"]) {
    requirePositiveSafeInteger(metrics?.[field], `${gateId}.metrics.${field}`);
  }
  const calculatedTemporaryStorageLimit = artifact.compressedBytes + (2 * artifact.uncompressedBytes);
  if (!Number.isSafeInteger(calculatedTemporaryStorageLimit)
    || metrics.temporaryStorageLimitBytes !== calculatedTemporaryStorageLimit) {
    fail(`${gateId} temporary storage limit must equal compressedBytes + 2 * uncompressedBytes`);
  }
  if (metrics.temporaryStorageBytes > metrics.temporaryStorageLimitBytes) {
    fail(`${gateId} temporary storage exceeds its calculated limit`);
  }
  const checks = requirePassingChecks(gateId, result.checks, [
    "productionTopologyArtifact", "lowestSupportedAndroidProfile", "allStageSlosPassed",
    "baselineRegressionPassed", "atomicRecoveryPassed", "rolloutBlockerConnected", "zeroCrashAnrOom",
    "zeroMainThreadStallOver700Ms", "meteredNetworkConsentVerified", "secretRedactionVerified",
  ]);
  return {
    schemaVersion: 1,
    deviceProfile: {
      model: profile.model, ramBytes: profile.ramBytes, androidApiLevel: profile.androidApiLevel,
      osBuild: profile.osBuild, repetitions: profile.repetitions,
    },
    artifact: {
      sha256: artifact.sha256, compressedBytes: artifact.compressedBytes,
      uncompressedBytes: artifact.uncompressedBytes,
    },
    metrics: Object.fromEntries([
      ...Object.keys(metricLimits),
      "coldLoadP50Ms", "coldLoadP95Ms", "routeSearchP50Ms", "routeSearchP95Ms",
      "temporaryStorageBytes", "temporaryStorageLimitBytes",
    ].map((field) => [field, metrics[field]])),
    checks,
    evidenceReferences: normalizeEvidenceReferences(gateId, result.evidenceReferences),
  };
}

function dataPackUncompressedBytes(artifactPath, gateId) {
  if (!artifactPath || !existsSync(artifactPath)) {
    fail(`${gateId} requires an existing data pack artifact`);
  }
  let descriptor;
  try {
    descriptor = openSync(artifactPath, "r");
    const output = execFileSync(process.execPath, [
      path.join(repoRoot, "tools/release/count-gzip-uncompressed-bytes.mjs"),
    ], { encoding: "utf8", maxBuffer: 64 * 1024, stdio: [descriptor, "pipe", "pipe"] }).trim();
    const bytes = Number(output);
    if (!/^(?:0|[1-9]\d*)$/.test(output) || !Number.isSafeInteger(bytes)) throw new Error("invalid byte count");
    return bytes;
  } catch {
    fail(`${gateId} data pack artifact must be valid gzip data`);
  } finally {
    if (descriptor !== undefined) closeSync(descriptor);
  }
}

function normalizeCallbackReconciliationResult(result, identity) {
  const gateId = "callback_reconciliation";
  requireResultSchema(result, gateId);
  const delivery = result.deliveryIdentity;
  if (
    typeof delivery?.releaseRequestId !== "string" || delivery.releaseRequestId.trim().length === 0
    || !Number.isSafeInteger(delivery.releaseSequence) || delivery.releaseSequence <= 0
  ) {
    fail(`${gateId} requires releaseRequestId and a positive releaseSequence`);
  }
  requireSha256(delivery.manifestSha256, `${gateId}.deliveryIdentity.manifestSha256`);
  requireSha256(delivery.idempotencyKeySha256, `${gateId}.deliveryIdentity.idempotencyKeySha256`);
  if (delivery.manifestSha256 !== identity.dataPackManifestSha256) {
    fail(`${gateId} manifestSha256 does not match the RC identity`);
  }
  if (String(delivery.releaseSequence) !== String(identity.releaseSequence)) {
    fail(`${gateId} releaseSequence does not match the RC identity`);
  }
  const expectedIdempotencyKeySha256 = createHash("sha256")
    .update(`${delivery.releaseRequestId}:${delivery.releaseSequence}:${delivery.manifestSha256}`)
    .digest("hex");
  if (delivery.idempotencyKeySha256 !== expectedIdempotencyKeySha256) {
    fail(`${gateId} idempotencyKeySha256 does not match the delivery identity`);
  }
  requireNonNegativeFiniteNumber(result.metrics?.controlPlaneConvergenceP95Ms, `${gateId}.metrics.controlPlaneConvergenceP95Ms`);
  requireNonNegativeFiniteNumber(result.metrics?.terminalDispositionMaxMs, `${gateId}.metrics.terminalDispositionMaxMs`);
  if (result.metrics.controlPlaneConvergenceP95Ms > 10 * 60 * 1_000) {
    fail(`${gateId} control-plane convergence P95 exceeds 10 minutes`);
  }
  if (result.metrics.terminalDispositionMaxMs > 70 * 60 * 1_000) {
    fail(`${gateId} terminal disposition exceeds 70 minutes`);
  }
  const checks = requirePassingChecks(gateId, result.checks, [
    "boundedRetryConverged", "independentReconciliationConverged", "duplicateSingleApply",
    "concurrentSingleApply", "identityMismatchDeadLetter", "invalidSignatureDeadLetter",
    "missingRequestDeadLetter", "rolloutCappedUntilConfirmed", "secretRedactionVerified", "manualRepairAudited",
  ]);
  return {
    schemaVersion: 1,
    deliveryIdentity: {
      releaseRequestId: delivery.releaseRequestId, releaseSequence: delivery.releaseSequence,
      manifestSha256: delivery.manifestSha256,
      idempotencyKeySha256: delivery.idempotencyKeySha256,
    },
    metrics: {
      controlPlaneConvergenceP95Ms: result.metrics.controlPlaneConvergenceP95Ms,
      terminalDispositionMaxMs: result.metrics.terminalDispositionMaxMs,
    },
    checks,
    evidenceReferences: normalizeEvidenceReferences(gateId, result.evidenceReferences),
  };
}

function requireResultSchema(result, gateId) {
  if (result?.schemaVersion !== 1) fail(`${gateId} requires result schemaVersion 1`);
}

function requirePassingChecks(gateId, checks, requiredFields) {
  const suppliedFields = checks && typeof checks === "object" && !Array.isArray(checks)
    ? Object.keys(checks).sort(codepointCompare)
    : [];
  if (
    suppliedFields.join(",") !== [...requiredFields].sort(codepointCompare).join(",")
    || requiredFields.some((field) => checks[field] !== true)
  ) {
    fail(`${gateId} requires every canonical result check to pass`);
  }
  return Object.fromEntries(
    [...requiredFields].sort(codepointCompare).map((field) => [field, true]),
  );
}

function normalizeEvidenceReferences(gateId, references) {
  if (!Array.isArray(references) || references.length === 0) {
    fail(`${gateId} requires machine-readable evidenceReferences`);
  }
  const artifactIds = new Set();
  return references.map((reference) => {
    if (
      !reference || typeof reference !== "object" || Array.isArray(reference)
      || Object.keys(reference).sort(codepointCompare).join(",") !== "artifactId,sha256"
      || typeof reference.artifactId !== "string" || reference.artifactId.trim().length === 0
      || artifactIds.has(reference.artifactId)
    ) {
      fail(`${gateId} has invalid or duplicate evidenceReferences`);
    }
    requireSha256(reference.sha256, `${gateId}.evidenceReferences.sha256`);
    artifactIds.add(reference.artifactId);
    return { artifactId: reference.artifactId, sha256: reference.sha256 };
  }).sort((left, right) => codepointCompare(left.artifactId, right.artifactId));
}

function requirePositiveSafeInteger(value, name) {
  if (!Number.isSafeInteger(value) || value <= 0) fail(`${name} must be a positive safe integer`);
}

function normalizeReleaseSequence(explicitValue, manifestValue) {
  const value = explicitValue ?? manifestValue ?? null;
  if (value === null) return null;
  const parsed = typeof value === "string" && /^(?:0|[1-9]\d*)$/.test(value)
    ? Number(value)
    : value;
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    fail(explicitValue === undefined
      ? "data pack manifest releaseSequence must be a non-negative safe integer"
      : "--release-sequence must be a non-negative safe integer");
  }
  return parsed;
}
function requireNonNegativeSafeInteger(value, name) {
  if (!Number.isSafeInteger(value) || value < 0) fail(`${name} must be a non-negative safe integer`);
}
function requireNonNegativeFiniteNumber(value, name) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) fail(`${name} must be a non-negative finite number`);
}
function requirePositiveFiniteNumber(value, name) {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0) fail(`${name} must be a positive finite number`);
}

function requireSha256(value, name) {
  if (!/^[a-f0-9]{64}$/.test(value ?? "")) fail(`${name} must be a SHA-256 digest`);
}

function normalizeSourceInventory(inventory, generatedAt, gateExpiresAt, requiredSourceIds) {
  const requiredStatuses = ["APPROVED", "REVIEW_REQUIRED", "BLOCKED", "EXPIRED"];
  const inventoryAsOfMillis = Date.parse(inventory?.inventoryAsOf);
  if (!Number.isFinite(inventoryAsOfMillis) || inventoryAsOfMillis > Date.parse(generatedAt)) {
    fail("source governance evidence requires sourceInventory.inventoryAsOf");
  }
  if (!Array.isArray(inventory.entries) || inventory.entries.length === 0) {
    fail("source governance evidence requires current sourceInventory.entries");
  }
  if (inventory.entries.some((entry) => Date.parse(entry?.evaluatedAt) > Date.parse(inventory.inventoryAsOf))) {
    fail("sourceInventory.inventoryAsOf must cover child evidence");
  }
  const sourceIds = new Set();
  const entries = inventory.entries.map((entry) => {
    if (
      typeof entry?.sourceId !== "string"
      || entry.sourceId.length === 0
      || sourceIds.has(entry.sourceId)
      || !requiredStatuses.includes(entry.status)
      || !Number.isInteger(entry.producerVersion)
      || entry.producerVersion <= 0
      || !/^[a-f0-9]{64}$/.test(entry.evidenceSha256 ?? "")
      || !Number.isFinite(Date.parse(entry.evaluatedAt))
      || !Number.isFinite(Date.parse(entry.expiresAt))
      || Date.parse(entry.evaluatedAt) > Date.parse(generatedAt)
      || Date.parse(entry.expiresAt) < Date.parse(entry.evaluatedAt)
      || Date.parse(entry.expiresAt) < Date.parse(gateExpiresAt)
      || (entry.status === "EXPIRED") !== (Date.parse(entry.expiresAt) < Date.parse(generatedAt))
    ) {
      fail("source governance evidence has invalid, duplicate, stale, or contradictory sourceInventory.entries");
    }
    sourceIds.add(entry.sourceId);
    return {
      sourceId: entry.sourceId, status: entry.status, producerVersion: entry.producerVersion,
      evidenceSha256: entry.evidenceSha256, evaluatedAt: new Date(entry.evaluatedAt).toISOString(),
      expiresAt: new Date(entry.expiresAt).toISOString(),
    };
  }).sort((left, right) => codepointCompare(left.sourceId, right.sourceId));
  const statusCounts = Object.fromEntries(requiredStatuses.map((status) => (
    [status, entries.filter((entry) => entry.status === status).length]
  )));
  const latestChildEvidenceMillis = Math.max(...entries.map(({ evaluatedAt }) => Date.parse(evaluatedAt)));
  if (inventoryAsOfMillis !== latestChildEvidenceMillis) {
    fail("sourceInventory.inventoryAsOf must equal the latest child evidence evaluatedAt");
  }
  if (
    !Array.isArray(requiredSourceIds)
    || requiredSourceIds.length === 0
    || new Set(requiredSourceIds).size !== requiredSourceIds.length
    || requiredSourceIds.some((sourceId) => typeof sourceId !== "string" || !sourceIds.has(sourceId))
  ) {
    fail("source governance inventory must include every required production source");
  }
  if (statusCounts.REVIEW_REQUIRED + statusCounts.BLOCKED + statusCounts.EXPIRED > 0) {
    fail("SATISFIED source governance requires every current inventory entry to be APPROVED");
  }
  if (
    !inventory?.statusCounts
    || Object.keys(inventory.statusCounts).sort(codepointCompare).join(",")
      !== [...requiredStatuses].sort(codepointCompare).join(",")
    || requiredStatuses.some((status) => inventory.statusCounts[status] !== statusCounts[status])
  ) {
    fail("source governance evidence statusCounts must match current sourceInventory.entries");
  }
  return { inventoryAsOf: new Date(inventory.inventoryAsOf).toISOString(), statusCounts, entries };
}

function buildSourceInventory(gates, generatedAt, producerVersion) {
  const sourceGateIds = ["source_admission", "source_governance", "freshness_conditional_publish"];
  const sourceGates = sourceGateIds.map((id) => gates.find((gate) => gate.id === id));
  if (sourceGates.some((gate) => gate?.status !== "SATISFIED")) return null;
  const snapshotSetIdentity = sourceGates[0].snapshotSetIdentity;
  if (sourceGates.some((gate) => gate.snapshotSetIdentity !== snapshotSetIdentity)) {
    fail("SATISFIED source datapack gates have mixed snapshotSetIdentity");
  }
  const governance = sourceGates.find(({ id }) => id === "source_governance");
  const inventoryAsOfMillis = Date.parse(governance.sourceInventory.inventoryAsOf);
  const latestEvidenceMillis = Math.max(...sourceGates.map(({ evaluatedAt }) => Date.parse(evaluatedAt)));
  if (inventoryAsOfMillis !== latestEvidenceMillis || inventoryAsOfMillis > Date.parse(generatedAt)) {
    fail("sourceInventory.inventoryAsOf must equal the latest source gate evidence and not be in the future");
  }
  return {
    inventoryAsOf: new Date(inventoryAsOfMillis).toISOString(),
    generatedAt,
    producerVersion,
    statusCounts: Object.fromEntries(
      ["APPROVED", "REVIEW_REQUIRED", "BLOCKED", "EXPIRED"]
        .map((status) => [status, governance.sourceInventory.statusCounts[status]]),
    ),
    entries: governance.sourceInventory.entries,
    snapshotSetIdentity,
  };
}

function readIdentityLinkage(evidencePath, identity, identityMatrix, generatedAt) {
  if (!evidencePath) {
    return {
      status: "BLOCKED_EXTERNAL", reasonCodes: ["EVIDENCE_NOT_PROVIDED"],
      evidenceSha256: null, evaluatedAt: null, expiresAt: null, sharedIdentity: null,
    };
  }
  const resolved = resolvePath(evidencePath);
  if (!existsSync(resolved)) fail("--identity-linkage-evidence path does not exist");
  const evidenceBytes = readFileSync(resolved);
  const evidence = JSON.parse(evidenceBytes);
  if (
    evidence.schemaVersion !== 1
    || evidence.status !== "SATISFIED"
    || !Array.isArray(evidence.reasonCodes)
    || evidence.reasonCodes.length > 0
  ) {
    fail("identity linkage evidence must be schemaVersion 1 SATISFIED with empty reasonCodes");
  }
  if (!sameRcIdentity(evidence.rcIdentity, identity)) {
    fail("identity linkage evidence RC identity mismatch");
  }
  const evaluatedAt = evidence.evidenceValidity?.evaluatedAt;
  const expiresAt = evidence.evidenceValidity?.expiresAt;
  if (
    !Number.isFinite(Date.parse(evaluatedAt))
    || !Number.isFinite(Date.parse(expiresAt))
    || Date.parse(evaluatedAt) > Date.parse(generatedAt)
    || Date.parse(expiresAt) < Date.parse(generatedAt)
    || Date.parse(expiresAt) > Date.parse(addDays(evaluatedAt, 14))
  ) {
    fail("identity linkage evidence has invalid, future, expired, or overlong evidenceValidity");
  }
  const artifactNames = ["sourceTimetableArtifact", "serverTimetableSnapshot", "mobileTopologyPack"];
  const requiredFields = identityMatrix.requiredSharedFields;
  if (!Array.isArray(requiredFields) || requiredFields.length === 0) {
    fail("identity linkage matrix requires shared fields");
  }
  const artifacts = artifactNames.map((name) => [name, evidence[name]]);
  const artifactIds = new Set();
  for (const [name, artifact] of artifacts) {
    if (
      typeof artifact?.artifactId !== "string"
      || artifact.artifactId.length === 0
      || !/^[a-f0-9]{64}$/.test(artifact.sha256 ?? "")
      || !Number.isFinite(Date.parse(artifact.freshUntil))
      || Date.parse(artifact.freshUntil) < Date.parse(generatedAt)
    ) {
      fail(`identity linkage has invalid or expired ${name}`);
    }
    if (Date.parse(artifact.freshUntil) < Date.parse(expiresAt)) {
      fail(`identity linkage freshness does not cover evidence expiry: ${name}`);
    }
    if (name === "mobileTopologyPack" && artifact.sha256 !== identity.dataPackArtifactSha256) {
      fail("mobileTopologyPack sha256 does not match the RC data pack artifact");
    }
    artifact.identity = normalizeArtifactIdentity(name, artifact.identity, requiredFields);
    artifactIds.add(artifact.artifactId);
  }
  if (artifactIds.size !== artifactNames.length) fail("identity linkage artifactId values must be distinct");
  const sharedIdentity = Object.fromEntries(requiredFields.map((field) => {
    const value = artifacts[0][1].identity?.[field];
    if (!validSharedIdentityField(field, value)) {
      fail(`identity linkage has missing or invalid shared field: ${field}`);
    }
    if (artifacts.some(([, artifact]) => artifact.identity?.[field] !== value)) {
      fail(`identity linkage shared field mismatch: ${field}`);
    }
    return [field, value];
  }));
  return {
    status: "SATISFIED", reasonCodes: [],
    evidenceSha256: createHash("sha256").update(evidenceBytes).digest("hex"),
    evaluatedAt: new Date(evaluatedAt).toISOString(), expiresAt: new Date(expiresAt).toISOString(), sharedIdentity,
    ...Object.fromEntries(artifacts.map(([name, artifact]) => [name, {
      artifactId: artifact.artifactId, sha256: artifact.sha256,
      freshUntil: new Date(artifact.freshUntil).toISOString(),
      identity: artifact.identity,
    }])),
  };
}

function normalizeArtifactIdentity(name, identity, requiredFields) {
  if (!identity || typeof identity !== "object" || Array.isArray(identity)) {
    fail(`identity linkage has invalid ${name}.identity`);
  }
  const entries = Object.entries(identity).sort(([left], [right]) => codepointCompare(left, right));
  const allowedFields = new Set(requiredFields);
  if (
    entries.length === 0
    || entries.some(([key, value]) => (
      !allowedFields.has(key)
      || !/^[A-Za-z][A-Za-z0-9]*$/.test(key)
      || /(secret|token|credential|password|privatekey)/i.test(key)
      || !["string", "number", "boolean"].includes(typeof value)
      || (typeof value === "string" && value.trim().length === 0)
      || (typeof value === "number" && !Number.isFinite(value))
    ))
  ) {
    fail(`identity linkage has unsafe or non-scalar ${name}.identity`);
  }
  return Object.fromEntries(requiredFields.map((field) => [field, identity[field]]));
}

function validSharedIdentityField(field, value) {
  return field === "schemaVersion"
    ? Number.isSafeInteger(value) && value > 0
    : typeof value === "string" && value.trim().length > 0;
}

function validateSatisfiedEvidence(id, sourceIssue, evidencePath, generatedAt, context, requiredChecks) {
  const evidence = readJsonIfExists(resolvePath(evidencePath));
  if (id === "post_launch_operations") {
    validatePostLaunchOperationsEvidence(evidencePath, generatedAt, context);
    return;
  }
  if (!(
    evidence?.schemaVersion === 1
    && evidence?.evidenceId === id
    && evidence?.sourceIssue === sourceIssue
    && evidence?.status === "SATISFIED"
    && Array.isArray(evidence?.reasonCodes)
    && evidence.reasonCodes.length === 0
    && sameRcIdentity(evidence?.rcIdentity, context.identity)
  )) {
    fail(`SATISFIED evidence entry failed canonical envelope validation: ${id}`);
  }
  if (id === "abuse_penetration_rehearsal") {
    if (typeof evidence.canonicalSummaryPath !== "string" || evidence.canonicalSummaryPath.length === 0) {
      fail(`${id} requires an existing canonicalSummaryPath`);
    }
    const canonicalSummaryPath = resolvePath(evidence.canonicalSummaryPath);
    if (!existsSync(canonicalSummaryPath)) {
      fail(`${id} requires an existing canonicalSummaryPath`);
    }
    const canonicalSummarySha256 = sha256FileIfExists(canonicalSummaryPath);
    if (evidence.canonicalSummarySha256 !== canonicalSummarySha256) {
      fail(`${id} canonicalSummarySha256 mismatch`);
    }
    runCanonicalValidator(id, context.repoRoot, [
      path.join(context.repoRoot, "tools/security/validate-abuse-penetration-summary.mjs"),
      "--summary",
      canonicalSummaryPath,
      "--require-pass",
    ]);
    validateAbuseSummaryIdentity(canonicalSummaryPath, context);
    return;
  }
  if (!Array.isArray(requiredChecks) || requiredChecks.length === 0) {
    fail(`SATISFIED evidence entry has no canonical validator or required checks: ${id}`);
  }
  requireResultSchema(evidence.result, id);
  requirePassingChecks(id, evidence.result.checks, requiredChecks);
  normalizeEvidenceReferences(id, evidence.result.evidenceReferences);
}

function validateAbuseSummaryIdentity(summaryPath, context) {
  const summaryIdentity = readJsonIfExists(summaryPath)?.artifactIdentity;
  const identity = context.identity;
  const baseMatches = summaryIdentity
    && summaryIdentity.gitSha === identity.gitSha
    && String(summaryIdentity.versionCode) === String(identity.versionCode)
    && summaryIdentity.androidApplicationId === context.androidApplicationId
    && summaryIdentity.dataPackManifestSha256 === identity.dataPackManifestSha256
    && summaryIdentity.aabSha256 === identity.aabSha256;
  const backendFields = ["backendImageDigest", "backendArtifactSha256"];
  const backendMatches = backendFields.some((field) => (
    typeof identity[field] === "string"
    && identity[field].length > 0
    && summaryIdentity?.[field] === identity[field]
  )) && backendFields.every((field) => (
    summaryIdentity?.[field] === undefined || summaryIdentity[field] === identity[field]
  ));
  if (!baseMatches || !backendMatches) {
    fail("abuse_penetration_rehearsal canonical summary RC identity mismatch");
  }
}

function validatePostLaunchOperationsEvidence(evidencePath, generatedAt, context) {
  const validationDir = mkdtempSync(path.join(tmpdir(), "easysubway-rc-evidence-validation-"));
  const rcManifestPath = path.join(validationDir, "rc-evidence-manifest.json");
  writeFileSync(rcManifestPath, `${JSON.stringify({
    schemaVersion: 1,
    releaseGate: "rc-evidence-manifest",
    androidApplicationId: context.androidApplicationId,
    rcIdentity: context.identity,
  }, null, 2)}\n`);
  let validationError = null;
  try {
    execFileSync(process.execPath, [
      path.join(context.repoRoot, "tools/ops/validate-operations-release-summary.mjs"),
      "--summary",
      resolvePath(evidencePath),
      "--rc-manifest",
      rcManifestPath,
      "--now",
      generatedAt,
      "--require-pass",
    ], { cwd: context.repoRoot, stdio: "pipe" });
  } catch (error) {
    validationError = error.stderr?.toString().trim() || error.message;
  } finally {
    rmSync(validationDir, { recursive: true, force: true });
  }
  if (validationError) {
    fail(`SATISFIED evidence entry failed canonical validation: post_launch_operations: ${validationError}`);
  }
}

function runCanonicalValidator(id, repositoryRoot, validatorArgs) {
  try {
    execFileSync(process.execPath, validatorArgs, { cwd: repositoryRoot, stdio: "pipe" });
  } catch (error) {
    const detail = error.stderr?.toString().trim() || error.message;
    fail(`SATISFIED evidence entry failed canonical validation: ${id}: ${detail}`);
  }
}

function normalizeEvidenceRoot(rootPath) {
  return rootPath.endsWith("/") ? rootPath : `${rootPath}/`;
}

function addDays(isoDate, days) {
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) {
    fail(`Invalid testedAt value: ${isoDate}`);
  }
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString();
}

function identityBlockers(values) {
  const required = [
    "gitSha",
    "appVersionName",
    "versionCode",
    "aabSha256",
    "aabPayloadSha256",
    "dataPackManifestSha256",
    "dataPackArtifactSha256",
    "dataPackFallbackArtifactSha256",
    "sourceSnapshotSetHash",
    "supportContactSetSha256",
    "releaseSequence",
    "routeContractVersion",
    "realtimeContractVersion",
    "launchScopeId",
    "launchScopeSha256",
    "nationwideRoadmapScopeId",
    "nationwideRoadmapScopeSha256",
    "identityLinkageMatrixSha256",
  ];
  const blockers = required
    .filter((field) => !values[field])
    .map((field) => ({ id: `missing_${field}`, severity: "P0", reason: `${field} is required for RC identity` }));
  if (!values.backendImageDigest && !values.backendArtifactSha256) {
    blockers.push({
      id: "missing_backend_identity",
      severity: "P0",
      reason: "backendImageDigest or backendArtifactSha256 is required for RC identity",
    });
  }
  return blockers;
}

function expectedMismatchBlockers(values, expected) {
  return Object.entries(expected)
    .filter(([key, expectedValue]) => `${values[key] ?? ""}` !== expectedValue)
    .map(([key, expectedValue]) => ({
      id: `mismatch_${key}`,
      severity: "P0",
      reason: `${key} expected ${expectedValue} but got ${values[key] ?? "missing"}`,
    }));
}

function androidReleaseMetadataMismatchBlockers(values, metadata) {
  if (!metadata.aabPayloadSha256 || metadata.aabPayloadSha256 === values.aabPayloadSha256) return [];
  return [{
    id: "mismatch_android_release_metadata_aabPayloadSha256",
    severity: "P0",
    reason: "aabPayloadSha256 in release metadata does not match the supplied AAB payload",
  }];
}

function gateStatusBlockers(statuses) {
  return Object.entries(statuses)
    .filter(([, status]) => status !== "SATISFIED" && status !== "DEFERRED_OUT_OF_SCOPE")
    .map(([gate, status]) => ({
      id: `gate_${gate}_${status}`.toLowerCase(),
      severity: "P0",
      reason: `${gate} gate status is ${status}`,
    }));
}

function requiredOpenP0Count(raw = "0") {
  const count = Number(raw);
  if (!/^(?:0|[1-9]\d*)$/.test(raw) || !Number.isSafeInteger(count)) {
    fail("--open-android-p0-count must be a non-negative integer");
  }
  return count;
}

function openP0Blockers(count) {
  return count > 0
    ? [{ id: "open_android_p0", severity: "P0", reason: `${count} Android P0 issue(s) are open` }]
    : [];
}

function activeIssueBlockers(issues) {
  return issues.map((issue) => ({
    id: `active_blocker_issue_${issue}`,
    severity: "P0",
    reason: `Issue #${issue} is declared as an active release blocker`,
  }));
}

function evidenceBlockers(entries) {
  return entries
    .filter((entry) => entry.status !== "SATISFIED")
    .map((entry) => ({
      id: `pending_${entry.id}`,
      severity: "P0",
      reason: `Evidence entry ${entry.id} from #${entry.sourceIssue} is not satisfied`,
    }));
}

function datapackGateBlockers(gates) {
  return gates
    .filter(({ status }) => status !== "SATISFIED")
    .map(({ id, sourceIssue, status }) => ({
      id: `datapack_gate_${id}_${status}`.toLowerCase(),
      severity: "P0",
      reason: `Datapack gate ${id} from #${sourceIssue} is ${status}`,
    }));
}

function identityLinkageBlockers(linkage) {
  return linkage.status === "SATISFIED"
    ? []
    : [{
        id: "identity_linkage_blocked_external",
        severity: "P0",
        reason: "Source, server, and mobile artifact identity linkage evidence is not satisfied",
      }];
}

function githubWorkflowRunUrl(env) {
  if (!env.GITHUB_SERVER_URL || !env.GITHUB_REPOSITORY || !env.GITHUB_RUN_ID) return null;
  return `${env.GITHUB_SERVER_URL}/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`;
}

function currentGitSha(repositoryRoot) {
  try {
    return execFileSync("/usr/bin/git", ["rev-parse", "HEAD"], { cwd: repositoryRoot, encoding: "utf8" }).trim();
  } catch {
    fail("current checkout Git SHA is required");
  }
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
