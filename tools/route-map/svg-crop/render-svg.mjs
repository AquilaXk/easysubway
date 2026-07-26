#!/usr/bin/env node
// 오너 SVG를 headless Chrome으로 PNG 렌더한다(#2603 잉크 무손실 검증용).
//
//   node tools/route-map/svg-crop/render-svg.mjs <svg> <out.png> <scale> [--ink]
//
//   --ink : 전면 배경·그리드를 숨기고 투명 배경으로 그린다 → alpha>0이 곧 잉크다.
//           크롭 전후 비교(verify-ink-lossless.py)는 이 모드 산출물을 쓴다.
//
// 경로는 저장소 안이나 임시 디렉터리로 제한한다 — 저장소 도구가 임의 경로를
// 읽고 쓸 이유가 없고, 실수로 밖을 건드리면 조용히 넘어가지 않는 편이 낫다.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

/** 심볼릭 링크를 푼 절대경로(macOS의 /tmp → /private/tmp 등). */
function realOf(target) {
  let current = path.resolve(target);
  while (!existsSync(current) && path.dirname(current) !== current) {
    current = path.dirname(current);
  }
  return existsSync(current)
    ? path.join(realpathSync(current), path.relative(current, path.resolve(target)))
    : path.resolve(target);
}

const allowedRoots = [
  realOf(path.resolve(here, '..', '..', '..')),
  realOf(tmpdir()),
  realOf('/tmp'),
];

/** 저장소 또는 임시 디렉터리 안으로 해석되는 절대경로만 돌려준다. */
function resolveAllowed(candidate, label) {
  if (!candidate) throw new Error(`${label} 경로가 없습니다.`);
  const resolved = realOf(candidate);
  const inside = allowedRoots.some(
    (root) => resolved === root || resolved.startsWith(root + path.sep),
  );
  if (!inside) {
    throw new Error(
      `${label} 경로가 허용 범위 밖입니다: ${resolved}\n` +
        `허용: ${allowedRoots.join(', ')}`,
    );
  }
  return resolved;
}

/** 실행할 브라우저. 실제 파일인지 확인해 임의 명령 실행을 막는다. */
function resolveChrome() {
  const candidate =
    process.env.CHROME_BIN ??
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  const resolved = path.resolve(candidate);
  if (!existsSync(resolved) || !statSync(resolved).isFile()) {
    throw new Error(`브라우저 실행 파일을 찾지 못했습니다: ${resolved}`);
  }
  return resolved;
}

const CHROME = resolveChrome();
const [, , svgArg, outArg, scaleArg] = process.argv;
const inkOnly = process.argv.includes('--ink');
const svgPath = resolveAllowed(svgArg, '입력 SVG');
const outPng = resolveAllowed(outArg, '출력 PNG');
const scale = Number(scaleArg || 1);
if (!Number.isFinite(scale) || scale <= 0) {
  throw new Error(`scale이 유효하지 않습니다: ${scaleArg}`);
}

let svgText = readFileSync(svgPath, 'utf8')
  .replaceAll('\ufeff', '')
  .replaceAll(/<\?xml[\s\S]*?\?>/g, '')
  .replaceAll(/<!DOCTYPE[\s\S]*?>/g, '');

const vb = svgText.match(/viewBox\s*=\s*"([^"]+)"/)[1].trim().split(/[\s,]+/).map(Number);
const [, , vbw, vbh] = vb;
const W = Math.round(vbw * scale);
const H = Math.round(vbh * scale);

let inlined = svgText.replace(/<svg\b/, '<svg id="target"');
inlined = inlined.replace(/(<svg\b[^>]*?)\swidth\s*=\s*"[^"]*"/, '$1');
inlined = inlined.replace(/(<svg\b[^>]*?)\sheight\s*=\s*"[^"]*"/, '$1');
inlined = inlined.replace(/<svg\b/, `<svg width="${W}" height="${H}"`);

const inkCss = inkOnly
  ? '#page-background,#background-grid-overlay{display:none !important}html,body{background:transparent !important}'
  : 'html,body{background:#fff}';

const html = `<!doctype html><html><head><meta charset="utf-8"><style>
*{margin:0;padding:0}
html,body{width:${W}px;height:${H}px;overflow:hidden}
svg#target{display:block;width:${W}px;height:${H}px}
${inkCss}
</style></head><body>${inlined}</body></html>`;

const dir = mkdtempSync(path.join(tmpdir(), 'svgrender-'));
const htmlPath = path.join(dir, 'page.html');
writeFileSync(htmlPath, html);

const args = [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
  '--force-device-scale-factor=1',
  `--window-size=${W},${H}`,
  '--virtual-time-budget=60000',
  '--run-all-compositor-stages-before-draw',
  `--screenshot=${outPng}`,
];
if (inkOnly) args.push('--default-background-color=00000000');
args.push(`file://${htmlPath}`);

execFileSync(CHROME, args, { stdio: ['ignore', 'ignore', 'ignore'] });
console.log(`${outPng} ${W}x${H} scale=${scale} ink=${inkOnly}`);
