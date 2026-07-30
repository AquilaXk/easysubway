#!/usr/bin/env node

import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

const outputFiles = [
  "mobile-component-manifest.json",
  "backend-component-manifest.json",
  "data-component-manifest.json",
  "platform-component-manifest.json",
  "contracts-identity.json",
];
const issueRefPattern = /^AquilaXk\/(easysubway|easysubway-data|easysubway-platform|easysubway-backend|easysubway-mobile)#[1-9][0-9]*$/;
const semverPattern = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/;

function fail(message) {
  throw new Error(message);
}

function parseArgs(args) {
  if (args.length % 2 !== 0) fail("arguments must be option/value pairs");
  const values = {};
  for (let index = 0; index < args.length; index += 2) {
    const [option, value] = [args[index], args[index + 1]];
    if (!option.startsWith("--") || !value || Object.hasOwn(values, option)) fail("invalid arguments");
    values[option] = value;
  }
  const required = [
    "--repository", "--git-sha", "--mobile-version-name", "--mobile-version-code", "--aab", "--bundled-data-manifest",
    "--backend-image-inspect", "--backend-evidence", "--data-version", "--data-release-sequence", "--data-manifest",
    "--source-snapshot-evidence", "--platform-environment", "--platform-evidence", "--contracts-version", "--contracts-bundle",
    "--issue-ref", "--output-dir",
  ];
  if (Object.keys(values).length !== required.length || required.some((option) => !Object.hasOwn(values, option))) fail("invalid arguments");
  return values;
}

function sha256File(file, label) {
  try {
    return createHash("sha256").update(readFileSync(file)).digest("hex");
  } catch {
    fail(`${label} is unreadable`);
  }
}

function parseInteger(value, name, minimum) {
  if (!/^(0|[1-9][0-9]*)$/.test(value)) fail(`${name} must be an integer`);
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < minimum) fail(`${name} is out of range`);
  return parsed;
}

function imageDigest(inspectPath) {
  let inspect;
  try {
    inspect = JSON.parse(readFileSync(inspectPath, "utf8"));
  } catch {
    fail("backend image inspect is unreadable or invalid JSON");
  }
  if (Array.isArray(inspect)) {
    if (inspect.length !== 1) fail("backend image inspect must contain one image");
    inspect = inspect[0];
  }
  if (!inspect || typeof inspect !== "object" || Array.isArray(inspect)) fail("backend image inspect must be an object");
  const repoDigest = typeof inspect.RepoDigests?.[0] === "string"
    ? inspect.RepoDigests[0].match(/^.+@(sha256:[a-f0-9]{64})$/)?.[1]
    : null;
  if (repoDigest) return repoDigest;
  if (typeof inspect.Id === "string" && /^sha256:[a-f0-9]{64}$/.test(inspect.Id)) return inspect.Id;
  fail("backend image inspect lacks an immutable digest");
}

function validateComponent(component, schema) {
  const errors = validateSchema(schema, component).errors;
  if (errors.length > 0) fail(`component manifest validation failed: ${errors.join(", ")}`);
}

function writeOutput(outputDir, documents) {
  const parent = path.dirname(outputDir);
  if (!existsSync(parent)) fail("output parent directory does not exist");
  const temporary = mkdtempSync(path.join(parent, `.${path.basename(outputDir)}.tmp-`));
  try {
    for (const [name, document] of documents) writeFileSync(path.join(temporary, name), `${JSON.stringify(document, null, 2)}\n`);
    if (outputFiles.some((name) => !existsSync(path.join(temporary, name)))) fail("output write failed");
    symlinkSync(path.basename(temporary), outputDir, "dir");
  } catch (error) {
    rmSync(temporary, { recursive: true, force: true });
    throw error;
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args["--repository"] !== "AquilaXk/easysubway") fail("repository must be AquilaXk/easysubway");
  if (!/^[a-f0-9]{40}$/.test(args["--git-sha"])) fail("git sha must be 40 lowercase hex characters");
  if (!args["--mobile-version-name"]) fail("mobile version name is required");
  if (!args["--data-version"]) fail("data version is required");
  if (!semverPattern.test(args["--contracts-version"])) fail("contracts version must be SemVer");
  if (!issueRefPattern.test(args["--issue-ref"])) fail("issue ref is invalid");
  if (!["ci", "staging", "production"].includes(args["--platform-environment"])) fail("platform environment is invalid");

  const versionCode = parseInteger(args["--mobile-version-code"], "mobile version code", 1);
  const releaseSequence = parseInteger(args["--data-release-sequence"], "data release sequence", 0);
  const aabSha256 = sha256File(args["--aab"], "AAB");
  const bundledDataManifestSha256 = sha256File(args["--bundled-data-manifest"], "bundled data manifest");
  const dataManifestSha256 = sha256File(args["--data-manifest"], "data manifest");
  if (bundledDataManifestSha256 !== dataManifestSha256) fail("bundled data manifest hash mismatch");
  const backendEvidenceSha256 = sha256File(args["--backend-evidence"], "backend evidence");
  const sourceEvidenceSha256 = sha256File(args["--source-snapshot-evidence"], "source snapshot evidence");
  const platformEvidenceSha256 = sha256File(args["--platform-evidence"], "platform evidence");
  const contractsSha256 = sha256File(args["--contracts-bundle"], "contracts bundle");
  const digest = imageDigest(args["--backend-image-inspect"]);
  const common = { schemaVersion: 1, repository: args["--repository"], gitSha: args["--git-sha"], contractVersion: args["--contracts-version"], issueRefs: [args["--issue-ref"]] };
  const mobile = {
    ...common, component: "mobile",
    artifactIdentity: { versionName: args["--mobile-version-name"], versionCode, aabSha256, bundledDataManifestSha256 },
    evidenceSha256: aabSha256,
  };
  const backend = {
    ...common, component: "backend",
    artifactIdentity: { imageDigest: digest, apiContractVersion: args["--contracts-version"] },
    evidenceSha256: backendEvidenceSha256,
  };
  const data = {
    ...common, component: "data",
    artifactIdentity: { dataVersion: args["--data-version"], releaseSequence, manifestSha256: dataManifestSha256, sourceSnapshotSetHash: sourceEvidenceSha256 },
    evidenceSha256: sourceEvidenceSha256,
  };
  const platform = {
    ...common, component: "platform",
    artifactIdentity: { environment: args["--platform-environment"], deployedImageDigest: digest, deploymentEvidenceSha256: platformEvidenceSha256 },
    evidenceSha256: platformEvidenceSha256,
  };
  let componentSchema;
  try {
    componentSchema = JSON.parse(readFileSync(path.resolve("contracts/release/component-manifest.schema.json"), "utf8"));
  } catch {
    fail("component manifest schema is unavailable");
  }
  for (const component of [mobile, backend, data, platform]) validateComponent(component, componentSchema);
  writeOutput(args["--output-dir"], [
    ["mobile-component-manifest.json", mobile],
    ["backend-component-manifest.json", backend],
    ["data-component-manifest.json", data],
    ["platform-component-manifest.json", platform],
    ["contracts-identity.json", { version: args["--contracts-version"], sha256: contractsSha256 }],
  ]);
}

try {
  main();
} catch (error) {
  process.stderr.write(`build-monorepo-component-manifests: ${error.message}\n`);
  process.exitCode = 1;
}
