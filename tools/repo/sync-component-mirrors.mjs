#!/usr/bin/env node
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const MIRROR_DEFINITIONS = Object.freeze([
  {
    hubPath: "contracts/api/internal-api-index.json",
    repository: "AquilaXk/easysubway-backend",
    sourcePath: "contracts/api/internal-api-index.json",
  },
  {
    hubPath: "contracts/api/journey-v3.openapi.yaml",
    repository: "AquilaXk/easysubway-backend",
    sourcePath: "contracts/api/journey-v3.openapi.yaml",
  },
  {
    hubPath: "contracts/api/realtime-api.openapi.yaml",
    repository: "AquilaXk/easysubway-backend",
    sourcePath: "contracts/api/realtime-api.openapi.yaml",
  },
  {
    hubPath: "contracts/api/report-api.openapi.yaml",
    repository: "AquilaXk/easysubway-backend",
    sourcePath: "contracts/api/report-api.openapi.yaml",
  },
  {
    hubPath: "contracts/api/train-api.openapi.yaml",
    repository: "AquilaXk/easysubway-backend",
    sourcePath: "contracts/api/train-api.openapi.yaml",
  },
  {
    hubPath: "tools/datapack/source-candidates.json",
    repository: "AquilaXk/easysubway-data",
    sourcePath: "tools/datapack/source-candidates.json",
  },
  {
    hubPath: "tools/datapack/source-operation.mjs",
    repository: "AquilaXk/easysubway-data",
    sourcePath: "tools/datapack/source-operation.mjs",
  },
]);

export async function defaultExecGh({ repository, path, ref }) {
  const ghBin = existsSync("/usr/bin/gh")
    ? "/usr/bin/gh"
    : (existsSync("/usr/local/bin/gh")
      ? "/usr/local/bin/gh"
      : (existsSync("/opt/homebrew/bin/gh") ? "/opt/homebrew/bin/gh" : "gh"));
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn(
      ghBin,
      [
        "api",
        "-H",
        "Accept: application/vnd.github.raw",
        `repos/${repository}/contents/${path}?ref=${ref}`,
      ],
      {
        env: { ...process.env, PATH: "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" },
        stdio: ["ignore", "pipe", "pipe"],
      },
    ); // NOSONAR
    const chunks = [];
    const errChunks = [];
    child.stdout.on("data", (chunk) => chunks.push(chunk));
    child.stderr.on("data", (chunk) => errChunks.push(chunk));
    child.on("error", rejectPromise);
    child.on("close", (code) => {
      if (code !== 0) {
        rejectPromise(
          new Error(
            `gh api exited with code ${code}: ${Buffer.concat(errChunks).toString("utf8")}`,
          ),
        );
      } else {
        resolvePromise(Buffer.concat(chunks));
      }
    });
  });
}

export function parseArgs(argv) {
  const options = {
    mode: null,
    refs: {},
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--check") {
      options.mode = "check";
    } else if (arg === "--check-remote") {
      options.mode = "check-remote";
    } else if (arg === "--write") {
      options.mode = "write";
    } else if (arg === "--ref") {
      i++;
      if (i >= argv.length) throw new Error("--ref requires <repo>=<commit>");
      const refArg = argv[i];
      const eqIdx = refArg.indexOf("=");
      if (eqIdx === -1) {
        throw new Error(
          `Invalid --ref format '${refArg}', expected <repo>=<commit>`,
        );
      }
      const repo = refArg.slice(0, eqIdx);
      const commit = refArg.slice(eqIdx + 1);
      if (!/^[0-9a-f]{40}$/.test(commit)) {
        throw new Error(`Commit must be 40-character hex SHA: '${commit}'`);
      }
      options.refs[repo] = commit;
    } else {
      throw new Error(`Unknown option '${arg}'`);
    }
  }
  if (!options.mode) {
    throw new Error("Must specify one of --check, --check-remote, or --write");
  }
  return options;
}

export function validateManifest(manifest) {
  const errors = [];
  if (!manifest || typeof manifest !== "object") {
    errors.push("매니페스트는 객체여야 한다");
    return errors;
  }
  if (manifest.schemaVersion !== 1) {
    errors.push("schemaVersion은 1이어야 한다");
  }
  if (!Array.isArray(manifest.mirrors)) {
    errors.push("mirrors는 배열이어야 한다");
    return errors;
  }
  const seenPaths = new Set();
  let prevPath = "";
  for (let i = 0; i < manifest.mirrors.length; i++) {
    const m = manifest.mirrors[i];
    if (!m || typeof m !== "object") {
      errors.push(`mirrors[${i}]는 객체여야 한다`);
      continue;
    }
    if (typeof m.hubPath !== "string" || !m.hubPath) {
      errors.push(`mirrors[${i}].hubPath 누락`);
    } else {
      if (seenPaths.has(m.hubPath)) {
        errors.push(`mirrors[${i}].hubPath 중복: ${m.hubPath}`);
      }
      seenPaths.add(m.hubPath);
      if (m.hubPath.localeCompare(prevPath, "en") < 0) {
        errors.push(
          `mirrors는 hubPath 기준 오름차순 정렬되어야 한다 (${prevPath} > ${m.hubPath})`,
        );
      }
      prevPath = m.hubPath;
    }
    if (typeof m.repository !== "string" || !m.repository) {
      errors.push(`mirrors[${i}].repository 누락`);
    }
    if (typeof m.sourcePath !== "string" || !m.sourcePath) {
      errors.push(`mirrors[${i}].sourcePath 누락`);
    }
    if (
      typeof m.sourceCommit !== "string" ||
      !/^[0-9a-f]{40}$/.test(m.sourceCommit)
    ) {
      errors.push(
        `mirrors[${i}].sourceCommit은 40자 SHA여야 한다: ${m.sourceCommit}`,
      );
    }
    if (typeof m.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(m.sha256)) {
      errors.push(
        `mirrors[${i}].sha256은 64자 16진수여야 한다: ${m.sha256}`,
      );
    }
  }
  return errors;
}

export async function checkMirrors({
  rootDir = process.cwd(),
  manifest,
  manifestPath,
}) {
  if (!manifest) {
    const mPath =
      manifestPath ||
      join(rootDir, "contracts/api/component-mirror-manifest.json");
    const text = await readFile(mPath, "utf8");
    manifest = JSON.parse(text);
  }
  const validationErrors = validateManifest(manifest);
  if (validationErrors.length > 0) {
    return { ok: false, errors: validationErrors, drifted: [] };
  }
  const drifted = [];
  for (const mirror of manifest.mirrors) {
    const fullPath = join(rootDir, mirror.hubPath);
    let bytes;
    try {
      bytes = await readFile(fullPath);
    } catch {
      drifted.push({
        hubPath: mirror.hubPath,
        expected: mirror.sha256,
        actual: null,
        error: "FILE_MISSING",
      });
      continue;
    }
    const actualSha = createHash("sha256").update(bytes).digest("hex");
    if (actualSha !== mirror.sha256) {
      drifted.push({
        hubPath: mirror.hubPath,
        expected: mirror.sha256,
        actual: actualSha,
        error: "SHA_MISMATCH",
      });
    }
  }
  return { ok: drifted.length === 0, drifted, errors: [] };
}

export async function checkRemoteMirrors({
  rootDir = process.cwd(),
  manifest,
  manifestPath,
  execGh = defaultExecGh,
}) {
  if (!manifest) {
    const mPath =
      manifestPath ||
      join(rootDir, "contracts/api/component-mirror-manifest.json");
    const text = await readFile(mPath, "utf8");
    manifest = JSON.parse(text);
  }
  const validationErrors = validateManifest(manifest);
  if (validationErrors.length > 0) {
    return { ok: false, errors: validationErrors, drifted: [] };
  }
  const drifted = [];
  for (const mirror of manifest.mirrors) {
    let remoteBytes;
    try {
      remoteBytes = await execGh({
        repository: mirror.repository,
        path: mirror.sourcePath,
        ref: "main",
      });
    } catch (err) {
      drifted.push({
        hubPath: mirror.hubPath,
        expected: mirror.sha256,
        actual: null,
        error: err.message,
      });
      continue;
    }
    const remoteSha = createHash("sha256").update(remoteBytes).digest("hex");
    if (remoteSha !== mirror.sha256) {
      drifted.push({
        hubPath: mirror.hubPath,
        expected: mirror.sha256,
        actual: remoteSha,
        error: "REMOTE_DRIFT",
      });
    }
  }
  return { ok: drifted.length === 0, drifted, errors: [] };
}

export async function writeMirrors({
  rootDir = process.cwd(),
  refs,
  execGh = defaultExecGh,
  definitions = MIRROR_DEFINITIONS,
}) {
  const mirrors = [];
  for (const def of definitions) {
    const commit = refs[def.repository];
    if (!commit || !/^[0-9a-f]{40}$/.test(commit)) {
      throw new Error(
        `Repository ${def.repository} requires a 40-character commit SHA in refs`,
      );
    }
    const bytes = await execGh({
      repository: def.repository,
      path: def.sourcePath,
      ref: commit,
    });
    const targetFile = join(rootDir, def.hubPath);
    await mkdir(dirname(targetFile), { recursive: true });
    await writeFile(targetFile, bytes);
    const hash = createHash("sha256").update(bytes).digest("hex");
    mirrors.push({
      hubPath: def.hubPath,
      repository: def.repository,
      sourcePath: def.sourcePath,
      sourceCommit: commit,
      sha256: hash,
    });
  }
  mirrors.sort((a, b) => a.hubPath.localeCompare(b.hubPath, "en"));
  const manifest = {
    schemaVersion: 1,
    mirrors,
  };
  const manifestPath = join(
    rootDir,
    "contracts/api/component-mirror-manifest.json",
  );
  await mkdir(dirname(manifestPath), { recursive: true });
  await writeFile(
    manifestPath,
    `${JSON.stringify(manifest, null, 2)}\n`,
    "utf8",
  );
  return manifest;
}

export async function runCli(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

  if (options.mode === "check") {
    const result = await checkMirrors({ rootDir });
    if (!result.ok) {
      const driftSummary = result.drifted
        .map((d) => `  - ${d.hubPath} (${d.error}: expected ${d.expected}, got ${d.actual})`)
        .join("\n");
      process.stderr.write(`❌ Component mirror drift detected:\n${driftSummary}\n`);
      if (result.errors?.length) {
        const errorSummary = result.errors.map((e) => `  - ${e}`).join("\n");
        process.stderr.write(`  Validation errors:\n${errorSummary}\n`);
      }
      return 1;
    }
    process.stdout.write("✅ Component contract mirrors are up to date.\n");
    return 0;
  }

  if (options.mode === "check-remote") {
    const result = await checkRemoteMirrors({ rootDir });
    if (!result.ok) {
      const remoteDriftSummary = result.drifted
        .map((d) => `  - ${d.hubPath} (${d.error}: manifest=${d.expected}, remote=${d.actual})`)
        .join("\n");
      process.stderr.write(`❌ Remote component mirror drift detected on main:\n${remoteDriftSummary}\n`);
      return 1;
    }
    process.stdout.write("✅ Remote component contract mirrors match main.\n");
    return 0;
  }

  if (options.mode === "write") {
    const manifest = await writeMirrors({ rootDir, refs: options.refs });
    process.stdout.write(
      `✅ Updated ${manifest.mirrors.length} mirrors in manifest and hub workspace.\n`,
    );
    return 0;
  }

  return 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const code = await runCli();
    process.exit(code);
  } catch (err) {
    process.stderr.write(`❌ Error: ${err.message}\n`);
    process.exit(1);
  }
}
