#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";

import { DOCUMENTATION_REPOSITORIES } from "./documentation-inventory.mjs";
import { validateSchema } from "./lib/json-schema-lite.mjs";
import { codepointCompare } from "../lib/codepoint-compare.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";
import { validateDocumentationInventoryAuditScope } from "../repo/audit-documentation-inventory.mjs";

const CATALOG_SCHEMA_PATH = new URL(
  "../../contracts/documentation/documentation-system-catalog.schema.json",
  import.meta.url,
);
const SHA = /^[0-9a-f]{40}$/;
const SAFE_PATH = /^(?!\/)(?!.*(?:^|\/)\.{1,2}(?:\/|$))(?!.*[?#])[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const FIXED_REPOSITORIES = new Set(DOCUMENTATION_REPOSITORIES);
const GIT_ENV = Object.freeze({
  GIT_ATTR_NOSYSTEM: "1",
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CONFIG_SYSTEM: "/dev/null",
  GIT_LFS_SKIP_SMUDGE: "1",
  GIT_TERMINAL_PROMPT: "0",
});
const GIT_UNSET = Object.freeze([
  "GH_TOKEN",
  "GITHUB_TOKEN",
  "GIT_ASKPASS",
  "GIT_CONFIG_COUNT",
  "GIT_CONFIG_PARAMETERS",
  "GIT_DIR",
  "GIT_INDEX_FILE",
  "GIT_NAMESPACE",
  "GIT_OBJECT_DIRECTORY",
  "GIT_QUARANTINE_PATH",
  "GIT_SSH_COMMAND",
  "GIT_WORK_TREE",
  "SSH_AUTH_SOCK",
]);

function fail(code) {
  throw new Error(code);
}

function readJson(path) {
  try {
    const absolute = resolve(path);
    const stat = lstatSync(absolute);
    if (!stat.isFile() || stat.isSymbolicLink()) fail("DOCUMENTATION_FRAGMENT_WORKSPACE_INPUT_INVALID");
    return JSON.parse(readFileSync(absolute, "utf8"));
  } catch (error) {
    if (error?.message === "DOCUMENTATION_FRAGMENT_WORKSPACE_INPUT_INVALID") throw error;
    fail("DOCUMENTATION_FRAGMENT_WORKSPACE_INPUT_INVALID");
  }
}

function gitEnvironment() {
  const env = { ...process.env, ...GIT_ENV };
  for (const key of GIT_UNSET) delete env[key];
  return env;
}

function git(root, args, { runGit = execFileSync, encoding = "utf8" } = {}) {
  return runGit("/usr/bin/git", ["-C", root, ...args], {
    encoding,
    env: gitEnvironment(),
    shell: false,
    stdio: ["ignore", "pipe", "pipe"],
  });
}

export function cloneDocumentationRepository({ repository, defaultBranch, destination }, {
  runGit = execFileSync,
} = {}) {
  if (!FIXED_REPOSITORIES.has(repository) || defaultBranch !== "main" || !isAbsolute(destination)) {
    fail("DOCUMENTATION_FRAGMENT_WORKSPACE_INPUT_INVALID");
  }
  runGit("/usr/bin/git", [
    "clone",
    "--no-checkout",
    "--single-branch",
    "--branch",
    defaultBranch,
    "--no-tags",
    `https://github.com/${repository}.git`,
    destination,
  ], {
    env: gitEnvironment(),
    shell: false,
    stdio: ["ignore", "ignore", "ignore"],
  });
}

function validateInputs(catalog, scope) {
  const errors = [];
  const catalogSchema = JSON.parse(readFileSync(CATALOG_SCHEMA_PATH, "utf8"));
  const schemaResult = validateSchema(catalogSchema, catalog);
  errors.push(...schemaResult.errors);
  if (schemaResult.ok) {
    const expected = [...DOCUMENTATION_REPOSITORIES].sort(codepointCompare);
    const actual = catalog.repositories.map(({ repository }) => repository);
    if (JSON.stringify(actual) !== JSON.stringify(expected)) errors.push("repository inventory mismatch");
    for (const entry of catalog.repositories) {
      if (entry.status === "PROPOSED" && entry.fragment !== null) errors.push("proposed fragment mismatch");
      if (entry.status === "ACTIVE" && entry.fragment === null) errors.push("active fragment missing");
    }
  }
  validateDocumentationInventoryAuditScope(scope, errors);
  if (errors.length > 0) fail("DOCUMENTATION_FRAGMENT_WORKSPACE_INPUT_INVALID");

  const scopeByRepository = new Map(scope.repositories.map((entry) => [entry.repository, entry]));
  const active = catalog.repositories.filter(({ status }) => status === "ACTIVE");
  for (const entry of active) {
    const expected = scopeByRepository.get(entry.repository);
    if (expected == null || expected.defaultBranch !== "main" || expected.requiredStatus !== "ACTIVE"
        || !SAFE_PATH.test(expected.fragmentPath) || entry.fragment?.path !== expected.fragmentPath
        || !SHA.test(entry.fragment?.gitSha ?? "")) {
      fail("DOCUMENTATION_FRAGMENT_WORKSPACE_INPUT_INVALID");
    }
  }
  return active.map((entry) => ({ entry, scope: scopeByRepository.get(entry.repository) }));
}

function assertCreateOnlyPaths(rootDirectory, outputPath) {
  if (!isAbsolute(rootDirectory) || !isAbsolute(outputPath)
      || resolve(rootDirectory) !== rootDirectory || resolve(outputPath) !== outputPath
      || existsSync(rootDirectory) || existsSync(outputPath)) {
    fail("DOCUMENTATION_FRAGMENT_WORKSPACE_OUTPUT_EXISTS");
  }
  for (const parent of [dirname(rootDirectory), dirname(outputPath)]) {
    try {
      if (lstatSync(parent).isSymbolicLink()) {
        fail("DOCUMENTATION_FRAGMENT_WORKSPACE_OUTPUT_EXISTS");
      }
    } catch (error) {
      if (error?.message === "DOCUMENTATION_FRAGMENT_WORKSPACE_OUTPUT_EXISTS") throw error;
      fail("DOCUMENTATION_FRAGMENT_WORKSPACE_OUTPUT_EXISTS");
    }
  }
}

function validatePreparedRepository(root, entry, scope) {
  try {
    if (lstatSync(root).isSymbolicLink() || realpathSync(root) !== root) throw new Error();
    if (git(root, ["rev-parse", "--show-toplevel"]).trim() !== root) throw new Error();
    if (git(root, ["rev-parse", "--show-object-format=storage"]).trim() !== "sha1") throw new Error();
    if (git(root, ["rev-parse", "--verify", `${entry.fragment.gitSha}^{commit}`]).trim()
        !== entry.fragment.gitSha) throw new Error();
    git(root, ["merge-base", "--is-ancestor", entry.fragment.gitSha, `refs/remotes/origin/${scope.defaultBranch}`]);
  } catch {
    fail("DOCUMENTATION_FRAGMENT_WORKSPACE_LOCATOR_INVALID");
  }
}

export function prepareDocumentationFragmentWorkspace({
  catalogPath,
  scopePath,
  rootDirectory,
  outputPath,
}, {
  cloneRepository = cloneDocumentationRepository,
} = {}) {
  const catalog = readJson(catalogPath);
  const scope = readJson(scopePath);
  const active = validateInputs(catalog, scope);
  assertCreateOnlyPaths(rootDirectory, outputPath);
  mkdirSync(rootDirectory, { mode: 0o700 });
  const canonicalRootDirectory = realpathSync(rootDirectory);

  const repositories = [];
  for (const { entry, scope: scopeEntry } of active) {
    const destination = join(canonicalRootDirectory, entry.repository.slice(entry.repository.indexOf("/") + 1));
    try {
      cloneRepository({
        repository: entry.repository,
        defaultBranch: scopeEntry.defaultBranch,
        destination,
      });
    } catch (error) {
      if (/^DOCUMENTATION_FRAGMENT_WORKSPACE_[A-Z_]+$/.test(error?.message ?? "")) throw error;
      fail("DOCUMENTATION_FRAGMENT_WORKSPACE_CLONE_FAILED");
    }
    validatePreparedRepository(destination, entry, scopeEntry);
    repositories.push({ repository: entry.repository, root: destination });
  }

  const workspace = { schemaVersion: 1, repositories };
  try {
    writeFileSync(outputPath, `${JSON.stringify(workspace)}\n`, { encoding: "utf8", flag: "wx", mode: 0o600 });
  } catch {
    fail("DOCUMENTATION_FRAGMENT_WORKSPACE_OUTPUT_EXISTS");
  }
  return workspace;
}

function parseArguments(args) {
  if (args.length !== 8 || args[0] !== "--catalog" || args[2] !== "--scope"
      || args[4] !== "--root" || args[6] !== "--output"
      || args.some((value, index) => index % 2 === 1 && value.trim() === "")) {
    fail("DOCUMENTATION_FRAGMENT_WORKSPACE_USAGE");
  }
  return {
    catalogPath: args[1],
    scopePath: args[3],
    rootDirectory: args[5],
    outputPath: args[7],
  };
}

if (isMainModule(import.meta.url)) {
  try {
    const workspace = prepareDocumentationFragmentWorkspace(parseArguments(process.argv.slice(2)));
    process.stdout.write(`${JSON.stringify({
      status: "COMPLETE",
      activeRepositoryCount: workspace.repositories.length,
    })}\n`);
  } catch (error) {
    const code = /^DOCUMENTATION_FRAGMENT_WORKSPACE_[A-Z_]+$/.test(error?.message ?? "")
      ? error.message
      : "DOCUMENTATION_FRAGMENT_WORKSPACE_FAILED";
    process.stderr.write(`${code}\n`);
    process.exitCode = 1;
  }
}
