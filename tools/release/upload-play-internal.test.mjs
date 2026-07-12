import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { runUploadPlayInternal } from "./upload-play-internal.mjs";
import { assertRequestUrl } from "../ci/lib/google-play-auth.mjs";

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

// A response whose body is plain text (not JSON) — mirrors Google returning a
// bare error string that the previous unconditional JSON.parse would choke on.
function textResponse(status, text) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => {
      throw new SyntaxError("Unexpected token");
    },
    text: async () => text,
  };
}

// Builds a mock Android Publisher API. `tracks` is the existing track list, and
// `overrides` can force specific endpoints (e.g. an auth failure). `commit` may
// override the commit response: pass a single response applied to every commit
// call, or a function `(changesNotSentForReview) => response` to vary by flag.
function mockPlay({ tracks = [], uploadedVersionCode = "10005", overrides = {}, commit } = {}) {
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
    if (url.includes(":commit")) {
      if (typeof commit === "function") return commit(url.includes("changesNotSentForReview=true"));
      if (commit) return commit;
      return jsonResponse(200, {});
    }
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

test("surfaces the raw plaintext body when Play returns a non-JSON error (issue #2011)", async () => {
  await withFiles(async ({ envFile, aabPath, mappingPath, reportPath }) => {
    // Google occasionally returns a bare plaintext error instead of JSON; the
    // old code JSON.parse'd it unconditionally and lost the original message.
    const raw = "Could not commit changes for edit edit-1 because the app is in draft status.";
    const { fetchImpl } = mockPlay({ tracks: [], commit: textResponse(400, raw) });
    await assert.rejects(
      runUploadPlayInternal({
        envFile,
        aabPath,
        mappingPath,
        versionCode: "10005",
        reportPath,
        // changesNotSentForReview already true => no draft retry, error surfaces.
        changesNotSentForReview: true,
        apiBaseUrl: "https://api.example/v3",
        uploadBaseUrl: "https://upload.example/v3",
        fetchImpl,
      }),
      (error) => {
        assert.equal(error.name, "PlayApiError");
        assert.equal(error.status, 400);
        assert.equal(error.rawBody, raw);
        // The raw body must appear verbatim in the message, not "is not valid JSON".
        assert.match(error.message, /draft status/);
        assert.doesNotMatch(error.message, /is not valid JSON/);
        return true;
      },
    );
  });
});

test("retries commit once with changesNotSentForReview=true on a draft-status rejection", async () => {
  await withFiles(async ({ envFile, aabPath, mappingPath, reportPath }) => {
    const raw = "Could not commit changes for edit edit-1 because the app is in draft status.";
    // First commit (false) is rejected as draft; the retry (true) succeeds.
    const { fetchImpl, requests } = mockPlay({
      tracks: [],
      commit: (notSent) => (notSent ? jsonResponse(200, {}) : textResponse(400, raw)),
    });
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

    // Evidence records the escalated flag and that a retry occurred.
    assert.equal(evidence.changesNotSentForReview, true);
    assert.equal(evidence.changesNotSentForReviewRetried, true);

    const commits = requests.filter((request) => request.url.includes(":commit"));
    assert.equal(commits.length, 2);
    assert.ok(commits[0].url.includes("changesNotSentForReview=false"));
    assert.ok(commits[1].url.includes("changesNotSentForReview=true"));
  });
});

test("does not retry when a non-draft commit error occurs", async () => {
  await withFiles(async ({ envFile, aabPath, mappingPath, reportPath }) => {
    // A generic server error must NOT be masked by a draft retry.
    const { fetchImpl, requests } = mockPlay({
      tracks: [],
      commit: jsonResponse(500, { error: { status: "INTERNAL", message: "backend unavailable" } }),
    });
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
      /backend unavailable/,
    );
    const commits = requests.filter((request) => request.url.includes(":commit"));
    assert.equal(commits.length, 1, "a non-draft failure must not trigger a retry");
  });
});

test("assertRequestUrl only accepts absolute HTTPS URLs (SSRF guard)", () => {
  assert.equal(
    assertRequestUrl("https://androidpublisher.googleapis.com/androidpublisher/v3/x"),
    "https://androidpublisher.googleapis.com/androidpublisher/v3/x",
  );
  assert.throws(() => assertRequestUrl("http://androidpublisher.googleapis.com"), /must be https/);
  assert.throws(() => assertRequestUrl("http://169.254.169.254/latest/meta-data"), /must be https/);
  assert.throws(() => assertRequestUrl("ftp://example.com/x"), /must be https/);
  assert.throws(() => assertRequestUrl("/relative/path"), /invalid google play request url/);
  assert.throws(() => assertRequestUrl("not a url"), /invalid google play request url/);
});
