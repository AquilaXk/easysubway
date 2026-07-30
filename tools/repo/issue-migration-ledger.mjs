const HUB_REPOSITORY = "AquilaXk/easysubway";
const ALLOWED_REPOSITORIES = new Set([
  HUB_REPOSITORY,
  "AquilaXk/easysubway-data",
  "AquilaXk/easysubway-platform",
  "AquilaXk/easysubway-backend",
  "AquilaXk/easysubway-mobile",
]);
const CHILD_REPOSITORIES = ["AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile"];
const DISPOSITIONS = new Set(["KEEP_HUB", "TRANSFER", "SPLIT_CHILDREN"]);

export function validateLedger(ledger, { openIssueNumbers } = {}) {
  const errors = [];
  const issues = ledger?.issues;
  if (!Array.isArray(issues)) return ["issues: 배열 필요"];

  const seen = new Set();
  for (const [index, entry] of issues.entries()) {
    const path = `issues[${index}]`;
    const sourceIssue = entry?.sourceIssue;
    if (seen.has(sourceIssue)) errors.push(`issues: sourceIssue ${sourceIssue} 중복`);
    seen.add(sourceIssue);
    if (!DISPOSITIONS.has(entry?.disposition)) errors.push(`${path}.disposition: 지원하지 않는 disposition`);
    if (entry?.reason == null || String(entry.reason).trim() === "") errors.push(`${path}.reason: reason이 필요함`);
    if (!isSourceIssueUrl(entry?.sourceUrl)) errors.push(`${path}.sourceUrl: source issue GitHub URL 불량`);
    if (!ALLOWED_REPOSITORIES.has(entry?.targetRepository) && entry?.targetRepository !== null) {
      errors.push(`${path}.targetRepository: 허용되지 않은 repository`);
    }
    if (entry?.disposition === "TRANSFER" && entry.targetRepository === HUB_REPOSITORY) {
      errors.push(`${path}.targetRepository: TRANSFER는 hub target을 허용하지 않음`);
    }
    if (entry?.disposition === "KEEP_HUB" && entry.targetRepository !== HUB_REPOSITORY) {
      errors.push(`${path}.targetRepository: KEEP_HUB target은 sourceRepository여야 함`);
    }
    if (entry?.disposition === "SPLIT_CHILDREN") {
      if (entry.targetRepository !== null) errors.push(`${path}.targetRepository: SPLIT_CHILDREN target은 null이어야 함`);
      if (!sameValues(entry.childRepositories, CHILD_REPOSITORIES)) {
        errors.push(`${path}.childRepositories: data와 mobile child repository가 정확히 필요함`);
      }
    } else if (entry?.childRepositories !== undefined) {
      errors.push(`${path}.childRepositories: SPLIT_CHILDREN에서만 허용됨`);
    }
    if (entry?.executionApproval !== null) errors.push(`${path}.executionApproval: baseline에서는 null이어야 함`);
    if (entry?.transferredAt != null && entry?.targetUrl == null) {
      errors.push(`${path}.transferredAt: targetUrl 없이 transferredAt을 지정할 수 없음`);
    }
    if (entry?.targetUrl !== null) errors.push(`${path}.targetUrl: baseline에서는 null이어야 함`);
    if (entry?.transferredAt !== null) errors.push(`${path}.transferredAt: baseline에서는 null이어야 함`);
  }

  if (ledger?.inventory?.openIssueCount !== seen.size) {
    errors.push("inventory.openIssueCount: issues unique sourceIssue 수와 불일치");
  }
  if (openIssueNumbers !== undefined) {
    const expected = new Set(openIssueNumbers);
    const missing = [...expected].filter((number) => !seen.has(number)).sort(numberCompare);
    const extra = [...seen].filter((number) => !expected.has(number)).sort(numberCompare);
    if (missing.length || extra.length) {
      errors.push(`issues: open issue inventory 불일치 (누락: ${missing.join(", ") || "없음"}; 초과: ${extra.join(", ") || "없음"})`);
    }
  }
  return errors;
}

export function entriesForTarget(ledger, targetRepository) {
  return (ledger?.issues ?? []).filter((entry) => entry.targetRepository === targetRepository);
}

export function entryForSourceIssue(ledger, sourceIssue) {
  return (ledger?.issues ?? []).find((entry) => entry.sourceIssue === sourceIssue);
}

function isSourceIssueUrl(value) {
  return typeof value === "string" && /^https:\/\/github\.com\/AquilaXk\/easysubway\/issues\/\d+$/.test(value);
}

function sameValues(value, expected) {
  return Array.isArray(value) && value.length === expected.length
    && [...value].sort().every((item, index) => item === expected[index]);
}

function numberCompare(left, right) {
  return left - right;
}
