#!/usr/bin/env node
import { isMainModule } from "../lib/is-main-module.mjs";
import { existsSync, lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { basename, dirname, isAbsolute, join, relative, resolve, win32 } from "node:path";
import { validateSourceGovernancePolicy } from "../datapack/source-governance-policy.mjs";
import { validateAmendments, validateLedger } from "../repo/issue-migration-ledger.mjs";
import { validatePlanDocExecutionScope as validatePlanDocExecutionAuditInventory } from "../repo/audit-plan-doc-execution.mjs";
import { validateSchema } from "./lib/json-schema-lite.mjs";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isDeepStrictEqual } from "node:util";
import {
  DOCUMENTATION_REPOSITORIES,
  validateDocumentationRelations,
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
const PRODUCT_CLAIM_INVENTORY = [
  "PRODUCT_CLAIM_ACCESSIBILITY_PILOT:ACCESSIBILITY_PILOT",
  "PRODUCT_CLAIM_ANONYMOUS_REPORT:ANONYMOUS_REPORT",
  "PRODUCT_CLAIM_JOURNEY_CURRENT:JOURNEY",
  "PRODUCT_CLAIM_JOURNEY_FINAL:JOURNEY",
  "PRODUCT_CLAIM_OFFLINE_MAP_AND_STATION:OFFLINE_MAP_AND_STATION",
  "PRODUCT_CLAIM_PRIVACY:PRIVACY",
  "PRODUCT_CLAIM_PRODUCT_PRINCIPLE:PRODUCT_PRINCIPLE",
  "PRODUCT_CLAIM_PROVENANCE:PROVENANCE",
  "PRODUCT_CLAIM_RELEASE_STATUS:RELEASE_STATUS",
  "PRODUCT_CLAIM_VISION:VISION",
];

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
  const required = ["contracts", "gateDirectories", "datapackIndex", "sourceInventory", "governancePolicy", "freshnessPolicy", "architectureDecision", "documentationSystemCatalog", "productClaimCatalog"];
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
  for (const field of ["contracts", "datapackIndex", "sourceInventory", "governancePolicy", "freshnessPolicy", "architectureDecision", "documentationSystemCatalog", "productClaimCatalog"]) {
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
    productClaimCatalog: resolveWorkspacePath(workspace.productClaimCatalog),
    referenceAuditScope: workspace.referenceAuditScope == null ? null : resolveWorkspacePath(workspace.referenceAuditScope),
    referenceAuditReportSchema: workspace.referenceAuditReportSchema == null ? null : resolveWorkspacePath(workspace.referenceAuditReportSchema),
    publicSensitivityAuditScope: workspace.publicSensitivityAuditScope == null ? null : resolveWorkspacePath(workspace.publicSensitivityAuditScope),
    publicSensitivityOwnerReceiptSchema: workspace.publicSensitivityOwnerReceiptSchema == null ? null : resolveWorkspacePath(workspace.publicSensitivityOwnerReceiptSchema),
    publicSensitivityAuditReportSchema: workspace.publicSensitivityAuditReportSchema == null ? null : resolveWorkspacePath(workspace.publicSensitivityAuditReportSchema),
    planDocExecutionAuditScope: workspace.planDocExecutionAuditScope == null ? null : resolveWorkspacePath(workspace.planDocExecutionAuditScope),
    planDocExecutionAuditReportSchema: workspace.planDocExecutionAuditReportSchema == null ? null : resolveWorkspacePath(workspace.planDocExecutionAuditReportSchema),
  };
}

export function collectContractErrors(
  workspacePath = DEFAULT_WORKSPACE_PATH,
  { previousArchitectureDecision = null, documentationFragmentWorkspacePath = null } = {},
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
    const catalog = loadJson(workspace.documentationSystemCatalog);
    validateDocumentationSystemCatalogSemantics(catalog, errors, workspace.documentationSystemCatalog, false);
    resolveActiveDocumentationFragments(catalog, documentationFragmentWorkspacePath, errors, {
      fragmentSchema: contract("documentation/documentation-fragment.schema.json"),
      resourceSchema: contract("documentation/documentation-resource.schema.json"),
    });
  }
  const productClaimCatalogSchema = contract("documentation/product-claim-catalog.schema.json");
  if (validateJson(productClaimCatalogSchema, workspace.productClaimCatalog, errors)) {
    const releaseDecision = loadProductClaimInput(join(workspace.gateDirectories.hub, "production-datapack-scope.json"), "production-datapack-scope", errors);
    const forbiddenClaims = loadProductClaimInput(join(workspace.gateDirectories.hub, "forbidden-release-claims.json"), "forbidden-release-claims", errors);
    if (releaseDecision != null && forbiddenClaims != null) {
      validateProductClaimCatalog(loadJson(workspace.productClaimCatalog), loadJson(productClaimCatalogSchema), errors, {
        releaseDecision,
        forbiddenClaims,
        publicCopy: readProductClaimReadme(join(repositoryRoot, "README.md"), errors),
      });
    }
  }
  if (workspace.referenceAuditScope != null || workspace.referenceAuditReportSchema != null) {
    if (workspace.referenceAuditScope == null || workspace.referenceAuditReportSchema == null) {
      errors.push("reference audit workspace entries는 함께 필요하다");
    } else {
      const referenceAuditScopeValid = validateJson(contract("documentation/reference-audit-scope.schema.json"), workspace.referenceAuditScope, errors);
      if (referenceAuditScopeValid) validateReferenceAuditScope(loadJson(workspace.referenceAuditScope), errors, workspace.referenceAuditScope);
      if (!existsSync(workspace.referenceAuditReportSchema)) errors.push(`${workspace.referenceAuditReportSchema} 누락`);
      else {
        try { validateReferenceAuditReportSchema(loadJson(workspace.referenceAuditReportSchema), errors, workspace.referenceAuditReportSchema); }
        catch { errors.push(`${workspace.referenceAuditReportSchema}: 유효한 JSON이 필요하다`); }
      }
    }
  }
  const publicSensitivityEntries = [workspace.publicSensitivityAuditScope, workspace.publicSensitivityOwnerReceiptSchema, workspace.publicSensitivityAuditReportSchema];
  if (publicSensitivityEntries.some((entry) => entry != null)) {
    if (publicSensitivityEntries.some((entry) => entry == null)) {
      errors.push("public sensitivity workspace entries는 함께 필요하다");
    } else {
      const scopeValid = validateJson(contract("documentation/public-sensitivity-audit-scope.schema.json"), workspace.publicSensitivityAuditScope, errors);
      if (scopeValid) validatePublicSensitivityAuditScope(loadJson(workspace.publicSensitivityAuditScope), errors, workspace.publicSensitivityAuditScope);
      for (const [label, path] of [["owner receipt", workspace.publicSensitivityOwnerReceiptSchema], ["report", workspace.publicSensitivityAuditReportSchema]]) {
        if (!existsSync(path)) errors.push(`${path} 누락`);
        else {
          try {
            const schema = loadJson(path);
            if (label === "owner receipt") validatePublicSensitivityOwnerReceiptSchema(schema, errors, path);
            else validatePublicSensitivityAuditReportSchema(schema, errors, path);
          } catch { errors.push(`${path}: 유효한 JSON이 필요하다`); }
        }
      }
    }
  }
  const planDocAuditEntries = [workspace.planDocExecutionAuditScope, workspace.planDocExecutionAuditReportSchema];
  if (planDocAuditEntries.some((entry) => entry != null)) {
    if (planDocAuditEntries.some((entry) => entry == null)) errors.push("plan-doc execution audit workspace entries는 함께 필요하다");
    else {
      const scopeValid = validateJson(contract("documentation/plan-doc-execution-audit-scope.schema.json"), workspace.planDocExecutionAuditScope, errors);
      if (scopeValid) validatePlanDocExecutionAuditScope(loadJson(workspace.planDocExecutionAuditScope), errors, workspace.planDocExecutionAuditScope);
      if (!existsSync(workspace.planDocExecutionAuditReportSchema)) errors.push(`${workspace.planDocExecutionAuditReportSchema} 누락`);
      else { try { validatePlanDocExecutionAuditReportSchema(loadJson(workspace.planDocExecutionAuditReportSchema), errors, workspace.planDocExecutionAuditReportSchema); } catch { errors.push(`${workspace.planDocExecutionAuditReportSchema}: 유효한 JSON이 필요하다`); } }
    }
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
  const repositorySplitIssuesPath = join(repositoryRoot, "release/migrations/repository-split-issues.json");
  const repositorySplitIssueLedgerValid = validateJson(
    contract("repository-split-issues.schema.json"),
    repositorySplitIssuesPath,
    errors,
  );
  if (repositorySplitIssueLedgerValid) {
    errors.push(...validateRepositorySplitIssueLedger(loadJson(repositorySplitIssuesPath)).map(
      (error) => `${repositorySplitIssuesPath}: ${error}`,
    ));
  }
  const repositoryContractionInventoryPath = join(repositoryRoot, "release/migrations/repository-contraction-inventory.json");
  const repositoryContractionInventoryValid = validateJson(
    contract("repository-contraction-inventory.schema.json"),
    repositoryContractionInventoryPath,
    errors,
  );
  if (repositoryContractionInventoryValid) {
    errors.push(...validateRepositoryContractionInventory(loadJson(repositoryContractionInventoryPath), repositoryRoot).map(
      (error) => `${repositoryContractionInventoryPath}: ${error}`,
    ));
  }
  const amendmentsPath = join(repositoryRoot, "release/migrations/repository-split-issues-amendments.json");
  const amendmentsValid = validateJson(
    contract("repository-split-issue-amendments.schema.json"),
    amendmentsPath,
    errors,
  );
  if (repositorySplitIssueLedgerValid && amendmentsValid) {
    errors.push(...validateRepositorySplitIssueAmendments(
      loadJson(amendmentsPath),
      loadJson(repositorySplitIssuesPath),
    ).map((error) => `${amendmentsPath}: ${error}`));
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

const REPOSITORY_CONTRACTION_CLASSIFICATIONS = {
  HUB_SYSTEM_OWNER_RETAIN: { targetOwner: null, plannedAction: "RETAIN" },
  HUB_FALLBACK_REMOVE: { targetOwner: null, plannedAction: "REMOVE_FALLBACK" },
  TARGET_CANONICAL_DELETE_AFTER_HANDOFF: { targetOwner: "component", plannedAction: "DELETE_AFTER_HANDOFF" },
  TARGET_FALLBACK_REMOVE: { targetOwner: "component", plannedAction: "REMOVE_FALLBACK" },
  HISTORICAL_ARCHIVE_NONEXECUTABLE: { targetOwner: null, plannedAction: "ARCHIVE_NONEXECUTABLE" },
  DUPLICATE_GATE_DISABLE_AFTER_TARGET: { targetOwner: "component", plannedAction: "DISABLE_AFTER_TARGET" },
};
const KNOWN_FALLBACK_SURFACES = new Map([
  ["backend-ci-build", ["AquilaXk/easysubway", ".github/workflows/ci.yml", "backend build and package jobs"]],
  ["data-ci-producer", ["AquilaXk/easysubway", ".github/workflows/ci.yml", "datapack producer jobs"]],
  ["mobile-ci-build", ["AquilaXk/easysubway", ".github/workflows/ci.yml", "mobile build jobs"]],
  ["platform-ci-deploy", ["AquilaXk/easysubway", ".github/workflows/ci.yml", "platform deployment checks"]],
  ["data-datapack-release", ["AquilaXk/easysubway", ".github/workflows/datapack-release.yml", null]],
  ["mobile-release-artifacts", ["AquilaXk/easysubway", ".github/workflows/release-artifacts.yml", "Android artifact build job"]],
  ["backend-docker-image", ["AquilaXk/easysubway", "Dockerfile", null]],
  ["backend-source", ["AquilaXk/easysubway", "backend", null]],
  ["data-source", ["AquilaXk/easysubway", "tools/datapack", null]],
  ["mobile-source", ["AquilaXk/easysubway", "apps/mobile", null]],
  ["platform-infra", ["AquilaXk/easysubway", "infra", null]],
  ["platform-deploy-tools", ["AquilaXk/easysubway", "tools/deploy", null]],
  ["hub-automerge-queue", ["AquilaXk/easysubway", ".github/workflows/automerge-queue.yml", null]],
  ["backend-raw-main-v1-stage", ["AquilaXk/easysubway", "backend/tools/stage-contracts.mjs", null]],
  ["data-freshness-gate", ["AquilaXk/easysubway", "release/product-gates/datapack-freshness-sla.json", null]],
  ["data-previous-artifact-contract", ["AquilaXk/easysubway", "release/product-gates/rc-evidence-manifest-contract.json", "dataPackFallbackArtifactSha256"]],
  ["hub-release-artifacts-bundled-datapack", ["AquilaXk/easysubway", ".github/workflows/release-artifacts.yml", "missing datapack run uses bundled index and capital artifact"]],
  ["hub-rc-datapack-selector", ["AquilaXk/easysubway", "tools/release/select-rc-datapack-artifact.mjs", "fallback.sqlite.gz selection and copy"]],
  ["hub-manifest-emergency-override", ["AquilaXk/easysubway", "tools/datapack/lib/manifest-validation.mjs", "emergencyOverride fallback pack selection"]],
  ["hub-rc-evidence-fallback-artifact", ["AquilaXk/easysubway", "tools/release/generate-rc-evidence-manifest.mjs", "data-pack fallback artifact requirement"]],
  ["hub-admin-qa-upload-warn", ["AquilaXk/easysubway", ".github/workflows/ci.yml", "Admin QA upload continue-on-error and if-no-files-found warn"]],
  ["backend-realtime-fallback", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/application/service/RouteSearchService.java", "POST_SCAN_REALTIME_FALLBACK_REASON"]],
  ["backend-planner-fallback", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/application/service/RouteSearchService.java", "Legacy graph fallback"]],
  ["backend-stale-fallback", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/application/service/RouteSearchService.java", "STALE_FALLBACK"]],
  ["backend-static-fallback", ["AquilaXk/easysubway-backend", "tools/routes/check-route-commercialization-gate.mjs", "STATIC_BACKEND_ESTIMATE"]],
  ["backend-raw-main-contract", ["AquilaXk/easysubway-backend", "backend/tools/stage-contracts.mjs", "raw.githubusercontent.com/AquilaXk/easysubway/main"]],
  ["data-rollback-fallback", ["AquilaXk/easysubway-data", "tools/datapack/rollback-manifest.mjs", "rollback manifest"]],
  ["mobile-local-fallback", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/features/routes/data/local_route_repository.dart", "offline/local fallback repository"]],
  ["mobile-v1-fallback", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/route_search.dart", "Route V1 fallback"]],
  ["mobile-v2-fallback", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/route_search.dart", "Route V2 fallback"]],
  ["platform-raw-main-fallback", ["AquilaXk/easysubway-platform", "tools/platform/stage-contracts.mjs", "raw.githubusercontent.com/AquilaXk/easysubway/main"]],
  ["platform-legacy-restore-fallback", ["AquilaXk/easysubway-platform", "tools/deploy/deploy-backend.sh", "restore_legacy_backend_service"]],
  ["platform-legacy-credential-fallback", ["AquilaXk/easysubway-platform", "tools/deploy/prepare-deployment-env.sh", "legacy_pepper"]],
  ["backend-topis-fixture-fallback", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/realtime/application/TopisRealtimeProvider.java", "fixtureEnabled fallbackProvider"]],
  ["backend-realtime-overlay-fallback", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/domain/RealtimeEtaOverlay.java", "PLANNED EtaSource.FALLBACK"]],
  ["backend-v2-planner-legacy-graph", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/application/service/RouteV2Planner.java", "legacy graph"]],
  ["backend-route-controller-v1-refresh", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchController.java", "api/v1 LEGACY_STATIC refresh"]],
  ["backend-timetable-seed-last-known-good", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/adapter/out/persistence/TimetableSeedLoader.java", "last-known-good snapshot"]],
  ["backend-jdbc-timetable-break-glass", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/adapter/out/persistence/JdbcRouteTimetableRepository.java", "breakGlass freshness filter"]],
  ["backend-timetable-monitor-break-glass", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/adapter/out/persistence/TimetableFreshnessMonitor.java", "break-glass expired snapshot"]],
  ["backend-transit-master-static-empty", ["AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/transit/adapter/out/persistence/JdbcTransitMasterOverrideRepository.java", "static-seed Optional.empty DataAccess"]],
  ["data-itx-historical-previous", ["AquilaXk/easysubway-data", "tools/datapack/apply-itx-topology-to-bundled-pack.mjs", "UNCHANGED_AUTO previousArtifactPath"]],
  ["data-build-previous-artifact-chain", ["AquilaXk/easysubway-data", "tools/datapack/build-datapack.mjs", "previous artifact chain"]],
  ["data-manifest-emergency-latest-capital", ["AquilaXk/easysubway-data", "tools/datapack/lib/manifest-validation.mjs", "emergencyOverride latest capital"]],
  ["data-coverage-active-default-capital", ["AquilaXk/easysubway-data", "tools/datapack/report-coverage-gaps.mjs", "active default capital"]],
  ["data-release-first-pack", ["AquilaXk/easysubway-data", "tools/ci/datapack-release-workflow.test.mjs", "packs[0]"]],
  ["data-molit-edge-sample", ["AquilaXk/easysubway-data", "tools/datapack/build-molit-nationwide-fixture.mjs", "edge-sample"]],
  ["data-public-api-static-planned", ["AquilaXk/easysubway-data", "tools/datapack/collect-nationwide-public-api-coverage.mjs", "STATIC_LOCAL PLANNED"]],
  ["mobile-dependencies-local-first", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/app/app_dependencies.dart", "LocalFirst flag"]],
  ["mobile-bootstrap-local-route", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/app/app_bootstrap.dart", "LocalRouteRepository"]],
  ["mobile-route-search-refresh", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/route_search.dart", "V1 V2 refresh"]],
  ["mobile-route-v2-transport-scoped", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/route_v2_ingress.dart", "TransportScoped"]],
  ["mobile-internal-route-local", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/features/internal_route/data/local_internal_route_repository.dart", "local internal route"]],
  ["mobile-catalog-known-good-bundled", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/core/database/catalog/catalog_database_opener.dart", "known-good bundled"]],
  ["mobile-pack-update-corrupt-default", ["AquilaXk/easysubway-mobile", "apps/mobile/lib/core/datapack/data_pack_update_state.dart", "corrupted-policy default"]],
  ["platform-ci-raw-main", ["AquilaXk/easysubway-platform", ".github/workflows/ci.yml", "raw.githubusercontent.com/AquilaXk/easysubway/main"]],
  ["platform-contract-lock-raw-main", ["AquilaXk/easysubway-platform", "contracts.lock.json", "raw.githubusercontent.com/AquilaXk/easysubway/main"]],
  ["platform-compose-route-v2-gateway", ["AquilaXk/easysubway-platform", "infra/docker-compose.yml", "route-v2-gateway"]],
]);
const KNOWN_FORBIDDEN_FALLBACK_RESOURCE_IDS = new Set(KNOWN_FALLBACK_SURFACES.keys());
const KNOWN_DUPLICATE_GATE_SURFACES = new Map([
  ["data-datapack-expiry-alert", ["AquilaXk/easysubway", ".github/workflows/datapack-expiry-alert.yml", "scheduled/manual expiry alert jobs and Slack notification"]],
]);

export function validateRepositoryContractionInventory(inventory, repositoryRoot = process.cwd()) {
  const errors = [];
  const resourceIds = new Set();
  const selectorsBySurface = new Map();
  const activeFallbackVerificationIds = new Set();
  validateInventoryBaseHead(inventory, errors, repositoryRoot);
  for (const entry of inventory.entries ?? []) {
    if (resourceIds.has(entry.resourceId)) errors.push(`${entry.resourceId}: resourceId 중복`);
    resourceIds.add(entry.resourceId);
    const requiredSurface = KNOWN_FALLBACK_SURFACES.get(entry.resourceId);
    if (requiredSurface != null && (entry.repository !== requiredSurface[0] || entry.path !== requiredSurface[1] || entry.selector !== requiredSurface[2])) {
      errors.push(`${entry.resourceId}: known fallback exact repository/path/selector 불일치`);
    }
    const duplicateGateSurface = KNOWN_DUPLICATE_GATE_SURFACES.get(entry.resourceId);
    if (duplicateGateSurface != null && (entry.repository !== duplicateGateSurface[0]
        || entry.path !== duplicateGateSurface[1] || entry.selector !== duplicateGateSurface[2])) {
      errors.push(`${entry.resourceId}: known duplicate gate exact repository/path/selector 불일치`);
    }
    const surface = `${entry.repository}\u0000${entry.path}`;
    const selectors = selectorsBySurface.get(surface) ?? [];
    selectors.push(entry.selector);
    selectorsBySurface.set(surface, selectors);

    const rule = REPOSITORY_CONTRACTION_CLASSIFICATIONS[entry.classification];
    if (rule == null) {
      errors.push(`${entry.path}: unknown classification`);
      continue;
    }
    if (entry.hubOwner !== "hub") {
      errors.push(`${entry.resourceId}: hubOwner는 hub여야 한다`);
    }
    if (rule.targetOwner === null && entry.targetOwner !== null) {
      errors.push(`${entry.resourceId}: ${entry.classification} targetOwner는 null이어야 한다`);
    }
    if (rule.targetOwner === "component") {
      const expectedTargetOwner = entry.resourceId.split("-", 1)[0];
      if (entry.targetOwner !== expectedTargetOwner) {
        errors.push(`${entry.resourceId}: targetOwner 불일치`);
      }
    }
    if (entry.repository !== "AquilaXk/easysubway"
        && (!Object.hasOwn(EXTRACTION_REPOSITORIES, entry.targetOwner)
          || entry.repository !== EXTRACTION_REPOSITORIES[entry.targetOwner])) {
      errors.push(`${entry.resourceId}: repository/targetOwner extraction mapping 불일치`);
    }
    if (entry.plannedAction !== rule.plannedAction) {
      errors.push(`${entry.resourceId}: ${entry.classification} plannedAction 불일치`);
    }
    if (duplicateGateSurface != null && (entry.classification !== "DUPLICATE_GATE_DISABLE_AFTER_TARGET"
        || entry.targetOwner !== "data" || entry.plannedAction !== "DISABLE_AFTER_TARGET")) {
      errors.push(`${entry.resourceId}: known duplicate gate classification/target/action 불일치`);
    }
    if (entry.classification === "TARGET_FALLBACK_REMOVE"
        && (entry.repository !== EXTRACTION_REPOSITORIES[entry.targetOwner]
          || entry.fallbackRemovalOwner !== entry.targetOwner
          || entry.fallbackExposure !== "FORBIDDEN_ACTIVE"
          || entry.fallbackVerificationState !== "PLANNED"
          || entry.executionEligibility)) {
      errors.push(`${entry.resourceId}: TARGET_FALLBACK_REMOVE target/removal/fallback state 불일치`);
    }
    if (entry.classification === "HUB_FALLBACK_REMOVE"
        && (entry.repository !== "AquilaXk/easysubway" || entry.targetOwner !== null
          || entry.hubOwner !== "hub" || entry.fallbackRemovalOwner !== "hub"
          || entry.fallbackExposure !== "FORBIDDEN_ACTIVE"
          || entry.fallbackVerificationState !== "PLANNED" || entry.executionEligibility)) {
      errors.push(`${entry.resourceId}: HUB_FALLBACK_REMOVE hub/removal/fallback state 불일치`);
    }
    if (entry.classification === "HUB_SYSTEM_OWNER_RETAIN" && entry.fallbackExposure !== "NONE") {
      errors.push(`${entry.resourceId}: HUB_SYSTEM_OWNER_RETAIN은 fallbackExposure NONE이어야 한다`);
    }
    validateHandoffEvidence(entry, errors);
    if (typeof entry.selector === "string" && entry.selector.trim() === "") {
      errors.push(`${entry.resourceId}: selector는 비어 있을 수 없다`);
    }
    if (rule.targetOwner === "component" && !["PENDING", "VERIFIED"].includes(entry.handoffState)) {
      errors.push(`${entry.resourceId}: target handoffState는 PENDING 또는 VERIFIED여야 한다`);
    }
    if (rule.targetOwner === null && entry.handoffState !== "NOT_APPLICABLE") {
      errors.push(`${entry.resourceId}: Hub retain/historical handoffState는 NOT_APPLICABLE여야 한다`);
    }
    if (["TARGET_CANONICAL_DELETE_AFTER_HANDOFF", "DUPLICATE_GATE_DISABLE_AFTER_TARGET", "TARGET_FALLBACK_REMOVE"].includes(entry.classification)) {
      if (entry.activeConsumers.length === 0) errors.push(`${entry.resourceId}: active consumer가 필요하다`);
      if (entry.handoffEvidence.length === 0) errors.push(`${entry.resourceId}: handoff evidence가 필요하다`);
      if (entry.handoffState === "PENDING" && entry.executionEligibility) {
        errors.push(`${entry.resourceId}: PENDING은 execution-eligible일 수 없다`);
      }
      if (entry.handoffState === "VERIFIED" && entry.handoffEvidence.length === 0) {
        errors.push(`${entry.resourceId}: VERIFIED handoff evidence가 필요하다`);
      }
      if ((entry.handoffState === "VERIFIED" || entry.executionEligibility)
          && !hasTerminalHandoffEvidence(entry.handoffEvidence)) {
        errors.push(`${entry.resourceId}: VERIFIED/execution handoff에는 immutable target, consumer, terminal gate evidence가 필요하다`);
      }
    } else if (entry.executionEligibility) {
      errors.push(`${entry.resourceId}: ${entry.classification}은 execution-eligible일 수 없다`);
    }
    if (entry.classification === "HISTORICAL_ARCHIVE_NONEXECUTABLE") {
      if (entry.releaseReachability !== "NOT_CURRENT") errors.push(`${entry.resourceId}: historical item은 current-reachable일 수 없다`);
      if (entry.activeConsumers.length !== 0) errors.push(`${entry.resourceId}: historical item은 active consumer가 있을 수 없다`);
    }
    validateFallbackExposure(entry, errors, activeFallbackVerificationIds);
  }
  for (const resourceId of KNOWN_FALLBACK_SURFACES.keys()) {
    if (!resourceIds.has(resourceId)) errors.push(`${resourceId}: known fallback required-set 누락`);
  }
  for (const resourceId of KNOWN_DUPLICATE_GATE_SURFACES.keys()) {
    if (!resourceIds.has(resourceId)) errors.push(`${resourceId}: known duplicate gate required-set 누락`);
  }
  for (const [surface, selectors] of selectorsBySurface) {
    if (selectors.length < 2) continue;
    if (selectors.some((selector) => typeof selector !== "string" || selector.trim() === "")) {
      errors.push(`${surface.replace("\u0000", "/")}: mixed path selector가 필요하다`);
      continue;
    }
    if (new Set(selectors).size !== selectors.length) errors.push(`${surface.replace("\u0000", "/")}: mixed path selector 중복`);
  }
  return errors;
}

function validateInventoryBaseHead(inventory, errors, repositoryRoot) {
  try {
    const remote = inventoryGit(repositoryRoot, ["remote", "get-url", "origin"], "utf8").trim();
    if (!remote.includes("AquilaXk/easysubway")) throw new Error("Hub origin이 필요하다");
    inventoryGit(repositoryRoot, ["cat-file", "-e", `${inventory.inventoryBaseHead}^{commit}`]);
    inventoryGit(repositoryRoot, ["merge-base", "--is-ancestor", inventory.inventoryBaseHead, "HEAD"]);
  } catch {
    errors.push(`inventoryBaseHead ${inventory.inventoryBaseHead}: Hub Git base object와 HEAD ancestor가 필요하다`);
  }
}

function validateHandoffEvidence(entry, errors) {
  const evidence = entry.handoffEvidence ?? [];
  const kinds = new Set();
  const expiryAlertEvidenceKinds = new Set(["TARGET_SCHEDULED_GATE", "TARGET_MANUAL_GATE", "TARGET_NOTIFICATION_EVIDENCE"]);
  for (const item of evidence) {
    if (kinds.has(item.kind)) errors.push(`${entry.resourceId}: handoff evidence kind 중복`);
    kinds.add(item.kind);
    if (item.kind === "PLANNED_REFERENCE" && (item.identity !== null || !/^https:\/\/github\.com\/AquilaXk\/easysubway(?:-(?:backend|data|mobile|platform))?\/(?:issues|pull)\/\d+$/.test(item.reference))) {
      errors.push(`${entry.resourceId}: planned handoff reference format 불일치`);
    }
    if (["PLANNED_REFERENCE", "IMMUTABLE_TARGET", "TARGET_CONSUMER"].includes(item.kind) && item.conclusion !== "NOT_APPLICABLE") {
      errors.push(`${entry.resourceId}: non-gate handoff conclusion은 NOT_APPLICABLE여야 한다`);
    }
    if (["TARGET_TERMINAL_GATE", "SYSTEM_TERMINAL_GATE", ...expiryAlertEvidenceKinds].includes(item.kind) && item.conclusion !== "SUCCESS") {
      errors.push(`${entry.resourceId}: terminal gate conclusion은 SUCCESS여야 한다`);
    }
    if (expiryAlertEvidenceKinds.has(item.kind) && entry.resourceId !== "data-datapack-expiry-alert") {
      errors.push(`${entry.resourceId}: expiry alert handoff evidence는 data-datapack-expiry-alert에만 허용된다`);
    }
  }
  if (entry.handoffState !== "VERIFIED" && !entry.executionEligibility) return;
  const immutable = evidence.find((item) => item.kind === "IMMUTABLE_TARGET");
  const consumer = evidence.find((item) => item.kind === "TARGET_CONSUMER");
  const targetTerminal = evidence.find((item) => item.kind === "TARGET_TERMINAL_GATE");
  const systemTerminal = evidence.find((item) => item.kind === "SYSTEM_TERMINAL_GATE");
  const targetRepository = EXTRACTION_REPOSITORIES[entry.targetOwner];
  const immutableRevision = immutable?.identity ?? "";
  if (immutable == null || !/^(?:[a-f0-9]{40}|sha256:[a-f0-9]{64})$/.test(immutableRevision)
      || !isImmutableTargetReference(immutable.reference, targetRepository, immutableRevision)
      || consumer == null || !isTargetConsumerReference(consumer.reference, targetRepository, immutableRevision)
      || consumer.identity !== immutableRevision || targetTerminal == null || systemTerminal == null
      || !isTargetTerminalGateReference(targetTerminal.reference, targetRepository) || targetTerminal.identity !== immutableRevision || targetTerminal.conclusion !== "SUCCESS"
      || !isSystemTerminalGateReference(systemTerminal.reference) || systemTerminal.identity !== immutableRevision || systemTerminal.conclusion !== "SUCCESS"
      || evidence.some((item) => ["PLANNED_REFERENCE", "IMMUTABLE_TARGET", "TARGET_CONSUMER"].includes(item.kind) && item.conclusion !== "NOT_APPLICABLE")) {
    errors.push(`${entry.resourceId}: VERIFIED/execution handoff에는 exact target/system terminal gate evidence가 필요하다`);
  }
  if (entry.resourceId === "data-datapack-expiry-alert") {
    const scheduled = evidence.find((item) => item.kind === "TARGET_SCHEDULED_GATE");
    const manual = evidence.find((item) => item.kind === "TARGET_MANUAL_GATE");
    const notification = evidence.find((item) => item.kind === "TARGET_NOTIFICATION_EVIDENCE");
    const dataRepository = "AquilaXk/easysubway-data";
    const targetRun = new RegExp(`^https://github\\.com/${dataRepository}/actions/runs/\\d+$`);
    const notificationArtifact = new RegExp(`^https://github\\.com/${dataRepository}/actions/runs/\\d+/artifacts/\\d+$`);
    const notificationRun = typeof notification?.reference === "string"
      ? notification.reference.replace(/\/artifacts\/\d+$/, "")
      : "";
    if (scheduled == null || manual == null || notification == null
        || scheduled.identity !== immutableRevision || manual.identity !== immutableRevision || notification.identity !== immutableRevision
        || !targetRun.test(scheduled.reference) || !targetRun.test(manual.reference) || !notificationArtifact.test(notification.reference)
        || scheduled.reference === manual.reference || ![scheduled.reference, manual.reference].includes(notificationRun)
        || scheduled.conclusion !== "SUCCESS" || manual.conclusion !== "SUCCESS" || notification.conclusion !== "SUCCESS") {
      errors.push(`${entry.resourceId}: VERIFIED/execution handoff에는 exact scheduled/manual/notification evidence가 필요하다`);
    }
  }
}

function hasTerminalHandoffEvidence(evidence) {
  const kinds = new Set((evidence ?? []).map((item) => item.kind));
  return kinds.has("IMMUTABLE_TARGET") && kinds.has("TARGET_CONSUMER")
    && kinds.has("TARGET_TERMINAL_GATE") && kinds.has("SYSTEM_TERMINAL_GATE");
}

function isImmutableTargetReference(reference, repository, revision) {
  return repository != null && (reference === `https://github.com/${repository}/commit/${revision}`
    || (revision.startsWith("sha256:") && reference.startsWith(`oci://${repository}@${revision}`)));
}

function isTargetConsumerReference(reference, repository, revision) {
  return repository != null && (revision.startsWith("sha256:")
    ? reference === `oci://${repository}@${revision}`
    : /^[a-f0-9]{40}$/.test(revision)
      && new RegExp(`^https://github\\.com/${repository}/blob/${revision}/[^/]+`).test(reference));
}

function isTargetTerminalGateReference(reference, repository) {
  return repository != null && new RegExp(`^https://github\\.com/${repository}/actions/runs/\\d+$`).test(reference);
}

function isSystemTerminalGateReference(reference) {
  return /^https:\/\/github\.com\/AquilaXk\/easysubway\/actions\/runs\/\d+$/.test(reference);
}

function validateFallbackExposure(entry, errors, activeFallbackVerificationIds) {
  if (KNOWN_FORBIDDEN_FALLBACK_RESOURCE_IDS.has(entry.resourceId)
      && entry.fallbackExposure !== "FORBIDDEN_ACTIVE") {
    errors.push(`${entry.resourceId}: known fallback은 FORBIDDEN_ACTIVE여야 한다`);
  }
  if (entry.fallbackExposure === "NONE") {
    if (entry.fallbackRemovalOwner !== null || entry.fallbackVerification.length !== 0
        || entry.fallbackVerificationState !== "NOT_APPLICABLE"
        || entry.rollbackMode !== "NOT_APPLICABLE" || entry.rollbackRevision !== null
        || entry.rollbackTargetRepository != null || entry.rollbackApprovalEvidence != null || entry.rollbackOperation !== "NOT_APPLICABLE") {
      errors.push(`${entry.resourceId}: NONE fallback metadata 불일치`);
    }
    return;
  }
  if (entry.fallbackExposure === "FORBIDDEN_ACTIVE") {
    const expectedRemovalOwner = entry.targetOwner ?? "hub";
    if (entry.fallbackRemovalOwner !== expectedRemovalOwner) {
      errors.push(`${entry.resourceId}: fallback removal owner가 필요하다`);
    }
    if (entry.fallbackVerificationState !== "PLANNED") errors.push(`${entry.resourceId}: FORBIDDEN_ACTIVE fallback verification은 PLANNED여야 한다`);
    if (entry.fallbackVerification.length === 0) errors.push(`${entry.resourceId}: fallback verification이 필요하다`);
    if (entry.fallbackVerification.some((identifier) => !isFallbackVerificationIdentifier(identifier))) {
      errors.push(`${entry.resourceId}: fallback verification은 executable test/gate identifier여야 한다`);
    }
    for (const identifier of entry.fallbackVerification) {
      if (activeFallbackVerificationIds.has(identifier)) errors.push(`${entry.resourceId}: active fallback verification identifier 중복`);
      activeFallbackVerificationIds.add(identifier);
    }
    if (entry.handoffState === "VERIFIED") errors.push(`${entry.resourceId}: FORBIDDEN_ACTIVE은 handoff VERIFIED일 수 없다`);
    if (entry.executionEligibility) errors.push(`${entry.resourceId}: FORBIDDEN_ACTIVE은 execution-eligible일 수 없다`);
    if (entry.rollbackMode !== "NOT_APPLICABLE" || entry.rollbackRevision !== null
        || entry.rollbackTargetRepository != null || entry.rollbackApprovalEvidence != null || entry.rollbackOperation !== "NOT_APPLICABLE") {
      errors.push(`${entry.resourceId}: FORBIDDEN_ACTIVE rollback metadata 불일치`);
    }
    return;
  }
  const approval = entry.rollbackApprovalEvidence;
  const deploymentRollback = entry.resourceId === "platform-approved-deployment-rollback"
    && entry.kind === "DEPLOYMENT" && entry.targetOwner === "platform"
    && entry.repository === "AquilaXk/easysubway-platform"
    && entry.rollbackTargetRepository === "AquilaXk/easysubway-platform"
    && entry.path === ".github/workflows/deploy.yml" && entry.selector === "PLATFORM_ATOMIC_TRAFFIC_ACTIVATION"
    && hasVerifiedPlatformDeploymentHandoff(entry)
    && /^[a-f0-9]{40}$/.test(entry.rollbackRevision ?? "")
    && approval != null && approval.decision === "APPROVED" && approval.revision === entry.rollbackRevision
    && approval.operation === "MANUAL_DEPLOYMENT" && approval.deploymentClass === "PLATFORM_ATOMIC_TRAFFIC_ACTIVATION"
    && /^https:\/\/github\.com\/AquilaXk\/easysubway-platform\/(?:issues|pull)\/\d+$/.test(approval.reference)
    && entry.rollbackOperation === "MANUAL_DEPLOYMENT";
  if (entry.fallbackRemovalOwner !== null || entry.fallbackVerificationState !== "VERIFIED" || entry.fallbackVerification.length === 0
      || entry.fallbackVerification.some((identifier) => !isFallbackVerificationIdentifier(identifier))
      || entry.rollbackMode !== "EXACT_IMMUTABLE_DEPLOYMENT_ONLY"
      || !/^[a-f0-9]{40}$/.test(entry.rollbackRevision ?? "")
      || !deploymentRollback) {
    errors.push(`${entry.resourceId}: VERIFIED_ROLLBACK_ONLY는 Platform deployment rollback approval의 exact revision, manual operation, atomic traffic activation이어야 한다`);
  }
}

function hasVerifiedPlatformDeploymentHandoff(entry) {
  const evidence = entry.handoffEvidence ?? [];
  const immutable = evidence.find((item) => item.kind === "IMMUTABLE_TARGET");
  const consumer = evidence.find((item) => item.kind === "TARGET_CONSUMER");
  const targetTerminal = evidence.find((item) => item.kind === "TARGET_TERMINAL_GATE");
  const systemTerminal = evidence.find((item) => item.kind === "SYSTEM_TERMINAL_GATE");
  const revision = immutable?.identity ?? "";
  return entry.handoffState === "VERIFIED" && /^[a-f0-9]{40}$/.test(revision)
    && isImmutableTargetReference(immutable?.reference, "AquilaXk/easysubway-platform", revision)
    && consumer?.identity === revision
    && isTargetConsumerReference(consumer?.reference, "AquilaXk/easysubway-platform", revision)
    && targetTerminal?.identity === revision && targetTerminal.conclusion === "SUCCESS"
    && isTargetTerminalGateReference(targetTerminal?.reference, "AquilaXk/easysubway-platform")
    && systemTerminal?.identity === revision && systemTerminal.conclusion === "SUCCESS"
    && isSystemTerminalGateReference(systemTerminal?.reference);
}

function isFallbackVerificationIdentifier(value) {
  return /^(?:[A-Z][A-Z0-9_.-]*|[a-z0-9][a-z0-9/_.-]*(?::[A-Za-z0-9_.-]+)?)$/.test(value);
}

export function validateRepositorySplitIssueAmendments(amendments, ledger) {
  return validateAmendments(amendments, { ledger });
}

export function validateReferenceAuditScope(scope, errors = [], path = "reference-audit-scope") {
  const expected = [
    "AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform",
  ];
  const repositories = scope?.repositories;
  const actual = Array.isArray(repositories) ? repositories.map((entry) => entry?.repository) : [];
  if (scope?.schemaVersion !== 2) errors.push(`${path}: schemaVersion은 2여야 한다`);
  if (JSON.stringify(scope?.contentClassification?.knownBinaryExtensions) !== JSON.stringify([".gz", ".png"])
    || JSON.stringify(scope?.contentClassification?.bareReferenceExtensions) !== JSON.stringify([".json", ".md", ".yaml", ".yml"])) {
    errors.push(`${path}: contentClassification extension inventory는 exact여야 한다`);
  }
  if (JSON.stringify(actual) !== JSON.stringify(expected)) errors.push(`${path}: repository inventory는 exact codepoint sorted 5개여야 한다`);
  for (const entry of Array.isArray(repositories) ? repositories : []) {
    for (const root of entry?.trackedDiscoveryRoots ?? []) {
      if (typeof root !== "string" || root === "" || root.startsWith("/") || root.startsWith("./") || root.includes("\\") || root.split("/").includes("..")) {
        errors.push(`${path}: ${entry?.repository} discovery root는 안전한 repository-relative path여야 한다`);
      }
    }
  }
  return errors;
}

export function validateReferenceAuditReportSchema(schema, errors = [], path = "reference-audit-report.schema") {
  const report = schema?.properties;
  const inputs = report?.inputs?.properties;
  const finding = report?.findings?.items;
  if (schema?.type !== "object" || schema?.additionalProperties !== false || !Array.isArray(schema?.required)) errors.push(`${path}: strict report object schema가 필요하다`);
  if (report?.schemaVersion?.const !== 2) errors.push(`${path}: schemaVersion 2 contract가 필요하다`);
  if (!Array.isArray(report?.observedAt?.type) && report?.observedAt?.format !== "date-time") errors.push(`${path}: observedAt canonical timestamp contract가 필요하다`);
  if (!Array.isArray(report?.inputs?.required) || !report.inputs.required.includes("sourceSha") || (inputs?.sourceSha?.pattern !== "^[0-9a-f]{40}$" && inputs?.sourceSha?.$ref !== "#/$defs/sha")) errors.push(`${path}: sourceSha input identity가 필요하다`);
  if (finding?.additionalProperties !== false || !["code", "referenceClass", "source", "target", "reason"].every((key) => finding?.required?.includes(key))) errors.push(`${path}: strict finding shape가 필요하다`);
  if (JSON.stringify(finding?.properties?.referenceClass?.enum) !== JSON.stringify(["ARTIFACT_IMMUTABLE_REFERENCE", "EXTERNAL_INPUT_PENDING_REFERENCE", "ISSUE_CURRENT_OWNER", "ISSUE_NONCLOSING_DEPENDENCY", "ISSUE_PARENT_OR_COORDINATOR", "ISSUE_TERMINAL_IMPLEMENTATION", "PATH_CANONICAL_CURRENT", "PATH_HISTORICAL_OR_SUPERSEDED", "PR_EVIDENCE_ONLY", "PR_IMPLEMENTATION"])) errors.push(`${path}: referenceClass exact enum schema가 필요하다`);
  for (const field of ["source", "target"]) {
    const property = finding?.properties?.[field];
    const variants = property?.oneOf;
    if (property?.$ref !== `#/$defs/${field}` && (!Array.isArray(variants) || variants.length < 2 || variants.some((variant) => variant.type !== "object" || variant.additionalProperties !== false))) errors.push(`${path}: ${field} strict object schema가 필요하다`);
  }
  for (const field of ["referenced", "latestEffective"]) {
    const branches = finding?.properties?.[field]?.oneOf;
    if (!Array.isArray(branches) || !branches.some((branch) => branch.type === "null")
      || !branches.some((branch) => branch.type === "object" && branch.additionalProperties === false)) errors.push(`${path}: ${field} strict nullable object schema가 필요하다`);
  }
  const expectedOwners = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform", null];
  if (JSON.stringify(finding?.properties?.directOwner?.enum) !== JSON.stringify(expectedOwners)) errors.push(`${path}: directOwner enum schema가 필요하다`);
  if (JSON.stringify(finding?.properties?.consumerRoute?.enum) !== JSON.stringify(["PLAN-DOC", "PLAN-REPO", "PLAN-JOURNEY", null])) errors.push(`${path}: consumerRoute enum schema가 필요하다`);
  const selected = inputs?.repositories?.items?.properties?.selected?.items;
  if (!Array.isArray(selected?.required) || !selected.required.includes("contentClass")
    || JSON.stringify(selected?.properties?.contentClass?.enum) !== JSON.stringify(["AUDITABLE_TEXT", "NON_REFERENCE_BINARY"])) errors.push(`${path}: selected contentClass schema가 필요하다`);
  return errors;
}

export function validatePublicSensitivityAuditScope(scope, errors = [], path = "public-sensitivity-audit-scope") {
  const repositories = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
  const surfaces = ["REPOSITORY_SECURITY_RECEIPT", "ISSUE_TITLE", "ISSUE_BODY", "ISSUE_COMMENT", "PR_TITLE", "PR_BODY", "PR_COMMENT", "PR_REVIEW_BODY", "PR_REVIEW_COMMENT", "COMMIT_COMMENT", "RELEASE_METADATA", "PUBLIC_ARTIFACT"];
  const detectors = ["PRIVATE_KEY_BLOCK", "KNOWN_TOKEN_FORMAT", "AUTHORIZATION_VALUE", "SIGNED_URL_QUERY", "PRIVATE_ABSOLUTE_PATH", "RAW_PROVIDER_PAYLOAD", "RAW_USER_PAYLOAD"];
  if (scope?.schemaVersion !== 1) errors.push(`${path}: schemaVersion은 1이어야 한다`);
  if (JSON.stringify(scope?.repositories?.map(({ repository }) => repository)) !== JSON.stringify(repositories)) errors.push(`${path}: repository inventory는 exact codepoint sorted 5개여야 한다`);
  if (JSON.stringify(scope?.surfaces) !== JSON.stringify(surfaces)) errors.push(`${path}: surface inventory는 exact여야 한다`);
  if (JSON.stringify(scope?.detectors) !== JSON.stringify(detectors)) errors.push(`${path}: detector inventory는 exact여야 한다`);
  const expectedDispositionKeys = JSON.stringify(["detectorId", "expiresAt", "locationFingerprint", "owner", "reason", "verifiedAt"]);
  let previous = "";
  for (const disposition of scope?.falsePositiveDispositions ?? []) {
    if (JSON.stringify(Object.keys(disposition ?? {}).sort()) !== expectedDispositionKeys) errors.push(`${path}: falsePositiveDisposition shape는 exact여야 한다`);
    const identity = `${disposition?.locationFingerprint}\u0000${disposition?.detectorId}`;
    if (identity <= previous) errors.push(`${path}: falsePositiveDisposition은 codepoint sorted-unique여야 한다`);
    previous = identity;
    const verifiedAt = Date.parse(disposition?.verifiedAt); const expiresAt = Date.parse(disposition?.expiresAt);
    if (!Number.isFinite(verifiedAt) || !Number.isFinite(expiresAt) || verifiedAt >= expiresAt) errors.push(`${path}: falsePositiveDisposition current revalidation/expiry가 필요하다`);
  }
  return errors;
}

export function validatePublicSensitivityOwnerReceiptSchema(schema, errors = [], path = "public-sensitivity-owner-receipt.schema") {
  const required = ["schemaVersion", "repository", "gitSha", "observedAt", "secretScanningEnabled", "pushProtectionEnabled", "reachableRefAuditComplete", "alertEnumerationComplete", "locationEnumerationComplete", "openAlertCount", "unresolvedAlertCount", "detectorPolicyVersion", "evidenceLocator", "publicArtifactEnumerationComplete", "publicArtifacts"];
  if (schema?.type !== "object" || schema?.additionalProperties !== false || JSON.stringify(schema?.required) !== JSON.stringify(required)) errors.push(`${path}: strict owner receipt top-level schema가 필요하다`);
  const artifact = schema?.properties?.publicArtifacts?.items;
  const artifactRequired = ["artifactId", "artifactName", "workflowPath", "runId", "archiveDigest", "createdAt", "expiresAt", "detectorPolicyVersion", "scanStatus", "scanReceiptLocator"];
  if (artifact?.additionalProperties !== false || JSON.stringify(artifact?.required) !== JSON.stringify(artifactRequired) || JSON.stringify(artifact?.properties?.scanStatus?.enum) !== JSON.stringify(["COMPLETE", "AUDIT_INCOMPLETE"])) errors.push(`${path}: corrected publicArtifacts exact schema가 필요하다`);
  if (schema?.properties?.openAlertCount?.type !== "integer" || schema?.properties?.unresolvedAlertCount?.type !== "integer" || schema?.properties?.publicArtifacts?.uniqueItems !== true) errors.push(`${path}: receipt count와 artifact uniqueness 계약이 필요하다`);
  if (artifact?.properties?.artifactId?.pattern !== "^[0-9]+$" || artifact?.properties?.runId?.pattern !== "^[0-9]+$" || artifact?.properties?.createdAt?.format !== "date-time" || !artifact?.properties?.workflowPath?.pattern?.includes("github/workflows") || !artifact?.properties?.scanReceiptLocator?.pattern?.includes("actions/runs")) errors.push(`${path}: artifact identity/locator closed grammar가 필요하다`);
  return errors;
}

export function validatePublicSensitivityAuditReportSchema(schema, errors = [], path = "public-sensitivity-audit-report.schema") {
  const repositories = ["AquilaXk/easysubway", "AquilaXk/easysubway-backend", "AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile", "AquilaXk/easysubway-platform"];
  const surfaces = ["REPOSITORY_SECURITY_RECEIPT", "ISSUE_TITLE", "ISSUE_BODY", "ISSUE_COMMENT", "PR_TITLE", "PR_BODY", "PR_COMMENT", "PR_REVIEW_BODY", "PR_REVIEW_COMMENT", "COMMIT_COMMENT", "RELEASE_METADATA", "PUBLIC_ARTIFACT"];
  const detectors = ["PRIVATE_KEY_BLOCK", "KNOWN_TOKEN_FORMAT", "AUTHORIZATION_VALUE", "SIGNED_URL_QUERY", "PRIVATE_ABSOLUTE_PATH", "RAW_PROVIDER_PAYLOAD", "RAW_USER_PAYLOAD"];
  const report = schema?.properties;
  const required = ["schemaVersion", "status", "observedAt", "inputs", "summary", "findings", "incomplete"];
  if (schema?.type !== "object" || schema?.additionalProperties !== false || JSON.stringify(schema?.required) !== JSON.stringify(required)) errors.push(`${path}: strict public sensitivity report schema가 필요하다`);
  if (report?.schemaVersion?.const !== 1 || JSON.stringify(report?.status?.enum) !== JSON.stringify(["COMPLETE", "AUDIT_INCOMPLETE"])) errors.push(`${path}: report status contract가 필요하다`);
  const finding = report?.findings?.items;
  if (finding?.additionalProperties !== false || JSON.stringify(finding?.required) !== JSON.stringify(["code", "detectorId", "repository", "surface", "immutableSourceIdentity", "locationFingerprint"]) || finding?.properties?.code?.const !== "SENSITIVE_RAW_EVIDENCE") errors.push(`${path}: sanitized finding schema가 필요하다`);
  const incomplete = report?.incomplete?.items;
  if (incomplete?.additionalProperties !== false || JSON.stringify(incomplete?.required) !== JSON.stringify(["stage", "code", "affectedIdentity"])) errors.push(`${path}: incomplete shape가 필요하다`);
  const repositoryList = report?.inputs?.properties?.repositories;
  if (repositoryList?.minItems !== 5 || repositoryList?.maxItems !== 5 || repositoryList?.uniqueItems !== true || JSON.stringify(repositoryList?.items?.properties?.repository?.enum) !== JSON.stringify(repositories)) errors.push(`${path}: exact five repository schema가 필요하다`);
  if (report?.findings?.uniqueItems !== true || report?.incomplete?.uniqueItems !== true || JSON.stringify(finding?.properties?.detectorId?.enum) !== JSON.stringify(detectors) || JSON.stringify(finding?.properties?.repository?.enum) !== JSON.stringify(repositories) || JSON.stringify(finding?.properties?.surface?.enum) !== JSON.stringify(surfaces)) errors.push(`${path}: finding enum/uniqueness schema가 필요하다`);
  if (!["scannedSurfaces", "scannedArtifacts", "detectors", "findings", "incomplete"].every((key) => report?.summary?.properties?.[key]?.type === "integer")) errors.push(`${path}: integer summary schema가 필요하다`);
  const parity = schema?.oneOf;
  if (!Array.isArray(parity) || parity.length !== 2 || parity[0]?.properties?.status?.const !== "COMPLETE" || parity[0]?.properties?.incomplete?.maxItems !== 0 || parity[1]?.properties?.status?.const !== "AUDIT_INCOMPLETE" || parity[1]?.properties?.incomplete?.minItems !== 1) errors.push(`${path}: status/incomplete oneOf parity가 필요하다`);
  const inputRequired = repositoryList?.items?.required;
  if (!Array.isArray(inputRequired) || !inputRequired.includes("artifactBeginWatermark") || !inputRequired.includes("artifactEndWatermark") || repositoryList?.items?.properties?.artifactBeginWatermark?.pattern !== "^[0-9a-f]{64}$" || repositoryList?.items?.properties?.artifactEndWatermark?.pattern !== "^[0-9a-f]{64}$") errors.push(`${path}: artifact snapshot watermark input이 필요하다`);
  return errors;
}

export function validatePlanDocExecutionAuditScope(scope, errors = [], path = "plan-doc-execution-audit-scope") {
  if (scope?.schemaVersion !== 1 || scope?.executionRepository !== "AquilaXk/easysubway" || scope?.planOwner !== "PLAN-DOC" || scope?.self?.issueNumber !== 2797 || scope?.self?.planOwner !== "PLAN-DOC") errors.push(`${path}: exact PLAN-DOC self binding이 필요하다`);
  if (JSON.stringify(scope?.forbiddenTargetPathPrefixes) !== JSON.stringify(["apps/mobile/", "backend/", "infra/", "tools/datapack/", "tools/ops/", "tools/release/"])) errors.push(`${path}: target path deny inventory는 exact여야 한다`);
  const records = scope?.historical;
  if (!Array.isArray(records) || records.length !== 16 || new Set(records.map(({ prNumber }) => prNumber)).size !== 16 || new Set(records.map(({ mergeSha }) => mergeSha)).size !== 16 || records.some((record) => record?.planOwner !== "PLAN-DOC" || record?.changedPathClass !== "HUB_GOVERNANCE_ONLY")) errors.push(`${path}: exact historical PLAN-DOC inventory가 필요하다`);
  errors.push(...validatePlanDocExecutionAuditInventory(scope).map((error) => `${path}: ${error}`));
  return errors;
}

export function validatePlanDocExecutionAuditReportSchema(schema, errors = [], path = "plan-doc-execution-audit-report.schema") {
  const report = schema?.properties;
  const record = report?.records?.items;
  const finding = report?.findings?.items;
  const incomplete = report?.incomplete?.items;
  if (schema?.type !== "object" || schema?.additionalProperties !== false || JSON.stringify(schema?.required) !== JSON.stringify(["schemaVersion", "status", "observedAt", "inputs", "summary", "records", "findings", "incomplete"])) errors.push(`${path}: strict report schema가 필요하다`);
  if (report?.schemaVersion?.const !== 1 || JSON.stringify(report?.status?.enum) !== JSON.stringify(["COMPLETE", "AUDIT_INCOMPLETE"]) || report?.inputs?.properties?.sourceSha?.pattern !== "^[0-9a-f]{40}$" || report?.inputs?.properties?.executionRepository?.const !== "AquilaXk/easysubway") errors.push(`${path}: source/repository status contract가 필요하다`);
  if (record?.additionalProperties !== false || finding?.additionalProperties !== false || incomplete?.additionalProperties !== false || report?.findings?.uniqueItems !== true || report?.incomplete?.uniqueItems !== true) errors.push(`${path}: strict finding/incomplete records가 필요하다`);
  if (JSON.stringify(record?.required) !== JSON.stringify(["kind", "issueNumber", "prNumber", "repository", "mergeSha", "changedFiles"]) || JSON.stringify(finding?.required) !== JSON.stringify(["code", "identity"]) || JSON.stringify(incomplete?.required) !== JSON.stringify(["stage", "code", "affectedIdentity"])) errors.push(`${path}: records/findings/incomplete exact required lists가 필요하다`);
  const parity = schema?.oneOf;
  if (!Array.isArray(parity) || parity.length !== 2 || parity[0]?.properties?.status?.const !== "COMPLETE" || parity[0]?.properties?.incomplete?.maxItems !== 0 || parity[1]?.properties?.status?.const !== "AUDIT_INCOMPLETE" || parity[1]?.properties?.incomplete?.minItems !== 1) errors.push(`${path}: incomplete fail-closed parity가 필요하다`);
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

export function validateDocumentationSystemCatalog(catalog, schema, errors, { requireActiveResolution = true } = {}) {
  const result = validateSchema(schema, catalog);
  errors.push(...result.errors.map((error) => `documentation-system-catalog: ${error}`));
  if (result.ok) validateDocumentationSystemCatalogSemantics(catalog, errors, "documentation-system-catalog", requireActiveResolution);
}

export function validateProductClaimCatalog(catalog, schema, errors, { releaseDecision, forbiddenClaims, publicCopy = null }) {
  const result = validateSchema(schema, catalog);
  errors.push(...result.errors.map((error) => `product-claim-catalog: ${error}`));
  if (!result.ok) return;
  validateProductClaimReleaseAndPublicCopy(catalog, releaseDecision, forbiddenClaims, errors);
  validateProductClaimInventory(catalog, errors);
  validateProductClaimDecisionTokens(catalog, releaseDecision, publicCopy, errors);
  validateProductClaimSemantics(catalog.claims, errors);
}

function validateProductClaimReleaseAndPublicCopy(catalog, releaseDecision, forbiddenClaims, errors) {
  if (catalog.releaseDecision !== releaseDecision?.decision?.currentLaunchDecision) {
    errors.push("product-claim-catalog: releaseDecision은 releaseDecisionSource의 currentLaunchDecision과 일치해야 한다");
  }
  if (catalog.publicCopyPolicy !== "release/product-gates/forbidden-release-claims.json") {
    errors.push("product-claim-catalog: publicCopyPolicy source가 일치해야 한다");
  }
  if (!Array.isArray(forbiddenClaims?.scanTargets) || !forbiddenClaims.scanTargets.some((target) => target?.path === "README.md")) {
    errors.push("product-claim-catalog: publicCopyPolicy의 README.md scan target이 필요하다");
  }
}

function validateProductClaimInventory(catalog, errors) {
  const claimIds = catalog.claims.map(({ claimId }) => claimId);
  if (!isSortedUnique(claimIds)) errors.push("product-claim-catalog: claimId는 codepoint sorted-unique여야 한다");
  const claimInventory = catalog.claims.map(({ claimId, topic }) => `${claimId}:${topic}`);
  if (!isDeepStrictEqual(claimInventory, PRODUCT_CLAIM_INVENTORY)) {
    errors.push("product-claim-catalog: required claim inventory가 정확히 일치해야 한다");
  }
}

function validateProductClaimDecisionTokens(catalog, releaseDecision, publicCopy, errors) {
  const releaseStatusClaim = catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_RELEASE_STATUS");
  const decision = releaseDecision?.decision?.currentLaunchDecision;
  if (releaseStatusClaim != null) validateReleaseDecisionToken("release-status claim", releaseStatusClaim.copyKo, decision, errors);
  if (publicCopy != null) validateReleaseDecisionToken("README.md", publicCopy, decision, errors);
}

function validateProductClaimSemantics(claims, errors) {
  for (const claim of claims) {
    for (const field of ["surface", "requiredEvidence", "forbiddenWhen", "reviewTrigger"]) {
      if (!isSortedUnique(claim[field])) errors.push(`product-claim-catalog: ${claim.claimId} ${field}는 codepoint sorted-unique여야 한다`);
    }
    const currentPublic = claim.surface.length > 0;
    if (currentPublic && !["CURRENTLY_IMPLEMENTED_AND_EVIDENCED", "CURRENT_EXTERNAL_OR_DATA_BLOCKER"].includes(claim.assertionState)) {
      errors.push(`product-claim-catalog: ${claim.claimId} current public claim assertionState가 유효하지 않다`);
    }
    if (claim.assertionState === "CURRENTLY_IMPLEMENTED_AND_EVIDENCED" && claim.requiredEvidence.length === 0) {
      errors.push(`product-claim-catalog: ${claim.claimId} requiredEvidence가 필요하다`);
    }
    if (claim.assertionState === "REQUIRED_FINAL_PRODUCTION_BEHAVIOR" && currentPublic) {
      errors.push(`product-claim-catalog: ${claim.claimId} required-final claim은 current surface를 가질 수 없다`);
    }
  }
}

function readProductClaimReadme(path, errors) {
  try {
    return readFileSync(path, "utf8");
  } catch {
    errors.push("product-claim-catalog: README.md public surface를 읽을 수 없다");
    return null;
  }
}

function loadProductClaimInput(path, label, errors) {
  try {
    const value = loadJson(path);
    if (value == null || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value;
  } catch {
    errors.push(`product-claim-catalog: ${label} input이 유효한 JSON object여야 한다`);
    return null;
  }
}

function validateReleaseDecisionToken(surface, copy, decision, errors) {
  const tokens = [...copy.matchAll(/(?:^|[^A-Z0-9_])(NO_GO|GO)(?=$|[^A-Z0-9_])/g)].map(([, token]) => token);
  if (tokens.length !== 1 || tokens[0] !== decision) {
    errors.push(`product-claim-catalog: ${surface} decision token은 currentLaunchDecision과 정확히 하나 일치해야 한다`);
  }
}

function isSortedUnique(values) {
  return Array.isArray(values) && values.every((value, index) => index === 0 || codepointCompare(values[index - 1], value) < 0);
}

function validateDocumentationSystemCatalogSemantics(catalog, errors, label, requireActiveResolution = true) {
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
    if (entry.status === "ACTIVE" && requireActiveResolution) {
      errors.push(`${label}: ${entry.repository} ACTIVE fragment resolution contract가 필요하다`);
    }
    if (entry.fragment !== null) {
      if (!safeDocumentationPath(entry.fragment.path)) errors.push(`${label}: ${entry.repository} fragment path가 안전하지 않다`);
      if (!isCanonicalUtc(entry.fragment.lastVerifiedAt)) errors.push(`${label}: ${entry.repository} fragment lastVerifiedAt은 canonical UTC여야 한다`);
      validateDocumentationEvidence(entry.fragment.verificationEvidence, `${label}: ${entry.repository} fragment verificationEvidence`, errors);
    }
  }
}

const DOCUMENTATION_GIT_ENV = Object.freeze({
  GIT_NO_REPLACE_OBJECTS: "1",
  GIT_GRAFT_FILE: "/dev/null",
  GIT_NO_LAZY_FETCH: "1",
  GIT_TERMINAL_PROMPT: "0",
  GIT_LITERAL_PATHSPECS: "1",
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_SYSTEM: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_ATTR_NOSYSTEM: "1",
});
const DOCUMENTATION_GIT_UNSET = Object.freeze(["GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_NAMESPACE", "GIT_SHALLOW_FILE", "GIT_QUARANTINE_PATH", "GIT_CEILING_DIRECTORIES", "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS"]);
const DOCUMENTATION_GIT_MAX_BUFFER = 64 * 1024 * 1024;
const DOCUMENTATION_FRAGMENT_MAX_BYTES = 1024 * 1024;
const DOCUMENTATION_MAX_ARRAY_ITEMS = 256;
const DOCUMENTATION_MAX_RESOURCES = 256;

function documentationGit(root, args, encoding = "buffer") {
  const env = { ...process.env, ...DOCUMENTATION_GIT_ENV };
  for (const key of DOCUMENTATION_GIT_UNSET) delete env[key];
  return execFileSync("/usr/bin/git", ["-C", root, ...args], {
    encoding,
    env, maxBuffer: DOCUMENTATION_GIT_MAX_BUFFER,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function inventoryGit(repositoryRoot, args, encoding = "buffer") {
  const env = { ...process.env, ...DOCUMENTATION_GIT_ENV };
  for (const key of DOCUMENTATION_GIT_UNSET) delete env[key];
  return execFileSync("/usr/bin/git", ["-C", repositoryRoot, ...args], { encoding, env, stdio: ["ignore", "pipe", "pipe"] });
}

function documentationTransportError(errors, message) {
  errors.push(`documentation fragment transport: ${message}`);
}

function loadDocumentationFragmentWorkspace(path, activeRepositories, errors) {
  if (path == null) {
    documentationTransportError(errors, "ACTIVE fragment workspace가 필요하다");
    return null;
  }
  let workspace;
  try { workspace = loadJson(path); } catch {
    documentationTransportError(errors, "유효한 local workspace JSON이 필요하다");
    return null;
  }
  if (workspace == null || typeof workspace !== "object" || Array.isArray(workspace)
      || workspace.schemaVersion !== 1 || !Array.isArray(workspace.repositories)
      || Object.keys(workspace).length !== 2) {
    documentationTransportError(errors, "local workspace shape가 유효하지 않다");
    return null;
  }
  const mappings = new Map();
  for (const item of workspace.repositories) {
    if (item == null || typeof item !== "object" || Array.isArray(item)
        || Object.keys(item).length !== 2 || typeof item.repository !== "string"
        || typeof item.root !== "string" || !isAbsolute(item.root) || mappings.has(item.repository)) {
      documentationTransportError(errors, "local workspace mapping이 유효하지 않다");
      return null;
    }
    mappings.set(item.repository, item.root);
  }
  const actual = [...mappings.keys()];
  if (!isDeepStrictEqual(actual, activeRepositories)) {
    documentationTransportError(errors, "local workspace mapping이 ACTIVE repository 집합과 일치하지 않는다");
    return null;
  }
  return mappings;
}

function validateDocumentationGitRoot(root) {
  try {
    if (lstatSync(root).isSymbolicLink() || realpathSync(root) !== root) return false;
    if (documentationGit(root, ["rev-parse", "--show-toplevel"], "utf8").trim() !== root) return false;
    return documentationGit(root, ["rev-parse", "--show-object-format=storage"], "utf8").trim() === "sha1";
  } catch { return false; }
}

function resolveDocumentationBlob(
  root, commit, path,
  { readBytes = true, maxBytes = DOCUMENTATION_GIT_MAX_BUFFER } = {},
) {
  if (!/^[0-9a-f]{40}$/.test(commit) || !safeDocumentationPath(path)) return null;
  try {
    if (documentationGit(root, ["cat-file", "-t", commit], "utf8").trim() !== "commit") return null;
    const raw = documentationGit(root, ["ls-tree", "-z", commit, "--", path]);
    const entries = raw.toString("utf8").split("\0").filter(Boolean);
    if (entries.length !== 1) return null;
    const match = /^(\d+) (\w+) ([0-9a-f]{40})\t(.+)$/.exec(entries[0]);
    if (match == null || match[1] === "120000" || match[2] !== "blob" || match[4] !== path) return null;
    const size = documentationGit(root, ["cat-file", "-s", match[3]], "utf8").trim();
    if (!/^\d+$/.test(size)) return null;
    const byteLength = BigInt(size);
    if (byteLength > BigInt(maxBytes)) return { oid: match[3], byteLength, tooLarge: true };
    return {
      oid: match[3], byteLength,
      bytes: readBytes ? documentationGit(root, ["cat-file", "blob", match[3]]) : null,
    };
  } catch { return null; }
}

function hasOversizedDocumentationArray(value) {
  const pending = [value];
  while (pending.length > 0) {
    const current = pending.pop();
    if (Array.isArray(current)) {
      if (current.length > DOCUMENTATION_MAX_ARRAY_ITEMS) return true;
      for (const item of current) pending.push(item);
    } else if (current != null && typeof current === "object") {
      for (const item of Object.values(current)) pending.push(item);
    }
  }
  return false;
}

function resolveActiveDocumentationFragments(catalog, workspacePath, errors, schemaPaths) {
  const active = catalog.repositories.filter(({ status }) => status === "ACTIVE");
  if (active.length === 0) return;
  const repositories = active.map(({ repository }) => repository).sort(codepointCompare);
  const roots = loadDocumentationFragmentWorkspace(workspacePath, repositories, errors);
  if (roots == null) return;
  let fragmentSchema;
  let resourceSchema;
  try {
    fragmentSchema = loadJson(schemaPaths.fragmentSchema);
    resourceSchema = loadJson(schemaPaths.resourceSchema);
  } catch {
    documentationTransportError(errors, "fragment schema를 읽을 수 없다");
    return;
  }
  const resolvedFragments = [];
  let failed = false;
  let resourceCount = 0;
  for (const entry of active) {
    if (entry.fragment == null) { failed = true; continue; }
    const root = roots.get(entry.repository);
    if (!validateDocumentationGitRoot(root)) {
      documentationTransportError(errors, `${entry.repository} Git root가 유효하지 않다`);
      failed = true;
      continue;
    }
    const fragmentBlob = resolveDocumentationBlob(root, entry.fragment.gitSha, entry.fragment.path, {
      maxBytes: DOCUMENTATION_FRAGMENT_MAX_BYTES,
    });
    if (fragmentBlob?.tooLarge) {
      documentationTransportError(errors, `${entry.repository} fragment blob은 1 MiB 이하여야 한다`);
      failed = true;
      continue;
    }
    if (fragmentBlob == null) {
      documentationTransportError(errors, `${entry.repository} fragment blob을 확인할 수 없다`);
      failed = true;
      continue;
    }
    const expectedBlob = entry.fragment.blobSha.length === 40
      ? fragmentBlob.oid : createHash("sha256").update(fragmentBlob.bytes).digest("hex");
    if (expectedBlob !== entry.fragment.blobSha) {
      documentationTransportError(errors, `${entry.repository} fragment blob identity가 일치하지 않는다`);
      failed = true;
      continue;
    }
    let fragment;
    try { fragment = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(fragmentBlob.bytes)); } catch {
      documentationTransportError(errors, `${entry.repository} fragment JSON이 유효하지 않다`);
      failed = true;
      continue;
    }
    if (Array.isArray(fragment?.resources) && fragment.resources.length > DOCUMENTATION_MAX_ARRAY_ITEMS) {
      documentationTransportError(errors, `${entry.repository} fragment resources는 256개 이하여야 한다`);
      failed = true;
      continue;
    }
    if (hasOversizedDocumentationArray(fragment)) {
      documentationTransportError(errors, `${entry.repository} fragment 배열은 256개 항목 이하여야 한다`);
      failed = true;
      continue;
    }
    const fragmentErrors = [];
    try {
      validateDocumentationFragment(
        fragment,
        fragmentSchema, resourceSchema,
        fragmentErrors,
      );
    } catch {
      documentationTransportError(errors, "fragment schema가 유효하지 않다");
      return;
    }
    if (fragmentErrors.length > 0) {
      failed = true;
      for (const error of fragmentErrors) errors.push(`documentation fragment transport: ${entry.repository}: ${error}`);
      continue;
    }
    resourceCount += fragment.resources.length;
    if (resourceCount > DOCUMENTATION_MAX_RESOURCES) {
      documentationTransportError(errors, `${entry.repository} resources는 전체 256개 이하여야 한다`);
      failed = true;
      continue;
    }
    resolvedFragments.push({ entry, root, fragment });
  }
  if (failed) return;
  const records = [];
  let trackedDigestBytes = 0n;
  for (const { entry, root, fragment } of resolvedFragments) {
    const fragmentErrors = [];
    if (fragment.repository !== entry.repository || fragment.status !== "ACTIVE"
        || fragment.lastVerifiedAt !== entry.fragment.lastVerifiedAt
        || !isDeepStrictEqual(fragment.verificationEvidence, entry.fragment.verificationEvidence)) {
      fragmentErrors.push("catalog fragment header 불일치");
    }
    try {
      if (documentationGit(root, ["cat-file", "-t", fragment.gitSha], "utf8").trim() !== "commit") {
        fragmentErrors.push("inner commit relation 불일치");
      } else {
        documentationGit(root, ["merge-base", "--is-ancestor", fragment.gitSha, entry.fragment.gitSha]);
      }
    } catch { fragmentErrors.push("inner commit relation 불일치"); }
    const trackedRecords = fragment.resources.filter(({ sourceSurface }) => sourceSurface === "TRACKED");
    for (const record of trackedRecords) {
      const identity = /^git:([0-9a-f]{40}):([^:]+):([0-9a-f]{40}|[0-9a-f]{64})$/.exec(record.canonicalIdentity);
      const blob = identity != null && identity[1] === fragment.gitSha
        ? resolveDocumentationBlob(root, fragment.gitSha, identity[2], { readBytes: false }) : null;
      if (blob?.tooLarge) {
        fragmentErrors.push("TRACKED resource blob은 64 MiB 이하여야 한다");
        continue;
      }
      let actual = blob?.oid ?? null;
      if (blob != null && identity[3].length === 64) {
        if (trackedDigestBytes + blob.byteLength > BigInt(DOCUMENTATION_GIT_MAX_BUFFER)) {
          fragmentErrors.push("TRACKED resource SHA-256 payload 합계는 64 MiB 이하여야 한다");
          break;
        }
        trackedDigestBytes += blob.byteLength;
        try { actual = createHash("sha256").update(documentationGit(root, ["cat-file", "blob", blob.oid])).digest("hex"); }
        catch { actual = null; }
      }
      if (actual !== identity?.[3]) fragmentErrors.push("TRACKED resource blob identity가 일치하지 않는다");
    }
    if (fragmentErrors.length > 0) {
      failed = true;
      for (const error of fragmentErrors) errors.push(`documentation fragment transport: ${entry.repository}: ${error}`);
    } else records.push(...fragment.resources);
  }
  if (failed) return;
  try { validateDocumentationRelations(records); } catch {
    documentationTransportError(errors, "ACTIVE fragment relation이 유효하지 않다");
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
  const duplicateGroups = new Map();
  for (const record of records) {
    if (record.duplicateGroup !== null) {
      duplicateGroups.set(record.duplicateGroup, [...(duplicateGroups.get(record.duplicateGroup) ?? []), record]);
    }
  }
  for (const group of duplicateGroups.values()) {
    if (group.filter((record) => record.disposition === "RETAIN_CANONICAL").length > 1
        || group.some((record) => record.currentConsumers.length === 0
          || record.disposition !== "RETAIN_CANONICAL" && record.deletePrerequisite.length === 0)) {
      throw new Error("fragment duplicate group contradiction");
    }
  }
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
  const fragmentWorkspaceIndex = args.indexOf("--documentation-fragment-workspace");
  const hasFragmentWorkspace = fragmentWorkspaceIndex === -1
    || (fragmentWorkspaceIndex === args.length - 2 && args[fragmentWorkspaceIndex + 1].trim() !== "");
  const contractArgs = fragmentWorkspaceIndex === -1 ? args : args.slice(0, fragmentWorkspaceIndex);
  const hasBaseRef = contractArgs.length === 4 && contractArgs[2] === "--base-ref" && contractArgs[3].trim() !== "";
  const isCurrentOnly = contractArgs.length === 3 && contractArgs[2] === "--current-only";
  const validArgs = hasWorkspace && hasFragmentWorkspace && (hasBaseRef || isCurrentOnly);
  if (!validArgs) {
    console.error("사용법: node tools/ci/check-contracts.mjs --workspace <workspace.json> (--base-ref <40-hex-sha>|--current-only) [--documentation-fragment-workspace <local-json>]");
    process.exit(1);
  }
  let previousArchitectureDecision = null;
  try {
    if (hasBaseRef) previousArchitectureDecision = loadArchitectureDecisionAtRef(args[1], args[3]);
  } catch (error) {
    console.error(`- ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  }
  const errors = collectContractErrors(args[1], {
    previousArchitectureDecision,
    documentationFragmentWorkspacePath: fragmentWorkspaceIndex === -1 ? null : args[fragmentWorkspaceIndex + 1],
  });
  if (errors.length) {
    console.error(errors.map((error) => `- ${error}`).join("\n"));
    process.exit(1);
  }
}
