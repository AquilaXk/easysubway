import { createHash } from "node:crypto";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isSafeRelativePath, readRegularFile } from "../lib/read-regular-file.mjs";
import { governanceInventoryPaths } from "./validate-system-release-manifest.mjs";

const outputPath = "contracts/release/system-release-governance-inventory.json";

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
function validateClosedPathList() {
  if (!Array.isArray(governanceInventoryPaths) || governanceInventoryPaths.length === 0) {
    throw new Error("closed release governance path list is missing");
  }
  const seen = new Set();
  for (const entryPath of governanceInventoryPaths) {
    if (!isSafeRelativePath(entryPath) || seen.has(entryPath)) {
      throw new Error("closed release governance path list contains an unsafe or duplicate path");
    }
    seen.add(entryPath);
  }
  if (governanceInventoryPaths.join("\n") !== [...governanceInventoryPaths].sort(codepointCompare).join("\n")) {
    throw new Error("closed release governance path list is not canonical");
  }
}

export async function buildSystemReleaseGovernanceInventory({ repositoryRoot }) {
  if (typeof repositoryRoot !== "string") throw new Error("repositoryRoot is required");
  validateClosedPathList();
  const root = path.resolve(repositoryRoot);
  const files = await Promise.all(governanceInventoryPaths.map(async (entryPath) => ({
    path: entryPath,
    sha256: sha256(await readRegularFile(root, entryPath, { label: "governance input" })),
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
    const existing = await readRegularFile(root, outputPath, { label: "release governance inventory" });
    if (!generated.equals(existing)) throw new Error("release governance inventory is not generated from current closed inputs");
    return;
  }
  await writeFile(path.resolve(root, outputPath), generated);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    await main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
