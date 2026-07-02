#!/usr/bin/env node
import { readFileSync } from "node:fs";

const manifestPath = process.argv[2] ?? "apps/mobile/assets/datapacks/metro_map_pack/manifest.json";
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const maps = Array.isArray(manifest.maps) ? manifest.maps : [];
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
  "redistributionAllowed",
  "reviewStatus",
];

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
  for (const field of ["attributionRequired", "commercialUseAllowed", "redistributionAllowed"]) {
    if (typeof map.license[field] !== "boolean") {
      failures.push(`${id}: license.${field} must be boolean`);
    }
  }
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exitCode = 1;
}
