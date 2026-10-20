import assert from "node:assert/strict";
import { isAbsolute } from "node:path";
import test from "node:test";

import { GH_EXECUTABLE_CANDIDATES, TEST_GH_EXECUTABLE_ENV, resolveGhExecutable } from "./gh-executable.mjs";

const FAKE_GH = "/tmp/fake-gh/gh";
const TEST_RUNNER_ENV = { NODE_TEST_CONTEXT: "child-v8" };

test("gh executable candidates are fixed absolute paths", () => {
  assert.ok(GH_EXECUTABLE_CANDIDATES.length > 0);
  for (const candidate of GH_EXECUTABLE_CANDIDATES) assert.ok(isAbsolute(candidate), candidate);
});

test("resolveGhExecutable returns the first existing fixed candidate, never a PATH lookup name", () => {
  const second = GH_EXECUTABLE_CANDIDATES[1];
  const exists = (candidate) => candidate === second || candidate === GH_EXECUTABLE_CANDIDATES.at(-1);
  assert.equal(resolveGhExecutable({ exists, env: {} }), second);
});

test("resolveGhExecutable returns null instead of falling back to a bare gh name", () => {
  assert.equal(resolveGhExecutable({ exists: () => false, env: {} }), null);
});

test("the test-only override is honored under the node test runner", () => {
  assert.equal(resolveGhExecutable({ exists: () => false, env: { ...TEST_RUNNER_ENV, [TEST_GH_EXECUTABLE_ENV]: FAKE_GH } }), FAKE_GH);
});

test("the test-only override is ignored outside the node test runner", () => {
  assert.equal(resolveGhExecutable({ exists: () => false, env: { [TEST_GH_EXECUTABLE_ENV]: FAKE_GH } }), null);
  assert.equal(resolveGhExecutable({ exists: (candidate) => candidate === GH_EXECUTABLE_CANDIDATES[0], env: { [TEST_GH_EXECUTABLE_ENV]: FAKE_GH } }), GH_EXECUTABLE_CANDIDATES[0]);
});

test("a relative test-only override is ignored", () => {
  assert.equal(resolveGhExecutable({ exists: () => false, env: { ...TEST_RUNNER_ENV, [TEST_GH_EXECUTABLE_ENV]: "gh" } }), null);
});
