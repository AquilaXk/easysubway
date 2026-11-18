import { execFile } from "node:child_process";
import { closeSync, constants as fsConstants, fstatSync, fsyncSync, linkSync, lstatSync, openSync, readFileSync, readdirSync, realpathSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
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
const PRESERVED_METADATA_FIELDS = [
  "title", "state", "milestone", "commentCount", "labels", "assignees",
  "projectItems", "parent", "subIssues", "blocking", "blockedBy", "closingPullRequests",
];

export function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--ledger", "--source-issue", "--confirm-source", "--confirm-target", "--evidence-dir"].includes(argument)) {
      const key = { "--ledger": "ledgerPath", "--source-issue": "sourceIssue", "--confirm-source": "confirmSource", "--confirm-target": "confirmTarget", "--evidence-dir": "evidenceDir" }[argument];
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
  if (values.mode === "execute") validateEvidenceDirectory(values.evidenceDir);
  return { ledgerPath: values.ledgerPath, sourceIssue: Number(values.sourceIssue), mode: values.mode, confirmations: { source: values.confirmSource, target: values.confirmTarget }, evidenceDir: values.evidenceDir };
}

export function validateMigrationLedger({ ledger, schema }) {
  const schemaErrors = validateSchema(schema, ledger).errors;
  return [...schemaErrors, ...validateLedger(ledger)];
}

export async function runMigration({ arguments_, ledger, schema, execGh, retryDelayMs = 0, writeEvidence = writeEvidenceAtomically, afterPreflightPublish = async () => {} }) {
  if (validateMigrationLedger({ ledger, schema }).length !== 0) throw new Error("ledger validation failed");
  const entry = ledger.issues.find(({ sourceIssue }) => sourceIssue === arguments_.sourceIssue);
  if (!entry) throw new Error("source issue is not in the ledger");
  if (arguments_.mode === "dry-run") return preflightIssueTransfer({ entry, execGh });
  confirmExecution(entry, arguments_.confirmations);
  const evidence = captureEvidenceDirectory(arguments_.evidenceDir);
  const details = await preflightDetails({ entry, execGh });
  const sourceMetadataSnapshot = JSON.stringify(details.source);
  try {
    await writeEvidence(evidence, evidenceFileName(entry.sourceIssue, "preflight"), {
      sourceIssue: entry.sourceIssue,
      sourceUrl: entry.sourceUrl,
      sourceMetadata: details.source,
    });
  } catch (error) {
    throw new Error("preflight evidence could not be persisted; transfer was not executed", { cause: error });
  }
  const preflightEvidence = capturePublishedEvidence(evidence, evidenceFileName(entry.sourceIssue, "preflight"));
  await afterPreflightPublish({ evidence, preflightEvidence });
  const persistedSource = readPersistedPreflight(evidence, entry.sourceIssue, entry.sourceUrl, preflightEvidence);
  if (JSON.stringify(persistedSource) !== sourceMetadataSnapshot) throw new Error("durable preflight evidence does not match preflight details");
  const transferResult = await executeIssueTransfer({
    entry,
    confirmations: arguments_.confirmations,
    execGh,
    details: { ...details, source: persistedSource },
  });
  try {
    const verificationTransferResult = {
      ...transferResult,
      expectedMetadata: persistedSource,
    };
    return await verifyTransferredIssue({ entry, transferResult: verificationTransferResult, execGh, retryDelayMs, evidence, writeEvidence });
  } catch (error) {
    const partialFailure = new Error(`issue transfer completed but post-transfer verification failed: ${error instanceof Error ? error.message : String(error)}`, { cause: error });
    partialFailure.transferCompleted = true;
    throw partialFailure;
  }
}

export async function preflightIssueTransfer({ entry, execGh }) {
  const details = await preflightDetails({ entry, execGh });
  return reportForPreflight(entry, details);
}

async function executeIssueTransfer({ entry, confirmations, execGh, details }) {
  confirmExecution(entry, confirmations);
  const normalizedDetails = details ?? await preflightDetails({ entry, execGh });
  try {
    const output = await execGh([
      "issue", "transfer", String(entry.sourceIssue), entry.targetRepository, "--repo", SOURCE_REPOSITORY,
    ]);
    return {
      sourceUrl: entry.sourceUrl,
      expectedMetadata: normalizedDetails.source,
      redirectedIssue: transferredIssueFromUrl(output.trim(), entry.targetRepository),
    };
  } catch {
    const indeterminate = new Error("issue transfer response is indeterminate; do not retry without confirming the exact target issue");
    indeterminate.transferIndeterminate = true;
    throw indeterminate;
  }
}

export async function verifyTransferredIssue({ entry, transferResult, execGh, retryDelayMs = 0, evidence, writeEvidence = writeEvidenceAtomically }) {
  const targetUrl = transferResult?.redirectedIssue;
  if (!targetUrl) throw new Error("transferred issue identity is missing");
  const expected = transferResult?.expectedMetadata;
  let verificationError;
  for (let attempt = 0; attempt < 10; attempt += 1) {
    let target;
    try {
      target = await readIssueMetadata(targetUrl.repository, targetUrl.number, execGh);
    } catch (error) {
      if (evidence) await persistPostflightAttempt({ entry, evidence, writeEvidence, attempt, redirectIdentity: redirectIdentityFor(targetUrl), targetMetadata: null, mismatchedFields: ["target.metadata"], metadataDifferences: { "target.metadata": { expected: "normalized metadata", actual: "unavailable" } } });
      verificationError = error;
      if (attempt < 9) await delay(retryDelayMs);
      continue;
    }
    try {
      const redirectIdentity = redirectIdentityFor(targetUrl);
      const identityDifferences = metadataDifferences(redirectIdentity, { repository: targetUrl.repository, number: target.number, url: target.url }, ["repository", "number", "url"]);
      const metadataDifferences_ = expected ? metadataDifferences(expected, target) : { expectedMetadata: { expected: "present", actual: "missing" } };
      const identityFields = Object.keys(identityDifferences).filter((field) => field !== "repository").map((field) => `target.${field}`);
      if (evidence) await persistPostflightAttempt({ entry, evidence, writeEvidence, attempt, redirectIdentity, targetMetadata: target, mismatchedFields: [...identityFields, ...Object.keys(metadataDifferences_)], metadataDifferences: { ...Object.fromEntries(identityFields.map((field) => [field, identityDifferences[field.slice(7)]])), ...metadataDifferences_ } });
      if (identityFields.length) {
        const identityMismatch = new Error(`redirect identity mismatched fields: ${identityFields.join(", ")}`);
        identityMismatch.redirectIdentityMismatch = true;
        throw identityMismatch;
      }
      if (Object.keys(metadataDifferences_).length) throw new Error(`transferred issue metadata mismatched fields: ${Object.keys(metadataDifferences_).join(", ")}`);
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
      if (error?.postflightEvidencePersistenceFailed === true || error?.redirectIdentityMismatch === true) throw error;
      verificationError = error;
      if (attempt < 9) await delay(retryDelayMs);
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

function metadataDifferences(expected, actual, fields = PRESERVED_METADATA_FIELDS) {
  return Object.fromEntries(fields.filter((field) => JSON.stringify(expected[field]) !== JSON.stringify(actual[field]))
    .map((field) => [field, { expected: expected[field], actual: actual[field] }]));
}

function validateEvidenceDirectory(value) {
  if (typeof value !== "string" || !value.startsWith("/")) throw new Error("--execute requires exactly one --evidence-dir <absolute existing empty non-symlink directory>");
  const inspectedPath = value.length > 1 ? value.replace(/(?:\/\.?)+$/, "") : value;
  let stat;
  try { stat = lstatSync(inspectedPath); } catch { throw new Error("--execute requires exactly one --evidence-dir <absolute existing empty non-symlink directory>"); }
  if (stat.isSymbolicLink() || !stat.isDirectory() || readdirSync(value).length !== 0) {
    throw new Error("--execute requires exactly one --evidence-dir <absolute existing empty non-symlink directory>");
  }
  return stat;
}

function captureEvidenceDirectory(value) {
  const requestedStat = validateEvidenceDirectory(value);
  const canonicalPath = realpathSync(value);
  const canonicalStat = statSync(canonicalPath);
  if (requestedStat.dev !== canonicalStat.dev || requestedStat.ino !== canonicalStat.ino) {
    throw new Error("evidence directory identity changed");
  }
  const claimPath = join(canonicalPath, ".migration-claim");
  let claimStat;
  try {
    const claimDescriptor = openSync(claimPath, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_NOFOLLOW | fsConstants.O_RDWR, 0o600);
    try { claimStat = fstatSync(claimDescriptor); } finally { closeSync(claimDescriptor); }
  } catch { throw new Error("evidence directory is already used or claimed"); }
  if (!claimStat.isFile()) throw new Error("evidence directory identity changed");
  const context = { requestedPath: value, canonicalPath, dev: requestedStat.dev, ino: requestedStat.ino, claimPath, claimDev: claimStat.dev, claimIno: claimStat.ino };
  assertEvidenceDirectory(context);
  return context;
}

function assertEvidenceDirectory(context) {
  let requestedStat;
  let canonicalStat;
  let claimStat;
  try {
    requestedStat = lstatSync(context.requestedPath);
    canonicalStat = statSync(context.canonicalPath);
    claimStat = lstatSync(context.claimPath);
  } catch {
    throw new Error("evidence directory identity changed");
  }
  if (!requestedStat.isDirectory() || requestedStat.dev !== context.dev || requestedStat.ino !== context.ino
    || realpathSync(context.requestedPath) !== context.canonicalPath || !canonicalStat.isDirectory() || canonicalStat.dev !== context.dev || canonicalStat.ino !== context.ino
    || !claimStat.isFile() || claimStat.dev !== context.claimDev || claimStat.ino !== context.claimIno) throw new Error("evidence directory identity changed");
}

function capturePublishedEvidence(context, filename) {
  assertEvidenceDirectory(context);
  const path = join(context.canonicalPath, filename);
  const descriptor = openSync(path, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
  try {
    const stat = fstatSync(descriptor);
    if (!stat.isFile()) throw new Error("durable preflight evidence is unavailable");
    const bytes = readFileSync(descriptor);
    assertEvidenceDirectory(context);
    const directoryDescriptor = openSync(context.canonicalPath, fsConstants.O_RDONLY | fsConstants.O_DIRECTORY | fsConstants.O_NOFOLLOW);
    try {
      const directoryStat = fstatSync(directoryDescriptor);
      if (!directoryStat.isDirectory() || directoryStat.dev !== context.dev || directoryStat.ino !== context.ino) throw new Error("evidence directory identity changed");
    } finally { closeSync(directoryDescriptor); }
    const destinationStat = lstatSync(path);
    if (!destinationStat.isFile() || destinationStat.dev !== stat.dev || destinationStat.ino !== stat.ino) throw new Error("durable preflight evidence is unavailable");
    assertEvidenceDirectory(context);
    return { path, dev: stat.dev, ino: stat.ino, bytes };
  } finally {
    closeSync(descriptor);
  }
}

function evidenceFileName(sourceIssue, suffix) {
  if (!Number.isSafeInteger(sourceIssue) || sourceIssue < 1 || !/^(preflight|postflight-[1-9]\d*)$/.test(suffix)) throw new Error("invalid evidence filename");
  return `${sourceIssue}-${suffix}.json`;
}

async function writeEvidenceAtomically(context, filename, value) {
  assertEvidenceDirectory(context);
  const destination = join(context.canonicalPath, filename);
  const temporary = join(context.canonicalPath, `.${filename}.tmp`);
  const expectedBytes = Buffer.from(`${JSON.stringify(value)}\n`);
  try {
    const temporaryFd = openSync(temporary, "wx", 0o600);
    try { writeFileSync(temporaryFd, expectedBytes); fsyncSync(temporaryFd); } finally { closeSync(temporaryFd); }
    linkSync(temporary, destination);
    unlinkSync(temporary);
    const directoryFd = openSync(context.canonicalPath, "r");
    try { fsyncSync(directoryFd); } finally { closeSync(directoryFd); }
    assertEvidenceDirectory(context);
    if (!capturePublishedEvidence(context, filename).bytes.equals(expectedBytes)) throw new Error("published evidence is invalid");
  } finally {
    try { unlinkSync(temporary); } catch {}
  }
}

function readPersistedPreflight(context, sourceIssue, sourceUrl, publishedEvidence) {
  assertEvidenceDirectory(context);
  let evidence;
  try {
    const descriptor = openSync(publishedEvidence.path, fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW);
    try {
      const stat = fstatSync(descriptor);
      if (!stat.isFile() || stat.dev !== publishedEvidence.dev || stat.ino !== publishedEvidence.ino) {
        throw new Error("durable preflight evidence is unavailable");
      }
      const bytes = readFileSync(descriptor);
      if (!bytes.equals(publishedEvidence.bytes)) throw new Error("durable preflight evidence is unavailable");
      evidence = JSON.parse(bytes.toString("utf8"));
    } finally {
      closeSync(descriptor);
    }
    assertEvidenceDirectory(context);
  } catch {
    throw new Error("durable preflight evidence is unavailable");
  }
  if (evidence?.sourceIssue !== sourceIssue || evidence.sourceUrl !== sourceUrl || !isNormalizedMetadata(evidence.sourceMetadata)) {
    throw new Error("durable preflight evidence is invalid");
  }
  return evidence.sourceMetadata;
}

function isNormalizedMetadata(value) {
  return value && typeof value === "object" && typeof value.number === "number" && typeof value.url === "string"
    && PRESERVED_METADATA_FIELDS.every((field) => Object.hasOwn(value, field));
}

async function persistPostflightAttempt({ entry, evidence, writeEvidence, attempt, redirectIdentity, targetMetadata, mismatchedFields, metadataDifferences }) {
  try {
    const filename = evidenceFileName(entry.sourceIssue, `postflight-${attempt + 1}`);
    const value = { sourceIssue: entry.sourceIssue, sourceUrl: entry.sourceUrl, attempt: attempt + 1, redirectIdentity, targetMetadata, mismatchedFields, metadataDifferences };
    const expectedBytes = Buffer.from(`${JSON.stringify(value)}\n`);
    await writeEvidence(evidence, filename, value);
    if (!capturePublishedEvidence(evidence, filename).bytes.equals(expectedBytes)) throw new Error("published evidence is invalid");
  } catch (error) {
    const persistenceFailure = new Error("postflight evidence could not be persisted", { cause: error });
    persistenceFailure.postflightEvidencePersistenceFailed = true;
    throw persistenceFailure;
  }
}

function redirectIdentityFor(targetUrl) {
  return { repository: targetUrl.repository, number: targetUrl.number, url: `https://github.com/${targetUrl.repository}/issues/${targetUrl.number}` };
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
