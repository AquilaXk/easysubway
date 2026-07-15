#!/usr/bin/env node

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { canonicalScopeHash } from "../datapack/build-launch-denominator-report.mjs";

const args = parseArgs(process.argv.slice(2));
const cwd = process.cwd();
const repoRoot = resolvePath(arg("repoRoot", "repo-root") ?? ".");
const appRoot = resolvePath(arg("appRoot", "app-root") ?? path.join(repoRoot, "apps/mobile"));
const outputPath = args.output ? resolvePath(args.output) : null;

if (!outputPath) {
  fail("--output is required");
}

const generatedAt = new Date().toISOString();
const testedAt = arg("testedAt", "tested-at") ?? generatedAt;
const evidenceRoot = normalizeEvidenceRoot(
  arg("evidenceRoot", "evidence-root") ?? ".codex/evidence/release/rc-evidence-manifest/<rc-or-run>/",
);
const appVersion = readFlutterVersion(path.join(appRoot, "pubspec.yaml"));
const dataPackManifestPath = resolvePath(
  arg("dataPackManifest", "data-pack-manifest") ?? path.join(appRoot, "assets/datapacks/metro_map_pack/manifest.json"),
);
const dataPackManifest = readJsonIfExists(dataPackManifestPath);
const backendIdentity = readBackendIdentity(args);
const gateStatuses = parsePairs(arg("gateStatus", "gate-status"));
const evidenceStatuses = parsePairs(arg("evidenceStatus", "evidence-status"));
const evidencePaths = parsePairs(arg("evidencePath", "evidence-path"));
const expectedValues = parsePairs(args.expect);
const gitSha = arg("gitSha", "git-sha") ?? process.env.GITHUB_SHA ?? requiredGitSha();
const launchScope = readJsonIfExists(path.join(repoRoot, "apps/mobile/release/production-datapack-scope.json"));
if (!launchScope?.routingLaunchScope || !launchScope?.identityMatrix) {
  fail("production routing launch scope and identity matrix are required");
}
if (!launchScope?.nationwideRoadmapScope) {
  fail("production nationwide roadmap scope is required");
}

const identity = {
  gitSha,
  appVersionName: appVersion.name,
  versionCode: appVersion.code,
  aabSha256: sha256FileIfExists(args.aab),
  backendImageDigest: backendIdentity.backendImageDigest,
  backendArtifactSha256: backendIdentity.backendArtifactSha256,
  dataPackManifestSha256: sha256FileIfExists(dataPackManifestPath),
  releaseSequence: arg("releaseSequence", "release-sequence") ?? dataPackManifest?.releaseSequence ?? dataPackManifest?.pack_version ?? null,
  routeContractVersion: arg("routeContractVersion", "route-contract-version") ?? "route-map-contract-v1",
  realtimeContractVersion: arg("realtimeContractVersion", "realtime-contract-version") ?? readRealtimeContractVersion(repoRoot),
  launchScopeId: launchScope.routingLaunchScope.id,
  launchScopeSha256: canonicalScopeHash(launchScope.routingLaunchScope),
  nationwideRoadmapScopeId: launchScope.nationwideRoadmapScope.id,
  nationwideRoadmapScopeSha256: canonicalScopeHash(launchScope.nationwideRoadmapScope),
  identityLinkageMatrixSha256: canonicalScopeHash(launchScope.identityMatrix),
};

const evidenceEntries = requiredEvidenceEntries(
  testedAt,
  evidenceRoot,
  args.device,
  arg("androidVersion", "android-version"),
  evidenceStatuses,
  evidencePaths,
  generatedAt,
);
const blockers = [
  ...identityBlockers(identity),
  ...expectedMismatchBlockers(identity, expectedValues),
  ...gateStatusBlockers(gateStatuses),
  ...openP0Blockers(arg("openAndroidP0Count", "open-android-p0-count")),
  ...evidenceBlockers(evidenceEntries),
];

const manifest = {
  schemaVersion: 1,
  releaseGate: "rc-evidence-manifest",
  issue: 1020,
  applicationId: "easysubway",
  androidApplicationId: "com.easysubway.app",
  generatedAt,
  ...identity,
  rcIdentity: identity,
  evidenceEntries,
  readiness: {
    status: blockers.length === 0 ? "GO" : "NO_GO",
    gateStatus: blockers.length === 0 ? "SATISFIED" : "BLOCKED_RC_EVIDENCE",
    blockers,
    openAndroidP0Count: Number.parseInt(arg("openAndroidP0Count", "open-android-p0-count") ?? "0", 10),
    gateStatuses,
  },
  sourceManifests: {
    androidRcEvidenceManifest: "apps/mobile/release/android-rc-store-evidence.json",
    signedReleaseArtifactGate: "apps/mobile/release/signed-release-artifact-gate.json",
    releaseGovernanceGate: "apps/mobile/release/release-governance-gate.json",
    dataPackManifest: path.relative(repoRoot, dataPackManifestPath),
  },
};

mkdirSync(path.dirname(outputPath), { recursive: true });
writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);

if (arg("failOnBlocked", "fail-on-blocked") === "true" && blockers.length > 0) {
  fail(`RC evidence manifest is blocked: ${blockers.map((blocker) => blocker.id).join(", ")}`);
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const raw = values[index];
    if (!raw.startsWith("--")) {
      fail(`Unexpected argument: ${raw}`);
    }
    const withoutPrefix = raw.slice(2);
    const equalsIndex = withoutPrefix.indexOf("=");
    const key = equalsIndex === -1 ? withoutPrefix : withoutPrefix.slice(0, equalsIndex);
    const value = equalsIndex === -1 ? values[++index] : withoutPrefix.slice(equalsIndex + 1);
    if (value === undefined || value.startsWith("--")) {
      fail(`Missing value for --${key}`);
    }
    if (parsed[key] === undefined) {
      parsed[key] = value;
    } else if (Array.isArray(parsed[key])) {
      parsed[key].push(value);
    } else {
      parsed[key] = [parsed[key], value];
    }
  }
  return parsed;
}

function resolvePath(value) {
  return path.resolve(cwd, value);
}

function arg(camelName, kebabName) {
  return args[camelName] ?? args[kebabName];
}

function readFlutterVersion(pubspecPath) {
  const pubspec = readFileSync(pubspecPath, "utf8");
  const match = pubspec.match(/^version:\s*([0-9A-Za-z.+-]+)\s*$/m);
  if (!match) {
    fail(`version not found in ${pubspecPath}`);
  }
  const [name, code] = match[1].split("+");
  if (!name || !code) {
    fail(`Flutter version must include build number: ${match[1]}`);
  }
  return { name, code };
}

function sha256FileIfExists(filePath) {
  if (!filePath) {
    return null;
  }
  const resolved = resolvePath(filePath);
  if (!existsSync(resolved)) {
    return null;
  }
  return createHash("sha256").update(readFileSync(resolved)).digest("hex");
}

function readJsonIfExists(filePath) {
  if (!filePath || !existsSync(filePath)) {
    return null;
  }
  return JSON.parse(readFileSync(filePath, "utf8"));
}

function readBackendIdentity(parsedArgs) {
  const backendImageDigest = arg("backendImageDigest", "backend-image-digest");
  const backendArtifact = arg("backendArtifact", "backend-artifact");
  const backendImageInspect = arg("backendImageInspect", "backend-image-inspect");
  if (backendImageDigest) {
    return { backendImageDigest, backendArtifactSha256: null };
  }
  if (backendArtifact) {
    return { backendImageDigest: null, backendArtifactSha256: sha256FileIfExists(backendArtifact) };
  }
  if (!backendImageInspect) {
    return { backendImageDigest: null, backendArtifactSha256: null };
  }

  const inspectPath = resolvePath(backendImageInspect);
  if (!existsSync(inspectPath)) {
    return { backendImageDigest: null, backendArtifactSha256: null };
  }
  const inspect = JSON.parse(readFileSync(inspectPath, "utf8"));
  const firstImage = Array.isArray(inspect) ? inspect[0] : inspect;
  const repoDigest = firstImage?.RepoDigests?.find((digest) => digest.includes("@sha256:"));
  const imageId = typeof firstImage?.Id === "string" && firstImage.Id.startsWith("sha256:")
    ? firstImage.Id
    : null;
  return {
    backendImageDigest: repoDigest?.split("@").at(-1) ?? imageId,
    backendArtifactSha256: repoDigest || imageId ? null : sha256FileIfExists(inspectPath),
  };
}

function readRealtimeContractVersion(rootDir) {
  const contract = readJsonIfExists(path.join(rootDir, "tools/realtime/seoul-topis-provider-contract.json"));
  if (!contract) {
    return "realtime-contract-v1";
  }
  return `${contract.providerId ?? "realtime"}-schema-v${contract.schemaVersion ?? 1}`;
}

function parsePairs(value) {
  const values = value === undefined ? [] : Array.isArray(value) ? value : [value];
  return Object.fromEntries(values.map((entry) => {
    const separatorIndex = entry.indexOf("=");
    if (separatorIndex === -1) {
      fail(`Expected key=value pair: ${entry}`);
    }
    return [entry.slice(0, separatorIndex), entry.slice(separatorIndex + 1)];
  }));
}

function requiredEvidenceEntries(baseTestedAt, rootPath, device, androidVersion, statuses, paths, generatedAt) {
  const sourceEntries = [
    ["rc_device_qa", 571],
    ["production_datapack", 547],
    ["signed_rc_store_submission", 1015],
    ["play_generated_install", 1016],
    ["store_privacy_submission", 1018],
    ["backend_operations", 1017],
    ["post_launch_operations", 1019],
    ["android_release_quality", 1021],
    ["abuse_penetration_rehearsal", 1022],
    ["container_hardening", 1914],
  ];
  const knownIds = new Set(sourceEntries.map(([id]) => id));
  for (const id of [...Object.keys(statuses), ...Object.keys(paths)]) {
    if (!knownIds.has(id)) fail(`Unknown evidence entry: ${id}`);
  }
  for (const [id, status] of Object.entries(statuses)) {
    if (!["SATISFIED", "BLOCKED_EXTERNAL", "PENDING_LOCAL_EVIDENCE"].includes(status)) {
      fail(`Invalid evidence status for ${id}: ${status}`);
    }
    if (status === "SATISFIED" && !paths[id]) {
      fail(`SATISFIED evidence entry requires --evidence-path: ${id}`);
    }
    if (status === "SATISFIED" && !existsSync(resolvePath(paths[id]))) {
      fail(`SATISFIED evidence path does not exist for ${id}: ${paths[id]}`);
    }
  }
  return sourceEntries.map(([id, sourceIssue]) => {
    const evidencePaths = [`${rootPath}${id}/`];
    if (paths[id]) evidencePaths.push(paths[id]);
    const evidence = statuses[id] === "SATISFIED" ? readJsonIfExists(resolvePath(paths[id])) : null;
    if (statuses[id] === "SATISFIED" && (
      evidence?.evidenceValidity?.testedAt === undefined
      || evidence?.evidenceValidity?.expiresWhen === undefined
    )) {
      fail(`SATISFIED evidence entry requires evidenceValidity.testedAt and evidenceValidity.expiresWhen: ${id}`);
    }
    const evidenceTestedAt = evidence?.evidenceValidity?.testedAt ?? baseTestedAt;
    const evidenceExpiresWhen = evidence?.evidenceValidity?.expiresWhen ?? addDays(baseTestedAt, 14);
    if (statuses[id] === "SATISFIED" && (
      !Number.isFinite(Date.parse(evidenceTestedAt))
      || !Number.isFinite(Date.parse(evidenceExpiresWhen))
      || Date.parse(evidenceTestedAt) > Date.parse(generatedAt)
      || Date.parse(evidenceExpiresWhen) < Date.parse(generatedAt)
      || Date.parse(evidenceExpiresWhen) < Date.parse(baseTestedAt)
      || Date.parse(evidenceExpiresWhen) < Date.parse(evidenceTestedAt)
    )) {
      fail(`SATISFIED evidence entry has invalid, future, or expired evidenceValidity: ${id}`);
    }
    return {
      id,
      sourceIssue,
      device: device ?? "local_android_emulator",
      androidVersion: androidVersion ?? "android-15-or-16",
      testedAt: evidenceTestedAt,
      evidencePaths,
      expiresWhen: evidenceExpiresWhen,
      status: statuses[id] ?? "PENDING_LOCAL_EVIDENCE",
    };
  });
}

function normalizeEvidenceRoot(rootPath) {
  return rootPath.endsWith("/") ? rootPath : `${rootPath}/`;
}

function addDays(isoDate, days) {
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) {
    fail(`Invalid testedAt value: ${isoDate}`);
  }
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString();
}

function identityBlockers(values) {
  const required = [
    "gitSha",
    "appVersionName",
    "versionCode",
    "aabSha256",
    "dataPackManifestSha256",
    "releaseSequence",
    "routeContractVersion",
    "realtimeContractVersion",
    "launchScopeId",
    "launchScopeSha256",
    "nationwideRoadmapScopeId",
    "nationwideRoadmapScopeSha256",
    "identityLinkageMatrixSha256",
  ];
  const blockers = required
    .filter((field) => !values[field])
    .map((field) => ({ id: `missing_${field}`, severity: "P0", reason: `${field} is required for RC identity` }));
  if (!values.backendImageDigest && !values.backendArtifactSha256) {
    blockers.push({
      id: "missing_backend_identity",
      severity: "P0",
      reason: "backendImageDigest or backendArtifactSha256 is required for RC identity",
    });
  }
  return blockers;
}

function expectedMismatchBlockers(values, expected) {
  return Object.entries(expected)
    .filter(([key, expectedValue]) => `${values[key] ?? ""}` !== expectedValue)
    .map(([key, expectedValue]) => ({
      id: `mismatch_${key}`,
      severity: "P0",
      reason: `${key} expected ${expectedValue} but got ${values[key] ?? "missing"}`,
    }));
}

function gateStatusBlockers(statuses) {
  return Object.entries(statuses)
    .filter(([, status]) => status !== "SATISFIED" && status !== "DEFERRED_OUT_OF_SCOPE")
    .map(([gate, status]) => ({
      id: `gate_${gate}_${status}`.toLowerCase(),
      severity: "P0",
      reason: `${gate} gate status is ${status}`,
    }));
}

function openP0Blockers(value) {
  const count = Number.parseInt(value ?? "0", 10);
  if (Number.isNaN(count) || count < 0) {
    fail("--open-android-p0-count must be a non-negative integer");
  }
  return count > 0
    ? [{ id: "open_android_p0", severity: "P0", reason: `${count} Android P0 issue(s) are open` }]
    : [];
}

function evidenceBlockers(entries) {
  return entries
    .filter((entry) => entry.status !== "SATISFIED")
    .map((entry) => ({
      id: `pending_${entry.id}`,
      severity: "P0",
      reason: `Evidence entry ${entry.id} from #${entry.sourceIssue} is not satisfied`,
    }));
}

function requiredGitSha() {
  fail("--git-sha or GITHUB_SHA is required");
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
