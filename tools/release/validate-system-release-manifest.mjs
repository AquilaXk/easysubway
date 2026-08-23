#!/usr/bin/env node

import { createHash } from "node:crypto";
import { existsSync, lstatSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { isSemVer } from "./lib/semver.mjs";
import { codepointCompare } from "../lib/codepoint-compare.mjs";

const slots = ["mobile", "backend", "data", "platform"];
const canonicalHubRepository = "AquilaXk/easysubway";
const canonicalRepositories = Object.fromEntries(slots.map((slot) => [slot, `AquilaXk/easysubway-${slot}`]));
const allowedRepositories = Object.fromEntries(slots.map((slot) => [slot, new Set(["AquilaXk/easysubway", canonicalRepositories[slot]])]));
const journeyFallbackSuccessCounters = [
  "hubSource", "legacy", "local", "routeV1", "routeV2", "stale", "previous", "alternateProvider", "bestEffort",
];
const governanceInventoryPaths = [
  "contracts/release/system-release-manifest.schema.json",
  "contracts/release/system-release-governance-inventory.schema.json",
  "release/product-gates/rc-evidence-manifest-contract.json",
  "tools/release/generate-rc-evidence-manifest.mjs",
  "tools/release/validate-system-release-manifest.mjs",
];

export function calculateProductIdentity(manifest) {
  return sha256Canonical({
    identityVersion: 1,
    contracts: manifest?.contracts ?? null,
    journeyV3: manifest?.journeyV3 ?? null,
    components: slots.map((slot) => componentIdentity(manifest?.[slot])),
  });
}

export function calculateGovernanceRevision(governanceInventory) {
  return sha256Canonical({
    identityVersion: 1,
    schemaVersion: governanceInventory?.schemaVersion,
    artifactKind: governanceInventory?.artifactKind,
    files: [...(governanceInventory?.files ?? [])]
      .sort((left, right) => codepointCompare(left?.path ?? "", right?.path ?? "")),
  });
}

export function classifySystemReleaseChange({
  previousManifest,
  currentManifest,
  componentSchema,
  systemSchema,
  issueRefSchema,
  previousGovernanceInventory,
  currentGovernanceInventory,
  governanceInventorySchema,
  repoRoot,
}) {
  const sharedValidation = {
    componentSchema,
    systemSchema,
    issueRefSchema,
    governanceInventorySchema,
    repoRoot,
  };
  if (validateSystemReleaseManifest({
    manifest: previousManifest,
    governanceInventory: previousGovernanceInventory,
    ...sharedValidation,
  }).length > 0) {
    throw new Error("previous system release manifest is invalid");
  }
  if (validateSystemReleaseManifest({
    manifest: currentManifest,
    governanceInventory: currentGovernanceInventory,
    ...sharedValidation,
  }).length > 0) {
    throw new Error("current system release manifest is invalid");
  }
  if (calculateProductIdentity(previousManifest) !== calculateProductIdentity(currentManifest)) return "PRODUCT_CHANGE";
  if (previousManifest?.governanceRevisionSha256 !== currentManifest?.governanceRevisionSha256) return "GOVERNANCE_CHANGE";
  if (
    previousManifest?.hubObservedRevision?.repository !== currentManifest?.hubObservedRevision?.repository
    || previousManifest?.hubObservedRevision?.gitSha !== currentManifest?.hubObservedRevision?.gitSha
  ) return "OBSERVATION_ONLY_CHANGE";
  throw new Error("system release change has no classified identity difference");
}

export function validateGovernanceInventory({ governanceInventory, governanceInventorySchema, repoRoot }) {
  const errors = governanceInventorySchema
    ? validateSchema(governanceInventorySchema, governanceInventory).errors.map((error) => `governance inventory${error.slice(1)}`)
    : [];
  const files = governanceInventory?.files;
  if (!Array.isArray(files)) return [...errors, "governance inventory: files must be an array"];
  const paths = files.map((entry) => entry?.path);
  if (new Set(paths).size !== paths.length) errors.push("governance inventory: duplicate path");
  if (paths.join("\n") !== governanceInventoryPaths.join("\n")) {
    errors.push("governance inventory: files must exactly match the closed release governance scope");
  }
  if (repoRoot) {
    for (const entry of files) {
      const filePath = path.join(repoRoot, entry?.path ?? "");
      if (!entry?.path || !existsSync(filePath)) {
        errors.push("governance inventory: tracked file is missing");
      } else if (!lstatSync(filePath).isFile()) {
        errors.push(`governance inventory: tracked path must be a regular file: ${entry.path}`);
      } else if (sha256File(filePath) !== entry.sha256) {
        errors.push(`governance inventory: SHA-256 mismatch for ${entry.path}`);
      }
    }
  }
  return [...new Set(errors)];
}

export function validateSystemReleaseManifest({
  manifest, componentSchema, systemSchema, issueRefSchema, governanceInventory, governanceInventorySchema, repoRoot,
}) {
  const errors = [...validateSchema(systemSchema, manifest).errors];
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) return redact(errors);

  for (const slot of slots) {
    const component = manifest[slot];
    if (!component || typeof component !== "object" || Array.isArray(component)) continue;
    errors.push(...validateSchema(componentSchema, component).errors.map((error) => `${slot}${error.slice(1)}`));
    if (component.component !== slot) errors.push(`${slot}: component must match slot`);
    if (!allowedRepositories[slot].has(component.repository)) errors.push(`${slot}: repository is not allowed for slot`);
    if (Array.isArray(component.issueRefs)) {
      for (const issueRef of component.issueRefs) {
        errors.push(...validateSchema(issueRefSchema, issueRef).errors.map(() => `${slot}: invalid issue ref`));
      }
    }
  }
  if (Array.isArray(manifest.issueRefs)) {
    for (const issueRef of manifest.issueRefs) {
      errors.push(...validateSchema(issueRefSchema, issueRef).errors.map(() => "system: invalid issue ref"));
    }
  }
  errors.push(...validateGovernanceInventory({ governanceInventory, governanceInventorySchema, repoRoot }));
  if (manifest.hubObservedRevision?.repository !== canonicalHubRepository) errors.push("hub observed revision: repository must be canonical");
  if (manifest.productIdentitySha256 !== calculateProductIdentity(manifest)) errors.push("system: product identity SHA-256 mismatch");
  if (manifest.governanceRevisionSha256 !== calculateGovernanceRevision(governanceInventory)) {
    errors.push("system: governance revision SHA-256 mismatch");
  }
  if (!isSemVer(manifest.contracts?.version)) errors.push("system: contracts version must be SemVer");

  const components = slots.map((slot) => manifest[slot]).filter(Boolean);
  if (!Number.isSafeInteger(manifest.mobile?.artifactIdentity?.versionCode)) errors.push("mobile: versionCode must be a safe integer");
  if (!Number.isSafeInteger(manifest.data?.artifactIdentity?.releaseSequence)) errors.push("data: releaseSequence must be a safe integer");
  if (new Set(components.map((component) => component.component)).size !== components.length) errors.push("system: duplicate component name");
  if (manifest.mobile?.artifactIdentity?.bundledDataManifestSha256 !== manifest.data?.artifactIdentity?.manifestSha256) errors.push("system: mobile/data manifest hash mismatch");
  if (manifest.backend?.artifactIdentity?.imageDigest !== manifest.platform?.artifactIdentity?.deployedImageDigest) errors.push("system: backend/platform image digest mismatch");
  const journeyV3 = manifest.journeyV3;
  if (journeyV3 && typeof journeyV3 === "object" && !Array.isArray(journeyV3)) {
    if (journeyV3.executionMode !== "SERVER_ONLY") errors.push("system: Journey V3 execution mode must be SERVER_ONLY");
    if (journeyV3.owner?.repository !== canonicalRepositories.backend) errors.push("system: Journey V3 owner repository must be canonical backend");
    if (journeyV3.owner?.gitSha !== manifest.backend?.gitSha) errors.push("system: Journey V3 owner git SHA must match backend component");
    if (journeyV3.owner?.apiContractVersion !== manifest.backend?.artifactIdentity?.apiContractVersion) {
      errors.push("system: Journey V3 API contract must match backend component");
    }
    if (!/^[a-f0-9]{64}$/.test(journeyV3.evidenceSha256 ?? "")) {
      errors.push("system: Journey V3 evidence SHA-256 must be lowercase hex digest");
    }
    for (const counter of journeyFallbackSuccessCounters) {
      if (journeyV3.fallbackSuccessCounters?.[counter] !== 0) {
        errors.push(`system: Journey V3 ${counter} fallback success count must be zero`);
      }
    }
  }
  if (manifest.decision === "GO") {
    if (!journeyV3 || typeof journeyV3 !== "object" || Array.isArray(journeyV3)) {
      errors.push("system: GO requires Journey V3 server-only evidence");
    }
    if (manifest.phase !== "FINAL") errors.push("system: GO requires FINAL phase");
    if (slots.some((slot) => manifest[slot]?.repository !== canonicalRepositories[slot])) errors.push("system: GO requires canonical target repositories");
    if (manifest.platform?.artifactIdentity?.environment !== "production") errors.push("system: GO requires production platform");
    if (manifest.data?.artifactIdentity?.releaseSequence < 1) errors.push("system: GO requires data release sequence");
  }
  return redact(errors);
}

export function selectSystemReleaseDecision({
  legacyDecision,
  manifest,
  componentSchema,
  systemSchema,
  issueRefSchema,
  governanceInventory,
  governanceInventorySchema,
}) {
  const semanticErrors = validateSystemReleaseManifest({
    manifest: { ...manifest, decision: "GO" }, componentSchema, systemSchema, issueRefSchema,
    governanceInventory,
    governanceInventorySchema,
  });
  return legacyDecision === "GO" && semanticErrors.length === 0 ? "GO" : "NO_GO";
}

function componentIdentity(component) {
  if (!component || typeof component !== "object" || Array.isArray(component)) return null;
  return {
    schemaVersion: component.schemaVersion,
    component: component.component,
    repository: component.repository,
    gitSha: component.gitSha,
    artifactIdentity: component.artifactIdentity,
    contractVersion: component.contractVersion,
    evidenceSha256: component.evidenceSha256,
  };
}

function sha256Canonical(value) {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort(codepointCompare).map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function sha256File(filePath) {
  return createHash("sha256").update(readFileSync(filePath)).digest("hex");
}

function redact(errors) {
  return [...new Set(errors.map((error) => String(error).replace(/\$\.[^:]+/g, "$")))];
}

function main() {
  const options = parseOptions(process.argv.slice(2));
  if (!options) return fail("invalid arguments");
  const here = path.dirname(fileURLToPath(import.meta.url));
  let manifest;
  try {
    manifest = JSON.parse(readFileSync(options.manifestPath, "utf8"));
  } catch {
    return fail("manifest file is unreadable or invalid JSON");
  }
  try {
    const schema = (name) => JSON.parse(readFileSync(path.join(here, "../../contracts/release", name), "utf8"));
    const errors = validateSystemReleaseManifest({
      manifest,
      componentSchema: schema("component-manifest.schema.json"),
      systemSchema: schema("system-release-manifest.schema.json"),
      issueRefSchema: schema("issue-ref.schema.json"),
      governanceInventorySchema: schema("system-release-governance-inventory.schema.json"),
      governanceInventory: schema("system-release-governance-inventory.json"),
      repoRoot: path.join(here, "../.."),
    });
    if (errors.length > 0) return fail(errors.join("\n"));
    if (options.requireDecision && manifest.decision !== options.requireDecision) {
      return fail(`decision must be ${options.requireDecision}`);
    }
    process.stdout.write(`system-release-manifest: OK ${manifest.productReleaseId}\n`);
  } catch {
    fail("validator unavailable");
  }
}

function parseOptions(args) {
  if (args.length === 2 && args[0] === "--manifest" && args[1]) {
    return { manifestPath: args[1], requireDecision: null };
  }
  if (
    args.length === 4
    && args[0] === "--manifest" && args[1]
    && args[2] === "--require-decision" && args[3] === "GO"
  ) {
    return { manifestPath: args[1], requireDecision: args[3] };
  }
  return null;
}

function fail(message) {
  process.stderr.write(`system-release-manifest: invalid\n${message}\n`);
  process.exitCode = 1;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
