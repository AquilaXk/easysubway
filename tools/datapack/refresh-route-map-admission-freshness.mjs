#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
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

async function main() {
  const inventories = await Promise.all(inventoryPaths.map(async (relativePath) => ({
    relativePath,
    inventory: JSON.parse(await readFile(path.join(root, relativePath), "utf8")),
  })));
  const canonical = withRouteMapAdmissionFreshness(inventories[0].inventory);
  const bytes = `${JSON.stringify(canonical, null, 2)}\n`;
  await Promise.all(inventories.map(({ relativePath }) => writeFile(path.join(root, relativePath), bytes)));
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
