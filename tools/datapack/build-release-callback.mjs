#!/usr/bin/env node
// #1694 Part C: 게시 결과에서 release-callback payload를 만들고 HMAC-SHA256 서명한다.
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

export function buildReleaseCallback(e) {
  const releaseSequence = Number(e.RELEASE_SEQUENCE);
  if (!Number.isSafeInteger(releaseSequence) || releaseSequence < 1) {
    throw new Error("RELEASE_SEQUENCE must be a positive safe integer");
  }
  const fields = {
    schemaVersion: 2,
    artifactKind: "datapack-release-callback",
    releaseRequestId: e.RELEASE_REQUEST_ID,
    releaseSequence,
    channel: e.TARGET_CHANNEL,
    workflowRunUrl: e.WORKFLOW_RUN_URL,
    manifestSha256: e.MANIFEST_SHA256,
    sqliteSha256: e.SQLITE_SHA256,
    gzipSha256: e.GZIP_SHA256,
    evidenceBundleSha256: e.EVIDENCE_BUNDLE_SHA256,
    validatorStatus: e.VALIDATOR_STATUS,
    routeRegressionStatus: e.ROUTE_REGRESSION_STATUS,
    publishStatus: e.PUBLISH_STATUS,
  };
  fields.idempotencyKey = `${fields.releaseRequestId}:${fields.releaseSequence}:${fields.manifestSha256}`;
  const order = ["schemaVersion","artifactKind","releaseRequestId","releaseSequence","channel","idempotencyKey","workflowRunUrl","manifestSha256",
    "sqliteSha256","gzipSha256","evidenceBundleSha256","validatorStatus","routeRegressionStatus","publishStatus"];
  const message = order.map((k) => String(fields[k])).join("\n");
  const value = crypto.createHmac("sha256", e.EASYSUBWAY_DATAPACK_CALLBACK_HMAC_KEY || "")
    .update(message, "utf8").digest("hex");

  return { ...fields, callbackVerifier: { kind: "payload-signature", value } };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  try {
    process.stdout.write(JSON.stringify(buildReleaseCallback(process.env)));
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
