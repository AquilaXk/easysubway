import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";

const SOURCE_REPOSITORY = "AquilaXk/easysubway";
const APPROVED_TARGETS = new Set([
  "AquilaXk/easysubway-data",
  "AquilaXk/easysubway-platform",
  "AquilaXk/easysubway-backend",
  "AquilaXk/easysubway-mobile",
]);
const execFileAsync = promisify(execFile);
const ISSUE_METADATA_QUERY = [
  "query($owner: String!, $name: String!, $number: Int!) {",
  "  repository(owner: $owner, name: $name) {",
  "    issue(number: $number) {",
  "      number url title state",
  "      labels(first: 100) { totalCount nodes { name } }",
  "      milestone { title }",
  "      comments { totalCount }",
  "    }",
  "  }",
  "}",
].join("\n");

export function parseArguments(argv) {
  const values = { sourceIssues: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--ledger") values.ledgerPath = argv[++index];
    else if (argument === "--source-issue") values.sourceIssues.push(argv[++index]);
    else if (argument === "--dry-run" || argument === "--execute") {
      if (values.mode) throw new Error("choose exactly one execution mode");
      values.mode = argument.slice(2);
    } else if (argument === "--confirm-source") values.confirmSource = argv[++index];
    else if (argument === "--confirm-target") values.confirmTarget = argv[++index];
    else throw new Error("unsupported argument");
  }
  if (!values.ledgerPath) throw new Error("--ledger is required");
  if (values.sourceIssues.length !== 1 || !/^\d+$/.test(values.sourceIssues[0] ?? "")) {
    throw new Error("exactly one --source-issue is required");
  }
  if (!values.mode) throw new Error("choose exactly one execution mode");
  if (values.mode === "execute" && (!values.confirmSource || !values.confirmTarget)) {
    throw new Error("--execute requires both confirmations");
  }
  return { ledgerPath: values.ledgerPath, sourceIssue: Number(values.sourceIssues[0]), mode: values.mode };
}

export async function preflightIssueTransfer({ entry, execGh }) {
  const details = await preflightDetails({ entry, execGh });
  return reportForPreflight(entry, details);
}

export async function executeIssueTransfer({ entry, confirmations, execGh }) {
  confirmExecution(entry, confirmations);
  const details = await preflightDetails({ entry, execGh });
  await execGh(["issue", "transfer", String(entry.sourceIssue), entry.targetRepository, "--repo", SOURCE_REPOSITORY]);
  return { sourceUrl: entry.sourceUrl, expectedMetadata: details.source };
}

export async function verifyTransferredIssue({ entry, transferResult, execGh }) {
  const redirectHeaders = await execGh([
    "api", "--include", "--method", "HEAD", `/repos/${SOURCE_REPOSITORY}/issues/${entry.sourceIssue}`,
  ]);
  const targetUrl = redirectLocation(redirectHeaders, entry.targetRepository);
  const target = await readIssueMetadata(targetUrl.repository, targetUrl.number, execGh);
  const expected = transferResult?.expectedMetadata;
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
    milestone: target.milestone,
    commentCount: target.commentCount,
  };
}

async function preflightDetails({ entry, execGh }) {
  validateEntry(entry);
  const [targetExists, source, linkedPullRequests, targetLabels, targetMilestones] = await Promise.all([
    targetRepositoryExists(entry.targetRepository, execGh),
    readIssueMetadata(SOURCE_REPOSITORY, entry.sourceIssue, execGh),
    readLinkedPullRequests(entry.sourceIssue, execGh),
    readTargetLabels(entry.targetRepository, execGh),
    readTargetMilestones(entry.targetRepository, execGh),
  ]);
  if (!targetExists) throw new Error("target repository does not exist");
  if (source.url !== entry.sourceUrl || source.number !== entry.sourceIssue) throw new Error("source issue URL is stale");
  if (source.title !== entry.title || source.state !== "OPEN") throw new Error("source issue title or state is stale");
  if (linkedPullRequests !== 0) throw new Error("source issue has an open linked pull request");
  if (!source.labels.every((label) => targetLabels.has(label))) throw new Error("target repository labels do not match source");
  if (source.milestone !== null && !targetMilestones.has(source.milestone)) {
    throw new Error("target repository milestone does not match source");
  }
  return { source, targetLabels, targetMilestones };
}

function validateEntry(entry) {
  if (entry?.disposition !== "TRANSFER") throw new Error("entry disposition must be TRANSFER");
  if (entry?.executionApproval === null || typeof entry?.executionApproval !== "string") {
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

async function readLinkedPullRequests(sourceIssue, execGh) {
  const output = await execGh([
    "pr", "list", "--repo", SOURCE_REPOSITORY, "--state", "open",
    "--search", `linked:issue ${sourceIssue}`, "--json", "number",
  ]);
  const pullRequests = JSON.parse(output);
  if (!Array.isArray(pullRequests)) throw new Error("linked pull request metadata is invalid");
  return pullRequests.length;
}

async function readTargetLabels(repository, execGh) {
  const output = await execGh(["label", "list", "--repo", repository, "--limit", "100", "--json", "name"]);
  const labels = JSON.parse(output);
  if (!Array.isArray(labels) || !labels.every(({ name }) => typeof name === "string")) {
    throw new Error("target label metadata is invalid");
  }
  return new Set(labels.map(({ name }) => name));
}

async function readTargetMilestones(repository, execGh) {
  const output = await execGh(["api", `repos/${repository}/milestones?state=all&per_page=100`]);
  const milestones = JSON.parse(output);
  if (!Array.isArray(milestones) || !milestones.every(({ title }) => typeof title === "string")) {
    throw new Error("target milestone metadata is invalid");
  }
  return new Set(milestones.map(({ title }) => title));
}

async function readIssueMetadata(repository, number, execGh) {
  const [owner, name] = repository.split("/");
  const output = await execGh([
    "api", "graphql", "-f", `query=${ISSUE_METADATA_QUERY}`,
    "-F", `owner=${owner}`, "-F", `name=${name}`, "-F", `number=${number}`,
  ]);
  const issue = JSON.parse(output)?.data?.repository?.issue;
  if (!issue || !Array.isArray(issue.labels?.nodes) || typeof issue.comments?.totalCount !== "number") {
    throw new Error("issue metadata is invalid");
  }
  return {
    number: issue.number,
    url: issue.url,
    title: issue.title,
    state: issue.state,
    labels: issue.labels.nodes.map(({ name }) => name),
    milestone: issue.milestone?.title ?? null,
    commentCount: issue.comments.totalCount,
  };
}

function redirectLocation(headers, targetRepository) {
  const location = /^location:\s*(https:\/\/github\.com\/[^\s]+)$/im.exec(headers)?.[1];
  const match = location && new RegExp(`^https://github\\.com/${escapeRegExp(targetRepository)}/issues/(\\d+)$`).exec(location);
  if (!match) throw new Error("source issue redirect is missing or invalid");
  return { repository: targetRepository, number: Number(match[1]) };
}

function sameMetadata(left, right) {
  return left.title === right.title
    && left.state === right.state
    && left.milestone === right.milestone
    && left.commentCount === right.commentCount
    && left.labels.length === right.labels.length
    && left.labels.every((label) => right.labels.includes(label));
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
      milestone: source.milestone,
      commentCount: source.commentCount,
    },
    target: { repository: entry.targetRepository, exists: true, labelCount: details.targetLabels.size, milestone: source.milestone },
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
    const ledger = JSON.parse(await readFile(arguments_.ledgerPath, "utf8"));
    const entry = ledger?.issues?.find(({ sourceIssue }) => sourceIssue === arguments_.sourceIssue);
    if (!entry) throw new Error("source issue is not in the ledger");
    if (arguments_.mode === "dry-run") {
      console.log(JSON.stringify(await preflightIssueTransfer({ entry, execGh })));
      return;
    }
    const transferResult = await executeIssueTransfer({
      entry,
      confirmations: { source: process.argv[process.argv.indexOf("--confirm-source") + 1], target: process.argv[process.argv.indexOf("--confirm-target") + 1] },
      execGh,
    });
    console.log(JSON.stringify(await verifyTransferredIssue({ entry, transferResult, execGh })));
  } catch {
    console.error("issue migration was not executed");
    process.exitCode = 1;
  }
}

if (import.meta.url === new URL(process.argv[1], "file:").href) await main();
