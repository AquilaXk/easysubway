// 바탕층 paint-order 계약 게이트(#2068 오너 실기기 회귀 핫픽스, 2026-07-26).
//
// [막는 회귀] 오너 SVG의 역명 라벨은 `paint-order:stroke fill` + 흰 halo를 쓴다.
// vector_graphics_compiler 1.2.6은 paint-order를 **읽지 않고**(파서의 presentation
// attribute 목록·style 파서 어디에도 없다) 런타임 vector_graphics 1.2.2는 fill →
// stroke 순서로 그린다. 그대로 컴파일하면 흰 stroke가 글자 fill을 덮어 속이 빈
// 유령 글자가 된다 — 오너 실기기에서 대구 역명은 사실상 소멸했고 부산 일반역명은
// 파편화됐다. compile-basemap-vec.mjs의 decomposePaintOrder가 컴파일 입력에서
// 해당 요소를 `stroke 전용 사본 → fill 전용 사본` 두 형제로 분해해 halo를 글자
// 뒤에 깐다(오너 SVG 원본은 불변).
//
// [고정하는 것]
//   1) 값 해석이 SVG 사양과 일치하고 사양 밖 값은 fail-closed로 던진다.
//   2) 정규화된 컴파일 입력에 "stroke가 fill보다 먼저인데 분해되지 않은 요소"가
//      한 건도 남지 않는다(전 권역 전수).
//   3) 분해된 쌍이 stroke 전용 → fill 전용 순서이고, paint 선언을 뺀 나머지
//      (좌표·transform·text-anchor·tspan·letter-spacing·font)가 완전히 동일하다.
//   4) 권역별 분해 대상 구성 기준선 — 오너 SVG가 바뀌어 대상이 늘거나 줄면 red.
//      halo가 없는 3권역(수도권 라벨·대전·광주)은 분해가 **텍스트에 대해 no-op**
//      임을 함께 고정한다(라벨 산출물 불변).
//
// 픽셀 축(글자 코어 잉크가 실제로 살아있는지)은 컴파일된 .vec을 앱과 동일한
// 런타임으로 렌더해 확인한다:
// apps/mobile/test/features/network_map/presentation/route_map_basemap_label_paint_order_test.dart

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";

import {
  decomposePaintOrder,
  normalizeSvgForCompile,
  resolvePaintOrderSequence,
} from "./compile-basemap-vec.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const sourcesDir = path.join(
  root,
  "tools/route-map/route-map-defs/svg-sources",
);

const REGIONS = [
  { id: "seoul", svg: "easy-subway-sma-v4.svg" },
  { id: "busan", svg: "easy-subway-busan-v3.svg" },
  { id: "daegu", svg: "easy-subway-daegu-v3.svg" },
  { id: "daejeon", svg: "easy-subway-daejeon-v3.svg" },
  { id: "gwangju", svg: "easy-subway-gwangju-v3.svg" },
];

const STROKE_COPY_ID_SUFFIX = "-paint-order-stroke";

const normalizedByRegion = new Map(
  REGIONS.map((region) => [
    region.id,
    normalizeSvgForCompile(
      readFileSync(path.join(sourcesDir, region.svg), "utf8"),
    ),
  ]),
);

/** 여는 태그에 직접 선언된 property(style 선언이 presentation attribute를 이긴다). */
function declaredProperty(openTag, property) {
  const style = openTag.match(/\sstyle="([^"]*)"/)?.[1];
  if (style) {
    const declared = style.match(
      new RegExp(`(?:^|;)\\s*${property}\\s*:\\s*([^;]+)`),
    )?.[1];
    if (declared != null) return declared.trim();
  }
  return openTag.match(new RegExp(`\\s${property}="([^"]*)"`))?.[1]?.trim();
}

function isVisiblePaint(value) {
  const normalized = String(value ?? "").toLowerCase();
  return normalized !== "" && normalized !== "none" && normalized !== "transparent";
}

test("paint-order 값 해석이 SVG 사양과 일치한다", () => {
  assert.deepEqual(resolvePaintOrderSequence("normal"), [
    "fill",
    "stroke",
    "markers",
  ]);
  assert.deepEqual(resolvePaintOrderSequence(""), ["fill", "stroke", "markers"]);
  // 일부만 명시하면 나머지는 기본 순서로 뒤에 붙는다.
  assert.deepEqual(resolvePaintOrderSequence("stroke"), [
    "stroke",
    "fill",
    "markers",
  ]);
  assert.deepEqual(resolvePaintOrderSequence("stroke fill"), [
    "stroke",
    "fill",
    "markers",
  ]);
  assert.deepEqual(resolvePaintOrderSequence("stroke markers fill"), [
    "stroke",
    "markers",
    "fill",
  ]);
  assert.deepEqual(resolvePaintOrderSequence("markers"), [
    "markers",
    "fill",
    "stroke",
  ]);
  // 사양 밖 값·중복 토큰은 조용히 무시하지 않고 던진다.
  assert.throws(() => resolvePaintOrderSequence("stroke fill stroke"), /지원하지 않는/);
  assert.throws(() => resolvePaintOrderSequence("outline"), /지원하지 않는/);
});

test("stroke 우선 요소를 stroke 사본 → fill 사본으로 분해한다", () => {
  const input =
    '<svg><g><text id="a" x="10" y="20" text-anchor="middle" ' +
    'paint-order="stroke fill" fill="#111111" stroke="#FFFFFF" ' +
    'stroke-width="4" letter-spacing="-1px">' +
    '<tspan id="a-1" x="10" dy="0">역명</tspan></text></g></svg>';
  const output = decomposePaintOrder(input);
  const texts = [...output.matchAll(/<text\b[^>]*>[\s\S]*?<\/text>/g)].map(
    (match) => match[0],
  );
  assert.equal(texts.length, 2, "두 사본으로 분해돼야 합니다.");

  const [strokeCopy, fillCopy] = texts;
  const strokeOpen = strokeCopy.match(/^<text\b[^>]*>/)[0];
  const fillOpen = fillCopy.match(/^<text\b[^>]*>/)[0];
  // 순서: halo(stroke)가 먼저, 글자(fill)가 나중.
  assert.equal(declaredProperty(strokeOpen, "fill"), "none");
  assert.equal(declaredProperty(strokeOpen, "stroke"), "#FFFFFF");
  assert.equal(declaredProperty(fillOpen, "fill"), "#111111");
  assert.equal(declaredProperty(fillOpen, "stroke"), "none");
  // 원본 id는 글자 사본이 유지하고 halo 사본만 접미사를 붙인다.
  assert.match(strokeOpen, /id="a-paint-order-stroke"/);
  assert.match(fillOpen, /id="a"/);
  // paint-order 선언은 구조로 바뀌었으므로 남지 않는다(id 접미사는 별개).
  assert.ok(!/\spaint-order="/.test(output));
  // paint 선언과 id를 제외하면 두 사본은 완전히 동일하다.
  const canonical = (markup) =>
    markup
      .replaceAll(STROKE_COPY_ID_SUFFIX, "")
      .replace(/\s(?:fill|stroke)="[^"]*"/g, "");
  assert.equal(canonical(strokeCopy), canonical(fillCopy));
});

test("fill·stroke 중 한쪽만 보이면 분해하지 않는다(불필요한 draw 금지)", () => {
  const strokeless =
    '<svg><text paint-order="stroke" fill="#FFFFFF">배지</text></svg>';
  assert.equal(decomposePaintOrder(strokeless), strokeless);

  const fillless =
    '<svg><text paint-order="stroke fill" fill="none" stroke="#FFF">x</text></svg>';
  assert.equal(decomposePaintOrder(fillless), fillless);

  // 기본 순서(fill 먼저)는 런타임 순서와 이미 같다 — 건드리지 않는다.
  const defaultOrder =
    '<svg><text paint-order="fill stroke" fill="#111" stroke="#FFF">x</text></svg>';
  assert.equal(decomposePaintOrder(defaultOrder), defaultOrder);
});

test("상속된 fill·stroke도 유효 값으로 반영한다", () => {
  // 자신에겐 stroke 선언이 없지만 조상이 준다 → 분해 대상.
  const inherited =
    '<svg><g stroke="#FFFFFF" stroke-width="4">' +
    '<text paint-order="stroke fill" fill="#111111">역</text></g></svg>';
  const output = decomposePaintOrder(inherited);
  assert.equal(
    [...output.matchAll(/<text\b/g)].length,
    2,
    "조상이 준 stroke도 halo로 보고 분해해야 합니다.",
  );
});

test("전 권역 컴파일 입력에 미분해 stroke-우선 요소가 남지 않는다", () => {
  const leftovers = [];
  for (const region of REGIONS) {
    const normalized = normalizedByRegion.get(region.id);
    for (const match of normalized.matchAll(
      /<[A-Za-z][\w:.-]*\b[^>]*>/g,
    )) {
      const openTag = match[0];
      const declared = declaredProperty(openTag, "paint-order");
      if (declared == null) continue;
      const sequence = resolvePaintOrderSequence(declared);
      if (sequence.indexOf("stroke") > sequence.indexOf("fill")) continue;
      // 상속까지 보진 않지만, 자기 선언만으로 둘 다 보이면 확실한 누락이다.
      if (
        isVisiblePaint(declaredProperty(openTag, "fill")) &&
        isVisiblePaint(declaredProperty(openTag, "stroke"))
      ) {
        leftovers.push(`${region.id}: ${openTag.slice(0, 160)}`);
      }
    }
  }
  assert.deepEqual(
    leftovers,
    [],
    "paint-order가 stroke를 먼저 그리라고 지정했는데 분해되지 않은 요소가 " +
      "컴파일 입력에 남아 있습니다 — 흰 halo가 글자를 덮습니다:\n" +
      leftovers.join("\n"),
  );
});

test("분해 쌍은 stroke 사본이 먼저이고 paint 외 모든 속성이 동일하다", () => {
  const mismatches = [];
  for (const region of REGIONS) {
    const normalized = normalizedByRegion.get(region.id);
    for (const match of normalized.matchAll(
      new RegExp(
        `<([A-Za-z][\\w:.-]*)\\b[^>]*\\sid="([^"]*)${STROKE_COPY_ID_SUFFIX}"`,
        "g",
      ),
    )) {
      const [, tagName, baseId] = match;
      // tspan 사본은 부모 사본 안에 딸린 하위 노드라 형제 대조 대상이 아니다
      // (부모 text 사본 대조가 서브트리 전체 동일성을 이미 덮는다).
      if (tagName === "tspan") continue;
      // 같은 태그의 형제 fill 사본이 뒤에 있어야 한다.
      const fillIndex = normalized.indexOf(`<${tagName}`, match.index + 1);
      const fillOpen = normalized
        .slice(fillIndex)
        .match(new RegExp(`^<${tagName}\\b[^>]*>`))?.[0];
      if (fillOpen == null || !fillOpen.includes(`id="${baseId}"`)) {
        mismatches.push(
          `${region.id}: ${baseId} — stroke 사본 뒤에 대응하는 fill 사본이 없습니다.`,
        );
        continue;
      }
      const strokeOpen = normalized
        .slice(match.index)
        .match(new RegExp(`^<${tagName}\\b[^>]*>`))[0];
      if (declaredProperty(strokeOpen, "fill") !== "none") {
        mismatches.push(`${region.id}: ${baseId} — stroke 사본에 fill:none이 없습니다.`);
      }
      if (declaredProperty(fillOpen, "stroke") !== "none") {
        mismatches.push(`${region.id}: ${baseId} — fill 사본에 stroke:none이 없습니다.`);
      }
      const canonical = (tag) =>
        tag
          .replaceAll(STROKE_COPY_ID_SUFFIX, "")
          .replace(/\s(?:fill|stroke)="[^"]*"/g, "");
      if (canonical(strokeOpen) !== canonical(fillOpen)) {
        mismatches.push(
          `${region.id}: ${baseId} — 두 사본의 좌표·앵커·폰트 속성이 다릅니다.\n` +
            `  stroke: ${canonical(strokeOpen)}\n  fill:   ${canonical(fillOpen)}`,
        );
      }
    }
  }
  assert.deepEqual(mismatches, [], mismatches.join("\n"));
});

// 실측 기준선(2026-07-26). 오너 SVG의 halo 구성이 바뀌면 red가 되어 사람이
// 이 계약을 다시 보게 한다.
test("권역별 paint-order 분해 대상 구성 기준선", () => {
  const expected = {
    // 수도권: 역명 라벨 halo는 `#…-layer text` **id 선택자** CSS라 인라인 대상이
    // 아니고 컴파일러도 <style>을 읽지 않아 애초에 stroke가 없다 — 라벨은
    // 분해 대상이 0건이고, 공항 아이콘 path 6건만 분해된다(라벨 산출물 불변).
    seoul: { path: 6 },
    busan: { text: 147, path: 2 },
    daegu: { text: 97 },
    // 대전·광주도 같은 id 선택자 CSS라 컴파일 입력에 stroke 텍스트가 없다.
    daejeon: {},
    gwangju: {},
  };
  for (const region of REGIONS) {
    const normalized = normalizedByRegion.get(region.id);
    const counts = {};
    for (const match of normalized.matchAll(
      new RegExp(
        `<([A-Za-z][\\w:.-]*)\\b[^>]*\\sid="[^"]*${STROKE_COPY_ID_SUFFIX}"`,
        "g",
      ),
    )) {
      // tspan은 부모 사본에 딸린 하위 노드라 대상 수에 세지 않는다.
      if (match[1] === "tspan") continue;
      counts[match[1]] = (counts[match[1]] ?? 0) + 1;
    }
    assert.deepEqual(counts, expected[region.id], `${region.id} 분해 대상 구성`);
  }
});

test("halo 없는 3권역은 텍스트 분해가 no-op이다(라벨 산출물 불변)", () => {
  for (const regionId of ["seoul", "daejeon", "gwangju"]) {
    const normalized = normalizedByRegion.get(regionId);
    const textCopies = [
      ...normalized.matchAll(
        new RegExp(`<text\\b[^>]*\\sid="[^"]*${STROKE_COPY_ID_SUFFIX}"`, "g"),
      ),
    ];
    assert.equal(
      textCopies.length,
      0,
      `${regionId}: 역명 라벨이 분해됐습니다 — 이 권역은 halo가 없어 산출물이 ` +
        "바뀌면 안 됩니다.",
    );
  }
});
