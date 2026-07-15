import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

import { deleteExpiredItems } from "./purge-expired-source-raw.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const evaluationAt = "2026-07-15T00:00:00Z";

test("만료 raw만 삭제하고 active·rollback·legal hold 원본은 보존하며 재실행은 idempotent하다", async () => {
  await withFixture(async ({ baseUrl, objects, requests, workDir }) => {
    const files = await writeInputs(workDir, [
      rawEntry("expired", "raw/expired.json"),
      rawEntry("active", "raw/active.json", { protectedBy: ["ACTIVE_RELEASE"] }),
      rawEntry("rollback", "raw/rollback.json", { protectedBy: ["ROLLBACK_WINDOW"] }),
      rawEntry("legal-hold", "raw/legal-hold.json", { legalHold: legalHold("legal-hold") }),
    ]);
    for (const key of ["raw/expired.json", "raw/active.json", "raw/rollback.json", "raw/legal-hold.json"]) {
      objects.add(`/${key}`);
    }

    const first = await runPurge({ ...files, baseUrl, output: path.join(workDir, "first.json") });
    assert.deepEqual(first.deleted.map((entry) => entry.snapshotId), ["expired"]);
    assert.deepEqual(first.protected.map((entry) => entry.snapshotId), ["active", "legal-hold", "rollback"]);
    assert.deepEqual(requests, ["/raw/expired.json"]);
    assert.equal(objects.has("/raw/expired.json"), false);
    assert.equal(objects.has("/raw/active.json"), true);
    assert.equal(objects.has("/raw/rollback.json"), true);
    assert.equal(objects.has("/raw/legal-hold.json"), true);

    const second = await runPurge({ ...files, baseUrl, output: path.join(workDir, "second.json") });
    assert.deepEqual(second.alreadyAbsent.map((entry) => entry.snapshotId), ["expired"]);
    assert.deepEqual(requests, ["/raw/expired.json", "/raw/expired.json"]);
  });
});

test("dry-run은 만료 raw를 계획하지만 DELETE하지 않는다", async () => {
  await withFixture(async ({ baseUrl, objects, requests, workDir }) => {
    const files = await writeInputs(workDir, [rawEntry("expired", "raw/expired.json")]);
    objects.add("/raw/expired.json");

    const report = await runPurge({
      ...files,
      baseUrl,
      output: path.join(workDir, "dry-run.json"),
      dryRun: true,
    });

    assert.deepEqual(report.wouldDelete.map((entry) => entry.snapshotId), ["expired"]);
    assert.deepEqual(requests, []);
    assert.equal(objects.has("/raw/expired.json"), true);
  });
});

test("실제 DELETE는 CLI 인자가 아닌 env-injected preauthenticated base URL을 요구한다", async () => {
  await withFixture(async ({ baseUrl, requests, workDir }) => {
    const files = await writeInputs(workDir, [rawEntry("expired", "raw/expired.json")]);

    await assert.rejects(
      runPurge({ ...files, baseUrl, output: path.join(workDir, "unauthenticated.json"), authenticated: false }),
      /preauthenticated base URL environment variable/,
    );
    assert.deepEqual(requests, []);
  });
});

test("실제 DELETE는 env-injected snapshot evidence hash로 승인 bytes를 고정한다", async () => {
  await withFixture(async ({ baseUrl, objects, requests, workDir }) => {
    const files = await writeInputs(workDir, [rawEntry("expired", "raw/expired.json")]);
    objects.add("/raw/expired.json");

    await assert.rejects(
      runPurge({
        ...files,
        baseUrl,
        output: path.join(workDir, "untrusted-evidence.json"),
        trustedSnapshots: false,
      }),
      /snapshot evidence sha256 environment variable/,
    );
    assert.deepEqual(requests, []);
    assert.equal(objects.has("/raw/expired.json"), true);
  });
});

test("실제 DELETE는 system clock보다 미래인 evaluation-at을 요청 전에 거부한다", async () => {
  await withFixture(async ({ baseUrl, objects, requests, workDir }) => {
    const files = await writeInputs(workDir, [rawEntry("expired", "raw/expired.json")]);
    objects.add("/raw/expired.json");

    await assert.rejects(
      runPurge({
        ...files,
        baseUrl,
        output: path.join(workDir, "future-evaluation.json"),
        evaluationAtOverride: "2099-01-01T00:00:00Z",
      }),
      /evaluationAt must not be in the future/,
    );
    assert.deepEqual(requests, []);
    assert.equal(objects.has("/raw/expired.json"), true);
  });
});

test("서로 다른 governance policy 세대의 entry를 각 원본 policy bytes로 purge한다", async () => {
  await withFixture(async ({ baseUrl, objects, requests, workDir }) => {
    const first = policyFixture(["source-old"]);
    const second = { ...policyFixture(["source-new"]), policyVersion: "2026-07-16" };
    const policies = await Promise.all([
      writePolicy(workDir, "old", first),
      writePolicy(workDir, "new", second),
    ]);
    const ledger = {
      schemaVersion: 1,
      artifactKind: "source-raw-retention-ledger",
      entries: [
        bindPolicy(rawEntry("old", "raw/old.json"), policies[0]),
        bindPolicy(rawEntry("new", "raw/new.json"), policies[1]),
      ],
    };
    const ledgerPath = path.join(workDir, "multi-policy-ledger.json");
    await writeFile(ledgerPath, `${JSON.stringify(ledger, null, 2)}\n`);
    const snapshots = await writeSnapshotEvidence(workDir, ledger.entries);
    objects.add("/raw/old.json");
    objects.add("/raw/new.json");

    const report = await runPurge({
      ledger: ledgerPath,
      policies: policies.map((entry) => entry.path),
      snapshots,
      baseUrl,
      output: path.join(workDir, "multi-policy.json"),
    });

    assert.deepEqual(report.deleted.map((entry) => entry.snapshotId), ["new", "old"]);
    assert.deepEqual(requests.sort(), ["/raw/new.json", "/raw/old.json"]);
  });
});

test("invalid legal hold가 있으면 전체 plan을 DELETE 전에 거부한다", async () => {
  await withFixture(async ({ baseUrl, objects, requests, workDir }) => {
    const files = await writeInputs(workDir, [
      rawEntry("expired", "raw/expired.json"),
      rawEntry("invalid-hold", "raw/invalid-hold.json", {
        legalHold: { ...legalHold("invalid-hold"), expiresAt: evaluationAt },
      }),
    ]);
    objects.add("/raw/expired.json");
    objects.add("/raw/invalid-hold.json");
    const output = path.join(workDir, "invalid.json");

    await assert.rejects(
      runPurge({ ...files, baseUrl, output }),
      /LEGAL_HOLD_INVALID/,
    );
    assert.deepEqual(requests, []);
    assert.equal(objects.has("/raw/expired.json"), true);
  });
});

test("같은 object key가 만료와 legal hold entry에 중복되면 DELETE 전에 거부한다", async () => {
  await withFixture(async ({ baseUrl, objects, requests, workDir }) => {
    const files = await writeInputs(workDir, [
      rawEntry("expired", "raw/shared.json"),
      rawEntry("legal-hold", "raw/shared.json", { legalHold: legalHold("legal-hold") }),
    ]);
    objects.add("/raw/shared.json");

    await assert.rejects(
      runPurge({ ...files, baseUrl, output: path.join(workDir, "duplicate-object.json") }),
      /duplicate object key/,
    );
    assert.deepEqual(requests, []);
    assert.equal(objects.has("/raw/shared.json"), true);
  });
});

test("ledger object key가 LOCKED snapshot raw URI와 다르면 DELETE 전에 거부한다", async () => {
  await withFixture(async ({ baseUrl, objects, requests, workDir }) => {
    const entry = rawEntry("expired", "raw/active.json");
    const files = await writeInputs(workDir, [entry]);
    const snapshots = await writeSnapshotEvidence(workDir, [entry], {
      expired: "raw/expired.json",
    });
    objects.add("/raw/active.json");

    await assert.rejects(
      runPurge({
        ...files,
        snapshots,
        baseUrl,
        output: path.join(workDir, "mismatched-object.json"),
      }),
      /snapshot evidence mismatch/,
    );
    assert.deepEqual(requests, []);
    assert.equal(objects.has("/raw/active.json"), true);
  });
});

test("DELETE 5xx는 sanitized RAW_RETENTION_OVERDUE evidence를 남기고 실패한다", async () => {
  await withFixture(async ({ baseUrl, objects, requests, workDir, failPaths }) => {
    const files = await writeInputs(workDir, [rawEntry("failed", "raw/failed-secret-name.json")]);
    objects.add("/raw/failed-secret-name.json");
    failPaths.add("/raw/failed-secret-name.json");
    const output = path.join(workDir, "failed.json");

    await assert.rejects(runPurge({ ...files, baseUrl, output }), /RAW_RETENTION_OVERDUE/);
    const reportText = await readFile(output, "utf8");
    const report = JSON.parse(reportText);
    assert.deepEqual(requests, ["/raw/failed-secret-name.json"]);
    assert.deepEqual(report.reasonCodes, ["RAW_RETENTION_OVERDUE"]);
    assert.deepEqual(report.failed.map((entry) => entry.snapshotId), ["failed"]);
    assert.doesNotMatch(reportText, /failed-secret-name|objectKey|baseUrl/i);
  });
});

test("DELETE는 최대 4개 동시 실행하고 각 요청에 timeout signal을 건다", async () => {
  let active = 0;
  let maxActive = 0;
  const items = Array.from({ length: 9 }, (_, index) => ({
    snapshotId: `snapshot-${index}`,
    objectUrl: `https://objects.example.invalid/raw/${index}`,
  }));
  const results = await deleteExpiredItems(items, {
    fetchImpl: async (_url, options) => {
      assert.ok(options.signal instanceof AbortSignal);
      active += 1;
      maxActive = Math.max(maxActive, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active -= 1;
      return { status: 204 };
    },
  });

  assert.equal(maxActive, 4);
  assert.deepEqual(results.map((result) => result.status), Array(9).fill(204));
});

test("응답 없는 DELETE는 timeout 뒤 실패 상태로 반환한다", async () => {
  const [result] = await deleteExpiredItems(
    [{ snapshotId: "stalled", objectUrl: "https://objects.example.invalid/raw/stalled" }],
    {
      timeoutMs: 5,
      fetchImpl: async (_url, { signal }) => new Promise((_resolve, reject) => {
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
      }),
    },
  );

  assert.equal(result.status, 0);
});

async function withFixture(run) {
  const workDir = path.join(tmpdir(), `easysubway-source-purge-${process.pid}-${Date.now()}`);
  const objects = new Set();
  const requests = [];
  const failPaths = new Set();
  await mkdir(workDir, { recursive: true });
  const server = createServer((request, response) => {
    if (request.method !== "DELETE") {
      response.writeHead(405).end();
      return;
    }
    requests.push(request.url);
    if (failPaths.has(request.url)) {
      response.writeHead(503).end();
      return;
    }
    if (!objects.delete(request.url)) {
      response.writeHead(404).end();
      return;
    }
    response.writeHead(204).end();
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  try {
    const address = server.address();
    await run({
      baseUrl: `http://127.0.0.1:${address.port}/`,
      objects,
      requests,
      failPaths,
      workDir,
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await rm(workDir, { recursive: true, force: true });
  }
}

async function writeInputs(workDir, entries) {
  const policy = policyFixture(entries.map((entry) => entry.sourceId));
  const policyFile = await writePolicy(workDir, "current", policy);
  const ledger = {
    schemaVersion: 1,
    artifactKind: "source-raw-retention-ledger",
    entries: entries.map((entry) => ({
      ...entry,
      governancePolicyVersion: policy.policyVersion,
      governancePolicySha256: policyFile.hash,
    })),
  };
  const ledgerPath = path.join(workDir, "ledger.json");
  await writeFile(ledgerPath, `${JSON.stringify(ledger, null, 2)}\n`);
  const snapshots = await writeSnapshotEvidence(workDir, ledger.entries);
  return { policies: [policyFile.path], ledger: ledgerPath, snapshots };
}

async function runPurge({
  ledger,
  policies,
  snapshots,
  baseUrl,
  output,
  dryRun = false,
  authenticated = true,
  trustedSnapshots = true,
  evaluationAtOverride = evaluationAt,
}) {
  try {
    const snapshotEvidenceSha256 = snapshots && trustedSnapshots
      ? sha256(await readFile(snapshots))
      : "";
    await execFileAsync(process.execPath, [
      "tools/datapack/purge-expired-source-raw.mjs",
      "--ledger", ledger,
      ...policies.flatMap((policy) => ["--policy", policy]),
      ...(snapshots ? ["--snapshots", snapshots] : []),
      "--evaluation-at", evaluationAtOverride,
      "--output", output,
      ...(dryRun ? ["--dry-run", "--base-url", baseUrl] : []),
      ...(!dryRun && !authenticated ? ["--base-url", baseUrl] : []),
    ], {
      cwd: root,
      env: {
        ...process.env,
        EASYSUBWAY_SOURCE_RAW_PURGE_PREAUTH_BASE_URL: !dryRun && authenticated ? baseUrl : "",
        EASYSUBWAY_SOURCE_RAW_PURGE_SNAPSHOT_EVIDENCE_SHA256: !dryRun ? snapshotEvidenceSha256 : "",
      },
    });
  } catch (error) {
    const message = `${error.stderr ?? ""}${error.stdout ?? ""}`;
    const wrapped = new Error(message || error.message);
    wrapped.cause = error;
    throw wrapped;
  }
  return JSON.parse(await readFile(output, "utf8"));
}

async function writeSnapshotEvidence(workDir, entries, objectKeyOverrides = {}) {
  const snapshots = entries.map((entry) => ({
    snapshotId: entry.snapshotId,
    sourceId: entry.sourceId,
    snapshotStatus: "LOCKED",
    retrievedAt: entry.retrievedAt,
    rawSha256: entry.rawSha256,
    rawObjectUri: `s3://easysubway-datapack-sources/${objectKeyOverrides[entry.snapshotId] ?? entry.objectKey}`,
  }));
  const snapshotsPath = path.join(workDir, "source-snapshots.json");
  await writeFile(snapshotsPath, `${JSON.stringify(snapshots, null, 2)}\n`);
  return snapshotsPath;
}

async function writePolicy(workDir, name, policy) {
  const text = `${JSON.stringify(policy, null, 2)}\n`;
  const policyPath = path.join(workDir, `${name}-policy.json`);
  await writeFile(policyPath, text);
  return { path: policyPath, hash: sha256(text), policy };
}

function bindPolicy(entry, policyFile) {
  return {
    ...entry,
    governancePolicyVersion: policyFile.policy.policyVersion,
    governancePolicySha256: policyFile.hash,
  };
}

function rawEntry(snapshotId, objectKey, overrides = {}) {
  return {
    sourceId: `source-${snapshotId}`,
    snapshotId,
    objectKey,
    rawSha256: sha256(snapshotId),
    retrievedAt: "2026-04-16T00:00:00Z",
    rawRetentionExpiresAt: "2026-07-15T00:00:00.000Z",
    protectedBy: [],
    legalHold: null,
    ...overrides,
  };
}

function legalHold(snapshotId) {
  return {
    sourceId: `source-${snapshotId}`,
    snapshotId,
    ownerRole: "datapack-source-owner",
    reasonCode: "REGULATORY_AUDIT",
    createdAt: "2026-07-01T00:00:00Z",
    expiresAt: "2026-07-20T00:00:00Z",
  };
}

function policyFixture(sourceIds) {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-source-governance-policy",
    policyVersion: "2026-07-15",
    retentionClasses: [{ id: "standard-90d", retentionDays: 90 }],
    sources: sourceIds.map((sourceId) => ({
      sourceId,
      retentionClassId: "standard-90d",
      ownerRole: "datapack-source-owner",
    })),
  };
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}
