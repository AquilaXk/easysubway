import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/internal_route.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('내부 경로 API 저장소는 노드 목록을 읽고 노드 간 이동 경로를 요청한다', () async {
    final requestedUris = <Uri>[];
    final requestedBodies = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedUris.add(request.uri);
      final requestBody = await utf8.decoder.bind(request).join();
      requestedBodies.add(requestBody);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(
          jsonEncode({
            'success': true,
            'data': [
              {
                'id': 'node-sangnoksu-elevator-1',
                'stationId': 'station-sangnoksu',
                'type': 'ELEVATOR',
                'name': '1번 출구 엘리베이터',
                'facilityId': 'facility-sangnoksu-elevator-1',
                'displayLabel': '1번 출구 승강기',
              },
              {
                'id': 'node-sangnoksu-faregate',
                'stationId': 'station-sangnoksu',
                'type': 'FAREGATE',
                'name': '개찰구',
                'facilityId': null,
                'displayLabel': '개찰구',
              },
            ],
          }),
        );
      } else {
        request.response.write(
          jsonEncode({
            'success': true,
            'data': {
              'stationId': 'station-sangnoksu',
              'stationName': '상록수',
              'fromNodeId': 'node-sangnoksu-elevator-1',
              'fromNodeName': '1번 출구 엘리베이터',
              'toNodeId': 'node-sangnoksu-faregate',
              'toNodeName': '개찰구',
              'mobilityType': 'WHEELCHAIR',
              'status': 'FOUND',
              'totalDistanceMeters': 28,
              'totalEstimatedSeconds': 75,
              'steps': [
                {
                  'sequence': 1,
                  'edgeId': 'edge-sangnoksu-elevator-to-faregate',
                  'fromNodeId': 'node-sangnoksu-elevator-1',
                  'fromNodeName': '1번 출구 엘리베이터',
                  'toNodeId': 'node-sangnoksu-faregate',
                  'toNodeName': '개찰구',
                  'edgeType': 'WALK',
                  'distanceMeters': 28,
                  'estimatedSeconds': 75,
                  'includesStairs': false,
                  'requiresElevator': true,
                  'requiresEscalator': false,
                  'slopeLevel': 1,
                  'widthLevel': 2,
                  'reliabilityScore': 92,
                  'guidance': '엘리베이터에서 개찰구까지 이동합니다.',
                },
              ],
              'warnings': <Object?>[],
              'blockedReasons': <Object?>[],
            },
          }),
        );
      }
      await request.response.close();
    });

    final repository = InternalRouteApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final nodes = await repository.listRouteNodes('station-sangnoksu');
    final request = InternalRouteRequest.defaultForNodes(
      stationId: 'station-sangnoksu',
      mobilityType: 'WHEELCHAIR',
      nodes: nodes,
    );
    final result = await repository.searchInternalRoute(request!);

    expect(requestedUris.map((uri) => uri.path), [
      '/api/v1/stations/station-sangnoksu/route-nodes',
      '/api/v1/routes/internal',
    ]);
    expect(nodes.first.displayLabel, '1번 출구 승강기');
    expect(request.fromNodeId, 'node-sangnoksu-elevator-1');
    expect(request.toNodeId, 'node-sangnoksu-faregate');
    expect(jsonDecode(requestedBodies.last), {
      'stationId': 'station-sangnoksu',
      'fromNodeId': 'node-sangnoksu-elevator-1',
      'toNodeId': 'node-sangnoksu-faregate',
      'mobilityType': 'WHEELCHAIR',
    });
    expect(result.statusLabel, '내부 이동 경로를 찾았습니다');
    expect(result.summaryLabel, '1번 출구 엘리베이터에서 개찰구까지');
    expect(result.totalBurdenLabel, '약 1분 15초 · 28m');
    expect(
      result.steps.single.burdenLabel,
      '약 1분 15초 · 28m · 현장 검증 전 · 엘리베이터 필요',
    );
    expect(result.semanticLabel, contains('1번 내부 이동, 1번 출구 엘리베이터에서 개찰구까지'));
    expect(result.semanticLabel, contains('엘리베이터에서 개찰구까지 이동합니다.'));
  });

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
                  'stepType': 'entry',
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
                  'stepType': 'exit',
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
              'recommendationReasons': [
                '엘리베이터 동선을 우선했어요',
                '계단 없는 출구를 확인했어요',
                '휠체어 이동에 맞춰 계단을 피했어요',
              ],
              'blockedReasons': <Object?>[],
              'createdAt': '2026-06-13T04:20:00',
            },
          }),
        );
      await request.response.close();
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
    expect(result.scoreLabel, '이동 부담 확인 필요');
    expect(result.scoreLabel, isNot(contains('92점')));
    expect(result.recommendationReasons, [
      '엘리베이터 동선을 우선했어요',
      '계단 없는 출구를 확인했어요',
      '휠체어 이동에 맞춰 계단을 피했어요',
    ]);
    expect(result.steps.first.title, '상록수역에서 4호선 승강장으로 이동');
    expect(result.steps.first.actionTitle, isEmpty);
    expect(result.steps.first.hasMetricSourceMetadata, isFalse);
    expect(result.steps.first.estimatedMinutes, 4);
    expect(result.steps.first.distanceMeters, 180);
    expect(result.steps.first.stepType, 'entry');
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
    expect(result.semanticLabel, isNot(contains('시간 확인 필요')));
    expect(result.semanticLabel, isNot(contains('거리 확인 필요')));
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

  test('경로 검색 결과 음성 안내는 내부 식별자와 운영 출처 값을 읽지 않는다', () {
    final result = _sampleRouteSearchResult(
      recommendationReasons: const [
        '선택된 경로 edge:edge-a-b-local 근거로 안내합니다.',
        'OFFICIAL_FILE',
      ],
      steps: const [
        RouteSearchStep(
          sequence: 1,
          title: '출발역에서 중간역까지 테스트 노선 이동',
          description: '출발역에서 중간역까지 열차를 이용합니다.',
          lineId: 'line-test',
          lineName: '테스트 노선',
          fromStationId: 'station-a',
          toStationId: 'station-b',
          estimatedMinutes: 2,
          distanceMeters: 830,
          includesStairs: false,
          requiresAccessibilityCheck: false,
          actionTitle: '열차 이동',
          actionDetail: '출발역에서 중간역까지 테스트 노선을 이용합니다.',
          reason: '선택된 경로 edge:edge-a-b-local 근거로 안내합니다.',
          evidenceSources: ['edge:edge-a-b-local'],
          timeSource: 'STATIC_ESTIMATE',
          distanceSource: 'MEASURED',
          confidenceLabel: '높은 신뢰도',
        ),
      ],
    );

    final semanticLabel = result.semanticLabel;
    expect(semanticLabel, contains('선택한 경로 기준으로 안내합니다.'));
    expect(semanticLabel, isNot(contains('edge:')));
    expect(semanticLabel, isNot(contains('line:')));
    expect(semanticLabel, isNot(contains('OFFICIAL_')));
    expect(semanticLabel, isNot(contains('STATIC_ESTIMATE')));
    expect(semanticLabel, isNot(contains('MEASURED')));
    expect(semanticLabel, isNot(contains('정적 추정')));
    expect(semanticLabel, isNot(contains('측정값')));
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

  test('경로 단계 이동 부담은 측정 거리 없음 상태를 0m로 표시하지 않는다', () {
    const step = RouteSearchStep(
      sequence: 2,
      title: '수도권 4호선으로 사당역까지 이동',
      description: '15개 역을 이동합니다. 환승은 없습니다.',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      fromStationId: 'station-sangnoksu',
      toStationId: 'station-sadang',
      estimatedMinutes: 30,
      distanceMeters: 0,
      includesStairs: false,
      requiresAccessibilityCheck: false,
    );

    expect(step.burdenLabel, '약 30분 · 거리 확인 필요');
  });

  test('경로 단계 이동 부담은 측정 시간 없음 상태를 0분으로 표시하지 않는다', () {
    const step = RouteSearchStep(
      sequence: 2,
      title: '수도권 4호선으로 사당역까지 이동',
      description: '15개 역을 이동합니다. 환승은 없습니다.',
      lineId: 'seoul-4',
      lineName: '수도권 4호선',
      fromStationId: 'station-sangnoksu',
      toStationId: 'station-sadang',
      estimatedMinutes: 0,
      distanceMeters: 180,
      includesStairs: false,
      requiresAccessibilityCheck: false,
    );

    expect(step.burdenLabel, '시간 확인 필요 · 180m');
  });

  test('경로 요약 사실값은 열차 거리와 환승 문구에 의존하지 않는다', () {
    final result = _sampleRouteSearchResult(
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '출발역 승강장 접근',
          description: '엘리베이터로 승강장까지 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 3,
          distanceMeters: 180,
          includesStairs: false,
          requiresAccessibilityCheck: true,
        ),
        RouteSearchStep(
          sequence: 2,
          stepType: 'ride',
          title: '수도권 4호선 이동',
          description: '열차로 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sadang',
          estimatedMinutes: 30,
          distanceMeters: 10000,
          includesStairs: false,
          requiresAccessibilityCheck: false,
        ),
        RouteSearchStep(
          sequence: 3,
          stepType: 'transfer',
          title: '노선 변경 준비',
          description: '다음 열차 승강장으로 이동합니다.',
          lineId: 'seoul-2',
          lineName: '수도권 2호선',
          fromStationId: 'station-sadang',
          toStationId: 'station-sadang',
          estimatedMinutes: 4,
          distanceMeters: 120,
          includesStairs: false,
          requiresAccessibilityCheck: true,
        ),
      ],
    );

    expect(result.walkingDistanceMeters, 300);
    expect(result.transferCount, 1);
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
    expect(saved.mobilityLabel, '천천히 이동');
    expect(saved.scoreLabel, '상세 이동 정보는 다시 검색해 확인');
    expect(saved.scoreLabel, isNot(contains('92점')));
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
        );
      await request.response.close();
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

RouteSearchResult _sampleRouteSearchResult({
  String status = 'FOUND',
  List<RouteSearchStep> steps = const [
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
  List<String> recommendationReasons = const [
    '엘리베이터 동선을 우선했어요',
    '계단 없는 출구를 확인했어요',
    '천천히 이동하기 쉬운 동선을 확인했어요',
  ],
}) {
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
    steps: steps,
    warnings: const [
      RouteSearchWarning(
        code: 'LOW_DATA_CONFIDENCE',
        message: '일부 시설 정보는 확인이 필요합니다.',
      ),
    ],
    recommendationReasons: recommendationReasons,
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
