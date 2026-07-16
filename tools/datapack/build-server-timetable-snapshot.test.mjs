import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { promisify } from "node:util";
import { gunzipSync } from "node:zlib";

import { buildServerTimetableSnapshot } from "./build-server-timetable-snapshot.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");
const baselinePath = path.join(
  root,
  "backend/src/main/resources/timetable/line4-subway-timetable-seed.sql.gz",
);
const contractPath = path.join(root, "tools/datapack/itx-cheongchun-coverage-contract.json");
const buildNow = new Date("2026-07-16T00:00:00.000Z");

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function inputs() {
  const baselineGzipBytes = await readFile(baselinePath);
  const contractBytes = await readFile(contractPath);
  const contract = JSON.parse(contractBytes);
  const sourceBytes = await readFile(path.join(root, contract.sourceTimetableArtifact.artifactPath));
  const completenessBytes = await readFile(path.join(
    root,
    contract.sourceTimetableArtifact.completenessEvidencePath,
  ));
  return { baselineGzipBytes, contractBytes, sourceBytes, completenessBytes };
}

test("#2135 ADMITTED source와 subway seed를 deterministic complete server snapshot으로 만든다", async () => {
  const value = await inputs();
  const first = buildServerTimetableSnapshot({ ...value, buildNow });
  const second = buildServerTimetableSnapshot({ ...value, buildNow });
  const contract = JSON.parse(value.contractBytes);
  const source = JSON.parse(value.sourceBytes);

  assert.deepEqual(second, first);
  assert.equal(gunzipSync(first.gzipBytes).toString("utf8"), first.sql);
  assert.equal(first.evidence.snapshotSha256, sha256(Buffer.from(first.sql)));
  assert.equal(first.evidence.sourceArtifact.id, contract.sourceTimetableArtifact.artifactId);
  assert.equal(first.evidence.sourceArtifact.sha256, sha256(value.sourceBytes));
  assert.equal(first.evidence.sourceArtifact.completenessEvidenceSha256, sha256(value.completenessBytes));
  assert.equal(first.evidence.freshUntil, source.freshUntil);
  assert.deepEqual(first.evidence.serviceIdentity, {
    serviceId: "ITX_CHEONGCHUN",
    canonicalLineId: contract.canonicalLineId,
    servicePattern: "EXPRESS",
    timezone: "Asia/Seoul",
  });
  assert.equal(first.evidence.rowCounts.itxTrips, source.transitTrips.length);
  assert.equal(first.evidence.rowCounts.itxStopTimes, source.transitStopTimes.length);
  assert.ok(first.evidence.rowCounts.subwayTrips > 0);
  assert.ok(first.evidence.rowCounts.subwayStopTimes > first.evidence.rowCounts.subwayTrips);
  assert.match(first.sql, /'ITX_CHEONGCHUN'/);
  assert.match(first.sql, /, 2135\);/);
  assert.equal((first.sql.match(/INSERT INTO transit_feed_info/g) ?? []).length, 1);
  assert.equal((first.sql.match(/VALUES \('weekday-kric'/g) ?? []).length, 1);
  assert.equal((first.sql.match(/VALUES \('holiday-kric'/g) ?? []).length, 1);
  assert.equal((first.sql.match(/VALUES \('saturday-kric'/g) ?? []).length, 1);
  const localPattern = first.evidence.servicePatternEvidence.representativeLocal;
  const expressPattern = first.evidence.servicePatternEvidence.representativeExpress;
  assert.ok(localPattern.stopStationIds.length > 1);
  assert.deepEqual(localPattern.passThroughStationIds, []);
  assert.ok(expressPattern.stopStationIds.length > 1);
  assert.ok(expressPattern.passThroughStationIds.length > 0);
  assert.ok(expressPattern.passThroughStationIds.every(
    (stationId) => !expressPattern.stopStationIds.includes(stationId),
  ));
  assert.ok(first.evidence.servicePatternEvidence.localTripCount > 0);
  assert.ok(first.evidence.servicePatternEvidence.expressTripCount > 0);
});

test("complete snapshot은 source·completeness identity와 freshness를 fail closed한다", async () => {
  const value = await inputs();
  const source = JSON.parse(value.sourceBytes);
  source.transitStopTimes[0].arrivalSeconds += 1;
  const tamperedSourceBytes = Buffer.from(`${JSON.stringify(source, null, 2)}\n`);

  assert.throws(
    () => buildServerTimetableSnapshot({ ...value, sourceBytes: tamperedSourceBytes, buildNow }),
    /source artifact SHA-256 mismatch/,
  );
  assert.throws(
    () => buildServerTimetableSnapshot({
      ...value,
      buildNow: new Date("2026-07-19T15:00:00.000Z"),
    }),
    /source artifact is stale/,
  );
});

test("CLI는 tracked snapshot/evidence를 생성하고 --check에서 byte identity를 검증한다", async (context) => {
  const directory = await mkdtemp(path.join(tmpdir(), "server-timetable-snapshot-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const outputPath = path.join(directory, "snapshot.sql.gz");
  const evidencePath = path.join(directory, "evidence.json");
  const runtimeEvidencePath = path.join(directory, "runtime-evidence.json");
  const args = [
    "tools/datapack/build-server-timetable-snapshot.mjs",
    "--baseline", baselinePath,
    "--contract", contractPath,
    "--output", outputPath,
    "--evidence", evidencePath,
    "--runtime-evidence", runtimeEvidencePath,
  ];
  const env = { ...process.env, EASYSUBWAY_TIMETABLE_SNAPSHOT_BUILD_NOW: buildNow.toISOString() };

  await execFileAsync(process.execPath, args, { cwd: root, env });
  const before = await Promise.all([
    readFile(outputPath),
    readFile(evidencePath),
    readFile(runtimeEvidencePath),
  ]);
  assert.deepEqual(before[2], before[1]);
  await execFileAsync(process.execPath, [...args, "--check"], { cwd: root, env });
  assert.deepEqual(await Promise.all([
    readFile(outputPath),
    readFile(evidencePath),
    readFile(runtimeEvidencePath),
  ]), before);

  await writeFile(outputPath, Buffer.concat([before[0], Buffer.from("tampered")]));
  await assert.rejects(
    execFileAsync(process.execPath, [...args, "--check"], { cwd: root, env }),
    /server timetable snapshot is stale/,
  );
});
