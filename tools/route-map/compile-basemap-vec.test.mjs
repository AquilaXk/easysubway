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
        <g id="route-lines-layer">
          <polyline class="route-line" points="0,0 10,10" />
          <g data-state="construction">
            <path class="route-line" d="M 0 0 L 20 20" />
          </g>
          <polyline class="route-line" data-line="line2-phase1" points="0,0 30,30" />
        </g>
        <text class="station-name is-long">테스트역</text>
      </g>
    </svg>
  `);

  assert.doesNotMatch(normalized, /통합 노선도/);
  assert.match(normalized, /route-lines-layer/);
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

  const gwangju = normalizeSvgForCompile(
    readFileSync(path.join(sources, "easy-subway-gwangju-v1.svg"), "utf8"),
  );
  assert.doesNotMatch(gwangju, /data-line="line2-phase/);
  const gwangjuStations = gwangju.match(
    /id="station-symbols-layer"[\s\S]*?<\/g>/,
  )?.[0];
  assert.ok(gwangjuStations);
  for (const circle of gwangjuStations.match(/<circle\b[^>]*\/>/g) ?? []) {
    assert.match(circle, /stroke="#009088"/);
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
