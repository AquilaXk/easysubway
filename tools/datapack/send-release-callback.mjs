#!/usr/bin/env node
import { createHash } from "node:crypto";
import { appendFile, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { canonicalCallbackMessage } from "./build-release-callback.mjs";

export const CALLBACK_RETRY_DELAYS_SECONDS = [60, 480, 3600];

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const httpClass = (status) => `${Math.floor(status / 100)}XX`;
const retryable = (status) => status === 408 || status === 429 || status >= 500;

function validatedEndpoint(value) {
  const url = new URL(value);
  const loopback = url.hostname === "localhost" || url.hostname === "127.0.0.1" || url.hostname === "[::1]";
  if (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) {
    throw new Error("callback endpoint must use HTTPS except for loopback testing");
  }
  return url.toString();
}

export async function sendReleaseCallback({
  payload,
  endpoint,
  token,
  retryDelaysSeconds = CALLBACK_RETRY_DELAYS_SECONDS,
  sleep = (seconds) => new Promise((resolve) => setTimeout(resolve, seconds * 1000)),
  fetchImpl = fetch,
}) {
  endpoint = validatedEndpoint(endpoint);
  const payloadBytes = JSON.stringify(payload);
  const artifact = {
    schemaVersion: 1,
    artifactKind: "datapack-release-callback-delivery",
    idempotencyKey: payload.idempotencyKey,
    payloadSha256: sha256(canonicalCallbackMessage(payload)),
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
  const { payloadPath, outputPath, githubOutputPath } = runnerPaths(process.env);
  const endpoint = process.env.EASYSUBWAY_DATAPACK_CALLBACK_URL;
  const token = process.env.EASYSUBWAY_DATAPACK_WORKFLOW_TOKEN;
  if (!endpoint || !token) throw new Error("callback endpoint/token env is required");
  const artifact = await sendReleaseCallback({
    payload: JSON.parse(await readFile(payloadPath, "utf8")),
    endpoint,
    token,
  });
  await writeFile(outputPath, `${JSON.stringify(artifact, null, 2)}\n`);
  await appendFile(githubOutputPath, `state=${artifact.state}\n`);
  if (artifact.state !== "DELIVERED") process.exitCode = 2;
}

function runnerPaths(env) {
  if (!env.RUNNER_TEMP || !env.GITHUB_OUTPUT) {
    throw new Error("RUNNER_TEMP and GITHUB_OUTPUT are required");
  }
  const runnerTemp = path.resolve(env.RUNNER_TEMP);
  const githubOutputPath = path.resolve(env.GITHUB_OUTPUT);
  const relativeGithubOutput = path.relative(runnerTemp, githubOutputPath);
  if (relativeGithubOutput === "" || relativeGithubOutput === ".."
    || relativeGithubOutput.startsWith(`..${path.sep}`) || path.isAbsolute(relativeGithubOutput)) {
    throw new Error("GITHUB_OUTPUT must be inside RUNNER_TEMP");
  }
  const stage = path.join(runnerTemp, "easysubway-datapack-stage");
  return {
    payloadPath: path.join(stage, "release-callback.json"),
    outputPath: path.join(stage, "release-callback-delivery.json"),
    githubOutputPath,
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
