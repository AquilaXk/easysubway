#!/usr/bin/env node
// 이슈 #2529: 모바일 production RSA 검증 경로(`_validateEnvelopeSignature`의
// `publicKey != null` 분기와 `DataPackSigningPublicKey.verify`) 테스트가 쓰는 서명
// fixture를 만든다.
//
// Dart 테스트가 기대값을 스스로 계산하면 검증 대상 구현을 복제하게 되어(tautology)
// 회귀를 잡지 못한다. 그래서 정준 문자열은 Node 구현(`tools/datapack/lib/
// manifest-validation.mjs`)이, 서명은 Node `crypto`가 만들어 이 fixture에 고정하고
// Dart 테스트는 저장된 값과 비교만 한다.
//
// 실행 방법:
//   EASYSUBWAY_DATAPACK_SIGNING_PRIVATE_KEY_PEM="$(cat <테스트 전용 개인키 PEM>)" \
//     node tools/mobile/build-manifest-envelope-signature-fixture.mjs
//
// 키 출처: 저장소가 이미 쓰고 있는 **테스트 전용** 데이터팩 서명 키쌍이다. 공개
// modulus는 `tools/ci/repository-contract.test.mjs`와
// `apps/mobile/test/core/datapack/data_pack_manifest_test.dart`에 이미 커밋돼 있고,
// 짝이 되는 개인키 PEM은 `tools/datapack/datapack-tools.test.mjs`의 테스트 상수다.
// 운영 서명 키는 저장소에 존재하지 않으며 CI 시크릿으로만 주입되므로 이 fixture와
// 무관하다. 이 스크립트는 개인키를 인자로 받기만 하고 어디에도 기록하지 않는다.
import { constants, createHash, createPrivateKey, createPublicKey, privateDecrypt, publicEncrypt } from "node:crypto";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { canonicalJson, withoutSignature } from "../datapack/lib/manifest-validation.mjs";
import { rsaSha256Signature, signingPrivateKey } from "../datapack/lib/manifest-signing.mjs";

const root = path.resolve(import.meta.dirname, "../..");
const outputPath = path.join(root, "apps/mobile/test/core/datapack/fixtures/production_manifest_envelope.json");

const KEY_ID = "datapack-test-v1";

// `contracts/datapack/canonical-number-contract.json`의 경계 숫자 중 JSON 파일에
// 리터럴로 살아남는 것들. `1.0`·`-0.0`처럼 파서가 접어버리는 표기는 JSON 파일에
// 담을 수 없어(JSON.stringify가 `1`·`0`으로 되돌린다) DP-02 자체 테스트가 맡는다.
const boundaryNumbers = [
  { contractId: "max-safe-integer", pointer: "/packs/1/sizeBytes", canonical: "9007199254740991" },
  {
    contractId: "double-rounding-artifact",
    pointer: "/packs/0/regionalQualityMetrics/facilityCoverageRatio",
    canonical: "0.30000000000000004",
  },
  {
    contractId: "plain-boundary-lower",
    pointer: "/packs/0/regionalQualityMetrics/unknownAccessibilityRatio",
    canonical: "0.000001",
  },
  {
    contractId: "exponent-boundary-lower",
    pointer: "/packs/1/regionalQualityMetrics/facilityCoverageRatio",
    canonical: "1e-7",
  },
  {
    contractId: "smallest-subnormal",
    pointer: "/packs/1/regionalQualityMetrics/unknownAccessibilityRatio",
    canonical: "5e-324",
  },
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

function sha256Hex(value) {
  return createHash("sha256").update(value).digest("hex");
}

function packPayload(pack) {
  return `${pack.id}:${pack.version}:${pack.sha256}:${pack.sqliteSha256}:${pack.sizeBytes}`;
}

function routeRegressionPayload(pack) {
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

function powMod(base, exponent, modulus) {
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

function modInverse(value, modulus) {
  let [old_r, r] = [value % modulus, modulus];
  let [old_s, s] = [1n, 0n];
  while (r !== 0n) {
    const quotient = old_r / r;
    [old_r, r] = [r, old_r - quotient * r];
    [old_s, s] = [s, old_s - quotient * s];
  }
  if (old_r !== 1n) throw new Error("modular inverse does not exist");
  return ((old_s % modulus) + modulus) % modulus;
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

async function main() {
  const privateKeyPem = signingPrivateKey();
  const publicKey = createPublicKey(createPrivateKey(privateKeyPem));
  const modulus = modulusBytes(publicKey);

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
      nonBase64UrlValue: "A".repeat(341),
      corruptedPaddingValue: forgeCorruptedPadding(privateKeyPem, signatureValue),
      undersizedModulusKey: undersizedModulusCase(canonicalSignedPayload),
    },
    fallbackManifest,
    fallbackCanonicalSignedPayload: fallbackCanonical,
  };

  await writeFile(outputPath, `${JSON.stringify(fixture, null, 2)}\n`, "utf8");
  process.stdout.write(`${path.relative(root, outputPath)} 갱신 완료\n`);
}

await main();
