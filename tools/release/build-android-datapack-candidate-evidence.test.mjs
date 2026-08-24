import assert from "node:assert/strict";
import test from "node:test";
import { buildAndroidDatapackCandidateEvidence } from "./build-android-datapack-candidate-evidence.mjs";

const hash = "a".repeat(64);
function input() { return {
  candidate: { candidateBinding: { candidateId: "nationwide@1", buildSpecSha256: hash, manifestSha256: hash }, freshnessExpiresAt: "2026-08-25T00:00:00.000Z" },
  mobileIdentity: { gitSha: "b".repeat(40), androidApplicationId: "com.easysubway.app", versionCode: 1, aabSha256: hash, aabPayloadSha256: hash, dataPackManifestSha256: hash },
  actionsArtifact: { repository: "AquilaXk/easysubway", workflowPath: ".github/workflows/release-artifacts.yml", runId: 1, artifactId: 2, artifactName: "android", archiveDigest: `sha256:${hash}`, headSha: "b".repeat(40), createdAt: "2026-08-24T00:00:00.000Z", expiresAt: "2026-09-24T00:00:00.000Z" },
  ociReceipt: { namespace: "namespace", bucket: "release", objectKey: `android/${hash}.json`, objectUri: `oci://namespace/release/android/${hash}.json`, objectSha256: hash, byteSize: 1, putAt: "2026-08-24T00:00:00.000Z", getAt: "2026-08-24T00:00:01.000Z", getSha256: hash, getByteSize: 1, createOnly: true },
}; }

test("exact candidate, AAB and OCI full-readback receipt becomes a deterministic handoff", () => {
  const output = buildAndroidDatapackCandidateEvidence({ ...input(), now: "2026-08-24T00:00:00.000Z" });
  assert.equal(output.artifactKind, "android-datapack-candidate-evidence");
  assert.equal(output.candidateBinding.candidateId, "nationwide@1");
  assert.match(output.receiptSha256, /^[a-f0-9]{64}$/);
});

for (const [name, mutate, expected] of [
  ["expired candidate", (value) => { value.candidate.freshnessExpiresAt = "2026-08-23T00:00:00.000Z"; }, /expired/],
  ["candidate manifest drift", (value) => { value.mobileIdentity.dataPackManifestSha256 = "c".repeat(64); }, /does not bind/],
  ["mutable locator", (value) => { value.ociReceipt.objectUri = "https://example.invalid/current"; }, /invalid or mutable/],
  ["partial GET", (value) => { value.ociReceipt.getByteSize = 2; }, /full GET/],
  ["non-create-only receipt", (value) => { value.ociReceipt.createOnly = false; }, /create-only/],
  ["secret-shaped extra field", (value) => { value.ociReceipt.authorization = "secret"; }, /invalid field set/],
]) test(`${name} fails closed`, () => {
  const value = input(); mutate(value);
  assert.throws(() => buildAndroidDatapackCandidateEvidence({ ...value, now: "2026-08-24T00:00:00.000Z" }), expected);
});
