#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const REQUIRED_TESTS = Object.freeze([
  [
    "com.easysubway.train.application.TrainSearchServiceTest",
    "threeNodesShareOneProviderCallThroughTheDatabaseLease",
  ],
  [
    "com.easysubway.train.adapter.out.persistence.JdbcTrainSearchCacheTest",
    "enforcesSharedMinuteAndDayQuotaPerProvider",
  ],
  [
    "com.easysubway.train.adapter.out.persistence.JdbcTrainSearchCacheTest",
    "concurrentLeaseAttemptsHaveExactlyOneOwner",
  ],
  [
    "com.easysubway.train.adapter.out.http.SharedTrainSearchProviderCallBudgetTest",
    "quotaRejectionFailsClosedAsUnavailable",
  ],
  [
    "com.easysubway.train.adapter.out.http.SharedTrainSearchProviderCallBudgetTest",
    "quotaPersistenceFailureFailsClosedAsUnavailable",
  ],
  [
    "com.easysubway.train.adapter.out.http.SharedTrainSearchProviderCallBudgetTest",
    "quotaTransactionBoundaryFailureFailsClosedAsUnavailable",
  ],
]);

export function buildBackendObservation(files) {
  if (!Array.isArray(files) || files.length === 0) throw new Error("backend observation test results were missing");
  const passingTests = new Set();
  const testResults = files.map(({ path: filePath, content }) => {
    if (typeof content !== "string") throw new Error("backend observation test result was unreadable");
    const suite = /<testsuite\b([^>]*)>/u.exec(content);
    if (!suite) throw new Error("backend observation test suite was invalid");
    const attributes = xmlAttributes(suite[1]);
    if (!positiveInteger(attributes.tests)
      || attributes.failures !== "0"
      || attributes.errors !== "0"
      || attributes.skipped !== "0"
      || /<(?:failure|error|skipped)\b/u.test(content)) {
      throw new Error("backend observation test suite failed");
    }
    for (const match of content.matchAll(/<testcase\b([^>]*)\/?>(?:<\/testcase>)?/gu)) {
      const testcase = xmlAttributes(match[1]);
      if (testcase.classname && testcase.name?.endsWith("()")) {
        passingTests.add(`${testcase.classname}#${testcase.name.slice(0, -2)}`);
      }
    }
    return {
      file: path.basename(filePath),
      sha256: sha256(content),
      testCount: Number(attributes.tests),
    };
  }).sort((left, right) => left.file.localeCompare(right.file));

  const requiredTests = REQUIRED_TESTS.map(([className, method]) => `${className}#${method}`);
  if (requiredTests.some((test) => !passingTests.has(test))) {
    throw new Error("backend observation required test was missing");
  }
  const artifact = {
    schemaVersion: 1,
    artifactKind: "train-search-backend-observation",
    status: "PASS",
    threeNodeSingleProviderCallVerifiedByTest: true,
    quotaFailClosedVerifiedByTests: true,
    requiredTests,
    testResults,
  };
  artifact.evidenceSha256 = sha256(JSON.stringify(artifact));
  return artifact;
}

export function validateBackendObservationArtifact(artifact) {
  if (!artifact || typeof artifact !== "object") throw new Error("backend observation artifact was invalid");
  const { evidenceSha256, ...unsigned } = artifact;
  if (artifact.schemaVersion !== 1
    || artifact.artifactKind !== "train-search-backend-observation"
    || artifact.status !== "PASS"
    || artifact.threeNodeSingleProviderCallVerifiedByTest !== true
    || artifact.quotaFailClosedVerifiedByTests !== true
    || "nodeCount" in artifact
    || "providerCallCount" in artifact
    || "quotaVerdict" in artifact
    || !Array.isArray(artifact.requiredTests)
    || artifact.requiredTests.length !== REQUIRED_TESTS.length
    || REQUIRED_TESTS.some(([className, method]) => !artifact.requiredTests.includes(`${className}#${method}`))
    || !Array.isArray(artifact.testResults)
    || artifact.testResults.length < 3
    || artifact.testResults.some((result) => (
      !validXmlFileName(result?.file)
        || !/^[0-9a-f]{64}$/u.test(result.sha256 ?? "")
        || !positiveInteger(String(result.testCount))
    ))
    || !/^[0-9a-f]{64}$/u.test(evidenceSha256 ?? "")
    || sha256(JSON.stringify(unsigned)) !== evidenceSha256) {
    throw new Error("backend observation artifact failed validation");
  }
  return artifact;
}

function xmlAttributes(value) {
  const attributes = {};
  let cursor = 0;
  while (cursor < value.length) {
    while (cursor < value.length && whitespace(value[cursor])) cursor += 1;
    if (cursor === value.length || (value[cursor] === "/" && cursor === value.length - 1)) break;
    const nameStart = cursor;
    if (!xmlNameStart(value[cursor])) throw new Error("backend observation XML attribute was invalid");
    cursor += 1;
    while (cursor < value.length && xmlNameCharacter(value[cursor])) cursor += 1;
    const name = value.slice(nameStart, cursor);
    while (cursor < value.length && whitespace(value[cursor])) cursor += 1;
    if (value[cursor] !== "=") throw new Error("backend observation XML attribute was invalid");
    cursor += 1;
    while (cursor < value.length && whitespace(value[cursor])) cursor += 1;
    if (value[cursor] !== "\"") throw new Error("backend observation XML attribute was invalid");
    const contentStart = cursor + 1;
    const contentEnd = value.indexOf("\"", contentStart);
    if (contentEnd < 0 || Object.hasOwn(attributes, name)) {
      throw new Error("backend observation XML attribute was invalid");
    }
    attributes[name] = value.slice(contentStart, contentEnd);
    cursor = contentEnd + 1;
  }
  return attributes;
}

function whitespace(character) {
  return character === " " || character === "\t" || character === "\r" || character === "\n";
}

function xmlNameStart(character) {
  return character === ":" || character === "_" || asciiLetter(character);
}

function xmlNameCharacter(character) {
  return xmlNameStart(character)
    || character === "."
    || character === "-"
    || (character >= "0" && character <= "9");
}

function asciiLetter(character) {
  return (character >= "A" && character <= "Z") || (character >= "a" && character <= "z");
}

function validXmlFileName(value) {
  return typeof value === "string"
    && value.length > ".xml".length
    && value.endsWith(".xml")
    && path.basename(value) === value
    && !value.includes("\\");
}

function positiveInteger(value) {
  return /^[1-9]\d*$/u.test(value ?? "");
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function parseArgs(argv) {
  const result = {};
  for (let index = 0; index < argv.length; index += 2) {
    if (!argv[index]?.startsWith("--") || argv[index + 1] === undefined) {
      throw new Error("arguments must be --name value pairs");
    }
    result[argv[index].slice(2)] = argv[index + 1];
  }
  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args["test-results-dir"] || !path.isAbsolute(args.output ?? "")) {
    throw new Error("--test-results-dir is required and --output must be absolute");
  }
  const testResultsDir = path.resolve(args["test-results-dir"]);
  const names = (await readdir(testResultsDir))
    .filter((name) => name.startsWith("TEST-") && name.endsWith(".xml"))
    .sort((left, right) => left.localeCompare(right));
  const files = await Promise.all(names.map(async (name) => ({
    path: name,
    content: await readFile(path.join(testResultsDir, name), "utf8"),
  })));
  const artifact = buildBackendObservation(files);
  await writeFile(args.output, `${JSON.stringify(artifact, null, 2)}\n`, { mode: 0o600 });
  console.log("train-search backend observation PASS: 3-node single-flight and quota fail-closed verified by tests");
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    await main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : "backend observation failed");
    process.exitCode = 1;
  }
}
