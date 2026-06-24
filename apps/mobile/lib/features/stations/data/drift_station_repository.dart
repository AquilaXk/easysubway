import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/catalog/catalog_database.dart';
import '../../../network_map.dart';
import '../../../station_search.dart';

class DriftStationRepository
    implements
        StationSearchRepository,
        StationLineFilterRepository,
        NetworkMapRepository {
  DriftStationRepository({required this.database});

  final CatalogDatabase database;
  Future<List<_LocalStationSummary>>? _stationSummaryCache;

  void invalidateStationSummaryCache() {
    _stationSummaryCache = null;
  }

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const [];
    }

    final stations = await _listStationSummaries();
    return stations
        .where((station) => station.matches(trimmedQuery))
        .map((station) => station.toSearchResult())
        .toList(growable: false);
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
            region: '수도권',
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
      throw const StationSearchException('역 정보를 불러오지 못했습니다.');
    }

    return StationDetail(
      id: summary.id,
      nameKo: summary.nameKo,
      nameEn: summary.nameEn,
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
    final rows = await database
        .customSelect(
          '''
          SELECT
            e.id,
            e.station_id,
            e.exit_number,
            e.description,
            s.data_source_type,
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
            EXISTS(
              SELECT 1
              FROM facilities f
              WHERE f.exit_id = e.id
                AND UPPER(f.type) = 'ELEVATOR'
            ) AS has_elevator_connection
          FROM station_exits e
          JOIN stations s ON s.id = e.station_id
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
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
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
              upPath: row.read<String>('up_path'),
              downPath: row.read<String>('down_path'),
              sourceId: row.read<String>('source_id'),
            ),
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
    );
  }

  Future<String> _selectedNetworkMapRegion(String? requestedRegion) async {
    final trimmedRegion = requestedRegion?.trim();
    if (trimmedRegion != null && trimmedRegion.isNotEmpty) {
      return trimmedRegion;
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
  final String region;
  final double? latitude;
  final double? longitude;
  final String dataQualityLevel;
  final String dataSourceType;
  final String lastVerifiedAt;
  final List<String> aliases;
  final List<StationSearchLine> lines;

  bool matches(String query) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return false;
    }

    final terms = <String>{
      nameKo,
      '$nameKo역',
      nameEn,
      ...aliases,
      ...lines.map((line) => line.stationCode),
      ...lines.map((line) => '${_lineSearchName(line.name)}$nameKo'),
    };

    return terms
        .map(_normalize)
        .any(
          (term) => term == normalizedQuery || term.contains(normalizedQuery),
        );
  }

  StationSearchResult toSearchResult({int? distanceMeters}) {
    return StationSearchResult(
      id: id,
      nameKo: nameKo,
      nameEn: nameEn,
      region: region,
      dataQualityLevel: dataQualityLevel,
      dataSourceType: dataSourceType,
      lastVerifiedAt: lastVerifiedAt,
      distanceMeters: distanceMeters,
      lines: List.unmodifiable(lines),
    );
  }
}

String _normalize(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), '').trim();
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
