#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";

const SHA256 = /^[a-f0-9]{64}$/;
const SHA40 = /^[a-f0-9]{40}$/;
const OCI_URI = /^oci:\/\/([^/]+)\/([^/]+)\/([A-Za-z0-9][A-Za-z0-9._/-]*)$/;

const required = (value, name) => {
  if (value === undefined || value === null || value === "") throw new Error(`${name} is required`);
  return value;
};
const sha = (value, name) => {
  if (!SHA256.test(required(value, name))) throw new Error(`${name} must be sha256`);
  return value;
};
const timestamp = (value, name) => {
  if (!Number.isFinite(Date.parse(required(value, name)))) throw new Error(`${name} must be an ISO timestamp`);
  return value;
};
const exactObject = (value, fields, name) => {
  if (!value || typeof value !== "object" || Array.isArray(value)
    || Object.keys(value).length !== fields.length || fields.some((field) => !Object.hasOwn(value, field))) {
    throw new Error(`${name} has an invalid field set`);
  }
  return value;
};
const canonical = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};
const digest = (value) => createHash("sha256").update(canonical(value)).digest("hex");

export function buildAndroidDatapackCandidateEvidence({ candidate, mobileIdentity, actionsArtifact, ociReceipt, now = new Date() }) {
  exactObject(candidate, ["candidateBinding", "freshnessExpiresAt"], "candidate");
  const binding = candidate.candidateBinding;
  exactObject(binding, ["candidateId", "buildSpecSha256", "manifestSha256"], "candidateBinding");
  for (const field of ["candidateId", "buildSpecSha256", "manifestSha256"]) required(binding[field], `candidateBinding.${field}`);
  sha(binding.buildSpecSha256, "candidateBinding.buildSpecSha256");
  sha(binding.manifestSha256, "candidateBinding.manifestSha256");
  const freshnessExpiresAt = timestamp(candidate.freshnessExpiresAt, "freshnessExpiresAt");
  if (Date.parse(freshnessExpiresAt) <= new Date(now).getTime()) throw new Error("candidate evidence is expired");

  exactObject(mobileIdentity, ["gitSha", "androidApplicationId", "versionCode", "aabSha256", "aabPayloadSha256", "dataPackManifestSha256"], "mobileIdentity");
  if (!SHA40.test(required(mobileIdentity.gitSha, "mobileIdentity.gitSha"))) throw new Error("mobileIdentity.gitSha must be a full git SHA");
  if (mobileIdentity.androidApplicationId !== "com.easysubway.app") throw new Error("mobileIdentity.androidApplicationId is invalid");
  if (!Number.isInteger(mobileIdentity.versionCode) || mobileIdentity.versionCode < 1) throw new Error("mobileIdentity.versionCode must be positive");
  for (const field of ["aabSha256", "aabPayloadSha256", "dataPackManifestSha256"]) sha(mobileIdentity[field], `mobileIdentity.${field}`);
  if (mobileIdentity.dataPackManifestSha256 !== binding.manifestSha256) throw new Error("mobile identity does not bind the candidate manifest");

  exactObject(actionsArtifact, ["repository", "workflowPath", "runId", "artifactId", "artifactName", "archiveDigest", "headSha", "createdAt", "expiresAt"], "actionsArtifact");
  if (actionsArtifact.repository !== "AquilaXk/easysubway" || actionsArtifact.workflowPath !== ".github/workflows/release-artifacts.yml") throw new Error("actions artifact source is invalid");
  if (!Number.isInteger(actionsArtifact.runId) || actionsArtifact.runId < 1 || !Number.isInteger(actionsArtifact.artifactId) || actionsArtifact.artifactId < 1) throw new Error("actions artifact identity is invalid");
  if (typeof actionsArtifact.artifactName !== "string" || actionsArtifact.artifactName.length === 0) throw new Error("actions artifact name is invalid");
  sha(actionsArtifact.archiveDigest?.replace(/^sha256:/, ""), "actionsArtifact.archiveDigest");
  if (!SHA40.test(required(actionsArtifact.headSha, "actionsArtifact.headSha")) || actionsArtifact.headSha !== mobileIdentity.gitSha) throw new Error("actions artifact head must match mobile identity");
  timestamp(actionsArtifact.createdAt, "actionsArtifact.createdAt"); timestamp(actionsArtifact.expiresAt, "actionsArtifact.expiresAt");

  exactObject(ociReceipt, ["namespace", "bucket", "objectKey", "objectUri", "objectSha256", "byteSize", "putAt", "getAt", "getSha256", "getByteSize", "createOnly"], "ociReceipt");
  const match = OCI_URI.exec(required(ociReceipt.objectUri, "ociReceipt.objectUri"));
  if (!match || ociReceipt.namespace !== match[1] || ociReceipt.bucket !== match[2] || ociReceipt.objectKey !== match[3]) throw new Error("OCI receipt locator is invalid or mutable");
  if (ociReceipt.createOnly !== true) throw new Error("OCI receipt must prove create-only publication");
  sha(ociReceipt.objectSha256, "ociReceipt.objectSha256");
  if (!Number.isInteger(ociReceipt.byteSize) || ociReceipt.byteSize < 1) throw new Error("ociReceipt.byteSize must be positive");
  timestamp(ociReceipt.putAt, "ociReceipt.putAt"); timestamp(ociReceipt.getAt, "ociReceipt.getAt");
  if (ociReceipt.getSha256 !== ociReceipt.objectSha256 || ociReceipt.getByteSize !== ociReceipt.byteSize) throw new Error("OCI full GET receipt does not match PUT object bytes");

  const body = {
    schemaVersion: 1,
    artifactKind: "android-datapack-candidate-evidence",
    candidateBinding: { candidateId: binding.candidateId, buildSpecSha256: binding.buildSpecSha256, manifestSha256: binding.manifestSha256 },
    freshnessExpiresAt,
    mobileIdentity: { ...mobileIdentity },
    sourceActionsArtifact: { ...actionsArtifact },
    oci: { ...ociReceipt },
  };
  return { ...body, receiptSha256: digest(body) };
}

async function main(argv) {
  if (argv.length !== 4 || argv[0] !== "--input" || argv[2] !== "--output") throw new Error("usage: --input <json> --output <json>");
  const input = JSON.parse(await readFile(argv[1], "utf8"));
  const output = buildAndroidDatapackCandidateEvidence(input);
  await writeFile(argv[3], `${JSON.stringify(output, null, 2)}\n`, { flag: "wx" });
}

if (import.meta.url === `file://${process.argv[1]}`) main(process.argv.slice(2)).catch((error) => { console.error(error.message); process.exitCode = 1; });
