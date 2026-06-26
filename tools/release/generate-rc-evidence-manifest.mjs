#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

const args = parseArgs(process.argv.slice(2));
const cwd = process.cwd();
const repoRoot = resolvePath(arg("repoRoot", "repo-root") ?? ".");
const appRoot = resolvePath(arg("appRoot", "app-root") ?? path.join(repoRoot, "apps/mobile"));
const outputPath = args.output ? resolvePath(args.output) : null;

if (!outputPath) {
  fail("--output is required");
}

const testedAt = arg("testedAt", "tested-at") ?? new Date().toISOString();
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
const expectedValues = parsePairs(args.expect);
const gitSha = arg("gitSha", "git-sha") ?? process.env.GITHUB_SHA ?? gitRevParse(repoRoot);

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
};

const evidenceEntries = requiredEvidenceEntries(testedAt, evidenceRoot, args.device, arg("androidVersion", "android-version"));
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
  issue: 926,
  applicationId: "easysubway",
  androidApplicationId: "com.easysubway.app",
  generatedAt: new Date().toISOString(),
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
  return {
    backendImageDigest: repoDigest?.split("@").at(-1) ?? null,
    backendArtifactSha256: createHash("sha256").update(readFileSync(inspectPath)).digest("hex"),
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

function requiredEvidenceEntries(baseTestedAt, rootPath, device, androidVersion) {
  const sourceEntries = [
    ["rc_device_qa", 571],
    ["signed_rc_store_submission", 907],
    ["android_release_quality", 917],
  ];
  return sourceEntries.map(([id, sourceIssue]) => ({
    id,
    sourceIssue,
    device: device ?? "local_android_emulator",
    androidVersion: androidVersion ?? "android-15-or-16",
    testedAt: baseTestedAt,
    evidencePaths: [`${rootPath}${id}/`],
    expiresWhen: addDays(baseTestedAt, 14),
    status: "PENDING_LOCAL_EVIDENCE",
  }));
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

function gitRevParse(rootDir) {
  return execFileSync("git", ["rev-parse", "HEAD"], { cwd: rootDir, encoding: "utf8" }).trim();
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
