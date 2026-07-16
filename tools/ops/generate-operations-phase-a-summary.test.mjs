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
      aabSha256: "15d9c7a3ff98c770a6b757f776ad102ad10c5b1dda81a0847a84e6d65b689a69",
      aabPayloadSha256: "6c4962a7858d7b6887d22770adaa1a3988dbed17f36d76e1298bd789639ad281",
      backendImageDigest: null,
      backendArtifactSha256: "8bc8f71f92fa82b38739a02424c6758f317b6dd4d3f07398cdf29a886c4b5f98",
      dataPackManifestSha256: "2ee9f38f3e748d7bbc6d9eba124b34e6b5c8ad539338a6cdeee7a472515456e5",
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

function markFixedReleaseRevalidated(gate) {
  gate.preLaunchReadiness.status = "PASS";
  gate.preLaunchReadiness.evidenceSummary.find(
    (item) => item.id === "fixed-release-versioncode-build-submit-procedure",
  ).status = "PASS";
  gate.latestQaEvidenceSummary.remainingExternalBlockers =
    gate.latestQaEvidenceSummary.remainingExternalBlockers.filter(
      (item) => item !== "fixed-release-rehearsal-after-node24-runtime-change",
    );
  return gate;
}

async function generate(output, extraArgs = []) {
  const timeArgs = extraArgs.includes("--now") ? [] : ["--now", validPhaseANow];
  const gateArgs = extraArgs.includes("--post-launch-gate") ? [] : [
    "--post-launch-gate",
    path.join(output.dir, "revalidated-post-launch-gate.json"),
  ];
  if (gateArgs.length > 0) {
    const gate = markFixedReleaseRevalidated(JSON.parse(await readFile(
      path.join(root, "apps/mobile/release/post-launch-operations-review-gate.json"),
      "utf8",
    )));
    await writeFile(gateArgs[1], `${JSON.stringify(gate, null, 2)}\n`);
  }
  await execFileAsync(process.execPath, [
    "tools/ops/generate-operations-phase-a-summary.mjs",
    "--rc-manifest",
    output.manifest,
    "--summary",
    output.summary,
    "--status-output",
    output.status,
    ...gateArgs,
    ...timeArgs,
    ...extraArgs,
  ], { cwd: root });
}

test("canonical Phase A gate blocks until the Node 24 fixed-release rehearsal is refreshed", async () => {
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
    validPhaseANow,
  ], { cwd: root });

  assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
  await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
});

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
    "--post-launch-gate",
    path.join(output.dir, "revalidated-post-launch-gate.json"),
    "--rc-manifest",
    output.manifest,
    "--now",
    validPhaseANow,
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

for (const [field, value] of [
  ["aabPayloadSha256", "d".repeat(64)],
  ["backendArtifactSha256", "d".repeat(64)],
  ["dataPackManifestSha256", "d".repeat(64)],
]) {
  test(`Phase A summary generator rejects an RC with an unvalidated ${field}`, async () => {
    const output = await paths();
    const gate = JSON.parse(await readFile(
      path.join(root, "apps/mobile/release/post-launch-operations-review-gate.json"),
      "utf8",
    ));
    markFixedReleaseRevalidated(gate);
    gate.preLaunchReadiness.finalRcBinding.validatedArtifactIdentity = rcManifest().rcIdentity;
    const gatePath = path.join(output.dir, "post-launch-operations-review-gate.json");
    await writeFile(output.manifest, `${JSON.stringify(rcManifest({ [field]: value }), null, 2)}\n`);
    await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);

    await generate(output, ["--post-launch-gate", gatePath]);

    assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
    await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
  });
}

test("Phase A summary generator binds a newly signed AAB with the validated payload", async () => {
  const output = await paths();
  await writeFile(
    output.manifest,
    `${JSON.stringify(rcManifest({ aabSha256: "d".repeat(64) }), null, 2)}\n`,
  );

  await generate(output);

  assert.equal((await readFile(output.status, "utf8")).trim(), "SATISFIED");
  const summary = JSON.parse(await readFile(output.summary, "utf8"));
  assert.equal(summary.artifactIdentity.aabSha256, "d".repeat(64));
  assert.equal(
    summary.artifactIdentity.aabPayloadSha256,
    "6c4962a7858d7b6887d22770adaa1a3988dbed17f36d76e1298bd789639ad281",
  );
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

for (const [label, receivedAt] of [
  ["before the evidence window", "2026-07-14T23:59:59+09:00"],
  ["after the validation clock", "2026-07-17T00:00:00+09:00"],
]) {
  test(`Phase A summary generator rejects support evidence ${label}`, async () => {
    const output = await paths();
    const gate = JSON.parse(await readFile(path.join(root, "apps/mobile/release/support-incident-response-gate.json"), "utf8"));
    gate.latestQaEvidenceSummary.channelEvidence[0].receivedAt = receivedAt;
    const gatePath = path.join(output.dir, "support-incident-response-gate.json");
    await writeFile(output.manifest, `${JSON.stringify(rcManifest(), null, 2)}\n`);
    await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);

    await generate(output, ["--support-gate", gatePath]);

    assert.equal((await readFile(output.status, "utf8")).trim(), "BLOCKED_EXTERNAL");
    await assert.rejects(readFile(output.summary, "utf8"), /ENOENT/);
  });
}

test("Phase A summary generator requires a PASS summary for every required evidence ID", async () => {
  const output = await paths();
  const gate = JSON.parse(await readFile(path.join(root, "apps/mobile/release/post-launch-operations-review-gate.json"), "utf8"));
  markFixedReleaseRevalidated(gate);
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
  markFixedReleaseRevalidated(gate);
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
