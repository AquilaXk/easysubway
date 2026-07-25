// route_map_positions admitted 소스가 claim한 (region, operator, line) scope에 대해
// "MOLIT roster 역 집합 ⊆ admitted snapshot 역 집합" containment를 판정한다(#2516).
//
// 면제는 두 가지만 허용하고 둘 다 근거를 실측 검증한다.
// - 승인 별칭 사전: 같은 역을 다른 표기로 실은 경우만. 별칭 대상이 snapshot에 실존해야 하고,
//   roster의 다른 역을 가리는 표기는 거부한다(결측 은폐 차단).
// - 문서화된 결측 ledger: quarantine 기록·공식 원문 결함처럼 실측 가능한 근거가 있는 결측만.
//   근거가 데이터로 확인되지 않으면 면제하지 않는다.
// 그 외 불일치는 전부 fail-closed다.

export const ROUTE_MAP_DOMAIN = "route_map_positions";

const ALIAS_REASON_CODES = Object.freeze([
  "OFFICIAL_LINE_ORDINAL_SUFFIX",
  "OFFICIAL_ABBREVIATION",
  "OFFICIAL_RENAME",
]);

const GAP_REASON_CODES = Object.freeze([
  "ADMISSION_QUARANTINED",
  "OFFICIAL_FILE_ROW_ABSENT",
  "PACK_SCOPE_ABSENT",
]);

// MOLIT 원본과 admitted snapshot은 같은 역을 다른 표기로 싣는다(부역명 병기, 역 접미사).
// 판정 대상은 역 집합의 포함 관계뿐이므로 표기 차이만 제거하고 비교한다.
function normalizeStationName(value) {
  return String(value)
    .normalize("NFKC")
    .replace(/\([^()]*\)/gu, "")
    .replace(/[·.\s]/gu, "")
    .replace(/역$/u, "")
    .trim();
}

function scopeKey({ regionId, operatorId, lineId }) {
  return `${regionId}:${operatorId}:${lineId}`;
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function isIssueNumber(value) {
  return Number.isInteger(value) && value > 0;
}

function isHttpsUrl(value) {
  return isNonEmptyString(value) && value.startsWith("https://");
}

function isIsoDate(value) {
  return isNonEmptyString(value) && /^\d{4}-\d{2}-\d{2}$/u.test(value);
}

function isSubsequence(short, long) {
  let index = 0;
  for (const character of long) {
    if (character === short[index]) {
      index += 1;
    }
  }
  return index === short.length;
}

// 노선 topology snapshot은 두 형태다: capital처럼 lines[] 묶음, daegu처럼 단일 lineId.
function topologyStationNames(topology, lineId) {
  if (Array.isArray(topology?.lines)) {
    const line = topology.lines.find((entry) => entry?.lineId === lineId);
    return Array.isArray(line?.scope) ? line.scope.map((entry) => entry?.stationName) : null;
  }
  if (topology?.lineId === lineId && Array.isArray(topology.scope)) {
    return topology.scope.map((entry) => entry?.stationName);
  }
  return null;
}

function claimedScopes(scope) {
  const claims = [];
  for (const regionId of scope.regionIds ?? []) {
    for (const operatorId of scope.operatorIds ?? []) {
      for (const lineId of scope.lineIds ?? []) {
        claims.push({ key: scopeKey({ regionId, operatorId, lineId }), lineId });
      }
    }
  }
  return claims;
}

// (operator, line) scope를 claim하지 않는 소스는 containment 판정 대상이 아니다.
function routeMapSnapshotOf(source, snapshotsByPath, violations) {
  const scope = source.coverageScope;
  if (!scope?.sourceDomains?.includes(ROUTE_MAP_DOMAIN) || (scope.lineIds ?? []).length === 0) {
    return null;
  }
  const snapshotPath = source.routeMapAdmissionEvidence?.snapshotPath;
  if (!isNonEmptyString(snapshotPath)) {
    violations.push({
      kind: "SOURCE_SNAPSHOT_PATH_MISSING",
      sourceId: source.id,
      message: `${source.id}: lineIds를 claim한 route_map_positions 소스는 routeMapAdmissionEvidence.snapshotPath가 필요하다`,
    });
    return null;
  }
  const snapshot = snapshotsByPath.get(snapshotPath);
  if (!snapshot) {
    violations.push({
      kind: "SOURCE_SNAPSHOT_UNREADABLE",
      sourceId: source.id,
      message: `${source.id}: snapshot을 읽지 못했다 (${snapshotPath})`,
    });
    return null;
  }
  return { snapshotPath, snapshot };
}

function indexScopeCoverage(coverage, snapshot, lineId) {
  for (const position of snapshot.positions ?? []) {
    if (position.lineId === lineId) {
      coverage.positionsByName.set(normalizeStationName(position.stationName), position);
    }
  }
  for (const position of snapshot.quarantinedPositions ?? []) {
    if (position.lineId === lineId) {
      coverage.quarantinedByName.set(normalizeStationName(position.stationName), position);
    }
  }
}

// coverageScope가 route_map_positions를 claim한 소스에서 (scope, snapshot) 결속을 모은다.
// 같은 scope를 여러 소스가 나눠 커버할 수 있으므로(예: 9호선 1단계 + 2·3단계) 역 집합은 합집합이다.
function collectScopeCoverage({ inventory, snapshotsByPath, violations }) {
  const coverageByScope = new Map();
  const claims = [];
  for (const source of inventory.sources ?? []) {
    const resolved = routeMapSnapshotOf(source, snapshotsByPath, violations);
    if (!resolved) {
      continue;
    }
    for (const { key, lineId } of claimedScopes(source.coverageScope)) {
      claims.push({ sourceId: source.id, key });
      const coverage = coverageByScope.get(key) ?? {
        lineId,
        sourceIds: [],
        snapshotPaths: [],
        positionsByName: new Map(),
        quarantinedByName: new Map(),
      };
      coverage.sourceIds.push(source.id);
      coverage.snapshotPaths.push(resolved.snapshotPath);
      indexScopeCoverage(coverage, resolved.snapshot, lineId);
      coverageByScope.set(key, coverage);
    }
  }
  return { coverageByScope, claims };
}

function validateAliasShape(alias, auditedScopeKeys, push) {
  if (!isNonEmptyString(alias?.scopeKey) || !auditedScopeKeys.has(alias.scopeKey)) {
    push("ALIAS_SCOPE_NOT_AUDITED", "containment 감사 대상 scope가 아니다");
    return false;
  }
  if (!isNonEmptyString(alias.snapshotStationName) || !isNonEmptyString(alias.rosterStationName)) {
    push("ALIAS_STATION_NAME_INVALID", "snapshotStationName·rosterStationName이 필요하다");
    return false;
  }
  if (!ALIAS_REASON_CODES.includes(alias.reasonCode)) {
    push("ALIAS_REASON_CODE_INVALID", `reasonCode가 승인 목록에 없다 (${alias.reasonCode})`);
    return false;
  }
  const evidence = alias.evidence;
  if (!isIssueNumber(evidence?.issue) || !isHttpsUrl(evidence?.officialUrl) || !isNonEmptyString(evidence?.note)) {
    push("ALIAS_EVIDENCE_INVALID", "evidence.issue·officialUrl·note 근거가 필요하다");
    return false;
  }
  return true;
}

function validateAliasBinding({ alias, coverage, roster, snapshotName, rosterName, seen, push }) {
  // 별칭 대상 역이 snapshot에 실존해야 한다 — 결측을 별칭으로 은폐할 수 없다.
  if (!coverage.positionsByName.has(snapshotName)) {
    push("ALIAS_SNAPSHOT_STATION_ABSENT", "snapshotStationName이 admitted snapshot에 없다");
    return false;
  }
  if (!roster.stationNames.includes(alias.rosterStationName)) {
    push("ALIAS_ROSTER_STATION_ABSENT", "rosterStationName이 MOLIT roster 원문과 다르다");
    return false;
  }
  if (coverage.positionsByName.has(rosterName)) {
    push("ALIAS_NOT_NEEDED", "roster 역이 이미 snapshot에 있어 별칭이 필요 없다");
    return false;
  }
  // snapshot 표기가 roster의 다른 역과 같으면 한 역이 두 역을 커버하게 되므로 거부한다.
  if (roster.stationNames.some((name) => normalizeStationName(name) === snapshotName)) {
    push("ALIAS_SHADOWS_ROSTER_STATION", "snapshotStationName이 roster의 다른 역과 같다");
    return false;
  }
  if (seen.snapshotNames.has(snapshotName) || seen.rosterNames.has(rosterName)) {
    push("ALIAS_DUPLICATE", "같은 scope에서 별칭은 1:1이어야 한다");
    return false;
  }
  return true;
}

function neighboursOf(orderedNames, stationName) {
  const index = orderedNames.indexOf(stationName);
  if (index < 0) {
    return null;
  }
  return [orderedNames[index - 1] ?? null, orderedNames[index + 1] ?? null];
}

function sameNeighbours(left, right) {
  if (!left || !right) {
    return false;
  }
  const [leftPrevious, leftNext] = left;
  const [rightPrevious, rightNext] = right;
  // snapshot과 roster의 나열 방향이 반대일 수 있어 역순 일치도 같은 위치로 본다.
  return (leftPrevious === rightPrevious && leftNext === rightNext)
    || (leftPrevious === rightNext && leftNext === rightPrevious);
}

// 대구 공식 파일·pack topology는 환승역을 "역명 + 호선번호"로 표기한다(명덕1 = 1호선 명덕).
function verifyLineOrdinalSuffixAlias({ coverage, snapshotName, rosterName, push }) {
  const ordinal = coverage.positionsByName.get(snapshotName).line;
  if (!isNonEmptyString(ordinal) || !/^\d+$/u.test(ordinal)) {
    push("ALIAS_LINE_ORDINAL_UNKNOWN", "snapshot position에 호선 번호(line)가 없다");
    return false;
  }
  if (snapshotName !== `${rosterName}${ordinal}`) {
    push("ALIAS_LINE_ORDINAL_MISMATCH", `표기가 "${rosterName}${ordinal}" 형태가 아니다`);
    return false;
  }
  return true;
}

function verifyRenameAlias({ alias, coverage, roster, snapshotName, rosterName, push }) {
  if (!isIsoDate(alias.evidence?.renamedAt)) {
    push("ALIAS_RENAME_EVIDENCE_INVALID", "evidence.renamedAt(YYYY-MM-DD) 공식 변경일이 필요하다");
    return false;
  }
  // 같은 역이라는 근거를 데이터로 확인한다: 노선 나열에서 이웃 역이 같아야 한다.
  if (!sameNeighbours(
    neighboursOf([...coverage.positionsByName.keys()], snapshotName),
    neighboursOf(roster.stationNames.map(normalizeStationName), rosterName),
  )) {
    push("ALIAS_RENAME_SEQUENCE_MISMATCH", "노선 나열에서 두 표기의 이웃 역이 다르다");
    return false;
  }
  return true;
}

function validateAliasReason(context) {
  const { alias, snapshotName, rosterName, push } = context;
  if (alias.reasonCode === "OFFICIAL_LINE_ORDINAL_SUFFIX") {
    return verifyLineOrdinalSuffixAlias(context);
  }
  if (alias.reasonCode === "OFFICIAL_RENAME") {
    return verifyRenameAlias(context);
  }
  if (snapshotName.length >= rosterName.length || !isSubsequence(snapshotName, rosterName)) {
    push("ALIAS_ABBREVIATION_MISMATCH", "snapshot 표기가 roster 표기의 축약형이 아니다");
    return false;
  }
  return true;
}

function validateAliases({ aliases, auditedScopeKeys, coverageByScope, rosters, violations }) {
  const aliasedRosterNamesByScope = new Map();
  const seenByScope = new Map();
  for (const [index, alias] of aliases.entries()) {
    const label = `승인 별칭[${index}] ${alias?.scopeKey} ${alias?.snapshotStationName}→${alias?.rosterStationName}`;
    const push = (kind, message) => violations.push({
      kind,
      scopeKey: alias?.scopeKey,
      message: `${label}: ${message}`,
    });
    if (!validateAliasShape(alias, auditedScopeKeys, push)) {
      continue;
    }
    const coverage = coverageByScope.get(alias.scopeKey);
    const roster = rosters.get(alias.scopeKey);
    const snapshotName = normalizeStationName(alias.snapshotStationName);
    const rosterName = normalizeStationName(alias.rosterStationName);
    const seen = seenByScope.get(alias.scopeKey)
      ?? { snapshotNames: new Set(), rosterNames: new Set() };
    seenByScope.set(alias.scopeKey, seen);
    const context = { alias, coverage, roster, snapshotName, rosterName, seen, push };
    if (!validateAliasBinding(context) || !validateAliasReason(context)) {
      continue;
    }
    seen.snapshotNames.add(snapshotName);
    seen.rosterNames.add(rosterName);
    const aliased = aliasedRosterNamesByScope.get(alias.scopeKey) ?? new Set();
    aliased.add(rosterName);
    aliasedRosterNamesByScope.set(alias.scopeKey, aliased);
  }
  return aliasedRosterNamesByScope;
}

function validateGapShape(gap, auditedScopeKeys, push) {
  if (!isNonEmptyString(gap?.scopeKey) || !auditedScopeKeys.has(gap.scopeKey)) {
    push("LEDGER_SCOPE_NOT_AUDITED", "containment 감사 대상 scope가 아니다");
    return false;
  }
  if (!isNonEmptyString(gap.rosterStationName)) {
    push("LEDGER_STATION_NAME_INVALID", "rosterStationName이 필요하다");
    return false;
  }
  if (!GAP_REASON_CODES.includes(gap.reasonCode)) {
    push("LEDGER_REASON_CODE_INVALID", `reasonCode가 승인 목록에 없다 (${gap.reasonCode})`);
    return false;
  }
  if (!isIssueNumber(gap.evidence?.issue) || !isNonEmptyString(gap.evidence?.note)) {
    push("LEDGER_EVIDENCE_INVALID", "evidence.issue·note 근거가 필요하다");
    return false;
  }
  return true;
}

function validateGapBinding({ gap, coverage, roster, rosterName, aliased, seen, push }) {
  if (!roster.stationNames.includes(gap.rosterStationName)) {
    push("LEDGER_ROSTER_STATION_ABSENT", "rosterStationName이 MOLIT roster 원문과 다르다");
    return false;
  }
  // 별칭 적용 후에도 여전히 결측인 항목만 남긴다 — admission으로 해소되면 ledger에서 빼야 한다.
  if (coverage.positionsByName.has(rosterName) || aliased.has(rosterName)) {
    push("LEDGER_NOT_NEEDED", "역이 이미 admitted snapshot에 있어 면제가 필요 없다");
    return false;
  }
  if (seen.has(rosterName)) {
    push("LEDGER_DUPLICATE", "같은 scope에 중복 항목이 있다");
    return false;
  }
  const snapshotPath = gap.evidence.snapshotPath;
  if (!isNonEmptyString(snapshotPath) || !coverage.snapshotPaths.includes(snapshotPath)) {
    push("LEDGER_SNAPSHOT_NOT_CLAIMED", "evidence.snapshotPath가 이 scope를 커버하는 admitted snapshot이 아니다");
    return false;
  }
  return true;
}

function packTopologyNames({ gap, coverage, topologiesByPath, push }) {
  const topologyPath = gap.evidence.packTopologyPath;
  if (!isHttpsUrl(gap.evidence.officialUrl)) {
    push("LEDGER_EVIDENCE_INVALID", "evidence.officialUrl 공식 원문 출처가 필요하다");
    return null;
  }
  if (!isNonEmptyString(topologyPath)) {
    push("LEDGER_PACK_TOPOLOGY_MISSING", "evidence.packTopologyPath가 필요하다");
    return null;
  }
  const stationNames = topologyStationNames(topologiesByPath.get(topologyPath), coverage.lineId);
  if (!stationNames) {
    push("LEDGER_PACK_TOPOLOGY_MISSING", `pack topology에서 ${coverage.lineId} scope를 찾지 못했다`);
    return null;
  }
  return new Set(stationNames.map(normalizeStationName));
}

function verifyQuarantinedGap({ gap, coverage, rosterName, push }) {
  const quarantined = coverage.quarantinedByName.get(rosterName);
  const declared = gap.evidence.quarantineReasonCode;
  if (!quarantined || !isNonEmptyString(declared) || quarantined.reasonCode !== declared) {
    push("LEDGER_QUARANTINE_RECORD_ABSENT", "snapshot quarantinedPositions에 같은 reasonCode 기록이 없다");
    return false;
  }
  return true;
}

// pack은 이 역을 요구하는데 공식 원문에 행이 없는 경우만 이 사유에 해당한다.
function verifyOfficialFileRowAbsentGap(context) {
  const { coverage, rosterName, snapshot, push } = context;
  const topologyNames = packTopologyNames(context);
  if (!topologyNames) {
    return false;
  }
  if (!topologyNames.has(rosterName)) {
    push("LEDGER_PACK_TOPOLOGY_STATION_ABSENT", "pack topology에 없는 역은 OFFICIAL_FILE_ROW_ABSENT가 아니다");
    return false;
  }
  if (coverage.quarantinedByName.has(rosterName)) {
    push("LEDGER_STATION_QUARANTINED", "quarantine 기록이 있는 역은 ADMISSION_QUARANTINED로 분류한다");
    return false;
  }
  // 원본 행이 전부 admitted·quarantined로 회계되면 남은 결측은 공식 원문 자체의 행 부재다.
  const accounted = (snapshot?.stationCount ?? Number.NaN) + (snapshot?.quarantinedCount ?? Number.NaN);
  if (!Number.isInteger(snapshot?.rawStationCount) || snapshot.rawStationCount !== accounted) {
    push("LEDGER_RAW_ROW_ACCOUNTING_MISMATCH", "snapshot rawStationCount가 stationCount+quarantinedCount와 다르다");
    return false;
  }
  return true;
}

// pack 노선 topology 자체가 역을 싣지 않은 경우만 이 사유에 해당한다.
function verifyPackScopeAbsentGap(context) {
  const topologyNames = packTopologyNames(context);
  if (!topologyNames) {
    return false;
  }
  if (topologyNames.has(context.rosterName)) {
    context.push("LEDGER_PACK_TOPOLOGY_STATION_PRESENT", "pack topology에 있는 역은 PACK_SCOPE_ABSENT가 아니다");
    return false;
  }
  return true;
}

function validateGapReason(context) {
  if (context.gap.reasonCode === "ADMISSION_QUARANTINED") {
    return verifyQuarantinedGap(context);
  }
  if (context.gap.reasonCode === "OFFICIAL_FILE_ROW_ABSENT") {
    return verifyOfficialFileRowAbsentGap(context);
  }
  return verifyPackScopeAbsentGap(context);
}

function validateGaps({
  gaps,
  auditedScopeKeys,
  coverageByScope,
  rosters,
  aliasedRosterNamesByScope,
  snapshotsByPath,
  topologiesByPath,
  violations,
}) {
  const gapRosterNamesByScope = new Map();
  for (const [index, gap] of gaps.entries()) {
    const label = `결측 ledger[${index}] ${gap?.scopeKey} ${gap?.rosterStationName}`;
    const push = (kind, message) => violations.push({
      kind,
      scopeKey: gap?.scopeKey,
      message: `${label}: ${message}`,
    });
    if (!validateGapShape(gap, auditedScopeKeys, push)) {
      continue;
    }
    const coverage = coverageByScope.get(gap.scopeKey);
    const rosterName = normalizeStationName(gap.rosterStationName);
    const seen = gapRosterNamesByScope.get(gap.scopeKey) ?? new Set();
    gapRosterNamesByScope.set(gap.scopeKey, seen);
    const context = {
      gap,
      coverage,
      roster: rosters.get(gap.scopeKey),
      rosterName,
      aliased: aliasedRosterNamesByScope.get(gap.scopeKey) ?? new Set(),
      seen,
      snapshot: snapshotsByPath.get(gap.evidence.snapshotPath),
      topologiesByPath,
      push,
    };
    if (!validateGapBinding(context) || !validateGapReason(context)) {
      continue;
    }
    seen.add(rosterName);
  }
  return gapRosterNamesByScope;
}

function auditableScopeKeys({ claims, activeScopeKeys, rosters, violations }) {
  const auditedScopeKeys = [];
  const seen = new Set();
  for (const claim of claims) {
    // activeLineScopes에 없는 (operator, line) 조합은 #2138 requirement가 아니라 lineage 표기다.
    if (!activeScopeKeys.has(claim.key) || seen.has(claim.key)) {
      continue;
    }
    seen.add(claim.key);
    if (!rosters.get(claim.key)) {
      violations.push({
        kind: "ROSTER_MISSING",
        scopeKey: claim.key,
        message: `${claim.key}: MOLIT roster가 없다 (${claim.sourceId})`,
      });
      continue;
    }
    auditedScopeKeys.push(claim.key);
  }
  return auditedScopeKeys;
}

/**
 * route_map_positions 전 scope containment를 판정한다.
 *
 * @returns {{ auditedScopeKeys: string[], violations: Array<{ kind: string, message: string }> }}
 */
export function auditRouteMapCoverageScopes({
  inventory,
  targets,
  rosters,
  exemptions,
  snapshotsByPath,
  topologiesByPath = new Map(),
}) {
  const violations = [];
  const activeScopeKeys = new Set((targets.activeLineScopes ?? []).map(scopeKey));
  const { coverageByScope, claims } = collectScopeCoverage({ inventory, snapshotsByPath, violations });
  const auditedScopeKeys = auditableScopeKeys({ claims, activeScopeKeys, rosters, violations });
  const auditedScopeKeySet = new Set(auditedScopeKeys);

  const aliasedRosterNamesByScope = validateAliases({
    aliases: exemptions.approvedStationNameAliases ?? [],
    auditedScopeKeys: auditedScopeKeySet,
    coverageByScope,
    rosters,
    violations,
  });
  const gapRosterNamesByScope = validateGaps({
    gaps: exemptions.documentedCoverageGaps ?? [],
    auditedScopeKeys: auditedScopeKeySet,
    coverageByScope,
    rosters,
    aliasedRosterNamesByScope,
    snapshotsByPath,
    topologiesByPath,
    violations,
  });

  for (const key of auditedScopeKeys) {
    const roster = rosters.get(key);
    const coverage = coverageByScope.get(key);
    const aliased = aliasedRosterNamesByScope.get(key) ?? new Set();
    const ledgered = gapRosterNamesByScope.get(key) ?? new Set();
    // MOLIT roster 나열 순서를 유지한다(노선 순서). 정렬은 로케일 의존이라 쓰지 않는다.
    const missing = [...new Set(roster.stationNames.map(normalizeStationName))]
      .filter((stationName) => !coverage.positionsByName.has(stationName)
        && !aliased.has(stationName)
        && !ledgered.has(stationName));
    if (missing.length > 0) {
      violations.push({
        kind: "MISSING_STATION",
        scopeKey: key,
        message: `${key} (${roster.operatorName}): admitted snapshot [${coverage.sourceIds.join(", ")}]에 없는 역 ${missing.join(", ")}`,
      });
    }
  }

  return { auditedScopeKeys, violations };
}
