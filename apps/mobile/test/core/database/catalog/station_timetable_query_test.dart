import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/catalog/station_timetable_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;

/// `transit_feed_info`는 데이터팩만 제공하는 테이블이므로(#2530) 카탈로그는
/// "테이블 없음 / `feed_end_date` 열 없음 / 행 0 / 형식이 깨진 행 / 정상 행"
/// 상태를 모두 가진다. 각 상태의 시간표 조회 동작을 여기에서 못박는다.
void main() {
  group('transit_feed_info 테이블이 없는 카탈로그', () {
    test('요일을 지정한 조회가 예외 없이 유효기간 필터를 생략한다', () async {
      final database = await _openSeededCatalog();

      await _expectDayTypeDepartures(database);
    });

    test('요일을 지정하지 않은 조회는 모든 출발을 그대로 반환한다', () async {
      final database = await _openSeededCatalog();

      final departures = await CatalogStationTimetableQuery(
        database,
      ).loadDepartures(stationId: 'station-sadang', lineId: 'seoul-4');

      expect(
        departures.map((departure) => departure.seconds),
        unorderedEquals(_allDepartureSeconds),
      );
    });
  });

  group('transit_feed_info 테이블에 feed_end_date 열이 없는 카탈로그', () {
    test('피드 정보 없음으로 보고 유효기간 필터를 생략한다', () async {
      final database = await _openSeededCatalog();
      await database.customStatement(
        'CREATE TABLE transit_feed_info (id INTEGER PRIMARY KEY)',
      );

      await _expectDayTypeDepartures(database);
    });
  });

  group('transit_feed_info 테이블이 있고 행이 없는 카탈로그', () {
    test('피드 정보 없음으로 보고 유효기간 필터를 생략한다', () async {
      final database = await _openSeededCatalog();
      await _createTransitFeedInfo(database);

      await _expectDayTypeDepartures(database);
    });
  });

  group('transit_feed_info 행의 feed_end_date 형식이 깨진 카탈로그', () {
    test('NULL 값은 피드 정보 없음으로 보고 유효기간 필터를 생략한다', () async {
      final database = await _openSeededCatalog();
      await _createTransitFeedInfo(database, nullableFeedEndDate: true);
      await _insertFeedEndDate(database, null);

      await _expectDayTypeDepartures(database);
    });

    test('YYYYMMDD가 아닌 값은 피드 정보 없음으로 보고 유효기간 필터를 생략한다', () async {
      final database = await _openSeededCatalog();
      await _createTransitFeedInfo(database);
      await _insertFeedEndDate(database, '2026-12-31');

      await _expectDayTypeDepartures(database);
    });

    // 'Z0261231'은 기준일보다 문자열 비교에서 크다. 존재 판정과 조립되는 필터가
    // 같은 GLOB 조건을 쓰지 않으면 유효한 행이 만료됐는데도 필터가 통과한다.
    test('형식이 깨진 행과 유효한 행이 섞여 있으면 유효한 행 기준으로 필터한다', () async {
      final database = await _openSeededCatalog();
      await _createTransitFeedInfo(database);
      await _insertFeedEndDate(database, 'Z0261231', id: 1);
      await _insertFeedEndDate(database, '20260101', id: 2);

      for (final dayType in CatalogTimetableDayType.values) {
        final departures = await CatalogStationTimetableQuery(database)
            .loadDepartures(
              stationId: 'station-sadang',
              lineId: 'seoul-4',
              dayType: dayType,
              referenceDate: _referenceDate,
            );

        expect(departures, isEmpty, reason: dayType.name);
      }
    });
  });

  group('transit_feed_info 테이블이 있고 행이 있는 카탈로그', () {
    test('유효기간이 남은 피드는 기존 필터링 결과를 그대로 유지한다', () async {
      final database = await _openSeededCatalog();
      await _createTransitFeedInfo(database);
      await _insertFeedEndDate(database, '20261231');

      await _expectDayTypeDepartures(database);
    });

    test('유효기간이 지난 피드는 요일 지정 조회 결과를 비운다', () async {
      final database = await _openSeededCatalog();
      await _createTransitFeedInfo(database);
      await _insertFeedEndDate(database, '20260101');

      for (final dayType in CatalogTimetableDayType.values) {
        final departures = await CatalogStationTimetableQuery(database)
            .loadDepartures(
              stationId: 'station-sadang',
              lineId: 'seoul-4',
              dayType: dayType,
              referenceDate: _referenceDate,
            );

        expect(departures, isEmpty, reason: dayType.name);
      }
    });

    test('유효기간이 지나도 요일 미지정 조회는 영향을 받지 않는다', () async {
      final database = await _openSeededCatalog();
      await _createTransitFeedInfo(database);
      await _insertFeedEndDate(database, '20260101');

      final departures = await CatalogStationTimetableQuery(
        database,
      ).loadDepartures(stationId: 'station-sadang', lineId: 'seoul-4');

      expect(
        departures.map((departure) => departure.seconds),
        unorderedEquals(_allDepartureSeconds),
      );
    });
  });

  group('피드 유효기간 판정 조회가 실패한 카탈로그', () {
    test('실패한 판정은 캐시되지 않아 다음 조회가 다시 시도한다', () async {
      final database = await _openSeededCatalog();
      await database.customStatement('''
        CREATE VIEW transit_feed_info AS
        SELECT feed_end_date FROM missing_feed_source
      ''');

      await expectLater(
        CatalogStationTimetableQuery(database).loadDepartures(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          dayType: CatalogTimetableDayType.weekday,
          referenceDate: _referenceDate,
        ),
        throwsA(
          isA<SqliteException>().having(
            (error) => error.message,
            'message',
            contains('missing_feed_source'),
          ),
        ),
      );

      await database.customStatement('DROP VIEW transit_feed_info');
      await _createTransitFeedInfo(database);
      await _insertFeedEndDate(database, '20261231');

      final departures = await CatalogStationTimetableQuery(database)
          .loadDepartures(
            stationId: 'station-sadang',
            lineId: 'seoul-4',
            dayType: CatalogTimetableDayType.weekday,
            referenceDate: _referenceDate,
          );

      expect(
        departures.map((departure) => departure.seconds),
        unorderedEquals(
          _expectedDepartureSecondsByDayType[CatalogTimetableDayType.weekday]!,
        ),
      );
    });
  });
}

final DateTime _referenceDate = DateTime(2026, 7, 12);

const _expectedDepartureSecondsByDayType = <CatalogTimetableDayType, List<int>>{
  CatalogTimetableDayType.weekday: [19200, 19500, 87900],
  CatalogTimetableDayType.saturday: [33120],
  CatalogTimetableDayType.sundayHoliday: [37800],
};

const _allDepartureSeconds = <int>[19200, 19500, 33120, 37800, 87900];

/// 요일 3종 조회가 유효기간 필터 없이 요일별 전체 출발을 돌려주는지 확인한다.
Future<void> _expectDayTypeDepartures(CatalogDatabase database) async {
  for (final entry in _expectedDepartureSecondsByDayType.entries) {
    final departures = await CatalogStationTimetableQuery(database)
        .loadDepartures(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          dayType: entry.key,
          referenceDate: _referenceDate,
        );

    expect(
      departures.map((departure) => departure.seconds),
      unorderedEquals(entry.value),
      reason: entry.key.name,
    );
  }
}

Future<CatalogDatabase> _openSeededCatalog() async {
  final database = CatalogDatabase.memory();
  addTearDown(database.close);
  await database.seedBaselineIfEmpty();
  await _seedTimetable(database);
  return database;
}

Future<void> _createTransitFeedInfo(
  CatalogDatabase database, {
  bool nullableFeedEndDate = false,
}) async {
  await database.customStatement('''
    CREATE TABLE transit_feed_info (
      id INTEGER PRIMARY KEY,
      feed_end_date TEXT${nullableFeedEndDate ? '' : ' NOT NULL'}
    )
  ''');
}

Future<void> _insertFeedEndDate(
  CatalogDatabase database,
  String? feedEndDate, {
  int id = 1,
}) async {
  await database.customStatement(
    'INSERT INTO transit_feed_info (id, feed_end_date) VALUES (?, ?)',
    [id, feedEndDate],
  );
}

Future<void> _seedTimetable(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO service_calendars (
      service_id, monday, tuesday, wednesday, thursday, friday,
      saturday, sunday, start_date, end_date, timezone
    ) VALUES
      ('weekday-2530', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231', 'Asia/Seoul'),
      ('saturday-2530', 0, 0, 0, 0, 0, 1, 0, '20260101', '20261231', 'Asia/Seoul'),
      ('holiday-2530', 0, 0, 0, 0, 0, 0, 1, '20260101', '20261231', 'Asia/Seoul')
  ''');
  await database.customStatement('''
    INSERT INTO transit_routes (
      id, line_id, route_short_name, route_long_name, direction_name, timezone
    ) VALUES
      ('line4-up-2530', 'seoul-4', '4', '상록수 방면', '상록수 방면', 'Asia/Seoul'),
      ('line4-down-2530', 'seoul-4', '4', '사당 방면', '사당 방면', 'Asia/Seoul')
  ''');
  await database.customStatement('''
    INSERT INTO transit_trips (
      id, route_id, service_id, trip_headsign, direction_id,
      service_pattern, service_day_start_seconds
    ) VALUES
      ('weekday-up-2530', 'line4-up-2530', 'weekday-2530', '상록수', 'up', 'LOCAL', 0),
      ('weekday-down-2530-a', 'line4-down-2530', 'weekday-2530', '사당', 'down', 'LOCAL', 0),
      ('weekday-down-2530-b', 'line4-down-2530', 'weekday-2530', '사당', 'down', 'LOCAL', 0),
      ('saturday-down-2530', 'line4-down-2530', 'saturday-2530', '사당', 'down', 'LOCAL', 0),
      ('holiday-down-2530', 'line4-down-2530', 'holiday-2530', '사당', 'down', 'LOCAL', 0)
  ''');
  for (final row in <(String, int)>[
    ('weekday-up-2530', 19500),
    ('weekday-down-2530-a', 19200),
    ('weekday-down-2530-b', 87900),
    ('saturday-down-2530', 33120),
    ('holiday-down-2530', 37800),
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
