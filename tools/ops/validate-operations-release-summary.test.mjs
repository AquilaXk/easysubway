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
  versionName: "1.0.4",
  versionCode: 10005,
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
    evidenceValidity: {
      testedAt: "2026-07-15T00:00:00+09:00",
      expiresWhen: "2026-07-29T23:59:59.999+09:00",
    },
    artifactIdentity: { ...artifactIdentity },
    preLaunchReadiness: {
      status: "PASS",
      evidenceIds: postLaunchGate.preLaunchReadiness.requiredEvidence,
    },
    postLaunchObservation: {
      status: "IN_PROGRESS",
      publicReleaseIdentity: {
        publishedAt: "2020-01-01T00:00:00+09:00",
        versionCode: artifactIdentity.versionCode,
        gitSha: artifactIdentity.gitSha,
      },
    },
    observabilitySignals: observabilityGate.signals.map((signal) => {
      const evidence = observabilityGate.phaseAValidatedEvidence.find((item) => item.signalId === signal.id);
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
    postLaunchReviews: postLaunchGate.reviewWindows.map((window) => ({
      reviewWindowId: window.id,
      observedAt: {
        first_2h: "2020-01-01T02:00:00+09:00",
        first_24h: "2020-01-02T00:00:00+09:00",
        day_7: "2020-01-08T00:00:00+09:00",
        day_30: "2020-01-31T00:00:00+09:00",
      }[window.id],
      artifactIdentity: { ...artifactIdentity },
      signalSnapshot: window.requiredSignals,
      owner: window.ownerKo,
      decision: window.decisionKo,
      goNoGoResult: "PASS",
      redactionNotes: "summary only; no personal data",
      localEvidencePath: ".codex/evidence/release/post-launch-operations-review/rc/redacted-summary.json",
    })),
    postLaunchDryRunEvidence: postLaunchGate.dryRunRequiredEvidence,
    supportChannels: supportGate.supportChannels.map((channel) => {
      const evidence = supportGate.latestQaEvidenceSummary.channelEvidence.find(
        (item) => item.channelId === channel.id,
      );
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
    supportDryRunEvidence: supportGate.dryRunRequiredEvidence,
    operatorContactRoutes: supportGate.operatorContactRoutes.map((route) => ({
      routeId: route.id,
      evidenceIds: route.requiredEvidence,
      result: "PASS",
      localEvidencePath: ".codex/evidence/release/support-incident-response/rc/operator-contact-readiness.json",
    })),
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
  const rcManifestPath = path.join(dir, "rc-evidence-manifest.json");
  await writeFile(summaryPath, `${JSON.stringify(summary, null, 2)}\n`);
  await writeFile(rcManifestPath, `${JSON.stringify({
    schemaVersion: 1,
    releaseGate: "rc-evidence-manifest",
    androidApplicationId: summary.artifactIdentity.androidApplicationId,
    rcIdentity: {
      gitSha: summary.artifactIdentity.gitSha,
      appVersionName: summary.artifactIdentity.versionName,
      versionCode: summary.artifactIdentity.versionCode,
      aabSha256: summary.artifactIdentity.aabSha256,
      backendImageDigest: summary.artifactIdentity.backendImageDigest ?? null,
      backendArtifactSha256: summary.artifactIdentity.backendArtifactSha256 ?? null,
      dataPackManifestSha256: summary.artifactIdentity.dataPackManifestSha256,
    },
  }, null, 2)}\n`);
  const previousRcManifest = process.env.EASYSUBWAY_OPERATIONS_RC_MANIFEST;
  process.env.EASYSUBWAY_OPERATIONS_RC_MANIFEST = rcManifestPath;
  try {
    return await fn(summaryPath, rcManifestPath);
  } finally {
    if (previousRcManifest === undefined) delete process.env.EASYSUBWAY_OPERATIONS_RC_MANIFEST;
    else process.env.EASYSUBWAY_OPERATIONS_RC_MANIFEST = previousRcManifest;
  }
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

test("operations release summary validator rejects expired Phase A evidence", async () => {
  await assert.rejects(
    withSummary(validSummary(), (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--now",
        "2026-07-30T00:00:00+09:00",
        "--require-pass",
      ], { cwd: root }),
    ),
    /evidenceValidity must be current/,
  );
});

test("operations release summary validator rejects identity outside the canonical evidence scope", async () => {
  const summary = validSummary();
  summary.artifactIdentity.versionName = "1.0.5";
  summary.artifactIdentity.versionCode = 10006;
  for (const review of summary.postLaunchReviews) {
    review.artifactIdentity.versionName = summary.artifactIdentity.versionName;
    review.artifactIdentity.versionCode = summary.artifactIdentity.versionCode;
  }
  summary.postLaunchObservation.publicReleaseIdentity.versionCode = summary.artifactIdentity.versionCode;
  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /artifactIdentity must match the canonical Phase A evidence scope/,
  );
});

test("operations release summary validator rejects regressed canonical support readiness", async () => {
  for (const mutate of [
    (gate) => { gate.preLaunchReadiness.status = "FAIL"; },
    (gate) => { gate.latestQaEvidenceSummary.helpScreenDeviceQa.result = "FAIL"; },
    (gate) => { gate.latestQaEvidenceSummary.operatorContactReadiness.result = "FAIL"; },
    (gate) => { gate.latestQaEvidenceSummary.remainingSupportReadiness = ["mailbox-routing"]; },
  ]) {
    await assert.rejects(
      withSummary(validSummary(), async (summaryPath) => {
        const gate = structuredClone(supportGate);
        mutate(gate);
        const gatePath = path.join(path.dirname(summaryPath), "support-gate.json");
        await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);
        return execFileAsync(process.execPath, [
          "tools/ops/validate-operations-release-summary.mjs",
          "--summary",
          summaryPath,
          "--support-gate",
          gatePath,
          "--require-pass",
        ], { cwd: root });
      }),
      /canonical support readiness must be PASS/,
    );
  }
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

test("operations release summary validator accepts backendImageDigest as the final RC backend identity", async () => {
  const summary = validSummary();
  delete summary.artifactIdentity.backendArtifactSha256;
  summary.artifactIdentity.backendImageDigest = `sha256:${"b".repeat(64)}`;
  for (const review of summary.postLaunchReviews) {
    delete review.artifactIdentity.backendArtifactSha256;
    review.artifactIdentity.backendImageDigest = summary.artifactIdentity.backendImageDigest;
  }

  await withSummary(summary, (summaryPath) =>
    execFileAsync(process.execPath, [
      "tools/ops/validate-operations-release-summary.mjs",
      "--summary",
      summaryPath,
      "--require-pass",
    ], { cwd: root }),
  );
});

test("operations release summary validator rejects an identity that does not match the RC manifest", async () => {
  const summary = validSummary();

  await assert.rejects(
    withSummary(summary, async (summaryPath, rcManifestPath) => {
      const rcManifest = JSON.parse(readFileSync(rcManifestPath, "utf8"));
      rcManifest.rcIdentity.versionCode += 1;
      await writeFile(rcManifestPath, `${JSON.stringify(rcManifest, null, 2)}\n`);
      return execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root });
    }),
    /artifactIdentity must match the RC manifest identity/,
  );
});

test("operations release summary validator rejects a version name that does not match the RC manifest", async () => {
  const summary = validSummary();

  await assert.rejects(
    withSummary(summary, async (summaryPath, rcManifestPath) => {
      const rcManifest = JSON.parse(readFileSync(rcManifestPath, "utf8"));
      rcManifest.rcIdentity.appVersionName = "9.9.9";
      await writeFile(rcManifestPath, `${JSON.stringify(rcManifest, null, 2)}\n`);
      return execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root });
    }),
    /artifactIdentity must match the RC manifest identity/,
  );
});

test("operations release summary validator rejects an application ID that does not match the RC manifest", async () => {
  const summary = validSummary();

  await assert.rejects(
    withSummary(summary, async (summaryPath, rcManifestPath) => {
      const rcManifest = JSON.parse(readFileSync(rcManifestPath, "utf8"));
      rcManifest.androidApplicationId = "com.attacker.other";
      await writeFile(rcManifestPath, `${JSON.stringify(rcManifest, null, 2)}\n`);
      return execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root });
    }),
    /artifactIdentity must match the RC manifest identity/,
  );
});

test("operations release summary validator rejects a manifest and summary with the same noncanonical application ID", async () => {
  const summary = validSummary();
  summary.artifactIdentity.androidApplicationId = "com.attacker.other";
  for (const review of summary.postLaunchReviews) {
    review.artifactIdentity.androidApplicationId = "com.attacker.other";
  }

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /artifactIdentity must match the RC manifest identity/,
  );
});

test("operations release summary validator rejects missing post-launch dry-run evidence", async () => {
  const summary = validSummary();
  delete summary.postLaunchDryRunEvidence;
  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /postLaunchDryRunEvidence/,
  );
});

test("operations release summary validator accepts Phase A PASS while Phase B waits for public release", async () => {
  const summary = validSummary();
  summary.preLaunchReadiness = {
    status: "PASS",
    evidenceIds: [
      "signal-owner-threshold-first-response",
      "grafana-prometheus-loki-play-console-access",
      "p0-p1-p2-alert-route-dry-run",
      "support-security-privacy-data-deletion-mailbox-receive-test",
      "backend-datapack-rollback-rehearsal",
      "p0-data-error-emergency-release-rollback-rehearsal",
      "fixed-release-versioncode-build-submit-procedure",
      "post-launch-window-owner-time-checklist-record-location-reservation",
      "incident-notice-template-approval-route",
    ],
  };
  summary.postLaunchObservation = {
    status: "PENDING_PUBLIC_RELEASE",
    publicReleaseIdentity: { publishedAt: null, versionCode: null, gitSha: null },
  };
  delete summary.postLaunchReviews;

  await withSummary(summary, (summaryPath) =>
    execFileAsync(process.execPath, [
      "tools/ops/validate-operations-release-summary.mjs",
      "--summary",
      summaryPath,
      "--require-pass",
    ], { cwd: root }),
  );
});

test("operations release summary validator rejects a stale pending summary after public release", async () => {
  const summary = validSummary();
  summary.postLaunchObservation = {
    status: "PENDING_PUBLIC_RELEASE",
    publicReleaseIdentity: { publishedAt: null, versionCode: null, gitSha: null },
  };
  delete summary.postLaunchReviews;

  await assert.rejects(
    withSummary(summary, async (summaryPath) => {
      const gate = structuredClone(postLaunchGate);
      gate.postLaunchObservation.status = "IN_PROGRESS";
      gate.postLaunchObservation.publicReleaseIdentity = {
        publishedAt: "2026-07-15T00:00:00+09:00",
        versionCode: artifactIdentity.versionCode,
        gitSha: artifactIdentity.gitSha,
      };
      const gatePath = path.join(path.dirname(summaryPath), "post-launch-gate.json");
      await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);
      return execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--post-launch-gate",
        gatePath,
        "--require-pass",
      ], { cwd: root });
    }),
    /postLaunchObservation.status must follow an allowed transition/,
  );
});

test("operations release summary validator rejects skipping directly from pending to pass", async () => {
  const summary = validSummary();
  summary.postLaunchObservation.status = "PASS";

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /postLaunchObservation.status must follow an allowed transition/,
  );
});

test("operations release summary validator accepts the declared in-progress to pass transition", async () => {
  const summary = validSummary();
  summary.postLaunchObservation.status = "PASS";

  await withSummary(summary, async (summaryPath) => {
    const gate = structuredClone(postLaunchGate);
    gate.postLaunchObservation.status = "IN_PROGRESS";
    gate.postLaunchObservation.publicReleaseIdentity = structuredClone(
      summary.postLaunchObservation.publicReleaseIdentity,
    );
    const gatePath = path.join(path.dirname(summaryPath), "post-launch-gate.json");
    await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);
    return execFileAsync(process.execPath, [
      "tools/ops/validate-operations-release-summary.mjs",
      "--summary",
      summaryPath,
      "--post-launch-gate",
      gatePath,
      "--require-pass",
    ], { cwd: root });
  });
});

test("operations release summary validator accepts a non-pass Phase A diagnostic summary", async () => {
  const summary = validSummary();
  summary.status = "FAIL";
  summary.preLaunchReadiness = { status: "FAIL", evidenceIds: [] };
  summary.postLaunchObservation = {
    status: "PENDING_PUBLIC_RELEASE",
    publicReleaseIdentity: { publishedAt: null, versionCode: null, gitSha: null },
  };
  delete summary.postLaunchReviews;
  summary.externalBlockers = ["phase-a-evidence-incomplete"];

  await withSummary(summary, async (summaryPath) => {
    const gate = structuredClone(postLaunchGate);
    gate.preLaunchReadiness.status = "FAIL";
    const gatePath = path.join(path.dirname(summaryPath), "post-launch-gate.json");
    await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);
    return execFileAsync(process.execPath, [
      "tools/ops/validate-operations-release-summary.mjs",
      "--summary",
      summaryPath,
      "--post-launch-gate",
      gatePath,
    ], { cwd: root });
  });
});

test("operations release summary validator rejects PASS when the canonical Phase A gate is not PASS", async () => {
  const summary = validSummary();

  await assert.rejects(
    withSummary(summary, async (summaryPath) => {
      const gate = structuredClone(postLaunchGate);
      gate.preLaunchReadiness.status = "BLOCKED_EXTERNAL";
      const gatePath = path.join(path.dirname(summaryPath), "post-launch-gate.json");
      await writeFile(gatePath, `${JSON.stringify(gate, null, 2)}\n`);
      return execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--post-launch-gate",
        gatePath,
        "--require-pass",
      ], { cwd: root });
    }),
    /preLaunchReadiness.status must match the current gate state/,
  );
});

test("operations release summary validator accepts a partial Phase B observation in progress", async () => {
  const summary = validSummary();
  summary.postLaunchObservation.status = "IN_PROGRESS";
  summary.postLaunchReviews = summary.postLaunchReviews.slice(0, 1);

  await withSummary(summary, (summaryPath) =>
    execFileAsync(process.execPath, [
      "tools/ops/validate-operations-release-summary.mjs",
      "--summary",
      summaryPath,
      "--require-pass",
    ], { cwd: root }),
  );
});

test("operations release summary validator rejects a non-prefix Phase B observation", async () => {
  const summary = validSummary();
  summary.postLaunchReviews = [summary.postLaunchReviews[2]];

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /IN_PROGRESS postLaunchReviews must be a chronological prefix/,
  );
});

test("operations release summary validator accepts Phase B in progress before the first review window", async () => {
  const summary = validSummary();
  summary.postLaunchObservation.status = "IN_PROGRESS";
  summary.postLaunchReviews = [];

  await withSummary(summary, (summaryPath) =>
    execFileAsync(process.execPath, [
      "tools/ops/validate-operations-release-summary.mjs",
      "--summary",
      summaryPath,
      "--require-pass",
    ], { cwd: root }),
  );
});

test("operations release summary validator rejects missing operator contact route evidence", async () => {
  const summary = validSummary();
  summary.operatorContactRoutes[0].evidenceIds = [];

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /operatorContactRoutes.seoul_metro_or_city_provider.evidenceIds missing/,
  );
});

test("operations release summary validator rejects a failed Phase B review when pass is required", async () => {
  const summary = validSummary();
  summary.postLaunchObservation.status = "IN_PROGRESS";
  summary.postLaunchReviews = summary.postLaunchReviews.slice(0, 1);
  summary.postLaunchReviews[0].goNoGoResult = "FAIL";

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /goNoGoResult must be PASS/,
  );
});

test("operations release summary validator rejects an invalid public release timestamp", async () => {
  const summary = validSummary();
  summary.postLaunchObservation.publicReleaseIdentity.publishedAt = "not-a-date";

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /publishedAt must be an RFC 3339 timestamp/,
  );
});

test("operations release summary validator rejects a public release timestamp in the future", async () => {
  const summary = validSummary();
  summary.postLaunchObservation.publicReleaseIdentity.publishedAt = "2999-01-01T00:00:00Z";
  summary.postLaunchReviews = [];

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /publishedAt must not be in the future/,
  );
});

test("operations release summary validator rejects a review observed before its due time", async () => {
  const summary = validSummary();
  summary.postLaunchReviews.at(-1).observedAt = summary.postLaunchObservation.publicReleaseIdentity.publishedAt;

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /observedAt must be at or after its due time/,
  );
});

test("operations release summary validator rejects a review dated in the future", async () => {
  const summary = validSummary();
  summary.postLaunchReviews[0].observedAt = "2999-01-01T00:00:00Z";

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /observedAt must not be in the future/,
  );
});

test("operations release summary validator rejects a public release identity from another RC", async () => {
  const summary = validSummary();
  summary.postLaunchObservation.publicReleaseIdentity.versionCode += 1;

  await assert.rejects(
    withSummary(summary, (summaryPath) =>
      execFileAsync(process.execPath, [
        "tools/ops/validate-operations-release-summary.mjs",
        "--summary",
        summaryPath,
        "--require-pass",
      ], { cwd: root }),
    ),
    /public release identity must match artifactIdentity/,
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
