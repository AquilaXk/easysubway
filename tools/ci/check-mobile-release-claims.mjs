#!/usr/bin/env node
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { canonicalScopeHash } from "../datapack/build-launch-denominator-report.mjs";

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.get("root") ?? process.cwd());
  const configPath = path.resolve(root, args.get("config") ?? "release/product-gates/forbidden-release-claims.json");
  const config = JSON.parse(await readFile(configPath, "utf8"));
  const scope = JSON.parse(await readFile(path.resolve(root, config.scopeSource), "utf8"));
  const supportedClaimKo = scope.verifiedAccessibilityScope?.supportedClaimKo;
  if (!supportedClaimKo) throw new Error("production scope supportedClaimKo missing");

  const allowedPhrasesKo = config.allowedPhrasesKo ?? [];
  const failures = [];
  for (const target of config.scanTargets ?? []) {
    for (const file of await targetFiles(root, target)) {
      const rawText = await scanText(file, target);
      // 허용 구절(시설명 등)을 먼저 전부 치환 제거한 뒤 남은 텍스트에서 금지 표현을 검사한다.
      let text = rawText;
      for (const phrase of allowedPhrasesKo) {
        text = text.split(phrase).join("");
      }
      for (const claim of config.forbiddenClaimsKo ?? []) {
        if (text.includes(claim)) failures.push(`${path.relative(root, file)} contains forbidden release claim: ${claim}`);
      }
    }
  }

  const play = JSON.parse(await readFile(path.resolve(root, "apps/mobile/release/play-store-submission-content.json"), "utf8"));
  if (play.koreanListing?.supportRegionKo !== supportedClaimKo) {
    failures.push(`play-store supportRegionKo must match production scope: ${supportedClaimKo}`);
  }
  if (play.verifiedAccessibilityScopeId !== scope.verifiedAccessibilityScope?.id) {
    failures.push("play-store verifiedAccessibilityScopeId must match verified accessibility scope");
  }
  if (play.verifiedAccessibilityScopeSha256 !== canonicalScopeHash(scope.verifiedAccessibilityScope)) {
    failures.push("play-store verifiedAccessibilityScopeSha256 must match canonical verified accessibility scope");
  }
  if (play.launchScopeId !== scope.routingLaunchScope?.id) {
    failures.push("play-store launchScopeId must match routing launch scope");
  }
  if (play.launchScopeSha256 !== canonicalScopeHash(scope.routingLaunchScope)) {
    failures.push("play-store launchScopeSha256 must match canonical routing launch scope");
  }
  if (play.nationwideRoadmapScopeId !== scope.nationwideRoadmapScope?.id) {
    failures.push("play-store nationwideRoadmapScopeId must match nationwide roadmap scope");
  }
  if (play.nationwideRoadmapScopeSha256 !== canonicalScopeHash(scope.nationwideRoadmapScope)) {
    failures.push("play-store nationwideRoadmapScopeSha256 must match canonical nationwide roadmap scope");
  }
  if (play.identityLinkageMatrixSha256 !== canonicalScopeHash(scope.identityMatrix)) {
    failures.push("play-store identityLinkageMatrixSha256 must match canonical identity linkage matrix");
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
