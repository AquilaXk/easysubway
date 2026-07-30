import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { validateSystemReleaseManifest } from "./validate-system-release-manifest.mjs";

const sha = "a".repeat(64);
const gitSha = "b".repeat(40);
const issue = (repository, number) => `AquilaXk/${repository}#${number}`;

function validManifest() {
  return {
    schemaVersion: 2,
    productReleaseId: "easysubway-2026.07.30.1",
    phase: "FINAL",
    decision: "GO",
    generatedAt: "2026-07-30T00:00:00Z",
    issueRefs: [issue("easysubway", 2693)],
    contracts: { version: "release-manifest-v2", sha256: sha },
    mobile: {
      schemaVersion: 1, component: "mobile", repository: "AquilaXk/easysubway-mobile", gitSha,
      artifactIdentity: { versionName: "1.0.0", versionCode: 1, aabSha256: sha, bundledDataManifestSha256: sha },
      contractVersion: "mobile-v1", evidenceSha256: sha, issueRefs: [issue("easysubway-mobile", 2693)],
    },
    backend: {
      schemaVersion: 1, component: "backend", repository: "AquilaXk/easysubway-backend", gitSha,
      artifactIdentity: { imageDigest: `sha256:${sha}`, apiContractVersion: "api-v1" },
      contractVersion: "backend-v1", evidenceSha256: sha, issueRefs: [issue("easysubway-backend", 2693)],
    },
    data: {
      schemaVersion: 1, component: "data", repository: "AquilaXk/easysubway-data", gitSha,
      artifactIdentity: { dataVersion: "2026.07", releaseSequence: 1, manifestSha256: sha, sourceSnapshotSetHash: sha },
      contractVersion: "data-v1", evidenceSha256: sha, issueRefs: [issue("easysubway-data", 2693)],
    },
    platform: {
      schemaVersion: 1, component: "platform", repository: "AquilaXk/easysubway-platform", gitSha,
      artifactIdentity: { environment: "production", deployedImageDigest: `sha256:${sha}`, deploymentEvidenceSha256: sha },
      contractVersion: "platform-v1", evidenceSha256: sha, issueRefs: [issue("easysubway-platform", 2693)],
    },
  };
}

const schemas = {
  componentSchema: JSON.parse(readFileSync("contracts/release/component-manifest.schema.json", "utf8")),
  systemSchema: JSON.parse(readFileSync("contracts/release/system-release-manifest.schema.json", "utf8")),
  issueRefSchema: JSON.parse(readFileSync("contracts/release/issue-ref.schema.json", "utf8")),
};

test("system release manifest v2 validates the locked release identity", () => {
  assert.deepEqual(validateSystemReleaseManifest({ manifest: validManifest(), ...schemas }), []);
});

test("system release manifest v2 rejects every locked identity violation", () => {
  const cases = [
    ["top-level gitSha", (manifest) => { manifest.gitSha = gitSha; }],
    ["bare issue number", (manifest) => { manifest.issueRefs = [2693]; }],
    ["uppercase hash", (manifest) => { manifest.contracts.sha256 = sha.toUpperCase(); }],
    ["malformed hash", (manifest) => { manifest.contracts.sha256 = "invalid"; }],
    ["mutable backend tag", (manifest) => { manifest.backend.artifactIdentity.imageDigest = "latest"; }],
    ["wrong slot component", (manifest) => { manifest.mobile.component = "backend"; }],
    ["wrong target repository", (manifest) => { manifest.mobile.repository = "AquilaXk/easysubway-data"; }],
    ["duplicate component name", (manifest) => { manifest.backend.component = "mobile"; }],
    ["mobile/data hash mismatch", (manifest) => { manifest.mobile.artifactIdentity.bundledDataManifestSha256 = "c".repeat(64); }],
    ["backend/platform digest mismatch", (manifest) => { manifest.platform.artifactIdentity.deployedImageDigest = `sha256:${"c".repeat(64)}`; }],
    ["invalid GO transition", (manifest) => { manifest.phase = "CANDIDATE"; }],
  ];

  for (const [name, mutate] of cases) {
    const manifest = validManifest();
    mutate(manifest);
    assert.ok(validateSystemReleaseManifest({ manifest, ...schemas }).length > 0, name);
  }
});
