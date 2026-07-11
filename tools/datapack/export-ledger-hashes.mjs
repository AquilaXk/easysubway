#!/usr/bin/env node
// 원장 해시 exporter — admission admin review 필수 필드 6종 hash의 producer.
//
// source-admission-runbook.json의 requiredAdminReviewFields 중 hash 6종
// (licenseEvidenceHash, aliasLedgerHash, operatorMappingLedgerHash,
//  facilityEvidenceLedgerHash, routeEvidenceLedgerHash, overrideHash)을
// 리포에 실존하는 canonical 원장 데이터에서 결정적으로 산출한다.
//
// 결정성 규칙:
//   - 모든 객체 key를 재귀적으로 사전순 정렬(sortJson)한 뒤 JSON.stringify.
//   - 배열(레코드 집합)은 canonical row 문자열로 직렬화한 뒤 사전순 정렬하여
//     입력 순서와 무관하게 동일 해시를 낸다.
//   - 공백 없는 JSON.stringify(기본) 사용 — 구분자·들여쓰기 없음.
//   - sha256 hex(소문자 64자).
//
// canonical 원장 소스(실측):
//   - aliasLedger:           fixture pack.stationAliases
//   - operatorMappingLedger: fixture pack.operators
//   - facilityEvidenceLedger: fixture pack.stationFacilityEvidence(있으면) → 없으면 pack.facilities
//   - routeEvidenceLedger:   fixture pack.networkEdges
//   - override:              manual override ledger 파일(apply-admin-review-overrides.mjs 계약)
//   - licenseEvidence:       source-inventory.json 해당 source.license 블록
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = path.resolve(import.meta.dirname, "../..");

const ledgerKinds = new Set(["alias", "operator-mapping", "facility-evidence", "route-evidence", "override", "license"]);

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const kind = requireArg(args, "kind");
  if (!ledgerKinds.has(kind)) {
    throw new Error(`--kind must be one of ${[...ledgerKinds].join(", ")}`);
  }

  const result = await exportLedgerHash(kind, args);
  console.log(JSON.stringify(result, null, 2));
}

async function exportLedgerHash(kind, args) {
  if (kind === "license") {
    return exportLicenseEvidenceHash(args);
  }
  if (kind === "override") {
    return exportOverrideHash(args);
  }
  return exportFixtureLedgerHash(kind, args);
}

// fixture pack에서 원장 레코드 집합을 뽑아 canonical 해시를 낸다.
async function exportFixtureLedgerHash(kind, args) {
  const fixturePath = path.resolve(root, requireArg(args, "fixture"));
  const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
  const packs = requiredArray(fixture.packs, "fixture.packs");

  const rows = [];
  for (const pack of packs) {
    rows.push(...ledgerRowsForPack(kind, pack));
  }
  const canonicalRows = canonicalizeRows(rows);
  return {
    schemaVersion: 1,
    artifactKind: `datapack-${kind}-ledger-hash`,
    kind,
    fixturePath: path.relative(root, fixturePath),
    rowCount: canonicalRows.length,
    ledgerHash: sha256(JSON.stringify(canonicalRows)),
  };
}

function ledgerRowsForPack(kind, pack) {
  switch (kind) {
    case "alias":
      return requiredArray(pack.stationAliases ?? [], "pack.stationAliases").map((row) => ({
        stationId: requiredString(row.stationId, "stationAliases.stationId"),
        alias: requiredString(row.alias, "stationAliases.alias"),
        normalizedAlias: requiredString(row.normalizedAlias, "stationAliases.normalizedAlias"),
      }));
    case "operator-mapping":
      return requiredArray(pack.operators ?? [], "pack.operators").map((row) => ({
        id: requiredString(row.id, "operators.id"),
        nameKo: requiredString(row.nameKo, "operators.nameKo"),
        nameEn: requiredString(row.nameEn, "operators.nameEn"),
      }));
    case "facility-evidence": {
      const evidence = pack.stationFacilityEvidence;
      if (Array.isArray(evidence) && evidence.length > 0) {
        return evidence.map((row) => ({
          stationId: requiredString(row.stationId, "stationFacilityEvidence.stationId"),
          lineId: requiredString(row.lineId, "stationFacilityEvidence.lineId"),
          facilityType: requiredString(row.facilityType, "stationFacilityEvidence.facilityType"),
          evidenceHash: requiredString(row.evidenceHash, "stationFacilityEvidence.evidenceHash"),
          providerRecordHash: requiredString(row.providerRecordHash, "stationFacilityEvidence.providerRecordHash"),
        }));
      }
      return requiredArray(pack.facilities ?? [], "pack.facilities").map((row) => ({
        id: requiredString(row.id, "facilities.id"),
        stationId: requiredString(row.stationId, "facilities.stationId"),
        type: requiredString(row.type, "facilities.type"),
        status: requiredString(row.status, "facilities.status"),
      }));
    }
    case "route-evidence":
      return requiredArray(pack.networkEdges ?? [], "pack.networkEdges").map((row) => ({
        id: requiredString(row.id, "networkEdges.id"),
        fromNodeId: requiredString(row.fromNodeId, "networkEdges.fromNodeId"),
        toNodeId: requiredString(row.toNodeId, "networkEdges.toNodeId"),
        edgeType: requiredString(row.edgeType, "networkEdges.edgeType"),
      }));
    default:
      throw new Error(`unsupported fixture ledger kind: ${kind}`);
  }
}

// license evidence hash — source-inventory.json 해당 source의 license 블록.
async function exportLicenseEvidenceHash(args) {
  const inventoryPath = path.resolve(root, args.inventory ?? "tools/datapack/source-inventory.json");
  const sourceId = requireArg(args, "source-id");
  const inventory = JSON.parse(await readFile(inventoryPath, "utf8"));
  const source = requiredArray(inventory.sources, "inventory.sources").find((entry) => entry.id === sourceId);
  if (!source) {
    throw new Error(`source-id not found in inventory: ${sourceId}`);
  }
  const license = source.license;
  if (!license || typeof license !== "object" || Array.isArray(license)) {
    throw new Error(`inventory source ${sourceId} has no license block`);
  }
  return {
    schemaVersion: 1,
    artifactKind: "datapack-license-evidence-hash",
    kind: "license",
    inventoryPath: path.relative(root, inventoryPath),
    sourceId,
    ledgerHash: sha256(JSON.stringify(sortJson(license))),
  };
}

// override hash — manual override ledger(apply-admin-review-overrides.mjs 계약과 동일 파일).
async function exportOverrideHash(args) {
  const overridesPath = path.resolve(root, requireArg(args, "overrides"));
  const overrides = JSON.parse(await readFile(overridesPath, "utf8"));
  if (overrides.artifactKind !== "datapack-manual-override-ledger") {
    throw new Error("override ledger artifactKind must be datapack-manual-override-ledger");
  }
  if (overrides.ledgerSource !== "manual_overrides") {
    throw new Error("override ledger ledgerSource must be manual_overrides");
  }
  return {
    schemaVersion: 1,
    artifactKind: "datapack-override-ledger-hash",
    kind: "override",
    overridesPath: path.relative(root, overridesPath),
    rowCount: Array.isArray(overrides.facilityStatusUpdates) ? overrides.facilityStatusUpdates.length : 0,
    ledgerHash: sha256(JSON.stringify(sortJson(overrides))),
  };
}

// row 집합을 canonical 문자열로 직렬화한 뒤 사전순 정렬 — 입력 순서 불변.
function canonicalizeRows(rows) {
  return rows
    .map((row) => JSON.stringify(sortJson(row)))
    .sort((left, right) => (left < right ? -1 : left > right ? 1 : 0));
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!flag?.startsWith("--")) throw new Error(`unexpected argument: ${flag}`);
    if (value == null || value.startsWith("--")) throw new Error(`${flag} requires a value`);
    args[flag.slice(2)] = value;
    index += 1;
  }
  return args;
}

function requireArg(args, name) {
  return requiredString(args[name], `--${name}`);
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} is required`);
  }
  return value;
}

function requiredArray(value, label) {
  if (!Array.isArray(value)) {
    throw new Error(`${label} must be an array`);
  }
  return value;
}

function sortJson(value) {
  if (Array.isArray(value)) return value.map(sortJson);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(
    Object.entries(value)
      .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
      .map(([key, entry]) => [key, sortJson(entry)]),
  );
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await main();
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

export { exportLedgerHash, canonicalizeRows, sortJson, sha256 };
