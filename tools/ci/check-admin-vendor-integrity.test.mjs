import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { checkAdminVendorIntegrity } from "./check-admin-vendor-integrity.mjs";

test("광고 creative ID HTML pattern은 v mode에서 route-safe 경계를 유지한다", async () => {
  const template = await readFile(
    path.resolve(import.meta.dirname, "../../backend/src/main/resources/templates/admin/ads/list.html"),
    "utf8",
  );
  const input = template.match(/<input\b[^>]*\bid="creative-id"[^>]*>/)?.[0];
  const pattern = input?.match(/\bpattern="([^"]+)"/)?.[1];
  assert.ok(pattern, "creative-id pattern missing");
  assert.doesNotThrow(() => new RegExp(pattern, "v"));

  const constraint = new RegExp(`^(?:${pattern})$`, "v");
  for (const value of [".", "..", "a/b"]) assert.equal(constraint.test(value), false, value);
  for (const value of ["A", ".banner", "a..b", "A._-".repeat(16)]) {
    assert.equal(constraint.test(value), true, value);
  }
});

test("admin vendor integrity check passes matching SHA256SUMS and SRI", async () => {
  const root = await fixtureRoot("console.log('ok');");
  assert.deepEqual(checkAdminVendorIntegrity(root), {
    checkedVendorFiles: 1,
    checkedTemplateScripts: 1,
  });
});

test("admin vendor integrity check fails stale SRI", async () => {
  const root = await fixtureRoot("console.log('ok');", "sha384-bad");
  assert.throws(
    () => checkAdminVendorIntegrity(root),
    /integrity mismatch/,
  );
});

test("admin vendor integrity check fails when one duplicate vendor ref has stale SRI", async () => {
  const root = await duplicateVendorRefFixtureRoot("console.log('ok');");
  assert.throws(
    () => checkAdminVendorIntegrity(root),
    /integrity mismatch/,
  );
});

test("admin vendor integrity check passes stylesheet vendor refs", async () => {
  const root = await stylesheetFixtureRoot("body { color: #111; }");
  assert.deepEqual(checkAdminVendorIntegrity(root), {
    checkedVendorFiles: 1,
    checkedTemplateScripts: 1,
  });
});

test("admin vendor integrity check blocks inline scripts", async () => {
  const root = await fixtureRoot("console.log('ok');");
  await writeFile(
    path.join(root, "backend/src/main/resources/templates/admin/inline-script.html"),
    "<script>alert(1)</script>",
  );
  assert.throws(
    () => checkAdminVendorIntegrity(root),
    /inline <script> is not allowed/,
  );
});

test("admin vendor integrity check blocks inline handlers", async () => {
  const root = await fixtureRoot("console.log('ok');");
  await writeFile(
    path.join(root, "backend/src/main/resources/templates/admin/inline.html"),
    "<button onclick=\"alert(1)\">bad</button>",
  );
  assert.throws(
    () => checkAdminVendorIntegrity(root),
    /inline event handler is not allowed/,
  );
});

async function fixtureRoot(vendorSource, integrityOverride) {
  const root = await mkdtemp(path.join(tmpdir(), "admin-vendor-"));
  const vendorDir = path.join(root, "backend/src/main/resources/static/vendor/example-1.0.0");
  const adminTemplates = path.join(root, "backend/src/main/resources/templates/admin");
  const operatorTemplates = path.join(root, "backend/src/main/resources/templates/operator");
  await mkdir(vendorDir, { recursive: true });
  await mkdir(adminTemplates, { recursive: true });
  await mkdir(operatorTemplates, { recursive: true });
  const vendorFile = path.join(vendorDir, "example.js");
  await writeFile(vendorFile, vendorSource);
  const sha256 = createHash("sha256").update(vendorSource).digest("hex");
  const sha384 = createHash("sha384").update(vendorSource).digest("base64");
  await writeFile(path.join(vendorDir, "SHA256SUMS.txt"), `${sha256}  example.js\n`);
  await writeFile(
    path.join(adminTemplates, "page.html"),
    `<script th:src="@{/vendor/example-1.0.0/example.js}" integrity="${integrityOverride ?? `sha384-${sha384}`}" crossorigin="anonymous" defer></script>`,
  );
  return root;
}

async function stylesheetFixtureRoot(vendorSource) {
  const root = await mkdtemp(path.join(tmpdir(), "admin-vendor-"));
  const vendorDir = path.join(root, "backend/src/main/resources/static/vendor/example-1.0.0");
  const adminTemplates = path.join(root, "backend/src/main/resources/templates/admin");
  const operatorTemplates = path.join(root, "backend/src/main/resources/templates/operator");
  await mkdir(vendorDir, { recursive: true });
  await mkdir(adminTemplates, { recursive: true });
  await mkdir(operatorTemplates, { recursive: true });
  const vendorFile = path.join(vendorDir, "example.css");
  await writeFile(vendorFile, vendorSource);
  const sha256 = createHash("sha256").update(vendorSource).digest("hex");
  const sha384 = createHash("sha384").update(vendorSource).digest("base64");
  await writeFile(path.join(vendorDir, "SHA256SUMS.txt"), `${sha256}  example.css\n`);
  await writeFile(
    path.join(adminTemplates, "page.html"),
    `<link rel="stylesheet" th:href="@{/vendor/example-1.0.0/example.css}" integrity="sha384-${sha384}" crossorigin="anonymous">`,
  );
  return root;
}

async function duplicateVendorRefFixtureRoot(vendorSource) {
  const root = await mkdtemp(path.join(tmpdir(), "admin-vendor-"));
  const vendorDir = path.join(root, "backend/src/main/resources/static/vendor/example-1.0.0");
  const adminTemplates = path.join(root, "backend/src/main/resources/templates/admin");
  const operatorTemplates = path.join(root, "backend/src/main/resources/templates/operator");
  await mkdir(vendorDir, { recursive: true });
  await mkdir(adminTemplates, { recursive: true });
  await mkdir(operatorTemplates, { recursive: true });
  const vendorFile = path.join(vendorDir, "example.js");
  await writeFile(vendorFile, vendorSource);
  const sha256 = createHash("sha256").update(vendorSource).digest("hex");
  const sha384 = createHash("sha384").update(vendorSource).digest("base64");
  await writeFile(path.join(vendorDir, "SHA256SUMS.txt"), `${sha256}  example.js\n`);
  await writeFile(
    path.join(adminTemplates, "page.html"),
    `<script th:src="@{/vendor/example-1.0.0/example.js}" integrity="sha384-stale" crossorigin="anonymous" defer></script>`,
  );
  await writeFile(
    path.join(operatorTemplates, "page.html"),
    `<script th:src="@{/vendor/example-1.0.0/example.js}" integrity="sha384-${sha384}" crossorigin="anonymous" defer></script>`,
  );
  return root;
}
