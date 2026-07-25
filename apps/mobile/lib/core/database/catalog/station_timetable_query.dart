import 'package:drift/drift.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'catalog_database.dart';

enum CatalogTimetableDayType { weekday, saturday, sundayHoliday }

class CatalogStationDeparture {
  const CatalogStationDeparture({
    required this.directionName,
    required this.seconds,
    required this.servicePattern,
    required this.serviceClass,
  });

  final String directionName;
  final int seconds;

  /// 운행종별(예: `LOCAL`·`EXPRESS`). final catalog 값을 손실 없이 전달한다.
  final String servicePattern;

  /// 운행 클래스(예: `SUBWAY`). 지하철 여부 판정에 쓴다.
  final String serviceClass;
}

class CatalogStationDayTimetable {
  const CatalogStationDayTimetable({
    required this.dayType,
    required this.departures,
  });

  final CatalogTimetableDayType dayType;
  final List<CatalogStationDeparture> departures;
}

class CatalogStationTimetableQuery {
  const CatalogStationTimetableQuery(this.database);

  final CatalogDatabase database;

  Future<CatalogStationDayTimetable> loadDeparturesForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async {
    final serviceDate = tz.TZDateTime.from(date, _seoulLocation);
    final dateKey = _dateKey(serviceDate);
    final weekdayColumn = _weekdayColumn(serviceDate.weekday);
    final calendarRows = await database
        .customSelect(
          '''
          SELECT *
          FROM service_calendars
          WHERE (start_date <= ? AND end_date >= ?)
             OR service_id IN (
               SELECT service_id
               FROM service_calendar_dates
               WHERE date = ? AND exception_type = 1
             )
          ''',
          variables: [
            Variable.withString(dateKey),
            Variable.withString(dateKey),
            Variable.withString(dateKey),
          ],
        )
        .get();
    final calendarsById = {
      for (final row in calendarRows) row.read<String>('service_id'): row,
    };
    final activeServiceIds = <String>{
      for (final row in calendarRows)
        if (row.read<String>('start_date').compareTo(dateKey) <= 0 &&
            row.read<String>('end_date').compareTo(dateKey) >= 0 &&
            _isEnabled(row.data[weekdayColumn]))
          row.read<String>('service_id'),
    };
    final addedServiceIds = <String>{};
    final exceptionRows = await database
        .customSelect(
          '''
          SELECT service_id, exception_type
          FROM service_calendar_dates
          WHERE date = ?
          ''',
          variables: [Variable.withString(dateKey)],
        )
        .get();
    for (final row in exceptionRows) {
      final serviceId = row.read<String>('service_id');
      if (row.read<int>('exception_type') == 1) {
        activeServiceIds.add(serviceId);
        addedServiceIds.add(serviceId);
      } else {
        activeServiceIds.remove(serviceId);
      }
    }
    final dayType = _dayTypeForDate(
      serviceDate,
      weekdayColumn: weekdayColumn,
      addedServiceIds: addedServiceIds,
      calendarsById: calendarsById,
    );
    return CatalogStationDayTimetable(
      dayType: dayType,
      departures: await loadDepartures(
        stationId: stationId,
        lineId: lineId,
        serviceIds: activeServiceIds,
      ),
    );
  }

  Future<List<CatalogStationDeparture>> loadDepartures({
    required String stationId,
    required String lineId,
    CatalogTimetableDayType? dayType,
    DateTime? referenceDate,
    Set<String>? serviceIds,
  }) async {
    if (serviceIds != null && serviceIds.isEmpty) {
      return const [];
    }
    if (dayType != null && referenceDate == null) {
      throw ArgumentError.notNull('referenceDate');
    }
    final sortedServiceIds = serviceIds == null
        ? null
        : (serviceIds.toList(growable: false)..sort());
    final calendarJoin = dayType == null
        ? ''
        : 'JOIN service_calendars c ON c.service_id = t.service_id';
    final referenceDateKey = dayType == null
        ? null
        : _dateKey(tz.TZDateTime.from(referenceDate!, _seoulLocation));
    final dayFilter = switch (dayType) {
      CatalogTimetableDayType.weekday =>
        'AND (c.monday = 1 OR c.tuesday = 1 OR c.wednesday = 1 '
            'OR c.thursday = 1 OR c.friday = 1)',
      CatalogTimetableDayType.saturday => 'AND c.saturday = 1',
      CatalogTimetableDayType.sundayHoliday => 'AND c.sunday = 1',
      null => '',
    };
    // transit_feed_info는 데이터팩만 제공하는 테이블이라 없을 수도, 비어 있을 수도
    // 있다(#2530). 피드 유효기간을 읽을 수 없으면 필터를 조립하지 않고 나머지
    // 조건으로 조회한다. 홈 위젯 `_feedEndDate`가 같은 상태에서 `null`을 돌려주는
    // 것과 같은 판정이며, 그 뒤 위젯이 `unavailable`로 끝나는 것과 달리 시간표는
    // 필터만 생략하고 결과를 유지한다.
    //
    // GLOB 조건은 존재 판정(`transitFeedEndDate()`)과 같아야 한다. 형식이 깨진 값은
    // 문자열 비교에서 기준일보다 커질 수 있어, 조건이 어긋나면 유효한 행이 없는데도
    // 필터가 통과한다.
    final hasFeedValidityWindow =
        dayType != null && await database.hasTransitFeedValidityWindow();
    final feedValidityFilter = hasFeedValidityWindow
        ? '''
            AND EXISTS (
              SELECT 1
              FROM transit_feed_info feed
              WHERE feed.feed_end_date GLOB '$transitFeedEndDateGlob'
                AND feed.feed_end_date >= ?
            )
          '''
        : '';
    final validityFilter = dayType == null
        ? ''
        : '''
            AND c.start_date <= ?
            AND c.end_date >= ?
            $feedValidityFilter
          ''';
    final serviceFilter = sortedServiceIds == null
        ? ''
        : 'AND t.service_id IN '
              '(${List.filled(sortedServiceIds.length, '?').join(',')})';
    final rows = await database
        .customSelect(
          '''
          SELECT DISTINCT r.direction_name, st.departure_seconds,
                 t.service_pattern, t.service_class
          FROM transit_stop_times st
          JOIN transit_trips t ON t.id = st.trip_id
          JOIN transit_routes r ON r.id = t.route_id
          $calendarJoin
          WHERE st.station_id = ?
            AND st.line_id = ?
            AND st.pickup_type = 0
            AND UPPER(TRIM(t.service_class)) = 'SUBWAY'
            AND r.line_id = st.line_id
            AND TRIM(r.direction_name) <> ''
            $dayFilter
            $validityFilter
            $serviceFilter
          ORDER BY r.direction_name, st.departure_seconds
          ''',
          variables: [
            Variable.withString(stationId),
            Variable.withString(lineId),
            if (referenceDateKey != null) ...[
              Variable.withString(referenceDateKey),
              Variable.withString(referenceDateKey),
              if (hasFeedValidityWindow) Variable.withString(referenceDateKey),
            ],
            ...?sortedServiceIds?.map(Variable.withString),
          ],
        )
        .get();
    return rows
        .map(
          (row) => CatalogStationDeparture(
            directionName: row.read<String>('direction_name'),
            seconds: row.read<int>('departure_seconds'),
            servicePattern: row.read<String?>('service_pattern') ?? '',
            serviceClass: row.read<String?>('service_class') ?? '',
          ),
        )
        .toList(growable: false);
  }
}

CatalogTimetableDayType _dayTypeForDate(
  DateTime date, {
  required String weekdayColumn,
  required Set<String> addedServiceIds,
  required Map<String, QueryRow> calendarsById,
}) {
  if (date.weekday == DateTime.sunday) {
    return CatalogTimetableDayType.sundayHoliday;
  }
  final hasHolidayException = addedServiceIds.any((serviceId) {
    final row = calendarsById[serviceId];
    return row != null &&
        _isEnabled(row.data['sunday']) &&
        !_isEnabled(row.data[weekdayColumn]);
  });
  if (hasHolidayException) {
    return CatalogTimetableDayType.sundayHoliday;
  }
  return date.weekday == DateTime.saturday
      ? CatalogTimetableDayType.saturday
      : CatalogTimetableDayType.weekday;
}

String _weekdayColumn(int weekday) => switch (weekday) {
  DateTime.monday => 'monday',
  DateTime.tuesday => 'tuesday',
  DateTime.wednesday => 'wednesday',
  DateTime.thursday => 'thursday',
  DateTime.friday => 'friday',
  DateTime.saturday => 'saturday',
  _ => 'sunday',
};

String _dateKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}

bool _isEnabled(Object? value) => value == true || value == 1;

final tz.Location _seoulLocation = _loadSeoulLocation();

tz.Location _loadSeoulLocation() {
  tz_data.initializeTimeZones();
  return tz.getLocation('Asia/Seoul');
}
