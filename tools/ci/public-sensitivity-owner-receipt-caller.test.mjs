import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("hub caller forwards the coordinator observed_at to the pinned common owner receipt engine", async () => {
  const text = await readFile(new URL("../../.github/workflows/public-sensitivity-owner-receipt-caller.yml", import.meta.url), "utf8");
  assert.match(text, /workflow_dispatch:\s*\n\s*inputs:\s*\n\s*observed_at:\s*\n\s*required: true\s*\n\s*type: string/);
  assert.match(text, /permissions:\s*\n\s*contents: read\s*\n\s*actions: read/);
  assert.match(text, /uses: AquilaXk\/easysubway\/\.github\/workflows\/public-sensitivity-owner-receipt\.yml@fa2f2602573651af6694e7f56077414b685987b9/);
  assert.match(text, /with:\s*\n\s*observed_at: \$\{\{ inputs\.observed_at \}\}/);
  assert.match(text, /D20_SECRET_SCANNING_ALERTS_READ_TOKEN: \$\{\{ secrets\.D20_SECRET_SCANNING_ALERTS_READ_TOKEN \}\}/);
  assert.doesNotMatch(text, /observed_at:\s*\n\s*default:|secrets:\s*inherit|@main|@master|issues: write|pull-requests: write|contents: write/);
  assert.equal(validateCallerWorkflow(text), true);
});

test("caller contract rejects permission, invocation, and secret expansions", () => {
  const canonical = `name: Public Sensitivity Owner Receipt Caller

on:
  workflow_dispatch:
    inputs:
      observed_at:
        required: true
        type: string

permissions:
  contents: read
  actions: read

jobs:
  receipt:
    uses: AquilaXk/easysubway/.github/workflows/public-sensitivity-owner-receipt.yml@fa2f2602573651af6694e7f56077414b685987b9
    with:
      observed_at: \${{ inputs.observed_at }}
    secrets:
      D20_SECRET_SCANNING_ALERTS_READ_TOKEN: \${{ secrets.D20_SECRET_SCANNING_ALERTS_READ_TOKEN }}`;
  for (const mutation of [
    canonical.replace("  actions: read", "  actions: read\n  id-token: write"),
    canonical.replace("workflow_dispatch:", "push:"),
    canonical.replace("        required: true", "        required: false"),
    canonical.replace("        type: string", "        default: 2026-08-10T00:00:00.000Z\n        type: string"),
    canonical.replace("      observed_at:", "      observedAt:"),
    canonical.replace("@fa2f2602573651af6694e7f56077414b685987b9", "@3d1590baa98c929ceabd0d2d44414cebcc643c6f"),
    canonical.replace("@fa2f2602573651af6694e7f56077414b685987b9", "@main"),
    canonical.replace("    with:\n      observed_at: \${{ inputs.observed_at }}\n", ""),
    canonical.replace("      observed_at: \${{ inputs.observed_at }}", "      observed_at: \${{ inputs.observedAt }}"),
    canonical.replace("    secrets:", "    with:\n      unsafe: true\n    secrets:"),
    canonical.replace("D20_SECRET_SCANNING_ALERTS_READ_TOKEN }}", "D20_SECRET_SCANNING_ALERTS_READ_TOKEN }}\n      EXTRA: \${{ secrets.EXTRA }}"),
    `${canonical}\n  extra:\n    runs-on: ubuntu-latest`,
  ]) assert.equal(validateCallerWorkflow(mutation), false);
});

function validateCallerWorkflow(value) {
  const expected = `name: Public Sensitivity Owner Receipt Caller

on:
  workflow_dispatch:
    inputs:
      observed_at:
        required: true
        type: string

permissions:
  contents: read
  actions: read

jobs:
  receipt:
    uses: AquilaXk/easysubway/.github/workflows/public-sensitivity-owner-receipt.yml@fa2f2602573651af6694e7f56077414b685987b9
    with:
      observed_at: \${{ inputs.observed_at }}
    secrets:
      D20_SECRET_SCANNING_ALERTS_READ_TOKEN: \${{ secrets.D20_SECRET_SCANNING_ALERTS_READ_TOKEN }}`;
  return value.trimEnd() === expected;
}
