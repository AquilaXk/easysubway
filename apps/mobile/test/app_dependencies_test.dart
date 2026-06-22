import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
