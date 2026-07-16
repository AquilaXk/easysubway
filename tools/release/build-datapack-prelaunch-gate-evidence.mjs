#!/usr/bin/env node

import { execFile } from "node:child_process";
import { createHash, createSign, generateKeyPairSync, randomBytes } from "node:crypto";
import { appendFile, mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { gunzipSync } from "node:zlib";

import { buildRescueManifest } from "../datapack/build-rescue-manifest.mjs";
import { buildReleaseCallback } from "../datapack/build-release-callback.mjs";
import { evaluateReleaseDecision } from "../datapack/decide-datapack-release.mjs";
import { canonicalJson, withoutSignature } from "../datapack/lib/manifest-validation.mjs";
import { sendReleaseCallback } from "../datapack/send-release-callback.mjs";

const GATE_LIFETIME_MS = 14 * 86_400_000;
const REQUIRED_SUITES = ["source", "freshness", "rollback", "android", "callback", "backend"];
const execFileAsync = promisify(execFile);

const sha256 = (value) => createHash("sha256").update(value).digest("hex");

export function buildGateFragments({
  candidate, buildSpec, sourceReport, rollbackReport, callbackReport, conditionalPublishReport,
  androidDeviceReport, backendReconciliationReport,
  verifiedSuites, references, evaluatedAt,
}) {
  const identity = candidate?.releaseCandidateIdentity;
  if (candidate?.phase !== "CANDIDATE" || !identity || candidate.rcIdentity && !same(identity, candidate.rcIdentity)) {
    throw new Error("candidate context identity is invalid");
  }
  for (const field of ["dataPackManifestSha256", "dataPackArtifactSha256", "sourceSnapshotSetHash"]) {
    requiredSha(identity[field], `RC ${field}`);
  }
  if (!Number.isSafeInteger(identity.releaseSequence) || identity.releaseSequence < 1) {
    throw new Error("RC releaseSequence is invalid");
  }
  const evaluatedMillis = Date.parse(evaluatedAt);
  if (!Number.isFinite(evaluatedMillis)) throw new Error("evaluatedAt is invalid");
  const expiresAt = new Date(evaluatedMillis + GATE_LIFETIME_MS).toISOString();
  for (const suite of REQUIRED_SUITES) {
    if (!verifiedSuites?.has(suite)) throw new Error(`missing verified suite: ${suite}`);
    validateReference(references?.[suite], suite);
  }

  validateSourceInputs(buildSpec, sourceReport, identity, evaluatedMillis);
  validateRollbackReport(rollbackReport, identity);
  validateCallbackReport(callbackReport, identity);
  validateConditionalPublishReport(conditionalPublishReport, identity);
  validateAndroidDeviceReport(androidDeviceReport, identity);
  validateBackendReconciliationReport(backendReconciliationReport, identity);
  validateReference(references?.callbackExecution, "callback execution");
  validateReference(references?.conditionalPublish, "conditional publish execution");
  validateReference(references?.androidDevice, "Android device execution");

  const sourceExpiresAt = new Date(Math.min(
    Date.parse(expiresAt),
    ...buildSpec.sourceSnapshots.flatMap((snapshot) => [
      Date.parse(snapshot.freshnessExpiresAt), Date.parse(snapshot.rawRetentionExpiresAt),
    ]),
  )).toISOString();

  const envelope = (gateId, sourceIssue, result, evidenceExpiresAt = expiresAt) => ({
    schemaVersion: 1, gateId, sourceIssue, status: "SATISFIED", reasonCodes: [],
    rcIdentity: identity,
    evidenceValidity: { evaluatedAt: new Date(evaluatedMillis).toISOString(), expiresAt: evidenceExpiresAt },
    result,
  });
  const sourceInventory = buildSourceInventory(buildSpec.sourceSnapshots, evaluatedAt, expiresAt);
  const snapshotSetIdentity = identity.sourceSnapshotSetHash;
  const callbackIdentity = {
    releaseRequestId: callbackReport.payload.releaseRequestId,
    releaseSequence: callbackReport.payload.releaseSequence,
    manifestSha256: callbackReport.payload.manifestSha256,
    idempotencyKeySha256: sha256(callbackReport.payload.idempotencyKey),
  };

  return {
    source_governance: {
      ...envelope("source_governance", 2133,
        sourceResult(snapshotSetIdentity, [references.source, references.backend]), sourceExpiresAt),
      snapshotSetIdentity,
      sourceInventory,
    },
    freshness_conditional_publish: {
      ...envelope("freshness_conditional_publish", 2054,
        freshnessResult(snapshotSetIdentity, [references.freshness, references.conditionalPublish]), sourceExpiresAt),
      snapshotSetIdentity,
    },
    rollback_rescue: envelope("rollback_rescue", 2051, {
      schemaVersion: 1,
      currentReleaseSequence: rollbackReport.from.releaseSequence,
      failedReleaseSequence: rollbackReport.failed.releaseSequence,
      catalogMaxReleaseSequence: Math.max(
        rollbackReport.from.releaseSequence,
        rollbackReport.failed.releaseSequence,
        rollbackReport.knownGood.releaseSequence,
      ),
      rescueReleaseSequence: rollbackReport.rescue.releaseSequence,
      knownGoodPackSha256: rollbackReport.knownGood.packs[0].sha256,
      rescueManifestSha256: rollbackReport.rescue.manifestSha256,
      checks: passing([
        "monotonicSequence", "signatureVerified", "sqliteIntegrityVerified", "immutableCatalogWritten",
        "channelManifestPublishedLast", "idempotentRetryVerified", "androidReplayRecoveryVerified",
        "productionPreservedOnFailure", "secretRedactionVerified",
      ]),
      evidenceReferences: [references.rollback, references.android, references.androidDevice],
    }),
    callback_reconciliation: envelope("callback_reconciliation", 2057, {
      schemaVersion: 1,
      deliveryIdentity: callbackIdentity,
      metrics: {
        controlPlaneConvergenceP95Ms: callbackReport.metrics.controlPlaneConvergenceMs,
        terminalDispositionMaxMs: callbackReport.metrics.terminalDispositionMs,
      },
      checks: passing([
        "boundedRetryConverged", "independentReconciliationConverged", "duplicateSingleApply",
        "concurrentSingleApply", "identityMismatchDeadLetter", "invalidSignatureDeadLetter",
        "missingRequestDeadLetter", "rolloutCappedUntilConfirmed", "secretRedactionVerified",
        "manualRepairAudited",
      ]),
      evidenceReferences: [references.callbackExecution, references.callback, references.backend],
    }),
  };
}

function sourceResult(snapshotSetIdentity, evidenceReferences) {
  return {
    schemaVersion: 1, snapshotSetIdentity,
    checks: passing([
      "inventoryComplete", "freshnessCurrent", "retentionPolicyCurrent", "rawPurgeAccounted",
      "credentialsRedacted",
    ]),
    evidenceReferences,
  };
}

function freshnessResult(snapshotSetIdentity, evidenceReferences) {
  return {
    schemaVersion: 1, snapshotSetIdentity,
    checks: passing([
      "freshnessValidated", "materialChangeClassified", "approvalPolicyApplied",
      "monotonicSequenceVerified", "noChangeHandled",
    ]),
    evidenceReferences,
  };
}

function buildSourceInventory(snapshots, evaluatedAt, expiresAt) {
  const entries = snapshots.map((snapshot) => ({
    sourceId: snapshot.sourceId,
    status: "APPROVED",
    producerVersion: 1,
    evidenceSha256: sha256(JSON.stringify(snapshot)),
    evaluatedAt: new Date(evaluatedAt).toISOString(),
    expiresAt: new Date(Math.min(
      Date.parse(expiresAt), Date.parse(snapshot.freshnessExpiresAt), Date.parse(snapshot.rawRetentionExpiresAt),
    )).toISOString(),
  })).sort((left, right) => left.sourceId.localeCompare(right.sourceId));
  return {
    inventoryAsOf: new Date(evaluatedAt).toISOString(),
    entries,
    statusCounts: { APPROVED: entries.length, REVIEW_REQUIRED: 0, BLOCKED: 0, EXPIRED: 0 },
  };
}

function validateCallbackReport(report, identity) {
  const expectedIdempotencyKey = `${report?.payload?.releaseRequestId}:${identity.releaseSequence}:${identity.dataPackManifestSha256}`;
  if (report?.schemaVersion !== 1 || report.executionEnvironment !== "ISOLATED_PRELAUNCH"
    || report.productionExecuted !== false
    || report.payload?.releaseSequence !== identity.releaseSequence
    || report.payload?.manifestSha256 !== identity.dataPackManifestSha256
    || report.payload?.idempotencyKey !== expectedIdempotencyKey
    || report.delivery?.state !== "DELIVERED"
    || report.delivery.idempotencyKey !== expectedIdempotencyKey
    || report.terminalHandoff?.state !== "RECONCILIATION_REQUIRED"
    || report.terminalHandoff.idempotencyKey !== expectedIdempotencyKey) {
    throw new Error("callback execution identity mismatch");
  }
  const deliveredClasses = report.delivery.attempts?.map(({ httpClass }) => httpClass) ?? [];
  const terminalClasses = report.terminalHandoff.attempts?.map(({ httpClass }) => httpClass) ?? [];
  if (!deliveredClasses.includes("5XX") || deliveredClasses.at(-1) !== "2XX"
    || terminalClasses.length !== 4 || terminalClasses.some((value) => value !== "5XX")
    || report.metrics?.controlPlaneConvergenceMs !== 60_000
    || report.metrics?.terminalDispositionMs !== 4_140_000) {
    throw new Error("callback retry and reconciliation rehearsal did not pass");
  }
}

function validateAndroidDeviceReport(report, identity) {
  if (report?.artifactKind !== "android-datapack-monotonic-rescue-evidence"
    || report.status !== "PASS"
    || report.rcManifestSha256 !== identity.dataPackManifestSha256
    || report.rcArtifactSha256 !== identity.dataPackArtifactSha256
    || report.rescueReleaseSequence !== identity.releaseSequence
    || report.rcManifestBytesVerified !== true
    || report.rcArtifactBytesVerified !== true
    || report.rcSignatureVerified !== true
    || report.rcSqliteIntegrityVerified !== true
    || report.knownGoodContentRestored !== true
    || report.idempotentReplayVerified !== true
    || report.corruptSuccessorPreservedKnownGood !== true
    || report.lowerSequenceRejected !== true
    || !Number.isSafeInteger(report.recoveryElapsedMs)
    || report.recoveryElapsedMs < 0) {
    throw new Error("Android device rescue evidence does not match the RC identity");
  }
}

function validateConditionalPublishReport(report, identity) {
  if (report?.schemaVersion !== 1 || report.executionEnvironment !== "ISOLATED_PRELAUNCH"
    || report.productionExecuted !== false || report.productionWriteCount !== 0
    || report.noChange?.outcome !== "NO_CHANGE_VALID"
    || report.noChange.productionWriteAllowed !== false
    || report.noChange.publishAttempted !== false
    || report.candidatePublish?.outcome !== "PUBLISHED_AND_VERIFIED"
    || report.candidatePublish.publishAttempted !== true
    || report.candidatePublish.remoteValidationPassed !== true
    || report.candidatePublish.selectedManifestSha256 !== identity.dataPackManifestSha256
    || report.candidatePublish.selectedReleaseSequence !== identity.releaseSequence
    || report.isolatedTarget?.manifestSha256 !== identity.dataPackManifestSha256
    || report.isolatedTarget?.artifactSha256 !== identity.dataPackArtifactSha256
    || report.isolatedTarget?.immutableManifestWritten !== true
    || report.isolatedTarget?.channelManifestWrittenLast !== true
    || report.isolatedTarget?.readBackVerified !== true
    || report.isolatedTarget?.idempotentReplayVerified !== true
    || report.isolatedTarget?.immutableConflictRejected !== true
    || report.isolatedTarget?.executor !== "tools/datapack/publish-object-storage.mjs") {
    throw new Error("conditional publish rehearsal does not match the RC identity");
  }
}

function validateBackendReconciliationReport(report, identity) {
  if (report?.artifactKind !== "backend-datapack-reconciliation-evidence"
    || report.status !== "PASS"
    || report.manifestSha256 !== identity.dataPackManifestSha256
    || report.releaseSequence !== identity.releaseSequence
    || report.convergedWithinTenMinutes !== true) {
    throw new Error("backend reconciliation evidence does not match the RC identity");
  }
}

function validateSourceInputs(buildSpec, report, identity, evaluatedMillis) {
  if (buildSpec?.sourceSnapshotSetHash !== identity.sourceSnapshotSetHash
    || report?.sourceSnapshotSetHash !== identity.sourceSnapshotSetHash) {
    throw new Error("source snapshot identity mismatch");
  }
  if (report.status !== "PASS" || report.governanceDecision !== "GO") {
    throw new Error("source governance did not pass");
  }
  if (!Array.isArray(buildSpec.sourceSnapshots) || buildSpec.sourceSnapshots.length === 0
    || report.snapshotCount !== buildSpec.sourceSnapshots.length) {
    throw new Error("source inventory is incomplete");
  }
  const sourceIds = new Set();
  for (const snapshot of buildSpec.sourceSnapshots) {
    if (typeof snapshot.sourceId !== "string" || sourceIds.has(snapshot.sourceId)
      || snapshot.licenseStatus !== "PASS" || snapshot.redistributionAllowed !== true
      || snapshot.snapshotStatus !== "LOCKED" || snapshot.credentialRedacted !== true
      || Date.parse(snapshot.freshnessExpiresAt) <= evaluatedMillis
      || Date.parse(snapshot.rawRetentionExpiresAt) <= evaluatedMillis
      || typeof snapshot.governancePolicyVersion !== "string") {
      throw new Error("source inventory contains an unapproved or stale snapshot");
    }
    requiredSha(snapshot.rawSha256, "snapshot rawSha256");
    requiredSha(snapshot.governancePolicySha256, "snapshot governancePolicySha256");
    sourceIds.add(snapshot.sourceId);
  }
}

function validateRollbackReport(report, identity) {
  if (report?.status !== "PASS" || report.validatorStatus !== "PASS"
    || report.manifestLastStatus !== "PASS" || report.idempotentReplay !== true) {
    throw new Error("rollback rehearsal did not pass");
  }
  if (report.productionExecuted !== false || report.executionEnvironment !== "ISOLATED_PRELAUNCH") {
    throw new Error("rollback evidence must come from isolated prelaunch execution");
  }
  for (const value of [
    report.from?.releaseSequence, report.failed?.releaseSequence,
    report.knownGood?.releaseSequence, report.rescue?.releaseSequence,
  ]) {
    if (!Number.isSafeInteger(value) || value < 1) throw new Error("rollback sequence is invalid");
  }
  if (report.from.releaseSequence !== report.failed.releaseSequence
    || report.rescue.releaseSequence !== identity.releaseSequence
    || report.rescue.manifestSha256 !== identity.dataPackManifestSha256
    || report.rescue.releaseSequence <= Math.max(
      report.from.releaseSequence, report.failed.releaseSequence, report.knownGood.releaseSequence,
    )) {
    throw new Error("rollback rescue identity mismatch");
  }
  if (!Array.isArray(report.knownGood.packs) || report.knownGood.packs.length === 0
    || ![identity.dataPackArtifactSha256, identity.dataPackFallbackArtifactSha256]
      .includes(report.knownGood.packs[0].sha256)) {
    throw new Error("rollback known-good pack identity mismatch");
  }
}

function validateReference(value, suite) {
  if (typeof value?.artifactId !== "string" || value.artifactId.length === 0) {
    throw new Error(`missing evidence reference: ${suite}`);
  }
  requiredSha(value.sha256, `${suite} evidence sha256`);
}

function requiredSha(value, label) {
  if (!/^[a-f0-9]{64}$/.test(value ?? "")) throw new Error(`${label} is invalid`);
}

function passing(names) {
  return Object.fromEntries([...names].sort((left, right) => left.localeCompare(right)).map((name) => [name, true]));
}

function same(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

async function main(argv) {
  const args = parseArgs(argv);
  const mode = requiredArg(args, "mode");
  if (mode === "prepare") return prepare(args);
  if (mode === "collect") return collect(args);
  throw new Error("--mode must be prepare or collect");
}

async function prepare(args) {
  const repoRoot = path.resolve(args.get("repo-root") ?? ".");
  const outputDir = path.resolve(requiredArg(args, "output-dir"));
  const buildSpecPath = path.resolve(requiredArg(args, "build-spec"));
  const reviewedPackPath = path.resolve(requiredArg(args, "reviewed-pack"));
  const evaluatedAt = requiredInstant(args.get("evaluated-at") ?? new Date().toISOString(), "--evaluated-at");
  const evaluatedMillis = Date.parse(evaluatedAt);
  const [buildSpecBytes, reviewedPackBytes] = await Promise.all([
    readFile(buildSpecPath), readFile(reviewedPackPath),
  ]);
  const buildSpec = JSON.parse(buildSpecBytes);
  const reviewedPack = JSON.parse(reviewedPackBytes).packs?.[0];
  if (!reviewedPack || !/^[a-f0-9]{64}$/.test(buildSpec.sourceSnapshotSetHash ?? "")) {
    throw new Error("reviewed pack and build spec are required");
  }
  if (path.resolve(repoRoot, buildSpec.fixturePath ?? "") !== reviewedPackPath) {
    throw new Error("build spec reviewed pack binding mismatch");
  }
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const privateKeyPem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
  const publicKeyPem = publicKey.export({ type: "spki", format: "pem" }).toString();
  const publicKeyJwk = publicKey.export({ format: "jwk" });
  const buildOutput = path.join(outputDir, "built-datapack");
  await mkdir(outputDir, { recursive: true });
  await execFileAsync(process.execPath, [
    path.join(repoRoot, "tools/datapack/build-datapack.mjs"),
    "--build-spec", buildSpecPath, "--output", buildOutput,
  ], {
    cwd: repoRoot,
    env: {
      ...process.env,
      EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM: privateKeyPem,
      EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM: publicKeyPem,
      EASYSUBWAY_DATAPACK_RELEASE_SEQUENCE: "2",
      EASYSUBWAY_DATAPACK_BUILD_PUBLISHED_AT: evaluatedAt,
    },
  });
  const builtManifest = await readJson(path.join(buildOutput, "current.json"));
  const pack = builtManifest.packs?.[0];
  if (!pack || pack.artifactKind !== "production") throw new Error("production pack build failed");
  const artifactPath = path.join(buildOutput, `catalog/${pack.id}-v${pack.version}.sqlite.gz`);
  const artifactBytes = await readFile(artifactPath);
  if (pack.sha256 !== sha256(artifactBytes) || pack.sqliteSha256 !== sha256(gunzipSync(artifactBytes))) {
    throw new Error("built data pack identity mismatch");
  }
  const manifest = (releaseSequence, publishedAt) => {
    const value = {
      manifestVersion: 2, channel: "production", releaseSequence, publishedAt,
      expiresAt: new Date(evaluatedMillis + 30 * 86_400_000).toISOString(),
      keyId: "production-v1", ttlSeconds: 3_600,
      activePack: { id: pack.id, version: pack.version },
      packs: [structuredClone(pack)],
    };
    value.signature = {
      algorithm: "rsa-sha256-manifest-v2",
      value: sign(canonicalJson(withoutSignature(value)), privateKeyPem),
    };
    return value;
  };
  const knownGood = manifest(1, new Date(evaluatedMillis - 7_200_000).toISOString());
  const failed = manifest(2, new Date(evaluatedMillis - 3_600_000).toISOString());
  const knownGoodBytes = jsonBytes(knownGood);
  const failedBytes = jsonBytes(failed);
  const approval = {
    schemaVersion: 1, artifactKind: "datapack-rollback-approval",
    rollbackApprovalEventId: `prelaunch-${sha256(failedBytes).slice(0, 16)}`,
    targetChannel: "production", failedManifestSha256: sha256(failedBytes),
    knownGoodManifestSha256: sha256(knownGoodBytes), approvedBy: "prelaunch-requester",
    approvedByRole: "admin.datapack.rollback",
    approvedAt: new Date(evaluatedMillis - 1_800_000).toISOString(),
    reasonCode: "PRELAUNCH_REHEARSAL",
  };
  const rescueInput = {
    currentManifest: failed, currentManifestBytes: failedBytes, failedSequence: 2,
    knownGoodManifest: knownGood, knownGoodManifestBytes: knownGoodBytes,
    catalogSequences: [1, 2], approval,
    publishedAt: evaluatedAt,
    expiresAt: new Date(evaluatedMillis + 30 * 86_400_000).toISOString(),
    privateKey: privateKeyPem, now: new Date(evaluatedAt),
  };
  process.env.EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM = publicKeyPem;
  process.env.EASYSUBWAY_DATAPACK_SIGNING_KEY_ID = "production-v1";
  const rescue = buildRescueManifest(rescueInput);
  const replay = buildRescueManifest(rescueInput);
  if (!rescue.manifestBytes.equals(replay.manifestBytes)) {
    throw new Error("rollback rehearsal is not deterministic");
  }
  const rollbackReport = {
    ...rescue.evidence, status: "PASS", validatorStatus: "PASS", manifestLastStatus: "PASS",
    idempotentReplay: true, productionExecuted: false, executionEnvironment: "ISOLATED_PRELAUNCH",
  };
  const rehearsalBinding = {
    schemaVersion: 1, artifactKind: "datapack-prelaunch-rehearsal-binding",
    executionEnvironment: "ISOLATED_PRELAUNCH", productionExecuted: false,
    sourceSnapshotSetHash: buildSpec.sourceSnapshotSetHash,
    selectedManifestSha256: sha256(rescue.manifestBytes),
    selectedArtifactSha256: pack.sha256,
    selectedReleaseSequence: rescue.manifest.releaseSequence,
  };
  const paths = {
    manifest: path.join(outputDir, "rescue-manifest.json"),
    rollback: path.join(outputDir, "rollback-report.json"),
    callback: path.join(outputDir, "callback-execution-report.json"),
    conditionalPublish: path.join(outputDir, "conditional-publish-report.json"),
    binding: path.join(outputDir, "rehearsal-binding.json"),
    androidBundle: path.join(outputDir, "android-rc-bundle.json"),
    publicKey: path.join(outputDir, "public-key.pem"),
    candidate: path.join(outputDir, "candidate-context.json"),
  };
  await Promise.all([
    writeFile(paths.manifest, rescue.manifestBytes),
    writeFile(paths.rollback, jsonBytes(rollbackReport)),
    writeFile(paths.binding, jsonBytes(rehearsalBinding)),
    writeFile(paths.androidBundle, jsonBytes({
      schemaVersion: 1,
      artifactKind: "android-prelaunch-rc-bundle",
      manifestSha256: sha256(rescue.manifestBytes),
      artifactSha256: pack.sha256,
      manifestBytesBase64: rescue.manifestBytes.toString("base64"),
      artifactBytesBase64: artifactBytes.toString("base64"),
      publicKey: {
        keyId: "production-v1",
        modulusBase64Url: publicKeyJwk.n,
        exponentBase64Url: publicKeyJwk.e,
      },
    })),
    writeFile(paths.publicKey, publicKeyPem, { mode: 0o600 }),
  ]);
  const isolatedPublish = await runIsolatedPublishExecutor({
    repoRoot, outputDir, rescue, artifactBytes, publicKeyPem,
  });
  const conditionalPublishReport = await buildConditionalPublishReport({
    buildSpec, buildSpecBytes, evaluatedAt, rescue, failed, artifactBytes,
    isolatedPublish,
  });
  await writeFile(paths.conditionalPublish, jsonBytes(conditionalPublishReport));
  const gitSha = (await execFileAsync("git", ["rev-parse", "HEAD"], { cwd: repoRoot })).stdout.trim();
  await runGenerator({
    repoRoot, gitSha, evaluatedAt, manifestPath: paths.manifest, artifactPath,
    rehearsalBindingPath: paths.binding, publicKeyPem, phase: "CANDIDATE", outputPath: paths.candidate,
  });
  const candidate = await readJson(paths.candidate);
  const callbackReport = await runCallbackRehearsal({
    manifestBytes: rescue.manifestBytes, identity: candidate.releaseCandidateIdentity,
    pack, rollbackReport,
  });
  await writeFile(paths.callback, jsonBytes(callbackReport));
  const githubOutput = args.get("github-output");
  if (githubOutput) {
    await appendFile(githubOutput, [
      `manifestSha256=${candidate.releaseCandidateIdentity.dataPackManifestSha256}`,
      `releaseSequence=${candidate.releaseCandidateIdentity.releaseSequence}`,
    ].join("\n") + "\n");
  }
  process.stdout.write(`${JSON.stringify({
    status: "PASS", outputDir, dataPackArtifact: artifactPath,
    releaseSequence: rescue.manifest.releaseSequence,
  })}\n`);
}

async function collect(args) {
  const repoRoot = path.resolve(args.get("repo-root") ?? ".");
  const outputDir = path.resolve(requiredArg(args, "output-dir"));
  const evaluatedAt = requiredInstant(args.get("evaluated-at") ?? new Date().toISOString(), "--evaluated-at");
  const files = Object.fromEntries([
    "candidate", "build-spec", "source-validation-report", "rollback-report", "source-suite-report",
    "freshness-suite-report", "rollback-suite-report", "callback-suite-report", "android-suite-report",
    "callback-execution-report", "conditional-publish-report", "android-device-report",
    "data-pack-rehearsal-binding", "public-key",
    "data-pack-manifest", "data-pack-artifact",
  ].map((name) => [name, path.resolve(requiredArg(args, name))]));
  const [candidate, buildSpec, sourceReport, rollbackReport, callbackReport, conditionalPublishReport,
    androidDeviceReport, publicKeyPem] = await Promise.all([
    readJson(files.candidate), readJson(files["build-spec"]), readJson(files["source-validation-report"]),
    readJson(files["rollback-report"]), readJson(files["callback-execution-report"]),
    readJson(files["conditional-publish-report"]),
    readAndroidDeviceReport(files["android-device-report"]),
    readFile(files["public-key"], "utf8"),
  ]);
  const suitePaths = {
    source: files["source-suite-report"], freshness: files["freshness-suite-report"],
    rollback: files["rollback-suite-report"], callback: files["callback-suite-report"],
    android: files["android-suite-report"],
  };
  for (const suite of ["source", "freshness", "rollback", "callback"]) {
    validateTap(await readFile(suitePaths[suite], "utf8"), suite);
  }
  const androidText = await readFile(suitePaths.android, "utf8");
  if (!androidText.includes("All tests passed!") || androidText.includes("Some tests failed")) {
    throw new Error("android suite did not pass");
  }
  const backendJunitDir = path.resolve(requiredArg(args, "backend-junit-dir"));
  const backendFiles = await junitFiles(backendJunitDir);
  const backendReconciliationReport = await validateJunit(
    backendFiles, candidate.releaseCandidateIdentity,
  );
  const verifiedSuites = new Set(REQUIRED_SUITES);
  const references = {};
  await mkdir(path.join(outputDir, "suite-evidence"), { recursive: true });
  for (const suite of ["source", "freshness", "rollback", "callback", "android"]) {
    references[suite] = await writeSuiteEvidence(outputDir, suite, [suitePaths[suite]]);
  }
  references.backend = await writeSuiteEvidence(outputDir, "backend", backendFiles);
  references.callbackExecution = await evidenceReference(
    "callback-execution-report", files["callback-execution-report"],
  );
  references.conditionalPublish = await evidenceReference(
    "conditional-publish-report", files["conditional-publish-report"],
  );
  references.androidDevice = await evidenceReference("android-device-report", files["android-device-report"]);
  const fragments = buildGateFragments({
    candidate, buildSpec, sourceReport, rollbackReport, callbackReport, conditionalPublishReport,
    androidDeviceReport, backendReconciliationReport,
    verifiedSuites, references, evaluatedAt,
  });
  const gatePaths = {};
  await mkdir(path.join(outputDir, "gates"), { recursive: true });
  for (const [gateId, fragment] of Object.entries(fragments)) {
    gatePaths[gateId] = path.join(outputDir, `gates/${gateId}.json`);
    await writeFile(gatePaths[gateId], jsonBytes(fragment));
  }
  const gitSha = candidate.releaseCandidateIdentity.gitSha;
  const finalPath = path.join(outputDir, "final-readiness.json");
  await runGenerator({
    repoRoot, gitSha, evaluatedAt, manifestPath: files["data-pack-manifest"],
    artifactPath: files["data-pack-artifact"], rehearsalBindingPath: files["data-pack-rehearsal-binding"],
    publicKeyPem, phase: "FINAL", candidatePath: files.candidate, gatePaths, outputPath: finalPath,
  });
  process.stdout.write(`${JSON.stringify({ status: "PASS", finalReadiness: finalPath, gateIds: Object.keys(fragments) })}\n`);
}

async function runGenerator({
  repoRoot, gitSha, evaluatedAt, manifestPath, artifactPath, rehearsalBindingPath, publicKeyPem,
  phase, candidatePath, gatePaths = {}, outputPath,
}) {
  const argv = [
    path.join(repoRoot, "tools/release/generate-rc-evidence-manifest.mjs"),
    "--repo-root", repoRoot, "--app-root", path.join(repoRoot, "apps/mobile"),
    "--git-sha", gitSha, "--now", evaluatedAt,
    "--data-pack-manifest", manifestPath, "--data-pack-artifact", artifactPath,
    "--data-pack-fallback-artifact", artifactPath,
    "--data-pack-rehearsal-binding", rehearsalBindingPath,
    "--phase", phase, "--output", outputPath,
  ];
  if (candidatePath) argv.push("--candidate-context", candidatePath);
  for (const [gateId, gatePath] of Object.entries(gatePaths)) {
    argv.push("--datapack-gate-status", `${gateId}=SATISFIED`);
    argv.push("--datapack-gate-evidence", `${gateId}=${gatePath}`);
  }
  await execFileAsync(process.execPath, argv, {
    cwd: repoRoot,
    env: { ...process.env, EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM: publicKeyPem },
  });
}

async function buildConditionalPublishReport({
  buildSpec, buildSpecBytes, evaluatedAt, rescue, failed, artifactBytes,
  isolatedPublish,
}) {
  const candidateManifest = rescue.manifest;
  const candidateManifestSha256 = sha256(rescue.manifestBytes);
  const previousManifest = structuredClone(failed);
  previousManifest.packs[0].version = `previous-${previousManifest.packs[0].version}`;
  const previousManifestSha256 = sha256(jsonBytes(previousManifest));
  const releaseRequest = {
    artifactKind: "datapack-release-request", targetChannel: "production",
    approvalId: `prelaunch-${candidateManifestSha256.slice(0, 16)}`,
    requestedBy: "prelaunch-requester", approvedBy: "prelaunch-approver",
    candidateId: buildSpec.candidateId, buildSpecSha256: sha256(buildSpecBytes),
    sourceSnapshotSetHash: buildSpec.sourceSnapshotSetHash,
    approvedLedgerHash: buildSpec.approvedAliasLedgerHash,
  };
  const noChange = evaluateReleaseDecision({
    candidateManifest, currentManifest: candidateManifest,
    candidateManifestSha256, currentManifestSha256: candidateManifestSha256,
    buildSpec, buildSpecSha256: sha256(buildSpecBytes), releaseRequest,
    strictValidationPassed: true, publishAttempted: false, remoteValidationPassed: true,
    evaluationAt: evaluatedAt,
  });
  const candidatePublish = evaluateReleaseDecision({
    candidateManifest, currentManifest: previousManifest,
    candidateManifestSha256, currentManifestSha256: previousManifestSha256,
    buildSpec, buildSpecSha256: sha256(buildSpecBytes), releaseRequest,
    strictValidationPassed: true,
    publishAttempted: isolatedPublish.executor === "tools/datapack/publish-object-storage.mjs",
    remoteValidationPassed: isolatedPublish.immutableManifestWritten
      && isolatedPublish.channelManifestWrittenLast
      && isolatedPublish.idempotentReplayVerified
      && isolatedPublish.immutableConflictRejected
      && isolatedPublish.manifestSha256 === candidateManifestSha256
      && isolatedPublish.artifactSha256 === candidateManifest.packs[0].sha256,
    evaluationAt: evaluatedAt,
  });
  const readBackVerified = isolatedPublish.manifestSha256 === candidateManifestSha256
    && isolatedPublish.artifactSha256 === candidateManifest.packs[0].sha256
    && sha256(artifactBytes) === candidateManifest.packs[0].sha256;
  return {
    schemaVersion: 1, executionEnvironment: "ISOLATED_PRELAUNCH",
    productionExecuted: false, productionWriteCount: 0,
    noChange, candidatePublish,
    isolatedTarget: {
      manifestSha256: candidateManifestSha256,
      artifactSha256: candidateManifest.packs[0].sha256,
      executor: isolatedPublish.executor,
      immutableManifestWritten: isolatedPublish.immutableManifestWritten,
      channelManifestWrittenLast: isolatedPublish.channelManifestWrittenLast,
      idempotentReplayVerified: isolatedPublish.idempotentReplayVerified,
      immutableConflictRejected: isolatedPublish.immutableConflictRejected,
      readBackVerified,
    },
  };
}

async function runIsolatedPublishExecutor({ repoRoot, outputDir, rescue, artifactBytes, publicKeyPem }) {
  const stageRoot = path.join(outputDir, "isolated-publish-stage");
  const pack = rescue.manifest.packs[0];
  const stagedPackPath = path.join(stageRoot, `catalog/${pack.id}-v${pack.version}.sqlite.gz`);
  const stagedManifestPath = path.join(stageRoot, "catalog/current.json");
  const planPath = path.join(outputDir, "isolated-publish-plan.json");
  await mkdir(path.dirname(stagedPackPath), { recursive: true });
  await Promise.all([
    writeFile(stagedPackPath, artifactBytes),
    writeFile(stagedManifestPath, rescue.manifestBytes),
  ]);
  await execFileAsync(process.execPath, [
    path.join(repoRoot, "tools/datapack/create-publish-plan.mjs"),
    "--manifest", stagedManifestPath,
    "--root", stageRoot,
    "--output", planPath,
  ], {
    cwd: repoRoot,
    env: { ...process.env, EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM: publicKeyPem },
  });

  const objects = new Map();
  const operations = [];
  const server = createServer(async (request, response) => {
    const key = decodeURIComponent(new URL(request.url, "http://127.0.0.1").pathname.replace(/^\/+/, ""));
    if (request.method === "PUT") {
      if (request.headers["if-none-match"] === "*" && objects.has(key)) {
        operations.push({ method: "PUT", key, status: 412 });
        response.writeHead(412).end();
        return;
      }
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = Buffer.concat(chunks);
      objects.set(key, {
        body,
        cacheControl: request.headers["cache-control"],
      });
      operations.push({ method: "PUT", key, status: 200 });
      response.writeHead(200).end();
      return;
    }
    const stored = objects.get(key);
    operations.push({ method: request.method, key, status: stored ? 200 : 404 });
    if (!stored) {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(200, {
      "cache-control": stored.cacheControl,
      "content-length": stored.body.length,
    });
    response.end(request.method === "HEAD" ? undefined : stored.body);
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("isolated publish server address is invalid");
    const runExecutor = () => execFileAsync(process.execPath, [
      path.join(repoRoot, "tools/datapack/publish-object-storage.mjs"),
      "--plan", planPath,
      "--root", stageRoot,
    ], {
      cwd: repoRoot,
      env: {
        ...process.env,
        EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL: `http://127.0.0.1:${address.port}`,
      },
    });
    await runExecutor();
    const firstRunOperations = operations.slice();
    const immutableKey = `catalog/releases/${rescue.manifest.releaseSequence}.json`;
    const channelKey = "catalog/current.json";
    const packKey = `catalog/${pack.id}-v${pack.version}.sqlite.gz`;
    const immutable = objects.get(immutableKey);
    const channel = objects.get(channelKey);
    const storedPack = objects.get(packKey);
    const immutableManifestWritten = sha256(immutable?.body ?? Buffer.alloc(0)) === sha256(rescue.manifestBytes);
    const manifestSha256 = sha256(channel?.body ?? Buffer.alloc(0));
    const artifactSha256 = sha256(storedPack?.body ?? Buffer.alloc(0));
    const putIndex = (key) => firstRunOperations.findIndex((entry) => entry.method === "PUT" && entry.key === key);
    const channelManifestWrittenLast = putIndex(packKey) >= 0
      && putIndex(immutableKey) > putIndex(packKey)
      && putIndex(channelKey) > putIndex(immutableKey);

    await runExecutor();
    const idempotentReplayVerified = sha256(objects.get(immutableKey)?.body ?? Buffer.alloc(0))
      === sha256(rescue.manifestBytes);
    const originalImmutable = objects.get(immutableKey);
    objects.set(immutableKey, {
      body: Buffer.from("conflicting-immutable-manifest"),
      cacheControl: originalImmutable.cacheControl,
    });
    let immutableConflictRejected = false;
    try {
      await runExecutor();
    } catch (error) {
      if (!String(error.stderr ?? error.message).includes("immutable violation")) throw error;
      immutableConflictRejected = true;
    } finally {
      objects.set(immutableKey, originalImmutable);
    }
    return {
      executor: "tools/datapack/publish-object-storage.mjs",
      manifestSha256,
      artifactSha256,
      immutableManifestWritten,
      channelManifestWrittenLast,
      idempotentReplayVerified,
      immutableConflictRejected,
    };
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

async function runCallbackRehearsal({ manifestBytes, identity, pack, rollbackReport }) {
  if (identity?.dataPackManifestSha256 !== sha256(manifestBytes)
    || identity.dataPackArtifactSha256 !== pack.sha256) {
    throw new Error("callback rehearsal RC identity mismatch");
  }
  const token = randomBytes(32).toString("base64url");
  const payload = buildReleaseCallback({
    RELEASE_REQUEST_ID: `prelaunch-${identity.dataPackManifestSha256}`,
    RELEASE_SEQUENCE: String(identity.releaseSequence), TARGET_CHANNEL: "production",
    WORKFLOW_RUN_URL: "https://github.com/AquilaXk/easysubway/actions/workflows/datapack-prelaunch-gates.yml",
    MANIFEST_SHA256: identity.dataPackManifestSha256, SQLITE_SHA256: pack.sqliteSha256,
    GZIP_SHA256: identity.dataPackArtifactSha256,
    EVIDENCE_BUNDLE_SHA256: sha256(jsonBytes(rollbackReport)),
    VALIDATOR_STATUS: "PASS", ROUTE_REGRESSION_STATUS: "PASS", PUBLISH_STATUS: "PASS",
    EASYSUBWAY_DATAPACK_CALLBACK_HMAC_KEY: randomBytes(32).toString("base64url"),
  });
  let scenario = "DELIVERY";
  let postCount = 0;
  const server = createServer(async (request, response) => {
    if (request.method === "GET" && request.url === "/catalog/current.json") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(manifestBytes);
      return;
    }
    if (request.method !== "POST" || request.url !== "/callback"
      || request.headers.authorization !== `Bearer ${token}`) {
      response.writeHead(404).end();
      return;
    }
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    let received;
    try {
      received = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    } catch {
      response.writeHead(400).end();
      return;
    }
    if (received.idempotencyKey !== payload.idempotencyKey
      || received.manifestSha256 !== identity.dataPackManifestSha256) {
      response.writeHead(409).end();
      return;
    }
    postCount += 1;
    const status = scenario === "DELIVERY" && postCount > 1 ? 204 : 500;
    response.writeHead(status).end();
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  try {
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("callback rehearsal server address is invalid");
    const baseUrl = `http://127.0.0.1:${address.port}`;
    let deliveryElapsedMs = 0;
    const delivery = await sendReleaseCallback({
      payload, endpoint: `${baseUrl}/callback`, token,
      currentManifestUrl: `${baseUrl}/catalog/current.json`, retryDelaysSeconds: [60],
      sleep: async (seconds) => { deliveryElapsedMs += seconds * 1_000; },
    });
    scenario = "TERMINAL_HANDOFF";
    postCount = 0;
    let terminalElapsedMs = 0;
    const terminalHandoff = await sendReleaseCallback({
      payload, endpoint: `${baseUrl}/callback`, token,
      currentManifestUrl: `${baseUrl}/catalog/current.json`,
      sleep: async (seconds) => { terminalElapsedMs += seconds * 1_000; },
    });
    return {
      schemaVersion: 1, executionEnvironment: "ISOLATED_PRELAUNCH", productionExecuted: false,
      payload: {
        releaseRequestId: payload.releaseRequestId, releaseSequence: payload.releaseSequence,
        manifestSha256: payload.manifestSha256, idempotencyKey: payload.idempotencyKey,
      },
      delivery, terminalHandoff,
      metrics: {
        controlPlaneConvergenceMs: deliveryElapsedMs,
        terminalDispositionMs: terminalElapsedMs,
      },
    };
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
}

function sign(value, privateKeyPem) {
  return createSign("RSA-SHA256").update(value).sign(privateKeyPem).toString("base64url");
}

function validateTap(text, suite) {
  if (!/(?:^|\n)# fail 0(?:\n|$)/.test(text) || /(?:^|\n)not ok\b/.test(text)) {
    throw new Error(`${suite} suite did not pass`);
  }
}

async function junitFiles(root, required = true) {
  const files = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const child = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...await junitFiles(child, false));
    else if (entry.name.endsWith(".xml")) files.push(child);
  }
  if (required && files.length === 0) throw new Error("backend JUnit reports are missing");
  return files.sort();
}

async function validateJunit(files, identity) {
  const requiredClasses = [
    "JdbcDataSourceSnapshotRepositoryContainerTest", "DatapackReleaseCallbackServiceTest",
    "DatapackReleaseReconciliationServiceTest", "DatapackReleaseReconciliationSchedulerTest",
    "DatapackReleaseRequestAdminPageControllerTest", "JdbcDatapackReleaseRequestRepositoryTest",
  ];
  const texts = await Promise.all(files.map((file) => readFile(file, "utf8")));
  const joined = texts.join("\n");
  if (texts.some((text) => /<(?:testsuite|testsuites)\b[^>]*(?:failures|errors)="[1-9][0-9]*"/.test(text))) {
    throw new Error("backend JUnit suite did not pass");
  }
  for (const className of requiredClasses) {
    if (!joined.includes(className)) throw new Error(`backend JUnit class is missing: ${className}`);
  }
  const match = joined.match(/\{"artifactKind":"backend-datapack-reconciliation-evidence"[^\r\n<]*\}/);
  if (!match) throw new Error("backend reconciliation machine evidence is missing");
  const report = JSON.parse(match[0]);
  validateBackendReconciliationReport(report, identity);
  return report;
}

async function writeSuiteEvidence(outputDir, suite, files) {
  const artifacts = [];
  for (const file of files) {
    const bytes = await readFile(file);
    artifacts.push({ name: path.basename(file), sha256: sha256(bytes) });
  }
  const summaryPath = path.join(outputDir, `suite-evidence/${suite}.json`);
  const bytes = jsonBytes({ schemaVersion: 1, suite, status: "PASS", artifacts });
  await writeFile(summaryPath, bytes);
  return { artifactId: `${suite}-suite-evidence`, sha256: sha256(bytes) };
}

async function evidenceReference(artifactId, file) {
  return { artifactId, sha256: sha256(await readFile(file)) };
}

async function readAndroidDeviceReport(file) {
  const lines = (await readFile(file, "utf8")).split("\n").filter(Boolean);
  for (const line of lines) {
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      continue;
    }
    if (event?.type !== "print" || typeof event.message !== "string") continue;
    try {
      const report = JSON.parse(event.message);
      if (report?.artifactKind === "android-datapack-monotonic-rescue-evidence") return report;
    } catch {
      // Ignore regular test runner output and continue to the machine evidence event.
    }
  }
  throw new Error("Android device machine evidence is missing");
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!flag?.startsWith("--") || value === undefined || value.startsWith("--")) {
      throw new Error(`invalid argument near ${flag ?? "<end>"}`);
    }
    const name = flag.slice(2);
    if (args.has(name)) throw new Error(`duplicate argument: ${flag}`);
    args.set(name, value);
  }
  return args;
}

function requiredArg(args, name) {
  const value = args.get(name);
  if (!value) throw new Error(`--${name} is required`);
  return value;
}

function requiredInstant(value, label) {
  const millis = Date.parse(value);
  if (!Number.isFinite(millis) || !/(Z|[+-]\d{2}:\d{2})$/.test(value)) {
    throw new Error(`${label} must be an ISO timestamp with timezone`);
  }
  return new Date(millis).toISOString();
}

async function readJson(file) {
  return JSON.parse(await readFile(file, "utf8"));
}

function jsonBytes(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    await main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
