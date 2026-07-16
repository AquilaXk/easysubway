#!/usr/bin/env node

import { createReadStream } from "node:fs";
import { pipeline } from "node:stream/promises";
import { Writable } from "node:stream";
import { createGunzip } from "node:zlib";

const artifactPath = process.argv[2];
if (!artifactPath || process.argv.length !== 3) {
  process.stderr.write("usage: count-gzip-uncompressed-bytes.mjs <artifact.gz>\n");
  process.exit(1);
}

let bytes = 0;
const counter = new Writable({
  write(chunk, _encoding, callback) {
    bytes += chunk.length;
    if (!Number.isSafeInteger(bytes)) {
      callback(new Error("uncompressed byte count exceeds the safe integer range"));
      return;
    }
    callback();
  },
});

await pipeline(createReadStream(artifactPath), createGunzip(), counter);
process.stdout.write(`${bytes}\n`);
