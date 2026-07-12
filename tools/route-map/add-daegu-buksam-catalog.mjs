#!/usr/bin/env node
// #2019: 대구 카탈로그에 대경선 북삼역 추가 — 개통역 미수록 공백 해소.
// #1954(검단연장 3역 카탈로그 신설)와 같은 station-surgery 패턴이나, 북삼은
// 노선 중간(왜관↔사곡)에 끼어들어 후속 역의 line_sequence를 밀어야 하므로
// 시퀀스 리시퀀싱을 포함한다.
//
// ⛔ 사실 확정은 공식 출처.
//  - 소속: 대구권 광역철도 1단계 대경선(코레일 운영). 대경선은 #1951 확정 4노선의 하나.
//  - 개통: 2026-02-28 첫차 운영 개시(경상북도 2026-02-27 개통식 공식 보도자료,
//    칠곡군 북삼읍 율리). 1918년 약목역 이후 칠곡군 백년 만의 신설역.
//  - 위상: 왜관(칠곡)↔사곡(구미) 사이 — 그동안 과도했던 역간 거리를 메운다.
//    도식 실측(easy-subway-daegu-v1) x좌표: 왜관 800 > 북삼 590 > 사곡 380 > 구미 150.
//    즉 대경선 순서는 …왜관(5) → 북삼(6) → 사곡(7) → 구미(8).
//
// 좌표 provenance: admitted 소스(MOLIT 전국 순번표 2025-12-11 스냅샷)는 북삼
// 개통(2026-02-28)보다 앞서 아직 북삼을 담지 않는다. 날조 금지 원칙에 따라
// 좌표는 NULL, 품질 표기는 LEVEL_1/OPERATOR_PAGE로 남긴다(#1954 검단연장과 동일).
// 도식 좌표(route_map_positions)는 대구 파이프라인(run-sma-pipeline-daegu.sh)이
// 자작 정본 도식에서 재생성한다 — 그 전제로 sma-region-configs DAEGU
// excludedStations에서 "북삼"을 제거한다.
//
// 사용: node tools/route-map/add-daegu-buksam-catalog.mjs [--pack …] [--index …] [--check]
import { createHash } from "node:crypto";
import { mutatePack, parsePackArgs } from "./station-surgery.mjs";

export const REGION = "대구권";
export const DAEGYEONG = "line-8f7ed01f290a"; // 대구 대경선

// 경상북도 공식 보도자료 개통식(2026-02-27) 검증 기준일.
export const VERIFIED_PRESS_AT = Date.UTC(2026, 1, 27) / 1000;

/** 신설 역의 결정적 station id — #1954 해시 기반 id 정책과 동일(이슈 번호로 salt). */
export function newStationId(lineId, nameKo) {
  const hex = createHash("sha256")
    .update(`new-station:${lineId}:${nameKo}:2019`)
    .digest("hex");
  return `station-${hex.slice(0, 12)}`;
}

/** 신설 역 스펙(공식 근거 첨부). 좌표 null = admitted 소스 미반영(날조 금지). */
export const BUKSAM = {
  name: "북삼",
  lineId: DAEGYEONG,
  lineSequence: 6, // 왜관(5) 다음, 사곡(기존 6)을 7로 밀어낸다.
  latitude: null,
  longitude: null,
  dataQualityLevel: "LEVEL_1",
  dataSourceType: "OPERATOR_PAGE",
  lastVerifiedAt: VERIFIED_PRESS_AT,
  evidence:
    "대경선 북삼역 개통(2026-02-28 운영 개시, 경상북도 공식 보도자료 — 칠곡군 북삼읍, 왜관↔사곡 사이)",
};

/**
 * 북삼을 잇는 RIDE 인접 체인. 문자열은 BUKSAM(신규 id로 해소), `{id,name}`은 기존 역.
 * removeDirect는 북삼이 끼어들며 끊어야 할 기존 왜관↔사곡 직결쌍.
 * expectedMembers는 반영 후 대경선 멤버 수(기존 7 + 북삼 = 8) 게이트.
 */
export const RIDE_CHAIN = {
  lineId: DAEGYEONG,
  // 왜관(기존) → 북삼(신규) → 사곡(기존)
  chain: [
    { id: "station-6502c3637045", name: "왜관" },
    "북삼",
    { id: "station-2e9e270f159d", name: "사곡" },
  ],
  expectedMembers: 8,
  removeDirect: [["station-6502c3637045", "station-2e9e270f159d"]],
  lastVerifiedAt: VERIFIED_PRESS_AT,
};

/**
 * 순수: 신설 역 스펙 → stations/station_lines 행. 기존 대구 카탈로그 관례를 따른다
 * (normalized_name = name_ko 원문, station_code = line_sequence 문자열,
 * name_en/name_sub/platform_info 빈 문자열).
 */
export function planNewStation(spec) {
  const id = newStationId(spec.lineId, spec.name);
  return {
    station: {
      id,
      name_ko: spec.name,
      name_en: "",
      normalized_name: spec.name,
      region: REGION,
      latitude: spec.latitude,
      longitude: spec.longitude,
      data_quality_level: spec.dataQualityLevel,
      data_source_type: spec.dataSourceType,
      last_verified_at: spec.lastVerifiedAt,
      name_sub: "",
    },
    stationLine: {
      station_id: id,
      line_id: spec.lineId,
      station_code: String(spec.lineSequence),
      line_sequence: spec.lineSequence,
      platform_info: "",
    },
  };
}

/** 순수: 인접쌍 → 양방향 RIDE 엣지 2행(기존 RIDE 관례 필드값·id 포맷). */
export function rideEdgePair(lineId, fromStationId, toStationId, lastVerifiedAt) {
  const row = (a, b) => ({
    id: `edge-${lineId}-${a}-${b}`,
    from_node_id: `${a}:${lineId}`,
    to_node_id: `${b}:${lineId}`,
    duration_seconds: 120,
    distance_meters: 0,
    edge_type: "RIDE",
    service_pattern: "LOCAL",
    includes_stairs: 0,
    stair_access_state: "UNKNOWN",
    accessibility_status: "UNKNOWN",
    reliability_score: 80,
    facility_id: null,
    last_verified_at: lastVerifiedAt,
  });
  return [row(fromStationId, toStationId), row(toStationId, fromStationId)];
}

function insertRow(db, table, row) {
  const cols = Object.keys(row);
  db.prepare(
    `INSERT INTO ${table} (${cols.join(",")}) VALUES (${cols.map(() => "?").join(",")})`,
  ).run(...cols.map((c) => row[c]));
}

/**
 * 신설 역의 seq를 비우기 위해, 해당 노선에서 line_sequence >= insertAt인 기존 역의
 * line_sequence를 +1 밀고 station_code(=순번 문자열 관례)도 동기화한다.
 * 큰 순번부터 내려오며 갱신해 UNIQUE 충돌을 피한다. 밀린 역 목록을 반환한다.
 */
export function resequenceFrom(db, lineId, insertAt) {
  const shifted = db
    .prepare(
      "SELECT sl.station_id, sl.line_sequence, s.name_ko FROM station_lines sl JOIN stations s ON s.id = sl.station_id WHERE sl.line_id = ? AND sl.line_sequence >= ? ORDER BY sl.line_sequence DESC",
    )
    .all(lineId, insertAt);
  const upd = db.prepare(
    "UPDATE station_lines SET line_sequence = ?, station_code = ? WHERE station_id = ? AND line_id = ?",
  );
  for (const row of shifted) {
    const next = row.line_sequence + 1;
    upd.run(next, String(next), row.station_id, lineId);
  }
  return shifted
    .map((r) => ({ name: r.name_ko, from: r.line_sequence, to: r.line_sequence + 1 }))
    .reverse();
}

function applyNewStation(db, spec) {
  const { station, stationLine } = planNewStation(spec);
  if (db.prepare("SELECT 1 FROM stations WHERE id=?").get(station.id)) {
    return { name: spec.name, id: station.id, skipped: "이미 반영됨" };
  }
  const clash = db
    .prepare("SELECT id FROM stations WHERE normalized_name=? AND region=?")
    .get(station.normalized_name, REGION);
  if (clash) {
    throw new Error(`${spec.name}: 동명 역이 이미 있음(${clash.id}) — 수동 확인`);
  }
  // 삽입 위치를 비우기 위해 후속 역을 먼저 리시퀀싱한다.
  const shifted = resequenceFrom(db, spec.lineId, spec.lineSequence);
  insertRow(db, "stations", station);
  insertRow(db, "station_lines", stationLine);
  return {
    name: spec.name,
    id: station.id,
    lineId: spec.lineId,
    lineSequence: spec.lineSequence,
    shifted,
    evidence: spec.evidence,
  };
}

/**
 * 읽기 전용: applyChain 사전조건(체인 역 존재·removeDirect 직결 엣지 존재)을
 * --check 미리보기용으로 점검한다. applyChain과 동일한 id 해소 규칙을 쓴다.
 */
export function previewChain(db, { lineId, chain, removeDirect }) {
  const rows = [];
  for (const entry of chain) {
    const id = typeof entry === "string" ? newStationId(lineId, entry) : entry.id;
    const name = typeof entry === "string" ? entry : entry.name;
    const present = Boolean(db.prepare("SELECT 1 FROM stations WHERE id=?").get(id));
    rows.push({ name, id, present });
  }
  for (const [a, b] of removeDirect) {
    const present = Boolean(
      db
        .prepare(
          "SELECT 1 FROM network_edges WHERE edge_type='RIDE' AND from_node_id=? AND to_node_id=?",
        )
        .get(`${a}:${lineId}`, `${b}:${lineId}`),
    );
    rows.push({ name: `직결 ${a}↔${b}`, id: `${a}:${lineId}`, present });
  }
  return rows;
}

export function applyChain(db, { lineId, chain, expectedMembers, removeDirect, lastVerifiedAt }) {
  const ids = chain.map((entry) =>
    typeof entry === "string" ? newStationId(lineId, entry) : entry.id,
  );
  for (const entry of chain) {
    const id = typeof entry === "string" ? newStationId(lineId, entry) : entry.id;
    if (!db.prepare("SELECT 1 FROM stations WHERE id=?").get(id)) {
      const name = typeof entry === "string" ? entry : entry.name;
      throw new Error(`${lineId}: 체인 역 없음 ${name}(${id})`);
    }
  }
  const del = db.prepare(
    "DELETE FROM network_edges WHERE edge_type='RIDE' AND from_node_id=? AND to_node_id=?",
  );
  let removed = 0;
  for (const [a, b] of removeDirect) {
    removed += del.run(`${a}:${lineId}`, `${b}:${lineId}`).changes;
    removed += del.run(`${b}:${lineId}`, `${a}:${lineId}`).changes;
  }
  let inserted = 0;
  for (let i = 0; i + 1 < ids.length; i += 1) {
    for (const edge of rideEdgePair(lineId, ids[i], ids[i + 1], lastVerifiedAt)) {
      const dup = db
        .prepare(
          "SELECT 1 FROM network_edges WHERE edge_type='RIDE' AND from_node_id=? AND to_node_id=?",
        )
        .get(edge.from_node_id, edge.to_node_id);
      if (dup) continue;
      insertRow(db, "network_edges", edge);
      inserted += 1;
    }
  }
  const members = db
    .prepare("SELECT COUNT(*) c FROM station_lines WHERE line_id=?")
    .get(lineId).c;
  if (members !== expectedMembers) {
    throw new Error(`${lineId}: 반영 후 멤버 수 ${members} ≠ 기대 ${expectedMembers}`);
  }
  return { lineId, removedEdges: removed, insertedEdges: inserted, members };
}

function main() {
  const o = parsePackArgs(process.argv.slice(2));
  mutatePack({ ...o, tmpPrefix: "add-daegu-buksam-", run: (db) => {
    if (o.check) {
      const { station } = planNewStation(BUKSAM);
      const exists = db.prepare("SELECT 1 FROM stations WHERE id=?").get(station.id);
      const occupied = db
        .prepare("SELECT station_id FROM station_lines WHERE line_id=? AND line_sequence=?")
        .get(BUKSAM.lineId, BUKSAM.lineSequence);
      console.log(
        `(--check) ${BUKSAM.name} → ${station.id} ${BUKSAM.lineId} seq=${BUKSAM.lineSequence} [${exists ? "이미 있음" : "신규"}${occupied ? `, seq 현재 점유: ${occupied.station_id}(리시퀀싱 대상)` : ""}] (${BUKSAM.evidence})`,
      );
      for (const { name, id, present } of previewChain(db, RIDE_CHAIN)) {
        console.log(`(--check) 체인 ${RIDE_CHAIN.lineId}: ${name}(${id}) ${present ? "있음" : "없음 ⚠"}`);
      }
      return;
    }
    db.exec("BEGIN");
    const station = applyNewStation(db, BUKSAM);
    const chain = applyChain(db, RIDE_CHAIN);
    db.exec("COMMIT");
    if (station.skipped) {
      console.log(`${station.name}: ${station.skipped} (${station.id})`);
    } else {
      console.log(`${station.name}: ${station.id} ${station.lineId} seq=${station.lineSequence} (${station.evidence})`);
      for (const s of station.shifted) console.log(`  리시퀀싱: ${s.name} ${s.from}→${s.to}`);
    }
    console.log(
      `${chain.lineId}: RIDE 엣지 +${chain.insertedEdges}/-${chain.removedEdges} · 멤버 ${chain.members}`,
    );
  } });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
