#!/usr/bin/env node

import path from "node:path";
import { Writable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";
import { createGunzip } from "node:zlib";

export const DEFAULT_MAX_OUTPUT_LENGTH = 256 * 1024 * 1024;

export async function countGzipUncompressedBytes(
  input = process.stdin,
  { maxOutputLength = DEFAULT_MAX_OUTPUT_LENGTH } = {},
) {
  if (!Number.isSafeInteger(maxOutputLength) || maxOutputLength <= 0) {
    throw new Error("maxOutputLength must be a positive safe integer");
  }

  let bytes = 0;
  const counter = new Writable({
    write(chunk, _encoding, callback) {
      bytes += chunk.length;
      if (!Number.isSafeInteger(bytes)) {
        callback(new Error("uncompressed byte count exceeds the safe integer range"));
        return;
      }
      if (bytes > maxOutputLength) {
        callback(new Error(`uncompressed byte count exceeds maxOutputLength (${maxOutputLength})`));
        return;
      }
      callback();
    },
  });

  await pipeline(input, createGunzip(), counter);
  return bytes;
}

function parseCliArgs(argv) {
  if (argv.length === 0) {
    return { maxOutputLength: DEFAULT_MAX_OUTPUT_LENGTH };
  }
  if (argv.length === 2 && argv[0] === "--max-output-length" && /^[1-9]\d*$/.test(argv[1])) {
    const parsed = Number(argv[1]);
    if (Number.isSafeInteger(parsed) && parsed > 0) {
      return { maxOutputLength: parsed };
    }
  }
  return null;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const options = parseCliArgs(process.argv.slice(2));
  if (!options) {
    process.stderr.write("usage: count-gzip-uncompressed-bytes.mjs [--max-output-length <bytes>] < artifact.gz\n");
    process.exit(1);
  }
  const bytes = await countGzipUncompressedBytes(process.stdin, options);
  process.stdout.write(`${bytes}\n`);
}
