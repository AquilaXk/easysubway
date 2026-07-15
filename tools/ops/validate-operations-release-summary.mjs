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

function isRfc3339Timestamp(value) {
  const match = typeof value === "string" && value.match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$/,
  );
  if (!match || !Number.isFinite(Date.parse(value))) return false;
  const [
    , yearText, monthText, dayText, hourText, minuteText, secondText,
    offsetHourText = "0", offsetMinuteText = "0",
  ] = match;
  const [year, month, day, hour, minute, second, offsetHour, offsetMinute] = [
    yearText, monthText, dayText, hourText, minuteText, secondText, offsetHourText, offsetMinuteText,
  ].map(Number);
  return year > 0
    && month >= 1 && month <= 12
    && day >= 1 && day <= new Date(Date.UTC(year, month, 0)).getUTCDate()
    && hour <= 23 && minute <= 59 && second <= 59
    && offsetHour <= 23 && offsetMinute <= 59;
}

function durationMillis(value) {
  const hours = /^PT(\d+)H$/.exec(value);
  if (hours) return Number(hours[1]) * 60 * 60 * 1000;
  const days = /^P(\d+)D$/.exec(value);
  if (days) return Number(days[1]) * 24 * 60 * 60 * 1000;
  throw new Error(`unsupported review window duration: ${value}`);
}

function assertRcManifestIdentity(artifactIdentity, rcManifest, gate) {
  const rcIdentity = required(rcManifest.rcIdentity, "rcManifest.rcIdentity");
  if (
    String(artifactIdentity.versionName) !== String(rcIdentity.appVersionName)
    || artifactIdentity.androidApplicationId !== rcManifest.androidApplicationId
    || artifactIdentity.androidApplicationId !== gate.androidApplicationId
  ) {
    throw new Error("artifactIdentity must match the RC manifest identity");
  }
  for (const field of gate.preLaunchReadiness.finalRcBinding.requiredFields) {
    if (String(artifactIdentity[field]) !== String(rcIdentity[field])) {
      throw new Error("artifactIdentity must match the RC manifest identity");
    }
  }
  const backendFields = gate.preLaunchReadiness.finalRcBinding.backendIdentityFieldsAnyOf;
  if (!backendFields.some((field) => (
    artifactIdentity[field] !== undefined
    && artifactIdentity[field] !== null
    && artifactIdentity[field] === rcIdentity[field]
  ))) {
    throw new Error("artifactIdentity must match the RC manifest identity");
  }
}

function assertEvidenceValidity(summary, gate, artifactIdentity, requirePass, now) {
  const validity = required(summary.evidenceValidity, "evidenceValidity");
  const expectedTestedAt = `${gate.preLaunchReadiness.evidenceDateKst}T00:00:00+09:00`;
  const expectedExpiresWhen = `${gate.preLaunchReadiness.finalRcBinding.evidenceValidity.validUntilKst}T23:59:59.999+09:00`;
  if (validity.testedAt !== expectedTestedAt || validity.expiresWhen !== expectedExpiresWhen) {
    throw new Error("evidenceValidity must match the canonical Phase A evidence window");
  }
  if (
    requirePass
    && (!Number.isFinite(now) || now < Date.parse(validity.testedAt) || now > Date.parse(validity.expiresWhen))
  ) {
    throw new Error("evidenceValidity must be current for --require-pass");
  }
  if (requirePass && (
    String(artifactIdentity.versionName) !== String(gate.preLaunchReadiness.finalRcBinding.evidenceValidity.appVersionName)
    || String(artifactIdentity.versionCode) !== String(gate.preLaunchReadiness.finalRcBinding.evidenceValidity.versionCode)
  )) {
    throw new Error("artifactIdentity must match the canonical Phase A evidence scope");
  }
}

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

function assertIdentity(
  summary,
  path = "artifactIdentity",
  backendIdentityFieldsAnyOf = ["backendImageDigest", "backendArtifactSha256"],
) {
  const identity = required(summary.artifactIdentity, path);
  for (const field of [
    "gitSha",
    "versionName",
    "versionCode",
    "androidApplicationId",
    "aabSha256",
    "dataPackManifestSha256",
  ]) {
    required(identity[field], `${path}.${field}`);
  }
  if (!backendIdentityFieldsAnyOf.some((field) => identity[field] !== undefined && identity[field] !== null)) {
    throw new Error(`${path} must include one of ${backendIdentityFieldsAnyOf.join(", ")}`);
  }
  return identity;
}

function assertObservability(summary, gate, requirePass) {
  const allowedKinds = new Set(gate.signalEvidencePolicy.allowedResolutionKinds);
  const byId = new Map(required(summary.observabilitySignals, "observabilitySignals").map((item) => [item.signalId, item]));
  const validatedById = new Map(
    required(gate.phaseAValidatedEvidence, "gate.phaseAValidatedEvidence").map((item) => [item.signalId, item]),
  );
  for (const signal of gate.signals) {
    const item = required(byId.get(signal.id), `observabilitySignals.${signal.id}`);
    const validated = required(validatedById.get(signal.id), `gate.phaseAValidatedEvidence.${signal.id}`);
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
    if (
      item.resolutionKind !== validated.resolutionKind
      || item.result !== validated.result
      || item.localEvidencePath !== validated.localEvidencePath
      || stableFlatJson([...evidence].sort()) !== stableFlatJson([...validated.evidenceIds].sort())
    ) {
      throw new Error(`observabilitySignals.${signal.id} must match validated Phase A evidence`);
    }
    if (requirePass && item.result !== "PASS") {
      throw new Error(`observabilitySignals.${signal.id}.result must be PASS`);
    }
  }
}

function assertPostLaunch(summary, gate, artifactIdentity, requirePass) {
  const preLaunch = required(summary.preLaunchReadiness, "preLaunchReadiness");
  if (!STATUS.has(preLaunch.status)) {
    throw new Error("preLaunchReadiness.status must be a release gate status");
  }
  if (preLaunch.status !== required(gate.preLaunchReadiness.status, "gate.preLaunchReadiness.status")) {
    throw new Error("preLaunchReadiness.status must match the current gate state");
  }
  if ((requirePass || summary.status === "PASS") && preLaunch.status !== "PASS") {
    throw new Error("preLaunchReadiness.status must be PASS");
  }
  const preLaunchEvidence = new Set(required(preLaunch.evidenceIds, "preLaunchReadiness.evidenceIds"));
  if (preLaunch.status === "PASS") {
    for (const evidenceId of gate.preLaunchReadiness.requiredEvidence) {
      if (!preLaunchEvidence.has(evidenceId)) {
        throw new Error(`preLaunchReadiness.evidenceIds missing ${evidenceId}`);
      }
    }
  }

  const observation = required(summary.postLaunchObservation, "postLaunchObservation");
  if (!new Set(["PENDING_PUBLIC_RELEASE", "IN_PROGRESS", "PASS"]).has(observation.status)) {
    throw new Error("postLaunchObservation.status must be a post-launch state");
  }
  const gateObservation = required(gate.postLaunchObservation, "gate.postLaunchObservation");
  const transition = `${gateObservation.status}->${observation.status}`;
  if (
    observation.status !== gateObservation.status
    && !required(gateObservation.allowedStatusTransitions, "gate.postLaunchObservation.allowedStatusTransitions")
      .includes(transition)
  ) {
    throw new Error("postLaunchObservation.status must follow an allowed transition from the current gate state");
  }
  if (observation.status === "PENDING_PUBLIC_RELEASE") {
    const identity = required(observation.publicReleaseIdentity, "postLaunchObservation.publicReleaseIdentity");
    if (identity.publishedAt !== null || identity.versionCode !== null || identity.gitSha !== null) {
      throw new Error("PENDING_PUBLIC_RELEASE must not contain a public release identity");
    }
    if ((summary.postLaunchReviews ?? []).length > 0) {
      throw new Error("PENDING_PUBLIC_RELEASE must not contain post-launch observations");
    }
  } else {
    const publicReleaseIdentity = required(
      observation.publicReleaseIdentity,
      "postLaunchObservation.publicReleaseIdentity",
    );
    if (!isRfc3339Timestamp(publicReleaseIdentity.publishedAt)) {
      throw new Error("postLaunchObservation.publicReleaseIdentity.publishedAt must be an RFC 3339 timestamp");
    }
    if (Date.parse(publicReleaseIdentity.publishedAt) > Date.now()) {
      throw new Error("postLaunchObservation.publicReleaseIdentity.publishedAt must not be in the future");
    }
    required(publicReleaseIdentity.versionCode, "postLaunchObservation.publicReleaseIdentity.versionCode");
    required(publicReleaseIdentity.gitSha, "postLaunchObservation.publicReleaseIdentity.gitSha");
    if (
      String(publicReleaseIdentity.versionCode) !== String(artifactIdentity.versionCode)
      || publicReleaseIdentity.gitSha !== artifactIdentity.gitSha
    ) {
      throw new Error("public release identity must match artifactIdentity");
    }
    if (
      gateObservation.status !== "PENDING_PUBLIC_RELEASE"
      && stableFlatJson(publicReleaseIdentity) !== stableFlatJson(gateObservation.publicReleaseIdentity)
    ) {
      throw new Error("public release identity must match the current gate state");
    }
    const reviews = required(summary.postLaunchReviews, "postLaunchReviews");
    const byId = new Map(reviews.map((item) => [item.reviewWindowId, item]));
    if (byId.size !== reviews.length) throw new Error("postLaunchReviews must not contain duplicate review windows");
    if (
      observation.status === "IN_PROGRESS"
      && reviews.some((item, index) => item.reviewWindowId !== gate.reviewWindows[index]?.id)
    ) {
      throw new Error("IN_PROGRESS postLaunchReviews must be a chronological prefix of reviewWindows");
    }
    const windows = observation.status === "PASS"
      ? gate.reviewWindows
      : reviews.map((item) => required(
        gate.reviewWindows.find((window) => window.id === item.reviewWindowId),
        `reviewWindows.${item.reviewWindowId}`,
      ));
    for (const window of windows) {
      const item = required(byId.get(window.id), `postLaunchReviews.${window.id}`);
      if (!isRfc3339Timestamp(item.observedAt)) {
        throw new Error(`postLaunchReviews.${window.id}.observedAt must be an RFC 3339 timestamp`);
      }
      if (Date.parse(item.observedAt) > Date.now()) {
        throw new Error(`postLaunchReviews.${window.id}.observedAt must not be in the future`);
      }
      const dueAt = Date.parse(publicReleaseIdentity.publishedAt) + durationMillis(window.afterPublicRelease);
      if (Date.parse(item.observedAt) < dueAt) {
        throw new Error(`postLaunchReviews.${window.id}.observedAt must be at or after its due time`);
      }
      assertIdentity(
        item,
        `postLaunchReviews.${window.id}.artifactIdentity`,
        gate.preLaunchReadiness.finalRcBinding.backendIdentityFieldsAnyOf,
      );
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
      if ((requirePass || observation.status === "PASS") && item.goNoGoResult !== "PASS") {
        throw new Error(`postLaunchReviews.${window.id}.goNoGoResult must be PASS`);
      }
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
  if (requirePass && (
    required(gate.status, "gate.status") !== "PASS"
    || required(gate.preLaunchReadiness, "gate.preLaunchReadiness").status !== "PASS"
    || required(
      gate.latestQaEvidenceSummary.remainingSupportReadiness,
      "gate.latestQaEvidenceSummary.remainingSupportReadiness",
    ).length > 0
    || required(
      gate.latestQaEvidenceSummary.helpScreenDeviceQa,
      "gate.latestQaEvidenceSummary.helpScreenDeviceQa",
    ).result !== "PASS"
    || required(
      gate.latestQaEvidenceSummary.operatorContactReadiness,
      "gate.latestQaEvidenceSummary.operatorContactReadiness",
    ).result !== "PASS"
  )) {
    throw new Error("canonical support readiness must be PASS for --require-pass");
  }
  const byId = new Map(required(summary.supportChannels, "supportChannels").map((item) => [item.channelId, item]));
  const validatedById = new Map(
    required(gate.latestQaEvidenceSummary.channelEvidence, "gate.latestQaEvidenceSummary.channelEvidence")
      .map((item) => [item.channelId, item]),
  );
  for (const channel of gate.supportChannels) {
    const item = required(byId.get(channel.id), `supportChannels.${channel.id}`);
    const validated = required(validatedById.get(channel.id), `gate.latestQaEvidenceSummary.channelEvidence.${channel.id}`);
    for (const field of gate.supportEvidenceSummaryPolicy.githubSummaryFields) {
      required(item[field], `supportChannels.${channel.id}.${field}`);
    }
    const evidence = new Set(required(item.evidenceIds, `supportChannels.${channel.id}.evidenceIds`));
    for (const evidenceId of channel.requiredEvidence) {
      if (!evidence.has(evidenceId)) throw new Error(`supportChannels.${channel.id}.evidenceIds missing ${evidenceId}`);
    }
    if (
      item.result !== validated.result
      || item.redactedReceiptReference !== validated.redactedReceiptReference
      || item.receivedAt !== validated.receivedAt
      || item.localEvidencePath !== validated.localEvidencePath
      || stableFlatJson([...evidence].sort()) !== stableFlatJson([...validated.evidenceIds].sort())
    ) {
      throw new Error(`supportChannels.${channel.id} must match validated Phase A evidence`);
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
  const contactRoutes = new Map(
    required(summary.operatorContactRoutes, "operatorContactRoutes").map((item) => [item.routeId, item]),
  );
  for (const route of gate.operatorContactRoutes) {
    const item = required(contactRoutes.get(route.id), `operatorContactRoutes.${route.id}`);
    required(item.localEvidencePath, `operatorContactRoutes.${route.id}.localEvidencePath`);
    const evidence = new Set(required(item.evidenceIds, `operatorContactRoutes.${route.id}.evidenceIds`));
    for (const evidenceId of route.requiredEvidence) {
      if (!evidence.has(evidenceId)) {
        throw new Error(`operatorContactRoutes.${route.id}.evidenceIds missing ${evidenceId}`);
      }
    }
    if (requirePass && item.result !== "PASS") {
      throw new Error(`operatorContactRoutes.${route.id}.result must be PASS`);
    }
  }
}

async function main() {
  const args = process.argv.slice(2);
  const summaryPath = argValue(args, "--summary");
  const requirePass = args.includes("--require-pass");
  const nowArg = argValue(args, "--now");
  const now = nowArg === undefined ? Date.now() : Date.parse(nowArg);
  const rcManifestPath = argValue(args, "--rc-manifest", process.env.EASYSUBWAY_OPERATIONS_RC_MANIFEST);
  if (!summaryPath) throw new Error("--summary is required");
  if (requirePass && !rcManifestPath) throw new Error("--rc-manifest is required for --require-pass");

  const [summary, observability, postLaunch, support, rcManifest] = await Promise.all([
    readJson(summaryPath),
    readJson(argValue(args, "--observability-gate", "apps/mobile/release/operations-observability-gate.json")),
    readJson(argValue(args, "--post-launch-gate", "apps/mobile/release/post-launch-operations-review-gate.json")),
    readJson(argValue(args, "--support-gate", "apps/mobile/release/support-incident-response-gate.json")),
    rcManifestPath ? readJson(rcManifestPath) : null,
  ]);
  if (summary.schemaVersion !== 1) throw new Error("schemaVersion must be 1");
  if (summary.releaseGate !== "operations-release-summary") throw new Error("releaseGate must be operations-release-summary");
  if (summary.issue !== 1019) throw new Error("issue must be 1019");
  if (!STATUS.has(summary.status)) throw new Error("status must be a release gate status");
  if (requirePass && summary.status !== "PASS") throw new Error("status must be PASS");
  if (requirePass && required(summary.externalBlockers, "externalBlockers").length > 0) {
    throw new Error("externalBlockers must be empty for --require-pass");
  }

  const artifactIdentity = assertIdentity(
    summary,
    "artifactIdentity",
    postLaunch.preLaunchReadiness.finalRcBinding.backendIdentityFieldsAnyOf,
  );
  assertEvidenceValidity(summary, postLaunch, artifactIdentity, requirePass, now);
  if (rcManifest) assertRcManifestIdentity(artifactIdentity, rcManifest, postLaunch);
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
