#!/usr/bin/env node
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { validateSchema } from "./lib/json-schema-lite.mjs";

const DATAPACK_MANIFEST_SCHEMA_PATH = "contracts/datapack/datapack-manifest.schema.json";
const DATAPACK_COMPATIBILITY_MATRIX_PATH = "contracts/datapack/compatibility-matrix.json";
const DATAPACK_INDEX_PATH = "apps/mobile/assets/datapacks/index.json";
const RELEASE_GATE_INDEX_PATH = "contracts/release/gate-index.json";
const RELEASE_GATE_DIRECTORY = "apps/mobile/release";

export function loadJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

export function collectContractErrors() {
  const errors = [];
  validateJson("contracts/datapack/datapack-index.schema.json", "apps/mobile/assets/datapacks/index.json", errors);
  validateJson(
    "contracts/datapack/source-inventory.schema.json",
    "apps/mobile/assets/datapacks/source-inventory.json",
    errors,
  );
  validateBoundaries(errors);
  validateOpenApiFixtures(errors);
  validateCompatibilityMatrix(errors);
  validateGateIndex(errors);
  validateEnvScopeMap(errors);
  return errors;
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
  return left.localeCompare(right);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const errors = collectContractErrors();
  if (errors.length) {
    console.error(errors.map((error) => `- ${error}`).join("\n"));
    process.exit(1);
  }
}
