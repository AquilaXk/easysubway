import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { mkdtemp, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { runGooglePlayApiAccess } from "./check-google-play-api-access.mjs";

test("Google Play API access checker는 edit를 삭제하고 redacted report를 만든다", async (t) => {
  const requests = [];
  t.after(() => {
    requests.length = 0;
  });

  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const baseUrl = "https://androidpublisher.example.invalid";
  const serviceAccount = {
    client_email: "play-service@example.invalid",
    private_key: privateKey.export({ type: "pkcs8", format: "pem" }),
    token_uri: `${baseUrl}/token`,
  };
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-google-play-api-"));
  const envFile = path.join(dir, "store.env");
  const outputFile = path.join(dir, "github-output.txt");
  const reportFile = path.join(dir, "report.txt");
  await writeFile(
    envFile,
    [
      `EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=${Buffer.from(JSON.stringify(serviceAccount)).toString("base64")}`,
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=7",
      "",
    ].join("\n"),
  );

  await runGooglePlayApiAccess({
    envFile,
    githubOutput: outputFile,
    reportPath: reportFile,
    apiBaseUrl: `${baseUrl}/androidpublisher/v3`,
    fetchImpl: mockGooglePlayFetch(requests, "7"),
  });

  const output = readFileSync(outputFile, "utf8");
  const report = readFileSync(reportFile, "utf8");
  assert.match(output, /^google_play_api_access_ready=true$/m);
  assert.match(report, /^edit_insert\.ready=true$/m);
  assert.match(report, /^tracks\.ids=internal,production$/m);
  assert.match(report, /^tracks\.max_version_code=7$/m);
  assert.match(report, /^latest_version_code_covers_track_max=true$/m);
  assert.match(report, /^edit_delete\.ready=true$/m);
  assert.doesNotMatch(report, /play-service@example\.invalid/);
  assert.ok(requests.includes("DELETE https://androidpublisher.example.invalid/androidpublisher/v3/applications/com.easysubway.app/edits/edit-1"));
});

test("Google Play API access checker는 env versionCode가 Play track max보다 낮으면 실패한다", async () => {
  const requests = [];
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const serviceAccount = {
    client_email: "play-service@example.invalid",
    private_key: privateKey.export({ type: "pkcs8", format: "pem" }),
    token_uri: "https://androidpublisher.example.invalid/token",
  };
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-google-play-api-mismatch-"));
  const envFile = path.join(dir, "store.env");
  const outputFile = path.join(dir, "github-output.txt");
  const reportFile = path.join(dir, "report.txt");
  await writeFile(
    envFile,
    [
      `EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=${Buffer.from(JSON.stringify(serviceAccount)).toString("base64")}`,
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=6",
      "",
    ].join("\n"),
  );

  await assert.rejects(
    runGooglePlayApiAccess({
      envFile,
      githubOutput: outputFile,
      reportPath: reportFile,
      apiBaseUrl: "https://androidpublisher.example.invalid/androidpublisher/v3",
      fetchImpl: mockGooglePlayFetch(requests, "7"),
    }),
    /latest versionCode is lower than track max/,
  );

  const output = readFileSync(outputFile, "utf8");
  const report = readFileSync(reportFile, "utf8");
  assert.match(output, /^google_play_api_access_ready=false$/m);
  assert.match(report, /^latest_version_code_covers_track_max=false$/m);
  assert.match(report, /^edit_delete\.ready=true$/m);
  assert.ok(requests.includes("DELETE https://androidpublisher.example.invalid/androidpublisher/v3/applications/com.easysubway.app/edits/edit-1"));
});

test("Google Play API access checker는 env versionCode가 track max 이상이면 통과한다", async () => {
  const requests = [];
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const serviceAccount = {
    client_email: "play-service@example.invalid",
    private_key: privateKey.export({ type: "pkcs8", format: "pem" }),
    token_uri: "https://androidpublisher.example.invalid/token",
  };
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-google-play-api-lower-bound-"));
  const envFile = path.join(dir, "store.env");
  const outputFile = path.join(dir, "github-output.txt");
  const reportFile = path.join(dir, "report.txt");
  await writeFile(
    envFile,
    [
      `EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=${Buffer.from(JSON.stringify(serviceAccount)).toString("base64")}`,
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=9",
      "",
    ].join("\n"),
  );

  await runGooglePlayApiAccess({
    envFile,
    githubOutput: outputFile,
    reportPath: reportFile,
    apiBaseUrl: "https://androidpublisher.example.invalid/androidpublisher/v3",
    fetchImpl: mockGooglePlayFetch(requests, "7"),
  });

  const output = readFileSync(outputFile, "utf8");
  const report = readFileSync(reportFile, "utf8");
  assert.match(output, /^google_play_api_access_ready=true$/m);
  assert.match(report, /^tracks\.max_version_code=7$/m);
  assert.match(report, /^latest_version_code_env=9$/m);
  assert.match(report, /^latest_version_code_covers_track_max=true$/m);
});

test("Google Play API access checker는 Play API 실패도 redacted report로 남긴다", async () => {
  const requests = [];
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const serviceAccount = {
    client_email: "play-service@example.invalid",
    private_key: privateKey.export({ type: "pkcs8", format: "pem" }),
    token_uri: "https://androidpublisher.example.invalid/token",
  };
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-google-play-api-failure-"));
  const envFile = path.join(dir, "store.env");
  const outputFile = path.join(dir, "github-output.txt");
  const reportFile = path.join(dir, "report.txt");
  await writeFile(
    envFile,
    [
      `EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=${Buffer.from(JSON.stringify(serviceAccount)).toString("base64")}`,
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=7",
      "",
    ].join("\n"),
  );

  await assert.rejects(
    runGooglePlayApiAccess({
      envFile,
      githubOutput: outputFile,
      reportPath: reportFile,
      apiBaseUrl: "https://androidpublisher.example.invalid/androidpublisher/v3",
      fetchImpl: mockGooglePlayFetch(requests, "7", {
        validateStatus: 403,
        validateBody: {
          error: {
            status: "PERMISSION_DENIED",
            message: "Android Publisher API is disabled for project secret-project-id",
          },
        },
      }),
    }),
    /google play api POST failed: 403/,
  );

  const output = readFileSync(outputFile, "utf8");
  const report = readFileSync(reportFile, "utf8");
  assert.match(output, /^google_play_api_access_ready=false$/m);
  assert.match(report, /^failure=google play api POST failed: 403 status=PERMISSION_DENIED/m);
  assert.match(report, /^edit_delete\.ready=true$/m);
  assert.doesNotMatch(report, /play-service@example\.invalid/);
  assert.ok(requests.includes("DELETE https://androidpublisher.example.invalid/androidpublisher/v3/applications/com.easysubway.app/edits/edit-1"));
});

test("Google Play API access checker는 malformed credential도 redacted report로 남긴다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-google-play-api-malformed-"));
  const envFile = path.join(dir, "store.env");
  const outputFile = path.join(dir, "github-output.txt");
  const reportFile = path.join(dir, "report.txt");
  await writeFile(
    envFile,
    [
      "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=not-json",
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=7",
      "",
    ].join("\n"),
  );

  await assert.rejects(
    runGooglePlayApiAccess({
      envFile,
      githubOutput: outputFile,
      reportPath: reportFile,
      apiBaseUrl: "https://androidpublisher.example.invalid/androidpublisher/v3",
      fetchImpl: async () => {
        throw new Error("fetch must not be called");
      },
    }),
    /invalid google play service account json/,
  );

  const output = readFileSync(outputFile, "utf8");
  const report = readFileSync(reportFile, "utf8");
  assert.match(output, /^google_play_api_access_ready=false$/m);
  assert.match(report, /^service_account_json_source=base64$/m);
  assert.match(report, /^failure=invalid google play service account json$/m);
  assert.match(report, /^edit_delete\.ready=false$/m);
  assert.doesNotMatch(report, /not-json/);
});

test("Google Play API access checker는 malformed JSON credential 원문을 report에 남기지 않는다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-google-play-api-malformed-json-"));
  const envFile = path.join(dir, "store.env");
  const outputFile = path.join(dir, "github-output.txt");
  const reportFile = path.join(dir, "report.txt");
  await writeFile(
    envFile,
    [
      "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=abc123secret",
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=7",
      "",
    ].join("\n"),
  );

  await assert.rejects(
    runGooglePlayApiAccess({
      envFile,
      githubOutput: outputFile,
      reportPath: reportFile,
      apiBaseUrl: "https://androidpublisher.example.invalid/androidpublisher/v3",
      fetchImpl: async () => {
        throw new Error("fetch must not be called");
      },
    }),
    /invalid google play service account json/,
  );

  const output = readFileSync(outputFile, "utf8");
  const report = readFileSync(reportFile, "utf8");
  assert.match(output, /^google_play_api_access_ready=false$/m);
  assert.match(report, /^service_account_json_source=json$/m);
  assert.match(report, /^failure=invalid google play service account json$/m);
  assert.doesNotMatch(report, /abc123secret/);
});

function mockGooglePlayFetch(requests, maxVersionCode, config = {}) {
  return async (url, requestOptions = {}) => {
    const method = requestOptions.method ?? "GET";
    requests.push(`${method} ${url}`);
    if (url === "https://androidpublisher.example.invalid/token") {
      return jsonResponse({ access_token: "access-token", token_type: "Bearer", expires_in: 3600 });
    }
    if (method === "POST" && url === "https://androidpublisher.example.invalid/androidpublisher/v3/applications/com.easysubway.app/edits") {
      return jsonResponse({ id: "edit-1", expiryTimeSeconds: "1800000000" });
    }
    if (method === "GET" && url === "https://androidpublisher.example.invalid/androidpublisher/v3/applications/com.easysubway.app/edits/edit-1/tracks") {
      return jsonResponse({
        tracks: [
          { trackId: "internal", releases: [{ versionCodes: [maxVersionCode] }] },
          { trackId: "production", releases: [] },
        ],
      });
    }
    if (method === "POST" && url === "https://androidpublisher.example.invalid/androidpublisher/v3/applications/com.easysubway.app/edits/edit-1:validate") {
      assert.equal(requestOptions.body, undefined);
      assert.equal(requestOptions.headers?.["content-type"], undefined);
      return jsonResponse(config.validateBody ?? { id: "edit-1" }, config.validateStatus ?? 200);
    }
    if (method === "DELETE" && url === "https://androidpublisher.example.invalid/androidpublisher/v3/applications/com.easysubway.app/edits/edit-1") {
      return jsonResponse({});
    }
    return jsonResponse({}, 404);
  };
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
