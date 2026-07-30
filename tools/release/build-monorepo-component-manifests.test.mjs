import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const script = path.resolve("tools/release/build-monorepo-component-manifests.mjs");
const gitSha = "a".repeat(40);
const imageDigest = `sha256:${"b".repeat(64)}`;
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

function fixture() {
  const directory = mkdtempSync(path.join(os.tmpdir(), "component-manifests-"));
  const file = (name, content) => {
    const target = path.join(directory, name);
    writeFileSync(target, content);
    return target;
  };
  return {
    directory,
    aab: file("app.aab", "android bundle bytes"),
    dataManifest: file("data-manifest.json", "{\"data\":true}\n"),
    backendInspect: file("backend-inspect.json", JSON.stringify([{ RepoDigests: [`registry.example/easysubway@${imageDigest}`] }])),
    backendEvidence: file("backend-evidence.json", "backend evidence"),
    sourceEvidence: file("source-evidence.json", "source evidence"),
    platformEvidence: file("platform-evidence.json", "platform evidence"),
    contractsBundle: file("contracts.tgz", "contracts bundle"),
    output: path.join(directory, "output"),
  };
}

function args(files, overrides = {}) {
  const values = {
    "--repository": "AquilaXk/easysubway",
    "--git-sha": gitSha,
    "--mobile-version-name": "2.3.4",
    "--mobile-version-code": "17",
    "--aab": files.aab,
    "--bundled-data-manifest": files.dataManifest,
    "--backend-image-inspect": files.backendInspect,
    "--backend-evidence": files.backendEvidence,
    "--data-version": "2026.07.30",
    "--data-release-sequence": "0",
    "--data-manifest": files.dataManifest,
    "--source-snapshot-evidence": files.sourceEvidence,
    "--platform-environment": "ci",
    "--platform-evidence": files.platformEvidence,
    "--contracts-version": "1.2.3",
    "--contracts-bundle": files.contractsBundle,
    "--issue-ref": "AquilaXk/easysubway#2693",
    "--output-dir": files.output,
    ...overrides,
  };
  return Object.entries(values).flat();
}

function runArguments(arguments_) {
  return spawnSync(process.execPath, [script, ...arguments_], { encoding: "utf8" });
}

function run(files, overrides, extra = []) {
  return runArguments([...args(files, overrides), ...extra]);
}

test("builds deterministic truthful monorepo component manifests", () => {
  const files = fixture();
  try {
    const result = run(files);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(lstatSync(files.output).isSymbolicLink(), true);
    assert.deepEqual(requireFiles(files.output), [
      "backend-component-manifest.json", "contracts-identity.json", "data-component-manifest.json",
      "mobile-component-manifest.json", "platform-component-manifest.json",
    ]);
    const mobile = json(files.output, "mobile-component-manifest.json");
    const backend = json(files.output, "backend-component-manifest.json");
    const data = json(files.output, "data-component-manifest.json");
    const platform = json(files.output, "platform-component-manifest.json");
    assert.deepEqual(mobile, {
      schemaVersion: 1, component: "mobile", repository: "AquilaXk/easysubway", gitSha,
      artifactIdentity: { versionName: "2.3.4", versionCode: 17, aabSha256: sha256("android bundle bytes"), bundledDataManifestSha256: sha256("{\"data\":true}\n") },
      contractVersion: "1.2.3", evidenceSha256: sha256("android bundle bytes"), issueRefs: ["AquilaXk/easysubway#2693"],
    });
    assert.equal(backend.artifactIdentity.imageDigest, imageDigest);
    assert.equal(backend.artifactIdentity.apiContractVersion, "1.2.3");
    assert.equal(backend.evidenceSha256, sha256("backend evidence"));
    assert.equal(data.artifactIdentity.manifestSha256, mobile.artifactIdentity.bundledDataManifestSha256);
    assert.equal(data.artifactIdentity.sourceSnapshotSetHash, sha256("source evidence"));
    assert.equal(data.evidenceSha256, sha256("source evidence"));
    assert.equal(platform.artifactIdentity.environment, "ci");
    assert.equal(platform.artifactIdentity.deployedImageDigest, imageDigest);
    assert.equal(platform.artifactIdentity.deploymentEvidenceSha256, sha256("platform evidence"));
    assert.equal(platform.evidenceSha256, sha256("platform evidence"));
    assert.deepEqual(json(files.output, "contracts-identity.json"), { version: "1.2.3", sha256: sha256("contracts bundle") });
    for (const name of requireFiles(files.output)) assert.match(readFileSync(path.join(files.output, name), "utf8"), /\n$/);
    const secondOutput = path.join(files.directory, "output-second");
    assert.equal(run(files, { "--output-dir": secondOutput }).status, 0);
    for (const name of requireFiles(files.output)) {
      assert.deepEqual(readFileSync(path.join(files.output, name)), readFileSync(path.join(secondOutput, name)), name);
    }
  } finally {
    rmSync(files.directory, { recursive: true, force: true });
  }
});

test("accepts object-form immutable Id fallback and rejects mutable Docker identity", () => {
  const files = fixture();
  try {
    writeFileSync(files.backendInspect, JSON.stringify({ RepoDigests: ["registry.example/easysubway:latest"], Id: imageDigest }));
    assert.equal(run(files).status, 0);
    assert.equal(json(files.output, "backend-component-manifest.json").artifactIdentity.imageDigest, imageDigest);
    const absent = fixture();
    try {
      writeFileSync(absent.backendInspect, JSON.stringify({ Id: imageDigest }));
      assert.equal(run(absent).status, 0);
    } finally {
      rmSync(absent.directory, { recursive: true, force: true });
    }
    const mutable = fixture();
    try {
      writeFileSync(mutable.backendInspect, JSON.stringify({ RepoDigests: ["registry.example/easysubway:latest"], Id: "sha256:latest" }));
      assert.notEqual(run(mutable).status, 0);
      assert.equal(requireFiles(mutable.output), null);
    } finally {
      rmSync(mutable.directory, { recursive: true, force: true });
    }
  } finally {
    rmSync(files.directory, { recursive: true, force: true });
  }
});

test("rejects version bounds and mismatched bundled data manifests", () => {
  const files = fixture();
  try {
    assert.notEqual(run(files, { "--mobile-version-code": "0" }).status, 0);
    assert.notEqual(run(files, { "--data-release-sequence": "-1" }).status, 0);
    const otherManifest = path.join(files.directory, "different-data-manifest.json");
    writeFileSync(otherManifest, "different manifest");
    assert.notEqual(run(files, { "--bundled-data-manifest": otherManifest }).status, 0);
    assert.equal(requireFiles(files.output), null);
  } finally {
    rmSync(files.directory, { recursive: true, force: true });
  }
});

test("preserves an existing output directory and rejects required CLI boundaries", () => {
  const files = fixture();
  try {
    mkdirSync(files.output);
    const sentinel = path.join(files.output, "sentinel");
    writeFileSync(sentinel, "preserve me");
    assert.notEqual(run(files).status, 0);
    assert.equal(readFileSync(sentinel, "utf8"), "preserve me");
    assert.equal(readdirSync(files.directory).some((name) => name.startsWith(".output.tmp-")), false);
    const base = args(files, { "--output-dir": path.join(files.directory, "boundary-output") });
    const without = (option) => {
      const index = base.indexOf(option);
      return [...base.slice(0, index), ...base.slice(index + 2)];
    };
    for (const [name, arguments_] of [
      ["missing option", without("--aab")],
      ["extraneous option", [...base, "--extra", "x"]],
      ["repository", args(files, { "--repository": "AquilaXk/other", "--output-dir": path.join(files.directory, "repository") })],
      ["git SHA", args(files, { "--git-sha": "A".repeat(40), "--output-dir": path.join(files.directory, "git") })],
      ["platform environment", args(files, { "--platform-environment": "dev", "--output-dir": path.join(files.directory, "environment") })],
      ["SemVer", args(files, { "--contracts-version": "1.2", "--output-dir": path.join(files.directory, "semver") })],
      ["issueRef", args(files, { "--issue-ref": "2693", "--output-dir": path.join(files.directory, "issue") })],
    ]) assert.notEqual(runArguments(arguments_).status, 0, name);
  } finally {
    rmSync(files.directory, { recursive: true, force: true });
  }
});

function json(directory, name) {
  return JSON.parse(readFileSync(path.join(directory, name), "utf8"));
}

function requireFiles(directory) {
  try {
    return readdirSync(directory).sort();
  } catch {
    return null;
  }
}
