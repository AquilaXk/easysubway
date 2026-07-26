import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/app/app_endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

/// 이슈 #2531(DP-05) — 매니페스트 수락 하한의 단일 원본 고정.
///
/// 하한 값을 코드와 정책 JSON 두 곳에서 손으로 맞추는 구조면 릴리즈마다 어긋난다.
/// 여기서 두 값을 묶어 두면 한쪽만 바꾸는 순간 빨간불이 난다.
void main() {
  final policy =
      jsonDecode(
            File(
              'release/datapack-manifest-acceptance-policy.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  test('Dart 수락 하한 상수가 release 정책 JSON과 같다', () {
    expect(policy['schemaVersion'], 1);
    expect(policy['artifactKind'], 'datapack-manifest-acceptance-policy');
    expect(policy['channel'], 'production');
    expect(policy['rejectLegacyEnvelopeWhenSigningKeyInjected'], isTrue);
    expect(
      productionDataPackMinimumReleaseSequence,
      policy['minimumReleaseSequence'],
    );
  });

  test('하한은 관측한 published 순번을 넘지 않는다', () {
    // 하한이 실제 배포 순번보다 높으면 그 하한을 심고 나간 빌드가 현재 매니페스트를
    // 거부한다. 하한을 올리려면 새 관측값을 함께 기록해야 한다는 규칙을 고정한다.
    final evidence =
        policy['minimumReleaseSequenceEvidence']! as Map<String, Object?>;
    expect(
      policy['minimumReleaseSequence']! as int,
      lessThanOrEqualTo(evidence['observedReleaseSequence']! as int),
    );
  });

  test('하한은 production 서명 공개키가 주입된 빌드에만 적용된다', () {
    const production = AppEndpoints(
      dataPackBaseUrl: 'https://datapacks.example.test',
      dataPackSigningPublicKeyModulus: 'AQ',
      dataPackSigningPublicKeyExponent: 'AQAB',
      reportApiBaseUrl: 'https://api.example.test',
    );
    const development = AppEndpoints(
      dataPackBaseUrl: 'https://datapacks.example.test',
      dataPackSigningPublicKeyModulus: '',
      dataPackSigningPublicKeyExponent: '',
      reportApiBaseUrl: 'https://api.example.test',
    );

    expect(
      production.dataPackMinimumReleaseSequence,
      productionDataPackMinimumReleaseSequence,
    );
    expect(development.dataPackMinimumReleaseSequence, isNull);
  });
}
