import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { validateLedger } from "./issue-migration-ledger.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { isMainModule } from "../lib/is-main-module.mjs";

const SOURCE_REPOSITORY = "AquilaXk/easysubway";
const MOBILE_REPOSITORY = "AquilaXk/easysubway-mobile";
const execFileAsync = promisify(execFile);
const MAX_GH_BUFFER_BYTES = 64 * 1024 * 1024;

export function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (["--ledger", "--source-issue", "--confirm-source", "--confirm-target"].includes(argument)) {
      const key = { "--ledger": "ledgerPath", "--source-issue": "sourceIssue", "--confirm-source": "confirmSource", "--confirm-target": "confirmTarget" }[argument];
      const value = argv[++index];
      if (values[key] !== undefined || value === undefined || value.startsWith("--")) throw new Error(`${argument} must appear exactly once with a value`);
      values[key] = value;
    } else if (argument === "--dry-run" || argument === "--execute") {
      if (values.mode) throw new Error("choose exactly one execution mode");
      values.mode = argument.slice(2);
    } else throw new Error("unsupported argument");
  }
  if (!values.ledgerPath || !/^[1-9]\d*$/.test(values.sourceIssue ?? "") || !values.mode) throw new Error("ledger, source issue, and execution mode are required");
  if (values.mode === "execute" && (!values.confirmSource || !values.confirmTarget)) throw new Error("execute requires both confirmations");
  return {
    ledgerPath: values.ledgerPath,
    sourceIssue: Number(values.sourceIssue),
    mode: values.mode,
    confirmations: values.mode === "execute" ? { source: values.confirmSource, target: values.confirmTarget } : {},
  };
}

export async function runNormalization({ arguments_, ledger, execGh }) {
  const entry = ledger?.issues?.find(({ sourceIssue }) => sourceIssue === arguments_?.sourceIssue);
  if (!entry) throw new Error(`source issue #${arguments_?.sourceIssue} is not present in the ledger`);
  const target = transferredReference(entry);
  if (target.repository !== MOBILE_REPOSITORY) throw new Error("target repository must be easysubway-mobile");
  const targetUrl = `https://github.com/${target.repository}/issues/${target.number}`;
  if (arguments_?.mode === "execute") {
    confirmExecution(entry, target, arguments_.confirmations);
    throw new Error("execute is unsupported: GitHub issue PATCH has no supported conditional write");
  }
  else if (arguments_?.mode !== "dry-run") throw new Error("choose dry-run or execute mode");

  const [body, comments] = await Promise.all([
    readIssueBody(target.repository, target.number, execGh),
    readIssueComments(target.repository, target.number, execGh),
  ]);
  const unresolved = [
    ...qualifyIssueReferences({ text: body, ledger }).map((reference) => ({ surface: { kind: "body", id: null }, ...reference })),
    ...comments.flatMap((comment) => qualifyIssueReferences({ text: comment.body, ledger })
      .map((reference) => ({ surface: { kind: "comment", id: comment.id }, ...reference }))),
  ];
  const result = {
    sourceIssue: entry.sourceIssue,
    targetUrl,
    referenceMap: Object.fromEntries([...referencesFromLedger(ledger)].map(([sourceIssue, reference]) => [sourceIssue, `${reference.repository}#${reference.number}`])),
    changes: [],
    unresolved,
  };
  return result;
}

export function qualifyIssueReferences({ text, ledger }) {
  if (typeof text !== "string") throw new Error("issue text must be a string");
  const references = referencesFromLedger(ledger);
  let fenced = null;
  let prose = "";
  const unresolved = [];
  for (const line of text.split(/(?<=\n)/)) {
    if (fenced !== null) {
      const closingFence = line.match(/^ {0,3}(`{3,}|~{3,})[ \t]*(?:\r?\n)?$/);
      if (closingFence?.[1][0] === fenced.character && closingFence[1].length >= fenced.length) fenced = null;
      continue;
    }

    if (/^(?:\t| {4})/.test(line)) throw new Error("indented code block is unsupported");
    const openingFence = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (openingFence) {
      unresolved.push(...qualifyText(prose, references));
      prose = "";
      fenced = { character: openingFence[1][0], length: openingFence[1].length };
    } else prose += line;
  }
  if (fenced !== null) throw new Error("unterminated fenced code block");
  return [...unresolved, ...qualifyText(prose, references)];
}

function qualifyText(text, references) {
  const unresolved = [];
  for (let index = 0; index < text.length;) {
    if (text.startsWith("http://", index) || text.startsWith("https://", index)) {
      const end = text.slice(index).search(/\s/);
      const length = end === -1 ? text.length - index : end;
      index += length; continue;
    }
    if (text[index] === "`") {
      const length = text.slice(index).match(/^`+/)[0].length;
      const delimiter = "`".repeat(length); const end = text.indexOf(delimiter, index + length);
      if (end === -1) throw new Error("unterminated inline code span");
      index = end + length; continue;
    }
    const match = text.slice(index).match(/^#([1-9]\d*)/);
    if (match && !/[\w/]/.test(text[index - 1] ?? "")) {
      const reference = references.get(Number(match[1]));
      if (!reference) throw new Error(`unresolved bare issue reference #${match[1]}`);
      unresolved.push({ reference: Number(match[1]), reason: "bare reference is ambiguous after issue transfer" });
      index += match[0].length; continue;
    }
    index += 1;
  }
  return unresolved;
}

function referencesFromLedger(ledger) {
  if (!Array.isArray(ledger?.issues)) throw new Error("ledger issues are required");
  const references = new Map();
  for (const entry of ledger.issues) {
    if (!Number.isInteger(entry?.sourceIssue) || entry.sourceIssue < 1) continue;
    if (references.has(entry.sourceIssue)) throw new Error(`duplicate ledger source issue #${entry.sourceIssue}`);
    if (entry.disposition === "KEEP_HUB" || entry.disposition === "SPLIT_CHILDREN") {
      references.set(entry.sourceIssue, { repository: SOURCE_REPOSITORY, number: entry.sourceIssue });
    } else if (typeof entry.targetUrl === "string") {
      references.set(entry.sourceIssue, transferredReference(entry));
    }
  }
  return references;
}

function transferredReference(entry) {
  const match = typeof entry?.targetUrl === "string"
    && entry.targetUrl.match(/^https:\/\/github\.com\/(AquilaXk\/easysubway-(?:data|platform|backend|mobile))\/issues\/([1-9]\d*)$/);
  if (!match || match[1] !== entry.targetRepository) {
    throw new Error(`incomplete transfer mapping for #${entry?.sourceIssue}`);
  }
  return { repository: match[1], number: Number(match[2]) };
}

function confirmExecution(entry, target, confirmations) {
  if (confirmations?.source !== `${SOURCE_REPOSITORY}#${entry?.sourceIssue}`) throw new Error("source confirmation does not match");
  if (confirmations?.target !== `${target.repository}#${target.number}`) throw new Error("target confirmation does not match");
}

async function readIssueBody(repository, number, execGh) {
  const issue = JSON.parse(await execGh(["api", `repos/${repository}/issues/${number}`]));
  if (issue?.body !== null && typeof issue?.body !== "string") throw new Error("issue body is invalid");
  return issue.body ?? "";
}

async function readIssueComments(repository, number, execGh) {
  const pages = JSON.parse(await execGh(["api", "--paginate", "--slurp", `repos/${repository}/issues/${number}/comments?per_page=100`]));
  const comments = pages.flat();
  const issueUrl = `https://api.github.com/repos/${repository}/issues/${number}`;
  if (!Array.isArray(comments) || new Set(comments.map(({ id }) => id)).size !== comments.length
    || !comments.every(({ id, body, issue_url: commentIssueUrl }) => Number.isInteger(id) && typeof body === "string" && commentIssueUrl === issueUrl)) {
    throw new Error("issue comments are invalid");
  }
  return comments;
}

async function execGh(args) {
  const { stdout } = await execFileAsync("gh", args, { encoding: "utf8", maxBuffer: MAX_GH_BUFFER_BYTES });
  return stdout;
}

async function main() {
  try {
    const arguments_ = parseArguments(process.argv.slice(2));
    const [ledgerText, schemaText] = await Promise.all([
      readFile(arguments_.ledgerPath, "utf8"),
      readFile(new URL("../../contracts/repository-split-issues.schema.json", import.meta.url), "utf8"),
    ]);
    const ledger = JSON.parse(ledgerText);
    const errors = [...validateSchema(JSON.parse(schemaText), ledger).errors, ...validateLedger(ledger)];
    if (errors.length !== 0) throw new Error(`ledger validation failed: ${errors.join("; ")}`);
    console.log(JSON.stringify(await runNormalization({ arguments_, ledger, execGh })));
  } catch (error) {
    console.error(`issue reference normalization was not executed: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}

if (isMainModule(import.meta.url)) await main();
