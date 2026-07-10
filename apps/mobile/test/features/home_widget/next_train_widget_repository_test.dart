import 'package:flutter_test/flutter_test.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_repository.dart';

void main() {
  late CatalogDatabase catalogDatabase;
  late UserDatabase userDatabase;
  late NextTrainWidgetRepository repository;

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

  test('공휴일 exception은 평일 calendar보다 우선한다', () async {
    await _seedSchedule(catalogDatabase, holidayDate: '20260817');

    final data = await repository.load(_sadangLine4, DateTime(2026, 8, 17, 9));

    expect(data.status, NextTrainWidgetStatus.available);
    expect(data.directions.map((item) => item.departureLabel), [
      '09:12',
      '09:18',
    ]);
  });

  test('오늘 운행이 끝났으면 다음 service day 첫차를 표시한다', () async {
    await _seedSchedule(catalogDatabase);

    final data = await repository.load(
      _sadangLine4,
      DateTime(2026, 7, 9, 23, 59),
    );

    expect(data.status, NextTrainWidgetStatus.serviceEnded);
    expect(data.statusLabel, '오늘 운행 종료 · 첫차 05:20');
  });

  test('feed 유효기간이 지났으면 시간을 만들지 않는다', () async {
    await _seedSchedule(catalogDatabase, feedEndDate: '20261231');

    final data = await repository.load(_sadangLine4, DateTime(2027, 1, 1, 9));

    expect(data.status, NextTrainWidgetStatus.timetableUnavailable);
    expect(data.directions, isEmpty);
  });

  test('feed 종료 뒤 service day 열차를 만들지 않는다', () async {
    await _seedSchedule(catalogDatabase, feedEndDate: '20260709');

    final data = await repository.load(
      _sadangLine4,
      DateTime(2026, 7, 9, 23, 59),
    );

    expect(data.status, NextTrainWidgetStatus.timetableUnavailable);
    expect(data.directions, isEmpty);
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
  await database.customStatement('''
    INSERT INTO transit_stop_times (
      trip_id, stop_sequence, station_id, line_id,
      arrival_seconds, departure_seconds, pickup_type, drop_off_type
    ) VALUES
      ('weekday-up', 1, 'station-sadang', 'seoul-4', 19200, 19200, 0, 0),
      ('weekday-down', 1, 'station-sadang', 'seoul-4', 19500, 19500, 0, 0),
      ('holiday-up', 1, 'station-sadang', 'seoul-4', 33120, 33120, 0, 0),
      ('holiday-down', 1, 'station-sadang', 'seoul-4', 33480, 33480, 0, 0)
  ''');
  await database.customStatement(
    'INSERT INTO transit_feed_info (id, feed_end_date) VALUES (1, ?)',
    [feedEndDate],
  );
}
