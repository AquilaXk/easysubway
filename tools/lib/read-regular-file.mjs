import { constants } from "node:fs";
import { randomUUID } from "node:crypto";
import { lstat, open, rename, unlink } from "node:fs/promises";
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

export async function replaceRegularFileAtomically(repositoryRoot, relativePath, bytes, { label = "output" } = {}) {
  if (!isSafeRelativePath(relativePath)) throw new Error(`${label} path is unsafe`);
  const root = path.resolve(repositoryRoot);
  const rootStat = await lstat(root);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) throw new Error("repositoryRoot must be a regular directory");
  let target = root;
  const parts = relativePath.split("/");
  for (const [index, part] of parts.entries()) {
    target = path.join(target, part);
    try {
      const stat = await lstat(target);
      if (stat.isSymbolicLink()) throw new Error(`${label} must not contain a symlink`);
      if (index < parts.length - 1 && !stat.isDirectory()) throw new Error(`${label} parent must be a regular directory`);
      if (index === parts.length - 1 && !stat.isFile()) throw new Error(`${label} must be a regular file`);
    } catch (error) {
      if (error.code !== "ENOENT" || index < parts.length - 1) throw error;
    }
  }

  const temporary = path.join(path.dirname(target), `.${path.basename(target)}.${randomUUID()}.tmp`);
  let handle;
  try {
    handle = await open(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o666);
    await handle.writeFile(bytes);
    await handle.sync();
    await handle.close();
    handle = undefined;
    await rename(temporary, target);
  } catch (error) {
    await handle?.close();
    await unlink(temporary).catch((cleanupError) => {
      if (cleanupError.code !== "ENOENT") throw cleanupError;
    });
    throw error;
  }
}
