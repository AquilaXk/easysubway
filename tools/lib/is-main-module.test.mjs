import assert from "node:assert/strict";
import path from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";
import { isMainModule } from "./is-main-module.mjs";

test("relative argv[1] matches absolute import.meta.url", () => {
  const abs = path.resolve("tools/lib/is-main-module.mjs");
  const meta = pathToFileURL(abs).href;
  assert.equal(isMainModule(meta, "tools/lib/is-main-module.mjs"), true);
  assert.equal(isMainModule(meta, abs), true);
  assert.equal(isMainModule(meta, "tools/ci/other.mjs"), false);
  assert.equal(isMainModule(meta, undefined), false);
});
