#!/usr/bin/env node
import { randomUUID } from "node:crypto";
import { mkdir, open, readFile, rename, rm, stat } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { addCadence } from "./freshness-policy.mjs";
import { requiredUtcInstant } from "./lib/utc-instant.mjs";
import { ROUTE_MAP_REVERIFICATION_CADENCE } from "./lib/route-map-admission-freshness.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const inventoryPaths = [
  "tools/datapack/source-inventory.json",
  "apps/mobile/assets/datapacks/source-inventory.json",
];

export function withRouteMapAdmissionFreshness(inventory) {
  const next = structuredClone(inventory);
  for (const source of next.sources ?? []) {
    const evidence = source.routeMapAdmissionEvidence;
    if (!evidence) continue;
    const capturedAt = requiredUtcInstant(evidence.capturedAt, `${source.id} route-map capturedAt`);
    evidence.freshUntil = new Date(addCadence(capturedAt, ROUTE_MAP_REVERIFICATION_CADENCE)).toISOString();
  }
  return next;
}

export function assertInventoryMirrorByteParity(inventories) {
  if (inventories.some(({ bytes }) => !bytes.equals(inventories[0].bytes))) {
    throw new Error("source inventory mirrors must be byte-identical before refresh");
  }
}

export async function replaceFileAtomically(targetPath, bytes) {
  const directory = path.dirname(targetPath);
  await mkdir(directory, { recursive: true });
  const mode = (await stat(targetPath)).mode & 0o777;
  const temporaryPath = path.join(directory, `.${path.basename(targetPath)}.${process.pid}.${randomUUID()}.tmp`);
  let temporaryFile;
  try {
    temporaryFile = await open(temporaryPath, "wx", mode);
    await temporaryFile.writeFile(bytes);
    await temporaryFile.sync();
    await temporaryFile.close();
    temporaryFile = undefined;
    await rename(temporaryPath, targetPath);
  } catch (error) {
    await temporaryFile?.close().catch(() => {});
    await rm(temporaryPath, { force: true }).catch(() => {});
    throw error;
  }
}

async function main() {
  const inventories = await Promise.all(inventoryPaths.map(async (relativePath) => ({
    relativePath,
    bytes: await readFile(path.join(root, relativePath)),
  })));
  assertInventoryMirrorByteParity(inventories);
  const canonical = withRouteMapAdmissionFreshness(JSON.parse(inventories[0].bytes.toString("utf8")));
  const bytes = `${JSON.stringify(canonical, null, 2)}\n`;
  await Promise.all(inventories.map(({ relativePath }) => replaceFileAtomically(path.join(root, relativePath), bytes)));
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
