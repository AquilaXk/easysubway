import { createHash } from "node:crypto";

const sha = (value) => createHash("sha256").update(value).digest("hex");
const noGo = (reasonCode) => ({ decision: "NO_GO", reasonCode, artifactReuseCount: 0, output: null });
const compare = (left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right));

// fetchImpl is deliberately injected: Phase 1 has no runtime, workflow, or network wiring.
export async function fetchDatapackCandidateOciHandoff({ storage, identity, fetchImpl, now }) {
  try {
    const input = validateInput(storage, identity, fetchImpl, now);
    const descriptorKey = `${input.prefix}descriptors/${input.identity.artifactId}.json`;
    const descriptorResponse = await fetchObject(fetchImpl, descriptorKey);
    if (sha(descriptorResponse) !== input.identity.artifactId) return noGo("DESCRIPTOR_HASH_MISMATCH");
    const descriptor = parse(descriptorResponse, "descriptor");
    const checked = validateDescriptor(descriptor, input);
    const bodies = new Map();
    for (const item of checked.objects) {
      const body = await fetchObject(fetchImpl, item.objectKey);
      if (body.length !== item.sizeBytes || sha(body) !== item.sha256) return noGo("OBJECT_BYTES_MISMATCH");
      bodies.set(item.path, body);
    }
    validateBindings(checked, bodies);
    return {
      decision: "GO",
      reasonCode: "NONE",
      artifactReuseCount: 0,
      output: {
        descriptorLocator: `oci://${input.storage.namespace}/${input.storage.bucket}/${descriptorKey}`,
        descriptor: descriptorResponse,
        objects: checked.objects.map(({ path, objectKey, ociUri, sizeBytes, sha256 }) => ({ path, objectKey, ociUri, sizeBytes, sha256, body: bodies.get(path) })),
      },
    };
  } catch (error) {
    return noGo(error.code ?? "DESCRIPTOR_REJECTED");
  }
}

function validateInput(storage, identity, fetchImpl, now) {
  exactKeys(storage, ["namespace", "bucket"], "storage");
  exactKeys(identity, ["repository", "workflowRunId", "headSha", "candidateId", "artifactName", "artifactId"], "identity");
  if (typeof fetchImpl !== "function") fail("INVALID_INPUT");
  const checkedStorage = { namespace: segment(storage.namespace), bucket: segment(storage.bucket) };
  const checkedIdentity = {
    repository: exact(identity.repository, "AquilaXk/easysubway-data"),
    workflowRunId: decimal(identity.workflowRunId), headSha: gitSha(identity.headSha), candidateId: token(identity.candidateId), artifactName: required(identity.artifactName), artifactId: hash(identity.artifactId),
  };
  if (checkedIdentity.artifactName !== `easysubway-datapack-candidate-${checkedIdentity.workflowRunId}`) fail("INVALID_INPUT");
  const instant = utc(now);
  return { storage: checkedStorage, identity: checkedIdentity, now: Date.parse(instant), prefix: `candidates/v1/runs/${checkedIdentity.workflowRunId}/heads/${checkedIdentity.headSha}/candidates/${checkedIdentity.candidateId}/` };
}

function validateDescriptor(value, input) {
  exactKeys(value, ["schemaVersion", "artifactKind", "repository", "workflowRunId", "headSha", "artifactName", "candidateBinding", "freshnessExpiresAt", "createdAt", "expiresAt", "inventory", "component", "tuple", "objects"], "descriptor");
  if (value.schemaVersion !== 1 || value.artifactKind !== "datapack-candidate-oci-artifact-descriptor" || value.repository !== input.identity.repository || value.workflowRunId !== input.identity.workflowRunId || value.headSha !== input.identity.headSha || value.artifactName !== input.identity.artifactName) fail("DESCRIPTOR_IDENTITY_MISMATCH");
  exactKeys(value.candidateBinding, ["candidateId", "buildSpecSha256", "manifestSha256"], "candidateBinding");
  if (token(value.candidateBinding.candidateId) !== input.identity.candidateId) fail("DESCRIPTOR_IDENTITY_MISMATCH");
  hash(value.candidateBinding.buildSpecSha256); hash(value.candidateBinding.manifestSha256);
  const createdAt = Date.parse(utc(value.createdAt)); const freshnessExpiresAt = Date.parse(utc(value.freshnessExpiresAt)); const expiresAt = Date.parse(utc(value.expiresAt));
  if (createdAt >= freshnessExpiresAt || expiresAt !== Math.min(createdAt + 14 * 86400000, freshnessExpiresAt) || expiresAt <= input.now || freshnessExpiresAt <= input.now) fail("DESCRIPTOR_EXPIRED");
  const metadata = { inventory: file(value.inventory), component: file(value.component), tuple: file(value.tuple) };
  if (new Set(Object.values(metadata).map(({ path }) => path)).size !== 3 || !Array.isArray(value.objects) || value.objects.length === 0) fail("DESCRIPTOR_OBJECT_SET_INVALID");
  const paths = new Set(); const keys = new Set(); let previous = null;
  const objects = value.objects.map((raw) => {
    exactKeys(raw, ["path", "objectKey", "ociUri", "sizeBytes", "sha256"], "object");
    const item = { ...file({ path: raw.path, sizeBytes: raw.sizeBytes, sha256: raw.sha256 }), objectKey: required(raw.objectKey), ociUri: required(raw.ociUri) };
    if (!item.objectKey.startsWith(`${input.prefix}objects/${item.sha256}/`) || item.objectKey !== `${input.prefix}objects/${item.sha256}/${item.path}` || paths.has(item.path) || keys.has(item.objectKey) || (previous !== null && compare(previous, item.path) >= 0)) fail("DESCRIPTOR_OBJECT_SET_INVALID");
    const locator = /^oci:\/\/([a-z0-9][a-z0-9-]{0,62})\/([a-z0-9][a-z0-9-]{0,62})\/(.+)$/.exec(item.ociUri);
    if (!locator || locator[1] !== input.storage.namespace || locator[2] !== input.storage.bucket || locator[3] !== item.objectKey) fail("DESCRIPTOR_LOCATOR_MISMATCH");
    paths.add(item.path); keys.add(item.objectKey); previous = item.path; return item;
  });
  for (const item of Object.values(metadata)) if (!paths.has(item.path)) fail("DESCRIPTOR_OBJECT_SET_INVALID");
  return { value, metadata, objects };
}

function validateBindings(checked, bodies) {
  const { value, metadata, objects } = checked;
  const inventoryBytes = bodies.get(metadata.inventory.path); const componentBytes = bodies.get(metadata.component.path); const tupleBytes = bodies.get(metadata.tuple.path);
  if (!inventoryBytes || !componentBytes || !tupleBytes) fail("BINDING_MISMATCH");
  const inventory = parse(inventoryBytes, "inventory"); const component = parse(componentBytes, "component"); const tuple = parse(tupleBytes, "tuple");
  exactKeys(inventory, ["schemaVersion", "artifactKind", "entries"], "inventory");
  if (inventory.schemaVersion !== 1 || inventory.artifactKind !== "datapack-candidate-inventory" || !Array.isArray(inventory.entries)) fail("BINDING_MISMATCH");
  const declared = new Map();
  for (const raw of inventory.entries) { const item = file(raw); if (declared.has(item.path) || item.path === metadata.inventory.path || item.path === metadata.component.path) fail("BINDING_MISMATCH"); declared.set(item.path, item); }
  const expected = new Map([...declared, [metadata.inventory.path, metadata.inventory], [metadata.component.path, metadata.component]]);
  if (expected.size !== objects.length) fail("BINDING_MISMATCH");
  for (const item of objects) { const expectedItem = expected.get(item.path); if (!expectedItem || expectedItem.sizeBytes !== item.sizeBytes || expectedItem.sha256 !== item.sha256) fail("BINDING_MISMATCH"); }
  exactKeys(component, ["schemaVersion", "component", "repository", "gitSha", "workflowRunId", "dataVersion", "releaseSequence", "manifestSha256", "provenance", "artifactInventorySha256", "contractVersion", "issueRef"], "component");
  if (component.schemaVersion !== 1 || component.component !== "data" || component.repository !== value.repository || component.gitSha !== value.headSha || component.workflowRunId !== value.workflowRunId || component.manifestSha256 !== value.candidateBinding.manifestSha256 || component.artifactInventorySha256 !== sha(inventoryBytes)) fail("BINDING_MISMATCH");
  exactKeys(tuple, ["candidateBinding", "freshnessExpiresAt"], "tuple");
  exactKeys(tuple.candidateBinding, ["candidateId", "buildSpecSha256", "manifestSha256"], "tuple.candidateBinding");
  if (tuple.candidateBinding.candidateId !== value.candidateBinding.candidateId || tuple.candidateBinding.buildSpecSha256 !== value.candidateBinding.buildSpecSha256 || tuple.candidateBinding.manifestSha256 !== value.candidateBinding.manifestSha256 || tuple.freshnessExpiresAt !== value.freshnessExpiresAt) fail("BINDING_MISMATCH");
}

async function fetchObject(fetchImpl, key) { const response = await fetchImpl(key); if (!response || response.status !== 200 || !Buffer.isBuffer(response.body)) fail("OCI_GET_FAILED"); return response.body; }
function parse(bytes, label) { try { const value = JSON.parse(bytes.toString("utf8")); if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(); return value; } catch { fail(`${label.toUpperCase()}_INVALID`); } }
function file(value) { exactKeys(value, ["path", "sizeBytes", "sha256"], "file"); return { path: safePath(value.path), sizeBytes: size(value.sizeBytes), sha256: hash(value.sha256) }; }
function exactKeys(value, keys, label) { if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).sort(compare).join("\0") !== [...keys].sort(compare).join("\0")) fail(`${label.toUpperCase()}_FIELDS_INVALID`); }
function required(value) { if (typeof value !== "string" || value.length === 0 || value.trim() !== value) fail("INVALID_INPUT"); return value; }
function exact(value, expected) { if (value !== expected) fail("INVALID_INPUT"); return value; }
function segment(value) { const result = required(value); if (!/^[a-z0-9][a-z0-9-]{0,62}$/.test(result)) fail("INVALID_INPUT"); return result; }
function decimal(value) { const result = required(value); if (!/^[1-9][0-9]*$/.test(result)) fail("INVALID_INPUT"); return result; }
function gitSha(value) { const result = required(value); if (!/^[a-f0-9]{40}$/.test(result)) fail("INVALID_INPUT"); return result; }
function token(value) { const result = required(value); if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(result)) fail("INVALID_INPUT"); return result; }
function hash(value) { const result = required(value); if (!/^[a-f0-9]{64}$/.test(result)) fail("INVALID_INPUT"); return result; }
function size(value) { if (!Number.isSafeInteger(value) || value < 1) fail("DESCRIPTOR_REJECTED"); return value; }
function safePath(value) { const result = required(value); if (result.startsWith("/") || result.split("/").some((part) => part === "" || part === "." || part === "..")) fail("DESCRIPTOR_REJECTED"); return result; }
function utc(value) { const result = required(value); if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(result) || new Date(result).toISOString() !== result) fail("INVALID_INPUT"); return result; }
function fail(code) { const error = new Error(code); error.code = code; throw error; }
