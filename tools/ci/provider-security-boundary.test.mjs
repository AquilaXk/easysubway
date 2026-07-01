import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../..");

function read(file) {
  return readFileSync(path.join(root, file), "utf8");
}

function readJson(file) {
  return JSON.parse(read(file));
}

test("provider credential과 release artifact security boundary regression을 고정한다", () => {
  const releaseSecurityGate = readJson("apps/mobile/release/release-security-gate.json");
  const securityPrivacyEvidence = readJson("apps/mobile/release/security-privacy-release-evidence.json");
  const abuseGate = readJson("apps/mobile/release/abuse-penetration-rehearsal-gate.json");
  const releaseArtifactsWorkflow = read(".github/workflows/release-artifacts.yml");
  const androidBuildGradle = read("apps/mobile/android/app/build.gradle.kts");
  const mobileTrackedSource = trackedFiles("apps/mobile").map((file) => [file, read(file)]);

  const providerStorageExposureGuard = releaseSecurityGate.items.find(
    (item) => item.id === "repository_provider_storage_exposure_guard",
  );
  assert.ok(providerStorageExposureGuard);
  assert.ok(providerStorageExposureGuard.evidence.includes("provider-security-boundary-regression-test"));
  assert.match(providerStorageExposureGuard.readyWhenKo, /provider key|object storage credential|signed URL/i);

  assert.ok(securityPrivacyEvidence.releaseArtifactSecretScan.forbiddenClasses.includes("provider-key"));
  assert.ok(securityPrivacyEvidence.releaseArtifactSecretScan.forbiddenClasses.includes("local-placeholder-endpoint"));
  assert.ok(securityPrivacyEvidence.crashAnrPrivacyEvidence.forbiddenPayload.includes("provider secret"));
  assert.ok(securityPrivacyEvidence.crashAnrPrivacyEvidence.forbiddenPayload.includes("object storage credential"));
  assert.ok(securityPrivacyEvidence.abusePenetrationRehearsal.requiredScenarios.includes("provider_and_release_secret_exposure"));

  const providerExposureMatrix = abuseGate.rehearsalMatrices.providerReleaseSecretExposure;
  assert.ok(providerExposureMatrix.requiredCases.includes("release_endpoint_allowlist_diff"));
  assert.ok(providerExposureMatrix.requiredCases.includes("pr_evidence_redaction"));
  assert.ok(providerExposureMatrix.forbiddenSummaryValues.includes("provider secret"));
  assert.ok(providerExposureMatrix.forbiddenSummaryValues.includes("object storage credential"));
  assert.ok(providerExposureMatrix.forbiddenSummaryValues.includes("local or internal endpoint"));

  assert.equal(abuseGate.productionLikeEvidencePolicy.missingEvidenceDisposition, "KEEP_OPEN_NO_GO");
  assert.ok(
    abuseGate.productionLikeEvidencePolicy.requiredForClosing.includes("play-installed-or-play-generated-artifact-identity"),
  );
  assert.ok(
    abuseGate.productionLikeEvidencePolicy.requiredForClosing.includes("deployed-public-https-backend-base-url"),
  );
  assert.ok(abuseGate.productionLikeEvidencePolicy.forbiddenClosureEvidence.includes("preflight env check only"));
  assert.ok(abuseGate.productionLikeEvidencePolicy.forbiddenClosureEvidence.includes("local selected tests only"));
  assert.ok(abuseGate.productionLikeEvidencePolicy.forbiddenClosureEvidence.includes("stale evidence from previous RC"));

  assert.doesNotMatch(releaseArtifactsWorkflow, /EASYSUBWAY_OBJECT_STORAGE_(?:ACCESS_KEY|SECRET_KEY|ENDPOINT|REGION)/);
  assert.doesNotMatch(releaseArtifactsWorkflow, /EASYSUBWAY_[A-Z0-9_]*(?:PROVIDER|REALTIME)[A-Z0-9_]*KEY/);
  assert.doesNotMatch(androidBuildGradle, /EASYSUBWAY_OBJECT_STORAGE|PROVIDER_API_KEY|REALTIME_PROVIDER_KEY/);

  for (const [file, content] of mobileTrackedSource) {
    assert.doesNotMatch(content, /swopenapi\.seoul\.go\.kr/i, `${file} must not call TOPIS directly`);
    assert.doesNotMatch(content, /EASYSUBWAY_SEOUL_TOPIS_SERVICE_KEY/i, `${file} must not reference backend TOPIS key`);
    assert.doesNotMatch(content, /["']?(?:serviceKey|apiKey|providerUrl|provider_url)["']?\s*(?:=|:)/i, `${file} must not carry provider credential fields`);
  }
});

function trackedFiles(prefix) {
  return execFileSync("git", ["ls-files", prefix], { cwd: root, encoding: "utf8" })
    .split("\n")
    .filter(Boolean)
    .filter((file) => /\.(dart|gradle|kts|xml|json|ya?ml|properties|plist|swift|kt)$/.test(file));
}
