import assert from "node:assert/strict";
import test from "node:test";

import { execNode } from "./run-source-admission-pipeline.mjs";

test("admission pipeline은 1 MiB를 넘는 provider hash 증거를 수집한다", async () => {
  const expectedSize = 2 * 1024 * 1024;
  const { stdout } = await execNode([
    "--eval",
    `process.stdout.write("x".repeat(${expectedSize}))`,
  ]);

  assert.equal(stdout.length, expectedSize);
});
