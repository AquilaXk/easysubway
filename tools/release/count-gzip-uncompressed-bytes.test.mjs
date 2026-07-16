import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import { gzipSync } from "node:zlib";

const execFileAsync = promisify(execFile);
const tool = new URL("./count-gzip-uncompressed-bytes.mjs", import.meta.url);

test("gzip payload를 메모리에 모으지 않고 uncompressed byte count만 출력한다", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "easysubway-gzip-count-"));
  const artifact = path.join(directory, "pack.sqlite.gz");
  const payload = Buffer.alloc(1024 * 1024, 7);
  await writeFile(artifact, gzipSync(payload));

  const { stdout } = await execFileAsync(process.execPath, [tool.pathname, artifact]);
  assert.equal(stdout.trim(), String(payload.length));
});

test("invalid gzip은 성공 byte count로 처리하지 않는다", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "easysubway-gzip-count-invalid-"));
  const artifact = path.join(directory, "pack.sqlite.gz");
  await writeFile(artifact, "not-gzip");

  await assert.rejects(execFileAsync(process.execPath, [tool.pathname, artifact]));
});
