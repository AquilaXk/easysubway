#!/usr/bin/env node

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { fileURLToPath } from "node:url";

const execFileAsync = promisify(execFile);
const API_PAGE_SIZE = 100;
const ACTIONS_RESULT_PAGES = 10;
const OPEN_PULL_REQUEST_PAGE_LIMIT = 100;

class GitHubCallError extends Error {
  constructor(message, status) {
    super(message);
    this.name = "GitHubCallError";
    this.status = status;
  }
}

function positiveInteger(value, name) {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
}

function repositoryName(value) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(value ?? "")) {
    throw new Error("GITHUB_REPOSITORY must be OWNER/REPO");
  }
  return value;
}

function protectedRunIds(value) {
  const ids = new Set();
  for (const token of String(value ?? "").split(/[\s,]+/).filter(Boolean)) {
    ids.add(positiveInteger(token, "PROTECTED_RUN_IDS"));
  }
  return ids;
}

export function configFromEnv(env = process.env) {
  if (!env.GH_TOKEN) throw new Error("GH_TOKEN is required");
  const protectedIds = protectedRunIds(env.PROTECTED_RUN_IDS);
  protectedIds.add(positiveInteger(env.GITHUB_RUN_ID, "GITHUB_RUN_ID"));
  return {
    repository: repositoryName(env.GITHUB_REPOSITORY),
    minAgeHours: positiveInteger(env.MIN_AGE_HOURS, "MIN_AGE_HOURS"),
    maxDelete: positiveInteger(env.MAX_DELETE, "MAX_DELETE"),
    quotaReserve: positiveInteger(env.QUOTA_RESERVE, "QUOTA_RESERVE"),
    failureResolutionHeadroom: positiveInteger(
      env.FAILURE_RESOLUTION_HEADROOM,
      "FAILURE_RESOLUTION_HEADROOM",
    ),
    protectedRunIds: protectedIds,
  };
}

function errorStatus(error) {
  if (Number.isInteger(error?.status)) return error.status;
  const match = String(error?.message ?? "").match(/HTTP\s+(\d{3})\b/);
  return match ? Number(match[1]) : undefined;
}

async function callGh(args) {
  try {
    const { stdout } = await execFileAsync("gh", args, {
      encoding: "utf8",
      maxBuffer: 16 * 1024 * 1024,
    });
    return stdout;
  } catch (error) {
    const message = String(error?.stderr || error?.message || "gh command failed").trim();
    throw new GitHubCallError(message, errorStatus({ message }));
  }
}

function parseJson(text, label) {
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${label} returned malformed JSON`);
  }
}

async function listOpenPullRequestHeads(repository, api) {
  const heads = new Set();
  for (let page = 1; page <= OPEN_PULL_REQUEST_PAGE_LIMIT; page += 1) {
    const rows = parseJson(await api([
      "api", "--method", "GET", `repos/${repository}/pulls`,
      "-f", "state=open", "-f", `per_page=${API_PAGE_SIZE}`, "-f", `page=${page}`,
    ]), "open pull request listing");
    if (!Array.isArray(rows)) throw new Error("open pull request listing schema mismatch");
    for (const pullRequest of rows) {
      const sha = pullRequest?.head?.sha;
      if (typeof sha !== "string" || !/^[a-f0-9]{40}$/.test(sha)) {
        throw new Error("open pull request head schema mismatch");
      }
      heads.add(sha);
    }
    if (rows.length < API_PAGE_SIZE) return heads;
  }
  throw new Error("open pull request inventory exceeds the safety page limit");
}

async function listCompletedRuns(repository, before, api) {
  const runs = [];
  for (let page = 1; page <= ACTIONS_RESULT_PAGES; page += 1) {
    const payload = parseJson(await api([
      "api", "--method", "GET", `repos/${repository}/actions/runs`,
      "-f", "status=completed", "-f", `created=<=${before}`,
      "-f", `per_page=${API_PAGE_SIZE}`, "-f", `page=${page}`,
    ]), "completed workflow-run listing");
    if (!Array.isArray(payload?.workflow_runs)) {
      throw new Error("completed workflow-run listing schema mismatch");
    }
    runs.push(...payload.workflow_runs);
    if (payload.workflow_runs.length < API_PAGE_SIZE) break;
  }
  return runs;
}

function equalSets(left, right) {
  return left.size === right.size && [...left].every((value) => right.has(value));
}

export function selectCleanupCandidates({ runs, before, openHeadShas, protectedRunIds }) {
  const beforeMs = Date.parse(before);
  if (!Number.isFinite(beforeMs)) throw new Error("before must be an ISO timestamp");
  const seen = new Set();
  const candidates = [];
  for (const run of runs) {
    if (!Number.isSafeInteger(run?.id) || run.id <= 0) {
      throw new Error("workflow run id schema mismatch");
    }
    if (seen.has(run.id)) throw new Error(`duplicate workflow run ${run.id}`);
    seen.add(run.id);
    if (run.status !== "completed") throw new Error(`workflow run ${run.id} is not completed`);
    if (typeof run.head_sha !== "string" || !/^[a-f0-9]{40}$/.test(run.head_sha)) {
      throw new Error(`workflow run ${run.id} head schema mismatch`);
    }
    const createdAt = Date.parse(run.created_at);
    if (!Number.isFinite(createdAt) || createdAt > beforeMs) {
      throw new Error(`workflow run ${run.id} is outside the requested cutoff`);
    }
    if (protectedRunIds.has(run.id) || openHeadShas.has(run.head_sha)) continue;
    candidates.push({ id: run.id, createdAt });
  }
  candidates.sort((left, right) => left.createdAt - right.createdAt || left.id - right.id);
  return candidates.map(({ id }) => id);
}

async function deleteRun(repository, runId, api, resolution) {
  try {
    await api(["api", "--method", "DELETE", `repos/${repository}/actions/runs/${runId}`]);
    return "direct";
  } catch (error) {
    if (errorStatus(error) !== 504) throw error;
  }

  if (resolution.used >= resolution.limit) {
    throw new Error("failure-resolution headroom exhausted before existence check");
  }
  resolution.used += 1;
  try {
    await api(["api", "--method", "GET", `repos/${repository}/actions/runs/${runId}`]);
  } catch (error) {
    if (errorStatus(error) === 404) return "timeout-confirmed-absent";
    throw error;
  }

  if (resolution.used >= resolution.limit) {
    throw new Error("failure-resolution headroom exhausted before bounded retry");
  }
  resolution.used += 1;
  await api(["api", "--method", "DELETE", `repos/${repository}/actions/runs/${runId}`]);
  return "timeout-retried";
}

export async function runCleanup(config, { api = callGh, now = new Date() } = {}) {
  const before = new Date(now.getTime() - config.minAgeHours * 60 * 60 * 1000).toISOString();
  const firstOpenHeads = await listOpenPullRequestHeads(config.repository, api);
  const runs = await listCompletedRuns(config.repository, before, api);
  const secondOpenHeads = await listOpenPullRequestHeads(config.repository, api);
  if (!equalSets(firstOpenHeads, secondOpenHeads)) {
    throw new Error("open pull request inventory changed before deletion");
  }
  const candidates = selectCleanupCandidates({
    runs,
    before,
    openHeadShas: secondOpenHeads,
    protectedRunIds: config.protectedRunIds,
  });
  const rateLimit = parseJson(await api(["api", "rate_limit"]), "rate limit");
  const remaining = rateLimit?.resources?.core?.remaining;
  if (!Number.isSafeInteger(remaining) || remaining < 0) {
    throw new Error("core rate-limit schema mismatch");
  }
  const deleteCapacity = Math.max(
    0,
    remaining - config.quotaReserve - config.failureResolutionHeadroom,
  );
  const targets = candidates.slice(0, Math.min(config.maxDelete, deleteCapacity));
  if (targets.length === 0) {
    return {
      repository: config.repository,
      before,
      selected: 0,
      deleted: 0,
      reason: candidates.length === 0 ? "no-safe-candidates" : "quota-reserve",
      coreRemaining: remaining,
    };
  }

  const counts = { direct: 0, "timeout-confirmed-absent": 0, "timeout-retried": 0 };
  const resolution = { used: 0, limit: config.failureResolutionHeadroom };
  for (const runId of targets) {
    const disposition = await deleteRun(config.repository, runId, api, resolution);
    counts[disposition] += 1;
  }
  return {
    repository: config.repository,
    before,
    selected: targets.length,
    deleted: Object.values(counts).reduce((sum, count) => sum + count, 0),
    counts,
    coreRemainingBeforeDelete: remaining,
    quotaReserve: config.quotaReserve,
  };
}

function isMainModule() {
  return process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
}

function safeMessage(error) {
  return String(error?.message ?? error)
    .replace(/\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)\b/g, "[REDACTED]");
}

if (isMainModule()) {
  try {
    const result = await runCleanup(configFromEnv());
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } catch (error) {
    process.stderr.write(`${safeMessage(error)}\n`);
    process.exitCode = 1;
  }
}
