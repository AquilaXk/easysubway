import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { createHash } from "node:crypto";

import {
  validateManifest,
  checkMirrors,
  checkRemoteMirrors,
  writeMirrors,
  parseArgs,
} from "./sync-component-mirrors.mjs";

function sha256(data) {
  return createHash("sha256").update(data).digest("hex");
}

test("매니페스트 형식 검증 - 정상 매니페스트", () => {
  const valid = {
    schemaVersion: 1,
    mirrors: [
      {
        hubPath: "contracts/api/a.json",
        repository: "AquilaXk/easysubway-backend",
        sourcePath: "contracts/api/a.json",
        sourceCommit: "1111111111111111111111111111111111111111",
        sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      },
      {
        hubPath: "contracts/api/b.yaml",
        repository: "AquilaXk/easysubway-backend",
        sourcePath: "contracts/api/b.yaml",
        sourceCommit: "2222222222222222222222222222222222222222",
        sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      },
    ],
  };
  const errors = validateManifest(valid);
  assert.equal(errors.length, 0);
});

test("매니페스트 형식 검증 - 40자 커밋, 정렬, 중복 경로 금지", () => {
  // invalid schemaVersion
  assert.ok(validateManifest({ schemaVersion: 2, mirrors: [] }).length > 0);

  // short commit hash
  assert.ok(
    validateManifest({
      schemaVersion: 1,
      mirrors: [
        {
          hubPath: "contracts/api/a.json",
          repository: "AquilaXk/easysubway-backend",
          sourcePath: "contracts/api/a.json",
          sourceCommit: "shortsha",
          sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        },
      ],
    }).some((e) => e.includes("40자")),
  );

  // unsorted hubPath
  assert.ok(
    validateManifest({
      schemaVersion: 1,
      mirrors: [
        {
          hubPath: "contracts/api/z.json",
          repository: "AquilaXk/easysubway-backend",
          sourcePath: "contracts/api/z.json",
          sourceCommit: "1111111111111111111111111111111111111111",
          sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        },
        {
          hubPath: "contracts/api/a.json",
          repository: "AquilaXk/easysubway-backend",
          sourcePath: "contracts/api/a.json",
          sourceCommit: "2222222222222222222222222222222222222222",
          sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        },
      ],
    }).some((e) => e.includes("정렬")),
  );

  // duplicate hubPath
  assert.ok(
    validateManifest({
      schemaVersion: 1,
      mirrors: [
        {
          hubPath: "contracts/api/a.json",
          repository: "AquilaXk/easysubway-backend",
          sourcePath: "contracts/api/a.json",
          sourceCommit: "1111111111111111111111111111111111111111",
          sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        },
        {
          hubPath: "contracts/api/a.json",
          repository: "AquilaXk/easysubway-backend",
          sourcePath: "contracts/api/a.json",
          sourceCommit: "2222222222222222222222222222222222222222",
          sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        },
      ],
    }).some((e) => e.includes("중복")),
  );
});

test("--check는 사본 1바이트 변경 시 실패", async () => {
  const tempDir = await mkdtemp(join(tmpdir(), "mirror-check-test-"));
  try {
    const hubFile = join(tempDir, "contracts/api/test.json");
    await mkdir(dirname(hubFile), { recursive: true });
    const content = '{"key": "value"}';
    await writeFile(hubFile, content, "utf8");

    const manifest = {
      schemaVersion: 1,
      mirrors: [
        {
          hubPath: "contracts/api/test.json",
          repository: "AquilaXk/easysubway-backend",
          sourcePath: "contracts/api/test.json",
          sourceCommit: "1111111111111111111111111111111111111111",
          sha256: sha256(content),
        },
      ],
    };

    const passResult = await checkMirrors({ rootDir: tempDir, manifest });
    assert.equal(passResult.ok, true);
    assert.equal(passResult.drifted.length, 0);

    // 1바이트 변조
    await writeFile(hubFile, '{"key": "value!"}', "utf8");
    const failResult = await checkMirrors({ rootDir: tempDir, manifest });
    assert.equal(failResult.ok, false);
    assert.equal(failResult.drifted.length, 1);
    assert.equal(failResult.drifted[0].hubPath, "contracts/api/test.json");
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test("--write는 받은 바이트를 그대로 쓰고 sha256을 기록 (주입 함수, 네트워크 없음)", async () => {
  const tempDir = await mkdtemp(join(tmpdir(), "mirror-write-test-"));
  try {
    const fakeBackendContent = Buffer.from('{"hello": "world"}');
    const fakeDataContent = Buffer.from('[{"id": "source-1"}]');

    const fakeExecGh = async ({ repository, path, ref }) => {
      if (repository === "AquilaXk/easysubway-backend") return fakeBackendContent;
      if (repository === "AquilaXk/easysubway-data") return fakeDataContent;
      throw new Error(`unknown repo ${repository}`);
    };

    const refs = {
      "AquilaXk/easysubway-backend": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "AquilaXk/easysubway-data": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    };

    const manifest = await writeMirrors({
      rootDir: tempDir,
      refs,
      execGh: fakeExecGh,
    });

    assert.equal(manifest.schemaVersion, 1);
    assert.equal(validateManifest(manifest).length, 0);

    // Written files match hashes
    const checkResult = await checkMirrors({ rootDir: tempDir, manifest });
    assert.equal(checkResult.ok, true);

    const backendMirror = manifest.mirrors.find(
      (m) => m.repository === "AquilaXk/easysubway-backend",
    );
    assert.equal(backendMirror.sha256, sha256(fakeBackendContent));
    assert.equal(backendMirror.sourceCommit, refs["AquilaXk/easysubway-backend"]);
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test("--check-remote는 원격 sha가 다르면 exit 1 (주입 함수)", async () => {
  const manifest = {
    schemaVersion: 1,
    mirrors: [
      {
        hubPath: "contracts/api/test.json",
        repository: "AquilaXk/easysubway-backend",
        sourcePath: "contracts/api/test.json",
        sourceCommit: "1111111111111111111111111111111111111111",
        sha256: sha256("current-manifest-content"),
      },
    ],
  };

  // When remote returns identical content
  const passExecGh = async () => Buffer.from("current-manifest-content");
  const passResult = await checkRemoteMirrors({ manifest, execGh: passExecGh });
  assert.equal(passResult.ok, true);
  assert.equal(passResult.drifted.length, 0);

  // When remote returns drifted content
  const failExecGh = async () => Buffer.from("remote-updated-content");
  const failResult = await checkRemoteMirrors({ manifest, execGh: failExecGh });
  assert.equal(failResult.ok, false);
  assert.equal(failResult.drifted.length, 1);
  assert.equal(failResult.drifted[0].hubPath, "contracts/api/test.json");
});
