import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const validPhaseANow = "2026-07-16T00:00:00.000Z";

function rcManifest(overrides = {}) {
  return {
    schemaVersion: 1,
    releaseGate: "rc-evidence-manifest",
    androidApplicationId: "com.easysubway.app",
    rcIdentity: {
      gitSha: "abcdef1234567890",
      appVersionName: "1.0.4",
      versionCode: "10005",
      aabSha256: "a".repeat(64),
      backendImageDigest: `sha256:${"b".repeat(64)}`,
      backendArtifactSha256: null,
      dataPackManifestSha256: "c".repeat(64),
      supportContactSetSha256: "e361e4d770796fc6dc2ade2eb560b2e6885917c027a67661b3644ea8ff30044a",
      ...overrides,
    },
  };
}

async function paths() {
  const dir = await mkdtemp(path.join(tmpdir(), "operations-phase-a-"));
  return {
    dir,
    manifest: path.join(dir, "rc-evidence-manifest.json"),
    summary: path.join(dir, "operations-phase-a-summary.json"),
    status: path.join(dir, "operations-phase-a-status.txt"),
  };
}

async function generate(output, extraArgs = []) {
  const timeArgs = extraArgs.includes("--now") ? [] : ["--now", validPhaseANow];
  await execFileAsync(process.execPath, [
    "tools/ops/generate-operations-phase-a-summary.mjs",
    "--rc-manifest",
    output.manifest,
    "--summary",
    output.summary,
    "--status-output",
    output.status,
    ...timeArgs,
    ...extraArgs,
  ], { cwd: root });
}

test("Phase A summary generator binds a complete RC and validator accepts it", async () => {
  const output = await paths();
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);

  await generate(output);

  assert.equal((await readFile(output.status, "utf8")).trim(), "SATISFIED");
  const summary = JSON.parse(await readFile(output.summary, "utf8"));
  assert.equal(summary.artifactIdentity.gitSha, rcManifest().rcIdentity.gitSha);
  assert.equal(summary.postLaunchObservation.status, "PENDING_PUBLIC_RELEASE");
  assert.deepEqual(summary.evidenceValidity, {
    testedAt: "2026-07-15T00:00:00+09:00",
    expiresWhen: "2026-07-28T23:59:59.999+09:00",
  });
  await execFileAsync(process.execPath, [
    "tools/ops/validate-operations-release-summary.mjs",
    "--summary",
    output.summary,
    "--rc-manifest",
    output.manifest,
    "--require-pass",
  ], { cwd: root });
});

test("Phase A summary generator fails closed when the RC identity is incomplete", async () => {
  const output = await paths();
  await writeFile(output.manifest, `${JSON.stringify(rcManifest({ aabSha256: null }), null, 2)}\n`);

  await execFileAsync(process.execPath, [
    "tools/ops/generate-operations-phase-a-summary.mjs",
    "--rc-manifest",
    output.manifest,
    "--summary",
    output.summary,
    "--status-output",
    output.status,
  ], { cwd: root });

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator rejects an RC outside the recorded evidence scope", async () => {
  const output = await paths();
  await writeFile(output.manifest, `${JSON.stringify(rcManifest({ appVersionName: "1.0.3", versionCode: "10004" }), null, 2)}\n`);

  await execFileAsync(process.execPath, [
    "tools/ops/generate-operations-phase-a-summary.mjs",
    "--rc-manifest",
    output.manifest,
    "--summary",
    output.summary,
    "--status-output",
    output.status,
    "--now",
    "2026-07-15T16:00:00.000Z",
  ], { cwd: root });

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator rejects help-screen device QA from a different RC", async () => {
  const output = await paths();
  const gate = JSON.parse(await readFile(path.join(root, "apps/mobile/release/support-incident-response-gate.json"), "utf8"));
  gate.latestQaEvidenceSummary.helpScreenDeviceQa.versionCode = 10004;
  const gatePath = path.join(output.dir, "support-incident-response-gate.json");
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);
  await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);

  await generate(output, ["--support-gate", gatePath]);

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator rejects a contact set not verified by device QA", async () => {
  const output = await paths();
  const gate = JSON.parse(await readFile(path.join(root, "apps/mobile/release/support-incident-response-gate.json"), "utf8"));
  gate.latestQaEvidenceSummary.helpScreenDeviceQa.contactSetSha256 = "e".repeat(64);
  const gatePath = path.join(output.dir, "support-incident-response-gate.json");
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);
  await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);

  await generate(output, ["--support-gate", gatePath]);

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator requires a PASS summary for every required evidence ID", async () => {
  const output = await paths();
  const gate = JSON.parse(await readFile(path.join(root, "apps/mobile/release/post-launch-operations-review-gate.json"), "utf8"));
  gate.preLaunchReadiness.requiredEvidence.push("new-unproven-required-evidence");
  const gatePath = path.join(output.dir, "post-launch-operations-review-gate.json");
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);
  await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);

  await generate(output, ["--post-launch-gate", gatePath]);

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator rejects expired evidence", async () => {
  const output = await paths();
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);

  await execFileAsync(process.execPath, [
    "tools/ops/generate-operations-phase-a-summary.mjs",
    "--rc-manifest",
    output.manifest,
    "--summary",
    output.summary,
    "--status-output",
    output.status,
    "--now",
    "2026-07-30T00:00:00.000Z",
  ], { cwd: root });

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator removes a stale PASS summary when a later run is blocked", async () => {
  const output = await paths();
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);
  await generate(output);
  assert.equal(JSON.parse(await readFile(output.summary, "utf8")).status, "PASS");

  await writeFile(
    output.manifest,
    `${JSON.stringify(rcManifest({ appVersionName: "1.0.3", versionCode: "10004" }), null, 2)}\n`,
  );
  await generate(output);

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator fails closed when a refresh-bound surface changes", async () => {
  const output = await paths();
  const gate = JSON.parse(await readFile(path.join(root, "apps/mobile/release/post-launch-operations-review-gate.json"), "utf8"));
  gate.preLaunchReadiness.finalRcBinding.refreshBindings[0].files[0].sha256 = "0".repeat(64);
  const gatePath = path.join(output.dir, "post-launch-operations-review-gate.json");
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);
  await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);

  await generate(output, ["--post-launch-gate", gatePath]);

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator rejects a noncanonical Android application ID", async () => {
  const output = await paths();
  const manifest = rcManifest();
  manifest.androidApplicationId = "com.attacker.other";
  await writeFile(output.manifest, `${JSON.stringify(manifest, null, 2)}\n`);

  await generate(output);

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator uses signal-specific validated evidence", async () => {
  const output = await paths();
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);

  await generate(output);

  const summary = JSON.parse(await readFile(output.summary, "utf8"));
  const mapping = summary.observabilitySignals.find((item) => item.signalId === "android_mapping_retention");
  assert.equal(mapping.resolutionKind, "runbook");
  assert.match(mapping.localEvidencePath, /release-artifacts\.yml/);
  assert.equal(mapping.result, "PASS");
});

test("Phase A summary generator fails closed when one signal lacks validated evidence", async () => {
  const output = await paths();
  const gate = JSON.parse(await readFile(path.join(root, "apps/mobile/release/operations-observability-gate.json"), "utf8"));
  gate.phaseAValidatedEvidence = gate.phaseAValidatedEvidence.filter(
    (item) => item.signalId !== "android_mapping_retention",
  );
  const gatePath = path.join(output.dir, "operations-observability-gate.json");
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);
  await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);

  await generate(output, ["--observability-gate", gatePath]);

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

test("Phase A summary generator connects each support channel to its own validated evidence", async () => {
  const output = await paths();
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);

  await generate(output);

  const summary = JSON.parse(await readFile(output.summary, "utf8"));
  const supportEmail = summary.supportChannels.find((item) => item.channelId === "support_email");
  const faq = summary.supportChannels.find((item) => item.channelId === "faq_and_status_notice");
  assert.match(supportEmail.localEvidencePath, /mailbox-routing-summary\.json/);
  assert.match(faq.localEvidencePath, /fixed-release-help-ui-summary\.json/);
  assert.notEqual(supportEmail.localEvidencePath, faq.localEvidencePath);
});

test("Phase A summary generator fails closed when one support channel lacks validated evidence", async () => {
  const output = await paths();
  const gate = JSON.parse(await readFile(path.join(root, "apps/mobile/release/support-incident-response-gate.json"), "utf8"));
  gate.latestQaEvidenceSummary.channelEvidence = gate.latestQaEvidenceSummary.channelEvidence.filter(
    (item) => item.channelId !== "security_privacy_deletion",
  );
  const gatePath = path.join(output.dir, "support-incident-response-gate.json");
  await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);
  await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);

  await generate(output, ["--support-gate", gatePath]);

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});
