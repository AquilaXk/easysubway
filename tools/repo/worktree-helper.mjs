#!/usr/bin/env node

/**
 * Git Worktree Lifecycle Helper CLI for EasySubway ecosystem.
 *
 * Implements conventions specified in AGENTS.md Article 5:
 *   - Shared Root protection (root repos are read-only)
 *   - Worktree path format: /Volumes/MACSSD/Projects/GitProjects/easysubway-<component>-wt-<issue#>
 *   - Automated listing, branch tracking, creation, and pruning of merged worktrees.
 *
 * Usage:
 *   node tools/repo/worktree-helper.mjs list
 *   node tools/repo/worktree-helper.mjs create <hub|backend|data|mobile|platform> <issue-number> [branch-name]
 *   node tools/repo/worktree-helper.mjs prune [--dry-run]
 */

import { execFileSync } from 'node:child_process';
import { existsSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '../..');
const WORKSPACE_BASE = process.env.EASYSUBWAY_WORKSPACE_BASE || '/Volumes/MACSSD/Projects/GitProjects';

const COMPONENT_REPO_MAP = {
  hub: 'swieun-jihacheol',
  backend: 'easysubway-backend',
  data: 'easysubway-data',
  mobile: 'easysubway-mobile',
  platform: 'easysubway-platform',
};

export function parseArgs(argv = process.argv.slice(2)) {
  const [command, ...rest] = argv;
  return {
    command: command || 'list',
    args: rest,
  };
}

export function getWorktrees(repoDir) {
  try {
    const raw = execFileSync('git', ['worktree', 'list', '--porcelain'], {
      cwd: repoDir,
      encoding: 'utf8',
    });

    const entries = [];
    let current = {};

    for (const line of raw.split('\n')) {
      if (!line.trim()) {
        if (current.worktree) {
          entries.push(current);
          current = {};
        }
        continue;
      }

      const spaceIndex = line.indexOf(' ');
      const key = spaceIndex > 0 ? line.slice(0, spaceIndex) : line;
      const value = spaceIndex > 0 ? line.slice(spaceIndex + 1).trim() : true;

      if (key === 'worktree') current.worktree = value;
      else if (key === 'HEAD') current.head = value;
      else if (key === 'branch') current.branch = value.replace('refs/heads/', '');
      else if (key === 'bare') current.bare = true;
      else if (key === 'detached') current.detached = true;
    }

    if (current.worktree) entries.push(current);
    return entries;
  } catch (error) {
    return [];
  }
}

export function listAllWorktrees() {
  console.log('\n=== EasySubway Git Worktrees ===\n');

  for (const [component, repoName] of Object.entries(COMPONENT_REPO_MAP)) {
    const repoDir = path.join(WORKSPACE_BASE, repoName);
    if (!existsSync(repoDir)) continue;

    const worktrees = getWorktrees(repoDir);
    console.log(`📦 [${component.toUpperCase()}] ${repoName} (${worktrees.length} worktree(s))`);

    for (const wt of worktrees) {
      const isRoot = wt.worktree === repoDir;
      const label = isRoot ? ' [ROOT (Read-only)]' : '';
      console.log(`   - Path:   ${wt.worktree}${label}`);
      console.log(`     Branch: ${wt.branch || '(detached)'} @ ${wt.head ? wt.head.slice(0, 8) : 'unknown'}`);
    }
    console.log('');
  }
}

export function createWorktree(component, issueNumber, customBranch) {
  if (!component || !COMPONENT_REPO_MAP[component]) {
    console.error(`Invalid component: "${component}". Expected one of: ${Object.keys(COMPONENT_REPO_MAP).join(', ')}`);
    process.exit(1);
  }

  if (!issueNumber || !/^[0-9]+$/.test(issueNumber)) {
    console.error(`Invalid issue number: "${issueNumber}". Must be numeric.`);
    process.exit(1);
  }

  const repoName = COMPONENT_REPO_MAP[component];
  const repoDir = path.join(WORKSPACE_BASE, repoName);
  if (!existsSync(repoDir)) {
    console.error(`Repository directory not found: ${repoDir}`);
    process.exit(1);
  }

  const prefix = component === 'hub' ? 'easysubway-hub' : `easysubway-${component}`;
  const targetDir = path.join(WORKSPACE_BASE, `${prefix}-wt-${issueNumber}`);
  const branchName = customBranch || `feat/${component}-${issueNumber}`;

  if (existsSync(targetDir)) {
    console.error(`Target worktree directory already exists: ${targetDir}`);
    process.exit(1);
  }

  console.log(`Fetching latest origin/main in ${repoName}...`);
  try {
    execFileSync('git', ['fetch', 'origin', 'main'], { cwd: repoDir, stdio: 'inherit' });
  } catch (e) {
    console.warn(`Warning: failed to fetch origin/main: ${e.message}`);
  }

  console.log(`Creating worktree at: ${targetDir}`);
  console.log(`Branch: ${branchName} (based on origin/main)`);

  execFileSync('git', ['worktree', 'add', '-b', branchName, targetDir, 'origin/main'], {
    cwd: repoDir,
    stdio: 'inherit',
  });

  console.log(`\n✅ Worktree created successfully!`);
  console.log(`   To begin work: cd ${targetDir}\n`);
}

export function pruneWorktrees(options = {}) {
  const dryRun = options.dryRun || false;
  console.log(`\n=== Pruning Merged Worktrees (dryRun=${dryRun}) ===\n`);

  for (const [component, repoName] of Object.entries(COMPONENT_REPO_MAP)) {
    const repoDir = path.join(WORKSPACE_BASE, repoName);
    if (!existsSync(repoDir)) continue;

    const worktrees = getWorktrees(repoDir);
    for (const wt of worktrees) {
      if (wt.worktree === repoDir) continue; // Never remove root

      // Check if branch is merged into origin/main
      if (!wt.branch) continue;

      let isMerged = false;
      try {
        const mergedOutput = execFileSync('git', ['branch', '--merged', 'origin/main'], {
          cwd: repoDir,
          encoding: 'utf8',
        });
        const mergedBranches = mergedOutput.split('\n').map((b) => b.trim().replace(/^\*\s*/, ''));
        isMerged = mergedBranches.includes(wt.branch);
      } catch {
        // Ignored
      }

      if (isMerged) {
        console.log(`🗑️  Merged worktree found: ${wt.worktree} (Branch: ${wt.branch})`);
        if (!dryRun) {
          try {
            execFileSync('git', ['worktree', 'remove', '--force', wt.worktree], {
              cwd: repoDir,
              stdio: 'inherit',
            });
            console.log(`   Removed successfully.`);
          } catch (e) {
            console.error(`   Failed to remove: ${e.message}`);
          }
        }
      }
    }

    if (!dryRun) {
      try {
        execFileSync('git', ['worktree', 'prune'], { cwd: repoDir });
      } catch {}
    }
  }

  console.log('\nPrune scan complete.\n');
}

export function main() {
  const { command, args } = parseArgs();

  switch (command) {
    case 'list':
      listAllWorktrees();
      break;
    case 'create':
      createWorktree(args[0], args[1], args[2]);
      break;
    case 'prune':
    case 'clean':
      pruneWorktrees({ dryRun: args.includes('--dry-run') });
      break;
    default:
      console.log(`EasySubway Worktree Helper CLI

Commands:
  list                                    List all active worktrees across 5 repositories
  create <component> <issue#> [branch]   Create a new isolated worktree
  prune [--dry-run]                       Prune worktrees whose branches are merged into main
`);
      break;
  }
}

if (process.argv[1] === __filename) {
  main();
}
