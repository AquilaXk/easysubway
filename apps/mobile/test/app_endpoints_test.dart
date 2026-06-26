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
}
