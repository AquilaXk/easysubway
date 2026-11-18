import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

import { fetchDatapackCandidateOciHandoff } from "./fetch-datapack-candidate-oci-handoff.mjs";

const sha = (value) => createHash("sha256").update(value).digest("hex");
const bytes = (value) => Buffer.from(JSON.stringify(value));
const identity = {
  repository: "AquilaXk/easysubway-data",
  workflowRunId: "42",
  headSha: "a".repeat(40),
  candidateId: "candidate-1",
  artifactName: "easysubway-datapack-candidate-42",
};
const storage = { namespace: "namespace", bucket: "candidate-private" };

test("handoff schema는 storage와 six-field identity만 허용한다", () => {
  const schema = JSON.parse(readFileSync("contracts/release/datapack-candidate-oci-handoff.schema.json", "utf8"));
  assert.deepEqual(schema.required, ["storage", "identity"]);
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.identity.required, ["repository", "workflowRunId", "headSha", "candidateId", "artifactName", "artifactId"]);
  assert.equal(schema.properties.identity.additionalProperties, false);
});

test("six-field identity and descriptor-first OCI object-set을 fail-closed로 소비한다", async () => {
  const fixture = makeFixture();
  const result = await fetchDatapackCandidateOciHandoff({ ...fixture.input, fetchImpl: fixture.fetch });
  assert.deepEqual(result.decision, "GO", JSON.stringify(result));
  assert.equal(result.artifactReuseCount, 0);
  assert.deepEqual(fixture.calls, [fixture.descriptorKey, ...fixture.objectKeys]);
  assert.equal(result.output.descriptorLocator, `oci://${storage.namespace}/${storage.bucket}/${fixture.descriptorKey}`);
});

test("missing/type/identity mismatch는 OCI GET 0이며 descriptor 실패는 payload GET 0이다", async () => {
  for (const input of [
    { storage, identity: { ...identity, artifactId: "z".repeat(64) } },
    { storage, identity: { ...identity, artifactId: "0".repeat(64), workflowRunId: 42 } },
  ]) {
    const calls = [];
    const result = await fetchDatapackCandidateOciHandoff({ ...input, fetchImpl: async (key) => { calls.push(key); return { status: 404, body: Buffer.alloc(0) }; } });
    assert.deepEqual(result, { decision: "NO_GO", reasonCode: "INVALID_INPUT", artifactReuseCount: 0, output: null });
    assert.deepEqual(calls, []);
  }
  for (const mutate of [
    (descriptor) => { descriptor.objects[0].ociUri = "oci://other/bucket/key"; },
    (descriptor) => { descriptor.objects[0].objectKey = "wrong"; },
    (descriptor) => { descriptor.expiresAt = "2026-08-23T00:00:00.000Z"; },
  ]) {
    const fixture = makeFixture(mutate);
    const result = await fetchDatapackCandidateOciHandoff({ ...fixture.input, fetchImpl: fixture.fetch });
    assert.equal(result.decision, "NO_GO");
    assert.deepEqual(fixture.calls, [fixture.descriptorKey]);
  }
});

test("duplicate/missing/extra/traversal paths와 object size/hash·inventory/component/tuple drift는 output 0이다", async () => {
  for (const mutate of [
    (descriptor) => { descriptor.objects[1].path = descriptor.objects[0].path; },
    (descriptor) => { descriptor.objects[0].path = "../escape"; },
    (descriptor) => { descriptor.objects.pop(); },
    (descriptor) => { descriptor.objects.push({ ...descriptor.objects[0], path: "extra.json", objectKey: descriptor.objects[0].objectKey.replace("catalog/current.json", "extra.json"), ociUri: descriptor.objects[0].ociUri.replace("catalog/current.json", "extra.json") }); },
    (_descriptor, objects) => { objects.set("catalog/current.json", Buffer.from("drift")); },
    (_descriptor, objects) => { objects.set("datapack-candidate-tuple.json", bytes({ candidateBinding: { candidateId: "other", buildSpecSha256: "b".repeat(64), manifestSha256: "c".repeat(64) }, freshnessExpiresAt: "2026-08-25T00:00:00.000Z" })); },
  ]) {
    const fixture = makeFixture(mutate);
    const result = await fetchDatapackCandidateOciHandoff({ ...fixture.input, fetchImpl: fixture.fetch });
    assert.deepEqual(result.output, null);
    assert.equal(result.artifactReuseCount, 0);
  }
});

function makeFixture(mutate = null) {
  const manifest = Buffer.from("manifest\n");
  const tuple = bytes({ candidateBinding: { candidateId: identity.candidateId, buildSpecSha256: "b".repeat(64), manifestSha256: sha(manifest) }, freshnessExpiresAt: "2026-08-25T00:00:00.000Z" });
  const component = bytes({ schemaVersion: 1, component: "data", repository: identity.repository, gitSha: identity.headSha, workflowRunId: identity.workflowRunId, dataVersion: "1", releaseSequence: 1, manifestSha256: sha(manifest), provenance: {}, artifactInventorySha256: "", contractVersion: "datapack-contract-v3", issueRef: "AquilaXk/easysubway-data#529" });
  const objects = new Map([["catalog/current.json", manifest], ["datapack-candidate-tuple.json", tuple]]);
  const inventory = bytes({ schemaVersion: 1, artifactKind: "datapack-candidate-inventory", entries: [...objects].map(([path, value]) => ({ path, sizeBytes: value.length, sha256: sha(value) })) });
  const finalComponent = bytes({ ...JSON.parse(component), artifactInventorySha256: sha(inventory) });
  objects.set("data-artifact-inventory.json", inventory); objects.set("data-component-manifest.json", finalComponent);
  const prefix = `candidates/v1/runs/${identity.workflowRunId}/heads/${identity.headSha}/candidates/${identity.candidateId}/`;
  const descriptor = { schemaVersion: 1, artifactKind: "datapack-candidate-oci-artifact-descriptor", repository: identity.repository, workflowRunId: identity.workflowRunId, headSha: identity.headSha, artifactName: identity.artifactName, candidateBinding: JSON.parse(tuple).candidateBinding, freshnessExpiresAt: "2026-08-25T00:00:00.000Z", createdAt: "2026-08-24T00:00:00.000Z", expiresAt: "2026-08-25T00:00:00.000Z", inventory: entry("data-artifact-inventory.json", inventory), component: entry("data-component-manifest.json", finalComponent), tuple: entry("datapack-candidate-tuple.json", tuple), objects: [...objects].sort(([left], [right]) => Buffer.compare(Buffer.from(left), Buffer.from(right))).map(([path, value]) => ({ ...entry(path, value), objectKey: `${prefix}objects/${sha(value)}/${path}`, ociUri: `oci://${storage.namespace}/${storage.bucket}/${prefix}objects/${sha(value)}/${path}` })) };
  mutate?.(descriptor, objects);
  const descriptorBytes = bytes(descriptor); const artifactId = sha(descriptorBytes);
  const descriptorKey = `${prefix}descriptors/${artifactId}.json`; const calls = [];
  return { input: { storage, identity: { ...identity, artifactId }, now: "2026-08-24T12:00:00.000Z" }, descriptorKey, objectKeys: descriptor.objects.map(({ objectKey }) => objectKey), calls, fetch: async (key) => { calls.push(key); return key === descriptorKey ? { status: 200, body: descriptorBytes } : objects.has(keyFrom(descriptor, key)) ? { status: 200, body: objects.get(keyFrom(descriptor, key)) } : { status: 404, body: Buffer.alloc(0) }; } };
}
function entry(path, value) { return { path, sizeBytes: value.length, sha256: sha(value) }; }
function keyFrom(descriptor, key) { return descriptor.objects.find((item) => item.objectKey === key)?.path; }
