import assert from "node:assert/strict";
import test from "node:test";
import path from "node:path";
import { readFileSync } from "node:fs";
import { execFile as execFileCallback } from "node:child_process";
import { promisify } from "node:util";
import { validateMapAttributionManifest } from "./check-map-attribution.mjs";

const execFile = promisify(execFileCallback);
const root = path.resolve(import.meta.dirname, "../..");

function fixture(name) {
  return JSON.parse(readFileSync(path.join(root, "tools/ci/fixtures", name), "utf8"));
}

test("지도 asset license 누락은 실패한다", () => {
  assert.deepEqual(validateMapAttributionManifest(fixture("map-attribution-missing-license.json")), [
    "busan: missing license block",
  ]);
});

test("지도 asset license boolean 타입 오류는 실패한다", () => {
  assert.ok(
    validateMapAttributionManifest(fixture("map-attribution-invalid-boolean.json")).includes(
      "busan: license.attributionRequired must be boolean",
    ),
  );
});

test("번들 지도 manifest license는 완비되어 있다", async () => {
  await execFile(process.execPath, ["tools/ci/check-map-attribution.mjs"], { cwd: root });
});
