// 이슈 #2531(DP-05): publish 게이트가 지키는 불변식은 "live >= 앱 수락 하한"이다.
// 게이트를 workflow 인라인 `node -e`로 두면 비교 방향이 뒤집히거나 throw가 빠져도 아무도
// 모른다. 여기서 위/같음/아래와 실패 동작을 직접 실행해 고정한다.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";
import { acceptanceFloorViolations, DEFAULT_POLICY_PATH } from "./check-manifest-acceptance-floor.mjs";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");

function policy({ minimumReleaseSequence = 114, observedReleaseSequence = 114, observedManifestSha256 = "a".repeat(64) } = {}) {
  return {
    schemaVersion: 1,
    artifactKind: "datapack-manifest-acceptance-policy",
    channel: "production",
    minimumReleaseSequence,
    minimumReleaseSequenceEvidence: {
      observedReleaseSequence,
      observedManifestSha256,
      observedAt: "2026-07-26T04:58:56.000Z",
      source: "production-catalog-current-json",
    },
  };
}

function manifest(releaseSequence) {
  return { manifestVersion: 2, channel: "production", releaseSequence, ttlSeconds: 3600, packs: [] };
}

test("하한 위 순번은 통과한다", () => {
  assert.deepEqual(acceptanceFloorViolations({ manifest: manifest(115), manifestSha256: "b".repeat(64), policy: policy() }), []);
});

test("하한과 같은 순번은 통과한다", () => {
  // 경계값. 기록한 관측 매니페스트와 같은 순번이므로 sha256 대조까지 함께 돈다.
  const sha256 = "c".repeat(64);
  assert.deepEqual(
    acceptanceFloorViolations({
      manifest: manifest(114),
      manifestSha256: sha256,
      policy: policy({ observedManifestSha256: sha256 }),
    }),
    [],
  );
});

test("하한 아래 순번은 거부한다", () => {
  const violations = acceptanceFloorViolations({ manifest: manifest(113), manifestSha256: "b".repeat(64), policy: policy() });
  assert.equal(violations.length, 1);
  assert.match(violations[0], /releaseSequence\(113\).*하한\(114\) 아래/);
});

test("정책 하한이 관측 순번을 넘으면 거부한다", () => {
  const violations = acceptanceFloorViolations({
    manifest: manifest(200),
    manifestSha256: "b".repeat(64),
    policy: policy({ minimumReleaseSequence: 150, observedReleaseSequence: 114 }),
  });
  assert.equal(violations.length, 1);
  assert.match(violations[0], /하한\(150\)은 관측한 published 순번\(114\)을 넘을 수 없다/);
});

test("같은 순번인데 기록한 관측 해시가 다르면 거부한다", () => {
  // 관측 근거가 같은 파일 안의 자기신고 값에 머무르지 않게 하는 대조다.
  const violations = acceptanceFloorViolations({
    manifest: manifest(114),
    manifestSha256: "d".repeat(64),
    policy: policy({ observedManifestSha256: "e".repeat(64) }),
  });
  assert.equal(violations.length, 1);
  assert.match(violations[0], /관측 근거 sha256/);
});

test("releaseSequence가 없거나 정수가 아니면 거부한다", () => {
  for (const value of [undefined, null, "114", 114.5, 0]) {
    const violations = acceptanceFloorViolations({
      manifest: { ...manifest(1), releaseSequence: value },
      manifestSha256: "b".repeat(64),
      policy: policy(),
    });
    assert.ok(violations.some((violation) => /releaseSequence는 1 이상 정수/.test(violation)), `${value} 케이스`);
  }
});

test("정책 artifactKind가 다르면 거부한다", () => {
  const violations = acceptanceFloorViolations({
    manifest: manifest(200),
    manifestSha256: "b".repeat(64),
    policy: { ...policy(), artifactKind: "datapack-update-policy" },
  });
  assert.ok(violations.some((violation) => /artifactKind/.test(violation)));
});

test("저장소의 현행 정책 파일은 스스로의 불변식을 만족한다", async () => {
  const livePolicy = JSON.parse(await readFile(path.join(root, DEFAULT_POLICY_PATH), "utf8"));
  const violations = acceptanceFloorViolations({
    manifest: manifest(livePolicy.minimumReleaseSequenceEvidence.observedReleaseSequence + 1),
    manifestSha256: "b".repeat(64),
    policy: livePolicy,
  });
  assert.deepEqual(violations, []);
});

test("CLI는 하한 아래 매니페스트에서 비정상 종료한다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "acceptance-floor-"));
  const manifestPath = path.join(dir, "current.json");
  const policyPath = path.join(dir, "policy.json");
  await writeFile(manifestPath, `${JSON.stringify(manifest(113))}\n`);
  await writeFile(policyPath, `${JSON.stringify(policy())}\n`);

  await assert.rejects(
    execFileAsync("node", ["tools/datapack/check-manifest-acceptance-floor.mjs", "--manifest", manifestPath, "--policy", policyPath], { cwd: root }),
    (error) => {
      assert.equal(error.code, 1);
      assert.match(error.stderr, /publish할 수 없다/);
      return true;
    },
  );
});

test("CLI는 하한 이상 매니페스트에서 PASS 요약을 낸다", async () => {
  const dir = await mkdtemp(path.join(tmpdir(), "acceptance-floor-"));
  const manifestPath = path.join(dir, "current.json");
  const policyPath = path.join(dir, "policy.json");
  const manifestJson = `${JSON.stringify(manifest(115))}\n`;
  await writeFile(manifestPath, manifestJson);
  await writeFile(policyPath, `${JSON.stringify(policy())}\n`);

  const { stdout } = await execFileAsync(
    "node",
    ["tools/datapack/check-manifest-acceptance-floor.mjs", "--manifest", manifestPath, "--policy", policyPath],
    { cwd: root },
  );
  const summary = JSON.parse(stdout);
  assert.equal(summary.status, "PASS");
  assert.equal(summary.releaseSequence, 115);
  assert.equal(summary.minimumReleaseSequence, 114);
  assert.equal(summary.manifestSha256, createHash("sha256").update(manifestJson).digest("hex"));
});
