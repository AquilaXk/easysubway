#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const requiredLicenseFields = [
  "name",
  "spdx",
  "url",
  "source",
  "source_page",
  "date",
  "authors",
  "changes",
  "attributionRequired",
  "commercialUseAllowed",
  "derivativeWorkAllowed",
  "redistributionAllowed",
  "reviewStatus",
];

export function validateMapAttributionManifest(manifest) {
  const maps = Array.isArray(manifest.maps) ? manifest.maps : [];
  const failures = [];
  for (const map of maps) {
    const id = map.id ?? "(unknown)";
    if (!map.license || typeof map.license !== "object") {
      failures.push(`${id}: missing license block`);
      continue;
    }
    for (const field of requiredLicenseFields) {
      const value = map.license[field];
      if (value === undefined || value === null || value === "") {
        failures.push(`${id}: missing license.${field}`);
      }
    }
    if (!Array.isArray(map.license.authors) || map.license.authors.length === 0) {
      failures.push(`${id}: license.authors must be a non-empty array`);
    }
    for (const field of ["attributionRequired", "commercialUseAllowed", "derivativeWorkAllowed", "redistributionAllowed"]) {
      if (typeof map.license[field] !== "boolean") {
        failures.push(`${id}: license.${field} must be boolean`);
      }
    }
  }
  return failures;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const manifest = JSON.parse(readFileSync("apps/mobile/assets/datapacks/metro_map_pack/manifest.json", "utf8"));
  const failures = validateMapAttributionManifest(manifest);
  if (failures.length > 0) {
    console.error(failures.join("\n"));
    process.exitCode = 1;
  }
}
