#!/usr/bin/env node
import { isMainModule } from "../lib/is-main-module.mjs";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { validateSourceGovernancePolicy } from "../datapack/source-governance-policy.mjs";
import { validateLedger } from "../repo/issue-migration-ledger.mjs";
import { validateSchema } from "./lib/json-schema-lite.mjs";
import { codepointCompare } from "../lib/codepoint-compare.mjs";

const DATAPACK_MANIFEST_SCHEMA_PATH = "contracts/datapack/datapack-manifest.schema.json";
const DATAPACK_INDEX_SCHEMA_PATH = "contracts/datapack/datapack-index.schema.json";
const DATAPACK_COMPATIBILITY_MATRIX_PATH = "contracts/datapack/compatibility-matrix.json";
const DATAPACK_INDEX_PATH = "apps/mobile/assets/datapacks/index.json";
const DEFAULT_WORKSPACE_PATH = "contracts/workspaces/hub.json";
const SOURCE_INVENTORY_PATH = "apps/mobile/assets/datapacks/source-inventory.json";
const SOURCE_INVENTORY_SCHEMA_PATH = "contracts/datapack/source-inventory.schema.json";
const SOURCE_GOVERNANCE_POLICY_PATH = "tools/datapack/source-governance-policy.json";
const CANONICAL_NUMBER_CONTRACT_SCHEMA_PATH = "contracts/datapack/canonical-number-contract.schema.json";
const CANONICAL_NUMBER_CONTRACT_PATH = "contracts/datapack/canonical-number-contract.json";
const FRESHNESS_POLICY_PATH = "release/product-gates/datapack-freshness-sla.json";
const PACK_APP_SCHEMA_PARITY_ALLOWLIST_PATH = "contracts/datapack/pack-app-schema-parity-allowlist.json";
const PACK_APP_SCHEMA_PARITY_ALLOWLIST_SCHEMA_PATH =
  "contracts/datapack/pack-app-schema-parity-allowlist.schema.json";
const CATALOG_RAW_SQL_TABLES_PATH = "contracts/datapack/catalog-raw-sql-tables.json";
const CATALOG_RAW_SQL_TABLES_SCHEMA_PATH = "contracts/datapack/catalog-raw-sql-tables.schema.json";
const REPOSITORY_SPLIT_ISSUES_SCHEMA_PATH = "contracts/repository-split-issues.schema.json";
const REPOSITORY_SPLIT_ISSUES_PATH = "release/migrations/repository-split-issues.json";
const EXTRACTION_REPOSITORIES = {
  data: "AquilaXk/easysubway-data",
  platform: "AquilaXk/easysubway-platform",
  backend: "AquilaXk/easysubway-backend",
  mobile: "AquilaXk/easysubway-mobile",
};

export function loadJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

export function loadWorkspace(workspacePath = DEFAULT_WORKSPACE_PATH) {
  const absoluteWorkspacePath = resolve(workspacePath);
  if (!existsSync(absoluteWorkspacePath)) throw new Error(`${workspacePath}: workspace 누락`);
  let workspace;
  try {
    workspace = loadJson(absoluteWorkspacePath);
  } catch {
    throw new Error(`${workspacePath}: 유효한 JSON이 필요하다`);
  }
  if (workspace == null || typeof workspace !== "object" || Array.isArray(workspace)) {
    throw new Error(`${workspacePath}: 객체가 필요하다`);
  }
  const required = ["contracts", "gateDirectories", "datapackIndex", "sourceInventory", "governancePolicy", "freshnessPolicy"];
  for (const field of required) {
    if (!Object.hasOwn(workspace, field)) throw new Error(`${workspacePath}: ${field} 필수`);
  }
  if (workspace.gateDirectories == null || typeof workspace.gateDirectories !== "object" || Array.isArray(workspace.gateDirectories)) {
    throw new Error(`${workspacePath}: gateDirectories 객체가 필요하다`);
  }
  for (const ownerComponent of ["hub", "mobile"]) {
    if (typeof workspace.gateDirectories[ownerComponent] !== "string" || workspace.gateDirectories[ownerComponent].trim() === "") {
      throw new Error(`${workspacePath}: gateDirectories.${ownerComponent} 필수`);
    }
  }
  for (const field of ["contracts", "datapackIndex", "sourceInventory", "governancePolicy", "freshnessPolicy"]) {
    if (typeof workspace[field] !== "string" || workspace[field].trim() === "") {
      throw new Error(`${workspacePath}: ${field}은 비어 있지 않은 경로가 필요하다`);
    }
  }
  const workspaceDirectory = dirname(absoluteWorkspacePath);
  const resolveWorkspacePath = (value) => relative(process.cwd(), resolve(workspaceDirectory, value)) || ".";
  return {
    contracts: resolveWorkspacePath(workspace.contracts),
    gateDirectories: Object.fromEntries(Object.entries(workspace.gateDirectories).map(
      ([ownerComponent, directory]) => [ownerComponent, resolveWorkspacePath(directory)],
    )),
    datapackIndex: resolveWorkspacePath(workspace.datapackIndex),
    sourceInventory: resolveWorkspacePath(workspace.sourceInventory),
    governancePolicy: resolveWorkspacePath(workspace.governancePolicy),
    freshnessPolicy: resolveWorkspacePath(workspace.freshnessPolicy),
  };
}

export function collectContractErrors(workspacePath = DEFAULT_WORKSPACE_PATH) {
  const errors = [];
  let workspace;
  try {
    workspace = loadWorkspace(workspacePath);
  } catch (error) {
    errors.push(error instanceof Error ? error.message : String(error));
    return errors;
  }
  const contract = (path) => join(workspace.contracts, path);
  const repositoryRoot = dirname(workspace.contracts);
  validateJson(contract("datapack/datapack-index.schema.json"), workspace.datapackIndex, errors);
  validateJson(
    contract("datapack/source-inventory.schema.json"),
    workspace.sourceInventory,
    errors,
  );
  validateJson(
    contract("datapack/source-governance-policy.schema.json"),
    workspace.governancePolicy,
    errors,
  );
  validateJson(
    contract("datapack/canonical-number-contract.schema.json"),
    contract("datapack/canonical-number-contract.json"),
    errors,
  );
  validateJson(
    contract("datapack/pack-app-schema-parity-allowlist.schema.json"),
    contract("datapack/pack-app-schema-parity-allowlist.json"),
    errors,
  );
  validateJson(contract("datapack/catalog-raw-sql-tables.schema.json"), contract("datapack/catalog-raw-sql-tables.json"), errors);
  const repositorySplitIssueLedgerValid = validateJson(
    contract("repository-split-issues.schema.json"),
    join(repositoryRoot, "release/migrations/repository-split-issues.json"),
    errors,
  );
  if (repositorySplitIssueLedgerValid) {
    const repositorySplitIssuesPath = join(repositoryRoot, "release/migrations/repository-split-issues.json");
    errors.push(...validateRepositorySplitIssueLedger(loadJson(repositorySplitIssuesPath)).map(
      (error) => `${repositorySplitIssuesPath}: ${error}`,
    ));
  }
  if (!existsSync(workspace.freshnessPolicy)) errors.push(`${workspace.freshnessPolicy} 누락`);
  if ([workspace.sourceInventory, workspace.governancePolicy, workspace.freshnessPolicy].every(existsSync)) {
    validateSourceGovernanceContracts({
      inventory: loadJson(workspace.sourceInventory),
      governancePolicy: loadJson(workspace.governancePolicy),
      freshnessPolicy: loadJson(workspace.freshnessPolicy),
    }, errors);
  }
  validateBoundaries(errors, contract("boundaries.json"));
  validateOpenApiFixtures(errors, workspace.contracts);
  validateCompatibilityMatrix(errors, contract("datapack/compatibility-matrix.json"), workspace.datapackIndex);
  validateGateIndex(errors, contract("release/gate-index.json"), workspace.gateDirectories);
  validateEnvScopeMap(errors, join(workspace.contracts, "env/env-scope-map.json"), join(repositoryRoot, ".env.example"));
  return errors;
}

export function validateRepositorySplitIssueLedger(ledger) {
  return validateLedger(ledger);
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
  if (missing) return false;
  let schema;
  let value;
  try {
    schema = loadJson(schemaPath);
  } catch {
    errors.push(`${schemaPath}: 유효한 JSON이 필요하다`);
    return false;
  }
  try {
    value = loadJson(valuePath);
  } catch {
    errors.push(`${valuePath}: 유효한 JSON이 필요하다`);
    return false;
  }
  const result = validateSchema(schema, value);
  errors.push(...result.errors.map((error) => `${valuePath}: ${error}`));
  if (schemaPath === DATAPACK_MANIFEST_SCHEMA_PATH) validateDatapackManifest(value, valuePath, errors);
  if (schemaPath === DATAPACK_INDEX_SCHEMA_PATH) validateDatapackIndex(value, valuePath, errors);
  if (schemaPath === SOURCE_INVENTORY_SCHEMA_PATH) validateSourceInventory(value, valuePath, errors);
  return result.errors.length === 0;
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

function validateBoundaries(errors, boundariesPath) {
  if (!existsSync(boundariesPath)) return;
  errors.push(...validateBoundariesPayload(loadJson(boundariesPath)));
}

export function validateBoundariesPayload(boundaries) {
  const errors = [];
  if (boundaries.schemaVersion !== 2) errors.push("contracts/boundaries.json: schemaVersion은 2이어야 한다");
  const targets = boundaries.extractionTargets ?? {};
  const splitOrder = Array.isArray(boundaries.splitOrder) ? boundaries.splitOrder : [];
  const splitTargets = new Set();
  for (const targetName of splitOrder) {
    if (splitTargets.has(targetName)) {
      errors.push(`contracts/boundaries.json: ${targetName} splitOrder 중복`);
      continue;
    }
    splitTargets.add(targetName);
    if (!(targetName in targets)) errors.push(`contracts/boundaries.json: ${targetName} extraction target 누락`);
  }
  for (const targetName of Object.keys(targets)) {
    if (!splitTargets.has(targetName)) errors.push(`contracts/boundaries.json: ${targetName} splitOrder 누락`);
  }
  for (const targetName of Object.keys(EXTRACTION_REPOSITORIES)) {
    if (!Object.hasOwn(targets, targetName) && !splitTargets.has(targetName)) {
      errors.push(`contracts/boundaries.json: ${targetName} extraction target 누락`);
      errors.push(`contracts/boundaries.json: ${targetName} splitOrder 누락`);
    }
  }
  const repositories = new Set();
  const ownedRoots = new Set();
  const sourceAreaOwners = new Map();
  const partialRoots = [];
  for (const [targetName, target] of Object.entries(targets)) {
    if (!Object.hasOwn(EXTRACTION_REPOSITORIES, targetName)) {
      errors.push(`contracts/boundaries.json: ${targetName} extraction target 불량`);
      continue;
    }
    const expectedRepository = EXTRACTION_REPOSITORIES[targetName];
    if (target.repository !== expectedRepository) {
      errors.push(`contracts/boundaries.json: ${targetName} repository 불량`);
    } else if (repositories.has(target.repository)) {
      errors.push(`contracts/boundaries.json: ${target.repository} repository 중복`);
    } else {
      repositories.add(target.repository);
    }
    const sourceAreas = requiredStringArray(targetName, target, "sourceAreas", errors);
    if (new Set(sourceAreas).size !== sourceAreas.length) {
      errors.push(`contracts/boundaries.json: ${targetName} sourceAreas 중복`);
    }
    for (const area of sourceAreas) {
      if (!(area in (boundaries.areas ?? {}))) errors.push(`contracts/boundaries.json: ${targetName}.${area} area 누락`);
      const owner = sourceAreaOwners.get(area);
      if (owner !== undefined && owner !== targetName) {
        errors.push(`contracts/boundaries.json: ${area} sourceArea가 ${owner}, ${targetName}에 중복 귀속됨`);
      }
      sourceAreaOwners.set(area, targetName);
    }
    for (const root of requiredStringArray(targetName, target, "ownedRoots", errors)) {
      if (ownedRoots.has(root)) errors.push(`contracts/boundaries.json: ${root} ownedRoots 중복`);
      ownedRoots.add(root);
    }
    for (const root of requiredStringArray(targetName, target, "partialRoots", errors)) {
      partialRoots.push({ targetName, root });
    }
  }
  for (const { targetName, root } of partialRoots) {
    if (ownedRoots.has(root)) errors.push(`contracts/boundaries.json: ${targetName}.${root} partialRoots가 ownedRoots와 겹친다`);
  }
  return errors;
}

function requiredStringArray(targetName, target, field, errors) {
  const value = target?.[field];
  const path = `contracts/boundaries.json: ${targetName}.${field}`;
  if (!Array.isArray(value) || value.length === 0) {
    errors.push(`${path}는 비어 있지 않은 배열이 필요하다`);
    return [];
  }
  if (value.some((item) => typeof item !== "string" || item.trim() === "")) {
    errors.push(`${path}는 비어 있지 않은 문자열만 허용한다`);
  }
  if (new Set(value).size !== value.length) errors.push(`${path} 중복`);
  return value;
}

function validateOpenApiFixtures(errors, contractsDirectory) {
  const apiDirectory = join(contractsDirectory, "api");
  if (!existsSync(apiDirectory)) return;
  const fixtures = [
    "report-upload-intent.created.json",
    "report-create.created.json",
    "report-status.ok.json",
    "report-confirm.ok.json",
    "realtime-arrivals.ok.json",
    "realtime-train-positions.ok.json",
  ];
  for (const fixture of fixtures) {
    if (!existsSync(join(apiDirectory, "fixtures", fixture))) errors.push(`${join(apiDirectory, "fixtures", fixture)} 누락`);
  }
  for (const [file, paths] of Object.entries({
    "report-api.openapi.yaml": ["/api/v1/report-uploads", "/api/v1/reports", "/api/v1/reports/{reportId}"],
    "realtime-api.openapi.yaml": ["/api/v1/realtime/arrivals", "/api/v1/realtime/train-positions"],
    "train-api.openapi.yaml": ["/api/v1/trains/stations", "/api/v1/trains/search"],
  })) {
    const docPath = join(apiDirectory, file);
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

function validateCompatibilityMatrix(errors, matrixPath, indexPath) {
  if (!existsSync(matrixPath)) return;
  if (!existsSync(indexPath)) {
    errors.push(`${indexPath} 누락`);
    return;
  }
  const matrix = loadJson(matrixPath);
  const index = loadJson(indexPath);
  validateCompatibilityMatrixPayload(matrix, index, errors);
}

export function validateCompatibilityMatrixPayload(matrix, index, errors) {
  if (!(matrix.mobile ?? []).some((mobile) => mobile.acceptsIndexSchemaVersions?.includes(index.schemaVersion))) {
    errors.push("contracts/datapack/compatibility-matrix.json: 번들 index schemaVersion 미지원");
  }
}

function validateGateIndex(errors, indexPath, gateDirectories) {
  if (!existsSync(indexPath)) return;
  const index = loadJson(indexPath);
  const ownerComponents = { product: "hub", mobile: "mobile" };
  for (const gate of index.gates ?? []) {
    const ownerComponent = ownerComponents[gate.scope];
    if (ownerComponent === undefined) {
      errors.push(`${indexPath}: ${gate.file} scope 불량`);
    } else if (gate.ownerComponent !== ownerComponent) {
      errors.push(`${indexPath}: ${gate.file} ownerComponent 불량`);
    }
  }
  for (const [ownerComponent, directory] of Object.entries(gateDirectories)) {
    if (!existsSync(directory)) {
      errors.push(`${directory} 디렉터리 누락`);
      continue;
    }
    const actual = readdirSync(directory).filter((file) => file.endsWith(".json")).sort(compareText);
    const indexed = (index.gates ?? [])
      .filter((gate) => gate.ownerComponent === ownerComponent)
      .map((gate) => gate.file)
      .sort(compareText);
    if (JSON.stringify(actual) !== JSON.stringify(indexed)) {
      errors.push(`${indexPath}: ${ownerComponent} gate 디렉터리 실물과 1:1 대응하지 않는다`);
    }
  }
}

function validateEnvScopeMap(errors, mapPath, envExamplePath) {
  if (!existsSync(mapPath) || !existsSync(envExamplePath)) return;
  const map = loadJson(mapPath);
  const envKeys = readFileSync(envExamplePath, "utf8")
    .split(/\r?\n/)
    .filter((line) => line && !line.startsWith("#"))
    .map((line) => line.split("=", 1)[0])
    .sort(compareText);
  const mapped = Object.keys(map.keys ?? {}).sort(compareText);
  if (JSON.stringify(envKeys) !== JSON.stringify(mapped)) {
    errors.push(`${mapPath}: .env.example 키 집합과 다르다`);
  }
}

function compareText(left, right) {
  return codepointCompare(left, right);
}

if (isMainModule(import.meta.url)) {
  const workspaceIndex = process.argv.indexOf("--workspace");
  if (workspaceIndex === -1 || workspaceIndex !== process.argv.length - 2) {
    console.error("사용법: node tools/ci/check-contracts.mjs --workspace <workspace.json>");
    process.exit(1);
  }
  const errors = collectContractErrors(process.argv[workspaceIndex + 1]);
  if (errors.length) {
    console.error(errors.map((error) => `- ${error}`).join("\n"));
    process.exit(1);
  }
}
