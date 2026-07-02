import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { execFile as execFileCallback } from "node:child_process";
import { promisify } from "node:util";

const execFile = promisify(execFileCallback);
const root = path.resolve(import.meta.dirname, "../..");

test("지도 asset license 누락은 실패한다", async () => {
  const tempDir = await mkdtemp(path.join(tmpdir(), "map-attribution-"));
  const manifestPath = path.join(tempDir, "manifest.json");
  await writeFile(
    manifestPath,
    JSON.stringify({
      maps: [{ id: "busan", name_ko: "부산" }],
    }),
  );

  await assert.rejects(
    execFile(process.execPath, ["tools/ci/check-map-attribution.mjs", manifestPath], { cwd: root }),
    /busan: missing license block/,
  );
});

test("번들 지도 manifest license는 완비되어 있다", async () => {
  await execFile(process.execPath, [
    "tools/ci/check-map-attribution.mjs",
    "apps/mobile/assets/datapacks/metro_map_pack/manifest.json",
  ], { cwd: root });
});
