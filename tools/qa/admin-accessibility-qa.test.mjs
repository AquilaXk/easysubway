import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const source = readFileSync(new URL("./admin-accessibility-qa.mjs", import.meta.url), "utf8");

test("admin accessibility QA script covers Phase 3 required routes and viewports", () => {
  for (const expected of [
    "/admin/dashboard/page",
    "/admin/reports/page",
    "/admin/stations/station-sangnoksu/page",
    "/admin/datapack/pipeline/page",
    "/admin/audits/page",
    "/operator/accessibility-report/page",
  ]) {
    assert.match(source, new RegExp(expected.replaceAll("/", "\\/")));
  }
  for (const expected of ["desktop-1280", "tablet-1024", "mobile-768", "desktop-1440", "mobile-390"]) {
    assert.match(source, new RegExp(expected));
  }
});

test("admin accessibility QA script captures text 200 percent reflow evidence on 1440 and 390", () => {
  assert.match(source, /TEXT_SCALE_FACTOR = 2/);
  assert.match(source, /TEXT_SCALE_VIEWPORTS = \["desktop-1440", "mobile-390"\]/);
  for (const expected of [
    "/admin/dashboard/page",
    "/admin/stations/page",
    "/admin/stations/station-sangnoksu/page",
    "/admin/datapack/pipeline/page",
    "/operator/accessibility-report/page",
  ]) {
    assert.match(source, new RegExp(expected.replaceAll("/", "\\/")));
  }
  assert.match(source, /report\.textScale\.push/);
  assert.match(source, /noHorizontalScroll: doc\.scrollWidth <= doc\.clientWidth/);
  assert.match(source, /clippedContainers/);
});

test("admin accessibility QA script captures login NONE and RETRY_WARNING public parity", () => {
  assert.match(source, /runLoginStatePass/);
  assert.match(source, /qa-nonexistent-/);
  assert.match(source, /login-\$\{surface\.key\}-none\.png/);
  assert.match(source, /login-\$\{surface\.key\}-retry-warning\.png/);
  assert.match(source, /RETRY_WARNING_COPY/);
  assert.match(source, /report\.loginParity = \{/);
  assert.match(source, /warningCopyParity/);
  assert.match(source, /did not render RETRY_WARNING after failed login/);
});

test("admin accessibility QA script verifies admin-table-scroll keyboard and focus outline", () => {
  assert.match(source, /keyboardTableCheck/);
  assert.match(source, /admin-table-scroll/);
  assert.match(source, /scrolledRight/);
  assert.match(source, /scrolledBackLeft/);
  assert.match(source, /outlineVisible/);
  assert.match(source, /ArrowRight/);
  assert.match(source, /ArrowLeft/);
});

test("admin accessibility QA script records manual-only screen reader and contrast work", () => {
  assert.match(source, /VoiceOver reading flow/);
  assert.match(source, /high-contrast visual inspection/);
  assert.match(source, /200 percent browser zoom visual inspection/);
});

test("admin accessibility QA script fails on serious and critical axe violations", () => {
  assert.match(source, /criticalAxeViolations/);
  assert.match(source, /seriousAxeViolations/);
  assert.match(source, /impact === "critical"/);
  assert.match(source, /impact === "serious"/);
  assert.match(source, /throw new Error\(`blocking axe violations/);
});

test("admin accessibility QA script fails non-success page responses", () => {
  assert.match(source, /response\.status\(\)/);
  assert.match(source, /status < 200 \|\| status >= 300/);
  assert.match(source, /returned HTTP \$\{status\}/);
  assert.match(source, /did not return a page response/);
});
