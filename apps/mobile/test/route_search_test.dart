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
    expect(result.statusLabel, '역 안 이동 경로를 찾았어요');
    expect(result.summaryLabel, '1번 출구 엘리베이터에서 개찰구까지');
    expect(result.totalBurdenLabel, '약 1분 15초 · 28m');
    expect(result.steps.single.burdenLabel, '약 1분 15초 · 28m · 엘리베이터를 이용해요');
    expect(result.semanticLabel, contains('1번 역 안 이동, 1번 출구 엘리베이터에서 개찰구까지'));
    expect(result.semanticLabel, contains('엘리베이터에서 개찰구까지 이동합니다.'));
  });

  test('내부 경로 API 저장소는 잘못된 envelope를 기능 오류로 바꾼다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false}))
        ..close();
    });

    final repository = InternalRouteApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    await expectLater(
      repository.listRouteNodes('station-sangnoksu'),
      throwsA(
        isA<InternalRouteException>().having(
          (error) => error.message,
          'message',
          '역 안 이동 안내를 불러오지 못했어요.',
        ),
      ),
    );
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
              'constraintMode': 'STRICT_STEP_FREE',
              'status': 'FOUND',
              'lineId': 'seoul-4',
              'lineName': '수도권 4호선',
              'score': 92,
              'burdenCost': 41,
              'estimatedDurationSeconds': 420,
              'walkingDistanceMeters': 300,
              'transferCount': 0,
              'evidenceSummary': [
                'ACCESSIBILITY_CHECK_REQUIRED',
                'DURATION_ESTIMATED',
                'DISTANCE_MEASURED',
              ],
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
                  'message': '일부 시설 안내는 아직 확인되지 않았어요.',
                },
                {
                  'code': 'STALE_ACCESSIBILITY_DATA',
                  'message': '엘리베이터와 시설 안내가 오래됐을 수 있어요.',
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
        objective: RouteObjective.fewestTransfers,
      ),
    );

    expect(requestedUri.path, '/api/v1/routes/search');
    expect(jsonDecode(requestedBody), {
      'originStationId': 'station-sangnoksu',
      'destinationStationId': 'station-sadang',
      'mobilityType': 'WHEELCHAIR',
      'constraintMode': 'STRICT_STEP_FREE',
    });
    expect(result.routeSearchId, 'route-1');
    expect(result.objective, RouteObjective.fastest);
    expect(result.constraintMode, 'STRICT_STEP_FREE');
    expect(result.summaryTitle, '상록수에서 사당까지');
    expect(result.lineName, '수도권 4호선');
    expect(result.statusLabel, '경로를 찾았습니다');
    expect(result.score, 92);
    expect(result.burdenCost, 41);
    expect(result.estimatedDurationSeconds, 420);
    expect(result.walkingDistanceMeters, 300);
    expect(result.transferCount, 0);
    expect(result.evidenceSummary, [
      'ACCESSIBILITY_CHECK_REQUIRED',
      'DURATION_ESTIMATED',
      'DISTANCE_MEASURED',
    ]);
    expect(result.scoreLabel, '이동 부담 보통');
    expect(result.scoreLabel, isNot(contains('92점')));
    expect(result.recommendationReasons, [
      '엘리베이터 동선을 우선했어요',
      '계단 없는 출구를 확인했어요',
      '휠체어 이동에 맞춰 계단을 피했어요',
    ]);
    expect(result.steps.first.title, '상록수역에서 4호선 승강장으로 이동');
    expect(result.steps.first.actionTitle, isEmpty);
    expect(result.steps.first.hasMetricSourceMetadata, isTrue);
    expect(result.steps.first.metricSourceLabel, '시간·거리 정보 미확인');
    expect(result.steps.first.estimatedMinutes, 4);
    expect(result.steps.first.distanceMeters, 180);
    expect(result.steps.first.stepType, 'entry');
    expect(result.steps.first.includesStairs, isFalse);
    expect(result.steps.first.requiresAccessibilityCheck, isTrue);
    // 판정은 살아 있지만 구간 줄은 확인된 사실만 적는다. 확인 필요는 경로 단위
    // 표기(접근성 배지·계단 표기)가 말한다.
    expect(result.steps.first.burdenLabel, '약 4분 · 180m');
    expect(result.steps[1].userTitle, '사당역에서 출구 엘리베이터와 통로 안내를 확인');
    expect(result.semanticLabel, isNot(contains('접근성 정보')));
    expect(result.arrivalGuidanceStep?.description, '2번 출구의 엘리베이터를 먼저 확인하세요.');
    expect(
      result.warnings.map((warning) => warning.code),
      containsAll(['LOW_DATA_CONFIDENCE', 'STALE_ACCESSIBILITY_DATA']),
    );
    expect(
      result.warnings.map((warning) => warning.userMessage),
      contains('시설 상태 안내가 오래됐을 수 있어요.'),
    );
    expect(result.semanticLabel, contains('시간·거리 정보 미확인'));
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

    repository.error = const RouteSearchException('경로 정보를 불러오지 못했어요.');

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
    expect(controller.state.message, '경로 정보를 불러오지 못했어요.');
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

  test('경로 검색 컨트롤러는 현재 결과 ETA refresh 상태를 유지해서 표시한다', () async {
    final repository = FakeRouteSearchRepository();
    repository.searchResult = _sampleRouteSearchResult(
      objective: RouteObjective.fewestTransfers,
    );
    final controller = RouteSearchController(repository: repository);

    await controller.search(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'SENIOR',
      ),
    );
    repository.refreshResult = RouteRefreshResult(
      routeSearchId: 'route-1',
      status: 'STALE_FALLBACK',
      result: _sampleRouteSearchResult(
        warnings: const [
          RouteSearchWarning(
            code: 'STALE_ACCESSIBILITY_DATA',
            message: '시설 상태 안내가 오래됐을 수 있어요.',
          ),
        ],
      ),
      refreshedAt: '2026-07-01T15:30:00',
      etaSource: 'FALLBACK',
      etaConfidence: 'LOW',
      sourceLabel: '최근 확인 시간이 오래되어 계획 시간으로 안내',
      reasonCodes: const ['STALE_FALLBACK'],
    );

    await controller.refreshCurrentRoute();

    expect(repository.refreshRouteSearchIds, ['route-1']);
    expect(controller.state.status, RouteSearchViewStatus.success);
    expect(controller.state.isRefreshing, isFalse);
    expect(controller.state.result!.objective, RouteObjective.fewestTransfers);
    expect(
      controller.state.refreshMessage,
      '실시간 정보가 늦어 계획 시간으로 안내해요. · 최근 확인 시간이 오래되어 계획 시간으로 안내 · 신뢰도 낮음',
    );
    expect(
      controller.state.result!.warnings.map((warning) => warning.code),
      contains('STALE_ACCESSIBILITY_DATA'),
    );
  });

  test('경로 검색 컨트롤러는 오래된 ETA refresh 응답으로 새 검색 결과를 덮지 않는다', () async {
    final repository = FakeRouteSearchRepository();
    final controller = RouteSearchController(repository: repository);

    await controller.search(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'SENIOR',
      ),
    );

    final pendingRefresh = Completer<RouteRefreshResult>();
    repository.pendingRefresh = pendingRefresh;
    final refreshFuture = controller.refreshCurrentRoute();

    repository.searchResult = _sampleRouteSearchResult(
      routeSearchId: 'route-2',
    );
    await controller.search(
      const RouteSearchRequest(
        originStationId: 'station-sadang',
        destinationStationId: 'station-sangnoksu',
        mobilityType: 'SENIOR',
      ),
    );

    pendingRefresh.complete(
      RouteRefreshResult(
        routeSearchId: 'route-1',
        status: 'UPDATED_ETA',
        result: _sampleRouteSearchResult(routeSearchId: 'route-1'),
        refreshedAt: '2026-07-01T15:31:00',
        etaSource: 'REALTIME',
        etaConfidence: 'HIGH',
        sourceLabel: '실시간 도착 정보 기준',
      ),
    );
    await refreshFuture;

    expect(controller.state.result!.routeSearchId, 'route-2');
    expect(controller.state.refreshMessage, isEmpty);
  });

  test('경로 검색 결과는 확인 필요 상태를 이동 가능으로 안내하지 않는다', () {
    final result = _sampleRouteSearchResult(status: 'REVIEW_REQUIRED');

    expect(result.statusLabel, '경로 상태를 확인하고 있어요');
    expect(result.guidanceLabel, '확인 후 이동');
    expect(result.guidanceIcon, Icons.warning_amber);
    expect(result.semanticLabel, isNot(contains('이동할 수 있는 경로')));
  });

  test('경로 검색 UNKNOWN 상태는 reason이 있어도 blocked workflow로 분기하지 않는다', () {
    final result = _sampleRouteSearchResult(
      status: 'UNKNOWN',
      blockedReasons: const ['ROUTE_GRAPH_UNKNOWN'],
    );

    expect(result.isBlocked, isFalse);
    expect(result.statusLabel, '경로 상태를 확인하고 있어요');
    expect(result.guidanceLabel, '확인 후 이동');
    expect(result.guidanceIcon, Icons.warning_amber);
    expect(result.needsConfirmation, isTrue);
    expect(result.attentionLabel, '살펴볼 내용');
    expect(result.semanticLabel, contains('살펴볼 내용 길이 이어지는지 확인하고 있어요.'));
    expect(result.semanticLabel, isNot(contains('안내 불가 이유')));
    expect(result.semanticLabel, isNot(contains('다음 행동')));
  });

  test('경로 검색 UNKNOWN localized reason은 구체 안내 문구를 유지한다', () {
    final result = _sampleRouteSearchResult(
      status: 'UNKNOWN',
      blockedReasons: const ['경로 연결 정보를 확인할 수 없습니다.'],
    );

    expect(result.isBlocked, isFalse);
    expect(result.blockedReasonLabels, ['길이 이어지는지 확인하고 있어요.']);
    expect(result.semanticLabel, contains('길이 이어지는지 확인하고 있어요.'));
  });

  test('경로 검색 localized reason은 쉬운 문구를 generic으로 바꾸지 않는다', () {
    final result = _sampleRouteSearchResult(
      status: 'BLOCKED',
      blockedReasons: const ['꼭 필요한 시설을 지금 이용하기 어려워요.'],
    );

    expect(result.blockedReasonLabels, ['꼭 필요한 시설을 지금 이용하기 어려워요.']);
    expect(result.semanticLabel, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
    // 면책은 '안전 안내' 한 곳으로 통합됐다. '이동 전 살펴보기' 이중 고지는 제거(#1577).
    expect(result.semanticLabel, contains('안전 안내'));
    expect(result.semanticLabel, isNot(contains('이동 전 살펴보기')));
    expect(result.semanticLabel, isNot(contains('이동 전 확인')));
    expect(result.semanticLabel, isNot(contains('안내할 수 있는 경로를 아직 찾지 못했어요.')));
  });

  test('경로 검색 결과는 주의 안내를 쉬운 문구로 보여준다', () {
    final safeResult = _sampleRouteSearchResult(warnings: const []);
    final warningResult = _sampleRouteSearchResult(
      warnings: const [
        RouteSearchWarning(code: 'ROUTE_GRAPH_UNKNOWN', message: ''),
      ],
    );

    expect(safeResult.attentionLabel, '주의 안내가 없어요');
    expect(warningResult.attentionLabel, '주의 안내 보기');
  });

  test('경로 warning은 code만으로 사용자 문구를 만들고 서버 원문을 읽지 않는다', () {
    final result = RouteSearchResult.fromJson({
      'routeSearchId': 'route-unknown-warning',
      'originStationId': 'station-sangnoksu',
      'originStationName': '상록수',
      'destinationStationId': 'station-sadang',
      'destinationStationName': '사당',
      'mobilityType': 'SENIOR',
      'status': 'FOUND',
      'lineId': 'seoul-4',
      'lineName': '수도권 4호선',
      'score': 92,
      'steps': <Object?>[],
      'warnings': [
        {'code': 'SERVER_RAW_WARNING'},
      ],
      'recommendationReasons': <Object?>[],
      'blockedReasons': <Object?>[],
      'createdAt': '2026-06-13T04:20:00',
    });

    expect(result.warnings.single.userMessage, '일부 안내를 확인하고 있어요.');
    expect(result.semanticLabel, contains('일부 안내를 확인하고 있어요.'));
    expect(result.semanticLabel, isNot(contains('SERVER_RAW_WARNING')));
  });

  test('경로 contract는 burdenCost 우선 읽기와 score-only legacy fallback을 지원한다', () {
    final newContractResult = RouteSearchResult.fromJson({
      'routeSearchId': 'route-new-contract',
      'originStationId': 'station-sangnoksu',
      'originStationName': '상록수',
      'destinationStationId': 'station-sadang',
      'destinationStationName': '사당',
      'mobilityType': 'SENIOR',
      'status': 'FOUND',
      'lineId': 'seoul-4',
      'lineName': '수도권 4호선',
      'accessibilityScore': 88,
      'burdenCost': 31,
      'estimatedDurationSeconds': 420,
      'walkingDistanceMeters': 250,
      'transferCount': 1,
      'evidenceSummary': ['DURATION_ESTIMATED', 'DISTANCE_MEASURED'],
      'steps': <Object?>[],
      'warnings': <Object?>[],
      'recommendationReasons': <Object?>[],
      'blockedReasons': <Object?>[],
      'createdAt': '2026-06-13T04:20:00',
    });
    final legacyResult = RouteSearchResult.fromJson({
      'routeSearchId': 'route-legacy-score',
      'originStationId': 'station-sangnoksu',
      'originStationName': '상록수',
      'destinationStationId': 'station-sadang',
      'destinationStationName': '사당',
      'mobilityType': 'SENIOR',
      'status': 'FOUND',
      'lineId': 'seoul-4',
      'lineName': '수도권 4호선',
      'score': 92,
      'steps': <Object?>[],
      'warnings': <Object?>[],
      'recommendationReasons': <Object?>[],
      'blockedReasons': <Object?>[],
      'createdAt': '2026-06-13T04:20:00',
    });

    expect(newContractResult.score, 88);
    expect(newContractResult.accessibilityScore, 88);
    expect(newContractResult.burdenCost, 31);
    expect(newContractResult.estimatedDurationSeconds, 420);
    expect(newContractResult.walkingDistanceMeters, 250);
    expect(newContractResult.transferCount, 1);
    expect(newContractResult.evidenceSummary, [
      'DURATION_ESTIMATED',
      'DISTANCE_MEASURED',
    ]);
    expect(legacyResult.score, 92);
    expect(legacyResult.accessibilityScore, 92);
    expect(legacyResult.burdenCost, 92);
  });

  test('경로 검색 요청은 이동 유형별 기본 constraintMode를 직렬화한다', () {
    expect(
      const RouteSearchRequest(
        originStationId: 'a',
        destinationStationId: 'b',
        mobilityType: 'WHEELCHAIR',
      ).toJson()['constraintMode'],
      'STRICT_STEP_FREE',
    );
    expect(
      const RouteSearchRequest(
        originStationId: 'a',
        destinationStationId: 'b',
        mobilityType: 'STROLLER',
      ).toJson()['constraintMode'],
      'PREFER_STEP_FREE',
    );
    expect(
      const RouteSearchRequest(
        originStationId: 'a',
        destinationStationId: 'b',
        mobilityType: 'TEMPORARY_INJURY',
        constraintMode: 'STRICT_STEP_FREE',
      ).toJson()['constraintMode'],
      'STRICT_STEP_FREE',
    );
  });

  test('ETA source 라벨은 상용 claim 전에 무음 또는 실시간 claim으로 떨어지지 않는다', () {
    expect(routeEtaSourceLabels.keys.toSet(), {
      'REALTIME',
      'MIXED',
      'PLANNED',
      'STATIC_BACKEND_ESTIMATE',
      'STATIC_BACKEND_V1',
      'STATIC_LOCAL',
      'STATIC_ESTIMATE',
      'FALLBACK',
      'UNSUPPORTED',
      'STALE',
    });
    expect(routeEtaSourceLabel('REALTIME'), '실시간 도착정보');
    expect(routeEtaSourceLabel('MIXED'), '일부 실시간 도착정보');
    expect(routeEtaSourceLabel('STATIC_BACKEND_ESTIMATE'), '시간표 기준');
    expect(routeEtaSourceLabel('STATIC_ESTIMATE'), '정적 추정');
    expect(routeEtaSourceLabel('UNSUPPORTED'), '실시간 미지원');
    expect(routeEtaSourceLabel('STALE'), '저장된 데이터 기준');
    expect(routeEtaSourceLabel(''), '도착 정보를 확인하고 있어요');
    expect(routeEtaSourceLabel('SERVER_NEW_VALUE'), '도착 정보를 확인하고 있어요');
    expect(routeEtaSourceLabels.values, isNot(contains('실시간 반영')));
    expect(routeEtaSourceLabels.values, isNot(contains('일부 실시간 반영')));
  });

  test('즐겨찾기 경로는 STATIC_ESTIMATE와 누락된 ETA source를 명시한다', () {
    final staticEstimate = FavoriteRoute.fromJson({
      ..._favoriteRouteJson(),
      'etaSource': 'STATIC_ESTIMATE',
    });
    final missingSource = FavoriteRoute.fromJson(_favoriteRouteJson());

    expect(staticEstimate.scoreBasisText, contains('정적 추정'));
    expect(staticEstimate.semanticLabel, contains('정적 추정'));
    expect(missingSource.scoreBasisText, contains('도착 정보를 확인하고 있어요'));
    expect(missingSource.semanticLabel, contains('도착 정보를 확인하고 있어요'));
  });

  test('경로 V2 contract는 itinerary와 leg 단위 ETA 필드를 읽는다', () {
    final result = RouteSearchV2Result.fromJson({
      'contractVersion': 'ROUTE_SEARCH_V2',
      'originStationId': 'station-sangnoksu',
      'destinationStationId': 'station-sadang',
      'departureTime': '2026-06-30T09:15:00+09:00',
      'mobilityType': 'STROLLER',
      'constraintMode': 'STRICT_STEP_FREE',
      'useRealtime': true,
      'maxTransfers': 3,
      'alternativeCount': 2,
      'statuses': [
        'FOUND',
        'BLOCKED_ACCESSIBILITY',
        'NO_TIMETABLE_SERVICE',
        'REALTIME_UNAVAILABLE_PLANNED_USED',
        'UNSUPPORTED_REGION',
        'ROUTE_GRAPH_UNKNOWN',
      ],
      'itineraries': [
        {
          'itineraryId': 'route-1-primary',
          'status': 'FOUND',
          'plannedArrivalTime': '2026-06-30T09:22:00+09:00',
          'realtimeArrivalTime': null,
          'etaSource': 'STATIC_BACKEND_V1',
          'etaConfidence': 'LOW',
          'durationSeconds': 420,
          'transferCount': 1,
          'walkingDistanceMeters': 180,
          'accessibilityRisk': {
            'stairCount': 1,
            'unknownAccessibilityCount': 1,
            'generatedConnectorCount': 0,
            'staleDataCount': 1,
            'lowConfidenceCount': 1,
            'unavailableFacilityCount': 0,
            'riskLevel': 'HIGH',
            'reasonCodes': [
              'LOW_DATA_CONFIDENCE',
              'STALE_ACCESSIBILITY_DATA',
              'ACCESSIBILITY_CHECK_REQUIRED',
            ],
            'level': 'REVIEW_REQUIRED',
            'reasons': ['ACCESSIBILITY_CHECK_REQUIRED'],
          },
          'legs': [
            {
              'legType': 'ACCESS',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-sangnoksu',
              'fromNodeId': '',
              'toNodeId': '',
              'lineId': 'line-4',
              'tripId': '',
              'trainNo': '',
              'plannedDepartureTime': '2026-06-30T09:15:00+09:00',
              'realtimeDepartureTime': null,
              'plannedArrivalTime': '2026-06-30T09:22:00+09:00',
              'realtimeArrivalTime': null,
              'waitTimeSeconds': 0,
              'slackSeconds': 0,
              'durationSeconds': 420,
              'distanceMeters': 180,
              'etaSource': 'STATIC_BACKEND_V1',
              'confidence': 'LOW',
              'accessibilityRisk': {
                'stairCount': 1,
                'unknownAccessibilityCount': 1,
                'generatedConnectorCount': 0,
                'staleDataCount': 0,
                'lowConfidenceCount': 0,
                'unavailableFacilityCount': 0,
                'riskLevel': 'HIGH',
                'reasonCodes': [
                  'STAIR_ONLY_ACCESS',
                  'ACCESSIBILITY_CHECK_REQUIRED',
                ],
                'level': 'REVIEW_REQUIRED',
                'reasons': ['ACCESSIBILITY_CHECK_REQUIRED'],
              },
            },
            {
              'legType': 'OUT_OF_STATION_TRANSFER',
              'fromStationId': 'station-sangnoksu',
              'toStationId': 'station-transfer',
              'fromNodeId': '',
              'toNodeId': '',
              'lineId': '',
              'tripId': '',
              'trainNo': '',
              'plannedDepartureTime': '2026-06-30T09:22:00+09:00',
              'realtimeDepartureTime': null,
              'plannedArrivalTime': '2026-06-30T09:24:00+09:00',
              'realtimeArrivalTime': null,
              'waitTimeSeconds': 0,
              'slackSeconds': 90,
              'durationSeconds': 120,
              'distanceMeters': 80,
              'etaSource': 'PLANNED',
              'confidence': 'MEDIUM',
              'accessibilityRisk': {
                'stairCount': 0,
                'unknownAccessibilityCount': 0,
                'generatedConnectorCount': 0,
                'staleDataCount': 0,
                'lowConfidenceCount': 0,
                'unavailableFacilityCount': 0,
                'riskLevel': 'LOW',
                'reasonCodes': <Object?>[],
                'level': 'LOW',
                'reasons': <Object?>[],
              },
            },
            {
              'legType': 'IN_STATION_TRANSFER',
              'fromStationId': 'station-transfer',
              'toStationId': 'station-transfer',
              'fromNodeId': '',
              'toNodeId': '',
              'lineId': '',
              'tripId': '',
              'trainNo': '',
              'plannedDepartureTime': '2026-06-30T09:24:00+09:00',
              'realtimeDepartureTime': null,
              'plannedArrivalTime': '2026-06-30T09:25:00+09:00',
              'realtimeArrivalTime': null,
              'waitTimeSeconds': 0,
              'slackSeconds': 45,
              'durationSeconds': 60,
              'distanceMeters': 40,
              'etaSource': 'PLANNED',
              'confidence': 'MEDIUM',
              'accessibilityRisk': {
                'stairCount': 0,
                'unknownAccessibilityCount': 0,
                'generatedConnectorCount': 0,
                'staleDataCount': 0,
                'lowConfidenceCount': 0,
                'unavailableFacilityCount': 0,
                'riskLevel': 'LOW',
                'reasonCodes': <Object?>[],
                'level': 'LOW',
                'reasons': <Object?>[],
              },
            },
          ],
          'commercialEtaEligible': false,
        },
        {
          'itineraryId': 'route-1-review',
          'status': 'ROUTE_GRAPH_UNKNOWN',
          'plannedArrivalTime': '2026-06-30T09:22:00+09:00',
          'realtimeArrivalTime': null,
          'etaSource': 'STATIC_BACKEND_V1',
          'etaConfidence': 'UNKNOWN',
          'durationSeconds': 420,
          'transferCount': 0,
          'walkingDistanceMeters': 180,
          'accessibilityRisk': {
            'stairCount': 0,
            'unknownAccessibilityCount': 0,
            'generatedConnectorCount': 0,
            'staleDataCount': 0,
            'lowConfidenceCount': 0,
            'unavailableFacilityCount': 0,
            'riskLevel': 'UNKNOWN',
            'reasonCodes': <Object?>[],
            'level': 'UNKNOWN',
            'reasons': <Object?>[],
          },
          'legs': <Object?>[],
          'commercialEtaEligible': false,
        },
      ],
    });

    expect(result.contractVersion, 'ROUTE_SEARCH_V2');
    expect(result.statuses, contains('REALTIME_UNAVAILABLE_PLANNED_USED'));
    expect(result.itineraries, hasLength(2));
    expect(result.itineraries.first.status, 'FOUND');
    expect(
      result.itineraries.first.plannedArrivalTime,
      '2026-06-30T09:22:00+09:00',
    );
    expect(result.itineraries.first.realtimeArrivalTime, isNull);
    expect(result.itineraries.first.commercialEtaEligible, isFalse);
    expect(result.itineraries.first.accessibilityRisk.level, 'REVIEW_REQUIRED');
    expect(result.itineraries.first.accessibilityRisk.riskLevel, 'HIGH');
    expect(result.itineraries.first.accessibilityRisk.stairCount, 1);
    expect(
      result.itineraries.first.accessibilityRisk.unknownAccessibilityCount,
      1,
    );
    expect(result.itineraries.first.accessibilityRisk.staleDataCount, 1);
    expect(result.itineraries.first.accessibilityRisk.lowConfidenceCount, 1);
    expect(
      result.itineraries.first.accessibilityRisk.reasonCodes,
      contains('STALE_ACCESSIBILITY_DATA'),
    );
    expect(result.itineraries.first.legs.first.legType, 'ACCESS');
    expect(
      result.itineraries.first.legs.first.accessibilityRisk.riskLevel,
      'HIGH',
    );
    expect(result.itineraries.first.legs.first.waitTimeSeconds, 0);
    expect(result.itineraries.first.legs.first.slackSeconds, 0);
    expect(result.itineraries.first.legs.first.etaSource, 'STATIC_BACKEND_V1');
    final displayResult = RouteSearchResult.fromV2(result);
    expect(displayResult.steps.first.metricSourceLabel, '서버 경로 안내 기준이에요');
    expect(displayResult.etaConfidence, 'LOW');
    expect(displayResult.accessibilityRiskLevel, 'HIGH');
    expect(displayResult.transferSlackSeconds, 45);
    expect(displayResult.hasOutOfStationTransfer, isTrue);
    expect(displayResult.commercialEtaEligible, isFalse);
  });

  test('경로 V2 변환은 ride 노선과 불확실 접근성을 보수적으로 표시한다', () {
    const uncertainRisk = RouteSearchV2AccessibilityRisk(
      stairCount: 0,
      unknownAccessibilityCount: 0,
      generatedConnectorCount: 1,
      staleDataCount: 0,
      lowConfidenceCount: 0,
      unavailableFacilityCount: 0,
      riskLevel: 'UNKNOWN',
      reasonCodes: ['GENERATED_CONNECTOR_UNVERIFIED'],
      level: 'REVIEW_REQUIRED',
      reasons: ['GENERATED_CONNECTOR_UNVERIFIED'],
    );
    const clearRisk = RouteSearchV2AccessibilityRisk(
      stairCount: 0,
      unknownAccessibilityCount: 0,
      generatedConnectorCount: 0,
      staleDataCount: 0,
      lowConfidenceCount: 0,
      unavailableFacilityCount: 0,
      riskLevel: 'LOW',
      reasonCodes: [],
      level: 'LOW',
      reasons: [],
    );

    final result = RouteSearchResult.fromV2(
      const RouteSearchV2Result(
        contractVersion: 'ROUTE_SEARCH_V2',
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        departureTime: '2026-06-30T09:15:00+09:00',
        mobilityType: 'WHEELCHAIR',
        constraintMode: 'STRICT_STEP_FREE',
        useRealtime: true,
        maxTransfers: 3,
        alternativeCount: 3,
        statuses: ['FOUND'],
        itineraries: [
          RouteSearchV2Itinerary(
            itineraryId: 'route-ride-line-primary',
            status: 'FOUND',
            plannedArrivalTime: '2026-06-30T09:42:00+09:00',
            realtimeArrivalTime: null,
            etaSource: 'PLANNED',
            etaConfidence: 'MEDIUM',
            durationSeconds: 1620,
            transferCount: 0,
            walkingDistanceMeters: 80,
            accessibilityRisk: uncertainRisk,
            commercialEtaEligible: false,
            legs: [
              RouteSearchV2Leg(
                legType: 'ACCESS',
                fromStationId: 'station-sangnoksu',
                toStationId: 'station-sangnoksu',
                fromNodeId: '',
                toNodeId: '',
                lineId: '',
                tripId: '',
                trainNo: '',
                plannedDepartureTime: '2026-06-30T09:15:00+09:00',
                realtimeDepartureTime: null,
                plannedArrivalTime: '2026-06-30T09:17:00+09:00',
                realtimeArrivalTime: null,
                waitTimeSeconds: 0,
                slackSeconds: 0,
                durationSeconds: 120,
                distanceMeters: 80,
                etaSource: 'PLANNED',
                confidence: 'LOW',
                accessibilityRisk: uncertainRisk,
              ),
              RouteSearchV2Leg(
                legType: 'RIDE',
                fromStationId: 'station-sangnoksu',
                toStationId: 'station-sadang',
                fromNodeId: '',
                toNodeId: '',
                lineId: 'line-4',
                tripId: 'trip-1',
                trainNo: '4001',
                plannedDepartureTime: '2026-06-30T09:17:00+09:00',
                realtimeDepartureTime: null,
                plannedArrivalTime: '2026-06-30T09:42:00+09:00',
                realtimeArrivalTime: null,
                waitTimeSeconds: 60,
                slackSeconds: 0,
                durationSeconds: 1500,
                distanceMeters: 12000,
                etaSource: 'PLANNED',
                confidence: 'MEDIUM',
                accessibilityRisk: clearRisk,
              ),
            ],
          ),
        ],
      ),
    );

    expect(result.lineId, 'line-4');
    expect(result.lineName, 'line-4');
    expect(result.score, 85);
    expect(result.steps.first.stepType, 'entry');
    expect(result.steps.first.actionTitle, isEmpty);
    expect(result.steps.first.userDescription, contains('승강장 접근'));
    expect(result.steps.last.estimatedMinutes, 26);
    expect(result.steps.first.stairAccessState, 'unknown');
    expect(result.stairAccessLabel, '계단 여부를 확인하고 있어요');
    expect(result.transferSlackSeconds, isNull);
    expect(result.hasOutOfStationTransfer, isFalse);
  });

  test('경로 결과 badge는 ETA, 접근성, 환승 explicit 필드에서 파생된다', () {
    final tightTransfer = _sampleRouteSearchResult(
      etaSource: 'STATIC_ESTIMATE',
      accessibilityRiskLevel: 'HIGH',
      transferSlackSeconds: 45,
      hasOutOfStationTransfer: true,
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'transfer',
          title: '역 밖 환승',
          description: '밖으로 나가 다음 노선으로 갈아탑니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sadang',
          toStationId: 'station-sadang',
          estimatedMinutes: 5,
          distanceMeters: 180,
          includesStairs: false,
          stairAccessState: 'unknown',
          requiresAccessibilityCheck: true,
        ),
      ],
    );

    expect(tightTransfer.badgeLabels, ['정적 추정', '엘리베이터 상태를 살펴봐 주세요', '역 밖 환승']);
    expect(tightTransfer.semanticLabel, contains('정적 추정'));
    expect(tightTransfer.semanticLabel, contains('엘리베이터 상태를 살펴봐 주세요'));
    expect(tightTransfer.semanticLabel, contains('역 밖 환승'));

    final clearTransfer = _sampleRouteSearchResult(
      etaSource: 'PLANNED',
      accessibilityRiskLevel: 'LOW',
      transferSlackSeconds: 180,
      warnings: const [],
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'transfer',
          title: '노선 변경 준비',
          description: '다음 노선으로 갈아탑니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sadang',
          toStationId: 'station-sadang',
          estimatedMinutes: 4,
          distanceMeters: 120,
          includesStairs: false,
          stairAccessState: 'stepFree',
          requiresAccessibilityCheck: false,
        ),
      ],
    );

    expect(clearTransfer.badgeLabels, ['시간표 기준', '계단 없는 경로 확인', '환승 여유 충분']);
  });

  test('경로 V2 blocked reasonCodes가 비어 있으면 status를 보존한다', () {
    const clearRisk = RouteSearchV2AccessibilityRisk(
      stairCount: 0,
      unknownAccessibilityCount: 0,
      generatedConnectorCount: 0,
      staleDataCount: 0,
      lowConfidenceCount: 0,
      unavailableFacilityCount: 0,
      riskLevel: 'UNKNOWN',
      reasonCodes: [],
      level: 'UNKNOWN',
      reasons: [],
    );

    final result = RouteSearchResult.fromV2(
      const RouteSearchV2Result(
        contractVersion: 'ROUTE_SEARCH_V2',
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        departureTime: '2026-06-30T09:15:00+09:00',
        mobilityType: 'WHEELCHAIR',
        constraintMode: 'STRICT_STEP_FREE',
        useRealtime: true,
        maxTransfers: 3,
        alternativeCount: 3,
        statuses: ['ROUTE_GRAPH_UNKNOWN'],
        itineraries: [
          RouteSearchV2Itinerary(
            itineraryId: 'route-unknown-primary',
            status: 'ROUTE_GRAPH_UNKNOWN',
            plannedArrivalTime: '2026-06-30T09:42:00+09:00',
            realtimeArrivalTime: null,
            etaSource: 'PLANNED',
            etaConfidence: 'UNKNOWN',
            durationSeconds: 0,
            transferCount: 0,
            walkingDistanceMeters: 0,
            accessibilityRisk: clearRisk,
            legs: [],
            commercialEtaEligible: false,
          ),
        ],
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.blockedReasons, ['ROUTE_GRAPH_UNKNOWN']);
  });

  test('경로 contract는 accessibilityScore만으로 이동 비용을 대체하지 않는다', () {
    expect(
      () => RouteSearchResult.fromJson({
        'routeSearchId': 'route-score-only',
        'originStationId': 'station-sangnoksu',
        'originStationName': '상록수',
        'destinationStationId': 'station-sadang',
        'destinationStationName': '사당',
        'mobilityType': 'SENIOR',
        'status': 'FOUND',
        'lineId': 'seoul-4',
        'lineName': '수도권 4호선',
        'accessibilityScore': 88,
        'steps': <Object?>[],
        'warnings': <Object?>[],
        'recommendationReasons': <Object?>[],
        'blockedReasons': <Object?>[],
        'createdAt': '2026-06-13T04:20:00',
      }),
      throwsFormatException,
    );
  });

  test('경로 이동 부담은 warning 없음만으로 낮음이 되지 않는다', () {
    final longWalkingResult = _sampleRouteSearchResult(
      warnings: const [],
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '출발역 승강장 접근',
          description: '승강장까지 길게 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 18,
          distanceMeters: 1200,
          includesStairs: false,
          stairAccessState: 'stepFree',
          requiresAccessibilityCheck: false,
        ),
      ],
    );
    final uncertainResult = _sampleRouteSearchResult(
      warnings: const [],
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '출발역 승강장 접근',
          description: '승강장까지 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 3,
          distanceMeters: 80,
          includesStairs: false,
          stairAccessState: 'unknown',
          requiresAccessibilityCheck: true,
        ),
      ],
    );

    expect(longWalkingResult.guidanceLabel, '안내 가능');
    expect(longWalkingResult.scoreLabel, '이동 부담 높음');
    expect(uncertainResult.guidanceLabel, '안내 가능');
    expect(uncertainResult.scoreLabel, '이동 부담 보통');
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
          confidenceLabel: '확인된 정보예요',
        ),
        RouteSearchStep(
          sequence: 2,
          title: '도착역 출구 이동',
          description: 'edge:exit-b line:test STATIC_ESTIMATE',
          lineId: 'line-test',
          lineName: '테스트 노선',
          fromStationId: 'station-sadang',
          toStationId: 'station-sadang',
          estimatedMinutes: 1,
          distanceMeters: 40,
          includesStairs: false,
          requiresAccessibilityCheck: true,
          actionTitle: '출구 이동',
          actionDetail: 'edge:exit-b line:test STATIC_ESTIMATE',
          reason: 'OFFICIAL_FILE',
          evidenceSources: ['edge:exit-b'],
          timeSource: 'STATIC_ESTIMATE',
          distanceSource: 'MEASURED',
          confidenceLabel: '확인된 정보예요',
          stepType: 'exit',
        ),
      ],
    );

    final semanticLabel = result.semanticLabel;
    expect(semanticLabel, contains('선택한 길을 따라 안내합니다.'));
    expect(semanticLabel, contains('도착역에서 계단 없는 출구 동선을 확인합니다.'));
    expect(semanticLabel, isNot(contains('edge:')));
    expect(semanticLabel, isNot(contains('line:')));
    expect(semanticLabel, isNot(contains('OFFICIAL_')));
    expect(semanticLabel, isNot(contains('STATIC_ESTIMATE')));
    expect(semanticLabel, isNot(contains('MEASURED')));
    expect(semanticLabel, isNot(contains('정적 추정')));
    expect(semanticLabel, isNot(contains('측정값')));
  });

  test('경유 스텝 음성 안내는 신뢰도·측정 출처 문구를 읽지 않는다 (#1975)', () {
    // 경유 마커가 신뢰도 문구(confidenceLabel)와 측정 출처를 갖고 있어도 경유
    // 스텝에서는 그 문구가 음성 안내에 새어 나오지 않아야 한다.
    const waypointStep = RouteSearchStep(
      sequence: 2,
      stepType: 'waypoint',
      title: '선릉 경유',
      description: '내리지 않고 이 역을 지나가요',
      lineId: '',
      lineName: '',
      fromStationId: 'station-seolleung',
      toStationId: 'station-seolleung',
      estimatedMinutes: 0,
      distanceMeters: 0,
      includesStairs: false,
      requiresAccessibilityCheck: false,
      timeSource: 'UNKNOWN',
      distanceSource: 'UNKNOWN',
      confidenceLabel: '확인된 정보예요',
    );

    final label = waypointStep.semanticGuidanceLabel;
    expect(label, isNot(contains('확인된 정보예요')));
    expect(label, isNot(contains('확인하고 있어요')));
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

    expect(step.burdenLabel, '약 30분 · 거리 미확인');
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

    expect(step.burdenLabel, '시간 미확인 · 180m');
  });

  test('경로 계단 상태는 unknown을 계단 없음으로 올리지 않는다', () {
    final result = _sampleRouteSearchResult(
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '출발역 승강장 접근',
          description: '승강장까지 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 3,
          distanceMeters: 80,
          includesStairs: false,
          stairAccessState: 'unknown',
          requiresAccessibilityCheck: true,
        ),
      ],
    );

    expect(result.stairAccessLabel, '계단 여부를 확인하고 있어요');
    expect(result.semanticLabel, contains('계단 여부를 확인하고 있어요'));
    expect(result.semanticLabel, isNot(contains('계단 없음')));
  });

  test('경로 계단 상태는 계단 없는 길을 쉬운 문구로 보여준다', () {
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
          distanceMeters: 80,
          includesStairs: false,
          stairAccessState: 'stepFree',
          requiresAccessibilityCheck: false,
        ),
      ],
    );

    expect(result.stairAccessLabel, '계단 없는 길이에요');
    expect(result.semanticLabel, contains('계단 없는 길이에요'));
    expect(result.semanticLabel, isNot(contains('계단 없음 확인')));
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
    expect(result.estimatedDurationSeconds, 2220);
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
    expect(saved.mobilityLabel, '천천히');
    // 플레이스홀더(score/이동·접근성 메트릭) 문구는 카드·시맨틱에서 제거됐다(#1488).
    expect(saved.semanticLabel, contains('상록수에서 사당까지'));
    expect(saved.semanticLabel, isNot(contains('92점')));
    expect(saved.semanticLabel, isNot(contains('아직 알 수 없어요')));
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
        itineraryId: 'route-1-primary',
        mobilityType: 'SENIOR',
        constraintMode: 'PREFER_STEP_FREE',
        etaSource: 'PLANNED',
        etaOffsetBucket: RouteEtaOffsetBucket.notProvided,
        etaFeedbackOptedIn: true,
      ),
    );

    expect(requestedUri.path, '/api/v1/routes/route-1/feedback');
    expect(requestedAuthorization, startsWith('Basic '));
    expect(jsonDecode(requestedBody), {
      'userId': 'anonymous-user-1',
      'rating': 'HELPFUL',
      'comment': '추천이 도움이 됐어요',
      'itineraryId': 'route-1-primary',
      'mobilityType': 'SENIOR',
      'constraintMode': 'PREFER_STEP_FREE',
      'etaSource': 'PLANNED',
      'etaOffsetBucket': 'NOT_PROVIDED',
      'etaFeedbackOptedIn': true,
    });
  });

  group('#2099 V2 leg 운행 정보 파싱·급행 배지 파생', () {
    test('RIDE SUBWAY/EXPRESS leg은 급행으로 파생된다', () {
      final leg = RouteSearchV2Leg.fromJson(
        _rideLegJson(serviceClass: 'SUBWAY', servicePattern: 'EXPRESS'),
      );
      expect(leg.serviceClass, 'SUBWAY');
      expect(leg.servicePattern, 'EXPRESS');
      expect(leg.isSubwayExpress, isTrue);
      final step = RouteSearchStep.fromV2(1, leg);
      expect(step.isSubwayExpress, isTrue);
    });

    test('RIDE SUBWAY/LOCAL leg은 급행이 아니다', () {
      final leg = RouteSearchV2Leg.fromJson(
        _rideLegJson(serviceClass: 'SUBWAY', servicePattern: 'LOCAL'),
      );
      expect(leg.isSubwayExpress, isFalse);
      expect(RouteSearchStep.fromV2(1, leg).isSubwayExpress, isFalse);
    });

    test('RIDE ITX_CHEONGCHUN/EXPRESS leg은 generic 급행 배지를 만들지 않는다', () {
      final leg = RouteSearchV2Leg.fromJson(
        _rideLegJson(serviceClass: 'ITX_CHEONGCHUN', servicePattern: 'EXPRESS'),
      );
      expect(leg.serviceClass, 'ITX_CHEONGCHUN');
      expect(leg.isSubwayExpress, isFalse);
      expect(RouteSearchStep.fromV2(1, leg).isSubwayExpress, isFalse);
    });

    test('RIDE ITX_CHEONGCHUN leg은 ITX-청춘 서비스 식별로 파생된다', () {
      final leg = RouteSearchV2Leg.fromJson(
        _rideLegJson(serviceClass: 'ITX_CHEONGCHUN', servicePattern: 'EXPRESS'),
      );
      final step = RouteSearchStep.fromV2(1, leg);
      expect(step.isItxCheongchun, isTrue);
      // ITX-청춘은 급행 배지와 상호 배타다.
      expect(step.isSubwayExpress, isFalse);
    });

    test('RIDE ITX_CHEONGCHUN/LOCAL leg도 ITX-청춘 서비스 식별을 유지한다', () {
      // isItxCheongchun은 servicePattern과 무관하게 serviceClass만 본다(의도 동작).
      // EXPRESS 케이스만 고정되어 있으면 LOCAL 회귀를 못 잡으므로 별도로 고정한다.
      final leg = RouteSearchV2Leg.fromJson(
        _rideLegJson(serviceClass: 'ITX_CHEONGCHUN', servicePattern: 'LOCAL'),
      );
      final step = RouteSearchStep.fromV2(1, leg);
      expect(step.isItxCheongchun, isTrue);
      expect(step.isSubwayExpress, isFalse);
    });

    test('RIDE SUBWAY leg은 ITX-청춘이 아니다', () {
      final local = RouteSearchStep.fromV2(
        1,
        RouteSearchV2Leg.fromJson(
          _rideLegJson(serviceClass: 'SUBWAY', servicePattern: 'LOCAL'),
        ),
      );
      final express = RouteSearchStep.fromV2(
        1,
        RouteSearchV2Leg.fromJson(
          _rideLegJson(serviceClass: 'SUBWAY', servicePattern: 'EXPRESS'),
        ),
      );
      expect(local.isItxCheongchun, isFalse);
      expect(express.isItxCheongchun, isFalse);
    });

    test('non-ride leg의 service 필드는 null만 허용한다', () {
      final walk = _rideLegJson(legType: 'WALK')
        ..remove('serviceClass')
        ..remove('servicePattern');
      final leg = RouteSearchV2Leg.fromJson(walk);
      expect(leg.serviceClass, isNull);
      expect(leg.servicePattern, isNull);
      expect(leg.isSubwayExpress, isFalse);
    });

    test('non-ride leg이 service 필드를 실으면 payload error다', () {
      final walk = _rideLegJson(legType: 'WALK');
      walk['serviceClass'] = 'SUBWAY';
      walk['servicePattern'] = 'EXPRESS';
      expect(
        () => RouteSearchV2Leg.fromJson(walk),
        throwsA(isA<FormatException>()),
      );
    });

    test('RIDE unknown pattern은 LOCAL 추정 없이 payload error다', () {
      final leg = _rideLegJson(serviceClass: 'SUBWAY', servicePattern: 'RAPID');
      expect(
        () => RouteSearchV2Leg.fromJson(leg),
        throwsA(isA<FormatException>()),
      );
    });

    test('RIDE blank service 필드는 LOCAL 추정 없이 payload error다', () {
      final leg = _rideLegJson(serviceClass: '', servicePattern: '');
      expect(
        () => RouteSearchV2Leg.fromJson(leg),
        throwsA(isA<FormatException>()),
      );
    });

    test('RIDE에 service 필드가 없으면 payload error다', () {
      final leg = _rideLegJson()
        ..remove('serviceClass')
        ..remove('servicePattern');
      expect(
        () => RouteSearchV2Leg.fromJson(leg),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('#2099 objective-tagged itinerary 보존·선택', () {
    test('선택 objective와 공식 운임, exact leg 시각을 공유 입력까지 보존한다', () {
      final itinerary = RouteSearchV2Itinerary.fromJson({
        'itineraryId': 'route-itx-primary',
        'status': 'FOUND',
        'plannedArrivalTime': '2026-06-30T11:42:00+09:00',
        'realtimeArrivalTime': null,
        'etaSource': 'PLANNED',
        'etaConfidence': 'MEDIUM',
        'durationSeconds': 9120,
        'transferCount': 1,
        'walkingDistanceMeters': 180,
        'accessibilityRisk': <String, Object?>{
          'stairCount': 0,
          'unknownAccessibilityCount': 0,
          'generatedConnectorCount': 0,
          'staleDataCount': 0,
          'lowConfidenceCount': 0,
          'unavailableFacilityCount': 0,
          'riskLevel': 'LOW',
          'reasonCodes': <String>[],
          'level': 'LOW',
          'reasons': <String>[],
        },
        'legs': [
          _rideLegJson(
            serviceClass: 'ITX_CHEONGCHUN',
            servicePattern: 'EXPRESS',
          ),
        ],
        'commercialEtaEligible': true,
        'objectiveTags': ['FEWEST_TRANSFERS'],
        'officialFare': <String, Object?>{
          'adultFareWon': 9800,
          'currency': 'KRW',
          'policy': 'SUM_OF_OFFICIAL_RIDE_OD_FARES',
          'sourceIds': ['tago-train-schedule-fares'],
          'sourceSnapshotIds': ['itx-20260630'],
        },
      });
      final result = _objectiveResult([itinerary]);

      final display = RouteSearchResult.fromV2(
        result,
        objective: RouteObjective.fewestTransfers,
      );

      expect(display.objective, RouteObjective.fewestTransfers);
      expect(display.departureTimeIso, '2026-06-30T09:15:00+09:00');
      expect(display.arrivalTimeIso, '2026-06-30T11:42:00+09:00');
      expect(display.officialFare?.adultFareWon, 9800);
      expect(display.officialFare?.currency, 'KRW');
      expect(
        display.steps.single.plannedDepartureTimeIso,
        '2026-06-30T09:17:00+09:00',
      );
      expect(
        display.steps.single.plannedArrivalTimeIso,
        '2026-06-30T09:42:00+09:00',
      );
    });

    test('dual-tag dedupe된 대표 itinerary는 두 objective에서 모두 선택된다', () {
      final result = _objectiveResult([
        _taggedItinerary(
          lineId: 'line-shared',
          objectiveTags: const ['FASTEST', 'FEWEST_TRANSFERS'],
        ),
      ]);
      expect(
        RouteSearchResult.fromV2(
          result,
          objective: RouteObjective.fastest,
        ).lineId,
        'line-shared',
      );
      expect(
        RouteSearchResult.fromV2(
          result,
          objective: RouteObjective.fewestTransfers,
        ).lineId,
        'line-shared',
      );
    });

    test('objective별 대표가 다르면 각 objective의 태그된 itinerary를 고른다', () {
      final result = _objectiveResult([
        _taggedItinerary(lineId: 'line-fast', objectiveTags: const ['FASTEST']),
        _taggedItinerary(
          lineId: 'line-few',
          objectiveTags: const ['FEWEST_TRANSFERS'],
        ),
      ]);
      expect(
        RouteSearchResult.fromV2(
          result,
          objective: RouteObjective.fastest,
        ).lineId,
        'line-fast',
      );
      expect(
        RouteSearchResult.fromV2(
          result,
          objective: RouteObjective.fewestTransfers,
        ).lineId,
        'line-few',
      );
    });

    test('태그 없는 응답은 첫 FOUND로 폴백해 기존 동작을 보존한다', () {
      final result = _objectiveResult([
        _taggedItinerary(lineId: 'line-a', objectiveTags: const []),
      ]);
      expect(
        RouteSearchResult.fromV2(
          result,
          objective: RouteObjective.fewestTransfers,
        ).lineId,
        'line-a',
      );
    });

    test('#2582 무단차 대안 태그가 붙은 후보를 대표와 함께 화면 모델로 만든다', () {
      final result = _objectiveResult([
        _taggedItinerary(
          lineId: 'line-stair',
          objectiveTags: const ['FASTEST'],
          stairCount: 1,
        ),
        _taggedItinerary(
          lineId: 'line-step-free',
          objectiveTags: const ['STEP_FREE_PREFERRED'],
          reasonCodes: const ['LOW_DATA_CONFIDENCE'],
        ),
      ]);

      final display = RouteSearchResult.fromV2(
        result,
        objective: RouteObjective.fastest,
      );

      expect(display.lineId, 'line-stair');
      expect(display.stairAccessLabel, '계단 포함');
      final alternative = display.stepFreeAlternative;
      expect(alternative, isNotNull);
      expect(alternative!.lineId, 'line-step-free');
      // 대안 자신은 다시 대안을 갖지 않는다(전환 시 그대로 주 결과가 된다).
      expect(alternative.stepFreeAlternative, isNull);
      // 대안의 경고는 감추지 않고 그대로 실어 보낸다.
      expect(alternative.warningNoticeText, '일부 시설 안내는 아직 확인되지 않았어요.');
    });

    test('#2582 판정 필드가 없는 레거시 응답에서는 태그가 붙어도 미확인으로 남는다', () {
      // 백엔드가 계단 판정을 싣지 않는 응답에서는 화면이 원자료로 폴백한다(#2590).
      // 승차 leg의 unknownAccessibilityCount=1을 미확인으로 읽어 라벨이 "계단 여부를
      // 확인하고 있어요"로 떨어지므로, 태그를 "확인된 무단차"로 옮겨 적으면 과대
      // 주장이 된다. 폴백은 이렇게 fail closed 쪽으로만 틀린다.
      final result = _objectiveResult([
        _taggedItinerary(
          lineId: 'line-stair',
          objectiveTags: const ['FASTEST'],
          stairCount: 1,
        ),
        _taggedItinerary(
          lineId: 'line-step-free',
          objectiveTags: const ['STEP_FREE_PREFERRED'],
          unknownAccessibilityCount: 1,
        ),
      ]);

      final alternative = RouteSearchResult.fromV2(
        result,
        objective: RouteObjective.fastest,
      ).stepFreeAlternative;

      expect(alternative, isNotNull);
      expect(alternative!.stairAccessLabel, '계단 여부를 확인하고 있어요');
    });

    test('#2582 무단차 대안 태그가 없으면 대안 없이 기존 단건 결과 그대로다', () {
      final result = _objectiveResult([
        _taggedItinerary(lineId: 'line-fast', objectiveTags: const ['FASTEST']),
      ]);

      final display = RouteSearchResult.fromV2(
        result,
        objective: RouteObjective.fastest,
      );

      expect(display.lineId, 'line-fast');
      expect(display.stepFreeAlternative, isNull);
    });

    test('#2582 태그 없는 레거시 응답도 대안 없이 첫 FOUND를 그대로 쓴다', () {
      final result = _objectiveResult([
        _taggedItinerary(lineId: 'line-a', objectiveTags: const []),
      ]);

      final display = RouteSearchResult.fromV2(
        result,
        objective: RouteObjective.fewestTransfers,
      );

      expect(display.lineId, 'line-a');
      expect(display.stepFreeAlternative, isNull);
    });

    test('#2582 대안 태그만 있고 요청 objective 대표가 없으면 여전히 fail closed', () {
      final result = _objectiveResult([
        _taggedItinerary(
          lineId: 'line-step-free',
          objectiveTags: const ['STEP_FREE_PREFERRED'],
        ),
      ]);
      expect(
        () =>
            RouteSearchResult.fromV2(result, objective: RouteObjective.fastest),
        throwsFormatException,
      );
    });

    test('태그가 있는데 요청 objective와 매칭되는 FOUND가 없으면 fail closed', () {
      // FASTEST 전용 경로만 있는데 최소환승을 요청하면 silent fallback(계약 위반)을
      // 피해 payload 오류로 실패시킨다. RouteSearchV2ApiRepository.searchRoute의 generic
      // catch가 이 FormatException을 unavailable로 흘려보낸다.
      final result = _objectiveResult([
        _taggedItinerary(lineId: 'line-fast', objectiveTags: const ['FASTEST']),
      ]);
      expect(
        () => RouteSearchResult.fromV2(
          result,
          objective: RouteObjective.fewestTransfers,
        ),
        throwsFormatException,
      );
    });

    test('이전 objective 검색의 늦은 응답은 현재 화면을 덮지 않는다', () async {
      final repository = _ManualRouteSearchRepository();
      final controller = RouteSearchController(repository: repository);
      addTearDown(controller.dispose);

      const fastRequest = RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'STANDARD',
      );
      const fewRequest = RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'STANDARD',
        objective: RouteObjective.fewestTransfers,
      );

      unawaited(controller.search(fastRequest));
      unawaited(controller.search(fewRequest));
      await pumpEventQueue();

      // 이전(FASTEST) 검색이 늦게 도착해도 최신(FEWEST_TRANSFERS) 상태를 덮지 못한다.
      repository.completers[RouteObjective.fastest]!.complete(
        _routeResult('route-fast'),
      );
      await pumpEventQueue();
      expect(controller.state.result, isNull);
      expect(controller.state.status, RouteSearchViewStatus.loading);

      repository.completers[RouteObjective.fewestTransfers]!.complete(
        _routeResult('route-few'),
      );
      await pumpEventQueue();
      expect(controller.state.status, RouteSearchViewStatus.success);
      expect(controller.state.result?.routeSearchId, 'route-few');
    });
  });

  group('#2590 계단 접근성 판정 원천 통일', () {
    test('승차 leg만 미확인인 경로는 백엔드 판정대로 계단 없는 길로 표시한다', () {
      final display = _judgedDisplay(
        stairAccess: 'STEP_FREE',
        legs: [
          _judgedLeg(legType: 'ACCESS', stairAccess: 'STEP_FREE'),
          _judgedLeg(
            legType: 'RIDE',
            stairAccess: 'NOT_APPLICABLE',
            unknownAccessibilityCount: 1,
          ),
          _judgedLeg(legType: 'EGRESS', stairAccess: 'STEP_FREE'),
        ],
      );

      expect(display.stairAccessLabel, '계단 없는 길이에요');
    });

    test('계단 전이가 있는 경로는 계단 포함으로 표시한다', () {
      final display = _judgedDisplay(
        stairAccess: 'STAIR_ONLY',
        legs: [
          _judgedLeg(
            legType: 'ACCESS',
            stairAccess: 'STAIR_ONLY',
            stairCount: 1,
          ),
          _judgedLeg(
            legType: 'RIDE',
            stairAccess: 'NOT_APPLICABLE',
            unknownAccessibilityCount: 1,
          ),
        ],
      );

      expect(display.stairAccessLabel, '계단 포함');
    });

    test('실제 미확인 사유가 있는 경로는 계단 없는 길로 승격되지 않는다', () {
      // 백엔드가 내는 형태 그대로다: 신뢰도 사유는 경로 단위 경고라 itinerary
      // accessibilityRisk에만 실리고, 그 사유로 강등된 접근 leg는 판정 필드가
      // UNKNOWN이 되며 leg 카운터는 그대로 0이다.
      for (final reason in const ['staleDataCount', 'lowConfidenceCount']) {
        final display = _judgedDisplay(
          stairAccess: 'UNKNOWN',
          staleDataCount: reason == 'staleDataCount' ? 1 : 0,
          lowConfidenceCount: reason == 'lowConfidenceCount' ? 1 : 0,
          legs: [
            _judgedLeg(legType: 'ACCESS', stairAccess: 'UNKNOWN'),
            _judgedLeg(
              legType: 'RIDE',
              stairAccess: 'NOT_APPLICABLE',
              unknownAccessibilityCount: 1,
            ),
          ],
        );

        expect(
          display.stairAccessLabel,
          '계단 여부를 확인하고 있어요',
          reason: '$reason가 있는 경로는 무단차로 단언하지 않는다',
        );
      }
    });

    test('미확인 사유로 강등된 경로는 칩 행과 스크린리더가 한 목소리로 말한다', () {
      final display = _judgedDisplay(
        stairAccess: 'UNKNOWN',
        staleDataCount: 1,
        legs: [
          _judgedLeg(legType: 'ACCESS', stairAccess: 'UNKNOWN'),
          _judgedLeg(
            legType: 'RIDE',
            stairAccess: 'NOT_APPLICABLE',
            unknownAccessibilityCount: 1,
          ),
        ],
      );

      expect(display.stairAccessLabel, '계단 여부를 확인하고 있어요');
      expect(display.accessibilityBadgeLabel, '엘리베이터 상태를 살펴봐 주세요');
    });

    test('무단차 경로는 계단 칩과 접근성 칩이 서로 모순되지 않는다', () {
      final display = _judgedDisplay(
        stairAccess: 'STEP_FREE',
        legs: [
          _judgedLeg(legType: 'ACCESS', stairAccess: 'STEP_FREE'),
          _judgedLeg(
            legType: 'RIDE',
            stairAccess: 'NOT_APPLICABLE',
            unknownAccessibilityCount: 1,
          ),
          _judgedLeg(legType: 'EGRESS', stairAccess: 'STEP_FREE'),
        ],
      );

      expect(display.stairAccessLabel, '계단 없는 길이에요');
      // 승차 leg의 unknownAccessibilityCount는 원자료라 "확인 필요"가 아니다.
      // 이 값을 그대로 읽으면 같은 칩 행이 "계단 없는 길이에요"와 "엘리베이터
      // 상태를 살펴봐 주세요"를 함께 내 자기모순에 빠진다(#2590).
      expect(display.accessibilityBadgeLabel, '계단 없는 경로 확인');
      expect(
        display.steps.every((step) => !step.requiresAccessibilityCheck),
        isTrue,
      );
      // 시간·거리 값이 없을 때 나오는 다른 "미확인" 문구는 이 변경의 범위 밖이라
      // 구간 줄에서는 엘리베이터 확인 안내만 본다.
      expect(
        display.steps.map((step) => step.burdenLabel),
        everyElement(isNot(contains('엘리베이터'))),
      );
    });

    test('계단으로 확인된 leg도 근거가 없으면 확인 안내를 함께 낸다', () {
      // 계단 사실과 검증 여부는 다른 축이다. 확인 필요 표기를 계단 판정에서 파생하면
      // 계단이 있고 근거도 없는 — 가장 확인이 필요한 — 조합에서 안내가 사라진다(#2590).
      final display = _judgedDisplay(
        stairAccess: 'STAIR_ONLY',
        legs: [
          _judgedLeg(
            legType: 'ACCESS',
            stairAccess: 'STAIR_ONLY',
            stairCount: 1,
            requiresAccessibilityCheck: true,
          ),
          _judgedLeg(
            legType: 'RIDE',
            stairAccess: 'NOT_APPLICABLE',
            unknownAccessibilityCount: 1,
          ),
        ],
      );

      final accessStep = display.steps.first;
      expect(accessStep.stairAccessState, 'stairOnly');
      expect(accessStep.requiresAccessibilityCheck, isTrue);
      expect(accessStep.burdenLabel, contains('계단 포함'));
      // 판정은 살아 있어도 구간 줄에 확인 안내를 적지 않는다. 그 사실은 아래 경로
      // 단위 표기가 진다.
      expect(accessStep.burdenLabel, isNot(contains('엘리베이터')));
      expect(display.stairAccessLabel, '계단 포함');
      expect(display.accessibilityBadgeLabel, '엘리베이터 상태를 살펴봐 주세요');
      // 승차 leg는 여전히 확인 대상이 아니다.
      expect(display.steps.last.requiresAccessibilityCheck, isFalse);
    });

    test('계단으로 확인되고 근거도 있는 leg에는 확인 안내를 붙이지 않는다', () {
      final display = _judgedDisplay(
        stairAccess: 'STAIR_ONLY',
        legs: [
          _judgedLeg(
            legType: 'ACCESS',
            stairAccess: 'STAIR_ONLY',
            stairCount: 1,
            requiresAccessibilityCheck: false,
          ),
          _judgedLeg(
            legType: 'RIDE',
            stairAccess: 'NOT_APPLICABLE',
            unknownAccessibilityCount: 1,
          ),
        ],
      );

      final accessStep = display.steps.first;
      expect(accessStep.requiresAccessibilityCheck, isFalse);
      expect(accessStep.burdenLabel, contains('계단 포함'));
      expect(accessStep.burdenLabel, isNot(contains('엘리베이터')));
      expect(display.stairAccessLabel, '계단 포함');
    });

    test('표시 이름을 채워 넣어도 경로 판정이 leg 폴백으로 되돌아가지 않는다', () {
      // 계단 장벽을 질 수 있는 leg가 없는 경로에서는 leg를 접어도 경로 판정을
      // 복원할 수 없다. 판정을 옮기지 않는 재구성이 있으면 여기서 표시가 실제
      // 근거보다 강해진다(#2590 C1).
      final display = _judgedDisplay(
        stairAccess: 'UNKNOWN',
        staleDataCount: 1,
        legs: [
          _judgedLeg(
            legType: 'RIDE',
            stairAccess: 'NOT_APPLICABLE',
            unknownAccessibilityCount: 1,
          ),
        ],
      );

      expect(display.stairAccessLabel, '계단 여부를 확인하고 있어요');

      final relabeled = display.withDisplayLabels(lineName: '수도권 4호선');

      expect(relabeled.stairAccess, 'UNKNOWN');
      expect(relabeled.stairAccessLabel, '계단 여부를 확인하고 있어요');
    });

    test('계단 경고가 붙은 차단 경로는 확인 중이 아니라 계단 포함이라고 말한다', () {
      // 차단 응답은 leg가 없어 접을 근거가 없지만, 계단 경고는 경로 단위 사실이라 그대로
      // 말한다. 이 경고가 언제나 관측된 계단 구간에서 오는 것은 아니다 — V1은 고신뢰 출구
      // 중 쓸 수 있는 무단차 출구를 찾지 못하면 부재 추론으로도 붙이고
      // (`RouteSearchService.hasStairOnlyAccess`), 이 테스트가 다루는 차단 경로가 바로 그
      // 갈래다. 그때의 `계단 포함`은 "계단을 확인했다"가 아니라 "무단차 출구를 찾지
      // 못했다"에 가깝지만, 표시가 근거보다 신중해지는 방향이라 정직 사다리를 거스르지
      // 않는다. 차단된 이유 자체는 별도의 사유 배지가 말한다.
      final display = _judgedDisplay(
        stairAccess: 'STAIR_ONLY',
        status: 'BLOCKED_ACCESSIBILITY',
        riskLevel: 'BLOCKED',
        legs: const [],
      );

      expect(display.isBlocked, isTrue);
      expect(display.stairAccessLabel, '계단 포함');
    });

    test('RouteSearchResult 재구성은 생성자 필드를 하나도 빠뜨리지 않는다', () {
      // C1 재발 방지: withDisplayLabels가 결과를 통째로 다시 만들기 때문에,
      // 여기 없는 필드는 온라인 결과가 화면에 닿기 전에 기본값으로 되돌아간다.
      _expectRebuildCarriesEveryField(
        source: File('lib/route_search.dart').readAsStringSync(),
        constructorSignature: 'const RouteSearchResult({',
        methodSignature: '  RouteSearchResult withDisplayLabels({',
        callSignature: 'return RouteSearchResult(',
      );
    });

    test('RouteSearchStep 재구성도 생성자 필드를 하나도 빠뜨리지 않는다', () {
      // 온라인 step도 화면에 닿기 전 이 재구성을 지난다. 같은 유실 갈래다.
      _expectRebuildCarriesEveryField(
        source: File('lib/route_search.dart').readAsStringSync(),
        constructorSignature: 'const RouteSearchStep({',
        methodSignature: '  RouteSearchStep withDisplayLabels({',
        callSignature: 'return RouteSearchStep(',
      );
    });

    test('재구성 가드의 파라미터 파서는 감싼 선언과 중첩 인자를 정확히 읽는다', () {
      // 가드가 필드를 조용히 놓치면 C1 같은 유실이 다시 통과한다. `dart format`이 긴
      // 기본값을 여러 줄로 감싸는 것이 그 갈래라 파서 자신을 고정한다.
      const parameterList = '''
    required this.sequence,
    this.wrapped =
        const RouteSearchOfficialFare(currency: 'KRW', amount: 1450),
    this.counts = const <String, int>{'a': 1, 'b': 2},
    // 주석 줄은 필드가 아니다.
    List<String> plain = const [],
    this.trailing,
''';

      expect(_namedParameters(parameterList), {
        'sequence',
        'wrapped',
        'counts',
        'plain',
        'trailing',
      });
    });

    test('화면은 leg 판정을 재계산하지 않고 백엔드 값을 그대로 쓴다', () {
      final display = _judgedDisplay(
        stairAccess: 'STEP_FREE',
        legs: [
          _judgedLeg(legType: 'ACCESS', stairAccess: 'STEP_FREE'),
          _judgedLeg(
            legType: 'RIDE',
            stairAccess: 'NOT_APPLICABLE',
            unknownAccessibilityCount: 1,
          ),
        ],
      );

      expect(display.steps.map((step) => step.stairAccessState).toList(), [
        'stepFree',
        'notApplicable',
      ]);
    });

    test('판정 필드가 없는 레거시 응답은 승차 leg 때문에 fail closed로 떨어진다', () {
      // 판정을 싣기 전 백엔드가 내던 형태 그대로다. 접근 leg는 검증돼 카운터가 모두
      // 0이지만 승차 leg의 stairAccessState="UNKNOWN"이 unknownAccessibilityCount=1로
      // 실려, leg를 접는 폴백은 무단차라 단언하지 못한다. 폴백이 경로 판정보다 강하게
      // 말할 수 없다는 뜻이며, #2590이 고치려던 증상이기도 하다.
      final display = _judgedDisplay(
        stairAccess: '',
        legs: [
          _judgedLeg(legType: 'ACCESS', stairAccess: ''),
          _judgedLeg(
            legType: 'RIDE',
            stairAccess: '',
            unknownAccessibilityCount: 1,
          ),
        ],
      );

      expect(display.stairAccessLabel, '계단 여부를 확인하고 있어요');
    });

    test('JSON 계약은 leg와 itinerary의 계단 판정을 읽고, 없으면 빈 값으로 폴백한다', () {
      final withJudgment = RouteSearchV2Itinerary.fromJson(
        _judgedItineraryJson(
          stairAccess: 'STEP_FREE',
          legStairAccess: 'NOT_APPLICABLE',
          legRequiresAccessibilityCheck: false,
        ),
      );
      expect(withJudgment.stairAccess, 'STEP_FREE');
      expect(withJudgment.legs.single.stairAccess, 'NOT_APPLICABLE');
      expect(withJudgment.legs.single.requiresAccessibilityCheck, isFalse);

      final legacy = RouteSearchV2Itinerary.fromJson(_judgedItineraryJson());
      expect(legacy.stairAccess, '');
      expect(legacy.legs.single.stairAccess, '');
      expect(legacy.legs.single.requiresAccessibilityCheck, isNull);
    });
  });
}

/// #2590 판정 필드를 실은 leg. [stairAccess]가 비면 판정 필드가 없는 레거시 응답이라
/// 확인 필요 표기도 함께 비운다.
///
/// 신뢰도 카운터를 받지 않는 이유는 leg에서 구조적으로 늘 0이기 때문이다 — 백엔드
/// leg DTO가 만드는 사유는 STAIR_ONLY_ACCESS·ACCESSIBILITY_CHECK_REQUIRED 둘뿐이고,
/// 신뢰도 경고는 경로 단위라 itinerary 쪽에만 실린다.
RouteSearchV2Leg _judgedLeg({
  required String legType,
  required String stairAccess,
  int stairCount = 0,
  int unknownAccessibilityCount = 0,
  bool? requiresAccessibilityCheck,
}) {
  final isRide = legType == 'RIDE';
  return RouteSearchV2Leg(
    legType: legType,
    fromStationId: 'station-a',
    toStationId: 'station-b',
    fromNodeId: '',
    toNodeId: '',
    lineId: 'line-4',
    tripId: isRide ? 'trip-1' : '',
    trainNo: isRide ? '4001' : '',
    plannedDepartureTime: '2026-06-30T09:17:00+09:00',
    realtimeDepartureTime: null,
    plannedArrivalTime: '2026-06-30T09:42:00+09:00',
    realtimeArrivalTime: null,
    waitTimeSeconds: 0,
    slackSeconds: 0,
    durationSeconds: 1500,
    distanceMeters: 12000,
    etaSource: 'PLANNED',
    confidence: 'MEDIUM',
    accessibilityRisk: RouteSearchV2AccessibilityRisk(
      stairCount: stairCount,
      unknownAccessibilityCount: unknownAccessibilityCount,
      generatedConnectorCount: 0,
      staleDataCount: 0,
      lowConfidenceCount: 0,
      unavailableFacilityCount: 0,
      riskLevel: 'LOW',
      reasonCodes: const [],
      level: 'LOW',
      reasons: const [],
    ),
    stairAccess: stairAccess,
    // 백엔드는 판정과 확인 필요 표기를 함께 싣는다. 따로 주지 않으면 플래너가 세우는
    // 값(계단 사실과 무관하게 근거가 없을 때만 true)을 기본으로 둔다.
    requiresAccessibilityCheck: stairAccess.isEmpty
        ? null
        : requiresAccessibilityCheck ?? stairAccess == 'UNKNOWN',
    serviceClass: isRide ? 'SUBWAY' : null,
    servicePattern: isRide ? 'LOCAL' : null,
  );
}

/// 소스에서 [signature]로 시작하는 메서드 본문. 중괄호 균형 대신 클래스 들여쓰기의
/// 닫는 줄을 찾는다 — 가드가 볼 것은 재구성 호출부뿐이다.
String _methodSource(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature를 찾지 못했다');
  final end = source.indexOf('\n  }\n', start);
  expect(end, isNonNegative, reason: '$signature의 끝을 찾지 못했다');
  return source.substring(start, end);
}

/// `이름({` 뒤부터 짝이 맞는 `}`까지. 생성자 파라미터 목록만 떼어낸다.
String _parameterList(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: '$signature를 찾지 못했다');
  var index = start + signature.length - 1;
  var depth = 1;
  while (depth > 0) {
    index += 1;
    depth += switch (source[index]) {
      '{' => 1,
      '}' => -1,
      _ => 0,
    };
  }
  return source.substring(start + signature.length, index);
}

/// 파라미터 목록에서 선언 이름을 뽑는다.
///
/// 줄 단위로 `,`로 끝나는 줄만 보면 `dart format`이 긴 기본값을 여러 줄로 감쌌을 때 그
/// 필드를 **조용히 건너뛰고**, 중첩 인자 줄을 가짜 필드로 잡을 수도 있다. 커버리지가
/// 소리 없이 줄어드는 것이 이 가드에서 가장 나쁜 고장이라, 최상위 쉼표로 잘라 조각마다
/// 이름을 뽑고 하나라도 못 뽑으면 실패시킨다.
///
/// 알려진 한계: 주석 제거가 문자열 리터럴 안의 `//`를 구분하지 않는다. Dart 파서가
/// 아니라 소스 가드이므로 그 형태가 나타나면 여기서 다뤄야 한다.
Set<String> _namedParameters(String parameterList) {
  final names = <String>{};
  for (final segment in _topLevelSegments(parameterList)) {
    final declaration = segment
        .split('\n')
        .map((line) {
          final comment = line.indexOf('//');
          return comment < 0 ? line : line.substring(0, comment);
        })
        .join(' ')
        .split('=')
        .first
        .trim()
        .replaceFirst('required ', '');
    if (declaration.isEmpty) {
      continue;
    }
    final name = declaration.startsWith('this.')
        ? declaration.substring('this.'.length)
        : declaration.split(RegExp(r'\s+')).last;
    expect(
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name),
      isTrue,
      reason: '파라미터 선언에서 이름을 뽑지 못했다: $segment',
    );
    names.add(name);
  }
  return names;
}

/// 괄호·중괄호·대괄호·꺾쇠 깊이를 세어 최상위 쉼표로만 자른다. 제네릭 인자
/// (`Map<String, int>`)와 중첩 기본값 안의 쉼표는 조각을 나누지 않는다.
List<String> _topLevelSegments(String source) {
  final segments = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  var angleDepth = 0;
  for (final character in source.split('')) {
    if (character == '(' || character == '[' || character == '{') {
      depth += 1;
    } else if (character == ')' || character == ']' || character == '}') {
      depth -= 1;
    } else if (character == '<' && depth == 0) {
      angleDepth += 1;
    } else if (character == '>' && depth == 0 && angleDepth > 0) {
      angleDepth -= 1;
    }
    if (character == ',' && depth == 0 && angleDepth == 0) {
      segments.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(character);
    }
  }
  segments.add(buffer.toString());
  return segments;
}

/// 재구성 호출이 생성자 필드를 전부, 그리고 실제 값으로 옮기는지 본다.
///
/// 이름만 세면 `field: ''` 같은 상수 대입을 통과시키고, 중첩 생성자 호출의 인자까지
/// 커버리지로 집계하면 가드가 조용히 무력해진다. 그래서 최상위 인자만 이름→값 식으로
/// 떼어내고, 값 식이 그 필드(또는 그 private 백킹 필드)나 재구성 메서드의 파라미터를
/// 참조하는지까지 본다 — 파라미터로 갈아 끼우는 것이 이 메서드의 목적이라 그 갈래는
/// 허용한다.
void _expectRebuildCarriesEveryField({
  required String source,
  required String constructorSignature,
  required String methodSignature,
  required String callSignature,
}) {
  final fields = _namedParameters(_parameterList(source, constructorSignature));
  final parameters = _namedParameters(_parameterList(source, methodSignature));
  final methodSource = _methodSource(source, methodSignature);
  final forwarded = _topLevelNamedArguments(methodSource, callSignature);

  expect(fields, isNotEmpty);
  expect(parameters, isNotEmpty);
  expect(
    fields.difference(forwarded.keys.toSet()),
    isEmpty,
    reason: '$methodSignature가 옮기지 않는 생성자 필드가 있다',
  );
  for (final field in fields) {
    final referenced = RegExp(
      r'[A-Za-z_][A-Za-z0-9_]*',
    ).allMatches(forwarded[field]!).map((match) => match.group(0)!).toSet();
    expect(
      referenced.contains(field) ||
          referenced.contains('_$field') ||
          referenced.intersection(parameters).isNotEmpty,
      isTrue,
      reason: '$methodSignature의 $field가 원래 값도 파라미터도 참조하지 않는다',
    );
  }
}

/// 호출 인자 목록에서 **최상위** named argument만 이름→값 식으로 뽑는다. 중첩 호출
/// 안의 인자는 깊이로 걸러진다.
Map<String, String> _topLevelNamedArguments(
  String source,
  String callSignature,
) {
  final start = source.indexOf(callSignature);
  expect(start, isNonNegative, reason: '$callSignature를 찾지 못했다');
  var index = start + callSignature.length;
  var depth = 1;
  final arguments = <String>[];
  final buffer = StringBuffer();
  while (depth > 0) {
    final character = source[index];
    depth += switch (character) {
      '(' || '[' || '{' => 1,
      ')' || ']' || '}' => -1,
      _ => 0,
    };
    if (depth == 0) {
      break;
    }
    if (character == ',' && depth == 1) {
      arguments.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(character);
    }
    index += 1;
  }
  arguments.add(buffer.toString());

  final named = <String, String>{};
  final pattern = RegExp(
    r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:(.*)$',
    dotAll: true,
  );
  for (final argument in arguments) {
    final match = pattern.firstMatch(argument);
    if (match != null) {
      named[match.group(1)!] = match.group(2)!;
    }
  }
  return named;
}

/// [riskLevel]은 백엔드가 원자료로 계산하는 값이라 무단차 경로에서도 승차 step의
/// `stairAccessState="UNKNOWN"` 때문에 `MEDIUM`이 된다. 판정과 별개 축임을 픽스처에
/// 그대로 담는다.
RouteSearchResult _judgedDisplay({
  required String stairAccess,
  required List<RouteSearchV2Leg> legs,
  int staleDataCount = 0,
  int lowConfidenceCount = 0,
  String riskLevel = 'MEDIUM',
  String status = 'FOUND',
}) {
  final itinerary = RouteSearchV2Itinerary(
    itineraryId: 'route-judged',
    status: status,
    plannedArrivalTime: '2026-06-30T09:42:00+09:00',
    realtimeArrivalTime: null,
    etaSource: 'PLANNED',
    etaConfidence: 'MEDIUM',
    durationSeconds: 1620,
    transferCount: 0,
    walkingDistanceMeters: 80,
    accessibilityRisk: RouteSearchV2AccessibilityRisk(
      stairCount: 0,
      unknownAccessibilityCount: 0,
      generatedConnectorCount: 0,
      staleDataCount: staleDataCount,
      lowConfidenceCount: lowConfidenceCount,
      unavailableFacilityCount: 0,
      riskLevel: riskLevel,
      reasonCodes: const [],
      level: 'LOW',
      reasons: const [],
    ),
    legs: legs,
    commercialEtaEligible: false,
    stairAccess: stairAccess,
  );
  return RouteSearchResult.fromV2(
    _objectiveResult([itinerary]),
    objective: RouteObjective.fastest,
  );
}

Map<String, Object?> _judgedItineraryJson({
  String? stairAccess,
  String? legStairAccess,
  bool? legRequiresAccessibilityCheck,
}) {
  final leg = _rideLegJson();
  if (legStairAccess != null) {
    leg['stairAccess'] = legStairAccess;
  }
  if (legRequiresAccessibilityCheck != null) {
    leg['requiresAccessibilityCheck'] = legRequiresAccessibilityCheck;
  }
  return <String, Object?>{
    'itineraryId': 'route-judged',
    'status': 'FOUND',
    'plannedArrivalTime': '2026-06-30T09:42:00+09:00',
    'realtimeArrivalTime': null,
    'etaSource': 'PLANNED',
    'etaConfidence': 'MEDIUM',
    'durationSeconds': 1620,
    'transferCount': 0,
    'walkingDistanceMeters': 80,
    'accessibilityRisk': <String, Object?>{
      'stairCount': 0,
      'unknownAccessibilityCount': 0,
      'generatedConnectorCount': 0,
      'staleDataCount': 0,
      'lowConfidenceCount': 0,
      'unavailableFacilityCount': 0,
      'riskLevel': 'LOW',
      'reasonCodes': <String>[],
      'level': 'LOW',
      'reasons': <String>[],
    },
    'legs': <Object?>[leg],
    'commercialEtaEligible': false,
    'stairAccess': ?stairAccess,
  };
}

class _ManualRouteSearchRepository implements RouteSearchRepository {
  final requests = <RouteSearchRequest>[];
  final completers = <RouteObjective, Completer<RouteSearchResult>>{};

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) {
    requests.add(request);
    final completer = Completer<RouteSearchResult>();
    completers[request.objective] = completer;
    return completer.future;
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) {
    throw UnimplementedError();
  }
}

RouteSearchResult _routeResult(String routeSearchId) {
  return RouteSearchResult(
    routeSearchId: routeSearchId,
    originStationId: 'station-a',
    originStationName: '상록수',
    destinationStationId: 'station-b',
    destinationStationName: '사당',
    mobilityType: 'STANDARD',
    constraintMode: 'PREFER_STEP_FREE',
    status: 'FOUND',
    lineId: 'seoul-4',
    lineName: '수도권 4호선',
    score: 90,
    burdenCost: 90,
    steps: const [],
    warnings: const [],
    recommendationReasons: const [],
    blockedReasons: const [],
    createdAt: '2026-06-30T09:15:00+09:00',
  );
}

Map<String, Object?> _rideLegJson({
  String legType = 'RIDE',
  Object? serviceClass = 'SUBWAY',
  Object? servicePattern = 'LOCAL',
}) {
  return <String, Object?>{
    'legType': legType,
    'fromStationId': 'station-a',
    'toStationId': 'station-b',
    'fromNodeId': '',
    'toNodeId': '',
    'lineId': 'line-4',
    'tripId': 'trip-1',
    'trainNo': '4001',
    'plannedDepartureTime': '2026-06-30T09:17:00+09:00',
    'realtimeDepartureTime': null,
    'plannedArrivalTime': '2026-06-30T09:42:00+09:00',
    'realtimeArrivalTime': null,
    'waitTimeSeconds': 0,
    'slackSeconds': 0,
    'durationSeconds': 1500,
    'distanceMeters': 12000,
    'etaSource': 'PLANNED',
    'confidence': 'MEDIUM',
    'accessibilityRisk': <String, Object?>{
      'stairCount': 0,
      'unknownAccessibilityCount': 0,
      'generatedConnectorCount': 0,
      'staleDataCount': 0,
      'lowConfidenceCount': 0,
      'unavailableFacilityCount': 0,
      'riskLevel': 'LOW',
      'reasonCodes': <String>[],
      'level': 'LOW',
      'reasons': <String>[],
    },
    'serviceClass': serviceClass,
    'servicePattern': servicePattern,
  };
}

/// 실응답에서 승차 leg는 `stairAccessState = "UNKNOWN"`이라 leg DTO의
/// `unknownAccessibilityCount`가 1이다(`AccessibilityRiskDto.from(RouteStep)`).
/// 그 조합을 만들 수 있도록 카운터도 인자로 받는다.
RouteSearchV2Itinerary _taggedItinerary({
  required String lineId,
  required List<String> objectiveTags,
  int stairCount = 0,
  int unknownAccessibilityCount = 0,
  List<String> reasonCodes = const [],
}) {
  final risk = RouteSearchV2AccessibilityRisk(
    stairCount: stairCount,
    unknownAccessibilityCount: unknownAccessibilityCount,
    generatedConnectorCount: 0,
    staleDataCount: 0,
    lowConfidenceCount: 0,
    unavailableFacilityCount: 0,
    riskLevel: 'LOW',
    reasonCodes: reasonCodes,
    level: 'LOW',
    reasons: reasonCodes,
  );
  return RouteSearchV2Itinerary(
    itineraryId: 'route-$lineId-primary',
    status: 'FOUND',
    plannedArrivalTime: '2026-06-30T09:42:00+09:00',
    realtimeArrivalTime: null,
    etaSource: 'PLANNED',
    etaConfidence: 'MEDIUM',
    durationSeconds: 1620,
    transferCount: 0,
    walkingDistanceMeters: 80,
    accessibilityRisk: risk,
    commercialEtaEligible: false,
    objectiveTags: objectiveTags,
    legs: [
      RouteSearchV2Leg(
        legType: 'RIDE',
        fromStationId: 'station-a',
        toStationId: 'station-b',
        fromNodeId: '',
        toNodeId: '',
        lineId: lineId,
        tripId: 'trip-1',
        trainNo: '4001',
        plannedDepartureTime: '2026-06-30T09:17:00+09:00',
        realtimeDepartureTime: null,
        plannedArrivalTime: '2026-06-30T09:42:00+09:00',
        realtimeArrivalTime: null,
        waitTimeSeconds: 60,
        slackSeconds: 0,
        durationSeconds: 1500,
        distanceMeters: 12000,
        etaSource: 'PLANNED',
        confidence: 'MEDIUM',
        accessibilityRisk: risk,
        serviceClass: 'SUBWAY',
        servicePattern: 'LOCAL',
      ),
    ],
  );
}

RouteSearchV2Result _objectiveResult(List<RouteSearchV2Itinerary> itineraries) {
  return RouteSearchV2Result(
    contractVersion: 'ROUTE_SEARCH_V2',
    originStationId: 'station-a',
    destinationStationId: 'station-b',
    departureTime: '2026-06-30T09:15:00+09:00',
    mobilityType: 'STANDARD',
    constraintMode: 'PREFER_STEP_FREE',
    useRealtime: true,
    maxTransfers: 3,
    alternativeCount: 3,
    statuses: const ['FOUND'],
    itineraries: itineraries,
  );
}

class FakeRouteSearchRepository implements RouteSearchRepository {
  final requests = <RouteSearchRequest>[];
  final refreshRouteSearchIds = <String>[];
  Object? error;
  RouteSearchResult searchResult = _sampleRouteSearchResult();
  Completer<RouteRefreshResult>? pendingRefresh;
  RouteRefreshResult? refreshResult;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    requests.add(request);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return searchResult;
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) async {
    refreshRouteSearchIds.add(routeSearchId);
    final pending = pendingRefresh;
    if (pending != null) {
      return pending.future;
    }
    return refreshResult ??
        RouteRefreshResult(
          routeSearchId: routeSearchId,
          status: 'UNCHANGED',
          result: searchResult,
          refreshedAt: '2026-07-01T15:30:00',
          etaSource: 'PLANNED',
          etaConfidence: 'MEDIUM',
          sourceLabel: '계획 시간 기준',
        );
  }
}

class PendingRouteSearchRepository implements RouteSearchRepository {
  final _completer = Completer<RouteSearchResult>();

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) =>
      _completer.future;

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) {
    throw UnimplementedError();
  }

  void complete(RouteSearchResult result) {
    _completer.complete(result);
  }
}

RouteSearchResult _sampleRouteSearchResult({
  String routeSearchId = 'route-1',
  String status = 'FOUND',
  String constraintMode = 'PREFER_STEP_FREE',
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
  List<RouteSearchWarning> warnings = const [
    RouteSearchWarning(
      code: 'LOW_DATA_CONFIDENCE',
      message: '일부 시설 안내는 아직 확인되지 않았어요.',
    ),
  ],
  List<String> blockedReasons = const [],
  String etaSource = '',
  String etaConfidence = '',
  String accessibilityRiskLevel = '',
  int? transferSlackSeconds,
  bool hasOutOfStationTransfer = false,
  RouteObjective objective = RouteObjective.fastest,
}) {
  return RouteSearchResult(
    routeSearchId: routeSearchId,
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-sadang',
    destinationStationName: '사당',
    mobilityType: 'SENIOR',
    constraintMode: constraintMode,
    status: status,
    lineId: 'seoul-4',
    lineName: '수도권 4호선',
    score: 92,
    steps: steps,
    warnings: warnings,
    recommendationReasons: recommendationReasons,
    blockedReasons: blockedReasons,
    createdAt: '2026-06-13T04:20:00',
    etaSource: etaSource,
    etaConfidence: etaConfidence,
    accessibilityRiskLevel: accessibilityRiskLevel,
    transferSlackSeconds: transferSlackSeconds,
    hasOutOfStationTransfer: hasOutOfStationTransfer,
    objective: objective,
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
