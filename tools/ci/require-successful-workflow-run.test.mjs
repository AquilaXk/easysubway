import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const root = process.cwd();
const scriptPath = "tools/ci/require-successful-workflow-run.mjs";
const expectedSha = "a".repeat(40);
const expectedName = "Production route API closure evidence";

function successfulRun(overrides = {}) {
  return {
    id: 123456,
    name: expectedName,
    head_sha: expectedSha,
    head_branch: "main",
    event: "push",
    status: "completed",
    conclusion: "success",
    updated_at: new Date().toISOString(),
    ...overrides,
  };
}

async function invoke(workflowRuns, totalCount = Array.isArray(workflowRuns) ? workflowRuns.length : 0) {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-workflow-run-"));
  const responsePath = path.join(dir, "response.json");
  await writeFile(responsePath, JSON.stringify({ total_count: totalCount, workflow_runs: workflowRuns }));
  try {
    return await execFileAsync(
      "node",
      [
        scriptPath,
        responsePath,
        expectedSha,
        expectedName,
        "push,workflow_dispatch",
        "main",
        "3600",
      ],
      { cwd: root, encoding: "utf8" },
    );
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

test("exact SHA의 completed/success workflow run만 승인한다", async () => {
  const pushResult = await invoke([successfulRun()]);
  const dispatchResult = await invoke([successfulRun({ event: "workflow_dispatch" })]);

  assert.equal(pushResult.stdout, "validated_workflow_run_id=123456\n");
  assert.equal(pushResult.stderr, "");
  assert.equal(dispatchResult.stdout, "validated_workflow_run_id=123456\n");
  assert.equal(dispatchResult.stderr, "");
});

test("workflow run이 없거나 유효 기간이 지났을 때만 unavailable로 구분한다", async () => {
  for (const workflowRuns of [
    [],
    [successfulRun({ updated_at: new Date(Date.now() - 3_601_000).toISOString() })],
  ]) {
    await assert.rejects(invoke(workflowRuns), (error) => {
      assert.equal(error.code, 3);
      assert.match(error.stderr, /required successful workflow run is unavailable/);
      return true;
    });
  }
});

test("workflow run evidence가 malformed 또는 identity 불일치면 trust failure로 중단한다", async () => {
  for (const mismatch of [
    { head_sha: "b".repeat(40) },
    { name: "CI" },
    { head_branch: "release" },
    { event: "pull_request" },
    { status: "in_progress" },
    { conclusion: "failure" },
    { id: "123456" },
    { updated_at: "not-a-timestamp" },
  ]) {
    await assert.rejects(invoke([successfulRun(mismatch)]), (error) => {
      assert.equal(error.code, 1);
      assert.match(error.stderr, /workflow runs response is inconsistent/);
      return true;
    });
  }

  for (const args of [[null], [[successfulRun()], 2]]) {
    await assert.rejects(invoke(...args), (error) => {
      assert.equal(error.code, 1);
      assert.match(error.stderr, /workflow runs response is inconsistent/);
      return true;
    });
  }
});
