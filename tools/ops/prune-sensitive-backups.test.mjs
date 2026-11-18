import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test, { afterEach } from "node:test";
import { pruneSensitiveBackups } from "./prune-sensitive-backups.mjs";

const sandboxes = [];
const toolPath = new URL("./prune-sensitive-backups.mjs", import.meta.url).pathname;

afterEach(async () => {
  for (const dir of sandboxes.splice(0)) {
    await rm(dir, { recursive: true, force: true });
  }
});

async function createSandbox() {
  const dir = await mkdtemp(path.join(tmpdir(), "prune-sensitive-backups-test-"));
  sandboxes.push(dir);
  return dir;
}

test("retentionDays 경계값에서 정확히 만료된 사본만 삭제하고 하루 덜 된 사본은 보존한다", async () => {
  const root = await createSandbox();
  // 기준 시각: 2026-08-31T00:00:00Z, 보존 기간 30일 -> cutoff = 2026-08-01T00:00:00Z
  const now = Date.parse("2026-08-31T00:00:00Z");

  const expiredExact = path.join(root, "easysubway-postgres-20260801T000000Z.abc123.dump");
  const expiredOlder = path.join(root, "easysubway-postgres-20260731T235959Z.abc123.dump");
  // 만료 기준보다 1초 늦게 생성(29일 23시간 59분 59초 경과) -> 반드시 보존되어야 함
  const keptOneSecondAfter = path.join(root, "easysubway-postgres-20260801T000001Z.abc123.dump");
  // 만료 기준보다 하루 덜 경과(29일 경과) -> 기존 +86_400_000 버그 시 잘못 삭제되던 대상
  const keptTwentyNineDays = path.join(root, "easysubway-postgres-20260802T000000Z.abc123.dump");

  await Promise.all([
    writeFile(expiredExact, "dump-exact"),
    writeFile(expiredOlder, "dump-older"),
    writeFile(keptOneSecondAfter, "dump-kept-1s"),
    writeFile(keptTwentyNineDays, "dump-kept-29d"),
  ]);

  const pruned = await pruneSensitiveBackups({ root, retentionDays: 30, now });
  assert.equal(pruned, 2);

  await assert.rejects(readFile(expiredExact), { code: "ENOENT" });
  await assert.rejects(readFile(expiredOlder), { code: "ENOENT" });
  assert.equal(await readFile(keptOneSecondAfter, "utf8"), "dump-kept-1s");
  assert.equal(await readFile(keptTwentyNineDays, "utf8"), "dump-kept-29d");
});

test("easysubway-postgres-*.dump와 .sha256 sidecar를 함께 정리한다", async () => {
  const root = await createSandbox();
  const now = Date.parse("2026-08-31T12:00:00Z");

  const expiredDump = path.join(root, "easysubway-postgres-20260701T000000Z.xyz999.dump");
  const expiredSha = `${expiredDump}.sha256`;
  const freshDump = path.join(root, "easysubway-postgres-20260820T000000Z.xyz999.dump");
  const freshSha = `${freshDump}.sha256`;

  await Promise.all([
    writeFile(expiredDump, "old"),
    writeFile(expiredSha, "old-sha"),
    writeFile(freshDump, "new"),
    writeFile(freshSha, "new-sha"),
  ]);

  const pruned = await pruneSensitiveBackups({ root, retentionDays: 30, now });
  assert.equal(pruned, 2);

  await assert.rejects(readFile(expiredDump), { code: "ENOENT" });
  await assert.rejects(readFile(expiredSha), { code: "ENOENT" });
  assert.equal(await readFile(freshDump, "utf8"), "new");
  assert.equal(await readFile(freshSha, "utf8"), "new-sha");
});

test("easysubway-report-photos-*.tar.gz 및 .sha256/.manifest.tsv sidecar를 정리하고 미만료본과 비대상 파일은 보존한다", async () => {
  const root = await createSandbox();
  const now = Date.parse("2026-09-10T00:00:00Z");

  const expiredTargets = [
    "easysubway-report-photos-20260801T000000Z.tar.gz",
    "easysubway-report-photos-20260801T000000Z.tar.gz.sha256",
    "easysubway-report-photos-20260801T000000Z.tar.gz.manifest.tsv",
    "easysubway-report-photos-20260801T000000Z.AbC123.tar.gz",
    "easysubway-report-photos-20260801T000000Z.AbC123.tar.gz.sha256",
    "easysubway-report-photos-20260801T000000Z.AbC123.tar.gz.manifest.tsv",
    "easysubway-report-photos-20260801T000000Z.sha256",
    "easysubway-report-photos-20260801T000000Z.manifest.tsv",
  ];
  const keptTargets = [
    "easysubway-report-photos-20260812T000000Z.tar.gz",
    "easysubway-report-photos-20260812T000000Z.tar.gz.sha256",
    "easysubway-report-photos-20260812T000000Z.tar.gz.manifest.tsv",
    "easysubway-report-photos-20260801T000000Z.tar.gz.tmp",
    "unrelated-archive-20200101T000000Z.tar.gz",
  ];

  await Promise.all([
    ...expiredTargets.map((name) => writeFile(path.join(root, name), "expired")),
    ...keptTargets.map((name) => writeFile(path.join(root, name), "kept")),
  ]);

  const pruned = await pruneSensitiveBackups({ root, retentionDays: 30, now });
  assert.equal(pruned, expiredTargets.length);

  for (const name of expiredTargets) {
    await assert.rejects(readFile(path.join(root, name)), { code: "ENOENT" });
  }
  for (const name of keptTargets) {
    assert.equal(await readFile(path.join(root, name), "utf8"), "kept");
  }
});

test("하위 디렉터리를 재귀 탐색해 만료 백업을 삭제하고 심볼릭 링크는 건너뛴다", async () => {
  const root = await createSandbox();
  const backupRoot = path.join(root, "backups");
  const subDir = path.join(backupRoot, "postgres", "daily");
  const outsideDir = path.join(root, "outside");
  await mkdir(subDir, { recursive: true });
  await mkdir(outsideDir, { recursive: true });

  const now = Date.parse("2026-09-15T00:00:00Z");
  const nestedExpired = path.join(subDir, "easysubway-report-photos-20260701T000000Z.tar.gz");
  const outsideTarget = path.join(outsideDir, "easysubway-postgres-20260701T000000Z.keep.dump");
  const symlinkFile = path.join(backupRoot, "easysubway-postgres-20260701T000000Z.link.dump");
  const symlinkDir = path.join(backupRoot, "linked-outside");

  await writeFile(nestedExpired, "nested");
  await writeFile(outsideTarget, "do-not-delete");
  await symlink(outsideTarget, symlinkFile);
  await symlink(outsideDir, symlinkDir);

  const pruned = await pruneSensitiveBackups({ root: backupRoot, retentionDays: 30, now });
  assert.equal(pruned, 1);

  await assert.rejects(readFile(nestedExpired), { code: "ENOENT" });
  assert.equal(await readFile(outsideTarget, "utf8"), "do-not-delete");
});

test("잘못된 인자와 유효하지 않은 백업 타임스탬프는 fail-closed로 거부한다", async () => {
  const root = await createSandbox();
  const now = Date.parse("2026-09-15T00:00:00Z");

  await assert.rejects(
    () => pruneSensitiveBackups({ root: "/", retentionDays: 30, now }),
    /--root/,
  );
  await assert.rejects(
    () => pruneSensitiveBackups({ root: "", retentionDays: 30, now }),
    /--root/,
  );
  await assert.rejects(
    () => pruneSensitiveBackups({ root, retentionDays: 0, now }),
    /--retention-days/,
  );
  await assert.rejects(
    () => pruneSensitiveBackups({ root, retentionDays: 366, now }),
    /--retention-days/,
  );
  await assert.rejects(
    () => pruneSensitiveBackups({ root, retentionDays: 30, now: Number.NaN }),
    /--now/,
  );

  // 존재하지 않는 달력 날짜(2월 31일)가 담긴 백업 파일명 거부
  await writeFile(path.join(root, "easysubway-postgres-20260231T000000Z.bad.dump"), "x");
  await assert.rejects(
    () => pruneSensitiveBackups({ root, retentionDays: 30, now }),
    /invalid backup creation timestamp/,
  );
});

test("lstat 도중 사라진 ENOENT 엔트리는 실패하지 않고 건너뛴다", async () => {
  const root = await createSandbox();
  const now = Date.parse("2026-09-15T00:00:00Z");
  await writeFile(path.join(root, "easysubway-postgres-20260701T000000Z.race.dump"), "gone");

  const pruned = await pruneSensitiveBackups({
    root,
    retentionDays: 30,
    now,
    lstat: async () => {
      const error = new Error("vanished");
      error.code = "ENOENT";
      throw error;
    },
  });
  assert.equal(pruned, 0);
});

test("CLI 실행 시 옵션을 파싱해 삭제 건수를 출력한다", async () => {
  const root = await createSandbox();
  const expired = path.join(root, "easysubway-report-photos-20260701T000000Z.tar.gz");
  const fresh = path.join(root, "easysubway-report-photos-20260901T000000Z.tar.gz");
  await writeFile(expired, "old");
  await writeFile(fresh, "fresh");

  const stdout = execFileSync(
    process.execPath,
    [toolPath, "--root", root, "--retention-days", "30", "--now", "2026-09-10T00:00:00Z"],
    { encoding: "utf8" },
  );
  assert.match(stdout, /sensitive-backup-retention: pruned=1 retention_days=30/);
  await assert.rejects(readFile(expired), { code: "ENOENT" });
  assert.equal(await readFile(fresh, "utf8"), "fresh");

  assert.throws(() =>
    execFileSync(
      process.execPath,
      [toolPath, "--root", root, "--unknown", "1", "--retention-days", "30"],
      { encoding: "utf8", stdio: "pipe" },
    ),
  );

  // 만료된 사진 백업 디렉터리와 보존 대상 디렉터리 처리
  const dirRoot = await createSandbox();
  const expiredDir = path.join(dirRoot, "easysubway-report-photos-20260701T000000Z.run1");
  const freshDir = path.join(dirRoot, "easysubway-report-photos-20260901T000000Z.run2");
  await mkdir(path.join(expiredDir, "objects"), { recursive: true });
  await mkdir(path.join(freshDir, "objects"), { recursive: true });
  await writeFile(path.join(expiredDir, "objects/a.jpg"), "old");
  await writeFile(path.join(freshDir, "objects/b.jpg"), "new");
  assert.equal(
    await pruneSensitiveBackups({ root: dirRoot, retentionDays: 30, now: Date.parse("2026-09-10T00:00:00Z") }),
    1,
  );
  await assert.rejects(readFile(path.join(expiredDir, "objects/a.jpg")), { code: "ENOENT" });
  assert.equal(await readFile(path.join(freshDir, "objects/b.jpg"), "utf8"), "new");
});
