#!/usr/bin/env node
import { readFileSync, statSync } from "node:fs";
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
  return {
    totalFrames: total ? parseNumber(total[1]) : null,
    jankyFrames: janky ? parseNumber(janky[1]) : null,
    jankyPercent: janky ? Number.parseFloat(janky[2]) : null,
    p50Ms: percentiles["50th"] ?? null,
    p90Ms: percentiles["90th"] ?? null,
    p95Ms: percentiles["95th"] ?? null,
    p99Ms: percentiles["99th"] ?? null,
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

function parseRendererLog(text) {
  const latencies = [...text.matchAll(/cameraLatency revision=\d+ elapsedMs=(\d+)/g)].map((match) =>
    parseNumber(match[1]),
  );
  return {
    cameraLatencyCount: latencies.length,
    cameraLatencyMinMs: latencies.length > 0 ? Math.min(...latencies) : null,
    cameraLatencyP50Ms: percentile(latencies, 50),
    cameraLatencyP95Ms: percentile(latencies, 95),
    cameraLatencyP99Ms: percentile(latencies, 99),
    cameraLatencyMaxMs: latencies.length > 0 ? Math.max(...latencies) : null,
    disposedObserved: /routeMapRenderer disposed/.test(text),
  };
}

function analyzeRun(artifactDir) {
  const dir = path.resolve(artifactDir);
  const metadata = parseMetadata(readRequired(path.join(dir, "metadata.env")));
  const gfxinfo = parseGfxinfo(readRequired(path.join(dir, "gfxinfo.txt")));
  const meminfo = parseMeminfo(readRequired(path.join(dir, "meminfo.txt")));
  const renderer = parseRendererLog(readRequired(path.join(dir, "route-map-renderer.log")));
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
  };
}

function aggregate(runs) {
  return {
    runCount: runs.length,
    measurementScopes: [...new Set(runs.map((run) => run.measurementScope))],
    maxJankyPercent: Math.max(...runs.map((run) => run.gfxinfo.jankyPercent ?? 0)),
    maxP95FrameMs: Math.max(...runs.map((run) => run.gfxinfo.p95Ms ?? 0)),
    maxP99FrameMs: Math.max(...runs.map((run) => run.gfxinfo.p99Ms ?? 0)),
    maxCameraLatencyP95Ms: Math.max(...runs.map((run) => run.renderer.cameraLatencyP95Ms ?? 0)),
    maxTotalPssKb: Math.max(...runs.map((run) => run.meminfo.totalPssKb ?? 0)),
    disposeObservedInAllRuns: runs.every((run) => run.renderer.disposedObserved),
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
    `- max_p99_frame_ms: ${result.aggregate.maxP99FrameMs}`,
    `- max_camera_latency_p95_ms: ${result.aggregate.maxCameraLatencyP95Ms}`,
    `- max_total_pss_kb: ${result.aggregate.maxTotalPssKb}`,
    `- dispose_observed_in_all_runs: ${result.aggregate.disposeObservedInAllRuns}`,
    "",
    "| run | scope | build | viewport | frames | janky | p95 frame | p99 frame | camera p95 | total PSS | dispose | evidence |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  ];
  for (const [index, run] of result.runs.entries()) {
    const cells = [
      index + 1,
      run.measurementScope,
      run.buildMode,
      run.viewport,
      run.gfxinfo.totalFrames ?? "",
      run.gfxinfo.jankyPercent == null
        ? ""
        : `${run.gfxinfo.jankyFrames} (${run.gfxinfo.jankyPercent}%)`,
      run.gfxinfo.p95Ms == null ? "" : `${run.gfxinfo.p95Ms}ms`,
      run.gfxinfo.p99Ms == null ? "" : `${run.gfxinfo.p99Ms}ms`,
      run.renderer.cameraLatencyP95Ms == null ? "" : `${run.renderer.cameraLatencyP95Ms}ms`,
      run.meminfo.totalPssKb ?? "",
      run.renderer.disposedObserved,
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
