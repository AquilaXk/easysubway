import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";
import { buildReleaseRequestBinding } from "./build-release-request-binding.mjs";
import { canonicalJson, verifyRsaSha256Signature, withoutSignature } from "./lib/manifest-validation.mjs";

const execFileAsync = promisify(execFile);

test("release request binding은 manifest identity를 변경하지 않고 요청을 서명해 결합한다", () => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const manifestBytes = Buffer.from(JSON.stringify({
    manifestVersion: 2,
    channel: "production",
    releaseSequence: 42,
    keyId: "production-v1",
    ttlSeconds: 3600,
    packs: [],
  }));

  const binding = buildReleaseRequestBinding(
    manifestBytes,
    "request-2057",
    privateKey.export({ type: "pkcs8", format: "pem" }),
    "production-v1",
  );

  assert.equal(binding.releaseRequestId, "request-2057");
  assert.equal(binding.releaseSequence, 42);
  assert.equal(binding.channel, "production");
  assert.match(binding.manifestSha256, /^[a-f0-9]{64}$/);
  assert.equal(
    verifyRsaSha256Signature(
      publicKey.export({ type: "spki", format: "pem" }),
      canonicalJson(withoutSignature(binding)),
      binding.signature.value,
    ),
    true,
  );
  assert.equal(JSON.parse(manifestBytes).releaseRequestId, undefined);
});

test("publish plan은 request binding을 current pointer보다 먼저 immutable 게시한다", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "datapack-request-binding-"));
  await mkdir(path.join(root, "catalog"), { recursive: true });
  const packBytes = Buffer.from("pack");
  const manifest = {
    manifestVersion: 2,
    channel: "production",
    releaseSequence: 42,
    keyId: "production-v1",
    ttlSeconds: 3600,
    packs: [{
      id: "capital",
      version: "1",
      url: "catalog/capital-v1.sqlite.gz",
      sha256: (await import("node:crypto")).createHash("sha256").update(packBytes).digest("hex"),
      sizeBytes: packBytes.length,
    }],
  };
  const manifestBytes = Buffer.from(`${JSON.stringify(manifest)}\n`);
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const binding = buildReleaseRequestBinding(
    manifestBytes,
    "request-2057",
    privateKey.export({ type: "pkcs8", format: "pem" }),
    "production-v1",
  );
  const manifestPath = path.join(root, "catalog", "current.json");
  const bindingPath = path.join(root, "catalog", "release-request-binding.json");
  const planPath = path.join(root, "publish-plan.json");
  await writeFile(path.join(root, "catalog", "capital-v1.sqlite.gz"), packBytes);
  await writeFile(manifestPath, manifestBytes);
  await writeFile(bindingPath, `${JSON.stringify(binding)}\n`);

  await execFileAsync(process.execPath, [
    "tools/datapack/create-publish-plan.mjs",
    "--manifest", manifestPath,
    "--root", root,
    "--output", planPath,
    "--release-request-binding", bindingPath,
  ]);
  const plan = JSON.parse(await readFile(planPath, "utf8"));
  const bindingPut = plan.steps.findIndex((step) => step.type === "put-release-request-binding-object");
  const currentPut = plan.steps.findIndex((step) => step.type === "put-manifest-object");
  assert.equal(plan.schemaVersion, 3);
  assert.ok(bindingPut >= 0 && bindingPut < currentPut);
  assert.match(plan.steps[bindingPut].objectKey, /^catalog\/release-requests\/[a-f0-9]{64}\.json$/);

  await execFileAsync(process.execPath, [
    "tools/datapack/publish-object-storage.mjs",
    "--plan", planPath,
    "--root", root,
    "--dry-run",
  ]);
});
