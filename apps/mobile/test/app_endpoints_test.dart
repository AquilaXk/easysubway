import 'dart:convert';

import 'package:easysubway_mobile/app/app_endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('앱 endpoint는 데이터팩 base URL에서 manifest URI를 만든다', () {
    const endpoints = AppEndpoints(
      dataPackBaseUrl: 'https://cdn.easysubway.example/datapacks/',
      dataPackSigningPublicKeyModulus: ' public-modulus ',
      dataPackSigningPublicKeyExponent: ' AQAB ',
      dataPackSigningKeyId: ' production-v2 ',
      dataPackChannel: ' production ',
      reportApiBaseUrl: 'https://api.easysubway.example',
    );

    expect(
      endpoints.dataPackManifestUri,
      Uri.parse(
        'https://cdn.easysubway.example/datapacks/catalog/current.json',
      ),
    );
    expect(
      endpoints.productionDataPackSigningPublicKey?.modulusBase64Url,
      'public-modulus',
    );
    expect(
      endpoints.productionDataPackSigningPublicKey?.exponentBase64Url,
      'AQAB',
    );
    expect(
      endpoints.productionDataPackSigningPublicKey?.keyId,
      'production-v2',
    );
    expect(endpoints.expectedDataPackChannel, 'production');
    expect(
      endpoints.realtimeApiBaseUri,
      Uri.parse('https://api.easysubway.example/'),
    );
  });

  test('앱 endpoint는 slash가 없는 데이터팩 base URL도 directory로 처리한다', () {
    const endpoints = AppEndpoints(
      dataPackBaseUrl: 'https://cdn.easysubway.example/datapacks',
      dataPackSigningPublicKeyModulus: '',
      dataPackSigningPublicKeyExponent: '',
      reportApiBaseUrl: 'https://api.easysubway.example',
    );

    expect(
      endpoints.dataPackManifestUri,
      Uri.parse(
        'https://cdn.easysubway.example/datapacks/catalog/current.json',
      ),
    );
  });

  test('앱 endpoint는 비어 있거나 host가 없는 데이터팩 URL을 사용하지 않는다', () {
    expect(
      const AppEndpoints(
        dataPackBaseUrl: '',
        dataPackSigningPublicKeyModulus: '',
        dataPackSigningPublicKeyExponent: '',
        reportApiBaseUrl: 'https://api.easysubway.example',
      ).dataPackManifestUri,
      isNull,
    );
    expect(
      const AppEndpoints(
        dataPackBaseUrl: 'not-a-url',
        dataPackSigningPublicKeyModulus: '',
        dataPackSigningPublicKeyExponent: '',
        reportApiBaseUrl: 'https://api.easysubway.example',
      ).dataPackManifestUri,
      isNull,
    );
  });

  test('앱 endpoint는 비어 있는 데이터팩 channel을 production으로 처리한다', () {
    const endpoints = AppEndpoints(
      dataPackBaseUrl: 'https://cdn.easysubway.example/datapacks/',
      dataPackSigningPublicKeyModulus: '',
      dataPackSigningPublicKeyExponent: '',
      dataPackChannel: ' ',
      reportApiBaseUrl: 'https://api.easysubway.example',
    );

    expect(endpoints.expectedDataPackChannel, 'production');
  });

  test('앱 endpoint는 모바일 TOPIS service key 환경값을 노출하지 않는다', () {
    const endpoints = AppEndpoints(
      dataPackBaseUrl: '',
      dataPackSigningPublicKeyModulus: '',
      dataPackSigningPublicKeyExponent: '',
      reportApiBaseUrl: '',
    );

    expect(endpoints.realtimeApiBaseUri, isNull);
  });

  test('앱 endpoint는 production 빌드에 공개키가 없으면 업데이트를 시작하지 않는다', () {
    const endpoints = AppEndpoints(
      dataPackBaseUrl: 'https://cdn.easysubway.example/datapacks/',
      dataPackSigningPublicKeyModulus: '',
      dataPackSigningPublicKeyExponent: '',
      dataPackChannel: 'production',
      reportApiBaseUrl: 'https://api.easysubway.example',
    );

    expect(endpoints.dataPackManifestUri, isNotNull);
    expect(
      endpoints.dataPackSigningPublicKeyStatus,
      DataPackSigningPublicKeyStatus.missing,
    );
    expect(
      endpoints.dataPackUpdateStartDecision,
      DataPackUpdateStartDecision.missingProductionSigningKey,
    );
    expect(
      endpoints.dataPackUpdateStartDecision.blockedDiagnosticMessage,
      isNotNull,
    );
  });

  test('앱 endpoint는 공개키 미주입과 형식 오류를 구분한다', () {
    const missing = AppEndpoints(
      dataPackBaseUrl: 'https://cdn.easysubway.example/datapacks/',
      dataPackSigningPublicKeyModulus: '   ',
      dataPackSigningPublicKeyExponent: 'AQAB',
      reportApiBaseUrl: '',
    );
    const malformed = AppEndpoints(
      dataPackBaseUrl: 'https://cdn.easysubway.example/datapacks/',
      dataPackSigningPublicKeyModulus: 'not-a-2048-bit-modulus',
      dataPackSigningPublicKeyExponent: 'AQAB',
      reportApiBaseUrl: '',
    );

    expect(
      missing.dataPackSigningPublicKeyStatus,
      DataPackSigningPublicKeyStatus.missing,
    );
    expect(
      malformed.dataPackSigningPublicKeyStatus,
      DataPackSigningPublicKeyStatus.malformed,
    );
    expect(
      malformed.dataPackUpdateStartDecision,
      DataPackUpdateStartDecision.malformedProductionSigningKey,
    );
  });

  test('앱 endpoint는 공개키가 주입된 production 빌드에서 업데이트를 시작한다', () {
    final endpoints = AppEndpoints(
      dataPackBaseUrl: 'https://cdn.easysubway.example/datapacks/',
      dataPackSigningPublicKeyModulus: _rsaModulusBase64Url,
      dataPackSigningPublicKeyExponent: 'AQAB',
      reportApiBaseUrl: '',
    );

    expect(
      endpoints.dataPackSigningPublicKeyStatus,
      DataPackSigningPublicKeyStatus.present,
    );
    expect(
      endpoints.dataPackUpdateStartDecision,
      DataPackUpdateStartDecision.start,
    );
    expect(
      endpoints.dataPackUpdateStartDecision.blockedDiagnosticMessage,
      isNull,
    );
  });

  test('앱 endpoint는 비-production 채널에서는 공개키 없이도 업데이트를 시작한다', () {
    const endpoints = AppEndpoints(
      dataPackBaseUrl: 'https://cdn.easysubway.example/datapacks/',
      dataPackSigningPublicKeyModulus: '',
      dataPackSigningPublicKeyExponent: '',
      dataPackChannel: 'staging',
      reportApiBaseUrl: '',
    );

    expect(
      endpoints.dataPackUpdateStartDecision,
      DataPackUpdateStartDecision.start,
    );
    expect(endpoints.productionDataPackSigningPublicKey, isNull);
  });

  test('앱 endpoint는 데이터팩 base URL이 없으면 갱신 대상 없음으로 판정한다', () {
    const endpoints = AppEndpoints(
      dataPackBaseUrl: '',
      dataPackSigningPublicKeyModulus: '',
      dataPackSigningPublicKeyExponent: '',
      reportApiBaseUrl: '',
    );

    expect(
      endpoints.dataPackUpdateStartDecision,
      DataPackUpdateStartDecision.noManifestEndpoint,
    );
    expect(
      endpoints.dataPackUpdateStartDecision.blockedDiagnosticMessage,
      isNull,
    );
  });
}

/// RC 게이트(`tools/ci/validate-store-privacy-env.mjs`)가 요구하는 최소 길이(2048비트)를
/// 만족하는 modulus. 값 자체는 서명 검증에 쓰지 않으므로 형식만 맞춘다.
final String _rsaModulusBase64Url = base64Url.encode(
  List<int>.filled(256, 0xab),
);
