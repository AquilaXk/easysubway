import { appendFileSync, readFileSync } from "node:fs";
import { basename } from "node:path";

const requiredKeys = [
  "EASYSUBWAY_PRIVACY_POLICY_URL",
  "EASYSUBWAY_SUPPORT_EMAIL",
  "EASYSUBWAY_SECURITY_EMAIL",
  "EASYSUBWAY_DATA_DELETION_EMAIL",
];

const androidRcProductionKeys = [
  "EASYSUBWAY_DATA_PACK_BASE_URL",
  "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N",
  "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E",
  "EASYSUBWAY_DATAPACK_SIGNING_KEY_ID",
  "EASYSUBWAY_DATAPACK_CHANNEL",
  "EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256",
];

function usage() {
  return [
    `Usage: node ${basename(process.argv[1])} --env-file <path> [--github-env <path>] [--require-android-rc-production]`,
    "",
    "Validates store privacy release values restored from EASYSUBWAY_ENV.",
  ].join("\n");
}

function parseArgs(argv) {
  const args = { envFile: null, githubEnv: null, requireAndroidRcProduction: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--env-file") {
      args.envFile = argv[index + 1];
      index += 1;
    } else if (arg === "--github-env") {
      args.githubEnv = argv[index + 1];
      index += 1;
    } else if (arg === "--require-android-rc-production") {
      args.requireAndroidRcProduction = true;
    } else {
      throw new Error(`Unknown argument: ${arg}\n${usage()}`);
    }
  }

  if (!args.envFile) {
    throw new Error(`Missing --env-file\n${usage()}`);
  }

  return args;
}

function unquote(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }

  return trimmed;
}

function parseDotenv(source) {
  const values = new Map();
  for (const rawLine of source.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }

    const normalized = line.startsWith("export ") ? line.slice("export ".length).trim() : line;
    const match = normalized.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) {
      continue;
    }

    values.set(match[1], unquote(match[2]));
  }

  return values;
}

function assertNoPlaceholder(key, value, host = "") {
  const normalizedValue = value.toLowerCase();
  const normalizedHost = host.toLowerCase();
  const placeholderPattern = /\b(todo|tbd|changeme|placeholder)\b/;
  const usesPlaceholder =
    placeholderPattern.test(normalizedValue) ||
    normalizedValue.includes("example.") ||
    normalizedHost === "localhost" ||
    normalizedHost.endsWith(".local");

  if (usesPlaceholder) {
    throw new Error(`${key} must not use local or placeholder values`);
  }
}

function validateHttpsUrl(key, value) {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error(`${key} must be a valid HTTPS URL`);
  }

  if (parsed.protocol !== "https:") {
    throw new Error(`${key} must be a valid HTTPS URL`);
  }

  assertNoPlaceholder(key, value, parsed.hostname);
}

function validateEmail(key, value) {
  const match = value.match(/^[^\s@]+@([^\s@]+\.[^\s@]+)$/);
  if (!match) {
    throw new Error(`${key} must be a valid email address`);
  }

  assertNoPlaceholder(key, value, match[1]);
}

function requireSingleLineValue(values, key) {
  const value = values.get(key);
  if (!value) {
    throw new Error(`${key} is required`);
  }

  if (/[\r\n\0]/.test(value)) {
    throw new Error(`${key} must be a single-line value`);
  }

  return value;
}

function validateTokenValue(key, value) {
  assertNoPlaceholder(key, value);
}

function decodeBase64Url(key, value) {
  assertNoPlaceholder(key, value);
  if (!/^[A-Za-z0-9_-]+$/.test(value) || value.length % 4 === 1) {
    throw new Error(`${key} must be base64url encoded`);
  }

  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padding = "=".repeat((4 - (normalized.length % 4)) % 4);
  const decoded = Buffer.from(`${normalized}${padding}`, "base64");
  if (decoded.length === 0) {
    throw new Error(`${key} must be base64url encoded`);
  }

  return decoded;
}

function unsignedBigInt(bytes) {
  return bytes.reduce((value, byte) => (value << 8n) + BigInt(byte), 0n);
}

function validateRsaModulusBase64Url(key, value) {
  const bytes = decodeBase64Url(key, value);
  if (bytes.length < 256) {
    throw new Error(`${key} must be a base64url RSA modulus of at least 2048 bits`);
  }
}

function validateRsaExponentBase64Url(key, value) {
  const bytes = decodeBase64Url(key, value);
  const exponent = unsignedBigInt([...bytes]);
  if (bytes.length > 8 || exponent <= 1n || exponent % 2n === 0n) {
    throw new Error(`${key} must be a base64url RSA public exponent`);
  }
}

function validateSha256Fingerprint(key, value) {
  assertNoPlaceholder(key, value);
  const colonSeparated = /^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$/.test(value);
  const compact = /^[0-9A-Fa-f]{64}$/.test(value);
  if (!colonSeparated && !compact) {
    throw new Error(`${key} must be a full SHA-256 fingerprint`);
  }
}

function validateAndroidRcProduction(values, selected) {
  for (const key of androidRcProductionKeys) {
    selected.set(key, requireSingleLineValue(values, key));
  }

  validateHttpsUrl("EASYSUBWAY_DATA_PACK_BASE_URL", selected.get("EASYSUBWAY_DATA_PACK_BASE_URL"));
  validateRsaModulusBase64Url(
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N",
    selected.get("EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N"),
  );
  validateRsaExponentBase64Url(
    "EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E",
    selected.get("EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E"),
  );
  validateTokenValue(
    "EASYSUBWAY_DATAPACK_SIGNING_KEY_ID",
    selected.get("EASYSUBWAY_DATAPACK_SIGNING_KEY_ID"),
  );
  if (selected.get("EASYSUBWAY_DATAPACK_CHANNEL") !== "production") {
    throw new Error("EASYSUBWAY_DATAPACK_CHANNEL must be production");
  }
  validateSha256Fingerprint(
    "EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256",
    selected.get("EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256"),
  );
}

function validateEnv(values, options = {}) {
  const selected = new Map();
  for (const key of requiredKeys) {
    selected.set(key, requireSingleLineValue(values, key));
  }

  validateHttpsUrl("EASYSUBWAY_PRIVACY_POLICY_URL", selected.get("EASYSUBWAY_PRIVACY_POLICY_URL"));
  validateEmail("EASYSUBWAY_SUPPORT_EMAIL", selected.get("EASYSUBWAY_SUPPORT_EMAIL"));
  validateEmail("EASYSUBWAY_SECURITY_EMAIL", selected.get("EASYSUBWAY_SECURITY_EMAIL"));
  validateEmail("EASYSUBWAY_DATA_DELETION_EMAIL", selected.get("EASYSUBWAY_DATA_DELETION_EMAIL"));

  if (options.requireAndroidRcProduction) {
    validateAndroidRcProduction(values, selected);
  }

  return selected;
}

function appendGitHubEnv(path, values) {
  const lines = [];
  for (const [key, value] of values.entries()) {
    lines.push(`${key}=${value}`);
  }
  appendFileSync(path, `${lines.join("\n")}\n`, "utf8");
}

try {
  const args = parseArgs(process.argv.slice(2));
  const values = validateEnv(parseDotenv(readFileSync(args.envFile, "utf8")), {
    requireAndroidRcProduction: args.requireAndroidRcProduction,
  });
  if (args.githubEnv) {
    appendGitHubEnv(args.githubEnv, values);
  }
  console.log("store privacy env ok");
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
