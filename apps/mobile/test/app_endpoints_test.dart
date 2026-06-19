import 'package:easysubway_mobile/app/app_endpoints.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('앱 endpoint는 데이터팩 base URL에서 manifest URI를 만든다', () {
    const endpoints = AppEndpoints(
      dataPackBaseUrl: 'https://cdn.easysubway.example/datapacks/',
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
        reportApiBaseUrl: 'https://api.easysubway.example',
      ).dataPackManifestUri,
      isNull,
    );
    expect(
      const AppEndpoints(
        dataPackBaseUrl: 'not-a-url',
        reportApiBaseUrl: 'https://api.easysubway.example',
      ).dataPackManifestUri,
      isNull,
    );
  });
}
