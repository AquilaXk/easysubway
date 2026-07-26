import 'dart:convert';
import 'dart:io';

// 정준 직렬화는 검증 대상 구현을 그대로 쓴다. 테스트가 규칙을 복제하면 3언어
// 분열(이슈 #2528)을 구조적으로 검출할 수 없다.
import 'package:easysubway_mobile/core/datapack/canonical_json.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// 이슈 #2531(DP-05) — 봉투 수락 경로 fail-closed.
///
/// production 서명 공개키가 주입된 빌드는 신선도를 증명할 수 없는 v1 봉투를 수락하지
/// 않는다. 검증 하네스는 DP-03(#2529)이 만든
/// `apps/mobile/test/core/datapack/fixtures/production_manifest_envelope.json`을
/// 그대로 쓴다. 그 fixture의 `legacyEnvelopeManifest`는 Node 구현이 만든 v1 봉투이며
/// 팩 서명은 v2 봉투의 값과 바이트 동일하다(생성기:
/// `tools/mobile/build-manifest-envelope-signature-fixture.mjs`). 테스트가 서명을 스스로
/// 만들면 검증 대상 구현을 복제하게 되므로 저장 값과 비교만 한다.
void main() {
  final fixture = _loadJson(
    'apps/mobile/test/core/datapack/fixtures/production_manifest_envelope.json',
  );

  final publicKeyJson = fixture['publicKey']! as Map<String, Object?>;
  final publicKey = DataPackSigningPublicKey(
    modulusBase64Url: publicKeyJson['modulusBase64Url']! as String,
    exponentBase64Url: publicKeyJson['exponentBase64Url']! as String,
    keyId: publicKeyJson['keyId']! as String,
  );
  final canonicalSignedPayload = fixture['canonicalSignedPayload']! as String;

  Map<String, Object?> legacyJson() =>
      _clone(fixture['legacyEnvelopeManifest']! as Map<String, Object?>);

  Map<String, Object?> legacyFallbackJson() => _clone(
    fixture['legacyFallbackEnvelopeManifest']! as Map<String, Object?>,
  );

  Map<String, Object?> manifestJson() =>
      _clone(fixture['manifest']! as Map<String, Object?>);

  test('1. production 공개키가 주입된 빌드는 v1 봉투를 거부한다', () {
    final legacy = legacyJson();

    // 거부 사유가 "봉투 버전" 하나로 좁혀진다는 근거: 팩 단위 검증은 전부 통과할 수
    // 있는 문서다. 팩 서명·대표 경로 회귀 서명 모두 주입 공개키로 검증된다.
    for (final pack
        in (legacy['packs']! as List<Object?>).cast<Map<String, Object?>>()) {
      final signature = pack['signature']! as Map<String, Object?>;
      expect(signature['algorithm'], 'rsa-sha256-pack-manifest-v1');
      expect(
        publicKey.verify(
          _packSignaturePayload(pack),
          signature['value']! as String,
        ),
        isTrue,
        reason: '${pack['id']} 팩 서명은 v1 봉투 안에서도 유효하다',
      );
    }

    expect(
      () => DataPackManifest.fromJson(
        legacy,
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
  });

  test('2. 공개키가 없는 개발·테스트 빌드에서는 v1 봉투 파싱이 그대로 유지된다', () {
    // production 팩은 공개키 없이는 팩 서명 단계에서 거부되므로, 개발 빌드가 실제로
    // 만나는 문서는 fixture 팩을 담은 v1 봉투다.
    final manifest = DataPackManifest.fromJson(legacyFallbackJson());

    expect(manifest.manifestVersion, 1);
    expect(manifest.hasReplayProtection, isFalse);
    // v1 봉투는 신선도 메타데이터를 전부 잃는다 — 만료·채널·순번 판정이 성립하지 않는다.
    expect(manifest.channel, isNull);
    expect(manifest.releaseSequence, isNull);
    expect(manifest.publishedAt, isNull);
    expect(manifest.expiresAt, isNull);
    expect(manifest.signature, isNull);
    expect(manifest.manifestHash, isNull);
    expect(manifest.isExpiredAt(DateTime.utc(2030)), isFalse);
  });

  test('3. production v2 매니페스트는 공개키 주입 상태에서 그대로 수락된다', () {
    final manifest = DataPackManifest.fromJson(
      manifestJson(),
      productionSigningPublicKey: publicKey,
    );

    expect(manifest.manifestVersion, 2);
    expect(manifest.channel, 'production');
    expect(manifest.releaseSequence, 42);
    expect(manifest.hasReplayProtection, isTrue);
  });

  test('4. 봉투 signature 객체의 미서명 필드는 거부한다', () {
    // 서명 대상 정준 문자열은 `signature` 키를 제외하므로, 그 안에 무엇을 넣어도
    // 서명은 그대로 유효하다. 즉 signature 객체는 봉투에서 유일하게 서명 밖에 있는
    // 자리다. 그 자리에 뜻 모를 값을 실어 나르는 것을 허용하면 "서명된 문서"라는
    // 진술이 무너지므로 fail closed로 닫는다.
    final traced = manifestJson();
    final signature = Map<String, Object?>.from(
      traced['signature']! as Map<String, Object?>,
    )..['unsignedTrace'] = 'issue-2531';
    traced['signature'] = signature;

    expect(_canonicalWithoutSignature(traced), canonicalSignedPayload);
    expect(
      publicKey.verify(canonicalSignedPayload, signature['value']! as String),
      isTrue,
    );
    expect(
      () => DataPackManifest.fromJson(
        traced,
        productionSigningPublicKey: publicKey,
      ),
      throwsFormatException,
    );
    // 공개키가 없는 자기해시 경로에서도 같은 규칙이 적용된다.
    expect(
      () => DataPackSignature.fromJson({
        'algorithm': 'sha256-manifest-v2',
        'value': 'a' * 64,
        'unsignedTrace': 'issue-2531',
      }),
      throwsFormatException,
    );
  });
}

String _packSignaturePayload(Map<String, Object?> pack) {
  return '${pack['id']}:${pack['version']}:${pack['sha256']}'
      ':${pack['sqliteSha256']}:${pack['sizeBytes']}:${pack['url']}';
}

String _canonicalWithoutSignature(Map<String, Object?> manifest) {
  return canonicalDataPackJson({
    for (final entry in manifest.entries)
      if (entry.key != 'signature') entry.key: entry.value,
  });
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
