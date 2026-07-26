import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/app/app_bootstrap.dart';
import 'package:easysubway_mobile/app/app_endpoints.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
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
    // 관측 근거는 나중에 재검증할 수 있는 식별자를 함께 남긴다. 순번만 손으로 적으면
    // 하한을 올리는 변경이 관측값을 같이 올려도 아무도 대조할 수 없다.
    expect(
      evidence['observedManifestSha256'],
      matches(RegExp(r'^[a-f0-9]{64}$')),
    );
    expect(
      evidence['observedAt'],
      matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')),
    );
    expect(evidence['observedPublishRunId'], isA<int>());
    expect(
      evidence['observedPublishRunNumber'],
      evidence['observedReleaseSequence'],
    );
  });

  test('하한은 공개키가 주입되고 채널이 production인 빌드에만 적용된다', () {
    // 정책 JSON이 선언한 적용 범위(channel: production)와 코드 판정을 일치시킨다.
    expect(_endpoints().dataPackMinimumReleaseSequence, isNull);
    expect(
      _endpoints(keyInjected: true).dataPackMinimumReleaseSequence,
      productionDataPackMinimumReleaseSequence,
    );
    expect(
      _endpoints(
        keyInjected: true,
        channel: 'staging',
      ).dataPackMinimumReleaseSequence,
      isNull,
    );
    expect(
      _endpoints(channel: 'staging').dataPackMinimumReleaseSequence,
      isNull,
    );
  });

  test('업데이트 상태 저장소 조립은 판정한 하한을 그대로 주입한다', () {
    // 하한이 실제로 적용되는 지점은 이 조립 한 곳뿐이다. 배선이 빠지면 나머지 계약이
    // 전부 초록인 채로 신규 설치 사각이 되살아나므로, 조립 결과를 직접 확인한다.
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);

    expect(
      createDataPackUpdateStateRepository(
        userDatabase: userDatabase,
        endpoints: _endpoints(keyInjected: true),
      ).minimumReleaseSequence,
      productionDataPackMinimumReleaseSequence,
    );
    expect(
      createDataPackUpdateStateRepository(
        userDatabase: userDatabase,
        endpoints: _endpoints(),
      ).minimumReleaseSequence,
      isNull,
    );
    expect(
      createDataPackUpdateStateRepository(
        userDatabase: userDatabase,
        endpoints: _endpoints(keyInjected: true, channel: 'staging'),
      ).minimumReleaseSequence,
      isNull,
    );
  });
}

AppEndpoints _endpoints({
  bool keyInjected = false,
  String channel = 'production',
}) {
  return AppEndpoints(
    dataPackBaseUrl: 'https://datapacks.example.test',
    dataPackSigningPublicKeyModulus: keyInjected ? 'AQ' : '',
    dataPackSigningPublicKeyExponent: keyInjected ? 'AQAB' : '',
    dataPackChannel: channel,
    reportApiBaseUrl: 'https://api.example.test',
  );
}
