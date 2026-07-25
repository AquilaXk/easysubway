import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { parseMolitLineOperatorRosters } from "./build-molit-nationwide-fixture.mjs";
import { ROUTE_MAP_DOMAIN, auditRouteMapCoverageScopes } from "./route-map-coverage-scope.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const MOLIT_ROSTER_PATH = "tools/datapack/sources/molit-urban-rail-full-route-20251211.csv";
const EXEMPTIONS_PATH = "tools/datapack/route-map-coverage-scope-exemptions.json";

// #2499·#2508에서 배선한 dual-operator containment는 전 scope 감사의 부분집합으로 유지한다.
const DUAL_OPERATOR_SCOPE_KEYS = Object.freeze([
  "capital:korail:line-051552e50435",
  "capital:operator-28e01fb8509d:shinbundang",
  "capital:operator-38450e138464:line-051552e50435",
  "capital:operator-5ca780d7dee1:line-8604048b6430",
  "capital:operator-936e454d0bfb:line-f0e747248a31",
  "capital:operator-9e999d4aa596:line-8604048b6430",
]);

// route_map_positions admitted 소스가 claim한 활성 (region, operator, line) scope 전량을
// source-inventory 등재 순서 그대로 고정한다. 감사 대상이 줄어드는 회귀를 잡기 위한 장치다.
const AUDITED_SCOPE_KEYS = Object.freeze([
  "busan:busan-transportation:line-ab1a041f6266",
  "busan:busan-transportation:line-d74614a04530",
  "busan:busan-transportation:line-d812a5bc1e5f",
  "busan:busan-transportation:line-eb7b47920390",
  "daegu:daegu-transportation:line-5b8d9b05e7e6",
  "daegu:daegu-transportation:line-e2938a4cc492",
  "daegu:daegu-transportation:line-0ffaa95b1b5d",
  "daejeon:daejeon-transportation:line-7051a9c2525c",
  "gwangju:gwangju-metropolitan-rapid-transit:line-e57a361e8892",
  "capital:incheon-transit:line-42b5805f3b5a",
  "capital:incheon-transit:line-98718184f016",
  "capital:incheon-transit:line-15b3b8a93259",
  "capital:operator-8134e61f8dbd:line-e9e9a5b520a4",
  "capital:operator-b2d80436b438:line-828f04afc588",
  "capital:operator-2e23276dfa94:line-5500c1600f71",
  "capital:operator-5ca780d7dee1:line-8604048b6430",
  "capital:operator-9e999d4aa596:line-8604048b6430",
  "capital:korail:line-54a7b980b7c3",
  "capital:korail:line-e4939a4b4713",
  "capital:korail:line-6e39be0cb6e2",
  "capital:korail:line-051552e50435",
  "capital:operator-38450e138464:line-051552e50435",
  "capital:operator-936e454d0bfb:line-f0e747248a31",
  "capital:operator-28e01fb8509d:shinbundang",
  "capital:operator-10d7cf275a80:line-aefa08ccc0a9",
  "capital:korail:line-558d0bd8312d",
  "capital:operator-3c623bf1a427:line-30886152e4f8",
  "capital:operator-29e323a78a93:line-62096860ab09",
  "capital:seoul-metro:line-472a81add377",
  "capital:seoul-metro:seoul-2",
  "capital:seoul-metro:line-41a8c75ec9d8",
  "capital:seoul-metro:seoul-4",
  "capital:seoul-metro:line-80fc4d5350d4",
  "capital:seoul-metro:line-3f41718e0833",
  "capital:seoul-metro:line-15b3b8a93259",
  "capital:seoul-metro:line-2b2d9eaa53d0",
]);

async function readJson(relativePath) {
  return JSON.parse(await readFile(path.join(root, relativePath), "utf8"));
}

async function loadAuditInputs() {
  const [inventory, targets, exemptions, molitCsvBytes] = await Promise.all([
    readJson("tools/datapack/source-inventory.json"),
    readJson("tools/datapack/nationwide-coverage-targets.json"),
    readJson(EXEMPTIONS_PATH),
    readFile(path.join(root, MOLIT_ROSTER_PATH)),
  ]);
  const snapshotsByPath = new Map();
  for (const source of inventory.sources) {
    const snapshotPath = source.routeMapAdmissionEvidence?.snapshotPath;
    if (source.coverageScope?.sourceDomains?.includes(ROUTE_MAP_DOMAIN) && snapshotPath) {
      snapshotsByPath.set(snapshotPath, await readJson(snapshotPath));
    }
  }
  const topologiesByPath = new Map();
  for (const gap of exemptions.documentedCoverageGaps) {
    const topologyPath = gap.evidence?.packTopologyPath;
    if (topologyPath && !topologiesByPath.has(topologyPath)) {
      topologiesByPath.set(topologyPath, await readJson(topologyPath));
    }
  }
  return {
    inventory,
    targets,
    exemptions,
    rosters: parseMolitLineOperatorRosters(molitCsvBytes),
    snapshotsByPath,
    topologiesByPath,
  };
}

// 위반은 별칭 → 결측 ledger → containment 순서로 쌓이므로 나열 순서가 결정론적이다.
function violationKinds(result) {
  return result.violations.map(({ kind }) => kind);
}

test("route_map_positions 전 scope containment는 승인 별칭·문서화 결측 반영 후 fail-closed다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const result = auditRouteMapCoverageScopes(inputs);

  assert.deepEqual(
    result.violations.map(({ message }) => message),
    [],
    "containment 위반이 남아 있다",
  );
  assert.deepEqual(result.auditedScopeKeys, [...AUDITED_SCOPE_KEYS]);
  for (const scopeKey of DUAL_OPERATOR_SCOPE_KEYS) {
    assert.ok(
      result.auditedScopeKeys.includes(scopeKey),
      `#2508 dual-operator scope가 감사에서 빠졌다: ${scopeKey}`,
    );
  }
});

test("면제 fixture는 항목마다 공식 근거를 싣는다 (#2516)", async () => {
  const { exemptions } = await loadAuditInputs();

  assert.equal(exemptions.artifactKind, "route-map-coverage-scope-exemptions");
  for (const alias of exemptions.approvedStationNameAliases) {
    assert.ok(alias.evidence.officialUrl.startsWith("https://"), `${alias.snapshotStationName} 근거 URL이 없다`);
    assert.ok(alias.evidence.note.length > 0, `${alias.snapshotStationName} 근거 서술이 없다`);
  }
  for (const gap of exemptions.documentedCoverageGaps) {
    assert.ok(gap.evidence.snapshotPath.startsWith("tools/datapack/sources/"));
    assert.ok(gap.evidence.note.length > 0, `${gap.rosterStationName} 근거 서술이 없다`);
  }
});

test("admitted snapshot에서 커버 역이 사라지면 containment가 실패한다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const snapshotPath = "tools/datapack/sources/gwangju-transportation-route-map-positions-20260725.json";
  const snapshot = structuredClone(inputs.snapshotsByPath.get(snapshotPath));
  snapshot.positions = snapshot.positions.filter(({ stationName }) => stationName !== "광주송정");
  const snapshotsByPath = new Map(inputs.snapshotsByPath).set(snapshotPath, snapshot);

  const result = auditRouteMapCoverageScopes({ ...inputs, snapshotsByPath });

  assert.deepEqual(violationKinds(result), ["MISSING_STATION"]);
  assert.match(result.violations[0].message, /광주송정/u);
});

test("결측을 가리는 별칭은 거부된다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const exemptions = structuredClone(inputs.exemptions);
  // 8호선 암사역사공원 결측을 이웃 역 암사 표기로 덮으려는 시도.
  exemptions.documentedCoverageGaps = exemptions.documentedCoverageGaps
    .filter(({ rosterStationName }) => rosterStationName !== "암사역사공원");
  exemptions.approvedStationNameAliases.push({
    scopeKey: "capital:seoul-metro:line-2b2d9eaa53d0",
    snapshotStationName: "암사",
    rosterStationName: "암사역사공원",
    reasonCode: "OFFICIAL_RENAME",
    evidence: {
      issue: 2516,
      renamedAt: "2024-08-10",
      officialUrl: "https://www.data.go.kr/data/15099316/fileData.do",
      note: "근거 없는 별칭",
    },
  });

  const result = auditRouteMapCoverageScopes({ ...inputs, exemptions });

  assert.deepEqual(violationKinds(result), ["ALIAS_SHADOWS_ROSTER_STATION", "MISSING_STATION"]);
});

test("snapshot에 없는 역을 가리키는 별칭은 거부된다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const exemptions = structuredClone(inputs.exemptions);
  exemptions.documentedCoverageGaps = exemptions.documentedCoverageGaps
    .filter(({ rosterStationName }) => rosterStationName !== "신설동");
  exemptions.approvedStationNameAliases.push({
    scopeKey: "capital:operator-3c623bf1a427:line-30886152e4f8",
    snapshotStationName: "신설동종점",
    rosterStationName: "신설동",
    reasonCode: "OFFICIAL_RENAME",
    evidence: {
      issue: 2516,
      renamedAt: "2017-09-02",
      officialUrl: "https://www.data.go.kr/data/15041324/fileData.do",
      note: "근거 없는 별칭",
    },
  });

  const result = auditRouteMapCoverageScopes({ ...inputs, exemptions });

  assert.deepEqual(violationKinds(result), ["ALIAS_SNAPSHOT_STATION_ABSENT", "MISSING_STATION"]);
});

test("근거가 빠진 별칭은 거부된다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const exemptions = structuredClone(inputs.exemptions);
  delete exemptions.approvedStationNameAliases[0].evidence.officialUrl;

  const result = auditRouteMapCoverageScopes({ ...inputs, exemptions });

  assert.deepEqual(violationKinds(result), ["ALIAS_EVIDENCE_INVALID", "MISSING_STATION"]);
});

test("호선 접미사 표기 별칭은 표기 규칙이 어긋나면 거부된다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const exemptions = structuredClone(inputs.exemptions);
  const alias = exemptions.approvedStationNameAliases
    .find(({ snapshotStationName }) => snapshotStationName === "성서산단");
  alias.reasonCode = "OFFICIAL_LINE_ORDINAL_SUFFIX";

  const result = auditRouteMapCoverageScopes({ ...inputs, exemptions });

  assert.deepEqual(violationKinds(result), ["ALIAS_LINE_ORDINAL_MISMATCH", "MISSING_STATION"]);
});

test("공식 개명 별칭은 노선 나열 위치가 다르면 거부된다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const exemptions = structuredClone(inputs.exemptions);
  const alias = exemptions.approvedStationNameAliases
    .find(({ snapshotStationName }) => snapshotStationName === "당고개");
  const snapshotPath = "tools/datapack/sources/seoul-metro-route-map-positions-20260724.json";
  const snapshot = structuredClone(inputs.snapshotsByPath.get(snapshotPath));
  // 상계를 지우면 당고개의 이웃이 노원으로 바뀌어 불암산과 같은 위치라는 근거가 깨진다.
  snapshot.positions = snapshot.positions
    .filter((position) => !(position.lineId === "seoul-4" && position.stationName === "상계"));
  const snapshotsByPath = new Map(inputs.snapshotsByPath).set(snapshotPath, snapshot);

  const result = auditRouteMapCoverageScopes({ ...inputs, snapshotsByPath });

  assert.equal(alias.reasonCode, "OFFICIAL_RENAME");
  assert.deepEqual(violationKinds(result), ["ALIAS_RENAME_SEQUENCE_MISMATCH", "MISSING_STATION"]);
});

test("quarantine 기록이 없는 결측 ledger 항목은 거부된다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const exemptions = structuredClone(inputs.exemptions);
  const gap = exemptions.documentedCoverageGaps
    .find(({ rosterStationName }) => rosterStationName === "암사역사공원");
  gap.reasonCode = "ADMISSION_QUARANTINED";
  gap.evidence.quarantineReasonCode = "OFFICIAL_DUPLICATE_LATLON";

  const result = auditRouteMapCoverageScopes({ ...inputs, exemptions });

  assert.deepEqual(violationKinds(result), ["LEDGER_QUARANTINE_RECORD_ABSENT", "MISSING_STATION"]);
});

test("pack topology가 싣고 있는 역은 pack 결측으로 면제할 수 없다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const exemptions = structuredClone(inputs.exemptions);
  const gap = exemptions.documentedCoverageGaps
    .find(({ rosterStationName }) => rosterStationName === "암사역사공원");
  gap.reasonCode = "PACK_SCOPE_ABSENT";

  const result = auditRouteMapCoverageScopes({ ...inputs, exemptions });

  assert.deepEqual(violationKinds(result), ["LEDGER_PACK_TOPOLOGY_STATION_PRESENT", "MISSING_STATION"]);
});

test("pack topology에 없는 역은 공식 원문 결측으로 면제할 수 없다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const exemptions = structuredClone(inputs.exemptions);
  const gap = exemptions.documentedCoverageGaps
    .find(({ rosterStationName }) => rosterStationName === "신설동");
  gap.reasonCode = "OFFICIAL_FILE_ROW_ABSENT";

  const result = auditRouteMapCoverageScopes({ ...inputs, exemptions });

  assert.deepEqual(violationKinds(result), ["LEDGER_PACK_TOPOLOGY_STATION_ABSENT", "MISSING_STATION"]);
});

test("이미 커버된 역을 임의로 면제하는 ledger 항목은 거부된다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const exemptions = structuredClone(inputs.exemptions);
  exemptions.documentedCoverageGaps.push({
    scopeKey: "gwangju:gwangju-metropolitan-rapid-transit:line-e57a361e8892",
    rosterStationName: "광주송정역",
    reasonCode: "OFFICIAL_FILE_ROW_ABSENT",
    evidence: {
      issue: 2516,
      snapshotPath: "tools/datapack/sources/gwangju-transportation-route-map-positions-20260725.json",
      packTopologyPath: "tools/datapack/sources/capital-route-topology-20260724.json",
      officialUrl: "https://www.data.go.kr/data/15122916/fileData.do",
      note: "근거 없는 면제",
    },
  });

  const result = auditRouteMapCoverageScopes({ ...inputs, exemptions });

  assert.deepEqual(violationKinds(result), ["LEDGER_NOT_NEEDED"]);
});

test("admission으로 해소된 결측은 ledger에 남길 수 없다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const snapshotPath = "tools/datapack/sources/kric-ui-sinseol-route-map-positions-20260725.json";
  const snapshot = structuredClone(inputs.snapshotsByPath.get(snapshotPath));
  snapshot.positions = [...snapshot.positions, { ...snapshot.positions[0], stationName: "신설동" }];
  const snapshotsByPath = new Map(inputs.snapshotsByPath).set(snapshotPath, snapshot);

  const result = auditRouteMapCoverageScopes({ ...inputs, snapshotsByPath });

  assert.deepEqual(violationKinds(result), ["LEDGER_NOT_NEEDED"]);
});

test("lineIds를 claim한 route_map_positions 소스는 admitted snapshot 경로가 있어야 한다 (#2516)", async () => {
  const inputs = await loadAuditInputs();
  const inventory = structuredClone(inputs.inventory);
  const source = inventory.sources.find(({ id }) => id === "daejeon-transportation-route-map-positions");
  delete source.routeMapAdmissionEvidence.snapshotPath;

  const result = auditRouteMapCoverageScopes({ ...inputs, inventory });

  assert.deepEqual(violationKinds(result), ["SOURCE_SNAPSHOT_PATH_MISSING"]);
  assert.equal(result.auditedScopeKeys.includes("daejeon:daejeon-transportation:line-7051a9c2525c"), false);
});
