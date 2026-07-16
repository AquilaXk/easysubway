import assert from "node:assert/strict";
import { createServer } from "node:http";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { sendReleaseCallback } from "./send-release-callback.mjs";
import { buildReleaseCallback } from "./build-release-callback.mjs";

const secret = "callback-secret-never-log";
const token = "bearer-token-never-log";
const payload = {
  schemaVersion: 2,
  artifactKind: "datapack-release-callback",
  releaseRequestId: "req-2057",
  releaseSequence: 42,
  channel: "production",
  manifestSha256: "a".repeat(64),
  idempotencyKey: `req-2057:42:${"a".repeat(64)}`,
  callbackVerifier: { kind: "payload-signature", value: secret },
};

async function withServer(handler, callback) {
  const server = createServer(handler);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await callback(`http://127.0.0.1:${server.address().port}/callback`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("500 뒤 재시도해 전달하고 artifact에서 secret을 제거한다", async () => {
  let requests = 0;
  await withServer((request, response) => {
    requests += 1;
    response.writeHead(requests === 1 ? 500 : 200).end();
  }, async (endpoint) => {
    const slept = [];
    const artifact = await sendReleaseCallback({
      payload,
      endpoint,
      token,
      retryDelaysSeconds: [60, 480, 3600],
      sleep: async (seconds) => slept.push(seconds),
    });

    assert.equal(artifact.state, "DELIVERED");
    assert.equal(artifact.attempts.length, 2);
    assert.deepEqual(slept, [60]);
    assert.equal(artifact.attempts[0].httpClass, "5XX");
    const serialized = JSON.stringify(artifact);
    assert.equal(serialized.includes(secret), false);
    assert.equal(serialized.includes(token), false);
    assert.equal(serialized.includes("Authorization"), false);
  });
});

test("400은 재시도하지 않고 reconciliation 대상으로 남긴다", async () => {
  await withServer((_request, response) => response.writeHead(400).end(), async (endpoint) => {
    const artifact = await sendReleaseCallback({ payload, endpoint, token, sleep: async () => {} });
    assert.equal(artifact.state, "RECONCILIATION_REQUIRED");
    assert.equal(artifact.attempts.length, 1);
    assert.equal(artifact.attempts[0].httpClass, "4XX");
  });
});

test("Bearer 전송 전 non-loopback HTTP endpoint를 거부한다", async () => {
  await assert.rejects(
    sendReleaseCallback({ payload, endpoint: "http://example.com/callback", token }),
    /must use HTTPS/,
  );
});

test("callback producer는 safe integer가 아닌 release sequence를 거부한다", () => {
  assert.throws(() => buildReleaseCallback({
    RELEASE_SEQUENCE: "9007199254740992",
  }), /positive safe integer/);
});

test("callback producer는 서명 전 required gate와 hash를 검증한다", () => {
  const env = {
    RELEASE_SEQUENCE: "42",
    RELEASE_REQUEST_ID: "req-2057",
    TARGET_CHANNEL: "production",
    WORKFLOW_RUN_URL: "https://github.com/AquilaXk/easysubway/actions/runs/1",
    MANIFEST_SHA256: "a".repeat(64),
    SQLITE_SHA256: "b".repeat(64),
    GZIP_SHA256: "c".repeat(64),
    EVIDENCE_BUNDLE_SHA256: "d".repeat(64),
    VALIDATOR_STATUS: "PASS",
    ROUTE_REGRESSION_STATUS: "PASS",
    PUBLISH_STATUS: "PASS",
    EASYSUBWAY_DATAPACK_CALLBACK_HMAC_KEY: secret,
  };
  assert.equal(buildReleaseCallback(env).releaseRequestId, "req-2057");
  assert.throws(() => buildReleaseCallback({ ...env, MANIFEST_SHA256: "invalid" }), /SHA-256/);
  assert.throws(() => buildReleaseCallback({ ...env, VALIDATOR_STATUS: "UNKNOWN" }), /is invalid/);
});

test("transient failure를 모두 소진하면 bounded retry 계획을 기록한다", async () => {
  await withServer((_request, response) => response.writeHead(503).end(), async (endpoint) => {
    const slept = [];
    const artifact = await sendReleaseCallback({
      payload,
      endpoint,
      token,
      retryDelaysSeconds: [60, 480, 3600],
      sleep: async (seconds) => slept.push(seconds),
    });
    assert.equal(artifact.state, "RECONCILIATION_REQUIRED");
    assert.equal(artifact.attempts.length, 4);
    assert.deepEqual(slept, [60, 480, 3600]);
  });
});

test("CLI는 delivery state를 GitHub output에 기록한다", async () => {
  await withServer((_request, response) => response.writeHead(200).end(), async (endpoint) => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "callback-sender-"));
    const payloadPath = path.join(directory, "payload.json");
    const artifactPath = path.join(directory, "delivery.json");
    const githubOutputPath = path.join(directory, "github-output");
    await writeFile(payloadPath, JSON.stringify(payload));

    const exitCode = await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [
        new URL("./send-release-callback.mjs", import.meta.url).pathname,
        "--payload", payloadPath,
        "--output", artifactPath,
        "--github-output", githubOutputPath,
      ], {
        env: {
          ...process.env,
          EASYSUBWAY_DATAPACK_CALLBACK_URL: endpoint,
          EASYSUBWAY_DATAPACK_WORKFLOW_TOKEN: token,
        },
      });
      child.once("error", reject);
      child.once("exit", resolve);
    });

    assert.equal(exitCode, 0);
    assert.equal(await readFile(githubOutputPath, "utf8"), "state=DELIVERED\n");
    assert.equal(JSON.parse(await readFile(artifactPath, "utf8")).state, "DELIVERED");
  });
});

test("CLI는 terminal failure를 exit 2와 reconciliation output으로 기록한다", async () => {
  await withServer((_request, response) => response.writeHead(400).end(), async (endpoint) => {
    const directory = await mkdtemp(path.join(os.tmpdir(), "callback-sender-failure-"));
    const payloadPath = path.join(directory, "payload.json");
    const artifactPath = path.join(directory, "delivery.json");
    const githubOutputPath = path.join(directory, "github-output");
    await writeFile(payloadPath, JSON.stringify(payload));

    const exitCode = await new Promise((resolve, reject) => {
      const child = spawn(process.execPath, [
        new URL("./send-release-callback.mjs", import.meta.url).pathname,
        "--payload", payloadPath,
        "--output", artifactPath,
        "--github-output", githubOutputPath,
      ], {
        env: {
          ...process.env,
          EASYSUBWAY_DATAPACK_CALLBACK_URL: endpoint,
          EASYSUBWAY_DATAPACK_WORKFLOW_TOKEN: token,
        },
      });
      child.once("error", reject);
      child.once("exit", resolve);
    });

    assert.equal(exitCode, 2);
    assert.equal(await readFile(githubOutputPath, "utf8"), "state=RECONCILIATION_REQUIRED\n");
    assert.equal(JSON.parse(await readFile(artifactPath, "utf8")).state, "RECONCILIATION_REQUIRED");
  });
});
