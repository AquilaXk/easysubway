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

  test('로컬 역 검색은 부역명(name_sub)으로도 역을 찾는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement(
      "INSERT INTO stations "
      "(id, name_ko, name_en, name_sub, normalized_name, region, "
      "data_quality_level, data_source_type) "
      "VALUES ('station-gongneung', '공릉', '', '서울과학기술대', '공릉', "
      "'수도권', 'LEVEL_1', 'OFFICIAL_FILE')",
    );
    final repository = DriftStationRepository(database: database);

    final results = await repository.searchStations('서울과학기술대');

    expect(results, hasLength(1));
    expect(results.single.id, 'station-gongneung');
    expect(results.single.nameKo, '공릉');
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

  test('노선도 데이터는 label polygon metadata를 보존한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement(
      '''
      UPDATE route_map_positions
      SET label_polygon = ?
      WHERE station_id = ? AND line_id = ? AND region = ?
      ''',
      [
        '[{"x":166,"y":226},{"x":214,"y":226},{"x":214,"y":246},{"x":166,"y":246}]',
        'station-sangnoksu',
        'seoul-4',
        '수도권',
      ],
    );
    final repository = DriftStationRepository(database: database);

    final map = await repository.getNetworkMap(
      region: '수도권',
      lineId: 'seoul-4',
    );
    final sangnoksu = map.stations.singleWhere(
      (station) => station.id == 'station-sangnoksu',
    );

    expect(
      sangnoksu.position.labelPolygon,
      '[{"x":166,"y":226},{"x":214,"y":226},{"x":214,"y":246},{"x":166,"y":246}]',
    );
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
    expect(elevator.semanticLabel, isNot(contains('시설 상태가 확인됐어요')));
    expect(elevator.lastUpdatedAt, '2026-06-19');
    expect(escalator.dataConfidence, 'LOW');
    expect(escalator.semanticLabel, isNot(contains('최신 상태를 준비 중이에요')));
    expect(toilet.dataConfidence, 'LOW');
    expect(toilet.semanticLabel, isNot(contains('최신 상태를 준비 중이에요')));
  });

  test('상록수역 시설은 최신 현장 검증 record를 선택한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO data_quality_records (
        id,
        target_type,
        target_id,
        quality_level,
        checked_at
      )
      VALUES
        ('quality-facility-elevator-stale-newer', 'facility', 'facility-sangnoksu-elevator-1', 'FIELD_STALE', 1781913600),
        ('quality-facility-elevator-unknown-undated', 'facility', 'facility-sangnoksu-elevator-1', 'FIELD_UNKNOWN', NULL)
      ''');
    final repository = DriftStationRepository(database: database);

    final facilities = await repository.listStationFacilities(
      'station-sangnoksu',
    );

    final elevator = facilities.singleWhere(
      (facility) => facility.id == 'facility-sangnoksu-elevator-1',
    );
    expect(elevator.dataConfidence, 'LOW');
    expect(elevator.lastUpdatedAt, '2026-06-20');
    expect(elevator.semanticLabel, isNot(contains('최신 상태를 준비 중이에요')));
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

  test('노선도 데이터는 노선별 line track을 track index 순으로 로드한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    // track_index를 일부러 뒤집어 삽입 — ORDER BY track_index 검증.
    await database.customStatement(
      '''
      INSERT INTO route_map_line_tracks
        (region, line_id, track_index, path, svg_color, source_id, source_name,
         source_url, license, license_status, commercial_use_allowed, attribution_required)
      VALUES
        (?, ?, 1, 'M 20 0 L 30 0', '', 's', 'n', 'u', 'l', 'reviewed', 0, 1),
        (?, ?, 0, 'M 0 0 L 10 0', '', 's', 'n', 'u', 'l', 'reviewed', 0, 1)
      ''',
      ['수도권', 'seoul-4', '수도권', 'seoul-4'],
    );
    final repository = DriftStationRepository(database: database);

    final map = await repository.getNetworkMap(region: '수도권', lineId: 'seoul-4');
    final track = map.lineTracks.singleWhere(
      (track) => track.lineId == 'seoul-4',
    );

    expect(track.paths, ['M 0 0 L 10 0', 'M 20 0 L 30 0']);
  });
}
