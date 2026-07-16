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
          ? { color: "#009088", radius: "20", strokeWidth: "6" }
          : { color: "#00975A", radius: "15", strokeWidth: "4.5" },
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

// compiled-map-coordinate-layer 래퍼의 `scale(k)`에서 k를 파싱한다(없으면 1).
// `scale(x y)` 2값 형식은 첫 값을 쓴다(축정렬 가정과 정합).
function scaleFromMapTransform(transform) {
  if (!transform) return 1;
  const match = transform.match(/scale\(\s*(-?[\d.]+)/);
  const k = match ? Number(match[1]) : 1;
  return Number.isFinite(k) ? k : 1;
}

// 결정성 유지를 위해 고정 소수 4자리로 직렬화(trailing zero는 Number가 정리).
function roundCoord(value) {
  return Number(value.toFixed(4));
}

// 오너 SVG 라벨 실측 좌표 추출(#2068 6차) — 자동 솔버가 밀집부에서 선을
// 가로지르는 한계를, 오너가 SVG에서 손으로 배치한 역명 라벨 앵커로 대체한다.
// station-name-labels-layer(및 gwangju의 동등 레이어)는 컴파일 대상(.vec)에서
// 제외되므로(제목·범례·역명은 구조화 오버레이가 담당) 원본 svgText에서 별도
// 추출해 sidecar JSON으로 낸다.
//
// 5권역 실측(2026-07) 결과 마크업이 서로 다르다:
//   - seoul/busan/daegu/daejeon: data-label-role이 <text> 태그 자체에 있다.
//   - gwangju: data-label-role이 감싸는 <g>에 있고 바로 안에 <text>가 온다.
// 위치도 2형식이 섞여 있다: x/y 속성형(대부분) / transform="translate(a b)"
// + tspan x="0" y="0" 형(예: 뚝섬). 드물게(인천 다중행 라벨 2건) 양쪽 다 있어
// "발견한 모든 translate 오프셋의 합 + text(또는 첫 tspan) x/y"라는 단일
// 공식을 쓴다 — SVG 렌더 의미(자신의 transform이 좌표계를 옮긴 뒤 그 안에서
// x/y를 해석)와 정확히 일치해 모든 형식을 하나로 포섭한다.
//
// 역명 키는 속성명이 권역마다 다르다(seoul/busan="data-station" 직접 한글명,
// daejeon="data-full-official-name", gwangju="data-station-name" g 래퍼) —
// 신뢰하지 않는다. 대신 렌더된 텍스트 내용(tspan 연결)을 station 키로 쓴다.
// 전 권역 실측 결과 텍스트 내용이 해당 속성값과 항상 일치해 더 단순·강건하다.
//
// role 필터: ordinary/transfer/terminal만 포함. code(대구 역번호 라벨) 제외.
// daejeon의 planned·regional 6+2건은 전부 data-status="construction"/"planned"
// (미개통 연장·충청권 광역철도 공사중 표기)이라 제외 — compile-basemap-vec.mjs의
// 기존 construction/planned 제외 관례와 일치한다.
//
// font-size는 대개 <text> 속성이지만 gwangju는 CSS class(.station-label-<role>)
// 에서만 온다 — 클래스 규칙을 role별로 미리 읽어 인라인 속성이 없을 때 쓴다.
const ownerLabelRoles = ["ordinary", "transfer", "terminal"];

function parseTranslate(transformValue) {
  if (!transformValue) return { dx: 0, dy: 0 };
  const match = transformValue.match(
    /translate\(\s*(-?[\d.]+)[,\s]+(-?[\d.]+)\s*\)/,
  );
  return match
    ? { dx: Number(match[1]), dy: Number(match[2]) }
    : { dx: 0, dy: 0 };
}

function firstAttr(tag, name) {
  const match = tag.match(new RegExp(`\\s${name}="([^"]*)"`));
  return match ? match[1] : null;
}

// <style> 블록에서 .station-label-<role> { ... font-size:<n>px ... } 규칙을
// role → local px 맵으로 읽는다(gwangju처럼 인라인 font-size가 없는 경우 폴백).
function stationLabelFontSizesByRole(svgText) {
  const css = [...svgText.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/g)]
    .map((match) => match[1])
    .join("\n");
  const byRole = {};
  for (const role of ownerLabelRoles) {
    const rule = css.match(
      new RegExp(`\\.station-label-${role}\\s*\\{([^}]*)\\}`),
    );
    const fontSize = rule?.[1].match(/font-size:\s*([\d.]+)px/)?.[1];
    if (fontSize) byRole[role] = Number(fontSize);
  }
  return byRole;
}

function ownerLabelTextContent(textBlock) {
  return textBlock
    .replace(/^<text\b[^>]*>/, "")
    .replace(/<\/text>$/, "")
    .replace(/<[^>]+>/g, "")
    .replace(/\s+/g, "")
    .trim();
}

// [groupOpenTag]는 gwangju처럼 role이 감싸는 <g>에 있을 때만 넘긴다(그 외 null).
function ownerLabelEntryFrom(
  groupOpenTag,
  textBlock,
  role,
  mapScale,
  mapTranslate,
  cssFontSizeByRole,
) {
  const textOpenTagMatch = textBlock.match(/^<text\b[^>]*>/);
  if (!textOpenTagMatch) return null;
  const textOpenTag = textOpenTagMatch[0];
  // 미개통(공사중) 라벨 제외 — role만으로는 못 거른다(daejeon 2호선 트램 39건이
  // role="ordinary/transfer/terminal"이면서 data-status="construction"). 기존
  // compile-basemap-vec.mjs의 construction/planned 제외 관례와 일치시킨다.
  const constructionPattern = /data-(?:status|state)="(?:construction|planned)"/;
  if (
    constructionPattern.test(textOpenTag) ||
    (groupOpenTag && constructionPattern.test(groupOpenTag))
  ) {
    return null;
  }
  const groupTranslate = groupOpenTag
    ? parseTranslate(firstAttr(groupOpenTag, "transform"))
    : { dx: 0, dy: 0 };
  const textTranslate = parseTranslate(firstAttr(textOpenTag, "transform"));
  let x = firstAttr(textOpenTag, "x");
  let y = firstAttr(textOpenTag, "y");
  if (x == null || y == null) {
    const firstTspan = textBlock.match(/<tspan\b[^>]*>/);
    if (firstTspan) {
      x = x ?? firstAttr(firstTspan[0], "x");
      y = y ?? firstAttr(firstTspan[0], "y");
    }
  }
  const localX = groupTranslate.dx + textTranslate.dx + Number(x ?? NaN);
  const localY = groupTranslate.dy + textTranslate.dy + Number(y ?? NaN);
  const anchorRaw = firstAttr(textOpenTag, "text-anchor") ?? "start";
  const anchor = ["start", "middle", "end"].includes(anchorRaw)
    ? anchorRaw
    : "start";
  const fontSizeAttr = firstAttr(textOpenTag, "font-size");
  const fontSizeLocal = fontSizeAttr
    ? Number(fontSizeAttr.replace(/px$/, ""))
    : cssFontSizeByRole[role];
  const station = ownerLabelTextContent(textBlock);
  if (
    !station ||
    !Number.isFinite(localX) ||
    !Number.isFinite(localY) ||
    !Number.isFinite(fontSizeLocal)
  ) {
    return null;
  }
  return {
    station,
    role,
    x: roundCoord(mapTranslate.dx + localX * mapScale),
    y: roundCoord(mapTranslate.dy + localY * mapScale),
    anchor,
    fontSizePx: roundCoord(fontSizeLocal * mapScale),
  };
}

// 원본 svgText(정규화·레이어 추출 이전)에서 오너 라벨 앵커 목록을 뽑는다.
// 반환은 station 오름차순(로케일 정렬) → role 오름차순으로 정렬해 결정적이다.
export function extractOwnerLabels(svgText) {
  const mapTransform = svgText.match(
    /<g\b(?=[^>]*\bid="main-map-scaled-layer")(?=[^>]*\btransform="([^"]+)")[^>]*>/,
  )?.[1];
  const mapScale = scaleFromMapTransform(mapTransform);
  const mapTranslate = parseTranslate(mapTransform);
  const cssFontSizeByRole = stationLabelFontSizesByRole(svgText);
  const rolePattern = ownerLabelRoles.join("|");

  const entries = [];
  const textRe = new RegExp(
    `<text\\b[^>]*\\bdata-label-role="(${rolePattern})"[^>]*>[\\s\\S]*?<\\/text>`,
    "g",
  );
  for (const match of svgText.matchAll(textRe)) {
    const entry = ownerLabelEntryFrom(
      null,
      match[0],
      match[1],
      mapScale,
      mapTranslate,
      cssFontSizeByRole,
    );
    if (entry) entries.push(entry);
  }
  const groupRe = new RegExp(
    `<g\\b[^>]*\\bdata-label-role="(${rolePattern})"[^>]*>\\s*<text\\b[^>]*>[\\s\\S]*?<\\/text>`,
    "g",
  );
  for (const match of svgText.matchAll(groupRe)) {
    const groupOpenTag = match[0].match(/^<g\b[^>]*>/)[0];
    const textBlock = match[0].slice(groupOpenTag.length).trim();
    const entry = ownerLabelEntryFrom(
      groupOpenTag,
      textBlock,
      match[1],
      mapScale,
      mapTranslate,
      cssFontSizeByRole,
    );
    if (entry) entries.push(entry);
  }
  entries.sort((a, b) =>
    a.station === b.station
      ? a.role.localeCompare(b.role)
      : a.station.localeCompare(b.station, "ko"),
  );
  return entries;
}

// 종점 호선 마크 sidecar 플래그(#2068 광주 2차) — region의 원본 SVG가 자체
// 종점 배지(<g data-role="line-terminal-badge">, route-lines-layer 내 원+숫자
// 마감)를 그리면 앱 솔버가 같은 자리에 노선 뱃지 pill을 중복해 그리지 않도록
// terminal role 오너 라벨 엔트리에 hasLineTerminalBadge:true를 표시한다.
// region 단위 감지(개별 역 좌표 매칭 불필요 — 광주·대전 둘 다 노선이 1개뿐이라
// terminal 엔트리 전부에 표시해도 의미가 동일하다). 플래그 없는 권역은 기존
// 엔트리 그대로(추가 키 없음) — 하위 호환.
export function markLineTerminalBadgeEntries(ownerLabels, sourceText) {
  if (!/data-role="line-terminal-badge"/.test(sourceText)) {
    return ownerLabels;
  }
  return ownerLabels.map((entry) =>
    entry.role === "terminal"
      ? { ...entry, hasLineTerminalBadge: true }
      : entry,
  );
}

// style="...font-size:<n>px?..." 선언 값을 ×k로 교체한다(px 접미사는 유지).
// text·tspan 공통 — SVG에서 style 속성은 동명 presentation attribute보다 우선하므로
// (예: 클래스가 준 font-size 속성 위에 개별 style로 덮어쓴 배지들) 실제 렌더 크기는
// style 값이 결정한다. Inkscape 수작업 stray 텍스트(예: GTX-A 배지 옆 tspan, class
// 없음)는 font-size가 style에만 있어 속성형 스케일링을 비껴간다 — 별도로 보정한다.
function scaleStyleFontSize(tag, k) {
  return tag.replace(/style="([^"]*)"/, (_m, styleValue) => {
    if (!/font-size\s*:/.test(styleValue)) return `style="${styleValue}"`;
    const scaled = styleValue.replace(
      /font-size\s*:\s*([\d.]+)(px)?/,
      (_fm, num, px) => `font-size:${roundCoord(Number(num) * k)}${px ?? ""}`,
    );
    return `style="${scaled}"`;
  });
}

// vector_graphics_compiler 1.2.6은 축정렬 transform을 소비하며 텍스트 x/y만 변환하고
// transform을 버린다(node.dart computeTextPosition). 런타임은 fontSize를 그대로 쓰므로
// scale(k) 레이어 안 텍스트가 viewBox 좌표계에서 k배 안 된 크기로 렌더된다. 또한
// dominant-baseline central/alignment-baseline middle을 컴파일러·런타임이 지원하지 않아
// 글리프가 의도한 세로 중심보다 위로 뜬다. 정규화 단계에서 결정적으로 보정한다:
//   1) font-size(속성형·style형 모두)를 로컬 값 × k로 교체(px 접미사는 속성형만 제거,
//      style형은 유지) — k=1이면 값 유지.
//   2) baseline이 central/middle이면 y를 로컬 단위 0.35*fontSize만큼 내리고
//      baseline 속성을 제거(이후 컴파일러가 point를 k배 변환하므로 로컬 단위가 맞다).
//      style형 전용 stray 텍스트(Inkscape 수작업)에는 baseline 속성이 없어 대상이
//      아니다 — 이미 alphabetic 기준으로 배치돼 있으므로 y는 건드리지 않는다.
// inlineSimpleClassStyles 이후에 적용해 class에서 온 font-size·baseline도 속성으로
// 정리된 상태를 다룬다. text·tspan 이외 요소는 건드리지 않으며, 텍스트 내용은 불변이다.
function normalizeTextBaselineAndScale(svgText, k) {
  const withStyleFontSizeScaled = svgText.replace(
    /<(?:text|tspan)\b[^>]*>/g,
    (tag) => scaleStyleFontSize(tag, k),
  );
  return withStyleFontSizeScaled.replace(/<text\b[^>]*>/g, (tag) => {
    const fontSizeMatch = tag.match(/\sfont-size="([\d.]+)(?:px)?"/);
    if (!fontSizeMatch) return tag;
    const fontSizeLocal = Number(fontSizeMatch[1]);
    if (!Number.isFinite(fontSizeLocal)) return tag;
    let result = tag;
    const central =
      /\sdominant-baseline="central"/.test(result) ||
      /\salignment-baseline="(?:middle|central)"/.test(result);
    if (central) {
      const yMatch = result.match(/\sy="(-?[\d.]+)"/);
      if (yMatch && Number.isFinite(Number(yMatch[1]))) {
        result = result.replace(
          /\sy="-?[\d.]+"/,
          ` y="${roundCoord(Number(yMatch[1]) + 0.35 * fontSizeLocal)}"`,
        );
      }
      result = result
        .replace(/\sdominant-baseline="[^"]*"/g, "")
        .replace(/\salignment-baseline="[^"]*"/g, "");
    }
    return result.replace(
      /\sfont-size="[\d.]+(?:px)?"/,
      ` font-size="${roundCoord(fontSizeLocal * k)}"`,
    );
  });
}

export function normalizeSvgForCompile(svgText) {
  const extracted = extractMapSvg(svgText);
  const k = scaleFromMapTransform(
    extracted.match(
      /<g id="compiled-map-coordinate-layer" transform="([^"]+)"/,
    )?.[1],
  );
  const inlined = inlineSimpleClassStyles(extracted)
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
  return normalizeTextBaselineAndScale(inlined, k);
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

const labelsSidecarPath = path.join(outDir, "labels.json");

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
  const labelsByRegion = {};
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
      const ownerLabels = markLineTerminalBadgeEntries(
        extractOwnerLabels(sourceText),
        sourceText,
      );
      labelsByRegion[region.id] = ownerLabels;
      buildMaps.push({
        id: region.id,
        source: path.relative(root, inputSvg).replaceAll(path.sep, "/"),
        compiledVector: path.relative(root, outputVec).replaceAll(path.sep, "/"),
        sourceSvgSha256: sha256Value(sourceSvg),
        normalizedSvgSha256: sha256Value(normalizedSvg),
        compiledVectorSha256: digest,
        viewBox,
        ownerLabelCount: ownerLabels.length,
      });
      process.stdout.write(
        `${region.id}.vec  sha256=${digest}  ownerLabels=${ownerLabels.length}\n`,
      );

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

  // 오너 라벨 sidecar(#2068 6차): basemap 모드가 자동 솔버 대신 참조하는 SVG
  // 실측 앵커. 5권역 결합 단일 파일 — metro_map_pack/basemap/ 디렉터리는
  // pubspec.yaml에 통째로 등록돼 있어 추가 자산 등록이 필요 없다.
  const labelsSidecarJson = `${JSON.stringify(
    {
      schemaVersion: 1,
      artifactKind: "route-map-basemap-owner-labels",
      regions: labelsByRegion,
    },
    null,
    2,
  )}\n`;
  writeFileSync(labelsSidecarPath, labelsSidecarJson);
  const labelsSidecarSha256 = sha256Value(labelsSidecarJson);
  process.stdout.write(
    `labels.json  sha256=${labelsSidecarSha256}  regions=${Object.keys(labelsByRegion).length}\n`,
  );

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
          labels: "owner-svg-anchor-with-solver-fallback",
          interaction: "route_map_positions",
        },
        ownerLabelsSidecar: {
          path: path
            .relative(root, labelsSidecarPath)
            .replaceAll(path.sep, "/"),
          sha256: labelsSidecarSha256,
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
