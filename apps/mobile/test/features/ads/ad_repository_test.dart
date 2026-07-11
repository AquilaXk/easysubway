import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/ads/ad_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient(this.response, {this.error})
    : super(baseUri: Uri.parse('https://api.easysubway.example'));

  final ApiResponse response;
  final Object? error;
  final paths = <String>[];

  @override
  Future<ApiResponse> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    paths.add(path);
    if (error != null) {
      throw error!;
    }
    return response;
  }
}

Map<String, Object?> _creativeData({
  String placement = 'route-result-bottom',
  String creativeId = 'creative-1',
  String imageUrl = 'https://cdn.easysubway.app/ad.png',
  String landingUrl = 'https://advertiser.example/campaign',
  String advertiserName = '이지상점',
  String altText = '이지상점 여름 할인',
}) => {
  'placement': placement,
  'creativeId': creativeId,
  'imageUrl': imageUrl,
  'landingUrl': landingUrl,
  'advertiserName': advertiserName,
  'altText': altText,
};

ApiResponse _response(int statusCode, {Object? data, bool success = true}) =>
    ApiResponse(
      statusCode: statusCode,
      jsonBody: statusCode == HttpStatus.noContent
          ? null
          : {'success': success, 'data': data},
    );

void main() {
  test('lazy repository는 fetch 전 base URI를 읽지 않고 없으면 null이다', () async {
    var reads = 0;
    final repository = AdRepository.lazy(() {
      reads++;
      return null;
    });

    expect(reads, 0);

    expect(await repository.fetchActive(AdPlacement.routeResultBottom), isNull);
    expect(reads, 1);
  });

  test('지원 placement는 정확히 두 개다', () {
    expect(AdPlacement.values.map((placement) => placement.id), [
      'route-result-bottom',
      'station-detail-bottom',
    ]);
  });

  test('GET active 요청의 method, path, query가 정확하고 event 요청은 없다', () async {
    final requests = <HttpRequest>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests.add(request);
      if (request.uri.queryParameters['placement'] == 'station-detail-bottom') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': _creativeData(),
            'message': null,
          }),
        );
      await request.response.close();
    });
    final repository = AdRepository(
      ApiClient(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      ),
    );

    final routeCreative = await repository.fetchActive(
      AdPlacement.routeResultBottom,
    );
    final stationCreative = await repository.fetchActive(
      AdPlacement.stationDetailBottom,
    );

    expect(routeCreative, isNotNull);
    expect(stationCreative, isNull);
    expect(requests, hasLength(2));
    expect(requests.map((request) => request.method), everyElement('GET'));
    expect(
      requests.map((request) => request.uri.path),
      everyElement('/api/ads/active'),
    );
    expect(requests.map((request) => request.uri.queryParameters), [
      {'placement': 'route-result-bottom'},
      {'placement': 'station-detail-bottom'},
    ]);
    expect(
      requests.where((request) => request.uri.path == '/api/ads/events'),
      isEmpty,
    );
  });

  test('정상 200의 필드를 immutable creative로 매핑한다', () async {
    final client = _StubApiClient(_response(200, data: _creativeData()));

    final creative = await AdRepository(
      client,
    ).fetchActive(AdPlacement.routeResultBottom);

    expect(client.paths, ['/api/ads/active?placement=route-result-bottom']);
    expect(creative?.placement, AdPlacement.routeResultBottom);
    expect(creative?.creativeId, 'creative-1');
    expect(creative?.imageUrl, Uri.parse('https://cdn.easysubway.app/ad.png'));
    expect(
      creative?.landingUrl,
      Uri.parse('https://advertiser.example/campaign'),
    );
    expect(creative?.advertiserName, '이지상점');
    expect(creative?.altText, '이지상점 여름 할인');
  });

  test('204와 non-200은 null이다', () async {
    for (final statusCode in [204, 400, 404, 500]) {
      final result = await AdRepository(
        _StubApiClient(_response(statusCode)),
      ).fetchActive(AdPlacement.routeResultBottom);

      expect(result, isNull, reason: '$statusCode');
    }
  });

  test('network, timeout, malformed JSON은 null이다', () async {
    for (final error in [
      const ApiException('network'),
      const ApiException('timeout'),
      const ApiException('malformed JSON'),
    ]) {
      final result = await AdRepository(
        _StubApiClient(_response(200), error: error),
      ).fetchActive(AdPlacement.routeResultBottom);

      expect(result, isNull, reason: error.message);
    }
  });

  test('wrapper나 data가 malformed면 null이다', () async {
    final responses = [
      const ApiResponse(statusCode: 200, jsonBody: null),
      const ApiResponse(statusCode: 200, jsonBody: []),
      _response(200, data: _creativeData(), success: false),
      _response(200, data: null),
      _response(200, data: []),
    ];

    for (final response in responses) {
      final result = await AdRepository(
        _StubApiClient(response),
      ).fetchActive(AdPlacement.routeResultBottom);

      expect(result, isNull);
    }
  });

  test('필수 문자열이 없거나 blank면 null이다', () async {
    for (final field in [
      'placement',
      'creativeId',
      'imageUrl',
      'landingUrl',
      'advertiserName',
      'altText',
    ]) {
      for (final invalidValue in <Object?>[null, '', '   ', 1]) {
        final data = _creativeData()..[field] = invalidValue;
        final result = await AdRepository(
          _StubApiClient(_response(200, data: data)),
        ).fetchActive(AdPlacement.routeResultBottom);

        expect(result, isNull, reason: '$field=$invalidValue');
      }
    }
  });

  test('요청과 응답 placement가 다르면 null이다', () async {
    final result = await AdRepository(
      _StubApiClient(
        _response(200, data: _creativeData(placement: 'station-detail-bottom')),
      ),
    ).fetchActive(AdPlacement.routeResultBottom);

    expect(result, isNull);
  });

  test('imageUrl과 landingUrl은 host가 있는 HTTPS만 허용한다', () async {
    for (final url in [
      'http://example.com/ad',
      'ftp://example.com/ad',
      'https:///ad',
      'not a url',
    ]) {
      for (final field in ['imageUrl', 'landingUrl']) {
        final data = _creativeData()..[field] = url;
        final result = await AdRepository(
          _StubApiClient(_response(200, data: data)),
        ).fetchActive(AdPlacement.routeResultBottom);

        expect(result, isNull, reason: '$field=$url');
      }
    }
  });
}
