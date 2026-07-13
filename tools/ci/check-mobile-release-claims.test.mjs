import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const root = path.resolve(import.meta.dirname, "../..");

test("mobile release claim scan passes current app and store copy", async () => {
  const { stdout } = await execFileAsync(process.execPath, ["tools/ci/check-mobile-release-claims.mjs"], { cwd: root });
  assert.match(stdout, /mobile release claim scan passed: 상록수·사당 검증 pilot/);
});

test("mobile release claim scan rejects forbidden app copy", async () => {
  const tmp = path.join(tmpdir(), `mobile-claim-scan-${Date.now()}`);
  await rm(tmp, { recursive: true, force: true });
  await mkdir(path.join(tmp, "apps/mobile"), { recursive: true });
  await cp(path.join(root, "apps/mobile/lib"), path.join(tmp, "apps/mobile/lib"), { recursive: true });
  await cp(path.join(root, "apps/mobile/release"), path.join(tmp, "apps/mobile/release"), { recursive: true });
  await writeFile(path.join(tmp, "apps/mobile/lib/bad_claim.dart"), "const bad = '모든 역 지원';\n");

  await assert.rejects(
    execFileAsync(process.execPath, [
      path.join(root, "tools/ci/check-mobile-release-claims.mjs"),
      "--root",
      tmp,
    ], { cwd: root }),
    /forbidden release claim: 모든 역/,
  );
});

test("allowedPhrasesKo lets facility names pass but still blocks classification context", async () => {
  const tmp = path.join(tmpdir(), `mobile-claim-scan-allow-${Date.now()}`);
  await rm(tmp, { recursive: true, force: true });
  await mkdir(path.join(tmp, "apps/mobile"), { recursive: true });
  await cp(path.join(root, "apps/mobile/lib"), path.join(tmp, "apps/mobile/lib"), { recursive: true });
  await cp(path.join(root, "apps/mobile/release"), path.join(tmp, "apps/mobile/release"), { recursive: true });

  // '장애인'을 임시로 금지어에 넣고, 허용 구절(시설명)은 통과, 분류맥락은 차단됨을 증명한다.
  // 스토어 카피(fullDescriptionKo)의 분류맥락 '장애인'은 이 케이스의 검증 대상이 아니므로
  // scanTargets를 격리 dart 파일 하나로 좁힌다(supportRegionKo 매칭 검사는 그대로 유지).
  const facilityDir = path.join(tmp, "apps/mobile/claim-fixture");
  await mkdir(facilityDir, { recursive: true });
  const facilityFile = path.join(facilityDir, "facility_name.dart");

  const configPath = path.join(tmp, "apps/mobile/release/forbidden-release-claims.json");
  const config = JSON.parse(await readFile(configPath, "utf8"));
  config.forbiddenClaimsKo = [...(config.forbiddenClaimsKo ?? []), "장애인"];
  config.allowedPhrasesKo = ["장애인 화장실"];
  config.scanTargets = [{ path: "apps/mobile/claim-fixture", extensions: [".dart"] }];
  await writeFile(configPath, JSON.stringify(config));

  // 허용 구절만(시설명) 들어간 파일은 통과해야 한다.
  await writeFile(facilityFile, "const label = '대합실 장애인 화장실 위치';\n");

  await execFileAsync(process.execPath, [
    path.join(root, "tools/ci/check-mobile-release-claims.mjs"),
    "--root",
    tmp,
  ], { cwd: root });

  // 분류맥락(허용 구절이 아닌 '장애인' 사용)은 차단돼야 한다.
  await writeFile(facilityFile, "const label = '장애인 우대석 안내';\n");

  await assert.rejects(
    execFileAsync(process.execPath, [
      path.join(root, "tools/ci/check-mobile-release-claims.mjs"),
      "--root",
      tmp,
    ], { cwd: root }),
    /forbidden release claim: 장애인/,
  );
});
