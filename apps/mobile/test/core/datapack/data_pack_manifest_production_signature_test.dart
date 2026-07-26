import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
// 정준 직렬화는 검증 대상 구현을 그대로 쓴다. 테스트가 규칙을 복제하면 3언어
// 분열(이슈 #2528)을 구조적으로 검출할 수 없다.
import 'package:easysubway_mobile/core/datapack/canonical_json.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// 이슈 #2529 — production 매니페스트 봉투 서명(RSA) 검증 경로 커버리지.
///
/// `_validateEnvelopeSignature`의 `publicKey != null` 분기와
/// `DataPackSigningPublicKey.verify`(RSASSA-PKCS1-v1_5 직접 구현)를 덮는다.
///
/// 기대값은 전부 `apps/mobile/test/core/datapack/fixtures/`의 저장 fixture에서
/// 읽는다. 그 fixture는 Node 구현(`tools/datapack/lib/manifest-validation.mjs`,
/// `node:crypto`)이 만들었고 생성기는
/// `tools/mobile/build-manifest-envelope-signature-fixture.mjs`다. 테스트가 정준
/// 문자열이나 서명을 스스로 계산하면 검증 대상 구현을 복제하게 되어(tautology) 회귀를
/// 잡지 못하므로, 여기서는 저장된 값과 비교만 한다.
///
/// 서명 키쌍은 저장소가 이미 쓰는 **테스트 전용** 데이터팩 서명 키쌍이다. 공개
/// modulus는 `tools/ci/repository-contract.test.mjs`에도 같은 값으로 커밋돼 있고,
/// 운영 서명 키는 저장소에 존재하지 않고 CI 시크릿으로만 주입되므로 무관하다. 개인키는
/// 이 테스트에도 fixture에도 담지 않는다.
void main() {
  final fixture = _loadJson(
    'apps/mobile/test/core/datapack/fixtures/production_manifest_envelope.json',
  );
  final contract = _loadJson(
    'contracts/datapack/canonical-number-contract.json',
  );

  final publicKeyJson = fixture['publicKey']! as Map<String, Object?>;
  final publicKey = DataPackSigningPublicKey(
    modulusBase64Url: publicKeyJson['modulusBase64Url']! as String,
    exponentBase64Url: publicKeyJson['exponentBase64Url']! as String,
    keyId: publicKeyJson['keyId']! as String,
  );
  final canonicalSignedPayload = fixture['canonicalSignedPayload']! as String;
  final manifestHashSha256 = fixture['manifestHashSha256']! as String;
  final rejections = fixture['rejections']! as Map<String, Object?>;
  final signedSignatureValue =
      (fixture['manifest']! as Map<String, Object?>)['signature']!
          as Map<String, Object?>;
  final validSignatureValue = signedSignatureValue['value']! as String;

  Map<String, Object?> manifestJson() =>
      _clone(fixture['manifest']! as Map<String, Object?>);

  Map<String, Object?> withSignature(
    Map<String, Object?> manifest,
    Map<String, Object?> signature,
  ) {
    return manifest..['signature'] = signature;
  }

  Map<String, Object?> withSignatureValue(String value) {
    return withSignature(manifestJson(), {
      'algorithm': 'rsa-sha256-manifest-v2',
      'value': value,
    });
  }

  test('1. 올바른 keyId·rsa-sha256-manifest-v2·유효 서명이면 매니페스트 파싱이 끝까지 완료된다', () {
    final manifest = DataPackManifest.fromJson(
      manifestJson(),
      productionSigningPublicKey: publicKey,
    );

    expect(manifest.keyId, publicKey.keyId);
    expect(manifest.signature?.algorithm, 'rsa-sha256-manifest-v2');
    expect(manifest.signature?.value, validSignatureValue);
    expect(manifest.packs.map((pack) => pack.id), [
      'capital',
      'metro',
      'harbor',
      'valley',
    ]);
    expect(
      manifest.packs.map((pack) => pack.artifactKind),
      everyElement(DataPackArtifactKind.production),
    );

    // `publicKey != null` 분기가 실제로 실행됐다는 근거. 자기해시 폴백 블록은
    // 알고리즘이 `sha256-manifest-v2`가 아니면 무조건 거부하므로,
    // `rsa-sha256-manifest-v2` 봉투가 수용되는 경로는 RSA 분기밖에 없다. 같은 문서를
    // 공개키 없이 파싱하면 폴백이 거부한다.
    expect(
      () => DataPackManifest.fromJson(manifestJson()),
      throwsFormatException,
    );
  });

  test('2. manifestVersion 2 필수 필드가 모두 채워지고 manifestHash가 계산된다', () {
    final manifest = DataPackManifest.fromJson(
      manifestJson(),
      productionSigningPublicKey: publicKey,
    );

    expect(manifest.manifestVersion, 2);
    expect(manifest.channel, 'production');
    expect(manifest.releaseSequence, 42);
    expect(manifest.publishedAt, DateTime.utc(2026, 7, 1));
    expect(manifest.expiresAt, DateTime.utc(2026, 7, 2));
    expect(manifest.hasReplayProtection, isTrue);
    expect(manifest.manifestHash, manifestHashSha256);
    expect(manifest.rollout?.percentage, 100);
    expect(manifest.ttl, const Duration(hours: 1));
  });

  test('3. 서명 대상은 signature 키를 제외한 정준 JSON이다', () {
    expect(_canonicalWithoutSignature(manifestJson()), canonicalSignedPayload);

    // signature 객체를 통째로 다른 내용으로 바꿔도 서명 대상 정준 문자열과 replay
    // hash는 달라지지 않는다 — 봉투가 서명 범위 밖이라는 사실을 이것으로 고정한다.
    // 알 수 없는 키를 봉투에 넣었을 때 수용할지 거부할지는 여기서 판단하지 않는다.
    // 그 정책은 DP-05(#2531, v2 봉투 엄격 파싱)의 몫이고, 여기서 "수용한다"를 고정하면
    // 후속 하드닝이 테스트 회귀로 보이는 함정이 된다.
    final replacedEnvelope = withSignature(manifestJson(), {
      'algorithm': 'sha256-manifest-v2',
      'value': rejections['selfHashAlgorithmValue']! as String,
    });
    expect(
      _canonicalWithoutSignature(replacedEnvelope),
      canonicalSignedPayload,
    );

    final manifest = DataPackManifest.fromJson(
      manifestJson(),
      productionSigningPublicKey: publicKey,
    );
    expect(manifest.manifestHash, manifestHashSha256);
    expect(
      publicKey.verify(canonicalSignedPayload, validSignatureValue),
      isTrue,
    );
  });

  test('4. 본문을 한 필드만 변조하고 원 서명을 유지하면 거부한다', () {
    final tampered = manifestJson();
    final overrides =
        (rejections['tamperedBody']! as Map<String, Object?>)['overrides']!
            as Map<String, Object?>;
    tampered.addAll(_clone(overrides));

    // 서명 대상 정준 문자열이 실제로 달라졌음을 먼저 고정한다.
    expect(_canonicalWithoutSignature(tampered), isNot(canonicalSignedPayload));
    expect(
      () => DataPackManifest.fromJson(
        tampered,
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('5. 서명 값 1바이트만 변조해도 거부한다', () {
    final tamperedValue = rejections['tamperedSignatureValue']! as String;

    expect(tamperedValue, isNot(validSignatureValue));
    expect(
      _base64UrlLength(tamperedValue),
      _base64UrlLength(validSignatureValue),
    );
    expect(publicKey.verify(canonicalSignedPayload, tamperedValue), isFalse);
    expect(
      () => DataPackManifest.fromJson(
        withSignatureValue(tamperedValue),
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('6. keyId가 주입 공개키와 다르면 서명이 유효해도 거부한다', () {
    final mismatch = rejections['keyIdMismatch']! as Map<String, Object?>;
    final rotated = manifestJson()
      ..addAll(_clone(mismatch['overrides']! as Map<String, Object?>));
    final rotatedSignature = mismatch['signatureValue']! as String;

    // 서명 자체는 유효하다 — 거부 사유가 keyId 하나로 좁혀진다.
    expect(
      publicKey.verify(_canonicalWithoutSignature(rotated), rotatedSignature),
      isTrue,
    );
    expect(rotated['keyId'], isNot(publicKey.keyId));
    expect(
      () => DataPackManifest.fromJson(
        withSignature(rotated, {
          'algorithm': 'rsa-sha256-manifest-v2',
          'value': rotatedSignature,
        }),
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('7. 공개키가 있으면 자기해시 봉투(sha256-manifest-v2)로 내려가지 않고 거부한다', () {
    final selfHashValue = rejections['selfHashAlgorithmValue']! as String;

    // 폴백 블록이라면 수용했을 값이다(= 정준 문자열의 sha256).
    expect(selfHashValue, manifestHashSha256);
    expect(
      selfHashValue,
      sha256.convert(utf8.encode(canonicalSignedPayload)).toString(),
    );
    expect(
      () => DataPackManifest.fromJson(
        withSignature(manifestJson(), {
          'algorithm': 'sha256-manifest-v2',
          'value': selfHashValue,
        }),
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('8. 다른 RSA 알고리즘 식별자는 서명이 유효해도 거부한다', () {
    final value = rejections['packManifestAlgorithmValue']! as String;

    expect(publicKey.verify(canonicalSignedPayload, value), isTrue);
    expect(
      () => DataPackManifest.fromJson(
        withSignature(manifestJson(), {
          'algorithm': 'rsa-sha256-pack-manifest-v1',
          'value': value,
        }),
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('9. signature 필드 자체가 없으면 파싱 단계 타입 가드가 먼저 거부한다', () {
    final withoutSignature = manifestJson()..remove('signature');

    // 실측: `manifestVersion == 2`면 `DataPackManifest.fromJson`이 봉투 검증보다 먼저
    // `_parseManifestEnvelopeSignature(json['signature'])`를 호출하고, 인자가 null이면
    // Map이 아니라서 그 자리에서 FormatException이 난다. 그래서 이슈가 지목한
    // `_validateEnvelopeSignature`의 `parsedSignature == null` 가드는 v2 경로에서
    // 도달 불가능하고, 이 케이스는 봉투 검증이 아니라 파싱 단계에서 닫힌다.
    // 공개키 유무와 무관하게 같은 지점에서 거부되는 것이 그 근거다.
    expect(
      () => DataPackManifest.fromJson(
        withoutSignature,
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
    expect(
      () => DataPackManifest.fromJson(manifestJson()..remove('signature')),
      throwsFormatException,
    );
  });

  test('10. 서명 길이가 modulus 길이와 다르면 거부한다', () {
    final shortValue = rejections['shortSignatureValue']! as String;

    expect(_base64UrlLength(shortValue), 128);
    expect(
      _base64UrlLength(shortValue),
      isNot(publicKeyJson['modulusLengthBytes']),
    );
    expect(publicKey.verify(canonicalSignedPayload, shortValue), isFalse);
    expect(
      () => DataPackManifest.fromJson(
        withSignatureValue(shortValue),
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('11. 서명 정수값이 modulus 이상이면 거부한다', () {
    final oversizedValue = rejections['signatureAboveModulusValue']! as String;

    // 길이 검사는 통과하고 크기 검사에서만 걸린다.
    expect(
      _base64UrlLength(oversizedValue),
      publicKeyJson['modulusLengthBytes'],
    );
    expect(
      _base64UrlBigInt(oversizedValue),
      greaterThan(_base64UrlBigInt(publicKey.modulusBase64Url)),
    );
    expect(publicKey.verify(canonicalSignedPayload, oversizedValue), isFalse);
    expect(
      () => DataPackManifest.fromJson(
        withSignatureValue(oversizedValue),
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('12. base64url 디코딩이 실패하는 서명 값은 예외가 새지 않고 거부로 닫힌다', () {
    final invalidValue = rejections['invalidBase64UrlLengthValue']! as String;

    // 문자는 전부 base64url 알파벳이고 길이만 4의 배수+1이다. charset 위반 문자열은
    // `DataPackSignature.fromJson`의 `^[A-Za-z0-9_-]+$` 검사가 verify 앞에서 거부하므로,
    // verify 내부의 `on FormatException` 폴백에 도달할 수 있는 입력은 길이 위반뿐이다.
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(invalidValue), isTrue);
    expect(invalidValue.length % 4, 1);
    expect(
      () => DataPackSignature.fromJson({
        'algorithm': 'rsa-sha256-manifest-v2',
        'value': 'not/base64url+value',
      }),
      throwsFormatException,
    );

    // 서명 값 문법 검사(DataPackSignature)는 통과해 verify까지 도달한다.
    expect(
      DataPackSignature.fromJson({
        'algorithm': 'rsa-sha256-manifest-v2',
        'value': invalidValue,
      }).value,
      invalidValue,
    );
    expect(
      () => base64Url.decode(base64Url.normalize(invalidValue)),
      throwsFormatException,
    );
    expect(publicKey.verify(canonicalSignedPayload, invalidValue), isFalse);
    expect(
      () => DataPackManifest.fromJson(
        withSignatureValue(invalidValue),
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('13. PKCS#1 v1.5 패딩 바이트가 오염된 서명은 거부한다', () {
    final corruptedValue = rejections['corruptedPaddingValue']! as String;

    // 같은 키의 진짜 RSA 변환 결과이고 길이도 같다 — 차이는 패딩 바이트 하나뿐이다.
    expect(
      _base64UrlLength(corruptedValue),
      publicKeyJson['modulusLengthBytes'],
    );
    expect(corruptedValue, isNot(validSignatureValue));
    expect(publicKey.verify(canonicalSignedPayload, corruptedValue), isFalse);
    expect(
      () => DataPackManifest.fromJson(
        withSignatureValue(corruptedValue),
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('14. modulus가 너무 작아 최소 패딩 8바이트를 못 채우면 verify가 false로 닫힌다', () {
    final undersized =
        rejections['undersizedModulusKey']! as Map<String, Object?>;
    final undersizedKey = DataPackSigningPublicKey(
      modulusBase64Url: undersized['modulusBase64Url']! as String,
      exponentBase64Url: undersized['exponentBase64Url']! as String,
      keyId: undersized['keyId']! as String,
    );
    final undersizedSignature = undersized['signatureValue']! as String;

    // verify의 앞선 가드는 모두 통과하는 입력이다: modulus·exponent 비어 있지 않고,
    // 서명 길이가 modulus 길이와 같고, 서명 정수값이 modulus 미만이다. 게다가 이
    // 서명은 패딩 7바이트짜리 "구조상 정상인" PKCS#1 v1.5 블록의 진짜 RSA 변환이라
    // 최소 패딩 8바이트 규칙이 없으면 검증에 성공해 버린다. 거부 사유가
    // paddingLength < 8 하나로 좁혀진다.
    expect(undersized['modulusLengthBytes'], 61);
    expect(undersized['paddingLength'], 7);
    expect(_base64UrlLength(undersizedKey.modulusBase64Url), 61);
    expect(_base64UrlLength(undersizedSignature), 61);
    expect(
      _base64UrlBigInt(undersizedKey.exponentBase64Url),
      BigInt.from(65537),
    );
    expect(
      _base64UrlBigInt(undersizedSignature),
      lessThan(_base64UrlBigInt(undersizedKey.modulusBase64Url)),
    );
    expect(
      undersizedKey.verify(canonicalSignedPayload, undersizedSignature),
      isFalse,
    );

    // 같은 메시지가 정상 키에서는 검증에 성공한다 — verify가 늘 false인 게 아니다.
    expect(
      publicKey.verify(canonicalSignedPayload, validSignatureValue),
      isTrue,
    );
  });

  test('15. DP-02 정준 계약의 경계 숫자를 담은 매니페스트도 RSA 검증에 성공한다', () {
    final boundaries = (fixture['boundaryNumbers']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(boundaries, isNotEmpty);

    final manifest = manifestJson();
    // 서명 대상 정준 문자열을 되짚어 같은 pointer 위치의 값을 확인한다. 키 이름만
    // 보는 `contains`는 `/packs/0`과 `/packs/1`처럼 같은 키가 여러 곳에 있을 때 값이
    // 서로 뒤바뀌어도 통과하므로 위치까지 닫지 못한다.
    final signedDocument =
        jsonDecode(canonicalSignedPayload) as Map<String, Object?>;
    for (final boundary in boundaries) {
      final pointer = boundary['pointer']! as String;
      final canonical = boundary['canonical']! as String;
      expect(
        canonicalDataPackJson(_resolvePointer(manifest, pointer)),
        canonical,
        reason: '$pointer 값의 정준 표기가 계약과 다르다',
      );
      expect(
        canonicalDataPackJson(_resolvePointer(signedDocument, pointer)),
        canonical,
        reason: '$pointer 위치의 값이 서명 대상 정준 문자열에서 계약 표기와 다르다',
      );
    }

    // 정준 표기 규칙이 하나라도 바뀌면 정준 문자열이 달라져 이 검증이 깨진다.
    expect(_canonicalWithoutSignature(manifest), canonicalSignedPayload);
    expect(
      DataPackManifest.fromJson(
        manifest,
        productionSigningPublicKey: publicKey,
      ).manifestHash,
      manifestHashSha256,
    );
  });

  test('16. 매니페스트 정준 문자열이 Node·Java 공유 계약 기대값과 일치한다', () {
    // fixture의 정준 문자열은 Node 구현이 만든 값이다. Dart가 같은 바이트를 만드는지
    // 비교하는 것이 3언어 정합의 모바일 쪽 교차 확인이다.
    expect(_canonicalWithoutSignature(manifestJson()), canonicalSignedPayload);

    final formatting = (contract['formatting']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final contractCanonical = {
      for (final entry in formatting)
        entry['id']! as String: entry['canonical']! as String,
    };
    final boundaries = (fixture['boundaryNumbers']! as List<Object?>)
        .cast<Map<String, Object?>>();
    for (final boundary in boundaries) {
      final contractId = boundary['contractId']! as String;
      expect(
        contractCanonical[contractId],
        boundary['canonical'],
        reason:
            '$contractId 표기가 contracts/datapack/canonical-number-contract.json 과 다르다',
      );
    }
  });

  test('17. 공개키 미주입 시 자기해시 폴백 동작이 그대로 유지된다', () {
    final fallbackJson = _clone(
      fixture['fallbackManifest']! as Map<String, Object?>,
    );
    final fallbackCanonical =
        fixture['fallbackCanonicalSignedPayload']! as String;
    final manifest = DataPackManifest.fromJson(_clone(fallbackJson));

    expect(manifest.signature?.algorithm, 'sha256-manifest-v2');
    expect(_canonicalWithoutSignature(_clone(fallbackJson)), fallbackCanonical);
    expect(
      manifest.manifestHash,
      sha256.convert(utf8.encode(fallbackCanonical)).toString(),
    );
    expect(
      manifest.packs.map((pack) => pack.artifactKind),
      everyElement(DataPackArtifactKind.fixture),
    );

    // 폴백 문서는 공개키가 주입되면 오히려 거부돼야 한다(분기 전환이 실제로 일어난다).
    expect(
      () => DataPackManifest.fromJson(
        _clone(fallbackJson),
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });
}

String _canonicalWithoutSignature(Map<String, Object?> manifest) {
  return canonicalDataPackJson({
    for (final entry in manifest.entries)
      if (entry.key != 'signature') entry.key: entry.value,
  });
}

int _base64UrlLength(String value) {
  return base64Url.decode(base64Url.normalize(value)).length;
}

BigInt _base64UrlBigInt(String value) {
  var result = BigInt.zero;
  for (final byte in base64Url.decode(base64Url.normalize(value))) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Object? _resolvePointer(Object? root, String pointer) {
  var current = root;
  for (final rawSegment in pointer.split('/').skip(1)) {
    final segment = rawSegment.replaceAll('~1', '/').replaceAll('~0', '~');
    current = switch (current) {
      final Map<String, Object?> map => map[segment],
      final List<Object?> list => list[int.parse(segment)],
      _ => fail('JSON pointer $pointer 를 해석할 수 없다'),
    };
  }
  return current;
}

Map<String, Object?> _clone(Map<String, Object?> value) {
  return jsonDecode(jsonEncode(value)) as Map<String, Object?>;
}

Map<String, Object?> _loadJson(String relativePath) {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth += 1) {
    final file = File('${directory.path}/$relativePath');
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    }
    directory = directory.parent;
  }
  fail('$relativePath not found from ${Directory.current.path}');
}
