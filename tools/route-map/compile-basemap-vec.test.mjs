import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import { normalizeSvgForCompile } from "./compile-basemap-vec.mjs";

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
    labels: "structured-data",
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
  }
});
