#!/usr/bin/env node
import { isMainModule } from "../lib/is-main-module.mjs";
import { existsSync, lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { basename, dirname, isAbsolute, join, relative, resolve, win32 } from "node:path";
import { validateSourceGovernancePolicy } from "../datapack/source-governance-policy.mjs";
import { validateLedger } from "../repo/issue-migration-ledger.mjs";
import { validateSchema } from "./lib/json-schema-lite.mjs";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isDeepStrictEqual } from "node:util";
import {
  DOCUMENTATION_REPOSITORIES,
  validateDocumentationRecord,
} from "./documentation-inventory.mjs";

const DEFAULT_WORKSPACE_PATH = "contracts/workspaces/hub.json";
const architectureDecisionSchemaSnapshots = new WeakMap();
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
  const required = ["contracts", "gateDirectories", "datapackIndex", "sourceInventory", "governancePolicy", "freshnessPolicy", "architectureDecision", "documentationSystemCatalog"];
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
  for (const field of ["contracts", "datapackIndex", "sourceInventory", "governancePolicy", "freshnessPolicy", "architectureDecision", "documentationSystemCatalog"]) {
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
    architectureDecision: resolveWorkspacePath(workspace.architectureDecision),
    documentationSystemCatalog: resolveWorkspacePath(workspace.documentationSystemCatalog),
  };
}

export function collectContractErrors(
  workspacePath = DEFAULT_WORKSPACE_PATH,
  { previousArchitectureDecision = null } = {},
) {
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
  const architectureDecisionValid = validateJson(
    contract("documentation/architecture-decision.schema.json"),
    workspace.architectureDecision,
    errors,
  );
  const documentationSystemCatalogSchema = contract("documentation/documentation-system-catalog.schema.json");
  if (validateJson(documentationSystemCatalogSchema, workspace.documentationSystemCatalog, errors)) {
    validateDocumentationSystemCatalogSemantics(
      loadJson(workspace.documentationSystemCatalog),
      errors,
      workspace.documentationSystemCatalog,
    );
  }
  let currentArchitectureDecisions = [];
  const currentArchitectureDecisionCandidates = new Map();
  if (architectureDecisionValid) {
    const currentArchitectureDecision = loadJson(workspace.architectureDecision);
    if (currentArchitectureDecision.id !== "ADR-HUB-0001") {
      errors.push(`${workspace.architectureDecision}: workspace architectureDecision은 ADR-HUB-0001 root여야 한다`);
    } else {
      currentArchitectureDecisions = validateArchitectureDecisionChain(
        contract("documentation/architecture-decision.schema.json"),
        workspace.architectureDecision,
        currentArchitectureDecision,
        errors,
        currentArchitectureDecisionCandidates,
      );
    }
  }
  if (previousArchitectureDecision != null && currentArchitectureDecisions.length > 0) {
    const previousArchitectureDecisions = Array.isArray(previousArchitectureDecision)
      ? previousArchitectureDecision : [previousArchitectureDecision];
    const previousById = new Map();
    for (const previous of previousArchitectureDecisions) {
      const candidates = previousById.get(previous.id) ?? [];
      candidates.push(previous);
      previousById.set(previous.id, candidates);
    }
    const previousChainIds = new Set();
    let previousMember = previousById.get("ADR-HUB-0001")?.[0];
    while (previousMember != null && !previousChainIds.has(previousMember.id)) {
      previousChainIds.add(previousMember.id);
      if (previousMember.status !== "superseded") break;
      const successors = previousById.get(previousMember.supersededBy) ?? [];
      if (successors.length !== 1) break;
      [previousMember] = successors;
    }
    const currentById = new Map(currentArchitectureDecisions.map((member) => [member.adr.id, member]));
    for (const [previousId, previousCandidates] of previousById) {
      if (previousCandidates.length !== 1) {
        errors.push(`${workspace.architectureDecision}: base ADR ${previousId} 중복`);
        continue;
      }
      const [previous] = previousCandidates;
      const currentCandidates = currentArchitectureDecisionCandidates.get(previousId) ?? [];
      if (currentCandidates.length > 1) {
        errors.push(`${workspace.architectureDecision}: current ADR ${previousId} 중복`);
        continue;
      }
      const current = currentById.get(previousId) ?? (currentCandidates.length === 1
        ? { path: currentCandidates[0][0], adr: currentCandidates[0][1] } : null);
      if (current == null) {
        if (previousChainIds.has(previousId)) {
          errors.push(`${workspace.architectureDecision}: base ADR ${previousId}가 current chain에서 삭제되었다`);
        } else {
          errors.push(`${workspace.architectureDecision}: base ADR ${previousId}가 current catalog에서 삭제되었다`);
        }
        continue;
      }
      const transitionErrors = validateArchitectureDecisionTransition(previous, current.adr);
      errors.push(...transitionErrors
        .map((error) => `${current.path}: ${error}`));
      const previousDecisionSchema = architectureDecisionSchemaSnapshots.get(previous);
      const finalizingProposal = previous.status === "proposed"
        && ["accepted", "rejected", "withdrawn"].includes(current.adr.status);
      if (transitionErrors.length === 0 && previousDecisionSchema !== undefined
        && (previous.status !== "proposed" || finalizingProposal)) {
        let currentDecisionSchema;
        try {
          currentDecisionSchema = loadJson(resolve(dirname(current.path), current.adr.decisionSchema));
        } catch {
          currentDecisionSchema = undefined;
        }
        if (currentDecisionSchema !== undefined
          && !isDeepStrictEqual(previousDecisionSchema, currentDecisionSchema)) {
          errors.push(finalizingProposal
            ? `${current.path}: proposed ADR의 종결 전환은 decision schema도 status-only여야 한다`
            : `${current.path}: accepted/terminal ADR decision schema는 in-place 변경할 수 없고 새 ADR로 supersede해야 한다`);
        }
      }
      if (transitionErrors.length === 0
        && previous.status === "accepted" && current.adr.status === "superseded") {
        const successors = currentArchitectureDecisionCandidates.get(current.adr.supersededBy) ?? [];
        if (successors.length === 0) {
          errors.push(`${current.path}: successor ADR 누락`);
        } else if (successors.length > 1) {
          errors.push(`${current.path}: successor ADR 중복`);
        } else if (!successors[0][2]) {
          errors.push(`${successors[0][0]}: successor ADR는 schema와 semantic 검증을 통과해야 한다`);
        } else if (successors[0][1].status !== "accepted") {
          errors.push(`${current.path}: accepted ADR의 direct successor는 accepted 상태여야 한다`);
        } else if (!successors[0][1].supersedes.includes(current.adr.id)) {
          errors.push(`${successors[0][0]}: supersedes reciprocal link가 필요하다`);
        }
      }
    }
  }
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
  let semanticErrors = [];
  let referencedSchemaValid = true;
  switch (basename(schemaPath)) {
    case "architecture-decision.schema.json":
      referencedSchemaValid = validateArchitectureDecisionSchema(value, valuePath, errors);
      if (result.errors.length === 0 && referencedSchemaValid) {
        semanticErrors = validateArchitectureDecision(value);
        errors.push(...semanticErrors.map((error) => `${valuePath}: ${error}`));
      }
      break;
    case "datapack-manifest.schema.json":
      validateDatapackManifest(value, valuePath, errors);
      break;
    case "datapack-index.schema.json":
      validateDatapackIndex(value, valuePath, errors);
      break;
    case "source-inventory.schema.json":
      validateSourceInventory(value, valuePath, errors);
      break;
    default:
      break;
  }
  return result.errors.length === 0 && referencedSchemaValid && semanticErrors.length === 0;
}

export function validateDocumentationSystemCatalog(catalog, schema, errors) {
  const result = validateSchema(schema, catalog);
  errors.push(...result.errors.map((error) => `documentation-system-catalog: ${error}`));
  if (result.ok) validateDocumentationSystemCatalogSemantics(catalog, errors, "documentation-system-catalog");
}

function validateDocumentationSystemCatalogSemantics(catalog, errors, label) {
  const expected = [...DOCUMENTATION_REPOSITORIES].sort(codepointCompare);
  const actual = catalog.repositories.map(({ repository }) => repository);
  if (!isDeepStrictEqual(actual, expected)) errors.push(`${label}: repositories는 정렬된 5개 정본 저장소와 정확히 일치해야 한다`);
  for (const entry of catalog.repositories) {
    if (entry.status === "PROPOSED" && entry.fragment !== null) {
      errors.push(`${label}: ${entry.repository} PROPOSED fragment는 null이어야 한다`);
    }
    if (entry.status === "ACTIVE" && entry.fragment === null) {
      errors.push(`${label}: ${entry.repository} ACTIVE fragment가 필요하다`);
      continue;
    }
    if (entry.status === "ACTIVE") {
      errors.push(`${label}: ${entry.repository} ACTIVE fragment resolution contract가 필요하다`);
    }
    if (entry.fragment !== null) {
      if (!safeDocumentationPath(entry.fragment.path)) errors.push(`${label}: ${entry.repository} fragment path가 안전하지 않다`);
      if (!isCanonicalUtc(entry.fragment.lastVerifiedAt)) errors.push(`${label}: ${entry.repository} fragment lastVerifiedAt은 canonical UTC여야 한다`);
      validateDocumentationEvidence(entry.fragment.verificationEvidence, `${label}: ${entry.repository} fragment verificationEvidence`, errors);
    }
  }
}

export function validateDocumentationFragment(fragment, fragmentSchema, resourceSchema, errors) {
  const result = validateSchema(fragmentSchema, fragment);
  errors.push(...result.errors.map((error) => `documentation-fragment: ${error}`));
  if (!result.ok) return;
  if (fragment.status === "ACTIVE") {
    if (fragment.verificationEvidence.length === 0) {
      errors.push("documentation-fragment: ACTIVE verificationEvidence가 필요하다");
    }
    if (fragment.lastVerifiedAt === null) {
      errors.push("documentation-fragment: ACTIVE lastVerifiedAt이 필요하다");
    }
  }
  validateDocumentationEvidence(fragment.verificationEvidence, "documentation-fragment: verificationEvidence", errors);
  if (fragment.lastVerifiedAt !== null && !isCanonicalUtc(fragment.lastVerifiedAt)) {
    errors.push("documentation-fragment: lastVerifiedAt은 canonical UTC여야 한다");
  }
  const resourceIds = fragment.resources.map(({ resource }) => resource);
  if (resourceIds.some((resource) => typeof resource !== "string")
      || !isDeepStrictEqual(resourceIds, [...new Set(resourceIds)].sort(codepointCompare))) {
    errors.push("documentation-fragment: resources는 resource ID 기준 sorted-unique여야 한다");
  }
  const validRecords = [];
  for (const record of fragment.resources) {
    const resourceResult = validateSchema(resourceSchema, record);
    errors.push(...resourceResult.errors.map((error) => `documentation-fragment resource: ${error}`));
    if (!resourceResult.ok) continue;
    try {
      validateDocumentationRecord(record, {
        ownerRepository: fragment.repository,
        gitSha: fragment.gitSha,
        tracked: record.sourceSurface === "TRACKED",
      });
      if (record.sourceSurface === "TRACKED") {
        const prefix = `${fragment.repository}:`;
        const identity = /^git:[0-9a-f]{40}:([^:]+):(?:[0-9a-f]{40}|[0-9a-f]{64})$/.exec(record.canonicalIdentity);
        if (!record.resource.startsWith(prefix) || identity?.[1] !== record.resource.slice(prefix.length)) {
          throw new Error("tracked fragment identity mismatch");
        }
      }
      validRecords.push(record);
    } catch (error) {
      errors.push(`documentation-fragment resource: ${error instanceof Error ? error.message : String(error)}`);
    }
  }
  try {
    validateDocumentationFragmentRelations(validRecords);
  } catch (error) {
    errors.push(`documentation-fragment resource: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function validateDocumentationFragmentRelations(records) {
  const byResource = new Map(records.map((record) => [record.resource, record]));
  for (const record of records) {
    if (record.supersededBy === record.resource || record.supersedes.includes(record.resource)
        || (record.status === "SUPERSEDED") !== (record.supersededBy !== null)) {
      throw new Error("fragment lifecycle contradiction");
    }
    if (record.status === "INVALIDATED") {
      const replacement = byResource.get(record.invalidatedBy);
      if (replacement !== undefined && (replacement.resourceClass !== "EVIDENCE"
          || ["INVALIDATED", "REVOKED"].includes(replacement.status)
          || replacement.mutationPolicy !== "EVIDENCE_IMMUTABLE"
          || !replacement.supersedes.includes(record.resource))) {
        throw new Error("fragment relation contradiction");
      }
    }
    if (record.status === "SUPERSEDED") {
      const successor = byResource.get(record.supersededBy);
      if (successor !== undefined && !successor.supersedes.includes(record.resource)) {
        throw new Error("fragment relation contradiction");
      }
    }
    for (const predecessorResource of record.supersedes) {
      const predecessor = byResource.get(predecessorResource);
      if (predecessor !== undefined
          && (predecessor.status === "INVALIDATED" && predecessor.invalidatedBy !== record.resource
            || predecessor.status !== "INVALIDATED"
              && (predecessor.status !== "SUPERSEDED" || predecessor.supersededBy !== record.resource))) {
        throw new Error("fragment relation contradiction");
      }
    }
  }
  for (const start of records) {
    const seen = new Set();
    let current = start;
    while (current !== undefined && current.supersededBy !== null) {
      if (seen.has(current.resource)) throw new Error("fragment supersession cycle");
      seen.add(current.resource);
      current = byResource.get(current.supersededBy);
    }
  }
}

function safeDocumentationPath(value) {
  return typeof value === "string" && value.length > 0
    && !isAbsolute(value) && !win32.isAbsolute(value)
    && !value.split(/[\\/]/).includes("..") && !/[\x00-\x1f\x7f]/.test(value);
}

function validateDocumentationEvidence(values, label, errors) {
  if (!isDeepStrictEqual(values, [...new Set(values)].sort(codepointCompare))) {
    errors.push(`${label}는 sorted-unique여야 한다`);
  }
  if (values.some((value) => !safeDocumentationIdentifier(value))) {
    errors.push(`${label}에 안전한 identity가 필요하다`);
  }
}

function safeDocumentationIdentifier(value) {
  if (typeof value !== "string" || value.length === 0 || value !== value.trim()
      || /[\x00-\x1f\x7f]/.test(value) || isAbsolute(value) || win32.isAbsolute(value)
      || value.split(/[\\/]/).includes("..") || !value.includes(":")) return false;
  if (/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) {
    if (!value.startsWith("https://")) return false;
    try {
      const url = new URL(value);
      return !url.username && !url.password && !url.search && !url.hash;
    } catch {
      return false;
    }
  }
  return !value.includes("?");
}

function isCanonicalUtc(value) {
  if (typeof value !== "string") return false;
  const millis = Date.parse(value);
  return Number.isFinite(millis) && new Date(millis).toISOString() === value;
}

function validateArchitectureDecisionSchema(adr, valuePath, errors) {
  const reference = adr?.decisionSchema;
  if (typeof reference !== "string" || typeof adr?.id !== "string") {
    errors.push(`${valuePath}: decisionSchema는 repository 내부 상대 JSON path여야 한다`);
    return false;
  }
  const expectedReference = `./${adr.id}-decision.schema.json`;
  if (reference !== expectedReference) {
    errors.push(`${valuePath}: decisionSchema는 repository 내부 상대 JSON path ${expectedReference}여야 한다`);
    return false;
  }
  const schemaPath = resolve(dirname(valuePath), reference);
  if (!existsSync(schemaPath)) {
    errors.push(`${valuePath}: decisionSchema ${reference} 누락`);
    return false;
  }
  if (lstatSync(schemaPath).isSymbolicLink()) {
    errors.push(`${valuePath}: decisionSchema symlink는 허용하지 않는다`);
    return false;
  }
  if (dirname(realpathSync(schemaPath)) !== realpathSync(dirname(resolve(valuePath)))) {
    errors.push(`${valuePath}: decisionSchema는 repository 내부 상대 JSON path여야 한다`);
    return false;
  }
  let schema;
  try {
    schema = loadJson(schemaPath);
  } catch {
    errors.push(`${valuePath}: decisionSchema ${reference}: 유효한 JSON이 필요하다`);
    return false;
  }
  if (schema == null || typeof schema !== "object" || Array.isArray(schema)
      || schema.type !== "object" || !Array.isArray(schema.required) || schema.required.length === 0
      || schema.additionalProperties !== false) {
    errors.push(`${valuePath}: decisionSchema ${reference}: 최상위 object, 비어 있지 않은 required, additionalProperties false가 필요하다`);
    return false;
  }
  try {
    const result = validateSchema(schema, adr.decision);
    errors.push(...result.errors.map((error) =>
      `${valuePath}: ${error.replace(/^\$/, "$.decision")}`));
    return result.errors.length === 0;
  } catch (error) {
    errors.push(`${valuePath}: decisionSchema ${reference}: ${error instanceof Error ? error.message : String(error)}`);
    return false;
  }
}

export function validateArchitectureDecision(adr) {
  if (adr == null || typeof adr !== "object" || Array.isArray(adr)) return [];
  const errors = [];
  const repositoryOwners = {
    hub: "AquilaXk/easysubway",
    data: "AquilaXk/easysubway-data",
    backend: "AquilaXk/easysubway-backend",
    mobile: "AquilaXk/easysubway-mobile",
    platform: "AquilaXk/easysubway-platform",
  };
  if (adr.id === "ADR-HUB-0001") {
    for (const [component, repository] of Object.entries(repositoryOwners)) {
      if (adr.decision?.repositoryOwners?.[component] !== repository) {
        errors.push(`${component} repository owner는 ${repository}여야 한다`);
      }
    }
    if (adr.decision?.childIssuePolicy?.firstChildAfter !== "ADR_HUB_0001_MERGED") {
      errors.push("첫 파생 이슈는 ADR-HUB-0001 병합 뒤에만 만들 수 있다");
    }
    if (adr.decision?.sensitiveEvidence?.trackedContentAllowed !== false) {
      errors.push("sensitiveEvidence.trackedContentAllowed는 false여야 한다");
    }
    if (adr.contextIssue !== "https://github.com/AquilaXk/easysubway/issues/2748") {
      errors.push("ADR-HUB-0001 contextIssue는 Hub #2748이어야 한다");
    }
  }
  if ((Array.isArray(adr.supersedes) && adr.supersedes.includes(adr.id)) || adr.supersededBy === adr.id) {
    errors.push("supersession은 자기 자신을 참조할 수 없다");
  }
  if (adr.status === "superseded" && adr.supersededBy == null) {
    errors.push("superseded 상태에는 supersededBy가 필요하다");
  }
  if (adr.status !== "superseded" && adr.supersededBy != null) {
    errors.push("non-superseded 상태의 supersededBy는 null이어야 한다");
  }
  if (Array.isArray(adr.consideredOptions)) {
    const chosenCount = adr.consideredOptions.filter((option) => option?.chosen === true).length;
    if (chosenCount !== 1) errors.push("consideredOptions에는 chosen 옵션이 정확히 하나여야 한다");
    const optionIds = adr.consideredOptions.map((option) => option?.id);
    if (new Set(optionIds).size !== optionIds.length) {
      errors.push("consideredOptions의 id는 유일해야 한다");
    }
  }
  return errors;
}

export function validateArchitectureDecisionTransition(previous, current) {
  if (isDeepStrictEqual(previous, current)) return [];
  if (previous?.status === "proposed" && current?.status !== "proposed") {
    const statusOnly = structuredClone(current);
    statusOnly.status = "proposed";
    if (["accepted", "rejected", "withdrawn"].includes(current?.status)
      && isDeepStrictEqual(previous, statusOnly)) return [];
    return ["proposed ADR의 종결 전환은 status-only여야 한다"];
  }
  const terminalStatuses = new Set(["rejected", "withdrawn", "superseded"]);
  if (terminalStatuses.has(previous?.status)) {
    return ["종결 상태 ADR 본문은 변경할 수 없다"];
  }
  if (previous?.status !== "accepted") return [];
  const allowed = structuredClone(current);
  allowed.status = previous.status;
  allowed.supersededBy = previous.supersededBy;
  if (current?.status === "superseded" && current.supersededBy != null
    && isDeepStrictEqual(previous, allowed)) return [];
  return ["accepted ADR 본문은 in-place 변경할 수 없고 새 ADR로 supersede해야 한다"];
}

function validateArchitectureDecisionChain(schemaPath, rootPath, root, errors, candidatesById) {
  let candidatePaths;
  try {
    candidatePaths = readdirSync(dirname(rootPath))
      .filter((name) => name.endsWith(".json"))
      .map((name) => join(dirname(rootPath), name));
  } catch {
    errors.push(`${rootPath}: successor ADR directory를 읽을 수 없다`);
    return [];
  }
  const malformedPaths = [];
  for (const candidatePath of candidatePaths) {
    const namedAdr = /^ADR-[A-Z0-9-]+\.json$/.test(basename(candidatePath));
    let candidate;
    try {
      candidate = loadJson(candidatePath);
    } catch {
      if (namedAdr) {
        malformedPaths.push(candidatePath);
        errors.push(`${candidatePath}: 유효한 JSON이 필요하다`);
      }
      continue;
    }
    const declaredAdr = candidate?.kind === "architecture-decision"
      || (typeof candidate?.$schema === "string"
        && basename(candidate.$schema) === "architecture-decision.schema.json");
    if (candidatePath !== rootPath && !namedAdr && !declaredAdr && !/^ADR-/.test(candidate?.id)) continue;
    const candidateErrors = [];
    const candidateValid = candidatePath === rootPath
      || validateJson(schemaPath, candidatePath, candidateErrors);
    errors.push(...candidateErrors);
    if (typeof candidate?.id !== "string") continue;
    const candidates = candidatesById.get(candidate.id) ?? [];
    candidates.push([candidatePath, candidate, candidateValid]);
    candidatesById.set(candidate.id, candidates);
  }
  for (const [id, candidates] of candidatesById) {
    if (candidates.length > 1) errors.push(`${rootPath}: current ADR ID 중복 (${id})`);
  }
  for (const candidates of candidatesById.values()) {
    if (candidates.length !== 1 || !candidates[0][2]) continue;
    const startPath = candidates[0][0];
    for (const predecessorId of candidates[0][1].supersedes) {
      const predecessors = candidatesById.get(predecessorId) ?? [];
      if (predecessors.length !== 1 || !predecessors[0][2]
        || predecessors[0][1].status !== "superseded"
        || predecessors[0][1].supersededBy !== candidates[0][1].id) {
        errors.push(`${startPath}: supersedes predecessor reciprocal link가 필요하다`);
      }
    }
    const seen = new Set();
    let currentCandidate = candidates[0];
    while (currentCandidate[1].status === "superseded") {
      const [currentPath, currentAdr] = currentCandidate;
      if (seen.has(currentAdr.id)) {
        errors.push(`${startPath}: supersession cycle을 허용하지 않는다`);
        break;
      }
      seen.add(currentAdr.id);
      const successors = candidatesById.get(currentAdr.supersededBy) ?? [];
      if (successors.length === 0) {
        errors.push(`${currentPath}: successor ADR 누락`);
        break;
      }
      if (successors.length > 1) {
        errors.push(`${currentPath}: successor ADR 중복`);
        break;
      }
      const [successorPath, successor, successorValid] = successors[0];
      if (!successorValid) {
        errors.push(`${successorPath}: successor ADR는 schema와 semantic 검증을 통과해야 한다`);
        break;
      }
      if (!["accepted", "superseded"].includes(successor.status)) {
        errors.push(`${successorPath}: terminal successor ADR는 accepted 상태여야 한다`);
        break;
      }
      if (!successor.supersedes.includes(currentAdr.id)) {
        errors.push(`${successorPath}: supersedes reciprocal link가 필요하다`);
        break;
      }
      currentCandidate = successors[0];
    }
  }
  const members = [];
  const visited = new Set();
  let current = [rootPath, root];
  while (true) {
    const [currentPath, currentAdr] = current;
    if (visited.has(currentAdr.id)) {
      errors.push(`${currentPath}: supersession cycle을 허용하지 않는다`);
      return members;
    }
    visited.add(currentAdr.id);
    members.push({ path: currentPath, adr: currentAdr });
    if (currentAdr.status !== "superseded") return members;
    const successors = candidatesById.get(currentAdr.supersededBy) ?? [];
    if (successors.length === 0) {
      if (malformedPaths.length > 0) {
        errors.push(`${currentPath}: successor ADR 판정에 유효한 JSON이 필요하다`);
      } else {
        errors.push(`${currentPath}: current ADR directory에 successor ADR 누락`);
      }
      return members;
    }
    if (successors.length > 1) {
      errors.push(`${currentPath}: successor ADR 중복`);
      return members;
    }
    const [successorPath, successor, successorValid] = successors[0];
    if (!successorValid) {
      errors.push(`${successorPath}: successor ADR는 schema와 semantic 검증을 통과해야 한다`);
      return members;
    }
    if (!["accepted", "superseded"].includes(successor.status)) {
      errors.push(`${successorPath}: terminal successor ADR는 accepted 상태여야 한다`);
      return members;
    }
    if (!successor.supersedes.includes(currentAdr.id)) {
      errors.push(`${successorPath}: supersedes reciprocal link가 필요하다`);
      return members;
    }
    current = [successorPath, successor];
  }
}

export function validateArchitectureDecisionWorkspaceTransition(previous, current) {
  if (!Object.hasOwn(previous, "architectureDecision")) return [];
  if (previous.architectureDecision !== current.architectureDecision) {
    return ["workspace architectureDecision path redirect는 허용되지 않는다"];
  }
  return [];
}

export function loadArchitectureDecisionAtRef(workspacePath, baseRef) {
  if (!/^[0-9a-f]{40}$/i.test(baseRef)) throw new Error("base-ref는 40자리 Git SHA여야 한다");
  const absoluteWorkspacePath = resolve(workspacePath);
  const workspaceRepositoryPath = relative(process.cwd(), absoluteWorkspacePath);
  if (workspaceRepositoryPath.startsWith("..") || workspaceRepositoryPath === "") {
    throw new Error("base-ref workspace 경로는 repository 내부여야 한다");
  }
  execFileSync("/usr/bin/git", ["rev-parse", "--verify", `${baseRef}^{commit}`], { stdio: "ignore" });
  const loadAtRef = (repositoryPath, required) => {
    const found = execFileSync("/usr/bin/git", ["ls-tree", "--name-only", baseRef, "--", repositoryPath], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (found === "") {
      if (!required) return null;
      throw new Error(`${baseRef}:${repositoryPath} 누락`);
    }
    const raw = execFileSync("/usr/bin/git", ["show", `${baseRef}:${repositoryPath}`], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    try {
      return JSON.parse(raw);
    } catch {
      throw new Error(`${baseRef}:${repositoryPath}: 유효한 JSON이 필요하다`);
    }
  };
  const previousWorkspace = loadAtRef(workspaceRepositoryPath, true);
  const currentWorkspace = loadJson(absoluteWorkspacePath);
  const workspaceErrors = validateArchitectureDecisionWorkspaceTransition(previousWorkspace, currentWorkspace);
  if (workspaceErrors.length > 0) throw new Error(workspaceErrors.join("; "));
  if (!Object.hasOwn(previousWorkspace, "architectureDecision")) return null;
  const repositoryPath = relative(
    "/",
    resolve("/", dirname(workspaceRepositoryPath), previousWorkspace.architectureDecision),
  );
  if (repositoryPath.startsWith("..") || repositoryPath === "") {
    throw new Error("base-ref ADR 경로는 repository 내부여야 한다");
  }
  const root = loadAtRef(repositoryPath, true);
  const directory = dirname(repositoryPath);
  const candidatesById = new Map();
  let hasMalformedCandidate = false;
  const candidatePaths = execFileSync("/usr/bin/git", ["ls-tree", "--name-only", directory === "." ? baseRef : `${baseRef}:${directory}`], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim().split("\n")
    .filter((path) => path.endsWith(".json"))
    .map((path) => join(directory, path));
  for (const candidatePath of candidatePaths) {
    const namedAdr = /^ADR-[A-Z0-9-]+\.json$/.test(basename(candidatePath));
    let candidate;
    try {
      candidate = loadAtRef(candidatePath, true);
    } catch {
      if (namedAdr) hasMalformedCandidate = true;
      continue;
    }
    const declaredAdr = candidate?.kind === "architecture-decision"
      || (typeof candidate?.$schema === "string"
        && basename(candidate.$schema) === "architecture-decision.schema.json");
    if (candidatePath !== repositoryPath && !namedAdr && !declaredAdr && !/^ADR-/.test(candidate?.id)) continue;
    if (typeof candidate?.id !== "string") continue;
    if (typeof candidate.decisionSchema === "string") {
      const expectedReference = `./${candidate.id}-decision.schema.json`;
      if (candidate.decisionSchema !== expectedReference) {
        throw new Error(`${baseRef}:${candidatePath}: decisionSchema는 ${expectedReference}여야 한다`);
      }
      const decisionSchemaPath = relative(
        "/",
        resolve("/", dirname(candidatePath), candidate.decisionSchema),
      );
      if (decisionSchemaPath.startsWith("..") || decisionSchemaPath === "") {
        throw new Error(`${baseRef}:${candidatePath}: decisionSchema 경로는 repository 내부여야 한다`);
      }
      architectureDecisionSchemaSnapshots.set(candidate, loadAtRef(decisionSchemaPath, true));
    }
    const candidates = candidatesById.get(candidate.id) ?? [];
    candidates.push(candidate);
    candidatesById.set(candidate.id, candidates);
  }
  const visited = new Set();
  let current = root;
  while (true) {
    if (visited.has(current.id)) throw new Error(`${baseRef}:${repositoryPath}: supersession cycle을 허용하지 않는다`);
    visited.add(current.id);
    if (current.status !== "superseded") return [...candidatesById.values()].flat();
    const successors = candidatesById.get(current.supersededBy) ?? [];
    if (successors.length === 0) {
      if (hasMalformedCandidate) throw new Error(`${baseRef}:${repositoryPath}: successor ADR 판정에 유효한 JSON이 필요하다`);
      throw new Error(`${baseRef}:${repositoryPath}: current ADR directory에 successor ADR 누락`);
    }
    if (successors.length > 1) throw new Error(`${baseRef}:${repositoryPath}: successor ADR 중복`);
    current = successors[0];
  }
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

export function validateGateIndex(errors, indexPath, gateDirectories) {
  if (!existsSync(indexPath)) {
    errors.push(`${indexPath} 누락`);
    return;
  }
  const index = loadJson(indexPath);
  const ownerComponents = { product: "hub", mobile: "mobile" };
  const files = new Set();
  for (const gate of index.gates ?? []) {
    if (files.has(gate.file)) errors.push(`${indexPath}: ${gate.file} gate.file 중복`);
    files.add(gate.file);
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
  const args = process.argv.slice(2);
  const hasWorkspace = args[0] === "--workspace" && args[1]?.trim() !== "";
  const hasBaseRef = args.length === 4 && args[2] === "--base-ref" && args[3].trim() !== "";
  const isCurrentOnly = args.length === 3 && args[2] === "--current-only";
  const validArgs = hasWorkspace && (hasBaseRef || isCurrentOnly);
  if (!validArgs) {
    console.error("사용법: node tools/ci/check-contracts.mjs --workspace <workspace.json> (--base-ref <40-hex-sha>|--current-only)");
    process.exit(1);
  }
  let previousArchitectureDecision = null;
  try {
    if (hasBaseRef) previousArchitectureDecision = loadArchitectureDecisionAtRef(args[1], args[3]);
  } catch (error) {
    console.error(`- ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  }
  const errors = collectContractErrors(args[1], { previousArchitectureDecision });
  if (errors.length) {
    console.error(errors.map((error) => `- ${error}`).join("\n"));
    process.exit(1);
  }
}
