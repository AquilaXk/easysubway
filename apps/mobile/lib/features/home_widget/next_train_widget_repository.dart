import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../core/database/catalog/catalog_database.dart';
import '../../core/database/catalog/station_timetable_query.dart';
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
    final stationIds = <String>{};
    for (final favorite in favorites) {
      final stationId = await _canonicalStationId(
        favorite.read<String>('station_id'),
      );
      if (stationId != null) stationIds.add(stationId);
    }
    if (stationIds.isEmpty) return const [];
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
    final canonicalStationId = await _canonicalStationId(selection.stationId);
    if (canonicalStationId != null &&
        canonicalStationId != selection.stationId) {
      selection = WidgetStationSelection(
        stationId: canonicalStationId,
        lineId: selection.lineId,
        stationName: selection.stationName,
        lineName: selection.lineName,
      );
    }
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
      final departures =
          (await CatalogStationTimetableQuery(
                catalogDatabase,
              ).loadDeparturesForDate(
                stationId: selection.stationId,
                lineId: selection.lineId,
                date: serviceDate,
              ))
              .departures;
      if (departures.isEmpty) {
        continue;
      }
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

  Future<String?> _canonicalStationId(String stationId) async {
    final rows = await catalogDatabase
        .customSelect(
          '''
      SELECT id AS station_id FROM stations WHERE id = ?
      UNION
      SELECT sa.station_id
      FROM station_aliases sa
      JOIN stations s ON s.id = sa.station_id
      WHERE sa.alias = ?
      LIMIT 2
      ''',
          variables: [
            Variable.withString(stationId),
            Variable.withString(stationId),
          ],
          readsFrom: {catalogDatabase.stations, catalogDatabase.stationAliases},
        )
        .get();
    return rows.length == 1 ? rows.single.read<String>('station_id') : null;
  }

  Future<tz.TZDateTime?> _feedEndDate() async {
    late final QueryRow? row;
    try {
      row = await catalogDatabase
          .customSelect('SELECT feed_end_date FROM transit_feed_info LIMIT 1')
          .getSingleOrNull();
    } on SqliteException catch (error) {
      if (error.message != 'no such table: transit_feed_info' &&
          error.message != 'no such column: feed_end_date') {
        rethrow;
      }
      return null;
    }
    if (row == null) {
      return null;
    }
    return _parseServiceDate(row.read<String>('feed_end_date'));
  }

  Future<List<CatalogStationDeparture>> _departures({
    required WidgetStationSelection selection,
    Set<String>? serviceIds,
  }) {
    return CatalogStationTimetableQuery(catalogDatabase).loadDepartures(
      stationId: selection.stationId,
      lineId: selection.lineId,
      serviceIds: serviceIds,
    );
  }
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
