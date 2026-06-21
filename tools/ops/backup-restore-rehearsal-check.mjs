#!/usr/bin/env node
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

const root = process.cwd();
const gatePath = path.join(root, "apps/mobile/release/backup-restore-rehearsal-gate.json");
const gate = JSON.parse(readFileSync(gatePath, "utf8"));

const requiredTargetIds = [
  "postgres_application_database",
  "facility_report_photo_objects",
  "datapack_source_inventory",
  "datapack_release_manifest_history",
];

assert.equal(gate.releaseGate, "backup-restore-rehearsal");
assert.equal(gate.releaseBlockerPolicy, true);
assert.doesNotMatch(JSON.stringify(gate), /\b(TBD|TODO|PLACEHOLDER)\b|\.{3}/i);

const targets = new Map(gate.backupTargets.map((target) => [target.id, target]));
assert.deepEqual([...targets.keys()].sort(), requiredTargetIds.toSorted());

for (const id of requiredTargetIds) {
  const target = targets.get(id);
  assert.ok(target.ownerKo.includes("담당자"), `${id} owner must be assigned`);
  assert.ok(target.backupCommand.length > 0, `${id} backup command must be defined`);
  assert.ok(target.restoreRehearsalCommand.length > 0, `${id} restore command must be defined`);
  assert.ok(target.successEvidence.length > 0, `${id} success evidence must be defined`);
  assert.ok(target.failureConditions.length > 0, `${id} failure conditions must be defined`);

  for (const artifact of target.linkedArtifacts) {
    assert.ok(existsSync(path.join(root, artifact)), `${id} linked artifact missing: ${artifact}`);
  }
}

assert.match(gate.rehearsalPolicy.frequencyKo, /월 1회|릴리즈/);
assert.match(gate.rehearsalPolicy.dataSafetyKo, /운영 데이터 직접 복원 금지|격리/);
assert.match(gate.rehearsalPolicy.requiredOutputKo, /backup-restore-rehearsal/);

console.log("backup-restore-rehearsal gate ok");
