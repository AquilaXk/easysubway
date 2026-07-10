import 'package:drift/drift.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/database/catalog/catalog_database.dart';
import '../../core/database/user/user_database.dart';

enum NextTrainWidgetStatus { available, serviceEnded, timetableUnavailable }

class WidgetStationSelection {
  const WidgetStationSelection({
    required this.stationId,
    required this.lineId,
    required this.stationName,
    required this.lineName,
  });

  final String stationId;
  final String lineId;
  final String stationName;
  final String lineName;
}

class NextTrainDirection {
  const NextTrainDirection({required this.name, required this.departureAt});

  final String name;
  final DateTime departureAt;

  String get departureLabel => _timeLabel(departureAt);
}

class NextTrainWidgetData {
  const NextTrainWidgetData({
    required this.selection,
    required this.status,
    required this.directions,
    required this.statusLabel,
    required this.updatedAt,
  });

  factory NextTrainWidgetData.unavailable(
    WidgetStationSelection selection,
    DateTime updatedAt,
  ) {
    return NextTrainWidgetData(
      selection: selection,
      status: NextTrainWidgetStatus.timetableUnavailable,
      directions: const [],
      statusLabel: '시간표를 확인할 수 없어요.',
      updatedAt: updatedAt,
    );
  }

  final WidgetStationSelection selection;
  final NextTrainWidgetStatus status;
  final List<NextTrainDirection> directions;
  final String statusLabel;
  final DateTime updatedAt;
}

class NextTrainWidgetRepository {
  const NextTrainWidgetRepository({
    required this.catalogDatabase,
    required this.userDatabase,
  });

  final CatalogDatabase catalogDatabase;
  final UserDatabase userDatabase;

  Future<List<WidgetStationSelection>> availableSelections() async {
    final favorites = await userDatabase
        .customSelect('SELECT station_id FROM favorite_stations')
        .get();
    if (favorites.isEmpty) {
      return const [];
    }
    final stationIds = favorites
        .map((row) => row.read<String>('station_id'))
        .toList(growable: false);
    final placeholders = List.filled(stationIds.length, '?').join(',');
    final rows = await catalogDatabase.customSelect('''
          SELECT DISTINCT
            s.id AS station_id,
            sl.line_id,
            s.name_ko AS station_name,
            l.name_ko AS line_name
          FROM stations s
          JOIN station_lines sl ON sl.station_id = s.id
          JOIN lines l ON l.id = sl.line_id
          WHERE s.id IN ($placeholders)
          ORDER BY s.name_ko, l.name_ko
          ''', variables: stationIds.map(Variable.withString).toList()).get();
    final selections = rows
        .map(
          (row) => WidgetStationSelection(
            stationId: row.read<String>('station_id'),
            lineId: row.read<String>('line_id'),
            stationName: row.read<String>('station_name'),
            lineName: row.read<String>('line_name'),
          ),
        )
        .toList(growable: false);
    final available = <WidgetStationSelection>[];
    for (final selection in selections) {
      final directions = (await _departures(
        selection: selection,
      )).map((departure) => departure.directionName).toSet();
      if (directions.length >= 2) {
        available.add(selection);
      }
    }
    return available;
  }

  Future<NextTrainWidgetData> load(
    WidgetStationSelection selection,
    DateTime now,
  ) async {
    final serviceNow = tz.TZDateTime.from(now, _seoulLocation);
    final feedEndDate = await _feedEndDate();
    if (feedEndDate == null) {
      return NextTrainWidgetData.unavailable(selection, serviceNow);
    }

    final midnight = tz.TZDateTime(
      _seoulLocation,
      serviceNow.year,
      serviceNow.month,
      serviceNow.day,
    );
    final candidates = <_Departure>[];
    for (var dayOffset = -1; dayOffset <= 7; dayOffset += 1) {
      final serviceDate = midnight.add(Duration(days: dayOffset));
      if (serviceDate.isAfter(feedEndDate)) {
        break;
      }
      final serviceIds = await _activeServiceIds(serviceDate);
      if (serviceIds.isEmpty) {
        continue;
      }
      final departures = await _departures(
        selection: selection,
        serviceIds: serviceIds,
      );
      for (final departure in departures) {
        final departureAt = serviceDate.add(
          Duration(seconds: departure.seconds),
        );
        if (departureAt.isBefore(serviceNow)) {
          continue;
        }
        candidates.add(
          _Departure(
            directionName: departure.directionName,
            serviceDate: serviceDate,
            departureAt: departureAt,
          ),
        );
      }
    }
    candidates.sort(
      (left, right) => left.departureAt.compareTo(right.departureAt),
    );

    final nextByDirection = <String, _Departure>{};
    for (final candidate in candidates) {
      nextByDirection.putIfAbsent(candidate.directionName, () => candidate);
    }
    final nextDepartures = nextByDirection.values.toList(growable: false)
      ..sort((left, right) => left.departureAt.compareTo(right.departureAt));
    final directions =
        nextDepartures
            .map(
              (departure) => NextTrainDirection(
                name: departure.directionName,
                departureAt: departure.departureAt,
              ),
            )
            .toList(growable: false)
          ..sort(
            (left, right) => left.departureAt.compareTo(right.departureAt),
          );
    if (directions.length < 2) {
      return NextTrainWidgetData.unavailable(selection, serviceNow);
    }

    final hasCurrentServiceDayDeparture = nextDepartures.any(
      (departure) => !departure.serviceDate.isAfter(midnight),
    );
    final status = hasCurrentServiceDayDeparture
        ? NextTrainWidgetStatus.available
        : NextTrainWidgetStatus.serviceEnded;
    return NextTrainWidgetData(
      selection: selection,
      status: status,
      directions: directions,
      statusLabel: status == NextTrainWidgetStatus.serviceEnded
          ? '오늘 운행 종료 · 첫차 ${directions.first.departureLabel}'
          : '시간표 기준',
      updatedAt: serviceNow,
    );
  }

  Future<tz.TZDateTime?> _feedEndDate() async {
    final row = await catalogDatabase
        .customSelect('SELECT feed_end_date FROM transit_feed_info LIMIT 1')
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _parseServiceDate(row.read<String>('feed_end_date'));
  }

  Future<Set<String>> _activeServiceIds(DateTime date) async {
    final dateKey = _dateKey(date);
    final calendarRows = await catalogDatabase
        .customSelect(
          '''
          SELECT *
          FROM service_calendars
          WHERE start_date <= ? AND end_date >= ?
          ''',
          variables: [
            Variable.withString(dateKey),
            Variable.withString(dateKey),
          ],
        )
        .get();
    final weekdayColumn = switch (date.weekday) {
      DateTime.monday => 'monday',
      DateTime.tuesday => 'tuesday',
      DateTime.wednesday => 'wednesday',
      DateTime.thursday => 'thursday',
      DateTime.friday => 'friday',
      DateTime.saturday => 'saturday',
      _ => 'sunday',
    };
    final active = <String>{
      for (final row in calendarRows)
        if (_isEnabled(row.data[weekdayColumn])) row.read<String>('service_id'),
    };
    final exceptionRows = await catalogDatabase
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
        active.add(serviceId);
      } else {
        active.remove(serviceId);
      }
    }
    return active;
  }

  Future<List<_StopTimeDeparture>> _departures({
    required WidgetStationSelection selection,
    Set<String>? serviceIds,
  }) async {
    final serviceFilter = serviceIds == null
        ? ''
        : 'AND t.service_id IN (${List.filled(serviceIds.length, '?').join(',')})';
    final rows = await catalogDatabase
        .customSelect(
          '''
          SELECT r.direction_name, st.departure_seconds
          FROM transit_stop_times st
          JOIN transit_trips t ON t.id = st.trip_id
          JOIN transit_routes r ON r.id = t.route_id
          WHERE st.station_id = ?
            AND st.line_id = ?
            AND st.pickup_type = 0
            AND r.line_id = st.line_id
            AND TRIM(r.direction_name) <> ''
            $serviceFilter
          ORDER BY st.departure_seconds
          ''',
          variables: [
            Variable.withString(selection.stationId),
            Variable.withString(selection.lineId),
            ...?serviceIds?.map(Variable.withString),
          ],
        )
        .get();
    return rows
        .map(
          (row) => _StopTimeDeparture(
            directionName: row.read<String>('direction_name'),
            seconds: row.read<int>('departure_seconds'),
          ),
        )
        .toList(growable: false);
  }
}

class _StopTimeDeparture {
  const _StopTimeDeparture({
    required this.directionName,
    required this.seconds,
  });

  final String directionName;
  final int seconds;
}

class _Departure {
  const _Departure({
    required this.directionName,
    required this.serviceDate,
    required this.departureAt,
  });

  final String directionName;
  final DateTime serviceDate;
  final DateTime departureAt;
}

bool _isEnabled(Object? value) => value == true || value == 1;

String _dateKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
}

tz.TZDateTime? _parseServiceDate(String value) {
  if (!RegExp(r'^\d{8}$').hasMatch(value)) {
    return null;
  }
  return tz.TZDateTime(
    _seoulLocation,
    int.parse(value.substring(0, 4)),
    int.parse(value.substring(4, 6)),
    int.parse(value.substring(6, 8)),
  );
}

final tz.Location _seoulLocation = _loadSeoulLocation();

tz.Location _loadSeoulLocation() {
  tz_data.initializeTimeZones();
  return tz.getLocation('Asia/Seoul');
}

String _timeLabel(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
