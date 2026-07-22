#!/usr/bin/env node
/**
 * Flutter `coverage/lcov.info`에서 생성 코드·노이즈 경로를 제거한다.
 * lcov 바이너리 없이 동작하며, Sonar `sonar.dart.lcov.reportPaths` 입력으로 쓴다.
 */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const DEFAULT_EXCLUDES = [
  /(^|\/)[^/]+\.g\.dart$/,
  /(^|\/)[^/]+\.freezed\.dart$/,
  /(^|\/)generated\//,
  /\/\.dart_tool\//,
];

function parseArgs(argv) {
  const args = { input: null, output: null, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === "--help" || token === "-h") {
      args.help = true;
    } else if (token === "--input") {
      args.input = argv[++i];
    } else if (token === "--output") {
      args.output = argv[++i];
    } else if (!args.input) {
      args.input = token;
    } else if (!args.output) {
      args.output = token;
    }
  }
  return args;
}

function shouldExcludeSource(sourcePath, patterns) {
  const normalized = sourcePath.replaceAll("\\", "/");
  return patterns.some((pattern) => pattern.test(normalized));
}

export function filterLcov(content, patterns = DEFAULT_EXCLUDES) {
  const lines = content.split(/\r?\n/);
  const kept = [];
  let skipping = false;
  let keptFiles = 0;
  let removedFiles = 0;

  for (const line of lines) {
    if (line.startsWith("SF:")) {
      const sourcePath = line.slice(3);
      skipping = shouldExcludeSource(sourcePath, patterns);
      if (skipping) {
        removedFiles += 1;
        continue;
      }
      keptFiles += 1;
      kept.push(line);
      continue;
    }
    if (skipping) {
      if (line === "end_of_record") {
        skipping = false;
      }
      continue;
    }
    kept.push(line);
  }

  while (kept.length > 0 && kept[kept.length - 1] === "") {
    kept.pop();
  }
  if (kept.length > 0) {
    kept.push("");
  }

  return {
    content: kept.join("\n"),
    keptFiles,
    removedFiles,
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || !args.input) {
    process.stdout.write(
      "usage: node tools/ci/filter-mobile-lcov.mjs --input <lcov.info> [--output <lcov.info>]\n",
    );
    process.exit(args.help ? 0 : 1);
  }

  const inputPath = path.resolve(args.input);
  const outputPath = path.resolve(args.output ?? args.input);
  const raw = readFileSync(inputPath, "utf8");
  const filtered = filterLcov(raw);
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, filtered.content, "utf8");
  process.stdout.write(
    `filter-mobile-lcov: kept=${filtered.keptFiles} removed=${filtered.removedFiles} output=${outputPath}\n`,
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main();
}
