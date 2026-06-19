import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('로컬 역 검색은 역명과 역 suffix, 영문명, 역 번호, 노선명 검색어를 같은 역으로 찾는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = DriftStationRepository(database: database);

    for (final query in ['상록수', '상록수역', 'Sangnoksu', '448', '4호선 상록수']) {
      final results = await repository.searchStations(query);

      expect(results, hasLength(1), reason: query);
      expect(results.single.id, 'station-sangnoksu', reason: query);
      expect(results.single.nameKo, '상록수', reason: query);
      expect(results.single.lines.single.stationCode, '448', reason: query);
    }
  });

  test('주변 역 검색은 로컬 좌표로 거리순 정렬과 limit을 적용한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = DriftStationRepository(database: database);

    final results = await repository.searchNearbyStations(
      const CurrentLocation(latitude: 37.3028, longitude: 126.8666),
      radiusMeters: 30000,
      limit: 1,
    );

    expect(results, hasLength(1));
    expect(results.single.id, 'station-sangnoksu');
    expect(results.single.distanceMeters, isNotNull);
  });

  test('역 상세와 출구, 시설 정보는 로컬 카탈로그의 품질/검증일을 유지한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = DriftStationRepository(database: database);

    final detail = await repository.getStationDetail('station-sangnoksu');
    final exits = await repository.listStationExits('station-sangnoksu');
    final facilities = await repository.listStationFacilities(
      'station-sangnoksu',
    );

    expect(detail.nameKo, '상록수');
    expect(detail.latitude, closeTo(37.3028, 0.001));
    expect(detail.longitude, closeTo(126.8666, 0.001));
    expect(detail.dataQualityLevel, 'LEVEL_2');
    expect(detail.lastVerifiedAt, '2026-06-19');
    expect(exits.single.name, '1번 출구');
    expect(exits.single.hasElevatorConnection, isTrue);
    expect(facilities.single.type, 'ELEVATOR');
    expect(facilities.single.lastUpdatedAt, '2026-06-19');
  });

  test('앱 기본 의존성은 catalog DB가 있으면 로컬 역 repository를 사용한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    final dependencies = AppDependencies.resolve(
      catalogDatabase: database,
      enableAnonymousAuth: false,
      enablePushNotifications: false,
    );

    expect(dependencies.repository, isA<DriftStationRepository>());
  });
}
