// 이슈 #2529: `apps/mobile/test/core/datapack/fixtures/production_manifest_envelope.json`
// 이 stale해지지 않도록 지키는 drift 가드.
//
// Dart 테스트는 기대값을 fixture에서 읽기만 하므로, Node 쪽 정준 규칙
// (`tools/datapack/lib/manifest-validation.mjs`의 `canonicalJson`)이 바뀌어도 저장된
// 스냅샷과만 비교해 17건이 전부 초록으로 남고 실기기만 운영 매니페스트를 거부한다.
// 여기서 저장 값을 **현재 Node 구현으로 재계산**해 비교하면 그 분열이 CI에서 잡힌다.
//
// 개인키는 쓰지 않는다. 서명 검증은 fixture에 저장된 공개 modulus·exponent만으로
// 공개 연산으로 수행하므로 CI에 시크릿이 필요 없다.
//
// 배선: `node --test tools/mobile/*.test.mjs`가 repository 게이트와 mobile 게이트
// 양쪽에 있어(#2518, `.github/workflows/ci.yml`) Node 전용 변경과 Dart 전용 변경
// 모두에서 이 가드가 돈다.
import assert from "node:assert/strict";
import { createHash, createPublicKey, createVerify, generateKeyPairSync } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { canonicalJson, withoutSignature } from "../datapack/lib/manifest-validation.mjs";
import {
  EXPECTED_TEST_MODULUS_BASE64URL,
  boundaryNumbers,
  buildFixture,
  packPayload,
  powMod,
  routeRegressionPayload,
  sha256Hex,
} from "./build-manifest-envelope-signature-fixture.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const fixture = JSON.parse(
  readFileSync(path.join(root, "apps/mobile/test/core/datapack/fixtures/production_manifest_envelope.json"), "utf8"),
);
const contract = JSON.parse(readFileSync(path.join(root, "contracts/datapack/canonical-number-contract.json"), "utf8"));

const publicKey = createPublicKey({
  key: { kty: "RSA", n: fixture.publicKey.modulusBase64Url, e: fixture.publicKey.exponentBase64Url },
  format: "jwk",
});

function verifies(message, signatureBase64Url) {
  return createVerify("RSA-SHA256").update(message).verify(publicKey, Buffer.from(signatureBase64Url, "base64url"));
}

function resolvePointer(root_, pointer) {
  return pointer
    .split("/")
    .slice(1)
    .reduce((current, segment) => current[segment.replace(/~1/g, "/").replace(/~0/g, "~")], root_);
}

function productionSuffix(pack) {
  return pack.artifactKind === "production" ? `:${pack.url}` : "";
}

test("fixture는 저장소의 테스트 전용 서명 키로 만들어졌다", () => {
  // 운영 키로 재생성된 fixture가 커밋되는 것을 산출물 수준에서도 막는다. 생성기
  // 내부에도 같은 fail-closed 가드가 있다.
  assert.equal(fixture.publicKey.modulusBase64Url, EXPECTED_TEST_MODULUS_BASE64URL);
  assert.equal(fixture.publicKey.exponentBase64Url, "AQAB");
  assert.equal(fixture.publicKey.modulusLengthBytes, 256);
});

test("생성기는 테스트 키가 아닌 개인키로는 fixture를 만들지 않는다", () => {
  // 산출물 검사(위 테스트)만으로는 가드가 실제로 던지는지 알 수 없다. 다른 키로
  // 직접 호출해 fixture 생성 전에 막히는지 확인한다.
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  assert.throws(() => buildFixture(privateKey.export({ type: "pkcs8", format: "pem" })), /테스트 전용/);
});

test("저장된 정준 문자열이 현재 Node 정준 구현의 출력과 바이트 동일하다", () => {
  assert.equal(canonicalJson(withoutSignature(fixture.manifest)), fixture.canonicalSignedPayload);
  assert.equal(sha256Hex(fixture.canonicalSignedPayload), fixture.manifestHashSha256);
});

test("봉투 서명이 저장된 공개키로 검증된다", () => {
  assert.equal(fixture.manifest.signature.algorithm, "rsa-sha256-manifest-v2");
  assert.equal(fixture.manifest.keyId, fixture.publicKey.keyId);
  assert.ok(verifies(fixture.canonicalSignedPayload, fixture.manifest.signature.value));
});

test("production 팩 서명과 대표 경로 회귀 서명이 모두 검증된다", () => {
  assert.ok(fixture.manifest.packs.length >= 2);
  for (const pack of fixture.manifest.packs) {
    assert.equal(pack.artifactKind, "production");
    assert.equal(pack.signature.algorithm, "rsa-sha256-pack-manifest-v2");
    assert.ok(
      verifies(`${packPayload(pack)}${productionSuffix(pack)}`, pack.signature.value),
      `${pack.id} 팩 서명 검증 실패`,
    );
    assert.equal(pack.representativeRouteRegressionSignature.algorithm, "rsa-sha256-route-regression-v1");
    assert.ok(
      verifies(
        `${routeRegressionPayload(pack)}${productionSuffix(pack)}`,
        pack.representativeRouteRegressionSignature.value,
      ),
      `${pack.id} 대표 경로 회귀 서명 검증 실패`,
    );
  }
});

test("유효 서명을 전제로 한 거부 케이스들은 서명 자체가 실제로 유효하다", () => {
  // keyId 불일치·다른 알고리즘 식별자 케이스는 "서명은 유효한데 한 조건만 어긋난"
  // 입력이어야 거부 사유가 좁혀진다. 그 전제를 여기서 고정한다.
  const rotated = { ...withoutSignature(fixture.manifest), ...fixture.rejections.keyIdMismatch.overrides };
  assert.notEqual(rotated.keyId, fixture.publicKey.keyId);
  assert.ok(verifies(canonicalJson(rotated), fixture.rejections.keyIdMismatch.signatureValue));
  assert.ok(verifies(fixture.canonicalSignedPayload, fixture.rejections.packManifestAlgorithmValue));
  assert.equal(fixture.rejections.selfHashAlgorithmValue, fixture.manifestHashSha256);
});

test("변조·오염된 서명 값은 검증에 실패한다", () => {
  const {
    tamperedSignatureValue,
    shortSignatureValue,
    signatureAboveModulusValue,
    invalidBase64UrlLengthValue,
    corruptedPaddingValue,
  } = fixture.rejections;

  assert.equal(
    Buffer.from(tamperedSignatureValue, "base64url").length,
    Buffer.from(fixture.manifest.signature.value, "base64url").length,
  );
  assert.equal(Buffer.from(shortSignatureValue, "base64url").length, 128);
  assert.equal(Buffer.from(signatureAboveModulusValue, "base64url").length, 256);
  assert.equal(invalidBase64UrlLengthValue.length % 4, 1);
  assert.match(invalidBase64UrlLengthValue, /^[A-Za-z0-9_-]+$/);
  assert.equal(Buffer.from(corruptedPaddingValue, "base64url").length, 256);
  assert.notEqual(corruptedPaddingValue, fixture.manifest.signature.value);

  for (const value of [
    tamperedSignatureValue,
    shortSignatureValue,
    signatureAboveModulusValue,
    invalidBase64UrlLengthValue,
    corruptedPaddingValue,
  ]) {
    assert.equal(verifies(fixture.canonicalSignedPayload, value), false);
  }
});

test("본문 변조 케이스는 정준 문자열을 실제로 바꾼다", () => {
  const tampered = { ...withoutSignature(fixture.manifest), ...fixture.rejections.tamperedBody.overrides };
  assert.notEqual(canonicalJson(tampered), fixture.canonicalSignedPayload);
  assert.equal(verifies(canonicalJson(tampered), fixture.manifest.signature.value), false);
});

test("modulus 과소 키는 최소 패딩 8바이트를 채울 수 없는 크기다", () => {
  const key = fixture.rejections.undersizedModulusKey;
  const modulus = Buffer.from(key.modulusBase64Url, "base64url");
  const signature = Buffer.from(key.signatureValue, "base64url");

  assert.equal(modulus.length, 61);
  assert.equal(signature.length, modulus.length);
  assert.equal(Buffer.from(key.exponentBase64Url, "base64url").readUIntBE(0, 3), 65537);
  // SHA-256 DigestInfo 51 byte + 헤더 3 byte를 빼면 패딩이 7 byte만 남는다.
  assert.equal(key.paddingLength, modulus.length - 51 - 3);
  assert.ok(key.paddingLength < 8);
  assert.ok(BigInt(`0x${signature.toString("hex")}`) < BigInt(`0x${modulus.toString("hex")}`));
});

test("modulus 과소 키 서명은 해당 키의 진짜 RSA 변환 결과다", () => {
  // 길이만 맞는 난수였다면 Dart 쪽 거부 사유가 "modulus 크기 가드"가 아니라 "깨진
  // 서명"이 되어 케이스가 의도한 조건을 격리하지 못한다. signature^e mod n 이 패딩
  // 7 byte짜리 PKCS#1 v1.5 블록을 복원하는지 확인해 그 전제를 고정한다.
  const key = fixture.rejections.undersizedModulusKey;
  const toBigInt = (base64Url) => BigInt(`0x${Buffer.from(base64Url, "base64url").toString("hex")}`);
  const recovered = powMod(toBigInt(key.signatureValue), toBigInt(key.exponentBase64Url), toBigInt(key.modulusBase64Url))
    .toString(16)
    .padStart(key.modulusLengthBytes * 2, "0");
  const expectedBlock = Buffer.concat([
    Buffer.from([0x00, 0x01]),
    Buffer.alloc(key.paddingLength, 0xff),
    Buffer.from([0x00]),
    Buffer.from("3031300d060960864801650304020105000420", "hex"),
    createHash("sha256").update(fixture.canonicalSignedPayload).digest(),
  ]);

  assert.equal(expectedBlock.length, key.modulusLengthBytes);
  assert.equal(recovered, expectedBlock.toString("hex"));
});

test("폴백 매니페스트는 자기해시 봉투로 정합하다", () => {
  const fallbackCanonical = canonicalJson(withoutSignature(fixture.fallbackManifest));
  assert.equal(fallbackCanonical, fixture.fallbackCanonicalSignedPayload);
  assert.equal(fixture.fallbackManifest.signature.algorithm, "sha256-manifest-v2");
  assert.equal(fixture.fallbackManifest.signature.value, sha256Hex(fallbackCanonical));
  for (const pack of fixture.fallbackManifest.packs) {
    assert.equal(pack.artifactKind, "fixture");
    assert.equal(pack.signature.algorithm, "sha256-pack-manifest-v2");
    assert.equal(pack.signature.value, sha256Hex(packPayload(pack)));
    assert.equal(pack.representativeRouteRegressionSignature.value, sha256Hex(routeRegressionPayload(pack)));
  }
});

test("심은 경계 숫자가 DP-02 정준 계약과 위치까지 일치한다", () => {
  assert.deepEqual(fixture.boundaryNumbers, boundaryNumbers);
  const contractCanonical = new Map(contract.formatting.map((entry) => [entry.id, entry.canonical]));
  const canonicalDocument = JSON.parse(fixture.canonicalSignedPayload);

  for (const boundary of boundaryNumbers) {
    assert.equal(
      contractCanonical.get(boundary.contractId),
      boundary.canonical,
      `${boundary.contractId} 표기가 계약과 다르다`,
    );
    // 정준 문자열을 되짚어 같은 pointer 위치의 값이 계약 표기와 같은지 본다.
    assert.equal(
      String(resolvePointer(canonicalDocument, boundary.pointer)),
      boundary.canonical,
      `${boundary.pointer} 위치의 정준 표기가 다르다`,
    );
    assert.equal(String(resolvePointer(fixture.manifest, boundary.pointer)), boundary.canonical);
  }
});
