import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('경로 API 저장소는 백엔드 경로 검색을 요청하고 결과를 파싱한다', () async {
    late Uri requestedUri;
    late String requestedBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      expect(request.method, 'POST');
      expect(
        request.headers.value(HttpHeaders.contentTypeHeader),
        contains(ContentType.json.mimeType),
      );
      requestedUri = request.uri;
      requestedBody = await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'routeSearchId': 'route-1',
              'originStationId': 'station-sangnoksu',
              'originStationName': '상록수',
              'destinationStationId': 'station-sadang',
              'destinationStationName': '사당',
              'mobilityType': 'WHEELCHAIR',
              'status': 'FOUND',
              'lineId': 'seoul-4',
              'lineName': '수도권 4호선',
              'score': 92,
              'steps': [
                {
                  'sequence': 1,
                  'title': '상록수역에서 4호선 승강장으로 이동',
                  'description': '엘리베이터를 이용해 승강장으로 이동합니다.',
                  'lineId': 'seoul-4',
                  'lineName': '수도권 4호선',
                  'fromStationId': 'station-sangnoksu',
                  'toStationId': 'station-sadang',
                  'estimatedMinutes': 4,
                  'distanceMeters': 180,
                  'includesStairs': false,
                  'requiresAccessibilityCheck': true,
                },
                {
                  'sequence': 2,
                  'title': '사당역에서 출구 접근성 정보를 확인',
                  'description': '2번 출구의 엘리베이터를 먼저 확인하세요.',
                  'lineId': 'seoul-4',
                  'lineName': '수도권 4호선',
                  'fromStationId': 'station-sadang',
                  'toStationId': 'station-sadang',
                  'estimatedMinutes': 3,
                  'distanceMeters': 120,
                  'includesStairs': false,
                  'requiresAccessibilityCheck': true,
                },
              ],
              'warnings': [
                {
                  'code': 'LOW_DATA_CONFIDENCE',
                  'message': '일부 시설 정보는 확인이 필요합니다.',
                },
                {
                  'code': 'STALE_ACCESSIBILITY_DATA',
                  'message':
                      '접근성 시설 정보가 최근 30일 이내 확인되지 않았습니다. 이동 전 역 상세 정보를 확인하세요.',
                },
              ],
              'blockedReasons': [],
              'createdAt': '2026-06-13T04:20:00',
            },
          }),
        )
        ..close();
    });

    final repository = RouteSearchApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(requestedUri.path, '/api/v1/routes/search');
    expect(jsonDecode(requestedBody), {
      'originStationId': 'station-sangnoksu',
      'destinationStationId': 'station-sadang',
      'mobilityType': 'WHEELCHAIR',
    });
    expect(result.routeSearchId, 'route-1');
    expect(result.summaryTitle, '상록수에서 사당까지');
    expect(result.lineName, '수도권 4호선');
    expect(result.statusLabel, '경로를 찾았습니다');
    expect(result.scoreLabel, '이동 점수 92점');
    expect(result.steps.first.title, '상록수역에서 4호선 승강장으로 이동');
    expect(result.steps.first.estimatedMinutes, 4);
    expect(result.steps.first.distanceMeters, 180);
    expect(result.steps.first.includesStairs, isFalse);
    expect(result.steps.first.requiresAccessibilityCheck, isTrue);
    expect(result.steps.first.burdenLabel, '약 4분 · 180m · 접근성 확인');
    expect(result.arrivalGuidanceStep?.description, '2번 출구의 엘리베이터를 먼저 확인하세요.');
    expect(
      result.warnings.map((warning) => warning.code),
      containsAll(['LOW_DATA_CONFIDENCE', 'STALE_ACCESSIBILITY_DATA']),
    );
    expect(
      result.warnings.map((warning) => warning.message),
      contains('접근성 시설 정보가 최근 30일 이내 확인되지 않았습니다. 이동 전 역 상세 정보를 확인하세요.'),
    );
  });

  test('경로 검색 컨트롤러는 빈 입력과 실패 상태를 쉬운 문구로 표시한다', () async {
    final repository = FakeRouteSearchRepository();
    final controller = RouteSearchController(repository: repository);

    await controller.search(
      const RouteSearchRequest(
        originStationId: '  ',
        destinationStationId: 'station-sadang',
        mobilityType: 'SENIOR',
      ),
    );

    expect(repository.requests, isEmpty);
    expect(controller.state.status, RouteSearchViewStatus.failure);
    expect(controller.state.message, '출발역과 도착역을 입력해 주세요.');

    repository.error = const RouteSearchException('경로 정보를 불러오지 못했습니다.');

    await controller.search(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'SENIOR',
      ),
    );

    expect(repository.requests, hasLength(1));
    expect(repository.requests.single.originStationId, 'station-sangnoksu');
    expect(repository.requests.single.destinationStationId, 'station-sadang');
    expect(repository.requests.single.mobilityType, 'SENIOR');
    expect(controller.state.status, RouteSearchViewStatus.failure);
    expect(controller.state.message, '경로 정보를 불러오지 못했습니다.');
  });

  test('경로 검색 컨트롤러는 화면 종료 후 비동기 결과를 알리지 않는다', () async {
    final repository = PendingRouteSearchRepository();
    final controller = RouteSearchController(repository: repository);
    var notificationCount = 0;
    controller.addListener(() {
      notificationCount += 1;
    });

    final searchFuture = controller.search(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'SENIOR',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, RouteSearchViewStatus.loading);
    expect(notificationCount, 1);

    controller.dispose();
    repository.complete(_sampleRouteSearchResult());
    await searchFuture;

    expect(notificationCount, 1);
  });

  test('경로 검색 결과는 확인 필요 상태를 이동 가능으로 안내하지 않는다', () {
    final result = _sampleRouteSearchResult(status: 'REVIEW_REQUIRED');

    expect(result.statusLabel, '확인이 필요합니다');
    expect(result.guidanceLabel, '확인이 필요합니다');
    expect(result.guidanceIcon, Icons.warning_amber);
    expect(result.semanticLabel, isNot(contains('이동할 수 있는 경로')));
  });

  test('경로 단계 이동 부담은 긴 거리를 킬로미터로 표시한다', () {
    const step = RouteSearchStep(
      sequence: 2,
      title: '수도권 4호선으로 사당역까지 이동',
      description: '15개 역을 이동합니다. 환승은 없습니다.',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      fromStationId: 'station-sangnoksu',
      toStationId: 'station-sadang',
      estimatedMinutes: 30,
      distanceMeters: 13500,
      includesStairs: false,
      requiresAccessibilityCheck: false,
    );

    expect(step.burdenLabel, '약 30분 · 13.5km');
  });

  test('즐겨찾기 경로 API 저장소는 인증 헤더로 저장과 목록과 삭제를 요청한다', () async {
    final requestedMethods = <String>[];
    final requestedPaths = <String>[];
    final requestedBodies = <String>[];
    final requestedAuthorizations = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedMethods.add(request.method);
      requestedPaths.add(request.uri.path);
      requestedAuthorizations.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      requestedBodies.add(await utf8.decoder.bind(request).join());

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json;

      if (request.method == 'GET') {
        request.response.write(
          jsonEncode({
            'success': true,
            'data': [_favoriteRouteJson()],
          }),
        );
      } else if (request.method == 'POST') {
        request.response.write(
          jsonEncode({'success': true, 'data': _favoriteRouteJson()}),
        );
      } else {
        request.response.write(jsonEncode({'success': true, 'data': null}));
      }
      await request.response.close();
    });

    final repository = FavoriteRouteApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'password',
      ),
    );

    final favorites = await repository.listFavoriteRoutes();
    final saved = await repository.saveFavoriteRoute('route-1');
    await repository.removeFavoriteRoute('route-1');

    expect(requestedMethods, ['GET', 'POST', 'DELETE']);
    expect(requestedPaths, [
      '/api/v1/me/favorites/routes',
      '/api/v1/me/favorites/routes',
      '/api/v1/me/favorites/routes/route-1',
    ]);
    expect(jsonDecode(requestedBodies[1]), {'routeSearchId': 'route-1'});
    expect(requestedAuthorizations, everyElement(startsWith('Basic ')));
    expect(favorites.single.summaryTitle, '상록수에서 사당까지');
    expect(saved.favoriteRouteId, 'route-1');
    expect(saved.mobilityLabel, '고령자');
    expect(saved.scoreLabel, '이동 점수 92점');
  });

  test('경로 피드백 API 저장소는 익명 사용자 식별자와 평가를 전송한다', () async {
    late Uri requestedUri;
    late String requestedBody;
    late String? requestedAuthorization;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedUri = request.uri;
      requestedAuthorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      requestedBody = await utf8.decoder.bind(request).join();

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'feedbackId': 'route-feedback-1',
              'routeSearchId': 'route-1',
              'userId': 'anonymous-user-1',
              'rating': 'HELPFUL',
              'comment': '추천이 도움이 됐어요',
              'createdAt': '2026-06-15T12:00:00',
            },
          }),
        )
        ..close();
    });

    final repository = RouteFeedbackApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'password',
      ),
    );

    await repository.submitRouteFeedback(
      const RouteFeedbackRequest(
        routeSearchId: 'route-1',
        rating: RouteFeedbackRating.helpful,
        comment: '추천이 도움이 됐어요',
      ),
    );

    expect(requestedUri.path, '/api/v1/routes/route-1/feedback');
    expect(requestedAuthorization, startsWith('Basic '));
    expect(jsonDecode(requestedBody), {
      'userId': 'anonymous-user-1',
      'rating': 'HELPFUL',
      'comment': '추천이 도움이 됐어요',
    });
  });
}

class FakeRouteSearchRepository implements RouteSearchRepository {
  final requests = <RouteSearchRequest>[];
  Object? error;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    requests.add(request);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return _sampleRouteSearchResult();
  }
}

class PendingRouteSearchRepository implements RouteSearchRepository {
  final _completer = Completer<RouteSearchResult>();

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) =>
      _completer.future;

  void complete(RouteSearchResult result) {
    _completer.complete(result);
  }
}

RouteSearchResult _sampleRouteSearchResult({String status = 'FOUND'}) {
  return RouteSearchResult(
    routeSearchId: 'route-1',
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-sadang',
    destinationStationName: '사당',
    mobilityType: 'SENIOR',
    status: status,
    lineId: 'seoul-4',
    lineName: '수도권 4호선',
    score: 92,
    steps: const [
      RouteSearchStep(
        sequence: 1,
        title: '상록수역에서 4호선 승강장으로 이동',
        description: '엘리베이터를 이용해 승강장으로 이동합니다.',
        lineId: 'seoul-4',
        lineName: '수도권 4호선',
        fromStationId: 'station-sangnoksu',
        toStationId: 'station-sadang',
        estimatedMinutes: 4,
        distanceMeters: 180,
        includesStairs: false,
        requiresAccessibilityCheck: true,
      ),
    ],
    warnings: const [
      RouteSearchWarning(
        code: 'LOW_DATA_CONFIDENCE',
        message: '일부 시설 정보는 확인이 필요합니다.',
      ),
    ],
    blockedReasons: [],
    createdAt: '2026-06-13T04:20:00',
  );
}

Map<String, Object?> _favoriteRouteJson() {
  return {
    'userId': 'anonymous-user-1',
    'favoriteRouteId': 'route-1',
    'routeSearchId': 'route-1',
    'originStationId': 'station-sangnoksu',
    'originStationName': '상록수',
    'destinationStationId': 'station-sadang',
    'destinationStationName': '사당',
    'mobilityType': 'SENIOR',
    'status': 'FOUND',
    'lineId': 'seoul-4',
    'lineName': '수도권 4호선',
    'score': 92,
    'routeCreatedAt': '2026-06-13T04:20:00',
    'addedAt': '2026-06-14T10:00:00',
  };
}
