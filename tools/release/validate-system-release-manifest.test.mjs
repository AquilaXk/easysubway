import assert from "node:assert/strict";
import test from "node:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import { selectSystemReleaseDecision, validateSystemReleaseManifest } from "./validate-system-release-manifest.mjs";

const sha = "a".repeat(64);
const gitSha = "b".repeat(40);
const issue = (repository, number) => `AquilaXk/${repository}#${number}`;

function validManifest() {
  return {
    schemaVersion: 3,
    productReleaseId: "easysubway-2026.07.30.1",
    phase: "FINAL",
    decision: "GO",
    generatedAt: "2026-07-30T00:00:00Z",
    issueRefs: [issue("easysubway", 2693)],
    hub: { repository: "AquilaXk/easysubway", gitSha },
    contracts: { version: "1.2.3", sha256: sha },
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

test("system release manifest v3 validates the locked five-repository release identity", () => {
  assert.deepEqual(validateSystemReleaseManifest({ manifest: validManifest(), ...schemas }), []);
});

test("system release manifest v3 rejects invalid contracts SemVer", () => {
  const manifest = validManifest();
  manifest.contracts.version = `1.2.3-${"a.".repeat(150)}a`;
  assert.ok(validateSystemReleaseManifest({ manifest, ...schemas }).includes("system: contracts version must be SemVer"));
});

test("system release decision requires legacy GO and every GO transition condition", () => {
  assert.equal(selectSystemReleaseDecision({ legacyDecision: "GO", manifest: validManifest(), ...schemas }), "GO");
  assert.equal(selectSystemReleaseDecision({ legacyDecision: "NO_GO", manifest: validManifest(), ...schemas }), "NO_GO");

  for (const mutate of [
    (manifest) => { manifest.platform.artifactIdentity.environment = "ci"; },
    (manifest) => { manifest.data.artifactIdentity.releaseSequence = 0; },
    (manifest) => { for (const slot of ["mobile", "backend", "data", "platform"]) manifest[slot].repository = "AquilaXk/easysubway"; },
  ]) {
    const manifest = validManifest();
    mutate(manifest);
    assert.equal(selectSystemReleaseDecision({ legacyDecision: "GO", manifest, ...schemas }), "NO_GO");
  }
});

test("system release manifest v3 rejects every locked identity violation", () => {
  const cases = [
    ["legacy v2", (manifest) => { manifest.schemaVersion = 2; }],
    ["missing Hub identity", (manifest) => { delete manifest.hub; }],
    ["missing Hub SHA", (manifest) => { delete manifest.hub.gitSha; }],
    ["wrong Hub repository", (manifest) => { manifest.hub.repository = "AquilaXk/easysubway-backend"; }],
    ["uppercase Hub SHA", (manifest) => { manifest.hub.gitSha = gitSha.toUpperCase(); }],
    ["short Hub SHA", (manifest) => { manifest.hub.gitSha = "b".repeat(39); }],
    ["extra Hub identity field", (manifest) => { manifest.hub.ref = "main"; }],
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

test("system release manifest v3 rejects unsafe identity integers", () => {
  for (const [mutate, expected] of [
    [(manifest) => { manifest.mobile.artifactIdentity.versionCode = Number.MAX_SAFE_INTEGER + 1; }, "mobile: versionCode must be a safe integer"],
    [(manifest) => { manifest.data.artifactIdentity.releaseSequence = Number.MAX_SAFE_INTEGER + 1; }, "data: releaseSequence must be a safe integer"],
  ]) {
    const manifest = validManifest();
    mutate(manifest);
    assert.deepEqual(validateSystemReleaseManifest({ manifest, ...schemas }), [expected]);
  }
});

test("system and component non-array issue refs return validation errors without throwing", () => {
  for (const mutate of [
    (manifest) => { manifest.issueRefs = 2693; },
    (manifest) => { manifest.mobile.issueRefs = {}; },
  ]) {
    const manifest = validManifest();
    mutate(manifest);
    assert.doesNotThrow(() => validateSystemReleaseManifest({ manifest, ...schemas }));
    assert.ok(validateSystemReleaseManifest({ manifest, ...schemas }).length > 0);
  }
});

test("CLI emits fixed redacted errors for argument, file, and JSON failures", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "release-manifest-test-"));
  const missingPath = path.join(directory, "TOP_SECRET_MANIFEST_BODY.json");
  const malformedPath = path.join(directory, "malformed.json");
  writeFileSync(malformedPath, '{"secret":"TOP_SECRET_MANIFEST_BODY"');
  try {
    const cases = [
      [[], "invalid arguments"],
      [["--manifest", missingPath], "manifest file is unreadable or invalid JSON"],
      [["--manifest", malformedPath], "manifest file is unreadable or invalid JSON"],
    ];
    for (const [args, message] of cases) {
      const result = spawnSync(process.execPath, ["tools/release/validate-system-release-manifest.mjs", ...args], { encoding: "utf8" });
      assert.equal(result.status, 1);
      assert.equal(result.stdout, "");
      assert.equal(result.stderr, `system-release-manifest: invalid\n${message}\n`);
      assert.doesNotMatch(result.stderr, /TOP_SECRET_MANIFEST_BODY|release-manifest-test/);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("CLI require-decision GO rejects NO_GO and accepts GO", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "release-manifest-decision-"));
  const manifestPath = path.join(directory, "system-release-manifest.json");
  try {
    const manifest = validManifest();
    manifest.decision = "NO_GO";
    writeFileSync(manifestPath, JSON.stringify(manifest));
    const rejected = spawnSync(process.execPath, [
      "tools/release/validate-system-release-manifest.mjs",
      "--manifest", manifestPath,
      "--require-decision", "GO",
    ], { encoding: "utf8" });
    assert.equal(rejected.status, 1);
    assert.equal(rejected.stdout, "");
    assert.equal(rejected.stderr, "system-release-manifest: invalid\ndecision must be GO\n");

    manifest.decision = "GO";
    writeFileSync(manifestPath, JSON.stringify(manifest));
    const accepted = spawnSync(process.execPath, [
      "tools/release/validate-system-release-manifest.mjs",
      "--manifest", manifestPath,
      "--require-decision", "GO",
    ], { encoding: "utf8" });
    assert.equal(accepted.status, 0, accepted.stderr);
    assert.equal(accepted.stdout, `system-release-manifest: OK ${manifest.productReleaseId}\n`);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
