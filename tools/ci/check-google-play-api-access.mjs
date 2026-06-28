#!/usr/bin/env node
import { appendFile, readFile, writeFile } from "node:fs/promises";
import { createSign } from "node:crypto";

const androidPublisherScope = "https://www.googleapis.com/auth/androidpublisher";
const defaultTokenUri = "https://oauth2.googleapis.com/token";
const defaultApiBaseUrl = "https://androidpublisher.googleapis.com/androidpublisher/v3";

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const envFile = requireArg(args, "env-file");
  const githubOutput = requireArg(args, "github-output");
  const reportPath = requireArg(args, "report");
  const apiBaseUrl = (args.get("api-base-url") ?? defaultApiBaseUrl).replace(/\/$/, "");
  const env = parseDotenv(await readFile(envFile, "utf8"));
  const packageName = requireEnv(env, "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME");
  const latestVersionCode = env.EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE?.trim() || "unknown";
  const { serviceAccount, source } = readServiceAccount(env);
  const token = await fetchAccessToken(serviceAccount);
  let editId;
  let editDeleted = false;
  const report = [
    "google_play_api_access",
    `package_name=${packageName}`,
    `service_account_json_source=${source}`,
    "oauth_scope=androidpublisher",
    `latest_version_code_env=${latestVersionCode}`,
  ];

  try {
    const edit = await requestJson(`${apiBaseUrl}/applications/${encodePath(packageName)}/edits`, {
      method: "POST",
      token,
      body: {},
    });
    editId = requireJsonString(edit, "id");
    report.push("edit_insert.ready=true");

    const tracks = await requestJson(
      `${apiBaseUrl}/applications/${encodePath(packageName)}/edits/${encodePath(editId)}/tracks`,
      { method: "GET", token },
    );
    const trackList = Array.isArray(tracks.tracks) ? tracks.tracks : [];
    const trackIds = trackList
      .map((track) => track.trackId ?? track.track)
      .filter((track) => typeof track === "string" && track.length > 0)
      .toSorted();
    const maxTrackVersionCode = maxVersionCode(trackList);
    report.push("tracks_list.ready=true");
    report.push(`tracks.count=${trackList.length}`);
    report.push(`tracks.ids=${trackIds.join(",") || "none"}`);
    report.push(`tracks.max_version_code=${maxTrackVersionCode ?? "none"}`);
    report.push(`latest_version_code_matches_track_max=${versionCodeMatch(latestVersionCode, maxTrackVersionCode)}`);

    await requestJson(
      `${apiBaseUrl}/applications/${encodePath(packageName)}/edits/${encodePath(editId)}:validate`,
      { method: "POST", token, body: {} },
    );
    report.push("edit_validate.ready=true");
  } finally {
    if (editId) {
      await requestJson(
        `${apiBaseUrl}/applications/${encodePath(packageName)}/edits/${encodePath(editId)}`,
        { method: "DELETE", token },
      );
      editDeleted = true;
    }
  }

  report.push(`edit_delete.ready=${editDeleted}`);
  report.push("secret_values_printed=false");
  report.push("");
  await appendFile(githubOutput, "google_play_api_access_ready=true\n");
  await writeFile(reportPath, report.join("\n"));
}

async function fetchAccessToken(serviceAccount) {
  const tokenUri = serviceAccount.token_uri || defaultTokenUri;
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = base64UrlJson({ alg: "RS256", typ: "JWT" });
  const claim = base64UrlJson({
    iss: requireJsonString(serviceAccount, "client_email"),
    scope: androidPublisherScope,
    aud: tokenUri,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  });
  const unsignedToken = `${header}.${claim}`;
  const signature = createSign("RSA-SHA256").update(unsignedToken).sign(requireJsonString(serviceAccount, "private_key"));
  const assertion = `${unsignedToken}.${signature.toString("base64url")}`;
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || typeof body.access_token !== "string") {
    throw new Error(`google play oauth failed: ${response.status}`);
  }
  return body.access_token;
}

async function requestJson(url, { method, token, body }) {
  const response = await fetch(url, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      ...(body === undefined ? {} : { "content-type": "application/json" }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (response.status === 204) {
    return {};
  }
  const text = await response.text();
  const parsed = text.length === 0 ? {} : JSON.parse(text);
  if (!response.ok) {
    throw new Error(`google play api ${method} failed: ${response.status} ${apiErrorSummary(parsed)}`);
  }
  return parsed;
}

function apiErrorSummary(parsed) {
  const error = parsed.error;
  if (!error || typeof error !== "object") {
    return "status=unknown";
  }
  const status = typeof error.status === "string" ? error.status : "unknown";
  const message = typeof error.message === "string" ? error.message.replace(/\s+/g, " ").slice(0, 180) : "none";
  return `status=${status} message=${message}`;
}

function readServiceAccount(env) {
  if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")) {
    return {
      serviceAccount: JSON.parse(env.EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON),
      source: "json",
    };
  }
  if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64")) {
    return {
      serviceAccount: JSON.parse(Buffer.from(env.EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64.trim(), "base64").toString("utf8")),
      source: "base64",
    };
  }
  throw new Error("missing google play service account json");
}

function parseDotenv(source) {
  const values = {};
  for (const line of source.split(/\r?\n/)) {
    if (!line || line.trimStart().startsWith("#")) {
      continue;
    }
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (match) {
      values[match[1]] = unquote(match[2]);
    }
  }
  return values;
}

function unquote(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith("\"") && trimmed.endsWith("\""))
    || (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }
  return value;
}

function hasValue(env, name) {
  return typeof env[name] === "string" && env[name].trim().length > 0;
}

function requireEnv(env, name) {
  if (!hasValue(env, name)) {
    throw new Error(`missing required env: ${name}`);
  }
  return env[name].trim();
}

function requireJsonString(value, field) {
  if (typeof value[field] !== "string" || value[field].trim().length === 0) {
    throw new Error(`missing service account field: ${field}`);
  }
  return value[field];
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function encodePath(value) {
  return encodeURIComponent(value).replaceAll("%2E", ".");
}

function maxVersionCode(tracks) {
  const versions = tracks.flatMap((track) =>
    (track.releases ?? []).flatMap((release) => release.versionCodes ?? []),
  );
  let max;
  for (const version of versions) {
    if (!/^(0|[1-9]\d*)$/.test(String(version))) {
      continue;
    }
    const parsed = BigInt(version);
    if (max === undefined || parsed > max) {
      max = parsed;
    }
  }
  return max?.toString();
}

function versionCodeMatch(latestVersionCode, maxTrackVersionCode) {
  if (latestVersionCode === "unknown" || maxTrackVersionCode === undefined) {
    return "unknown";
  }
  return latestVersionCode === maxTrackVersionCode ? "true" : "false";
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined || value.startsWith("--")) {
      throw new Error(`invalid argument near ${key ?? "<end>"}`);
    }
    args.set(key.slice(2), value);
    index += 1;
  }
  return args;
}

function requireArg(args, name) {
  const value = args.get(name);
  if (!value) {
    throw new Error(`missing required argument: --${name}`);
  }
  return value;
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
