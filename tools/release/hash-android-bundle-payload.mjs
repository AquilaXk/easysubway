#!/usr/bin/env node

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";

const aabArgumentIndex = process.argv.indexOf("--aab");
const aabPath = aabArgumentIndex === -1 ? null : process.argv[aabArgumentIndex + 1];
if (!aabPath || !existsSync(aabPath)) {
  throw new Error("--aab must reference an existing Android App Bundle");
}

// unzip을 이름으로 호출하면 쓰기 가능한 PATH를 상속하므로, 신뢰된 시스템 경로에서
// 절대 경로를 한 번만 해석해 PATH 조작을 차단한다(macOS·Linux CI 모두 /usr/bin/unzip).
const unzipBinary = ["/usr/bin/unzip", "/bin/unzip", "/usr/local/bin/unzip", "/opt/homebrew/bin/unzip"].find(
  (candidate) => existsSync(candidate),
);
if (!unzipBinary) {
  throw new Error("unzip executable was not found in a trusted system path");
}

const signatureEntry = /^META-INF\/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))$/i;
const entries = execFileSync(unzipBinary, ["-Z1", aabPath], {
  encoding: "utf8",
  maxBuffer: 16 * 1024 * 1024,
})
  .split(/\r?\n/)
  .filter((entry) => entry && !entry.endsWith("/") && !signatureEntry.test(entry))
  .sort();

if (entries.length === 0) {
  throw new Error("Android App Bundle contains no payload entries");
}

const digest = createHash("sha256");
for (const entry of entries) {
  const entryName = Buffer.from(entry, "utf8");
  const contents = execFileSync(unzipBinary, ["-p", aabPath, entry], {
    encoding: "buffer",
    maxBuffer: 512 * 1024 * 1024,
  });
  const lengths = Buffer.alloc(12);
  lengths.writeUInt32BE(entryName.length, 0);
  lengths.writeBigUInt64BE(BigInt(contents.length), 4);
  digest.update(lengths);
  digest.update(entryName);
  digest.update(contents);
}

process.stdout.write(`${digest.digest("hex")}\n`);
