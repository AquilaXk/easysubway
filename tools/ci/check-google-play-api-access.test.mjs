import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdtemp, writeFile } from "node:fs/promises";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = process.cwd();

test("Google Play API access checker는 edit를 삭제하고 redacted report를 만든다", async (t) => {
  const requests = [];
  const server = createServer((request, response) => {
    requests.push(`${request.method} ${request.url}`);
    request.resume();
    if (request.url === "/token") {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify({ access_token: "access-token", token_type: "Bearer", expires_in: 3600 }));
      return;
    }
    if (request.method === "POST" && request.url === "/androidpublisher/v3/applications/com.easysubway.app/edits") {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify({ id: "edit-1", expiryTimeSeconds: "1800000000" }));
      return;
    }
    if (request.method === "GET" && request.url === "/androidpublisher/v3/applications/com.easysubway.app/edits/edit-1/tracks") {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify({
        tracks: [
          { trackId: "internal", releases: [{ versionCodes: ["7"] }] },
          { trackId: "production", releases: [] },
        ],
      }));
      return;
    }
    if (request.method === "POST" && request.url === "/androidpublisher/v3/applications/com.easysubway.app/edits/edit-1:validate") {
      response.setHeader("content-type", "application/json");
      response.end(JSON.stringify({ id: "edit-1" }));
      return;
    }
    if (request.method === "DELETE" && request.url === "/androidpublisher/v3/applications/com.easysubway.app/edits/edit-1") {
      response.setHeader("content-type", "application/json");
      response.end("{}");
      return;
    }
    response.statusCode = 404;
    response.end("{}");
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
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

  await execFileAsync(
    process.execPath,
    [
      "tools/ci/check-google-play-api-access.mjs",
      "--env-file",
      envFile,
      "--github-output",
      outputFile,
      "--report",
      reportFile,
      "--api-base-url",
      `${baseUrl}/androidpublisher/v3`,
    ],
    { cwd: root },
  );

  const output = readFileSync(outputFile, "utf8");
  const report = readFileSync(reportFile, "utf8");
  assert.match(output, /^google_play_api_access_ready=true$/m);
  assert.match(report, /^edit_insert\.ready=true$/m);
  assert.match(report, /^tracks\.ids=internal,production$/m);
  assert.match(report, /^tracks\.max_version_code=7$/m);
  assert.match(report, /^latest_version_code_matches_track_max=true$/m);
  assert.match(report, /^edit_delete\.ready=true$/m);
  assert.doesNotMatch(report, /play-service@example\.invalid/);
  assert.ok(requests.includes("DELETE /androidpublisher/v3/applications/com.easysubway.app/edits/edit-1"));
});
