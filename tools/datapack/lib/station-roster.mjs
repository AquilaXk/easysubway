// #1701 Phase 2: importer 공용 canonical roster 매칭 헬퍼.
//
// roster 입력: [{ stationId, lineId, nameKo, normalizedName, aliases: [{alias, normalizedAlias}] }].
// 임의 추측 매칭을 금지한다 — 정규화된 역명이 roster의 normalizedName/normalizedAlias와
// 일치하는 후보만 사용한다. 매칭 실패·모호(2건 이상 stationId 후보)는 { error }로 계측한다.
//
// 정규화 규칙은 기존 build-molit-nationwide-fixture.mjs의 normalizedStationNameForMap 관례를
// 따른다: 괄호/대괄호 병기 제거, 중점·공백 제거, "역" 접미사 제거.

/**
 * 순수 함수: 역명을 매칭용 canonical 형태로 정규화한다.
 * 괄호/대괄호 병기·중점·공백 제거 후 "역" 접미사를 제거한다.
 */
export function normalizeStationName(name) {
  return String(name ?? "")
    .replace(/\([^)]*\)/g, "")
    .replace(/\[[^\]]*]/g, "")
    .replace(/[·.\s]/g, "")
    .replace(/역$/g, "")
    .trim();
}

/**
 * 순수 함수: 노선명을 매칭용 canonical 형태로 정규화한다(공백·중점 제거).
 */
export function normalizeLineName(name) {
  return String(name ?? "").replace(/[·.\s]/g, "").trim();
}

/**
 * roster 배열을 색인해 매칭 API를 반환한다.
 * - matchStation(name): 정규화된 역명 → { stationId } 또는 { error }.
 *   normalizedName / alias 둘 다 조회하며, stationId 후보가 2개 이상이면 모호 error.
 * - matchLineForStation(stationId, lineName): 해당 역에 속한 라인 중 정규화 노선명과
 *   일치하는 lineId → { lineId } 또는 { error }.
 */
export function buildRosterIndex(roster) {
  // normalizedName → Set(stationId)
  const stationIdsByNormalizedName = new Map();
  // stationId → Set(lineId)
  const lineIdsByStation = new Map();
  // stationId → Map(normalizedLineName → Set(lineId))
  const lineNamesByStation = new Map();

  const addNameKey = (key, stationId) => {
    if (!key) return;
    if (!stationIdsByNormalizedName.has(key)) {
      stationIdsByNormalizedName.set(key, new Set());
    }
    stationIdsByNormalizedName.get(key).add(stationId);
  };

  for (const entry of roster) {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new TypeError("roster entries must be objects");
    }
    const stationId = requiredRosterString(entry.stationId, "roster.stationId");
    const lineId = requiredRosterString(entry.lineId, "roster.lineId");

    const normalizedName = typeof entry.normalizedName === "string" && entry.normalizedName.trim() !== ""
      ? normalizeStationName(entry.normalizedName)
      : normalizeStationName(entry.nameKo);
    addNameKey(normalizedName, stationId);

    for (const alias of entry.aliases ?? []) {
      if (!alias || typeof alias !== "object") continue;
      const normalizedAlias = typeof alias.normalizedAlias === "string" && alias.normalizedAlias.trim() !== ""
        ? normalizeStationName(alias.normalizedAlias)
        : normalizeStationName(alias.alias);
      addNameKey(normalizedAlias, stationId);
    }

    if (!lineIdsByStation.has(stationId)) {
      lineIdsByStation.set(stationId, new Set());
    }
    lineIdsByStation.get(stationId).add(lineId);

    if (!lineNamesByStation.has(stationId)) {
      lineNamesByStation.set(stationId, new Map());
    }
    const lineNameMap = lineNamesByStation.get(stationId);
    // lineId 자체와 nameKo에서 유추한 노선명 후보를 등록. lineNameKo가 있으면 그것도.
    for (const candidate of [entry.lineNameKo, entry.lineName, lineId]) {
      const key = normalizeLineName(candidate);
      if (!key) continue;
      if (!lineNameMap.has(key)) {
        lineNameMap.set(key, new Set());
      }
      lineNameMap.get(key).add(lineId);
    }
  }

  return {
    matchStation(name) {
      const normalized = normalizeStationName(name);
      if (!normalized) {
        return { error: `station name normalization empty: ${name}` };
      }
      const candidates = stationIdsByNormalizedName.get(normalized);
      if (!candidates || candidates.size === 0) {
        return { error: `station roster match failed: ${name}` };
      }
      if (candidates.size > 1) {
        return { error: `station roster match ambiguous: ${name} -> ${[...candidates].sort().join(", ")}` };
      }
      return { stationId: [...candidates][0] };
    },
    matchLineForStation(stationId, lineName) {
      const lineNameMap = lineNamesByStation.get(stationId);
      if (!lineNameMap) {
        return { error: `line roster match failed (unknown station): ${stationId}` };
      }
      const normalized = normalizeLineName(lineName);
      if (!normalized) {
        return { error: `line name normalization empty: ${lineName}` };
      }
      const candidates = lineNameMap.get(normalized);
      if (!candidates || candidates.size === 0) {
        return { error: `line roster match failed: ${stationId}:${lineName}` };
      }
      if (candidates.size > 1) {
        return { error: `line roster match ambiguous: ${stationId}:${lineName} -> ${[...candidates].sort().join(", ")}` };
      }
      return { lineId: [...candidates][0] };
    },
  };
}

function requiredRosterString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new TypeError(`${label} is required`);
  }
  return value.trim();
}
