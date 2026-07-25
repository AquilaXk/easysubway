import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { gunzipSync } from "node:zlib";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import {
  buildAssignments,
  canonicalStationName,
  resolveStationIds,
} from "./apply-sma-svg-positions.mjs";
import { getRegionConfig } from "./sma-region-configs.mjs";
import { octolinearizeChain, stitchToPaths, SVG_COLOR_TO_SLUG } from "./build-sma-tracks.mjs";
import { diffExtractions } from "./diff-sma-versions.mjs";

test("canonicalStationName: 콜론 동명이역·역 접미·이수 별칭 규칙", () => {
  // 콜론 동명이역은 이름만 취하고 노선 disambiguate 플래그를 세운다.
  assert.deepEqual(canonicalStationName("신촌:2호선"), {
    name: "신촌",
    disambiguateByLine: true,
  });
  assert.deepEqual(canonicalStationName("양평:경의중앙선"), {
    name: "양평",
    disambiguateByLine: true,
  });
  // 하남검단산 → 역 접미.
  assert.deepEqual(canonicalStationName("하남검단산"), { name: "하남검단산역" });
  // 이수 → 총신대입구 별칭.
  assert.deepEqual(canonicalStationName("이수"), { name: "총신대입구" });
  // 일반 역은 그대로.
  assert.deepEqual(canonicalStationName("용인중앙시장"), { name: "용인중앙시장" });
});

// #2068 오너 v4 반입: data-station 표기가 바뀌었다(콜론 동명이역 힌트 제거,
// 괄호 부제, 가운뎃점). 규칙이 v4 표기를 흡수하는지 고정한다.
test("canonicalStationName: v4 표기(괄호 부제·가운뎃점·콜론 제거)를 카탈로그 표기로 정규화한다", () => {
  // 콜론이 사라진 신촌·양평은 이름만으로 동명 별개역이므로 여전히 노선 해소가 필요하다.
  assert.deepEqual(canonicalStationName("신촌"), {
    name: "신촌",
    disambiguateByLine: true,
  });
  assert.deepEqual(canonicalStationName("신촌(경의중앙선)"), {
    name: "신촌",
    disambiguateByLine: true,
  });
  assert.deepEqual(canonicalStationName("양평"), {
    name: "양평",
    disambiguateByLine: true,
  });
  // 괄호 부제 제거 후 이수 별칭까지 적용된다.
  assert.deepEqual(canonicalStationName("총신대입구(이수)"), { name: "총신대입구" });
  // 가운뎃점(U+00B7) → 카탈로그 표기(마침표).
  assert.deepEqual(canonicalStationName("시청·용인대"), { name: "시청.용인대" });
  assert.deepEqual(canonicalStationName("전대·에버랜드"), { name: "전대.에버랜드" });
  // 마침표를 이름에 포함하는 역은 건드리지 않는다.
  assert.deepEqual(canonicalStationName("4.19민주묘지"), { name: "4.19민주묘지" });
});

// #2068 신원 보호: 신촌·양평은 이름이 같아도 별개 물리역이다. 노선 해소가 풀리면
// resolveStationIds가 두 station_id에 같은 좌표를 broadcast해 신원이 뒤섞인다
// (부산역↔부산진 전례). 노선당 정확히 1개 id만 나오도록 계약을 고정한다.
test("resolveStationIds: 동명 별개역(신촌·양평)은 노선으로 1:1 해소하고 broadcast하지 않는다", () => {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    CREATE TABLE stations (id TEXT PRIMARY KEY, name_ko TEXT);
    CREATE TABLE lines (id TEXT PRIMARY KEY, name_ko TEXT);
    CREATE TABLE station_lines (station_id TEXT, line_id TEXT);
    INSERT INTO stations VALUES ('s-yp-5','양평'),('s-yp-gj','양평');
    INSERT INTO lines VALUES ('l-5','수도권 5호선'),('l-gj','수도권 경의중앙');
    INSERT INTO station_lines VALUES ('s-yp-5','l-5'),('s-yp-gj','l-gj');
  `);
  const canon = canonicalStationName("양평");
  const opts = { disambiguateByLine: canon.disambiguateByLine === true };
  assert.deepEqual(resolveStationIds(db, canon.name, "l-5", opts), ["s-yp-5"]);
  assert.deepEqual(resolveStationIds(db, canon.name, "l-gj", opts), ["s-yp-gj"]);
  // 규칙이 풀리면(플래그 없음) 두 id에 같은 좌표가 broadcast된다 — 회귀 감지용 대조.
  assert.deepEqual(resolveStationIds(db, "양평", "l-5", {}), ["s-yp-5", "s-yp-gj"]);
  db.close();
});

// 위 계약은 오너 SVG가 두 노드에 서로 다른 data-line을 실어 줄 때만 성립한다.
// v4 실 SVG에서 그 전제를 실측으로 고정한다(도식이 힌트를 잃으면 즉시 실패).
test("easy-subway-sma-v4: 동명 별개역 노드는 서로 다른 data-line을 들고 있다", () => {
  const svg = readFileSync(
    path.join(
      import.meta.dirname,
      "route-map-defs/svg-sources/easy-subway-sma-v4.svg",
    ),
    "utf8",
  );
  const lineAttrsFor = (dataStation) =>
    [...svg.matchAll(/<circle\b[^>]*>/g)]
      .map((m) => m[0])
      .filter((tag) => tag.includes(`data-station="${dataStation}"`))
      .map((tag) => /\bdata-line="([^"]*)"/.exec(tag)?.[1] ?? "");

  assert.deepEqual(lineAttrsFor("양평"), ["5", "gyeongui-jungang"]);
  assert.deepEqual(lineAttrsFor("신촌"), ["2"]);
  assert.deepEqual(lineAttrsFor("신촌(경의중앙선)"), ["gyeongui-jungang"]);
});

test("SVG_COLOR_TO_SLUG: 24 노선색이 슬러그와 1:1", () => {
  const slugs = new Set(Object.values(SVG_COLOR_TO_SLUG));
  assert.equal(Object.keys(SVG_COLOR_TO_SLUG).length, 24);
  assert.equal(slugs.size, 24);
  assert.equal(SVG_COLOR_TO_SLUG["#a49d87"], "9"); // 저채도 9호선 gold
  assert.equal(SVG_COLOR_TO_SLUG["#5eac41"], "seohae");
});

test("octolinearizeChain: 비축 세그먼트를 최근접 8방향으로 스냅", () => {
  // 수평 후 약간 어긋난 대각 → 순수 8방향(수평·45°)으로 정렬.
  const snapped = octolinearizeChain([
    { x: 0, y: 0 },
    { x: 100, y: 2 }, // ≈수평
    { x: 150, y: 53 }, // ≈45°
  ]);
  // 각 세그먼트가 0/45/90/135°인지 확인.
  for (let i = 1; i < snapped.length; i += 1) {
    const dx = snapped[i].x - snapped[i - 1].x;
    const dy = snapped[i].y - snapped[i - 1].y;
    const angle = ((Math.atan2(dy, dx) * 180) / Math.PI) % 45;
    assert.ok(Math.min(Math.abs(angle), 45 - Math.abs(angle)) < 1e-6, `세그먼트 ${i} 비축`);
  }
});

test("stitchToPaths: 끝점 근접 조각을 하나의 chain으로 잇는다", () => {
  const paths = stitchToPaths(
    [
      [
        { x: 0, y: 0 },
        { x: 100, y: 0 },
      ],
      [
        { x: 100, y: 0 },
        { x: 100, y: 100 },
      ],
    ],
    6,
  );
  assert.equal(paths.length, 1); // 한 chain으로 이어짐
  assert.match(paths[0], /^M /);
});

test("diffExtractions: 역 추가/삭제/이동/노선 변화 요약", () => {
  const old = {
    sourceSvgSha256: "a",
    stationNodes: [
      { dataStation: "가", dataLine: "1", x: 0, y: 0 },
      { dataStation: "나", dataLine: "1", x: 10, y: 0 },
    ],
  };
  const next = {
    sourceSvgSha256: "b",
    stationNodes: [
      { dataStation: "가", dataLine: "1", x: 0, y: 0 }, // 동일
      { dataStation: "다", dataLine: "2", x: 20, y: 0 }, // 추가
    ],
  };
  const report = diffExtractions(old, next, { moveThreshold: 4 });
  assert.equal(report.addedCount, 1);
  assert.equal(report.added[0].station, "다");
  assert.equal(report.removedCount, 1);
  assert.equal(report.removed[0].station, "나");
  assert.equal(report.movedCount, 0);
  // 노선 노드 수 변화: 1호선 2→1, 2호선 0→1.
  assert.ok(report.lineNodeCountChanges.some((c) => c.line === "1" && c.before === 2 && c.after === 1));
});

test("diffExtractions: moveThreshold 초과 이동을 moved로 감지", () => {
  const old = {
    sourceSvgSha256: "a",
    stationNodes: [
      { dataStation: "가", dataLine: "1", x: 0, y: 0 }, // 이동 없음
      { dataStation: "나", dataLine: "1", x: 10, y: 0 }, // 임계 초과 이동
    ],
  };
  const next = {
    sourceSvgSha256: "b",
    stationNodes: [
      { dataStation: "가", dataLine: "1", x: 0, y: 0 }, // 동일
      { dataStation: "나", dataLine: "1", x: 20, y: 0 }, // dist 10 > threshold 4
    ],
  };
  const report = diffExtractions(old, next, { moveThreshold: 4 });
  assert.equal(report.addedCount, 0);
  assert.equal(report.removedCount, 0);
  assert.equal(report.movedCount, 1);
  assert.equal(report.moved[0].station, "나");
  assert.equal(report.moved[0].distance, 10);
  assert.deepEqual(report.moved[0].from, { x: 10, y: 0 });
  assert.deepEqual(report.moved[0].to, { x: 20, y: 0 });
  // 임계 이하 이동(가: dist 0)은 moved에 포함되지 않는다.
  assert.ok(!report.moved.some((m) => m.station === "가"));
});

// #2068 신원 사고 구조적 방어(C2). 한 station_id에 서로 멀리 떨어진 노드가 여러 개
// 배정 후보로 잡히면 "첫 배정 채택"이 좌표를 통째로 엉뚱한 자리로 보낼 수 있는데,
// 미매핑·미해소 게이트는 개수만 보므로 그대로 통과한다(v4 김포공항 픽토그램).
function scatterProbeDb() {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    CREATE TABLE stations (id TEXT PRIMARY KEY, name_ko TEXT);
    CREATE TABLE lines (id TEXT PRIMARY KEY, name_ko TEXT);
    CREATE TABLE station_lines (station_id TEXT, line_id TEXT);
    CREATE TABLE route_map_positions (station_id TEXT, line_id TEXT, region TEXT, x REAL, y REAL);
    INSERT INTO stations VALUES ('s-gimpo','김포공항');
    INSERT INTO lines VALUES ('l-air','수도권 공항'),('l-gold','수도권 김포골드라인');
    INSERT INTO station_lines VALUES ('s-gimpo','l-air'),('s-gimpo','l-gold');
  `);
  return db;
}

function scatterProbeConfig(exceptions = []) {
  return {
    ...getRegionConfig("seoul"),
    slugToSuffix: { "airport-railroad": "공항", "gimpo-goldline": "김포골드라인" },
    scatteredCandidateExceptions: exceptions,
  };
}

const scatterProbeExtraction = {
  stationNodes: [
    {
      dataStation: "김포공항",
      dataLine: "gimpo-goldline",
      x: 763,
      y: 1055,
      nodeRole: "transfer",
    },
    // 장식 픽토그램이 역 마커로 오인된 상황 재현(캡슐에서 200px 떨어짐).
    {
      dataStation: "김포공항",
      dataLine: "airport-railroad",
      x: 870,
      y: 1033,
      nodeRole: "transfer",
    },
  ],
  labels: [],
};

test("buildAssignments: 한 역에 100px 넘게 떨어진 복수 노드가 잡히면 실패한다(fail-closed)", () => {
  const db = scatterProbeDb();
  assert.throws(
    () => buildAssignments(db, scatterProbeExtraction, scatterProbeConfig()),
    (error) =>
      /100px 넘게 떨어진 노드/.test(error.message) &&
      /s-gimpo/.test(error.message) &&
      /109\.2px/.test(error.message),
  );
  db.close();
});

test("buildAssignments: 100px 이내 중복 노드와 명시 예외는 통과한다", () => {
  const db = scatterProbeDb();
  // (a) 같은 자리 근처의 정상 중복 노드는 통과.
  const near = {
    labels: [],
    stationNodes: [
      { ...scatterProbeExtraction.stationNodes[0] },
      { ...scatterProbeExtraction.stationNodes[1], x: 770, y: 1060 },
    ],
  };
  assert.equal(buildAssignments(db, near, scatterProbeConfig()).assignments.length, 1);
  // (b) 카탈로그 오병합 등 알려진 케이스는 config 명시 예외로만 면제된다.
  const exempt = scatterProbeConfig([{ name: "김포공항", reason: "테스트 예외" }]);
  assert.equal(
    buildAssignments(db, scatterProbeExtraction, exempt).assignments.length,
    1,
  );
  db.close();
});

test("easy-subway-sma-v4 geometry: 김포공항 노드는 캡슐 1개뿐이고 장식 픽토그램은 없다", () => {
  const geometry = JSON.parse(
    readFileSync(
      path.join(import.meta.dirname, "route-map-defs/easy-subway-sma-v4-geometry.json"),
      "utf8",
    ),
  );
  const gimpo = geometry.stationNodes.filter((n) => n.dataStation === "김포공항");
  assert.equal(gimpo.length, 1, "김포공항 노드는 환승 캡슐 1개여야 한다");
  assert.equal(gimpo[0].id, "transfer-station-symbol-김포공항");
  // 캡슐 실좌표(오염 값 (870,1033)·(763,864)가 아니다).
  assert.ok(Math.abs(gimpo[0].x - 763.3) < 1, `x=${gimpo[0].x}`);
  assert.ok(Math.abs(gimpo[0].y - 1055.0) < 1, `y=${gimpo[0].y}`);
  assert.equal(
    geometry.stationNodes.some((n) => n.id === "transfer-station-symbol-김포공항-0"),
    false,
    "공항 픽토그램 장식 노드는 geometry에 남으면 안 된다",
  );
});

// #2068 I4: 동명 별개역 목록은 손으로 유지하는 값이라, 카탈로그가 새 동명 역을
// 들이면 갱신을 놓치기 쉽다(놓치면 두 역이 한 좌표로 broadcast된다). 팩 실측
// 집합과 deepEqual로 묶어 누락을 자동으로 잡는다.
test("SEOUL.distinctSameNameStations는 수도권 카탈로그의 동명 역명 집합과 일치한다", () => {
  const tmp = mkdtempSync(path.join(tmpdir(), "sma-distinct-"));
  try {
    const packPath = path.join(tmp, "capital.sqlite");
    writeFileSync(
      packPath,
      gunzipSync(
        readFileSync(
          path.join(
            import.meta.dirname,
            "../../apps/mobile/assets/datapacks/capital.sqlite.gz",
          ),
        ),
      ),
    );
    const db = new DatabaseSync(packPath);
    const catalogDuplicates = db
      .prepare(
        `SELECT s.name_ko AS nameKo
         FROM stations s
         JOIN station_lines sl ON sl.station_id = s.id
         JOIN lines l ON l.id = sl.line_id
         WHERE l.name_ko LIKE ?
         GROUP BY s.name_ko
         HAVING COUNT(DISTINCT s.id) > 1
         ORDER BY s.name_ko`,
      )
      .all(`${getRegionConfig("seoul").lineNamePrefix} %`)
      .map((row) => row.nameKo);
    db.close();
    assert.deepEqual(
      [...getRegionConfig("seoul").distinctSameNameStations].sort(),
      catalogDuplicates.sort(),
      "동명 별개역 목록이 카탈로그 실측과 어긋납니다 — 목록을 갱신하세요(누락 시 좌표 broadcast 사고).",
    );
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});
