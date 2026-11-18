import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { closeSync, createWriteStream, openSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import test, { afterEach } from "node:test";
import { createGzip, gzipSync } from "node:zlib";
import {
  DEFAULT_MAX_OUTPUT_LENGTH,
  countGzipUncompressedBytes,
} from "./count-gzip-uncompressed-bytes.mjs";

const tool = new URL("./count-gzip-uncompressed-bytes.mjs", import.meta.url);
const sandboxes = [];

afterEach(async () => {
  for (const dir of sandboxes.splice(0)) {
    await rm(dir, { recursive: true, force: true });
  }
});

async function makeTempDir(prefix) {
  const dir = await mkdtemp(path.join(tmpdir(), prefix));
  sandboxes.push(dir);
  return dir;
}

function countFromFile(artifact, extraArgs = []) {
  const descriptor = openSync(artifact, "r");
  try {
    return execFileSync(process.execPath, [tool.pathname, ...extraArgs], {
      encoding: "utf8",
      stdio: [descriptor, "pipe", "pipe"],
    });
  } finally {
    closeSync(descriptor);
  }
}

test("gzip payload를 메모리에 모으지 않고 uncompressed byte count만 출력한다", async () => {
  const directory = await makeTempDir("easysubway-gzip-count-");
  const artifact = path.join(directory, "pack.sqlite.gz");
  const payload = Buffer.alloc(1024 * 1024, 7);
  await writeFile(artifact, gzipSync(payload));

  assert.equal(countFromFile(artifact).trim(), String(payload.length));
});

test("invalid gzip은 성공 byte count로 처리하지 않는다", async () => {
  const directory = await makeTempDir("easysubway-gzip-count-invalid-");
  const artifact = path.join(directory, "pack.sqlite.gz");
  await writeFile(artifact, "not-gzip");

  assert.throws(() => countFromFile(artifact));
});

test("filesystem path argument를 받지 않는다", () => {
  assert.throws(() => execFileSync(process.execPath, [tool.pathname, "/tmp/untrusted.gz"]));
});

test("--max-output-length 상한 이하 payload는 통과하고 1바이트라도 초과하면 fail-closed 한다", async () => {
  const directory = await makeTempDir("easysubway-gzip-count-limit-");
  const exactArtifact = path.join(directory, "exact.gz");
  const overArtifact = path.join(directory, "over.gz");
  await writeFile(exactArtifact, gzipSync(Buffer.alloc(4096, 1)));
  await writeFile(overArtifact, gzipSync(Buffer.alloc(4097, 1)));

  assert.equal(countFromFile(exactArtifact, ["--max-output-length", "4096"]).trim(), "4096");
  assert.throws(() => countFromFile(overArtifact, ["--max-output-length", "4096"]));
});

test("기본 256MiB 상한을 초과하는 악의적 gzip bomb은 OOM 없이 즉시 거부한다", async () => {
  const directory = await makeTempDir("easysubway-gzip-bomb-");
  const bombArtifact = path.join(directory, "bomb.gz");
  const chunk = Buffer.alloc(1024 * 1024, 0);
  const totalChunks = DEFAULT_MAX_OUTPUT_LENGTH / chunk.length;

  async function* generateOversizedStream() {
    for (let i = 0; i < totalChunks; i += 1) {
      yield chunk;
    }
    yield Buffer.from([1]);
  }

  await pipeline(
    Readable.from(generateOversizedStream()),
    createGzip(),
    createWriteStream(bombArtifact),
  );

  assert.throws(() => countFromFile(bombArtifact));
});

test("직접 호출과 잘못된 --max-output-length 옵션도 fail-closed로 검증한다", async () => {
  const gz = gzipSync(Buffer.alloc(128, 3));
  assert.equal(await countGzipUncompressedBytes(Readable.from([gz]), { maxOutputLength: 128 }), 128);
  await assert.rejects(
    () => countGzipUncompressedBytes(Readable.from([gz]), { maxOutputLength: 127 }),
    /maxOutputLength/,
  );
  await assert.rejects(
    () => countGzipUncompressedBytes(Readable.from([gz]), { maxOutputLength: 0 }),
    /maxOutputLength/,
  );

  const directory = await makeTempDir("easysubway-gzip-bad-flag-");
  const artifact = path.join(directory, "small.gz");
  await writeFile(artifact, gz);
  for (const badArgs of [
    ["--max-output-length"],
    ["--max-output-length", "0"],
    ["--max-output-length", "-1"],
    ["--max-output-length", "12.5"],
    ["--unknown", "128"],
  ]) {
    assert.throws(() => countFromFile(artifact, badArgs));
  }
});
