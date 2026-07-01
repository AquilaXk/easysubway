#!/usr/bin/env node
import {
  argValue,
  collectStrings,
  readJson,
  required,
  stableFlatJson,
} from "../release/summary-validation-utils.mjs";

const STATUS = new Set(["PASS", "FAIL", "BLOCKED_EXTERNAL"]);
const RAW_SECRET_PATTERNS = [
  /https?:\/\/\S*(x-amz-signature|x-goog-signature|signature=|sig=|token=|receipt)/i,
  /\bAuthorization:\s*(Bearer|Basic)\s+\S+/i,
  /\bCookie:\s*\S+/i,
  /\b(JSESSIONID|sessionid)=\S+/i,
  /\b[a-f0-9]{64}\b.*\b(device|mailbox|personal)\b/i,
];

function assertNoSensitiveSummary(summary, gates) {
  const observabilityMarkers = [
    gates.observability.sensitiveLogPolicy.forbidReceiptTokens ? "receipt token" : "",
    gates.observability.sensitiveLogPolicy.forbidUploadUrls ? "upload URL" : "",
    gates.observability.sensitiveLogPolicy.forbidPhotoMetadata ? "photo metadata" : "",
  ];
  const forbiddenValues = new Set([
    ...observabilityMarkers,
    ...gates.postLaunch.releaseEvidenceSummaryPolicy.forbiddenInGithubSummary,
    ...gates.postLaunch.sensitiveEvidencePolicy.forbiddenInPullRequest,
    ...gates.support.supportEvidenceSummaryPolicy.forbiddenInGithubSummary,
    ...gates.support.sensitiveEvidencePolicy.forbiddenInPullRequest,
  ].filter(Boolean).map((value) => value.toLowerCase()));
  for (const [path, value] of collectStrings(summary)) {
    const normalized = value.toLowerCase();
    const descriptivePolicyField = /\.(firstResponse|threshold|decision|redactionNotes)$/.test(path);
    if (!descriptivePolicyField) {
      for (const forbidden of forbiddenValues) {
        if (normalized.includes(forbidden)) {
          throw new Error(`${path} contains forbidden sensitive evidence marker: ${forbidden}`);
        }
      }
    } else {
      for (const forbidden of forbiddenValues) {
        const rawMarker = forbidden.startsWith("raw ") ? forbidden : `raw ${forbidden}`;
        if (normalized.includes(rawMarker)) {
          throw new Error(`${path} contains forbidden sensitive evidence marker: ${rawMarker}`);
        }
      }
    }
    for (const pattern of RAW_SECRET_PATTERNS) {
      if (pattern.test(value)) {
        throw new Error(`${path} appears to contain raw secret, token, cookie, signed URL, or personal data`);
      }
    }
  }
}

function assertIdentity(summary, path = "artifactIdentity") {
  const identity = required(summary.artifactIdentity, path);
  for (const field of [
    "gitSha",
    "versionName",
    "versionCode",
    "androidApplicationId",
    "aabSha256",
    "backendArtifactSha256",
    "dataPackManifestSha256",
  ]) {
    required(identity[field], `${path}.${field}`);
  }
  return identity;
}

function assertObservability(summary, gate, requirePass) {
  const allowedKinds = new Set(gate.signalEvidencePolicy.allowedResolutionKinds);
  const byId = new Map(required(summary.observabilitySignals, "observabilitySignals").map((item) => [item.signalId, item]));
  for (const signal of gate.signals) {
    const item = required(byId.get(signal.id), `observabilitySignals.${signal.id}`);
    required(item.owner, `observabilitySignals.${signal.id}.owner`);
    required(item.threshold, `observabilitySignals.${signal.id}.threshold`);
    required(item.firstResponse, `observabilitySignals.${signal.id}.firstResponse`);
    required(item.result, `observabilitySignals.${signal.id}.result`);
    required(item.redactionNotes, `observabilitySignals.${signal.id}.redactionNotes`);
    required(item.localEvidencePath, `observabilitySignals.${signal.id}.localEvidencePath`);
    if (!allowedKinds.has(item.resolutionKind)) {
      throw new Error(`observabilitySignals.${signal.id}.resolutionKind must be allowed`);
    }
    if (requirePass && item.resolutionKind === "external-blocker-record") {
      throw new Error("external-blocker-record cannot satisfy --require-pass");
    }
    const evidence = new Set(required(item.evidenceIds, `observabilitySignals.${signal.id}.evidenceIds`));
    if (!signal.evidence.some((evidenceId) => evidence.has(evidenceId))) {
      throw new Error(`observabilitySignals.${signal.id}.evidenceIds must include signal evidence`);
    }
    if (requirePass && item.result !== "PASS") {
      throw new Error(`observabilitySignals.${signal.id}.result must be PASS`);
    }
  }
}

function assertPostLaunch(summary, gate, artifactIdentity, requirePass) {
  const byId = new Map(required(summary.postLaunchReviews, "postLaunchReviews").map((item) => [item.reviewWindowId, item]));
  for (const window of gate.reviewWindows) {
    const item = required(byId.get(window.id), `postLaunchReviews.${window.id}`);
    assertIdentity(item, `postLaunchReviews.${window.id}.artifactIdentity`);
    if (stableFlatJson(item.artifactIdentity) !== stableFlatJson(artifactIdentity)) {
      throw new Error(`postLaunchReviews.${window.id}.artifactIdentity must match artifactIdentity`);
    }
    for (const field of gate.releaseEvidenceSummaryPolicy.githubSummaryFields) {
      required(item[field], `postLaunchReviews.${window.id}.${field}`);
    }
    const snapshot = new Set(required(item.signalSnapshot, `postLaunchReviews.${window.id}.signalSnapshot`));
    for (const signalId of window.requiredSignals) {
      if (!snapshot.has(signalId)) throw new Error(`postLaunchReviews.${window.id}.signalSnapshot missing ${signalId}`);
    }
    if (requirePass && item.goNoGoResult !== "PASS") {
      throw new Error(`postLaunchReviews.${window.id}.goNoGoResult must be PASS`);
    }
  }
  const fixedSteps = new Set(required(summary.fixedReleaseSteps, "fixedReleaseSteps"));
  for (const step of gate.fixedReleaseProcedure.requiredSteps) {
    if (!fixedSteps.has(step)) throw new Error(`fixedReleaseSteps missing ${step}`);
  }
  const dryRunEvidence = new Set(required(summary.postLaunchDryRunEvidence, "postLaunchDryRunEvidence"));
  for (const evidenceId of gate.dryRunRequiredEvidence) {
    if (!dryRunEvidence.has(evidenceId)) throw new Error(`postLaunchDryRunEvidence missing ${evidenceId}`);
  }
}

function assertSupport(summary, gate, requirePass) {
  const byId = new Map(required(summary.supportChannels, "supportChannels").map((item) => [item.channelId, item]));
  for (const channel of gate.supportChannels) {
    const item = required(byId.get(channel.id), `supportChannels.${channel.id}`);
    for (const field of gate.supportEvidenceSummaryPolicy.githubSummaryFields) {
      required(item[field], `supportChannels.${channel.id}.${field}`);
    }
    const evidence = new Set(required(item.evidenceIds, `supportChannels.${channel.id}.evidenceIds`));
    for (const evidenceId of channel.requiredEvidence) {
      if (!evidence.has(evidenceId)) throw new Error(`supportChannels.${channel.id}.evidenceIds missing ${evidenceId}`);
    }
    if (requirePass && item.result !== "PASS") throw new Error(`supportChannels.${channel.id}.result must be PASS`);
  }
  for (const [field, requiredValues] of [
    ["supportDryRunEvidence", gate.dryRunRequiredEvidence],
    ["dataCorrectionSteps", gate.dataCorrectionFlow.requiredSteps],
  ]) {
    const values = new Set(required(summary[field], field));
    for (const value of requiredValues) {
      if (!values.has(value)) throw new Error(`${field} missing ${value}`);
    }
  }
}

async function main() {
  const args = process.argv.slice(2);
  const summaryPath = argValue(args, "--summary");
  const requirePass = args.includes("--require-pass");
  if (!summaryPath) throw new Error("--summary is required");

  const [summary, observability, postLaunch, support] = await Promise.all([
    readJson(summaryPath),
    readJson(argValue(args, "--observability-gate", "apps/mobile/release/operations-observability-gate.json")),
    readJson(argValue(args, "--post-launch-gate", "apps/mobile/release/post-launch-operations-review-gate.json")),
    readJson(argValue(args, "--support-gate", "apps/mobile/release/support-incident-response-gate.json")),
  ]);
  if (summary.schemaVersion !== 1) throw new Error("schemaVersion must be 1");
  if (summary.releaseGate !== "operations-release-summary") throw new Error("releaseGate must be operations-release-summary");
  if (summary.issue !== 1019) throw new Error("issue must be 1019");
  if (!STATUS.has(summary.status)) throw new Error("status must be a release gate status");
  if (requirePass && summary.status !== "PASS") throw new Error("status must be PASS");
  if (requirePass && required(summary.externalBlockers, "externalBlockers").length > 0) {
    throw new Error("externalBlockers must be empty for --require-pass");
  }

  const artifactIdentity = assertIdentity(summary);
  const gates = { observability, postLaunch, support };
  assertNoSensitiveSummary(summary, gates);
  assertObservability(summary, observability, requirePass);
  assertPostLaunch(summary, postLaunch, artifactIdentity, requirePass);
  assertSupport(summary, support, requirePass);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
