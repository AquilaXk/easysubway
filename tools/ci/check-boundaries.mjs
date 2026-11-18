#!/usr/bin/env node
import { isMainModule } from "../lib/is-main-module.mjs";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { loadJson } from "./check-contracts.mjs";

const MAX_BOUNDARY_FILE_BYTES = 64 * 1024 * 1024; // 64 MiB Fail-Closed cap

export function findViolations(rules, { root = ".", allowlist = [], maxFileBytes = MAX_BOUNDARY_FILE_BYTES } = {}) {
  const now = Date.now();
  const allow = new Map();
  for (const entry of allowlist) {
    allow.set(entry.file, {
      reason: entry.reason,
      expires: entry.expires,
      expiresAt: entry.expires ? Date.parse(entry.expires) : Number.NaN,
    });
  }

  // Pre-compile rule regexes once and group rules by `from` root so each subtree is walked once.
  const rulesByFrom = new Map();
  for (const rule of rules) {
    const compiled = {
      from: rule.from,
      reason: rule.reason,
      regex: new RegExp(rule.pattern),
    };
    let group = rulesByFrom.get(rule.from);
    if (!group) {
      group = [];
      rulesByFrom.set(rule.from, group);
    }
    group.push(compiled);
  }

  // Cache file contents across overlapping `from` prefixes so every file on disk is read at most once.
  const fileTextCache = new Map();
  const readCachedText = (relFile) => {
    let text = fileTextCache.get(relFile);
    if (text !== undefined) return text;
    const fullPath = path.join(root, relFile);
    const stat = statSync(fullPath);
    if (stat.size > maxFileBytes) {
      throw new Error(`Boundary scan input exceeds maxFileBytes (${stat.size} > ${maxFileBytes}): ${relFile}`);
    }
    text = readFileSync(fullPath, "utf8");
    fileTextCache.set(relFile, text);
    return text;
  };

  const violations = [];
  for (const [from, compiledRules] of rulesByFrom.entries()) {
    const files = filesForRule(root, from);
    for (const file of files) {
      const text = readCachedText(file);
      const allowed = allow.get(file);
      for (const rule of compiledRules) {
        if (!rule.regex.test(text)) continue;
        if (allowed) {
          if (!allowed.reason || !allowed.expires) {
            violations.push({ file, why: "allowlist reason/expires 누락" });
          } else if (Number.isNaN(allowed.expiresAt)) {
            violations.push({ file, why: `allowlist 만료일 불량: ${allowed.expires}` });
          } else if (allowed.expiresAt < now) {
            violations.push({ file, why: `allowlist 만료: ${allowed.expires}` });
          }
          continue;
        }
        violations.push({ file, why: rule.reason });
      }
    }
  }
  return violations;
}

function filesForRule(root, from) {
  return walk(path.join(root, from)).map((file) => path.relative(root, file));
}

function walk(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  const stack = [dir];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = readdirSync(current, { withFileTypes: true });
    for (let i = entries.length - 1; i >= 0; i--) {
      const dirent = entries[i];
      const fullPath = path.join(current, dirent.name);
      if (dirent.isDirectory()) {
        stack.push(fullPath);
      } else if (dirent.isSymbolicLink()) {
        if (statSync(fullPath).isDirectory()) stack.push(fullPath);
        else out.push(fullPath);
      } else {
        out.push(fullPath);
      }
    }
  }
  return out;
}

if (isMainModule(import.meta.url)) {
  const boundaries = loadJson("contracts/boundaries.json");
  const violations = findViolations(boundaries.forbiddenReferences ?? [], {
    root: ".",
    allowlist: boundaries.allowlist ?? [],
  });
  if (violations.length) {
    console.error(violations.map((v) => `- ${v.file}: ${v.why}`).join("\n"));
    process.exit(1);
  }
}
