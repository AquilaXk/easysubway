#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { regularJson, validateComponent } from "./validate-promotion-request.mjs";

export function buildEvidence({ component, manifestBytes, matrix, appVersion }) {
  validateComponent(component);
  const manifest = JSON.parse(manifestBytes);
  const version = /^(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$/.exec(appVersion);
  const compatible = matrix?.schemaVersion === 1 && Array.isArray(matrix.mobile)
    && matrix.mobile.find((row) => row?.appVersionRange === ">=1.0.0" && Number(version?.[1]) >= 1);
  if (component.manifestSha256 !== sha256(manifestBytes)
    || manifest?.manifestVersion !== 2 || !Array.isArray(manifest.packs) || manifest.packs.length === 0
    || !compatible?.acceptsIndexSchemaVersions?.includes(1)
    || !manifest.packs.every((pack) => compatible.acceptsManifestSchemaVersions?.includes(Number(pack.schemaVersion)))
    || !compatible.acceptsSigningKeyIds?.includes(manifest.keyId)) {
    throw new Error("candidate is incompatible with the current mobile contract");
  }
  return {
    schemaVersion: 1,
    artifactKind: "datapack-mobile-compatibility-evidence",
    decision: "PASS",
    candidate: component,
  };
}

async function main() {
  const names = ["component", "manifest", "matrix", "pubspec", "output"];
  const argv = process.argv.slice(2);
  if (argv.length !== names.length * 2) throw new Error("exact arguments required");
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index]?.slice(2);
    if (!names.includes(name) || args.has(name) || !argv[index]?.startsWith("--")) throw new Error("invalid arguments");
    args.set(name, argv[index + 1]);
  }
  const [component] = await regularJson(args.get("component"), "--component");
  const [, manifestBytes] = await regularJson(args.get("manifest"), "--manifest");
  const [matrix] = await regularJson(args.get("matrix"), "--matrix");
  const version = (await readFile(args.get("pubspec"), "utf8")).match(/^version:\s*(\S+)\s*$/m)?.[1];
  const evidence = buildEvidence({ component, manifestBytes, matrix, appVersion: version });
  await writeFile(args.get("output"), `${JSON.stringify(evidence, null, 2)}\n`, { flag: "wx" });
}

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => { console.error(error.message); process.exitCode = 1; });
}
