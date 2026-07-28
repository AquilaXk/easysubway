#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { isDeepStrictEqual } from "node:util";

import { canonicalJson } from "../datapack/lib/manifest-validation.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";
import { normalizeSvgForCompile } from "./compile-basemap-vec.mjs";
import { cleanupPackDir, openPack, repoRoot } from "./pack-io.mjs";
import { FULL_CANVAS_DECOR_IDS, inkBBoxOf, viewBoxOf } from "./svg-ink-bbox.mjs";

const REGIONS = [
  { id: "seoul", region: "수도권", source: "easy-subway-sma-v4" },
  { id: "busan", region: "부산권", source: "easy-subway-busan-v3" },
  { id: "daegu", region: "대구권", source: "easy-subway-daegu-v3" },
  { id: "daejeon", region: "대전권", source: "easy-subway-daejeon-v3" },
  { id: "gwangju", region: "광주권", source: "easy-subway-gwangju-v3" },
];

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const compareText = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
const compareRows = (a, b) =>
  compareText(String(a.station_id), String(b.station_id)) ||
  compareText(String(a.line_id), String(b.line_id)) ||
  compareText(String(a.region), String(b.region));

export function buildRegionProvenance({ svg, geometryBytes, routeMapPositionRows }) {
  const geometry = JSON.parse(Buffer.from(geometryBytes).toString("utf8"));
  const sourceSvgSha256 = sha256(svg);
  if (geometry.sourceSvgSha256 !== sourceSvgSha256) {
    throw new Error(
      `geometry sourceSvgSha256 mismatch: ${geometry.sourceSvgSha256} != ${sourceSvgSha256}`,
    );
  }

  const normalized = normalizeSvgForCompile(svg);
  const sourceViewBox = viewBoxOf(normalized);
  if (!isDeepStrictEqual(geometry.sourceViewBox, sourceViewBox)) {
    throw new Error(
      `geometry sourceViewBox mismatch: ${JSON.stringify(geometry.sourceViewBox)} != ${JSON.stringify(sourceViewBox)}`,
    );
  }
  const ink = inkBBoxOf(normalized, { excludeIds: FULL_CANVAS_DECOR_IDS });
  const rows = routeMapPositionRows.slice().sort(compareRows);

  return {
    sourceSvgSha256,
    normalizedSvgSha256: sha256(normalized),
    sourceViewBox,
    fullInkBounds: {
      minX: ink.minX,
      minY: ink.minY,
      maxX: ink.maxX,
      maxY: ink.maxY,
    },
    extractorVersion: geometry.extractorVersion,
    geometrySha256: sha256(geometryBytes),
    routeMapPositionsSha256: sha256(canonicalJson(rows)),
    labelSourceCount: (geometry.labels ?? []).filter(
      ({ classification }) => classification === "STATION_LABEL",
    ).length,
    stationNodeCount: (geometry.stationNodes ?? []).length,
    generatorContractVersion: 1,
  };
}

export function generateGeometryProvenanceManifest({
  pack = "apps/mobile/assets/datapacks/capital.sqlite.gz",
} = {}) {
  const opened = openPack(pack, "geometry-provenance-");
  try {
    const regions = {};
    for (const item of REGIONS) {
      const svgPath = path.join(
        repoRoot,
        "tools/route-map/route-map-defs/svg-sources",
        `${item.source}.svg`,
      );
      const geometryPath = path.join(
        repoRoot,
        "tools/route-map/route-map-defs",
        `${item.source}-geometry.json`,
      );
      const rows = opened.db
        .prepare(
          "SELECT * FROM route_map_positions WHERE region = ? ORDER BY station_id, line_id, region",
        )
        .all(item.region);
      regions[item.id] = buildRegionProvenance({
        svg: readFileSync(svgPath, "utf8"),
        geometryBytes: readFileSync(geometryPath),
        routeMapPositionRows: rows,
      });
    }
    return {
      schemaVersion: 1,
      artifactKind: "route-map-geometry-provenance-manifest",
      regions,
    };
  } finally {
    opened.db.close();
    cleanupPackDir(opened.dir);
  }
}

export function verifyGeometryProvenanceManifest(expected, actual) {
  if (!isDeepStrictEqual(expected, actual)) {
    throw new Error("geometry provenance drift");
  }
}

function main() {
  const output = path.join(
    repoRoot,
    "tools/route-map/geometry-provenance-manifest.json",
  );
  writeFileSync(
    output,
    `${JSON.stringify(generateGeometryProvenanceManifest(), null, 2)}\n`,
  );
  process.stdout.write(`${path.relative(repoRoot, output)}\n`);
}

if (isMainModule(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
