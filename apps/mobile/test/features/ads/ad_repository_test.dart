import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/ads/ad_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubApiClient extends ApiClient {
  _StubApiClient(this.response, {this.error, this.postError})
    : super(baseUri: Uri.parse('https://api.easysubway.example'));

  final ApiResponse response;
  final Object? error;
  final Object? postError;
  final paths = <String>[];
  final postPaths = <String>[];
  final postBodies = <Map<String, Object?>>[];

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

  @override
  Future<ApiResponse> postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) async {
    postPaths.add(path);
    postBodies.add(Map<String, Object?>.of(body));
    if (postError != null) {
      throw postError!;
    }
    return const ApiResponse(statusCode: 204, jsonBody: null);
  }
}

Map<String, Object?> _creativeData({
  String placement = 'route-result-bottom',
  String creativeId = 'creative-1',
  String imageUrl = 'https://cdn.easysubway.app/ad.png',
  String landingUrl = 'https://advertiser.example/campaign',
  String advertiserName = '이지상점',
  String altText = '이지상점 여름 할인',
  Object? endsAt = '2026-07-12T12:34:56Z',
}) => {
  'placement': placement,
  'creativeId': creativeId,
  'imageUrl': imageUrl,
  'landingUrl': landingUrl,
  'advertiserName': advertiserName,
  'altText': altText,
  'endsAt': endsAt,
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

  test('lazy repository는 유효 base URI와 ApiClient를 한 번만 해소한다', () async {
    var providerReads = 0;
    var requests = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      requests++;
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    final repository = AdRepository.lazy(() {
      providerReads++;
      return Uri.parse('http://${server.address.host}:${server.port}');
    });

    expect(providerReads, 0);

    await repository.fetchActive(AdPlacement.routeResultBottom);
    await repository.fetchActive(AdPlacement.stationDetailBottom);

    expect(providerReads, 1);
    expect(requests, 2);
  });

  test('지원 placement는 정확히 두 개다', () {
    expect(AdPlacement.values.map((placement) => placement.id), [
      'route-result-bottom',
      'station-detail-bottom',
    ]);
  });

  test('GET active 요청의 method, path, query가 정확하고 식별 header가 없다', () async {
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
    final headerNames = <String>{};
    for (final request in requests) {
      request.headers.forEach((name, values) => headerNames.add(name));
    }
    expect(
      headerNames.intersection({
        HttpHeaders.authorizationHeader,
        HttpHeaders.cookieHeader,
        'device-id',
        'x-device-id',
        'session-id',
        'x-session-id',
        'user-id',
        'x-user-id',
        'ad-id',
        'x-ad-id',
        'advertising-id',
        'x-advertising-id',
      }),
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
    expect(creative?.endsAt, DateTime.utc(2026, 7, 12, 12, 34, 56));
    expect(creative?.endsAt?.isUtc, isTrue);
  });

  test('endsAt null은 허용하고 malformed 또는 local 시각은 소재 전체를 숨긴다', () async {
    final noExpiry = await AdRepository(
      _StubApiClient(_response(200, data: _creativeData(endsAt: null))),
    ).fetchActive(AdPlacement.routeResultBottom);
    expect(noExpiry, isNotNull);
    expect(noExpiry?.endsAt, isNull);

    for (final invalid in <Object?>[
      'not-a-date',
      '2026-07-12T12:34:56',
      1,
      true,
    ]) {
      final creative = await AdRepository(
        _StubApiClient(_response(200, data: _creativeData(endsAt: invalid))),
      ).fetchActive(AdPlacement.routeResultBottom);
      expect(creative, isNull, reason: 'endsAt=$invalid');
    }
  });

  test('endsAt key 누락은 null과 구분해 소재 전체를 숨긴다', () async {
    final data = _creativeData()..remove('endsAt');

    final creative = await AdRepository(
      _StubApiClient(_response(200, data: data)),
    ).fetchActive(AdPlacement.routeResultBottom);

    expect(creative, isNull);
  });

  test('endsAt은 uppercase Z RFC3339와 유효한 날짜 및 시간만 허용한다', () async {
    for (final valid in [
      '2026-07-12T12:34:56Z',
      '2026-07-12T12:34:56.1Z',
      '2026-07-12T12:34:56.123456Z',
    ]) {
      final creative = await AdRepository(
        _StubApiClient(_response(200, data: _creativeData(endsAt: valid))),
      ).fetchActive(AdPlacement.routeResultBottom);
      expect(creative, isNotNull, reason: 'endsAt=$valid');
      expect(creative?.endsAt?.isUtc, isTrue, reason: 'endsAt=$valid');
    }

    for (final invalid in [
      '2026-07-12T12:34:56+09:00',
      '2026-07-12T12:34:56z',
      '2026-02-30T12:34:56Z',
      '2026-07-12T24:00:00Z',
      '2026-07-12T12:60:00Z',
      '2026-07-12T12:34:60Z',
    ]) {
      final creative = await AdRepository(
        _StubApiClient(_response(200, data: _creativeData(endsAt: invalid))),
      ).fetchActive(AdPlacement.routeResultBottom);
      expect(creative, isNull, reason: 'endsAt=$invalid');
    }
  });

  test('event는 정확한 세 필드만 POST하고 204를 완료로 취급한다', () async {
    final client = _StubApiClient(_response(204));
    final repository = AdRepository(client);

    await repository.recordEvent(
      AdPlacement.routeResultBottom,
      'creative-1',
      AdEventType.impression,
    );

    expect(client.postPaths, ['/api/ads/events']);
    expect(client.postBodies, [
      {
        'placement': 'route-result-bottom',
        'creativeId': 'creative-1',
        'eventType': 'IMPRESSION',
      },
    ]);
  });

  test('event network와 timeout 실패는 저장이나 재시도 없이 무시한다', () async {
    for (final error in [
      const ApiException('network'),
      const ApiException('timeout'),
    ]) {
      final client = _StubApiClient(_response(204), postError: error);
      await expectLater(
        AdRepository(client).recordEvent(
          AdPlacement.routeResultBottom,
          'creative-1',
          AdEventType.click,
        ),
        completes,
      );
      expect(client.postBodies, hasLength(1));
    }
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
