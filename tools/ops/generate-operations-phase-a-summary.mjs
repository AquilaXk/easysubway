#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  const name = process.argv[index];
  const value = process.argv[index + 1];
  if (!name?.startsWith("--") || value === undefined) throw new Error(`invalid argument: ${name ?? "<missing>"}`);
  args.set(name, value);
}

const rcManifestPath = requiredArg("--rc-manifest");
const summaryPath = requiredArg("--summary");
const statusOutputPath = requiredArg("--status-output");
const [rcManifest, observability, postLaunch, support] = await Promise.all([
  readJson(rcManifestPath),
  readJson(args.get("--observability-gate") ?? "apps/mobile/release/operations-observability-gate.json"),
  readJson(args.get("--post-launch-gate") ?? "apps/mobile/release/post-launch-operations-review-gate.json"),
  readJson(args.get("--support-gate") ?? "apps/mobile/release/support-incident-response-gate.json"),
]);

const identity = rcManifest.rcIdentity ?? {};
const requiredIdentity = postLaunch.preLaunchReadiness.finalRcBinding.requiredFields;
const backendIdentityFields = postLaunch.preLaunchReadiness.finalRcBinding.backendIdentityFieldsAnyOf;
const validatedArtifactIdentity = postLaunch.preLaunchReadiness.finalRcBinding.validatedArtifactIdentity ?? {};
const validity = postLaunch.preLaunchReadiness.finalRcBinding.evidenceValidity;
const now = Date.parse(args.get("--now") ?? new Date().toISOString());
const validFrom = Date.parse(`${validity.validFromKst}T00:00:00+09:00`);
const validUntil = Date.parse(`${validity.validUntilKst}T23:59:59.999+09:00`);
const refreshBindings = postLaunch.preLaunchReadiness.finalRcBinding.refreshBindings ?? [];
const refreshChecks = await Promise.all(refreshBindings.map(async (binding) => {
  if (!Array.isArray(binding.files) || binding.files.length === 0) return false;
  const fileChecks = await Promise.all(binding.files.map(async (file) => {
    try {
      const contents = await readFile(file.path);
      return createHash("sha256").update(contents).digest("hex") === file.sha256;
    } catch {
      return false;
    }
  }));
  return fileChecks.every(Boolean);
}));
const refreshConditions = new Set(validity.refreshOn);
const refreshBindingsReady = refreshBindings.length === refreshConditions.size
  && new Set(refreshBindings.map((binding) => binding.refreshOn)).size === refreshBindings.length
  && refreshBindings.every((binding) => refreshConditions.has(binding.refreshOn))
  && refreshChecks.every(Boolean);
const validatedSignals = new Map(
  (observability.phaseAValidatedEvidence ?? []).map((item) => [item.signalId, item]),
);
const validatedChannels = new Map(
  (support.latestQaEvidenceSummary.channelEvidence ?? []).map((item) => [item.channelId, item]),
);
const requiredEvidence = postLaunch.preLaunchReadiness.requiredEvidence ?? [];
const evidenceSummary = postLaunch.preLaunchReadiness.evidenceSummary ?? [];
const evidenceSummaryById = new Map(evidenceSummary.map((item) => [item.id, item]));
const evidenceSummaryReady = new Set(requiredEvidence).size === requiredEvidence.length
  && requiredEvidence.length === evidenceSummary.length
  && evidenceSummaryById.size === evidenceSummary.length
  && requiredEvidence.every((evidenceId) => evidenceSummaryById.get(evidenceId)?.status === "PASS");
const signalEvidenceReady = validatedSignals.size === observability.signals.length
  && observability.signals.every((signal) => {
    const item = validatedSignals.get(signal.id);
    const evidenceIds = new Set(item?.evidenceIds ?? []);
    return item?.result === "PASS"
      && observability.signalEvidencePolicy.allowedResolutionKinds.includes(item.resolutionKind)
      && item.resolutionKind !== "external-blocker-record"
      && typeof item.localEvidencePath === "string" && item.localEvidencePath.length > 0
      && typeof item.redactionNotes === "string" && item.redactionNotes.length > 0
      && signal.evidence.every((evidenceId) => evidenceIds.has(evidenceId));
  });
const channelEvidenceReady = validatedChannels.size === support.supportChannels.length
  && support.supportChannels.every((channel) => {
    const item = validatedChannels.get(channel.id);
    const evidenceIds = new Set(item?.evidenceIds ?? []);
    const receivedAt = Date.parse(item?.receivedAt);
    return item?.result === "PASS"
      && typeof item.redactedReceiptReference === "string" && item.redactedReceiptReference.length > 0
      && typeof item.receivedAt === "string" && Number.isFinite(receivedAt)
      && receivedAt >= validFrom && receivedAt <= validUntil && receivedAt <= now
      && typeof item.redactionNotes === "string" && item.redactionNotes.length > 0
      && typeof item.localEvidencePath === "string" && item.localEvidencePath.length > 0
      && channel.requiredEvidence.every((evidenceId) => evidenceIds.has(evidenceId));
  });
const validatedBackendIdentityReady = backendIdentityFields.some((field) => (
  typeof validatedArtifactIdentity[field] === "string"
  && validatedArtifactIdentity[field].length > 0
  && identity[field] === validatedArtifactIdentity[field]
)) && backendIdentityFields.every((field) => (
  identity[field] === undefined
  || identity[field] === null
  || identity[field] === ""
  || identity[field] === validatedArtifactIdentity[field]
));
const validatedArtifactIdentityReady = identity.aabSha256 === validatedArtifactIdentity.aabSha256
  && identity.dataPackManifestSha256 === validatedArtifactIdentity.dataPackManifestSha256
  && validatedBackendIdentityReady;
const ready = postLaunch.preLaunchReadiness.status === "PASS"
  && support.preLaunchReadiness.status === "PASS"
  && rcManifest.androidApplicationId === postLaunch.androidApplicationId
  && refreshBindingsReady
  && signalEvidenceReady
  && channelEvidenceReady
  && validatedArtifactIdentityReady
  && evidenceSummaryReady
  && support.latestQaEvidenceSummary.remainingSupportReadiness.length === 0
  && support.latestQaEvidenceSummary.helpScreenDeviceQa.result === "PASS"
  && String(support.latestQaEvidenceSummary.helpScreenDeviceQa.versionName) === String(identity.appVersionName)
  && String(support.latestQaEvidenceSummary.helpScreenDeviceQa.versionCode) === String(identity.versionCode)
  && support.latestQaEvidenceSummary.helpScreenDeviceQa.contactSetSha256 === identity.supportContactSetSha256
  && support.latestQaEvidenceSummary.operatorContactReadiness.result === "PASS"
  && identity.appVersionName === validity.appVersionName
  && String(identity.versionCode) === String(validity.versionCode)
  && Number.isFinite(now) && now >= validFrom && now <= validUntil
  && requiredIdentity.every((field) => identity[field] !== undefined && identity[field] !== null && identity[field] !== "")
  && backendIdentityFields.some((field) => identity[field] !== undefined && identity[field] !== null && identity[field] !== "");

await mkdir(path.dirname(statusOutputPath), { recursive: true });
if (!ready) {
  await rm(summaryPath, { force: true });
  await writeFile(statusOutputPath, "BLOCKED_EXTERNAL\n");
  process.exit(0);
}

const artifactIdentity = {
  gitSha: identity.gitSha,
  versionName: identity.appVersionName,
  versionCode: identity.versionCode,
  androidApplicationId: rcManifest.androidApplicationId,
  aabSha256: identity.aabSha256,
  dataPackManifestSha256: identity.dataPackManifestSha256,
  supportContactSetSha256: identity.supportContactSetSha256,
};
for (const field of backendIdentityFields) {
  if (identity[field] !== undefined && identity[field] !== null && identity[field] !== "") {
    artifactIdentity[field] = identity[field];
  }
}

const summary = {
  schemaVersion: 1,
  releaseGate: "operations-release-summary",
  issue: 1019,
  status: "PASS",
  evidenceValidity: {
    testedAt: `${postLaunch.preLaunchReadiness.evidenceDateKst}T00:00:00+09:00`,
    expiresWhen: `${validity.validUntilKst}T23:59:59.999+09:00`,
  },
  artifactIdentity,
  preLaunchReadiness: {
    status: "PASS",
    evidenceIds: requiredEvidence,
  },
  postLaunchObservation: {
    status: "PENDING_PUBLIC_RELEASE",
    publicReleaseIdentity: { publishedAt: null, versionCode: null, gitSha: null },
  },
  observabilitySignals: observability.signals.map((signal) => {
    const evidence = validatedSignals.get(signal.id);
    return {
      signalId: signal.id,
      owner: signal.ownerKo,
      threshold: signal.thresholdKo,
      firstResponse: signal.firstResponseKo,
      resolutionKind: evidence.resolutionKind,
      evidenceIds: evidence.evidenceIds,
      result: evidence.result,
      redactionNotes: evidence.redactionNotes,
      localEvidencePath: evidence.localEvidencePath,
    };
  }),
  postLaunchDryRunEvidence: postLaunch.dryRunRequiredEvidence,
  supportChannels: support.supportChannels.map((channel) => {
    const evidence = validatedChannels.get(channel.id);
    return {
      channelId: channel.id,
      redactedReceiptReference: evidence.redactedReceiptReference,
      receivedAt: evidence.receivedAt,
      owner: channel.ownerKo,
      result: evidence.result,
      redactionNotes: evidence.redactionNotes,
      localEvidencePath: evidence.localEvidencePath,
      evidenceIds: evidence.evidenceIds,
    };
  }),
  supportDryRunEvidence: support.dryRunRequiredEvidence,
  operatorContactRoutes: support.operatorContactRoutes.map((route) => ({
    routeId: route.id,
    evidenceIds: route.requiredEvidence,
    result: "PASS",
    localEvidencePath: support.latestQaEvidenceSummary.operatorContactReadiness.localOnlyEvidence,
  })),
  dataCorrectionSteps: support.dataCorrectionFlow.requiredSteps,
  fixedReleaseSteps: postLaunch.fixedReleaseProcedure.requiredSteps,
  externalBlockers: [],
};

await mkdir(path.dirname(summaryPath), { recursive: true });
await writeFile(summaryPath, `${JSON.stringify(summary, null, 2)}\n`);
await writeFile(statusOutputPath, "SATISFIED\n");

function requiredArg(name) {
  const value = args.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}

async function readJson(filePath) {
  return JSON.parse(await readFile(filePath, "utf8"));
}
