#!/usr/bin/env node
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.get("root") ?? process.cwd());
  const configPath = path.resolve(root, args.get("config") ?? "apps/mobile/release/forbidden-release-claims.json");
  const config = JSON.parse(await readFile(configPath, "utf8"));
  const scope = JSON.parse(await readFile(path.resolve(root, config.scopeSource), "utf8"));
  const supportedClaimKo = scope.supportScope?.supportedClaimKo;
  if (!supportedClaimKo) throw new Error("production scope supportedClaimKo missing");

  const failures = [];
  for (const target of config.scanTargets ?? []) {
    for (const file of await targetFiles(root, target)) {
      const text = await scanText(file, target);
      for (const claim of config.forbiddenClaimsKo ?? []) {
        if (text.includes(claim)) failures.push(`${path.relative(root, file)} contains forbidden release claim: ${claim}`);
      }
    }
  }

  const play = JSON.parse(await readFile(path.resolve(root, "apps/mobile/release/play-store-submission-content.json"), "utf8"));
  if (play.koreanListing?.supportRegionKo !== supportedClaimKo) {
    failures.push(`play-store supportRegionKo must match production scope: ${supportedClaimKo}`);
  }

  if (failures.length > 0) throw new Error(failures.join("\n"));
  console.log(`mobile release claim scan passed: ${supportedClaimKo}`);
}

async function targetFiles(root, target) {
  const targetPath = path.resolve(root, target.path);
  const targetStat = await stat(targetPath);
  if (!targetStat.isDirectory()) return [targetPath];
  const files = [];
  const pending = [targetPath];
  while (pending.length > 0) {
    const current = pending.pop();
    for (const entry of await readdir(current, { withFileTypes: true })) {
      const entryPath = path.join(current, entry.name);
      if (entry.isDirectory()) pending.push(entryPath);
      else if ((target.extensions ?? []).includes(path.extname(entry.name))) files.push(entryPath);
    }
  }
  return files;
}

async function scanText(file, target) {
  const source = await readFile(file, "utf8");
  if (!target.jsonPointers) return source;
  const parsed = JSON.parse(source);
  return target.jsonPointers.map((pointer) => stringsAtPointer(parsed, pointer).join("\n")).join("\n");
}

function stringsAtPointer(value, pointer) {
  const target = pointer.split("/").slice(1).reduce((cursor, part) => cursor?.[part], value);
  const strings = [];
  collectStrings(target, strings);
  return strings;
}

function collectStrings(value, strings) {
  if (typeof value === "string") strings.push(value);
  else if (Array.isArray(value)) value.forEach((item) => collectStrings(item, strings));
  else if (value && typeof value === "object") Object.values(value).forEach((item) => collectStrings(item, strings));
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined || value.startsWith("--")) {
      throw new Error(`invalid argument near ${key ?? "<end>"}`);
    }
    args.set(key.slice(2), value);
  }
  return args;
}

await main();
