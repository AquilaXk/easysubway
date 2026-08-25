import { createHash } from "node:crypto";
import { constants } from "node:fs";
import { lstat, open, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { governanceInventoryPaths } from "./validate-system-release-manifest.mjs";

const outputPath = "contracts/release/system-release-governance-inventory.json";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const safePath = (value) => typeof value === "string" && value.length > 0 && !value.includes("\\")
  && !path.posix.isAbsolute(value) && path.posix.normalize(value) === value
  && value.split("/").every((part) => part !== "" && part !== "." && part !== "..");

function validateClosedPathList() {
  if (!Array.isArray(governanceInventoryPaths) || governanceInventoryPaths.length === 0) {
    throw new Error("closed release governance path list is missing");
  }
  const seen = new Set();
  for (const entryPath of governanceInventoryPaths) {
    if (!safePath(entryPath) || seen.has(entryPath)) {
      throw new Error("closed release governance path list contains an unsafe or duplicate path");
    }
    seen.add(entryPath);
  }
  if (governanceInventoryPaths.join("\n") !== [...governanceInventoryPaths].sort().join("\n")) {
    throw new Error("closed release governance path list is not canonical");
  }
}

async function readRegularFile(repositoryRoot, relativePath) {
  if (!safePath(relativePath)) throw new Error("governance input path is unsafe");
  const root = path.resolve(repositoryRoot);
  const rootStat = await lstat(root);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) throw new Error("repositoryRoot must be a regular directory");
  let source = root;
  const parts = relativePath.split("/");
  for (const [index, part] of parts.entries()) {
    source = path.join(source, part);
    const stat = await lstat(source);
    if (stat.isSymbolicLink()) throw new Error("governance input must not contain a symlink");
    if (index === parts.length - 1 && !stat.isFile()) throw new Error("governance input must be a regular file");
  }
  const handle = await open(source, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    if (!stat.isFile()) throw new Error("governance input must be a regular file");
    return handle.readFile();
  } finally {
    await handle.close();
  }
}

export async function buildSystemReleaseGovernanceInventory({ repositoryRoot }) {
  if (typeof repositoryRoot !== "string") throw new Error("repositoryRoot is required");
  validateClosedPathList();
  const root = path.resolve(repositoryRoot);
  const files = await Promise.all(governanceInventoryPaths.map(async (entryPath) => ({
    path: entryPath,
    sha256: sha256(await readRegularFile(root, entryPath)),
  })));
  return Buffer.from(`${JSON.stringify({
    schemaVersion: 1,
    artifactKind: "system-release-governance-inventory",
    files,
  }, null, 2)}\n`, "utf8");
}

async function main() {
  const [mode] = process.argv.slice(2);
  if (!["--check", "--write"].includes(mode) || process.argv.length !== 3) {
    throw new Error("usage: --check | --write");
  }
  const root = process.cwd();
  const generated = await buildSystemReleaseGovernanceInventory({ repositoryRoot: root });
  if (mode === "--check") {
    const existing = await readRegularFile(root, outputPath);
    if (!generated.equals(existing)) throw new Error("release governance inventory is not generated from current closed inputs");
    return;
  }
  await writeFile(path.resolve(root, outputPath), generated);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
}
