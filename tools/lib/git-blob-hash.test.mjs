import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  hashGitBlobBuffer,
  hashWorktreeGitBlob,
  readDirtyPathsBatch,
  readTreeBlobShasBatch,
} from "./git-blob-hash.mjs";

test("hashGitBlobBuffer 및 hashWorktreeGitBlob은 git hash-object와 동일한 SHA-1을 계산한다", () => {
  const dir = mkdtempSync(join(tmpdir(), "git-blob-hash-test-"));
  try {
    mkdirSync(join(dir, "docs"), { recursive: true });
    const samples = [
      ["empty.txt", ""],
      ["docs/korean.md", "# 쉬운 지하철 안내\n엘리베이터·휠체어 리프트 경로\n"],
      ["binary.bin", Buffer.from([0x00, 0xff, 0x10, 0x20, 0x7f, 0x80])],
    ];
    for (const [relPath, content] of samples) {
      const fullPath = join(dir, relPath);
      writeFileSync(fullPath, content);
      const expected = execFileSync("git", ["hash-object", fullPath], {
        encoding: "utf8",
      }).trim();
      assert.equal(hashWorktreeGitBlob(dir, relPath), expected);
      assert.equal(hashGitBlobBuffer(Buffer.from(content)), expected);
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("hashWorktreeGitBlob은 바이트 상한 초과 및 심볼릭 링크를 Fail-Closed로 거부한다", () => {
  const dir = mkdtempSync(join(tmpdir(), "git-blob-cap-test-"));
  try {
    writeFileSync(join(dir, "oversized.txt"), "0123456789abcdef", "utf8");
    symlinkSync(join(dir, "oversized.txt"), join(dir, "link.txt"));

    assert.throws(
      () => hashWorktreeGitBlob(dir, "oversized.txt", { maxBytes: 8 }),
      /exceeds maxBytes/,
    );
    assert.throws(
      () => hashWorktreeGitBlob(dir, "link.txt"),
      /regular file/,
    );
    assert.throws(
      () => hashWorktreeGitBlob(dir, "missing.txt"),
      /missing on disk/,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("readTreeBlobShasBatch와 readDirtyPathsBatch는 단일 호출로 트리 해시와 더티 경로를 수집한다", () => {
  const dir = mkdtempSync(join(tmpdir(), "git-tree-batch-test-"));
  try {
    execFileSync("git", ["init", "-b", "main"], { cwd: dir });
    execFileSync("git", ["config", "user.name", "Test"], { cwd: dir });
    execFileSync("git", ["config", "user.email", "test@example.invalid"], { cwd: dir });
    mkdirSync(join(dir, "nested"), { recursive: true });
    writeFileSync(join(dir, "a.md"), "alpha\n", "utf8");
    writeFileSync(join(dir, "nested/b.md"), "beta\n", "utf8");
    execFileSync("git", ["add", "a.md", "nested/b.md"], { cwd: dir });
    execFileSync("git", ["commit", "-m", "init"], { cwd: dir });

    const map = readTreeBlobShasBatch(dir, "HEAD", ["a.md", "nested/b.md", "absent.md"]);
    assert.equal(map.size, 2);
    assert.equal(map.get("a.md"), hashWorktreeGitBlob(dir, "a.md"));
    assert.equal(map.get("nested/b.md"), hashWorktreeGitBlob(dir, "nested/b.md"));
    assert.equal(map.has("absent.md"), false);

    writeFileSync(join(dir, "nested/b.md"), "beta-dirty\n", "utf8");
    const dirty = readDirtyPathsBatch(dir, ["a.md", "nested/b.md"]);
    assert.equal(dirty.has("a.md"), false);
    assert.equal(dirty.has("nested/b.md"), true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
