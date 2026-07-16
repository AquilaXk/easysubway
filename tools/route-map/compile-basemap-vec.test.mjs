import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import {
  extractOwnerLabels,
  markLineTerminalBadgeEntries,
  normalizeSvgForCompile,
} from "./compile-basemap-vec.mjs";

test("컴파일 전에 단순 class 스타일을 SVG 속성으로 인라인한다", () => {
  const normalized = normalizeSvgForCompile(`
    <svg>
      <style>
        .route-line { fill:none; stroke-width:8px; }
        .station-name { fill:#14293D; font-size:12.5px; font-weight:700; }
        .station-name.is-long { font-size:11.6px; }
      </style>
      <g id="header-title"><text>통합 노선도</text></g>
      <g id="map-card-clipped-content-layer">
        <g id="main-map-scaled-layer" transform="translate(70 138) scale(0.455)">
        <g id="route-lines-layer">
          <polyline class="route-line" points="0,0 10,10" />
          <g data-state="construction">
            <path class="route-line" d="M 0 0 L 20 20" />
          </g>
          <polyline class="route-line" data-line="line2-phase1" points="0,0 30,30" />
        </g>
        <text class="station-name is-long">테스트역</text>
        </g>
      </g>
    </svg>
  `);

  assert.doesNotMatch(normalized, /통합 노선도/);
  assert.match(normalized, /route-lines-layer/);
  assert.match(normalized, /transform="translate\(70 138\) scale\(0\.455\)"/);
  assert.doesNotMatch(normalized, /construction|line2-phase1|20 20|30,30/);
  assert.match(normalized, /<polyline[^>]*fill="none"[^>]*stroke-width="8px"/);
  assert.match(
    normalized,
    /<polyline[^>]*stroke-linecap="round"[^>]*stroke-linejoin="round"/,
  );
  assert.doesNotMatch(normalized, /테스트역|<text\b/);
  assert.doesNotMatch(normalized, /\/\s+[\w-]+="/);
});

test("5권역 basemap에는 노선·기존 역 심벌만 남기고 미개통 노선을 제외한다", () => {
  const sources = path.join(import.meta.dirname, "route-map-defs/svg-sources");
  const files = [
    "easy-subway-sma-v2.svg",
    "easy-subway-busan-v1.svg",
    "easy-subway-daegu-v1.svg",
    "easy-subway-daejeon-v1.svg",
    "easy-subway-gwangju-v1.svg",
  ];

  for (const file of files) {
    const normalized = normalizeSvgForCompile(
      readFileSync(path.join(sources, file), "utf8"),
    );
    const rendered = normalized.includes("</defs>")
      ? normalized.slice(normalized.lastIndexOf("</defs>") + 7)
      : normalized;
    assert.match(normalized, /id="route-lines-layer"/);
    assert.match(normalized, /id="station-symbols-layer"/);
    if (!/gwangju|daejeon/.test(file)) {
      assert.match(normalized, /id="transfer-station-symbols-layer"/);
    }
    assert.doesNotMatch(rendered, /station-name-labels-layer|header-|legend/);
    assert.doesNotMatch(rendered, /<title\b/);
  }

  const daejeon = normalizeSvgForCompile(
    readFileSync(path.join(sources, "easy-subway-daejeon-v1.svg"), "utf8"),
  );
  assert.doesNotMatch(daejeon, /data-state="construction"/);
  assert.equal(
    (daejeon.match(/data-role="current-line-station"/g) ?? []).length,
    5,
  );

  const gwangju = normalizeSvgForCompile(
    readFileSync(path.join(sources, "easy-subway-gwangju-v1.svg"), "utf8"),
  );
  assert.doesNotMatch(gwangju, /data-line="line2-phase/);
  assert.equal(
    (gwangju.match(/data-role="current-line-station"/g) ?? []).length,
    2,
  );
  const gwangjuStations = gwangju.match(
    /id="station-symbols-layer"[\s\S]*?<\/g>/,
  )?.[0];
  assert.ok(gwangjuStations);
  for (const circle of gwangjuStations.match(/<circle\b[^>]*\/>/g) ?? []) {
    assert.match(circle, /stroke="#009088"/);
  }
});

test("scale 레이어 안 텍스트는 font-size를 k배하고 baseline central은 y를 보정한다", () => {
  const normalized = normalizeSvgForCompile(`
    <svg>
      <g id="main-map-scaled-layer" transform="translate(70 138) scale(0.455)">
        <g id="route-lines-layer"><polyline points="0,0 10,10" /></g>
        <g id="transfer-station-symbols-layer">
          <text x="100" y="200" font-size="10.3"
                dominant-baseline="central" alignment-baseline="middle">1</text>
        </g>
      </g>
    </svg>
  `);
  const text = normalized.match(/<text\b[^>]*>/)[0];
  // 10.3 × 0.455 = 4.6865
  assert.match(text, /font-size="4\.6865"/);
  // 200 + 0.35 × 10.3 = 203.605 (로컬 단위)
  assert.match(text, /\sy="203\.605"/);
  assert.doesNotMatch(text, /dominant-baseline|alignment-baseline/);
});

test("scale 없는 권역은 font-size를 유지하고 baseline y만 보정한다", () => {
  const normalized = normalizeSvgForCompile(`
    <svg>
      <g id="route-lines-layer"><polyline points="0,0 10,10" /></g>
      <g id="transfer-station-symbols-layer">
        <text x="100" y="200" font-size="10.3" dominant-baseline="central">1</text>
      </g>
    </svg>
  `);
  const text = normalized.match(/<text\b[^>]*>/)[0];
  assert.match(text, /font-size="10\.3"/); // k=1 → 불변
  assert.match(text, /\sy="203\.605"/);
  assert.doesNotMatch(text, /dominant-baseline/);
});

test("font-size의 px 접미사를 제거하고 k배 순수 숫자로 직렬화한다", () => {
  const normalized = normalizeSvgForCompile(`
    <svg>
      <g id="main-map-scaled-layer" transform="translate(0 0) scale(0.5)">
        <g id="route-lines-layer"><polyline points="0,0 10,10" /></g>
        <g id="transfer-station-symbols-layer">
          <text x="100" y="200" font-size="10.3px" dominant-baseline="central">1</text>
        </g>
      </g>
    </svg>
  `);
  const text = normalized.match(/<text\b[^>]*>/)[0];
  // 10.3 × 0.5 = 5.15, px 접미사 제거
  assert.match(text, /font-size="5\.15"/);
  assert.doesNotMatch(text, /font-size="[^"]*px"/);
});

test("class에서 인라인된 baseline 속성도 제거한다(인라인 이후 적용)", () => {
  const normalized = normalizeSvgForCompile(`
    <svg>
      <style>
        .badge-label { dominant-baseline: central; alignment-baseline: middle; }
      </style>
      <g id="main-map-scaled-layer" transform="translate(0 0) scale(0.5)">
        <g id="route-lines-layer"><polyline points="0,0 10,10" /></g>
        <g id="transfer-station-symbols-layer">
          <text class="badge-label" x="100" y="200" font-size="10">1</text>
        </g>
      </g>
    </svg>
  `);
  const text = normalized.match(/<text\b[^>]*>/)[0];
  assert.doesNotMatch(text, /dominant-baseline|alignment-baseline/);
  assert.match(text, /font-size="5"/); // 10 × 0.5
  assert.match(text, /\sy="203\.5"/); // 200 + 0.35 × 10
});

test("style형 font-size(px 있음)는 text·tspan 모두 ×k 되고 baseline 보정은 없다", () => {
  const normalized = normalizeSvgForCompile(`
    <svg>
      <g id="main-map-scaled-layer" transform="translate(0 0) scale(0.5)">
        <g id="route-lines-layer"><polyline points="0,0 10,10" /></g>
        <g id="transfer-station-symbols-layer">
          <text xml:space="preserve" style="font-weight:bold;font-size:9.37729px;line-height:0.9" x="100" y="200" id="text1"><tspan
            style="font-size:8.79121px;stroke-width:2.1978" x="100" y="200">GTX</tspan><tspan
            style="font-size:8.79121px;stroke-width:2.1978" x="100" y="208" id="tspan2">A</tspan></text>
        </g>
      </g>
    </svg>
  `);
  const outerText = normalized.match(/<text\b[^>]*id="text1"[^>]*>/)[0];
  const tspans = [...normalized.matchAll(/<tspan\b[^>]*>/g)].map((m) => m[0]);
  // 9.37729 × 0.5 = 4.688645 → roundCoord(4자리) = 4.6886
  assert.match(outerText, /font-size:4\.6886px/);
  assert.doesNotMatch(outerText, /dominant-baseline|alignment-baseline/);
  // y는 baseline 보정 대상이 아니라 불변.
  assert.match(outerText, /\sy="200"/);
  // 8.79121 × 0.5 = 4.395605 → roundCoord(4자리) = 4.3956
  assert.equal(tspans.length, 2);
  for (const tspan of tspans) {
    assert.match(tspan, /font-size:4\.3956px/);
  }
  assert.match(normalized, />GTX</);
  assert.match(normalized, />A</);
});

test("style형 font-size(px 없음)도 동일하게 ×k 스케일한다", () => {
  const normalized = normalizeSvgForCompile(`
    <svg>
      <g id="main-map-scaled-layer" transform="translate(0 0) scale(0.5)">
        <g id="route-lines-layer"><polyline points="0,0 10,10" /></g>
        <g id="transfer-station-symbols-layer">
          <text style="font-size:10" x="100" y="200">A</text>
        </g>
      </g>
    </svg>
  `);
  const text = normalized.match(/<text\b[^>]*>/)[0];
  assert.match(text, /font-size:5(?!\d)/); // 10 × 0.5, px 접미사 없음 유지
  assert.doesNotMatch(text, /font-size:5px/);
});

test("extractOwnerLabels: x/y 속성형 위치를 main-map-scaled-layer 변환(×scale+translate)해 뽑는다", () => {
  const entries = extractOwnerLabels(`
    <svg>
      <g id="main-map-scaled-layer" transform="translate(70 138) scale(0.455)">
        <text data-station="시청" data-label-role="transfer"
              font-size="28.571px" x="2196.2356" y="1493.1528"
              ><tspan x="2196.2356" y="1493.1528">시청</tspan></text>
      </g>
    </svg>
  `);
  assert.equal(entries.length, 1);
  const [entry] = entries;
  assert.equal(entry.station, "시청");
  assert.equal(entry.role, "transfer");
  assert.equal(entry.anchor, "start"); // 미지정 → 기본값.
  // x = 70 + 2196.2356*0.455, y = 138 + 1493.1528*0.455.
  assert.equal(entry.x, Number((70 + 2196.2356 * 0.455).toFixed(4)));
  assert.equal(entry.y, Number((138 + 1493.1528 * 0.455).toFixed(4)));
  assert.equal(entry.fontSizePx, Number((28.571 * 0.455).toFixed(4)));
});

test("extractOwnerLabels: transform=translate + tspan x=0/y=0 위치형(뚝섬형)도 뽑는다", () => {
  const entries = extractOwnerLabels(`
    <svg>
      <g id="main-map-scaled-layer" transform="translate(70 138) scale(0.455)">
        <text data-station="뚝섬" data-label-role="ordinary"
              transform="translate(3100.2 1650.8)" font-size="26.374"
              ><tspan x="0" y="0">뚝섬</tspan></text>
      </g>
    </svg>
  `);
  assert.equal(entries.length, 1);
  const [entry] = entries;
  assert.equal(entry.station, "뚝섬");
  assert.equal(entry.x, Number((70 + 3100.2 * 0.455).toFixed(4)));
  assert.equal(entry.y, Number((138 + 1650.8 * 0.455).toFixed(4)));
});

test("extractOwnerLabels: scale 없는 권역(main-map-scaled-layer 부재)은 좌표를 그대로 쓴다", () => {
  const entries = extractOwnerLabels(`
    <svg>
      <text data-station="가야" data-label-role="ordinary" text-anchor="middle"
            font-size="12.5" x="1958" y="1430"><tspan x="1958" y="1430" dy="0">가야</tspan></text>
    </svg>
  `);
  assert.equal(entries.length, 1);
  assert.equal(entries[0].x, 1958);
  assert.equal(entries[0].y, 1430);
  assert.equal(entries[0].anchor, "middle");
  assert.equal(entries[0].fontSizePx, 12.5);
});

test("extractOwnerLabels: <g data-label-role>에 감싸인 gwangju형은 g의 transform도 더하고 CSS class font-size로 폴백한다", () => {
  const entries = extractOwnerLabels(`
    <svg>
      <style>
        .station-label-terminal { fill:#111111; font-size:15px; font-weight:700; }
      </style>
      <g id="station-label-group-119" data-station="119" data-station-name="평동"
         data-label-role="terminal" transform="translate(3.0637434,55.147382)">
        <text x="110" y="918" class="station-label station-label-terminal"
              text-anchor="middle">평동</text>
      </g>
    </svg>
  `);
  assert.equal(entries.length, 1);
  const [entry] = entries;
  assert.equal(entry.station, "평동"); // data-station(코드 "119")이 아니라 텍스트 내용.
  assert.equal(entry.role, "terminal");
  assert.equal(entry.x, Number((110 + 3.0637434).toFixed(4)));
  assert.equal(entry.y, Number((918 + 55.147382).toFixed(4)));
  assert.equal(entry.fontSizePx, 15); // 인라인 font-size 없음 → CSS class 폴백.
});

test("extractOwnerLabels: code role과 construction/planned 상태는 제외한다", () => {
  const entries = extractOwnerLabels(`
    <svg>
      <text data-label-role="code" font-size="10" x="0" y="0">312</text>
      <text data-label-role="ordinary" data-status="construction" font-size="13"
            x="10" y="10">가수원네거리</text>
      <text data-label-role="planned" font-size="13" x="20" y="20">용두광역철도</text>
      <text data-label-role="regional" data-status="construction" font-size="13"
            x="30" y="30">흑석리</text>
      <g data-label-role="ordinary" data-state="planned">
        <text x="40" y="40">미개통역</text>
      </g>
      <text data-label-role="ordinary" font-size="13" x="50" y="50">정상역</text>
    </svg>
  `);
  assert.equal(entries.length, 1);
  assert.equal(entries[0].station, "정상역");
});

test("extractOwnerLabels: daejeon 환승 복합 표기는 data-full-official-name의 canonical 1호선 역명을 station 키로 쓴다(#2068 실기기 확정 — 텍스트 flatten 대신)", () => {
  const entries = extractOwnerLabels(`
    <svg>
      <text data-label-role="transfer" font-size="14.2" x="0" y="0"
            data-full-official-name="1호선 대동 | 2호선 208 대동(하늘공원)"
            ><tspan x="0" dy="0">대동</tspan><tspan x="0" dy="10.8">하늘공원</tspan></text>
      <text data-label-role="transfer" font-size="14.2" x="0" y="0"
            data-full-official-name="1호선 대전역 | 2호선 206 대전역(중앙시장)"
            >대전역</text>
      <text data-label-role="ordinary" font-size="13.2" x="0" y="0"
            data-full-official-name="구암">구암</text>
    </svg>
  `);
  const byStation = Object.fromEntries(entries.map((e) => [e.station, e]));
  assert.ok(byStation["대동"], "복합 표기 flatten(대동하늘공원) 대신 canonical 키(대동)여야 한다");
  assert.ok(!byStation["대동하늘공원"]);
  assert.ok(byStation["대전"], "역 접미 정규화(대전역→대전)까지 적용돼야 한다");
  assert.ok(!byStation["대전역"]);
  assert.ok(byStation["구암"], "data-full-official-name이 단순 역명이면 그대로 유지");
});

test("extractOwnerLabels: 5권역 실 SVG에서 ordinary/transfer/terminal 개수가 실측과 일치한다", () => {
  const sources = path.join(import.meta.dirname, "route-map-defs/svg-sources");
  const expected = {
    "easy-subway-sma-v2.svg": { ordinary: 501, transfer: 124, terminal: 30 },
    "easy-subway-busan-v1.svg": { ordinary: 127, transfer: 12, terminal: 7 },
    "easy-subway-daegu-v1.svg": { ordinary: 84, transfer: 5, terminal: 8 },
    // daejeon: SVG상 ordinary/transfer/terminal 64건 중 39건이 미개통(2호선
    // 트램) data-status="construction"이라 제외 → 25건(15/8/2)만 남는다.
    "easy-subway-daejeon-v1.svg": { ordinary: 15, transfer: 8, terminal: 2 },
    "easy-subway-gwangju-v1.svg": { ordinary: 53, transfer: 7, terminal: 2 },
  };
  for (const [file, counts] of Object.entries(expected)) {
    const entries = extractOwnerLabels(
      readFileSync(path.join(sources, file), "utf8"),
    );
    const byRole = { ordinary: 0, transfer: 0, terminal: 0 };
    for (const entry of entries) byRole[entry.role] += 1;
    assert.deepEqual(byRole, counts, file);
    for (const entry of entries) {
      assert.ok(entry.station.length > 0, `${file}: 빈 station 키`);
      assert.ok(Number.isFinite(entry.x) && Number.isFinite(entry.y), file);
      assert.ok(entry.fontSizePx > 0, file);
      assert.ok(["start", "middle", "end"].includes(entry.anchor), file);
    }
  }
});

test("build manifest가 source·normalized·vec hash와 viewBox를 결합한다", () => {
  const root = path.resolve(import.meta.dirname, "../..");
  const manifest = JSON.parse(
    readFileSync(
      path.join(import.meta.dirname, "basemap-build-manifest.json"),
      "utf8",
    ),
  );
  assert.equal(manifest.compiler.version, "1.2.6");
  assert.deepEqual(manifest.content, {
    svgLayer: "route-lines-and-station-symbols",
    stationSymbols: "owner-svg",
    labels: "owner-svg-anchor-with-solver-fallback",
    interaction: "route_map_positions",
  });
  assert.equal(manifest.maps.length, 5);

  for (const map of manifest.maps) {
    const source = readFileSync(path.join(root, map.source));
    const normalized = normalizeSvgForCompile(source.toString("utf8"));
    const vec = readFileSync(path.join(root, map.compiledVector));
    const hash = (value) => createHash("sha256").update(value).digest("hex");
    assert.equal(map.sourceSvgSha256, hash(source));
    assert.equal(map.normalizedSvgSha256, hash(normalized));
    assert.equal(map.compiledVectorSha256, hash(vec));
    assert.equal(map.viewBox.length, 4);
    const ownerLabels = extractOwnerLabels(source.toString("utf8"));
    assert.equal(map.ownerLabelCount, ownerLabels.length);
  }

  const sidecarPath = path.join(root, manifest.ownerLabelsSidecar.path);
  const sidecar = readFileSync(sidecarPath, "utf8");
  const hash = (value) => createHash("sha256").update(value).digest("hex");
  assert.equal(manifest.ownerLabelsSidecar.sha256, hash(sidecar));
  const parsedSidecar = JSON.parse(sidecar);
  assert.equal(parsedSidecar.artifactKind, "route-map-basemap-owner-labels");
  assert.deepEqual(
    Object.keys(parsedSidecar.regions).sort(),
    ["busan", "daegu", "daejeon", "gwangju", "seoul"],
  );
  for (const map of manifest.maps) {
    assert.equal(
      parsedSidecar.regions[map.id].length,
      map.ownerLabelCount,
      map.id,
    );
  }
});

test("markLineTerminalBadgeEntries: line-terminal-badge가 없으면 원본을 그대로 반환한다", () => {
  const entries = [
    { station: "평동", role: "terminal", x: 0, y: 0, anchor: "start", fontSizePx: 10 },
  ];
  const result = markLineTerminalBadgeEntries(entries, "<svg></svg>");
  assert.equal(result, entries); // .map 없이 원본 참조 그대로.
});

test("markLineTerminalBadgeEntries: 있으면 terminal role 엔트리에만 표시하고 나머지는 불변", () => {
  const entries = [
    { station: "평동", role: "terminal", x: 0, y: 0, anchor: "start", fontSizePx: 10 },
    { station: "녹동", role: "terminal", x: 1, y: 1, anchor: "start", fontSizePx: 10 },
    { station: "도산", role: "ordinary", x: 2, y: 2, anchor: "start", fontSizePx: 10 },
  ];
  const svgText = '<g data-role="line-terminal-badge"><circle /></g>';
  const result = markLineTerminalBadgeEntries(entries, svgText);
  assert.equal(result[0].hasLineTerminalBadge, true);
  assert.equal(result[1].hasLineTerminalBadge, true);
  assert.equal(result[2].hasLineTerminalBadge, undefined);
  // 원본 배열/객체는 변경하지 않는다(순수 함수).
  assert.equal(entries[0].hasLineTerminalBadge, undefined);
});

test("labels.json sidecar: 광주·대전·부산은 terminal 엔트리에 hasLineTerminalBadge, 다른 권역은 플래그 없음", () => {
  const root = path.resolve(import.meta.dirname, "../..");
  const sidecarPath = path.join(
    root,
    "apps/mobile/assets/datapacks/metro_map_pack/basemap/labels.json",
  );
  const sidecar = JSON.parse(readFileSync(sidecarPath, "utf8"));
  // 부산(#2068): 6개 노선의 비환승 종점 7곳에 line-terminal-badge를 그려
  // 앱 배지 억제를 켠다. markLineTerminalBadgeEntries는 권역 단위 감지라 terminal
  // role 엔트리 전부에 플래그가 붙고, 부산 terminal 라벨 7건은 모두 그 종점이다.
  for (const regionId of ["gwangju", "daejeon", "busan"]) {
    const terminals = sidecar.regions[regionId].filter(
      (entry) => entry.role === "terminal",
    );
    assert.ok(terminals.length > 0, regionId);
    for (const entry of terminals) {
      assert.equal(entry.hasLineTerminalBadge, true, `${regionId}:${entry.station}`);
    }
  }
  for (const regionId of ["seoul", "daegu"]) {
    for (const entry of sidecar.regions[regionId]) {
      assert.equal(
        entry.hasLineTerminalBadge,
        undefined,
        `${regionId}:${entry.station}`,
      );
    }
  }
});
