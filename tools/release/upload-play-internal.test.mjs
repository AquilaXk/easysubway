import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { runUploadPlayInternal } from "./upload-play-internal.mjs";

const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });

function serviceAccountEnv() {
  const serviceAccount = {
    client_email: "uploader@easysubway.iam.gserviceaccount.com",
    private_key: privateKey.export({ type: "pkcs8", format: "pem" }),
    token_uri: "https://oauth2.example/token",
  };
  return `EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app\nEASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=${JSON.stringify(serviceAccount)}\n`;
}

function jsonResponse(status, body) {
  const text = JSON.stringify(body);
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
    text: async () => text,
  };
}

// Builds a mock Android Publisher API. `tracks` is the existing track list, and
// `overrides` can force specific endpoints (e.g. an auth failure).
function mockPlay({ tracks = [], uploadedVersionCode = "10005", overrides = {} } = {}) {
  const requests = [];
  const fetchImpl = async (url, options = {}) => {
    const method = options.method ?? "GET";
    requests.push({ url, method });
    if (overrides.token && url.includes("/token")) return overrides.token;
    if (url.includes("/token")) return jsonResponse(200, { access_token: "token-123" });
    if (url.endsWith("/edits") && method === "POST") return jsonResponse(200, { id: "edit-1" });
    if (url.endsWith("/tracks") && method === "GET") return jsonResponse(200, { tracks });
    if (url.includes("/bundles?uploadType=media")) return jsonResponse(200, { versionCode: uploadedVersionCode });
    if (url.includes("/deobfuscationFiles/")) return jsonResponse(200, {});
    if (url.includes("/tracks/") && method === "PUT") return jsonResponse(200, { track: "internal" });
    if (url.includes(":commit")) return jsonResponse(200, {});
    return jsonResponse(404, { error: { status: "NOT_FOUND", message: url } });
  };
  return { fetchImpl, requests };
}

async function withFiles(fn) {
  const dir = await mkdtemp(path.join(tmpdir(), "play-upload-"));
  const envFile = path.join(dir, "env");
  const aabPath = path.join(dir, "app.aab");
  const mappingPath = path.join(dir, "mapping.txt");
  const reportPath = path.join(dir, "evidence.json");
  await writeFile(envFile, serviceAccountEnv());
  await writeFile(aabPath, "fake-aab-bytes");
  await writeFile(mappingPath, "fake-mapping");
  return fn({ envFile, aabPath, mappingPath, reportPath });
}

test("uploads an AAB and mapping to the internal track and emits evidence", async () => {
  await withFiles(async ({ envFile, aabPath, mappingPath, reportPath }) => {
    const { fetchImpl, requests } = mockPlay({ tracks: [], uploadedVersionCode: "10005" });
    const evidence = await runUploadPlayInternal({
      envFile,
      aabPath,
      mappingPath,
      versionCode: "10005",
      reportPath,
      apiBaseUrl: "https://api.example/v3",
      uploadBaseUrl: "https://upload.example/v3",
      fetchImpl,
    });

    assert.equal(evidence.versionCode, "10005");
    assert.equal(evidence.track, "internal");
    assert.equal(evidence.editId, "edit-1");
    assert.equal(evidence.packageName, "com.easysubway.app");
    assert.match(evidence.aabSha256, /^[0-9a-f]{64}$/);
    assert.match(evidence.mappingSha256, /^[0-9a-f]{64}$/);

    const flow = requests.map((request) => `${request.method} ${request.url.replace(/^https:\/\/[^/]+/, "")}`);
    assert.ok(flow.some((entry) => entry.includes("/bundles?uploadType=media")));
    assert.ok(flow.some((entry) => entry.includes("/deobfuscationFiles/10005/proguard")));
    assert.ok(flow.some((entry) => entry.startsWith("PUT ") && entry.includes("/tracks/internal")));
    assert.ok(flow.some((entry) => entry.includes(":commit?changesNotSentForReview=false")));
  });
});

test("rejects a versionCode that is not greater than the current Play max before uploading", async () => {
  await withFiles(async ({ envFile, aabPath, mappingPath, reportPath }) => {
    const tracks = [{ track: "internal", releases: [{ status: "completed", versionCodes: ["10005"] }] }];
    const { fetchImpl, requests } = mockPlay({ tracks });
    await assert.rejects(
      runUploadPlayInternal({
        envFile,
        aabPath,
        mappingPath,
        versionCode: "10005",
        reportPath,
        apiBaseUrl: "https://api.example/v3",
        uploadBaseUrl: "https://upload.example/v3",
        fetchImpl,
      }),
      /not greater than current Play max 10005/,
    );
    // The monotonic gate must fire before any binary is uploaded.
    assert.ok(!requests.some((request) => request.url.includes("/bundles")));
  });
});

test("fails when service-account authentication is rejected", async () => {
  await withFiles(async ({ envFile, aabPath, mappingPath, reportPath }) => {
    const { fetchImpl } = mockPlay({ overrides: { token: jsonResponse(401, { error: "unauthorized" }) } });
    await assert.rejects(
      runUploadPlayInternal({
        envFile,
        aabPath,
        mappingPath,
        versionCode: "10005",
        reportPath,
        apiBaseUrl: "https://api.example/v3",
        uploadBaseUrl: "https://upload.example/v3",
        fetchImpl,
      }),
      /google play oauth failed: 401/,
    );
  });
});

test("fails when the uploaded bundle versionCode does not match the expected one", async () => {
  await withFiles(async ({ envFile, aabPath, mappingPath, reportPath }) => {
    const { fetchImpl } = mockPlay({ tracks: [], uploadedVersionCode: "10004" });
    await assert.rejects(
      runUploadPlayInternal({
        envFile,
        aabPath,
        mappingPath,
        versionCode: "10005",
        reportPath,
        apiBaseUrl: "https://api.example/v3",
        uploadBaseUrl: "https://upload.example/v3",
        fetchImpl,
      }),
      /does not match expected 10005/,
    );
  });
});
