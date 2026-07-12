#!/usr/bin/env node
// #1701 baseline 적재 검증 게이트 리포트 생성기(tracked 산출물).
//
// 공공기관 환승역거리 소요시간·빠른하차·KRIC 동선 baseline을 capital 참조 팩(catalog-fixture.json)에
// 적재하면서, 수집 전량(환승 145행/빠른하차 2358행) 기준으로 coverage와 desk 게이트 ①②③를 산출한다.
//
// 스코프 결정(리포트 최상단 metadata에 명기):
//   - 팩 적재 대상은 capital 참조 팩(catalog-fixture.json)뿐이다.
//   - 프로덕션 pilot 팩·release gate 확장은 이 PR의 비범위이며 #1702/#1414 트랙 후속이다.
//   - coverage/desk 게이트 수치는 수집 전량 기준으로 계산하고, capital 6역 스코프라는 한정 사유를 명기한다.
//
// 이 스크립트는 원본 importer(buildTransferBaseline/buildCarDoorHints)와 normalizer를 재사용해
// 적재 결과·quarantine를 그대로 반영한다. importer/normalizer/build-datapack은 수정하지 않는다.
//
// 사용: node tools/datapack/build-baseline-ingestion-gate-report.mjs \
//   --fixture tools/datapack/fixtures/catalog-fixture.json \
//   --transfer-rows <transfer.merged-rows.json> \
//   --car-door-rows <fast-exit.merged-rows.json> \
//   --kric-movement <kric-transfer-movement-detailed.raw.json> \
//   --output <report.json>
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { readJsonFile, requireArg, sortJson } from "./lib/ledger-admission-cli.mjs";
import { buildTransferBaseline } from "./import-transfer-baseline.mjs";
import { buildCarDoorHints } from "./import-car-door-hints.mjs";
import { normalizeTransferDistanceDurationRows } from "./normalize-transfer-distance-duration-rows.mjs";

const TRANSFER_SOURCE_ID = "seoul-metro-transfer-distance-duration";
const CAR_DOOR_SOURCE_ID = "seoul-metro-fast-exit-car-door";
const KRIC_MOVEMENT_SOURCE_ID = "kric-transfer-movement-detailed";

async function main(argv) {
  const args = parseArgs(argv);
  const fixture = await readJsonFile(requireArg(args, "fixture"));
  const transferRows = await readJsonFile(requireArg(args, "transfer-rows"));
  const carDoorRows = await readJsonFile(requireArg(args, "car-door-rows"));
  const kricMovement = await readJsonFile(requireArg(args, "kric-movement"));
  const outputPath = requireArg(args, "output");

  const pack = fixture.packs[0];
  const report = buildBaselineIngestionGateReport({
    roster: buildRosterFromPack(pack),
    transferRows,
    carDoorRows,
    kricMovement,
    existingEdges: pack.stationPathwayEdges ?? [],
    existingNodes: pack.stationPathwayNodes ?? [],
    fixtureReflectedRuleCount: (pack.transferRules ?? []).length,
  });

  await mkdir(path.dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(sortJson(report), null, 2)}\n`);
}

/**
 * catalog-fixture pack의 stations/stationAliases/stationLines/lines에서 roster를 빌드한다.
 * stationLine 하나당 엔트리 하나. lineNameKo는 line.nameKo에서 "수도권 " prefix를 제거한 짧은형으로
 * 지정해야 데이터의 짧은형("2호선" 등)과 matchLineForStation이 매칭된다.
 */
export function buildRosterFromPack(pack) {
  const stationsById = new Map((pack.stations ?? []).map((station) => [station.id, station]));
  const linesById = new Map((pack.lines ?? []).map((line) => [line.id, line]));
  const aliasesByStation = new Map();
  for (const alias of pack.stationAliases ?? []) {
    if (!aliasesByStation.has(alias.stationId)) aliasesByStation.set(alias.stationId, []);
    aliasesByStation.get(alias.stationId).push({ alias: alias.alias, normalizedAlias: alias.normalizedAlias });
  }
  return (pack.stationLines ?? []).map((stationLine) => {
    const station = stationsById.get(stationLine.stationId);
    const line = linesById.get(stationLine.lineId);
    return {
      stationId: stationLine.stationId,
      lineId: stationLine.lineId,
      nameKo: station?.nameKo ?? "",
      normalizedName: station?.normalizedName ?? "",
      lineNameKo: shortLineName(line?.nameKo ?? ""),
      lineName: line?.nameKo ?? "",
      aliases: aliasesByStation.get(stationLine.stationId) ?? [],
    };
  });
}

// line.nameKo("수도권 2호선")에서 수도권 prefix를 제거한 짧은형("2호선")을 도출한다. prefix 없으면 원형.
function shortLineName(nameKo) {
  return String(nameKo ?? "").replace(/^수도권\s+/, "");
}

/**
 * 순수 함수: 수집 전량 + roster → 검증 게이트 리포트.
 */
export function buildBaselineIngestionGateReport({
  roster,
  transferRows,
  carDoorRows,
  kricMovement,
  existingEdges = [],
  existingNodes = [],
  fixtureReflectedRuleCount = 0,
}) {
  const transferRowList = Array.isArray(transferRows) ? transferRows : [];
  const carDoorRowList = Array.isArray(carDoorRows) ? carDoorRows : [];
  const validTransferRows = transferRowList.filter(
    (row) => row != null && typeof row === "object" && !Array.isArray(row),
  );
  const { normalizedRows, malformed } = normalizeTransferDistanceDurationRows(transferRowList);

  const transfer = buildTransferBaseline({
    roster,
    rows: normalizedRows,
    existingEdges,
    existingNodes,
    sourceId: TRANSFER_SOURCE_ID,
    verificationStatus: "VERIFIED",
  });
  const carDoor = buildCarDoorHints({
    roster,
    rows: carDoorRowList,
    sourceId: CAR_DOOR_SOURCE_ID,
    verificationStatus: "OFFICIAL",
  });

  // from==to 자기루프 transferRule은 무의미하므로 적재 대상에서 제외한다(성수 2호선→2호선).
  const admittedTransferRules = transfer.transferRules.filter((rule) => rule.fromLineId !== rule.toLineId);
  const selfLoopTransferRules = transfer.transferRules.filter((rule) => rule.fromLineId === rule.toLineId);

  const uniqueTransferStations = new Set(validTransferRows.map((row) => String(row["환승역명"]))).size;
  const matchedTransferStations = new Set(admittedTransferRules.map((rule) => rule.fromStationId));

  return {
    schemaVersion: 1,
    artifactKind: "baseline-ingestion-gate-report",
    metadata: {
      issue: "#1701",
      scopeDecision:
        "프로덕션 pilot 팩 적재는 이 PR의 비범위이며 #1702/#1414 트랙 후속이다. 이 리포트의 팩 적재 대상은 " +
        "capital 참조 팩(tools/datapack/fixtures/catalog-fixture.json)뿐이며, tools/datapack/release/의 " +
        "프로덕션 pilot 팩·tools/datapack/inputs/*·release gate는 건드리지 않았다.",
      countingBasis:
        `coverage와 desk 게이트 수치는 수집 전량(환승역거리 소요시간 ${transferRowList.length}행, ` +
        `빠른하차 ${carDoorRowList.length}행) 기준으로 계산한다. ` +
        "팩 적재 매칭은 capital 6역(상록수·사당·강남·정자·성수·신설동) roster 스코프로 한정되어 대부분의 전량 행은 " +
        "roster 밖이라 quarantine된다 — 이 한정 사유를 정직하게 계측한다.",
      officialSources: {
        transfer: TRANSFER_SOURCE_ID,
        carDoor: CAR_DOOR_SOURCE_ID,
        kricMovement: KRIC_MOVEMENT_SOURCE_ID,
      },
      reproducibility:
        "tracked snapshot; regenerated only from local-only raw inputs (.codex/evidence/1701/, gitignored)",
    },
    coverage: buildCoverage({
      transfer,
      admittedTransferRules,
      selfLoopTransferRules,
      malformed,
      uniqueTransferStations,
      matchedTransferStations,
      transferRowTotal: transferRowList.length,
      carDoor,
      carDoorRowTotal: carDoorRowList.length,
      fixtureReflectedRuleCount,
    }),
    gateInternalConsistency: buildGateInternalConsistency(transfer, admittedTransferRules, selfLoopTransferRules),
    gateKricStructuralAlignment: buildGateKricStructuralAlignment(validTransferRows, kricMovement),
    gateTimeSourceDistinction: buildGateTimeSourceDistinction(transfer),
    pilotFieldDeviation: {
      status: "SKIPPED",
      reason:
        "상록수·사당 pilot 실측 편차 검증은 2026-07-06 field-work 트랙으로 이관됐다(#1394 실측이 field-work 트랙 " +
        "이관 결정). 이 PR에서는 SKIPPED로 정직 기록한다.",
    },
  };
}

function buildCoverage({
  transfer,
  admittedTransferRules,
  selfLoopTransferRules,
  malformed,
  uniqueTransferStations,
  matchedTransferStations,
  transferRowTotal,
  carDoor,
  carDoorRowTotal,
  fixtureReflectedRuleCount,
}) {
  return {
    transfer: {
      totalRows: transferRowTotal,
      uniqueStationNames: uniqueTransferStations,
      malformedRows: malformed.length,
      admittedRules: admittedTransferRules.length,
      fixtureReflectedRules: {
        count: fixtureReflectedRuleCount,
        note:
          "importer는 사당 양방향(2→4/4→2)을 각각 rule로 산출하지만(admittedRules에 2건 포함), 팩에는 사당 방향쌍을 " +
          "기존 수기 정본 rule(transfer-sadang-seoul-4-to-seoul-2, 공식 62초로 갱신) 1건으로 유지한다. 따라서 " +
          "catalog-fixture.transferRules는 사당 1건 + 강남 1건 = 2건이다.",
      },
      admittedStations: [...matchedTransferStations].sort(compareText),
      selfLoopExcludedRules: selfLoopTransferRules.map((rule) => ({
        stationId: rule.fromStationId,
        fromLineId: rule.fromLineId,
        toLineId: rule.toLineId,
        reason: "from_line_id == to_line_id (무의미한 자기루프 — 적재 제외)",
      })),
      quarantinedRows: transfer.quarantine.length,
      quarantineReasonCounts: reasonCounts(transfer.quarantine),
    },
    carDoor: {
      totalRows: carDoorRowTotal,
      admittedHints: carDoor.stationCarDoorHints.length,
      admittedByStation: countBy(carDoor.stationCarDoorHints, (hint) => hint.stationId),
      duplicateRows: carDoor.duplicateReport.length,
      quarantinedRows: carDoor.quarantine.length,
      quarantineReasonCounts: reasonCounts(carDoor.quarantine),
    },
  };
}

// desk 게이트 ①: 적재 대상(매칭 성공)의 방향쌍 존재/불일치·중복 내부 정합.
function buildGateInternalConsistency(transfer, admittedTransferRules, selfLoopTransferRules) {
  return {
    description:
      "적재 대상(capital roster 매칭 성공분)의 방향쌍 존재/소요시간 불일치·중복을 리포트한다. capital 6역 스코프 " +
      "한정이라 전량 내부 정합은 roster 확장이 필요하며(비범위), 매칭 실패 전량 행은 coverage.quarantine으로 집계된다.",
    directionPairReport: transfer.directionPairReport,
    duplicateReport: transfer.duplicateReport,
    selfLoopExcluded: selfLoopTransferRules.map((rule) => ({
      stationId: rule.fromStationId,
      fromLineId: rule.fromLineId,
      toLineId: rule.toLineId,
    })),
    admittedRuleCount: admittedTransferRules.length,
  };
}

// desk 게이트 ②: KRIC 동선 존재 ↔ 환승소요시간 baseline 존재의 구조 정합(충무로 3↔4).
function buildGateKricStructuralAlignment(transferRows, kricMovement) {
  const chungmuroBaseline = (transferRows ?? []).filter((row) => String(row["환승역명"]).includes("충무로"));
  const resultCode = kricMovement?.header?.resultCode ?? null;
  const steps = Array.isArray(kricMovement?.body) ? kricMovement.body.length : 0;
  const admitted = resultCode === "00";
  return {
    description:
      "충무로역 KRIC 동선(3호선↔4호선 detailed tuple) 존재와 환승소요시간 baseline 충무로(3↔4, 17m/00:14) 존재의 " +
      "구조 정합을 명시 기록한다.",
    kricStandardResult:
      "KRIC standard tuple은 no-data(resultCode=03)라 detailed tuple만 사용한다. 서울 환승소요시간 데이터와 겹치는 " +
      "역이 충무로 1건뿐이라(standard 결과 없음 + detailed tuple 단위 호출 비용) 전량 교차검증은 불가하며 이 한정 " +
      "사유를 정직하게 기록한다.",
    kricMovementDetailed: {
      sourceId: KRIC_MOVEMENT_SOURCE_ID,
      resultCode,
      admitted,
      stepCount: steps,
      station: "충무로(3호선↔4호선)",
    },
    transferBaselineChungmuro: chungmuroBaseline.map((row) => ({
      호선: row["호선"],
      환승노선: row["환승노선"],
      환승거리: row["환승거리"],
      환승소요시간: row["환승소요시간"],
    })),
    structurallyAligned: admitted && chungmuroBaseline.length > 0,
    note:
      "충무로 baseline은 capital 6역에 없으므로 팩에는 적재되지 않는다 — 전량 기준 교차검증 근거로만 리포트에 남긴다.",
  };
}

// desk 게이트 ③: timeSource 구분. baseline edge의 provenance_kind는 OFFICIAL_SOURCE로 고정된다.
function buildGateTimeSourceDistinction(transfer) {
  const provenanceKinds = [...new Set(transfer.stationPathwayEdges.map((edge) => edge.provenanceKind))].sort(
    compareText,
  );
  return {
    description:
      "station_pathway_edges 스키마의 provenance_kind가 OFFICIAL_SOURCE(공식 baseline)와 거리기반 추정류를 구분하는 " +
      "축이다. importer가 baseline edge에 provenanceKind:OFFICIAL_SOURCE를 고정하는 것을 node --test로 고정했다 " +
      "(import-transfer-baseline.test.mjs).",
    provenanceKindAxis: "OFFICIAL_SOURCE",
    baselineEdgeCount: transfer.stationPathwayEdges.length,
    baselineEdgeProvenanceKinds: provenanceKinds,
    note:
      "capital 스코프에서는 사당(기존 양방향 edge로 중복 억제)·강남(platform node 부재) 때문에 신규 baseline edge가 " +
      "생성되지 않지만(baselineEdgeCount=0), 구분 축 자체는 스키마·importer·테스트에 실재한다.",
  };
}

function reasonCounts(quarantine) {
  return countBy(quarantine, (entry) => String(entry.reason).replace(/:.*$/, "").trim());
}

function countBy(items, keyFn) {
  const counts = {};
  for (const item of items) {
    const key = keyFn(item);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

function compareText(left, right) {
  return String(left).localeCompare(String(right));
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (!flag?.startsWith("--")) throw new Error(`unexpected argument: ${flag}`);
    const value = argv[index + 1];
    if (value == null || value.startsWith("--")) throw new Error(`${flag} requires a value`);
    args[flag.slice(2)] = value;
    index += 1;
  }
  return args;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await main(process.argv.slice(2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
