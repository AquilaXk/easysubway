import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const read = (file) => readFile(new URL(`../../.github/workflows/${file}`, import.meta.url), "utf8");

test("owner receipt workflow pins the reusable two-artifact protocol and separate alert secret", async () => {
  const text = await read("public-sensitivity-owner-receipt.yml");
  assert.match(text, /workflow_call:/);
  assert.doesNotMatch(text, /secrets:\s*inherit/);
  assert.match(text, /permissions:\s*\n\s*contents: read\s*\n\s*actions: read/);
  assert.match(text, /D20_SECRET_SCANNING_ALERTS_READ_TOKEN:/);
  assert.match(text, /REPO_CODE:.*'hub'.*'backend'.*'data'.*'mobile'.*'platform'/);
  assert.match(text, /d20-public-sensitivity-evidence-\$\{\{ env\.REPO_CODE \}\}-\$\{\{ github\.sha \}\}/);
  assert.match(text, /d20-public-sensitivity-owner-receipt-\$\{\{ env\.REPO_CODE \}\}-\$\{\{ github\.sha \}\}/);
  assert.match(text, /GH_TOKEN: \$\{\{ github\.token \}\}/);
  assert.match(text, /EVIDENCE_ARTIFACT_DIGEST: \$\{\{ steps\.evidence-upload\.outputs\.artifact-digest \}\}/);
  assert.match(text, /--evidence-digest "\$\{EVIDENCE_ARTIFACT_DIGEST\}"/);
  assert.match(text, /--evidence-input d20-evidence\/evidence\.json/);
  assert.ok(text.indexOf("Upload evidence first") < text.indexOf("Finalize receipt after evidence identity"));
  assert.ok(text.indexOf("Finalize receipt after evidence identity") < text.indexOf("Upload finalized handoff"));
  assert.match(text, /retention-days: 14/g);
  assert.match(text, /include-hidden-files: false/g);
  assert.match(text, /if-no-files-found: error/g);
  assert.match(text, /actions\/checkout@[0-9a-f]{40}/);
  assert.match(text, /actions\/setup-node@[0-9a-f]{40}/);
  assert.match(text, /actions\/upload-artifact@[0-9a-f]{40}/);
});

test("fan-in workflow uses its dedicated five-repository public-audit token and a write-once report", async () => {
  const text = await read("public-sensitivity-audit.yml");
  assert.match(text, /workflow_dispatch:/);
  assert.match(text, /D20_FIVE_REPO_PUBLIC_AUDIT_READ_TOKEN:/);
  assert.match(text, /GH_TOKEN: \$\{\{ secrets\.D20_FIVE_REPO_PUBLIC_AUDIT_READ_TOKEN \}\}/);
  assert.match(text, /--owner-receipts/);
  assert.match(text, /--output/);
  assert.match(text, /--runner-sha "\$\{GITHUB_SHA\}"/);
  assert.doesNotMatch(text, /GITHUB_TOKEN/);
  assert.doesNotMatch(text, /test -n "\$\{D20_FIVE_REPO_PUBLIC_AUDIT_READ_TOKEN\}"/);
  assert.match(text, /retention-days: 14/);
  assert.match(text, /if: \$\{\{ always\(\) \}\}[\s\S]*if-no-files-found: error/);
  assert.match(text, /actions\/checkout@[0-9a-f]{40}/);
  assert.match(text, /actions\/setup-node@[0-9a-f]{40}/);
  assert.match(text, /actions\/upload-artifact@[0-9a-f]{40}/);
});
