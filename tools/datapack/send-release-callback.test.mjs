import assert from "node:assert/strict";
import { createServer } from "node:http";
import test from "node:test";
import { sendReleaseCallback } from "./send-release-callback.mjs";

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
