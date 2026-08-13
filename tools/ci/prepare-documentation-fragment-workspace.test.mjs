import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

import {
  cloneDocumentationRepository,
  prepareDocumentationFragmentWorkspace,
} from "./prepare-documentation-fragment-workspace.mjs";

const MOBILE = "AquilaXk/easysubway-mobile";
const FRAGMENT_PATH = "contracts/documentation/documentation-fragment.json";
const LAST_VERIFIED_AT = "2026-08-13T07:33:23.000Z";
const EVIDENCE = [
  "https://github.com/AquilaXk/easysubway-mobile/issues/225",
  "https://github.com/AquilaXk/easysubway/pull/2854",
];

function git(root, args) {
  return execFileSync("/usr/bin/git", ["-C", root, ...args], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
  }).trim();
}

function createRepository(directory) {
  const root = join(directory, "source-repository");
  mkdirSync(root);
  execFileSync("/usr/bin/git", ["init", "--initial-branch=main", root], { stdio: "ignore" });
  git(root, ["config", "user.email", "test@example.com"]);
  git(root, ["config", "user.name", "Test"]);
  writeFileSync(join(root, "resource.txt"), "source\n");
  git(root, ["add", "resource.txt"]);
  git(root, ["commit", "-m", "source"]);
  const sourceSha = git(root, ["rev-parse", "HEAD"]);
  mkdirSync(join(root, "contracts/documentation"), { recursive: true });
  writeFileSync(join(root, FRAGMENT_PATH), "{}\n");
  git(root, ["add", FRAGMENT_PATH]);
  git(root, ["commit", "-m", "fragment"]);
  const outerSha = git(root, ["rev-parse", "HEAD"]);
  git(root, ["branch", "side", sourceSha]);
  git(root, ["switch", "side"]);
  writeFileSync(join(root, "side.txt"), "side\n");
  git(root, ["add", "side.txt"]);
  git(root, ["commit", "-m", "side"]);
  const sideSha = git(root, ["rev-parse", "HEAD"]);
  git(root, ["switch", "main"]);
  git(root, ["update-ref", "refs/remotes/origin/main", outerSha]);
  return { root, sourceSha, outerSha, sideSha };
}

function writeInputs(directory, outerSha, mutate = () => {}) {
  const catalog = JSON.parse(readFileSync("contracts/documentation/documentation-system-catalog.json", "utf8"));
  const scope = JSON.parse(readFileSync("contracts/documentation/documentation-inventory-audit-scope.json", "utf8"));
  const mobile = catalog.repositories.find(({ repository }) => repository === MOBILE);
  mobile.status = "ACTIVE";
  mobile.fragment = {
    gitSha: outerSha,
    path: FRAGMENT_PATH,
    blobSha: "a".repeat(40),
    lastVerifiedAt: LAST_VERIFIED_AT,
    verificationEvidence: EVIDENCE,
  };
  mutate({ catalog, scope, mobile });
  const catalogPath = join(directory, "catalog.json");
  const scopePath = join(directory, "scope.json");
  writeFileSync(catalogPath, `${JSON.stringify(catalog)}\n`);
  writeFileSync(scopePath, `${JSON.stringify(scope)}\n`);
  return { catalogPath, scopePath };
}

function copiedClone(source) {
  return ({ destination }) => cpSync(source, destination, { recursive: true });
}

test("documentation fragment workspace preparer creates one exact ACTIVE mapping", () => {
  const directory = mkdtempSync(join(tmpdir(), "documentation-fragment-workspace-"));
  try {
    const repository = createRepository(directory);
    const inputs = writeInputs(directory, repository.outerSha);
    const rootDirectory = join(directory, "prepared");
    const outputPath = join(directory, "workspace.json");
    const result = prepareDocumentationFragmentWorkspace({
      ...inputs,
      rootDirectory,
      outputPath,
    }, { cloneRepository: copiedClone(repository.root) });

    assert.deepEqual(result, {
      schemaVersion: 1,
      repositories: [{ repository: MOBILE, root: resolve(realpathSync(rootDirectory), "easysubway-mobile") }],
    });
    assert.deepEqual(JSON.parse(readFileSync(outputPath, "utf8")), result);
    assert.equal(git(result.repositories[0].root, ["rev-parse", "--verify", `${repository.outerSha}^{commit}`]), repository.outerSha);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("documentation fragment workspace preparer rejects unowned input and non-ancestor locator", () => {
  const cases = [
    ["repository", ({ mobile }) => { mobile.repository = "AquilaXk/unowned"; }],
    ["path", ({ mobile }) => { mobile.fragment.path = "contracts/other.json"; }],
    ["branch", ({ scope }) => { scope.repositories.find(({ repository }) => repository === MOBILE).defaultBranch = "release"; }],
  ];
  for (const [name, mutate] of cases) {
    const directory = mkdtempSync(join(tmpdir(), `documentation-fragment-${name}-`));
    try {
      const repository = createRepository(directory);
      const inputs = writeInputs(directory, repository.outerSha, mutate);
      assert.throws(() => prepareDocumentationFragmentWorkspace({
        ...inputs,
        rootDirectory: join(directory, "prepared"),
        outputPath: join(directory, "workspace.json"),
      }, { cloneRepository: copiedClone(repository.root) }), /DOCUMENTATION_FRAGMENT_WORKSPACE_INPUT_INVALID/);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }

  const directory = mkdtempSync(join(tmpdir(), "documentation-fragment-ancestor-"));
  try {
    const repository = createRepository(directory);
    const inputs = writeInputs(directory, repository.sideSha);
    assert.throws(() => prepareDocumentationFragmentWorkspace({
      ...inputs,
      rootDirectory: join(directory, "prepared"),
      outputPath: join(directory, "workspace.json"),
    }, { cloneRepository: copiedClone(repository.root) }), /DOCUMENTATION_FRAGMENT_WORKSPACE_LOCATOR_INVALID/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("documentation fragment workspace preparer is create-only and rejects symlink roots", () => {
  for (const kind of ["root", "output", "symlink"]) {
    const directory = mkdtempSync(join(tmpdir(), `documentation-fragment-${kind}-`));
    try {
      const repository = createRepository(directory);
      const inputs = writeInputs(directory, repository.outerSha);
      const rootDirectory = join(directory, "prepared");
      const outputPath = join(directory, "workspace.json");
      if (kind === "root") mkdirSync(rootDirectory);
      if (kind === "output") writeFileSync(outputPath, "existing\n");
      if (kind === "symlink") symlinkSync(repository.root, rootDirectory);
      assert.throws(() => prepareDocumentationFragmentWorkspace({
        ...inputs,
        rootDirectory,
        outputPath,
      }, { cloneRepository: copiedClone(repository.root) }), /DOCUMENTATION_FRAGMENT_WORKSPACE_OUTPUT_EXISTS/);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  }
});

test("documentation repository clone uses fixed public no-checkout single-branch arguments", () => {
  const calls = [];
  cloneDocumentationRepository({
    repository: MOBILE,
    defaultBranch: "main",
    destination: "/tmp/documentation-fragments/easysubway-mobile",
  }, {
    runGit: (executable, arguments_, options) => calls.push({ executable, arguments_, options }),
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].executable, "/usr/bin/git");
  assert.deepEqual(calls[0].arguments_, [
    "clone", "--no-checkout", "--single-branch", "--branch", "main", "--no-tags",
    "https://github.com/AquilaXk/easysubway-mobile.git",
    "/tmp/documentation-fragments/easysubway-mobile",
  ]);
  assert.equal(calls[0].options.shell, false);
  assert.deepEqual(calls[0].options.stdio, ["ignore", "ignore", "ignore"]);
  assert.equal(calls[0].options.env.GIT_TERMINAL_PROMPT, "0");
});
