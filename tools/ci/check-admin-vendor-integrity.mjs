#!/usr/bin/env node
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const defaultRoot = path.resolve(path.dirname(scriptPath), "../..");

export function checkAdminVendorIntegrity(root = defaultRoot) {
  const vendorRoot = path.join(root, "backend/src/main/resources/static/vendor");
  const templateRoots = [
    path.join(root, "backend/src/main/resources/templates/admin"),
    path.join(root, "backend/src/main/resources/templates/operator"),
  ];
  const failures = [];
  const vendorFiles = vendorManifestFiles(vendorRoot);
  const scriptRefs = scriptReferences(templateRoots);
  const refsBySrc = new Map();
  for (const ref of scriptRefs) {
    const refs = refsBySrc.get(ref.src) ?? [];
    refs.push(ref);
    refsBySrc.set(ref.src, refs);
  }

  for (const vendorFile of vendorFiles) {
    const relativeSrc = `/vendor/${vendorFile.relativePath}`;
    const actualSha256 = hashFile(vendorFile.absolutePath, "sha256", "hex");
    if (actualSha256 !== vendorFile.sha256) {
      failures.push(`${vendorFile.manifestPath}: ${vendorFile.fileName} sha256 mismatch`);
    }
    if (!vendorFile.requiresTemplateReference) {
      continue;
    }
    const sri = `sha384-${hashFile(vendorFile.absolutePath, "sha384", "base64")}`;
    const refs = refsBySrc.get(relativeSrc);
    if (!refs || refs.length === 0) {
      failures.push(`${relativeSrc} is not referenced by an admin/operator template`);
      continue;
    }
    for (const ref of refs) {
      if (ref.integrity !== sri) {
        failures.push(`${ref.templatePath}: ${relativeSrc} integrity mismatch`);
      }
      if (ref.crossorigin !== "anonymous") {
        failures.push(`${ref.templatePath}: ${relativeSrc} must use crossorigin="anonymous"`);
      }
    }
  }

  for (const ref of scriptRefs) {
    if (ref.src.startsWith("/vendor/") && !vendorFiles.some((file) => `/vendor/${file.relativePath}` === ref.src)) {
      failures.push(`${ref.templatePath}: ${ref.src} has no SHA256SUMS entry`);
    }
  }

  for (const templatePath of htmlFiles(templateRoots)) {
    const source = readFileSync(templatePath, "utf8");
    const inlineScripts = [...source.matchAll(/<script\b(?![^>]*\b(?:src|th:src)=)[^>]*>/gi)];
    if (inlineScripts.length > 0) {
      failures.push(`${templatePath}: inline <script> is not allowed`);
    }
    const inlineHandlers = [...source.matchAll(/\son[a-z]+\s*=/gi)];
    if (inlineHandlers.length > 0) {
      failures.push(`${templatePath}: inline event handler is not allowed`);
    }
  }

  if (failures.length > 0) {
    throw new Error(failures.join("\n"));
  }
  return { checkedVendorFiles: vendorFiles.length, checkedTemplateScripts: scriptRefs.length };
}

function vendorManifestFiles(vendorRoot) {
  if (!existsSync(vendorRoot)) {
    throw new Error(`vendor root not found: ${vendorRoot}`);
  }
  const files = [];
  for (const packageDir of readdirSync(vendorRoot).sort()) {
    const absolutePackageDir = path.join(vendorRoot, packageDir);
    if (!statSync(absolutePackageDir).isDirectory()) {
      continue;
    }
    const manifestPath = path.join(absolutePackageDir, "SHA256SUMS.txt");
    assert.ok(existsSync(manifestPath), `${packageDir} must have SHA256SUMS.txt`);
    const lines = readFileSync(manifestPath, "utf8").split(/\r?\n/).filter(Boolean);
    for (const line of lines) {
      const match = line.match(/^([a-f0-9]{64})\s+\*?(.+)$/);
      assert.ok(match, `${manifestPath} has invalid line: ${line}`);
      const fileName = match[2].trim();
      const absolutePath = path.join(absolutePackageDir, fileName);
      assert.ok(existsSync(absolutePath), `${manifestPath} references missing file ${fileName}`);
      files.push({
        sha256: match[1],
        fileName,
        relativePath: `${packageDir}/${fileName}`,
        absolutePath,
        manifestPath,
        requiresTemplateReference: /\.(?:js|css)$/i.test(fileName),
      });
    }
  }
  return files;
}

function scriptReferences(templateRoots) {
  const refs = [];
  for (const templatePath of htmlFiles(templateRoots)) {
    const source = readFileSync(templatePath, "utf8");
    for (const match of source.matchAll(/<script\b[^>]*>/gi)) {
      const tag = match[0];
      const src = attr(tag, "th:src") ?? attr(tag, "src");
      if (!src) {
        continue;
      }
      const normalized = normalizeTemplateSrc(src);
      refs.push({
        templatePath,
        src: normalized,
        integrity: attr(tag, "integrity"),
        crossorigin: attr(tag, "crossorigin"),
      });
    }
  }
  return refs;
}

function htmlFiles(roots) {
  const files = [];
  for (const root of roots) {
    if (!existsSync(root)) {
      continue;
    }
    collectHtml(root, files);
  }
  return files.sort();
}

function collectHtml(dir, files) {
  for (const entry of readdirSync(dir).sort()) {
    const absolute = path.join(dir, entry);
    const stat = statSync(absolute);
    if (stat.isDirectory()) {
      collectHtml(absolute, files);
    } else if (entry.endsWith(".html")) {
      files.push(absolute);
    }
  }
}

function attr(tag, name) {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = tag.match(new RegExp(`${escaped}="([^"]+)"`, "i"));
  return match ? match[1] : null;
}

function normalizeTemplateSrc(value) {
  const thymeleaf = value.match(/^@\{([^}]+)}$/);
  return thymeleaf ? thymeleaf[1] : value;
}

function hashFile(filePath, algorithm, encoding) {
  return createHash(algorithm).update(readFileSync(filePath)).digest(encoding);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const rootIndex = process.argv.indexOf("--root");
  const root = rootIndex >= 0 ? path.resolve(process.argv[rootIndex + 1]) : defaultRoot;
  try {
    const result = checkAdminVendorIntegrity(root);
    console.log(`admin vendor integrity ok: ${JSON.stringify(result)}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
