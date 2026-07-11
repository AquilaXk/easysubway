#!/usr/bin/env node
import { readFileSync } from "node:fs";
import path from "node:path";
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

// reviewStatus 허용 enum — 정본(route-map-license-decision.json)의 reviewStatusValues에서
// 파생한다. 리터럴 복사(이중 정의)는 정본과 이 게이트가 어긋나도(enum drift) 잡지 못하므로
// 정본을 단일 출처로 읽는다. 스크립트 위치 기준으로 리포 루트를 산출해 cwd에 의존하지 않는다.
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const licenseDecision = JSON.parse(
  readFileSync(path.join(repoRoot, "tools/route-map/route-map-license-decision.json"), "utf8"),
);
const allowedReviewStatus = licenseDecision.reviewStatusValues;

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
    if (
      map.license.reviewStatus !== undefined &&
      map.license.reviewStatus !== null &&
      map.license.reviewStatus !== "" &&
      !allowedReviewStatus.includes(map.license.reviewStatus)
    ) {
      failures.push(
        `${id}: license.reviewStatus must be one of ${allowedReviewStatus.join(", ")}`,
      );
    }
  }
  return failures;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const manifest = JSON.parse(
    readFileSync(path.join(repoRoot, "apps/mobile/assets/datapacks/metro_map_pack/manifest.json"), "utf8"),
  );
  const failures = validateMapAttributionManifest(manifest);
  if (failures.length > 0) {
    console.error(failures.join("\n"));
    process.exitCode = 1;
  }
}
