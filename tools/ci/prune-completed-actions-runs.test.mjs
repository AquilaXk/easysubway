import assert from "node:assert/strict";
import test from "node:test";

import {
  configFromEnv,
  runCleanup,
  selectCleanupCandidates,
} from "./prune-completed-actions-runs.mjs";

const SHA = {
  open: "1".repeat(40),
  closed: "2".repeat(40),
  other: "3".repeat(40),
};

function run(id, headSha, createdAt = "2026-08-20T00:00:00.000Z") {
  return { id, status: "completed", head_sha: headSha, created_at: createdAt };
}

function field(args, name) {
  for (let index = 0; index < args.length - 1; index += 1) {
    if (args[index] === "-f" && args[index + 1].startsWith(`${name}=`)) {
      return args[index + 1].slice(name.length + 1);
    }
  }
  return undefined;
}

function fakeApi({ pulls = [[{ head: { sha: SHA.open } }], [{ head: { sha: SHA.open } }]], runs = [], remaining = 5000, deleteErrors = new Map() } = {}) {
  const deleted = [];
  let pullInventory = 0;
  const calls = [];
  async function api(args) {
    calls.push(args);
    const endpoint = args.find((token) => token === "rate_limit" || token.startsWith("repos/"));
    const methodIndex = args.indexOf("--method");
    const method = methodIndex >= 0 ? args[methodIndex + 1] : "GET";
    if (endpoint === "rate_limit") {
      return JSON.stringify({ resources: { core: { remaining } } });
    }
    if (endpoint.endsWith("/pulls")) {
      const page = Number(field(args, "page"));
      if (page !== 1) return "[]";
      return JSON.stringify(pulls[Math.min(pullInventory++, pulls.length - 1)]);
    }
    if (endpoint.endsWith("/actions/runs")) {
      return JSON.stringify({ workflow_runs: Number(field(args, "page")) === 1 ? runs : [] });
    }
    const runMatch = endpoint.match(/\/actions\/runs\/(\d+)$/);
    if (!runMatch) throw new Error(`unexpected fake API request: ${args.join(" ")}`);
    const id = Number(runMatch[1]);
    const key = `${method}:${id}`;
    const queued = deleteErrors.get(key);
    if (queued?.length) {
      const status = queued.shift();
      if (status) throw Object.assign(new Error(`HTTP ${status}`), { status });
    }
    if (method === "DELETE") deleted.push(id);
    return method === "GET" ? JSON.stringify(run(id, SHA.closed)) : "";
  }
  return { api, calls, deleted };
}

const CONFIG = {
  repository: "AquilaXk/easysubway",
  minAgeHours: 48,
  maxDelete: 999,
  quotaReserve: 1000,
  failureResolutionHeadroom: 20,
  protectedRunIds: new Set([31280042807, 999999]),
};

test("환경 입력은 고정 날짜 없이 current run과 explicit protected run을 결속한다", () => {
  const config = configFromEnv({
    GH_TOKEN: "redacted",
    GITHUB_REPOSITORY: "AquilaXk/easysubway",
    GITHUB_RUN_ID: "444",
    MIN_AGE_HOURS: "48",
    MAX_DELETE: "999",
    QUOTA_RESERVE: "1000",
    FAILURE_RESOLUTION_HEADROOM: "20",
    PROTECTED_RUN_IDS: "31280042807, 555",
  });
  assert.deepEqual([...config.protectedRunIds], [31280042807, 555, 444]);
  assert.equal(config.minAgeHours, 48);
});

test("candidate 선택은 completed cutoff를 재검증하고 open head와 protected run을 제외한다", () => {
  const selected = selectCleanupCandidates({
    runs: [
      run(31280042807, SHA.closed),
      run(2, SHA.open),
      run(4, SHA.other, "2026-08-19T00:00:00.000Z"),
      run(3, SHA.closed, "2026-08-18T00:00:00.000Z"),
    ],
    before: "2026-08-24T00:00:00.000Z",
    openHeadShas: new Set([SHA.open]),
    protectedRunIds: new Set([31280042807]),
  });
  assert.deepEqual(selected, [3, 4]);
});

test("quota reserve와 resolution headroom을 제외한 exact oldest batch만 삭제한다", async () => {
  const fake = fakeApi({
    runs: [run(3, SHA.closed, "2026-08-18T00:00:00.000Z"), run(4, SHA.other), run(5, SHA.closed)],
    remaining: 1022,
  });
  const result = await runCleanup(CONFIG, { api: fake.api, now: new Date("2026-08-26T00:00:00.000Z") });
  assert.equal(result.deleted, 2);
  assert.deepEqual(fake.deleted, [3, 4]);
});

test("quota가 reserve와 resolution headroom만 남기면 mutation 0으로 종료한다", async () => {
  const fake = fakeApi({ runs: [run(3, SHA.closed)], remaining: 1020 });
  const result = await runCleanup(CONFIG, { api: fake.api, now: new Date("2026-08-26T00:00:00.000Z") });
  assert.equal(result.reason, "quota-reserve");
  assert.deepEqual(fake.deleted, []);
});

test("open PR inventory가 selection 중 바뀌면 첫 DELETE 전에 fail closed한다", async () => {
  const fake = fakeApi({
    pulls: [[{ head: { sha: SHA.open } }], [{ head: { sha: SHA.other } }]],
    runs: [run(3, SHA.closed)],
  });
  await assert.rejects(
    runCleanup(CONFIG, { api: fake.api, now: new Date("2026-08-26T00:00:00.000Z") }),
    /open pull request inventory changed/,
  );
  assert.deepEqual(fake.deleted, []);
});

test("DELETE 504 뒤 exact GET 404는 삭제 반영으로 한 번만 확인한다", async () => {
  const fake = fakeApi({
    pulls: [[], []],
    runs: [run(3, SHA.closed)],
    remaining: 1050,
    deleteErrors: new Map([["DELETE:3", [504]], ["GET:3", [404]]]),
  });
  const result = await runCleanup(CONFIG, { api: fake.api, now: new Date("2026-08-26T00:00:00.000Z") });
  assert.equal(result.counts["timeout-confirmed-absent"], 1);
  assert.deepEqual(fake.deleted, []);
});

test("DELETE 504 뒤 run이 존재하면 headroom 안에서 한 번만 재시도한다", async () => {
  const fake = fakeApi({
    pulls: [[], []],
    runs: [run(3, SHA.closed)],
    remaining: 1050,
    deleteErrors: new Map([["DELETE:3", [504, undefined]]]),
  });
  const result = await runCleanup(CONFIG, { api: fake.api, now: new Date("2026-08-26T00:00:00.000Z") });
  assert.equal(result.counts["timeout-retried"], 1);
  assert.deepEqual(fake.deleted, [3]);
});
