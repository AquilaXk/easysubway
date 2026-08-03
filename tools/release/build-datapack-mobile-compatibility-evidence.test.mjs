import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import { buildEvidence } from "./build-datapack-mobile-compatibility-evidence.mjs";

test("candidate manifest와 mobile compatibility matrix를 exact component에 결속한다", () => {
  const manifestBytes = Buffer.from(JSON.stringify({
    manifestVersion: 2,
    keyId: "production-v1",
    packs: [{ schemaVersion: "1" }],
  }));
  const component = {
    schemaVersion: 1, component: "data", repository: "AquilaXk/easysubway-data", gitSha: "a".repeat(40),
    workflowRunId: "123", dataVersion: "2026.07.30", releaseSequence: 1,
    manifestSha256: createHash("sha256").update(manifestBytes).digest("hex"),
    provenance: { sourceSnapshotSetHash: "b".repeat(64) }, artifactInventorySha256: "c".repeat(64),
    contractVersion: "datapack-contract-v3", issueRef: "AquilaXk/easysubway#2705",
  };
  const matrix = { schemaVersion: 1, mobile: [{
    appVersionRange: ">=1.0.0", acceptsIndexSchemaVersions: [1],
    acceptsManifestSchemaVersions: [1], acceptsSigningKeyIds: ["production-v1"],
  }] };

  assert.deepEqual(buildEvidence({ component, manifestBytes, matrix, appVersion: "1.0.5+10006" }), {
    schemaVersion: 1, artifactKind: "datapack-mobile-compatibility-evidence", decision: "PASS", candidate: component,
  });
  assert.throws(() => buildEvidence({
    component: { ...component, manifestSha256: "d".repeat(64) }, manifestBytes, matrix, appVersion: "1.0.5+10006",
  }), /incompatible/);
  assert.throws(() => buildEvidence({
    component, manifestBytes, matrix: { ...matrix, mobile: [{ ...matrix.mobile[0], acceptsSigningKeyIds: [] }] },
    appVersion: "1.0.5+10006",
  }), /incompatible/);
});
