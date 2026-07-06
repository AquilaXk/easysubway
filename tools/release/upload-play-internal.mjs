#!/usr/bin/env node
// Upload a production-signed AAB (+ deobfuscation mapping) to the Google Play
// internal track via the Android Publisher API v3 (issue #1689). Self-contained
// Node — no third-party upload action — reusing the service-account JWT flow in
// tools/ci/lib/google-play-auth.mjs.
//
// The versionCode monotonic policy is enforced BEFORE any upload: if the AAB's
// versionCode is not strictly greater than the highest versionCode already on
// any track, the run fails without touching Play (versionCodeMonotonicPolicy).
import { readFile as readFileFs, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import {
  defaultApiBaseUrl,
  encodePath,
  fetchAccessToken,
  parseDotenv,
  readServiceAccount,
  requestJson,
  requireEnv,
  requireJsonString,
  uploadMedia,
} from "../ci/lib/google-play-auth.mjs";

const defaultUploadBaseUrl = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3";

function maxTrackVersionCode(tracks) {
  const list = Array.isArray(tracks) ? tracks : [];
  let max;
  for (const track of list) {
    for (const release of track.releases ?? []) {
      for (const code of release.versionCodes ?? []) {
        if (!/^(0|[1-9]\d*)$/.test(String(code))) continue;
        const parsed = BigInt(code);
        if (max === undefined || parsed > max) max = parsed;
      }
    }
  }
  return max;
}

function sha256OfBuffer(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

export async function runUploadPlayInternal({
  envFile,
  aabPath,
  mappingPath,
  versionCode,
  track = "internal",
  reportPath,
  packageNameOverride,
  apiBaseUrl = defaultApiBaseUrl,
  uploadBaseUrl = defaultUploadBaseUrl,
  changesNotSentForReview = false,
  fetchImpl = fetch,
  readFileImpl = readFileFs,
}) {
  const api = apiBaseUrl.replace(/\/$/, "");
  const upload = uploadBaseUrl.replace(/\/$/, "");

  if (!/^[1-9]\d*$/.test(String(versionCode))) {
    throw new Error("versionCode must be a positive integer");
  }
  const targetVersionCode = BigInt(versionCode);

  const env = parseDotenv(await readFileImpl(envFile, "utf8"));
  const packageName = packageNameOverride?.trim()
    || env.EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME?.trim()
    || "com.easysubway.app";
  const serviceAccount = readServiceAccount(env);
  const token = await fetchAccessToken(serviceAccount, fetchImpl);

  const aab = await readFileImpl(aabPath);
  const aabSha256 = sha256OfBuffer(aab);
  let mapping;
  let mappingSha256;
  if (mappingPath) {
    mapping = await readFileImpl(mappingPath);
    mappingSha256 = sha256OfBuffer(mapping);
  }

  const editsBase = `${api}/applications/${encodePath(packageName)}/edits`;
  const edit = await requestJson(editsBase, { method: "POST", token, body: {} }, fetchImpl);
  const editId = requireJsonString(edit, "id");

  // versionCode monotonic policy — reject before any upload.
  const tracks = await requestJson(`${editsBase}/${encodePath(editId)}/tracks`, { method: "GET", token }, fetchImpl);
  const currentMax = maxTrackVersionCode(tracks.tracks);
  if (currentMax !== undefined && targetVersionCode <= currentMax) {
    throw new Error(
      `versionCode ${targetVersionCode} is not greater than current Play max ${currentMax}`,
    );
  }

  const uploadEditsBase = `${upload}/applications/${encodePath(packageName)}/edits`;
  const bundle = await uploadMedia(
    `${uploadEditsBase}/${encodePath(editId)}/bundles?uploadType=media`,
    { token, contentType: "application/octet-stream", data: aab },
    fetchImpl,
  );
  const uploadedVersionCode = bundle.versionCode;
  if (String(uploadedVersionCode) !== String(versionCode)) {
    throw new Error(
      `uploaded bundle versionCode ${uploadedVersionCode} does not match expected ${versionCode}`,
    );
  }

  if (mapping) {
    await uploadMedia(
      `${uploadEditsBase}/${encodePath(editId)}/deobfuscationFiles/${encodePath(String(versionCode))}/proguard?uploadType=media`,
      { token, contentType: "application/octet-stream", data: mapping },
      fetchImpl,
    );
  }

  await requestJson(
    `${editsBase}/${encodePath(editId)}/tracks/${encodePath(track)}`,
    {
      method: "PUT",
      token,
      body: { track, releases: [{ status: "completed", versionCodes: [String(versionCode)] }] },
    },
    fetchImpl,
  );

  await requestJson(
    `${editsBase}/${encodePath(editId)}:commit?changesNotSentForReview=${changesNotSentForReview ? "true" : "false"}`,
    { method: "POST", token },
    fetchImpl,
  );

  const evidence = {
    schemaVersion: 1,
    gate: "play-internal-upload",
    issue: 1689,
    packageName,
    track,
    editId,
    versionCode: String(versionCode),
    aabSha256,
    mappingSha256: mappingSha256 ?? null,
    changesNotSentForReview,
    uploadedAt: new Date().toISOString(),
  };
  if (reportPath) {
    await writeFile(reportPath, `${JSON.stringify(evidence, null, 2)}\n`);
  }
  return evidence;
}

function parseArgs(argv) {
  const args = new Map();
  const flags = new Set();
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (!key?.startsWith("--")) throw new Error(`invalid argument near ${key ?? "<end>"}`);
    const value = argv[index + 1];
    if (value === undefined || value.startsWith("--")) {
      flags.add(key.slice(2));
    } else {
      args.set(key.slice(2), value);
      index += 1;
    }
  }
  return { args, flags };
}

function requireArg(args, name) {
  const value = args.get(name);
  if (!value) throw new Error(`missing required argument: --${name}`);
  return value;
}

async function main() {
  const { args, flags } = parseArgs(process.argv.slice(2));
  const evidence = await runUploadPlayInternal({
    envFile: requireArg(args, "env-file"),
    aabPath: requireArg(args, "aab"),
    mappingPath: args.get("mapping"),
    versionCode: requireArg(args, "version-code"),
    track: args.get("track") ?? "internal",
    reportPath: args.get("report"),
    packageNameOverride: args.get("package-name"),
    apiBaseUrl: args.get("api-base-url") ?? defaultApiBaseUrl,
    uploadBaseUrl: args.get("upload-base-url") ?? defaultUploadBaseUrl,
    changesNotSentForReview: flags.has("changes-not-sent-for-review"),
  });
  process.stdout.write(`play internal upload complete: versionCode ${evidence.versionCode} track ${evidence.track}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
