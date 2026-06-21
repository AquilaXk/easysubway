import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('로컬 데이터베이스가 있으면 API 주소 없이도 앱 의존성을 만든다', () {
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

    expect(dependencies.repository, isA<DriftStationRepository>());
    expect(dependencies.routeRepository, isA<FallbackRouteSearchRepository>());
    expect(
      dependencies.reportRepository,
      isA<UnavailableFacilityReportRepository>(),
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
