#!/usr/bin/env node
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";

const defaultPubspec = "apps/mobile/pubspec.yaml";

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.selfTest) {
    selfTest();
    return;
  }

  const pubspecPath = args.pubspec ?? defaultPubspec;
  const source = await readFile(pubspecPath, "utf8");
  const next = bumpVersion(parsePubspecVersion(source), {
    part: args.part ?? "patch",
    latestPlayVersionCode: args.latestPlayVersionCode,
  });
  const updated = source.replace(/^version:\s*[^\n]+$/m, `version: ${next.versionName}+${next.versionCode}`);

  if (args.write) {
    await writeFile(pubspecPath, updated);
  }

  console.log(`version=${next.versionName}+${next.versionCode}`);
}

function bumpVersion(current, options) {
  const part = options.part;
  if (!["major", "minor", "patch"].includes(part)) {
    throw new Error(`invalid --part: ${part}`);
  }

  const next = { ...current };
  if (part === "major") {
    next.major += 1;
    next.minor = 0;
    next.patch = 0;
  } else if (part === "minor") {
    next.minor += 1;
    next.patch = 0;
  } else {
    next.patch += 1;
  }

  const latest = options.latestPlayVersionCode === undefined
    ? current.versionCode
    : parseNonNegativeInteger(options.latestPlayVersionCode, "--latest-play-version-code");
  next.versionCode = Math.max(current.versionCode, latest) + 1;
  next.versionName = `${next.major}.${next.minor}.${next.patch}`;
  return next;
}

function parsePubspecVersion(source) {
  const match = source.match(/^version:\s*(\d+)\.(\d+)\.(\d+)[+](\d+)\s*$/m);
  if (!match) {
    throw new Error("pubspec version must look like 1.2.3+123");
  }
  const [, major, minor, patch, versionCode] = match;
  return {
    major: Number.parseInt(major, 10),
    minor: Number.parseInt(minor, 10),
    patch: Number.parseInt(patch, 10),
    versionCode: Number.parseInt(versionCode, 10),
  };
}

function parseNonNegativeInteger(value, label) {
  if (!/^(0|[1-9]\d*)$/.test(String(value))) {
    throw new Error(`${label} must be a non-negative integer`);
  }
  return Number.parseInt(value, 10);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (key === "--write") {
      args.write = true;
      continue;
    }
    if (key === "--self-test") {
      args.selfTest = true;
      continue;
    }
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined || value.startsWith("--")) {
      throw new Error(`invalid argument near ${key ?? "<end>"}`);
    }
    args[key.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value;
    index += 1;
  }
  return args;
}

function selfTest() {
  assert.deepEqual(
    bumpVersion(parsePubspecVersion("version: 1.0.1+10001\n"), { part: "patch", latestPlayVersionCode: "10001" }),
    { major: 1, minor: 0, patch: 2, versionCode: 10002, versionName: "1.0.2" },
  );
  assert.deepEqual(
    bumpVersion(parsePubspecVersion("version: 1.2.9+42\n"), { part: "minor", latestPlayVersionCode: "50" }),
    { major: 1, minor: 3, patch: 0, versionCode: 51, versionName: "1.3.0" },
  );
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
