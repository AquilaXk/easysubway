#!/usr/bin/env node
import { execFile } from "node:child_process";
import { createHash, generateKeyPairSync, randomUUID } from "node:crypto";
import { lstat, mkdtemp, open, readFile, rename, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { promisify } from "node:util";
import { pathToFileURL } from "node:url";
import { gunzipSync } from "node:zlib";

import { stagedPackPath } from "./lib/manifest-validation.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    if (!flag?.startsWith("--") || argv[index + 1] == null) throw new Error(`invalid argument: ${flag ?? ""}`);
    args[flag.slice(2)] = argv[index + 1];
  }
  return args;
}

function requiredArg(args, name) {
  const value = args[name];
  if (typeof value !== "string" || value.trim() === "") throw new Error(`--${name} is required`);
  return value;
}

function optionalBooleanArg(args, name) {
  const value = args[name];
  if (value === undefined) return false;
  if (!["true", "false"].includes(value)) throw new Error(`--${name} must be true or false`);
  return value === "true";
}

function assertEqual(actual, expected, label) {
  if (actual !== expected) throw new Error(`${label} mismatch: expected ${expected}, got ${actual}`);
}

function tableRowCounts(sqlitePath) {
  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  try {
    const tables = database.prepare(
      "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ).all();
    return Object.fromEntries(tables.map(({ name }) => [
      name,
      database.prepare(`SELECT count(*) AS count FROM "${name.replaceAll('"', '""')}"`).get().count,
    ]));
  } finally {
    database.close();
  }
}

function networkEdgeCounts(sqlitePath) {
  const database = new DatabaseSync(sqlitePath, { readOnly: true });
  try {
    const rows = database.prepare(`
      SELECT source_id, source_snapshot_id, provider_record_hash, provenance_kind,
             verification_status, last_verified_at, evidence_hash
      FROM network_edges
    `).all();
    const hasValidHash = (value) => /^[0-9a-f]{64}$/.test(value);
    const hasCompleteProvenance = (row) => row.source_id !== ""
      && row.source_snapshot_id !== ""
      && hasValidHash(row.provider_record_hash)
      && hasValidHash(row.evidence_hash)
      && row.provenance_kind !== "UNKNOWN"
      && row.verification_status !== "UNKNOWN"
      && row.last_verified_at != null;
    const provenanceComplete = rows.filter(hasCompleteProvenance);
    return {
      total: rows.length,
      provenanceComplete: provenanceComplete.length,
      strictEligible: provenanceComplete.filter((row) => row.verification_status === "VERIFIED"
        && ["OFFICIAL_SOURCE", "OPERATOR_CONFIRMED", "FIELD_SURVEY"].includes(row.provenance_kind)
        && !/^([0-9a-f])\1{63}$/.test(row.evidence_hash)).length,
    };
  } finally {
    database.close();
  }
}

export async function verifyProductionPackArtifactIdentity({
  buildSpecPath,
  assetPath,
  indexPath,
  packId,
  syncIndexFreshness = false,
}) {
  buildSpecPath = path.resolve(buildSpecPath);
  assetPath = path.resolve(assetPath);
  indexPath = path.resolve(indexPath);
  const outputDir = await mkdtemp(path.join(tmpdir(), "easysubway-production-pack-identity-"));
  try {
    // ponytail: manifest signatures are outside this SQLite identity gate, so CI needs no publish private key.
    const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
    await execFileAsync(process.execPath, [
      path.join(root, "tools/datapack/build-datapack.mjs"),
      "--build-spec", buildSpecPath,
      "--output", outputDir,
    ], {
      cwd: root,
      env: {
        ...process.env,
        EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM: privateKey.export({ type: "pkcs8", format: "pem" }),
      },
    });

    const manifest = JSON.parse(await readFile(path.join(outputDir, "current.json"), "utf8"));
    const packs = manifest.packs.filter(({ id }) => id === packId);
    if (packs.length !== 1 || packs[0].artifactKind !== "production") {
      throw new Error(`build must contain exactly one production pack: ${packId}`);
    }
    const pack = packs[0];
    const builtPath = path.join(outputDir, stagedPackPath(pack));
    const builtGzip = await readFile(builtPath);
    const assetGzip = await readFile(assetPath);
    const assetSqlite = gunzipSync(assetGzip);
    const gzipSha256 = sha256(assetGzip);
    const sqliteSha256 = sha256(assetSqlite);
    const byteSize = assetGzip.length;

    assertEqual(gzipSha256, pack.sha256, "asset gzip sha256");
    assertEqual(sqliteSha256, pack.sqliteSha256, "asset SQLite sha256");
    assertEqual(byteSize, pack.sizeBytes, "asset byteSize");
    assertEqual(sha256(builtGzip), pack.sha256, "built gzip sha256");

    const indexStat = await lstat(indexPath);
    if (!indexStat.isFile() || indexStat.isSymbolicLink()) {
      throw new Error("index must be a regular non-symlink file");
    }
    const indexBytes = await readFile(indexPath);
    const index = JSON.parse(indexBytes);
    const indexPacks = index.packs?.filter(({ id }) => id === packId) ?? [];
    if (indexPacks.length !== 1) throw new Error(`index must contain exactly one pack: ${packId}`);
    assertEqual(indexPacks[0].asset, path.relative(path.join(root, "apps/mobile"), assetPath).split(path.sep).join("/"), "index asset");
    assertEqual(indexPacks[0].sha256, gzipSha256, "index sha256");
    assertEqual(indexPacks[0].sqliteSha256, sqliteSha256, "index SQLite sha256");
    assertEqual(indexPacks[0].byteSize, byteSize, "index byteSize");

    const freshnessExpiresAt = manifest.expiresAt;
    if (typeof freshnessExpiresAt !== "string"
      || !Number.isFinite(Date.parse(freshnessExpiresAt))
      || new Date(freshnessExpiresAt).toISOString() !== freshnessExpiresAt) {
      throw new Error("manifest expiresAt must be a canonical UTC timestamp");
    }
    if (syncIndexFreshness && index.freshnessExpiresAt !== freshnessExpiresAt) {
      const nextBytes = Buffer.from(`${JSON.stringify({ ...index, freshnessExpiresAt }, null, 2)}\n`);
      const tempPath = `${indexPath}.freshness-sync-${process.pid}-${randomUUID()}`;
      let handle;
      try {
        handle = await open(tempPath, "wx", 0o600);
        await handle.writeFile(nextBytes);
        await handle.sync();
        await handle.close();
        handle = undefined;
        const currentBytes = await readFile(indexPath);
        if (!currentBytes.equals(indexBytes)) {
          throw new Error("index changed during freshness synchronization");
        }
        await rename(tempPath, indexPath);
      } finally {
        await handle?.close();
        await rm(tempPath, { force: true });
      }
    }

    return {
      packId,
      gzipSha256,
      sqliteSha256,
      byteSize,
      rowCounts: tableRowCounts(builtPath.replace(/\.gz$/, "")),
      networkEdgeCounts: networkEdgeCounts(builtPath.replace(/\.gz$/, "")),
    };
  } finally {
    await rm(outputDir, { recursive: true, force: true });
  }
}

async function main(argv) {
  const args = parseArgs(argv);
  const report = await verifyProductionPackArtifactIdentity({
    buildSpecPath: requiredArg(args, "build-spec"),
    assetPath: requiredArg(args, "asset"),
    indexPath: requiredArg(args, "index"),
    packId: requiredArg(args, "pack-id"),
    syncIndexFreshness: optionalBooleanArg(args, "sync-index-freshness"),
  });
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
