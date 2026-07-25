#!/usr/bin/env node
// #2507 전국 270 coverage 집계 정본화 — tally 도구(tracked ledger 생성기).
//
// #2138 전국 requirement 진행 집계를 이슈 코멘트 수기 집계에서 재현 가능한 커밋 산출물로 옮긴다.
// requirement 분모는 targets의 activeLineScopes × requiredSourceDomains이며, LAUNCH_REQUIRED tier가
// 270건(45 scope × 6 domain), ENHANCEMENT tier가 45건(45 scope × 1 domain)이다.
//
// 입력:
//   --targets     tools/datapack/nationwide-coverage-targets.json (분모·domain 계약 정본)
//   --inventory   tools/datapack/source-inventory.json (coverageScope admission 정본)
//   --resolutions EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE 정본. 생략하면 DEFAULT_RESOLUTIONS_PATH.
//                 (경로를 인자로 받는 이유: resolutions 문서는 재생성 시 파일이 교체된다.)
//   --output      ledger 출력 경로
//   --expected-launch-required-total  분모 drift fail-closed용 기대값(선택). 계산된 LAUNCH_REQUIRED
//                 분모와 다르면 실패한다.
//
// 상태 축(이 ledger가 산출하는 축):
//   INVENTORY_ADMITTED                  source-inventory coverageScope의 (operatorIds, lineIds,
//                                       sourceDomains) 엄격 매칭으로 domain requiredFields를
//                                       blockingThreshold 이상 충족.
//   EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE resolutions 문서의 정본 판정.
//   MISSING                              그 외. dual-operator 미매칭 여부를 하위 구분으로 남긴다.
//
// 범위 밖(별도 축):
//   provenance 기반 게이트 SUPPORTED 판정(report-coverage-gaps.mjs --manifest/--provenance)은 이
//   도구의 축이 아니다. INVENTORY_ADMITTED는 admission 근사치이며 게이트 통과를 뜻하지 않는다.
//   resolutions entry의 만료(nextReviewAt) 재검토 판정도 wall-clock에 의존하므로 게이트 몫이다.
//
// 판정 의미론은 report-coverage-gaps.mjs의 evaluateRequirements/coveredField와 어긋나면 안 된다.
// 특히 빈 lineIds는 와일드카드가 아니다(strictLineScope=true와 동일). 이 도구는 게이트의
// requireProvenance=false 경로(= inventory fieldsProvided 매칭)에 대응한다.
//
// 결정성: 같은 입력 → 같은 출력 바이트. wall-clock(Date.now/new Date)을 쓰지 않고 시각 값은
// 입력 파일에서만 유도한다. 정렬은 로케일 무관 코드포인트 비교로 고정한다.
//
// 사용: node tools/datapack/build-nationwide-coverage-tally.mjs \
//   --targets tools/datapack/nationwide-coverage-targets.json \
//   --inventory tools/datapack/source-inventory.json \
//   --resolutions tools/datapack/release/nationwide-public-api-coverage-resolutions-20260721.json \
//   --expected-launch-required-total 270 \
//   --output tools/datapack/reports/nationwide-coverage-tally.json
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";
import { parseArgs, requireArg, sortJson } from "./lib/ledger-admission-cli.mjs";

export const DEFAULT_RESOLUTIONS_PATH =
  "tools/datapack/release/nationwide-public-api-coverage-resolutions-20260721.json";
// 재생성 명령에 기록하는 tracked ledger 경로. --output이 임시 경로여도 산출 바이트가 달라지지
// 않도록 명령 문자열은 이 상수를 쓴다(재현성 검증이 임시 출력으로 가능해야 한다).
export const LEDGER_PATH = "tools/datapack/reports/nationwide-coverage-tally.json";
const TOOL_PATH = "tools/datapack/build-nationwide-coverage-tally.mjs";
const ALLOWED_FLAGS = new Set([
  "targets",
  "inventory",
  "resolutions",
  "output",
  "expected-launch-required-total",
]);
const TALLY_STATUSES = ["INVENTORY_ADMITTED", "EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE", "MISSING"];
const MISSING_KINDS = ["DUAL_OPERATOR_UNMATCHED", "NO_ADMITTED_SOURCE"];
const RELEASE_TIERS = ["LAUNCH_REQUIRED", "ENHANCEMENT"];

export function buildNationwideCoverageTally({
  targets,
  inventory,
  resolutions,
  inputs,
  expectedLaunchRequiredTotal = null,
}) {
  validateTargets(targets);
  validateInventory(inventory);
  const sources = inventory.sources.map(normalizeSource);
  const scopes = [...targets.activeLineScopes]
    .map(({ regionId, operatorId, lineId }) => ({ regionId, operatorId, lineId }))
    .sort(compareScopes);
  const domains = [...targets.requiredSourceDomains].sort((left, right) =>
    codepointCompare(left.id, right.id));
  const resolutionIndex = indexResolutions(targets, resolutions, scopes, domains);

  const requirements = scopes.flatMap((scope) =>
    domains.map((domain) => evaluateRequirement(scope, domain, sources, resolutionIndex)));
  const tiers = Object.fromEntries(RELEASE_TIERS.map((releaseTier) => [
    releaseTier,
    summarizeTier(requirements, releaseTier, domains, scopes),
  ]));

  const launchRequiredDomainCount = domains.filter(
    ({ releaseTier }) => releaseTier === "LAUNCH_REQUIRED").length;
  const enhancementDomainCount = domains.filter(
    ({ releaseTier }) => releaseTier === "ENHANCEMENT").length;
  const launchRequiredTotal = tiers.LAUNCH_REQUIRED.totalCount;
  // 분모 drift fail closed: scope × domain 곱과 어긋나면 집계를 신뢰할 수 없다.
  if (launchRequiredTotal !== scopes.length * launchRequiredDomainCount) {
    throw new Error(
      `launch-required denominator is inconsistent: ${launchRequiredTotal} != ` +
        `${scopes.length} scopes × ${launchRequiredDomainCount} domains`,
    );
  }
  if (expectedLaunchRequiredTotal !== null && launchRequiredTotal !== expectedLaunchRequiredTotal) {
    throw new Error(
      `launch-required denominator drift: expected ${expectedLaunchRequiredTotal}, ` +
        `computed ${launchRequiredTotal}`,
    );
  }

  return {
    schemaVersion: 1,
    artifactKind: "nationwide-coverage-tally-ledger",
    issue: 2507,
    parentIssue: 2138,
    targetVersion: targets.targetVersion,
    regeneration: {
      command: regenerationCommand(inputs, expectedLaunchRequiredTotal),
      ledgerPath: LEDGER_PATH,
    },
    statusAxis: {
      values: [...TALLY_STATUSES],
      missingKinds: [...MISSING_KINDS],
      inventoryAdmittedRuleKo:
        "source-inventory coverageScope의 (operatorIds, lineIds, sourceDomains) 엄격 매칭으로 domain의 "
        + "requiredFields를 blockingThreshold 이상 충족한 requirement. 빈 lineIds는 와일드카드가 아니다.",
      explicitlyUnsupportedRuleKo:
        "resolutions 문서의 EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE entry가 정본이다. entry의 evidence "
        + "심층 검증과 nextReviewAt 만료 재검토는 wall-clock에 의존하므로 report-coverage-gaps.mjs 게이트 몫이다.",
      dualOperatorRuleKo:
        "MISSING 중 operator 조건만 풀면 admitted가 되는 requirement는 DUAL_OPERATOR_UNMATCHED로 구분한다. "
        + "같은 노선을 커버하는 소스가 있으나 해당 운영기관이 coverageScope에 없는 경우다.",
      outOfScopeAxisKo:
        "provenance 기반 게이트 SUPPORTED 판정(report-coverage-gaps.mjs --manifest/--provenance)은 별도 축이며 "
        + "이 ledger가 대체하지 않는다. INVENTORY_ADMITTED는 admission 근사치이고 게이트 통과를 의미하지 않는다.",
    },
    inputs: {
      targets: { ...inputRecord(inputs, "targets"), targetVersion: targets.targetVersion },
      inventory: { ...inputRecord(inputs, "inventory"), retrievedAt: inventory.retrievedAt },
      resolutions: {
        ...inputRecord(inputs, "resolutions"),
        generatedAt: resolutions.generatedAt ?? null,
        entryCount: resolutions.entries.length,
      },
    },
    denominator: {
      activeLineScopeCount: scopes.length,
      activeLineCount: new Set(scopes.map(({ lineId }) => lineId)).size,
      launchRequiredDomainCount,
      launchRequiredTotal,
      enhancementDomainCount,
      enhancementTotal: tiers.ENHANCEMENT.totalCount,
      expectedLaunchRequiredTotal,
    },
    launchRequired: tiers.LAUNCH_REQUIRED,
    enhancement: tiers.ENHANCEMENT,
  };
}

// requirement 하나의 상태를 판정한다. 우선순위는 INVENTORY_ADMITTED > EXPLICITLY_UNSUPPORTED > MISSING이며,
// admitted requirement에 unsupported resolution이 붙으면 판정 충돌이므로 fail closed한다.
function evaluateRequirement(scope, domain, sources, resolutionIndex) {
  const threshold = domain.blockingThreshold?.minimumOfficialFieldCoverageRatio ?? 1;
  const fieldRows = domain.requiredFields.map((field) => ({
    field,
    sourceIds: admittedSourceIds(sources, scope, domain.id, field, { ignoreOperator: false }),
  }));
  const admittedFieldCount = fieldRows.filter(({ sourceIds }) => sourceIds.length > 0).length;
  const unadmittedFields = fieldRows
    .filter(({ sourceIds }) => sourceIds.length === 0)
    .map(({ field }) => field);
  const key = requirementKey(scope, domain.id);
  const base = {
    regionId: scope.regionId,
    operatorId: scope.operatorId,
    lineId: scope.lineId,
    sourceDomain: domain.id,
    releaseTier: domain.releaseTier,
    requiredFieldCount: fieldRows.length,
    admittedFieldCount,
    admissionRatio: ratio(admittedFieldCount, fieldRows.length),
    blockingThreshold: threshold,
    admittedSourceIds: uniqueSorted(fieldRows.flatMap(({ sourceIds }) => sourceIds)),
    unadmittedFields,
  };
  const resolution = resolutionIndex.get(key) ?? null;
  if (base.admissionRatio >= threshold) {
    if (resolution) {
      throw new Error(`inventory-admitted requirement must not have an unsupported resolution: ${key}`);
    }
    return { ...base, status: "INVENTORY_ADMITTED", missingKind: null, dualOperator: null, resolution: null };
  }
  if (resolution) {
    return {
      ...base,
      status: "EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE",
      missingKind: null,
      dualOperator: null,
      resolution,
    };
  }

  // dual-operator 미매칭: operator 조건만 풀면 admitted가 되는지 확인한다.
  const relaxedRows = domain.requiredFields.map((field) => ({
    field,
    sourceIds: admittedSourceIds(sources, scope, domain.id, field, { ignoreOperator: true }),
  }));
  const relaxedRatio = ratio(
    relaxedRows.filter(({ sourceIds }) => sourceIds.length > 0).length,
    relaxedRows.length,
  );
  if (relaxedRatio < threshold) {
    return { ...base, status: "MISSING", missingKind: "NO_ADMITTED_SOURCE", dualOperator: null, resolution: null };
  }
  const unadmitted = new Set(unadmittedFields);
  const coveringSourceIds = uniqueSorted(
    relaxedRows.filter(({ field }) => unadmitted.has(field)).flatMap(({ sourceIds }) => sourceIds),
  );
  const coveringSources = new Set(coveringSourceIds);
  const coveringOperatorIds = uniqueSorted(
    sources
      .filter(({ id }) => coveringSources.has(id))
      .flatMap(({ operatorIds }) => operatorIds)
      .filter((operatorId) => operatorId !== scope.operatorId),
  );
  return {
    ...base,
    status: "MISSING",
    missingKind: "DUAL_OPERATOR_UNMATCHED",
    dualOperator: { coveringOperatorIds, coveringSourceIds },
    resolution: null,
  };
}

// report-coverage-gaps.mjs coveredField(strictLineScope=true, requireProvenance=false)와 같은 매칭 규칙.
// 빈 lineIds를 와일드카드로 취급하지 않는다.
function admittedSourceIds(sources, scope, sourceDomain, field, { ignoreOperator }) {
  return sources
    .filter((source) =>
      source.regionIds.includes(scope.regionId)
      && (ignoreOperator || source.operatorIds.includes(scope.operatorId))
      && source.lineIds.includes(scope.lineId)
      && source.sourceDomains.includes(sourceDomain)
      && source.fields.includes(field))
    .map(({ id }) => id);
}

function summarizeTier(requirements, releaseTier, domains, scopes) {
  const tierRequirements = requirements.filter((entry) => entry.releaseTier === releaseTier);
  const tierDomains = domains.filter((domain) => domain.releaseTier === releaseTier);
  const regionIds = uniqueSorted(scopes.map(({ regionId }) => regionId));
  return {
    ...tierCounts(tierRequirements),
    byDomain: tierDomains.map((domain) => ({
      sourceDomain: domain.id,
      ...tierCounts(tierRequirements.filter((entry) => entry.sourceDomain === domain.id)),
    })),
    byRegion: regionIds.map((regionId) => ({
      regionId,
      ...tierCounts(tierRequirements.filter((entry) => entry.regionId === regionId)),
    })),
    requirements: tierRequirements,
  };
}

function tierCounts(entries) {
  const countStatus = (status) => entries.filter((entry) => entry.status === status).length;
  const inventoryAdmittedCount = countStatus("INVENTORY_ADMITTED");
  const explicitlyUnsupportedWithEvidenceCount = countStatus("EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE");
  const terminalCount = inventoryAdmittedCount + explicitlyUnsupportedWithEvidenceCount;
  return {
    totalCount: entries.length,
    inventoryAdmittedCount,
    explicitlyUnsupportedWithEvidenceCount,
    missingCount: countStatus("MISSING"),
    missingByKind: Object.fromEntries(MISSING_KINDS.map((kind) => [
      kind,
      entries.filter((entry) => entry.missingKind === kind).length,
    ])),
    terminalCount,
    terminalRatio: ratio(terminalCount, entries.length),
    inventoryAdmittedRatio: ratio(inventoryAdmittedCount, entries.length),
  };
}

// resolutions는 EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE의 정본이다. 이 도구는 requirement 매핑 무결성만
// fail closed로 확인하고, evidence 심층 검증(query·hash·만료)은 report-coverage-gaps.mjs 게이트에 맡긴다.
function indexResolutions(targets, resolutions, scopes, domains) {
  if (!resolutions || typeof resolutions !== "object" || Array.isArray(resolutions)) {
    throw new Error("coverage resolutions must be an object");
  }
  if (resolutions.schemaVersion !== 1) throw new Error("coverage resolutions schemaVersion must be 1");
  if (resolutions.artifactKind !== "nationwide-coverage-resolutions") {
    throw new Error("coverage resolutions artifactKind must be nationwide-coverage-resolutions");
  }
  if (resolutions.targetVersion !== targets.targetVersion) {
    throw new Error("coverage resolutions targetVersion must match coverage targets");
  }
  if (!Array.isArray(resolutions.entries)) {
    throw new Error("coverage resolutions entries must be an array");
  }
  const requirementKeys = new Set(
    scopes.flatMap((scope) => domains.map((domain) => requirementKey(scope, domain.id))),
  );
  const byKey = new Map();
  for (const [index, entry] of resolutions.entries.entries()) {
    const label = `coverage resolutions entries[${index}]`;
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error(`${label} must be an object`);
    }
    if (entry.state !== "EXPLICITLY_UNSUPPORTED_WITH_EVIDENCE") {
      throw new Error(`${label}.state is invalid: ${entry.state ?? "missing"}`);
    }
    const key = requirementKey(
      {
        regionId: requiredString(entry.regionId, `${label}.regionId`),
        operatorId: requiredString(entry.operatorId, `${label}.operatorId`),
        lineId: requiredString(entry.lineId, `${label}.lineId`),
      },
      requiredString(entry.sourceDomain, `${label}.sourceDomain`),
    );
    if (byKey.has(key)) throw new Error(`duplicate coverage resolution: ${key}`);
    if (!requirementKeys.has(key)) throw new Error(`unknown coverage resolution requirement: ${key}`);
    byKey.set(key, {
      reasonCode: requiredString(entry.reasonCode, `${label}.reasonCode`),
      fallback: requiredString(entry.fallback, `${label}.fallback`),
      evidenceHash: requiredString(entry.evidenceHash, `${label}.evidenceHash`),
      reviewedAt: requiredString(entry.reviewedAt, `${label}.reviewedAt`),
      nextReviewAt: requiredString(entry.nextReviewAt, `${label}.nextReviewAt`),
    });
  }
  return byKey;
}

function validateTargets(targets) {
  if (!targets || typeof targets !== "object" || Array.isArray(targets)) {
    throw new Error("coverage targets must be an object");
  }
  if (targets.schemaVersion !== 2) throw new Error("coverage targets schemaVersion must be 2");
  if (targets.artifactKind !== "nationwide-datapack-coverage-targets") {
    throw new Error("coverage targets artifactKind must be nationwide-datapack-coverage-targets");
  }
  requiredString(targets.targetVersion, "coverage targets targetVersion");
  if (!Array.isArray(targets.requiredSourceDomains) || targets.requiredSourceDomains.length === 0) {
    throw new Error("coverage targets requiredSourceDomains must be a non-empty array");
  }
  const domainIds = new Set();
  for (const domain of targets.requiredSourceDomains) {
    const id = requiredString(domain?.id, "requiredSourceDomains.id");
    if (domainIds.has(id)) throw new Error(`duplicate source domain id: ${id}`);
    domainIds.add(id);
    if (!RELEASE_TIERS.includes(domain.releaseTier)) {
      throw new Error(`${id}.releaseTier must be LAUNCH_REQUIRED or ENHANCEMENT`);
    }
    requiredStringArray(domain.requiredFields, `${id}.requiredFields`);
    const threshold = domain.blockingThreshold?.minimumOfficialFieldCoverageRatio ?? 1;
    if (typeof threshold !== "number" || threshold <= 0 || threshold > 1) {
      throw new Error(`${id}.blockingThreshold.minimumOfficialFieldCoverageRatio must be between 0 and 1`);
    }
  }
  if (!targets.requiredSourceDomains.some(({ releaseTier }) => releaseTier === "LAUNCH_REQUIRED")) {
    throw new Error("coverage targets must include at least one LAUNCH_REQUIRED domain");
  }
  if (!Array.isArray(targets.activeLineScopes) || targets.activeLineScopes.length === 0) {
    throw new Error("coverage targets activeLineScopes must be a non-empty array");
  }
  // scope 중복은 분모를 부풀리므로 fail closed.
  const scopeKeys = new Set();
  for (const scope of targets.activeLineScopes) {
    const lineId = requiredString(scope?.lineId, "activeLineScopes.lineId");
    const key = [
      requiredString(scope.regionId, `${lineId}.regionId`),
      requiredString(scope.operatorId, `${lineId}.operatorId`),
      lineId,
    ].join(":");
    if (scopeKeys.has(key)) throw new Error(`duplicate active line scope: ${key}`);
    scopeKeys.add(key);
  }
}

function validateInventory(inventory) {
  if (!inventory || typeof inventory !== "object" || Array.isArray(inventory)) {
    throw new Error("source inventory must be an object");
  }
  if (inventory.schemaVersion !== 1) throw new Error("source inventory schemaVersion must be 1");
  if (!Array.isArray(inventory.sources) || inventory.sources.length === 0) {
    throw new Error("source inventory sources must be a non-empty array");
  }
  requiredString(inventory.retrievedAt, "source inventory retrievedAt");
}

function normalizeSource(source) {
  const id = requiredString(source?.id, "source.id");
  const coverage = source.coverageScope;
  if (!coverage || typeof coverage !== "object" || Array.isArray(coverage)) {
    throw new Error(`${id}.coverageScope must be an object`);
  }
  return {
    id,
    regionIds: requiredStringArray(coverage.regionIds, `${id}.coverageScope.regionIds`),
    operatorIds: requiredStringArray(coverage.operatorIds, `${id}.coverageScope.operatorIds`),
    sourceDomains: requiredStringArray(coverage.sourceDomains, `${id}.coverageScope.sourceDomains`),
    lineIds: optionalStringArray(coverage.lineIds, `${id}.coverageScope.lineIds`),
    fields: requiredStringArray(source.fieldsProvided ?? source.fields, `${id}.fieldsProvided`),
  };
}

function regenerationCommand(inputs, expectedLaunchRequiredTotal) {
  const expected = expectedLaunchRequiredTotal === null
    ? []
    : ["--expected-launch-required-total", String(expectedLaunchRequiredTotal)];
  return [
    "node",
    TOOL_PATH,
    "--targets",
    inputRecord(inputs, "targets").path,
    "--inventory",
    inputRecord(inputs, "inventory").path,
    "--resolutions",
    inputRecord(inputs, "resolutions").path,
    ...expected,
    "--output",
    LEDGER_PATH,
  ].join(" ");
}

function inputRecord(inputs, name) {
  const record = inputs?.[name];
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    throw new Error(`inputs.${name} must be an object`);
  }
  return {
    path: requiredString(record.path, `inputs.${name}.path`),
    sha256: requiredString(record.sha256, `inputs.${name}.sha256`),
  };
}

function requirementKey({ regionId, operatorId, lineId }, sourceDomain) {
  return `${regionId}:${operatorId}:${lineId}:${sourceDomain}`;
}

function compareScopes(left, right) {
  return codepointCompare(left.regionId, right.regionId)
    || codepointCompare(left.operatorId, right.operatorId)
    || codepointCompare(left.lineId, right.lineId);
}

function uniqueSorted(values) {
  return [...new Set(values)].sort(codepointCompare);
}

function ratio(numerator, denominator) {
  return denominator === 0 ? 0 : Number((numerator / denominator).toFixed(4));
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`${label} is required`);
  return value;
}

function requiredStringArray(value, label) {
  if (
    !Array.isArray(value)
    || value.length === 0
    || value.some((entry) => typeof entry !== "string" || entry.trim() === "")
  ) {
    throw new Error(`${label} must be a non-empty string array`);
  }
  return value;
}

function optionalStringArray(value, label) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string" || entry.trim() === "")) {
    throw new Error(`${label} must be a string array`);
  }
  return value;
}

async function readJsonInput(filePath) {
  const bytes = await readFile(filePath);
  return {
    document: JSON.parse(bytes.toString("utf8")),
    input: { path: filePath, sha256: createHash("sha256").update(bytes).digest("hex") },
  };
}

async function main(argv) {
  const args = parseArgs(argv);
  for (const flag of Object.keys(args)) {
    if (!ALLOWED_FLAGS.has(flag)) throw new Error(`unexpected argument: --${flag}`);
  }
  const outputPath = requireArg(args, "output");
  const targets = await readJsonInput(requireArg(args, "targets"));
  const inventory = await readJsonInput(requireArg(args, "inventory"));
  const resolutions = await readJsonInput(args.resolutions ?? DEFAULT_RESOLUTIONS_PATH);
  const expectedRaw = args["expected-launch-required-total"];
  if (expectedRaw !== undefined && !/^\d+$/.test(expectedRaw)) {
    throw new Error("--expected-launch-required-total must be a non-negative integer");
  }

  const ledger = buildNationwideCoverageTally({
    targets: targets.document,
    inventory: inventory.document,
    resolutions: resolutions.document,
    inputs: {
      targets: targets.input,
      inventory: inventory.input,
      resolutions: resolutions.input,
    },
    expectedLaunchRequiredTotal: expectedRaw === undefined ? null : Number(expectedRaw),
  });

  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(sortJson(ledger), null, 2)}\n`);
}

if (isMainModule(import.meta.url)) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
