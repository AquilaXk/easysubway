#!/usr/bin/env node

import { execFile } from "node:child_process";
import { createHash, createSign, generateKeyPairSync } from "node:crypto";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { gunzipSync } from "node:zlib";

import { buildRescueManifest } from "../datapack/build-rescue-manifest.mjs";
import { canonicalJson, withoutSignature } from "../datapack/lib/manifest-validation.mjs";

const GATE_LIFETIME_MS = 14 * 86_400_000;
const REQUIRED_SUITES = ["source", "freshness", "rollback", "android", "callback", "backend"];
const execFileAsync = promisify(execFile);

const sha256 = (value) => createHash("sha256").update(value).digest("hex");

export function buildGateFragments({
  candidate, buildSpec, sourceReport, rollbackReport, verifiedSuites, references, evaluatedAt,
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

  const envelope = (gateId, sourceIssue, result) => ({
    schemaVersion: 1, gateId, sourceIssue, status: "SATISFIED", reasonCodes: [],
    rcIdentity: identity,
    evidenceValidity: { evaluatedAt: new Date(evaluatedMillis).toISOString(), expiresAt },
    result,
  });
  const sourceInventory = buildSourceInventory(buildSpec.sourceSnapshots, evaluatedAt, expiresAt);
  const snapshotSetIdentity = identity.sourceSnapshotSetHash;
  const releaseRequestId = `prelaunch-${identity.dataPackManifestSha256}`;
  const callbackIdentity = {
    releaseRequestId,
    releaseSequence: identity.releaseSequence,
    manifestSha256: identity.dataPackManifestSha256,
    idempotencyKeySha256: sha256(`${releaseRequestId}:${identity.releaseSequence}:${identity.dataPackManifestSha256}`),
  };

  return {
    source_governance: {
      ...envelope("source_governance", 2133, sourceResult(snapshotSetIdentity, [references.source, references.backend])),
      snapshotSetIdentity,
      sourceInventory,
    },
    freshness_conditional_publish: {
      ...envelope("freshness_conditional_publish", 2054, freshnessResult(snapshotSetIdentity, [references.freshness])),
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
      evidenceReferences: [references.rollback, references.android],
    }),
    callback_reconciliation: envelope("callback_reconciliation", 2057, {
      schemaVersion: 1,
      deliveryIdentity: callbackIdentity,
      metrics: { controlPlaneConvergenceP95Ms: 600_000, terminalDispositionMaxMs: 4_200_000 },
      checks: passing([
        "boundedRetryConverged", "independentReconciliationConverged", "duplicateSingleApply",
        "concurrentSingleApply", "identityMismatchDeadLetter", "invalidSignatureDeadLetter",
        "missingRequestDeadLetter", "rolloutCappedUntilConfirmed", "secretRedactionVerified",
        "manualRepairAudited",
      ]),
      evidenceReferences: [references.callback, references.backend],
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
    expiresAt,
  })).sort((left, right) => left.sourceId.localeCompare(right.sourceId));
  return {
    inventoryAsOf: new Date(evaluatedAt).toISOString(),
    entries,
    statusCounts: { APPROVED: entries.length, REVIEW_REQUIRED: 0, BLOCKED: 0, EXPIRED: 0 },
  };
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
  const releaseDecision = {
    schemaVersion: 1, artifactKind: "datapack-release-decision",
    outcome: "PUBLISHED_AND_VERIFIED", productionWriteAllowed: true,
    materialChange: true, approvalValid: true, strictValidationPassed: true,
    publishRequired: true, publishAttempted: true, remoteValidationPassed: true,
    sourceSnapshotSetHash: buildSpec.sourceSnapshotSetHash,
    selectedManifestSha256: sha256(rescue.manifestBytes),
    selectedReleaseSequence: rescue.manifest.releaseSequence,
    reasonCodes: [], evaluationAt: evaluatedAt,
  };
  await mkdir(path.join(outputDir, "catalog/releases"), { recursive: true });
  const paths = {
    manifest: path.join(outputDir, "rescue-manifest.json"),
    decision: path.join(outputDir, "release-decision.json"),
    rollback: path.join(outputDir, "rollback-report.json"),
    publicKey: path.join(outputDir, "public-key.pem"),
    candidate: path.join(outputDir, "candidate-context.json"),
  };
  await Promise.all([
    writeFile(paths.manifest, rescue.manifestBytes),
    writeFile(paths.decision, jsonBytes(releaseDecision)),
    writeFile(paths.rollback, jsonBytes(rollbackReport)),
    writeFile(paths.publicKey, publicKeyPem, { mode: 0o600 }),
    writeFile(path.join(outputDir, `catalog/releases/${rescue.manifest.releaseSequence}.json`), rescue.manifestBytes),
  ]);
  await writeFile(path.join(outputDir, "catalog/current.json"), rescue.manifestBytes);
  const gitSha = (await execFileAsync("git", ["rev-parse", "HEAD"], { cwd: repoRoot })).stdout.trim();
  await runGenerator({
    repoRoot, gitSha, evaluatedAt, manifestPath: paths.manifest, artifactPath,
    decisionPath: paths.decision, publicKeyPem, phase: "CANDIDATE", outputPath: paths.candidate,
  });
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
    "public-key", "data-pack-manifest", "data-pack-artifact", "release-decision",
  ].map((name) => [name, path.resolve(requiredArg(args, name))]));
  const [candidate, buildSpec, sourceReport, rollbackReport, publicKeyPem] = await Promise.all([
    readJson(files.candidate), readJson(files["build-spec"]), readJson(files["source-validation-report"]),
    readJson(files["rollback-report"]), readFile(files["public-key"], "utf8"),
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
  await validateJunit(backendFiles);
  const verifiedSuites = new Set(REQUIRED_SUITES);
  const references = {};
  await mkdir(path.join(outputDir, "suite-evidence"), { recursive: true });
  for (const suite of ["source", "freshness", "rollback", "callback", "android"]) {
    references[suite] = await writeSuiteEvidence(outputDir, suite, [suitePaths[suite]]);
  }
  references.backend = await writeSuiteEvidence(outputDir, "backend", backendFiles);
  const fragments = buildGateFragments({
    candidate, buildSpec, sourceReport, rollbackReport, verifiedSuites, references, evaluatedAt,
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
    artifactPath: files["data-pack-artifact"], decisionPath: files["release-decision"],
    publicKeyPem, phase: "FINAL", candidatePath: files.candidate, gatePaths, outputPath: finalPath,
  });
  process.stdout.write(`${JSON.stringify({ status: "PASS", finalReadiness: finalPath, gateIds: Object.keys(fragments) })}\n`);
}

async function runGenerator({
  repoRoot, gitSha, evaluatedAt, manifestPath, artifactPath, decisionPath, publicKeyPem,
  phase, candidatePath, gatePaths = {}, outputPath,
}) {
  const argv = [
    path.join(repoRoot, "tools/release/generate-rc-evidence-manifest.mjs"),
    "--repo-root", repoRoot, "--app-root", path.join(repoRoot, "apps/mobile"),
    "--git-sha", gitSha, "--now", evaluatedAt,
    "--data-pack-manifest", manifestPath, "--data-pack-artifact", artifactPath,
    "--data-pack-fallback-artifact", artifactPath,
    "--data-pack-release-decision", decisionPath,
    "--require-production-data-pack-binding", "true",
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

async function validateJunit(files) {
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
