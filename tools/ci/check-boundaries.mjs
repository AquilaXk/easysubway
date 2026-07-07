#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { loadJson } from "./check-contracts.mjs";

export function findViolations(rules, { root = ".", allowlist = [] } = {}) {
  const allow = new Map(allowlist.map((entry) => [entry.file, entry]));
  const violations = [];
  for (const rule of rules) {
    for (const file of filesForRule(root, rule.from)) {
      const text = readFileSync(path.join(root, file), "utf8");
      if (!new RegExp(rule.pattern).test(text)) continue;
      const allowed = allow.get(file);
      if (allowed) {
        if (!allowed.reason || !allowed.expires) {
          violations.push({ file, why: "allowlist reason/expires 누락" });
        } else if (Date.parse(allowed.expires) < Date.now()) {
          violations.push({ file, why: `allowlist 만료: ${allowed.expires}` });
        }
        continue;
      }
      violations.push({ file, why: rule.reason });
    }
  }
  return violations;
}

function filesForRule(root, from) {
  if (root === ".") {
    try {
      return execFileSync("git", ["ls-files", from], { encoding: "utf8" })
        .split(/\r?\n/)
        .filter(Boolean);
    } catch {
      return [];
    }
  }
  return walk(path.join(root, from)).map((file) => path.relative(root, file));
}

function walk(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const name of readdirSync(dir)) {
    const file = path.join(dir, name);
    if (statSync(file).isDirectory()) out.push(...walk(file));
    else out.push(file);
  }
  return out;
}

if (import.meta.url === `file://${process.argv[1]}`) {
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
