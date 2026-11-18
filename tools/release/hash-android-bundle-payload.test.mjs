import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { crc32, deflateRawSync } from "node:zlib";
import test, { afterEach } from "node:test";
import { hashAndroidBundlePayloadBuffer } from "./hash-android-bundle-payload.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
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

async function bundle(dir, name, signature, payload = "same-runtime-payload") {
  const source = path.join(dir, name);
  await mkdir(path.join(source, "META-INF"), { recursive: true });
  await mkdir(path.join(source, "base"), { recursive: true });
  await writeFile(path.join(source, "base", "payload.bin"), payload);
  await writeFile(path.join(source, "META-INF", "MANIFEST.MF"), signature);
  await writeFile(path.join(source, "META-INF", "UPLOAD.RSA"), signature);
  await writeFile(path.join(source, "META-INF", "UPLOAD.SF"), signature);
  await writeFile(path.join(source, "META-INF", "runtime-metadata.txt"), "kept");
  const output = path.join(dir, `${name}.aab`);
  await execFileAsync("zip", ["-q", "-r", output, "."], { cwd: source });
  return output;
}

async function payloadHash(aab, extraArgs = []) {
  const { stdout } = await execFileAsync(process.execPath, [
    "tools/release/hash-android-bundle-payload.mjs",
    "--aab",
    aab,
    ...extraArgs,
  ], { cwd: root });
  return stdout.trim();
}

function expectedDigest(entries) {
  const digest = createHash("sha256");
  const sorted = [...entries].sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  for (const entry of sorted) {
    const nameBytes = Buffer.from(entry.name, "utf8");
    const data = Buffer.isBuffer(entry.data) ? entry.data : Buffer.from(entry.data, "utf8");
    const lengths = Buffer.alloc(12);
    lengths.writeUInt32BE(nameBytes.length, 0);
    lengths.writeBigUInt64BE(BigInt(data.length), 4);
    digest.update(lengths);
    digest.update(nameBytes);
    digest.update(data);
  }
  return digest.digest("hex");
}

function buildZip(entries) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;

  for (const entry of entries) {
    const nameBytes = Buffer.from(entry.name, "utf8");
    const rawData = Buffer.isBuffer(entry.data) ? entry.data : Buffer.from(entry.data ?? "", "utf8");
    const method = entry.method ?? 8;
    const flags = entry.flags ?? 0;
    const compressedData = entry.rawCompressed
      ? entry.rawCompressed
      : (method === 0 ? rawData : deflateRawSync(rawData));
    const checksum = entry.crc ?? crc32(rawData);
    const declaredCompressed = entry.declaredCompressed ?? compressedData.length;
    const declaredUncompressed = entry.declaredUncompressed ?? rawData.length;
    const useDescriptor = (flags & 0x0008) !== 0;

    const localHeader = Buffer.alloc(30);
    localHeader.writeUInt32LE(0x04034b50, 0);
    localHeader.writeUInt16LE(20, 4);
    localHeader.writeUInt16LE(flags, 6);
    localHeader.writeUInt16LE(method, 8);
    localHeader.writeUInt32LE(useDescriptor ? 0 : checksum, 14);
    localHeader.writeUInt32LE(useDescriptor ? 0 : declaredCompressed, 18);
    localHeader.writeUInt32LE(useDescriptor ? 0 : declaredUncompressed, 22);
    localHeader.writeUInt16LE(nameBytes.length, 26);
    localHeader.writeUInt16LE(0, 28);

    const descriptor = useDescriptor ? Buffer.alloc(16) : Buffer.alloc(0);
    if (useDescriptor) {
      descriptor.writeUInt32LE(0x08074b50, 0);
      descriptor.writeUInt32LE(checksum, 4);
      descriptor.writeUInt32LE(declaredCompressed, 8);
      descriptor.writeUInt32LE(declaredUncompressed, 12);
    }

    const centralHeader = Buffer.alloc(46);
    centralHeader.writeUInt32LE(0x02014b50, 0);
    centralHeader.writeUInt16LE(0x031e, 4);
    centralHeader.writeUInt16LE(20, 6);
    centralHeader.writeUInt16LE(flags, 8);
    centralHeader.writeUInt16LE(method, 10);
    centralHeader.writeUInt32LE(checksum, 16);
    centralHeader.writeUInt32LE(declaredCompressed, 20);
    centralHeader.writeUInt32LE(declaredUncompressed, 24);
    centralHeader.writeUInt16LE(nameBytes.length, 28);
    centralHeader.writeUInt16LE(0, 30);
    centralHeader.writeUInt16LE(0, 32);
    centralHeader.writeUInt16LE(0, 34);
    centralHeader.writeUInt16LE(0, 36);
    centralHeader.writeUInt32LE(entry.externalAttributes ?? 0x81a40000, 38);
    centralHeader.writeUInt32LE(offset, 42);

    localParts.push(localHeader, nameBytes, compressedData, descriptor);
    centralParts.push(centralHeader, nameBytes);
    offset += localHeader.length + nameBytes.length + compressedData.length + descriptor.length;
  }

  const centralDir = Buffer.concat(centralParts);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(0, 4);
  eocd.writeUInt16LE(0, 6);
  eocd.writeUInt16LE(entries.length, 8);
  eocd.writeUInt16LE(entries.length, 10);
  eocd.writeUInt32LE(centralDir.length, 12);
  eocd.writeUInt32LE(offset, 16);
  eocd.writeUInt16LE(0, 20);

  return Buffer.concat([...localParts, centralDir, eocd]);
}

test("AAB payload hash ignores signing entries but detects runtime payload changes", async () => {
  const dir = await makeTempDir("aab-payload-hash-");
  const first = await bundle(dir, "first", "signature-one");
  const resigned = await bundle(dir, "resigned", "signature-two");
  const changed = await bundle(dir, "changed", "signature-three", "changed-runtime-payload");

  const firstHash = await payloadHash(first);
  assert.match(firstHash, /^[0-9a-f]{64}$/);
  assert.equal(await payloadHash(resigned), firstHash);
  assert.notEqual(await payloadHash(changed), firstHash);
  assert.equal(
    firstHash,
    expectedDigest([
      { name: "META-INF/runtime-metadata.txt", data: "kept" },
      { name: "base/payload.bin", data: "same-runtime-payload" },
    ]),
  );
});

test("glob 특수문자([0], *, ?)가 포함된 엔트리명도 문자 그대로 처리해 정확한 해시를 계산한다", async () => {
  const dir = await makeTempDir("aab-glob-chars-");
  const source = path.join(dir, "bundle");
  await mkdir(path.join(source, "base"), { recursive: true });
  await mkdir(path.join(source, "META-INF"), { recursive: true });
  await writeFile(path.join(source, "base", "a[0].txt"), "bracket-content");
  await writeFile(path.join(source, "base", "a0.txt"), "plain-content");
  await writeFile(path.join(source, "base", "*.txt"), "wildcard-content");
  await writeFile(path.join(source, "base", "q?.bin"), "question-content");
  await writeFile(path.join(source, "META-INF", "MANIFEST.MF"), "ignored-sig");
  const aab = path.join(dir, "special.aab");
  await execFileAsync("zip", ["-q", "-r", aab, "."], { cwd: source });

  const actual = await payloadHash(aab);
  assert.equal(
    actual,
    expectedDigest([
      { name: "base/*.txt", data: "wildcard-content" },
      { name: "base/a0.txt", data: "plain-content" },
      { name: "base/a[0].txt", data: "bracket-content" },
      { name: "base/q?.bin", data: "question-content" },
    ]),
  );
});

test("STORED(0), DEFLATE(8), data descriptor(0x0008), deflate hint(0x0002) 엔트리를 정상 해시한다", () => {
  const zip = buildZip([
    { name: "META-INF/CERT.RSA", data: "sig", method: 0 },
    { name: "base/stored.bin", data: "stored-payload", method: 0, flags: 0x0800 },
    { name: "base/deflated.bin", data: "deflated-payload-repeat-repeat", method: 8, flags: 0x080a },
  ]);

  assert.equal(
    hashAndroidBundlePayloadBuffer(zip),
    expectedDigest([
      { name: "base/deflated.bin", data: "deflated-payload-repeat-repeat" },
      { name: "base/stored.bin", data: "stored-payload" },
    ]),
  );
});

test("압축 폭탄과 거짓 비압축 크기 헤더를 fail-closed로 거부한다", async () => {
  const bombData = Buffer.alloc(512 * 1024, 0);
  const singleEntryZip = buildZip([{ name: "base/bomb.bin", data: bombData, method: 8 }]);
  assert.throws(
    () => hashAndroidBundlePayloadBuffer(singleEntryZip, { maxEntryBytes: 64 * 1024 }),
    /uncompressed size limit/,
  );

  const multiEntryZip = buildZip([
    { name: "base/part1.bin", data: Buffer.alloc(40 * 1024, 1), method: 8 },
    { name: "base/part2.bin", data: Buffer.alloc(40 * 1024, 2), method: 8 },
  ]);
  assert.throws(
    () => hashAndroidBundlePayloadBuffer(multiEntryZip, { maxTotalBytes: 64 * 1024 }),
    /total uncompressed size limit/,
  );

  // 헤더에는 16바이트로 속이고 실제 inflate 결과는 64KB가 넘게 만든 변조 ZIP
  const spoofed = buildZip([
    {
      name: "base/spoofed.bin",
      rawCompressed: deflateRawSync(Buffer.alloc(65 * 1024, 0)),
      declaredUncompressed: 16,
      crc: crc32(Buffer.alloc(65 * 1024, 0)),
      method: 8,
    },
  ]);
  assert.throws(
    () => hashAndroidBundlePayloadBuffer(spoofed, { maxEntryBytes: 32 * 1024 }),
    /ERR_BUFFER_TOO_LARGE|limit|mismatch/,
  );

  // CLI에서도 --max-entry-bytes / --max-total-bytes 상한이 적용되는지 검증
  const dir = await makeTempDir("aab-bomb-cli-");
  const aab = path.join(dir, "bomb.aab");
  await writeFile(aab, singleEntryZip);
  await assert.rejects(payloadHash(aab, ["--max-entry-bytes", "65536"]));
});

test("path traversal, symlink, 중복 엔트리, CRC 불일치, 암호화, 빈 payload를 fail-closed로 거부한다", async () => {
  for (const unsafeName of ["../escape.txt", "base/../../escape.txt", "/abs.txt", "base\\win.txt", "./dot.txt"]) {
    const zip = buildZip([{ name: unsafeName, data: "evil", method: 0 }]);
    assert.throws(() => hashAndroidBundlePayloadBuffer(zip), /unsafe/, unsafeName);
  }

  // symlink 엔트리(S_IFLNK = 0o120000 << 16 = 0xa0000000)
  const symlinkZip = buildZip([
    { name: "base/link", data: "/etc/passwd", method: 0, externalAttributes: 0xa1ff0000 },
  ]);
  assert.throws(() => hashAndroidBundlePayloadBuffer(symlinkZip), /symlink/);

  // 실제 zip --symlinks 로 생성한 symlink도 거부
  const dir = await makeTempDir("aab-symlink-");
  const src = path.join(dir, "src");
  await mkdir(path.join(src, "base"), { recursive: true });
  await writeFile(path.join(src, "base", "real.txt"), "real");
  await symlink("real.txt", path.join(src, "base", "sym.txt"));
  const symAab = path.join(dir, "sym.aab");
  await execFileAsync("zip", ["--symlinks", "-q", "-r", symAab, "."], { cwd: src });
  await assert.rejects(payloadHash(symAab));

  // 중복 엔트리명
  const duplicateZip = buildZip([
    { name: "base/dup.txt", data: "one", method: 0 },
    { name: "base/dup.txt", data: "two", method: 0 },
  ]);
  assert.throws(() => hashAndroidBundlePayloadBuffer(duplicateZip), /duplicate/);

  // CRC 변조
  const badCrcZip = buildZip([
    { name: "base/file.txt", data: "hello", method: 0, crc: 0xdeadbeef },
  ]);
  assert.throws(() => hashAndroidBundlePayloadBuffer(badCrcZip), /CRC/);

  // 암호화 엔트리 (flags bit 0)
  const encryptedZip = buildZip([
    { name: "base/secret.txt", data: "abc", method: 0, flags: 0x0001 },
  ]);
  assert.throws(() => hashAndroidBundlePayloadBuffer(encryptedZip), /unsupported|encrypted/);

  // 서명 파일만 있고 payload가 없는 AAB
  const sigOnlyZip = buildZip([{ name: "META-INF/MANIFEST.MF", data: "sig", method: 0 }]);
  assert.throws(() => hashAndroidBundlePayloadBuffer(sigOnlyZip), /no payload entries/);

  // 손상된 ZIP 바이트
  assert.throws(() => hashAndroidBundlePayloadBuffer(Buffer.from("not-a-zip")));
});
