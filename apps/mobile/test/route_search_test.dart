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
    expect(
      result.steps.single.burdenLabel,
      '약 1분 15초 · 28m · 최근 확인한 기록이 없어요 · 엘리베이터를 이용해요',
    );
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
                  'message': '일부 시설 안내를 준비 중이에요.',
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
    expect(result.steps.first.metricSourceLabel, '시간 또는 거리를 확인하고 있어요');
    expect(result.steps.first.estimatedMinutes, 4);
    expect(result.steps.first.distanceMeters, 180);
    expect(result.steps.first.stepType, 'entry');
    expect(result.steps.first.includesStairs, isFalse);
    expect(result.steps.first.requiresAccessibilityCheck, isTrue);
    expect(result.steps.first.burdenLabel, '약 4분 · 180m · 엘리베이터 안내 준비 중');
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
    expect(result.semanticLabel, contains('시간 또는 거리를 확인하고 있어요'));
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

  test('경로 검색 결과는 확인 필요 상태를 이동 가능으로 안내하지 않는다', () {
    final result = _sampleRouteSearchResult(status: 'REVIEW_REQUIRED');

    expect(result.statusLabel, '경로 상태를 아직 알 수 없어요');
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
    expect(result.statusLabel, '경로 상태를 아직 알 수 없어요');
    expect(result.guidanceLabel, '확인 후 이동');
    expect(result.guidanceIcon, Icons.warning_amber);
    expect(result.needsConfirmation, isTrue);
    expect(result.attentionLabel, '살펴볼 내용');
    expect(result.semanticLabel, contains('살펴볼 내용 길이 이어지는지 아직 확인하지 못했어요.'));
    expect(result.semanticLabel, isNot(contains('안내 불가 이유')));
    expect(result.semanticLabel, isNot(contains('다음 행동')));
  });

  test('경로 검색 UNKNOWN localized reason은 구체 안내 문구를 유지한다', () {
    final result = _sampleRouteSearchResult(
      status: 'UNKNOWN',
      blockedReasons: const ['경로 연결 정보를 확인할 수 없습니다.'],
    );

    expect(result.isBlocked, isFalse);
    expect(result.blockedReasonLabels, ['길이 이어지는지 아직 확인하지 못했어요.']);
    expect(result.semanticLabel, contains('길이 이어지는지 아직 확인하지 못했어요.'));
  });

  test('경로 검색 localized reason은 쉬운 문구를 generic으로 바꾸지 않는다', () {
    final result = _sampleRouteSearchResult(
      status: 'BLOCKED',
      blockedReasons: const ['꼭 필요한 시설을 지금 이용하기 어려워요.'],
    );

    expect(result.blockedReasonLabels, ['꼭 필요한 시설을 지금 이용하기 어려워요.']);
    expect(result.semanticLabel, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
    expect(result.semanticLabel, contains('이동 전 살펴보기'));
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

    expect(result.warnings.single.userMessage, '일부 이동 정보를 확인하지 못했어요.');
    expect(result.semanticLabel, contains('일부 이동 정보를 확인하지 못했어요.'));
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
          'transferCount': 0,
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
    expect(result.itineraries.first.legs.single.legType, 'ACCESS');
    expect(
      result.itineraries.first.legs.single.accessibilityRisk.riskLevel,
      'HIGH',
    );
    expect(result.itineraries.first.legs.single.waitTimeSeconds, 0);
    expect(result.itineraries.first.legs.single.slackSeconds, 0);
    expect(result.itineraries.first.legs.single.etaSource, 'STATIC_BACKEND_V1');
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

    expect(step.burdenLabel, '약 30분 · 거리를 확인하고 있어요');
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

    expect(step.burdenLabel, '시간을 확인하고 있어요 · 180m');
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

    expect(result.stairAccessLabel, '계단 여부를 아직 알 수 없어요');
    expect(result.semanticLabel, contains('계단 여부를 아직 알 수 없어요'));
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
    expect(saved.mobilityLabel, '천천히 이동');
    expect(saved.scoreLabel, '다시 찾으면 자세히 볼 수 있어요');
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
  List<RouteSearchWarning> warnings = const [
    RouteSearchWarning(
      code: 'LOW_DATA_CONFIDENCE',
      message: '일부 시설 안내를 준비 중이에요.',
    ),
  ],
  List<String> blockedReasons = const [],
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
    warnings: warnings,
    recommendationReasons: recommendationReasons,
    blockedReasons: blockedReasons,
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
