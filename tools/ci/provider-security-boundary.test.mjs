import assert from "node:assert/strict";
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

  assert.doesNotMatch(releaseArtifactsWorkflow, /EASYSUBWAY_OBJECT_STORAGE_(?:ACCESS_KEY|SECRET_KEY|ENDPOINT|REGION)/);
  assert.doesNotMatch(releaseArtifactsWorkflow, /EASYSUBWAY_[A-Z0-9_]*(?:PROVIDER|REALTIME)[A-Z0-9_]*KEY/);
  assert.doesNotMatch(androidBuildGradle, /EASYSUBWAY_OBJECT_STORAGE|PROVIDER_API_KEY|REALTIME_PROVIDER_KEY/);
});
