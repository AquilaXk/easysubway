import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");

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

async function payloadHash(aab) {
  const { stdout } = await execFileAsync(process.execPath, [
    "tools/release/hash-android-bundle-payload.mjs",
    "--aab",
    aab,
  ], { cwd: root });
  return stdout.trim();
}

test("AAB payload hash ignores signing entries but detects runtime payload changes", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "aab-payload-hash-"));
  const first = await bundle(dir, "first", "signature-one");
  const resigned = await bundle(dir, "resigned", "signature-two");
  const changed = await bundle(dir, "changed", "signature-three", "changed-runtime-payload");

  const firstHash = await payloadHash(first);
  assert.match(firstHash, /^[0-9a-f]{64}$/);
  assert.equal(await payloadHash(resigned), firstHash);
  assert.notEqual(await payloadHash(changed), firstHash);
});
