#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, readFile, realpath, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { gunzipSync, gzipSync } from "node:zlib";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const repositoryRoot = path.resolve(import.meta.dirname, "../..");
const allowedSeedPath = path.join(repositoryRoot, "backend/src/main/resources/timetable/line4-timetable-seed.sql.gz");
const allowedEvidencePath = path.join(repositoryRoot, "backend/src/main/resources/timetable/server-timetable-snapshot-evidence.json");

function resolveWithinRoot(root, candidate, label) {
  const resolved = path.resolve(candidate);
  const relative = path.relative(root, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`${label} path escapes allowed root`);
  }
  return resolved;
}

export function validateRollbackSourceIntegrity(seed, evidenceBytes) {
  const evidence = JSON.parse(evidenceBytes);
  if (evidence.artifactKind !== "server-timetable-snapshot-evidence") {
    throw new Error("unexpected timetable snapshot evidence");
  }

  const sourceSql = gunzipSync(seed);
  const { evidenceHash: sourceEvidenceHash, ...sourceEvidence } = evidence;
  if (
    evidence.snapshotSha256 !== sha256(sourceSql) ||
    evidence.snapshotGzipSha256 !== sha256(seed) ||
    evidence.snapshotSqlByteSize !== sourceSql.length ||
    evidence.snapshotGzipByteSize !== seed.length ||
    sourceEvidenceHash !== sha256(Buffer.from(JSON.stringify(sourceEvidence)))
  ) {
    throw new Error("seed and evidence integrity check failed");
  }
  return { evidence, sourceSql };
}

export async function prepareRollbackCandidate(seedPath, evidencePath, outputDirectory) {
  const resolvedSeedPath = resolveWithinRoot(repositoryRoot, seedPath, "seed");
  const resolvedEvidencePath = resolveWithinRoot(repositoryRoot, evidencePath, "evidence");
  if (resolvedSeedPath !== allowedSeedPath || resolvedEvidencePath !== allowedEvidencePath) {
    throw new Error("rollback candidate inputs must use the checked-in timetable snapshot");
  }
  const [canonicalSeedPath, canonicalEvidencePath] = await Promise.all([
    realpath(resolvedSeedPath),
    realpath(resolvedEvidencePath),
  ]);
  if (canonicalSeedPath !== allowedSeedPath || canonicalEvidencePath !== allowedEvidencePath) {
    throw new Error("rollback candidate inputs must not use symbolic links");
  }
  const outputRoot = path.resolve(process.env.RUNNER_TEMP ?? tmpdir());
  const resolvedOutputDirectory = resolveWithinRoot(outputRoot, outputDirectory, "output");
  await mkdir(resolvedOutputDirectory, { recursive: true });
  const [canonicalOutputRoot, canonicalOutputDirectory] = await Promise.all([
    realpath(outputRoot),
    realpath(resolvedOutputDirectory),
  ]);
  resolveWithinRoot(canonicalOutputRoot, canonicalOutputDirectory, "output");

  const [seed, evidenceBytes] = await Promise.all([
    readFile(canonicalSeedPath),
    readFile(canonicalEvidencePath),
  ]);
  const { evidence, sourceSql } = validateRollbackSourceIntegrity(seed, evidenceBytes);

  const sql = Buffer.concat([sourceSql, Buffer.from("SELECT 1;\n")]);
  const compressed = gzipSync(sql, { level: 9, mtime: 0 });
  evidence.snapshotSha256 = sha256(sql);
  evidence.snapshotId = `server-timetable-snapshot-${evidence.snapshotSha256.slice(0, 16)}`;
  evidence.snapshotSqlByteSize = sql.length;
  evidence.snapshotGzipSha256 = sha256(compressed);
  evidence.snapshotGzipByteSize = compressed.length;
  delete evidence.evidenceHash;
  evidence.evidenceHash = sha256(Buffer.from(JSON.stringify(evidence)));

  await Promise.all([
    writeFile(path.join(canonicalOutputDirectory, "candidate.sql.gz"), compressed, { flag: "wx" }),
    writeFile(path.join(canonicalOutputDirectory, "evidence.json"), `${JSON.stringify(evidence, null, 2)}\n`, { flag: "wx" }),
  ]);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [, , seedPath, evidencePath, outputDirectory] = process.argv;
  if (!seedPath || !evidencePath || !outputDirectory) {
    throw new Error("usage: prepare-timetable-rollback-candidate.mjs <seed.gz> <evidence.json> <output-dir>");
  }
  await prepareRollbackCandidate(seedPath, evidencePath, outputDirectory);
}
