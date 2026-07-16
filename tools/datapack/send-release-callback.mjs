#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";

export const CALLBACK_RETRY_DELAYS_SECONDS = [60, 480, 3600];

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const httpClass = (status) => `${Math.floor(status / 100)}XX`;
const retryable = (status) => status === 408 || status === 429 || status >= 500;

export async function sendReleaseCallback({
  payload,
  endpoint,
  token,
  retryDelaysSeconds = CALLBACK_RETRY_DELAYS_SECONDS,
  sleep = (seconds) => new Promise((resolve) => setTimeout(resolve, seconds * 1000)),
  fetchImpl = fetch,
}) {
  const payloadBytes = JSON.stringify(payload);
  const artifact = {
    schemaVersion: 1,
    artifactKind: "datapack-release-callback-delivery",
    idempotencyKey: payload.idempotencyKey,
    payloadSha256: sha256(payloadBytes),
    signatureSha256: sha256(payload.callbackVerifier?.value ?? ""),
    attempts: [],
    state: "PENDING",
  };

  for (let index = 0; index <= retryDelaysSeconds.length; index += 1) {
    let status;
    try {
      const response = await fetchImpl(endpoint, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: payloadBytes,
        signal: AbortSignal.timeout(15_000),
      });
      status = response.status;
      artifact.attempts.push({
        attempt: index + 1,
        httpClass: httpClass(status),
        ...(retryable(status) && index < retryDelaysSeconds.length
          ? { nextRetrySeconds: retryDelaysSeconds[index] }
          : {}),
      });
      if (response.ok) {
        artifact.state = "DELIVERED";
        return artifact;
      }
      if (!retryable(status)) break;
    } catch {
      artifact.attempts.push({
        attempt: index + 1,
        httpClass: "NETWORK",
        ...(index < retryDelaysSeconds.length
          ? { nextRetrySeconds: retryDelaysSeconds[index] }
          : {}),
      });
    }
    if (index < retryDelaysSeconds.length) await sleep(retryDelaysSeconds[index]);
  }

  artifact.state = "RECONCILIATION_REQUIRED";
  return artifact;
}

async function main() {
  const { values } = parseArgs({
    options: {
      payload: { type: "string" },
      output: { type: "string" },
    },
  });
  if (!values.payload || !values.output) throw new Error("--payload and --output are required");
  const endpoint = process.env.EASYSUBWAY_DATAPACK_CALLBACK_URL;
  const token = process.env.EASYSUBWAY_DATAPACK_WORKFLOW_TOKEN;
  if (!endpoint || !token) throw new Error("callback endpoint/token env is required");
  const artifact = await sendReleaseCallback({
    payload: JSON.parse(await readFile(values.payload, "utf8")),
    endpoint,
    token,
  });
  await writeFile(values.output, `${JSON.stringify(artifact, null, 2)}\n`);
  if (artifact.state !== "DELIVERED") process.exitCode = 2;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
