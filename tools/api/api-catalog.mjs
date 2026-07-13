#!/usr/bin/env node
import { readFile, readdir } from "node:fs/promises";
import { basename } from "node:path";
import { pathToFileURL } from "node:url";

import { listOperations } from "../datapack/source-operation.mjs";

const ROOT_URL = new URL("../../", import.meta.url);
const INTERNAL_URL = new URL("contracts/api/internal-api-index.json", ROOT_URL);
const PROVIDERS_URL = new URL("tools/datapack/source-candidates.json", ROOT_URL);
const INTEGRATIONS_URL = new URL("contracts/api/outbound-integrations.json", ROOT_URL);
const POLICY_URL = new URL("contracts/api/api-catalog-contract.json", ROOT_URL);
const CONTRACTS_URL = new URL("contracts/api/", ROOT_URL);
const KINDS = new Set(["contract", "integration", "internal", "provider"]);
const HTTP_METHODS = new Set(["ANY", "DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]);

function contractId(path) {
  return `contract:${basename(path).replace(/\.openapi\.ya?ml$/, "")}`;
}

export function buildCatalog({
  internalDocument,
  providerDocument,
  integrationsDocument,
  contractDocuments,
}) {
  const internal = (internalDocument?.operations ?? []).map((operation) => ({
    ...operation,
    kind: "internal",
  }));
  const providers = listOperations(providerDocument).map((operation) => ({
    ...operation,
    id: `provider:${operation.id}`,
    kind: "provider",
    documentationStatus: operation.operation ? "reproducible-operation" : "metadata-only",
  }));
  const integrations = (integrationsDocument?.operations ?? []).map((operation) => ({
    ...operation,
    kind: "integration",
  }));
  const contracts = (contractDocuments ?? []).map((path) => ({
    id: contractId(path),
    kind: "contract",
    path,
  }));
  return [...internal, ...providers, ...integrations, ...contracts].sort((left, right) =>
    left.id.localeCompare(right.id, "en"),
  );
}

function containsForbiddenValue(value) {
  if (Array.isArray(value)) return value.some(containsForbiddenValue);
  if (typeof value === "string") {
    let decoded = value;
    try {
      decoded = decodeURIComponent(value);
    } catch {
      // Invalid URL encoding is handled by the structural validators.
    }
    if (/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(decoded)) return true;
    if (/\bBearer\s+(?!\[|\{|env:)[A-Za-z0-9._~-]+/i.test(decoded)) return true;
    for (const match of decoded.matchAll(/[?&](?:accessKey|apiKey|password|secret|serviceKey|token)=([^&#]*)/gi)) {
      if (!/^(?:\[[^\]]+\]|\{[^}]+\}|\$\{[^}]+\})$/.test(match[1])) return true;
    }
    return false;
  }
  if (value == null || typeof value !== "object") return false;
  return Object.entries(value).some(([key, child]) =>
    /^(?:apiKey|credential|password|secret|serviceKey|token)Value$/i.test(key) ||
    containsForbiddenValue(child),
  );
}

export function validateCatalog(catalog) {
  if (!Array.isArray(catalog)) throw new Error("catalog must be an array");
  const ids = new Set();
  for (const entry of catalog) {
    if (!entry || typeof entry.id !== "string" || entry.id.length === 0) {
      throw new Error("catalog id is required");
    }
    if (ids.has(entry.id)) throw new Error(`duplicate catalog id: ${entry.id}`);
    ids.add(entry.id);
    if (!KINDS.has(entry.kind)) throw new Error(`${entry.id}.kind is invalid`);
    if (containsForbiddenValue(entry)) {
      throw new Error(`${entry.id}: secret-like values are forbidden`);
    }
    if (entry.kind === "internal") {
      if (!HTTP_METHODS.has(entry.method) || typeof entry.path !== "string" || !entry.path.startsWith("/")) {
        throw new Error(`${entry.id}: invalid internal method/path`);
      }
      if (entry.path === "/api/catalog" || entry.path.includes("/api-catalog")) {
        throw new Error(`${entry.id}: runtime catalog endpoint is forbidden`);
      }
    }
    if (entry.kind === "provider" && !/^https?:\/\//.test(entry.endpoint ?? "")) {
      throw new Error(`${entry.id}: invalid provider endpoint`);
    }
    if (entry.kind === "integration") {
      if (!HTTP_METHODS.has(entry.method) || !/^(?:config|constant|manifest-entry):/.test(entry.endpointRef ?? "")) {
        throw new Error(`${entry.id}: invalid integration operation`);
      }
      if (typeof entry.source !== "string" || entry.source.length === 0) {
        throw new Error(`${entry.id}: integration source is required`);
      }
    }
    if (entry.kind === "contract" && !/^contracts\/api\/.+\.openapi\.ya?ml$/.test(entry.path ?? "")) {
      throw new Error(`${entry.id}: invalid OpenAPI contract reference`);
    }
  }
  return catalog;
}

export function validateCatalogPolicy(policy) {
  if (policy?.schemaVersion !== 1 || policy?.artifactKind !== "repository-api-catalog-contract") {
    throw new Error("API catalog policy identity is invalid");
  }
  if (policy.runtimeExposure !== "forbidden") {
    throw new Error("API catalog runtime exposure must be forbidden");
  }
  for (const command of ["list", "show", "validate"]) {
    if (typeof policy.commands?.[command] !== "string" || !policy.commands[command].startsWith("node tools/api/api-catalog.mjs ")) {
      throw new Error(`API catalog ${command} command is invalid`);
    }
  }
  if (!Array.isArray(policy.sources) || policy.sources.length !== 4) {
    throw new Error("API catalog sources are invalid");
  }
  if (typeof policy.secretPolicy !== "string" || !policy.secretPolicy.includes("credential-values")) {
    throw new Error("API catalog secret policy is invalid");
  }
  return policy;
}

export function listCatalog(catalog, { kind = null, query = null } = {}) {
  const needle = query?.toLocaleLowerCase("en") ?? null;
  return catalog.filter((entry) => {
    if (kind && entry.kind !== kind) return false;
    if (!needle) return true;
    return JSON.stringify(entry).toLocaleLowerCase("en").includes(needle);
  });
}

export function findCatalogEntry(catalog, id) {
  const entry = catalog.find((candidate) => candidate.id === id);
  if (!entry) throw new Error(`API catalog entry not found: ${id}`);
  return entry;
}

async function readJson(url) {
  return JSON.parse(await readFile(url, "utf8"));
}

export async function loadCatalogPolicy() {
  return readJson(POLICY_URL);
}

export async function loadProjectCatalog() {
  validateCatalogPolicy(await loadCatalogPolicy());
  const contractDocuments = (await readdir(CONTRACTS_URL))
    .filter((name) => name.endsWith(".openapi.yaml") || name.endsWith(".openapi.yml"))
    .map((name) => `contracts/api/${name}`)
    .sort();
  return validateCatalog(buildCatalog({
    internalDocument: await readJson(INTERNAL_URL),
    providerDocument: await readJson(PROVIDERS_URL),
    integrationsDocument: await readJson(INTEGRATIONS_URL),
    contractDocuments,
  }));
}

function option(args, name) {
  const inline = args.find((arg) => arg.startsWith(`${name}=`));
  if (inline) return inline.slice(name.length + 1);
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : null;
}

function humanLine(entry) {
  const target = entry.path ?? entry.endpointRef ?? entry.endpoint ?? "";
  return [entry.id, entry.kind, entry.method ?? "-", target].join("\t");
}

async function main(args = process.argv.slice(2)) {
  const command = args[0];
  const json = args.includes("--json");
  const catalog = await loadProjectCatalog();
  if (command === "list") {
    const entries = listCatalog(catalog, {
      kind: option(args, "--kind"),
      query: option(args, "--query"),
    });
    console.log(json ? JSON.stringify(entries, null, 2) : entries.map(humanLine).join("\n"));
    return;
  }
  if (command === "show" && args[1]) {
    const entry = findCatalogEntry(catalog, args[1]);
    console.log(JSON.stringify(entry, null, 2));
    return;
  }
  if (command === "validate") {
    validateCatalog(catalog);
    const counts = Object.fromEntries([...KINDS].map((kind) => [kind, catalog.filter((entry) => entry.kind === kind).length]));
    console.log(`API catalog valid: ${catalog.length} (${Object.entries(counts).map(([kind, count]) => `${kind}=${count}`).join(", ")})`);
    return;
  }
  throw new Error("usage: api-catalog.mjs list [--kind <kind>] [--query <text>] [--json] | show <id> [--json] | validate");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : "API catalog failed");
    process.exitCode = 1;
  });
}
