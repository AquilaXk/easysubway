#!/usr/bin/env node
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { gunzipSync, gzipSync } from "node:zlib";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");

export async function prepareRollbackCandidate(seedPath, evidencePath, outputDirectory) {
  const [seed, evidenceBytes] = await Promise.all([readFile(seedPath), readFile(evidencePath)]);
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

  const sql = Buffer.concat([sourceSql, Buffer.from("SELECT 1;\n")]);
  const compressed = gzipSync(sql, { level: 9, mtime: 0 });
  evidence.snapshotSha256 = sha256(sql);
  evidence.snapshotId = `server-timetable-snapshot-${evidence.snapshotSha256.slice(0, 16)}`;
  evidence.snapshotSqlByteSize = sql.length;
  evidence.snapshotGzipSha256 = sha256(compressed);
  evidence.snapshotGzipByteSize = compressed.length;
  delete evidence.evidenceHash;
  evidence.evidenceHash = sha256(Buffer.from(JSON.stringify(evidence)));

  await mkdir(outputDirectory, { recursive: true });
  await Promise.all([
    writeFile(path.join(outputDirectory, "candidate.sql.gz"), compressed),
    writeFile(path.join(outputDirectory, "evidence.json"), `${JSON.stringify(evidence, null, 2)}\n`),
  ]);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const [, , seedPath, evidencePath, outputDirectory] = process.argv;
  if (!seedPath || !evidencePath || !outputDirectory) {
    throw new Error("usage: prepare-timetable-rollback-candidate.mjs <seed.gz> <evidence.json> <output-dir>");
  }
  await prepareRollbackCandidate(seedPath, evidencePath, outputDirectory);
}
