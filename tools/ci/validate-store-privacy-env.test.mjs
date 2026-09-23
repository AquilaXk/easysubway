import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { writeFileSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

function createTempEnvFile(envMap) {
  const filePath = join(tmpdir(), `test-env-${Date.now()}-${Math.random().toString(36).slice(2)}.env`);
  const content = Object.entries(envMap).map(([k, v]) => `${k}=${v}`).join("\n");
  writeFileSync(filePath, content, "utf8");
  return filePath;
}

const validBaseEnv = {
  EASYSUBWAY_TERMS_OF_SERVICE_URL: "https://easysubway-api.aquilaxk.site/easysubway/terms",
  EASYSUBWAY_PRIVACY_POLICY_URL: "https://easysubway-api.aquilaxk.site/easysubway/privacy",
  EASYSUBWAY_LOCATION_TERMS_URL: "https://easysubway-api.aquilaxk.site/easysubway/location-terms",
  EASYSUBWAY_SUPPORT_EMAIL: "support@aquilaxk.site",
  EASYSUBWAY_SECURITY_EMAIL: "security@aquilaxk.site",
  EASYSUBWAY_DATA_DELETION_EMAIL: "privacy@aquilaxk.site",
  EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY: "prod-kakao-native-app-key-12345678",
};

const validRsaModulus = Buffer.alloc(256, 7).toString("base64url");

const validProductionRcEnv = {
  ...validBaseEnv,
  EASYSUBWAY_DATA_PACK_BASE_URL: "https://datapack.aquilaxk.site/packs",
  EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N: validRsaModulus,
  EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E: Buffer.from([1, 0, 1]).toString("base64url"),
  EASYSUBWAY_DATAPACK_SIGNING_KEY_ID: "datapack-key-v1",
  EASYSUBWAY_DATAPACK_CHANNEL: "production",
  EASYSUBWAY_PLAY_APP_SIGNING_KEY_SHA256: "0D:5E:2B:6F:8A:4C:1E:9B:3D:7A:5F:2C:8E:4B:0A:6D:9F:3E:7B:1C:5A:8E:2D:4F:0B:6C:8E:1A:3F:5D:7B:9C",
  EASYSUBWAY_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER: "1234567890",
};

test("validate-store-privacy-env allows ci-preflight kakao key in preflight mode without --require-android-rc-production", () => {
  const envFile = createTempEnvFile({
    ...validBaseEnv,
    EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY: "ci-preflight-kakao-key",
  });
  const githubEnvFile = createTempEnvFile({});
  try {
    execFileSync("node", [
      "tools/ci/validate-store-privacy-env.mjs",
      "--env-file", envFile,
      "--github-env", githubEnvFile,
    ], {
      encoding: "utf8",
    });
    // Exited with code 0 without throwing
    assert.ok(true);
  } finally {
    unlinkSync(envFile);
    unlinkSync(githubEnvFile);
  }
});

test("validate-store-privacy-env rejects ci-preflight kakao key when --require-android-rc-production is set", () => {
  const envFile = createTempEnvFile({
    ...validProductionRcEnv,
    EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY: "ci-preflight-kakao-key",
  });
  try {
    assert.throws(() => {
      execFileSync("node", ["tools/ci/validate-store-privacy-env.mjs", "--env-file", envFile, "--require-android-rc-production"], {
        encoding: "utf8",
        stdio: "pipe",
      });
    }, (err) => {
      return String(err.stderr || err.message).includes("EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY must not use CI preflight or dummy values in production RC");
    });
  } finally {
    unlinkSync(envFile);
  }
});

test("validate-store-privacy-env rejects dummy kakao key when --require-android-rc-production is set", () => {
  const envFile = createTempEnvFile({
    ...validProductionRcEnv,
    EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY: "dummy-kakao-key-9999",
  });
  try {
    assert.throws(() => {
      execFileSync("node", ["tools/ci/validate-store-privacy-env.mjs", "--env-file", envFile, "--require-android-rc-production"], {
        encoding: "utf8",
        stdio: "pipe",
      });
    }, (err) => {
      return String(err.stderr || err.message).includes("EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY must not use CI preflight or dummy values in production RC");
    });
  } finally {
    unlinkSync(envFile);
  }
});

test("validate-store-privacy-env accepts valid production keys when --require-android-rc-production is set", () => {
  const envFile = createTempEnvFile(validProductionRcEnv);
  const githubEnvFile = createTempEnvFile({});
  try {
    execFileSync("node", [
      "tools/ci/validate-store-privacy-env.mjs",
      "--env-file", envFile,
      "--github-env", githubEnvFile,
      "--require-android-rc-production",
    ], {
      encoding: "utf8",
    });
    assert.ok(true);
  } finally {
    unlinkSync(envFile);
    unlinkSync(githubEnvFile);
  }
});
