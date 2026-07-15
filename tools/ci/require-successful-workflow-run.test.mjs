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

async function invoke(workflowRuns) {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-workflow-run-"));
  const responsePath = path.join(dir, "response.json");
  await writeFile(responsePath, JSON.stringify({ workflow_runs: workflowRuns }));
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

test("workflow identity나 성공 상태가 다르면 fail closed한다", async () => {
  for (const mismatch of [
    { head_sha: "b".repeat(40) },
    { name: "CI" },
    { head_branch: "release" },
    { event: "pull_request" },
    { status: "in_progress" },
    { conclusion: "failure" },
    { updated_at: new Date(Date.now() - 3_601_000).toISOString() },
    { updated_at: "not-a-timestamp" },
  ]) {
    await assert.rejects(
      invoke([successfulRun(mismatch)]),
      /required successful workflow run was not found/,
    );
  }
});
