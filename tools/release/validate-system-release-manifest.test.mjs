import assert from "node:assert/strict";
import test from "node:test";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  calculateGovernanceRevision,
  calculateProductIdentity,
  classifySystemReleaseChange,
  selectSystemReleaseDecision,
  validateGovernanceInventory,
  validateSystemReleaseManifest,
} from "./validate-system-release-manifest.mjs";

const sha = "a".repeat(64);
const gitSha = "b".repeat(40);
const issue = (repository, number) => `AquilaXk/${repository}#${number}`;
const zeroFallbackSuccessCounters = () => ({
  hubSource: 0,
  legacy: 0,
  local: 0,
  routeV1: 0,
  routeV2: 0,
  stale: 0,
  previous: 0,
  alternateProvider: 0,
  bestEffort: 0,
});

const governanceInventory = JSON.parse(readFileSync(
  "contracts/release/system-release-governance-inventory.json",
  "utf8",
));

function validManifest() {
  const manifest = {
    schemaVersion: 4,
    productReleaseId: "easysubway-2026.07.30.1",
    phase: "FINAL",
    decision: "GO",
    generatedAt: "2026-07-30T00:00:00Z",
    issueRefs: [issue("easysubway", 2693)],
    hubObservedRevision: { repository: "AquilaXk/easysubway", gitSha },
    contracts: { version: "1.2.3", sha256: sha },
    journeyV3: {
      executionMode: "SERVER_ONLY",
      owner: {
        repository: "AquilaXk/easysubway-backend",
        gitSha,
        apiContractVersion: "api-v1",
      },
      evidenceSha256: sha,
      fallbackSuccessCounters: zeroFallbackSuccessCounters(),
    },
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
  manifest.productIdentitySha256 = calculateProductIdentity(manifest);
  manifest.governanceRevisionSha256 = calculateGovernanceRevision(governanceInventory);
  return manifest;
}

const schemas = {
  componentSchema: JSON.parse(readFileSync("contracts/release/component-manifest.schema.json", "utf8")),
  systemSchema: JSON.parse(readFileSync("contracts/release/system-release-manifest.schema.json", "utf8")),
  issueRefSchema: JSON.parse(readFileSync("contracts/release/issue-ref.schema.json", "utf8")),
  governanceInventorySchema: JSON.parse(readFileSync(
    "contracts/release/system-release-governance-inventory.schema.json",
    "utf8",
  )),
  governanceInventory,
};

const classifierInputs = {
  componentSchema: schemas.componentSchema,
  systemSchema: schemas.systemSchema,
  issueRefSchema: schemas.issueRefSchema,
  governanceInventorySchema: schemas.governanceInventorySchema,
  previousGovernanceInventory: governanceInventory,
  currentGovernanceInventory: governanceInventory,
  repoRoot: process.cwd(),
};

test("system release manifest v4 validates the separated product, governance and observation identities", () => {
  assert.deepEqual(validateSystemReleaseManifest({ manifest: validManifest(), ...schemas }), []);
});

test("system release manifest v4 rejects invalid contracts SemVer", () => {
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

test("system release GO requires typed Journey V3 server-only evidence while NO_GO may wait for receipts", () => {
  const missing = validManifest();
  delete missing.journeyV3;
  assert.ok(validateSystemReleaseManifest({ manifest: missing, ...schemas })
    .includes("system: GO requires Journey V3 server-only evidence"));
  assert.equal(selectSystemReleaseDecision({ legacyDecision: "GO", manifest: missing, ...schemas }), "NO_GO");

  missing.decision = "NO_GO";
  missing.productIdentitySha256 = calculateProductIdentity(missing);
  assert.deepEqual(validateSystemReleaseManifest({ manifest: missing, ...schemas }), []);
});

test("system release GO rejects Journey V3 policy, owner, identity and fallback drift", () => {
  for (const [name, mutate, expected] of [
    ["execution mode", (manifest) => { manifest.journeyV3.executionMode = "CLIENT_FALLBACK"; }, "system: Journey V3 execution mode must be SERVER_ONLY"],
    ["owner repository", (manifest) => { manifest.journeyV3.owner.repository = "AquilaXk/easysubway"; }, "system: Journey V3 owner repository must be canonical backend"],
    ["owner git SHA", (manifest) => { manifest.journeyV3.owner.gitSha = "c".repeat(40); }, "system: Journey V3 owner git SHA must match backend component"],
    ["API contract", (manifest) => { manifest.journeyV3.owner.apiContractVersion = "api-v2"; }, "system: Journey V3 API contract must match backend component"],
    ["evidence SHA", (manifest) => { manifest.journeyV3.evidenceSha256 = "invalid"; }, "system: Journey V3 evidence SHA-256 must be lowercase hex digest"],
    ["fallback success", (manifest) => { manifest.journeyV3.fallbackSuccessCounters.local = 1; }, "system: Journey V3 local fallback success count must be zero"],
  ]) {
    const manifest = validManifest();
    mutate(manifest);
    const errors = validateSystemReleaseManifest({ manifest, ...schemas });
    assert.ok(errors.length > 0, name);
    assert.ok(errors.includes(expected), name);
    assert.equal(selectSystemReleaseDecision({ legacyDecision: "GO", manifest, ...schemas }), "NO_GO", name);
  }
});

test("system release manifest v4 rejects every locked identity violation", () => {
  const cases = [
    ["legacy v2", (manifest) => { manifest.schemaVersion = 2; }],
    ["legacy v3", (manifest) => { manifest.schemaVersion = 3; }],
    ["missing observed identity", (manifest) => { delete manifest.hubObservedRevision; }],
    ["missing observed SHA", (manifest) => { delete manifest.hubObservedRevision.gitSha; }],
    ["wrong observed repository", (manifest) => { manifest.hubObservedRevision.repository = "AquilaXk/easysubway-backend"; }],
    ["uppercase observed SHA", (manifest) => { manifest.hubObservedRevision.gitSha = gitSha.toUpperCase(); }],
    ["short observed SHA", (manifest) => { manifest.hubObservedRevision.gitSha = "b".repeat(39); }],
    ["extra observed identity field", (manifest) => { manifest.hubObservedRevision.ref = "main"; }],
    ["top-level gitSha", (manifest) => { manifest.gitSha = gitSha; }],
    ["missing product identity", (manifest) => { delete manifest.productIdentitySha256; }],
    ["stale product identity", (manifest) => { manifest.productIdentitySha256 = "c".repeat(64); }],
    ["missing governance revision", (manifest) => { delete manifest.governanceRevisionSha256; }],
    ["stale governance revision", (manifest) => { manifest.governanceRevisionSha256 = "c".repeat(64); }],
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

test("system release manifest v4 rejects unsafe identity integers", () => {
  for (const [mutate, expected] of [
    [(manifest) => { manifest.mobile.artifactIdentity.versionCode = Number.MAX_SAFE_INTEGER + 1; }, "mobile: versionCode must be a safe integer"],
    [(manifest) => { manifest.data.artifactIdentity.releaseSequence = Number.MAX_SAFE_INTEGER + 1; }, "data: releaseSequence must be a safe integer"],
  ]) {
    const manifest = validManifest();
    mutate(manifest);
    manifest.productIdentitySha256 = calculateProductIdentity(manifest);
    assert.deepEqual(validateSystemReleaseManifest({ manifest, ...schemas }), [expected]);
  }
});

test("system release v4 change classification separates product, governance and observation changes", () => {
  const previous = validManifest();

  const issueOnly = structuredClone(previous);
  issueOnly.issueRefs = [issue("easysubway", 2840)];
  assert.throws(
    () => classifySystemReleaseChange({ previousManifest: previous, currentManifest: issueOnly, ...classifierInputs }),
    /no classified identity difference/,
  );

  const product = structuredClone(previous);
  product.mobile.artifactIdentity.aabSha256 = "c".repeat(64);
  product.productIdentitySha256 = calculateProductIdentity(product);
  assert.equal(classifySystemReleaseChange({ previousManifest: previous, currentManifest: product, ...classifierInputs }), "PRODUCT_CHANGE");

  const governance = structuredClone(previous);
  const changedInventory = structuredClone(governanceInventory);
  changedInventory.files[0].sha256 = "c".repeat(64);
  governance.governanceRevisionSha256 = calculateGovernanceRevision(changedInventory);
  const { repoRoot: ignoredRepoRoot, ...governanceClassifierInputs } = classifierInputs;
  assert.equal(classifySystemReleaseChange({
    previousManifest: previous,
    currentManifest: governance,
    ...governanceClassifierInputs,
    currentGovernanceInventory: changedInventory,
  }), "GOVERNANCE_CHANGE");

  const observation = structuredClone(previous);
  observation.hubObservedRevision.gitSha = "c".repeat(40);
  assert.equal(classifySystemReleaseChange({ previousManifest: previous, currentManifest: observation, ...classifierInputs }), "OBSERVATION_ONLY_CHANGE");

  for (const mutate of [
    (manifest) => { manifest.schemaVersion = 3; },
    (manifest) => { manifest.productIdentitySha256 = "c".repeat(64); },
  ]) {
    const malformed = structuredClone(previous);
    mutate(malformed);
    assert.throws(
      () => classifySystemReleaseChange({ previousManifest: previous, currentManifest: malformed, ...classifierInputs }),
      /current system release manifest is invalid/,
    );
  }
});

test("system release v4 rejects open, duplicated, or mismatched governance inventory", () => {
  for (const mutate of [
    (inventory) => { inventory.files.pop(); },
    (inventory) => { inventory.files[4].path = inventory.files[3].path; },
  ]) {
    const inventory = structuredClone(governanceInventory);
    mutate(inventory);
    const manifest = validManifest();
    manifest.governanceRevisionSha256 = calculateGovernanceRevision(inventory);
    const errors = validateSystemReleaseManifest({
      manifest,
      ...schemas,
      governanceInventory: inventory,
    });
    assert.ok(errors.some((error) => error.startsWith("governance inventory:")));
  }

  const mismatched = structuredClone(governanceInventory);
  mismatched.files[0].sha256 = "c".repeat(64);
  assert.ok(validateGovernanceInventory({
    governanceInventory: mismatched,
    repoRoot: process.cwd(),
  }).some((error) => error.includes("SHA-256 mismatch")));
});

test("system release v4 rejects a governance inventory symlink before hashing", () => {
  const directory = mkdtempSync(path.join(tmpdir(), "release-governance-inventory-"));
  const entry = governanceInventory.files[0];
  const inventoryPath = path.join(directory, entry.path);
  try {
    mkdirSync(path.dirname(inventoryPath), { recursive: true });
    writeFileSync(path.join(directory, "target"), "not a release schema");
    symlinkSync(path.join(directory, "target"), inventoryPath);
    assert.ok(validateGovernanceInventory({
      governanceInventory,
      governanceInventorySchema: schemas.governanceInventorySchema,
      repoRoot: directory,
    }).includes(`governance inventory: tracked path must be a regular file: ${entry.path}`));
  } finally {
    rmSync(directory, { recursive: true, force: true });
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
