import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

test("build-datapack 산출 manifest가 계약 스키마를 통과한다", () => {
  const out = mkdtempSync(join(tmpdir(), "dp-contract-"));
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  try {
    execFileSync(
      process.execPath,
      [
        "tools/datapack/build-datapack.mjs",
        "--fixture",
        "tools/datapack/fixtures/catalog-fixture.json",
        "--output",
        out,
      ],
      {
        env: {
          ...process.env,
          EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM: privateKey.export({ type: "pkcs8", format: "pem" }),
          EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_PEM: publicKey.export({ type: "spki", format: "pem" }),
        },
      },
    );

    const schema = JSON.parse(readFileSync("contracts/datapack/datapack-manifest.schema.json", "utf8"));
    const manifest = JSON.parse(readFileSync(join(out, "current.json"), "utf8"));
    assert.deepEqual(validateSchema(schema, manifest).errors, []);
  } finally {
    rmSync(out, { recursive: true, force: true });
  }
});
