#!/usr/bin/env node

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { validateSchema } from "../ci/lib/json-schema-lite.mjs";
import { isSemVer } from "./lib/semver.mjs";

const slots = ["mobile", "backend", "data", "platform"];
const canonicalHubRepository = "AquilaXk/easysubway";
const canonicalRepositories = Object.fromEntries(slots.map((slot) => [slot, `AquilaXk/easysubway-${slot}`]));
const allowedRepositories = Object.fromEntries(slots.map((slot) => [slot, new Set(["AquilaXk/easysubway", canonicalRepositories[slot]])]));

export function validateSystemReleaseManifest({ manifest, componentSchema, systemSchema, issueRefSchema }) {
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
  if (manifest.hub?.repository !== canonicalHubRepository) errors.push("hub: repository must be canonical");
  if (!isSemVer(manifest.contracts?.version)) errors.push("system: contracts version must be SemVer");

  const components = slots.map((slot) => manifest[slot]).filter(Boolean);
  if (!Number.isSafeInteger(manifest.mobile?.artifactIdentity?.versionCode)) errors.push("mobile: versionCode must be a safe integer");
  if (!Number.isSafeInteger(manifest.data?.artifactIdentity?.releaseSequence)) errors.push("data: releaseSequence must be a safe integer");
  if (new Set(components.map((component) => component.component)).size !== components.length) errors.push("system: duplicate component name");
  if (manifest.mobile?.artifactIdentity?.bundledDataManifestSha256 !== manifest.data?.artifactIdentity?.manifestSha256) errors.push("system: mobile/data manifest hash mismatch");
  if (manifest.backend?.artifactIdentity?.imageDigest !== manifest.platform?.artifactIdentity?.deployedImageDigest) errors.push("system: backend/platform image digest mismatch");
  if (manifest.decision === "GO") {
    if (manifest.phase !== "FINAL") errors.push("system: GO requires FINAL phase");
    if (slots.some((slot) => manifest[slot]?.repository !== canonicalRepositories[slot])) errors.push("system: GO requires canonical target repositories");
    if (manifest.platform?.artifactIdentity?.environment !== "production") errors.push("system: GO requires production platform");
    if (manifest.data?.artifactIdentity?.releaseSequence < 1) errors.push("system: GO requires data release sequence");
  }
  return redact(errors);
}

export function selectSystemReleaseDecision({ legacyDecision, manifest, componentSchema, systemSchema, issueRefSchema }) {
  const semanticErrors = validateSystemReleaseManifest({
    manifest: { ...manifest, decision: "GO" }, componentSchema, systemSchema, issueRefSchema,
  });
  return legacyDecision === "GO" && semanticErrors.length === 0 ? "GO" : "NO_GO";
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
