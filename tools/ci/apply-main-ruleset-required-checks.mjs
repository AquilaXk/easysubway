#!/usr/bin/env node
// Bring the main branch ruleset's required_status_checks in line with the CI
// jobs that must gate merges (issue #1685). The live PUT is an irreversible
// governance change, so this tool defaults to a dry run and only mutates when
// invoked with --apply; it always writes a backup first for a rollback path.
//
// Usage (owner-run):
//   node tools/ci/apply-main-ruleset-required-checks.mjs --backup ruleset-backup.json
//     → dry run: prints which contexts would be added.
//   node tools/ci/apply-main-ruleset-required-checks.mjs --backup ruleset-backup.json --apply
//     → writes backup, then PUTs the updated ruleset.
//
// The context list is the single source of truth shared (via the contract test)
// with ci.yml job names and the automerge-queue coordinator fallback.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { argValue } from "../release/summary-validation-utils.mjs";

export const MAIN_RULESET_ID = "17584352";

// 1:1 with the ci.yml job `name:` values. Renaming a job here without updating
// ci.yml (or vice versa) is caught by repository-contract.test.mjs.
export const REQUIRED_STATUS_CHECK_CONTEXTS = [
  "Changes",
  "Repository CI",
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

// The GitHub PUT rejects read-only envelope fields returned by GET.
function toWritableRuleset(ruleset) {
  const { name, target, enforcement, bypass_actors, conditions, rules } = ruleset;
  return { name, target, enforcement, bypass_actors, conditions, rules };
}

function ghApi(args, stdin) {
  return execFileSync("gh", ["api", ...args], { encoding: "utf8", input: stdin });
}

function main() {
  const args = process.argv.slice(2);
  const apply = args.includes("--apply");
  const backupPath = argValue(args, "--backup");
  const repo = argValue(args, "--repo", process.env.GITHUB_REPOSITORY || "AquilaXk/easysubway");
  const inputPath = argValue(args, "--input");

  const current = inputPath
    ? JSON.parse(readFileSync(inputPath, "utf8"))
    : JSON.parse(ghApi([`repos/${repo}/rulesets/${MAIN_RULESET_ID}`]));

  if (backupPath) {
    writeFileSync(backupPath, `${JSON.stringify(current, null, 2)}\n`);
    console.error(`backup written: ${backupPath}`);
  }

  const { ruleset, added } = ensureRequiredChecks(current, REQUIRED_STATUS_CHECK_CONTEXTS);
  if (added.length === 0) {
    console.error("required_status_checks already up to date; nothing to add");
    return;
  }
  console.error(`contexts to add: ${added.join(", ")}`);

  if (!apply) {
    console.error("dry run (pass --apply to PUT the updated ruleset)");
    return;
  }
  if (!backupPath) {
    throw new Error("--backup is required with --apply (rollback path)");
  }

  const body = JSON.stringify(toWritableRuleset(ruleset));
  ghApi(["-X", "PUT", `repos/${repo}/rulesets/${MAIN_RULESET_ID}`, "--input", "-"], body);
  console.error("ruleset updated");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    main();
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
