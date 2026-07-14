import 'package:flutter_test/flutter_test.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_repository.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late CatalogDatabase catalogDatabase;
  late UserDatabase userDatabase;
  late NextTrainWidgetRepository repository;

  setUpAll(tz_data.initializeTimeZones);

  setUp(() async {
    catalogDatabase = CatalogDatabase.memory();
    userDatabase = UserDatabase.memory();
    await catalogDatabase.customSelect('SELECT 1').get();
    await userDatabase.customSelect('SELECT 1').get();
    await catalogDatabase.customStatement('''
      CREATE TABLE transit_feed_info (
        id INTEGER PRIMARY KEY,
        feed_end_date TEXT NOT NULL
      )
    ''');
    repository = NextTrainWidgetRepository(
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
    await _seedStations(catalogDatabase);
  });

  tearDown(() async {
    await catalogDatabase.close();
    await userDatabase.close();
  });

  test('즐겨찾기 중 실제 시간표가 있는 station-line만 선택한다', () async {
    await _favorite(userDatabase, 'station-sadang');
    await _seedSchedule(catalogDatabase);

    final selections = await repository.availableSelections();

    expect(selections.map((item) => '${item.stationId}|${item.lineId}'), [
      'station-sadang|seoul-4',
    ]);
  });

  test('홈 위젯은 ITX trip을 지하철 출발로 노출하지 않는다', () async {
    await _seedSchedule(catalogDatabase);
    await catalogDatabase.customStatement('''
      INSERT INTO transit_routes (
        id, line_id, route_short_name, route_long_name, direction_name, timezone
      ) VALUES (
        'itx-route', 'seoul-4', 'ITX-청춘', '청량리 → 춘천',
        'ITX 춘천 방면', 'Asia/Seoul'
      )
    ''');
    await catalogDatabase.customStatement('''
      INSERT INTO transit_trips (
        id, route_id, service_id, trip_headsign, direction_id,
        service_pattern, service_class, service_day_start_seconds
      ) VALUES (
        'itx-trip', 'itx-route', 'weekday', '춘천', 'down',
        'EXPRESS', 'ITX_CHEONGCHUN', 0
      )
    ''');
    await catalogDatabase.customStatement('''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id,
        arrival_seconds, departure_seconds, pickup_type, drop_off_type
      ) VALUES (
        'itx-trip', 1, 'station-sadang', 'seoul-4', 18600, 18600, 0, 0
      )
    ''');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2026, 7, 10, 5),
    );

    expect(data.status, NextTrainWidgetStatus.available);
    expect(data.directions.map((item) => item.name), ['상록수 방면', '사당 방면']);
    expect(data.directions.map((item) => item.departureLabel), [
      '05:20',
      '05:25',
    ]);
  });

  test('흡수 station ID 즐겨찾기도 대표 station-line으로 선택한다', () async {
    await catalogDatabase.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sadang', 'station-sadang-old', 'station-sadang-old')
    ''');
    await _favorite(userDatabase, 'station-sadang-old');
    await _seedSchedule(catalogDatabase);

    final selections = await repository.availableSelections();

    expect(selections.map((item) => '${item.stationId}|${item.lineId}'), [
      'station-sadang|seoul-4',
    ]);
  });

  test('흡수 station ID로 저장된 위젯 선택도 대표 ID로 시간표를 조회한다', () async {
    await catalogDatabase.customStatement('''
      INSERT INTO station_aliases (station_id, alias, normalized_alias)
      VALUES ('station-sadang', 'station-sadang-old', 'station-sadang-old')
    ''');
    await _seedSchedule(catalogDatabase);

    final data = await repository.load(
      const WidgetStationSelection(
        stationId: 'station-sadang-old',
        lineId: 'seoul-4',
        stationName: '사당',
        lineName: '수도권 4호선',
      ),
      tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2026, 7, 10, 5),
    );

    expect(data.selection.stationId, 'station-sadang');
    expect(data.status, NextTrainWidgetStatus.available);
  });

  test('공휴일 exception은 평일 calendar보다 우선한다', () async {
    await _seedSchedule(catalogDatabase, holidayDate: '20260817');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2026, 8, 17, 9),
    );

    expect(data.status, NextTrainWidgetStatus.available);
    expect(data.directions.map((item) => item.departureLabel), [
      '09:12',
      '09:18',
    ]);
  });

  test('23:59 뒤 같은 service day의 24시대 양방향 열차를 표시한다', () async {
    await _seedSchedule(catalogDatabase, lateNight: true);
    final seoul = tz.getLocation('Asia/Seoul');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(seoul, 2026, 7, 9, 23, 59),
    );

    expect(data.status, NextTrainWidgetStatus.available);
    expect(data.statusLabel, '시간표 기준');
    expect(data.directions.map((item) => item.departureLabel), [
      '00:25',
      '00:30',
    ]);
    expect(data.directions.map((item) => item.departureAt), [
      tz.TZDateTime(seoul, 2026, 7, 10, 0, 25),
      tz.TZDateTime(seoul, 2026, 7, 10, 0, 30),
    ]);
  });

  test('feed 마지막 service date 다음 날 00시대 열차를 표시한다', () async {
    await _seedSchedule(
      catalogDatabase,
      feedEndDate: '20260709',
      lateNight: true,
    );

    final data = await repository.load(
      _sadangLine4,
      DateTime.utc(2026, 7, 9, 15, 10),
    );

    expect(data.status, NextTrainWidgetStatus.available);
    expect(data.directions.map((item) => item.departureLabel), [
      '00:25',
      '00:30',
    ]);
  });

  test('기기 timezone과 무관하게 Asia/Seoul service clock을 사용한다', () async {
    await _seedSchedule(catalogDatabase, holidayDate: '20260817');
    final newYork = tz.getLocation('America/New_York');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(newYork, 2026, 8, 16, 20),
    );

    expect(data.status, NextTrainWidgetStatus.available);
    expect(data.directions.first.departureLabel, '09:12');
    expect(data.updatedAt, isA<tz.TZDateTime>());
    expect((data.updatedAt as tz.TZDateTime).location.name, 'Asia/Seoul');
  });

  test('오늘 운행이 끝났으면 다음 service day 첫차를 표시한다', () async {
    await _seedSchedule(catalogDatabase);
    final seoul = tz.getLocation('Asia/Seoul');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(seoul, 2026, 7, 9, 23, 59),
    );

    expect(data.status, NextTrainWidgetStatus.serviceEnded);
    expect(data.statusLabel, '오늘 운행 종료 · 첫차 05:20');
  });

  test('feed 유효기간이 지났으면 시간을 만들지 않는다', () async {
    await _seedSchedule(catalogDatabase, feedEndDate: '20261231');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2027, 1, 1, 9),
    );

    expect(data.status, NextTrainWidgetStatus.timetableUnavailable);
    expect(data.directions, isEmpty);
  });

  test('feed 종료 뒤 service day 열차를 만들지 않는다', () async {
    await _seedSchedule(catalogDatabase, feedEndDate: '20260709');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2026, 7, 9, 23, 59),
    );

    expect(data.status, NextTrainWidgetStatus.timetableUnavailable);
    expect(data.directions, isEmpty);
  });

  test('legacy catalog에 transit_feed_info table이 없으면 unavailable이다', () async {
    await _seedSchedule(catalogDatabase);
    await catalogDatabase.customStatement('DROP TABLE transit_feed_info');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2026, 7, 10, 9),
    );

    expect(data.status, NextTrainWidgetStatus.timetableUnavailable);
    expect(data.directions, isEmpty);
  });

  test('legacy catalog에 feed_end_date column이 없으면 unavailable이다', () async {
    await _seedSchedule(catalogDatabase);
    await catalogDatabase.customStatement('DROP TABLE transit_feed_info');
    await catalogDatabase.customStatement('''
      CREATE TABLE transit_feed_info (id INTEGER PRIMARY KEY)
    ''');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2026, 7, 10, 9),
    );

    expect(data.status, NextTrainWidgetStatus.timetableUnavailable);
    expect(data.directions, isEmpty);
  });

  test('transit_feed_info row가 없으면 unavailable이다', () async {
    await _seedSchedule(catalogDatabase);
    await catalogDatabase.customStatement('DELETE FROM transit_feed_info');

    final data = await repository.load(
      _sadangLine4,
      tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2026, 7, 10, 9),
    );

    expect(data.status, NextTrainWidgetStatus.timetableUnavailable);
    expect(data.directions, isEmpty);
  });

  test('legacy feed schema 이외의 SQLite 오류는 전파한다', () async {
    await _seedSchedule(catalogDatabase);
    await catalogDatabase.customStatement('DROP TABLE transit_feed_info');
    await catalogDatabase.customStatement('''
      CREATE VIEW transit_feed_info AS
      SELECT feed_end_date FROM missing_feed_source
    ''');

    await expectLater(
      repository.load(
        _sadangLine4,
        tz.TZDateTime(tz.getLocation('Asia/Seoul'), 2026, 7, 10, 9),
      ),
      throwsA(
        isA<SqliteException>().having(
          (error) => error.message,
          'message',
          contains('missing_feed_source'),
        ),
      ),
    );
  });

  test('하차 전용 stop_times만 있는 station-line은 선택에서 제외한다', () async {
    await _favorite(userDatabase, 'station-sadang');
    await _seedSchedule(catalogDatabase, pickupType: 1);

    expect(await repository.availableSelections(), isEmpty);
  });

  test('한 방향 stop_times만 있는 station-line은 선택에서 제외한다', () async {
    await _favorite(userDatabase, 'station-sadang');
    await _seedSchedule(catalogDatabase, includeDownDirection: false);

    expect(await repository.availableSelections(), isEmpty);
  });
}

const _sadangLine4 = WidgetStationSelection(
  stationId: 'station-sadang',
  lineId: 'seoul-4',
  stationName: '사당',
  lineName: '수도권 4호선',
);

Future<void> _seedStations(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO operators (id, name_ko, name_en)
    VALUES ('seoul-metro', '서울교통공사', 'Seoul Metro')
  ''');
  await database.customStatement('''
    INSERT INTO lines (id, operator_id, name_ko, name_en, color)
    VALUES
      ('seoul-2', 'seoul-metro', '수도권 2호선', 'Line 2', '#00A84D'),
      ('seoul-4', 'seoul-metro', '수도권 4호선', 'Line 4', '#00A5DE')
  ''');
  await database.customStatement('''
    INSERT INTO stations (
      id, name_ko, name_en, name_sub, normalized_name, region,
      data_quality_level, data_source_type
    ) VALUES ('station-sadang', '사당', 'Sadang', '', '사당', '수도권',
      'LEVEL_2', 'OFFICIAL_FILE')
  ''');
  await database.customStatement('''
    INSERT INTO station_lines (
      station_id, line_id, station_code, line_sequence, platform_info
    ) VALUES
      ('station-sadang', 'seoul-2', '226', 26, '내선 / 외선'),
      ('station-sadang', 'seoul-4', '433', 28, '당고개 / 오이도')
  ''');
}

Future<void> _favorite(UserDatabase database, String stationId) async {
  await database.customStatement(
    'INSERT INTO favorite_stations (station_id, added_at) VALUES (?, ?)',
    [stationId, DateTime.utc(2026, 7, 10).millisecondsSinceEpoch ~/ 1000],
  );
}

Future<void> _seedSchedule(
  CatalogDatabase database, {
  String feedEndDate = '20261231',
  String? holidayDate,
  bool lateNight = false,
  int pickupType = 0,
  bool includeDownDirection = true,
}) async {
  await database.customStatement('''
    INSERT INTO service_calendars (
      service_id, monday, tuesday, wednesday, thursday, friday,
      saturday, sunday, start_date, end_date, timezone
    ) VALUES
      ('weekday', 1, 1, 1, 1, 1, 0, 0, '20260101', '20261231', 'Asia/Seoul'),
      ('holiday', 0, 0, 0, 0, 0, 1, 1, '20260101', '20261231', 'Asia/Seoul')
  ''');
  if (holidayDate != null) {
    await database.customStatement(
      '''
      INSERT INTO service_calendar_dates (service_id, date, exception_type)
      VALUES ('weekday', ?, 2), ('holiday', ?, 1)
      ''',
      [holidayDate, holidayDate],
    );
  }
  await database.customStatement('''
    INSERT INTO transit_routes (
      id, line_id, route_short_name, route_long_name, direction_name, timezone
    ) VALUES
      ('line4-up', 'seoul-4', '4', '상록수 방면', '상록수 방면', 'Asia/Seoul'),
      ('line4-down', 'seoul-4', '4', '사당 방면', '사당 방면', 'Asia/Seoul')
  ''');
  await database.customStatement('''
    INSERT INTO transit_trips (
      id, route_id, service_id, trip_headsign, direction_id,
      service_pattern, service_day_start_seconds
    ) VALUES
      ('weekday-up', 'line4-up', 'weekday', '상록수', 'up', 'LOCAL', 0),
      ('weekday-down', 'line4-down', 'weekday', '사당', 'down', 'LOCAL', 0),
      ('holiday-up', 'line4-up', 'holiday', '상록수', 'up', 'LOCAL', 0),
      ('holiday-down', 'line4-down', 'holiday', '사당', 'down', 'LOCAL', 0)
  ''');
  final weekdayUp = lateNight ? 87900 : 19200;
  final weekdayDown = lateNight ? 88200 : 19500;
  final stopTimes = <(String, int)>[
    ('weekday-up', weekdayUp),
    if (includeDownDirection) ('weekday-down', weekdayDown),
    ('holiday-up', 33120),
    if (includeDownDirection) ('holiday-down', 33480),
  ];
  for (final (tripId, seconds) in stopTimes) {
    await database.customStatement(
      '''
      INSERT INTO transit_stop_times (
        trip_id, stop_sequence, station_id, line_id,
        arrival_seconds, departure_seconds, pickup_type, drop_off_type
      ) VALUES (?, 1, 'station-sadang', 'seoul-4', ?, ?, ?, 0)
      ''',
      [tripId, seconds, seconds, pickupType],
    );
  }
  await database.customStatement(
    'INSERT INTO transit_feed_info (id, feed_end_date) VALUES (1, ?)',
    [feedEndDate],
  );
}
