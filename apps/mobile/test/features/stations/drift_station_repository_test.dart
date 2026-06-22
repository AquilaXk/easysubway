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

  test('로컬 역 검색은 빈 값과 결과 없는 검색어를 빈 목록으로 반환한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = DriftStationRepository(database: database);

    for (final query in ['', '   ', '없는역']) {
      final results = await repository.searchStations(query);

      expect(results, isEmpty, reason: query);
    }
  });

  test('노선 필터 검색과 노선 목록은 로컬 라인 매핑을 사용한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = DriftStationRepository(database: database);

    final lines = await repository.listLines();
    final line4 = lines.singleWhere((line) => line.id == 'seoul-4');

    expect(line4.name, '수도권 4호선');
    expect(line4.lineCode, '4');
    expect(line4.region, '수도권');
    expect(line4.active, isTrue);

    expect(
      await repository.searchStationsOnLine('상록수', 'seoul-4'),
      hasLength(1),
    );
    expect(await repository.searchStationsOnLine('', 'seoul-4'), isEmpty);
    expect(
      await repository.searchStationsOnLine('상록수', 'unknown-line'),
      isEmpty,
    );
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
    final elevator = facilities.singleWhere(
      (facility) => facility.id == 'facility-sangnoksu-elevator-1',
    );
    expect(elevator.type, 'ELEVATOR');
    expect(elevator.lastUpdatedAt, '2026-06-19');
  });

  test('상록수역 시설은 검증됨, 알 수 없음, 오래됨 현장 상태를 구분한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = DriftStationRepository(database: database);

    final facilities = await repository.listStationFacilities(
      'station-sangnoksu',
    );

    final elevator = facilities.singleWhere(
      (facility) => facility.id == 'facility-sangnoksu-elevator-1',
    );
    final escalator = facilities.singleWhere(
      (facility) => facility.id == 'facility-sangnoksu-escalator-1',
    );
    final toilet = facilities.singleWhere(
      (facility) => facility.id == 'facility-sangnoksu-accessible-toilet-1',
    );

    expect(elevator.dataConfidence, 'HIGH');
    expect(elevator.semanticLabel, contains('현장 검증됨'));
    expect(elevator.lastUpdatedAt, '2026-06-19');
    expect(escalator.dataConfidence, 'LOW');
    expect(escalator.semanticLabel, contains('현장 검증 전'));
    expect(toilet.dataConfidence, 'LOW');
    expect(toilet.semanticLabel, contains('현장 재확인 필요'));
  });

  test('존재하지 않는 역 상세 조회는 역 검색 예외를 던진다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = DriftStationRepository(database: database);

    expect(
      () => repository.getStationDetail('non-existent-station'),
      throwsA(isA<StationSearchException>()),
    );
  });

  test('앱 기본 의존성은 catalog DB가 있으면 로컬 역 repository를 사용한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    final dependencies = AppDependencies.resolve(
      catalogDatabase: database,
      enablePushNotifications: false,
    );

    expect(dependencies.repository, isA<DriftStationRepository>());
  });
}
