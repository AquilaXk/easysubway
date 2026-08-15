import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative, resolve } from "node:path";
import {
  collectContractErrors,
  loadArchitectureDecisionAtRef,
  loadWorkspace,
  loadJson,
  validateCompatibilityMatrixPayload,
  validateDatapackIndex,
  validateDatapackManifest,
  validateJson,
  validateSourceInventory,
  validateSourceGovernanceContracts,
  validateBoundariesPayload,
  validateRepositorySplitIssueAmendments,
  validateRepositorySplitIssueLedger,
  validateArchitectureDecision,
  validateArchitectureDecisionTransition,
  validateArchitectureDecisionWorkspaceTransition,
  validateDocumentationFragment,
  validateDocumentationSystemCatalog,
  validateGateIndex,
  validateProductClaimCatalog,
  validateRepositoryContractionInventory,
  validateReferenceAuditScope,
  validateReferenceAuditReportSchema,
  validatePublicSensitivityAuditScope,
  validatePublicSensitivityOwnerReceiptSchema,
  validatePublicSensitivityAuditReportSchema,
  validatePlanDocExecutionAuditScope,
  validatePlanDocExecutionAuditReportSchema,
  validateDocumentationInventoryAuditReportSchema,
  validateExternalTerminalLocatorAuditScope,
  validateExternalTerminalLocatorAuditReportSchema,
  validateCleanCheckoutReproducibilityAuditScope,
  validateCleanCheckoutReproducibilityAuditScopeSchema,
  validateCleanCheckoutReproducibilityOwnerContractSchema,
  validateCleanCheckoutReproducibilityOwnerReceiptSchema,
  validateCleanCheckoutReproducibilityAuditReportSchema,
  validatePostGoBoundaryAuditScope,
  validatePostGoBoundaryAuditReportSchema,
} from "./check-contracts.mjs";
import { validateSchema } from "./lib/json-schema-lite.mjs";
import { validateDocumentationInventoryAuditScope } from "../repo/audit-documentation-inventory.mjs";

const DOCUMENTATION_FRAGMENT_SCHEMA_URI =
  "https://raw.githubusercontent.com/AquilaXk/easysubway/32ce139789b97ce1f0c9bb059966cfc19f497480/contracts/documentation/documentation-fragment.schema.json";

test("documentation inventory audit contracts bind the exact five repositories and D01-D05", () => {
  const scope = loadJson("contracts/documentation/documentation-inventory-audit-scope.json");
  const scopeSchema = loadJson("contracts/documentation/documentation-inventory-audit-scope.schema.json");
  const reportSchema = loadJson("contracts/documentation/documentation-inventory-audit-report.schema.json");
  const workspace = loadWorkspace();
  assert.equal(workspace.documentationInventoryAuditScope, "contracts/documentation/documentation-inventory-audit-scope.json");
  assert.equal(workspace.documentationInventoryAuditReportSchema, "contracts/documentation/documentation-inventory-audit-report.schema.json");
  assert.equal(validateSchema(scopeSchema, scope).ok, true);
  assert.deepEqual(validateDocumentationInventoryAuditScope(scope), []);
  assert.deepEqual(validateDocumentationInventoryAuditReportSchema(reportSchema), []);
  for (const mutate of [
    (value) => value.repositories.reverse(),
    (value) => { value.repositories[0].fragmentPath = "../fragment.json"; },
    (value) => value.dods.pop(),
  ]) { const invalid = structuredClone(scope); mutate(invalid); assert.ok(validateDocumentationInventoryAuditScope(invalid).length > 0); }
  for (const mutate of [
    (value) => { value.properties.status.enum = ["COMPLETE"]; },
    (value) => { value.properties.summary.required.pop(); },
    (value) => { value.properties.repositories.maxItems = 6; },
    (value) => { value.properties.repositories.items.required.pop(); },
    (value) => { value.properties.dods.items.properties.id.enum.pop(); },
    (value) => { value.oneOf[0].properties.incomplete.maxItems = 1; },
  ]) { const invalid = structuredClone(reportSchema); mutate(invalid); assert.ok(validateDocumentationInventoryAuditReportSchema(invalid).length > 0); }
});

test("reference audit scope requires the exact five-repository inventory", () => {
  const errors = [];
  validateReferenceAuditScope({ repositories: [{ repository: "AquilaXk/easysubway", trackedDiscoveryRoots: ["../unsafe"] }] }, errors);
  assert.ok(errors.some((error) => error.includes("exact codepoint sorted 5개")));
  assert.ok(errors.some((error) => error.includes("안전한 repository-relative")));
});

test("reference audit scope schema rejects unapproved content classification extensions", () => {
  const schema = loadJson("contracts/documentation/reference-audit-scope.schema.json");
  const scope = loadJson("contracts/documentation/reference-audit-scope.json");
  for (const [field, value] of [["knownBinaryExtensions", [".gif", ".zip"]], ["bareReferenceExtensions", [".json", ".txt", ".yaml", ".yml"]]]) {
    const candidate = structuredClone(scope);
    candidate.contentClassification[field] = value;
    assert.equal(validateSchema(schema, candidate).ok, false);
  }
});

test("reference audit report schema requires source identity and strict findings", () => {
  const errors = [];
  validateReferenceAuditReportSchema({ type: "object", additionalProperties: false, required: [], properties: { observedAt: {}, inputs: { properties: {} }, findings: { items: {} } } }, errors);
  assert.equal(errors.length, 12);
});

test("public sensitivity contracts bind the exact scope and corrected owner receipt artifacts", () => {
  const scopeSchema = loadJson("contracts/documentation/public-sensitivity-audit-scope.schema.json");
  const scope = loadJson("contracts/documentation/public-sensitivity-audit-scope.json");
  const receiptSchema = loadJson("contracts/documentation/public-sensitivity-owner-receipt.schema.json");
  const reportSchema = loadJson("contracts/documentation/public-sensitivity-audit-report.schema.json");
  assert.equal(validateSchema(scopeSchema, scope).ok, true);
  assert.deepEqual(validatePublicSensitivityAuditScope(scope), []);
  assert.deepEqual(validatePublicSensitivityOwnerReceiptSchema(receiptSchema), []);
  assert.deepEqual(validatePublicSensitivityAuditReportSchema(reportSchema), []);
  for (const mutate of [
    (value) => { value.properties.openAlertCount.type = "number"; },
    (value) => { value.properties.publicArtifacts.uniqueItems = false; },
    (value) => { value.properties.publicArtifacts.items.properties.artifactId.pattern = ".+"; },
    (value) => { delete value.properties.publicArtifacts.items.properties.createdAt; },
  ]) {
    const weakened = structuredClone(receiptSchema);
    mutate(weakened);
    assert.ok(validatePublicSensitivityOwnerReceiptSchema(weakened).length > 0);
  }
  for (const mutate of [
    (value) => { delete value.oneOf; },
    (value) => { value.properties.summary.properties.findings.type = "number"; },
    (value) => { value.properties.findings.uniqueItems = false; },
    (value) => { value.properties.findings.items.properties.detectorId = { type: "string" }; },
    (value) => { value.properties.inputs.properties.repositories.minItems = 0; },
    (value) => { value.properties.inputs.properties.repositories.items.required = value.properties.inputs.properties.repositories.items.required.filter((field) => field !== "artifactBeginWatermark"); },
  ]) {
    const weakened = structuredClone(reportSchema);
    mutate(weakened);
    assert.ok(validatePublicSensitivityAuditReportSchema(weakened).length > 0);
  }
  const invalid = structuredClone(scope);
  invalid.falsePositiveDispositions.push({ locationFingerprint: "a".repeat(64), detectorId: "KNOWN_TOKEN_FORMAT", reason: "reviewed", owner: "owner", verifiedAt: "2026-08-09T03:00:00.000Z", expiresAt: "2026-08-08T03:00:00.000Z" });
  assert.ok(validatePublicSensitivityAuditScope(invalid).some((error) => error.includes("revalidation/expiry")));
  const offsetInvalid = structuredClone(scope);
  offsetInvalid.falsePositiveDispositions.push({ locationFingerprint: "a".repeat(64), detectorId: "KNOWN_TOKEN_FORMAT", reason: "reviewed", owner: "owner", verifiedAt: "2026-08-08T23:30:00Z", expiresAt: "2026-08-09T00:00:00+09:00" });
  assert.ok(validatePublicSensitivityAuditScope(offsetInvalid).some((error) => error.includes("revalidation/expiry")));
});

test("plan-doc execution audit contracts fix the historical inventory and fail-closed report", () => {
  const scope = loadJson("contracts/documentation/plan-doc-execution-audit-scope.json");
  const scopeSchema = loadJson("contracts/documentation/plan-doc-execution-audit-scope.schema.json");
  const reportSchema = loadJson("contracts/documentation/plan-doc-execution-audit-report.schema.json");
  assert.equal(scope.historical.length, 38);
  assert.equal(scope.self.issueNumber, 2849);
  assert.equal(scopeSchema.properties.historical.minItems, 38);
  assert.equal(scopeSchema.properties.historical.maxItems, 38);
  assert.equal(scopeSchema.properties.self.properties.issueNumber.const, 2849);
  const recordsByPr = new Map(scope.historical.map((record) => [record.prNumber, record]));
  for (const [prNumber, issueNumber] of [[2798, 2797], [2799, 2797], [2801, 2800], [2803, 2802], [2806, 2805], [2808, 2807], [2810, 2809], [2813, 2729], [2815, 2814], [2817, 2816], [2819, 2818], [2822, 2821], [2824, 2820], [2826, 2825], [2828, 2827], [2830, 2829], [2832, 2831], [2834, 2833], [2842, 2841], [2844, 2843], [2846, 2845], [2848, 2847]]) {
    assert.equal(recordsByPr.get(prNumber)?.issueNumber, issueNumber);
  }
  assert.equal(recordsByPr.get(2810)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2813)?.relation, "COORDINATOR_FOLLOWUP");
  assert.equal(recordsByPr.get(2815)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2817)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2819)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2822)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2824)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2826)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2828)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2830)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2832)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2834)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2842)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2844)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2846)?.relation, "CLOSES");
  assert.equal(recordsByPr.get(2848)?.relation, "CLOSES");
  assert.equal(validateSchema(scopeSchema, scope).ok, true);
  assert.deepEqual(validatePlanDocExecutionAuditScope(scope), []);
  assert.deepEqual(validatePlanDocExecutionAuditReportSchema(reportSchema), []);
  const invalid = structuredClone(scope); invalid.historical[0].mergeSha = "a".repeat(40);
  assert.ok(validatePlanDocExecutionAuditScope(invalid).length > 0);
  const invalidSelf = structuredClone(scope); invalidSelf.self.issueNumber = 2809;
  assert.ok(validatePlanDocExecutionAuditScope(invalidSelf).length > 0);
  const weakened = structuredClone(reportSchema); delete weakened.oneOf;
  assert.ok(validatePlanDocExecutionAuditReportSchema(weakened).length > 0);
  for (const [name, mutate] of [
    ["scopeSha256", (schema) => { schema.properties.inputs.properties.scopeSha256.pattern = ".+"; }],
    ["record repository", (schema) => { schema.properties.records.items.properties.repository.const = "AquilaXk/other"; }],
    ["mergeSha", (schema) => { schema.properties.records.items.properties.mergeSha.pattern = ".+"; }],
    ["changedFiles uniqueness", (schema) => { schema.properties.records.items.properties.changedFiles.uniqueItems = false; }],
    ["records", (schema) => { schema.properties.records.items.required = schema.properties.records.items.required.filter((field) => field !== "changedFiles"); }],
    ["findings", (schema) => { schema.properties.findings.items.required = schema.properties.findings.items.required.filter((field) => field !== "identity"); }],
    ["incomplete", (schema) => { schema.properties.incomplete.items.required = schema.properties.incomplete.items.required.filter((field) => field !== "affectedIdentity"); }],
  ]) {
    const mutated = structuredClone(reportSchema);
    mutate(mutated);
    assert.ok(validatePlanDocExecutionAuditReportSchema(mutated).length > 0, name);
  }
});

test("external terminal locator audit contracts fix the exact pending inventory and strict report", () => {
  const scope = loadJson("contracts/documentation/external-terminal-locator-audit-scope.json");
  const scopeSchema = loadJson("contracts/documentation/external-terminal-locator-audit-scope.schema.json");
  const reportSchema = loadJson("contracts/documentation/external-terminal-locator-audit-report.schema.json");
  assert.equal(validateSchema(scopeSchema, scope).ok, true);
  assert.deepEqual(validateExternalTerminalLocatorAuditScope(scope), []);
  assert.deepEqual(validateExternalTerminalLocatorAuditReportSchema(reportSchema), []);
  const invalid = structuredClone(scope); invalid.slots[0].ownerIssue = 1;
  assert.ok(validateExternalTerminalLocatorAuditScope(invalid).length > 0);
  const weakened = structuredClone(reportSchema); delete weakened.oneOf;
  assert.ok(validateExternalTerminalLocatorAuditReportSchema(weakened).length > 0);
  const weakenedNested = structuredClone(reportSchema); weakenedNested.properties.slots.items.properties.terminalLocator.oneOf[1].properties.path.pattern = ".+";
  assert.ok(validateExternalTerminalLocatorAuditReportSchema(weakenedNested).length > 0);
  const weakenedOci = structuredClone(reportSchema); weakenedOci.properties.slots.items.properties.terminalLocator.oneOf[2].properties.repositoryPath.pattern = ".+";
  assert.ok(validateExternalTerminalLocatorAuditReportSchema(weakenedOci).length > 0);
  const weakenedComplete = structuredClone(reportSchema); weakenedComplete.oneOf[0].properties.inputs.properties.stateBeginSha256.type = ["string", "null"];
  assert.ok(validateExternalTerminalLocatorAuditReportSchema(weakenedComplete).length > 0);
  const weakenedTimestamp = structuredClone(reportSchema); weakenedTimestamp.properties.slots.items.properties.terminalLocator.oneOf[3].properties.createdAt.pattern = ".+";
  assert.ok(validateExternalTerminalLocatorAuditReportSchema(weakenedTimestamp).length > 0);
  const weakenedWorkflowPath = structuredClone(reportSchema); weakenedWorkflowPath.properties.slots.items.properties.terminalLocator.oneOf[3].properties.workflowPath.pattern = ".+";
  assert.ok(validateExternalTerminalLocatorAuditReportSchema(weakenedWorkflowPath).length > 0);
  for (const mutate of [
    (value) => { value.properties.slots.items.properties.terminalLocator.oneOf[1].properties.kind.const = "OCI_DIGEST"; },
    (value) => { value.properties.slots.items.properties.terminalLocator.oneOf[1].required.pop(); },
    (value) => { value.properties.slots.items.properties.terminalLocator.oneOf[2].additionalProperties = true; },
    (value) => { value.properties.slots.items.properties.terminalLocator.oneOf[2].properties.digest.pattern = ".+"; },
    (value) => { value.properties.slots.items.properties.terminalLocator.oneOf[3].properties.artifactId.minimum = 0; },
    (value) => { value.properties.slots.items.additionalProperties = true; },
    (value) => { value.properties.slots.items.properties.ownerRepository.enum = ["AquilaXk/easysubway"]; },
    (value) => { value.properties.inputs.additionalProperties = true; },
    (value) => { value.properties.inputs.required.pop(); },
    (value) => { value.properties.inputs.properties.sourceSha.pattern = ".+"; },
    (value) => { value.properties.inputs.properties.stateBeginSha256.pattern = ".+"; },
    (value) => { value.properties.summary.type = "array"; },
    (value) => { value.properties.summary.additionalProperties = true; },
    (value) => { value.properties.summary.required.pop(); },
    (value) => { value.properties.summary.properties.ready.minimum = -1; },
    (value) => { value.properties.slots.type = "object"; },
    (value) => { value.properties.slots.items.type = "array"; },
  ]) { const invalid = structuredClone(reportSchema); mutate(invalid); assert.ok(validateExternalTerminalLocatorAuditReportSchema(invalid).length > 0); }
  const validActions = structuredClone(scope);
  validActions.slots[0] = { ...validActions.slots[0], state: "READY", terminalLocator: { kind: "ACTIONS_ARTIFACT", repository: "AquilaXk/easysubway", runId: 1, artifactId: 1, artifactName: "receipt", archiveDigest: `sha256:${"a".repeat(64)}`, workflowPath: ".github/workflows/audit.yml", headSha: "b".repeat(40), createdAt: "2026-08-10T00:00:00Z", expiresAt: "2026-08-11T00:00:00Z" } };
  assert.equal(validateSchema(scopeSchema, validActions).ok, true);
  const unsafeWorkflow = structuredClone(validActions); unsafeWorkflow.slots[0].terminalLocator.workflowPath = ".github/workflows/../audit.yml";
  assert.equal(validateSchema(scopeSchema, unsafeWorkflow).ok, false);
  const unsafeLocator = structuredClone(scope);
  unsafeLocator.slots[0] = { ...unsafeLocator.slots[0], state: "READY", terminalLocator: { kind: "GIT_BLOB", repository: "AquilaXk/easysubway", commitSha: "a".repeat(40), path: "../secret", blobSha: "b".repeat(40) } };
  assert.ok(validateExternalTerminalLocatorAuditScope(unsafeLocator).length > 0);
});

test("clean checkout reproducibility audit contracts fix the exact Hub READY and four-owner pending inventory", () => {
  const scope = loadJson("contracts/documentation/clean-checkout-reproducibility-audit-scope.json");
  const scopeSchema = loadJson("contracts/documentation/clean-checkout-reproducibility-audit-scope.schema.json");
  const contractSchema = loadJson("contracts/documentation/clean-checkout-reproducibility-owner-contract.schema.json");
  const receiptSchema = loadJson("contracts/documentation/clean-checkout-reproducibility-owner-receipt.schema.json");
  const reportSchema = loadJson("contracts/documentation/clean-checkout-reproducibility-audit-report.schema.json");
  assert.equal(validateSchema(scopeSchema, scope).ok, true);
  assert.deepEqual(validateCleanCheckoutReproducibilityAuditScope(scope), []);
  assert.deepEqual(validateCleanCheckoutReproducibilityAuditScopeSchema(scopeSchema), []);
  assert.deepEqual(validateCleanCheckoutReproducibilityOwnerContractSchema(contractSchema), []);
  assert.deepEqual(validateCleanCheckoutReproducibilityOwnerReceiptSchema(receiptSchema), []);
  assert.deepEqual(validateCleanCheckoutReproducibilityAuditReportSchema(reportSchema), []);
  assert.equal(scope.schemaVersion, 2);
  assert.equal(reportSchema.properties.schemaVersion.const, 2);
  assert.deepEqual(scope.slots, [
    {
      repository: "AquilaXk/easysubway",
      state: "READY",
      ownerIssue: 2843,
      evidenceSource: {
        contractPath: "contracts/documentation/clean-checkout-reproducibility-owner-contract.json",
        workflowPath: ".github/workflows/clean-checkout-reproducibility-owner-receipt-caller.yml",
        artifactNamePrefix: "clean-checkout-reproducibility-owner-receipt-",
      },
    },
    ...[
      "AquilaXk/easysubway-backend",
      "AquilaXk/easysubway-data",
      "AquilaXk/easysubway-mobile",
      "AquilaXk/easysubway-platform",
    ].map((repository) => ({ repository, state: "PENDING", ownerIssue: null, evidenceSource: null })),
  ]);

  const invalidScope = structuredClone(scope); invalidScope.slots[0].evidenceSource = null;
  assert.ok(validateCleanCheckoutReproducibilityAuditScope(invalidScope).length > 0);
  assert.deepEqual(contractSchema.required, ["schemaVersion", "repository", "variants"]);
  assert.equal(Object.hasOwn(contractSchema.properties, "sourceSha"), false);
  for (const mutate of [
    (value) => { value.properties.slots.minItems = 4; },
    (value) => { value.properties.slots.items.properties.repository.enum.pop(); },
    (value) => { value.properties.slots.items.properties.evidenceSource.oneOf[1].properties.contractPath.pattern = ".+"; },
    (value) => { value.properties.slots.items.properties.evidenceSource.oneOf[1].properties.workflowPath.pattern = ".+"; },
    (value) => { value.properties.slots.items.properties.evidenceSource.oneOf[1].properties.artifactNamePrefix.pattern = ".+"; },
    (value) => { value.properties.slots.items.properties.evidenceSource.oneOf[1].properties.contractPath.type = ["string", "null"]; },
    (value) => { value.properties.slots.items.properties.evidenceSource.oneOf[1].properties.workflowPath.type = ["string", "null"]; },
    (value) => { value.properties.slots.items.properties.evidenceSource.oneOf[1].properties.artifactNamePrefix.type = ["string", "null"]; },
    (value) => { value.properties.slots.items.properties.evidenceSource.oneOf.push({}); },
    (value) => { value.properties.slots.items.oneOf[0].properties.ownerIssue.type = "integer"; },
  ]) { const invalid = structuredClone(scopeSchema); mutate(invalid); assert.ok(validateCleanCheckoutReproducibilityAuditScopeSchema(invalid).length > 0); }

  for (const mutate of [
    (value) => { value.additionalProperties = true; },
    (value) => { value.required.splice(2, 0, "sourceSha"); value.properties.sourceSha = { type: "string", pattern: "^[0-9a-f]{40}$" }; },
    (value) => { value.properties.repository.enum = ["AquilaXk/easysubway"]; },
    (value) => { value.properties.variants.maxItems = 17; },
    (value) => { value.properties.variants.items.properties.phases.minItems = 3; },
    (value) => { value.properties.variants.items.properties.phases.items.properties.entrypoint.pattern = ".+"; },
    (value) => { value.properties.variants.items.properties.phases.items.properties.requiredEnvironment.items.pattern = ".+"; },
    (value) => { value.properties.variants.items.properties.phases.items.properties.timeoutSeconds.maximum = 7200; },
  ]) { const invalid = structuredClone(contractSchema); mutate(invalid); assert.ok(validateCleanCheckoutReproducibilityOwnerContractSchema(invalid).length > 0); }

  for (const mutate of [
    (value) => { value.properties.contractSha256.pattern = ".+"; },
    (value) => { value.properties.cleanCheckout.additionalProperties = true; },
    (value) => { value.properties.cleanCheckout.properties.initialTrackedDiffCount.minimum = -1; },
    (value) => { value.properties.variants.items.properties.phases.maxItems = 5; },
    (value) => { value.properties.variants.items.properties.phases.items.required.pop(); },
    (value) => { value.properties.variants.items.properties.phases.items.properties.commandSha256.pattern = ".+"; },
    (value) => { value.properties.variants.items.properties.runnerImage.pattern = ".+"; },
    (value) => { value.properties.variants.items.properties.phases.items.properties.startedAt.pattern = ".+"; },
    (value) => { value.properties.variants.items.properties.phases.items.properties.unexpectedProcessCount.type = "number"; },
  ]) { const invalid = structuredClone(receiptSchema); mutate(invalid); assert.ok(validateCleanCheckoutReproducibilityOwnerReceiptSchema(invalid).length > 0); }

  for (const mutate of [
    (value) => { delete value.oneOf; },
    (value) => { value.properties.inputs.additionalProperties = true; },
    (value) => { value.properties.inputs.properties.stateBeginSha256.pattern = ".+"; },
    (value) => { value.properties.summary.properties.ready.minimum = -1; },
    (value) => { value.properties.slots.minItems = 4; },
    (value) => { value.properties.slots.items.properties.evidenceSource.oneOf[1].additionalProperties = true; },
    (value) => { value.properties.slots.items.properties.contractLocator.oneOf[1].additionalProperties = true; },
    (value) => { value.properties.slots.items.properties.receiptLocator.oneOf[1].properties.artifactId.minimum = 0; },
    (value) => { value.properties.slots.items.properties.currentHead.pattern = ".+"; },
    (value) => { value.properties.slots.items.oneOf[0].properties.evidenceState.enum = ["VERIFIED"]; },
    (value) => { value.properties.findings.items.additionalProperties = true; },
    (value) => { value.oneOf[0].properties.inputs.properties.stateEndSha256.type = ["string", "null"]; },
  ]) { const invalid = structuredClone(reportSchema); mutate(invalid); assert.ok(validateCleanCheckoutReproducibilityAuditReportSchema(invalid).length > 0); }
});

test("clean checkout reproducibility contract collection reports malformed or missing scope schema without throwing", () => {
  const fixture = createExternalWorkspace();
  try {
    cpSync("contracts", join(fixture.directory, "contracts"), { recursive: true });
    const workspace = loadJson(fixture.workspacePath);
    Object.assign(workspace, {
      contracts: "contracts",
      cleanCheckoutReproducibilityAuditScope: "contracts/documentation/clean-checkout-reproducibility-audit-scope.json",
      cleanCheckoutReproducibilityOwnerContractSchema: "contracts/documentation/clean-checkout-reproducibility-owner-contract.schema.json",
      cleanCheckoutReproducibilityOwnerReceiptSchema: "contracts/documentation/clean-checkout-reproducibility-owner-receipt.schema.json",
      cleanCheckoutReproducibilityAuditReportSchema: "contracts/documentation/clean-checkout-reproducibility-audit-report.schema.json",
    });
    writeFileSync(fixture.workspacePath, JSON.stringify(workspace));
    const scopeSchemaPath = join(fixture.directory, "contracts/documentation/clean-checkout-reproducibility-audit-scope.schema.json");

    writeFileSync(scopeSchemaPath, "{");
    let malformedErrors;
    assert.doesNotThrow(() => { malformedErrors = collectContractErrors(fixture.workspacePath); });
    assert.ok(malformedErrors.some((error) => error.includes("clean-checkout-reproducibility-audit-scope.schema.json: 유효한 JSON")));

    rmSync(scopeSchemaPath);
    let missingErrors;
    assert.doesNotThrow(() => { missingErrors = collectContractErrors(fixture.workspacePath); });
    assert.ok(missingErrors.some((error) => error.includes("clean-checkout-reproducibility-audit-scope.schema.json 누락")));
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test("post-GO boundary audit contracts bind current blockers and strict report", () => {
  const scope = loadJson("contracts/documentation/post-go-boundary-audit-scope.json");
  const scopeSchema = loadJson("contracts/documentation/post-go-boundary-audit-scope.schema.json");
  const reportSchema = loadJson("contracts/documentation/post-go-boundary-audit-report.schema.json");
  assert.equal(validateSchema(scopeSchema, scope).ok, true);
  assert.deepEqual(validatePostGoBoundaryAuditScope(scope), []);
  assert.deepEqual(validatePostGoBoundaryAuditReportSchema(reportSchema), []);
  for (const mutate of [
    (value) => { value.parents.fieldResearch.activationMarker = "other"; },
    (value) => { value.parents.privacyMetrics.blockedMarkers[0] = "other"; },
  ]) { const invalid = structuredClone(scope); mutate(invalid); assert.ok(validatePostGoBoundaryAuditScope(invalid).length > 0); }
  for (const mutate of [
    (value) => { value.properties.status.enum = ["COMPLETE"]; },
    (value) => { value.properties.lanes.minItems = 1; },
    (value) => { value.properties.lanes.items.properties.status.enum.push("START_ELIGIBLE"); },
    (value) => { value.properties.lanes.items.required = ["parent"]; },
    (value) => { value.oneOf[1].properties.incomplete.minItems = 0; },
    (value) => { value.oneOf[0].properties.status.const = "AUDIT_INCOMPLETE"; },
    (value) => { value.properties.inputs.required = value.properties.inputs.required.filter((field) => field !== "stateEndSha256"); },
    (value) => { value.properties.inputs.properties.stateBeginSha256.pattern = ".+"; },
  ]) { const invalid = structuredClone(reportSchema); mutate(invalid); assert.ok(validatePostGoBoundaryAuditReportSchema(invalid).length > 0); }
});

test("F15 reference audit scope validation is total and skips semantics after schema failure", () => {
  const directErrors = [];
  assert.doesNotThrow(() => validateReferenceAuditScope({ repositories: null }, directErrors));
  assert.ok(directErrors.length > 0);
  const fixture = createExternalWorkspace();
  try {
    const workspace = loadJson(fixture.workspacePath);
    workspace.referenceAuditScope = "inputs/reference-audit-scope.json";
    workspace.referenceAuditReportSchema = "inputs/reference-audit-report.schema.json";
    cpSync("contracts/documentation/reference-audit-report.schema.json", join(fixture.directory, "inputs/reference-audit-report.schema.json"));
    writeFileSync(fixture.workspacePath, JSON.stringify(workspace));
    writeFileSync(join(fixture.directory, "inputs/reference-audit-scope.json"), "{");
    assert.doesNotThrow(() => collectContractErrors(fixture.workspacePath));
    assert.ok(collectContractErrors(fixture.workspacePath).some((error) => error.includes("유효한 JSON")));
    writeFileSync(join(fixture.directory, "inputs/reference-audit-scope.json"), JSON.stringify({ repositories: {} }));
    assert.doesNotThrow(() => collectContractErrors(fixture.workspacePath));
    assert.ok(collectContractErrors(fixture.workspacePath).some((error) => error.includes("reference-audit-scope")));
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("reference audit report schema fixes referenceClass to the exact inventory", () => {
  const schema = loadJson("contracts/documentation/reference-audit-report.schema.json");
  assert.deepEqual(validateReferenceAuditReportSchema(schema), []);
  schema.properties.findings.items.properties.referenceClass = { type: "string" };
  assert.ok(validateReferenceAuditReportSchema(schema).some((error) => error.includes("referenceClass")));
});

const FIXTURE_GIT_UNSET = ["GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS", "GIT_NAMESPACE", "GIT_SHALLOW_FILE", "GIT_QUARANTINE_PATH", "GIT_CEILING_DIRECTORIES", "GIT_GLOB_PATHSPECS", "GIT_NOGLOB_PATHSPECS", "GIT_ICASE_PATHSPECS"];

function fixtureGit(args, options = {}) {
  const env = {
    ...process.env,
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_SYSTEM: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
  };
  for (const key of FIXTURE_GIT_UNSET) delete env[key];
  const command = args[0] === "init" ? ["init", "--template=", ...args.slice(1)] : args;
  return execFileSync("/usr/bin/git", ["-c", "commit.gpgSign=false", "-c", "core.hooksPath=/dev/null", ...command], {
    ...options,
    env,
  });
}

function initializeHubInventoryFixtureRepository(directory) {
  fixtureGit(["init"], { cwd: directory, stdio: "ignore" });
  fixtureGit(["config", "user.email", "test@example.com"], { cwd: directory, stdio: "ignore" });
  fixtureGit(["config", "user.name", "Test"], { cwd: directory, stdio: "ignore" });
  fixtureGit(["remote", "add", "origin", "https://github.com/AquilaXk/easysubway.git"], {
    cwd: directory,
    stdio: "ignore",
  });
  fixtureGit(["add", "README.md"], { cwd: directory, stdio: "ignore" });
  fixtureGit(["commit", "-m", "inventory base"], { cwd: directory, stdio: "ignore" });
  const inventoryBaseHead = fixtureGit(["rev-parse", "HEAD"], {
    cwd: directory,
    encoding: "utf8",
  }).trim();
  const inventoryPath = join(directory, "release/migrations/repository-contraction-inventory.json");
  const inventory = loadJson(inventoryPath);
  inventory.inventoryBaseHead = inventoryBaseHead;
  writeFileSync(inventoryPath, JSON.stringify(inventory));
  return inventoryBaseHead;
}

function createExternalWorkspace() {
  const directory = mkdtempSync(join(tmpdir(), "gate-ownership-workspace-"));
  mkdirSync(join(directory, "inputs"), { recursive: true });
  const copy = (source, target) => cpSync(source, join(directory, target), { recursive: true });
  copy("apps/mobile/assets/datapacks/index.json", "inputs/datapack-index.json");
  copy("apps/mobile/assets/datapacks/source-inventory.json", "inputs/source-inventory.json");
  copy("tools/datapack/source-governance-policy.json", "inputs/governance-policy.json");
  copy("release/product-gates/datapack-freshness-sla.json", "inputs/freshness-policy.json");
  copy("release/product-gates", "gates/hub");
  copy("apps/mobile/release", "gates/mobile");
  mkdirSync(join(directory, "release/migrations"), { recursive: true });
  copy("release/migrations/repository-split-issues.json", "release/migrations/repository-split-issues.json");
  copy("release/migrations/repository-split-issues-amendments.json", "release/migrations/repository-split-issues-amendments.json");
  copy("release/migrations/repository-contraction-inventory.json", "release/migrations/repository-contraction-inventory.json");
  const workspacePath = join(directory, "hub.json");
  writeFileSync(workspacePath, JSON.stringify({
    contracts: relative(directory, resolve("contracts")),
    gateDirectories: { hub: "gates/hub", mobile: "gates/mobile" },
    datapackIndex: "inputs/datapack-index.json",
    sourceInventory: "inputs/source-inventory.json",
    governancePolicy: "inputs/governance-policy.json",
    freshnessPolicy: "inputs/freshness-policy.json",
    architectureDecision: "inputs/architecture-decision.json",
    documentationSystemCatalog: "inputs/documentation-system-catalog.json",
    productClaimCatalog: "inputs/product-claim-catalog.json",
  }));
  copy("contracts/documentation/ADR-HUB-0001.json", "inputs/architecture-decision.json");
  copy("contracts/documentation/ADR-HUB-0001-decision.schema.json", "inputs/ADR-HUB-0001-decision.schema.json");
  copy("contracts/documentation/documentation-system-catalog.json", "inputs/documentation-system-catalog.json");
  const fixtureCatalogPath = join(directory, "inputs/documentation-system-catalog.json");
  const fixtureCatalog = loadJson(fixtureCatalogPath);
  for (const entry of fixtureCatalog.repositories) {
    entry.status = "PROPOSED";
    entry.fragment = null;
  }
  writeFileSync(fixtureCatalogPath, JSON.stringify(fixtureCatalog));
  copy("contracts/documentation/product-claim-catalog.json", "inputs/product-claim-catalog.json");
  return { directory, workspacePath };
}

function bindRootDecisionSchema(directory, adr) {
  const schemaName = `${adr.id}-decision.schema.json`;
  adr.decisionSchema = `./${schemaName}`;
  cpSync("contracts/documentation/ADR-HUB-0001-decision.schema.json", join(directory, schemaName));
}

function documentationCatalogRecord(repository, innerSha, blobSha, path = "docs/resource.txt") {
  const resource = `${repository}:${path}`;
  const canonicalIdentity = `git:${innerSha}:${path}:${blobSha}`;
  return {
    resource, resourceClass: "CANONICAL_RESOURCE", documentationFamily: "ARCHITECTURE",
    kindCandidate: "DOCUMENTATION_RESOURCE", sourceSurface: "TRACKED", canonicalIdentity,
    status: "ACTIVE", ownerRepository: repository, ownerIssue: null,
    currentConsumers: ["consumer:documentation"], releaseReachability: "NONE",
    publicSurfaceReachability: [], assertionState: "REQUIRED_FINAL_PRODUCTION_BEHAVIOR",
    sensitivity: "INTERNAL", duplicateGroup: null, disposition: "RETAIN_CANONICAL",
    deletePrerequisite: [], supersedes: [], supersededBy: null, invalidatedBy: null,
    invalidationReason: null, invalidationEvidence: [], mutationPolicy: "CURRENT_STATE_WITH_CHANGE",
    reviewPolicyId: "EVENT_ONLY", reviewTrigger: ["event:change"],
    lastVerifiedAt: "2026-08-05T00:00:00.000Z", lastVerifiedIdentity: canonicalIdentity,
    verificationMethod: "contract-test", verificationEvidence: ["evidence:fixture"],
    nextReviewAtOrSemanticExpiry: null, implementationPlan: "PLAN-DOC", workloadClass: null,
    orchestrationProfile: null, stateClass: null, configurationDelivery: null,
    healthContract: null, availabilityContract: null, securityContract: null, releaseContract: null,
    portabilityOwner: null, portabilityEvidence: [], portabilityGap: [],
  };
}

function createDocumentationCatalogWorkspace({ activeIndexes = null } = {}) {
  const { directory, workspacePath } = createExternalWorkspace();
  const catalogPath = join(directory, "inputs/documentation-system-catalog.json");
  const catalog = loadJson(catalogPath);
  const active = activeIndexes ?? catalog.repositories.map((_, index) => index);
  const repositories = [];
  try {
    for (const [index, entry] of catalog.repositories.entries()) {
      if (!active.includes(index)) {
        entry.status = "PROPOSED";
        entry.fragment = null;
        continue;
      }
      const root = join(directory, `repository-${index}`);
      mkdirSync(join(root, "docs"), { recursive: true });
      for (const args of [["init"], ["config", "user.email", "test@example.com"], ["config", "user.name", "Test"]]) {
        fixtureGit(args, { cwd: root, stdio: "ignore" });
      }
      writeFileSync(join(root, "docs/resource.txt"), `resource-${index}\n`);
      fixtureGit(["add", "."], { cwd: root, stdio: "ignore" });
      fixtureGit(["commit", "-m", "inner"], { cwd: root, stdio: "ignore" });
      const innerSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
      const resourceBlob = fixtureGit(["rev-parse", "HEAD:docs/resource.txt"], { cwd: root, encoding: "utf8" }).trim();
      const resourceDigest = createHash("sha256").update(readFileSync(join(root, "docs/resource.txt"))).digest("hex");
      const resourceIdentity = index === 0 ? resourceBlob : resourceDigest;
      const fragment = {
        $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI, schemaVersion: 1,
        repository: entry.repository, sourceSha: innerSha, status: "ACTIVE",
        lastVerifiedAt: "2026-08-05T00:00:00.000Z", verificationEvidence: ["evidence:fixture"],
        resources: [documentationCatalogRecord(entry.repository, innerSha, resourceIdentity)],
      };
      writeFileSync(join(root, "docs/fragment.json"), JSON.stringify(fragment));
      fixtureGit(["add", "."], { cwd: root, stdio: "ignore" });
      fixtureGit(["commit", "-m", "outer"], { cwd: root, stdio: "ignore" });
      const outerSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
      const fragmentBlob = fixtureGit(["rev-parse", "HEAD:docs/fragment.json"], { cwd: root, encoding: "utf8" }).trim();
      entry.status = "ACTIVE";
      entry.fragment = {
        gitSha: outerSha, path: "docs/fragment.json", blobSha: index === 0
          ? fragmentBlob : createHash("sha256").update(readFileSync(join(root, "docs/fragment.json"))).digest("hex"),
        lastVerifiedAt: fragment.lastVerifiedAt, verificationEvidence: fragment.verificationEvidence,
      };
      repositories.push({ repository: entry.repository, root: realpathSync(root) });
    }
    writeFileSync(catalogPath, JSON.stringify(catalog));
    const fragmentWorkspacePath = join(directory, "documentation-fragment-workspace.json");
    writeFileSync(fragmentWorkspacePath, JSON.stringify({ schemaVersion: 1, repositories }));
    return { directory, workspacePath, fragmentWorkspacePath, catalogPath, repositories };
  } catch (error) {
    rmSync(directory, { recursive: true, force: true });
    throw error;
  }
}

function createSingleDocumentationCatalogWorkspace() {
  return createDocumentationCatalogWorkspace({ activeIndexes: [0] });
}

function documentationCatalogErrors(fixture) {
  return collectContractErrors(fixture.workspacePath, {
    documentationFragmentWorkspacePath: fixture.fragmentWorkspacePath,
  });
}

function assertDocumentationCatalogFailure(fixture, expected) {
  const errors = documentationCatalogErrors(fixture);
  assert.ok(errors.some((error) => error.includes(expected)), errors.join("\n"));
  for (const { root } of fixture.repositories) assert.ok(errors.every((error) => !error.includes(root)), errors.join("\n"));
}

function updateDocumentationCatalogWorkspace(fixture, mutate) {
  const workspace = loadJson(fixture.fragmentWorkspacePath);
  mutate(workspace);
  writeFileSync(fixture.fragmentWorkspacePath, JSON.stringify(workspace));
}

function commitDocumentationCatalogFragment(fixture, index, value, mutateCatalog = () => {}) {
  const root = fixture.repositories[index].root;
  writeFileSync(join(root, "docs/fragment.json"), value);
  fixtureGit(["add", "."], { cwd: root, stdio: "ignore" });
  fixtureGit(["commit", "-m", "mutate fragment"], { cwd: root, stdio: "ignore" });
  const catalog = loadJson(fixture.catalogPath);
  const fragment = catalog.repositories[index].fragment;
  fragment.gitSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
  fragment.blobSha = fixtureGit(["rev-parse", "HEAD:docs/fragment.json"], { cwd: root, encoding: "utf8" }).trim();
  mutateCatalog(catalog.repositories[index]);
  writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
}

function rebindDocumentationCatalogFragment(fixture, index, path, blobSha) {
  const root = fixture.repositories[index].root;
  const catalog = loadJson(fixture.catalogPath);
  catalog.repositories[index].fragment = {
    ...catalog.repositories[index].fragment,
    gitSha: fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim(),
    path,
    blobSha,
  };
  writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
}

function rewriteDocumentationFragmentInnerCommit(fragment, innerSha, resourcePath = "docs/resource.txt", blobSha = null) {
  const record = fragment.resources[0];
  const identity = blobSha ?? record.canonicalIdentity.split(":").at(-1);
  record.resource = `${fragment.repository}:${resourcePath}`;
  record.canonicalIdentity = `git:${innerSha}:${resourcePath}:${identity}`;
  record.lastVerifiedIdentity = record.canonicalIdentity;
  fragment.sourceSha = innerSha;
}

function documentationExternalRecord(record, resource) {
  const output = structuredClone(record);
  output.resource = resource;
  output.sourceSurface = "EXTERNAL";
  output.canonicalIdentity = `sha256:${"a".repeat(64)}`;
  output.lastVerifiedIdentity = output.canonicalIdentity;
  return output;
}

function commitDocumentationCatalogResources(fixture, index, mutate) {
  const root = fixture.repositories[index].root;
  const fragment = loadJson(join(root, "docs/fragment.json"));
  mutate(fragment.resources);
  commitDocumentationCatalogFragment(fixture, index, JSON.stringify(fragment));
}

test("documentation catalog resolves exact outer and inner Git blobs", () => {
  const fixture = createDocumentationCatalogWorkspace();
  try {
    assert.ok(collectContractErrors(fixture.workspacePath).some((error) => error.includes("workspace가 필요하다")));
    assert.deepEqual(collectContractErrors(fixture.workspacePath, {
      documentationFragmentWorkspacePath: fixture.fragmentWorkspacePath,
    }), []);

    const localWorkspace = loadJson(fixture.fragmentWorkspacePath);
    localWorkspace.repositories.pop();
    writeFileSync(fixture.fragmentWorkspacePath, JSON.stringify(localWorkspace));
    assert.ok(collectContractErrors(fixture.workspacePath, {
      documentationFragmentWorkspacePath: fixture.fragmentWorkspacePath,
    }).some((error) => error.includes("mapping")));
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test("documentation catalog accepts a source commit distinct from the outer fragment commit", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const fragment = loadJson(join(root, "docs/fragment.json"));
    const catalog = loadJson(fixture.catalogPath);
    assert.notEqual(fragment.sourceSha, catalog.repositories[0].fragment.gitSha);
    assert.deepEqual(documentationCatalogErrors(fixture), []);
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test("documentation catalog rejects current resource drift after source binding", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    writeFileSync(join(root, "docs/resource.txt"), "drifted-resource\n");
    fixtureGit(["add", "docs/resource.txt"], { cwd: root, stdio: "ignore" });
    fixtureGit(["commit", "-m", "drift resource"], { cwd: root, stdio: "ignore" });
    const catalog = loadJson(fixture.catalogPath);
    catalog.repositories[0].fragment.gitSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    catalog.repositories[0].fragment.blobSha = fixtureGit(["rev-parse", "HEAD:docs/fragment.json"], { cwd: root, encoding: "utf8" }).trim();
    writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    assertDocumentationCatalogFailure(fixture, "TRACKED resource current blob identity가 일치하지 않는다");
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test("documentation catalog rejects SHA-256 current resource drift after source binding", () => {
  const fixture = createDocumentationCatalogWorkspace({ activeIndexes: [1] });
  try {
    const [{ repository, root }] = fixture.repositories;
    const fragment = loadJson(join(root, "docs/fragment.json"));
    assert.equal(fragment.resources[0].canonicalIdentity.split(":").at(-1).length, 64);
    assert.deepEqual(documentationCatalogErrors(fixture), []);

    writeFileSync(join(root, "docs/resource.txt"), "drifted-sha256-resource\n");
    fixtureGit(["add", "docs/resource.txt"], { cwd: root, stdio: "ignore" });
    fixtureGit(["commit", "-m", "drift SHA-256 resource"], { cwd: root, stdio: "ignore" });
    const catalog = loadJson(fixture.catalogPath);
    const entry = catalog.repositories.find((candidate) => candidate.repository === repository);
    assert.ok(entry?.fragment);
    entry.fragment.gitSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    entry.fragment.blobSha = createHash("sha256").update(readFileSync(join(root, "docs/fragment.json"))).digest("hex");
    writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    assertDocumentationCatalogFailure(fixture, "TRACKED resource current blob identity가 일치하지 않는다");
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test("documentation catalog rejects schema-invalid fragment blobs without throwing", () => {
  const fixture = createDocumentationCatalogWorkspace();
  try {
    commitDocumentationCatalogFragment(fixture, 0, "null");
    const errors = collectContractErrors(fixture.workspacePath, {
      documentationFragmentWorkspacePath: fixture.fragmentWorkspacePath,
    });
    assert.ok(errors.some((error) => error.includes("documentation-fragment")), errors.join("\n"));
    assert.ok(errors.every((error) => !error.includes(fixture.repositories[0].root)));
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test("documentation catalog returns bounded malformed resource errors without throwing", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const fragment = loadJson(join(root, "docs/fragment.json"));
    fragment.resources = Array.from({ length: 256 }, () => ({}));
    commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    let errors;
    assert.doesNotThrow(() => { errors = documentationCatalogErrors(fixture); });
    assert.ok(errors.some((error) => error.includes("documentation-fragment resource")), errors.join("\n"));
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog rejects fragment resource arrays above 256 before item validation", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const fragment = loadJson(join(root, "docs/fragment.json"));
    fragment.resources = Array.from({ length: 257 }, () => ({}));
    commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    const errors = documentationCatalogErrors(fixture);
    assert.ok(errors.some((error) => error.includes("fragment resources는 256개 이하여야 한다")), errors.join("\n"));
    assert.ok(errors.every((error) => !error.includes("documentation-fragment resource")), errors.join("\n"));
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog limits the resource union across ACTIVE fragments", () => {
  const fixture = createDocumentationCatalogWorkspace({ activeIndexes: [0, 1] });
  try {
    for (const [repositoryIndex, count] of [128, 129].entries()) {
      const root = fixture.repositories[repositoryIndex].root;
      const fragment = loadJson(join(root, "docs/fragment.json"));
      const base = fragment.resources[0];
      fragment.resources = Array.from({ length: count }, (_, index) => {
        const record = documentationExternalRecord(base, `https://example.invalid/${repositoryIndex}/${String(index).padStart(3, "0")}`);
        record.canonicalIdentity = `sha256:${repositoryIndex}${index.toString(16).padStart(63, "0")}`;
        record.lastVerifiedIdentity = record.canonicalIdentity;
        return record;
      });
      if (repositoryIndex === 0) {
        fragment.resources[0] = documentationCatalogRecord(
          fragment.repository, fragment.sourceSha, "0".repeat(40), "docs/missing.txt",
        );
      }
      commitDocumentationCatalogFragment(fixture, repositoryIndex, JSON.stringify(fragment));
    }
    const errors = documentationCatalogErrors(fixture);
    assert.ok(errors.some((error) => error.includes("resources는 전체 256개 이하여야 한다")), errors.join("\n"));
    assert.ok(errors.every((error) => !error.includes("TRACKED resource source blob identity")), errors.join("\n"));
    assert.ok(errors.every((error) => !error.includes("TRACKED resource current blob identity")), errors.join("\n"));
    assert.ok(errors.every((error) => !error.includes("ACTIVE fragment relation")), errors.join("\n"));
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog rejects oversized nested arrays before schema validation", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const fragment = loadJson(join(root, "docs/fragment.json"));
    fragment.resources[0].currentConsumers = Array.from({ length: 257 }, (_, index) => `consumer:${index}`);
    commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    assertDocumentationCatalogFailure(fixture, "fragment 배열은 256개 항목 이하여야 한다");
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog rejects reversed local workspace mappings", () => {
  const fixture = createDocumentationCatalogWorkspace();
  try {
    const localWorkspace = loadJson(fixture.fragmentWorkspacePath);
    localWorkspace.repositories.reverse();
    writeFileSync(fixture.fragmentWorkspacePath, JSON.stringify(localWorkspace));
    assert.ok(collectContractErrors(fixture.workspacePath, {
      documentationFragmentWorkspacePath: fixture.fragmentWorkspacePath,
    }).some((error) => error.includes("mapping")));
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test("documentation catalog rejects ACTIVE null fragment without throwing", () => {
  const fixture = createDocumentationCatalogWorkspace();
  try {
    const catalog = loadJson(fixture.catalogPath);
    catalog.repositories[0].fragment = null;
    writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    const errors = collectContractErrors(fixture.workspacePath, {
      documentationFragmentWorkspacePath: fixture.fragmentWorkspacePath,
    });
    assert.ok(errors.some((error) => error.includes("ACTIVE fragment가 필요하다")), errors.join("\n"));
    assert.ok(errors.every((error) => !error.includes(fixture.repositories[0].root)));
  } finally {
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test("documentation catalog ignores inherited hostile Git environment", () => {
  const fixture = createDocumentationCatalogWorkspace();
  const hostile = {
    GIT_DIR: join(fixture.directory, "not-a-git-dir"),
    GIT_OBJECT_DIRECTORY: join(fixture.directory, "not-an-object-directory"),
    GIT_CONFIG_COUNT: "1",
    GIT_CONFIG_KEY_0: "core.hooksPath",
    GIT_CONFIG_VALUE_0: join(fixture.directory, "not-a-hook-directory"),
    GIT_GLOB_PATHSPECS: "1",
  };
  const previous = Object.fromEntries(Object.keys(hostile).map((key) => [key, process.env[key]]));
  try {
    Object.assign(process.env, hostile);
    assert.deepEqual(collectContractErrors(fixture.workspacePath, {
      documentationFragmentWorkspacePath: fixture.fragmentWorkspacePath,
    }), []);
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    rmSync(fixture.directory, { recursive: true, force: true });
  }
});

test("documentation catalog uses workspace-selected fragment schemas and sanitizes schema failures", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const contracts = join(fixture.directory, "selected-contracts");
    cpSync("contracts", contracts, { recursive: true });
    cpSync("README.md", join(fixture.directory, "README.md"));
    initializeHubInventoryFixtureRepository(fixture.directory);
    const workspace = loadJson(fixture.workspacePath);
    workspace.contracts = "selected-contracts";
    writeFileSync(fixture.workspacePath, JSON.stringify(workspace));
    assert.deepEqual(documentationCatalogErrors(fixture), []);

    const fragmentSchemaPath = join(contracts, "documentation/documentation-fragment.schema.json");
    const resourceSchemaPath = join(contracts, "documentation/documentation-resource.schema.json");
    const originalFragmentSchema = readFileSync(fragmentSchemaPath);
    const originalResourceSchema = readFileSync(resourceSchemaPath);
    const unsupportedFragmentSchema = { ...loadJson(fragmentSchemaPath), unsupportedKeyword: true };
    const unsupportedResourceSchema = { ...loadJson(resourceSchemaPath), unsupportedKeyword: true };
    for (const [schemaPath, value, expected] of [
      [fragmentSchemaPath, null, "fragment schema를 읽을 수 없다"],
      [fragmentSchemaPath, "{", "fragment schema를 읽을 수 없다"],
      [fragmentSchemaPath, "null", "fragment schema가 유효하지 않다"],
      [fragmentSchemaPath, JSON.stringify(unsupportedFragmentSchema), "fragment schema가 유효하지 않다"],
      [resourceSchemaPath, JSON.stringify(unsupportedResourceSchema), "fragment schema가 유효하지 않다"],
    ]) {
      writeFileSync(fragmentSchemaPath, originalFragmentSchema);
      writeFileSync(resourceSchemaPath, originalResourceSchema);
      if (value === null) rmSync(schemaPath);
      else writeFileSync(schemaPath, value);
      let errors;
      assert.doesNotThrow(() => { errors = documentationCatalogErrors(fixture); });
      assert.ok(errors.some((error) => error.includes(expected)), errors.join("\n"));
      assert.ok(errors.every((error) => !error.includes(schemaPath)), errors.join("\n"));
    }
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog fixtures ignore hostile global Git config", () => {
  const directory = mkdtempSync(join(tmpdir(), "documentation-git-config-"));
  const configPath = join(directory, "global-config");
  const previous = process.env.GIT_CONFIG_GLOBAL;
  writeFileSync(configPath, "[");
  try {
    process.env.GIT_CONFIG_GLOBAL = configPath;
    const fixture = createSingleDocumentationCatalogWorkspace();
    try { assert.deepEqual(documentationCatalogErrors(fixture), []); }
    finally { rmSync(fixture.directory, { recursive: true, force: true }); }
  } finally {
    if (previous === undefined) delete process.env.GIT_CONFIG_GLOBAL;
    else process.env.GIT_CONFIG_GLOBAL = previous;
    rmSync(directory, { recursive: true, force: true });
  }
});

test("documentation catalog rejects malformed and drifting local workspace mappings", () => {
  const cases = [
    ["malformed JSON", (fixture) => writeFileSync(fixture.fragmentWorkspacePath, "{"), "유효한 local workspace JSON"],
    ["invalid shape", (fixture) => writeFileSync(fixture.fragmentWorkspacePath, JSON.stringify({ schemaVersion: 2, repositories: [] })), "shape"],
    ["relative root", (fixture) => updateDocumentationCatalogWorkspace(fixture, (workspace) => { workspace.repositories[0].root = "relative"; }), "mapping"],
    ["duplicate mapping", (fixture) => updateDocumentationCatalogWorkspace(fixture, (workspace) => { workspace.repositories.push(structuredClone(workspace.repositories[0])); }), "mapping"],
    ["unknown mapping", (fixture) => updateDocumentationCatalogWorkspace(fixture, (workspace) => { workspace.repositories[0].repository = "unknown/repository"; }), "mapping"],
    ["missing mapping", (fixture) => updateDocumentationCatalogWorkspace(fixture, (workspace) => { workspace.repositories.pop(); }), "mapping"],
  ];
  for (const [, mutate, expected] of cases) {
    const fixture = createDocumentationCatalogWorkspace();
    try {
      mutate(fixture);
      assertDocumentationCatalogFailure(fixture, expected);
    } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
  }
});

test("documentation catalog rejects unsafe Git roots and missing outer objects without local path leaks", () => {
  const cases = [
    ["non-Git root", (fixture) => {
      const root = join(fixture.directory, "not-a-git-root");
      mkdirSync(root);
      updateDocumentationCatalogWorkspace(fixture, (workspace) => { workspace.repositories[0].root = root; });
    }, "Git root"],
    ["nested root", (fixture) => {
      const root = join(fixture.repositories[0].root, "nested");
      mkdirSync(root);
      updateDocumentationCatalogWorkspace(fixture, (workspace) => { workspace.repositories[0].root = root; });
    }, "Git root"],
    ["symlink root", (fixture) => {
      const link = join(fixture.directory, "root-link");
      symlinkSync(fixture.repositories[0].root, link);
      updateDocumentationCatalogWorkspace(fixture, (workspace) => { workspace.repositories[0].root = link; });
    }, "Git root"],
    ["missing outer SHA", (fixture) => {
      const catalog = loadJson(fixture.catalogPath);
      catalog.repositories[0].fragment.gitSha = "f".repeat(40);
      writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    }, "fragment blob"],
    ["missing outer path", (fixture) => {
      const catalog = loadJson(fixture.catalogPath);
      catalog.repositories[0].fragment.path = "docs/missing.json";
      writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    }, "fragment blob"],
  ];
  for (const [, mutate, expected] of cases) {
    const fixture = createDocumentationCatalogWorkspace();
    try {
      mutate(fixture);
      assertDocumentationCatalogFailure(fixture, expected);
    } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
  }
});

test("documentation catalog treats metacharacter paths literally and rejects malformed fragment bytes", () => {
  const fixture = createDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const fragment = loadJson(join(root, "docs/fragment.json"));
    const metacharacterPath = "docs/[fragment]*?.json";
    writeFileSync(join(root, metacharacterPath), JSON.stringify(fragment));
    fixtureGit(["add", "."], { cwd: root, stdio: "ignore" });
    fixtureGit(["commit", "-m", "literal path"], { cwd: root, stdio: "ignore" });
    const catalog = loadJson(fixture.catalogPath);
    catalog.repositories[0].fragment.gitSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    catalog.repositories[0].fragment.path = metacharacterPath;
    catalog.repositories[0].fragment.blobSha = fixtureGit(["rev-parse", `HEAD:${metacharacterPath}`], { cwd: root, encoding: "utf8" }).trim();
    writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    assert.deepEqual(documentationCatalogErrors(fixture), []);
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }

  for (const [label, value, expected] of [
    ["invalid UTF-8", Buffer.from([0xc3, 0x28]), "fragment JSON"],
    ["invalid JSON", "{", "fragment JSON"],
    ["schema invalid", "null", "documentation-fragment"],
  ]) {
    const invalid = createDocumentationCatalogWorkspace();
    try {
      commitDocumentationCatalogFragment(invalid, 0, value);
      assertDocumentationCatalogFailure(invalid, expected);
    } finally { rmSync(invalid.directory, { recursive: true, force: true }); }
  }
});

test("documentation catalog rejects fragment header and TRACKED identity drift", () => {
  const cases = [
    ["SHA-1 fragment identity", (fixture) => {
      const catalog = loadJson(fixture.catalogPath);
      catalog.repositories[0].fragment.blobSha = "0".repeat(40);
      writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    }, "fragment blob identity"],
    ["SHA-256 fragment identity", (fixture) => {
      const catalog = loadJson(fixture.catalogPath);
      catalog.repositories[1].fragment.blobSha = "0".repeat(64);
      writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    }, "fragment blob identity"],
    ["repository header", (fixture) => {
      const root = fixture.repositories[0].root;
      const fragment = loadJson(join(root, "docs/fragment.json"));
      fragment.repository = fixture.repositories[1].repository;
      commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    }, "invalid ownerRepository"],
    ["status header", (fixture) => {
      const root = fixture.repositories[0].root;
      const fragment = loadJson(join(root, "docs/fragment.json"));
      fragment.status = "PROPOSED";
      commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    }, "catalog fragment header"],
    ["lastVerifiedAt header", (fixture) => {
      const root = fixture.repositories[0].root;
      const fragment = loadJson(join(root, "docs/fragment.json"));
      fragment.lastVerifiedAt = "2026-08-06T00:00:00.000Z";
      commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    }, "catalog fragment header"],
    ["verificationEvidence header", (fixture) => {
      const root = fixture.repositories[0].root;
      const fragment = loadJson(join(root, "docs/fragment.json"));
      fragment.verificationEvidence = ["evidence:other"];
      commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    }, "catalog fragment header"],
    ["TRACKED resource SHA-1", (fixture) => {
      const root = fixture.repositories[0].root;
      const fragment = loadJson(join(root, "docs/fragment.json"));
      fragment.resources[0].canonicalIdentity = fragment.resources[0].canonicalIdentity.replace(/:[0-9a-f]{40}$/, `:${"0".repeat(40)}`);
      fragment.resources[0].lastVerifiedIdentity = fragment.resources[0].canonicalIdentity;
      commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    }, "TRACKED resource source blob identity"],
    ["TRACKED resource SHA-256", (fixture) => {
      const root = fixture.repositories[1].root;
      const fragment = loadJson(join(root, "docs/fragment.json"));
      fragment.resources[0].canonicalIdentity = fragment.resources[0].canonicalIdentity.replace(/:[0-9a-f]{64}$/, `:${"0".repeat(64)}`);
      fragment.resources[0].lastVerifiedIdentity = fragment.resources[0].canonicalIdentity;
      commitDocumentationCatalogFragment(fixture, 1, JSON.stringify(fragment));
    }, "TRACKED resource source blob identity"],
  ];
  for (const [, mutate, expected] of cases) {
    const fixture = createDocumentationCatalogWorkspace();
    try {
      mutate(fixture);
      assertDocumentationCatalogFailure(fixture, expected);
    } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
  }
});

test("documentation catalog accepts TRACKED resources larger than the default child-process buffer", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const resourcePath = join(root, "docs/resource.txt");
    writeFileSync(resourcePath, "x".repeat(1024 * 1024 + 1));
    fixtureGit(["add", "docs/resource.txt"], { cwd: root, stdio: "ignore" });
    fixtureGit(["commit", "-m", "large resource"], { cwd: root, stdio: "ignore" });
    const innerSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    const blobSha = fixtureGit(["rev-parse", "HEAD:docs/resource.txt"], { cwd: root, encoding: "utf8" }).trim();
    const fragment = loadJson(join(root, "docs/fragment.json"));
    rewriteDocumentationFragmentInnerCommit(fragment, innerSha, "docs/resource.txt", blobSha);
    commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    assert.deepEqual(documentationCatalogErrors(fixture), []);
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog enforces the explicit 64 MiB blob limit", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const resourcePath = join(root, "docs/resource.txt");
    const bindResource = (size) => {
      const bytes = Buffer.alloc(size, "x");
      writeFileSync(resourcePath, bytes);
      fixtureGit(["add", "docs/resource.txt"], { cwd: root, stdio: "ignore" });
      fixtureGit(["commit", "-m", `resource ${size}`], { cwd: root, stdio: "ignore" });
      const innerSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
      const blobSha = fixtureGit(["rev-parse", "HEAD:docs/resource.txt"], { cwd: root, encoding: "utf8" }).trim();
      const fragment = loadJson(join(root, "docs/fragment.json"));
      fragment.resources = [fragment.resources[0]];
      rewriteDocumentationFragmentInnerCommit(fragment, innerSha, "docs/resource.txt", blobSha);
      commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
      return createHash("sha256").update(bytes).digest("hex");
    };

    const largeDigest = bindResource(64 * 1024 * 1024);
    assert.deepEqual(documentationCatalogErrors(fixture), []);

    const smallBytes = Buffer.from("y");
    writeFileSync(join(root, "docs/small.txt"), smallBytes);
    fixtureGit(["add", "docs/small.txt"], { cwd: root, stdio: "ignore" });
    fixtureGit(["commit", "-m", "aggregate digest payload"], { cwd: root, stdio: "ignore" });
    const innerSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    const fragment = loadJson(join(root, "docs/fragment.json"));
    fragment.sourceSha = innerSha;
    fragment.resources = [
      documentationCatalogRecord(fragment.repository, innerSha, largeDigest),
      documentationCatalogRecord(
        fragment.repository,
        innerSha,
        createHash("sha256").update(smallBytes).digest("hex"),
        "docs/small.txt",
      ),
    ];
    commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    assertDocumentationCatalogFailure(fixture, "TRACKED resource SHA-256 payload 합계는 64 MiB 이하여야 한다");

    bindResource(64 * 1024 * 1024 + 1);
    assertDocumentationCatalogFailure(fixture, "TRACKED resource blob은 64 MiB 이하여야 한다");
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog enforces the 1 MiB fragment JSON limit before parsing", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const fragment = JSON.stringify(loadJson(join(root, "docs/fragment.json")));
    commitDocumentationCatalogFragment(fixture, 0, fragment.padEnd(1024 * 1024, " "));
    assert.deepEqual(documentationCatalogErrors(fixture), []);
    commitDocumentationCatalogFragment(fixture, 0, fragment.padEnd(1024 * 1024 + 1, " "));
    assertDocumentationCatalogFailure(fixture, "fragment blob은 1 MiB 이하여야 한다");
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog does not validate global relations after a fragment transport failure", () => {
  const fixture = createDocumentationCatalogWorkspace();
  try {
    const fragment = loadJson(join(fixture.repositories[0].root, "docs/fragment.json"));
    fragment.status = "PROPOSED";
    commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    commitDocumentationCatalogResources(fixture, 1, (records) => { records[0] = documentationExternalRecord(records[0], "external:duplicate"); });
    commitDocumentationCatalogResources(fixture, 2, (records) => { records[0] = documentationExternalRecord(records[0], "external:duplicate"); });
    const errors = documentationCatalogErrors(fixture);
    assert.ok(errors.some((error) => error.includes("catalog fragment header 불일치")), errors.join("\n"));
    assert.ok(errors.every((error) => !error.includes("ACTIVE fragment relation")), errors.join("\n"));
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog validates global relations across two ACTIVE fragments", () => {
  const cases = [
    ["duplicate resource", (fixture) => {
      commitDocumentationCatalogResources(fixture, 0, (records) => { records[0] = documentationExternalRecord(records[0], "external:duplicate"); });
      commitDocumentationCatalogResources(fixture, 1, (records) => { records[0] = documentationExternalRecord(records[0], "external:duplicate"); });
    }],
    ["invalid duplicate group", (fixture) => {
      commitDocumentationCatalogResources(fixture, 0, (records) => { records[0] = documentationExternalRecord(records[0], "external:solo"); records[0].duplicateGroup = "group:solo"; });
    }],
    ["missing supersession reciprocal", (fixture) => {
      commitDocumentationCatalogResources(fixture, 0, (records) => { records[0] = documentationExternalRecord(records[0], "external:old"); records[0].status = "SUPERSEDED"; records[0].supersededBy = "external:new"; });
      commitDocumentationCatalogResources(fixture, 1, (records) => { records[0] = documentationExternalRecord(records[0], "external:new"); });
    }],
    ["missing invalidation reciprocal", (fixture) => {
      commitDocumentationCatalogResources(fixture, 0, (records) => {
        records[0] = documentationExternalRecord(records[0], "external:invalidated");
        Object.assign(records[0], { resourceClass: "EVIDENCE", status: "INVALIDATED", invalidatedBy: "external:replacement", invalidationReason: "reason:test", invalidationEvidence: ["evidence:test"], mutationPolicy: "EVIDENCE_IMMUTABLE", releaseReachability: "EVIDENCE", currentConsumers: ["evidence:test"] });
      });
      commitDocumentationCatalogResources(fixture, 1, (records) => { records[0] = documentationExternalRecord(records[0], "external:replacement"); });
    }],
    ["supersession cycle", (fixture) => {
      commitDocumentationCatalogResources(fixture, 0, (records) => { records[0] = documentationExternalRecord(records[0], "external:a"); records[0].status = "SUPERSEDED"; records[0].supersededBy = "external:b"; records[0].supersedes = ["external:b"]; });
      commitDocumentationCatalogResources(fixture, 1, (records) => { records[0] = documentationExternalRecord(records[0], "external:b"); records[0].status = "SUPERSEDED"; records[0].supersededBy = "external:a"; records[0].supersedes = ["external:a"]; });
    }],
  ];
  for (const [, mutate] of cases) {
    const fixture = createDocumentationCatalogWorkspace({ activeIndexes: [0, 1] });
    try {
      mutate(fixture);
      assertDocumentationCatalogFailure(fixture, "ACTIVE fragment relation");
    } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
  }

  const valid = createDocumentationCatalogWorkspace({ activeIndexes: [0, 1] });
  try {
    commitDocumentationCatalogResources(valid, 0, (records) => { records[0] = documentationExternalRecord(records[0], "external:old"); records[0].status = "SUPERSEDED"; records[0].supersededBy = "external:new"; });
    commitDocumentationCatalogResources(valid, 1, (records) => { records[0] = documentationExternalRecord(records[0], "external:new"); records[0].supersedes = ["external:old"]; });
    assert.deepEqual(documentationCatalogErrors(valid), []);
  } finally { rmSync(valid.directory, { recursive: true, force: true }); }
});

test("documentation catalog rejects non-blob outer fragment paths", () => {
  const cases = [
    ["symlink", (fixture) => {
      const root = fixture.repositories[0].root;
      rmSync(join(root, "docs/fragment.json"));
      symlinkSync("resource.txt", join(root, "docs/fragment.json"));
      fixtureGit(["add", "-A"], { cwd: root, stdio: "ignore" });
      fixtureGit(["commit", "-m", "symlink fragment"], { cwd: root, stdio: "ignore" });
      rebindDocumentationCatalogFragment(fixture, 0, "docs/fragment.json", "0".repeat(40));
    }],
    ["tree", (fixture) => {
      const root = fixture.repositories[0].root;
      rebindDocumentationCatalogFragment(fixture, 0, "docs", "0".repeat(40));
    }],
    ["gitlink", (fixture) => {
      const root = fixture.repositories[0].root;
      rmSync(join(root, "docs/fragment.json"));
      fixtureGit(["rm", "--cached", "docs/fragment.json"], { cwd: root, stdio: "ignore" });
      fixtureGit(["update-index", "--add", "--cacheinfo", `160000,${"1".repeat(40)},docs/fragment.json`], { cwd: root, stdio: "ignore" });
      fixtureGit(["commit", "-m", "gitlink fragment"], { cwd: root, stdio: "ignore" });
      rebindDocumentationCatalogFragment(fixture, 0, "docs/fragment.json", "0".repeat(40));
    }],
  ];
  for (const [, mutate] of cases) {
    const fixture = createSingleDocumentationCatalogWorkspace();
    try {
      mutate(fixture);
      assertDocumentationCatalogFailure(fixture, "fragment blob");
    } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
  }
});

test("documentation catalog rejects missing and non-ancestor inner commits", () => {
  const cases = [
    ["missing", (fixture) => {
      const root = fixture.repositories[0].root;
      const fragment = loadJson(join(root, "docs/fragment.json"));
      rewriteDocumentationFragmentInnerCommit(fragment, "f".repeat(40));
      commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    }],
    ["non-ancestor", (fixture) => {
      const root = fixture.repositories[0].root;
      const innerSha = fixtureGit(["commit-tree", "HEAD^{tree}", "-m", "orphan inner"], { cwd: root, encoding: "utf8" }).trim();
      const fragment = loadJson(join(root, "docs/fragment.json"));
      rewriteDocumentationFragmentInnerCommit(fragment, innerSha);
      commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
    }],
    ["grafted non-ancestor", (fixture) => {
      const root = fixture.repositories[0].root;
      const innerSha = fixtureGit(["commit-tree", "HEAD^{tree}", "-m", "grafted inner"], { cwd: root, encoding: "utf8" }).trim();
      const fragment = loadJson(join(root, "docs/fragment.json"));
      rewriteDocumentationFragmentInnerCommit(fragment, innerSha);
      commitDocumentationCatalogFragment(fixture, 0, JSON.stringify(fragment));
      const outerSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
      mkdirSync(join(root, ".git/info"), { recursive: true });
      writeFileSync(join(root, ".git/info/grafts"), `${outerSha} ${innerSha}\n`);
    }],
  ];
  for (const [, mutate] of cases) {
    const fixture = createSingleDocumentationCatalogWorkspace();
    try {
      mutate(fixture);
      assertDocumentationCatalogFailure(fixture, "inner commit relation");
    } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
  }
});

test("documentation catalog rejects missing and symlink TRACKED resources", () => {
  const missing = createSingleDocumentationCatalogWorkspace();
  try {
    const root = missing.repositories[0].root;
    const fragment = loadJson(join(root, "docs/fragment.json"));
    rewriteDocumentationFragmentInnerCommit(fragment, fragment.sourceSha, "docs/missing.txt", "0".repeat(40));
    commitDocumentationCatalogFragment(missing, 0, JSON.stringify(fragment));
    assertDocumentationCatalogFailure(missing, "TRACKED resource source blob identity");
  } finally { rmSync(missing.directory, { recursive: true, force: true }); }

  const symlink = createSingleDocumentationCatalogWorkspace();
  try {
    const root = symlink.repositories[0].root;
    rmSync(join(root, "docs/resource.txt"));
    symlinkSync("fragment.json", join(root, "docs/resource.txt"));
    fixtureGit(["add", "-A"], { cwd: root, stdio: "ignore" });
    fixtureGit(["commit", "-m", "symlink resource inner"], { cwd: root, stdio: "ignore" });
    const innerSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    const fragment = loadJson(join(root, "docs/fragment.json"));
    rewriteDocumentationFragmentInnerCommit(fragment, innerSha);
    commitDocumentationCatalogFragment(symlink, 0, JSON.stringify(fragment));
    assertDocumentationCatalogFailure(symlink, "TRACKED resource source blob identity");
  } finally { rmSync(symlink.directory, { recursive: true, force: true }); }
});

test("documentation catalog ignores local Git replacement objects", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const goodOuter = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    const goodBlob = fixtureGit(["rev-parse", "HEAD:docs/fragment.json"], { cwd: root, encoding: "utf8" }).trim();
    writeFileSync(join(root, "docs/fragment.json"), "null");
    fixtureGit(["add", "."], { cwd: root, stdio: "ignore" });
    fixtureGit(["commit", "-m", "bad outer"], { cwd: root, stdio: "ignore" });
    const badOuter = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    fixtureGit(["replace", badOuter, goodOuter], { cwd: root, stdio: "ignore" });
    const catalog = loadJson(fixture.catalogPath);
    catalog.repositories[0].fragment.gitSha = badOuter;
    catalog.repositories[0].fragment.blobSha = goodBlob;
    writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    assertDocumentationCatalogFailure(fixture, "fragment blob identity");
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog rejects SHA-256 Git roots when local Git supports them", (t) => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = join(fixture.directory, "sha256-root");
    try {
      fixtureGit(["init", "--object-format=sha256", root], { encoding: "utf8", stdio: "pipe" });
    } catch (error) {
      t.skip(`fixed /usr/bin/git init --object-format=sha256 unavailable: ${error instanceof Error ? error.message : String(error)}`);
      return;
    }
    updateDocumentationCatalogWorkspace(fixture, (workspace) => { workspace.repositories[0].root = realpathSync(root); });
    assertDocumentationCatalogFailure(fixture, "Git root");
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog CLI accepts compatibility modes and rejects malformed optional pairs", () => {
  const run = (args, cwd = process.cwd()) => execFileSync(process.execPath, [resolve("tools/ci/check-contracts.mjs"), ...args], {
    cwd, encoding: "utf8", stdio: "pipe",
  });
  const proposed = createExternalWorkspace();
  try {
    assert.doesNotThrow(() => run(["--workspace", proposed.workspacePath, "--current-only"]));
    assert.doesNotThrow(() => run([
      "--workspace", proposed.workspacePath, "--current-only", "--local-contracts-only",
    ]));
  } finally { rmSync(proposed.directory, { recursive: true, force: true }); }

  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const valid = ["--workspace", fixture.workspacePath, "--current-only", "--documentation-fragment-workspace", fixture.fragmentWorkspacePath];
    assert.doesNotThrow(() => run(valid));
    assert.doesNotThrow(() => run([
      "--workspace", fixture.workspacePath, "--current-only", "--local-contracts-only",
    ]));
    const clone = mkdtempSync(join(tmpdir(), "documentation-catalog-cli-"));
    try {
      const copied = join(clone, "fixture");
      mkdirSync(copied);
      cpSync("contracts", join(clone, "contracts"), { recursive: true });
      cpSync("README.md", join(clone, "README.md"));
      for (const name of ["hub.json", "inputs", "gates"]) cpSync(join(fixture.directory, name), join(copied, name), { recursive: true });
      mkdirSync(join(clone, "release/migrations"), { recursive: true });
      cpSync("release/migrations/repository-split-issues.json", join(clone, "release/migrations/repository-split-issues.json"));
      cpSync("release/migrations/repository-contraction-inventory.json", join(clone, "release/migrations/repository-contraction-inventory.json"));
      cpSync("release/migrations/repository-split-issues-amendments.json", join(clone, "release/migrations/repository-split-issues-amendments.json"));
      initializeHubInventoryFixtureRepository(clone);
      const clonedWorkspacePath = join(copied, "hub.json");
      const clonedWorkspace = loadJson(clonedWorkspacePath);
      clonedWorkspace.contracts = "../contracts";
      writeFileSync(clonedWorkspacePath, JSON.stringify(clonedWorkspace));
      fixtureGit(["add", "fixture"], { cwd: clone, stdio: "ignore" });
      fixtureGit(["commit", "-m", "CLI fixture"], { cwd: clone, stdio: "ignore" });
      const baseRef = fixtureGit(["rev-parse", "HEAD"], { cwd: clone, encoding: "utf8" }).trim();
      assert.doesNotThrow(() => run([
        "--workspace", "fixture/hub.json", "--base-ref", baseRef,
        "--documentation-fragment-workspace", fixture.fragmentWorkspacePath,
      ], clone));
    } finally { rmSync(clone, { recursive: true, force: true }); }
    for (const args of [
      valid.slice(0, -1),
      ["--workspace", fixture.workspacePath, "--documentation-fragment-workspace", fixture.fragmentWorkspacePath, "--current-only"],
      [...valid, "--documentation-fragment-workspace", fixture.fragmentWorkspacePath],
      [...valid, "--local-contracts-only"],
      ["--workspace", fixture.workspacePath, "--base-ref", "a".repeat(40), "--local-contracts-only"],
      ["--workspace", fixture.workspacePath, "--current-only", "--documentation-fragment-workspace", "--local-contracts-only"],
      [...valid, "extra"],
    ]) assert.throws(() => run(args), /사용법/);
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("documentation catalog redacts real Git object diagnostics", () => {
  const fixture = createSingleDocumentationCatalogWorkspace();
  try {
    const root = fixture.repositories[0].root;
    const marker = "RAW-FRAGMENT-BYTES-MUST-NOT-LEAK";
    writeFileSync(join(root, "docs/fragment.json"), marker);
    fixtureGit(["add", "."], { cwd: root, stdio: "ignore" });
    fixtureGit(["commit", "-m", "bad bytes"], { cwd: root, stdio: "ignore" });
    const badSha = fixtureGit(["rev-parse", "HEAD"], { cwd: root, encoding: "utf8" }).trim();
    const catalog = loadJson(fixture.catalogPath);
    catalog.repositories[0].fragment.gitSha = badSha;
    catalog.repositories[0].fragment.blobSha = "0".repeat(40);
    writeFileSync(fixture.catalogPath, JSON.stringify(catalog));
    const errors = documentationCatalogErrors(fixture).join("\n");
    assert.match(errors, /fragment blob identity/);
    for (const secret of [root, badSha, marker]) assert.ok(!errors.includes(secret), errors);
  } finally { rmSync(fixture.directory, { recursive: true, force: true }); }
});

test("[gate-ownership] workspace는 legacy 경로 밖 복사 입력을 검증한다", () => {
  const { directory, workspacePath } = createExternalWorkspace();
  try {
    assert.deepEqual(collectContractErrors(workspacePath), []);
    const externalIndexPath = join(directory, "inputs/datapack-index.json");
    const externalIndex = loadJson(externalIndexPath);
    externalIndex.builtAt = "2026-02-31T00:00:00.000Z";
    writeFileSync(externalIndexPath, JSON.stringify(externalIndex));

    assert.ok(
      collectContractErrors(workspacePath).some((error) => error.includes("builtAt은 유효한 UTC 시각이어야 한다")),
      "외부 workspace datapack index의 semantic 검증이 필요하다",
    );
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("[gate-ownership] workspace는 필수 키 누락을 fail closed한다", () => {
  const directory = mkdtempSync(join(tmpdir(), "gate-ownership-workspace-"));
  try {
    const workspacePath = join(directory, "hub.json");
    writeFileSync(workspacePath, JSON.stringify({
      contracts: "contracts",
      gateDirectories: { hub: "release/product-gates", mobile: "apps/mobile/release" },
      datapackIndex: "apps/mobile/assets/datapacks/index.json",
      sourceInventory: "apps/mobile/assets/datapacks/source-inventory.json",
      governancePolicy: "tools/datapack/source-governance-policy.json",
    }));

    assert.throws(() => loadWorkspace(workspacePath), /freshnessPolicy/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("[gate-ownership] check-contracts CLI는 정확한 workspace 인자만 허용한다", () => {
  const run = (args) => execFileSync(process.execPath, ["tools/ci/check-contracts.mjs", ...args], {
    encoding: "utf8",
    stdio: "pipe",
  });

  const { directory, workspacePath } = createExternalWorkspace();
  try {
    assert.doesNotThrow(() => run(["--workspace", workspacePath, "--current-only"]));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
  for (const args of [
    [],
    ["--workspace"],
    ["--workspace", "contracts/workspaces/hub.json"],
    ["--workspace", "contracts/workspaces/hub.json", "--current-only", "extra"],
    ["--unexpected", "--workspace", "contracts/workspaces/hub.json"],
    ["--workspace", "contracts/workspaces/hub.json", "--workspace", "contracts/workspaces/hub.json"],
  ]) {
    assert.throws(() => run(args), /사용법/);
  }
});

test("product claim catalog validates current release decision and public claim semantics", () => {
  const schema = loadJson("contracts/documentation/product-claim-catalog.schema.json");
  const catalog = loadJson("contracts/documentation/product-claim-catalog.json");
  const errors = [];
  validateProductClaimCatalog(catalog, schema, errors, {
    releaseDecision: loadJson("release/product-gates/production-datapack-scope.json"),
    forbiddenClaims: loadJson("release/product-gates/forbidden-release-claims.json"),
  });
  assert.deepEqual(errors, []);

  const invalid = structuredClone(catalog);
  invalid.releaseDecision = "GO";
  invalid.claims.find(({ assertionState }) => assertionState === "CURRENTLY_IMPLEMENTED_AND_EVIDENCED").requiredEvidence = [];
  const invalidErrors = [];
  validateProductClaimCatalog(invalid, schema, invalidErrors, {
    releaseDecision: loadJson("release/product-gates/production-datapack-scope.json"),
    forbiddenClaims: loadJson("release/product-gates/forbidden-release-claims.json"),
  });
  assert.ok(invalidErrors.some((error) => error.includes("releaseDecision")));
  assert.ok(invalidErrors.some((error) => error.includes("requiredEvidence")));

  const schemaInvalid = structuredClone(catalog);
  schemaInvalid.unexpected = true;
  const schemaErrors = [];
  validateProductClaimCatalog(schemaInvalid, schema, schemaErrors, {
    releaseDecision: loadJson("release/product-gates/production-datapack-scope.json"),
    forbiddenClaims: loadJson("release/product-gates/forbidden-release-claims.json"),
  });
  assert.ok(schemaErrors.some((error) => error.includes("허용되지 않은 필드")));
});

for (const [name, mutate, expected] of [
  ["required inventory deletion", (catalog) => { catalog.claims = catalog.claims.filter(({ claimId }) => claimId !== "PRODUCT_CLAIM_VISION"); }, "inventory"],
  ["required inventory addition", (catalog) => { catalog.claims.push({ ...structuredClone(catalog.claims.at(-1)), claimId: "PRODUCT_CLAIM_EXTRA", topic: "VISION" }); }, "inventory"],
  ["required inventory topic binding", (catalog) => { catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_VISION").topic = "PRIVACY"; }, "inventory"],
  ["duplicate claim ID", (catalog) => { catalog.claims[1].claimId = catalog.claims[0].claimId; }, "claimId"],
  ["unsorted claim ID", (catalog) => { [catalog.claims[0], catalog.claims[1]] = [catalog.claims[1], catalog.claims[0]]; }, "claimId"],
  ["duplicate surface", (catalog) => { catalog.claims[0].surface = ["README.md", "README.md"]; }, "surface"],
  ["unsorted review trigger", (catalog) => { catalog.claims[0].reviewTrigger = ["z", "a"]; }, "reviewTrigger"],
  ["final state on current surface", (catalog) => { catalog.claims[0].assertionState = "HISTORICAL_OR_SUPERSEDED"; }, "current public"],
  ["required-final current surface", (catalog) => { catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_JOURNEY_FINAL").surface = ["README.md"]; }, "required-final"],
  ["README scan target drift", (catalog, forbiddenClaims) => { forbiddenClaims.scanTargets = forbiddenClaims.scanTargets.filter(({ path }) => path !== "README.md"); }, "README.md scan target"],
  ["non-array README scan target", (catalog, forbiddenClaims) => { forbiddenClaims.scanTargets = "README.md"; }, "README.md scan target"],
  ["null or primitive README scan target", (catalog, forbiddenClaims) => { forbiddenClaims.scanTargets = [null, "README.md"]; }, "README.md scan target"],
]) {
  test(`product claim catalog rejects ${name}`, () => {
    const catalog = structuredClone(loadJson("contracts/documentation/product-claim-catalog.json"));
    const forbiddenClaims = loadJson("release/product-gates/forbidden-release-claims.json");
    mutate(catalog, forbiddenClaims);
    const errors = [];
    validateProductClaimCatalog(catalog, loadJson("contracts/documentation/product-claim-catalog.schema.json"), errors, {
      releaseDecision: loadJson("release/product-gates/production-datapack-scope.json"),
      forbiddenClaims,
    });
    assert.ok(errors.some((error) => error.includes(expected)));
  });
}

test("product claim catalog rejects empty forbiddenWhen", () => {
  const catalog = structuredClone(loadJson("contracts/documentation/product-claim-catalog.json"));
  const claim = catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_ANONYMOUS_REPORT");
  claim.forbiddenWhen = [];
  const errors = [];
  validateProductClaimCatalog(catalog, loadJson("contracts/documentation/product-claim-catalog.schema.json"), errors, {
    releaseDecision: loadJson("release/product-gates/production-datapack-scope.json"),
    forbiddenClaims: loadJson("release/product-gates/forbidden-release-claims.json"),
  });
  assert.ok(errors.some((error) => error.includes("forbiddenWhen")));
});

for (const field of ["requiredEvidence", "forbiddenWhen", "reviewTrigger"]) {
  test(`product claim catalog rejects duplicate ${field}`, () => {
    const catalog = structuredClone(loadJson("contracts/documentation/product-claim-catalog.json"));
    const claim = catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_ANONYMOUS_REPORT");
    claim[field] = [claim[field][0], claim[field][0]];
    const errors = [];
    validateProductClaimCatalog(catalog, loadJson("contracts/documentation/product-claim-catalog.schema.json"), errors, {
      releaseDecision: loadJson("release/product-gates/production-datapack-scope.json"),
      forbiddenClaims: loadJson("release/product-gates/forbidden-release-claims.json"),
    });
    assert.ok(errors.some((error) => error.includes(field)));
  });

  test(`product claim catalog rejects unsorted ${field}`, () => {
    const catalog = structuredClone(loadJson("contracts/documentation/product-claim-catalog.json"));
    catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_ANONYMOUS_REPORT")[field] = ["z", "a"];
    const errors = [];
    validateProductClaimCatalog(catalog, loadJson("contracts/documentation/product-claim-catalog.schema.json"), errors, {
      releaseDecision: loadJson("release/product-gates/production-datapack-scope.json"),
      forbiddenClaims: loadJson("release/product-gates/forbidden-release-claims.json"),
    });
    assert.ok(errors.some((error) => error.includes(field)));
  });
}

for (const [name, mutate, expected] of [
  ["top-level GO does not leave NO_GO claim and README", (catalog) => {}, "release-status claim decision token"],
  ["GO claim does not leave NO_GO README", (catalog) => { catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_RELEASE_STATUS").copyKo = "현재 출시 결정은 GO입니다."; }, "README.md decision token"],
  ["missing release-status claim token", (catalog) => { catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_RELEASE_STATUS").copyKo = "현재 출시 결정을 확인합니다."; }, "release-status claim decision token"],
  ["multiple release-status claim tokens", (catalog) => { catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_RELEASE_STATUS").copyKo = "GO와 NO_GO를 함께 쓰지 않습니다."; }, "release-status claim decision token"],
  ["opposite release-status claim token", (catalog) => {}, "release-status claim decision token"],
  ["missing README decision token", (catalog, readme) => { readme.text = "현재 출시 결정을 확인합니다."; }, "README.md decision token"],
  ["multiple README decision tokens", (catalog, readme) => { readme.text = "GO와 NO_GO를 함께 쓰지 않습니다."; }, "README.md decision token"],
  ["opposite README decision token", (catalog, readme) => { catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_RELEASE_STATUS").copyKo = "현재 출시 결정은 GO입니다."; readme.text = "현재 출시 결정은 NO_GO입니다."; }, "README.md decision token"],
]) {
  test(`product claim catalog rejects ${name}`, () => {
    const catalog = structuredClone(loadJson("contracts/documentation/product-claim-catalog.json"));
    const readme = { text: readFileSync("README.md", "utf8") };
    catalog.releaseDecision = "GO";
    const releaseDecision = loadJson("release/product-gates/production-datapack-scope.json");
    releaseDecision.decision.currentLaunchDecision = "GO";
    mutate(catalog, readme);
    const errors = [];
    validateProductClaimCatalog(catalog, loadJson("contracts/documentation/product-claim-catalog.schema.json"), errors, {
      releaseDecision,
      forbiddenClaims: loadJson("release/product-gates/forbidden-release-claims.json"),
      publicCopy: readme.text,
    });
    assert.ok(errors.some((error) => error.includes(expected)));
  });
}

test("product claim catalog accepts matching GO release-status tokens", () => {
  const catalog = structuredClone(loadJson("contracts/documentation/product-claim-catalog.json"));
  catalog.releaseDecision = "GO";
  catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_RELEASE_STATUS").copyKo = "현재 출시 결정은 GO입니다.";
  const releaseDecision = loadJson("release/product-gates/production-datapack-scope.json");
  releaseDecision.decision.currentLaunchDecision = "GO";
  const errors = [];
  validateProductClaimCatalog(catalog, loadJson("contracts/documentation/product-claim-catalog.schema.json"), errors, {
    releaseDecision,
    forbiddenClaims: loadJson("release/product-gates/forbidden-release-claims.json"),
    publicCopy: "현재 출시 결정은 GO입니다.",
  });
  assert.deepEqual(errors, []);
});

test("product claim catalog reads the workspace README public surface", () => {
  const { directory, workspacePath } = createExternalWorkspace();
  try {
    const catalogPath = join(directory, "inputs/product-claim-catalog.json");
    const catalog = loadJson(catalogPath);
    catalog.releaseDecision = "GO";
    catalog.claims.find(({ claimId }) => claimId === "PRODUCT_CLAIM_RELEASE_STATUS").copyKo = "현재 출시 결정은 GO입니다.";
    writeFileSync(catalogPath, JSON.stringify(catalog));
    const releaseDecisionPath = join(directory, "gates/hub/production-datapack-scope.json");
    const releaseDecision = loadJson(releaseDecisionPath);
    releaseDecision.decision.currentLaunchDecision = "GO";
    writeFileSync(releaseDecisionPath, JSON.stringify(releaseDecision));

    assert.ok(collectContractErrors(workspacePath).some((error) => error.includes("README.md decision token")));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

for (const [label, filename, mutate] of [
  ["production-datapack-scope", "production-datapack-scope.json", (path) => rmSync(path)],
  ["production-datapack-scope", "production-datapack-scope.json", (path) => writeFileSync(path, "{")],
  ["production-datapack-scope", "production-datapack-scope.json", (path) => writeFileSync(path, "[]")],
  ["forbidden-release-claims", "forbidden-release-claims.json", (path) => rmSync(path)],
  ["forbidden-release-claims", "forbidden-release-claims.json", (path) => writeFileSync(path, "{")],
  ["forbidden-release-claims", "forbidden-release-claims.json", (path) => writeFileSync(path, "[]")],
]) {
  test(`product claim catalog sanitizes invalid ${label} input`, () => {
    const { directory, workspacePath } = createExternalWorkspace();
    try {
      mutate(join(directory, "gates/hub", filename));
      let errors;
      assert.doesNotThrow(() => { errors = collectContractErrors(workspacePath); });
      assert.ok(errors.some((error) => error.includes(`product-claim-catalog: ${label} input이 유효한 JSON object여야 한다`)));
      assert.ok(errors.every((error) => !error.includes(directory)));
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
}

test("repository split issue migration ledger가 계약 gate를 통과한다", () => {
  const errors = collectContractErrors().filter((error) => error.includes("repository-split-issues"));

  assert.deepEqual(errors, []);
});

test("repository contraction inventory가 계약 gate를 통과한다", () => {
  const errors = collectContractErrors().filter((error) => error.includes("repository-contraction-inventory"));

  assert.deepEqual(errors, []);
});

test("repository contraction inventory는 ownership, handoff state, mixed selector를 강제한다", () => {
  const inventory = loadJson("release/migrations/repository-contraction-inventory.json");
  assert.deepEqual(validateRepositoryContractionInventory(inventory), []);

  const target = inventory.entries.find((entry) => entry.classification === "TARGET_CANONICAL_DELETE_AFTER_HANDOFF");
  const retained = inventory.entries.find((entry) => entry.classification === "HUB_SYSTEM_OWNER_RETAIN");
  const duplicate = inventory.entries.find((entry) => entry.classification === "DUPLICATE_GATE_DISABLE_AFTER_TARGET");
  assert.ok(target, "TARGET_CANONICAL_DELETE_AFTER_HANDOFF entry가 필요하다");
  assert.ok(retained, "HUB_SYSTEM_OWNER_RETAIN entry가 필요하다");
  assert.ok(duplicate, "DUPLICATE_GATE_DISABLE_AFTER_TARGET entry가 필요하다");
  const forbiddenFallbackIds = [
    "backend-ci-build", "data-ci-producer", "mobile-ci-build", "platform-ci-deploy",
    "data-datapack-release", "mobile-release-artifacts", "backend-docker-image",
    "backend-raw-main-v1-stage", "data-previous-artifact-contract",
    "backend-source", "data-source", "mobile-source", "platform-infra", "platform-deploy-tools",
  ];
  for (const resourceId of forbiddenFallbackIds) {
    assert.equal(inventory.entries.find((entry) => entry.resourceId === resourceId)?.fallbackExposure, "FORBIDDEN_ACTIVE", resourceId);
  }
  for (const resourceId of [
    "hub-automerge-queue", "hub-release-artifacts-bundled-datapack", "hub-rc-datapack-selector",
    "hub-manifest-emergency-override", "hub-rc-evidence-fallback-artifact", "hub-admin-qa-upload-warn",
  ]) {
    const entry = inventory.entries.find((candidate) => candidate.resourceId === resourceId);
    assert.ok(entry, `${resourceId} entry가 필요하다`);
    assert.deepEqual(
      [entry.classification, entry.repository, entry.hubOwner, entry.targetOwner, entry.plannedAction,
        entry.executionEligibility, entry.fallbackExposure, entry.fallbackRemovalOwner, entry.fallbackVerificationState],
      ["HUB_FALLBACK_REMOVE", "AquilaXk/easysubway", "hub", null, "REMOVE_FALLBACK", false,
        "FORBIDDEN_ACTIVE", "hub", "PLANNED"],
      resourceId,
    );
  }

  for (const [mutate, expected] of [
    [(candidate) => { candidate.targetOwner = "mobile"; }, "targetOwner 불일치"],
    [(candidate) => { candidate.handoffEvidence = []; }, "handoff evidence가 필요하다"],
    [(candidate) => { candidate.activeConsumers = []; }, "active consumer가 필요하다"],
    [(candidate) => { candidate.plannedAction = "RETAIN"; }, "plannedAction 불일치"],
    [(candidate) => { candidate.executionEligibility = true; }, "PENDING은 execution-eligible일 수 없다"],
    [(candidate) => {
      const other = inventory.entries.find((entry) => entry.resourceId !== candidate.resourceId);
      assert.ok(other, "중복 대상으로 사용할 다른 entry가 필요하다");
      candidate.resourceId = other.resourceId;
    }, "resourceId 중복"],
  ]) {
    const candidate = structuredClone(inventory);
    mutate(candidate.entries.find((entry) => entry.resourceId === target.resourceId));
    assert.ok(validateRepositoryContractionInventory(candidate).some((error) => error.includes(expected)), expected);
  }

  const retainDelete = structuredClone(inventory);
  retainDelete.entries.find((entry) => entry.resourceId === retained.resourceId).plannedAction = "DELETE_AFTER_HANDOFF";
  assert.ok(validateRepositoryContractionInventory(retainDelete).some((error) => error.includes("plannedAction 불일치")));

  const verifiedWithoutEvidence = structuredClone(inventory);
  const verifiedTarget = verifiedWithoutEvidence.entries.find((entry) => entry.resourceId === target.resourceId);
  verifiedTarget.handoffState = "VERIFIED";
  verifiedTarget.handoffEvidence = [];
  assert.ok(validateRepositoryContractionInventory(verifiedWithoutEvidence)
    .some((error) => error.includes("VERIFIED handoff evidence가 필요하다")));

  const historical = structuredClone(retained);
  historical.resourceId = "historical-fixture";
  historical.classification = "HISTORICAL_ARCHIVE_NONEXECUTABLE";
  historical.plannedAction = "ARCHIVE_NONEXECUTABLE";
  historical.releaseReachability = "CURRENT";
  historical.activeConsumers = ["current validator"];
  const historicalErrors = validateRepositoryContractionInventory({ ...inventory, entries: [...inventory.entries, historical] });
  assert.ok(historicalErrors.some((error) => error.includes("current-reachable")));
  assert.ok(historicalErrors.some((error) => error.includes("active consumer가 있을 수 없다")));

  const missingSelector = structuredClone(inventory);
  missingSelector.entries.find((entry) => entry.resourceId === duplicate.resourceId).selector = null;
  assert.ok(validateRepositoryContractionInventory(missingSelector).some((error) => error.includes("mixed path selector가 필요하다")));

  const forbiddenFallback = inventory.entries.find((entry) => entry.resourceId === "backend-raw-main-v1-stage");
  for (const [mutate, expected] of [
    [(candidate) => { candidate.handoffState = "VERIFIED"; }, "FORBIDDEN_ACTIVE은 handoff VERIFIED일 수 없다"],
    [(candidate) => { candidate.executionEligibility = true; }, "FORBIDDEN_ACTIVE은 execution-eligible일 수 없다"],
    [(candidate) => { candidate.fallbackRemovalOwner = null; }, "fallback removal owner가 필요하다"],
    [(candidate) => { candidate.fallbackExposure = "NONE"; }, "known fallback은 FORBIDDEN_ACTIVE여야 한다"],
    [(candidate) => { candidate.fallbackVerification = ["https://github.com/AquilaXk/easysubway/issues/2731"]; }, "executable test/gate identifier"],
    [(candidate) => { candidate.fallbackVerificationState = "VERIFIED"; }, "fallback verification은 PLANNED"],
  ]) {
    const candidate = structuredClone(inventory);
    mutate(candidate.entries.find((entry) => entry.resourceId === forbiddenFallback.resourceId));
    assert.ok(validateRepositoryContractionInventory(candidate).some((error) => error.includes(expected)), expected);
  }

  const hubFallback = inventory.entries.find((entry) => entry.resourceId === "hub-automerge-queue");
  assert.ok(hubFallback, "hub-automerge-queue entry가 필요하다");
  for (const [mutate, expected] of [
    [(candidate) => { candidate.fallbackExposure = "NONE"; }, "known fallback은 FORBIDDEN_ACTIVE여야 한다"],
    [(candidate) => { candidate.fallbackRemovalOwner = null; }, "fallback removal owner가 필요하다"],
  ]) {
    const candidate = structuredClone(inventory);
    mutate(candidate.entries.find((entry) => entry.resourceId === hubFallback.resourceId));
    assert.ok(validateRepositoryContractionInventory(candidate).some((error) => error.includes(expected)), expected);
  }

  const retainHandoff = structuredClone(inventory);
  retainHandoff.entries.find((entry) => entry.resourceId === retained.resourceId).handoffState = "VERIFIED";
  assert.ok(validateRepositoryContractionInventory(retainHandoff).some((error) => error.includes("NOT_APPLICABLE")));

  const blankSelector = structuredClone(inventory);
  blankSelector.entries.find((entry) => entry.resourceId === duplicate.resourceId).selector = " ";
  assert.ok(validateRepositoryContractionInventory(blankSelector).some((error) => error.includes("selector는 비어 있을 수 없다")));

  const invalidRollback = structuredClone(inventory);
  const rollback = invalidRollback.entries.find((entry) => entry.resourceId === retained.resourceId);
  rollback.fallbackExposure = "VERIFIED_ROLLBACK_ONLY";
  rollback.fallbackVerificationState = "VERIFIED";
  rollback.fallbackVerification = ["https://github.com/AquilaXk/easysubway/issues/2731"];
  rollback.rollbackMode = "NOT_APPLICABLE";
  rollback.rollbackRevision = null;
  assert.ok(validateRepositoryContractionInventory(invalidRollback)
    .some((error) => error.includes("Platform deployment rollback approval")));

  const invalidHubRetain = structuredClone(inventory);
  invalidHubRetain.entries.find((entry) => entry.resourceId === retained.resourceId).fallbackExposure = "FORBIDDEN_ACTIVE";
  assert.ok(validateRepositoryContractionInventory(invalidHubRetain)
    .some((error) => error.includes("HUB_SYSTEM_OWNER_RETAIN은 fallbackExposure NONE")));

  const invalidExtractionRepository = structuredClone(inventory);
  invalidExtractionRepository.entries.find((entry) => entry.resourceId === "backend-realtime-fallback").repository = "AquilaXk/easysubway-mobile";
  assert.ok(validateRepositoryContractionInventory(invalidExtractionRepository)
    .some((error) => error.includes("repository/targetOwner extraction mapping 불일치")));

  const duplicateFallbackGate = structuredClone(inventory);
  const activeFallbacks = duplicateFallbackGate.entries.filter((entry) => entry.fallbackExposure === "FORBIDDEN_ACTIVE");
  activeFallbacks[1].fallbackVerification = [...activeFallbacks[0].fallbackVerification];
  assert.ok(validateRepositoryContractionInventory(duplicateFallbackGate)
    .some((error) => error.includes("verification identifier 중복")));
});

test("repository contraction inventory는 #2731 P1 fallback required-set과 폐쇄형 handoff를 강제한다", () => {
  const inventory = loadJson("release/migrations/repository-contraction-inventory.json");
  const requiredFallbacks = [
    ["backend-realtime-fallback", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/application/service/RouteSearchService.java", "POST_SCAN_REALTIME_FALLBACK_REASON"],
    ["backend-planner-fallback", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/application/service/RouteSearchService.java", "Legacy graph fallback"],
    ["backend-stale-fallback", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/application/service/RouteSearchService.java", "STALE_FALLBACK"],
    ["backend-static-fallback", "AquilaXk/easysubway-backend", "tools/routes/check-route-commercialization-gate.mjs", "STATIC_BACKEND_ESTIMATE"],
    ["backend-raw-main-contract", "AquilaXk/easysubway-backend", "backend/tools/stage-contracts.mjs", "raw.githubusercontent.com/AquilaXk/easysubway/main"],
    ["data-rollback-fallback", "AquilaXk/easysubway-data", "tools/datapack/rollback-manifest.mjs", "rollback manifest"],
    ["mobile-local-fallback", "AquilaXk/easysubway-mobile", "apps/mobile/lib/features/routes/data/local_route_repository.dart", "offline/local fallback repository"],
    ["mobile-v1-fallback", "AquilaXk/easysubway-mobile", "apps/mobile/lib/route_search.dart", "Route V1 fallback"],
    ["mobile-v2-fallback", "AquilaXk/easysubway-mobile", "apps/mobile/lib/route_search.dart", "Route V2 fallback"],
    ["platform-raw-main-fallback", "AquilaXk/easysubway-platform", "tools/platform/stage-contracts.mjs", "raw.githubusercontent.com/AquilaXk/easysubway/main"],
    ["platform-legacy-restore-fallback", "AquilaXk/easysubway-platform", "tools/deploy/deploy-backend.sh", "restore_legacy_backend_service"],
    ["platform-legacy-credential-fallback", "AquilaXk/easysubway-platform", "tools/deploy/prepare-deployment-env.sh", "legacy_pepper"],
    ["hub-admin-qa-upload-warn", "AquilaXk/easysubway", ".github/workflows/ci.yml", "Admin QA upload continue-on-error and if-no-files-found warn"],
    ["hub-automerge-queue", "AquilaXk/easysubway", ".github/workflows/automerge-queue.yml", null],
    ["hub-release-artifacts-bundled-datapack", "AquilaXk/easysubway", ".github/workflows/release-artifacts.yml", "missing datapack run uses bundled index and capital artifact"],
    ["hub-rc-datapack-selector", "AquilaXk/easysubway", "tools/release/select-rc-datapack-artifact.mjs", "fallback.sqlite.gz selection and copy"],
    ["hub-manifest-emergency-override", "AquilaXk/easysubway", "tools/datapack/lib/manifest-validation.mjs", "emergencyOverride fallback pack selection"],
    ["hub-rc-evidence-fallback-artifact", "AquilaXk/easysubway", "tools/release/generate-rc-evidence-manifest.mjs", "data-pack fallback artifact requirement"],
    ["backend-topis-fixture-fallback", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/realtime/application/TopisRealtimeProvider.java", "fixtureEnabled fallbackProvider"],
    ["backend-realtime-overlay-fallback", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/domain/RealtimeEtaOverlay.java", "PLANNED EtaSource.FALLBACK"],
    ["backend-v2-planner-legacy-graph", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/application/service/RouteV2Planner.java", "legacy graph"],
    ["backend-route-controller-v1-refresh", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/adapter/in/web/RouteSearchController.java", "api/v1 LEGACY_STATIC refresh"],
    ["backend-timetable-seed-last-known-good", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/adapter/out/persistence/TimetableSeedLoader.java", "last-known-good snapshot"],
    ["backend-jdbc-timetable-break-glass", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/adapter/out/persistence/JdbcRouteTimetableRepository.java", "breakGlass freshness filter"],
    ["backend-timetable-monitor-break-glass", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/route/adapter/out/persistence/TimetableFreshnessMonitor.java", "break-glass expired snapshot"],
    ["backend-transit-master-static-empty", "AquilaXk/easysubway-backend", "backend/src/main/java/com/easysubway/transit/adapter/out/persistence/JdbcTransitMasterOverrideRepository.java", "static-seed Optional.empty DataAccess"],
    ["data-itx-historical-previous", "AquilaXk/easysubway-data", "tools/datapack/apply-itx-topology-to-bundled-pack.mjs", "UNCHANGED_AUTO previousArtifactPath"],
    ["data-build-previous-artifact-chain", "AquilaXk/easysubway-data", "tools/datapack/build-datapack.mjs", "previous artifact chain"],
    ["data-manifest-emergency-latest-capital", "AquilaXk/easysubway-data", "tools/datapack/lib/manifest-validation.mjs", "emergencyOverride latest capital"],
    ["data-coverage-active-default-capital", "AquilaXk/easysubway-data", "tools/datapack/report-coverage-gaps.mjs", "active default capital"],
    ["data-release-first-pack", "AquilaXk/easysubway-data", "tools/ci/datapack-release-workflow.test.mjs", "packs[0]"],
    ["data-molit-edge-sample", "AquilaXk/easysubway-data", "tools/datapack/build-molit-nationwide-fixture.mjs", "edge-sample"],
    ["data-public-api-static-planned", "AquilaXk/easysubway-data", "tools/datapack/collect-nationwide-public-api-coverage.mjs", "STATIC_LOCAL PLANNED"],
    ["mobile-dependencies-local-first", "AquilaXk/easysubway-mobile", "apps/mobile/lib/app/app_dependencies.dart", "LocalFirst flag"],
    ["mobile-bootstrap-local-route", "AquilaXk/easysubway-mobile", "apps/mobile/lib/app/app_bootstrap.dart", "LocalRouteRepository"],
    ["mobile-route-search-refresh", "AquilaXk/easysubway-mobile", "apps/mobile/lib/route_search.dart", "V1 V2 refresh"],
    ["mobile-route-v2-transport-scoped", "AquilaXk/easysubway-mobile", "apps/mobile/lib/route_v2_ingress.dart", "TransportScoped"],
    ["mobile-internal-route-local", "AquilaXk/easysubway-mobile", "apps/mobile/lib/features/internal_route/data/local_internal_route_repository.dart", "local internal route"],
    ["mobile-catalog-known-good-bundled", "AquilaXk/easysubway-mobile", "apps/mobile/lib/core/database/catalog/catalog_database_opener.dart", "known-good bundled"],
    ["mobile-pack-update-corrupt-default", "AquilaXk/easysubway-mobile", "apps/mobile/lib/core/datapack/data_pack_update_state.dart", "corrupted-policy default"],
    ["platform-ci-raw-main", "AquilaXk/easysubway-platform", ".github/workflows/ci.yml", "raw.githubusercontent.com/AquilaXk/easysubway/main"],
    ["platform-contract-lock-raw-main", "AquilaXk/easysubway-platform", "contracts.lock.json", "raw.githubusercontent.com/AquilaXk/easysubway/main"],
    ["platform-compose-route-v2-gateway", "AquilaXk/easysubway-platform", "infra/docker-compose.yml", "route-v2-gateway"],
  ];
  for (const [resourceId, repository, path, selector] of requiredFallbacks) {
    const entry = inventory.entries.find((candidate) => candidate.resourceId === resourceId);
    assert.deepEqual([entry?.repository, entry?.path, entry?.selector], [repository, path, selector], resourceId);
    if (repository !== "AquilaXk/easysubway") {
      assert.equal(entry?.classification, "TARGET_FALLBACK_REMOVE", resourceId);
      assert.equal(entry?.plannedAction, "REMOVE_FALLBACK", resourceId);
    }
  }
  const schema = loadJson("contracts/repository-contraction-inventory.schema.json");
  for (const entry of inventory.entries) {
    assert.deepEqual(
      [entry.rollbackTargetRepository, entry.rollbackApprovalEvidence, entry.rollbackOperation],
      [null, null, "NOT_APPLICABLE"],
      `${entry.resourceId}: rollback closed fields`,
    );
  }
  const missingRollbackField = structuredClone(inventory);
  delete missingRollbackField.entries[0].rollbackOperation;
  assert.ok(validateSchema(schema, missingRollbackField).errors.some((error) => error.includes("rollbackOperation")));
  const uppercaseRollbackRevision = structuredClone(inventory);
  uppercaseRollbackRevision.entries[0].rollbackRevision = "A".repeat(40);
  assert.ok(validateSchema(schema, uppercaseRollbackRevision).errors.some((error) => error.includes("rollbackRevision")));

  const missing = structuredClone(inventory);
  missing.entries = missing.entries.filter((entry) => entry.resourceId !== "hub-automerge-queue");
  assert.ok(validateRepositoryContractionInventory(missing).some((error) => error.includes("known fallback required-set 누락")));

  const duplicateEvidence = structuredClone(inventory);
  const handoff = duplicateEvidence.entries.find((entry) => entry.resourceId === "backend-ci-build");
  handoff.handoffState = "VERIFIED";
  handoff.handoffEvidence = [
    { kind: "IMMUTABLE_TARGET", reference: "https://github.com/AquilaXk/easysubway-backend/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", conclusion: "NOT_APPLICABLE" },
    { kind: "IMMUTABLE_TARGET", reference: "https://github.com/AquilaXk/easysubway-backend/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", conclusion: "NOT_APPLICABLE" },
    { kind: "TARGET_CONSUMER", reference: "https://github.com/AquilaXk/easysubway-backend/blob/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/.github/workflows/release.yml", identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", conclusion: "NOT_APPLICABLE" },
    { kind: "TARGET_TERMINAL_GATE", reference: "https://github.com/AquilaXk/easysubway-backend/actions/runs/1", identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", conclusion: "SUCCESS" },
    { kind: "SYSTEM_TERMINAL_GATE", reference: "https://github.com/AquilaXk/easysubway/actions/runs/1", identity: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", conclusion: "SUCCESS" },
  ];
  assert.ok(validateRepositoryContractionInventory(duplicateEvidence).some((error) => error.includes("handoff evidence kind 중복")));

  const invalidBase = structuredClone(inventory);
  invalidBase.inventoryBaseHead = "0000000000000000000000000000000000000000";
  assert.ok(validateRepositoryContractionInventory(invalidBase).some((error) => error.includes("HEAD ancestor")));

  const invalidRollback = structuredClone(inventory);
  const rollback = invalidRollback.entries.find((entry) => entry.resourceId === "hub-system-boundaries");
  rollback.fallbackExposure = "VERIFIED_ROLLBACK_ONLY";
  rollback.fallbackVerificationState = "VERIFIED";
  rollback.fallbackVerification = ["PLATFORM_MANUAL_DEPLOYMENT_ROLLBACK"];
  rollback.rollbackMode = "EXACT_IMMUTABLE_DEPLOYMENT_ONLY";
  rollback.rollbackRevision = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  rollback.rollbackTargetRepository = "AquilaXk/easysubway-data";
  rollback.rollbackApprovalEvidence = "https://github.com/AquilaXk/easysubway-data/issues/1";
  rollback.rollbackOperation = "MANUAL_DEPLOYMENT";
  assert.ok(validateRepositoryContractionInventory(invalidRollback).some((error) => error.includes("deployment rollback")));
  for (const rejected of ["data restore", "artifact restore", "source restore", "legacy restore"]) {
    const candidate = structuredClone(invalidRollback);
    candidate.entries.find((entry) => entry.resourceId === rollback.resourceId).targetOutput = rejected;
    assert.ok(validateRepositoryContractionInventory(candidate).some((error) => error.includes("deployment rollback")), rejected);
  }
});

test("repository contraction inventory는 expiry alert duplicate gate handoff를 폐쇄형으로 강제한다", () => {
  const inventory = loadJson("release/migrations/repository-contraction-inventory.json");
  const entry = inventory.entries.find((candidate) => candidate.resourceId === "data-datapack-expiry-alert");
  assert.deepEqual(
    [entry?.repository, entry?.path, entry?.selector, entry?.classification, entry?.targetOwner, entry?.plannedAction,
      entry?.fallbackExposure, entry?.fallbackRemovalOwner, entry?.fallbackVerification, entry?.fallbackVerificationState],
    ["AquilaXk/easysubway", ".github/workflows/datapack-expiry-alert.yml", "scheduled/manual expiry alert jobs and Slack notification",
      "DUPLICATE_GATE_DISABLE_AFTER_TARGET", "data", "DISABLE_AFTER_TARGET", "NONE", null, [], "NOT_APPLICABLE"],
  );

  const missing = structuredClone(inventory);
  missing.entries = missing.entries.filter((candidate) => candidate.resourceId !== entry.resourceId);
  assert.ok(validateRepositoryContractionInventory(missing).some((error) => error.includes("known duplicate gate required-set 누락")));

  const renamed = structuredClone(inventory);
  renamed.entries.find((candidate) => candidate.resourceId === entry.resourceId).selector = "renamed";
  assert.ok(validateRepositoryContractionInventory(renamed).some((error) => error.includes("known duplicate gate exact repository/path/selector 불일치")));

  const fallbackMisclassification = structuredClone(inventory);
  const fallback = fallbackMisclassification.entries.find((candidate) => candidate.resourceId === entry.resourceId);
  fallback.classification = "TARGET_FALLBACK_REMOVE";
  fallback.plannedAction = "REMOVE_FALLBACK";
  assert.ok(validateRepositoryContractionInventory(fallbackMisclassification)
    .some((error) => error.includes("known duplicate gate classification/target/action 불일치")));

  const revision = "c".repeat(40);
  const verified = () => ({
    ...structuredClone(entry),
    handoffState: "VERIFIED",
    executionEligibility: true,
    handoffEvidence: [
      { kind: "IMMUTABLE_TARGET", reference: `https://github.com/AquilaXk/easysubway-data/commit/${revision}`, identity: revision, conclusion: "NOT_APPLICABLE" },
      { kind: "TARGET_CONSUMER", reference: `https://github.com/AquilaXk/easysubway-data/blob/${revision}/.github/workflows/datapack-expiry-alert.yml`, identity: revision, conclusion: "NOT_APPLICABLE" },
      { kind: "TARGET_TERMINAL_GATE", reference: "https://github.com/AquilaXk/easysubway-data/actions/runs/1", identity: revision, conclusion: "SUCCESS" },
      { kind: "SYSTEM_TERMINAL_GATE", reference: "https://github.com/AquilaXk/easysubway/actions/runs/2", identity: revision, conclusion: "SUCCESS" },
      { kind: "TARGET_SCHEDULED_GATE", reference: "https://github.com/AquilaXk/easysubway-data/actions/runs/3", identity: revision, conclusion: "SUCCESS" },
      { kind: "TARGET_MANUAL_GATE", reference: "https://github.com/AquilaXk/easysubway-data/actions/runs/4", identity: revision, conclusion: "SUCCESS" },
      { kind: "TARGET_NOTIFICATION_EVIDENCE", reference: "https://github.com/AquilaXk/easysubway-data/actions/runs/3/artifacts/6", identity: revision, conclusion: "SUCCESS" },
    ],
  });
  const fullyVerified = structuredClone(inventory);
  Object.assign(fullyVerified.entries.find((candidate) => candidate.resourceId === entry.resourceId), verified());
  assert.deepEqual(validateRepositoryContractionInventory(fullyVerified), []);

  for (const [mutate, expected] of [
    [(candidate) => { candidate.handoffEvidence = candidate.handoffEvidence.filter((item) => item.kind !== "TARGET_SCHEDULED_GATE"); }, "scheduled/manual/notification evidence"],
    [(candidate) => { candidate.handoffEvidence = candidate.handoffEvidence.filter((item) => item.kind !== "TARGET_MANUAL_GATE"); }, "scheduled/manual/notification evidence"],
    [(candidate) => { candidate.handoffEvidence = candidate.handoffEvidence.filter((item) => item.kind !== "TARGET_NOTIFICATION_EVIDENCE"); }, "scheduled/manual/notification evidence"],
    [(candidate) => { candidate.handoffEvidence.push(structuredClone(candidate.handoffEvidence.find((item) => item.kind === "TARGET_SCHEDULED_GATE"))); }, "handoff evidence kind 중복"],
    [(candidate) => { candidate.handoffEvidence.find((item) => item.kind === "TARGET_MANUAL_GATE").conclusion = "FAILURE"; }, "scheduled/manual/notification evidence"],
    [(candidate) => { candidate.handoffEvidence.find((item) => item.kind === "TARGET_SCHEDULED_GATE").reference = "https://github.com/AquilaXk/easysubway/actions/runs/3"; }, "scheduled/manual/notification evidence"],
    [(candidate) => { candidate.handoffEvidence.find((item) => item.kind === "TARGET_MANUAL_GATE").reference = "https://github.com/AquilaXk/easysubway-data/actions/runs/3"; }, "scheduled/manual/notification evidence"],
    [(candidate) => { candidate.handoffEvidence.find((item) => item.kind === "TARGET_NOTIFICATION_EVIDENCE").identity = "d".repeat(40); }, "scheduled/manual/notification evidence"],
    [(candidate) => { candidate.handoffEvidence.find((item) => item.kind === "TARGET_NOTIFICATION_EVIDENCE").reference = "https://github.com/AquilaXk/easysubway-data/actions/runs/5"; }, "scheduled/manual/notification evidence"],
    [(candidate) => { candidate.handoffEvidence.find((item) => item.kind === "TARGET_NOTIFICATION_EVIDENCE").reference = "https://github.com/AquilaXk/easysubway-data/actions/runs/5/artifacts/6"; }, "scheduled/manual/notification evidence"],
  ]) {
    const candidate = structuredClone(fullyVerified);
    mutate(candidate.entries.find((item) => item.resourceId === entry.resourceId));
    assert.ok(validateRepositoryContractionInventory(candidate).some((error) => error.includes(expected)), expected);
  }

  const fakeTypedEvidence = structuredClone(inventory);
  fakeTypedEvidence.entries.find((candidate) => candidate.resourceId === "backend-ci-build").handoffEvidence.push(
    { kind: "TARGET_SCHEDULED_GATE", reference: "https://github.com/AquilaXk/easysubway-data/actions/runs/7", identity: revision, conclusion: "SUCCESS" },
  );
  assert.ok(validateRepositoryContractionInventory(fakeTypedEvidence)
    .some((error) => error.includes("data-datapack-expiry-alert에만 허용된다")));
});

test("repository contraction inventory는 F3 terminal gate와 예약된 F4 Platform rollback binding을 강제한다", () => {
  const inventory = loadJson("release/migrations/repository-contraction-inventory.json");
  const revision = "a".repeat(40);
  const verifiedEvidence = [
    { kind: "IMMUTABLE_TARGET", reference: `https://github.com/AquilaXk/easysubway-platform/commit/${revision}`, identity: revision, conclusion: "NOT_APPLICABLE" },
    { kind: "TARGET_CONSUMER", reference: `https://github.com/AquilaXk/easysubway-platform/blob/${revision}/.github/workflows/deploy.yml`, identity: revision, conclusion: "NOT_APPLICABLE" },
    { kind: "TARGET_TERMINAL_GATE", reference: "https://github.com/AquilaXk/easysubway-platform/actions/runs/1", identity: revision, conclusion: "SUCCESS" },
    { kind: "SYSTEM_TERMINAL_GATE", reference: "https://github.com/AquilaXk/easysubway/actions/runs/2", identity: revision, conclusion: "SUCCESS" },
  ];
  const reservedRollback = () => ({
    ...structuredClone(inventory.entries.find((entry) => entry.resourceId === "platform-compose-route-v2-gateway")),
    resourceId: "platform-approved-deployment-rollback",
    path: ".github/workflows/deploy.yml",
    selector: "PLATFORM_ATOMIC_TRAFFIC_ACTIVATION",
    classification: "TARGET_CANONICAL_DELETE_AFTER_HANDOFF",
    targetOutput: "Platform atomic traffic activation rollback",
    plannedAction: "DELETE_AFTER_HANDOFF",
    handoffState: "VERIFIED",
    handoffEvidence: verifiedEvidence,
    fallbackExposure: "VERIFIED_ROLLBACK_ONLY",
    fallbackRemovalOwner: null,
    fallbackVerificationState: "VERIFIED",
    fallbackVerification: ["PLATFORM_ATOMIC_TRAFFIC_ROLLBACK"],
    rollbackMode: "EXACT_IMMUTABLE_DEPLOYMENT_ONLY",
    rollbackRevision: revision,
    rollbackTargetRepository: "AquilaXk/easysubway-platform",
    rollbackOperation: "MANUAL_DEPLOYMENT",
    rollbackApprovalEvidence: {
      decision: "APPROVED",
      revision,
      operation: "MANUAL_DEPLOYMENT",
      deploymentClass: "PLATFORM_ATOMIC_TRAFFIC_ACTIVATION",
      reference: "https://github.com/AquilaXk/easysubway-platform/issues/17",
    },
  });
  const rollbackCandidate = structuredClone(inventory);
  rollbackCandidate.entries.push(reservedRollback());
  assert.deepEqual(validateRepositoryContractionInventory(rollbackCandidate), []);

  const digest = `sha256:${"b".repeat(64)}`;
  const ociDigestCandidate = structuredClone(inventory);
  const backendCiBuild = inventory.entries.find((entry) => entry.resourceId === "backend-ci-build");
  assert.ok(backendCiBuild, "backend-ci-build entry가 필요하다");
  ociDigestCandidate.entries.push({
    ...structuredClone(backendCiBuild),
    resourceId: "backend-oci-digest-target",
    repository: "AquilaXk/easysubway-backend",
    path: ".github/workflows/release.yml",
    selector: "immutable OCI digest consumer",
    classification: "TARGET_CANONICAL_DELETE_AFTER_HANDOFF",
    targetOwner: "backend",
    targetOutput: "Backend immutable OCI image",
    activeConsumers: ["Backend deployment"],
    handoffState: "VERIFIED",
    handoffEvidence: [
      { kind: "IMMUTABLE_TARGET", reference: `oci://AquilaXk/easysubway-backend@${digest}`, identity: digest, conclusion: "NOT_APPLICABLE" },
      { kind: "TARGET_CONSUMER", reference: `oci://AquilaXk/easysubway-backend@${digest}`, identity: digest, conclusion: "NOT_APPLICABLE" },
      { kind: "TARGET_TERMINAL_GATE", reference: "https://github.com/AquilaXk/easysubway-backend/actions/runs/1", identity: digest, conclusion: "SUCCESS" },
      { kind: "SYSTEM_TERMINAL_GATE", reference: "https://github.com/AquilaXk/easysubway/actions/runs/2", identity: digest, conclusion: "SUCCESS" },
    ],
    plannedAction: "DELETE_AFTER_HANDOFF",
    executionEligibility: true,
    fallbackExposure: "NONE",
    fallbackRemovalOwner: null,
    fallbackVerification: [],
    fallbackVerificationState: "NOT_APPLICABLE",
  });
  assert.deepEqual(validateRepositoryContractionInventory(ociDigestCandidate), []);

  const gatewayPromotion = structuredClone(inventory);
  Object.assign(gatewayPromotion.entries.find((entry) => entry.resourceId === "platform-compose-route-v2-gateway"), reservedRollback(), {
    resourceId: "platform-compose-route-v2-gateway",
    path: "infra/docker-compose.yml",
    selector: "route-v2-gateway",
    classification: "TARGET_FALLBACK_REMOVE",
    plannedAction: "REMOVE_FALLBACK",
  });
  assert.ok(validateRepositoryContractionInventory(gatewayPromotion)
    .some((error) => error.includes("known fallback은 FORBIDDEN_ACTIVE여야 한다")));

  for (const [mutate, expected] of [
    [(entry) => { entry.handoffEvidence = entry.handoffEvidence.filter((item) => item.kind !== "SYSTEM_TERMINAL_GATE"); }, "target/system terminal gate evidence"],
    [(entry) => { entry.handoffEvidence[3].kind = "TARGET_TERMINAL_GATE"; }, "handoff evidence kind 중복"],
    [(entry) => { entry.handoffEvidence[2].conclusion = "FAILURE"; }, "target/system terminal gate evidence"],
    [(entry) => { entry.handoffEvidence[3].reference = "https://github.com/AquilaXk/easysubway-backend/actions/runs/2"; }, "target/system terminal gate evidence"],
  ]) {
    const candidate = structuredClone(rollbackCandidate);
    mutate(candidate.entries.find((entry) => entry.resourceId === "platform-approved-deployment-rollback"));
    assert.ok(validateRepositoryContractionInventory(candidate).some((error) => error.includes(expected)), expected);
  }
  for (const [mutate, expected] of [
    [(entry) => { entry.rollbackApprovalEvidence = null; }, "Platform deployment rollback approval"],
    [(entry) => { entry.rollbackApprovalEvidence.revision = "b".repeat(40); }, "Platform deployment rollback approval"],
    [(entry) => { entry.rollbackApprovalEvidence.operation = "AUTOMATIC"; }, "Platform deployment rollback approval"],
    [(entry) => { entry.rollbackApprovalEvidence.deploymentClass = "UNKNOWN"; }, "Platform deployment rollback approval"],
    [(entry) => { entry.rollbackTargetRepository = "AquilaXk/easysubway-data"; }, "Platform deployment rollback approval"],
    [(entry) => { entry.kind = "SOURCE"; }, "Platform deployment rollback approval"],
    [(entry) => { entry.path = "artifacts/current-pointer.json"; }, "Platform deployment rollback approval"],
    [(entry) => { entry.selector = "restore_legacy_backend_service"; }, "Platform deployment rollback approval"],
  ]) {
    const candidate = structuredClone(rollbackCandidate);
    mutate(candidate.entries.find((entry) => entry.resourceId === "platform-approved-deployment-rollback"));
    assert.ok(validateRepositoryContractionInventory(candidate).some((error) => error.includes(expected)), expected);
  }
});

test("contract gate는 post-snapshot amendments의 disposition↔lifecycle 결속을 검증한다", () => {
  const ledger = loadJson("release/migrations/repository-split-issues.json");
  const amendments = loadJson("release/migrations/repository-split-issues-amendments.json");
  const keepHubWithTargetUrl = structuredClone(amendments);
  keepHubWithTargetUrl.amendments[1].targetUrl = "https://github.com/AquilaXk/easysubway-mobile/issues/45";
  const duplicatedSnapshotIssue = structuredClone(amendments);
  duplicatedSnapshotIssue.amendments[1].sourceIssue = 2690;

  assert.deepEqual(validateRepositorySplitIssueAmendments(amendments, ledger), []);
  assert.deepEqual(validateRepositorySplitIssueAmendments(keepHubWithTargetUrl, ledger), [
    "amendments[1].execution: KEEP_HUB은 targetUrl과 transferredAt이 null이어야 함",
  ]);
  assert.deepEqual(validateRepositorySplitIssueAmendments(duplicatedSnapshotIssue, ledger), [
    "amendments[1].sourceIssue: snapshot ledger와 중복",
  ]);
});

test("문서 거버넌스 계약은 ADR-HUB-0001 실물을 허용한다", () => {
  const errors = [];
  const adr = loadJson("contracts/documentation/ADR-HUB-0001.json");

  assert.equal(validateJson(
    "contracts/documentation/architecture-decision.schema.json",
    "contracts/documentation/ADR-HUB-0001.json",
    errors,
  ), true);
  assert.deepEqual(errors, []);
  assert.ok(adr.confirmation.some(({ method }) => method.endsWith("--current-only --local-contracts-only")));
});

test("documentation catalog는 terminal Hub, Data, Backend와 Mobile locator를 ACTIVE로 소비하고 fragment lifecycle을 fail closed한다", () => {
  const resourceSchema = loadJson("contracts/documentation/documentation-resource.schema.json");
  const fragmentSchema = loadJson("contracts/documentation/documentation-fragment.schema.json");
  const catalogSchema = loadJson("contracts/documentation/documentation-system-catalog.schema.json");
  const catalog = loadJson("contracts/documentation/documentation-system-catalog.json");
  const errors = [];

  validateDocumentationSystemCatalog(catalog, catalogSchema, errors, { requireActiveResolution: false });
  assert.deepEqual(errors, []);
  assert.deepEqual(catalog.repositories.map(({ repository }) => repository), [
    "AquilaXk/easysubway",
    "AquilaXk/easysubway-backend",
    "AquilaXk/easysubway-data",
    "AquilaXk/easysubway-mobile",
    "AquilaXk/easysubway-platform",
  ]);
  assert.equal(catalog.status, "PROPOSED");
  const hub = catalog.repositories.find(({ repository }) => repository === "AquilaXk/easysubway");
  assert.deepEqual(hub, {
    repository: "AquilaXk/easysubway",
    status: "ACTIVE",
    fragment: {
      gitSha: "71d03cbb20cca0a1b358c921febe9ca646ad06b3",
      path: "contracts/documentation/documentation-fragment.json",
      blobSha: "317d93550975428f8e72c5ead516e3e101c74172",
      lastVerifiedAt: "2026-08-13T13:32:18.000Z",
      verificationEvidence: [
        "https://github.com/AquilaXk/easysubway/issues/2748",
        "https://github.com/AquilaXk/easysubway/issues/2861",
        "https://github.com/AquilaXk/easysubway/issues/2863",
      ],
    },
  });
  const backend = catalog.repositories.find(({ repository }) => repository === "AquilaXk/easysubway-backend");
  assert.deepEqual(backend, {
    repository: "AquilaXk/easysubway-backend",
    status: "ACTIVE",
    fragment: {
      gitSha: "e506d2c8718ad6af681e9389fba780673e1f24d2",
      path: "contracts/documentation/documentation-fragment.json",
      blobSha: "1c27d17a4acef8f6c4bed168e8a1e20c2d04b992",
      lastVerifiedAt: "2026-08-13T11:24:30.000Z",
      verificationEvidence: [
        "https://github.com/AquilaXk/easysubway-backend/issues/247",
        "https://github.com/AquilaXk/easysubway-backend/pull/250",
        "https://github.com/AquilaXk/easysubway/pull/2854",
        "https://github.com/AquilaXk/easysubway/pull/2856",
      ],
    },
  });
  const data = catalog.repositories.find(({ repository }) => repository === "AquilaXk/easysubway-data");
  assert.deepEqual(data, {
    repository: "AquilaXk/easysubway-data",
    status: "ACTIVE",
    fragment: {
      gitSha: "e13c01763ba7f4aca6e809e2a5c6a7dc8833d00b",
      path: "contracts/documentation/documentation-fragment.json",
      blobSha: "337d73ee1fd5c40c4686f7383100ddfbbf669fcd",
      lastVerifiedAt: "2026-08-14T18:05:42.000Z",
      verificationEvidence: [
        "https://github.com/AquilaXk/easysubway-data/issues/237",
        "https://github.com/AquilaXk/easysubway-data/issues/281",
        "https://github.com/AquilaXk/easysubway-data/issues/286",
        "https://github.com/AquilaXk/easysubway-data/issues/38",
      ],
    },
  });
  const mobile = catalog.repositories.find(({ repository }) => repository === "AquilaXk/easysubway-mobile");
  assert.deepEqual(mobile, {
    repository: "AquilaXk/easysubway-mobile",
    status: "ACTIVE",
    fragment: {
      gitSha: "397a475a988c65fb31600142d5c79f26e46a03f5",
      path: "contracts/documentation/documentation-fragment.json",
      blobSha: "37aa755bf7959737dc68a10ff346f16b5bc1954b",
      lastVerifiedAt: "2026-08-13T07:33:23.000Z",
      verificationEvidence: [
        "https://github.com/AquilaXk/easysubway-mobile/issues/225",
        "https://github.com/AquilaXk/easysubway/pull/2854",
      ],
    },
  });
  assert.deepEqual(catalog.repositories.filter(({ repository }) => ![hub.repository, backend.repository, data.repository, mobile.repository].includes(repository))
    .map(({ status, fragment }) => ({ status, fragment })), [{ status: "PROPOSED", fragment: null }]);
  const unresolvedErrors = [];
  validateDocumentationSystemCatalog(catalog, catalogSchema, unresolvedErrors);
  assert.ok(unresolvedErrors.some((error) => error.includes("ACTIVE fragment resolution contract")));

  for (const [mutate, expected] of [
    [(value) => value.repositories.pop(), /minItems 5/],
    [(value) => value.repositories.push(structuredClone(value.repositories[0])), /maxItems 5/],
    [(value) => { value.repositories[0].repository = "AquilaXk/unknown"; }, /enum/],
    [(value) => { value.repositories[0].status = "ACTIVE"; value.repositories[0].fragment = null; }, /ACTIVE fragment가 필요하다/],
    [(value) => { value.repositories[0].resources = []; }, /resources/],
  ]) {
    const invalid = structuredClone(catalog);
    mutate(invalid);
    const invalidErrors = [];
    validateDocumentationSystemCatalog(invalid, catalogSchema, invalidErrors);
    assert.ok(invalidErrors.some((error) => expected.test(error)), invalidErrors.join("; "));
  }

  const fragmentErrors = [];
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI,
    schemaVersion: 1,
    repository: "AquilaXk/easysubway",
    sourceSha: "a".repeat(40),
    status: "ACTIVE",
    lastVerifiedAt: "2026-08-05T00:00:00.000Z",
    verificationEvidence: [],
    resources: [],
  }, fragmentSchema, resourceSchema, fragmentErrors);
  assert.ok(fragmentErrors.some((error) => error.includes("verificationEvidence")));

  const missingTimestampErrors = [];
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI,
    schemaVersion: 1,
    repository: "AquilaXk/easysubway",
    sourceSha: "a".repeat(40),
    status: "ACTIVE",
    lastVerifiedAt: null,
    verificationEvidence: ["evidence:fixture"],
    resources: [],
  }, fragmentSchema, resourceSchema, missingTimestampErrors);
  assert.ok(missingTimestampErrors.some((error) => error.includes("lastVerifiedAt")));

  const unsafeEvidenceCatalog = structuredClone(catalog);
  unsafeEvidenceCatalog.repositories[0] = {
    repository: "AquilaXk/easysubway",
    status: "ACTIVE",
    fragment: {
      gitSha: "a".repeat(40),
      path: "contracts/documentation/documentation-fragment.json",
      blobSha: "b".repeat(40),
      lastVerifiedAt: "2026-08-05T00:00:00.000Z",
      verificationEvidence: ["/private/owner/raw.json"],
    },
  };
  const unsafeEvidenceErrors = [];
  validateDocumentationSystemCatalog(unsafeEvidenceCatalog, catalogSchema, unsafeEvidenceErrors);
  assert.ok(unsafeEvidenceErrors.some((error) => error.includes("verificationEvidence")));

  const unsupportedBlobCatalog = structuredClone(unsafeEvidenceCatalog);
  unsupportedBlobCatalog.repositories[0].fragment.blobSha = "b".repeat(41);
  unsupportedBlobCatalog.repositories[0].fragment.verificationEvidence = ["evidence:fixture"];
  const unsupportedBlobErrors = [];
  validateDocumentationSystemCatalog(unsupportedBlobCatalog, catalogSchema, unsupportedBlobErrors);
  assert.ok(unsupportedBlobErrors.some((error) => error.includes("oneOf")), unsupportedBlobErrors.join("; "));

  const unverifiedActiveCatalog = structuredClone(unsafeEvidenceCatalog);
  unverifiedActiveCatalog.repositories[0].fragment.verificationEvidence = ["evidence:fixture"];
  const unverifiedActiveErrors = [];
  validateDocumentationSystemCatalog(unverifiedActiveCatalog, catalogSchema, unverifiedActiveErrors);
  assert.ok(unverifiedActiveErrors.some((error) => error.includes("ACTIVE fragment resolution contract")));

  const unsortedErrors = [];
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI,
    schemaVersion: 1,
    repository: "AquilaXk/easysubway",
    sourceSha: "a".repeat(40),
    status: "PROPOSED",
    lastVerifiedAt: null,
    verificationEvidence: [],
    resources: [{ resource: "resource:z" }, { resource: "resource:a" }],
  }, fragmentSchema, resourceSchema, unsortedErrors);
  assert.ok(unsortedErrors.some((error) => error.includes("sorted-unique")));

  const crossRepositoryErrors = [];
  const canonicalIdentity = `sha256:${"c".repeat(64)}`;
  const crossRepositoryRecord = {
    resource: "surface:current", resourceClass: "CANONICAL_RESOURCE", documentationFamily: "ARCHITECTURE",
    kindCandidate: "CROSS_REPOSITORY_HANDOFF", sourceSurface: "EXTERNAL", canonicalIdentity, status: "ACTIVE",
    ownerRepository: "AquilaXk/easysubway", ownerIssue: null, currentConsumers: ["consumer:architecture"],
    releaseReachability: "NONE", publicSurfaceReachability: [], assertionState: "REQUIRED_FINAL_PRODUCTION_BEHAVIOR",
    sensitivity: "INTERNAL", duplicateGroup: null, disposition: "RETAIN_CANONICAL", deletePrerequisite: [],
    supersedes: ["surface:external-predecessor"], supersededBy: null, invalidatedBy: null, invalidationReason: null,
    invalidationEvidence: [], mutationPolicy: "CURRENT_STATE_WITH_CHANGE", reviewPolicyId: "EVENT_ONLY",
    reviewTrigger: ["event:change"], lastVerifiedAt: "2026-08-05T00:00:00.000Z",
    lastVerifiedIdentity: canonicalIdentity, verificationMethod: "contract-test", verificationEvidence: ["evidence:fixture"],
    nextReviewAtOrSemanticExpiry: null, implementationPlan: "PLAN-DOC", workloadClass: null,
    orchestrationProfile: null, stateClass: null, configurationDelivery: null, healthContract: null,
    availabilityContract: null, securityContract: null, releaseContract: null, portabilityOwner: null,
    portabilityEvidence: [], portabilityGap: [],
  };
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI,
    schemaVersion: 1,
    repository: "AquilaXk/easysubway",
    sourceSha: "a".repeat(40),
    status: "PROPOSED",
    lastVerifiedAt: null,
    verificationEvidence: [],
    resources: [crossRepositoryRecord],
  }, fragmentSchema, resourceSchema, crossRepositoryErrors);
  assert.deepEqual(crossRepositoryErrors, []);

  const trackedRecord = structuredClone(crossRepositoryRecord);
  trackedRecord.resource = "AquilaXk/easysubway-mobile:docs/a.json";
  trackedRecord.sourceSurface = "TRACKED";
  trackedRecord.canonicalIdentity = `git:${"a".repeat(40)}:docs/b.json:${"b".repeat(40)}`;
  trackedRecord.lastVerifiedIdentity = trackedRecord.canonicalIdentity;
  trackedRecord.supersedes = [];
  const trackedIdentityErrors = [];
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI, schemaVersion: 1,
    repository: "AquilaXk/easysubway", sourceSha: "a".repeat(40), status: "PROPOSED",
    lastVerifiedAt: null, verificationEvidence: [], resources: [trackedRecord],
  }, fragmentSchema, resourceSchema, trackedIdentityErrors);
  assert.ok(trackedIdentityErrors.some((error) => error.includes("tracked fragment identity mismatch")));

  const unsupportedTrackedIdentity = structuredClone(trackedRecord);
  unsupportedTrackedIdentity.resource = "AquilaXk/easysubway:docs/a.json";
  unsupportedTrackedIdentity.canonicalIdentity = `git:${"a".repeat(40)}:docs/a.json:${"b".repeat(41)}`;
  unsupportedTrackedIdentity.lastVerifiedIdentity = unsupportedTrackedIdentity.canonicalIdentity;
  const unsupportedTrackedErrors = [];
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI, schemaVersion: 1,
    repository: "AquilaXk/easysubway", sourceSha: "a".repeat(40), status: "PROPOSED",
    lastVerifiedAt: null, verificationEvidence: [], resources: [unsupportedTrackedIdentity],
  }, fragmentSchema, resourceSchema, unsupportedTrackedErrors);
  assert.ok(unsupportedTrackedErrors.some((error) => error.includes("invalid tracked identity")));

  for (const mutate of [
    (record) => { record.resource = "surface:self"; record.supersedes = ["surface:self"]; },
    (record) => { record.supersededBy = "surface:successor"; },
  ]) {
    const record = structuredClone(crossRepositoryRecord);
    mutate(record);
    const lifecycleErrors = [];
    validateDocumentationFragment({
      $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI, schemaVersion: 1,
      repository: "AquilaXk/easysubway", sourceSha: "a".repeat(40), status: "PROPOSED",
      lastVerifiedAt: null, verificationEvidence: [], resources: [record],
    }, fragmentSchema, resourceSchema, lifecycleErrors);
    assert.ok(lifecycleErrors.some((error) => error.includes("fragment lifecycle contradiction")));
  }

  const predecessor = structuredClone(crossRepositoryRecord);
  predecessor.resource = "surface:predecessor";
  predecessor.status = "SUPERSEDED";
  predecessor.supersedes = [];
  predecessor.supersededBy = "surface:successor";
  const successor = structuredClone(crossRepositoryRecord);
  successor.resource = "surface:successor";
  successor.supersedes = [];
  const reciprocalErrors = [];
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI, schemaVersion: 1,
    repository: "AquilaXk/easysubway", sourceSha: "a".repeat(40), status: "PROPOSED",
    lastVerifiedAt: null, verificationEvidence: [], resources: [predecessor, successor],
  }, fragmentSchema, resourceSchema, reciprocalErrors);
  assert.ok(reciprocalErrors.some((error) => error.includes("fragment relation contradiction")));

  const cycleA = structuredClone(predecessor);
  cycleA.resource = "surface:a";
  cycleA.supersedes = ["surface:b"];
  cycleA.supersededBy = "surface:b";
  const cycleB = structuredClone(predecessor);
  cycleB.resource = "surface:b";
  cycleB.supersedes = ["surface:a"];
  cycleB.supersededBy = "surface:a";
  const cycleErrors = [];
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI, schemaVersion: 1,
    repository: "AquilaXk/easysubway", sourceSha: "a".repeat(40), status: "PROPOSED",
    lastVerifiedAt: null, verificationEvidence: [], resources: [cycleA, cycleB],
  }, fragmentSchema, resourceSchema, cycleErrors);
  assert.ok(cycleErrors.some((error) => error.includes("fragment supersession cycle")));

  const duplicateCanonicalA = structuredClone(crossRepositoryRecord);
  duplicateCanonicalA.resource = "surface:duplicate-a";
  duplicateCanonicalA.duplicateGroup = "duplicate:fixture";
  duplicateCanonicalA.supersedes = [];
  const duplicateCanonicalB = structuredClone(duplicateCanonicalA);
  duplicateCanonicalB.resource = "surface:duplicate-b";
  const duplicateCanonicalErrors = [];
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI, schemaVersion: 1,
    repository: "AquilaXk/easysubway", sourceSha: "a".repeat(40), status: "PROPOSED",
    lastVerifiedAt: null, verificationEvidence: [], resources: [duplicateCanonicalA, duplicateCanonicalB],
  }, fragmentSchema, resourceSchema, duplicateCanonicalErrors);
  assert.ok(duplicateCanonicalErrors.some((error) => error.includes("fragment duplicate group contradiction")));

  for (const mutate of [
    (record) => { record.currentConsumers = []; },
    (record) => { record.disposition = "MIGRATE_REFERENCE"; },
  ]) {
    const record = structuredClone(duplicateCanonicalA);
    mutate(record);
    const duplicateMemberErrors = [];
    validateDocumentationFragment({
      $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI, schemaVersion: 1,
      repository: "AquilaXk/easysubway", sourceSha: "a".repeat(40), status: "PROPOSED",
      lastVerifiedAt: null, verificationEvidence: [], resources: [record],
    }, fragmentSchema, resourceSchema, duplicateMemberErrors);
    assert.ok(duplicateMemberErrors.some((error) => error.includes("fragment duplicate group contradiction")));
  }

  const unresolvedDuplicateErrors = [];
  validateDocumentationFragment({
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI, schemaVersion: 1,
    repository: "AquilaXk/easysubway", sourceSha: "a".repeat(40), status: "PROPOSED",
    lastVerifiedAt: null, verificationEvidence: [], resources: [duplicateCanonicalA],
  }, fragmentSchema, resourceSchema, unresolvedDuplicateErrors);
  assert.deepEqual(unresolvedDuplicateErrors, []);
});

test("documentation catalog fragment schema requires an immutable canonical Hub URI", () => {
  const schema = loadJson("contracts/documentation/documentation-fragment.schema.json");
  const fragment = {
    $schema: DOCUMENTATION_FRAGMENT_SCHEMA_URI,
    schemaVersion: 1,
    repository: "AquilaXk/easysubway-mobile",
    sourceSha: "b".repeat(40),
    status: "PROPOSED",
    lastVerifiedAt: null,
    verificationEvidence: [],
    resources: [],
  };
  const outcomes = [
    fragment.$schema,
    "./documentation-fragment.schema.json",
    "https://raw.githubusercontent.com/AquilaXk/easysubway/main/contracts/documentation/documentation-fragment.schema.json",
    "https://raw.githubusercontent.com/AquilaXk/easysubway/1f72280ccf45f091b4130054b0a426d55cdb9b4a/contracts/documentation/documentation-fragment.schema.json",
    `https://raw.githubusercontent.com/AquilaXk/easysubway-mobile/${"a".repeat(40)}/contracts/documentation/documentation-fragment.schema.json`,
    `https://raw.githubusercontent.com/AquilaXk/easysubway/${"a".repeat(40)}/contracts/documentation/documentation-resource.schema.json`,
    `${fragment.$schema}?download=1`,
  ].map(($schema) => validateSchema(schema, { ...fragment, $schema }).ok);
  assert.deepEqual(outcomes, [true, false, false, false, false, false, false]);
});

test("문서 거버넌스 계약은 successor의 자체 decision schema와 안전한 schema path만 허용한다", () => {
  const { directory, workspacePath } = createExternalWorkspace();
  try {
    const rootPath = join(directory, "inputs/architecture-decision.json");
    const root = loadJson(rootPath);
    root.status = "superseded";
    root.supersededBy = "ADR-HUB-0002";
    writeFileSync(rootPath, JSON.stringify(root));

    const successor = structuredClone(root);
    successor.id = "ADR-HUB-0002";
    successor.status = "accepted";
    successor.supersededBy = null;
    successor.supersedes = [root.id];
    successor.decisionSchema = "./ADR-HUB-0002-decision.schema.json";
    successor.decision = { policy: "successor-specific" };
    const successorPath = join(directory, "inputs/ADR-HUB-0002.json");
    const decisionSchemaPath = join(directory, "inputs/ADR-HUB-0002-decision.schema.json");
    const successorDecisionSchema = {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "type": "object",
      "required": ["policy"],
      "additionalProperties": false,
      "properties": {
        "policy": { "type": "string", "const": "successor-specific" }
      }
    };
    writeFileSync(decisionSchemaPath, JSON.stringify(successorDecisionSchema));
    writeFileSync(successorPath, JSON.stringify(successor));

    assert.deepEqual(collectContractErrors(workspacePath), []);

    for (const [name, mutate, expected] of [
      ["missing-reference", (adr) => { delete adr.decisionSchema; }, "decisionSchema"],
      ["missing-file", () => { rmSync(decisionSchemaPath); }, "decisionSchema ./ADR-HUB-0002-decision.schema.json 누락"],
      ["absolute", (adr) => { adr.decisionSchema = "/tmp/decision.schema.json"; }, "repository 내부 상대 JSON path"],
      ["escape", (adr) => { adr.decisionSchema = "../ADR-HUB-0002-decision.schema.json"; }, "repository 내부 상대 JSON path"],
      ["symlink", () => {
        rmSync(decisionSchemaPath);
        symlinkSync("ADR-HUB-0001-decision.schema.json", decisionSchemaPath);
      }, "symlink"],
      ["malformed", () => { writeFileSync(decisionSchemaPath, "{"); }, "유효한 JSON이 필요하다"],
      ["empty-schema", () => { writeFileSync(decisionSchemaPath, "{}"); }, "비어 있지 않은 required"],
      ["array-schema", () => { writeFileSync(decisionSchemaPath, "[]"); }, "비어 있지 않은 required"],
      ["invalid", (adr) => { adr.decision.policy = "wrong"; }, "$.decision.policy"],
    ]) {
      const candidate = structuredClone(successor);
      mutate(candidate);
      writeFileSync(successorPath, JSON.stringify(candidate));
      const errors = collectContractErrors(workspacePath);
      assert.ok(errors.some((error) => error.includes("ADR-HUB-0002.json") && error.includes(expected)), name);
      rmSync(decisionSchemaPath, { force: true });
      writeFileSync(decisionSchemaPath, JSON.stringify(successorDecisionSchema));
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 대표적인 ADR 계약 위반을 거부한다", () => {
  const directory = mkdtempSync(join(tmpdir(), "architecture-decision-contract-"));
  try {
    const schemaPath = "contracts/documentation/architecture-decision.schema.json";
    const valid = loadJson("contracts/documentation/ADR-HUB-0001.json");
    cpSync("contracts/documentation/ADR-HUB-0001-decision.schema.json", join(directory, "ADR-HUB-0001-decision.schema.json"));
    for (const [name, mutate, expected] of [
      ["invalid-id", (adr) => { adr.id = "ADR-DATA-0001"; }, "$.id: pattern"],
      ["invalid-kind", (adr) => { adr.kind = "runbook"; }, "$.kind: const"],
      ["missing-owner", (adr) => { delete adr.owner; }, "$.owner: 필수 필드 누락"],
      ["owner-prefix-mismatch", (adr) => { adr.owner.repository = "AquilaXk/easysubway-data"; }, "$.owner.repository: const"],
      ["invalid-status", (adr) => { adr.status = "implemented"; }, "$.status: enum"],
      ["missing-decision", (adr) => { delete adr.decision; }, "$.decision: 필수 필드 누락"],
      ["missing-context-issue", (adr) => { delete adr.contextIssue; }, "$.contextIssue: 필수 필드 누락"],
      ["wrong-context-issue", (adr) => { adr.contextIssue = "https://github.com/AquilaXk/easysubway/issues/1"; }, "ADR-HUB-0001 contextIssue"],
      ["unknown-field", (adr) => { adr.futureField = true; }, "$.futureField: 허용되지 않은 필드"],
      ["target-owner-mismatch", (adr) => { adr.decision.repositoryOwners.data = "AquilaXk/easysubway"; }, "$.decision.repositoryOwners.data: const"],
      ["tracked-sensitive-evidence", (adr) => { adr.decision.sensitiveEvidence.trackedContentAllowed = true; }, "$.decision.sensitiveEvidence.trackedContentAllowed: const"],
      ["malformed-supersedes", (adr) => { adr.supersedes = 1; }, "$.supersedes: type array"],
      ["no-chosen-option", (adr) => { adr.consideredOptions.forEach((option) => { option.chosen = false; }); }, "chosen 옵션이 정확히 하나"],
      ["multiple-chosen-options", (adr) => { adr.consideredOptions.forEach((option) => { option.chosen = true; }); }, "chosen 옵션이 정확히 하나"],
      ["duplicate-option-id", (adr) => { adr.consideredOptions[1].id = adr.consideredOptions[0].id; }, "id는 유일"],
    ]) {
      const candidate = structuredClone(valid);
      mutate(candidate);
      const candidatePath = join(directory, `${name}.json`);
      writeFileSync(candidatePath, JSON.stringify(candidate));
      const errors = [];

      assert.equal(validateJson(schemaPath, candidatePath, errors), false, name);
      assert.ok(errors.some((error) => error.includes(expected)), `${name}: ${expected}`);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 자기 supersession과 참조 없는 superseded 상태를 거부한다", () => {
  const valid = loadJson("contracts/documentation/ADR-HUB-0001.json");
  const selfSupersession = structuredClone(valid);
  selfSupersession.supersedes = [selfSupersession.id];
  const missingReference = structuredClone(valid);
  missingReference.status = "superseded";
  const prematureReference = structuredClone(valid);
  prematureReference.supersededBy = "ADR-HUB-0002";

  assert.ok(validateArchitectureDecision(selfSupersession).some((error) => error.includes("자기 자신")));
  assert.ok(validateArchitectureDecision(missingReference).some((error) => error.includes("supersededBy")));
  assert.ok(validateArchitectureDecision(prematureReference).some((error) => error.includes("non-superseded")));
});

test("문서 거버넌스 계약은 target owner, 민감 evidence, 첫 파생 이슈 정책을 fail closed한다", () => {
  const adr = loadJson("contracts/documentation/ADR-HUB-0001.json");
  const invalidOwner = structuredClone(adr);
  invalidOwner.decision.repositoryOwners.data = "AquilaXk/easysubway";
  const invalidEvidence = structuredClone(adr);
  invalidEvidence.decision.sensitiveEvidence.trackedContentAllowed = true;
  const invalidChildGate = structuredClone(adr);
  invalidChildGate.decision.childIssuePolicy.firstChildAfter = "BEFORE_ADR_HUB_0001_MERGED";

  assert.ok(validateArchitectureDecision(invalidOwner).some((error) => error.includes("repository owner")));
  assert.ok(validateArchitectureDecision(invalidEvidence).some((error) => error.includes("trackedContentAllowed")));
  assert.ok(validateArchitectureDecision(invalidChildGate).some((error) => error.includes("첫 파생 이슈")));
});

test("문서 거버넌스 계약은 raw evidence payload 필드를 integrated gate에서 거부한다", () => {
  const { directory, workspacePath } = createExternalWorkspace();
  try {
    const decisionPath = join(directory, "inputs/architecture-decision.json");
    const decision = loadJson(decisionPath);
    decision.confirmation[0].rawEvidence = { token: "synthetic-test-value" };
    writeFileSync(decisionPath, JSON.stringify(decision));

    assert.ok(collectContractErrors(workspacePath).some((error) => error.includes("rawEvidence: 허용되지 않은 필드")));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 accepted ADR 본문의 in-place 변경을 거부한다", () => {
  const accepted = loadJson("contracts/documentation/ADR-HUB-0001.json");
  accepted.status = "accepted";
  const modified = structuredClone(accepted);
  modified.title = "조용히 바뀐 결정";

  assert.ok(validateArchitectureDecisionTransition(accepted, modified).some((error) => error.includes("in-place")));
  assert.deepEqual(validateArchitectureDecisionTransition(accepted, accepted), []);

  const proposed = structuredClone(accepted);
  proposed.status = "proposed";
  const acceptedWithChange = structuredClone(accepted);
  acceptedWithChange.title = "accept와 함께 바뀐 결정";
  assert.ok(validateArchitectureDecisionTransition(proposed, acceptedWithChange).some((error) => error.includes("status-only")));
  assert.deepEqual(validateArchitectureDecisionTransition(proposed, accepted), []);

  const superseded = structuredClone(accepted);
  superseded.status = "superseded";
  superseded.supersededBy = "ADR-HUB-0002";
  assert.deepEqual(validateArchitectureDecisionTransition(accepted, superseded), []);

  for (const status of ["rejected", "withdrawn", "superseded"]) {
    const terminal = structuredClone(superseded);
    terminal.status = status;
    if (status !== "superseded") terminal.supersededBy = null;
    const changed = structuredClone(terminal);
    changed.title = "종결 뒤 바뀐 결정";
    assert.ok(validateArchitectureDecisionTransition(terminal, changed)
      .some((error) => error.includes("종결 상태")), status);
  }
});

test("문서 거버넌스 계약은 workspace gate에서 base revision 상태 전이를 비교한다", () => {
  const { directory, workspacePath } = createExternalWorkspace();
  try {
    const decisionPath = join(directory, "inputs/architecture-decision.json");
    const previous = loadJson(decisionPath);
    const current = structuredClone(previous);
    current.status = "accepted";
    current.title = "accept와 함께 바뀐 결정";
    writeFileSync(decisionPath, JSON.stringify(current));

    assert.ok(collectContractErrors(workspacePath, { previousArchitectureDecision: previous })
      .some((error) => error.includes("status-only")));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 accepted ADR의 supersession successor를 fail closed한다", () => {
  const cases = [
    ["missing", () => {}, "current ADR directory에 successor ADR 누락"],
    ["malformed", (directory) => { writeFileSync(join(directory, "inputs/ADR-HUB-0002.json"), "{"); }, "유효한 JSON"],
    ["duplicate", (directory, successor) => {
      writeFileSync(join(directory, "inputs/ADR-HUB-0002.json"), JSON.stringify(successor));
      writeFileSync(join(directory, "inputs/duplicate.json"), JSON.stringify(successor));
    }, "successor ADR 중복"],
    ["invalid", (directory, successor) => {
      successor.decision.repositoryOwners.data = "AquilaXk/easysubway";
      writeFileSync(join(directory, "inputs/ADR-HUB-0002.json"), JSON.stringify(successor));
    }, "successor ADR는 schema와 semantic 검증을 통과해야 한다"],
    ["missing-supersedes", (directory, successor) => {
      delete successor.supersedes;
      writeFileSync(join(directory, "inputs/ADR-HUB-0002.json"), JSON.stringify(successor));
    }, "$.supersedes: 필수 필드 누락"],
    ["non-reciprocal", (directory, successor) => {
      successor.supersedes = [];
      writeFileSync(join(directory, "inputs/ADR-HUB-0002.json"), JSON.stringify(successor));
    }, "supersedes reciprocal link가 필요하다"],
  ];

  for (const [name, prepare, expected] of cases) {
    const { directory, workspacePath } = createExternalWorkspace();
    try {
      const decisionPath = join(directory, "inputs/architecture-decision.json");
      const previous = loadJson(decisionPath);
      previous.status = "accepted";
      const current = structuredClone(previous);
      current.status = "superseded";
      current.supersededBy = "ADR-HUB-0002";
      writeFileSync(decisionPath, JSON.stringify(current));
      const successor = structuredClone(previous);
      successor.id = "ADR-HUB-0002";
      successor.supersedes = [previous.id];
      bindRootDecisionSchema(join(directory, "inputs"), successor);
      prepare(directory, successor);

      assert.ok(
        collectContractErrors(workspacePath, { previousArchitectureDecision: previous })
          .some((error) => error.includes(expected)),
        `${name}: ${expected}`,
      );
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }
});

test("문서 거버넌스 계약은 reciprocal successor가 있는 accepted ADR supersession을 허용한다", () => {
  const { directory, workspacePath } = createExternalWorkspace();
  try {
    const decisionPath = join(directory, "inputs/architecture-decision.json");
    const previous = loadJson(decisionPath);
    previous.status = "accepted";
    const current = structuredClone(previous);
    current.status = "superseded";
    current.supersededBy = "ADR-HUB-0002";
    writeFileSync(decisionPath, JSON.stringify(current));
    const successor = structuredClone(previous);
    successor.id = "ADR-HUB-0002";
    successor.supersedes = [previous.id];
    bindRootDecisionSchema(join(directory, "inputs"), successor);
    writeFileSync(join(directory, "inputs/ADR-HUB-0002.json"), JSON.stringify(successor));
    writeFileSync(join(directory, "inputs/unrelated-malformed.json"), "{");

    assert.deepEqual(collectContractErrors(workspacePath, { previousArchitectureDecision: previous }), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 active chain 밖 ADR 후보도 검증한다", () => {
  const { directory, workspacePath } = createExternalWorkspace();
  try {
    const candidate = loadJson(join(directory, "inputs/architecture-decision.json"));
    candidate.id = "ADR-HUB-0002";
    bindRootDecisionSchema(join(directory, "inputs"), candidate);
    delete candidate.decision;
    writeFileSync(join(directory, "inputs/ADR-HUB-0002.json"), JSON.stringify(candidate));
    const unidentified = loadJson(join(directory, "inputs/architecture-decision.json"));
    delete unidentified.id;
    writeFileSync(join(directory, "inputs/candidate.json"), JSON.stringify(unidentified));
    const duplicate = loadJson(join(directory, "inputs/architecture-decision.json"));
    duplicate.id = "ADR-HUB-0003";
    bindRootDecisionSchema(join(directory, "inputs"), duplicate);
    writeFileSync(join(directory, "inputs/off-chain-a.json"), JSON.stringify(duplicate));
    writeFileSync(join(directory, "inputs/off-chain-b.json"), JSON.stringify(duplicate));

    const errors = collectContractErrors(workspacePath);
    assert.ok(errors.some((error) => (
      error.includes("ADR-HUB-0002.json") && error.includes("$.decision: 필수 필드 누락")
    )));
    assert.ok(errors.some((error) => (
      error.includes("candidate.json") && error.includes("$.id: 필수 필드 누락")
    )));
    assert.ok(errors.some((error) => error.includes("current ADR ID 중복")));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 active chain 밖 ADR lifecycle도 fail closed한다", () => {
  for (const [name, prepare, expected] of [
    ["missing", () => {}, "successor ADR 누락"],
    ["invalid", (directory, successor) => {
      delete successor.decision;
      writeFileSync(join(directory, "inputs/off-chain-successor.json"), JSON.stringify(successor));
    }, "successor ADR는 schema와 semantic 검증을 통과해야 한다"],
    ["non-reciprocal", (directory, successor) => {
      successor.supersedes = [];
      writeFileSync(join(directory, "inputs/off-chain-successor.json"), JSON.stringify(successor));
    }, "supersedes reciprocal link가 필요하다"],
  ]) {
    const { directory, workspacePath } = createExternalWorkspace();
    try {
      const rootPath = join(directory, "inputs/architecture-decision.json");
      const root = loadJson(rootPath);
      root.status = "accepted";
      writeFileSync(rootPath, JSON.stringify(root));
      const previousStandalone = structuredClone(root);
      previousStandalone.id = "ADR-HUB-0004";
      bindRootDecisionSchema(join(directory, "inputs"), previousStandalone);
      const currentStandalone = structuredClone(previousStandalone);
      currentStandalone.status = "superseded";
      currentStandalone.supersededBy = "ADR-HUB-0005";
      writeFileSync(join(directory, "inputs/off-chain.json"), JSON.stringify(currentStandalone));
      const successor = structuredClone(root);
      successor.id = "ADR-HUB-0005";
      successor.supersedes = [currentStandalone.id];
      bindRootDecisionSchema(join(directory, "inputs"), successor);
      prepare(directory, successor);

      const errors = collectContractErrors(workspacePath, {
        previousArchitectureDecision: [structuredClone(root), previousStandalone],
      });
      assert.ok(errors.some((error) => error.includes(expected)), `${name}: ${expected}`);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }

  const currentOnly = createExternalWorkspace();
  try {
    const rootPath = join(currentOnly.directory, "inputs/architecture-decision.json");
    const root = loadJson(rootPath);
    root.status = "accepted";
    writeFileSync(rootPath, JSON.stringify(root));
    const falseClaim = structuredClone(root);
    falseClaim.id = "ADR-HUB-0010";
    bindRootDecisionSchema(join(currentOnly.directory, "inputs"), falseClaim);
    falseClaim.status = "proposed";
    falseClaim.supersedes = [root.id];
    writeFileSync(join(currentOnly.directory, "inputs/false-claim.json"), JSON.stringify(falseClaim));
    assert.ok(collectContractErrors(currentOnly.workspacePath)
      .some((error) => error.includes("supersedes predecessor reciprocal link가 필요하다")));
    rmSync(join(currentOnly.directory, "inputs/false-claim.json"));

    const standalonePath = join(currentOnly.directory, "inputs/off-root-a.json");
    const successorPath = join(currentOnly.directory, "inputs/off-root-b.json");
    const standalone = structuredClone(root);
    standalone.id = "ADR-HUB-0006";
    bindRootDecisionSchema(join(currentOnly.directory, "inputs"), standalone);
    standalone.status = "superseded";
    standalone.supersededBy = "ADR-HUB-0007";
    writeFileSync(standalonePath, JSON.stringify(standalone));
    assert.ok(collectContractErrors(currentOnly.workspacePath)
      .some((error) => error.includes("off-root-a.json") && error.includes("successor ADR 누락")));

    const successor = structuredClone(standalone);
    successor.id = "ADR-HUB-0007";
    bindRootDecisionSchema(join(currentOnly.directory, "inputs"), successor);
    standalone.supersedes = [successor.id];
    successor.supersededBy = standalone.id;
    successor.supersedes = [standalone.id];
    writeFileSync(standalonePath, JSON.stringify(standalone));
    writeFileSync(successorPath, JSON.stringify(successor));
    assert.ok(collectContractErrors(currentOnly.workspacePath)
      .some((error) => error.includes("supersession cycle")));
  } finally {
    rmSync(currentOnly.directory, { recursive: true, force: true });
  }

  const { directory, workspacePath } = createExternalWorkspace();
  try {
    const root = loadJson(join(directory, "inputs/architecture-decision.json"));
    for (const [id, status] of [["ADR-HUB-0008", "proposed"], ["ADR-HUB-0009", "accepted"]]) {
      const deleted = structuredClone(root);
      deleted.id = id;
      deleted.status = status;
      assert.ok(collectContractErrors(workspacePath, {
        previousArchitectureDecision: [root, deleted],
      }).some((error) => error.includes(`base ADR ${id}가 current catalog에서 삭제되었다`)));
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 current-only와 base 비교에서 supersession chain을 검증한다", () => {
  const { directory, workspacePath } = createExternalWorkspace();
  try {
    const decisionPath = join(directory, "inputs/architecture-decision.json");
    const root = loadJson(decisionPath);
    const previousRoot = structuredClone(root);
    previousRoot.status = "accepted";
    root.status = "superseded";
    root.supersededBy = "ADR-HUB-0002";
    writeFileSync(decisionPath, JSON.stringify(root));
    const successor = structuredClone(root);
    successor.id = "ADR-HUB-0002";
    bindRootDecisionSchema(join(directory, "inputs"), successor);
    successor.status = "proposed";
    successor.supersededBy = null;
    successor.supersedes = [root.id];
    const successorPath = join(directory, "inputs/ADR-HUB-0002.json");
    writeFileSync(successorPath, JSON.stringify(successor));

    assert.ok(collectContractErrors(workspacePath).some((error) => (
      error.includes("successor ADR는 accepted 상태여야 한다")
    )));

    successor.status = "superseded";
    successor.supersededBy = "ADR-HUB-0003";
    writeFileSync(successorPath, JSON.stringify(successor));
    const terminal = structuredClone(successor);
    terminal.id = "ADR-HUB-0003";
    bindRootDecisionSchema(join(directory, "inputs"), terminal);
    terminal.status = "accepted";
    terminal.supersededBy = null;
    terminal.supersedes = [successor.id];
    const terminalPath = join(directory, "inputs/ADR-HUB-0003.json");
    writeFileSync(terminalPath, JSON.stringify(terminal));
    assert.deepEqual(collectContractErrors(workspacePath), []);

    writeFileSync(join(directory, "inputs/ADR-HUB-0001-duplicate.json"), JSON.stringify(root));
    assert.ok(collectContractErrors(workspacePath).some((error) => error.includes("current ADR ID 중복")));
    rmSync(join(directory, "inputs/ADR-HUB-0001-duplicate.json"));

    assert.ok(collectContractErrors(workspacePath, {
      previousArchitectureDecision: [previousRoot, previousRoot],
    }).some((error) => error.includes("base ADR ADR-HUB-0001 중복")));

    assert.ok(collectContractErrors(workspacePath, {
      previousArchitectureDecision: [previousRoot],
    }).some((error) => error.includes("direct successor는 accepted")));

    terminal.supersedes = [];
    writeFileSync(terminalPath, JSON.stringify(terminal));
    assert.ok(collectContractErrors(workspacePath).some((error) => error.includes("reciprocal link")));
    terminal.supersedes = [successor.id];
    writeFileSync(terminalPath, JSON.stringify(terminal));

    writeFileSync(join(directory, "inputs/ADR-HUB-0003-duplicate.json"), JSON.stringify(terminal));
    assert.ok(collectContractErrors(workspacePath).some((error) => error.includes("successor ADR 중복")));
    rmSync(join(directory, "inputs/ADR-HUB-0003-duplicate.json"));

    root.supersedes = [terminal.id];
    terminal.status = "superseded";
    terminal.supersededBy = root.id;
    writeFileSync(decisionPath, JSON.stringify(root));
    writeFileSync(terminalPath, JSON.stringify(terminal));
    assert.ok(collectContractErrors(workspacePath).some((error) => error.includes("supersession cycle")));
    root.supersedes = [];
    terminal.status = "accepted";
    terminal.supersededBy = null;
    writeFileSync(decisionPath, JSON.stringify(root));
    writeFileSync(terminalPath, JSON.stringify(terminal));

    successor.status = "accepted";
    successor.supersededBy = null;
    writeFileSync(successorPath, JSON.stringify(successor));
    rmSync(terminalPath);
    const previousSuccessor = structuredClone(successor);
    previousSuccessor.title = "base revision successor";
    successor.title = "current revision successor";
    writeFileSync(successorPath, JSON.stringify(successor));

    assert.ok(collectContractErrors(workspacePath, {
      previousArchitectureDecision: [structuredClone(root), previousSuccessor],
    }).some((error) => error.includes("in-place")));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 base-ref에서 전체 supersession chain을 읽는다", () => {
  const repository = mkdtempSync(join(tmpdir(), "architecture-chain-git-"));
  const previousCwd = process.cwd();
  try {
    mkdirSync(join(repository, "docs"), { recursive: true });
    const root = loadJson("contracts/documentation/ADR-HUB-0001.json");
    bindRootDecisionSchema(join(repository, "docs"), root);
    root.status = "superseded";
    root.supersededBy = "ADR-HUB-0002";
    const intermediate = structuredClone(root);
    intermediate.id = "ADR-HUB-0002";
    bindRootDecisionSchema(join(repository, "docs"), intermediate);
    intermediate.status = "superseded";
    intermediate.supersededBy = "ADR-HUB-0003";
    intermediate.supersedes = [root.id];
    const terminal = structuredClone(intermediate);
    terminal.id = "ADR-HUB-0003";
    bindRootDecisionSchema(join(repository, "docs"), terminal);
    terminal.status = "accepted";
    terminal.supersededBy = null;
    terminal.supersedes = [intermediate.id];
    writeFileSync(join(repository, "docs/ADR-HUB-0001.json"), JSON.stringify(root));
    writeFileSync(join(repository, "docs/ADR-HUB-0002.json"), JSON.stringify(intermediate));
    writeFileSync(join(repository, "docs/ADR-HUB-0003.json"), JSON.stringify(terminal));
    writeFileSync(join(repository, "docs/non-adr.json"), JSON.stringify({ id: "fixture-id", kind: "fixture" }));
    mkdirSync(join(repository, "docs/nested"));
    writeFileSync(join(repository, "docs/nested/duplicate.json"), JSON.stringify(intermediate));
    writeFileSync(join(repository, "workspace.json"), JSON.stringify({
      contracts: resolve(previousCwd, "contracts"),
      gateDirectories: { hub: resolve(previousCwd, "release/product-gates"), mobile: resolve(previousCwd, "apps/mobile/release") },
      datapackIndex: resolve(previousCwd, "apps/mobile/assets/datapacks/index.json"),
      sourceInventory: resolve(previousCwd, "apps/mobile/assets/datapacks/source-inventory.json"),
      governancePolicy: resolve(previousCwd, "tools/datapack/source-governance-policy.json"),
      freshnessPolicy: resolve(previousCwd, "release/product-gates/datapack-freshness-sla.json"),
      architectureDecision: "docs/ADR-HUB-0001.json",
      documentationSystemCatalog: resolve(previousCwd, "contracts/documentation/documentation-system-catalog.json"),
      productClaimCatalog: resolve(previousCwd, "contracts/documentation/product-claim-catalog.json"),
    }));
    const rootLevel = structuredClone(root);
    bindRootDecisionSchema(repository, rootLevel);
    rootLevel.status = "accepted";
    rootLevel.supersededBy = null;
    writeFileSync(join(repository, "ADR-HUB-0001.json"), JSON.stringify(rootLevel));
    const rootWorkspace = loadJson(join(repository, "workspace.json"));
    rootWorkspace.architectureDecision = "ADR-HUB-0001.json";
    writeFileSync(join(repository, "root-workspace.json"), JSON.stringify(rootWorkspace));
    mkdirSync(join(repository, "staged"));
    const stagedRoot = structuredClone(rootLevel);
    bindRootDecisionSchema(join(repository, "staged"), stagedRoot);
    const stagedSuccessor = structuredClone(stagedRoot);
    stagedSuccessor.id = "ADR-HUB-0002";
    bindRootDecisionSchema(join(repository, "staged"), stagedSuccessor);
    stagedSuccessor.status = "proposed";
    stagedSuccessor.title = "base staged successor";
    stagedSuccessor.supersedes = [stagedRoot.id];
    writeFileSync(join(repository, "staged/ADR-HUB-0001.json"), JSON.stringify(stagedRoot));
    writeFileSync(join(repository, "staged/ADR-HUB-0002.json"), JSON.stringify(stagedSuccessor));
    const stagedWorkspace = structuredClone(rootWorkspace);
    stagedWorkspace.architectureDecision = "staged/ADR-HUB-0001.json";
    writeFileSync(join(repository, "staged-workspace.json"), JSON.stringify(stagedWorkspace));
    mkdirSync(join(repository, "malformed"));
    const malformedRoot = structuredClone(root);
    bindRootDecisionSchema(join(repository, "malformed"), malformedRoot);
    malformedRoot.supersededBy = "ADR-HUB-0099";
    writeFileSync(join(repository, "malformed/ADR-HUB-0001.json"), JSON.stringify(malformedRoot));
    writeFileSync(join(repository, "malformed/ADR-HUB-0099.json"), "{");
    const malformedWorkspace = structuredClone(rootWorkspace);
    malformedWorkspace.architectureDecision = "malformed/ADR-HUB-0001.json";
    writeFileSync(join(repository, "malformed-workspace.json"), JSON.stringify(malformedWorkspace));
    for (const args of [["init"], ["config", "user.email", "test@example.com"], ["config", "user.name", "Test"], ["add", "."], ["commit", "-m", "base"]]) {
      fixtureGit(args, { cwd: repository, stdio: "ignore" });
    }
    const baseRef = fixtureGit(["rev-parse", "HEAD"], { cwd: repository, encoding: "utf8" }).trim();

    process.chdir(repository);
    assert.deepEqual(
      loadArchitectureDecisionAtRef("root-workspace.json", baseRef).map(({ id }) => id),
      ["ADR-HUB-0001"],
    );
    assert.throws(
      () => loadArchitectureDecisionAtRef("malformed-workspace.json", baseRef),
      /successor ADR 판정에 유효한 JSON이 필요하다/,
    );
    const stagedBase = loadArchitectureDecisionAtRef("staged-workspace.json", baseRef);
    const stagedDecisionSchemaPath = join(repository, "staged/ADR-HUB-0002-decision.schema.json");
    const stagedDecisionSchema = loadJson(stagedDecisionSchemaPath);
    stagedDecisionSchema.properties.futureField = { type: "string" };
    writeFileSync(stagedDecisionSchemaPath, JSON.stringify(stagedDecisionSchema));
    stagedSuccessor.status = "accepted";
    writeFileSync(join(repository, "staged/ADR-HUB-0002.json"), JSON.stringify(stagedSuccessor));
    assert.ok(collectContractErrors("staged-workspace.json", {
      previousArchitectureDecision: stagedBase,
    }).some((error) => error.includes("decision schema") && error.includes("status-only")));
    stagedSuccessor.status = "proposed";
    delete stagedDecisionSchema.properties.futureField;
    writeFileSync(stagedDecisionSchemaPath, JSON.stringify(stagedDecisionSchema));
    stagedSuccessor.status = "accepted";
    stagedSuccessor.title = "mutated current successor";
    writeFileSync(join(repository, "staged/ADR-HUB-0002.json"), JSON.stringify(stagedSuccessor));
    assert.ok(collectContractErrors("staged-workspace.json", {
      previousArchitectureDecision: stagedBase,
    }).some((error) => error.includes("status-only")));
    stagedRoot.status = "superseded";
    stagedRoot.supersededBy = stagedSuccessor.id;
    writeFileSync(join(repository, "staged/ADR-HUB-0001.json"), JSON.stringify(stagedRoot));
    assert.ok(collectContractErrors("staged-workspace.json", {
      previousArchitectureDecision: stagedBase,
    }).some((error) => error.includes("status-only")));
    const baseChain = loadArchitectureDecisionAtRef("workspace.json", baseRef);
    assert.deepEqual(
      baseChain.map(({ id }) => id),
      ["ADR-HUB-0001", "ADR-HUB-0002", "ADR-HUB-0003"],
    );
    const terminalDecisionSchemaPath = join(repository, "docs/ADR-HUB-0003-decision.schema.json");
    const terminalDecisionSchema = loadJson(terminalDecisionSchemaPath);
    terminalDecisionSchema.properties.futureField = { type: "string" };
    writeFileSync(terminalDecisionSchemaPath, JSON.stringify(terminalDecisionSchema));
    assert.ok(collectContractErrors("workspace.json", { previousArchitectureDecision: baseChain })
      .some((error) => error.includes("decision schema") && error.includes("in-place")));
    delete terminalDecisionSchema.properties.futureField;
    writeFileSync(terminalDecisionSchemaPath, JSON.stringify(terminalDecisionSchema));
    rmSync(join(repository, "docs/ADR-HUB-0002.json"));
    assert.ok(collectContractErrors("workspace.json", { previousArchitectureDecision: baseChain })
      .some((error) => error.includes("base ADR ADR-HUB-0002가 current chain에서 삭제되었다")));
  } finally {
    process.chdir(previousCwd);
    rmSync(repository, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 workspace ADR path redirect를 거부한다", () => {
  assert.ok(validateArchitectureDecisionWorkspaceTransition(
    { architectureDecision: "../documentation/ADR-HUB-0001.json" },
    { architectureDecision: "../documentation/ADR-HUB-0002.json" },
  ).some((error) => error.includes("path redirect")));
});

test("문서 거버넌스 계약은 PR·push base와 dispatch current-only CI 경로를 분리한다", () => {
  const validatorSource = readFileSync("tools/ci/check-contracts.mjs", "utf8");
  assert.doesNotMatch(validatorSource, /execFileSync\("git"/);
  assert.match(validatorSource, /execFileSync\("\/usr\/bin\/git"/);
  const workflow = readFileSync(".github/workflows/ci.yml", "utf8");
  assert.match(workflow,
    /Repository CI \/ Prepare active documentation fragment workspace[\s\S]{0,800}prepare-documentation-fragment-workspace\.mjs[\s\S]{0,800}documentation-fragment-workspace\.json/);
  assert.match(workflow,
    /Repository CI \/ Validate PR contract transitions[\s\S]{0,600}github\.event_name == 'pull_request'[\s\S]{0,600}--base-ref "\$\{BASE_REF\}"[\s\S]{0,300}--documentation-fragment-workspace/);
  assert.match(workflow,
    /Repository CI \/ Validate push contract transitions[\s\S]{0,600}github\.event_name == 'push'[\s\S]{0,600}github\.event\.before[\s\S]{0,600}--base-ref "\$\{BASE_REF\}"[\s\S]{0,300}--documentation-fragment-workspace/);
  assert.match(workflow,
    /Repository CI \/ Validate current contracts[\s\S]{0,600}github\.event_name == 'workflow_dispatch'[\s\S]{0,600}--current-only[\s\S]{0,300}--documentation-fragment-workspace/);
  assert.doesNotMatch(workflow, /Validate (?:PR|push|current) contract[^\n]*[\s\S]{0,500}--local-contracts-only/);
});

test("문서 거버넌스 계약은 workspace가 지정한 잘못된 ADR을 contract gate에서 거부한다", () => {
  const { directory, workspacePath } = createExternalWorkspace();
  try {
    const decisionPath = join(directory, "inputs/architecture-decision.json");
    const decision = loadJson(decisionPath);
    delete decision.decision;
    writeFileSync(decisionPath, JSON.stringify(decision));

    assert.ok(collectContractErrors(workspacePath).some((error) => (
      error.includes("architecture-decision.json: $.decision: 필수 필드 누락")
    )));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("contract gate의 ledger semantic path는 valid APPROVED와 TRANSFERRED를 허용한다", () => {
  const approved = loadJson("release/migrations/repository-split-issues.json");
  approved.issues[0].executionApproval = "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1";
  const transferred = structuredClone(approved);
  transferred.issues[0].targetUrl = "https://github.com/AquilaXk/easysubway-mobile/issues/1";
  transferred.issues[0].transferredAt = "2026-07-30T00:00:00.000Z";

  assert.deepEqual(validateRepositorySplitIssueLedger(approved), []);
  assert.deepEqual(validateRepositorySplitIssueLedger(transferred), []);
});

test("번들 datapack index 실물이 계약 스키마를 통과한다", () => {
  const schema = loadJson("contracts/datapack/datapack-index.schema.json");
  const index = loadJson("apps/mobile/assets/datapacks/index.json");

  assert.deepEqual(validateSchema(schema, index).errors, []);
});

test("번들 datapack index는 실재하지 않는 UTC 시각을 거부한다", () => {
  const errors = [];

  validateDatapackIndex({
    builtAt: "2026-02-31T00:00:00.000Z",
    qualityAsOf: "2026-07-12T25:00:00.000Z",
    freshnessExpiresAt: "2026-08-32T00:00:00.000Z",
  }, "index.json", errors);

  assert.deepEqual(errors, [
    "index.json: builtAt은 유효한 UTC 시각이어야 한다",
    "index.json: qualityAsOf은 유효한 UTC 시각이어야 한다",
    "index.json: freshnessExpiresAt은 유효한 UTC 시각이어야 한다",
  ]);
});

test("번들 datapack index semantic 검증은 비객체 입력에서 schema 오류를 가리지 않는다", () => {
  const directory = mkdtempSync(join(tmpdir(), "datapack-index-invalid-"));
  for (const [name, invalid] of [["null", null], ["array", []], ["string", "invalid"]]) {
    const valuePath = join(directory, `${name}.json`);
    writeFileSync(valuePath, JSON.stringify(invalid));
    const errors = [];

    assert.doesNotThrow(() => validateJson(
      "contracts/datapack/datapack-index.schema.json",
      valuePath,
      errors,
    ));
    assert.ok(errors.length > 0, `${name} 입력의 schema 오류가 필요하다`);
  }
});

test("번들 source-inventory 실물이 계약 스키마를 통과한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");

  assert.deepEqual(validateSchema(schema, inventory).errors, []);
});

test("UNMAPPED_RAW_SNAPSHOT schema는 raw admission과 non-production 빈 scope를 결합한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const raw = inventory.sources.find(({ coverageScope }) => coverageScope.mappingStatus === "UNMAPPED_RAW_SNAPSHOT");
  assert.ok(raw);
  assert.deepEqual(validateSchema(schema, inventory).errors, []);

  for (const mutate of [
    (source) => { delete source.rawSnapshotAdmission; },
    (source) => { source.requiredForProductionPack = true; },
    (source) => { delete source.productionUseAllowed; },
    (source) => { source.productionUseAllowed = true; },
    (source) => { source.capabilities.facility.productionUseAllowed = true; },
    (source) => { source.coverageScope.regionIds.push("capital"); },
    (source) => { source.coverageScope.operatorIds.push("seoul-metro"); },
  ]) {
    const invalid = structuredClone(inventory);
    mutate(invalid.sources.find(({ id }) => id === raw.id));
    assert.ok(validateSchema(schema, invalid).errors.some((error) => error.includes("oneOf")));
  }
});

test("accessibility admission evidence는 기존형과 source-governance형 필수 필드를 각각 유지한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  for (const [selector, requiredField] of [
    [(evidence) => evidence.materializer != null, "materializer"],
    [(evidence) => evidence.decision != null, "decision"],
  ]) {
    const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
    const source = inventory.sources.find(({ accessibilityAdmissionEvidence: evidence }) => evidence && selector(evidence));
    delete source.accessibilityAdmissionEvidence[requiredField];
    assert.ok(validateSchema(schema, inventory).errors.some((error) => (
      error.includes("accessibilityAdmissionEvidence: oneOf")
    )));
  }

  const combined = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const legacy = combined.sources.find((source) => source.accessibilityAdmissionEvidence?.materializer != null);
  const governed = combined.sources.find((source) => source.accessibilityAdmissionEvidence?.decision != null);
  Object.assign(legacy.accessibilityAdmissionEvidence, governed.accessibilityAdmissionEvidence);
  assert.ok(validateSchema(schema, combined).errors.some((error) => (
    error.includes("accessibilityAdmissionEvidence: oneOf")
  )));
});

test("source quota defaultDailyLimit는 허용된 scalar만 받는다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const admitted = inventory.sources.find((source) => source.admissionEvidence?.quotaEvidence != null);
  admitted.admissionEvidence.quotaEvidence.defaultDailyLimit = { unexpected: true };

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("quotaEvidence.defaultDailyLimit")
  )));
});

test("source admission evidence가 있으면 license evidence hash를 요구한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const admitted = inventory.sources.find((source) => source.admissionEvidence != null);
  delete admitted.admissionEvidence.licenseEvidenceHash;

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("admissionEvidence.licenseEvidenceHash")
  )));
});

test("source admission evidence envelope는 승인 필드 외 값을 거부하고 선택적으로 남는다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const admitted = inventory.sources.find((source) => source.admissionEvidence != null);
  admitted.admissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("admissionEvidence.serviceKey")
  )));

  delete admitted.admissionEvidence;
  assert.deepEqual(validateSchema(schema, inventory).errors, []);
});

test("inventory production 사용 승인은 domain별 admission evidence를 요구한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const admissionDomains = new Set([
    "route_graph_topology",
    "schedule_timetable",
    "station_line_membership",
    "route_map_positions",
    "accessibility_facilities",
  ]);
  const provenanceOnlySource = inventory.sources.find((source) => source.productionUseAllowed === false
    && !source.coverageScope.sourceDomains.some((domain) => admissionDomains.has(domain)));

  assert.ok(provenanceOnlySource, "production 사용 금지 source fixture가 필요하다");
  assert.deepEqual(validateSchema(schema, inventory).errors, []);

  provenanceOnlySource.productionUseAllowed = true;
  const errors = [];
  validateSourceInventory(inventory, "source-inventory.json", errors);
  assert.deepEqual(errors, [
    `source-inventory.json: $.sources.${inventory.sources.indexOf(provenanceOnlySource)}.productionUseAllowed: true는 production admission evidence가 필요하다`,
  ]);

  provenanceOnlySource.productionUseAllowed = false;
  errors.length = 0;
  const scheduleSource = inventory.sources.find((source) => source.scheduleAdmissionEvidence != null);
  scheduleSource.productionUseAllowed = false;
  validateSourceInventory(inventory, "source-inventory.json", errors);
  assert.equal(errors.at(-1),
    `source-inventory.json: $.sources.${inventory.sources.indexOf(scheduleSource)}.scheduleAdmissionEvidence: productionUseAllowed true가 필요하다`);
  assert.doesNotThrow(() => validateSourceInventory({ sources: {} }, "source-inventory.json", []));
});

test("production admission evidence는 coverage source domain과 일치해야 한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const topologySource = inventory.sources.find((source) => source.topologyAdmissionEvidence != null);
  const scheduleSource = inventory.sources.find((source) => source.scheduleAdmissionEvidence != null);
  const scheduleEvidence = structuredClone(scheduleSource.scheduleAdmissionEvidence);
  delete topologySource.topologyAdmissionEvidence;
  topologySource.scheduleAdmissionEvidence = scheduleEvidence;

  const errors = [];
  validateSourceInventory(inventory, "source-inventory.json", errors);

  assert.ok(errors.some((error) => error.includes("route_graph_topology production 승인은 topologyAdmissionEvidence가 필요하다")));
  assert.ok(errors.some((error) => error.includes("scheduleAdmissionEvidence: schedule_timetable source domain이 필요하다")));
});

test("membership production admission evidence는 domain과 production 승인을 함께 요구한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const membershipSource = inventory.sources.find((source) => source.membershipAdmissionEvidence != null);
  delete membershipSource.membershipAdmissionEvidence;

  const missingErrors = [];
  validateSourceInventory(inventory, "source-inventory.json", missingErrors);
  assert.ok(missingErrors.some((error) => error.includes(
    "station_line_membership production 승인은 membershipAdmissionEvidence가 필요하다",
  )));

  const freshInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const mismatchedSource = freshInventory.sources.find((source) => source.membershipAdmissionEvidence != null);
  mismatchedSource.coverageScope.sourceDomains = mismatchedSource.coverageScope.sourceDomains
    .filter((domain) => domain !== "station_line_membership");
  const mismatchedErrors = [];
  validateSourceInventory(freshInventory, "source-inventory.json", mismatchedErrors);
  assert.ok(mismatchedErrors.some((error) => error.includes(
    "membershipAdmissionEvidence: station_line_membership source domain이 필요하다",
  )));
});

test("route map production admission evidence는 domain과 production 승인을 함께 요구한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const routeMapSource = inventory.sources.find((source) => source.routeMapAdmissionEvidence != null);
  delete routeMapSource.routeMapAdmissionEvidence;

  const missingErrors = [];
  validateSourceInventory(inventory, "source-inventory.json", missingErrors);
  assert.ok(missingErrors.some((error) => error.includes(
    "route_map_positions production 승인은 routeMapAdmissionEvidence가 필요하다",
  )));

  const freshInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const mismatchedSource = freshInventory.sources.find((source) => source.routeMapAdmissionEvidence != null);
  mismatchedSource.coverageScope.sourceDomains = mismatchedSource.coverageScope.sourceDomains
    .filter((domain) => domain !== "route_map_positions");
  const mismatchedErrors = [];
  validateSourceInventory(freshInventory, "source-inventory.json", mismatchedErrors);
  assert.ok(mismatchedErrors.some((error) => error.includes(
    "routeMapAdmissionEvidence: route_map_positions source domain이 필요하다",
  )));

  const prohibitedInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const prohibitedSource = prohibitedInventory.sources.find((source) => source.routeMapAdmissionEvidence != null);
  prohibitedSource.productionUseAllowed = false;
  const prohibitedErrors = [];
  validateSourceInventory(prohibitedInventory, "source-inventory.json", prohibitedErrors);
  assert.ok(prohibitedErrors.some((error) => error.includes(
    "routeMapAdmissionEvidence: productionUseAllowed true가 필요하다",
  )));
});

test("accessibility production admission evidence는 domain과 production 승인을 함께 요구한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const accessibilitySource = inventory.sources.find((source) => source.accessibilityAdmissionEvidence != null);
  delete accessibilitySource.accessibilityAdmissionEvidence;

  const missingErrors = [];
  validateSourceInventory(inventory, "source-inventory.json", missingErrors);
  assert.ok(missingErrors.some((error) => error.includes(
    "accessibility_facilities production 승인은 accessibilityAdmissionEvidence가 필요하다",
  )));

  const freshInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const mismatchedSource = freshInventory.sources.find((source) => source.accessibilityAdmissionEvidence != null);
  mismatchedSource.coverageScope.sourceDomains = mismatchedSource.coverageScope.sourceDomains
    .filter((domain) => domain !== "accessibility_facilities");
  const mismatchedErrors = [];
  validateSourceInventory(freshInventory, "source-inventory.json", mismatchedErrors);
  assert.ok(mismatchedErrors.some((error) => error.includes(
    "accessibilityAdmissionEvidence: accessibility_facilities source domain이 필요하다",
  )));

  const prohibitedInventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const prohibitedSource = prohibitedInventory.sources.find((source) => source.accessibilityAdmissionEvidence != null);
  prohibitedSource.productionUseAllowed = false;
  const prohibitedErrors = [];
  validateSourceInventory(prohibitedInventory, "source-inventory.json", prohibitedErrors);
  assert.ok(prohibitedErrors.some((error) => error.includes(
    "accessibilityAdmissionEvidence: productionUseAllowed true가 필요하다",
  )));
});

test("source inventory semantic 검증은 schema-invalid sourceDomains에서 오류 수집을 중단하지 않는다", () => {
  assert.doesNotThrow(() => validateSourceInventory({
    sources: [{ coverageScope: { sourceDomains: 1 } }],
  }, "source-inventory.json", []));
});

test("topology admission evidence는 승인 필드 외 값을 거부한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const topologySource = inventory.sources.find((source) => source.topologyAdmissionEvidence != null);

  topologySource.topologyAdmissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("topologyAdmissionEvidence.serviceKey")
  )));
});

test("schedule admission evidence는 승인 필드 외 값을 거부한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const scheduleSource = inventory.sources.find((source) => source.scheduleAdmissionEvidence != null);

  scheduleSource.scheduleAdmissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("scheduleAdmissionEvidence.serviceKey")
  )));
});

test("membership admission evidence는 승인 필드 외 값을 거부한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const membershipSource = inventory.sources.find((source) => source.membershipAdmissionEvidence != null);

  membershipSource.membershipAdmissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("membershipAdmissionEvidence.serviceKey")
  )));
});

test("route map admission evidence는 승인 필드 외 값을 거부한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const routeMapSource = inventory.sources.find((source) => source.routeMapAdmissionEvidence != null);

  routeMapSource.routeMapAdmissionEvidence.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("routeMapAdmissionEvidence.serviceKey")
  )));

  const currentTopologySource = inventory.sources.find((source) =>
    source.routeMapAdmissionEvidence?.currentTopologyAdmission != null);
  currentTopologySource.routeMapAdmissionEvidence.currentTopologyAdmission.serviceKey = "must-never-enter-contract";

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("currentTopologyAdmission.serviceKey")
  )));
});

test("capital topology route-map source는 currentTopologyAdmission을 필수로 요구한다", () => {
  const schema = loadJson("contracts/datapack/source-inventory.schema.json");
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const source = inventory.sources.find((entry) =>
    entry.routeMapAdmissionEvidence?.topologySourceId === "capital-route-topology");
  assert.ok(source);
  delete source.routeMapAdmissionEvidence.currentTopologyAdmission;

  assert.ok(validateSchema(schema, inventory).errors.some((error) => (
    error.includes("routeMapAdmissionEvidence")
      && error.includes("oneOf 분기 정확히 하나")
  )));
});

test("boundaries.json이 스스로 정합하다", () => {
  const boundaries = loadJson("contracts/boundaries.json");

  assert.equal(boundaries.schemaVersion, 2);
  for (const targetName of boundaries.splitOrder) {
    const target = boundaries.extractionTargets[targetName];
    assert.ok(target, `splitOrder의 ${targetName} extraction target이 없다`);
    for (const area of target.sourceAreas) {
      assert.ok(area in boundaries.areas, `${targetName}의 ${area} area가 없다`);
    }
  }
});

test("boundaries v2는 모든 target과 정확히 한 번의 splitOrder를 요구한다", () => {
  const boundaries = loadJson("contracts/boundaries.json");
  const missing = structuredClone(boundaries);
  missing.splitOrder = ["data", "platform", "backend"];
  const extra = structuredClone(boundaries);
  extra.splitOrder = [...extra.splitOrder, "unknown"];
  const duplicate = structuredClone(boundaries);
  duplicate.splitOrder = ["data", "platform", "backend", "backend", "mobile"];
  const absent = structuredClone(boundaries);
  delete absent.extractionTargets.mobile;
  absent.splitOrder = absent.splitOrder.filter((target) => target !== "mobile");

  assert.ok(validateBoundariesPayload(missing).some((error) => error.includes("mobile splitOrder 누락")));
  assert.ok(validateBoundariesPayload(extra).some((error) => error.includes("unknown extraction target 누락")));
  assert.ok(validateBoundariesPayload(duplicate).some((error) => error.includes("backend splitOrder 중복")));
  assert.ok(validateBoundariesPayload(absent).some((error) => error.includes("mobile extraction target 누락")));
  assert.ok(validateBoundariesPayload(absent).some((error) => error.includes("mobile splitOrder 누락")));
});

test("boundaries v2는 malformed repository, source area, global root 충돌을 거부한다", () => {
  const boundaries = loadJson("contracts/boundaries.json");
  const malformed = structuredClone(boundaries);
  malformed.extractionTargets.data.repository = "AquilaXk/not-easysubway";
  malformed.extractionTargets.platform.sourceAreas = ["missing-area"];
  malformed.extractionTargets.backend.sourceAreas = ["mobile"];
  malformed.extractionTargets.mobile.partialRoots.push("tools/route-map");

  const errors = validateBoundariesPayload(malformed);
  assert.ok(errors.some((error) => error.includes("data repository 불량")));
  assert.ok(errors.some((error) => error.includes("platform.missing-area area 누락")));
  assert.ok(errors.some((error) => error.includes("mobile sourceArea가 backend, mobile에 중복 귀속됨")));
  assert.ok(errors.some((error) => error.includes("mobile.tools/route-map partialRoots가 ownedRoots와 겹친다")));
});

test("boundaries v2는 target 이름과 repository를 정확히 고정한다", () => {
  const boundaries = loadJson("contracts/boundaries.json");
  boundaries.extractionTargets.backend.repository = "AquilaXk/easysubway-mobile";
  boundaries.extractionTargets.unknown = {
    ...structuredClone(boundaries.extractionTargets.data),
  };
  boundaries.splitOrder.push("unknown");

  const errors = validateBoundariesPayload(boundaries);
  assert.ok(errors.some((error) => error.includes("backend repository 불량")));
  assert.ok(errors.some((error) => error.includes("unknown extraction target 불량")));
});

test("boundaries v2는 extraction target ownership metadata의 배열·빈 값·중복을 거부한다", () => {
  const boundaries = loadJson("contracts/boundaries.json");
  const cases = [
    ["missing", (target) => { delete target.sourceAreas; }],
    ["non-array", (target) => { target.ownedRoots = "tools/route-map"; }],
    ["empty array", (target) => { target.partialRoots = []; }],
    ["empty string", (target) => { target.sourceAreas = [""]; }],
    ["duplicate", (target) => { target.partialRoots = ["tools/routes", "tools/routes"]; }],
  ];
  for (const [name, mutate] of cases) {
    const malformed = structuredClone(boundaries);
    mutate(malformed.extractionTargets.data);
    assert.ok(validateBoundariesPayload(malformed).length > 0, `${name} ownership metadata 오류가 필요하다`);
  }
});

test("check-contracts CLI 검증 오류가 없다", () => {
  assert.deepEqual(collectContractErrors(undefined, {
    documentationFragmentResolution: "LOCAL_CONTRACTS_ONLY",
  }), []);
});

test("check-contracts는 inventory·freshness·governance 참조를 함께 검증한다", () => {
  const inventory = loadJson("apps/mobile/assets/datapacks/source-inventory.json");
  const freshnessPolicy = loadJson("release/product-gates/datapack-freshness-sla.json");
  const governancePolicy = loadJson("tools/datapack/source-governance-policy.json");
  governancePolicy.sources[0].retentionClassId = "missing-retention-class";
  const errors = [];

  validateSourceGovernanceContracts({ governancePolicy, inventory, freshnessPolicy }, errors);

  assert.equal(errors.length, 1);
  assert.match(errors[0], /RAW_RETENTION_OVERDUE/);
});

test("필수 계약 입력 파일이 없으면 실패한다", () => {
  const errors = [];

  validateJson("contracts/missing.schema.json", "contracts/missing-value.json", errors);

  assert.deepEqual(errors, ["contracts/missing.schema.json 누락", "contracts/missing-value.json 누락"]);
});

test("유효하지 않은 JSON은 예외 대신 계약 오류로 수집한다", () => {
  const directory = mkdtempSync(join(tmpdir(), "easysubway-contract-"));
  const schemaPath = join(directory, "schema.json");
  const valuePath = join(directory, "value.json");
  writeFileSync(schemaPath, JSON.stringify({ type: "object" }));
  writeFileSync(valuePath, "{");
  const errors = [];

  try {
    assert.equal(validateJson(schemaPath, valuePath, errors), false);
    assert.deepEqual(errors, [`${valuePath}: 유효한 JSON이 필요하다`]);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("v1 datapack manifest는 activePack을 요구하고 v2는 생략할 수 있다", () => {
  const errors = [];

  validateDatapackManifest({ ttlSeconds: 1, packs: [] }, "manifest-v1.json", errors);
  validateDatapackManifest(minimalV2Manifest(), "manifest-v2.json", errors);

  assert.deepEqual(errors, ["manifest-v1.json: manifestVersion 1은 activePack이 필요하다"]);
});

test("v2 datapack manifest는 envelope 필드를 요구한다", () => {
  const errors = [];

  validateDatapackManifest({ manifestVersion: 2, ttlSeconds: 1, packs: [] }, "manifest-v2.json", errors);

  assert.deepEqual(errors, [
    "manifest-v2.json: manifestVersion 2는 signature이 필요하다",
    "manifest-v2.json: manifestVersion 2는 keyId이 필요하다",
    "manifest-v2.json: manifestVersion 2는 channel이 필요하다",
    "manifest-v2.json: manifestVersion 2는 releaseSequence이 필요하다",
    "manifest-v2.json: manifestVersion 2는 publishedAt이 필요하다",
    "manifest-v2.json: manifestVersion 2는 expiresAt이 필요하다",
  ]);
});

test("datapack manifest rollout percentage는 100을 넘을 수 없다", () => {
  const errors = [];

  validateDatapackManifest(
    {
      ttlSeconds: 1,
      activePack: { id: "capital", version: "1" },
      rollout: { percentage: 101 },
      packs: [],
    },
    "manifest-v1.json",
    errors,
  );

  assert.deepEqual(errors, ["manifest-v1.json: rollout.percentage는 100 이하여야 한다"]);
});

test("datapack manifest 스키마는 production URL과 RSA 서명을 허용한다", () => {
  const schema = loadJson("contracts/datapack/datapack-manifest.schema.json");
  const manifest = {
    ttlSeconds: 1,
    activePack: { id: "capital", version: "1" },
    packs: [
      {
        id: "capital",
        version: "1",
        artifactKind: "production",
        url: "https://cdn.easysubway.kr/releases/catalog/capital-v1.sqlite.gz",
        sha256: "a".repeat(64),
        sqliteSha256: "b".repeat(64),
        sizeBytes: 1,
        signature: {
          algorithm: "rsa-sha256-pack-manifest-v1",
          value: "rsaSha256PackSignature_1",
        },
        schemaVersion: "1",
        sourceInventory: [{ id: "official-source", licenseStatus: "redistributable", updatedAt: "2026-07-07" }],
        regionalQualityMetrics: {},
        representativeRouteRegressions: [],
        representativeRouteRegressionSignature: {
          algorithm: "rsa-sha256-route-regression-v1",
          value: "rsaSha256RouteSignature_1",
        },
        requiredTables: ["stations"],
        minimumTableRows: { stations: 1 },
      },
    ],
  };

  assert.deepEqual(validateSchema(schema, manifest).errors, []);
});

test("OpenAPI 문서가 golden fixture 목록과 정합하다", () => {
  if (!existsSync("contracts/api")) return;
  const reportDoc = readFileSync("contracts/api/report-api.openapi.yaml", "utf8");
  for (const apiPath of ["/api/v1/report-uploads", "/api/v1/reports", "/api/v1/reports/{reportId}"]) {
    assert.ok(reportDoc.includes(`${apiPath}:`), `OpenAPI에 ${apiPath} 누락`);
  }
  for (const fixture of ["report-upload-intent.created.json", "report-status.ok.json"]) {
    assert.ok(existsSync(`contracts/api/fixtures/${fixture}`), `${fixture} 누락`);
  }
});

test("datapack compatibility matrix가 번들 index schemaVersion을 허용한다", () => {
  const matrix = loadJson("contracts/datapack/compatibility-matrix.json");
  const index = loadJson("apps/mobile/assets/datapacks/index.json");

  assert.ok(
    matrix.mobile.some((mobile) => mobile.acceptsIndexSchemaVersions.includes(index.schemaVersion)),
    "현재 번들 index schemaVersion을 허용하는 mobile 범위가 없다",
  );
});

test("datapack compatibility matrix는 현재 번들을 지원하는 mobile 행 하나를 요구한다", () => {
  const errors = [];

  validateCompatibilityMatrixPayload(
    {
      mobile: [
        { appVersionRange: "<1.0.0", acceptsIndexSchemaVersions: [0] },
        { appVersionRange: ">=1.0.0", acceptsIndexSchemaVersions: [1] },
      ],
    },
    { schemaVersion: 1 },
    errors,
  );

  assert.deepEqual(errors, []);
});

test("gate-index는 ownerComponent별 gate 디렉터리 실물과 1:1 대응한다", () => {
  const errors = collectContractErrors().filter((error) => error.includes("gate-index"));

  assert.deepEqual(errors, []);
  const index = loadJson("contracts/release/gate-index.json");
  assert.deepEqual(
    new Set(index.gates.filter((gate) => gate.scope === "product").map((gate) => gate.ownerComponent)),
    new Set(["hub"]),
  );
  assert.deepEqual(
    new Set(index.gates.filter((gate) => gate.scope === "mobile").map((gate) => gate.ownerComponent)),
    new Set(["mobile"]),
  );
});

test("[gate-ownership] gate-index는 owner 간에도 gate.file 중복을 거부한다", () => {
  const directory = mkdtempSync(join(tmpdir(), "gate-index-duplicate-"));
  try {
    const indexPath = join(directory, "gate-index.json");
    const index = loadJson("contracts/release/gate-index.json");
    const duplicate = structuredClone(index.gates.find((gate) => gate.ownerComponent === "hub"));
    duplicate.scope = "mobile";
    duplicate.ownerComponent = "mobile";
    index.gates.push(duplicate);
    writeFileSync(indexPath, JSON.stringify(index));
    const errors = [];

    validateGateIndex(errors, indexPath, {
      hub: "release/product-gates",
      mobile: "apps/mobile/release",
    });

    assert.ok(errors.some((error) => error.includes(`${duplicate.file} gate.file 중복`)));
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("[gate-ownership] gate-index 누락은 계약 오류로 수집한다", () => {
  const errors = [];

  validateGateIndex(errors, "contracts/release/missing-gate-index.json", {
    hub: "release/product-gates",
    mobile: "apps/mobile/release",
  });

  assert.deepEqual(errors, ["contracts/release/missing-gate-index.json 누락"]);
});

test("env-scope-map이 .env.example 키와 1:1 대응한다", () => {
  const errors = collectContractErrors().filter((error) => error.includes("env-scope-map"));

  assert.deepEqual(errors, []);
});

function minimalV2Manifest() {
  return {
    manifestVersion: 2,
    ttlSeconds: 1,
    signature: { algorithm: "sha256-manifest-v2", value: "a".repeat(64) },
    keyId: "fixture",
    channel: "stable",
    releaseSequence: 1,
    publishedAt: "2026-07-07T00:00:00.000Z",
    expiresAt: "2026-07-08T00:00:00.000Z",
    packs: [],
  };
}
