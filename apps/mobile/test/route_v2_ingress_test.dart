import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/route_v2_ingress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SUBWAY는 local만 호출하고 network를 0회 유지한다', () async {
    final local = _RecordingRepository('local');
    final online = _RecordingRepository('online');
    final dispatcher = TransportScopedRouteSearchRepository(
      localRepository: local,
      itxOnlineRepository: online,
    );

    final result = await dispatcher.searchRoute(
      _request(RouteTransportScope.subway),
    );

    expect(result.routeSearchId, 'local');
    expect(local.searchCount, 1);
    expect(online.searchCount, 0);
  });

  test('SUBWAY_AND_ITX_CHEONGCHUN은 authenticated online만 호출한다', () async {
    final local = _RecordingRepository('local');
    final online = _RecordingRepository('online');
    final dispatcher = TransportScopedRouteSearchRepository(
      localRepository: local,
      itxOnlineRepository: online,
    );

    final result = await dispatcher.searchRoute(
      _request(RouteTransportScope.subwayAndItxCheongchun),
    );

    expect(result.routeSearchId, 'online');
    expect(local.searchCount, 0);
    expect(online.searchCount, 1);
  });

  test('ITX_TIMETABLE_UNAVAILABLE을 SUBWAY로 자동 강등하지 않는다', () async {
    final local = _RecordingRepository('local');
    final online = _RecordingRepository(
      'online',
      error: const RouteSearchOnlineException.unavailable(
        failureReason: 'ITX_TIMETABLE_UNAVAILABLE',
      ),
    );
    final dispatcher = TransportScopedRouteSearchRepository(
      localRepository: local,
      itxOnlineRepository: online,
    );

    await expectLater(
      dispatcher.searchRoute(
        _request(RouteTransportScope.subwayAndItxCheongchun),
      ),
      throwsA(isA<RouteSearchOnlineException>()),
    );
    expect(local.searchCount, 0);
  });

  test(
    'session provider는 canonical requestHash와 nonce로 attestation 후 token을 발급받는다',
    () async {
      late Map<String, Object?> requestBody;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        requestBody =
            jsonDecode(await utf8.decodeStream(request))
                as Map<String, Object?>;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'token': 'A' * 43,
              'scope': 'route:v2:itx',
              'issuedAt': '2026-07-16T09:00:00Z',
              'expiresAt': '2026-07-16T09:10:00Z',
            }),
          );
        await request.response.close();
      });
      final attestor = _RecordingAttestor();
      final provider = PlayIntegrityRouteV2SessionProvider(
        apiClient: ApiClient(
          baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
        ),
        attestor: attestor,
        nonceFactory: () => 'AAAAAAAAAAAAAAAAAAAAAA',
      );

      final token = await provider.issueToken();

      expect(token, 'A' * 43);
      expect(
        attestor.requestHash,
        'SVOaIn_B5rcm1TVIPIEozQ_iGimOCakTxKuH3iXlD18',
      );
      expect(requestBody, {
        'integrityToken': 'integrity-token',
        'clientNonce': 'AAAAAAAAAAAAAAAAAAAAAA',
      });
    },
  );

  test('session 429는 exact code와 UI 문구를 보존하고 재시도하지 않는다', () async {
    var requestCount = 0;
    final server = await _errorServer(
      statusCode: HttpStatus.tooManyRequests,
      code: 'ROUTE_RATE_LIMITED',
      onRequest: () => requestCount++,
    );
    addTearDown(server.close);
    final provider = PlayIntegrityRouteV2SessionProvider(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      ),
      attestor: _RecordingAttestor(),
      nonceFactory: () => 'AAAAAAAAAAAAAAAAAAAAAA',
    );

    await expectLater(
      provider.issueToken(),
      throwsA(
        isA<RouteSearchOnlineException>()
            .having((error) => error.statusCode, 'statusCode', 429)
            .having(
              (error) => error.failureReason,
              'failureReason',
              'ROUTE_RATE_LIMITED',
            )
            .having((error) => error.message, 'message', '잠시 후 다시 시도'),
      ),
    );
    expect(requestCount, 1);
  });

  test('session attestation 403은 exact code와 UI 문구를 보존한다', () async {
    final server = await _errorServer(
      statusCode: HttpStatus.forbidden,
      code: 'ROUTE_SESSION_ATTESTATION_REJECTED',
    );
    addTearDown(server.close);
    final provider = PlayIntegrityRouteV2SessionProvider(
      apiClient: ApiClient(
        baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      ),
      attestor: _RecordingAttestor(),
      nonceFactory: () => 'AAAAAAAAAAAAAAAAAAAAAA',
    );

    await expectLater(
      provider.issueToken(),
      throwsA(
        isA<RouteSearchOnlineException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having(
              (error) => error.failureReason,
              'failureReason',
              'ROUTE_SESSION_ATTESTATION_REJECTED',
            )
            .having(
              (error) => error.message,
              'message',
              'ITX 시간표를 불러올 수 없어요',
            ),
      ),
    );
  });

  test('503 timetable 오류는 exact code로 보존하고 자동 재시도하지 않는다', () async {
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      requestCount++;
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer ${'T' * 43}',
      );
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': false,
            'code': 'ITX_TIMETABLE_UNAVAILABLE',
            'message': 'ITX 시간표를 불러올 수 없어요',
          }),
        );
      await request.response.close();
    });
    final repository = RouteSearchV2ApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      bearerTokenProvider: () async => 'T' * 43,
    );

    await expectLater(
      repository.searchRoute(
        _request(RouteTransportScope.subwayAndItxCheongchun),
      ),
      throwsA(
        isA<RouteSearchOnlineException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.failureReason,
              'failureReason',
              'ITX_TIMETABLE_UNAVAILABLE',
            )
            .having((error) => error.message, 'message', 'ITX 시간표를 불러올 수 없어요'),
      ),
    );
    expect(requestCount, 1);
  });
}

Future<HttpServer> _errorServer({
  required int statusCode,
  required String code,
  void Function()? onRequest,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    onRequest?.call();
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'success': false, 'code': code, 'message': 'error'}));
    await request.response.close();
  });
  return server;
}

RouteSearchRequest _request(RouteTransportScope scope) => RouteSearchRequest(
  originStationId: 'origin',
  destinationStationId: 'destination',
  mobilityType: 'SENIOR',
  transportScope: scope,
);

class _RecordingAttestor implements PlayIntegrityAttestor {
  String? requestHash;

  @override
  Future<String> requestToken(String requestHash) async {
    this.requestHash = requestHash;
    return 'integrity-token';
  }
}

class _RecordingRepository implements RouteSearchRepository {
  _RecordingRepository(this.id, {this.error});

  final String id;
  final Object? error;
  int searchCount = 0;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    searchCount++;
    if (error != null) throw error!;
    return RouteSearchResult(
      routeSearchId: id,
      originStationId: 'origin',
      originStationName: '출발',
      destinationStationId: 'destination',
      destinationStationName: '도착',
      mobilityType: 'SENIOR',
      status: 'FOUND',
      lineId: 'line',
      lineName: '노선',
      score: 1,
      burdenCost: 1,
      estimatedDurationSeconds: 60,
      walkingDistanceMeters: 0,
      transferCount: 0,
      steps: const [],
      warnings: const [],
      blockedReasons: const [],
      recommendationReasons: const [],
      evidenceSummary: const [],
      createdAt: '2026-07-16T09:00:00Z',
      etaSource: 'PLANNED',
      commercialEtaEligible: false,
    );
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) {
    throw UnimplementedError();
  }
}
