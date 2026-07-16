import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/features/routes/application/network_graph.dart'
    as graph;
import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/features/fare/official_od_fare_quote.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_route_mapping.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('흡수된 station ID는 대표 station ID로 정규화해 경로를 검색한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sangnoksu', 'station-sangnoksu-old', 'station-sangnoksu-old')
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu-old',
            destinationStationId: 'station-sadang',
            mobilityType: 'STANDARD',
          ),
        );

    expect(result.status, 'FOUND');
    expect(result.originStationId, 'station-sangnoksu');
  });

  test('로컬 경로는 exact official OD 요금을 함께 반환한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO official_od_fare_quotes (
        origin_station_id, destination_station_id, source_id, snapshot_id,
        mapping_ledger_hash, gnrl_card_fare, gnrl_cash_fare,
        yung_card_fare, yung_cash_fare, child_card_fare, child_cash_fare
      ) VALUES (
        'station-sangnoksu', 'station-sadang',
        '$approvedOfficialOdFareSourceId', '$approvedOfficialOdFareSnapshotId',
        '$approvedOfficialOdFareMappingLedgerHash', 1550, 1650, 800, 900, 500, 500
      )
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    final quote = result.officialOdFareQuote;
    expect(quote, isNotNull);
    expect(result.hasOfficialOdFareQuote, isTrue);
    expect(quote!.gnrlCardFare, 1550);
    expect(quote.gnrlCashFare, 1650);
    expect(quote.yungCardFare, 800);
    expect(quote.yungCashFare, 900);
    expect(quote.childCardFare, 500);
    expect(quote.childCashFare, 500);
  });

  test(
    'catalog DB가 있으면 offline/local fallback repository는 API 주소 없이 로컬 결과를 반환한다',
    () async {
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await database.seedBaselineIfEmpty();

      final dependencies = AppDependencies.resolve(
        catalogDatabase: database,
        reportRepository: const UnavailableFacilityReportRepository(),
        apiBaseUri: () {
          throw StateError('Local route defaults must not read API base URL.');
        },
        enablePushNotifications: false,
      );

      final routeResult = await dependencies.routeRepository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: 'WHEELCHAIR',
        ),
      );
      final internalNodes = await dependencies.internalRouteRepository
          .listRouteNodes('station-sangnoksu');

      expect(routeResult.status, 'FOUND');
      expect(routeResult.isLocalResult, isTrue);
      expect(internalNodes, isEmpty);
    },
  );

  test('offline 로컬 경로는 STANDARD 프리셋 대표 이동 유형을 지원한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'STANDARD',
          ),
        );

    // STANDARD는 senior로 폴백해 계단 회피 없는 표준 보행(preferStepFree)으로 안내된다.
    expect(result.status, 'FOUND');
    expect(result.isLocalResult, isTrue);
  });

  test(
    'online-first repository는 flag가 켜지면 V2 backend itinerary를 우선 사용한다',
    () async {
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await database.seedBaselineIfEmpty();
      await database.customStatement('''
        INSERT INTO official_od_fare_quotes (
          origin_station_id, destination_station_id, source_id, snapshot_id,
          mapping_ledger_hash, gnrl_card_fare, gnrl_cash_fare,
          yung_card_fare, yung_cash_fare, child_card_fare, child_cash_fare
        ) VALUES (
          'station-sangnoksu', 'station-sadang',
          '$approvedOfficialOdFareSourceId', '$approvedOfficialOdFareSnapshotId',
          '$approvedOfficialOdFareMappingLedgerHash', 1550, 1650, 800, 900, 500, 500
        )
      ''');
      final requestedPaths = <String>[];
      final requestedBodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        requestedPaths.add(request.uri.path);
        final requestBody = await utf8.decoder.bind(request).join();
        requestedBodies.add(jsonDecode(requestBody) as Map<String, Object?>);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/refresh')) {
          request.response.write(
            jsonEncode({'success': true, 'data': _routeRefreshPayload()}),
          );
        } else {
          request.response.write(
            jsonEncode({'success': true, 'data': _routeV2Payload()}),
          );
        }
        await request.response.close();
      });

      final dependencies = AppDependencies.resolve(
        catalogDatabase: database,
        reportRepository: const UnavailableFacilityReportRepository(),
        apiBaseUri: () =>
            Uri.parse('http://${server.address.host}:${server.port}'),
        enablePushNotifications: false,
        enableRouteV2OnlineFirst: true,
      );

      final result = await dependencies.routeRepository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: 'WHEELCHAIR',
          mobilityPreset: 'STEP_FREE',
        ),
      );

      expect(requestedPaths, ['/api/v2/routes/search']);
      expect(requestedBodies.single, containsPair('useRealtime', true));
      expect(requestedBodies.single, containsPair('maxTransfers', 3));
      expect(requestedBodies.single, containsPair('alternativeCount', 3));
      // 프리셋은 v2 body에 실리고, mobilityType은 하위호환으로 함께 전송된다.
      expect(
        requestedBodies.single,
        containsPair('mobilityPreset', 'STEP_FREE'),
      );
      expect(
        requestedBodies.single,
        containsPair('mobilityType', 'WHEELCHAIR'),
      );
      expect(requestedBodies.single['departureTime'], isA<String>());
      expect(result.routeSearchId, 'route-v2');
      expect(result.originStationName, '상록수');
      expect(result.destinationStationName, '사당');
      expect(result.lineName, '수도권 4호선');
      expect(result.steps, hasLength(2));
      expect(result.steps.first.title, '상록수 승강장 접근');
      expect(result.steps.first.actionTitle, isEmpty);
      expect(result.steps.first.actionDetail, '상록수 승강장 접근 동선을 확인합니다.');
      expect(result.steps.last.title, isNot(contains('station-')));
      expect(
        result.steps.last.plannedArrivalTimeIso,
        '2026-07-01T09:15:00+09:00',
      );
      expect(
        result.steps.last.realtimeArrivalTimeIso,
        '2026-07-01T09:13:00+09:00',
      );
      expect(result.etaSource, 'REALTIME');
      expect(result.isLocalResult, isFalse);
      expect(result.hasOfficialOdFareQuote, isTrue);
      expect(result.officialOdFareQuote!.gnrlCardFare, 1550);
      expect(result.officialOdFareQuote!.gnrlCashFare, 1650);
      expect(result.officialOdFareQuote!.yungCardFare, 800);
      expect(result.officialOdFareQuote!.yungCashFare, 900);
      expect(result.officialOdFareQuote!.childCardFare, 500);
      expect(result.officialOdFareQuote!.childCashFare, 500);

      final refresh = await dependencies.routeRepository.refreshRoute(
        result.routeSearchId,
      );

      expect(requestedPaths, [
        '/api/v2/routes/search',
        '/api/v2/routes/route-v2/refresh',
      ]);
      expect(refresh.routeSearchId, 'route-v2');
      expect(refresh.result.hasOfficialOdFareQuote, isTrue);
      expect(refresh.result.officialOdFareQuote!.gnrlCardFare, 1550);
      expect(refresh.result.officialOdFareQuote!.gnrlCashFare, 1650);
    },
  );

  test('V2 blocked itinerary는 기존 blocked UI 상태로 정규화된다', () {
    final result = RouteSearchResult.fromV2(
      RouteSearchV2Result.fromJson(
        _routeV2Payload(
          status: 'BLOCKED_ACCESSIBILITY',
          reasonCodes: const ['BLOCKED_ACCESSIBILITY'],
        ),
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.isBlocked, isTrue);
    expect(result.blockedReasons, ['BLOCKED_ACCESSIBILITY']);
  });

  test(
    'online-first backend 5xx는 catalog가 있어도 local route로 대체하지 않는다',
    () async {
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await database.seedBaselineIfEmpty();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'success': false}));
        await request.response.close();
      });
      final metrics = RouteSearchOnlineFirstMetrics();

      final dependencies = AppDependencies.resolve(
        catalogDatabase: database,
        reportRepository: const UnavailableFacilityReportRepository(),
        apiBaseUri: () =>
            Uri.parse('http://${server.address.host}:${server.port}'),
        enablePushNotifications: false,
        enableRouteV2OnlineFirst: true,
        routeSearchOnlineFirstMetrics: metrics,
      );

      await expectLater(
        dependencies.routeRepository.searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        ),
        throwsA(
          isA<RouteSearchOnlineException>()
              .having(
                (error) => error.message,
                'message',
                '실시간/서버 경로를 확인하지 못했어요.',
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('저장된 데이터')),
              ),
        ),
      );

      expect(metrics.onlineSuccessCount, 0);
      expect(metrics.onlineFailureCount, 1);
      expect(metrics.onlineFailureReasonCounts, {'backend-5xx': 1});
    },
  );

  test(
    'online-first backend 404는 catalog가 있어도 local route로 대체하지 않는다',
    () async {
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await database.seedBaselineIfEmpty();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'success': false}));
        await request.response.close();
      });
      final metrics = RouteSearchOnlineFirstMetrics();

      final dependencies = AppDependencies.resolve(
        catalogDatabase: database,
        reportRepository: const UnavailableFacilityReportRepository(),
        apiBaseUri: () =>
            Uri.parse('http://${server.address.host}:${server.port}'),
        enablePushNotifications: false,
        enableRouteV2OnlineFirst: true,
        routeSearchOnlineFirstMetrics: metrics,
      );

      await expectLater(
        dependencies.routeRepository.searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        ),
        throwsA(
          isA<RouteSearchOnlineException>()
              .having(
                (error) => error.message,
                'message',
                '실시간/서버 경로를 확인하지 못했어요.',
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('저장된 데이터')),
              ),
        ),
      );

      expect(metrics.onlineSuccessCount, 0);
      expect(metrics.onlineFailureCount, 1);
      expect(metrics.onlineFailureReasonCounts, {'backend-4xx': 1});
    },
  );

  test('online-first backend 4xx validation은 local route로 숨기지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false}));
      await request.response.close();
    });
    final metrics = RouteSearchOnlineFirstMetrics();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: database,
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () =>
          Uri.parse('http://${server.address.host}:${server.port}'),
      enablePushNotifications: false,
      enableRouteV2OnlineFirst: true,
      routeSearchOnlineFirstMetrics: metrics,
    );

    await expectLater(
      dependencies.routeRepository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: 'WHEELCHAIR',
        ),
      ),
      throwsA(
        isA<RouteSearchOnlineException>()
            .having(
              (error) => error.message,
              'message',
              '실시간/서버 경로를 확인하지 못했어요.',
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('저장된 데이터')),
            ),
      ),
    );
    expect(metrics.onlineSuccessCount, 0);
    expect(metrics.onlineFailureCount, 1);
    expect(metrics.onlineFailureReasonCounts, {'backend-4xx': 1});
  });

  test('online-first 예상 밖 HTTP status는 local route로 숨기지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.notModified
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false}));
      await request.response.close();
    });
    final metrics = RouteSearchOnlineFirstMetrics();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: database,
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () =>
          Uri.parse('http://${server.address.host}:${server.port}'),
      enablePushNotifications: false,
      enableRouteV2OnlineFirst: true,
      routeSearchOnlineFirstMetrics: metrics,
    );

    await expectLater(
      dependencies.routeRepository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: 'WHEELCHAIR',
        ),
      ),
      throwsA(isA<RouteSearchException>()),
    );
    expect(metrics.onlineSuccessCount, 0);
    expect(metrics.onlineFailureCount, 1);
    expect(metrics.onlineFailureReasonCounts, {'backend-unexpected': 1});
  });

  test('로컬 경로 repository는 baseline catalog에서 상록수-사당 경로를 계산한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();

    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.originStationName, '상록수');
    expect(result.destinationStationName, '사당');
    expect(result.lineId, 'seoul-4');
    expect(result.lineName, '수도권 4호선');
    expect(result.isLocalResult, isTrue);
    expect(result.score, inInclusiveRange(0, 100));
    expect(result.burdenCost, greaterThan(result.score));
    // WHEELCHAIR는 STEP_FREE 프리셋이라 총 소요시간은 스텝 표시분 합에 경로당
    // 1회 승강기 대기(60초)가 더해진 값이다.
    expect(
      result.estimatedDurationSeconds,
      result.steps.fold<int>(
            0,
            (sum, step) => sum + step.estimatedMinutes * 60,
          ) +
          MobilityProfilePolicy.stepFreeElevatorWaitSeconds,
    );
    expect(
      result.walkingDistanceMeters,
      result.steps
          .where((step) => step.isWalkingStep)
          .fold<int>(0, (sum, step) => sum + step.distanceMeters),
    );
    expect(result.transferCount, 0);
    expect(result.evidenceSummary, contains('DURATION_ESTIMATED'));
    expect(result.evidenceSummary, contains('DISTANCE_UNKNOWN'));
    expect(result.etaSource, 'STATIC_LOCAL');
    expect(result.sourceNotice, contains('저장된 데이터 기준'));
    expect(result.sourceNotice, contains('최근 확인 2026-06-19'));
    expect(result.sourceNotice, isNot(contains('실시간')));
    expect(result.sourceNotice, isNot(contains('시간표')));
    expect(
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'seoul-4'},
    );
    expect(result.blockedReasons, isEmpty);
  });

  test('로컬 경로는 현재 이후 공식 시간표의 ride 도착시각을 노출한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedBaselineTimetable(database);
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-10T07:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final ride = result.steps.singleWhere((step) => step.stepType == 'ride');
    expect(ride.plannedArrivalTimeIso, '2026-07-10T08:12:00+09:00');
    expect(result.etaSource, 'STATIC_LOCAL');
  });

  test('Mobile 로컬 planner는 ITX topology를 직접 소비하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _insertVerifiedNetworkEdge(
      database,
      id: 'itx-edge-a-b',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-b:line-test',
      edgeType: 'RIDE',
      durationSeconds: 60,
      servicePattern: 'EXPRESS',
    );

    final subwayResult = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-a',
            destinationStationId: 'station-b',
            mobilityType: 'WHEELCHAIR',
          ),
        );
    expect(subwayResult.status, 'FOUND');

    await database.customStatement('''
      UPDATE network_edges
      SET service_class = 'ITX_CHEONGCHUN'
      WHERE id = 'itx-edge-a-b'
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-a',
            destinationStationId: 'station-b',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    expect(result.status, isNot('FOUND'));
    expect(
      result.steps.expand((step) => step.evidenceSources),
      isNot(contains('edge:itx-edge-a-b')),
    );
  });

  test('Mobile 로컬 planner는 ITX timetable row를 직접 소비하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _insertVerifiedNetworkEdge(
      database,
      id: 'subway-edge-a-b',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-b:line-test',
      edgeType: 'RIDE',
      durationSeconds: 600,
      servicePattern: 'EXPRESS',
    );
    await database.customStatement('''
      INSERT INTO service_calendars (
        service_id, monday, tuesday, wednesday, thursday, friday,
        saturday, sunday, start_date, end_date
      ) VALUES (
        'itx-weekday', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231'
      )
    ''');
    await database.customStatement('''
      INSERT INTO transit_routes (id, line_id, route_short_name)
      VALUES ('itx-route', 'line-test', 'ITX-청춘')
    ''');
    await database.customStatement('''
      INSERT INTO transit_trips (
        id, route_id, service_id, service_pattern, service_class
      ) VALUES (
        'itx-trip', 'itx-route', 'itx-weekday', 'EXPRESS', 'ITX_CHEONGCHUN'
      )
    ''');
    await database.customStatement('''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id,
        arrival_seconds, departure_seconds
      ) VALUES
        ('itx-trip', 1, 'station-a', 'line-test', 28770, 28800),
        ('itx-trip', 2, 'station-b', 'line-test', 29400, 29430)
    ''');
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-10T07:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final ride = result.steps.singleWhere((step) => step.stepType == 'ride');
    expect(result.status, 'FOUND');
    expect(ride.plannedArrivalTimeIso, isEmpty);
  });

  test('SLOW 프리셋은 보행 스텝 시간을 늘리고 ride 스텝은 그대로 둔다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = LocalRouteRepository(catalogDatabase: database);

    final standard = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'STANDARD',
      ),
    );
    final slow = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'SENIOR',
      ),
    );

    expect(standard.status, 'FOUND');
    expect(slow.status, 'FOUND');

    // SLOW(speedFactor 1.35)는 보행 성분 시간을 늘려 총 소요시간이 STANDARD보다 크다.
    expect(
      slow.estimatedDurationSeconds,
      greaterThan(standard.estimatedDurationSeconds),
    );

    // ride 스텝은 실제 시간표 기반이라 프리셋과 무관하게 동일해야 한다.
    final standardRide = standard.steps.singleWhere(
      (step) => step.stepType == 'ride',
    );
    final slowRide = slow.steps.singleWhere((step) => step.stepType == 'ride');
    expect(slowRide.estimatedMinutes, standardRide.estimatedMinutes);

    // 보행 스텝(ride 제외)의 표시분 합은 SLOW가 STANDARD 이상이어야 한다.
    int walkingMinutes(RouteSearchResult result) => result.steps
        .where((step) => step.stepType != 'ride')
        .fold<int>(0, (sum, step) => sum + step.estimatedMinutes);
    expect(walkingMinutes(slow), greaterThan(walkingMinutes(standard)));
  });

  test('STEP_FREE 프리셋은 STANDARD 대비 승강기 대기 60초만 더한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = LocalRouteRepository(catalogDatabase: database);

    final standard = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'STANDARD',
      ),
    );
    final stepFree = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(standard.status, 'FOUND');
    expect(stepFree.status, 'FOUND');

    // STEP_FREE는 speedFactor 1.0이라 보행 스텝 표시분 자체는 STANDARD와 동일하고,
    // 경로당 1회 승강기 대기(60초)만 총 소요시간에 가산된다.
    expect(
      stepFree.steps.map((step) => step.estimatedMinutes).toList(),
      standard.steps.map((step) => step.estimatedMinutes).toList(),
    );
    expect(
      stepFree.estimatedDurationSeconds - standard.estimatedDurationSeconds,
      MobilityProfilePolicy.stepFreeElevatorWaitSeconds,
    );
  });

  test('연속된 동일 노선·패턴 ride는 양 끝을 포함하는 한 trip과 도착 알림 하나로 묶는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedConsecutiveRideRoute(database);
    await _seedConsecutiveRideTimetable(database);
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-10T07:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final rides = result.steps
        .where((step) => step.stepType == 'ride')
        .toList(growable: false);
    expect(rides, hasLength(1));
    expect(rides.single.fromStationId, 'station-a');
    expect(rides.single.toStationId, 'station-c');
    expect(rides.single.plannedArrivalTimeIso, '2026-07-10T08:12:00+09:00');

    final alarmStops = getOffAlarmStopsFromRideLegs(
      rideLegs: [
        for (final ride in rides)
          RideLegArrival(
            toStationId: ride.toStationId,
            plannedArrivalIso: ride.plannedArrivalTimeIso,
          ),
      ],
      stationName: (stationId) => stationId,
      source: GetOffAlarmTimeSource.planned,
    );
    expect(alarmStops, hasLength(1));
    expect(alarmStops.single.stationId, 'station-c');
    expect(alarmStops.single.kind, GetOffAlarmKind.destination);
  });

  test('출발 초보다 500ms 늦은 cursor는 이미 출발한 trip을 건너뛴다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedBaselineTimetable(database);
    await database.customStatement('''
      UPDATE network_edges
      SET duration_seconds = 0
      WHERE id = 'entry-sangnoksu-seoul-4'
    ''');
    await _insertBaselineTrip(
      database,
      tripId: 'trip-after-fractional-cursor',
      departureSeconds: 28980,
      arrivalSeconds: 29700,
    );
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-10T08:00:30.500+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final ride = result.steps.singleWhere((step) => step.stepType == 'ride');
    expect(ride.plannedArrivalTimeIso, '2026-07-10T08:15:00+09:00');
  });

  test('운행 제외일은 건너뛰고 7일 범위의 다음 활성 서비스를 선택한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedBaselineTimetable(database);
    await database.customStatement('''
      INSERT INTO service_calendar_dates (service_id, date, exception_type)
      VALUES ('weekday-service', '20260710', 2)
    ''');
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-10T07:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final ride = result.steps.singleWhere((step) => step.stepType == 'ride');
    expect(ride.plannedArrivalTimeIso, '2026-07-13T08:12:00+09:00');
  });

  test('주말에 추가된 예외 서비스를 활성 운행으로 선택한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedBaselineTimetable(database);
    await database.customStatement('''
      INSERT INTO service_calendar_dates (service_id, date, exception_type)
      VALUES ('weekday-service', '20260711', 1)
    ''');
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-11T07:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final ride = result.steps.singleWhere((step) => step.stepType == 'ride');
    expect(ride.plannedArrivalTimeIso, '2026-07-11T08:12:00+09:00');
  });

  test('03:00 이전은 전일 service day의 24시간 초과 시간표를 사용한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedBaselineTimetable(database);
    await database.customStatement('''
      UPDATE transit_stop_times
      SET arrival_seconds = CASE stop_sequence WHEN 1 THEN 93600 ELSE 94320 END,
          departure_seconds = CASE stop_sequence WHEN 1 THEN 93630 ELSE 94350 END
      WHERE trip_id = 'trip-seoul-4-sangnoksu-sadang'
    ''');
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-11T01:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final ride = result.steps.singleWhere((step) => step.stepType == 'ride');
    expect(ride.plannedArrivalTimeIso, '2026-07-11T02:12:00+09:00');
  });

  test('pickup·drop-off 금지 trip을 건너뛰고 다음 승하차 가능 trip을 선택한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedBaselineTimetable(database);
    await database.customStatement('''
      UPDATE transit_stop_times
      SET pickup_type = 1
      WHERE trip_id = 'trip-seoul-4-sangnoksu-sadang' AND stop_sequence = 1
    ''');
    await _insertBaselineTrip(
      database,
      tripId: 'trip-drop-off-blocked',
      departureSeconds: 28950,
      arrivalSeconds: 29640,
      dropOffType: 1,
    );
    await _insertBaselineTrip(
      database,
      tripId: 'trip-boardable',
      departureSeconds: 29070,
      arrivalSeconds: 29760,
    );
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-10T07:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final ride = result.steps.singleWhere((step) => step.stepType == 'ride');
    expect(ride.plannedArrivalTimeIso, '2026-07-10T08:16:00+09:00');
  });

  test('다중 ride는 이전 도착과 환승 시간 이후의 다음 trip을 순차 선택한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedTwoLegRoute(database);
    await _seedTwoLegTimetable(database);
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-10T07:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final rides = result.steps
        .where((step) => step.stepType == 'ride')
        .toList(growable: false);
    expect(rides.map((ride) => ride.plannedArrivalTimeIso), [
      '2026-07-10T08:10:00+09:00',
      '2026-07-10T08:22:00+09:00',
    ]);
  });

  test('다중 ride 중 하나라도 공식 도착이 없으면 전체 알림 투영을 빈다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedTwoLegRoute(database);
    await _seedTwoLegTimetable(database);
    await database.customStatement('''
      DELETE FROM transit_stop_times
      WHERE trip_id IN (SELECT id FROM transit_trips WHERE route_id = 'route-alt')
    ''');
    await database.customStatement(
      "DELETE FROM transit_trips WHERE route_id = 'route-alt'",
    );
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-10T07:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final rides = result.steps.where((step) => step.stepType == 'ride');
    expect(rides, isNotEmpty);
    expect(
      rides,
      everyElement(
        predicate<RouteSearchStep>(
          (ride) => ride.plannedArrivalTimeIso.isEmpty,
        ),
      ),
    );
  });

  test('공식 시간표가 없으면 static 소요시간으로 절대 도착을 합성하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = LocalRouteRepository(
      catalogDatabase: database,
      now: () => DateTime.parse('2026-07-10T07:58:00+09:00'),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final ride = result.steps.singleWhere((step) => step.stepType == 'ride');
    expect(ride.plannedArrivalTimeIso, isEmpty);
  });

  test('로컬 capability는 station 존재와 realtime 지원을 분리한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = LocalRouteRepository(catalogDatabase: database);

    final capability = await repository.routeCapability(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(capability.stationExists, isTrue);
    expect(capability.routeGraphConnected, isTrue);
    expect(capability.strictEvidenceSupported, isTrue);
    expect(capability.realtimeSupported, isFalse);
    expect(capability.plannedTimetableSupported, isFalse);
    expect(capability.outOfStationTransferAllowed, isFalse);
    expect(capability.regions, ['수도권']);
    expect(capability.operatorIds, ['seoul-metro']);
  });

  test('로컬 capability는 시간표 row가 있을 때만 planned ETA를 지원한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedBaselineTimetable(database);
    final repository = LocalRouteRepository(catalogDatabase: database);

    final capability = await repository.routeCapability(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(capability.routeGraphConnected, isTrue);
    expect(capability.plannedTimetableSupported, isTrue);
  });

  test('로컬 capability는 같은 provider의 양끝 mapping이 있을 때 realtime을 지원한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedRealtimeMapping(database);
    final repository = LocalRouteRepository(catalogDatabase: database);

    final capability = await repository.routeCapability(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(capability.stationExists, isTrue);
    expect(capability.realtimeSupported, isTrue);
  });

  test('로컬 capability는 mapping이 있어도 arrivals 미지원이면 realtime을 끈다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedRealtimeMapping(database, supportsArrivals: false);
    final repository = LocalRouteRepository(catalogDatabase: database);

    final capability = await repository.routeCapability(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(capability.stationExists, isTrue);
    expect(capability.realtimeSupported, isFalse);
  });

  test('로컬 capability strict 근거는 요청 경로 기준으로 판단한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
      fillInsertedNetworkEdgeEvidence: false,
    );
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-b-local',
        'station-a:line-test',
        'station-b:line-test',
        120,
        'RIDE',
        'STEP_FREE',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final capability = await repository.routeCapability(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(capability.routeGraphConnected, isTrue);
    expect(capability.strictEvidenceSupported, isFalse);
  });

  test('전역 strict 지원이어도 경유 구간 중 하나가 미지원이면 강등한다 (#1975)', () async {
    // 전역 strict 지원(strictEvidenceSupported=true)이지만, 경유 구간 b→c의
    // 근거가 검증되지 않아 해당 구간만 strict 미지원인 상황. 구간별 판정이면
    // 경유 요청은 STRICT_EVIDENCE_UNSUPPORTED로 강등되어야 한다.
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    // a→b: 검증된 strict 근거(전역 strict 지원을 성립시킨다).
    await _insertVerifiedNetworkEdge(
      database,
      id: 'ride-a-b-strict',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-b:line-test',
      edgeType: 'RIDE',
      durationSeconds: 120,
    );
    // b→c: 검증되지 않은 근거 → 해당 구간만 strict 미지원.
    await _insertVerifiedNetworkEdge(
      database,
      id: 'ride-b-c-unverified',
      fromNodeId: 'station-b:line-test',
      toNodeId: 'station-c:line-test',
      edgeType: 'RIDE',
      durationSeconds: 120,
      verificationStatus: 'UNVERIFIED',
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    // 경유 없는 a→b는 strict FOUND(전역 지원 성립 확인).
    final directResult = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );
    expect(directResult.status, 'FOUND');

    // b 경유 a→c는 b→c 구간이 strict 미지원이므로 강등된다.
    final waypointResult = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        waypointStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );
    expect(waypointResult.status, 'UNKNOWN');
    // 구간별 판정이면 strict 근거 부족을 명시하는 STRICT_EVIDENCE_UNSUPPORTED
    // 사유로 강등된다(전역 bool만 보던 기존 경로는 이 사유를 내지 못한다).
    expect(
      waypointResult.blockedReasons,
      contains('검증 근거가 부족해 계단 없는 경로로 안내하지 않아요.'),
    );
  });

  test('경유 병합 결과 요약은 경계 마커 때문에 강등되지 않는다 (#1975)', () async {
    // access edge 없이 거리·시간을 가진 순수 ride만으로 a→b→c 경로를 구성한다.
    // 유일하게 0/unknown 메타를 가질 수 있는 스텝은 경계 마커뿐이므로, 마커가
    // 요약(_evidenceSummary)을 왜곡하는지 격리 검증할 수 있다.
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'ride-a-b-summary',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-b:line-test',
      edgeType: 'RIDE',
      durationSeconds: 120,
      distanceMeters: 500,
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'ride-b-c-summary',
      fromNodeId: 'station-b:line-test',
      toNodeId: 'station-c:line-test',
      edgeType: 'RIDE',
      durationSeconds: 120,
      distanceMeters: 500,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        waypointStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    expect(result.status, 'FOUND');
    // 실제 이동 스텝(entry/ride/exit)은 모두 소요시간이 양수다. 유일하게 0분인
    // 스텝은 경계 마커뿐이므로, 마커가 요약에서 제외되지 않으면 DURATION_UNKNOWN으로
    // 강등된다. 마커 격리가 되면 DURATION_ESTIMATED가 유지되어야 한다.
    expect(result.evidenceSummary, contains('DURATION_ESTIMATED'));
    expect(result.evidenceSummary, isNot(contains('DURATION_UNKNOWN')));
  });

  test('기존 baseline catalog도 명시 access edge를 보강해 휠체어 경로를 유지한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      DELETE FROM network_edges
      WHERE id IN (
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''');

    await database.seedBaselineIfEmpty();

    final repository = LocalRouteRepository(catalogDatabase: database);
    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.blockedReasons, isEmpty);
    expect(
      result.steps.map((step) => step.stepType),
      containsAll(['entry', 'exit']),
    );
    expect(result.steps.expand((step) => step.evidenceSources), isNotEmpty);
  });

  test('기존 baseline access edge 값은 보강 과정에서 덮어쓰지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      UPDATE network_edges
      SET accessibility_status = 'UNAVAILABLE',
          duration_seconds = 999,
          reliability_score = 30
      WHERE id = 'entry-sangnoksu-seoul-4'
    ''');

    await database.seedBaselineIfEmpty();

    final edge = await database.customSelect('''
            SELECT accessibility_status, duration_seconds, reliability_score
            FROM network_edges
            WHERE id = 'entry-sangnoksu-seoul-4'
          ''').getSingle();
    expect(edge.read<String>('accessibility_status'), 'UNAVAILABLE');
    expect(edge.read<int>('duration_seconds'), 999);
    expect(edge.read<int>('reliability_score'), 30);
  });

  test(
    '데이터팩 UNDER_MAINTENANCE edge는 표시 경로에서 가용이 아니라 보수중으로 차단된다 (#1996)',
    () async {
      // 백엔드 게이트가 확정한 network_edges.accessibility_status='UNDER_MAINTENANCE'가
      // 앱 표시 경로까지 도달하면서, available로 렌더되지 않고 '보수중' 사유로
      // 정직하게 구분 표시되는지 end-to-end로 검증한다.
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await database.seedBaselineIfEmpty();
      await database.customStatement('''
      UPDATE network_edges
      SET accessibility_status = 'UNDER_MAINTENANCE'
      WHERE id = 'entry-sangnoksu-seoul-4'
    ''');
      final repository = LocalRouteRepository(catalogDatabase: database);

      final result = await repository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: 'WHEELCHAIR',
        ),
      );

      // 가용으로 렌더되면 안 된다: FOUND가 아니라 차단이어야 한다.
      expect(result.status, 'BLOCKED');
      expect(result.steps, isEmpty);
      // 확인 불가가 아니라 실측 보수중 사유로 구분 표시된다.
      expect(result.blockedReasons, contains('지금은 보수중이라 이용하기 어려워요.'));
      // 보수중 문구는 available·확인 불가 문구와 겹치지 않는다.
      expect(result.blockedReasons, isNot(contains('엘리베이터·통로 상태를 확인하고 있어요.')));
    },
  );

  test(
    '데이터팩 NO_OFFICIAL_FEED edge는 표시 경로에서 확인 불가(unknown)로 취급된다 (#1996)',
    () async {
      // 상록수형: 공식 상태 피드 부재. available로 매핑되면 안 되고 확인 불가로
      // 취급되어, 휠체어 strict 프로필에서는 UNKNOWN으로 남는다.
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await database.seedBaselineIfEmpty();
      await database.customStatement('''
      UPDATE network_edges
      SET accessibility_status = 'NO_OFFICIAL_FEED'
      WHERE id = 'entry-sangnoksu-seoul-4'
    ''');
      final repository = LocalRouteRepository(catalogDatabase: database);

      final result = await repository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: 'WHEELCHAIR',
        ),
      );

      // available로 오인되어 FOUND가 되면 안 된다. 확인 불가는 UNKNOWN 계열이다.
      expect(result.status, 'UNKNOWN');
      expect(result.steps, isEmpty);
      // 확인 불가 문구로 안내하고, 보수중 문구는 쓰지 않는다.
      expect(result.blockedReasons, contains('엘리베이터·통로 상태를 확인하고 있어요.'));
      expect(result.blockedReasons, isNot(contains('지금은 보수중이라 이용하기 어려워요.')));
    },
  );

  test('기존 baseline edge provenance를 보강해 strict 경로를 유지한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      UPDATE network_edges
      SET source_id = '',
          source_snapshot_id = '',
          provider_record_hash = '',
          provenance_kind = 'UNKNOWN',
          verification_status = 'UNKNOWN',
          evidence_hash = ''
      WHERE id IN (
        'edge-sangnoksu-sadang-seoul-4',
        'edge-sadang-sangnoksu-seoul-4',
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''');

    await database.seedBaselineIfEmpty();

    final edge = await database.customSelect('''
            SELECT source_id, verification_status, evidence_hash
            FROM network_edges
            WHERE id = 'edge-sangnoksu-sadang-seoul-4'
          ''').getSingle();
    final repository = LocalRouteRepository(catalogDatabase: database);
    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(edge.read<String>('source_id'), 'baseline-route-source-capital');
    expect(edge.read<String>('verification_status'), 'VERIFIED');
    expect(edge.read<String>('evidence_hash'), hasLength(64));
    expect(result.status, 'FOUND');
    expect(result.blockedReasons, isEmpty);
  });

  test('기존 baseline edge의 명시 non-verified 상태는 보강 과정에서 덮어쓰지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      UPDATE network_edges
      SET verification_status = 'STALE'
      WHERE id = 'edge-sangnoksu-sadang-seoul-4'
    ''');

    await database.seedBaselineIfEmpty();

    final edge = await database.customSelect('''
            SELECT verification_status
            FROM network_edges
            WHERE id = 'edge-sangnoksu-sadang-seoul-4'
          ''').getSingle();
    final repository = LocalRouteRepository(catalogDatabase: database);
    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(edge.read<String>('verification_status'), 'STALE');
    expect(result.status, 'UNKNOWN');
    expect(result.blockedReasons, contains('검증되지 않은 경로는 안내하지 않아요.'));
  });

  test('로컬 경로 추천 이유는 확인되지 않은 접근성 검증을 단정하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final reasons = result.recommendationReasons.join('\n');
    expect(reasons, isNot(contains('확인했어요')));
    expect(reasons, contains('현장 안내'));
  });

  test('로컬 경로 단계는 행동 이유 근거와 시간 거리 출처를 함께 제공한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, distance_meters,
        edge_type, stair_access_state, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-b-local',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        830,
        'RIDE',
        'STEP_FREE',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final rideStep = result.steps.singleWhere(
      (step) => step.stepType == 'ride',
    );
    expect(rideStep.actionTitle, '열차 이동');
    expect(rideStep.actionDetail, contains('출발역에서 중간역까지'));
    expect(rideStep.reason, '선택한 길을 따라 안내합니다.');
    expect(rideStep.evidenceSources, contains('edge:edge-a-b-local'));
    expect(rideStep.timeSource, 'STATIC_ESTIMATE');
    expect(rideStep.distanceSource, 'MEASURED');
    expect(rideStep.confidenceLabel, '확인된 정보예요');
  });

  test('계단 없는 동선 여부가 미확인인 선택 경로는 확인된 정보 문구로 표시하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
    );
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, distance_meters,
        edge_type, stair_access_state, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-b-unknown-stair',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        830,
        'RIDE',
        'UNKNOWN',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    final rideStep = result.steps.singleWhere(
      (step) => step.lineId == 'line-test',
    );
    expect(result.status, 'FOUND');
    expect(
      result.warnings.map((warning) => warning.code),
      contains('STAIR_ONLY_ACCESS_UNKNOWN'),
    );
    expect(rideStep.confidenceLabel, '안내를 준비 중이에요');
  });

  test('로컬 경로 추천 이유와 음성 안내는 선택 경로에 없는 계단 차단 근거를 말하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES (
        'edge-a-b-local',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'STEP_FREE',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    const unusedEvidenceClaim = '차단된 계단 구간은 제외했습니다.';
    expect(result.status, 'FOUND');
    expect(result.steps.any((step) => step.includesStairs), isFalse);
    expect(
      result.recommendationReasons.join('\n'),
      isNot(contains(unusedEvidenceClaim)),
    );
    expect(result.semanticLabel, isNot(contains(unusedEvidenceClaim)));
  });

  test('로컬 catalog가 모르는 역 경로는 API fallback 없이 차단 결과를 반환한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = LocalFirstRouteSearchRepository(
      localRepository: LocalRouteRepository(catalogDatabase: database),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-outside-pack',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.destinationStationName, '역 이름을 확인하고 있어요');
    expect(result.isLocalResult, isTrue);
  });

  test('명시적 철도 간선이 없으면 같은 노선 순번만으로 경로를 만들지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.blockedReasons, isNotEmpty);
  });

  test('WALK network edge는 열차 ride 경로로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state
      )
      VALUES (
        'edge-a-c-walk',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'WALK',
        'STEP_FREE'
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.steps, isEmpty);
  });

  test('mobile catalog edge type mapping은 허용된 상용 edge 값을 모두 해석한다', () {
    final cases = {
      'RIDE': graph.RouteEdgeType.ride,
      'TRANSFER': graph.RouteEdgeType.inStationTransfer,
      'IN_STATION_TRANSFER': graph.RouteEdgeType.inStationTransfer,
      'OUT_OF_STATION_TRANSFER': graph.RouteEdgeType.outOfStationTransfer,
      'ENTRY': graph.RouteEdgeType.entry,
      'EXIT': graph.RouteEdgeType.exit,
      'WALKWAY': graph.RouteEdgeType.walkway,
      'ELEVATOR': graph.RouteEdgeType.elevator,
      'RAMP': graph.RouteEdgeType.ramp,
      'STAIR': graph.RouteEdgeType.stair,
      'ESCALATOR': graph.RouteEdgeType.escalator,
      'FACILITY_CONNECTOR': graph.RouteEdgeType.facilityConnector,
      'LEGACY_TRANSFER': graph.RouteEdgeType.inStationTransfer,
      'transfer': graph.RouteEdgeType.inStationTransfer,
    };

    for (final entry in cases.entries) {
      expect(
        graph.routeEdgeTypeFromCatalogValue(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
    expect(graph.routeEdgeTypeFromCatalogValue('UNKNOWN'), isNull);
  });

  test('역외 환승 edge는 역 밖 환승 문구로 표시한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await _allowOutOfStationTransfer(
      database,
      'station-a:line-test->station-c:line-alt',
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'edge-b-a-line-test',
      fromNodeId: 'station-b:line-test',
      toNodeId: 'station-a:line-test',
      edgeType: 'RIDE',
      durationSeconds: 90,
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'out-transfer-a-c',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-c:line-alt',
      edgeType: 'OUT_OF_STATION_TRANSFER',
      durationSeconds: 300,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );
    final capability = await repository.routeCapability(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final transferStep = result.steps.singleWhere(
      (step) => step.stepType == 'outOfStationTransfer',
    );
    expect(result.status, 'FOUND');
    expect(capability.outOfStationTransferAllowed, isTrue);
    expect(result.transferCount, 1);
    expect(
      result.warnings.map((warning) => warning.code),
      contains('FARE_EXIT_REENTRY_REQUIRED'),
    );
    expect(transferStep.title, contains('역 밖으로 이동해'));
    expect(transferStep.actionTitle, '역외 환승');
  });

  test('역외 환승 edge는 allowlist 없으면 후보에서 제외한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await _insertVerifiedNetworkEdge(
      database,
      id: 'edge-b-a-line-test',
      fromNodeId: 'station-b:line-test',
      toNodeId: 'station-a:line-test',
      edgeType: 'RIDE',
      durationSeconds: 90,
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'out-transfer-a-c',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-c:line-alt',
      edgeType: 'OUT_OF_STATION_TRANSFER',
      durationSeconds: 300,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, isNot('FOUND'));
    expect(
      result.steps.where((step) => step.stepType == 'outOfStationTransfer'),
      isEmpty,
    );
  });

  test('역외 환승 runtime kill switch off는 다음 검색부터 후보에서 제외한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await _allowOutOfStationTransfer(
      database,
      'station-a:line-test->station-c:line-alt',
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'edge-b-a-line-test',
      fromNodeId: 'station-b:line-test',
      toNodeId: 'station-a:line-test',
      edgeType: 'RIDE',
      durationSeconds: 90,
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'out-transfer-a-c',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-c:line-alt',
      edgeType: 'OUT_OF_STATION_TRANSFER',
      durationSeconds: 300,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final enabledResult = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );
    await _setOutOfStationTransferRuntimeEnabled(database, false);
    final disabledResult = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(enabledResult.status, 'FOUND');
    expect(disabledResult.status, isNot('FOUND'));
  });

  test('역외 환승 edge는 역방향을 자동으로 열지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await _allowOutOfStationTransfer(
      database,
      'station-a:line-test->station-c:line-alt',
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'edge-a-b-line-test',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-b:line-test',
      edgeType: 'RIDE',
      durationSeconds: 90,
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'out-transfer-a-c-one-way',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-c:line-alt',
      edgeType: 'OUT_OF_STATION_TRANSFER',
      durationSeconds: 300,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-c',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, isNot('FOUND'));
  });

  test('시설 connector edge는 generic transfer 문구로 렌더링하지 않는다', () async {
    for (final fixture in const [
      (edgeType: 'WALKWAY', stepType: 'walkway', actionTitle: '통로 이동'),
      (edgeType: 'ELEVATOR', stepType: 'elevator', actionTitle: '엘리베이터 이동'),
      (edgeType: 'RAMP', stepType: 'ramp', actionTitle: '경사로 이동'),
      (
        edgeType: 'FACILITY_CONNECTOR',
        stepType: 'facilityConnector',
        actionTitle: '시설 연결 이동',
      ),
    ]) {
      final database = CatalogDatabase.memory();
      try {
        await _seedLineWithoutNetworkEdges(database);
        await _insertVerifiedNetworkEdge(
          database,
          id: 'edge-a-c-${fixture.edgeType.toLowerCase()}',
          fromNodeId: 'station-a:line-test',
          toNodeId: 'station-c:line-test',
          edgeType: fixture.edgeType,
          durationSeconds: 180,
        );
        final repository = LocalRouteRepository(catalogDatabase: database);

        final result = await repository.searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-a',
            destinationStationId: 'station-c',
            mobilityType: 'WHEELCHAIR',
          ),
        );

        final step = result.steps.singleWhere(
          (step) => step.stepType == fixture.stepType,
        );
        expect(result.status, 'FOUND', reason: fixture.edgeType);
        expect(step.actionTitle, fixture.actionTitle);
        expect(step.title, isNot(contains('환승')));
      } finally {
        await database.close();
      }
    }
  });

  test('STAIR edge는 stair_access_state가 잘못 들어와도 strict mode에서 차단한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _insertVerifiedNetworkEdge(
      database,
      id: 'edge-a-c-stair',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-c:line-test',
      edgeType: 'STAIR',
      durationSeconds: 180,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'STROLLER',
        constraintMode: 'STRICT_STEP_FREE',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('계단 없는 경로를 아직 찾지 못했어요.'));
  });

  test('사용 불가 접근성 edge는 이동 가능 경로로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status
      )
      VALUES (
        'edge-a-c-elevator-down',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE',
        'STEP_FREE',
        'UNAVAILABLE'
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.blockedReasons, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
    expect(result.steps, isEmpty);
  });

  test('확인되지 않은 접근성 edge는 휠체어 경로에서 이동 가능으로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status
      )
      VALUES (
        'edge-a-c-unknown-access',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE',
        'STEP_FREE',
        'UNKNOWN'
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('엘리베이터·통로 상태를 확인하고 있어요.'));
    expect(result.warnings, isEmpty);
    expect(result.recommendationReasons.join('\n'), isNot(contains('확인했어요')));
  });

  test('검증되지 않은 network edge는 strict 경로에서 FOUND로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'entry-a-line-test',
      fromNodeId: 'station-a',
      toNodeId: 'station-a:line-test',
      edgeType: 'ENTRY',
      durationSeconds: 90,
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'edge-a-c-unverified',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-c:line-test',
      edgeType: 'RIDE',
      durationSeconds: 180,
      verificationStatus: 'PENDING',
    );
    await _insertVerifiedNetworkEdge(
      database,
      id: 'exit-c-line-test',
      fromNodeId: 'station-c:line-test',
      toNodeId: 'station-c',
      edgeType: 'EXIT',
      durationSeconds: 60,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'STROLLER',
        constraintMode: 'STRICT_STEP_FREE',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('검증되지 않은 경로는 안내하지 않아요.'));
    expect(result.warnings, isEmpty);
  });

  test('오래된 network edge는 strict 경로에서 stale 사유를 표시한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _insertVerifiedNetworkEdge(
      database,
      id: 'edge-a-c-stale',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-c:line-test',
      edgeType: 'RIDE',
      durationSeconds: 180,
      lastVerifiedAtSeconds: 0,
    );

    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('오래된 안내라 계단 없는 경로로 안내하지 않아요.'));
    expect(result.warnings, isEmpty);
  });

  test('잘못된 provenance와 evidence hash는 strict 경로에서 FOUND 근거가 되지 않는다', () async {
    for (final fixture in const [
      (
        id: 'edge-a-c-missing-evidence',
        provenanceKind: 'OFFICIAL_SOURCE',
        evidenceHash: '',
        expectedReason: '검증 근거가 없는 경로는 안내하지 않아요.',
      ),
      (
        id: 'edge-a-c-placeholder-evidence',
        provenanceKind: 'OFFICIAL_SOURCE',
        evidenceHash:
            '0000000000000000000000000000000000000000000000000000000000000000',
        expectedReason: '임시 근거만 있는 경로는 안내하지 않아요.',
      ),
      (
        id: 'edge-a-c-unsupported-provenance',
        provenanceKind: 'GENERATED',
        evidenceHash:
            '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        expectedReason: '지원 범위 밖 경로는 안내하지 않아요.',
      ),
    ]) {
      final database = CatalogDatabase.memory();
      try {
        await _seedLineWithoutNetworkEdges(
          database,
          includeExplicitAccessEdges: false,
        );
        await _insertVerifiedNetworkEdge(
          database,
          id: 'entry-a-line-test-${fixture.id}',
          fromNodeId: 'station-a',
          toNodeId: 'station-a:line-test',
          edgeType: 'ENTRY',
          durationSeconds: 90,
        );
        await _insertVerifiedNetworkEdge(
          database,
          id: fixture.id,
          fromNodeId: 'station-a:line-test',
          toNodeId: 'station-c:line-test',
          edgeType: 'RIDE',
          durationSeconds: 180,
          provenanceKind: fixture.provenanceKind,
          evidenceHash: fixture.evidenceHash,
        );
        await _insertVerifiedNetworkEdge(
          database,
          id: 'exit-c-line-test-${fixture.id}',
          fromNodeId: 'station-c:line-test',
          toNodeId: 'station-c',
          edgeType: 'EXIT',
          durationSeconds: 60,
        );
        final repository = LocalRouteRepository(catalogDatabase: database);

        final result = await repository.searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-a',
            destinationStationId: 'station-c',
            mobilityType: 'WHEELCHAIR',
          ),
        );

        expect(result.status, 'UNKNOWN');
        expect(result.steps, isEmpty);
        expect(result.blockedReasons, contains(fixture.expectedReason));
        expect(result.warnings, isEmpty);
      } finally {
        await database.close();
      }
    }
  });

  test('부분 edge 근거 metadata는 strict 경로에서 FOUND 근거가 되지 않는다', () async {
    for (final fixture in const [
      (
        id: 'edge-a-c-missing-source-snapshot',
        setSql: "source_snapshot_id = ''",
        expectedReason: '검증되지 않은 경로는 안내하지 않아요.',
      ),
      (
        id: 'edge-a-c-missing-provider-hash',
        setSql: "provider_record_hash = ''",
        expectedReason: '검증 근거가 없는 경로는 안내하지 않아요.',
      ),
      (
        id: 'edge-a-c-missing-verified-at',
        setSql: 'last_verified_at = NULL',
        expectedReason: '검증되지 않은 경로는 안내하지 않아요.',
      ),
    ]) {
      final database = CatalogDatabase.memory();
      try {
        await _seedLineWithoutNetworkEdges(
          database,
          includeExplicitAccessEdges: false,
        );
        await _insertVerifiedNetworkEdge(
          database,
          id: 'entry-a-line-test-${fixture.id}',
          fromNodeId: 'station-a',
          toNodeId: 'station-a:line-test',
          edgeType: 'ENTRY',
          durationSeconds: 90,
        );
        await _insertVerifiedNetworkEdge(
          database,
          id: fixture.id,
          fromNodeId: 'station-a:line-test',
          toNodeId: 'station-c:line-test',
          edgeType: 'RIDE',
          durationSeconds: 180,
        );
        await database.customStatement(
          'UPDATE network_edges SET ${fixture.setSql} WHERE id = ?',
          [fixture.id],
        );
        await _insertVerifiedNetworkEdge(
          database,
          id: 'exit-c-line-test-${fixture.id}',
          fromNodeId: 'station-c:line-test',
          toNodeId: 'station-c',
          edgeType: 'EXIT',
          durationSeconds: 60,
        );
        final repository = LocalRouteRepository(catalogDatabase: database);

        final result = await repository.searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-a',
            destinationStationId: 'station-c',
            mobilityType: 'WHEELCHAIR',
          ),
        );

        expect(result.status, 'UNKNOWN');
        expect(result.steps, isEmpty);
        expect(result.blockedReasons, contains(fixture.expectedReason));
        expect(result.warnings, isEmpty);
      } finally {
        await database.close();
      }
    }
  });

  test('마이그레이션된 빈 근거 컬럼은 strict 지원으로 보지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
      fillInsertedNetworkEdgeEvidence: false,
    );
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status, reliability_score
      )
      VALUES
        (
          'entry-a-line-test-empty-evidence',
          'station-a',
          'station-a:line-test',
          90,
          'ENTRY',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-a-c-empty-evidence',
          'station-a:line-test',
          'station-c:line-test',
          180,
          'RIDE',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'exit-c-line-test-empty-evidence',
          'station-c:line-test',
          'station-c',
          60,
          'EXIT',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('검증 근거가 부족해 계단 없는 경로로 안내하지 않아요.'));
    expect(result.warnings, isEmpty);
  });

  test('구형 catalog의 network_edges는 미확인 접근성 상태로 안전하게 차단한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('DROP TABLE network_edges');
    await database.customStatement('''
      CREATE TABLE network_edges (
        id TEXT NOT NULL PRIMARY KEY,
        from_node_id TEXT NOT NULL,
        to_node_id TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        edge_type TEXT NOT NULL DEFAULT 'WALK'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type
      )
      VALUES (
        'edge-a-c-legacy',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE'
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('검증 근거가 부족해 계단 없는 경로로 안내하지 않아요.'));
    expect(result.warnings, isEmpty);
  });

  test('구형 catalog의 계단 여부 false 기본값은 계단 없는 경로로 단정하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('DROP TABLE network_edges');
    await database.customStatement('''
      CREATE TABLE network_edges (
        id TEXT NOT NULL PRIMARY KEY,
        from_node_id TEXT NOT NULL,
        to_node_id TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        edge_type TEXT NOT NULL DEFAULT 'WALK',
        includes_stairs INTEGER NOT NULL DEFAULT 0,
        accessibility_status TEXT NOT NULL DEFAULT 'AVAILABLE'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        includes_stairs, accessibility_status
      )
      VALUES (
        'edge-a-c-legacy-stair-default',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE',
        0,
        'AVAILABLE'
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('검증 근거가 부족해 계단 없는 경로로 안내하지 않아요.'));
    expect(result.warnings, isEmpty);
  });

  test('구형 catalog schema는 baseline access backfill 없이 계속 열린다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('DROP TABLE network_edges');
    await database.customStatement('''
      CREATE TABLE network_edges (
        id TEXT NOT NULL PRIMARY KEY,
        from_node_id TEXT NOT NULL,
        to_node_id TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        edge_type TEXT NOT NULL DEFAULT 'WALK'
      )
    ''');

    await database.seedBaselineIfEmpty();

    final rows = await database
        .customSelect(
          "SELECT id FROM network_edges WHERE id LIKE 'entry-%' OR id LIKE 'exit-%'",
        )
        .get();
    expect(rows, isEmpty);
  });

  test('service pattern node는 역-노선 node로 뭉개지지 않고 출입구와 연결된다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES (
        'edge-a-b-local',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'STEP_FREE',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'line-test'},
    );
    expect(result.blockedReasons, isEmpty);
  });

  test('생성 access edge만 있는 휠체어 경로는 검증된 경로로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
    );
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-b-step-free',
        'station-a:line-test',
        'station-b:line-test',
        120,
        'RIDE',
        'STEP_FREE',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('길이 이어지는지 확인하고 있어요.'));
  });

  test('생성 transfer edge만 있는 휠체어 환승 경로는 검증된 경로로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
    );
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status, reliability_score
      )
      VALUES
        (
          'entry-b-line-test-explicit',
          'station-b',
          'station-b:line-test',
          90,
          'ENTRY',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-b-a-line-test',
          'station-b:line-test',
          'station-a:line-test',
          90,
          'RIDE',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'exit-c-line-alt-explicit',
          'station-c:line-alt',
          'station-c',
          60,
          'EXIT',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'UNKNOWN');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('길이 이어지는지 확인하고 있어요.'));
  });

  test('service pattern entry가 사용 불가이면 생성 entry로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'entry-a-line-test-local-unavailable',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
  });

  test('base entry가 사용 불가이면 service pattern entry로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'entry-a-line-test-unavailable',
          'station-a',
          'station-a:line-test',
          90,
          'ENTRY',
          '',
          'STEP_FREE',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
  });

  test('고장 시설에 연결된 entry edge는 접근 가능 경로에서 제외한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'OUT_OF_SERVICE',
        'B1',
        '1F',
        '점검 중'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          NULL
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
  });

  test('사용 불가 edge는 연결 시설 확인 필요 상태로 약화하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'CHECK_REQUIRED',
        'B1',
        '1F',
        '확인 필요'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'UNAVAILABLE',
          95,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          NULL
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
  });

  test('운행 상태 미확인 시설에 연결된 edge는 휠체어 경로 FOUND가 되지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, operational_status,
        floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'NORMAL',
        'UNKNOWN',
        'B1',
        '1F',
        '설치 여부는 알지만 운행 상태는 확인 필요'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          NULL
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, isNot('FOUND'));
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('엘리베이터·통로 상태를 확인하고 있어요.'));
  });

  test('검수 완료 시설에 연결된 available edge는 이동 가능하게 유지한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'ADMIN_VERIFIED',
        'B1',
        '1F',
        '관리자 검수 완료'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          NULL
        )
    ''');
    await _addEligibleStationFacilityEvidence(database);
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.blockedReasons, isEmpty);
    expect(result.warnings, isEmpty);
  });

  test('active 시설 상태 snapshot이 사용 불가이면 strict 경로를 차단한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedAvailableFacilityRoute(database);
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await _addFacilityStatusSnapshot(
      database,
      id: 'snapshot-facility-a-live-unavailable',
      providerId: 'live-provider',
      sourceId: 'facility-live-source',
      sourceSnapshotId: 'facility-live-source-20260701',
      status: 'BROKEN',
      operationalStatus: 'OUT_OF_SERVICE',
      observedAtSeconds: nowSeconds,
      expiresAtSeconds: nowSeconds + 3600,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
  });

  test('operator override snapshot은 live snapshot보다 우선한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedAvailableFacilityRoute(database);
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await _addFacilityStatusSnapshot(
      database,
      id: 'snapshot-facility-a-live-unavailable',
      providerId: 'live-provider',
      sourceId: 'facility-live-source',
      sourceSnapshotId: 'facility-live-source-20260701',
      status: 'BROKEN',
      operationalStatus: 'OUT_OF_SERVICE',
      observedAtSeconds: nowSeconds,
      expiresAtSeconds: nowSeconds + 3600,
    );
    await _addFacilityStatusSnapshot(
      database,
      id: 'snapshot-facility-a-operator-available',
      providerId: 'operator-override',
      sourceId: 'facility-operator-source',
      sourceSnapshotId: 'facility-operator-source-20260701',
      status: 'AVAILABLE',
      operationalStatus: 'AVAILABLE',
      observedAtSeconds: nowSeconds - 60,
      expiresAtSeconds: nowSeconds + 1800,
      confidence: 0,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.blockedReasons, isEmpty);
    expect(
      result.warnings.map((warning) => warning.code),
      contains('LOW_DATA_CONFIDENCE'),
    );
    expect(
      result.steps.expand((step) => step.evidenceSources),
      containsAll([
        'source:facility-operator-source',
        'snapshot:facility-operator-source-20260701',
      ]),
    );
  });

  test('expired 사용 불가 snapshot은 strict 경로를 차단하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedAvailableFacilityRoute(database);
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await _addFacilityStatusSnapshot(
      database,
      id: 'snapshot-facility-a-expired-unavailable',
      providerId: 'operator-override',
      sourceId: 'facility-expired-source',
      sourceSnapshotId: 'facility-expired-source-20260701',
      status: 'BROKEN',
      operationalStatus: 'OUT_OF_SERVICE',
      observedAtSeconds: nowSeconds - 7200,
      expiresAtSeconds: nowSeconds,
    );
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.blockedReasons, isEmpty);
    expect(
      result.warnings.map((warning) => warning.code),
      contains('LOW_DATA_CONFIDENCE'),
    );
  });

  test('eligible evidence가 없는 검수 완료 시설 edge는 strict 경로에서 제외한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'ADMIN_VERIFIED',
        'B1',
        '1F',
        '관리자 검수 완료'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          NULL
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, isNot('FOUND'));
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('엘리베이터·통로 상태를 확인하고 있어요.'));
  });

  test('낮은 시설 품질 레코드는 연결된 edge의 신뢰도와 갱신 시각으로 전파된다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'NORMAL',
        'B1',
        '1F',
        ''
      )
    ''');
    await database.customStatement('''
      INSERT INTO data_quality_records (
        id, target_type, target_id, quality_level, checked_at
      )
      VALUES (
        'quality-facility-a-elevator',
        'facility',
        'facility-a-elevator',
        'LEVEL_1',
        0
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, last_verified_at, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          NULL
        )
    ''');
    await _addEligibleStationFacilityEvidence(database);
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.warnings.map((warning) => warning.code), {
      'LOW_DATA_CONFIDENCE',
      'STALE_ACCESSIBILITY_DATA',
    });
  });

  test('최근 확인된 시설 품질 레코드는 추가 확인 경고를 만들지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'NORMAL',
        'B1',
        '1F',
        ''
      )
    ''');
    await database.customStatement('''
      INSERT INTO data_quality_records (
        id, target_type, target_id, quality_level, checked_at
      )
      VALUES (
        'quality-facility-a-elevator',
        'facility',
        'facility-a-elevator',
        'LEVEL_4',
        1781827200
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, last_verified_at, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          NULL
        )
    ''');
    await _addEligibleStationFacilityEvidence(database);
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(
      result.warnings.map((warning) => warning.code),
      isNot(contains('LOW_DATA_CONFIDENCE')),
    );
  });

  test('시설 품질 테이블이 없는 catalog도 연결 시설 경로를 계산한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('DROP TABLE data_quality_records');
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'NORMAL',
        'B1',
        '1F',
        ''
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, last_verified_at, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          NULL
        )
    ''');
    await _addEligibleStationFacilityEvidence(database);
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.warnings, isEmpty);
  });

  test('명시 service pattern entry는 base entry 확장으로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'entry-a-line-test-available',
          'station-a',
          'station-a:line-test',
          90,
          'ENTRY',
          '',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'entry-a-line-test-local-unavailable',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
  });

  test('급행 pattern은 미정차역을 경유한 것처럼 연결하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES (
        'edge-a-c-express',
        'station-a:line-test:EXPRESS',
        'station-c:line-test:EXPRESS',
        150,
        'RIDE',
        'EXPRESS',
        'STEP_FREE',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final expressResult = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );
    final skippedStopResult = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(expressResult.status, 'FOUND');
    expect(skippedStopResult.status, 'UNKNOWN');
    expect(skippedStopResult.steps, isEmpty);
  });

  test(
    'service pattern 방향 suffix가 있는 node도 entry와 ride edge를 같은 node로 연결한다',
    () async {
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await _seedLineWithoutNetworkEdges(database);
      await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-a-b-local-clockwise',
          'station-a:line-test:LOCAL:CLOCKWISE',
          'station-b:line-test:LOCAL:CLOCKWISE',
          90,
          'RIDE',
          'LOCAL:CLOCKWISE',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-b-c-local-clockwise',
          'station-b:line-test:LOCAL:CLOCKWISE',
          'station-c:line-test:LOCAL:CLOCKWISE',
          90,
          'RIDE',
          'LOCAL:CLOCKWISE',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
      final repository = LocalRouteRepository(catalogDatabase: database);

      final result = await repository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-a',
          destinationStationId: 'station-c',
          mobilityType: 'WHEELCHAIR',
        ),
      );

      expect(result.status, 'FOUND');
      expect(result.blockedReasons, isEmpty);
      expect(
        result.steps.map((step) => step.fromStationId),
        contains('station-a'),
      );
      expect(
        result.steps.map((step) => step.toStationId),
        contains('station-c'),
      );
      expect(
        result.steps.map((step) => step.lineId).where((id) => id.isNotEmpty),
        everyElement('line-test'),
      );
    },
  );

  test('step 소요시간은 접근성 패널티가 아니라 사용된 edge 시간에서 만든다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score,
        stair_access_state, last_verified_at
      )
      VALUES (
        'edge-a-b-low-confidence',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'AVAILABLE',
        50,
        'STEP_FREE',
        0
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    final rideStep = result.steps.singleWhere(
      (step) => step.stepType == 'ride',
    );
    expect(result.status, 'FOUND');
    expect(result.warnings.map((warning) => warning.code), {
      'LOW_DATA_CONFIDENCE',
      'STALE_ACCESSIBILITY_DATA',
    });
    expect(rideStep.estimatedMinutes, 2);
  });

  test('step 소요시간은 확인된 값이 없으면 ranking fallback 시간으로 표시하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addDistanceMetersColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, distance_meters,
        edge_type, service_pattern, accessibility_status, reliability_score,
        stair_access_state, last_verified_at
      )
      VALUES (
        'edge-a-b-duration-unknown',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        0,
        850,
        'RIDE',
        'LOCAL',
        'AVAILABLE',
        100,
        'STEP_FREE',
        1700000000
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    final rideStep = result.steps.singleWhere(
      (step) => step.stepType == 'ride',
    );
    expect(result.status, 'FOUND');
    expect(rideStep.estimatedMinutes, 0);
    expect(rideStep.distanceMeters, 850);
  });

  test('step 거리는 ranking cost에서 만들지 않고 확인된 값이 없으면 미확인으로 둔다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score,
        stair_access_state, last_verified_at
      )
      VALUES (
        'edge-a-b-low-confidence-distance-unknown',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'AVAILABLE',
        50,
        'STEP_FREE',
        0
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    final rideStep = result.steps.singleWhere(
      (step) => step.stepType == 'ride',
    );
    expect(result.status, 'FOUND');
    expect(rideStep.estimatedMinutes, 2);
    expect(rideStep.distanceMeters, 0);
  });

  test('step 거리는 catalog에 확인된 값이 있으면 ranking cost 대신 그 값을 사용한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addDistanceMetersColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, distance_meters,
        edge_type, service_pattern, accessibility_status, reliability_score,
        stair_access_state, last_verified_at
      )
      VALUES (
        'edge-a-b-measured-distance',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        850,
        'RIDE',
        'LOCAL',
        'AVAILABLE',
        50,
        'STEP_FREE',
        0
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    final rideStep = result.steps.singleWhere(
      (step) => step.stepType == 'ride',
    );
    expect(result.status, 'FOUND');
    expect(rideStep.estimatedMinutes, 2);
    expect(rideStep.distanceMeters, 850);
  });

  test('사용 불가 explicit transfer edge는 자동 환승 edge로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test',
          'station-b:line-test',
          'station-a:line-test',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-unavailable',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'STEP_FREE',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('꼭 필요한 시설을 지금 이용하기 어려워요.'));
  });

  test('service pattern transfer도 사용 불가 explicit transfer를 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test-local',
          'station-b:line-test:LOCAL',
          'station-a:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-unavailable',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'STEP_FREE',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
  });

  test('service pattern explicit transfer는 다른 pattern의 환승을 막지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test-express',
          'station-b:line-test:EXPRESS',
          'station-a:line-test:EXPRESS',
          90,
          'RIDE',
          'EXPRESS',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-local-alt-unavailable',
          'station-a:line-test:LOCAL',
          'station-a:line-alt',
          140,
          'TRANSFER',
          'LOCAL',
          'STEP_FREE',
          'UNAVAILABLE',
          95
        ),
        (
          'transfer-a-express-alt-available',
          'station-a:line-test:EXPRESS',
          'station-a:line-alt',
          140,
          'TRANSFER',
          'EXPRESS',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'line-test', 'line-alt'},
    );
  });

  test('service pattern ride 뒤 base explicit transfer를 사용할 수 있다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test-local',
          'station-b:line-test:LOCAL',
          'station-a:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-available',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'line-test', 'line-alt'},
    );
  });

  test('같은 노선의 서로 다른 service pattern 사이를 환승할 수 있다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-b-local-express',
          'station-b:line-test:LOCAL',
          'station-b:line-test:EXPRESS',
          140,
          'TRANSFER',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-b-c-express',
          'station-b:line-test:EXPRESS',
          'station-c:line-test:EXPRESS',
          90,
          'RIDE',
          'EXPRESS',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.blockedReasons, isEmpty);
    expect(
      result.steps.map((step) => step.lineId).where((id) => id.isNotEmpty),
      everyElement('line-test'),
    );
  });

  test('같은 역의 base node와 service pattern node를 연결해 혼합 경로를 찾는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-a-b-base',
          'station-a:line-test',
          'station-b:line-test',
          90,
          'RIDE',
          '',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-b-base-local',
          'station-b:line-test',
          'station-b:line-test:LOCAL',
          140,
          'TRANSFER',
          '',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-b-c-local',
          'station-b:line-test:LOCAL',
          'station-c:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.blockedReasons, isEmpty);
    expect(
      result.steps.map((step) => step.lineId).where((id) => id.isNotEmpty),
      everyElement('line-test'),
    );
  });

  test('단방향 explicit transfer가 역방향 환승 경로를 제거하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-c-a-line-alt',
          'station-c:line-alt',
          'station-a:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-available',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-a-b-line-test',
          'station-a:line-test',
          'station-b:line-test',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-c',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'line-test', 'line-alt'},
    );
  });

  test(
    '역방향 service pattern transfer도 사용 불가 explicit transfer를 우회하지 않는다',
    () async {
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await _seedLineWithoutNetworkEdges(database);
      await _addSecondLineForTransferFixture(database);
      await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-c-a-line-alt',
          'station-c:line-alt',
          'station-a:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-unavailable',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'STEP_FREE',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-b-line-test-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        )
    ''');
      final repository = LocalRouteRepository(catalogDatabase: database);

      final result = await repository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-c',
          destinationStationId: 'station-b',
          mobilityType: 'WHEELCHAIR',
        ),
      );

      expect(result.status, 'BLOCKED');
      expect(result.steps, isEmpty);
    },
  );

  test('빠른 하차 안내: 방향(UP) 일치하면 승차 step에 칸-문·시설을 채운다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO station_car_door_hints (
        id, station_id, line_id, direction, target_facility_type,
        car_number, door_number, verification_status
      ) VALUES (
        'cardoor-a', 'station-sadang', 'seoul-4', 'UP', 'ELEVATOR',
        3, 4, 'OFFICIAL'
      )
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    final ride = result.steps.firstWhere((s) => s.stepType == 'ride');
    expect(ride.carDoorCarNumber, 3);
    expect(ride.carDoorDoorNumber, 4);
    expect(ride.carDoorFacilityType, 'ELEVATOR');
    expect(ride.hasCarDoorHint, isTrue);
  });

  test('빠른 하차 안내: 반대 방향(DOWN)만 있으면 매칭하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO station_car_door_hints (
        id, station_id, line_id, direction, target_facility_type,
        car_number, door_number, verification_status
      ) VALUES (
        'cardoor-down', 'station-sadang', 'seoul-4', 'DOWN', 'ELEVATOR',
        3, 4, 'OFFICIAL'
      )
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    final ride = result.steps.firstWhere((s) => s.stepType == 'ride');
    expect(ride.carDoorCarNumber, isNull);
    expect(ride.hasCarDoorHint, isFalse);
  });

  test('빠른 하차 안내: direction이 비면 방향 무관하게 매칭한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO station_car_door_hints (
        id, station_id, line_id, direction, target_facility_type,
        car_number, door_number, verification_status
      ) VALUES (
        'cardoor-anydir', 'station-sadang', 'seoul-4', '', 'ELEVATOR',
        3, 4, 'OFFICIAL'
      )
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    final ride = result.steps.firstWhere((s) => s.stepType == 'ride');
    expect(ride.carDoorCarNumber, 3);
    expect(ride.carDoorDoorNumber, 4);
  });

  test('빠른 하차 안내: 미검증(UNKNOWN) 힌트는 게이트에서 제외된다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO station_car_door_hints (
        id, station_id, line_id, direction, target_facility_type,
        car_number, door_number, verification_status
      ) VALUES (
        'cardoor-unknown', 'station-sadang', 'seoul-4', 'UP', 'ELEVATOR',
        3, 4, 'UNKNOWN'
      )
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    final ride = result.steps.firstWhere((s) => s.stepType == 'ride');
    expect(ride.carDoorCarNumber, isNull);
  });

  test('빠른 하차 안내: 후보가 여럿이면 시설 우선순위로 엘리베이터를 고른다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO station_car_door_hints (
        id, station_id, line_id, direction, target_facility_type,
        car_number, door_number, verification_status
      ) VALUES
        ('cardoor-stair', 'station-sadang', 'seoul-4', 'UP', 'STAIR',
          1, 1, 'OFFICIAL'),
        ('cardoor-elev', 'station-sadang', 'seoul-4', 'UP', 'ELEVATOR',
          3, 4, 'OFFICIAL')
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    final ride = result.steps.firstWhere((s) => s.stepType == 'ride');
    expect(ride.carDoorFacilityType, 'ELEVATOR');
    expect(ride.carDoorCarNumber, 3);
  });

  test('빠른 하차 안내: 규약 미검증 노선은 방향 hint를 매칭하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _insertVerifiedNetworkEdge(
      database,
      id: 'ride-a-b-line-test',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-b:line-test',
      edgeType: 'RIDE',
      durationSeconds: 90,
    );
    // line-test는 _carDoorSeqConventionByLine에 없는 미검증 노선이다. seq 1→2
    // 오름차순이라도 방향(UP/DOWN)을 유추하지 않으므로 DOWN hint는 매칭하지 않는다.
    await database.customStatement('''
      INSERT INTO station_car_door_hints (
        id, station_id, line_id, direction, target_facility_type,
        car_number, door_number, verification_status
      ) VALUES (
        'cardoor-unverified-line', 'station-b', 'line-test', 'DOWN', 'ELEVATOR',
        3, 4, 'OFFICIAL'
      )
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-a',
            destinationStationId: 'station-b',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    final ride = result.steps.firstWhere((s) => s.stepType == 'ride');
    expect(ride.carDoorCarNumber, isNull);
    expect(ride.hasCarDoorHint, isFalse);
  });

  test('빠른 하차 안내: 규약 미검증 노선도 빈 direction hint는 매칭한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _insertVerifiedNetworkEdge(
      database,
      id: 'ride-a-b-line-test',
      fromNodeId: 'station-a:line-test',
      toNodeId: 'station-b:line-test',
      edgeType: 'RIDE',
      durationSeconds: 90,
    );
    // 빈 direction hint는 방향 무관이므로 미검증 노선에서도 매칭된다.
    await database.customStatement('''
      INSERT INTO station_car_door_hints (
        id, station_id, line_id, direction, target_facility_type,
        car_number, door_number, verification_status
      ) VALUES (
        'cardoor-unverified-empty', 'station-b', 'line-test', '', 'ELEVATOR',
        3, 4, 'OFFICIAL'
      )
    ''');

    final result = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-a',
            destinationStationId: 'station-b',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    final ride = result.steps.firstWhere((s) => s.stepType == 'ride');
    expect(ride.carDoorCarNumber, 3);
    expect(ride.carDoorDoorNumber, 4);
  });
}

Map<String, Object?> _routeV2Payload({
  String status = 'FOUND',
  List<Object?> reasonCodes = const <Object?>[],
}) {
  return {
    'contractVersion': 'ROUTE_SEARCH_V2',
    'originStationId': 'station-sangnoksu',
    'destinationStationId': 'station-sadang',
    'departureTime': '2026-07-01T09:00:00+09:00',
    'mobilityType': 'WHEELCHAIR',
    'constraintMode': 'STRICT_STEP_FREE',
    'useRealtime': true,
    'maxTransfers': 3,
    'alternativeCount': 1,
    'statuses': [status],
    'itineraries': [
      {
        'itineraryId': 'route-v2-primary',
        'status': status,
        'plannedArrivalTime': '2026-07-01T09:15:00+09:00',
        'realtimeArrivalTime': '2026-07-01T09:13:00+09:00',
        'etaSource': 'REALTIME',
        'etaConfidence': 'HIGH',
        'durationSeconds': 780,
        'transferCount': 0,
        'walkingDistanceMeters': 180,
        'accessibilityRisk': {
          'stairCount': 0,
          'unknownAccessibilityCount': 0,
          'generatedConnectorCount': 0,
          'staleDataCount': 0,
          'lowConfidenceCount': 0,
          'unavailableFacilityCount': 0,
          'riskLevel': 'LOW',
          'reasonCodes': reasonCodes,
          'level': 'LOW',
          'reasons': reasonCodes,
        },
        'legs': [
          {
            'legType': 'ACCESS',
            'fromStationId': 'station-sangnoksu',
            'toStationId': 'station-sangnoksu',
            'fromNodeId': '',
            'toNodeId': '',
            'lineId': '',
            'tripId': '',
            'trainNo': '',
            'plannedDepartureTime': '2026-07-01T09:00:00+09:00',
            'realtimeDepartureTime': null,
            'plannedArrivalTime': '2026-07-01T09:01:00+09:00',
            'realtimeArrivalTime': null,
            'waitTimeSeconds': 0,
            'slackSeconds': 0,
            'durationSeconds': 60,
            'distanceMeters': 20,
            'etaSource': 'PLANNED',
            'confidence': 'HIGH',
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
            'legType': 'RIDE',
            'fromStationId': 'station-sangnoksu',
            'toStationId': 'station-sadang',
            'fromNodeId': '',
            'toNodeId': '',
            'lineId': 'seoul-4',
            'tripId': 'trip-1',
            'trainNo': '401',
            'plannedDepartureTime': '2026-07-01T09:00:00+09:00',
            'realtimeDepartureTime': '2026-07-01T09:00:30+09:00',
            'plannedArrivalTime': '2026-07-01T09:15:00+09:00',
            'realtimeArrivalTime': '2026-07-01T09:13:00+09:00',
            'waitTimeSeconds': 30,
            'slackSeconds': 60,
            'durationSeconds': 780,
            'distanceMeters': 180,
            'etaSource': 'REALTIME',
            'confidence': 'HIGH',
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
        'commercialEtaEligible': status == 'FOUND',
      },
    ],
  };
}

Map<String, Object?> _routeRefreshPayload() {
  return {
    'routeSearchId': 'route-v2',
    'status': 'UPDATED_ETA',
    'route': {
      'routeSearchId': 'route-v2',
      'originStationId': 'station-sangnoksu',
      'originStationName': '상록수',
      'destinationStationId': 'station-sadang',
      'destinationStationName': '사당',
      'mobilityType': 'WHEELCHAIR',
      'status': 'FOUND',
      'lineId': 'seoul-4',
      'lineName': '수도권 4호선',
      'score': 96,
      'burdenCost': 780,
      'estimatedDurationSeconds': 780,
      'walkingDistanceMeters': 180,
      'transferCount': 0,
      'evidenceSummary': ['ETA_REALTIME'],
      'steps': <Object?>[],
      'warnings': <Object?>[],
      'recommendationReasons': ['실시간 도착 정보를 반영했어요.'],
      'blockedReasons': <Object?>[],
      'createdAt': '2026-07-01T09:00:00+09:00',
      'etaSource': 'REALTIME',
    },
    'refreshedAt': '2026-07-01T09:01:00',
    'etaSource': 'REALTIME',
    'etaConfidence': 'HIGH',
    'sourceLabel': '실시간 도착 정보 기준',
    'reasonCodes': <Object?>[],
  };
}

Future<void> _seedLineWithoutNetworkEdges(
  CatalogDatabase database, {
  bool includeExplicitAccessEdges = true,
  bool fillInsertedNetworkEdgeEvidence = true,
}) async {
  await database.customStatement('''
    INSERT INTO catalog_metadata (key, value, updated_at)
    VALUES ('schemaVersion', '1', 1771459200000)
  ''');
  await database.customStatement('''
    INSERT INTO operators (id, name_ko, name_en)
    VALUES ('operator-test', '테스트 운영사', 'Test Operator')
  ''');
  await database.customStatement('''
    INSERT INTO lines (id, operator_id, name_ko, name_en, color)
    VALUES ('line-test', 'operator-test', '테스트 노선', 'Test Line', '#123456')
  ''');
  for (final station in const [
    ('station-a', '출발역', 1),
    ('station-b', '중간역', 2),
    ('station-c', '도착역', 3),
  ]) {
    await database.customStatement(
      '''
        INSERT INTO stations (
          id, name_ko, name_en, normalized_name, region,
          data_quality_level, data_source_type
        )
        VALUES (?, ?, ?, ?, '수도권', 'LEVEL_2', 'OFFICIAL_FILE')
      ''',
      [station.$1, station.$2, station.$2, station.$2],
    );
    await database.customStatement(
      '''
        INSERT INTO station_lines (
          station_id, line_id, station_code, line_sequence, platform_info
        )
        VALUES (?, 'line-test', ?, ?, '')
      ''',
      [station.$1, station.$3.toString(), station.$3],
    );
  }
  if (includeExplicitAccessEdges) {
    await _addExplicitAccessEdges(database);
  }
  if (fillInsertedNetworkEdgeEvidence) {
    await _fillInsertedNetworkEdgeEvidence(database);
  }
}

Future<void> _allowOutOfStationTransfer(
  CatalogDatabase database,
  String pairId,
) async {
  await database.customStatement(
    '''
      INSERT INTO catalog_metadata (key, value, updated_at)
      VALUES
        ('route.outOfStationTransfer.enabled', 'true', 1781827200),
        ('route.outOfStationTransfer.allowlist', ?, 1781827200)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    ''',
    [pairId],
  );
}

Future<void> _setOutOfStationTransferRuntimeEnabled(
  CatalogDatabase database,
  bool enabled,
) async {
  await database.customStatement(
    '''
      INSERT INTO catalog_metadata (key, value, updated_at)
      VALUES ('route.outOfStationTransfer.runtimeEnabled', ?, 1781827200)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
    ''',
    [enabled ? 'true' : 'false'],
  );
}

Future<void> _fillInsertedNetworkEdgeEvidence(CatalogDatabase database) async {
  await database.customStatement('''
    CREATE TRIGGER test_fill_network_edge_evidence
    AFTER INSERT ON network_edges
    WHEN NEW.source_id = ''
    BEGIN
      UPDATE network_edges
      SET source_id = 'test-source',
          source_snapshot_id = 'test-source-snapshot',
          provider_record_hash =
            'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
          provenance_kind = 'OFFICIAL_SOURCE',
          verification_status = 'VERIFIED',
          last_verified_at = COALESCE(NEW.last_verified_at, 1781827200),
          evidence_hash =
            '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      WHERE id = NEW.id
        AND source_id = '';
    END
  ''');
}

Future<void> _addExplicitAccessEdges(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO network_edges (
      id, from_node_id, to_node_id, duration_seconds, edge_type,
      stair_access_state, accessibility_status, reliability_score,
      source_id, source_snapshot_id, provider_record_hash, provenance_kind,
      verification_status, last_verified_at, evidence_hash
    )
    VALUES
      (
        'entry-station-a-line-test',
        'station-a',
        'station-a:line-test',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      ),
      (
        'exit-station-a-line-test',
        'station-a:line-test',
        'station-a',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      ),
      (
        'entry-station-b-line-test',
        'station-b',
        'station-b:line-test',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      ),
      (
        'exit-station-b-line-test',
        'station-b:line-test',
        'station-b',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      ),
      (
        'entry-station-c-line-test',
        'station-c',
        'station-c:line-test',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      ),
      (
        'exit-station-c-line-test',
        'station-c:line-test',
        'station-c',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      )
  ''');
}

Future<void> _insertVerifiedNetworkEdge(
  CatalogDatabase database, {
  required String id,
  required String fromNodeId,
  required String toNodeId,
  required String edgeType,
  required int durationSeconds,
  int distanceMeters = 0,
  String servicePattern = '',
  String serviceClass = 'SUBWAY',
  String verificationStatus = 'VERIFIED',
  String provenanceKind = 'OFFICIAL_SOURCE',
  int lastVerifiedAtSeconds = 1781827200,
  String evidenceHash =
      '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
}) async {
  await database.customStatement(
    '''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, distance_meters, edge_type,
        service_pattern, service_class, stair_access_state, accessibility_status, reliability_score,
        source_id, source_snapshot_id, provider_record_hash, provenance_kind,
        verification_status, last_verified_at, evidence_hash
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'STEP_FREE', 'AVAILABLE', 95, 'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        ?, ?, ?, ?)
    ''',
    [
      id,
      fromNodeId,
      toNodeId,
      durationSeconds,
      distanceMeters,
      edgeType,
      servicePattern,
      serviceClass,
      provenanceKind,
      verificationStatus,
      lastVerifiedAtSeconds,
      evidenceHash,
    ],
  );
}

Future<void> _addSecondLineForTransferFixture(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO lines (id, operator_id, name_ko, name_en, color)
    VALUES ('line-alt', 'operator-test', '대체 노선', 'Alt Line', '#654321')
  ''');
  for (final station in const [('station-a', 'A1'), ('station-c', 'C2')]) {
    await database.customStatement(
      '''
        INSERT INTO station_lines (
          station_id, line_id, station_code, line_sequence, platform_info
        )
        VALUES (?, 'line-alt', ?, 1, '')
      ''',
      [station.$1, station.$2],
    );
  }
  await database.customStatement('''
    INSERT INTO network_edges (
      id, from_node_id, to_node_id, duration_seconds, edge_type,
      stair_access_state, accessibility_status, reliability_score,
      source_id, source_snapshot_id, provider_record_hash, provenance_kind,
      verification_status, last_verified_at, evidence_hash
    )
    VALUES
      (
        'entry-station-a-line-alt',
        'station-a',
        'station-a:line-alt',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      ),
      (
        'exit-station-a-line-alt',
        'station-a:line-alt',
        'station-a',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      ),
      (
        'entry-station-c-line-alt',
        'station-c',
        'station-c:line-alt',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      ),
      (
        'exit-station-c-line-alt',
        'station-c:line-alt',
        'station-c',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95,
        'test-source',
        'test-source-snapshot',
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        'OFFICIAL_SOURCE',
        'VERIFIED',
        1781827200,
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      )
  ''');
}

Future<void> _addEligibleStationFacilityEvidence(
  CatalogDatabase database, {
  String stationId = 'station-a',
  String lineId = 'line-test',
  String facilityType = 'ELEVATOR',
}) async {
  await database.customStatement(
    '''
      INSERT INTO station_facility_evidence (
        station_id, line_id, facility_type, evidence_kind, source_id,
        source_snapshot_id, provider_record_hash, evidence_hash,
        provenance_kind, installation_status, operational_status,
        status_meaning, confidence, verified_at, retrieved_at,
        strict_route_eligible, strict_route_eligible_reason
      )
      VALUES (?, ?, ?, 'EXISTS', 'test-source', 'test-source-snapshot',
        'provider-hash', 'evidence-hash', 'OFFICIAL_SOURCE', 'INSTALLED',
        'AVAILABLE', 'REALTIME_OPERATION', 100, 1781827200, 1781827200, 1,
        'FACILITY_EXISTS_AND_PROVENANCE_VERIFIED')
    ''',
    [stationId, lineId, facilityType],
  );
}

Future<void> _seedAvailableFacilityRoute(CatalogDatabase database) async {
  await _seedLineWithoutNetworkEdges(database);
  await _addFacilityIdColumnIfMissing(database);
  await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, operational_status,
        floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'ADMIN_VERIFIED',
        'AVAILABLE',
        'B1',
        '1F',
        '관리자 검수 완료'
      )
    ''');
  await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          NULL
        )
    ''');
  await _addEligibleStationFacilityEvidence(database);
}

Future<void> _seedTwoLegRoute(CatalogDatabase database) async {
  await _seedLineWithoutNetworkEdges(database);
  await _addSecondLineForTransferFixture(database);
  await database.customStatement('''
    INSERT INTO station_lines (
      station_id, line_id, station_code, line_sequence, platform_info
    )
    VALUES ('station-b', 'line-alt', 'B2', 2, '')
  ''');
  await _insertVerifiedNetworkEdge(
    database,
    id: 'ride-a-b-test',
    fromNodeId: 'station-a:line-test',
    toNodeId: 'station-b:line-test',
    edgeType: 'RIDE',
    durationSeconds: 120,
  );
  await _insertVerifiedNetworkEdge(
    database,
    id: 'transfer-b-test-alt',
    fromNodeId: 'station-b:line-test',
    toNodeId: 'station-b:line-alt',
    edgeType: 'TRANSFER',
    durationSeconds: 60,
  );
  await _insertVerifiedNetworkEdge(
    database,
    id: 'ride-b-c-alt',
    fromNodeId: 'station-b:line-alt',
    toNodeId: 'station-c:line-alt',
    edgeType: 'RIDE',
    durationSeconds: 120,
  );
}

Future<void> _seedConsecutiveRideRoute(CatalogDatabase database) async {
  await _seedLineWithoutNetworkEdges(database);
  await _insertVerifiedNetworkEdge(
    database,
    id: 'ride-a-b-local',
    fromNodeId: 'station-a:line-test:LOCAL',
    toNodeId: 'station-b:line-test:LOCAL',
    edgeType: 'RIDE',
    durationSeconds: 300,
    servicePattern: 'LOCAL',
  );
  await _insertVerifiedNetworkEdge(
    database,
    id: 'ride-b-c-local',
    fromNodeId: 'station-b:line-test:LOCAL',
    toNodeId: 'station-c:line-test:LOCAL',
    edgeType: 'RIDE',
    durationSeconds: 300,
    servicePattern: 'LOCAL',
  );
}

Future<void> _seedConsecutiveRideTimetable(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO service_calendars (
      service_id, monday, tuesday, wednesday, thursday, friday,
      saturday, sunday, start_date, end_date
    )
    VALUES ('weekday-consecutive', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231')
  ''');
  await database.customStatement('''
    INSERT INTO transit_routes (id, line_id, route_short_name)
    VALUES ('route-consecutive', 'line-test', 'T')
  ''');
  await database.customStatement('''
    INSERT INTO transit_trips (id, route_id, service_id, service_pattern)
    VALUES ('trip-consecutive', 'route-consecutive', 'weekday-consecutive', 'LOCAL')
  ''');
  await database.customStatement('''
    INSERT INTO transit_stop_times (
      trip_id, stop_sequence, station_id, line_id,
      arrival_seconds, departure_seconds
    )
    VALUES
      ('trip-consecutive', 1, 'station-a', 'line-test', 28770, 28800),
      ('trip-consecutive', 2, 'station-b', 'line-test', 29100, 29130),
      ('trip-consecutive', 3, 'station-c', 'line-test', 29520, 29550)
  ''');
}

Future<void> _seedTwoLegTimetable(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO service_calendars (
      service_id, monday, tuesday, wednesday, thursday, friday,
      saturday, sunday, start_date, end_date
    )
    VALUES ('weekday-two-leg', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231')
  ''');
  await database.customStatement('''
    INSERT INTO transit_routes (id, line_id, route_short_name)
    VALUES ('route-test', 'line-test', 'T'), ('route-alt', 'line-alt', 'A')
  ''');
  await database.customStatement('''
    INSERT INTO transit_trips (id, route_id, service_id)
    VALUES
      ('trip-first', 'route-test', 'weekday-two-leg'),
      ('trip-alt-too-early', 'route-alt', 'weekday-two-leg'),
      ('trip-alt-boardable', 'route-alt', 'weekday-two-leg')
  ''');
  await database.customStatement('''
    INSERT INTO transit_stop_times (
      trip_id, stop_sequence, station_id, line_id,
      arrival_seconds, departure_seconds
    )
    VALUES
      ('trip-first', 1, 'station-a', 'line-test', 28770, 28800),
      ('trip-first', 2, 'station-b', 'line-test', 29400, 29430),
      ('trip-alt-too-early', 1, 'station-b', 'line-alt', 29070, 29100),
      ('trip-alt-too-early', 2, 'station-c', 'line-alt', 29700, 29730),
      ('trip-alt-boardable', 1, 'station-b', 'line-alt', 29490, 29520),
      ('trip-alt-boardable', 2, 'station-c', 'line-alt', 30120, 30150)
  ''');
}

Future<void> _seedBaselineTimetable(CatalogDatabase database) async {
  await database.customStatement('''
      INSERT INTO service_calendars (
        service_id, monday, tuesday, wednesday, thursday, friday,
        saturday, sunday, start_date, end_date
      )
      VALUES (
        'weekday-service', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231'
      )
    ''');
  await database.customStatement('''
      INSERT INTO transit_routes (
        id, line_id, route_short_name, route_long_name, direction_name
      )
      VALUES (
        'route-seoul-4-down', 'seoul-4', '4', '4호선 상록수-사당', '사당 방면'
      )
    ''');
  await database.customStatement('''
      INSERT INTO transit_trips (
        id, route_id, service_id, trip_headsign, direction_id, service_pattern
      )
      VALUES (
        'trip-seoul-4-sangnoksu-sadang',
        'route-seoul-4-down',
        'weekday-service',
        '사당',
        'UP',
        'LOCAL'
      )
    ''');
  await database.customStatement('''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id, arrival_seconds,
        departure_seconds
      )
      VALUES
        (
          'trip-seoul-4-sangnoksu-sadang',
          1,
          'station-sangnoksu',
          'seoul-4',
          28800,
          28830
        ),
        (
          'trip-seoul-4-sangnoksu-sadang',
          2,
          'station-sadang',
          'seoul-4',
          29520,
          29550
        )
    ''');
}

Future<void> _insertBaselineTrip(
  CatalogDatabase database, {
  required String tripId,
  required int departureSeconds,
  required int arrivalSeconds,
  int pickupType = 0,
  int dropOffType = 0,
}) async {
  await database.customStatement(
    '''
      INSERT INTO transit_trips (
        id, route_id, service_id, trip_headsign, direction_id, service_pattern
      )
      VALUES (?, 'route-seoul-4-down', 'weekday-service', '사당', 'UP', 'LOCAL')
    ''',
    [tripId],
  );
  await database.customStatement(
    '''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id, arrival_seconds,
        departure_seconds, pickup_type, drop_off_type
      )
      VALUES
        (?, 1, 'station-sangnoksu', 'seoul-4', ?, ?, ?, 0),
        (?, 2, 'station-sadang', 'seoul-4', ?, ?, 0, ?)
    ''',
    [
      tripId,
      departureSeconds - 30,
      departureSeconds,
      pickupType,
      tripId,
      arrivalSeconds,
      arrivalSeconds + 30,
      dropOffType,
    ],
  );
}

Future<void> _seedRealtimeMapping(
  CatalogDatabase database, {
  bool supportsArrivals = true,
}) async {
  final supportsArrivalsValue = supportsArrivals ? 1 : 0;
  await database.customStatement('''
      INSERT INTO realtime_provider_line_mappings (
        provider_id, provider_line_id, line_id, source_id,
        supports_arrivals, mapping_confidence
      )
      VALUES (
        'seoul-topis', '4', 'seoul-4', 'test-realtime-source',
        $supportsArrivalsValue, 'OFFICIAL'
      )
    ''');
  await database.customStatement('''
      INSERT INTO realtime_provider_station_mappings (
        provider_id, provider_line_id, provider_station_id, station_id,
        line_id, source_id, query_name, supports_arrivals, mapping_confidence
      )
      VALUES
        (
          'seoul-topis', '4', 'topis-sangnoksu', 'station-sangnoksu',
          'seoul-4', 'test-realtime-source', '상록수',
          $supportsArrivalsValue, 'OFFICIAL'
        ),
        (
          'seoul-topis', '4', 'topis-sadang', 'station-sadang',
          'seoul-4', 'test-realtime-source', '사당',
          $supportsArrivalsValue, 'OFFICIAL'
        )
    ''');
}

Future<void> _addFacilityStatusSnapshot(
  CatalogDatabase database, {
  required String id,
  required String providerId,
  required String sourceId,
  required String sourceSnapshotId,
  required String status,
  required String operationalStatus,
  required int observedAtSeconds,
  required int expiresAtSeconds,
  int confidence = 100,
}) async {
  await database.customStatement(
    '''
      INSERT INTO facility_status_snapshots (
        id, facility_id, provider_id, source_id, source_snapshot_id,
        provider_record_hash, evidence_hash, provenance_kind,
        verification_status, status, operational_status, confidence,
        observed_at, expires_at
      )
      VALUES (
        ?, 'facility-a-elevator', ?, ?, ?,
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        'OFFICIAL_SOURCE', 'VERIFIED', ?, ?, ?, ?, ?
      )
    ''',
    [
      id,
      providerId,
      sourceId,
      sourceSnapshotId,
      status,
      operationalStatus,
      confidence,
      observedAtSeconds,
      expiresAtSeconds,
    ],
  );
}

Future<void> _addFacilityIdColumnIfMissing(CatalogDatabase database) async {
  final columns = await database
      .customSelect('PRAGMA table_info(network_edges)')
      .get();
  final hasFacilityId = columns.any(
    (row) => row.read<String>('name') == 'facility_id',
  );
  if (!hasFacilityId) {
    await database.customStatement(
      'ALTER TABLE network_edges ADD COLUMN facility_id TEXT',
    );
  }
}

Future<void> _addDistanceMetersColumnIfMissing(CatalogDatabase database) async {
  final columns = await database
      .customSelect('PRAGMA table_info(network_edges)')
      .get();
  final hasDistanceMeters = columns.any(
    (row) => row.read<String>('name') == 'distance_meters',
  );
  if (!hasDistanceMeters) {
    await database.customStatement(
      'ALTER TABLE network_edges ADD COLUMN distance_meters INTEGER NOT NULL DEFAULT 0',
    );
  }
}
