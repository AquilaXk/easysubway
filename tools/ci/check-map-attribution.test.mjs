import assert from "node:assert/strict";
import test from "node:test";
import path from "node:path";
import { execFile as execFileCallback } from "node:child_process";
import { promisify } from "node:util";

const execFile = promisify(execFileCallback);
const root = path.resolve(import.meta.dirname, "../..");

test("지도 asset license 누락은 실패한다", async () => {
  await assert.rejects(
    execFile(process.execPath, [
      "tools/ci/check-map-attribution.mjs",
      "tools/ci/fixtures/map-attribution-missing-license.json",
    ], { cwd: root }),
    /busan: missing license block/,
  );
});

test("번들 지도 manifest license는 완비되어 있다", async () => {
  await execFile(process.execPath, [
    "tools/ci/check-map-attribution.mjs",
    "apps/mobile/assets/datapacks/metro_map_pack/manifest.json",
  ], { cwd: root });
});
