#!/usr/bin/env node
// 하이브리드 바탕층(#2068) 컴파일 파이프라인.
//
// 5권역 오너 자작 노선도 SVG에서 현재 운행 노선 형상과 기존 역 심벌만 추출해
// vector_graphics 바이너리(.vec) 오프라인 바탕 자산을 만든다. 역명·인터랙션은
// 구조화 데이터 렌더러가 담당한다. 산출 .vec는
// 원본 SVG의 viewBox 좌표계(예: sma-v2 `0 0 2400 1800`)를 그대로 유지하므로,
// 앱은 designScale 곱셈 없이 카메라 변환만으로 인터랙션 좌표와 1:1 정렬한다.
//
// [결정성 확보] 재실행 시 동일 바이트가 나오도록 다음을 고정한다:
//   1) 입력 불변: svg-sources/*.svg 원본 파일은 수정하지 않는다. 필요한 노선층만
//      추출·정규화한 임시 사본을 만들어 컴파일한다. 원본은 그대로다.
//   2) 컴파일러 버전 고정: pubspec dev_dependencies의 vector_graphics_compiler를
//      `dart run`으로 호출한다(패키지 버전은 pubspec.lock에 잠긴다).
//   3) 재현 검증: `--verify` 플래그로 각 SVG를 2회 컴파일해 두 산출물의 sha256이
//      동일한지 확인한다(비결정적 출력 조기 감지). 검증은 별도 임시 파일에 쓰고
//      비교 후 정리한다 — 커밋 산출물은 1회 컴파일 결과다.
//
// 원본 CSS의 비표준 font-weight도 컴파일러가 파싱할 수 있도록 표준 100 배수로
// 정규화한다. 환승 캡슐 내부 노선 표기는 유지하고 역명·제목·범례는 제외한다.
//
// 사용법(apps/mobile pubspec 컨텍스트가 필요하므로 컴파일은 apps/mobile cwd에서 실행):
//   node tools/route-map/compile-basemap-vec.mjs           # 5권역 컴파일 + sha256 출력
//   node tools/route-map/compile-basemap-vec.mjs --verify  # 2회 컴파일 sha256 동일 검증
//
// build-datapack.mjs의 결정적 빌드 관례(canonicalJson·sha256 산출)와 톤을 맞춘다.

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const root = path.resolve(import.meta.dirname, "../..");
const svgSourceDir = path.join(
  root,
  "tools/route-map/route-map-defs/svg-sources",
);
const mobileDir = path.join(root, "apps/mobile");
const outDir = path.join(
  mobileDir,
  "assets/datapacks/metro_map_pack/basemap",
);
const dartBin = process.env.DART_BIN ?? "dart";
const compilerVersion = "1.2.6";
const buildManifestPath = path.join(
  root,
  "tools/route-map/basemap-build-manifest.json",
);

// manifest maps[].id → 원본 SVG 파일명. .vec 파일명은 manifest id를 따른다.
const regions = [
  { id: "seoul", svg: "easy-subway-sma-v2.svg" },
  { id: "busan", svg: "easy-subway-busan-v1.svg" },
  { id: "daegu", svg: "easy-subway-daegu-v1.svg" },
  { id: "daejeon", svg: "easy-subway-daejeon-v1.svg" },
  { id: "gwangju", svg: "easy-subway-gwangju-v1.svg" },
];

function sha256(filePath) {
  return createHash("sha256").update(readFileSync(filePath)).digest("hex");
}

function sha256Value(value) {
  return createHash("sha256").update(value).digest("hex");
}

// 비표준 font-weight를 가장 가까운 표준 100 배수(100~900 clamp)로 정규화한다.
// 순수 함수 — 동일 입력에 동일 출력이라 컴파일 결정성을 해치지 않는다.
function normalizeFontWeightValue(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) {
    return raw;
  }
  const rounded = Math.round(n / 100) * 100;
  return String(Math.min(900, Math.max(100, rounded)));
}

// 노선 형상·역 심벌만 추출하고 컴파일러가 거부하는 SVG 속성을 정규화한다(원본 불변).
//   1) 비표준 font-weight: 속성형·CSS 선언형 모두 가장 가까운 100 배수로.
//   2) 다중값 x/y/dx/dy(예: <text dy="0 0 0 0">의 per-glyph 리스트): 컴파일러의
//      DoubleOrPercentage.fromString은 단일 double만 파싱하므로 첫 토큰만 남긴다.
//      (자작 SVG의 해당 값은 전부 0 리스트라 첫 토큰 축약이 시각적으로 무해하다.)
//      `\b`가 아니라 앞에 `[\s"']` 경계를 둬 viewBox 등 다른 속성명은 건드리지 않는다.
const supportedClassStyleProperties = new Set([
  "alignment-baseline",
  "display",
  "dominant-baseline",
  "fill",
  "fill-opacity",
  "font-family",
  "font-size",
  "font-style",
  "font-weight",
  "letter-spacing",
  "opacity",
  "paint-order",
  "stroke",
  "stroke-dasharray",
  "stroke-linecap",
  "stroke-linejoin",
  "stroke-miterlimit",
  "stroke-opacity",
  "stroke-width",
  "text-anchor",
]);

function extractGroup(svgText, groupId) {
  const id = `id="${groupId}"`;
  const idIndex = svgText.indexOf(id);
  if (idIndex < 0) return "";
  const groupStart = svgText.lastIndexOf("<g", idIndex);
  if (groupStart < 0) return "";

  const groupTags = /<\/?g\b[^>]*>/g;
  groupTags.lastIndex = groupStart;
  let depth = 0;
  let groupEnd = -1;
  for (let match = groupTags.exec(svgText); match; match = groupTags.exec(svgText)) {
    if (match[0].startsWith("</")) {
      depth -= 1;
      if (depth === 0) {
        groupEnd = groupTags.lastIndex;
        break;
      }
    } else if (!match[0].endsWith("/>")) {
      depth += 1;
    }
  }
  if (groupEnd < 0) {
    throw new Error(`${groupId}의 닫는 태그를 찾지 못했습니다.`);
  }
  return svgText.slice(groupStart, groupEnd);
}

function roundRouteStrokes(group) {
  return group.replace(/<(path|line|polyline)\b([^>]*)>/g, (_match, tag, raw) => {
    const selfClosing = /\/\s*$/.test(raw);
    const attributes = raw
      .replace(/\/\s*$/, "")
      .replace(/\s+stroke-linecap="[^"]*"/g, "")
      .replace(/\s+stroke-linejoin="[^"]*"/g, "");
    return `<${tag}${attributes} stroke-linecap="round" stroke-linejoin="round"${selfClosing ? " /" : ""}>`;
  });
}

function keepGwangjuLine1Stations(group) {
  return group.replace(/<circle\b[^>]*\/>/g, (circle) =>
    circle.includes('stroke="#009088"') ? circle : ""
  );
}

function currentLineStationsFromFutureTransfers(svgText, config) {
  let transferLayer = extractGroup(svgText, "transfer-station-symbols-layer");
  for (const match of transferLayer.matchAll(
    /<g\b(?=[^>]*\bid="([^"]+)")(?=[^>]*\bdata-state="planned")[^>]*>/g,
  )) {
    transferLayer = transferLayer.replace(extractGroup(transferLayer, match[1]), "");
  }
  const circles = [...transferLayer.matchAll(/<circle\b[^>]*>/g)]
    .map((match) => match[0])
    .filter((circle) =>
      new RegExp(`\\bfill="${config.color}"`, "i").test(circle),
    )
    .map((circle, index) => {
      const cx = circle.match(/\bcx="([^"]+)"/)?.[1];
      const cy = circle.match(/\bcy="([^"]+)"/)?.[1];
      if (cx == null || cy == null) {
        throw new Error("미개통 환승 노드의 현재 노선 좌표를 찾지 못했습니다.");
      }
      return `    <circle id="current-line-transfer-station-${index + 1}" data-role="current-line-station" cx="${cx}" cy="${cy}" r="${config.radius}" fill="#FFFFFF" stroke="${config.color}" stroke-width="${config.strokeWidth}" />`;
    });
  return [
    '  <g id="current-line-transfer-station-symbols-layer">',
    ...circles,
    "  </g>",
  ].join("\n");
}

function extractMapSvg(svgText) {
  const svgStart = svgText.match(/<svg\b[^>]*>/)?.[0];
  if (!svgStart) throw new Error("SVG 루트 태그를 찾지 못했습니다.");

  const defs = [...svgText.matchAll(/<defs\b[^>]*>[\s\S]*?<\/defs>/g)]
    .map((match) => match[0])
    .join("\n");
  const styles = defs
    ? ""
    : [...svgText.matchAll(/<style\b[^>]*>[\s\S]*?<\/style>/g)]
        .map((match) => match[0])
        .join("\n");
  const mapTransform = svgText.match(
    /<g\b(?=[^>]*\bid="main-map-scaled-layer")(?=[^>]*\btransform="([^"]+)")[^>]*>/,
  )?.[1];
  const regionalSingleLine = /id="(?:gwangju|daejeon)-metro-/.test(svgStart);
  const gwangju = svgStart.includes('id="gwangju-metro-');
  const currentLineTransferStations = regionalSingleLine
    ? currentLineStationsFromFutureTransfers(
        svgText,
        gwangju
          ? { color: "#009088", radius: "5.8", strokeWidth: "2" }
          : { color: "#00975A", radius: "4.8", strokeWidth: "1.8" },
      )
    : "";
  const layerIds = [
    "transfer-station-shell-underlay-layer",
    "route-lines-layer",
    "route-endpoint-markers-layer",
    "terminal-station-symbols-layer",
    "station-symbols-layer",
    ...(!regionalSingleLine ? ["transfer-station-symbols-layer"] : []),
  ];
  const mapGroup = layerIds
    .map((id) => {
      const group = extractGroup(svgText, id);
      if (id === "route-lines-layer") return roundRouteStrokes(group);
      if (gwangju && id === "station-symbols-layer") {
        return keepGwangjuLine1Stations(group);
      }
      return group;
    })
    .filter(Boolean)
    .join("\n")
    .replace(
      /<g\b(?=[^>]*data-state="(?:construction|planned)")[^>]*>[\s\S]*?<\/g>/g,
      "",
    )
    .replace(
      /<(?:path|polyline)\b(?=[^>]*data-status="planned-unbuilt")[^>]*\/>/g,
      "",
    )
    .replace(
      /<(?:path|polyline)\b(?=[^>]*data-line="line2-phase[^"]*")[^>]*\/>/g,
      "",
    )
    .replace(
      /<circle\b(?=[^>]*stroke="#E63332")[^>]*\/>/g,
      regionalSingleLine ? "" : "$&",
    )
    .replace(/<title\b[^>]*>[\s\S]*?<\/title>/g, "");
  let renderedMap = currentLineTransferStations
    ? `${mapGroup}\n${currentLineTransferStations}`
    : mapGroup;
  if (mapTransform) {
    renderedMap = `<g id="compiled-map-coordinate-layer" transform="${mapTransform}">\n${renderedMap}\n</g>`;
  }
  if (!mapGroup.includes('id="route-lines-layer"')) {
    throw new Error("route-lines-layer를 SVG에서 찾지 못했습니다.");
  }
  return `${svgStart}\n${defs || styles}\n${renderedMap}\n</svg>`;
}

function inlineSimpleClassStyles(svgText) {
  const rules = [];
  const css = [...svgText.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/g)]
    .map((match) => match[1])
    .join("\n")
    .replace(/\/\*[\s\S]*?\*\//g, "");
  for (const match of css.matchAll(/([^{}]+)\{([^{}]+)\}/g)) {
    const declarations = match[2]
      .split(";")
      .map((item) => item.trim())
      .filter(Boolean)
      .map((item) => item.split(/:(.*)/s).slice(0, 2).map((part) => part.trim()))
      .filter(
        ([property, value]) =>
          supportedClassStyleProperties.has(property) && !value.includes("var("),
      );
    for (const selector of match[1].split(",").map((item) => item.trim())) {
      if (/^(\.[A-Za-z_][\w-]*)+$/.test(selector)) {
        rules.push({
          classes: selector.slice(1).split("."),
          declarations,
        });
      }
    }
  }

  return svgText.replace(/<([A-Za-z][\w:-]*)\b([^<>]*\bclass="([^"]+)"[^<>]*)>/g, (
    tag,
    name,
    attributes,
    classValue,
  ) => {
    const selfClosing = /\/\s*$/.test(attributes);
    attributes = attributes.replace(/\/\s*$/, "");
    const classes = new Set(classValue.split(/\s+/));
    const declarations = rules
      .filter((rule) => rule.classes.every((className) => classes.has(className)))
      .flatMap((rule) => rule.declarations);
    for (const [property, value] of declarations) {
      const attributePattern = new RegExp(`\\s${property}="[^"]*"`);
      const attribute = ` ${property}="${value.replace(/\s*!important\s*$/, "")}"`;
      attributes = attributePattern.test(attributes)
        ? attributes.replace(attributePattern, attribute)
        : `${attributes}${attribute}`;
    }
    return `<${name}${attributes}${selfClosing ? " /" : ""}>`;
  });
}

export function normalizeSvgForCompile(svgText) {
  return inlineSimpleClassStyles(extractMapSvg(svgText))
    .replace(
      /font-weight="(\d+)"/g,
      (_m, v) => `font-weight="${normalizeFontWeightValue(v)}"`,
    )
    .replace(
      /font-weight:\s*(\d+)/g,
      (_m, v) => `font-weight:${normalizeFontWeightValue(v)}`,
    )
    .replace(
      /([\s"'])(x|y|dx|dy)="([^"]*)"/g,
      (_m, boundary, attr, value) => {
        const first = value.trim().split(/\s+/)[0] ?? value;
        return `${boundary}${attr}="${first}"`;
      },
    );
}

// vector_graphics_compiler를 apps/mobile 컨텍스트에서 실행한다. `--packages`가
// 자동 해석되도록 cwd를 apps/mobile로 둔다. 경로는 전부 절대경로로 넘긴다.
// 원본 SVG를 정규화한 임시 사본을 컴파일 입력으로 쓴다(원본 불변).
function compile(inputSvg, outputVec, normalizedSvgDir) {
  const normalizedSvg = path.join(
    normalizedSvgDir,
    `${path.basename(outputVec, ".vec")}.svg`,
  );
  writeFileSync(
    normalizedSvg,
    normalizeSvgForCompile(readFileSync(inputSvg, "utf8")),
  );
  execFileSync(dartBin, [
    "run",
    "vector_graphics_compiler",
    "-i",
    normalizedSvg,
    "-o",
    outputVec,
  ], { cwd: mobileDir, stdio: ["ignore", "inherit", "inherit"] });
}

function main() {
  const verify = process.argv.slice(2).includes("--verify");
  mkdirSync(outDir, { recursive: true });

  // 정규화 임시 SVG·재현검증 산출물은 커밋 대상 밖(.tmp)에 둔다.
  const tmpDir = path.join(outDir, ".tmp");
  const normalizedSvgDir = path.join(tmpDir, "svg");
  const verifyDir = path.join(tmpDir, "verify");
  mkdirSync(normalizedSvgDir, { recursive: true });
  if (verify) {
    mkdirSync(verifyDir, { recursive: true });
  }

  let allMatch = true;
  const buildMaps = [];
  try {
    for (const region of regions) {
      const inputSvg = path.join(svgSourceDir, region.svg);
      const outputVec = path.join(outDir, `${region.id}.vec`);
      const sourceSvg = readFileSync(inputSvg);
      const sourceText = sourceSvg.toString("utf8");
      const normalizedSvg = normalizeSvgForCompile(sourceText);
      const viewBox = sourceText
        .match(/\bviewBox="([^"]+)"/)?.[1]
        .trim()
        .split(/[\s,]+/)
        .map(Number);
      if (viewBox?.length !== 4 || viewBox.some((value) => !Number.isFinite(value))) {
        throw new Error(`${region.svg}: 유효한 viewBox를 찾지 못했습니다.`);
      }
      compile(inputSvg, outputVec, normalizedSvgDir);
      const digest = sha256(outputVec);
      buildMaps.push({
        id: region.id,
        source: path.relative(root, inputSvg).replaceAll(path.sep, "/"),
        compiledVector: path.relative(root, outputVec).replaceAll(path.sep, "/"),
        sourceSvgSha256: sha256Value(sourceSvg),
        normalizedSvgSha256: sha256Value(normalizedSvg),
        compiledVectorSha256: digest,
        viewBox,
      });
      process.stdout.write(`${region.id}.vec  sha256=${digest}\n`);

      if (verify) {
        const secondVec = path.join(verifyDir, `${region.id}.vec`);
        compile(inputSvg, secondVec, normalizedSvgDir);
        const secondDigest = sha256(secondVec);
        const match = secondDigest === digest;
        allMatch &&= match;
        process.stdout.write(
          `${region.id}.vec  재현검증(2회) ${match ? "일치" : "불일치"}` +
            `${match ? "" : ` (${secondDigest})`}\n`,
        );
      }
    }
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
  }

  if (verify) {
    if (!allMatch) {
      process.stderr.write(
        "컴파일 산출이 비결정적입니다(2회 sha256 불일치). 실패로 종료합니다.\n",
      );
      process.exit(1);
    }
    process.stdout.write("전 권역 재현검증 통과: 2회 컴파일 sha256 동일.\n");
  }

  writeFileSync(
    buildManifestPath,
    `${JSON.stringify(
      {
        schemaVersion: 1,
        artifactKind: "route-map-basemap-build-manifest",
        compiler: {
          package: "vector_graphics_compiler",
          version: compilerVersion,
        },
        content: {
          svgLayer: "route-lines-and-station-symbols",
          stationSymbols: "owner-svg",
          labels: "structured-data",
          interaction: "route_map_positions",
        },
        maps: buildMaps,
      },
      null,
      2,
    )}\n`,
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
