import assert from "node:assert/strict";
import test from "node:test";
import {
  parseArguments,
  preflightIssueTransfer,
  runMigration,
  validateMigrationLedger,
} from "./migrate-issue.mjs";
import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const SOURCE_REPOSITORY = "AquilaXk/easysubway";
const TARGET_REPOSITORY = "AquilaXk/easysubway-data";
const SOURCE_ISSUE = 2684;
const SOURCE_URL = `https://github.com/${SOURCE_REPOSITORY}/issues/${SOURCE_ISSUE}`;
const TARGET_URL = `https://github.com/${TARGET_REPOSITORY}/issues/7`;

function transferEntry(overrides = {}) {
  return {
    sourceIssue: SOURCE_ISSUE,
    sourceUrl: SOURCE_URL,
    title: "[Release Blocker][P0][Data] KRIC FACILITY 전체 station-line source admission",
    disposition: "TRANSFER",
    targetRepository: TARGET_REPOSITORY,
    executionApproval: "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1",
    targetUrl: null,
    transferredAt: null,
    ...overrides,
  };
}

function metadata({ url = SOURCE_URL, number = SOURCE_ISSUE, title, state = "OPEN", labels = ["release-blocker"], milestone = "P0", commentCount = 1, closingPullRequests = [] } = {}) {
  const repo = url.split("/issues/")[0].replace("https://github.com/", "");
  const connection = (nodes) => ({ totalCount: nodes.length, nodes });
  return { id: `I_${number}`, url, number, title: title ?? transferEntry().title, state, repository: { nameWithOwner: repo }, labels: connection(labels.map((name) => ({ name }))), milestone: milestone === null ? null : { title: milestone, dueOn: null }, comments: { totalCount: commentCount }, assignees: connection([]), projectItems: connection([]), parent: null, subIssues: connection([]), blocking: connection([]), blockedBy: connection([]), closedByPullRequestsReferences: connection(closingPullRequests) };
}

function fakeGh({ source = metadata(), target = metadata({ url: TARGET_URL, number: 7 }), targetResponses, targetExists = true, unassignableLogin, malformedAssigneeResponse, transferFailure = false, transferOutput = `${TARGET_URL}\n` } = {}) {
  const calls = [];
  let targetReadCount = 0;
  const execGh = async (args) => {
    calls.push(args);
    if (args[0] === "repo" && args[1] === "view") {
      if (!targetExists) throw new Error("target repository not found");
      return JSON.stringify({ nameWithOwner: TARGET_REPOSITORY });
    }
    if (args[0] === "issue" && args[1] === "transfer") {
      if (transferFailure) throw new Error("transfer response lost");
      return transferOutput;
    }
    if (args[0] === "api" && args.at(-1).includes("/assignees/")) {
      if (args.at(-1).endsWith(`/${encodeURIComponent(unassignableLogin)}`)) throw new Error("not assignable");
      if (malformedAssigneeResponse !== undefined) return malformedAssigneeResponse;
      return "";
    }
    if (args[0] === "api" && args.includes("--paginate")) {
      return JSON.stringify([args.at(-1).includes("labels") ? target.labels.nodes : (target.milestone === null ? [] : [{ title: target.milestone.title, due_on: target.milestone.dueOn }])]);
    }
    if (args[0] === "api" && args[1] === "graphql") {
      const issue = args.includes(`name=${TARGET_REPOSITORY.split("/")[1]}`)
        ? (targetResponses?.[Math.min(targetReadCount++, targetResponses.length - 1)] ?? target)
        : source;
      return JSON.stringify({ data: { repository: { issue } } });
    }
    throw new Error(`unexpected gh invocation: ${args.join(" ")}`);
  };
  return { calls, execGh };
}

function migrationContract() {
  return {
    ledger: JSON.parse(readFileSync("release/migrations/repository-split-issues.json", "utf8")),
    schema: JSON.parse(readFileSync("contracts/repository-split-issues.schema.json", "utf8")),
  };
}

function transferCalls(calls) {
  return calls.filter((args) => args[0] === "issue" && args[1] === "transfer");
}

function evidenceDirectory() {
  return mkdtempSync(join(tmpdir(), "issue-transfer-evidence-"));
}

test("argument parser accepts exactly one source issue and one mode", () => {
  assert.deepEqual(
    parseArguments(["--ledger", "ledger.json", "--source-issue", "2684", "--dry-run"]),
    { ledgerPath: "ledger.json", sourceIssue: 2684, mode: "dry-run", confirmations: { source: undefined, target: undefined }, evidenceDir: undefined },
  );
  assert.throws(
    () => parseArguments(["--ledger", "ledger.json", "--source-issue", "2684", "--source-issue", "2685", "--dry-run"]),
    /exactly one --source-issue/,
  );
});

test("execute argument parser requires one absolute empty non-symlink evidence directory", () => {
  const directory = evidenceDirectory();
  const symlinkTarget = evidenceDirectory();
  const symlink = `${directory}-link`;
  const oneCharacterDirectory = join(directory, "a");
  try {
    const base = ["--ledger", "ledger.json", "--source-issue", "2684", "--execute", "--confirm-source", "AquilaXk/easysubway#2684", "--confirm-target", TARGET_REPOSITORY];
    assert.throws(() => parseArguments(base), /--evidence-dir/);
    assert.throws(() => parseArguments([...base, "--evidence-dir", "relative"]), /absolute existing empty non-symlink/);
    mkdirSync(oneCharacterDirectory);
    assert.doesNotThrow(() => parseArguments([...base, "--evidence-dir", oneCharacterDirectory]));
    symlinkSync(symlinkTarget, symlink);
    assert.throws(() => parseArguments([...base, "--evidence-dir", symlink]), /absolute existing empty non-symlink/);
    assert.throws(() => parseArguments([...base, "--evidence-dir", `${symlink}/`]), /absolute existing empty non-symlink/);
    assert.throws(() => parseArguments([...base, "--evidence-dir", `${symlink}/.`]), /absolute existing empty non-symlink/);
  } finally {
    rmSync(symlink, { force: true });
    rmSync(directory, { recursive: true, force: true });
    rmSync(symlinkTarget, { recursive: true, force: true });
  }
});

test("preflight evidence write failure prevents transfer", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  const diskFull = new Error("disk full");
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh,
      writeEvidence: async () => { throw diskFull; },
    }), (error) => error.message.includes("preflight evidence") && error.cause === diskFull);
    assert.deepEqual(transferCalls(fake.calls), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("invalid execution confirmations leave the evidence directory empty", async (t) => {
  for (const [name, confirmations, error] of [
    ["source", { source: "AquilaXk/easysubway#1", target: TARGET_REPOSITORY }, /source confirmation/],
    ["target", { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: "AquilaXk/other" }, /target confirmation/],
  ]) await t.test(name, async () => {
    const directory = evidenceDirectory();
    const fake = fakeGh();
    const { ledger, schema } = migrationContract();
    Object.assign(ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE), transferEntry());
    try {
      await assert.rejects(() => runMigration({
        arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations, evidenceDir: directory }, ledger, schema, execGh: fake.execGh,
      }), error);
      assert.deepEqual(readdirSync(directory), []);
      assert.deepEqual(fake.calls, []);
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });
});

test("concurrent execute migrations claim one evidence directory before preflight", async () => {
  const directory = evidenceDirectory();
  const first = migrationContract();
  const second = migrationContract();
  const firstEntry = first.ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  const secondEntry = second.ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(firstEntry, transferEntry());
  Object.assign(secondEntry, transferEntry());
  const firstFake = fakeGh();
  const secondFake = fakeGh();
  const writeEvidence = async (context, filename, value) => {
    writeFileSync(join(context.canonicalPath, filename), `${JSON.stringify(value)}\n`);
  };
  try {
    const outcomes = await Promise.allSettled([
      runMigration({ arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory }, ledger: first.ledger, schema: first.schema, execGh: firstFake.execGh, writeEvidence }),
      runMigration({ arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory }, ledger: second.ledger, schema: second.schema, execGh: secondFake.execGh, writeEvidence }),
    ]);
    assert.equal(outcomes[0].status, "fulfilled");
    assert.equal(outcomes[1].status, "rejected");
    assert.match(outcomes[1].reason.message, /evidence-dir/);
    assert.equal(transferCalls([...firstFake.calls, ...secondFake.calls]).length, 1);
    assert.deepEqual(secondFake.calls, []);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("execute claim is a regular file", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  Object.assign(ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE), transferEntry());
  try {
    await runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory }, ledger, schema, execGh: fake.execGh,
    });
    assert.equal(lstatSync(join(directory, ".migration-claim")).isFile(), true);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("preexisting preflight destination is never clobbered or transferred", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  const destination = join(directory, `${SOURCE_ISSUE}-preflight.json`);
  const sentinel = "preserve this evidence\n";
  const original = fake.execGh;
  let seeded = false;
  const execGh = async (args) => {
    if (!seeded) {
      seeded = true;
      writeFileSync(destination, sentinel);
    }
    return original(args);
  };
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh,
    }), /preflight evidence could not be persisted/);
    assert.equal(readFileSync(destination, "utf8"), sentinel);
    assert.deepEqual(transferCalls(fake.calls), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("preflight evidence in-place rewrite prevents transfer", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh,
      afterPreflightPublish: ({ preflightEvidence }) => {
        const rewritten = JSON.parse(readFileSync(preflightEvidence.path, "utf8"));
        rewritten.sourceMetadata.commentCount = 99;
        writeFileSync(preflightEvidence.path, JSON.stringify(rewritten));
      },
    }), /durable preflight evidence/);
    assert.deepEqual(transferCalls(fake.calls), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("preflight evidence directory identity swap prevents transfer", async () => {
  const directory = evidenceDirectory();
  const movedDirectory = `${directory}-moved`;
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh,
      afterPreflightPublish: () => { renameSync(directory, movedDirectory); mkdirSync(directory); },
    }), /evidence directory identity changed/);
    assert.deepEqual(transferCalls(fake.calls), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
    rmSync(movedDirectory, { recursive: true, force: true });
  }
});

test("preflight evidence ABA without the original claim prevents transfer", async () => {
  const directory = evidenceDirectory();
  const movedDirectory = `${directory}-moved`;
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh,
      afterPreflightPublish: () => {
        renameSync(directory, movedDirectory);
        mkdirSync(directory);
        rmSync(join(movedDirectory, ".migration-claim"), { recursive: true });
        rmSync(directory, { recursive: true });
        renameSync(movedDirectory, directory);
      },
    }), /evidence directory identity changed/);
    assert.deepEqual(transferCalls(fake.calls), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
    rmSync(movedDirectory, { recursive: true, force: true });
  }
});

test("preflight evidence claim replacement prevents transfer", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  const claim = join(directory, ".migration-claim");
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh,
      afterPreflightPublish: () => { rmSync(claim, { recursive: true }); mkdirSync(claim); },
    }), /evidence directory identity changed/);
    assert.deepEqual(transferCalls(fake.calls), []);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("preflight evidence file identity or symlink swap prevents transfer", async (t) => {
  for (const replacement of ["file", "symlink"]) await t.test(replacement, async () => {
    const directory = evidenceDirectory();
    const fake = fakeGh();
    const { ledger, schema } = migrationContract();
    const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
    Object.assign(entry, transferEntry());
    const destination = join(directory, `${SOURCE_ISSUE}-preflight.json`);
    const original = join(directory, "published-preflight.json");
    try {
      await assert.rejects(() => runMigration({
        arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
        ledger, schema, execGh: fake.execGh,
        afterPreflightPublish: () => {
          renameSync(destination, original);
          if (replacement === "file") writeFileSync(destination, readFileSync(original));
          else symlinkSync(original, destination);
        },
      }), /durable preflight evidence/);
      assert.deepEqual(transferCalls(fake.calls), []);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
});

test("postflight fetch failure writes a sanitized exact artifact", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  const original = fake.execGh;
  const execGh = async (args) => {
    if (args[0] === "api" && args[1] === "graphql" && args.includes("name=easysubway-data")) throw new Error("target fetch failed");
    return original(args);
  };
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh, retryDelayMs: 0,
    }), /issue transfer completed but post-transfer verification failed/);
    assert.equal(readFileSync(join(directory, `${SOURCE_ISSUE}-postflight-1.json`), "utf8"), `${JSON.stringify({
      sourceIssue: SOURCE_ISSUE, sourceUrl: SOURCE_URL, attempt: 1,
      redirectIdentity: { repository: TARGET_REPOSITORY, number: 7, url: TARGET_URL },
      targetMetadata: null,
      mismatchedFields: ["target.metadata"],
      metadataDifferences: { "target.metadata": { expected: "normalized metadata", actual: "unavailable" } },
    })}\n`);
    assert.equal(transferCalls(fake.calls).length, 1);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("postflight evidence write failure is terminal after one transfer attempt", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  const diskFull = new Error("disk full");
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh, retryDelayMs: 0,
      writeEvidence: async (context, filename, value) => {
        if (filename.includes("postflight")) throw diskFull;
        writeFileSync(join(context.canonicalPath, filename), `${JSON.stringify(value)}\n`);
      },
    }), (error) => error.message.includes("postflight evidence could not be persisted")
      && error.cause?.postflightEvidencePersistenceFailed === true && error.cause.cause === diskFull);
    assert.equal(transferCalls(fake.calls).length, 1);
    assert.equal(fake.calls.filter((args) => args[0] === "api" && args[1] === "graphql" && args.includes("name=easysubway-data")).length, 1);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("postflight evidence writer mutation is terminal", async () => {
  const directory = evidenceDirectory();
  const target = { ...metadata({ url: TARGET_URL, number: 7 }), comments: { totalCount: 0 } };
  const fake = fakeGh({ target });
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh, retryDelayMs: 0,
      writeEvidence: async (context, filename, value) => {
        if (filename.includes("postflight")) value.attempt = 99;
        writeFileSync(join(context.canonicalPath, filename), `${JSON.stringify(value)}\n`);
      },
    }), /postflight evidence could not be persisted/);
    assert.equal(transferCalls(fake.calls).length, 1);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("postflight evidence directory replacement and restoration is terminal", async () => {
  const directory = evidenceDirectory();
  const movedDirectory = `${directory}-moved`;
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh, retryDelayMs: 0,
      writeEvidence: async (context, filename, value) => {
        if (!filename.includes("postflight")) return writeFileSync(join(context.canonicalPath, filename), `${JSON.stringify(value)}\n`);
        renameSync(directory, movedDirectory);
        mkdirSync(directory);
        writeFileSync(join(directory, filename), `${JSON.stringify(value)}\n`);
        rmSync(directory, { recursive: true });
        renameSync(movedDirectory, directory);
      },
    }), /postflight evidence could not be persisted/);
    assert.equal(transferCalls(fake.calls).length, 1);
  } finally {
    rmSync(directory, { recursive: true, force: true });
    rmSync(movedDirectory, { recursive: true, force: true });
  }
});

test("postflight evidence symlink replacement and restoration is terminal", async () => {
  const directory = evidenceDirectory();
  const movedDirectory = `${directory}-moved`;
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh, retryDelayMs: 0,
      writeEvidence: async (context, filename, value) => {
        if (!filename.includes("postflight")) return writeFileSync(join(context.canonicalPath, filename), `${JSON.stringify(value)}\n`);
        renameSync(directory, movedDirectory);
        symlinkSync(movedDirectory, directory);
        writeFileSync(join(directory, filename), `${JSON.stringify(value)}\n`);
        rmSync(join(movedDirectory, filename));
        rmSync(directory);
        renameSync(movedDirectory, directory);
      },
    }), /postflight evidence could not be persisted/);
    assert.equal(transferCalls(fake.calls).length, 1);
  } finally {
    rmSync(directory, { recursive: true, force: true });
    rmSync(movedDirectory, { recursive: true, force: true });
  }
});

test("postflight artifacts record propagation attempts, exact metadata differences, and redirect identity", async () => {
  const directory = evidenceDirectory();
  const target = metadata({ url: TARGET_URL, number: 7 });
  const stale = { ...target, comments: { totalCount: 0 } };
  const fake = fakeGh({ target, targetResponses: [stale, target] });
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  try {
    const result = await runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh, retryDelayMs: 0,
    });
    assert.equal(result.targetUrl, TARGET_URL);
    const firstAttempt = JSON.parse(readFileSync(join(directory, "2684-postflight-1.json"), "utf8"));
    assert.deepEqual(firstAttempt.mismatchedFields, ["commentCount"]);
    assert.deepEqual(firstAttempt.metadataDifferences.commentCount, { expected: 1, actual: 0 });
    assert.deepEqual(firstAttempt.redirectIdentity, { repository: TARGET_REPOSITORY, number: 7, url: TARGET_URL });
    assert.equal(JSON.parse(readFileSync(join(directory, "2684-postflight-2.json"), "utf8")).mismatchedFields.length, 0);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("shape-valid preflight metadata substitution prevents transfer", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger, schema, execGh: fake.execGh,
      writeEvidence: async (evidenceDir, filename, value) => {
        if (filename.endsWith("preflight.json")) value.sourceMetadata.commentCount = 99;
        writeFileSync(join(evidenceDir.canonicalPath, filename), `${JSON.stringify(value)}\n`);
      },
    }), /durable preflight evidence does not match preflight details/);
    assert.deepEqual(transferCalls(fake.calls), []);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test("preflight fails closed before transfer for unsafe ledger and GitHub metadata", async (t) => {
  const cases = [
    ["non-TRANSFER disposition", transferEntry({ disposition: "KEEP_HUB" })],
    ["missing execution approval", transferEntry({ executionApproval: null })],
    ["unapproved target", transferEntry({ targetRepository: "AquilaXk/other" })],
    ["missing target repository", transferEntry(), { targetExists: false }],
    ["stale source title", transferEntry(), { source: metadata({ title: "changed" }) }],
    ["closed source issue", transferEntry(), { source: metadata({ state: "CLOSED" }) }],
    ["open linked pull request", transferEntry(), { source: metadata({ closingPullRequests: [{ id: "PR_9", number: 9, url: "https://github.com/AquilaXk/easysubway/pull/9", state: "OPEN", repository: { nameWithOwner: SOURCE_REPOSITORY } }] }) }],
    ["label mismatch", transferEntry(), { target: metadata({ labels: ["different"] }) }],
    ["milestone mismatch", transferEntry(), { target: metadata({ milestone: "P1" }) }],
  ];

  for (const [name, entry, options] of cases) {
    await t.test(name, async () => {
      const fake = fakeGh(options);
      await assert.rejects(() => preflightIssueTransfer({ entry, execGh: fake.execGh }));
      assert.deepEqual(transferCalls(fake.calls), []);
    });
  }
});

test("dry-run preflight returns redacted metadata and never transfers", async () => {
  const fake = fakeGh();

  const report = await preflightIssueTransfer({ entry: transferEntry(), execGh: fake.execGh });

  assert.deepEqual(report, {
    source: { number: SOURCE_ISSUE, url: SOURCE_URL, title: transferEntry().title, state: "OPEN", labelCount: 1, milestone: "P0", commentCount: 1 },
    target: { repository: TARGET_REPOSITORY, exists: true, labelCount: 1, milestone: "P0" },
  });
  assert.deepEqual(transferCalls(fake.calls), []);
  assert.ok(fake.calls.every((args) => !args.some((value) => value.includes("body"))));
});

test("migration validates whole-ledger schema and semantics before any GitHub call", async (t) => {
  const cases = [
    ["schemaVersion", (ledger) => { ledger.schemaVersion = 2; }],
    ["classificationState", (ledger) => { ledger.issues[0].classificationState = "PENDING"; }],
    ["required metadata", (ledger) => { delete ledger.issues[0].reason; }],
    ["semantic mapping", (ledger) => { ledger.issues[0].targetRepository = "AquilaXk/easysubway-backend"; }],
  ];

  for (const [name, mutate] of cases) await t.test(name, async () => {
    const directory = evidenceDirectory();
    const { ledger, schema } = migrationContract();
    mutate(ledger);
    const fake = fakeGh();
    assert.ok(validateMigrationLedger({ ledger, schema }).length > 0);
    try {
      await assert.rejects(() => runMigration({
        arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
        ledger,
        schema,
        execGh: fake.execGh,
      }), /ledger validation failed/);
      assert.deepEqual(fake.calls, []);
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });
});

test("preflight verifies every source assignee can be assigned in the target before transfer", async () => {
  const source = metadata();
  source.assignees = { totalCount: 2, nodes: [{ id: "U_1", login: "space user" }, { id: "U_2", login: "owner" }] };
  const fake = fakeGh({ source });

  await preflightIssueTransfer({ entry: transferEntry(), execGh: fake.execGh });

  assert.ok(fake.calls.some((args) => args.at(-1) === "repos/AquilaXk/easysubway-data/assignees/space%20user"));
  assert.ok(fake.calls.some((args) => args.at(-1) === "repos/AquilaXk/easysubway-data/assignees/owner"));
});

test("preflight rejects unassignable or malformed target assignee responses before transfer", async (t) => {
  const source = metadata();
  source.assignees = { totalCount: 1, nodes: [{ id: "U_1", login: "owner" }] };
  for (const options of [{ unassignableLogin: "owner" }, { malformedAssigneeResponse: "{}" }]) await t.test(JSON.stringify(options), async () => {
    const fake = fakeGh({ source, ...options });
    await assert.rejects(() => preflightIssueTransfer({ entry: transferEntry(), execGh: fake.execGh }));
    assert.deepEqual(transferCalls(fake.calls), []);
  });
});

test("execution requires exact source and target confirmations before transfer", async () => {
  for (const confirmations of [{ source: "AquilaXk/easysubway#1", target: TARGET_REPOSITORY }, { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: "AquilaXk/other" }]) {
    const directory = evidenceDirectory();
    const fake = fakeGh();
    const { ledger, schema } = migrationContract();
    Object.assign(ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE), transferEntry());
    try {
      await assert.rejects(() => runMigration({
        arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations, evidenceDir: directory }, ledger, schema, execGh: fake.execGh,
      }), /confirmation/);
      assert.deepEqual(transferCalls(fake.calls), []);
    } finally { rmSync(directory, { recursive: true, force: true }); }
  }
});

test("execution transfers one approved issue and verifies redirected metadata", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, transferEntry());
  try {
    const verified = await runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory }, ledger, schema, execGh: fake.execGh,
    });
    assert.deepEqual(transferCalls(fake.calls), [["issue", "transfer", String(SOURCE_ISSUE), TARGET_REPOSITORY, "--repo", SOURCE_REPOSITORY]]);
    assert.deepEqual(verified, { sourceUrl: SOURCE_URL, targetUrl: TARGET_URL, number: 7, title: entry.title, state: "OPEN", labelCount: 1, milestone: "P0", commentCount: 1 });
    assert.equal(Object.hasOwn(verified, "body"), false);
    assert.equal(Object.hasOwn(verified, "comments"), false);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("completed transfer with failed verification reports a partial-success error", async () => {
  const directory = evidenceDirectory();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, { executionApproval: "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1", targetUrl: null, transferredAt: null });
  const fake = fakeGh({ target: metadata({ url: TARGET_URL, number: 8 }) });

  try {
    await assert.rejects(
      () => runMigration({
        arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
        ledger,
        schema,
        execGh: fake.execGh,
      }),
      (error) => error.message.startsWith("issue transfer completed but post-transfer verification failed:")
        && error.transferCompleted === true,
    );
    assert.equal(transferCalls(fake.calls).length, 1);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("post-transfer verification retries temporary target metadata propagation lag", async () => {
  const directory = evidenceDirectory();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, { executionApproval: "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1", targetUrl: null, transferredAt: null });
  const target = metadata({ url: TARGET_URL, number: 7 });
  const stale = { ...target, comments: { totalCount: 0 } };
  const fake = fakeGh({ target, targetResponses: [stale, stale, stale, stale, target] });

  try {
    const verified = await runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
      ledger,
      schema,
      execGh: fake.execGh,
      retryDelayMs: 0,
    });

    assert.equal(verified.targetUrl, TARGET_URL);
    assert.equal(fake.calls.filter((args) => args[0] === "api" && args[1] === "graphql" && args.includes("name=easysubway-data")).length, 5);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("unconfirmed transfer response reports an indeterminate result", async () => {
  const directory = evidenceDirectory();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, { executionApproval: "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1", targetUrl: null, transferredAt: null });
  const fake = fakeGh({ transferFailure: true });

  try {
    await assert.rejects(
      () => runMigration({
        arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
        ledger,
        schema,
        execGh: fake.execGh,
      }),
      (error) => error.message.includes("indeterminate") && error.transferIndeterminate === true,
    );
    assert.equal(transferCalls(fake.calls).length, 1);
    assert.equal(fake.calls.some((args) => args.at(-1) === `/repos/${SOURCE_REPOSITORY}/issues/${SOURCE_ISSUE}`), false);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("malformed successful transfer output reports an indeterminate result", async () => {
  const directory = evidenceDirectory();
  const { ledger, schema } = migrationContract();
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE);
  Object.assign(entry, { executionApproval: "https://github.com/AquilaXk/easysubway/issues/2691#issuecomment-1", targetUrl: null, transferredAt: null });
  const fake = fakeGh({ transferOutput: "Transferred\n" });

  try {
    await assert.rejects(
      () => runMigration({
        arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory },
        ledger,
        schema,
        execGh: fake.execGh,
      }),
      (error) => error.message.includes("indeterminate") && error.transferIndeterminate === true,
    );
    assert.equal(transferCalls(fake.calls).length, 1);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("post-transfer verification rejects metadata that does not identify the redirected issue", async () => {
  const directory = evidenceDirectory();
  const fake = fakeGh({ target: metadata({ url: TARGET_URL, number: 8 }) });
  const { ledger, schema } = migrationContract();
  Object.assign(ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE), transferEntry());
  try {
    await assert.rejects(() => runMigration({
      arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory }, ledger, schema, execGh: fake.execGh, retryDelayMs: 0,
    }), /redirect identity mismatched fields: target.number/);
    assert.equal(transferCalls(fake.calls).length, 1);
    assert.equal(fake.calls.filter((args) => args[0] === "api" && args[1] === "graphql" && args.includes("name=easysubway-data")).length, 1);
  } finally { rmSync(directory, { recursive: true, force: true }); }
});

test("unsafe entries and incomplete connections never transfer", async (t) => {
  const cases = [
    transferEntry(),
  ];
  for (const [index, entry] of cases.entries()) await t.test(String(index), async () => {
    const source = { ...metadata(), labels: { totalCount: 2, nodes: [{ name: "release-blocker" }] } };
    const fake = fakeGh({ source });
    await assert.rejects(() => preflightIssueTransfer({ entry, execGh: fake.execGh }));
    assert.deepEqual(transferCalls(fake.calls), []);
  });
});

test("execution entry validation prevents mutation through the evidence-gated path", async (t) => {
  const cases = [
    transferEntry({ executionApproval: "bad" }),
    transferEntry({ targetUrl: TARGET_URL, transferredAt: "2026-07-30T00:00:00.000Z" }),
  ];
  for (const entry of cases) await t.test(entry.executionApproval, async () => {
    const directory = evidenceDirectory();
    const fake = fakeGh();
    const { ledger, schema } = migrationContract();
    Object.assign(ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE), entry);
    try {
      await assert.rejects(() => runMigration({
        arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory }, ledger, schema, execGh: fake.execGh,
      }));
      assert.deepEqual(transferCalls(fake.calls), []);
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });
});

test("parser rejects duplicate and missing singleton values", () => {
  for (const flag of ["--ledger", "--source-issue", "--confirm-source", "--confirm-target"]) {
    const base = ["--ledger", "l", "--source-issue", "1", "--execute", "--confirm-source", "AquilaXk/easysubway#1", "--confirm-target", "AquilaXk/easysubway-data"];
    assert.throws(() => parseArguments([...base, flag, "x"]));
    const index = base.indexOf(flag);
    assert.throws(() => parseArguments([...base.slice(0, index), ...base.slice(index + 1)]));
  }
  assert.throws(() => parseArguments(["--ledger", "l", "--source-issue", "1", "--execute", "--confirm-source", "AquilaXk/easysubway#1", "--confirm-target"]));
  assert.throws(() => parseArguments(["--ledger", "--source-issue", "1", "--execute", "--confirm-source", "AquilaXk/easysubway#1", "--confirm-target", "AquilaXk/easysubway-data"]));
});

test("target milestone due-date mismatch rejects before transfer", async () => {
  const fake = fakeGh({ target: metadata({ milestone: "P0" }) });
  const original = fake.execGh;
  const execGh = async (args) => args[0] === "api" && args.includes("--paginate") && args.at(-1).includes("milestones")
    ? JSON.stringify([[{ title: "P0", due_on: "2026-08-01T00:00:00Z" }]]) : original(args);
  await assert.rejects(() => preflightIssueTransfer({ entry: transferEntry(), execGh }));
  assert.deepEqual(transferCalls(fake.calls), []);
});

test("post-transfer relation snapshots reject every changed relation after one transfer", async (t) => {
  const relation = { id: "I_9", number: 9, url: "https://github.com/AquilaXk/easysubway/issues/9", repository: { nameWithOwner: SOURCE_REPOSITORY } };
  const cases = [
    ["assignee", { assignees: { totalCount: 1, nodes: [{ id: "U_1", login: "owner" }] } }],
    ["project", { projectItems: { totalCount: 1, nodes: [{ id: "PVTITEM_1", project: { id: "PVT_1", number: 1, title: "P", url: "https://github.com/orgs/AquilaXk/projects/1" } }] } }],
    ["parent", { parent: relation }],
    ["sub issue", { subIssues: { totalCount: 1, nodes: [relation] } }],
    ["blocking", { blocking: { totalCount: 1, nodes: [relation] } }],
    ["blocked by", { blockedBy: { totalCount: 1, nodes: [relation] } }],
    ["closing PR", { closedByPullRequestsReferences: { totalCount: 1, nodes: [{ ...relation, id: "PR_9", state: "CLOSED" }] } }],
  ];
  for (const [name, changed] of cases) await t.test(name, async () => {
    const directory = evidenceDirectory();
    const fake = fakeGh({ target: { ...metadata({ url: TARGET_URL, number: 7 }), ...changed } });
    const { ledger, schema } = migrationContract();
    Object.assign(ledger.issues.find(({ sourceIssue }) => sourceIssue === SOURCE_ISSUE), transferEntry());
    try {
      await assert.rejects(() => runMigration({
        arguments_: { sourceIssue: SOURCE_ISSUE, mode: "execute", confirmations: { source: `${SOURCE_REPOSITORY}#${SOURCE_ISSUE}`, target: TARGET_REPOSITORY }, evidenceDir: directory }, ledger, schema, execGh: fake.execGh, retryDelayMs: 0,
      }));
      assert.equal(transferCalls(fake.calls).length, 1);
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });
});
