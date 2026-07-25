import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { canonicalStationName, resolveStationIds } from "./apply-sma-svg-positions.mjs";
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
