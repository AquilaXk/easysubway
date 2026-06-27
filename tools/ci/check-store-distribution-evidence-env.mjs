#!/usr/bin/env node
import { appendFile, readFile, writeFile } from "node:fs/promises";

const androidRequiredAny = [
  "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",
  "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64",
];
const androidRequiredAll = ["EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME"];
const androidRequiredPlayEvidence = [
  "EASYSUBWAY_GOOGLE_PLAY_APP_SIGNING_SHA256",
  "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE",
];
const iosRequiredAll = [
  "EASYSUBWAY_APP_STORE_CONNECT_KEY_ID",
  "EASYSUBWAY_APP_STORE_CONNECT_ISSUER_ID",
  "EASYSUBWAY_APP_STORE_CONNECT_PRIVATE_KEY_PEM",
  "EASYSUBWAY_APP_STORE_APPLE_ID",
  "EASYSUBWAY_APP_STORE_BUNDLE_ID",
];
const datapackCommonRequiredAll = [
  "EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_ENABLED",
  "EASYSUBWAY_DATA_PACK_BASE_URL",
];
const datapackLegacyRequiredAll = [
  "EASYSUBWAY_OBJECT_STORAGE_ENDPOINT",
  "EASYSUBWAY_OBJECT_STORAGE_ACCESS_KEY",
  "EASYSUBWAY_OBJECT_STORAGE_SECRET_KEY",
  "EASYSUBWAY_OBJECT_STORAGE_REGION",
  "EASYSUBWAY_DATAPACK_BUCKET",
];

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const envFile = requireArg(args, "env-file");
  const mobilePubspec = args.get("mobile-pubspec");
  const githubOutput = requireArg(args, "github-output");
  const reportPath = requireArg(args, "report");
  const env = parseDotenv(await readFile(envFile, "utf8"));
  const mobileVersionCode = mobilePubspec ? await readMobileVersionCode(mobilePubspec) : undefined;

  const android = credentialGroupStatus(env, {
    label: "android_play_internal_track",
    requiredAll: [...androidRequiredAll, ...androidRequiredPlayEvidence],
    requiredAny: androidRequiredAny,
    releaseBlocker: true,
    validators: [
      validateSha256Fingerprint("EASYSUBWAY_GOOGLE_PLAY_APP_SIGNING_SHA256"),
      validateNonNegativeInteger("EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE"),
      validateMobileVersionCodeIsGreaterThanLatestPlayArtifact(mobileVersionCode),
    ],
  });
  const ios = credentialGroupStatus(env, {
    label: "ios_testflight",
    requiredAll: iosRequiredAll,
    requiredAny: [],
    releaseBlocker: false,
    deferredStatus: "DEFERRED_OUT_OF_SCOPE",
  });
  const datapack = datapackStatus(env);
  const groups = [android, ios, datapack];

  await appendFile(githubOutput, groups.map((group) => `${group.outputName}=${group.ready}`).join("\n") + "\n");
  await writeFile(reportPath, renderReport(groups));

  const notReady = groups.filter((group) => group.releaseBlocker && !group.ready);
  if (notReady.length > 0) {
    throw new Error(`store distribution evidence preflight failed: ${notReady.map((group) => group.label).join(", ")}`);
  }
}

function credentialGroupStatus(env, group) {
  const missingAll = group.requiredAll.filter((name) => !hasValue(env, name));
  const anySatisfied = group.requiredAny.length === 0 || group.requiredAny.some((name) => hasValue(env, name));
  const invalid = (group.validators ?? []).flatMap((validate) => validate(env));
  const missing = [
    ...missingAll,
    ...(anySatisfied ? [] : [`one_of:${group.requiredAny.join("|")}`]),
    ...invalid,
  ];
  return {
    label: group.label,
    outputName: outputName(group.label),
    ready: missing.length === 0 && anySatisfied,
    releaseBlocker: group.releaseBlocker,
    status: missing.length === 0 && anySatisfied ? "READY" : (group.deferredStatus ?? "BLOCKED"),
    missing,
    present: [
      ...group.requiredAll.filter((name) => hasValue(env, name)),
      ...group.requiredAny.filter((name) => hasValue(env, name)),
    ],
  };
}

function datapackStatus(env) {
  const missing = datapackCommonRequiredAll.filter((name) => !hasValue(env, name));
  const present = datapackCommonRequiredAll.filter((name) => hasValue(env, name));
  const hasPreauthUrl = hasValue(env, "EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL");
  const legacyMissing = datapackLegacyRequiredAll.filter((name) => !hasValue(env, name));

  if (env.EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_ENABLED !== "true") {
    missing.push("EASYSUBWAY_DATAPACK_REMOTE_PUBLISH_ENABLED:true");
  }
  if (hasPreauthUrl) {
    present.push("EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL");
  } else {
    missing.push(...legacyMissing);
    present.push(...datapackLegacyRequiredAll.filter((name) => hasValue(env, name)));
  }
  for (const name of [
    "EASYSUBWAY_DATA_PACK_BASE_URL",
    ...(hasPreauthUrl ? ["EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL"] : ["EASYSUBWAY_OBJECT_STORAGE_ENDPOINT"]),
  ]) {
    if (hasValue(env, name) && !isPublicHttps(env[name])) {
      missing.push(`${name}:public_https`);
    }
  }
  return {
    label: "datapack_object_storage_publish",
    outputName: outputName("datapack_object_storage_publish"),
    ready: missing.length === 0,
    releaseBlocker: true,
    status: missing.length === 0 ? "READY" : "BLOCKED",
    missing,
    present,
  };
}

function renderReport(groups) {
  return [
    "store_distribution_evidence_preflight",
    ...groups.flatMap((group) => [
      `${group.label}.ready=${group.ready}`,
      `${group.label}.release_blocker=${group.releaseBlocker}`,
      `${group.label}.status=${group.status}`,
      `${group.label}.present=${group.present.toSorted().join(",") || "none"}`,
      `${group.label}.missing=${group.missing.toSorted().join(",") || "none"}`,
    ]),
    "",
  ].join("\n");
}

function parseDotenv(source) {
  const values = {};
  for (const line of source.split(/\r?\n/)) {
    if (!line || line.trimStart().startsWith("#")) {
      continue;
    }
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!match) {
      continue;
    }
    values[match[1]] = unquote(match[2]);
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

function validateSha256Fingerprint(name) {
  return (env) => {
    if (!hasValue(env, name)) {
      return [];
    }
    const value = env[name].trim();
    const compact = /^[0-9a-f]{64}$/i.test(value);
    const colonSeparated = /^([0-9a-f]{2}:){31}[0-9a-f]{2}$/i.test(value);
    return compact || colonSeparated ? [] : [`${name}:sha256_fingerprint`];
  };
}

function validateNonNegativeInteger(name) {
  return (env) => {
    if (!hasValue(env, name)) {
      return [];
    }
    return /^(0|[1-9][0-9]*)$/.test(env[name].trim()) ? [] : [`${name}:nonnegative_integer`];
  };
}

function validateMobileVersionCodeIsGreaterThanLatestPlayArtifact(mobileVersionCode) {
  return (env) => {
    if (mobileVersionCode === undefined || !hasValue(env, "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE")) {
      return [];
    }
    const latestPlayVersionCode = Number.parseInt(env.EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE.trim(), 10);
    if (!Number.isSafeInteger(latestPlayVersionCode)) {
      return [];
    }
    return mobileVersionCode > latestPlayVersionCode
      ? []
      : [`EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE:must_be_less_than_mobile_version_code_${mobileVersionCode}`];
  };
}

async function readMobileVersionCode(pubspecPath) {
  const pubspec = await readFile(pubspecPath, "utf8");
  const match = pubspec.match(/^version:\s*[^+\s]+[+](\d+)\s*$/m);
  if (!match) {
    throw new Error(`mobile pubspec versionCode not found: ${pubspecPath}`);
  }
  return Number.parseInt(match[1], 10);
}

function isPublicHttps(value) {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
    return (
      url.protocol === "https:"
      && host !== "localhost"
      && host !== "::1"
      && host !== "0.0.0.0"
      && !host.startsWith("127.")
      && !host.endsWith(".localhost")
    );
  } catch {
    return false;
  }
}

function outputName(label) {
  return `${label.replace(/[^a-z0-9]+/g, "_")}_ready`;
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined || value.startsWith("--")) {
      throw new Error(`invalid argument near ${key ?? "<end>"}`);
    }
    const normalized = key.slice(2);
    if (args.has(normalized)) {
      throw new Error(`duplicate argument: ${key}`);
    }
    args.set(normalized, value);
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
