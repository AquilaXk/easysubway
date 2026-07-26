#!/usr/bin/env node
// 이슈 #2529: 모바일 production RSA 검증 경로(`_validateEnvelopeSignature`의
// `publicKey != null` 분기와 `DataPackSigningPublicKey.verify`) 테스트가 쓰는 서명
// fixture를 만든다.
//
// 이슈 #2531(DP-05)이 같은 fixture에 `legacyEnvelopeManifest`(v1 봉투)를 더한다.
// production 공개키가 주입된 빌드가 v1 봉투를 거부하는지 확인하는 회귀 테스트가 쓴다.
//
// Dart 테스트가 기대값을 스스로 계산하면 검증 대상 구현을 복제하게 되어(tautology)
// 회귀를 잡지 못한다. 그래서 정준 문자열은 Node 구현(`tools/datapack/lib/
// manifest-validation.mjs`)이, 서명은 Node `crypto`가 만들어 이 fixture에 고정하고
// Dart 테스트는 저장된 값과 비교만 한다.
//
// 실행 방법:
//   EASYSUBWAY_DATAPACK_TEST_SIGNING_PRIVATE_KEY_PEM="$(cat <테스트 전용 개인키 PEM>)" \
//     node tools/mobile/build-manifest-envelope-signature-fixture.mjs
//
// 키 출처: 저장소가 이미 쓰고 있는 **테스트 전용** 데이터팩 서명 키쌍이다. 공개
// modulus는 `tools/ci/repository-contract.test.mjs`와
// `apps/mobile/test/core/datapack/data_pack_manifest_test.dart`에 이미 커밋돼 있고,
// 짝이 되는 개인키 PEM은 `tools/datapack/datapack-tools.test.mjs`의 테스트 상수다.
// 개인키는 릴리즈 파이프라인이 쓰는 `EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM`이
// **아닌** 전용 변수로만 받고, 유도한 공개 modulus가 아래 상수와 다르면 즉시 실패한다.
// 운영 시크릿이 export된 셸에서 이 스크립트를 돌려도 fixture가 운영 키 산출물로
// 바뀌지 않게 fail closed로 닫은 것이다. 개인키 값은 어디에도 기록하지 않는다.
//
// 배치: 이 파일은 `apps/mobile` 테스트가 쓰는 fixture를 만들지만 `tools/mobile/**`는
// 경로 계약상 repository=true와 **android=true**를 함께 올린다(`tools/ci/
// repository-contract.test.mjs`). 즉 이 생성기만 고쳐도 Android 릴리즈 산출물 잡이
// 함께 돈다. 그 비용을 감수하는 이유는 짝이 되는 검증 테스트(`*.test.mjs`)가
// `tools/mobile/*.test.mjs` 글롭으로 repository 게이트와 mobile 게이트 **양쪽**에
// 배선돼 있어(#2518), Node 정준 규칙 변경과 Dart 전용 변경 모두에서 stale fixture를
// 잡을 수 있기 때문이다. `tools/datapack/`에 두면 datapack 게이트에서만 돈다.
import { constants, createHash, createPrivateKey, createPublicKey, privateDecrypt, publicEncrypt } from "node:crypto";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { canonicalJson, withoutSignature } from "../datapack/lib/manifest-validation.mjs";
import { rsaSha256Signature } from "../datapack/lib/manifest-signing.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const outputPath = path.join(root, "apps/mobile/test/core/datapack/fixtures/production_manifest_envelope.json");

const KEY_ID = "datapack-test-v1";
const PRIVATE_KEY_ENV = "EASYSUBWAY_DATAPACK_TEST_SIGNING_PRIVATE_KEY_PEM";

// 저장소에 이미 커밋된 테스트 전용 키쌍의 공개 modulus. 같은 값이
// `tools/ci/repository-contract.test.mjs`와
// `apps/mobile/test/core/datapack/data_pack_manifest_test.dart`에 있다.
export const EXPECTED_TEST_MODULUS_BASE64URL =
  "itNBIH_FyHbqONXe_z8LNzWes4rh3veI4_8RY76rb7onamA-WDoJlvFyvBG-ihBOl7LtgW1rV54hCLHz95VFLmm028-tll9ThDzSs3Bu9ychED-m0vny16tK8ZgB6gf7sJkjGBJn8MLDaiVWoVvD5TEjv433f_vMFIljdNUKZC2Xf0qHYlYv18dAwbJHKeOsmJkky13HNVn40HuEn5FWEJvFI5qqVgpJ-k1V3ip39ga2-Ek5SOVHAL6U44ypjSXUjo7NCKVpuQRwN7hAnvlYutXDdrEQ6Oa3iUtbQJIgkl-ZmTwNkYHCEIhd_ZLB9n_EEHdvyJAmUKCtAKLX5FOa9w";

// `contracts/datapack/canonical-number-contract.json`의 `formatting` 21건 중 v2
// 매니페스트 필드에 실제로 실을 수 있는 값들. 배제 사유는 JSON 파서 접힘이 아니라
// 필드 값 범위 제약이다.
//   - `integer-valued-fraction`(`1.0`)·`negative-zero-*`(`-0`, `-0.0`) 계열: JSON 파일에
//     리터럴로 살아남지 못한다(`JSON.stringify`가 `1`·`0`으로 되돌린다). DP-02 자체
//     테스트가 맡는다.
//   - `plain-boundary-upper`(1e20)·`exponent-boundary-upper`(1e21)·`max-double`·
//     `safe-integer-boundary`(2^53): 정준화가 안전 정수 범위 밖으로 fail closed 거부하므로
//     서명 가능한 매니페스트에 담을 자리가 없다.
//   - 나머지 1 초과 값: ratio 필드는 `_requiredRatio`가 0..1로 막고, 정수 필드는
//     `sizeBytes`가 양수 정수라 소수를 담을 수 없다.
// 아래 9건이 담을 수 있는 전부다.
function ratioBoundary(packIndex, field, contractId, canonical) {
  return { contractId, pointer: `/packs/${packIndex}/regionalQualityMetrics/${field}`, canonical };
}

export const boundaryNumbers = [
  { contractId: "max-safe-integer", pointer: "/packs/1/sizeBytes", canonical: "9007199254740991" },
  ratioBoundary(0, "facilityCoverageRatio", "double-rounding-artifact", "0.30000000000000004"),
  ratioBoundary(0, "unknownAccessibilityRatio", "plain-boundary-lower", "0.000001"),
  ratioBoundary(1, "facilityCoverageRatio", "exponent-boundary-lower", "1e-7"),
  ratioBoundary(1, "unknownAccessibilityRatio", "smallest-subnormal", "5e-324"),
  ratioBoundary(2, "facilityCoverageRatio", "plain-fraction", "0.1"),
  ratioBoundary(2, "unknownAccessibilityRatio", "exponent-small-mantissa", "1.5e-7"),
  ratioBoundary(3, "facilityCoverageRatio", "exponent-small", "2.5e-10"),
  ratioBoundary(3, "unknownAccessibilityRatio", "zero", "0"),
];

const representativeRouteRegressions = [
  {
    id: "direct-local-capital",
    pattern: "DIRECT",
    fromNodeId: "station-a-line-1",
    toNodeId: "station-b-line-1",
    requiredEdgeIds: ["edge-a-b"],
  },
  {
    id: "transfer-capital",
    pattern: "TRANSFER",
    fromNodeId: "station-a-line-1",
    toNodeId: "station-c-line-2",
    requiredEdgeIds: ["edge-a-b", "edge-b-transfer", "edge-b-c"],
  },
  {
    id: "multi-transfer-capital",
    pattern: "MULTI_TRANSFER",
    fromNodeId: "station-a-line-1",
    toNodeId: "station-d-line-3",
    requiredEdgeIds: ["edge-a-b", "edge-b-transfer", "edge-c-transfer", "edge-c-d"],
  },
  {
    id: "loop-branch-capital",
    pattern: "LOOP_BRANCH",
    fromNodeId: "station-branch-line-2",
    toNodeId: "station-c-line-2",
    requiredEdgeIds: ["edge-branch-loop", "edge-loop-c"],
  },
  {
    id: "express-local-capital",
    pattern: "EXPRESS_LOCAL",
    fromNodeId: "station-a-line-1-express",
    toNodeId: "station-b-line-1-express",
    requiredEdgeIds: ["edge-a-b-express"],
  },
];

export function sha256Hex(value) {
  return createHash("sha256").update(value).digest("hex");
}

export function packPayload(pack) {
  return `${pack.id}:${pack.version}:${pack.sha256}:${pack.sqliteSha256}:${pack.sizeBytes}`;
}

export function routeRegressionPayload(pack) {
  return `${packPayload(pack)}:${JSON.stringify(representativeRouteRegressions)}`;
}

function buildPack({ id, version, sizeBytes, facilityCoverageRatio, unknownAccessibilityRatio, production }) {
  const url = production
    ? `https://cdn.easysubway.example/catalog/${id}-v${version}.sqlite.gz`
    : `catalog/${id}-v${version}.sqlite.gz`;
  return {
    id,
    version,
    url,
    sha256: "a".repeat(64),
    sqliteSha256: "b".repeat(64),
    sizeBytes,
    artifactKind: production ? "production" : "fixture",
    payloadKind: "sqlite_catalog",
    representativeRouteRegressions,
    representativeRouteRegressionSignature: { algorithm: "", value: "" },
    signature: { algorithm: "", value: "" },
    sourceInventory: [
      {
        id: `${id}-catalog`,
        owner: production ? "테스트 공공기관" : "테스트",
        url: "https://example.invalid/source",
        license: production ? "test-open-license" : "fixture-only",
        licenseStatus: production ? "redistributable" : "fixture-only",
        redistributionAllowed: production,
        updateFrequency: "monthly",
        updatedAt: "2026-06-19T00:00:00.000Z",
        fields: ["stations", "network_edges"],
      },
    ],
    regionalQualityMetrics: {
      stationCount: 300,
      facilityCoverageRatio,
      edgeCount: 600,
      unknownAccessibilityRatio,
    },
    schemaVersion: "1",
    requiredTables: ["catalog_metadata", "stations"],
  };
}

function signPack(pack, privateKey) {
  const suffix = pack.artifactKind === "production" ? `:${pack.url}` : "";
  if (pack.artifactKind === "production") {
    pack.signature = {
      algorithm: "rsa-sha256-pack-manifest-v2",
      value: rsaSha256Signature(privateKey, `${packPayload(pack)}${suffix}`),
    };
    pack.representativeRouteRegressionSignature = {
      algorithm: "rsa-sha256-route-regression-v1",
      value: rsaSha256Signature(privateKey, `${routeRegressionPayload(pack)}${suffix}`),
    };
    return pack;
  }
  pack.signature = {
    algorithm: "sha256-pack-manifest-v2",
    value: sha256Hex(packPayload(pack)),
  };
  pack.representativeRouteRegressionSignature = {
    algorithm: "sha256-route-regression-v1",
    value: sha256Hex(routeRegressionPayload(pack)),
  };
  return pack;
}

// 이슈 #2531(DP-05): v1 봉투용 팩 서명. 서명 payload는 v2와 **같은 문자열**이고
// 알고리즘 식별자만 `-v1`이다. 즉 v2 시절에 정당하게 서명된 팩 값이 v1 봉투에서도
// 그대로 유효하다 — 팩 서명이 봉투 버전도 신선도도 결속하지 않는다는 사실을 fixture
// 수준에서 고정한다.
function signLegacyPack(pack, privateKey) {
  const suffix = `:${pack.url}`;
  pack.signature = {
    algorithm: "rsa-sha256-pack-manifest-v1",
    value: rsaSha256Signature(privateKey, `${packPayload(pack)}${suffix}`),
  };
  pack.representativeRouteRegressionSignature = {
    algorithm: "rsa-sha256-route-regression-v1",
    value: rsaSha256Signature(privateKey, `${routeRegressionPayload(pack)}${suffix}`),
  };
  return pack;
}

// v1 봉투용 fixture 팩 서명(공개키 미주입 개발·테스트 빌드 경로). 알고리즘 식별자만
// `-v1`이고 값은 자기해시다.
function signLegacyFixturePack(pack) {
  pack.signature = {
    algorithm: "sha256-pack-manifest-v1",
    value: sha256Hex(packPayload(pack)),
  };
  pack.representativeRouteRegressionSignature = {
    algorithm: "sha256-route-regression-v1",
    value: sha256Hex(routeRegressionPayload(pack)),
  };
  return pack;
}

// v1 봉투: `manifestVersion`·`channel`·`releaseSequence`·`publishedAt`·`expiresAt`·
// `keyId`·`signature`가 전부 없다. 팩만 서명돼 있어 팩 단위 검증은 모두 통과하고,
// 봉투 서명·만료·순번은 애초에 표현되지 않는다.
function legacyEnvelopeManifest({ production, keyId, privateKeyPem }) {
  const manifest = baseManifest({ production, keyId });
  // `signature`는 지금 baseManifest가 만들지 않지만 함께 지운다. 나중에 baseManifest가
  // 봉투 서명을 달면 v1 fixture에 v2 봉투 서명이 남아 회귀 테스트가 조용히 의미를 잃는다.
  for (const field of ["manifestVersion", "channel", "releaseSequence", "publishedAt", "expiresAt", "keyId", "signature"]) {
    delete manifest[field];
  }
  manifest.packs = manifest.packs.map((pack) =>
    production ? signLegacyPack(pack, privateKeyPem) : signLegacyFixturePack(pack),
  );
  return manifest;
}

function baseManifest({ production, keyId }) {
  return {
    manifestVersion: 2,
    channel: "production",
    releaseSequence: 42,
    publishedAt: "2026-07-01T00:00:00.000Z",
    expiresAt: "2026-07-02T00:00:00.000Z",
    ttlSeconds: 3600,
    keyId,
    activePack: { id: "capital", version: "18" },
    rollout: { percentage: 100, seed: "issue-2529" },
    packs: [
      buildPack({
        id: "capital",
        version: "18",
        sizeBytes: 1024,
        facilityCoverageRatio: 0.30000000000000004,
        unknownAccessibilityRatio: 0.000001,
        production,
      }),
      buildPack({
        id: "metro",
        version: "7",
        sizeBytes: 9007199254740991,
        facilityCoverageRatio: 1e-7,
        unknownAccessibilityRatio: 5e-324,
        production,
      }),
      buildPack({
        id: "harbor",
        version: "3",
        sizeBytes: 2048,
        facilityCoverageRatio: 0.1,
        unknownAccessibilityRatio: 1.5e-7,
        production,
      }),
      buildPack({
        id: "valley",
        version: "11",
        sizeBytes: 4096,
        facilityCoverageRatio: 2.5e-10,
        unknownAccessibilityRatio: 0,
        production,
      }),
    ],
  };
}

// 공개키의 modulus 바이트열.
function modulusBytes(publicKey) {
  const jwk = publicKey.export({ format: "jwk" });
  return Buffer.from(jwk.n, "base64url");
}

// 유효 서명을 공개 연산으로 되돌려 EMSA 블록을 얻고, 패딩 바이트 하나만 오염시킨 뒤
// 개인 연산으로 다시 서명한다. 패딩 규칙을 테스트가 직접 조립하지 않으므로
// 검증 구현을 복제하지 않는다.
function forgeCorruptedPadding(privateKeyPem, signatureBase64Url) {
  const privateKey = createPrivateKey(privateKeyPem);
  const publicKey = createPublicKey(privateKey);
  const signature = Buffer.from(signatureBase64Url, "base64url");
  const block = publicEncrypt({ key: publicKey, padding: constants.RSA_NO_PADDING }, signature);
  if (block[0] !== 0x00 || block[1] !== 0x01 || block[5] !== 0xff) {
    throw new Error("unexpected PKCS#1 v1.5 block layout");
  }
  const corrupted = Buffer.from(block);
  corrupted[5] = 0xfe;
  return privateDecrypt({ key: privateKey, padding: constants.RSA_NO_PADDING }, corrupted).toString("base64url");
}

export function powMod(base, exponent, modulus) {
  let result = 1n;
  let factor = base % modulus;
  let remaining = exponent;
  while (remaining > 0n) {
    if (remaining & 1n) result = (result * factor) % modulus;
    factor = (factor * factor) % modulus;
    remaining >>= 1n;
  }
  return result;
}

// 확장 유클리드 호제법. gcd가 1이 아니면 역원이 없다.
function modInverse(value, modulus) {
  let remainder = value % modulus;
  let nextRemainder = modulus;
  let coefficient = 1n;
  let nextCoefficient = 0n;
  while (nextRemainder > 0n) {
    const quotient = remainder / nextRemainder;
    [remainder, nextRemainder] = [nextRemainder, remainder - quotient * nextRemainder];
    [coefficient, nextCoefficient] = [nextCoefficient, coefficient - quotient * nextCoefficient];
  }
  if (remainder > 1n) throw new Error("modular inverse does not exist");
  return ((coefficient % modulus) + modulus) % modulus;
}

function bigIntToBytes(value, length) {
  const bytes = Buffer.alloc(length);
  let remaining = value;
  for (let index = length - 1; index >= 0; index -= 1) {
    bytes[index] = Number(remaining & 0xffn);
    remaining >>= 8n;
  }
  if (remaining !== 0n) throw new Error("value exceeds requested length");
  return bytes;
}

const MILLER_RABIN_BASES = [2n, 3n, 5n, 7n, 11n, 13n, 17n, 19n, 23n, 29n, 31n, 37n, 41n, 43n, 47n, 53n];

function isProbablePrime(candidate) {
  for (const small of MILLER_RABIN_BASES) {
    if (candidate % small === 0n) return candidate === small;
  }
  let d = candidate - 1n;
  let r = 0n;
  while (d % 2n === 0n) {
    d /= 2n;
    r += 1n;
  }
  for (const base of MILLER_RABIN_BASES) {
    let x = powMod(base, d, candidate);
    if (x === 1n || x === candidate - 1n) continue;
    let witness = true;
    for (let round = 1n; round < r; round += 1n) {
      x = (x * x) % candidate;
      if (x === candidate - 1n) {
        witness = false;
        break;
      }
    }
    if (witness) return false;
  }
  return true;
}

// SHA-256 DigestInfo(51 byte)와 PKCS#1 v1.5 최소 패딩 8 byte를 함께 담기에는 딱 한
// 바이트가 모자란 modulus를 만든다. 61 byte modulus면 패딩이 7 byte뿐이라
// `paddingLength < 8` 판정에 걸린다.
//
// n은 2^488-1에서 아래로 훑어 찾은 첫 소수다(탐색 시작점이 고정이라 재생성해도 같은
// 값이 나온다). n이 소수라 d = e^-1 mod (n-1)을 인수분해 없이 구할 수 있고, 덕분에
// 개인키를 저장하지 않고도 "패딩 7 byte짜리 구조상 정상인 블록"의 진짜 RSA 변환 결과를
// fixture에 담을 수 있다. 즉 이 서명은 최소 패딩 규칙이 없으면 검증에 성공한다.
function undersizedModulusCase(message) {
  const length = 61;
  const e = 65537n;
  let n = 2n ** BigInt(length * 8) - 1n;
  while (!isProbablePrime(n) || (n - 1n) % e === 0n) {
    n -= 2n;
  }
  const d = modInverse(e, n - 1n);
  const digestInfo = Buffer.concat([
    Buffer.from([
      0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04,
      0x20,
    ]),
    createHash("sha256").update(message).digest(),
  ]);
  const paddingLength = length - digestInfo.length - 3;
  const block = Buffer.concat([
    Buffer.from([0x00, 0x01]),
    Buffer.alloc(paddingLength, 0xff),
    Buffer.from([0x00]),
    digestInfo,
  ]);
  if (block.length !== length) throw new Error("unexpected undersized block length");
  const signature = powMod(BigInt(`0x${block.toString("hex")}`), d, n);
  return {
    keyId: KEY_ID,
    modulusBase64Url: bigIntToBytes(n, length).toString("base64url"),
    exponentBase64Url: bigIntToBytes(e, 3).toString("base64url"),
    signatureValue: bigIntToBytes(signature, length).toString("base64url"),
    modulusLengthBytes: length,
    paddingLength,
    note: "패딩 7 byte짜리 구조상 정상인 PKCS#1 v1.5 블록의 진짜 RSA 변환 — 최소 패딩 규칙만이 이를 막는다",
  };
}

export function buildFixture(privateKeyPem) {
  const publicKey = createPublicKey(createPrivateKey(privateKeyPem));
  const modulus = modulusBytes(publicKey);

  // fail closed: 운영 서명 키(같은 이름의 릴리즈 시크릿)로 fixture가 재생성되어 공개
  // 저장소에 커밋되는 경로를 막는다. Dart 테스트는 검증 공개키를 fixture 자신에서
  // 읽으므로 어떤 키로 만든 fixture든 초록이라, 이 가드가 유일한 기계적 방어다.
  if (modulus.toString("base64url") !== EXPECTED_TEST_MODULUS_BASE64URL) {
    throw new Error(
      "이 생성기는 저장소의 테스트 전용 데이터팩 서명 키로만 실행한다 (유도한 modulus가 기대값과 다르다)",
    );
  }

  const manifest = baseManifest({ production: true, keyId: KEY_ID });
  manifest.packs = manifest.packs.map((pack) => signPack(pack, privateKeyPem));
  const canonicalSignedPayload = canonicalJson(withoutSignature(manifest));
  const signatureValue = rsaSha256Signature(privateKeyPem, canonicalSignedPayload);
  manifest.signature = { algorithm: "rsa-sha256-manifest-v2", value: signatureValue };

  const tamperedBodyOverrides = { releaseSequence: 43 };
  const keyIdMismatchOverrides = { keyId: "rotated-key-v9" };
  const keyIdMismatchManifest = { ...withoutSignature(manifest), ...keyIdMismatchOverrides };

  const tamperedSignature = Buffer.from(signatureValue, "base64url");
  tamperedSignature[200] ^= 0x01;

  const fallbackManifest = baseManifest({ production: false, keyId: KEY_ID });
  fallbackManifest.packs = fallbackManifest.packs.map((pack) => signPack(pack, privateKeyPem));
  const fallbackCanonical = canonicalJson(withoutSignature(fallbackManifest));
  fallbackManifest.signature = { algorithm: "sha256-manifest-v2", value: sha256Hex(fallbackCanonical) };

  const fixture = {
    $comment:
      "이슈 #2529 — 생성기 tools/mobile/build-manifest-envelope-signature-fixture.mjs. 손으로 고치지 말 것. 정준 문자열과 서명은 Node 구현이 만든 값이며 Dart 테스트는 비교만 한다.",
    keyId: KEY_ID,
    publicKey: {
      keyId: KEY_ID,
      modulusBase64Url: modulus.toString("base64url"),
      exponentBase64Url: Buffer.from(publicKey.export({ format: "jwk" }).e, "base64url").toString("base64url"),
      modulusLengthBytes: modulus.length,
    },
    manifest,
    canonicalSignedPayload,
    manifestHashSha256: sha256Hex(canonicalSignedPayload),
    boundaryNumbers,
    rejections: {
      tamperedBody: {
        overrides: tamperedBodyOverrides,
        note: "본문 한 필드만 바꾸고 원 서명을 유지한다",
      },
      tamperedSignatureValue: tamperedSignature.toString("base64url"),
      keyIdMismatch: {
        overrides: keyIdMismatchOverrides,
        signatureValue: rsaSha256Signature(privateKeyPem, canonicalJson(keyIdMismatchManifest)),
        note: "서명 자체는 유효하고 keyId만 어긋난다",
      },
      selfHashAlgorithmValue: sha256Hex(canonicalSignedPayload),
      packManifestAlgorithmValue: signatureValue,
      shortSignatureValue: Buffer.from(signatureValue, "base64url").subarray(0, 128).toString("base64url"),
      signatureAboveModulusValue: Buffer.alloc(modulus.length, 0xff).toString("base64url"),
      // 문자는 전부 base64url 알파벳이고 길이만 4의 배수+1이라 틀렸다. charset 위반
      // 문자열은 `DataPackSignature.fromJson`의 `^[A-Za-z0-9_-]+$` 검사가 verify 앞에서
      // 거부하므로, verify 내부의 `on FormatException` 폴백에 도달할 수 있는 입력은
      // 길이 위반뿐이다.
      invalidBase64UrlLengthValue: "A".repeat(341),
      corruptedPaddingValue: forgeCorruptedPadding(privateKeyPem, signatureValue),
      undersizedModulusKey: undersizedModulusCase(canonicalSignedPayload),
    },
    fallbackManifest,
    fallbackCanonicalSignedPayload: fallbackCanonical,
    legacyEnvelopeManifest: legacyEnvelopeManifest({ production: true, keyId: KEY_ID, privateKeyPem }),
    legacyFallbackEnvelopeManifest: legacyEnvelopeManifest({ production: false, keyId: KEY_ID, privateKeyPem }),
  };

  return fixture;
}

async function main() {
  const privateKeyPem = process.env[PRIVATE_KEY_ENV]?.trim();
  if (!privateKeyPem) {
    throw new Error(`${PRIVATE_KEY_ENV} 가 필요하다 (저장소의 테스트 전용 데이터팩 서명 개인키 PEM)`);
  }
  const fixture = buildFixture(privateKeyPem);
  await writeFile(outputPath, `${JSON.stringify(fixture, null, 2)}\n`, "utf8");
  process.stdout.write(`${path.relative(root, outputPath)} 갱신 완료\n`);
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  await main();
}
