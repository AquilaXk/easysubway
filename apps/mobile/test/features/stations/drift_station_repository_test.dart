import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('로컬 역 검색은 역명·역 suffix·영문명만으로 찾는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = DriftStationRepository(database: database);

    for (final query in ['상록수', '상록수역', 'Sangnoksu']) {
      final results = await repository.searchStations(query);

      expect(results, hasLength(1), reason: query);
      expect(results.single.id, 'station-sangnoksu', reason: query);
      expect(results.single.nameKo, '상록수', reason: query);
      expect(results.single.lines.single.stationCode, '448', reason: query);
    }
  });

  test('로컬 역 검색은 초성 질의로 역명 접두를 찾는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement(
      "INSERT INTO stations "
      "(id, name_ko, name_en, name_sub, normalized_name, region, "
      "data_quality_level, data_source_type) "
      "VALUES "
      "('station-surisan', '수리산', 'Surisan', '', '수리산', "
      "'수도권', 'LEVEL_1', 'OFFICIAL_FILE'), "
      "('station-sanbon', '산본', 'Sanbon', '', '산본', "
      "'수도권', 'LEVEL_1', 'OFFICIAL_FILE'), "
      "('station-seomyeon', '서면', 'Seomyeon', '', '서면', "
      "'부산', 'LEVEL_1', 'OFFICIAL_FILE')",
    );
    final repository = DriftStationRepository(database: database);

    final byS = await repository.searchStations('ㅅ');
    expect(byS.map((s) => s.nameKo), containsAll(['수리산', '산본', '상록수']));

    final bySb = await repository.searchStations('ㅅㅂ');
    expect(bySb.map((s) => s.nameKo), contains('산본'));
    expect(bySb.map((s) => s.nameKo), isNot(contains('수리산')));

    final busanOnly = await repository.searchStations('ㅅ', region: '부산');
    expect(busanOnly.map((s) => s.nameKo), contains('서면'));
    expect(busanOnly.map((s) => s.region), everyElement('부산'));
  });

  test('로컬 역 검색은 호선명·역번호만으로는 결과를 내지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = DriftStationRepository(database: database);

    for (final query in ['448', '4호선', '4호선 상록수', '수인분당선']) {
      final results = await repository.searchStations(query);

      expect(results, isEmpty, reason: query);
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

  test('로컬 역 검색은 warm 전후·중복 warm에서 결과 집합과 순서가 같다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement(
      "INSERT INTO stations "
      "(id, name_ko, name_en, name_sub, normalized_name, region, "
      "data_quality_level, data_source_type) "
      "VALUES "
      "('station-surisan', '수리산', 'Surisan', '', '수리산', "
      "'수도권', 'LEVEL_1', 'OFFICIAL_FILE'), "
      "('station-sanbon', '산본', 'Sanbon', '', '산본', "
      "'수도권', 'LEVEL_1', 'OFFICIAL_FILE')",
    );
    final repository = DriftStationRepository(database: database);

    Future<List<String>> idsFor(String query) async {
      final results = await repository.searchStations(query);
      return results.map((station) => station.id).toList(growable: false);
    }

    final beforeWarm = await idsFor('ㅅ');
    await Future.wait([
      repository.warmSearchCache(),
      repository.warmSearchCache(),
    ]);
    final afterWarm = await idsFor('ㅅ');
    final afterSecondSearch = await idsFor('ㅅ');

    expect(afterWarm, beforeWarm);
    expect(afterSecondSearch, beforeWarm);
    expect(await idsFor('상'), await idsFor('상'));
  });

  test('로컬 역 검색은 중간 문자열(substring) 매칭을 유지한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement(
      "INSERT INTO stations "
      "(id, name_ko, name_en, name_sub, normalized_name, region, "
      "data_quality_level, data_source_type) "
      "VALUES "
      "('station-mid-sangnok', '테스트상록중앙', 'MidSangnok', '', "
      "'테스트상록중앙', '수도권', 'LEVEL_1', 'OFFICIAL_FILE')",
    );
    final repository = DriftStationRepository(database: database);

    final results = await repository.searchStations('상록');
    expect(
      results.map((station) => station.id),
      contains('station-mid-sangnok'),
    );
    expect(results.map((station) => station.id), contains('station-sangnoksu'));
  });

  test('로컬 역 검색은 결과 상한 40과 완전일치 예외를 지킨다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final buffer = StringBuffer();
    for (var i = 0; i < 50; i++) {
      if (i > 0) {
        buffer.write(', ');
      }
      final id = 'station-bulk-$i';
      final name = '상테스트$i';
      buffer.write(
        "('$id', '$name', 'Sang$i', '', '$name', "
        "'수도권', 'LEVEL_1', 'OFFICIAL_FILE')",
      );
    }
    await database.customStatement(
      "INSERT INTO stations "
      "(id, name_ko, name_en, name_sub, normalized_name, region, "
      "data_quality_level, data_source_type) "
      "VALUES ${buffer.toString()}",
    );
    final repository = DriftStationRepository(database: database);

    final prefixResults = await repository.searchStations('상');
    expect(prefixResults.length, lessThanOrEqualTo(40));

    // 동명 완전일치가 40을 넘어도 잘리지 않는다.
    final exactBuffer = StringBuffer();
    for (var i = 0; i < 45; i++) {
      if (i > 0) {
        exactBuffer.write(', ');
      }
      exactBuffer.write(
        "('station-exact-$i', '동일역명', 'Same$i', '', '동일역명', "
        "'수도권', 'LEVEL_1', 'OFFICIAL_FILE')",
      );
    }
    await database.customStatement(
      "INSERT INTO stations "
      "(id, name_ko, name_en, name_sub, normalized_name, region, "
      "data_quality_level, data_source_type) "
      "VALUES ${exactBuffer.toString()}",
    );
    repository.invalidateStationSummaryCache();
    final exactResults = await repository.searchStations('동일역명');
    expect(exactResults.length, greaterThanOrEqualTo(45));
    expect(exactResults.every((station) => station.nameKo == '동일역명'), isTrue);
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
    expect(exits.single.latitude, closeTo(37.3021, 0.0001));
    expect(exits.single.longitude, closeTo(126.8661, 0.0001));
    expect(exits.single.hasElevatorConnection, isTrue);
    expect(exits.single.lastVerifiedAt, '2026-06-19');
    final elevator = facilities.singleWhere(
      (facility) => facility.id == 'facility-sangnoksu-elevator-1',
    );
    expect(elevator.type, 'ELEVATOR');
    expect(elevator.lastUpdatedAt, '2026-06-19');
  });

  test('흡수된 station ID로 상세·출구·시설을 요청해도 대표 역을 반환한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sangnoksu', 'station-sangnoksu-old', 'station-sangnoksu-old')
    ''');
    final repository = DriftStationRepository(database: database);

    final detail = await repository.getStationDetail('station-sangnoksu-old');
    final exits = await repository.listStationExits('station-sangnoksu-old');
    final facilities = await repository.listStationFacilities(
      'station-sangnoksu-old',
    );

    expect(detail.id, 'station-sangnoksu');
    expect(exits, isNotEmpty);
    expect(facilities, isNotEmpty);
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

  test('로컬 역 시간표는 요일 유형별 출발을 방향으로 묶고 첫차와 막차를 보존한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    final repository = DriftStationRepository(database: database);

    final timetable = await repository.loadStationTimetable(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.weekday,
      referenceDate: DateTime(2026, 7, 12),
    );

    expect(timetable.isAvailable, isTrue);
    expect(timetable.dayType.label, '평일');
    expect(
      timetable.directions.map((direction) => direction.name),
      unorderedEquals(['상록수 방면', '사당 방면']),
    );
    final sadang = timetable.directions.singleWhere(
      (direction) => direction.name == '사당 방면',
    );
    expect(sadang.departures.map((departure) => departure.timeLabel), [
      '05:20',
      '다음 날 00:25',
    ]);
    expect(sadang.firstDeparture.timeLabel, '05:20');
    expect(sadang.lastDeparture.timeLabel, '다음 날 00:25');
    expect(sadang.lastDeparture.semanticLabel, '사당 방면, 다음 날 00시 25분 출발');
  });

  test('로컬 역 시간표는 ITX trip을 지하철 출발로 노출하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    await database.customStatement('''
      INSERT INTO transit_routes (
        id, line_id, route_short_name, route_long_name, direction_name, timezone
      ) VALUES (
        'itx-route-1919', 'seoul-4', 'ITX-청춘', '청량리 → 춘천',
        'ITX 춘천 방면', 'Asia/Seoul'
      )
    ''');
    await database.customStatement('''
      INSERT INTO transit_trips (
        id, route_id, service_id, trip_headsign, direction_id,
        service_pattern, service_class, service_day_start_seconds
      ) VALUES (
        'itx-trip-1919', 'itx-route-1919', 'weekday-1919', '춘천', 'down',
        'EXPRESS', 'ITX_CHEONGCHUN', 0
      )
    ''');
    await database.customStatement('''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id,
        arrival_seconds, departure_seconds, pickup_type, drop_off_type
      ) VALUES (
        'itx-trip-1919', 1, 'station-sadang', 'seoul-4', 19140, 19140, 0, 0
      )
    ''');
    final repository = DriftStationRepository(database: database);

    final timetable = await repository.loadStationTimetable(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.weekday,
      referenceDate: DateTime(2026, 7, 12),
    );

    expect(
      timetable.directions.map((direction) => direction.name),
      isNot(contains('ITX 춘천 방면')),
    );
  });

  test('로컬 역 시간표는 지하철 급행·일반 운행종별을 손실 없이 전달한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    await database.customStatement('''
      INSERT INTO transit_trips (
        id, route_id, service_id, trip_headsign, direction_id,
        service_pattern, service_class, service_day_start_seconds
      ) VALUES (
        'weekday-down-1919-express', 'line4-down-1919', 'weekday-1919', '사당', 'down',
        'EXPRESS', 'SUBWAY', 0
      )
    ''');
    await database.customStatement('''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id,
        arrival_seconds, departure_seconds, pickup_type, drop_off_type
      ) VALUES (
        'weekday-down-1919-express', 1, 'station-sadang', 'seoul-4', 19260, 19260, 0, 0
      )
    ''');
    final repository = DriftStationRepository(database: database);

    final timetable = await repository.loadStationTimetable(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.weekday,
      referenceDate: DateTime(2026, 7, 12),
    );

    final sadang = timetable.directions.singleWhere(
      (direction) => direction.name == '사당 방면',
    );
    final express = sadang.departures.singleWhere(
      (departure) => departure.isExpress,
    );
    expect(express.timeLabel, '05:21');
    expect(express.servicePattern, 'EXPRESS');
    expect(express.serviceClass, 'SUBWAY');
    final local = sadang.departures.singleWhere(
      (departure) => departure.timeLabel == '05:20',
    );
    expect(local.isExpress, isFalse);
    expect(local.servicePattern, 'LOCAL');
    expect(local.serviceClass, 'SUBWAY');
  });

  test('로컬 역 시간표는 소문자·공백 service_class도 지하철 출발로 매칭한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    // 저장소 레벨 정규화(trim/upper)와 비대칭인 정확 일치 SQL이 소문자·공백 값을
    // 조용히 누락하지 않는지 검증한다.
    await database.customStatement('''
      INSERT INTO transit_trips (
        id, route_id, service_id, trip_headsign, direction_id,
        service_pattern, service_class, service_day_start_seconds
      ) VALUES (
        'weekday-down-1919-messy', 'line4-down-1919', 'weekday-1919', '사당', 'down',
        'LOCAL', '  subway  ', 0
      )
    ''');
    await database.customStatement('''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id,
        arrival_seconds, departure_seconds, pickup_type, drop_off_type
      ) VALUES (
        'weekday-down-1919-messy', 1, 'station-sadang', 'seoul-4', 19380, 19380, 0, 0
      )
    ''');
    final repository = DriftStationRepository(database: database);

    final timetable = await repository.loadStationTimetable(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.weekday,
      referenceDate: DateTime(2026, 7, 12),
    );

    final sadang = timetable.directions.singleWhere(
      (direction) => direction.name == '사당 방면',
    );
    final messy = sadang.departures.singleWhere(
      (departure) => departure.timeLabel == '05:23',
    );
    expect(messy.serviceClass, 'SUBWAY');
    expect(messy.servicePattern, 'LOCAL');
  });

  test('로컬 역 시간표는 지하철 미상·공백 운행종별을 경계에서 실패시킨다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    await database.customStatement('''
      INSERT INTO transit_trips (
        id, route_id, service_id, trip_headsign, direction_id,
        service_pattern, service_class, service_day_start_seconds
      ) VALUES (
        'weekday-down-1919-unknown', 'line4-down-1919', 'weekday-1919', '사당', 'down',
        '', 'SUBWAY', 0
      )
    ''');
    await database.customStatement('''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id,
        arrival_seconds, departure_seconds, pickup_type, drop_off_type
      ) VALUES (
        'weekday-down-1919-unknown', 1, 'station-sadang', 'seoul-4', 19320, 19320, 0, 0
      )
    ''');
    final repository = DriftStationRepository(database: database);

    await expectLater(
      repository.loadStationTimetable(
        stationId: 'station-sadang',
        lineId: 'seoul-4',
        dayType: StationTimetableDayType.weekday,
        referenceDate: DateTime(2026, 7, 12),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('흡수된 station ID로도 대표 역 시간표를 반환한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    await database.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sadang', 'station-sadang-old', 'station-sadang-old')
    ''');
    final repository = DriftStationRepository(database: database);

    final selectedDay = await repository.loadStationTimetable(
      stationId: 'station-sadang-old',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.weekday,
      referenceDate: DateTime(2026, 7, 12),
    );
    final automaticDay = await repository.loadStationTimetableForDate(
      stationId: 'station-sadang-old',
      lineId: 'seoul-4',
      date: DateTime(2026, 7, 7),
    );

    expect(selectedDay.stationId, 'station-sadang');
    expect(selectedDay.isAvailable, isTrue);
    expect(automaticDay.stationId, 'station-sadang');
    expect(automaticDay.isAvailable, isTrue);
  });

  test('로컬 역 시간표는 토요일과 일요일·공휴일 calendar를 분리하고 미지원 역을 강등한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    final repository = DriftStationRepository(database: database);

    final saturday = await repository.loadStationTimetable(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.saturday,
      referenceDate: DateTime(2026, 7, 12),
    );
    final holiday = await repository.loadStationTimetable(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.sundayHoliday,
      referenceDate: DateTime(2026, 7, 12),
    );
    final unavailable = await repository.loadStationTimetable(
      stationId: 'station-sangnoksu',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.weekday,
      referenceDate: DateTime(2026, 7, 12),
    );

    expect(saturday.directions.single.departures.single.timeLabel, '09:12');
    expect(holiday.directions.single.departures.single.timeLabel, '10:30');
    expect(unavailable.isAvailable, isFalse);
    expect(unavailable.directions, isEmpty);
  });

  test('로컬 역 시간표는 평일 공휴일 exception을 일요일·공휴일로 자동 선택한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    await database.customStatement('''
      INSERT INTO service_calendar_dates (service_id, date, exception_type)
      VALUES ('weekday-1919', '20260817', 2),
             ('holiday-1919', '20260817', 1)
    ''');
    final repository = DriftStationRepository(database: database);

    final timetable = await repository.loadStationTimetableForDate(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      date: DateTime(2026, 8, 17),
    );

    expect(timetable.dayType, StationTimetableDayType.sundayHoliday);
    expect(timetable.directions.single.departures.single.timeLabel, '10:30');
  });

  test('로컬 역 시간표는 Asia/Seoul service date로 요일을 선택한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    final repository = DriftStationRepository(database: database);

    final timetable = await repository.loadStationTimetableForDate(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      date: DateTime.utc(2026, 7, 6, 15, 30),
    );

    expect(timetable.dayType, StationTimetableDayType.weekday);
    expect(
      timetable.directions
          .singleWhere((direction) => direction.name == '사당 방면')
          .firstDeparture
          .timeLabel,
      '05:20',
    );
  });

  test('로컬 역 요일 시간표는 feed 만료 뒤 출발을 반환하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await _seedStationTimetable(database);
    final repository = DriftStationRepository(database: database);

    final timetable = await repository.loadStationTimetable(
      stationId: 'station-sadang',
      lineId: 'seoul-4',
      dayType: StationTimetableDayType.weekday,
      referenceDate: DateTime(2027, 1, 1),
    );

    expect(timetable.isAvailable, isFalse);
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

    final map = await repository.getNetworkMap(
      region: '수도권',
      lineId: 'seoul-4',
    );
    final track = map.lineTracks.singleWhere(
      (track) => track.lineId == 'seoul-4',
    );

    expect(track.paths, ['M 0 0 L 10 0', 'M 20 0 L 30 0']);
  });
}

Future<void> _seedStationTimetable(CatalogDatabase database) async {
  await database.customStatement('''
    CREATE TABLE transit_feed_info (
      id INTEGER PRIMARY KEY,
      feed_end_date TEXT NOT NULL
    )
  ''');
  await database.customStatement(
    "INSERT INTO transit_feed_info (id, feed_end_date) VALUES (1, '20261231')",
  );
  await database.customStatement('''
    INSERT INTO service_calendars (
      service_id, monday, tuesday, wednesday, thursday, friday,
      saturday, sunday, start_date, end_date, timezone
    ) VALUES
      ('weekday-1919', 0, 1, 0, 0, 0, 0, 0, '20260101', '20261231', 'Asia/Seoul'),
      ('saturday-1919', 0, 0, 0, 0, 0, 1, 0, '20260101', '20261231', 'Asia/Seoul'),
      ('holiday-1919', 0, 0, 0, 0, 0, 0, 1, '20260101', '20261231', 'Asia/Seoul')
  ''');
  await database.customStatement('''
    INSERT INTO transit_routes (
      id, line_id, route_short_name, route_long_name, direction_name, timezone
    ) VALUES
      ('line4-up-1919', 'seoul-4', '4', '상록수 방면', '상록수 방면', 'Asia/Seoul'),
      ('line4-down-1919', 'seoul-4', '4', '사당 방면', '사당 방면', 'Asia/Seoul')
  ''');
  await database.customStatement('''
    INSERT INTO transit_trips (
      id, route_id, service_id, trip_headsign, direction_id,
      service_pattern, service_day_start_seconds
    ) VALUES
      ('weekday-up-1919', 'line4-up-1919', 'weekday-1919', '상록수', 'up', 'LOCAL', 0),
      ('weekday-down-1919-a', 'line4-down-1919', 'weekday-1919', '사당', 'down', 'LOCAL', 0),
      ('weekday-down-1919-b', 'line4-down-1919', 'weekday-1919', '사당', 'down', 'LOCAL', 0),
      ('saturday-down-1919', 'line4-down-1919', 'saturday-1919', '사당', 'down', 'LOCAL', 0),
      ('holiday-down-1919', 'line4-down-1919', 'holiday-1919', '사당', 'down', 'LOCAL', 0)
  ''');
  for (final row in <(String, int)>[
    ('weekday-up-1919', 19500),
    ('weekday-down-1919-a', 19200),
    ('weekday-down-1919-b', 87900),
    ('saturday-down-1919', 33120),
    ('holiday-down-1919', 37800),
  ]) {
    await database.customStatement(
      '''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id,
        arrival_seconds, departure_seconds, pickup_type, drop_off_type
      ) VALUES (?, 1, 'station-sadang', 'seoul-4', ?, ?, 0, 0)
      ''',
      [row.$1, row.$2, row.$2],
    );
  }
}
