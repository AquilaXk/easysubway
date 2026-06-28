#!/usr/bin/env node
import { appendFile, readFile, writeFile } from "node:fs/promises";
import { createSign } from "node:crypto";
import { pathToFileURL } from "node:url";

const androidPublisherScope = "https://www.googleapis.com/auth/androidpublisher";
const defaultTokenUri = "https://oauth2.googleapis.com/token";
const defaultApiBaseUrl = "https://androidpublisher.googleapis.com/androidpublisher/v3";

async function main() {
  const args = parseArgs(process.argv.slice(2));
  await runGooglePlayApiAccess({
    envFile: requireArg(args, "env-file"),
    githubOutput: requireArg(args, "github-output"),
    reportPath: requireArg(args, "report"),
    apiBaseUrl: args.get("api-base-url") ?? defaultApiBaseUrl,
  });
}

export async function runGooglePlayApiAccess({
  envFile,
  githubOutput,
  reportPath,
  apiBaseUrl = defaultApiBaseUrl,
  fetchImpl = fetch,
}) {
  const normalizedApiBaseUrl = apiBaseUrl.replace(/\/$/, "");
  const env = parseDotenv(await readFile(envFile, "utf8"));
  const packageName = env.EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME?.trim() || "unknown";
  const latestVersionCode = env.EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE?.trim() || "unknown";
  const serviceAccountSource = detectServiceAccountSource(env);
  let token;
  let editId;
  let editDeleted = false;
  let ready = true;
  let failureMessage;
  const report = [
    "google_play_api_access",
    `package_name=${packageName}`,
    `service_account_json_source=${serviceAccountSource}`,
    "oauth_scope=androidpublisher",
    `latest_version_code_env=${latestVersionCode}`,
  ];

  try {
    if (packageName === "unknown") {
      throw new Error("missing required env: EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME");
    }
    const serviceAccount = readServiceAccount(env);
    token = await fetchAccessToken(serviceAccount, fetchImpl);
    const edit = await requestJson(`${normalizedApiBaseUrl}/applications/${encodePath(packageName)}/edits`, {
      method: "POST",
      token,
      body: {},
    }, fetchImpl);
    editId = requireJsonString(edit, "id");
    report.push("edit_insert.ready=true");

    const tracks = await requestJson(
      `${normalizedApiBaseUrl}/applications/${encodePath(packageName)}/edits/${encodePath(editId)}/tracks`,
      { method: "GET", token },
      fetchImpl,
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
    const latestVersionCodeCoversTrackMax = versionCodeCoversTrackMax(latestVersionCode, maxTrackVersionCode);
    report.push(`latest_version_code_covers_track_max=${latestVersionCodeCoversTrackMax}`);
    if (latestVersionCodeCoversTrackMax === "false") {
      ready = false;
      failureMessage = "google play latest versionCode is lower than track max versionCode";
    }

    await requestJson(
      `${normalizedApiBaseUrl}/applications/${encodePath(packageName)}/edits/${encodePath(editId)}:validate`,
      { method: "POST", token, body: {} },
      fetchImpl,
    );
    report.push("edit_validate.ready=true");
  } catch (error) {
    ready = false;
    failureMessage = error instanceof Error ? error.message : "google play api access failed";
    report.push(`failure=${redactReportValue(failureMessage)}`);
  } finally {
    if (editId && token) {
      try {
        await requestJson(
          `${normalizedApiBaseUrl}/applications/${encodePath(packageName)}/edits/${encodePath(editId)}`,
          { method: "DELETE", token },
          fetchImpl,
        );
        editDeleted = true;
      } catch (error) {
        ready = false;
        failureMessage ??= error instanceof Error ? error.message : "google play edit delete failed";
        const deleteFailure = error instanceof Error ? error.message : "google play edit delete failed";
        report.push(`edit_delete.failure=${redactReportValue(deleteFailure)}`);
      }
    }
  }

  report.push(`edit_delete.ready=${editDeleted}`);
  report.push("secret_values_printed=false");
  report.push("");
  await appendFile(githubOutput, `google_play_api_access_ready=${ready}\n`);
  await writeFile(reportPath, report.join("\n"));
  if (!ready) {
    throw new Error(failureMessage);
  }
}

async function fetchAccessToken(serviceAccount, fetchImpl) {
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
  const response = await fetchImpl(tokenUri, {
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

async function requestJson(url, { method, token, body }, fetchImpl) {
  const response = await fetchImpl(url, {
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

function redactReportValue(value) {
  return value.replace(/\s+/g, " ").slice(0, 220);
}

function detectServiceAccountSource(env) {
  if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")) {
    return "json";
  }
  if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64")) {
    return "base64";
  }
  return "missing";
}

function readServiceAccount(env) {
  try {
    if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")) {
      return JSON.parse(env.EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON);
    }
    if (hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64")) {
      return JSON.parse(Buffer.from(env.EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64.trim(), "base64").toString("utf8"));
    }
  } catch {
    throw new Error("invalid google play service account json");
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

function versionCodeCoversTrackMax(latestVersionCode, maxTrackVersionCode) {
  if (latestVersionCode === "unknown" || maxTrackVersionCode === undefined) {
    return "unknown";
  }
  if (!/^(0|[1-9]\d*)$/.test(latestVersionCode)) {
    return "unknown";
  }
  return BigInt(latestVersionCode) >= BigInt(maxTrackVersionCode) ? "true" : "false";
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

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
