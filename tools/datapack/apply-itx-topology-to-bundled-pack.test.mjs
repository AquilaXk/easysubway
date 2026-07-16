import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { promisify } from "node:util";
import { gunzipSync } from "node:zlib";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function rejectedMutatedSource(context, mutate, expected) {
  const directory = await mkdtemp(path.join(os.tmpdir(), "itx-topology-reject-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const packPath = path.join(directory, "capital.sqlite.gz");
  const indexPath = path.join(directory, "index.json");
  const evidencePath = path.join(directory, "evidence.json");
  const contractPath = path.join(directory, "contract.json");
  const sourcePath = path.join(directory, "source.json");
  await copyFile(path.join(root, "apps/mobile/assets/datapacks/capital.sqlite.gz"), packPath);
  await copyFile(path.join(root, "apps/mobile/assets/datapacks/index.json"), indexPath);
  const contract = JSON.parse(await readFile(
    path.join(root, "tools/datapack/itx-cheongchun-coverage-contract.json"), "utf8"));
  const source = JSON.parse(await readFile(path.join(root, contract.sourceTimetableArtifact.artifactPath), "utf8"));
  const packBytes = await readFile(packPath);
  source.canonicalPackIdentity.sha256 = sha256(packBytes);
  contract.officialEvidence.korailCompletenessAdmission.canonicalPackIdentity.sha256 = sha256(packBytes);
  contract.officialEvidence.korailCompletenessAdmission.canonicalPackIdentity.sqliteSha256 = sha256(gunzipSync(packBytes));
  mutate(source);
  const sourceBytes = Buffer.from(`${JSON.stringify(source, null, 2)}\n`);
  await writeFile(sourcePath, sourceBytes);
  contract.sourceTimetableArtifact.artifactPath = sourcePath;
  contract.sourceTimetableArtifact.sha256 = sha256(sourceBytes);
  await writeFile(contractPath, `${JSON.stringify(contract, null, 2)}\n`);

  return assert.rejects(execFileAsync(process.execPath, [
    "tools/datapack/apply-itx-topology-to-bundled-pack.mjs",
    "--pack", packPath,
    "--index", indexPath,
    "--contract", contractPath,
    "--evidence", evidencePath,
  ], { cwd: root }), expected);
}

test("#2135 ADMITTED source를 Mobile topology-only edge와 evidence로 materialize한다", async (context) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "itx-topology-pack-"));
  context.after(() => rm(directory, { recursive: true, force: true }));
  const packPath = path.join(directory, "capital.sqlite.gz");
  const indexPath = path.join(directory, "index.json");
  const evidencePath = path.join(directory, "evidence.json");
  const contractPath = path.join(directory, "contract.json");
  const sourcePath = path.join(directory, "source.json");
  await copyFile(path.join(root, "apps/mobile/assets/datapacks/capital.sqlite.gz"), packPath);
  await copyFile(path.join(root, "apps/mobile/assets/datapacks/index.json"), indexPath);
  const contract = JSON.parse(await readFile(
    path.join(root, "tools/datapack/itx-cheongchun-coverage-contract.json"), "utf8"));
  const source = JSON.parse(await readFile(path.join(root, contract.sourceTimetableArtifact.artifactPath), "utf8"));
  const packBytes = await readFile(packPath);
  source.canonicalPackIdentity.sha256 = sha256(packBytes);
  contract.officialEvidence.korailCompletenessAdmission.canonicalPackIdentity.sha256 = sha256(packBytes);
  contract.officialEvidence.korailCompletenessAdmission.canonicalPackIdentity.sqliteSha256 = sha256(gunzipSync(packBytes));
  const sourceBytes = Buffer.from(`${JSON.stringify(source, null, 2)}\n`);
  await writeFile(sourcePath, sourceBytes);
  contract.sourceTimetableArtifact.artifactPath = sourcePath;
  contract.sourceTimetableArtifact.sha256 = sha256(sourceBytes);
  await writeFile(contractPath, `${JSON.stringify(contract, null, 2)}\n`);

  await execFileAsync(process.execPath, [
    "tools/datapack/apply-itx-topology-to-bundled-pack.mjs",
    "--pack", packPath,
    "--index", indexPath,
    "--contract", contractPath,
    "--evidence", evidencePath,
  ], { cwd: root });

  const sqlitePath = path.join(directory, "capital.sqlite");
  await writeFile(sqlitePath, gunzipSync(await readFile(packPath)));
  const database = new DatabaseSync(sqlitePath);
  try {
    const edges = database.prepare(`
      SELECT duration_seconds, service_pattern, service_class
      FROM network_edges
      WHERE service_class = 'ITX_CHEONGCHUN'
    `).all();
    assert.ok(edges.length > 0);
    assert.ok(edges.every((edge) => edge.duration_seconds === 0));
    assert.ok(edges.every((edge) => edge.service_pattern === "EXPRESS"));
    assert.equal(database.prepare(`
      SELECT COUNT(*) AS count FROM transit_trips WHERE service_class = 'ITX_CHEONGCHUN'
    `).get().count, 0);
    assert.equal(database.prepare("PRAGMA user_version").get().user_version, 18);
  } finally {
    database.close();
  }

  const evidence = JSON.parse(await readFile(evidencePath, "utf8"));
  assert.equal(evidence.sourceIssue, 2135);
  assert.equal(evidence.serviceId, "ITX_CHEONGCHUN");
  assert.ok(evidence.topology.edgeCount > 0);
  assert.match(evidence.topology.sha256, /^[a-f0-9]{64}$/);

  const beforeCheck = await Promise.all([
    readFile(packPath), readFile(indexPath), readFile(evidencePath),
  ]);
  await execFileAsync(process.execPath, [
    "tools/datapack/apply-itx-topology-to-bundled-pack.mjs",
    "--pack", packPath,
    "--index", indexPath,
    "--contract", contractPath,
    "--evidence", evidencePath,
    "--check",
  ], { cwd: root });
  const afterCheck = await Promise.all([
    readFile(packPath), readFile(indexPath), readFile(evidencePath),
  ]);
  assert.deepEqual(afterCheck, beforeCheck);
  await execFileAsync(process.execPath, [
    "tools/datapack/apply-itx-topology-to-bundled-pack.mjs",
    "--pack", packPath,
    "--index", indexPath,
    "--contract", contractPath,
    "--evidence", evidencePath,
  ], { cwd: root });
  assert.deepEqual(await Promise.all([
    readFile(packPath), readFile(indexPath), readFile(evidencePath),
  ]), beforeCheck);
});

test("ITX topology는 U/D 양방향 station sequence가 모두 있어야 한다", async (context) => {
  await rejectedMutatedSource(context, (source) => {
    source.stationSequences = source.stationSequences.filter(({ directionId }) => directionId === "up");
  }, /requires U\/D station sequences/);
});

test("ITX topology는 admitted service stop 전체를 보존해야 한다", async (context) => {
  await rejectedMutatedSource(context, (source) => {
    source.stationSequences = [
      source.stationSequences.find(({ directionId }) => directionId === "up"),
      source.stationSequences.find(({ directionId }) => directionId === "down"),
    ];
  }, /cover the admitted service stop set/);
});

test("ITX topology는 service stop을 두 개의 고립 component로 나누지 않는다", async (context) => {
  await rejectedMutatedSource(context, (source) => {
    const stops = [...new Map(source.stationSequences
      .flatMap(({ stops: sequenceStops }) => sequenceStops)
      .map((stop) => [`${stop.stationId}:${stop.lineId}`, stop])).values()]
      .sort((left, right) => left.corridorSequence - right.corridorSequence);
    const middle = Math.ceil(stops.length / 2);
    const groups = [stops.slice(0, middle), stops.slice(middle)];
    source.stationSequences = groups.flatMap((group, index) => [
      { trainNumber: `up-${index}`, directionId: "up", stops: group },
      { trainNumber: `down-${index}`, directionId: "down", stops: [...group].reverse() },
    ]);
  }, /service stop graph must be connected/);
});
