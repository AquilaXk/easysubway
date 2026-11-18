// Adapted from isomorphic-git (https://github.com/isomorphic-git/isomorphic-git, src/models/GitObject.js)
// Copyright (c) 2017-2024 isomorphic-git contributors — MIT License.
// Low-level in-process Git blob SHA-1 framing ("blob <byteLength>\0") and single-call NUL-delimited tree/status batching.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstatSync, readFileSync } from "node:fs";
import { join } from "node:path";

export const DEFAULT_MAX_BLOB_BYTES = 64 * 1024 * 1024; // 64 MiB Fail-Closed cap

export function hashGitBlobBuffer(buffer, { maxBytes = DEFAULT_MAX_BLOB_BYTES } = {}) {
  const bytes = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer);
  if (bytes.byteLength > maxBytes) {
    throw new Error(`Git blob input exceeds maxBytes (${bytes.byteLength} > ${maxBytes})`);
  }
  return createHash("sha1") // NOSONAR: Git storage object format requires SHA-1 blob framing
    .update(`blob ${bytes.byteLength}\0`, "utf8")
    .update(bytes)
    .digest("hex");
}

export function hashWorktreeGitBlob(
  rootDir,
  relativePath,
  { maxBytes = DEFAULT_MAX_BLOB_BYTES } = {},
) {
  const targetFile = join(rootDir, relativePath);
  let stat;
  try {
    stat = lstatSync(targetFile);
  } catch (error) {
    if (error?.code === "ENOENT") {
      const missing = new Error(`Tracked resource file missing on disk: ${relativePath}`);
      missing.code = "ENOENT";
      throw missing;
    }
    throw error;
  }
  if (stat.isSymbolicLink() || !stat.isFile()) {
    throw new Error(`Tracked resource must be a regular file: ${relativePath}`);
  }
  if (stat.size > maxBytes) {
    throw new Error(
      `Tracked resource "${relativePath}" exceeds maxBytes (${stat.size} > ${maxBytes})`,
    );
  }
  const bytes = readFileSync(targetFile);
  return hashGitBlobBuffer(bytes, { maxBytes });
}

export function readTreeBlobShasBatch(
  rootDir,
  treeRef,
  relativePaths,
  { exec = execFileSync } = {},
) {
  const result = new Map();
  if (!Array.isArray(relativePaths) || relativePaths.length === 0) {
    return result;
  }
  const uniquePaths = [...new Set(relativePaths)];
  const raw = exec(
    "git",
    ["-C", rootDir, "--literal-pathspecs", "ls-tree", "-z", "--full-tree", treeRef, "--", ...uniquePaths],
    {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 16 * 1024 * 1024,
    },
  );
  let start = 0;
  while (start < raw.length) {
    const end = raw.indexOf("\0", start);
    const entry = end === -1 ? raw.slice(start) : raw.slice(start, end);
    start = end === -1 ? raw.length : end + 1;
    if (!entry) continue;
    const tabIdx = entry.indexOf("\t");
    if (tabIdx === -1) continue;
    const header = entry.slice(0, tabIdx);
    const filePath = entry.slice(tabIdx + 1);
    const parts = header.split(" ");
    if (parts.length === 3 && parts[1] === "blob") {
      result.set(filePath, parts[2]);
    }
  }
  return result;
}

export function readDirtyPathsBatch(
  rootDir,
  relativePaths,
  { exec = execFileSync } = {},
) {
  const dirty = new Set();
  if (!Array.isArray(relativePaths) || relativePaths.length === 0) {
    return dirty;
  }
  const uniquePaths = [...new Set(relativePaths)];
  const raw = exec(
    "git",
    ["-C", rootDir, "--literal-pathspecs", "status", "--porcelain=v1", "-z", "--", ...uniquePaths],
    {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 16 * 1024 * 1024,
    },
  );
  const tokens = raw.split("\0");
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token.length < 4) continue;
    const status = token.slice(0, 2);
    const pathPart = token.slice(3);
    dirty.add(pathPart);
    if (status[0] === "R" || status[0] === "C") {
      i += 1; // Porcelain v1 -z emits the original path in the next NUL token
      if (i < tokens.length && tokens[i]) {
        dirty.add(tokens[i]);
      }
    }
  }
  return dirty;
}
