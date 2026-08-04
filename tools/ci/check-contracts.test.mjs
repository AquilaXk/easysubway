import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative, resolve } from "node:path";
import {
  collectContractErrors,
  loadWorkspace,
  loadJson,
  validateCompatibilityMatrixPayload,
  validateDatapackIndex,
  validateDatapackManifest,
  validateJson,
  validateSourceInventory,
  validateSourceGovernanceContracts,
  validateBoundariesPayload,
  validateRepositorySplitIssueLedger,
  validateArchitectureDecision,
  validateArchitectureDecisionTransition,
  validateArchitectureDecisionWorkspaceTransition,
  validateGateIndex,
} from "./check-contracts.mjs";
import { validateSchema } from "./lib/json-schema-lite.mjs";

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
  const workspacePath = join(directory, "hub.json");
  writeFileSync(workspacePath, JSON.stringify({
    contracts: relative(directory, resolve("contracts")),
    gateDirectories: { hub: "gates/hub", mobile: "gates/mobile" },
    datapackIndex: "inputs/datapack-index.json",
    sourceInventory: "inputs/source-inventory.json",
    governancePolicy: "inputs/governance-policy.json",
    freshnessPolicy: "inputs/freshness-policy.json",
    architectureDecision: "inputs/architecture-decision.json",
  }));
  copy("contracts/documentation/ADR-HUB-0001.json", "inputs/architecture-decision.json");
  return { directory, workspacePath };
}

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
  const run = (args) => execFileSync("node", ["tools/ci/check-contracts.mjs", ...args], {
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

test("repository split issue migration ledger가 계약 gate를 통과한다", () => {
  const errors = collectContractErrors().filter((error) => error.includes("repository-split-issues"));

  assert.deepEqual(errors, []);
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
  assert.ok(adr.confirmation.some(({ method }) => method.endsWith("--current-only")));
});

test("문서 거버넌스 계약은 대표적인 ADR 계약 위반을 거부한다", () => {
  const directory = mkdtempSync(join(tmpdir(), "architecture-decision-contract-"));
  try {
    const schemaPath = "contracts/documentation/architecture-decision.schema.json";
    const valid = loadJson("contracts/documentation/ADR-HUB-0001.json");
    for (const [name, mutate] of [
      ["invalid-id", (adr) => { adr.id = "ADR-DATA-0001"; }],
      ["invalid-kind", (adr) => { adr.kind = "runbook"; }],
      ["missing-owner", (adr) => { delete adr.owner; }],
      ["owner-prefix-mismatch", (adr) => { adr.owner.repository = "AquilaXk/easysubway-data"; }],
      ["invalid-status", (adr) => { adr.status = "implemented"; }],
      ["missing-decision", (adr) => { delete adr.decision; }],
      ["missing-context-issue", (adr) => { delete adr.contextIssue; }],
      ["wrong-context-issue", (adr) => { adr.contextIssue = "https://github.com/AquilaXk/easysubway/issues/1"; }],
      ["unknown-field", (adr) => { adr.futureField = true; }],
      ["target-owner-mismatch", (adr) => { adr.decision.repositoryOwners.data = "AquilaXk/easysubway"; }],
      ["tracked-sensitive-evidence", (adr) => { adr.decision.sensitiveEvidence.trackedContentAllowed = true; }],
      ["malformed-supersedes", (adr) => { adr.supersedes = 1; }],
      ["no-chosen-option", (adr) => { adr.consideredOptions.forEach((option) => { option.chosen = false; }); }],
      ["multiple-chosen-options", (adr) => { adr.consideredOptions.forEach((option) => { option.chosen = true; }); }],
      ["duplicate-option-id", (adr) => { adr.consideredOptions[1].id = adr.consideredOptions[0].id; }],
    ]) {
      const candidate = structuredClone(valid);
      mutate(candidate);
      const candidatePath = join(directory, `${name}.json`);
      writeFileSync(candidatePath, JSON.stringify(candidate));
      const errors = [];

      assert.equal(validateJson(schemaPath, candidatePath, errors), false, name);
      assert.ok(errors.length > 0, `${name} 오류가 필요하다`);
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
    writeFileSync(join(directory, "inputs/ADR-HUB-0002.json"), JSON.stringify(successor));
    writeFileSync(join(directory, "inputs/unrelated-malformed.json"), "{");

    assert.deepEqual(collectContractErrors(workspacePath, { previousArchitectureDecision: previous }), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("문서 거버넌스 계약은 workspace ADR path redirect를 거부한다", () => {
  assert.ok(validateArchitectureDecisionWorkspaceTransition(
    { architectureDecision: "../documentation/ADR-HUB-0001.json" },
    { architectureDecision: "../documentation/ADR-HUB-0002.json" },
  ).some((error) => error.includes("path redirect")));
});

test("문서 거버넌스 계약은 PR base와 non-PR current-only CI 경로를 분리한다", () => {
  const validatorSource = readFileSync("tools/ci/check-contracts.mjs", "utf8");
  assert.doesNotMatch(validatorSource, /execFileSync\("git"/);
  assert.match(validatorSource, /execFileSync\("\/usr\/bin\/git"/);
  const workflow = readFileSync(".github/workflows/ci.yml", "utf8");
  assert.match(workflow,
    /Repository CI \/ Validate PR contract transitions[\s\S]{0,400}github\.event_name == 'pull_request'[\s\S]{0,400}--base-ref "\$\{BASE_REF\}"/);
  assert.match(workflow,
    /Repository CI \/ Validate current contracts[\s\S]{0,400}github\.event_name != 'pull_request'[\s\S]{0,400}--current-only/);
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
  assert.deepEqual(collectContractErrors(), []);
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
