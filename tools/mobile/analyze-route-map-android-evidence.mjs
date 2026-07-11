#!/usr/bin/env node
import { existsSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";

function usage() {
  return `Usage:
  node tools/mobile/analyze-route-map-android-evidence.mjs --artifact-dir <dir> [--artifact-dir <dir> ...] [--format json|markdown]

Options:
  --artifact-dir <dir>  Evidence directory created by run-route-map-android-evidence.sh.
  --format <format>     Output format. Defaults to markdown.
  -h, --help            Show this help.
`;
}

function parseArgs(argv) {
  const artifactDirs = [];
  let format = "markdown";
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--artifact-dir":
        artifactDirs.push(argv[index + 1] ?? "");
        index += 1;
        break;
      case "--format":
        format = argv[index + 1] ?? "";
        index += 1;
        break;
      case "-h":
      case "--help":
        return { help: true, artifactDirs, format };
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (artifactDirs.length === 0 || artifactDirs.some((dir) => dir.length === 0)) {
    throw new Error("At least one --artifact-dir value is required.");
  }
  if (!["json", "markdown"].includes(format)) {
    throw new Error(`Unsupported format: ${format}`);
  }
  return { help: false, artifactDirs, format };
}

function readRequired(filePath) {
  const stat = statSync(filePath);
  if (!stat.isFile() || stat.size === 0) {
    throw new Error(`Expected non-empty file: ${filePath}`);
  }
  return readFileSync(filePath, "utf8");
}

function parseMetadata(text) {
  return Object.fromEntries(
    text
      .split(/\r?\n/)
      .filter((line) => line.includes("="))
      .map((line) => {
        const separator = line.indexOf("=");
        return [line.slice(0, separator), line.slice(separator + 1)];
      }),
  );
}

function parseNumber(value) {
  return Number.parseInt(value.replace(/,/g, ""), 10);
}

function parseGfxinfo(text) {
  const total = text.match(/Total frames rendered:\s*([\d,]+)/);
  const janky = text.match(/Janky frames:\s*([\d,]+)\s*\(([\d.]+)%\)/);
  const percentiles = {};
  for (const match of text.matchAll(/(50th|90th|95th|99th) percentile:\s*([\d,]+)ms/g)) {
    percentiles[match[1]] = parseNumber(match[2]);
  }
  const totalFrames = total ? parseNumber(total[1]) : null;
  // Flutter는 자체 canvas 렌더 파이프라인이라 dumpsys gfxinfo(HWUI)가 노선도
  // 프레임을 잡지 못한다. totalFrames=0이면 percentile/jankyPercent는 "측정
  // 불가"이며, histogram 최상단 버킷(4950ms)이 그대로 튀어나온 잔재이므로
  // null로 두어 FrameTiming 정본을 오염시키지 않는다.
  const captured = totalFrames != null && totalFrames > 0;
  return {
    totalFrames,
    measurementStatus: captured ? "captured" : "not_captured_flutter_canvas",
    jankyFrames: janky ? parseNumber(janky[1]) : null,
    jankyPercent: captured && janky ? Number.parseFloat(janky[2]) : null,
    p50Ms: captured ? percentiles["50th"] ?? null : null,
    p90Ms: captured ? percentiles["90th"] ?? null : null,
    p95Ms: captured ? percentiles["95th"] ?? null : null,
    p99Ms: captured ? percentiles["99th"] ?? null : null,
  };
}

function parseMeminfo(text) {
  const total = text.match(/TOTAL PSS:\s*([\d,]+)\s+TOTAL RSS:\s*([\d,]+)/);
  const javaHeap = text.match(/Java Heap:\s*([\d,]+)/);
  const nativeHeap = text.match(/Native Heap:\s*([\d,]+)/);
  const graphics = text.match(/Graphics:\s*([\d,]+)/);
  return {
    totalPssKb: total ? parseNumber(total[1]) : null,
    totalRssKb: total ? parseNumber(total[2]) : null,
    javaHeapKb: javaHeap ? parseNumber(javaHeap[1]) : null,
    nativeHeapKb: nativeHeap ? parseNumber(nativeHeap[1]) : null,
    graphicsKb: graphics ? parseNumber(graphics[1]) : null,
  };
}

function percentile(values, percentileValue) {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(
    sorted.length - 1,
    Math.ceil((percentileValue / 100) * sorted.length) - 1,
  );
  return sorted[index];
}

// 구조화 canvas 렌더러(#1641)는 WebView cameraLatency/dispose 로그를 내지 않는다.
// pan/zoom 구간의 렌더러 크래시 시그니처 수만 집계해 안정성 게이트로 쓴다.
function parseRendererCrashes(text) {
  const signatures = text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  return { crashSignatureCount: signatures.length };
}

// #1643 프레임 성능 정본: 앱이 로깅한 routeMapFrame build/raster/total(ms)에서
// P50/P90 지연과 jank 비율(빌드 또는 래스터가 1 vsync=16.7ms 초과한 프레임)을 낸다.
const FRAME_BUDGET_MS = 16.7;

function parseFrameTimings(text) {
  const frames = [
    ...text.matchAll(
      /routeMapFrame buildMs=([\d.]+) rasterMs=([\d.]+) totalMs=([\d.]+)/g,
    ),
  ].map((match) => ({
    build: Number.parseFloat(match[1]),
    raster: Number.parseFloat(match[2]),
    total: Number.parseFloat(match[3]),
  }));
  const builds = frames.map((frame) => frame.build);
  const rasters = frames.map((frame) => frame.raster);
  const totals = frames.map((frame) => frame.total);
  const jankyFrames = frames.filter(
    (frame) => frame.build > FRAME_BUDGET_MS || frame.raster > FRAME_BUDGET_MS,
  ).length;
  return {
    frameSampleCount: frames.length,
    buildP50Ms: percentile(builds, 50),
    buildP90Ms: percentile(builds, 90),
    buildP99Ms: percentile(builds, 99),
    rasterP50Ms: percentile(rasters, 50),
    rasterP90Ms: percentile(rasters, 90),
    rasterP99Ms: percentile(rasters, 99),
    totalP90Ms: percentile(totals, 90),
    jankyFrames,
    jankyPercent:
      frames.length > 0
        ? Math.round((jankyFrames / frames.length) * 10000) / 100
        : null,
  };
}

function analyzeRun(artifactDir) {
  const dir = path.resolve(artifactDir);
  const metadata = parseMetadata(readRequired(path.join(dir, "metadata.env")));
  const gfxinfo = parseGfxinfo(readRequired(path.join(dir, "gfxinfo.txt")));
  const meminfo = parseMeminfo(readRequired(path.join(dir, "meminfo.txt")));
  const crashesPath = path.join(dir, "renderer-crashes.log");
  const renderer = parseRendererCrashes(
    existsSync(crashesPath) ? readFileSync(crashesPath, "utf8") : "",
  );
  const frameTiming = parseFrameTimings(
    readRequired(path.join(dir, "route-map-frames.log")),
  );
  return {
    artifactDir: dir,
    serial: metadata.serial ?? "",
    package: metadata.package ?? "",
    buildMode: metadata.build_mode ?? "",
    measurementScope: metadata.measurement_scope ?? "route_map_entry_and_pan",
    gfxinfoResetAfterRouteMapSettle:
      metadata.gfxinfo_reset_after_route_map_settle === "true",
    viewport: `${metadata.width ?? ""}x${metadata.height ?? ""}`,
    capturedAtUtc: metadata.captured_at_utc ?? "",
    panCount: Number.parseInt(metadata.pan_count ?? "0", 10),
    gfxinfo,
    meminfo,
    renderer,
    frameTiming,
  };
}

function aggregate(runs) {
  // gfxinfo(HWUI) 지표는 프레임을 실제로 캡처한(captured) run만 반영한다.
  // Flutter canvas run(not_captured)의 4950ms 잔재가 프레임 게이트를 오염시키지
  // 않도록 배제하고, captured run이 하나도 없으면 null로 명시한다.
  const capturedRuns = runs.filter(
    (run) => run.gfxinfo.measurementStatus === "captured",
  );
  // captured run이 있어도 특정 지표가 모든 run에서 측정되지 않으면(예: gfxinfo.txt에
  // 해당 percentile/Janky 라인이 없어 null) 그 지표는 "측정 불가"다. null을 0으로
  // 폴백하면 Math.max(0)=0이 "0ms 측정됨"으로 둔갑하므로, null을 걸러낸 유효값만
  // 집계하고 유효값이 하나도 없으면 null을 전파한다.
  const maxCapturedGfxinfo = (selector) => {
    const values = capturedRuns
      .map((run) => selector(run.gfxinfo))
      .filter((value) => value != null);
    return values.length === 0 ? null : Math.max(...values);
  };
  return {
    runCount: runs.length,
    measurementScopes: [...new Set(runs.map((run) => run.measurementScope))],
    maxJankyPercent: maxCapturedGfxinfo((gfxinfo) => gfxinfo.jankyPercent),
    maxP95FrameMs: maxCapturedGfxinfo((gfxinfo) => gfxinfo.p95Ms),
    maxP99FrameMs: maxCapturedGfxinfo((gfxinfo) => gfxinfo.p99Ms),
    maxTotalPssKb: Math.max(...runs.map((run) => run.meminfo.totalPssKb ?? 0)),
    maxFrameJankyPercent: Math.max(
      ...runs.map((run) => run.frameTiming.jankyPercent ?? 0),
    ),
    maxBuildP90Ms: Math.max(...runs.map((run) => run.frameTiming.buildP90Ms ?? 0)),
    maxRasterP90Ms: Math.max(
      ...runs.map((run) => run.frameTiming.rasterP90Ms ?? 0),
    ),
    totalCrashSignatures: runs.reduce(
      (sum, run) => sum + (run.renderer.crashSignatureCount ?? 0),
      0,
    ),
    noCrashesInAllRuns: runs.every(
      (run) => (run.renderer.crashSignatureCount ?? 0) === 0,
    ),
  };
}

function markdownReport(result) {
  const lines = [
    "# Android route map profile evidence summary",
    "",
    `- runs: ${result.aggregate.runCount}`,
    `- measurement_scopes: ${result.aggregate.measurementScopes.join(", ")}`,
    `- max_janky_percent: ${result.aggregate.maxJankyPercent}`,
    `- max_p95_frame_ms: ${result.aggregate.maxP95FrameMs}`,
    `- max_p99_frame_ms_gfxinfo_hwui_only: ${result.aggregate.maxP99FrameMs}`,
    `- max_total_pss_kb: ${result.aggregate.maxTotalPssKb}`,
    `- total_crash_signatures: ${result.aggregate.totalCrashSignatures}`,
    `- no_crashes_in_all_runs: ${result.aggregate.noCrashesInAllRuns}`,
    "",
    "FrameTiming(정본, Flutter canvas 프레임):",
    `- max_frame_janky_percent: ${result.aggregate.maxFrameJankyPercent}`,
    `- max_build_p90_ms: ${result.aggregate.maxBuildP90Ms}`,
    `- max_raster_p90_ms: ${result.aggregate.maxRasterP90Ms}`,
    "",
    "> gfxinfo frame 지표는 HWUI 전용이라 Flutter canvas 노선도 프레임을 반영하지 않는다. 프레임 성능은 FrameTiming(build/raster p90·janky%)이 정본이다.",
    "",
    "| run | scope | build | viewport | frame samples | frame janky | build p90 | raster p90 | total PSS | crashes | evidence |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  ];
  for (const [index, run] of result.runs.entries()) {
    const cells = [
      index + 1,
      run.measurementScope,
      run.buildMode,
      run.viewport,
      run.frameTiming.frameSampleCount ?? "",
      run.frameTiming.jankyPercent == null
        ? ""
        : `${run.frameTiming.jankyFrames} (${run.frameTiming.jankyPercent}%)`,
      run.frameTiming.buildP90Ms == null ? "" : `${run.frameTiming.buildP90Ms}ms`,
      run.frameTiming.rasterP90Ms == null ? "" : `${run.frameTiming.rasterP90Ms}ms`,
      run.meminfo.totalPssKb ?? "",
      run.renderer.crashSignatureCount ?? "",
      run.artifactDir,
    ];
    lines.push(`| ${cells.join(" | ")} |`);
  }
  return `${lines.join("\n")}\n`;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    if (args.help) {
      process.stdout.write(usage());
      return;
    }
    const runs = args.artifactDirs.map(analyzeRun);
    const result = {
      schemaVersion: 1,
      artifactKind: "route-map-android-evidence-summary",
      runs,
      aggregate: aggregate(runs),
    };
    process.stdout.write(
      args.format === "json"
        ? `${JSON.stringify(result, null, 2)}\n`
        : markdownReport(result),
    );
  } catch (error) {
    process.stderr.write(`${error.message}\n\n${usage()}`);
    process.exitCode = 2;
  }
}

main();
