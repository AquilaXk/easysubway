import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";

import { probeTagoTrainProvider } from "./probe-tago-train-provider.mjs";

async function withServer(handler, run) {
  const server = http.createServer(handler);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address();
  try {
    await run(`http://127.0.0.1:${port}/`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("TAGO provider probe accepts HTTP success, resultCode 00, and city schema without exposing the key", async () => {
  await withServer((request, response) => {
    const url = new URL(request.url, "http://localhost");
    assert.equal(url.pathname, "/GetCtyCodeList");
    assert.equal(url.searchParams.get("serviceKey"), "encoded+secret");
    response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({
      response: {
        header: { resultCode: "00", resultMsg: "NORMAL SERVICE." },
        body: { items: { item: [{ citycode: "11", cityname: "서울특별시" }] } },
      },
    }));
  }, async (baseUrl) => {
    const result = await probeTagoTrainProvider({
      serviceKey: "encoded%2Bsecret",
      baseUrl,
      timeoutMs: 1000,
    });
    assert.deepEqual(result, { result: "PASS", operation: "GetCtyCodeList", validRows: 1 });
    assert.doesNotMatch(JSON.stringify(result), /encoded|secret|serviceKey/);
  });
});

test("TAGO provider probe fails closed for missing credentials and provider errors", async () => {
  await assert.rejects(
    probeTagoTrainProvider({ serviceKey: "", baseUrl: "https://example.invalid/" }),
    /EASYSUBWAY_TAGO_TRAIN_SERVICE_KEY env is required/,
  );
  await withServer((_request, response) => {
    response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({
      response: { header: { resultCode: "30" }, body: { items: { item: [] } } },
    }));
  }, async (baseUrl) => {
    await assert.rejects(
      probeTagoTrainProvider({ serviceKey: "never-print-this", baseUrl, timeoutMs: 1000 }),
      (error) => {
        assert.match(error.message, /provider resultCode was not 00/);
        assert.doesNotMatch(error.message, /never-print-this/);
        return true;
      },
    );
  });
});

test("TAGO provider probe retries one transient HTTP failure within the bounded check", async () => {
  let calls = 0;
  await withServer((_request, response) => {
    calls += 1;
    if (calls === 1) {
      response.writeHead(503).end("unavailable");
      return;
    }
    response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify({
      response: {
        header: { resultCode: "00" },
        body: { items: { item: { citycode: "11", cityname: "서울특별시" } } },
      },
    }));
  }, async (baseUrl) => {
    const result = await probeTagoTrainProvider({ serviceKey: "key", baseUrl, timeoutMs: 1000 });
    assert.equal(result.result, "PASS");
    assert.equal(calls, 2);
  });
});
