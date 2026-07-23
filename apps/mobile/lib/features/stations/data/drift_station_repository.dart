import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/catalog/canonical_station_id.dart';
import '../../../core/database/catalog/catalog_database.dart';
import '../../../core/database/catalog/station_timetable_query.dart';
import '../../../network_map.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';

class DriftStationRepository
    implements
        StationSearchRepository,
        StationSearchCache,
        StationLineFilterRepository,
        StationTimetableRepository,
        NetworkMapRepository {
  DriftStationRepository({required this.database});

  /// 지하철(`SUBWAY`) 출발에 허용되는 운행종별. 이 외 값은 경계에서 실패시킨다.
  static const _validSubwayServicePatterns = {'LOCAL', 'EXPRESS'};

  /// 짧은 검색어가 전 역을 펼치면 목록·배지 빌드가 메인 스레드를 막는다.
  static const _maxSearchResults = 40;

  final CatalogDatabase database;
  Future<List<_LocalStationSummary>>? _stationSummaryCache;

  void invalidateStationSummaryCache() {
    _stationSummaryCache = null;
  }

  @override
  Future<void> warmSearchCache() async {
    final stations = await _listStationSummaries();
    for (final station in stations) {
      station.primeSearchTerms();
    }
  }

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const [];
    }

    final normalizedQuery = _normalize(trimmedQuery);
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final stations = await _listStationSummaries();
    final ranked = <({_LocalStationSummary station, int rank})>[];
    for (final station in stations) {
      final rank = station.matchRank(normalizedQuery);
      if (rank == null) {
        continue;
      }
      ranked.add((station: station, rank: rank));
    }
    ranked.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) {
        return byRank;
      }
      return a.station.nameKo.compareTo(b.station.nameKo);
    });
    return ranked
        .take(_maxSearchResults)
        .map((entry) => entry.station.toSearchResult())
        .toList(growable: false);
  }

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async {
    stationId = await database.resolveCanonicalStationId(stationId);
    final catalogDayType = switch (dayType) {
      StationTimetableDayType.weekday => CatalogTimetableDayType.weekday,
      StationTimetableDayType.saturday => CatalogTimetableDayType.saturday,
      StationTimetableDayType.sundayHoliday =>
        CatalogTimetableDayType.sundayHoliday,
    };
    final rows = await CatalogStationTimetableQuery(database).loadDepartures(
      stationId: stationId,
      lineId: lineId,
      dayType: catalogDayType,
      referenceDate: referenceDate,
    );
    return _stationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: dayType,
      rows: rows,
    );
  }

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) async {
    stationId = await database.resolveCanonicalStationId(stationId);
    final timetable = await CatalogStationTimetableQuery(
      database,
    ).loadDeparturesForDate(stationId: stationId, lineId: lineId, date: date);
    final dayType = switch (timetable.dayType) {
      CatalogTimetableDayType.weekday => StationTimetableDayType.weekday,
      CatalogTimetableDayType.saturday => StationTimetableDayType.saturday,
      CatalogTimetableDayType.sundayHoliday =>
        StationTimetableDayType.sundayHoliday,
    };
    return _stationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: dayType,
      rows: timetable.departures,
    );
  }

  StationTimetable _stationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required List<CatalogStationDeparture> rows,
  }) {
    final grouped = <String, List<StationTimetableDeparture>>{};
    for (final row in rows) {
      final directionName = row.directionName;
      final servicePattern = row.servicePattern.trim().toUpperCase();
      final serviceClass = row.serviceClass.trim().toUpperCase();
      // 지하철 운행종별이 LOCAL/EXPRESS가 아니면(공백·미상) 일반으로 추정하지 않고
      // 경계에서 실패시킨다(fail closed) — 잘못된 급행/일반 표기를 원천 차단한다.
      if (serviceClass == 'SUBWAY' &&
          !_validSubwayServicePatterns.contains(servicePattern)) {
        throw StateError(
          '알 수 없는 지하철 운행종별입니다: "${row.servicePattern}" '
          '(station=$stationId, line=$lineId)',
        );
      }
      grouped
          .putIfAbsent(directionName, () => <StationTimetableDeparture>[])
          .add(
            StationTimetableDeparture(
              directionName: directionName,
              seconds: row.seconds,
              servicePattern: servicePattern,
              serviceClass: serviceClass,
            ),
          );
    }
    return StationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: dayType,
      directions: [
        for (final entry in grouped.entries)
          StationTimetableDirection(
            name: entry.key,
            departures: List.unmodifiable(entry.value),
          ),
      ],
    );
  }

  @override
  Future<List<StationSearchResult>> searchStationsOnLine(
    String query,
    String lineId,
  ) async {
    final trimmedLineId = lineId.trim();
    return (await searchStations(query))
        .where(
          (station) => station.lines.any((line) => line.id == trimmedLineId),
        )
        .toList(growable: false);
  }

  @override
  Future<List<SubwayLineOption>> listLines() async {
    final rows = await database.customSelect('''
          SELECT id, name_ko, color
          FROM lines
          ORDER BY name_ko
          ''').get();

    return rows
        .map(
          (row) => SubwayLineOption(
            id: row.read<String>('id'),
            name: row.read<String>('name_ko'),
            color: row.read<String>('color'),
            region: _lineRegion(row.read<String>('name_ko')),
            lineCode: _lineCode(row.read<String>('name_ko')),
            active: true,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    if (limit <= 0 || radiusMeters <= 0) {
      return const [];
    }

    final stations = await _listStationSummaries();
    final nearby =
        stations
            .map((station) {
              final latitude = station.latitude;
              final longitude = station.longitude;
              if (latitude == null || longitude == null) {
                return null;
              }
              final distanceMeters = _distanceMeters(
                fromLatitude: location.latitude,
                fromLongitude: location.longitude,
                toLatitude: latitude,
                toLongitude: longitude,
              );
              if (distanceMeters > radiusMeters) {
                return null;
              }
              return MapEntry(station, distanceMeters);
            })
            .whereType<MapEntry<_LocalStationSummary, int>>()
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    return nearby
        .take(limit)
        .map((entry) => entry.key.toSearchResult(distanceMeters: entry.value))
        .toList(growable: false);
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    final summary = await _getStationSummary(stationId);
    if (summary == null) {
      throw const StationSearchException('역 정보를 불러오지 못했어요.');
    }

    return StationDetail(
      id: summary.id,
      nameKo: summary.nameKo,
      nameEn: summary.nameEn,
      nameSub: summary.nameSub,
      region: summary.region,
      latitude: summary.latitude,
      longitude: summary.longitude,
      dataQualityLevel: summary.dataQualityLevel,
      dataSourceType: summary.dataSourceType,
      lastVerifiedAt: summary.lastVerifiedAt,
      lines: List.unmodifiable(summary.lines),
    );
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    stationId = await database.resolveCanonicalStationId(stationId);
    final rows = await database
        .customSelect(
          '''
          SELECT
            e.id,
            e.station_id,
            e.exit_number,
            e.description,
            e.latitude,
            e.longitude,
            e.data_source_type,
            CAST(e.last_verified_at AS INTEGER) AS exit_last_verified_at,
            (
              SELECT q.quality_level
              FROM data_quality_records q
              WHERE UPPER(q.target_type) = 'STATION_EXIT'
                AND q.target_id = e.id
              ORDER BY q.checked_at IS NULL, q.checked_at DESC, q.id DESC
              LIMIT 1
            ) AS field_quality_level,
            (
              SELECT q.checked_at
              FROM data_quality_records q
              WHERE UPPER(q.target_type) = 'STATION_EXIT'
                AND q.target_id = e.id
              ORDER BY q.checked_at IS NULL, q.checked_at DESC, q.id DESC
              LIMIT 1
            ) AS field_checked_at_value,
            CASE
              WHEN e.has_elevator_connection = 1 OR EXISTS(
                SELECT 1
                FROM facilities f
                WHERE f.exit_id = e.id
                  AND UPPER(f.type) = 'ELEVATOR'
              )
              THEN 1
              ELSE 0
            END AS has_elevator_connection
          FROM station_exits e
          WHERE e.station_id = ?
          ORDER BY CAST(e.exit_number AS INTEGER), e.exit_number
          ''',
          variables: [Variable.withString(stationId)],
        )
        .get();

    return rows
        .map(
          (row) => StationExitInfo(
            id: row.read<String>('id'),
            stationId: row.read<String>('station_id'),
            exitNumber: row.read<String>('exit_number'),
            name: '${row.read<String>('exit_number')}번 출구',
            latitude: row.read<double?>('latitude'),
            longitude: row.read<double?>('longitude'),
            hasElevatorConnection:
                row.read<int>('has_elevator_connection') == 1,
            hasStairOnlyPath: false,
            dataConfidence: _fieldValidationConfidence(
              row.read<String?>('field_quality_level'),
              row.read<int?>('field_checked_at_value'),
            ),
            dataSourceType: row.read<String>('data_source_type'),
            fieldValidationStatus: _fieldValidationStatus(
              row.read<String?>('field_quality_level'),
              row.read<int?>('field_checked_at_value'),
            ),
            lastVerifiedAt: _dateLabelFromEpoch(
              row.read<int?>('exit_last_verified_at'),
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    stationId = await database.resolveCanonicalStationId(stationId);
    final rows = await database
        .customSelect(
          '''
          SELECT
            f.id,
            f.station_id,
            f.exit_id,
            f.type,
            f.name,
            f.status,
            f.floor_from,
            f.floor_to,
            f.description,
            s.data_source_type,
            CAST(s.last_verified_at AS INTEGER) AS last_verified_at_value,
            (
              SELECT q.quality_level
              FROM data_quality_records q
              WHERE UPPER(q.target_type) = 'FACILITY'
                AND q.target_id = f.id
              ORDER BY q.checked_at IS NULL, q.checked_at DESC, q.id DESC
              LIMIT 1
            ) AS field_quality_level,
            (
              SELECT q.checked_at
              FROM data_quality_records q
              WHERE UPPER(q.target_type) = 'FACILITY'
                AND q.target_id = f.id
              ORDER BY q.checked_at IS NULL, q.checked_at DESC, q.id DESC
              LIMIT 1
            ) AS field_checked_at_value
          FROM facilities f
          JOIN stations s ON s.id = f.station_id
          WHERE f.station_id = ?
          ORDER BY f.type, f.name
          ''',
          variables: [Variable.withString(stationId)],
        )
        .get();

    return rows
        .map(
          (row) => StationFacilityInfo(
            id: row.read<String>('id'),
            stationId: row.read<String>('station_id'),
            exitId: row.read<String?>('exit_id') ?? '',
            type: row.read<String?>('type') ?? '',
            name: row.read<String?>('name') ?? '',
            floorFrom: row.read<String?>('floor_from') ?? '',
            floorTo: row.read<String?>('floor_to') ?? '',
            description: row.read<String?>('description') ?? '',
            status: row.read<String?>('status') ?? '',
            dataConfidence: _fieldValidationConfidence(
              row.read<String?>('field_quality_level'),
              row.read<int?>('field_checked_at_value'),
            ),
            dataSourceType: row.read<String?>('data_source_type') ?? '',
            lastUpdatedAt: _dateLabelFromEpoch(
              row.read<int?>('field_checked_at_value') ??
                  row.read<int?>('last_verified_at_value'),
            ),
            fieldValidationStatus: _fieldValidationStatus(
              row.read<String?>('field_quality_level'),
              row.read<int?>('field_checked_at_value'),
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    final selectedRegion = await _selectedNetworkMapRegion(region);
    final lineRows = await database
        .customSelect(
          '''
          SELECT DISTINCT l.id, l.name_ko, l.color, COALESCE(rmp.region, s.region, '') AS region
          FROM lines l
          JOIN station_lines sl ON sl.line_id = l.id
          JOIN stations s ON s.id = sl.station_id
          JOIN route_map_positions rmp
            ON rmp.station_id = sl.station_id
           AND rmp.line_id = sl.line_id
          WHERE COALESCE(rmp.region, s.region, '') = ?
          ORDER BY l.name_ko
          ''',
          variables: [Variable.withString(selectedRegion)],
        )
        .get();
    final lines = lineRows
        .map(
          (row) => NetworkMapLine(
            id: row.read<String>('id'),
            name: row.read<String>('name_ko'),
            color: row.read<String>('color'),
            region: row.read<String>('region'),
          ),
        )
        .toList(growable: false);
    final selectedLineIds = {
      for (final line in lines)
        if (lineId == null || lineId.trim().isEmpty || line.id == lineId.trim())
          line.id,
    };
    final stationRows = await database
        .customSelect(
          '''
          SELECT
            s.id,
            s.name_ko,
            s.name_en,
            s.region,
            sl.line_id,
            sl.station_code,
            sl.line_sequence,
            rmp.x,
            rmp.y,
            rmp.label_dx,
            rmp.label_dy,
            rmp.label_polygon,
            rmp.up_path,
            rmp.down_path,
            rmp.source_id
          FROM route_map_positions rmp
          JOIN station_lines sl
            ON sl.station_id = rmp.station_id
           AND sl.line_id = rmp.line_id
          JOIN stations s ON s.id = rmp.station_id
          WHERE rmp.region = ?
          ORDER BY sl.line_id, sl.line_sequence
          ''',
          variables: [Variable.withString(selectedRegion)],
        )
        .get();
    final stations = stationRows
        .where((row) => selectedLineIds.contains(row.read<String>('line_id')))
        .map(
          (row) => NetworkMapStation(
            id: row.read<String>('id'),
            nameKo: row.read<String>('name_ko'),
            nameEn: row.read<String>('name_en'),
            region: row.read<String>('region'),
            lineId: row.read<String>('line_id'),
            stationCode: row.read<String>('station_code'),
            sequence: row.read<int>('line_sequence'),
            position: NetworkMapPosition(
              x: row.read<int>('x'),
              y: row.read<int>('y'),
              labelDx: row.read<int>('label_dx'),
              labelDy: row.read<int>('label_dy'),
              labelPolygon: row.read<String>('label_polygon'),
              upPath: row.read<String>('up_path'),
              downPath: row.read<String>('down_path'),
              sourceId: row.read<String>('source_id'),
            ),
          ),
        )
        .toList(growable: false);
    final stationLineMemberships = stationRows
        .map(
          (row) => NetworkMapStationLineMembership(
            stationId: row.read<String>('id'),
            lineId: row.read<String>('line_id'),
          ),
        )
        .toList(growable: false);
    return NetworkMapData(
      regions: await _networkMapRegions(),
      selectedRegion: selectedRegion,
      lines: lines,
      stations: stations,
      edges: _networkMapEdges(stations),
      positionSources: await _networkMapPositionSources(selectedRegion),
      stationLineMemberships: stationLineMemberships,
      lineTracks: await _networkMapLineTracks(selectedRegion, selectedLineIds),
    );
  }

  /// route_map_line_tracks에서 노선별 track path를 track_index 순으로 로드한다(#1638).
  /// 선택 노선 필터를 반영하고, 구팩(테이블 없음)은 빈 목록을 반환한다.
  Future<List<NetworkMapLineTrack>> _networkMapLineTracks(
    String region,
    Set<String> selectedLineIds,
  ) async {
    final rows = await database
        .customSelect(
          '''
          SELECT line_id, path
          FROM route_map_line_tracks
          WHERE region = ?
          ORDER BY line_id, track_index
          ''',
          variables: [Variable.withString(region)],
        )
        .get();
    final pathsByLine = <String, List<String>>{};
    for (final row in rows) {
      final lineId = row.read<String>('line_id');
      if (!selectedLineIds.contains(lineId)) {
        continue;
      }
      pathsByLine
          .putIfAbsent(lineId, () => <String>[])
          .add(row.read<String>('path'));
    }
    return [
      for (final entry in pathsByLine.entries)
        NetworkMapLineTrack(lineId: entry.key, paths: entry.value),
    ];
  }

  Future<String> _selectedNetworkMapRegion(String? requestedRegion) async {
    final trimmedRegion = requestedRegion?.trim();
    if (trimmedRegion != null && trimmedRegion.isNotEmpty) {
      return _storedNetworkMapRegion(trimmedRegion);
    }
    final rows = await database.customSelect('''
      SELECT DISTINCT region
      FROM route_map_positions
      WHERE region <> ''
      ORDER BY CASE region WHEN '전국' THEN 0 WHEN '수도권' THEN 1 ELSE 2 END, region
      LIMIT 1
      ''').get();
    if (rows.isEmpty) {
      return '수도권';
    }
    return rows.single.read<String>('region');
  }

  Future<List<NetworkMapRegion>> _networkMapRegions() async {
    final rows = await database.customSelect('''
      SELECT DISTINCT region
      FROM route_map_positions
      WHERE region <> ''
      ORDER BY CASE region WHEN '전국' THEN 0 WHEN '수도권' THEN 1 ELSE 2 END, region
      ''').get();
    return rows
        .map((row) => NetworkMapRegion(name: row.read<String>('region')))
        .toList(growable: false);
  }

  Future<List<NetworkMapPositionSource>> _networkMapPositionSources(
    String region,
  ) async {
    final rows = await database
        .customSelect(
          '''
          SELECT source_id, source_name, license_status
          FROM route_map_positions
          WHERE region = ?
          GROUP BY source_id, source_name, license_status
          ORDER BY source_id
          ''',
          variables: [Variable.withString(region)],
        )
        .get();
    return rows
        .map(
          (row) => NetworkMapPositionSource(
            id: row.read<String>('source_id'),
            name: row.read<String>('source_name'),
            licenseStatus: row.read<String>('license_status'),
          ),
        )
        .toList(growable: false);
  }

  List<NetworkMapEdge> _networkMapEdges(List<NetworkMapStation> stations) {
    final byLine = <String, List<NetworkMapStation>>{};
    for (final station in stations) {
      byLine.putIfAbsent(station.lineId, () => []).add(station);
    }
    final edges = <NetworkMapEdge>[];
    for (final entry in byLine.entries) {
      final sortedStations = [...entry.value]
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      for (var index = 0; index < sortedStations.length - 1; index += 1) {
        final from = sortedStations[index];
        final to = sortedStations[index + 1];
        edges.add(
          NetworkMapEdge(
            id: 'map-edge-${entry.key}-${from.id}-${to.id}',
            lineId: entry.key,
            fromStationId: _mapStationKey(from),
            toStationId: _mapStationKey(to),
            accessibilityStatus: 'AVAILABLE',
            reliabilityScore: 100,
          ),
        );
      }
    }
    return edges;
  }

  Future<_LocalStationSummary?> _getStationSummary(String stationId) async {
    final summaries = await _listStationSummaries(stationId: stationId);
    return summaries.isEmpty ? null : summaries.single;
  }

  Future<List<_LocalStationSummary>> _listStationSummaries({
    String? stationId,
  }) async {
    if (stationId == null) {
      return _stationSummaryCache ??= _readStationSummaries();
    }

    stationId = await database.resolveCanonicalStationId(stationId);
    final cached = _stationSummaryCache;
    if (cached != null) {
      return (await cached)
          .where((summary) => summary.id == stationId)
          .toList(growable: false);
    }

    return _readStationSummaries(stationId: stationId);
  }

  Future<List<_LocalStationSummary>> _readStationSummaries({
    String? stationId,
  }) async {
    final stationFilter = stationId == null ? '' : 'WHERE s.id = ?';
    final rows = await database
        .customSelect(
          '''
          SELECT
            s.id,
            s.name_ko,
            s.name_en,
            s.name_sub,
            s.region,
            s.latitude,
            s.longitude,
            s.data_quality_level,
            s.data_source_type,
            CAST(s.last_verified_at AS INTEGER) AS last_verified_at_value,
            l.id AS line_id,
            l.name_ko AS line_name,
            l.color AS line_color,
            sl.station_code
          FROM stations s
          LEFT JOIN station_lines sl ON sl.station_id = s.id
          LEFT JOIN lines l ON l.id = sl.line_id
          $stationFilter
          ORDER BY s.name_ko, sl.line_sequence
          ''',
          variables: [if (stationId != null) Variable.withString(stationId)],
        )
        .get();

    final summaries = <String, _LocalStationSummary>{};
    for (final row in rows) {
      final stationId = row.read<String>('id');
      final summary = summaries.putIfAbsent(
        stationId,
        () => _LocalStationSummary(
          id: stationId,
          nameKo: row.read<String>('name_ko'),
          nameEn: row.read<String?>('name_en') ?? '',
          nameSub: row.read<String?>('name_sub') ?? '',
          region: row.read<String>('region'),
          latitude: row.read<double?>('latitude'),
          longitude: row.read<double?>('longitude'),
          dataQualityLevel: row.read<String>('data_quality_level'),
          dataSourceType: row.read<String?>('data_source_type') ?? '',
          lastVerifiedAt: _dateLabelFromEpoch(
            row.read<int?>('last_verified_at_value'),
          ),
          aliases: [],
          lines: [],
        ),
      );

      final lineId = row.read<String?>('line_id');
      if (lineId != null) {
        summary.lines.add(
          StationSearchLine(
            id: lineId,
            name: row.read<String>('line_name'),
            color: row.read<String>('line_color'),
            stationCode: row.read<String>('station_code'),
          ),
        );
      }
    }

    final aliasRows = await database
        .customSelect(
          '''
          SELECT station_id, alias
          FROM station_aliases
          ${stationId == null ? '' : 'WHERE station_id = ?'}
          ''',
          variables: [if (stationId != null) Variable.withString(stationId)],
        )
        .get();
    for (final row in aliasRows) {
      summaries[row.read<String>('station_id')]?.aliases.add(
        row.read<String>('alias'),
      );
    }

    return summaries.values.toList(growable: false);
  }
}

String _mapStationKey(NetworkMapStation station) =>
    '${station.id}:${station.lineId}';

class _LocalStationSummary {
  _LocalStationSummary({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.nameSub,
    required this.region,
    required this.latitude,
    required this.longitude,
    required this.dataQualityLevel,
    required this.dataSourceType,
    required this.lastVerifiedAt,
    required this.aliases,
    required this.lines,
  });

  final String id;
  final String nameKo;
  final String nameEn;
  final String nameSub;
  final String region;
  final double? latitude;
  final double? longitude;
  final String dataQualityLevel;
  final String dataSourceType;
  final String lastVerifiedAt;
  final List<String> aliases;
  final List<StationSearchLine> lines;

  List<String>? _normalizedTermsCache;

  /// 검색은 역 이름만 본다(한글명·영문명·부역명).
  /// aliases에 섞인 역번호·호선 합성어("448", "4호선 상록수")는 쓰지 않는다.
  List<String> get _normalizedTerms {
    return _normalizedTermsCache ??= [
      nameKo,
      '$nameKo역',
      nameEn,
      if (nameSub.isNotEmpty) nameSub,
    ].map(_normalize).where((term) => term.isNotEmpty).toList(growable: false);
  }

  void primeSearchTerms() {
    _normalizedTerms;
  }

  bool matches(String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return false;
    }
    return matchRank(normalizedQuery) != null;
  }

  /// 낮을수록 우선. 0=완전일치, 1=접두, 2=포함. 미매칭은 null.
  /// 초성 질의(`ㅅ`, `ㅅㅂ`)는 역명 초성 접두/완전일치로 매칭한다.
  int? matchRank(String normalizedQuery) {
    var best = 3;
    var matched = false;
    for (final term in _normalizedTerms) {
      if (term == normalizedQuery) {
        return 0;
      }
      if (term.startsWith(normalizedQuery)) {
        matched = true;
        if (best > 1) {
          best = 1;
        }
      } else if (term.contains(normalizedQuery)) {
        matched = true;
        if (best > 2) {
          best = 2;
        }
      }
    }
    if (matched) {
      return best;
    }
    final queryChosung = _chosungKey(normalizedQuery);
    if (queryChosung.isEmpty || !_isHangulJamoOnly(normalizedQuery)) {
      return null;
    }
    for (final term in _normalizedTerms) {
      final termChosung = _chosungKey(term);
      if (termChosung.isEmpty) {
        continue;
      }
      if (termChosung == queryChosung) {
        return 0;
      }
      if (termChosung.startsWith(queryChosung)) {
        matched = true;
        if (best > 1) {
          best = 1;
        }
      }
    }
    return matched ? best : null;
  }

  StationSearchResult toSearchResult({int? distanceMeters}) {
    return StationSearchResult(
      id: id,
      nameKo: nameKo,
      nameEn: nameEn,
      nameSub: nameSub,
      region: region,
      dataQualityLevel: dataQualityLevel,
      dataSourceType: dataSourceType,
      lastVerifiedAt: lastVerifiedAt,
      distanceMeters: distanceMeters,
      lines: List.unmodifiable(lines),
    );
  }
}

final _whitespacePattern = RegExp(r'\s+');

/// 음절 초성 인덱스(0–18) → 호환 자모.
const _hangulChoseongCompat = <String>[
  'ㄱ',
  'ㄲ',
  'ㄴ',
  'ㄷ',
  'ㄸ',
  'ㄹ',
  'ㅁ',
  'ㅂ',
  'ㅃ',
  'ㅅ',
  'ㅆ',
  'ㅇ',
  'ㅈ',
  'ㅉ',
  'ㅊ',
  'ㅋ',
  'ㅌ',
  'ㅍ',
  'ㅎ',
];

String _normalize(String value) {
  return value.toLowerCase().replaceAll(_whitespacePattern, '').trim();
}

bool _isHangulJamoRune(int rune) {
  return (rune >= 0x3131 && rune <= 0x318E) ||
      (rune >= 0x1100 && rune <= 0x11FF) ||
      (rune >= 0xA960 && rune <= 0xA97F) ||
      (rune >= 0xD7B0 && rune <= 0xD7FF);
}

bool _isHangulJamoOnly(String value) {
  if (value.isEmpty) {
    return false;
  }
  return value.runes.every(_isHangulJamoRune);
}

/// 음절·자모를 호환 초성 문자열로 펼친다. 영문 등은 건너뛴다.
String _chosungKey(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (rune >= 0xAC00 && rune <= 0xD7A3) {
      buffer.write(_hangulChoseongCompat[(rune - 0xAC00) ~/ 588]);
      continue;
    }
    // 호환 자모 초성만 유지(중·종성은 초성 질의에 쓰지 않음).
    if (rune >= 0x3131 && rune <= 0x314E) {
      buffer.write(String.fromCharCode(rune));
      continue;
    }
    // 현대 초성 jamo (U+1100–U+1112)
    if (rune >= 0x1100 && rune <= 0x1112) {
      buffer.write(_hangulChoseongCompat[rune - 0x1100]);
    }
  }
  return buffer.toString();
}

String _lineSearchName(String lineName) {
  return lineName.replaceAll('수도권 ', '').replaceAll('광역 ', '').trim();
}

String _lineCode(String lineName) {
  final numberedLine = RegExp(r'(\d+)\s*호선').firstMatch(lineName);
  if (numberedLine != null) {
    return numberedLine.group(1) ?? '';
  }
  return _lineSearchName(lineName).replaceAll('선', '');
}

String _lineRegion(String lineName) {
  for (final region in const ['수도권', '부산', '대구', '대전', '광주']) {
    if (lineName.startsWith(region)) {
      return region;
    }
  }
  return '수도권';
}

String _dateLabelFromEpoch(int? value) {
  if (value == null) {
    return '';
  }
  final utc = switch (value.abs()) {
    < 10000000000 => DateTime.fromMillisecondsSinceEpoch(
      value * 1000,
      isUtc: true,
    ),
    > 100000000000000 => DateTime.fromMicrosecondsSinceEpoch(
      value,
      isUtc: true,
    ),
    _ => DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
  };
  return _dateLabel(utc);
}

String _dateLabel(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

String _fieldValidationStatus(String? qualityLevel, int? checkedAt) {
  final normalizedLevel = qualityLevel?.trim().toUpperCase();
  return switch (normalizedLevel) {
    'FIELD_VERIFIED' when checkedAt != null => 'VERIFIED',
    'FIELD_STALE' => 'STALE',
    'FIELD_UNKNOWN' => 'UNKNOWN',
    _ => 'UNKNOWN',
  };
}

String _fieldValidationConfidence(String? qualityLevel, int? checkedAt) {
  final normalizedLevel = qualityLevel?.trim().toUpperCase();
  return switch (normalizedLevel) {
    'FIELD_VERIFIED' when checkedAt != null => 'HIGH',
    'FIELD_STALE' || 'FIELD_UNKNOWN' => 'LOW',
    _ => 'LOW',
  };
}

int _distanceMeters({
  required double fromLatitude,
  required double fromLongitude,
  required double toLatitude,
  required double toLongitude,
}) {
  const earthRadiusMeters = 6371000.0;
  final fromLatRad = _degreesToRadians(fromLatitude);
  final toLatRad = _degreesToRadians(toLatitude);
  final deltaLat = _degreesToRadians(toLatitude - fromLatitude);
  final deltaLon = _degreesToRadians(toLongitude - fromLongitude);

  final haversine =
      math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
      math.cos(fromLatRad) *
          math.cos(toLatRad) *
          math.sin(deltaLon / 2) *
          math.sin(deltaLon / 2);
  return (earthRadiusMeters *
          2 *
          math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine)))
      .round();
}

double _degreesToRadians(double degrees) {
  return degrees * math.pi / 180;
}

String _storedNetworkMapRegion(String region) {
  return switch (region) {
    '부산' => '부산권',
    '광주' => '광주권',
    '대구' => '대구권',
    '대전' => '대전권',
    _ => region,
  };
}
