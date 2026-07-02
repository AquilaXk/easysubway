import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { cp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");

test("mobile release claim scan passes current app and store copy", async () => {
  const { stdout } = await execFileAsync(process.execPath, ["tools/ci/check-mobile-release-claims.mjs"], { cwd: root });
  assert.match(stdout, /mobile release claim scan passed: 상록수·사당 검증 pilot/);
});

test("mobile release claim scan rejects forbidden app copy", async () => {
  const tmp = path.join(tmpdir(), `mobile-claim-scan-${Date.now()}`);
  await rm(tmp, { recursive: true, force: true });
  await mkdir(path.join(tmp, "apps/mobile"), { recursive: true });
  await cp(path.join(root, "apps/mobile/lib"), path.join(tmp, "apps/mobile/lib"), { recursive: true });
  await cp(path.join(root, "apps/mobile/release"), path.join(tmp, "apps/mobile/release"), { recursive: true });
  await writeFile(path.join(tmp, "apps/mobile/lib/bad_claim.dart"), "const bad = '모든 역 지원';\n");

  await assert.rejects(
    execFileAsync(process.execPath, [
      path.join(root, "tools/ci/check-mobile-release-claims.mjs"),
      "--root",
      tmp,
    ], { cwd: root }),
    /forbidden release claim: 모든 역/,
  );
});
