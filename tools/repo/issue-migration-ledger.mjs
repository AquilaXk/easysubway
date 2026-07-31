const HUB_REPOSITORY = "AquilaXk/easysubway";
const ALLOWED_REPOSITORIES = new Set([
  HUB_REPOSITORY,
  "AquilaXk/easysubway-data",
  "AquilaXk/easysubway-platform",
  "AquilaXk/easysubway-backend",
  "AquilaXk/easysubway-mobile",
]);
const CHILD_REPOSITORIES = ["AquilaXk/easysubway-data", "AquilaXk/easysubway-mobile"];
const APPROVAL_URL_PATTERN = new RegExp(
  `^https://github\\.com/${escapeRegExp(HUB_REPOSITORY)}/issues/\\d+#issuecomment-\\d+$`,
);
const DISPOSITIONS = new Set(["KEEP_HUB", "TRANSFER", "SPLIT_CHILDREN"]);
const REVIEWED_GROUPS = [
  {
    disposition: "KEEP_HUB",
    targetRepository: HUB_REPOSITORY,
    sourceIssues: [1019, 1020, 1022, 1393, 1414, 2050, 2058, 2065, 2126, 2268, 2406, 2526, 2548, 2627, 2674, 2690, 2691],
  },
  {
    disposition: "TRANSFER",
    targetRepository: "AquilaXk/easysubway-data",
    sourceIssues: [2138, 2523, 2533, 2607, 2608, 2610, 2611, 2684],
  },
  {
    disposition: "TRANSFER",
    targetRepository: "AquilaXk/easysubway-backend",
    sourceIssues: [2095, 2544, 2545, 2622, 2623, 2624, 2625, 2626, 2667, 2675, 2676, 2677],
  },
  {
    disposition: "TRANSFER",
    targetRepository: "AquilaXk/easysubway-mobile",
    sourceIssues: [571, 1016, 1021, 1918, 2055, 2524, 2525, 2535, 2536, 2537, 2538, 2539, 2540, 2541, 2542, 2543, 2547, 2586, 2591, 2596, 2600, 2612, 2613, 2617, 2619, 2620, 2621, 2628, 2629, 2630, 2678, 2679, 2680],
  },
  { disposition: "SPLIT_CHILDREN", targetRepository: null, sourceIssues: [2605] },
];

export function validateLedger(ledger, { openIssueNumbers, requirePending = false } = {}) {
  const errors = [];
  const issues = ledger?.issues;
  if (!Array.isArray(issues)) return ["issues: 배열 필요"];

  const seen = new Set();
  for (const [index, entry] of issues.entries()) {
    const path = `issues[${index}]`;
    const sourceIssue = entry?.sourceIssue;
    if (seen.has(sourceIssue)) errors.push(`issues: sourceIssue ${sourceIssue} 중복`);
    seen.add(sourceIssue);
    if (entry?.reason == null || String(entry.reason).trim() === "") errors.push(`${path}.reason: reason이 필요함`);
    const sourceUrlNumber = sourceIssueNumberFromUrl(entry?.sourceUrl);
    if (sourceUrlNumber === null) errors.push(`${path}.sourceUrl: source issue GitHub URL 불량`);
    else if (sourceUrlNumber !== sourceIssue) errors.push(`${path}.sourceUrl: sourceIssue와 URL 번호 불일치`);
    if (!DISPOSITIONS.has(entry?.disposition)) errors.push(`${path}.disposition: 지원하지 않는 disposition`);
    if (!ALLOWED_REPOSITORIES.has(entry?.targetRepository) && entry?.targetRepository !== null) {
      errors.push(`${path}.targetRepository: 허용되지 않은 repository`);
    }
    if (entry?.disposition === "TRANSFER" && !isApprovedTransferTarget(entry.targetRepository)) {
      errors.push(`${path}.targetRepository: TRANSFER는 approved non-hub target이 필요함`);
    }
    if (entry?.disposition === "KEEP_HUB" && entry.targetRepository !== HUB_REPOSITORY) {
      errors.push(`${path}.targetRepository: KEEP_HUB target은 sourceRepository여야 함`);
    }
    if (entry?.disposition === "SPLIT_CHILDREN") {
      if (entry.targetRepository !== null) errors.push(`${path}.targetRepository: SPLIT_CHILDREN target은 null이어야 함`);
      if (!sameValues(entry.childRepositories, CHILD_REPOSITORIES)) {
        errors.push(`${path}.childRepositories: data와 mobile child repository가 정확히 필요함`);
      }
      if (entry.childIssueUrls === undefined) errors.push(`${path}.childIssueUrls: data와 mobile child issue URL이 필요함`);
      else validateChildIssueUrls(entry.childIssueUrls, entry.childRepositories, `${path}.childIssueUrls`, errors);
    } else if (entry?.childRepositories !== undefined) {
      errors.push(`${path}.childRepositories: SPLIT_CHILDREN에서만 허용됨`);
    }
    if (entry?.disposition !== "SPLIT_CHILDREN" && entry?.childIssueUrls !== undefined) {
      errors.push(`${path}.childIssueUrls: SPLIT_CHILDREN에서만 허용됨`);
    }
    const reviewed = reviewedGroupFor(sourceIssue);
    if (reviewed === undefined) errors.push(`${path}: frozen reviewed mapping에 없는 sourceIssue`);
    else if (reviewed.disposition !== entry?.disposition) errors.push(`${path}.disposition: frozen reviewed mapping과 불일치`);
    else if (reviewed.targetRepository !== entry?.targetRepository) errors.push(`${path}.targetRepository: frozen reviewed mapping과 불일치`);

    const pending = isPending(entry);
    if (entry?.disposition === "TRANSFER") {
      if (!isTransferExecutionState(entry)) errors.push(`${path}.execution: 허용되지 않은 TRANSFER execution state`);
    } else if (!pending) {
      errors.push(`${path}.execution: ${entry?.disposition}은 PENDING만 허용`);
    }
    if (requirePending && !pending) errors.push(`${path}.execution: requirePending에서는 PENDING만 허용`);
  }

  if (ledger?.inventory?.openIssueCount !== seen.size) {
    errors.push("inventory.openIssueCount: issues unique sourceIssue 수와 불일치");
  }
  const missingReviewed = REVIEWED_GROUPS.flatMap(({ sourceIssues }) => sourceIssues)
    .filter((sourceIssue) => !seen.has(sourceIssue))
    .sort(numberCompare);
  if (missingReviewed.length) errors.push(`issues: frozen reviewed mapping 누락 (${missingReviewed.join(", ")})`);
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
  return (ledger?.issues ?? []).filter((entry) => (
    entry.targetRepository === targetRepository || entry.childRepositories?.includes(targetRepository)
  ));
}

export function entryForSourceIssue(ledger, sourceIssue) {
  return (ledger?.issues ?? []).find((entry) => entry.sourceIssue === sourceIssue);
}

function sourceIssueNumberFromUrl(value) {
  const match = typeof value === "string"
    ? /^https:\/\/github\.com\/AquilaXk\/easysubway\/issues\/(\d+)$/.exec(value) : null;
  return match === null ? null : Number(match[1]);
}

function isApprovedTransferTarget(value) {
  return typeof value === "string" && value !== HUB_REPOSITORY && ALLOWED_REPOSITORIES.has(value);
}

function reviewedGroupFor(sourceIssue) {
  return REVIEWED_GROUPS.find(({ sourceIssues }) => sourceIssues.includes(sourceIssue));
}

function isPending(entry) {
  return entry?.executionApproval === null && entry?.targetUrl === null && entry?.transferredAt === null;
}

function isTransferExecutionState(entry) {
  if (isPending(entry)) return true;
  const approvalValid = typeof entry?.executionApproval === "string"
    && APPROVAL_URL_PATTERN.test(entry.executionApproval);
  const approved = approvalValid && entry.targetUrl === null && entry.transferredAt === null;
  const transferred = approvalValid && isTargetIssueUrl(entry.targetUrl, entry.targetRepository)
    && isDateTime(entry.transferredAt);
  return approved || transferred;
}

function isTargetIssueUrl(value, targetRepository) {
  return typeof value === "string" && typeof targetRepository === "string"
    && new RegExp(`^https://github\\.com/${escapeRegExp(targetRepository)}/issues/\\d+$`).test(value);
}

function validateChildIssueUrls(childIssueUrls, childRepositories, path, errors) {
  if (childIssueUrls === undefined) return;
  if (childIssueUrls === null || typeof childIssueUrls !== "object" || Array.isArray(childIssueUrls)) {
    errors.push(`${path}: childRepositories key와 정확히 일치해야 함`);
    return;
  }
  const expectedRepositories = Array.isArray(childRepositories) ? childRepositories : [];
  const repositories = Object.keys(childIssueUrls);
  if (!sameRepositoryKeys(repositories, expectedRepositories)) {
    errors.push(`${path}: childRepositories key와 정확히 일치해야 함`);
  }
  const urls = Object.values(childIssueUrls);
  if (new Set(urls).size !== urls.length) errors.push(`${path}: child issue URL 중복`);
  for (const repository of expectedRepositories) {
    if (!(repository in childIssueUrls)) continue;
    validateChildIssueUrl(childIssueUrls[repository], repository, `${path}.${repository}`, errors);
  }
}

function sameRepositoryKeys(value, expected) {
  return new Set(expected).size === expected.length && sameValues(value, expected);
}

function validateChildIssueUrl(value, repository, path, errors) {
  const match = typeof value === "string"
    ? /^https:\/\/github\.com\/([^/]+\/[^/]+)\/issues\/([1-9]\d*)$/.exec(value) : null;
  if (match === null) {
    errors.push(`${path}: positive GitHub issue URL 불량`);
  } else if (match[1] !== repository) {
    errors.push(`${path}: repository와 URL repository 불일치`);
  }
}

function isDateTime(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value)) return false;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 19) === value.slice(0, 19);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function sameValues(value, expected) {
  return Array.isArray(value) && value.length === expected.length
    && expected.every((item) => value.includes(item));
}

function numberCompare(left, right) {
  return left - right;
}
