import { constants } from "node:fs";
import { lstat, open } from "node:fs/promises";
import path from "node:path";

export const isSafeRelativePath = (value) => typeof value === "string" && value.length > 0 && !value.includes("\\")
  && !path.posix.isAbsolute(value) && path.posix.normalize(value) === value
  && value.split("/").every((part) => part !== "" && part !== "." && part !== "..");

export async function readRegularFile(repositoryRoot, relativePath, { label = "input" } = {}) {
  if (!isSafeRelativePath(relativePath)) throw new Error(`${label} path is unsafe`);
  const root = path.resolve(repositoryRoot);
  const rootStat = await lstat(root);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) throw new Error("repositoryRoot must be a regular directory");
  let source = root;
  const parts = relativePath.split("/");
  for (const [index, part] of parts.entries()) {
    source = path.join(source, part);
    const stat = await lstat(source);
    if (stat.isSymbolicLink()) throw new Error(`${label} must not contain a symlink`);
    if (index === parts.length - 1 && !stat.isFile()) throw new Error(`${label} must be a regular file`);
  }
  const handle = await open(source, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    if (!stat.isFile()) throw new Error(`${label} must be a regular file`);
    return handle.readFile();
  } finally {
    await handle.close();
  }
}
