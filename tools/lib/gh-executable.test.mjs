import assert from "node:assert/strict";
import { isAbsolute } from "node:path";
import test from "node:test";

import { GH_EXECUTABLE_CANDIDATES, resolveGhExecutable } from "./gh-executable.mjs";

test("gh executable candidates are fixed absolute paths", () => {
  assert.ok(GH_EXECUTABLE_CANDIDATES.length > 0);
  for (const candidate of GH_EXECUTABLE_CANDIDATES) assert.ok(isAbsolute(candidate), candidate);
});

test("resolveGhExecutable returns the first existing fixed candidate, never a PATH lookup name", () => {
  const second = GH_EXECUTABLE_CANDIDATES[1];
  assert.equal(resolveGhExecutable((candidate) => candidate === second || candidate === GH_EXECUTABLE_CANDIDATES.at(-1)), second);
});

test("resolveGhExecutable returns null instead of falling back to a bare gh name", () => {
  assert.equal(resolveGhExecutable(() => false), null);
});
