#!/usr/bin/env node
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { promisify } from "node:util";
import { isMainModule } from "../lib/is-main-module.mjs";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { validateAmendments, validateLedger } from "./issue-migration-ledger.mjs";

const HUB_REPOSITORY = "AquilaXk/easysubway";
const HUB_ISSUE_URL_PATTERN = /^https:\/\/github\.com\/[^/]+\/[^/]+\/issues\/[1-9]\d*$/;
const NOT_FOUND_PATTERN = /\(HTTP 404\)/;
const MAX_GH_BUFFER_BYTES = 64 * 1024 * 1024;
const MAX_OPEN_ISSUES = 1000;
const execFileAsync = promisify(execFile);

export function parseArguments(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const key = { "--ledger": "ledgerPath", "--amendments": "amendmentsPath" }[argument];
    if (key === undefined) throw new Error("unsupported argument");
    const value = argv[++index];
    if (values[key] !== undefined || value === undefined || value.startsWith("--")) {
      throw new Error(`${argument} must appear exactly once with a value`);
    }
    values[key] = value;
  }
  if (!values.ledgerPath || !values.amendmentsPath) throw new Error("ledger and amendments paths are required");
  return { ledgerPath: values.ledgerPath, amendmentsPath: values.amendmentsPath };
}

/**
 * source issue별로 기록된 정본 위치를 만든다.
 * hub 소유(KEEP_HUB/SPLIT_CHILDREN)와 아직 실행되지 않은 TRANSFER는 hub issue URL이 기대값이다.
 */
export function recordedLocations({ ledger, amendments }) {
  const records = new Map();
  const duplicates = [];
  const add = (sourceIssue, record) => {
    if (records.has(sourceIssue)) {
      duplicates.push(sourceIssue);
      return;
    }
    records.set(sourceIssue, record);
  };
  for (const entry of ledger?.issues ?? []) {
    const transferred = entry.disposition === "TRANSFER" && typeof entry.targetUrl === "string";
    add(entry.sourceIssue, {
      origin: "snapshot",
      hubOwned: !transferred,
      pendingTransfer: entry.disposition === "TRANSFER" && !transferred,
      expectedUrl: transferred ? entry.targetUrl : hubIssueUrl(entry.sourceIssue),
    });
  }
  for (const entry of amendments?.amendments ?? []) {
    const transferred = entry.disposition === "TRANSFER" && typeof entry.targetUrl === "string";
    add(entry.sourceIssue, {
      origin: "amendments",
      hubOwned: !transferred,
      pendingTransfer: entry.disposition === "TRANSFER" && !transferred,
      expectedUrl: transferred ? entry.targetUrl : hubIssueUrl(entry.sourceIssue),
    });
  }
  return { records, duplicates: duplicates.sort(numberCompare) };
}

export function auditMigrationState({ ledger, amendments, live }) {
  const openIssueNumbers = live?.openIssueNumbers;
  const redirects = live?.redirects;
  if (!Array.isArray(openIssueNumbers)) return ["live.openIssueNumbers: 배열 필요"];
  if (redirects == null || typeof redirects !== "object" || Array.isArray(redirects)) {
    return ["live.redirects: 객체 필요"];
  }
  const findings = [];
  const { records, duplicates } = recordedLocations({ ledger, amendments });
  for (const sourceIssue of duplicates) {
    findings.push(`#${sourceIssue}: snapshot과 amendments에 중복 기록됨`);
  }
  const open = new Set(openIssueNumbers);
  for (const [sourceIssue, record] of [...records].sort(([left], [right]) => numberCompare(left, right))) {
    const redirect = redirects[sourceIssue];
    if (redirect === undefined) findings.push(`#${sourceIssue}: hub redirect 실측값 없음`);
    else if (redirect !== record.expectedUrl) {
      if (record.pendingTransfer) findings.push(`#${sourceIssue}: 미기록 이전 감지 — 실측 ${redirect}, 기록은 PENDING`);
      else if (record.hubOwned) findings.push(`#${sourceIssue}: hub 소유 기록인데 실측 위치는 ${redirect}`);
      else findings.push(`#${sourceIssue}: 기록된 이전 대상 ${record.expectedUrl}와 실측 ${redirect} 불일치`);
    }
    if (!record.hubOwned && open.has(sourceIssue)) {
      findings.push(`#${sourceIssue}: TRANSFER 기록인데 hub open 목록에 남아 있음`);
    }
  }
  for (const sourceIssue of openIssueNumbers.filter((number) => !records.has(number)).sort(numberCompare)) {
    findings.push(`#${sourceIssue}: hub open인데 분류 기록 없음`);
  }
  return findings;
}

export async function collectLiveState({ ledger, amendments, execGh }) {
  const { records } = recordedLocations({ ledger, amendments });
  const openIssueNumbers = await readHubOpenIssueNumbers(execGh);
  const redirects = {};
  for (const sourceIssue of [...records.keys()].sort(numberCompare)) {
    const redirect = await readIssueRedirect(sourceIssue, execGh);
    if (redirect !== null) redirects[sourceIssue] = redirect;
  }
  return { openIssueNumbers, redirects };
}

async function readHubOpenIssueNumbers(execGh) {
  const issues = JSON.parse(await execGh([
    "issue", "list", "--repo", HUB_REPOSITORY, "--state", "open",
    "--limit", String(MAX_OPEN_ISSUES), "--json", "number",
  ]));
  if (!Array.isArray(issues) || !issues.every(({ number }) => Number.isInteger(number) && number > 0)) {
    throw new Error("hub open issue list is invalid");
  }
  if (issues.length >= MAX_OPEN_ISSUES) throw new Error("hub open issue list is truncated");
  return issues.map(({ number }) => number);
}

async function readIssueRedirect(sourceIssue, execGh) {
  let output;
  try {
    output = await execGh(["api", `repos/${HUB_REPOSITORY}/issues/${sourceIssue}`, "--jq", ".html_url"]);
  } catch (error) {
    // HTTP 404만 "hub에 그 번호가 없다"는 실측 결과다. 인증·rate limit·네트워크 실패를
    // 실측값 부재로 흡수하면 일시적 장애가 drift 보고와 구분되지 않으므로 fail closed한다.
    const detail = String(error?.stderr ?? "").trim();
    if (!NOT_FOUND_PATTERN.test(detail)) {
      throw new Error(`#${sourceIssue} redirect 실측 실패: ${detail || String(error?.message ?? error)}`, { cause: error });
    }
    return null;
  }
  const redirect = typeof output === "string" ? output.trim() : "";
  if (!HUB_ISSUE_URL_PATTERN.test(redirect)) {
    throw new Error(`#${sourceIssue} redirect 응답이 issue URL이 아니다: ${JSON.stringify(redirect)}`);
  }
  return redirect;
}

function hubIssueUrl(sourceIssue) {
  return `https://github.com/${HUB_REPOSITORY}/issues/${sourceIssue}`;
}

function numberCompare(left, right) {
  return left - right;
}

async function execGh(args) {
  const { stdout } = await execFileAsync("gh", args, { encoding: "utf8", maxBuffer: MAX_GH_BUFFER_BYTES });
  return stdout;
}

async function main() {
  try {
    const arguments_ = parseArguments(process.argv.slice(2));
    const [ledgerText, amendmentsText, ledgerSchemaText, amendmentsSchemaText] = await Promise.all([
      readFile(arguments_.ledgerPath, "utf8"),
      readFile(arguments_.amendmentsPath, "utf8"),
      readFile(new URL("../../contracts/repository-split-issues.schema.json", import.meta.url), "utf8"),
      readFile(new URL("../../contracts/repository-split-issue-amendments.schema.json", import.meta.url), "utf8"),
    ]);
    const ledger = JSON.parse(ledgerText);
    const amendments = JSON.parse(amendmentsText);
    const errors = [
      ...validateSchema(JSON.parse(ledgerSchemaText), ledger).errors,
      ...validateLedger(ledger),
      ...validateSchema(JSON.parse(amendmentsSchemaText), amendments).errors,
      ...validateAmendments(amendments, { ledger }),
    ];
    if (errors.length !== 0) throw new Error(`offline validation failed: ${errors.join("; ")}`);
    const live = await collectLiveState({ ledger, amendments, execGh });
    const findings = auditMigrationState({ ledger, amendments, live });
    if (findings.length !== 0) {
      console.error(findings.map((finding) => `- ${finding}`).join("\n"));
      process.exitCode = 1;
      return;
    }
    console.log(`live audit finding 0건 (기록 ${Object.keys(live.redirects).length}건, hub open ${live.openIssueNumbers.length}건)`);
  } catch (error) {
    console.error(`live migration audit was not completed: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}

if (isMainModule(import.meta.url)) await main();
