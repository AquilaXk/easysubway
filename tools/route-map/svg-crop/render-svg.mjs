#!/usr/bin/env node
// Render an SVG to PNG with headless Chrome at a given scale.
// Usage: node render.mjs <svg> <out.png> <scale> [--ink]
//   --ink : hide #page-background / #background-grid-overlay and use a
//           transparent backdrop, so alpha>0 == owner ink.
import { readFileSync, writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const [, , svgPath, outPng, scaleArg] = process.argv;
const inkOnly = process.argv.includes('--ink');
const scale = Number(scaleArg || 1);

let svgText = readFileSync(svgPath, 'utf8')
  .replace(/^﻿/, '')
  .replace(/<\?xml[\s\S]*?\?>/g, '')
  .replace(/<!DOCTYPE[\s\S]*?>/g, '');

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

const dir = mkdtempSync(join(tmpdir(), 'svgrender-'));
const htmlPath = join(dir, 'page.html');
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
