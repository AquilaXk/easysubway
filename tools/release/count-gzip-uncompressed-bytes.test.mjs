import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { closeSync, openSync } from "node:fs";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { gzipSync } from "node:zlib";

const tool = new URL("./count-gzip-uncompressed-bytes.mjs", import.meta.url);

function countFromFile(artifact) {
  const descriptor = openSync(artifact, "r");
  try {
    return execFileSync(process.execPath, [tool.pathname], {
      encoding: "utf8",
      stdio: [descriptor, "pipe", "pipe"],
    });
  } finally {
    closeSync(descriptor);
  }
}

test("gzip payload를 메모리에 모으지 않고 uncompressed byte count만 출력한다", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "easysubway-gzip-count-"));
  const artifact = path.join(directory, "pack.sqlite.gz");
  const payload = Buffer.alloc(1024 * 1024, 7);
  await writeFile(artifact, gzipSync(payload));

  assert.equal(countFromFile(artifact).trim(), String(payload.length));
});

test("invalid gzip은 성공 byte count로 처리하지 않는다", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "easysubway-gzip-count-invalid-"));
  const artifact = path.join(directory, "pack.sqlite.gz");
  await writeFile(artifact, "not-gzip");

  assert.throws(() => countFromFile(artifact));
});

test("filesystem path argument를 받지 않는다", () => {
  assert.throws(() => execFileSync(process.execPath, [tool.pathname, "/tmp/untrusted.gz"]));
});
