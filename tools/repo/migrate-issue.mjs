import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";
import { promisify } from "node:util";
import { validateLedger } from "./issue-migration-ledger.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";

const SOURCE_REPOSITORY = "AquilaXk/easysubway";
const APPROVED_TARGETS = new Set([
  "AquilaXk/easysubway-data",
  "AquilaXk/easysubway-platform",
  "AquilaXk/easysubway-backend",
  "AquilaXk/easysubway-mobile",
]);
const APPROVAL_URL_PATTERN = new RegExp(
  `^https://github\\.com/${escapeRegExp(SOURCE_REPOSITORY)}/issues/\\d+#issuecomment-\\d+$`,
);
const execFileAsync = promisify(execFile);
const ISSUE_METADATA_QUERY = [
  "query($owner: String!, $name: String!, $number: Int!) {",
  "  repository(owner: $owner, name: $name) {",
  "    issue(number: $number) {",
  "      number url title state",
  "      repository { nameWithOwner }",
  "      labels(first: 100) { totalCount nodes { name } }",
  "      milestone { title dueOn }",
  "      assignees(first: 100) { totalCount nodes { id login } }",
  "      comments { totalCount }",
  "      projectItems(first: 100) { totalCount nodes { id project { id number title url } } }",
  "      parent { id number url repository { nameWithOwner } }",
  "      subIssues(first: 100) { totalCount nodes { id number url repository { nameWithOwner } } }",
  "      blocking(first: 100) { totalCount nodes { id number url repository { nameWithOwner } } }",
  "      blockedBy(first: 100) { totalCount nodes { id number url repository { nameWithOwner } } }",
  "      closedByPullRequestsReferences(first: 100, includeClosedPrs: true) { totalCount nodes { id number url state repository { nameWithOwner } } }",
  "    }",
  "  }",
  "}",
].join("\n");

export function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--ledger", "--source-issue", "--confirm-source", "--confirm-target"].includes(argument)) {
      const key = { "--ledger": "ledgerPath", "--source-issue": "sourceIssue", "--confirm-source": "confirmSource", "--confirm-target": "confirmTarget" }[argument];
      const value = argv[++index];
      if (values[key] !== undefined || value === undefined || value.startsWith("--")) throw new Error(argument === "--source-issue" ? "exactly one --source-issue is required" : `${argument} must appear exactly once with a value`);
      values[key] = value;
    }
    else if (argument === "--dry-run" || argument === "--execute") {
      if (values.mode) throw new Error("choose exactly one execution mode");
      values.mode = argument.slice(2);
    }
    else throw new Error("unsupported argument");
  }
  if (!values.ledgerPath) throw new Error("--ledger is required");
  if (!/^\d+$/.test(values.sourceIssue ?? "")) {
    throw new Error("exactly one --source-issue is required");
  }
  if (!values.mode) throw new Error("choose exactly one execution mode");
  if (values.mode === "execute" && (!values.confirmSource || !values.confirmTarget)) {
    throw new Error("--execute requires both confirmations");
  }
  return { ledgerPath: values.ledgerPath, sourceIssue: Number(values.sourceIssue), mode: values.mode, confirmations: { source: values.confirmSource, target: values.confirmTarget } };
}

export function validateMigrationLedger({ ledger, schema }) {
  const schemaErrors = validateSchema(schema, ledger).errors;
  return [...schemaErrors, ...validateLedger(ledger)];
}

export async function runMigration({ arguments_, ledger, schema, execGh, retryDelayMs = 0 }) {
  if (validateMigrationLedger({ ledger, schema }).length !== 0) throw new Error("ledger validation failed");
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === arguments_.sourceIssue);
  if (!entry) throw new Error("source issue is not in the ledger");
  if (arguments_.mode === "dry-run") return preflightIssueTransfer({ entry, execGh });
  const transferResult = await executeIssueTransfer({
    entry,
    confirmations: arguments_.confirmations,
    execGh,
  });
  try {
    return await verifyTransferredIssue({ entry, transferResult, execGh, retryDelayMs });
  } catch (error) {
    const partialFailure = new Error(`issue transfer completed but post-transfer verification failed: ${error instanceof Error ? error.message : String(error)}`);
    partialFailure.transferCompleted = true;
    throw partialFailure;
  }
}

export async function preflightIssueTransfer({ entry, execGh }) {
  const details = await preflightDetails({ entry, execGh });
  return reportForPreflight(entry, details);
}

export async function executeIssueTransfer({ entry, confirmations, execGh }) {
  confirmExecution(entry, confirmations);
  const details = await preflightDetails({ entry, execGh });
  try {
    const output = await execGh([
      "issue", "transfer", String(entry.sourceIssue), entry.targetRepository, "--repo", SOURCE_REPOSITORY,
    ]);
    return {
      sourceUrl: entry.sourceUrl,
      expectedMetadata: details.source,
      redirectedIssue: transferredIssueFromUrl(output.trim(), entry.targetRepository),
    };
  } catch {
    const indeterminate = new Error("issue transfer response is indeterminate; do not retry without confirming the exact target issue");
    indeterminate.transferIndeterminate = true;
    throw indeterminate;
  }
}

export async function verifyTransferredIssue({ entry, transferResult, execGh, retryDelayMs = 0 }) {
  const targetUrl = transferResult?.redirectedIssue;
  if (!targetUrl) throw new Error("transferred issue identity is missing");
  const expected = transferResult?.expectedMetadata;
  let verificationError;
  for (let attempt = 0; attempt < 3; attempt += 1) {
    try {
      const target = await readIssueMetadata(targetUrl.repository, targetUrl.number, execGh);
      if (target.number !== targetUrl.number || target.url !== `https://github.com/${targetUrl.repository}/issues/${targetUrl.number}`) {
        throw new Error("redirect target metadata is stale");
      }
      if (!expected || !sameMetadata(expected, target)) throw new Error("transferred issue metadata does not match source");
      return {
        sourceUrl: entry.sourceUrl,
        targetUrl: target.url,
        number: target.number,
        title: target.title,
        state: target.state,
        labelCount: target.labels.length,
        milestone: target.milestone?.title ?? null,
        commentCount: target.commentCount,
      };
    } catch (error) {
      verificationError = error;
      if (attempt < 2) await delay(retryDelayMs);
    }
  }
  throw verificationError;
}

async function preflightDetails({ entry, execGh }) {
  validateEntry(entry);
  const [targetExists, source, targetLabels, targetMilestones] = await Promise.all([
    targetRepositoryExists(entry.targetRepository, execGh),
    readIssueMetadata(SOURCE_REPOSITORY, entry.sourceIssue, execGh),
    readTargetLabels(entry.targetRepository, execGh),
    readTargetMilestones(entry.targetRepository, execGh),
  ]);
  if (!targetExists) throw new Error("target repository does not exist");
  if (source.url !== entry.sourceUrl || source.number !== entry.sourceIssue) throw new Error("source issue URL is stale");
  if (source.title !== entry.title || source.state !== "OPEN") throw new Error("source issue title or state is stale");
  if (source.closingPullRequests.some(({ state }) => state === "OPEN")) throw new Error("source issue has an open linked pull request");
  if (!source.labels.every((label) => targetLabels.has(label))) throw new Error("target repository labels do not match source");
  if (source.milestone !== null && !targetMilestones.has(JSON.stringify(source.milestone))) {
    throw new Error("target repository milestone does not match source");
  }
  await preflightTargetAssignees(entry.targetRepository, source.assignees, execGh);
  return { source, targetLabels, targetMilestones };
}

async function preflightTargetAssignees(repository, assignees, execGh) {
  for (const { login } of assignees) {
    if (typeof login !== "string" || login.length === 0) throw new Error("source assignee metadata is invalid");
    let output;
    try {
      output = await execGh([
        "api", "-H", "X-GitHub-Api-Version: 2022-11-28",
        `repos/${repository}/assignees/${encodeURIComponent(login)}`,
      ]);
    } catch {
      throw new Error("target assignee is not assignable");
    }
    if (typeof output !== "string" || output.trim() !== "") throw new Error("target assignee response is invalid");
  }
}

function validateEntry(entry) {
  if (entry?.disposition !== "TRANSFER") throw new Error("entry disposition must be TRANSFER");
  if (typeof entry?.executionApproval !== "string"
    || !APPROVAL_URL_PATTERN.test(entry.executionApproval)
    || entry.targetUrl !== null || entry.transferredAt !== null) {
    throw new Error("entry requires execution approval");
  }
  if (!APPROVED_TARGETS.has(entry?.targetRepository)) throw new Error("entry target is not approved");
  if (typeof entry?.sourceIssue !== "number" || typeof entry?.sourceUrl !== "string" || typeof entry?.title !== "string") {
    throw new Error("entry is incomplete");
  }
}

function confirmExecution(entry, confirmations) {
  const expectedSource = `${SOURCE_REPOSITORY}#${entry?.sourceIssue}`;
  if (confirmations?.source !== expectedSource) throw new Error("source confirmation does not match");
  if (confirmations?.target !== entry?.targetRepository) throw new Error("target confirmation does not match");
}

async function targetRepositoryExists(repository, execGh) {
  try {
    const output = await execGh(["repo", "view", repository, "--json", "nameWithOwner"]);
    return JSON.parse(output).nameWithOwner === repository;
  } catch {
    return false;
  }
}

async function readTargetLabels(repository, execGh) {
  const output = await execGh(["api", "--paginate", "--slurp", "-H", "X-GitHub-Api-Version: 2022-11-28", `repos/${repository}/labels?per_page=100`]);
  const labels = JSON.parse(output).flat();
  if (!Array.isArray(labels) || !labels.every(({ name }) => typeof name === "string")) {
    throw new Error("target label metadata is invalid");
  }
  return new Set(labels.map(({ name }) => name));
}

async function readTargetMilestones(repository, execGh) {
  const output = await execGh(["api", "--paginate", "--slurp", "-H", "X-GitHub-Api-Version: 2022-11-28", `repos/${repository}/milestones?state=all&per_page=100`]);
  const milestones = JSON.parse(output).flat();
  if (!Array.isArray(milestones) || !milestones.every(({ title, due_on: dueOn }) => typeof title === "string" && (dueOn === null || typeof dueOn === "string"))) {
    throw new Error("target milestone metadata is invalid");
  }
  return new Set(milestones.map(({ title, due_on: dueOn }) => JSON.stringify({ title, dueOn: canonicalDueOn(dueOn) })));
}

async function readIssueMetadata(repository, number, execGh) {
  const [owner, name] = repository.split("/");
  const output = await execGh([
    "api", "graphql", "-f", `query=${ISSUE_METADATA_QUERY}`,
    "-F", `owner=${owner}`, "-F", `name=${name}`, "-F", `number=${number}`,
  ]);
  const issue = JSON.parse(output)?.data?.repository?.issue;
  if (!issue || issue.repository?.nameWithOwner !== repository || typeof issue.comments?.totalCount !== "number") {
    throw new Error("issue metadata is invalid");
  }
  const connection = (value, name) => {
    if (!value || !Array.isArray(value.nodes) || value.totalCount !== value.nodes.length) throw new Error(`${name} metadata is incomplete`);
    return value.nodes;
  };
  return {
    number: issue.number,
    url: issue.url,
    title: issue.title,
    state: issue.state,
    labels: connection(issue.labels, "labels").map(({ name }) => name).sort(),
    milestone: issue.milestone === null ? null : { title: issue.milestone.title, dueOn: canonicalDueOn(issue.milestone.dueOn) },
    commentCount: issue.comments.totalCount,
    assignees: connection(issue.assignees, "assignees").map(({ id, login }) => {
      if (typeof id !== "string" || typeof login !== "string" || login.length === 0) throw new Error("assignee metadata is invalid");
      return { id, login };
    }).sort(compareIdentity),
    projectItems: connection(issue.projectItems, "project items").map(({ id, project }) => ({ id, project: { id: project.id, number: project.number, title: project.title, url: project.url } })).sort(compareIdentity),
    parent: issue.parent === null ? null : issueIdentity(issue.parent),
    subIssues: connection(issue.subIssues, "sub issues").map(issueIdentity).sort(compareIdentity),
    blocking: connection(issue.blocking, "blocking issues").map(issueIdentity).sort(compareIdentity),
    blockedBy: connection(issue.blockedBy, "blocked-by issues").map(issueIdentity).sort(compareIdentity),
    closingPullRequests: connection(issue.closedByPullRequestsReferences, "linked pull requests").map((item) => ({ ...issueIdentity(item), state: item.state })).sort(compareIdentity),
  };
}

function issueIdentity(issue) {
  if (!issue?.id || !issue?.number || !issue?.url || !issue.repository?.nameWithOwner) throw new Error("issue relation metadata is invalid");
  return { id: issue.id, number: issue.number, url: issue.url, repository: issue.repository.nameWithOwner };
}

function compareIdentity(left, right) { return left.id < right.id ? -1 : left.id > right.id ? 1 : 0; }

function canonicalDueOn(value) {
  if (value === null) return null;
  const date = new Date(value);
  if (typeof value !== "string" || !Number.isFinite(date.getTime())) throw new Error("milestone due date is invalid");
  return date.toISOString();
}

function transferredIssueFromUrl(url, targetRepository) {
  const match = typeof url === "string" && url.match(new RegExp(`^https://github\\.com/${escapeRegExp(targetRepository)}/issues/([1-9]\\d*)$`));
  if (!match) throw new Error("transferred issue URL is missing or invalid");
  return { repository: targetRepository, number: Number(match[1]) };
}

function sameMetadata(left, right) {
  return left.title === right.title
    && left.state === right.state
    && JSON.stringify(left.milestone) === JSON.stringify(right.milestone)
    && left.commentCount === right.commentCount
    && left.labels.length === right.labels.length
    && left.labels.every((label) => right.labels.includes(label))
    && JSON.stringify(left.assignees) === JSON.stringify(right.assignees)
    && JSON.stringify(left.projectItems) === JSON.stringify(right.projectItems)
    && JSON.stringify(left.parent) === JSON.stringify(right.parent)
    && JSON.stringify(left.subIssues) === JSON.stringify(right.subIssues)
    && JSON.stringify(left.blocking) === JSON.stringify(right.blocking)
    && JSON.stringify(left.blockedBy) === JSON.stringify(right.blockedBy)
    && JSON.stringify(left.closingPullRequests) === JSON.stringify(right.closingPullRequests);
}

function reportForPreflight(entry, details) {
  const { source } = details;
  return {
    source: {
      number: source.number,
      url: source.url,
      title: source.title,
      state: source.state,
      labelCount: source.labels.length,
      milestone: source.milestone?.title ?? null,
      commentCount: source.commentCount,
    },
    target: { repository: entry.targetRepository, exists: true, labelCount: details.targetLabels.size, milestone: source.milestone?.title ?? null },
  };
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function execGh(args) {
  const { stdout } = await execFileAsync("gh", args, { encoding: "utf8" });
  return stdout;
}

async function main() {
  try {
    const arguments_ = parseArguments(process.argv.slice(2));
    const [ledgerText, schemaText] = await Promise.all([
      readFile(arguments_.ledgerPath, "utf8"),
      readFile("contracts/repository-split-issues.schema.json", "utf8"),
    ]);
    console.log(JSON.stringify(await runMigration({
      arguments_,
      ledger: JSON.parse(ledgerText),
      schema: JSON.parse(schemaText),
      execGh,
      retryDelayMs: 1_000,
    })));
  } catch (error) {
    if (error?.transferCompleted === true || error?.transferIndeterminate === true) console.error(error.message);
    else console.error(`issue migration was not executed: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}

if (import.meta.url === new URL(process.argv[1], "file:").href) await main();
