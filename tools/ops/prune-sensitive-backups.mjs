#!/usr/bin/env node

import { lstat, opendir, rm } from "node:fs/promises";
import path from "node:path";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  args.set(process.argv[index], process.argv[index + 1]);
}

const root = path.resolve(args.get("--root") ?? "");
const retentionDays = Number(args.get("--retention-days"));

if (!args.get("--root") || root === path.parse(root).root) {
  throw new Error("--root must be a non-root backup directory");
}
if (!Number.isInteger(retentionDays) || retentionDays < 1 || retentionDays > 365) {
  throw new Error("--retention-days must be an integer from 1 to 365");
}

const cutoff = Date.now() - retentionDays * 24 * 60 * 60 * 1000;
const postgresBackup = /^easysubway-postgres-\d{8}T\d{6}Z\.[A-Za-z0-9]+\.dump(?:\.sha256)?$/;
const photoBackup = /^easysubway-report-photos-\d{8}T\d{6}Z\.[A-Za-z0-9]+$/;
let pruned = 0;

async function pruneDirectory(directory) {
  let entries;
  try {
    entries = await opendir(directory);
  } catch (error) {
    if (error?.code === "ENOENT") {
      return;
    }
    throw error;
  }

  for await (const entry of entries) {
    const candidate = path.join(directory, entry.name);
    const metadata = await lstat(candidate);
    if (metadata.isSymbolicLink()) {
      continue;
    }

    const isPostgresBackup = entry.isFile() && postgresBackup.test(entry.name);
    const isPhotoBackup = entry.isDirectory() && photoBackup.test(entry.name);
    if ((isPostgresBackup || isPhotoBackup) && metadata.mtimeMs <= cutoff) {
      await rm(candidate, { recursive: isPhotoBackup, force: true });
      pruned += 1;
      continue;
    }
    if (entry.isDirectory() && !isPhotoBackup) {
      await pruneDirectory(candidate);
    }
  }
}

await pruneDirectory(root);
console.log(`sensitive-backup-retention: pruned=${pruned} retention_days=${retentionDays}`);
