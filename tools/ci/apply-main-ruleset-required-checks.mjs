#!/usr/bin/env node
// Compute the main branch ruleset payload whose required_status_checks are in
// line with the CI jobs that must gate merges (issue #1685). This is a pure
// transform — it does NOT call the GitHub API itself; the owner runs the gh
// get/put around it, keeping the irreversible governance change explicit and
// out of any spawned process.
//
// Usage (owner-run):
//   gh api repos/AquilaXk/easysubway/rulesets/17584352 > current.json
//   node tools/ci/apply-main-ruleset-required-checks.mjs \
//     --input current.json --output updated.json --backup ruleset-backup.json
//   # review updated.json, then apply:
//   gh api -X PUT repos/AquilaXk/easysubway/rulesets/17584352 --input updated.json
//
// The context list is the single source of truth shared (via the contract test)
// with ci.yml job names and the automerge-queue coordinator fallback.
import { readFileSync, writeFileSync } from "node:fs";
import { argValue } from "../release/summary-validation-utils.mjs";

export const MAIN_RULESET_ID = "17584352";

// 1:1 with the ci.yml job `name:` values. Renaming a job here without updating
// ci.yml (or vice versa) is caught by repository-contract.test.mjs.
export const REQUIRED_STATUS_CHECK_CONTEXTS = [
  "Changes",
  "Repository CI",
  "Admin QA Gates",
  "Backend CI",
  "Mobile App CI",
  "Android CI",
  "Release Gate Consistency",
  "PR Title",
];

// Returns a new ruleset object whose required_status_checks rule contains every
// context in `contexts`, plus the list of contexts that were added. Existing
// contexts, other rules, and the strict policy flag are preserved.
export function ensureRequiredChecks(ruleset, contexts) {
  const next = structuredClone(ruleset);
  const rule = (next.rules ?? []).find((entry) => entry.type === "required_status_checks");
  if (!rule) {
    throw new Error("ruleset has no required_status_checks rule");
  }
  const existing = rule.parameters.required_status_checks ?? [];
  const present = new Set(existing.map((check) => check.context));
  const added = [];
  for (const context of contexts) {
    if (!present.has(context)) {
      existing.push({ context });
      added.push(context);
    }
  }
  rule.parameters.required_status_checks = existing;
  return { ruleset: next, added };
}

// The GitHub PUT rejects the read-only envelope fields returned by GET.
export function toWritableRuleset(ruleset) {
  const { name, target, enforcement, bypass_actors, conditions, rules } = ruleset;
  return { name, target, enforcement, bypass_actors, conditions, rules };
}

function main() {
  const args = process.argv.slice(2);
  const inputPath = argValue(args, "--input");
  if (!inputPath) {
    throw new Error("--input <ruleset-json> is required (gh api repos/.../rulesets/17584352 > current.json)");
  }
  const outputPath = argValue(args, "--output");
  const backupPath = argValue(args, "--backup");

  const current = JSON.parse(readFileSync(inputPath, "utf8"));
  if (backupPath) {
    writeFileSync(backupPath, `${JSON.stringify(current, null, 2)}\n`);
    console.error(`backup written: ${backupPath}`);
  }

  const { ruleset, added } = ensureRequiredChecks(current, REQUIRED_STATUS_CHECK_CONTEXTS);
  if (added.length === 0) {
    console.error("required_status_checks already up to date; nothing to add");
  } else {
    console.error(`contexts to add: ${added.join(", ")}`);
  }

  const payload = `${JSON.stringify(toWritableRuleset(ruleset), null, 2)}\n`;
  if (outputPath) {
    writeFileSync(outputPath, payload);
    console.error(`updated ruleset written: ${outputPath} (review, then gh api -X PUT --input ${outputPath})`);
  } else {
    process.stdout.write(payload);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
