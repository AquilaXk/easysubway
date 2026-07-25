#!/usr/bin/env node
import { isMainModule } from "../lib/is-main-module.mjs";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { validateSourceGovernancePolicy } from "../datapack/source-governance-policy.mjs";
import { validateSchema } from "./lib/json-schema-lite.mjs";
import { codepointCompare } from "../lib/codepoint-compare.mjs";

const DATAPACK_MANIFEST_SCHEMA_PATH = "contracts/datapack/datapack-manifest.schema.json";
const DATAPACK_INDEX_SCHEMA_PATH = "contracts/datapack/datapack-index.schema.json";
const DATAPACK_COMPATIBILITY_MATRIX_PATH = "contracts/datapack/compatibility-matrix.json";
const DATAPACK_INDEX_PATH = "apps/mobile/assets/datapacks/index.json";
const RELEASE_GATE_INDEX_PATH = "contracts/release/gate-index.json";
const RELEASE_GATE_DIRECTORY = "apps/mobile/release";
const SOURCE_INVENTORY_PATH = "apps/mobile/assets/datapacks/source-inventory.json";
const SOURCE_INVENTORY_SCHEMA_PATH = "contracts/datapack/source-inventory.schema.json";
const SOURCE_GOVERNANCE_POLICY_PATH = "tools/datapack/source-governance-policy.json";
const FRESHNESS_POLICY_PATH = "apps/mobile/release/datapack-freshness-sla.json";
const PACK_APP_SCHEMA_PARITY_ALLOWLIST_PATH = "contracts/datapack/pack-app-schema-parity-allowlist.json";
const PACK_APP_SCHEMA_PARITY_ALLOWLIST_SCHEMA_PATH =
  "contracts/datapack/pack-app-schema-parity-allowlist.schema.json";
const CATALOG_RAW_SQL_TABLES_PATH = "contracts/datapack/catalog-raw-sql-tables.json";
const CATALOG_RAW_SQL_TABLES_SCHEMA_PATH = "contracts/datapack/catalog-raw-sql-tables.schema.json";

export function loadJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

export function collectContractErrors() {
  const errors = [];
  validateJson("contracts/datapack/datapack-index.schema.json", "apps/mobile/assets/datapacks/index.json", errors);
  validateJson(
    "contracts/datapack/source-inventory.schema.json",
    SOURCE_INVENTORY_PATH,
    errors,
  );
  validateJson(
    "contracts/datapack/source-governance-policy.schema.json",
    SOURCE_GOVERNANCE_POLICY_PATH,
    errors,
  );
  validateJson(
    PACK_APP_SCHEMA_PARITY_ALLOWLIST_SCHEMA_PATH,
    PACK_APP_SCHEMA_PARITY_ALLOWLIST_PATH,
    errors,
  );
  validateJson(CATALOG_RAW_SQL_TABLES_SCHEMA_PATH, CATALOG_RAW_SQL_TABLES_PATH, errors);
  if (!existsSync(FRESHNESS_POLICY_PATH)) errors.push(`${FRESHNESS_POLICY_PATH} 누락`);
  if ([SOURCE_INVENTORY_PATH, SOURCE_GOVERNANCE_POLICY_PATH, FRESHNESS_POLICY_PATH].every(existsSync)) {
    validateSourceGovernanceContracts({
      inventory: loadJson(SOURCE_INVENTORY_PATH),
      governancePolicy: loadJson(SOURCE_GOVERNANCE_POLICY_PATH),
      freshnessPolicy: loadJson(FRESHNESS_POLICY_PATH),
    }, errors);
  }
  validateBoundaries(errors);
  validateOpenApiFixtures(errors);
  validateCompatibilityMatrix(errors);
  validateGateIndex(errors);
  validateEnvScopeMap(errors);
  return errors;
}

export function validateSourceGovernanceContracts(
  { governancePolicy, inventory, freshnessPolicy },
  errors,
) {
  try {
    validateSourceGovernancePolicy({ policy: governancePolicy, inventory, freshnessPolicy });
  } catch (error) {
    errors.push(`source-governance: ${error instanceof Error ? error.message : String(error)}`);
  }
}

export function validateJson(schemaPath, valuePath, errors) {
  let missing = false;
  if (!existsSync(schemaPath)) {
    errors.push(`${schemaPath} 누락`);
    missing = true;
  }
  if (!existsSync(valuePath)) {
    errors.push(`${valuePath} 누락`);
    missing = true;
  }
  if (missing) return;
  const result = validateSchema(loadJson(schemaPath), loadJson(valuePath));
  errors.push(...result.errors.map((error) => `${valuePath}: ${error}`));
  if (schemaPath === DATAPACK_MANIFEST_SCHEMA_PATH) validateDatapackManifest(loadJson(valuePath), valuePath, errors);
  if (schemaPath === DATAPACK_INDEX_SCHEMA_PATH) validateDatapackIndex(loadJson(valuePath), valuePath, errors);
  if (schemaPath === SOURCE_INVENTORY_SCHEMA_PATH) validateSourceInventory(loadJson(valuePath), valuePath, errors);
}

export function validateSourceInventory(inventory, valuePath, errors) {
  if (inventory == null || typeof inventory !== "object" || Array.isArray(inventory)
    || !Array.isArray(inventory.sources)) return;
  for (const [index, source] of inventory.sources.entries()) {
    if (source == null || typeof source !== "object" || Array.isArray(source)) continue;
    const path = `${valuePath}: $.sources.${index}`;
    const sourceDomains = new Set(Array.isArray(source.coverageScope?.sourceDomains)
      ? source.coverageScope.sourceDomains : []);
    const requiresTopology = sourceDomains.has("route_graph_topology");
    const requiresSchedule = sourceDomains.has("schedule_timetable");
    const requiresMembership = sourceDomains.has("station_line_membership");
    const requiresRouteMap = sourceDomains.has("route_map_positions");
    const requiresAccessibility = sourceDomains.has("accessibility_facilities");
    if (source.productionUseAllowed === true && requiresTopology && source.topologyAdmissionEvidence == null) {
      errors.push(`${path}.topologyAdmissionEvidence: route_graph_topology production 승인은 topologyAdmissionEvidence가 필요하다`);
    }
    if (source.productionUseAllowed === true && requiresSchedule && source.scheduleAdmissionEvidence == null) {
      errors.push(`${path}.scheduleAdmissionEvidence: schedule_timetable production 승인은 scheduleAdmissionEvidence가 필요하다`);
    }
    if (source.productionUseAllowed === true && requiresMembership && source.membershipAdmissionEvidence == null) {
      errors.push(`${path}.membershipAdmissionEvidence: station_line_membership production 승인은 membershipAdmissionEvidence가 필요하다`);
    }
    if (source.productionUseAllowed === true && requiresRouteMap && source.routeMapAdmissionEvidence == null) {
      errors.push(`${path}.routeMapAdmissionEvidence: route_map_positions production 승인은 routeMapAdmissionEvidence가 필요하다`);
    }
    if (source.productionUseAllowed === true && requiresAccessibility
      && source.accessibilityAdmissionEvidence == null) {
      errors.push(`${path}.accessibilityAdmissionEvidence: accessibility_facilities production 승인은 accessibilityAdmissionEvidence가 필요하다`);
    }
    if (source.productionUseAllowed === true && !requiresTopology && !requiresSchedule && !requiresMembership
      && !requiresRouteMap && !requiresAccessibility
      && source.topologyAdmissionEvidence == null && source.scheduleAdmissionEvidence == null
      && source.membershipAdmissionEvidence == null && source.routeMapAdmissionEvidence == null
      && source.accessibilityAdmissionEvidence == null) {
      errors.push(`${path}.productionUseAllowed: true는 production admission evidence가 필요하다`);
    }
    if (source.topologyAdmissionEvidence != null && !requiresTopology) {
      errors.push(`${path}.topologyAdmissionEvidence: route_graph_topology source domain이 필요하다`);
    }
    if (source.scheduleAdmissionEvidence != null && !requiresSchedule) {
      errors.push(`${path}.scheduleAdmissionEvidence: schedule_timetable source domain이 필요하다`);
    }
    if (source.membershipAdmissionEvidence != null && !requiresMembership) {
      errors.push(`${path}.membershipAdmissionEvidence: station_line_membership source domain이 필요하다`);
    }
    if (source.routeMapAdmissionEvidence != null && !requiresRouteMap) {
      errors.push(`${path}.routeMapAdmissionEvidence: route_map_positions source domain이 필요하다`);
    }
    if (source.accessibilityAdmissionEvidence != null && !requiresAccessibility) {
      errors.push(`${path}.accessibilityAdmissionEvidence: accessibility_facilities source domain이 필요하다`);
    }
    if (source.topologyAdmissionEvidence != null && source.productionUseAllowed !== true) {
      errors.push(`${path}.topologyAdmissionEvidence: productionUseAllowed true가 필요하다`);
    }
    if (source.scheduleAdmissionEvidence != null && source.productionUseAllowed !== true) {
      errors.push(`${path}.scheduleAdmissionEvidence: productionUseAllowed true가 필요하다`);
    }
    if (source.membershipAdmissionEvidence != null && source.productionUseAllowed !== true) {
      errors.push(`${path}.membershipAdmissionEvidence: productionUseAllowed true가 필요하다`);
    }
    if (source.routeMapAdmissionEvidence != null && source.productionUseAllowed !== true) {
      errors.push(`${path}.routeMapAdmissionEvidence: productionUseAllowed true가 필요하다`);
    }
    if (source.accessibilityAdmissionEvidence != null && source.productionUseAllowed !== true) {
      errors.push(`${path}.accessibilityAdmissionEvidence: productionUseAllowed true가 필요하다`);
    }
  }
}

export function validateDatapackIndex(index, valuePath, errors) {
  if (index == null || typeof index !== "object" || Array.isArray(index)) return;
  for (const field of ["builtAt", "qualityAsOf", "freshnessExpiresAt"]) {
    const value = index[field];
    const millis = typeof value === "string" ? Date.parse(value) : Number.NaN;
    if (!Number.isFinite(millis) || new Date(millis).toISOString() !== value) {
      errors.push(`${valuePath}: ${field}은 유효한 UTC 시각이어야 한다`);
    }
  }
}

export function validateDatapackManifest(manifest, valuePath, errors) {
  if ((manifest.manifestVersion ?? 1) === 1 && manifest.activePack === undefined) {
    errors.push(`${valuePath}: manifestVersion 1은 activePack이 필요하다`);
  }
  if (manifest.manifestVersion === 2) {
    for (const key of ["signature", "keyId", "channel", "releaseSequence", "publishedAt", "expiresAt"]) {
      if (!(key in manifest)) errors.push(`${valuePath}: manifestVersion 2는 ${key}이 필요하다`);
    }
  }
  const rolloutPercentage = manifest.rollout?.percentage;
  if (rolloutPercentage !== undefined && rolloutPercentage > 100) {
    errors.push(`${valuePath}: rollout.percentage는 100 이하여야 한다`);
  }
}

function validateBoundaries(errors) {
  if (!existsSync("contracts/boundaries.json")) return;
  const boundaries = loadJson("contracts/boundaries.json");
  if (boundaries.schemaVersion !== 1) errors.push("contracts/boundaries.json: schemaVersion은 1이어야 한다");
  for (const area of boundaries.splitOrder ?? []) {
    if (!(area in (boundaries.areas ?? {}))) errors.push(`contracts/boundaries.json: ${area} area 누락`);
  }
}

function validateOpenApiFixtures(errors) {
  if (!existsSync("contracts/api")) return;
  const fixtures = [
    "report-upload-intent.created.json",
    "report-create.created.json",
    "report-status.ok.json",
    "report-confirm.ok.json",
    "realtime-arrivals.ok.json",
    "realtime-train-positions.ok.json",
  ];
  for (const fixture of fixtures) {
    if (!existsSync(join("contracts/api/fixtures", fixture))) errors.push(`contracts/api/fixtures/${fixture} 누락`);
  }
  for (const [docPath, paths] of Object.entries({
    "contracts/api/report-api.openapi.yaml": ["/api/v1/report-uploads", "/api/v1/reports", "/api/v1/reports/{reportId}"],
    "contracts/api/realtime-api.openapi.yaml": ["/api/v1/realtime/arrivals", "/api/v1/realtime/train-positions"],
    "contracts/api/train-api.openapi.yaml": ["/api/v1/trains/stations", "/api/v1/trains/search"],
  })) {
    if (!existsSync(docPath)) {
      errors.push(`${docPath} 누락`);
      continue;
    }
    const doc = readFileSync(docPath, "utf8");
    for (const apiPath of paths) {
      if (!doc.includes(`${apiPath}:`)) errors.push(`${docPath}: ${apiPath} 누락`);
    }
  }
}

function validateCompatibilityMatrix(errors) {
  if (!existsSync(DATAPACK_COMPATIBILITY_MATRIX_PATH)) return;
  if (!existsSync(DATAPACK_INDEX_PATH)) {
    errors.push(`${DATAPACK_INDEX_PATH} 누락`);
    return;
  }
  const matrix = loadJson(DATAPACK_COMPATIBILITY_MATRIX_PATH);
  const index = loadJson(DATAPACK_INDEX_PATH);
  validateCompatibilityMatrixPayload(matrix, index, errors);
}

export function validateCompatibilityMatrixPayload(matrix, index, errors) {
  if (!(matrix.mobile ?? []).some((mobile) => mobile.acceptsIndexSchemaVersions?.includes(index.schemaVersion))) {
    errors.push("contracts/datapack/compatibility-matrix.json: 번들 index schemaVersion 미지원");
  }
}

function validateGateIndex(errors) {
  if (!existsSync(RELEASE_GATE_INDEX_PATH)) return;
  if (!existsSync(RELEASE_GATE_DIRECTORY)) {
    errors.push(`${RELEASE_GATE_DIRECTORY} 디렉터리 누락`);
    return;
  }
  const index = loadJson(RELEASE_GATE_INDEX_PATH);
  const actual = readdirSync(RELEASE_GATE_DIRECTORY).filter((file) => file.endsWith(".json")).sort(compareText);
  const indexed = (index.gates ?? []).map((gate) => gate.file).sort(compareText);
  if (JSON.stringify(actual) !== JSON.stringify(indexed)) {
    errors.push("contracts/release/gate-index.json: apps/mobile/release 실물과 1:1 대응하지 않는다");
  }
  for (const gate of index.gates ?? []) {
    if (!["mobile", "product"].includes(gate.scope)) {
      errors.push(`contracts/release/gate-index.json: ${gate.file} scope 불량`);
    }
  }
}

function validateEnvScopeMap(errors) {
  if (!existsSync("contracts/env/env-scope-map.json") || !existsSync(".env.example")) return;
  const map = loadJson("contracts/env/env-scope-map.json");
  const envKeys = readFileSync(".env.example", "utf8")
    .split(/\r?\n/)
    .filter((line) => line && !line.startsWith("#"))
    .map((line) => line.split("=", 1)[0])
    .sort(compareText);
  const mapped = Object.keys(map.keys ?? {}).sort(compareText);
  if (JSON.stringify(envKeys) !== JSON.stringify(mapped)) {
    errors.push("contracts/env/env-scope-map.json: .env.example 키 집합과 다르다");
  }
}

function compareText(left, right) {
  return codepointCompare(left, right);
}

if (isMainModule(import.meta.url)) {
  const errors = collectContractErrors();
  if (errors.length) {
    console.error(errors.map((error) => `- ${error}`).join("\n"));
    process.exit(1);
  }
}
