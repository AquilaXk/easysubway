import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const observabilityGate = JSON.parse(
  readFileSync(path.join(root, "apps/mobile/release/operations-observability-gate.json"), "utf8"),
);
const postLaunchGate = JSON.parse(
  readFileSync(path.join(root, "apps/mobile/release/post-launch-operations-review-gate.json"), "utf8"),
);
const supportGate = JSON.parse(
  readFileSync(path.join(root, "apps/mobile/release/support-incident-response-gate.json"), "utf8"),
);

const artifactIdentity = {
  gitSha: "abcdef1234567890",
  versionName: "1.0.2",
  versionCode: 10002,
  androidApplicationId: "com.easysubway.app",
  aabSha256: "a".repeat(64),
  backendArtifactSha256: "b".repeat(64),
  dataPackManifestSha256: "c".repeat(64),
};

function validSummary() {
  return {
    schemaVersion: 1,
    releaseGate: "operations-release-summary",
    issue: 1019,
    status: "PASS",
    artifactIdentity: { ...artifactIdentity },
    observabilitySignals: observabilityGate.signals.map((signal) => ({
      signalId: signal.id,
      owner: signal.ownerKo,
      threshold: signal.thresholdKo,
      firstResponse: signal.firstResponseKo,
      resolutionKind: "dashboard-url",
      evidenceIds: signal.evidence,
      result: "PASS",
      redactionNotes: "summary only; sensitive values removed",
      localEvidencePath: ".codex/evidence/operations-release/rc/redacted-summary.json",
    })),
    postLaunchReviews: postLaunchGate.reviewWindows.map((window) => ({
      reviewWindowId: window.id,
      artifactIdentity: { ...artifactIdentity },
      signalSnapshot: window.requiredSignals,
      owner: window.ownerKo,
      decision: window.decisionKo,
      goNoGoResult: "PASS",
      redactionNotes: "summary only; no personal data",
      localEvidencePath: ".codex/evidence/release/post-launch-operations-review/rc/redacted-summary.json",
    })),
    supportChannels: supportGate.supportChannels.map((channel) => ({
      channelId: channel.id,
      redactedReceiptReference: "redacted-routing-check",
      receivedAt: "2026-07-02T00:00:00+09:00",
      owner: channel.ownerKo,
      result: "PASS",
      redactionNotes: "message body and mailbox personal data omitted",
      localEvidencePath: ".codex/evidence/release/support-incident-response/rc/redacted-summary.json",
      evidenceIds: channel.requiredEvidence,
    })),
    supportDryRunEvidence: supportGate.dryRunRequiredEvidence,
    dataCorrectionSteps: supportGate.dataCorrectionFlow.requiredSteps,
    fixedReleaseSteps: postLaunchGate.fixedReleaseProcedure.requiredSteps,
    externalBlockers: [],
  };
}

async function withSummary(summary, fn) {
  const dir = path.join(tmpdir(), `operations-summary-${Date.now()}-${Math.random().toString(16).slice(2)}`);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });
  const summaryPath = path.join(dir, "summary.json");
  await writeFile(summaryPath, `${JSON.stringify(summary, null, 2)}\n`);
  return fn(summaryPath);
}

test("operations release summary validator accepts complete redacted release evidence", async () => {
  await withSummary(validSummary(), (summaryPath) =>
    execFileAsync(process.execPath, [
      "tools/ops/validate-operations-release-summary.mjs",
      "--summary",
      summaryPath,
      "--require-pass",
    ], { cwd: root }),
  );
});

test("operations release summary validator compares artifact identity independent of JSON key order", async () => {
  const summary = validSummary();
  summary.postLaunchReviews[0].artifactIdentity = {
    versionCode: artifactIdentity.versionCode,
    gitSha: artifactIdentity.gitSha,
    dataPackManifestSha256: artifactIdentity.dataPackManifestSha256,
    backendArtifactSha256: artifactIdentity.backendArtifactSha256,
    aabSha256: artifactIdentity.aabSha256,
    androidApplicationId: artifactIdentity.androidApplicationId,
    versionName: artifactIdentity.versionName,
  };
  await withSummary(summary, (summaryPath) =>
    execFileAsync(process.execPath, [
      "tools/ops/validate-operations-release-summary.mjs",
      "--summary",
      summaryPath,
      "--require-pass",
    ], { cwd: root }),
  );
});

test("operations release summary validator rejects missing signals, fallback pass-through, and raw sensitive data", async () => {
  const missingSignal = validSummary();
  missingSignal.observabilitySignals.pop();
  await assert.rejects(
    withSummary(missingSignal, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/ops/validate-operations-release-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /observabilitySignals\./,
  );

  const fallbackPass = validSummary();
  fallbackPass.observabilitySignals[0].resolutionKind = "external-blocker-record";
  await assert.rejects(
    withSummary(fallbackPass, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /external-blocker-record cannot satisfy --require-pass/,
  );

  const leaked = validSummary();
  leaked.supportChannels[0].redactionNotes = "Authorization: Bearer raw-token";
  await assert.rejects(
    withSummary(leaked, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/ops/validate-operations-release-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /raw secret, token, cookie, signed URL, or personal data/,
  );

  const rawReceiptMarker = validSummary();
  rawReceiptMarker.supportChannels[0].redactionNotes = "raw report receipt token: abc123";
  await assert.rejects(
    withSummary(rawReceiptMarker, (summaryPath) =>
      execFileAsync(process.execPath, ["tools/ops/validate-operations-release-summary.mjs", "--summary", summaryPath], {
        cwd: root,
      }),
    ),
    /forbidden sensitive evidence marker/,
  );
});
