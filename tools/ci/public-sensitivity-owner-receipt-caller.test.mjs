import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("hub caller pins the common owner receipt engine and maps only its alert secret", async () => {
  const text = await readFile(new URL("../../.github/workflows/public-sensitivity-owner-receipt-caller.yml", import.meta.url), "utf8");
  assert.match(text, /workflow_dispatch:/);
  assert.match(text, /permissions:\s*\n\s*contents: read\s*\n\s*actions: read/);
  assert.match(text, /uses: AquilaXk\/easysubway\/\.github\/workflows\/public-sensitivity-owner-receipt\.yml@3d1590baa98c929ceabd0d2d44414cebcc643c6f/);
  assert.match(text, /D20_SECRET_SCANNING_ALERTS_READ_TOKEN: \$\{\{ secrets\.D20_SECRET_SCANNING_ALERTS_READ_TOKEN \}\}/);
  assert.doesNotMatch(text, /secrets:\s*inherit|@main|@master|issues: write|pull-requests: write|contents: write/);
});
