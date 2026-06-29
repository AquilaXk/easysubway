import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/main.dart' as app;
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release build는 demo home data flag를 허용하지 않는다', () {
    expect(
      () => app.validateReleaseBuildFlags(
        isReleaseMode: true,
        demoHomeDataEnabled: true,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('로컬 데이터베이스가 있으면 API 주소 없이도 경로 의존성이 동작한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () {
        throw StateError('Local catalog defaults must not read API base URL.');
      },
      enablePushNotifications: false,
    );

    expect(dependencies.repository, isA<DriftStationRepository>());
    expect(
      dependencies.reportRepository,
      isA<UnavailableFacilityReportRepository>(),
    );

    final routeResult = await dependencies.routeRepository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(routeResult.status, 'FOUND');
    expect(routeResult.isLocalResult, isTrue);

    final internalNodes = await dependencies.internalRouteRepository
        .listRouteNodes('station-sangnoksu');

    expect(internalNodes, isEmpty);
  });

  test('로컬 데이터베이스 기본 의존성은 시설 신고 fallback 때문에 API 주소를 읽지 않는다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    var apiBaseReads = 0;
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      apiBaseUri: () {
        apiBaseReads++;
        throw StateError('Local app defaults must not read API base URL.');
      },
      enablePushNotifications: false,
    );

    expect(apiBaseReads, 0);
    expect(dependencies.repository, isA<DriftStationRepository>());
  });

  test('로컬 데이터베이스와 API 주소가 있으면 실시간은 API를 호출한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    late Uri requestedUri;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);
    addTearDown(server.close);

    server.listen((request) {
      requestedUri = request.uri;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'FRESH',
              'receivedAt': '2026-06-26T08:00:00Z',
              'arrivals': <Object?>[],
            },
          }),
        )
        ..close();
    });

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      apiBaseUri: () =>
          Uri.parse('http://${server.address.host}:${server.port}'),
      enablePushNotifications: false,
    );

    await dependencies.realtimeRepository.arrivals(
      const RealtimeStationQuery(
        stationId: 'station-sangnoksu',
        lineId: '4',
        stationQueryName: '상록수',
      ),
    );

    expect(requestedUri.path, '/api/v1/realtime/arrivals');
    expect(requestedUri.queryParameters['stationId'], 'station-sangnoksu');
  });

  test('시설 신고 기본 의존성은 API 주소가 없으면 호출 시점에 unavailable로 동작한다', () async {
    final catalogDatabase = CatalogDatabase.memory();
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(catalogDatabase.close);
    addTearDown(userDatabase.close);

    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
      apiBaseUri: () => null,
      enablePushNotifications: false,
    );

    await expectLater(
      dependencies.reportRepository.createReport(
        const FacilityReportRequest(
          stationId: 'station-sangnoksu',
          facilityId: 'facility-elevator-sangnoksu-1',
          reportType: 'BROKEN',
          description: '승강기 고장',
        ),
      ),
      throwsA(isA<FacilityReportException>()),
    );
  });

  test('로컬 데이터베이스가 없으면 API 주소 없는 원격 fallback을 만들지 않는다', () {
    expect(
      () => AppDependencies.resolve(
        apiBaseUri: () => null,
        enablePushNotifications: false,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Release API base URL must be configured.',
        ),
      ),
    );
  });
}
