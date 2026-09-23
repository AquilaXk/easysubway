import assert from 'node:assert/strict';
import test from 'node:test';
import { getWorktrees, parseArgs } from './worktree-helper.mjs';

test('parseArgs parses list command by default', () => {
  const result = parseArgs([]);
  assert.equal(result.command, 'list');
  assert.deepEqual(result.args, []);
});

test('parseArgs parses create command and arguments correctly', () => {
  const result = parseArgs(['create', 'backend', '400', 'feat/test']);
  assert.equal(result.command, 'create');
  assert.deepEqual(result.args, ['backend', '400', 'feat/test']);
});

test('parseArgs parses prune command with --dry-run', () => {
  const result = parseArgs(['prune', '--dry-run']);
  assert.equal(result.command, 'prune');
  assert.deepEqual(result.args, ['--dry-run']);
});

test('getWorktrees returns array of worktrees for repository', () => {
  const worktrees = getWorktrees('.');
  assert.ok(Array.isArray(worktrees));
  assert.ok(worktrees.length >= 1);
  assert.ok(worktrees.some((w) => w.branch === 'main' || w.worktree.includes('swieun-jihacheol')));
});

test('getWorktrees returns empty array for non-existent directory', () => {
  const worktrees = getWorktrees('/tmp/non-existent-repo-path-12345');
  assert.deepEqual(worktrees, []);
});
