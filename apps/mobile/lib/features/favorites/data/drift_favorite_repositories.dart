import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/catalog/catalog_database.dart';
import '../../../core/database/user/user_database.dart' as user_db;
import '../../../favorite_facility.dart';
import '../../../route_search.dart';
import '../../../station_search.dart';

const _localUserId = 'local-user';
const _routeSnapshotPrefix = 'favorite_route_snapshot:';

class DriftFavoriteStationRepository implements FavoriteStationRepository {
  DriftFavoriteStationRepository({
    required this.catalogDatabase,
    required this.userDatabase,
  });

  final CatalogDatabase catalogDatabase;
  final user_db.UserDatabase userDatabase;

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    final favoriteRows = await userDatabase
        .customSelect(
          '''
          SELECT station_id, CAST(added_at AS INTEGER) AS added_at_value
          FROM favorite_stations
          ORDER BY added_at DESC
          ''',
          readsFrom: {userDatabase.favoriteStations},
        )
        .get();

    final favorites = <FavoriteStation>[];
    for (final favoriteRow in favoriteRows) {
      final stationId = favoriteRow.read<String>('station_id');
      final stationRows = await catalogDatabase
          .customSelect(
            '''
            SELECT
              s.id,
              s.name_ko,
              s.name_en,
              s.region,
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
            WHERE s.id = ?
            ORDER BY sl.line_sequence
            ''',
            variables: [Variable.withString(stationId)],
            readsFrom: {
              catalogDatabase.stations,
              catalogDatabase.stationLines,
              catalogDatabase.lines,
            },
          )
          .get();
      if (stationRows.isEmpty) {
        continue;
      }
      final firstRow = stationRows.first;
      final builder = FavoriteStationBuilder(
        stationId: stationId,
        nameKo: firstRow.read<String>('name_ko'),
        nameEn: firstRow.read<String?>('name_en') ?? '',
        region: firstRow.read<String?>('region') ?? '',
        dataQualityLevel: firstRow.read<String?>('data_quality_level') ?? '',
        dataSourceType: firstRow.read<String?>('data_source_type') ?? '',
        lastVerifiedAt: _dateLabelFromEpoch(
          firstRow.read<int?>('last_verified_at_value'),
        ),
        addedAt: _isoFromEpoch(favoriteRow.read<int?>('added_at_value')),
      );
      for (final row in stationRows) {
        final lineId = row.read<String?>('line_id');
        if (lineId != null) {
          builder.lines.add(
            StationSearchLine(
              id: lineId,
              name: row.read<String>('line_name'),
              color: row.read<String>('line_color'),
              stationCode: row.read<String>('station_code'),
            ),
          );
        }
      }
      favorites.add(builder.build());
    }

    return favorites;
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(String stationId) async {
    final trimmedStationId = stationId.trim();
    await _ensureStationExists(trimmedStationId);
    await userDatabase
        .into(userDatabase.favoriteStations)
        .insertOnConflictUpdate(
          user_db.FavoriteStationsCompanion.insert(
            stationId: trimmedStationId,
            addedAt: DateTime.now().toUtc(),
          ),
        );
    return (await listFavoriteStations()).singleWhere(
      (favorite) => favorite.stationId == trimmedStationId,
    );
  }

  @override
  Future<void> removeFavoriteStation(String stationId) async {
    await userDatabase.customStatement(
      'DELETE FROM favorite_stations WHERE station_id = ?',
      [stationId.trim()],
    );
  }

  Future<void> _ensureStationExists(String stationId) async {
    final row = await catalogDatabase
        .customSelect(
          'SELECT id FROM stations WHERE id = ?',
          variables: [Variable.withString(stationId)],
          readsFrom: {catalogDatabase.stations},
        )
        .getSingleOrNull();
    if (row == null) {
      throw const FavoriteStationException('즐겨찾기 역을 저장하지 못했습니다.');
    }
  }
}

class DriftFavoriteFacilityRepository implements FavoriteFacilityRepository {
  DriftFavoriteFacilityRepository({
    required this.catalogDatabase,
    required this.userDatabase,
  });

  final CatalogDatabase catalogDatabase;
  final user_db.UserDatabase userDatabase;

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    final favoriteRows = await userDatabase
        .customSelect(
          '''
          SELECT facility_id, station_id, CAST(added_at AS INTEGER) AS added_at_value
          FROM favorite_facilities
          ORDER BY added_at DESC
          ''',
          readsFrom: {userDatabase.favoriteFacilities},
        )
        .get();

    final favorites = <FavoriteFacility>[];
    for (final favoriteRow in favoriteRows) {
      final facilityId = favoriteRow.read<String>('facility_id');
      final row = await catalogDatabase
          .customSelect(
            '''
            SELECT
              f.id,
              f.station_id,
              f.exit_id,
              f.type,
              f.name,
              f.floor_from,
              f.floor_to,
              f.description,
              f.status,
              s.name_ko AS station_name_ko,
              s.name_en AS station_name_en,
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
            WHERE f.id = ?
            ''',
            variables: [Variable.withString(facilityId)],
            readsFrom: {
              catalogDatabase.facilities,
              catalogDatabase.stations,
              catalogDatabase.dataQualityRecords,
            },
          )
          .getSingleOrNull();
      if (row == null) {
        continue;
      }
      favorites.add(
        FavoriteFacility(
          userId: _localUserId,
          facilityId: row.read<String>('id'),
          stationId: row.read<String>('station_id'),
          stationNameKo: row.read<String>('station_name_ko'),
          stationNameEn: row.read<String?>('station_name_en') ?? '',
          exitId: row.read<String?>('exit_id') ?? '',
          type: row.read<String?>('type') ?? '',
          name: row.read<String?>('name') ?? '',
          floorFrom: row.read<String?>('floor_from') ?? '',
          floorTo: row.read<String?>('floor_to') ?? '',
          description: row.read<String?>('description') ?? '',
          status: row.read<String?>('status') ?? '',
          dataConfidence: 'MEDIUM',
          dataSourceType: row.read<String?>('data_source_type') ?? '',
          fieldValidationStatus: _fieldValidationStatus(
            row.read<String?>('field_quality_level'),
            row.read<int?>('field_checked_at_value'),
          ),
          lastUpdatedAt: _dateLabelFromEpoch(
            row.read<int?>('field_checked_at_value') ??
                row.read<int?>('last_verified_at_value'),
          ),
          addedAt: _isoFromEpoch(favoriteRow.read<int?>('added_at_value')),
        ),
      );
    }
    return favorites;
  }

  @override
  Future<FavoriteFacility> saveFavoriteFacility(String facilityId) async {
    final trimmedFacilityId = facilityId.trim();
    final row = await _facilityCatalogRow(trimmedFacilityId);
    if (row == null) {
      throw const FavoriteFacilityException('즐겨찾기 시설을 처리하지 못했습니다.');
    }
    await userDatabase
        .into(userDatabase.favoriteFacilities)
        .insertOnConflictUpdate(
          user_db.FavoriteFacilitiesCompanion.insert(
            facilityId: trimmedFacilityId,
            stationId: row.read<String>('station_id'),
            addedAt: DateTime.now().toUtc(),
          ),
        );
    return (await listFavoriteFacilities()).singleWhere(
      (favorite) => favorite.facilityId == trimmedFacilityId,
    );
  }

  @override
  Future<void> removeFavoriteFacility(String facilityId) async {
    await userDatabase.customStatement(
      'DELETE FROM favorite_facilities WHERE facility_id = ?',
      [facilityId.trim()],
    );
  }

  Future<QueryRow?> _facilityCatalogRow(String facilityId) {
    return catalogDatabase
        .customSelect(
          'SELECT id, station_id FROM facilities WHERE id = ?',
          variables: [Variable.withString(facilityId)],
          readsFrom: {catalogDatabase.facilities},
        )
        .getSingleOrNull();
  }
}

class DriftFavoriteRouteRepository implements FavoriteRouteRepository {
  DriftFavoriteRouteRepository({
    required this.catalogDatabase,
    required this.userDatabase,
  });

  final CatalogDatabase catalogDatabase;
  final user_db.UserDatabase userDatabase;

  @override
  Future<List<FavoriteRoute>> listFavoriteRoutes() async {
    final rows = await userDatabase
        .customSelect(
          '''
          SELECT route_id, origin_station_id, destination_station_id,
                 mobility_profile, CAST(added_at AS INTEGER) AS added_at_value
          FROM favorite_routes
          ORDER BY added_at DESC
          ''',
          readsFrom: {userDatabase.favoriteRoutes},
        )
        .get();

    final favorites = <FavoriteRoute>[];
    for (final row in rows) {
      final routeId = row.read<String>('route_id');
      final snapshot = await _readRouteSnapshot(routeId);
      if (snapshot != null) {
        favorites.add(
          _favoriteRouteFromSnapshot(
            routeId: routeId,
            snapshot: snapshot,
            addedAt: _isoFromEpoch(row.read<int?>('added_at_value')),
          ),
        );
        continue;
      }

      favorites.add(
        await _fallbackFavoriteRoute(
          routeId: routeId,
          originStationId: row.read<String>('origin_station_id'),
          destinationStationId: row.read<String>('destination_station_id'),
          mobilityType: row.read<String>('mobility_profile'),
          addedAt: _isoFromEpoch(row.read<int?>('added_at_value')),
        ),
      );
    }
    return favorites;
  }

  @override
  Future<FavoriteRoute> saveFavoriteRoute(
    String routeSearchId, {
    RouteSearchResult? result,
  }) async {
    final routeResult = result;
    if (routeResult == null) {
      throw const FavoriteRouteException('즐겨찾기 경로를 처리하지 못했습니다.');
    }
    final routeId = _favoriteRouteStorageId(
      routeSearchId: routeSearchId,
      result: routeResult,
    );

    final addedAt = DateTime.now().toUtc();
    await userDatabase
        .into(userDatabase.favoriteRoutes)
        .insertOnConflictUpdate(
          user_db.FavoriteRoutesCompanion.insert(
            routeId: routeId,
            originStationId: routeResult.originStationId,
            destinationStationId: routeResult.destinationStationId,
            mobilityProfile: routeResult.mobilityType,
            addedAt: addedAt,
          ),
        );
    await _writeRouteSnapshot(routeId, routeResult);
    return _favoriteRouteFromResult(
      result: routeResult,
      favoriteRouteId: routeId,
      addedAt: _isoFromSql(addedAt),
    );
  }

  @override
  Future<void> removeFavoriteRoute(String favoriteRouteId) async {
    final routeId = favoriteRouteId.trim();
    await userDatabase.transaction(() async {
      await userDatabase.customStatement(
        'DELETE FROM favorite_routes WHERE route_id = ?',
        [routeId],
      );
      await userDatabase.customStatement(
        'DELETE FROM app_preferences WHERE key = ?',
        ['$_routeSnapshotPrefix$routeId'],
      );
    });
  }

  Future<Map<String, Object?>?> _readRouteSnapshot(String routeId) async {
    final row = await userDatabase
        .customSelect(
          'SELECT value FROM app_preferences WHERE key = ?',
          variables: [Variable.withString('$_routeSnapshotPrefix$routeId')],
          readsFrom: {userDatabase.appPreferences},
        )
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final decoded = jsonDecode(row.read<String>('value'));
    return decoded is Map<String, Object?> ? decoded : null;
  }

  Future<void> _writeRouteSnapshot(
    String routeId,
    RouteSearchResult result,
  ) async {
    final catalogVersion = await _catalogVersion();
    await userDatabase
        .into(userDatabase.appPreferences)
        .insertOnConflictUpdate(
          user_db.AppPreferencesCompanion.insert(
            key: '$_routeSnapshotPrefix$routeId',
            value: jsonEncode({
              ..._routeResultToJson(result),
              'savedCatalogVersion': catalogVersion,
            }),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  FavoriteRoute _favoriteRouteFromSnapshot({
    required String routeId,
    required Map<String, Object?> snapshot,
    required String addedAt,
  }) {
    final originalRouteSearchId = _string(
      snapshot['routeSearchId'],
      fallback: routeId,
    );
    return FavoriteRoute(
      userId: _localUserId,
      favoriteRouteId: routeId,
      routeSearchId: originalRouteSearchId,
      originStationId: _string(snapshot['originStationId']),
      originStationName: _string(snapshot['originStationName']),
      destinationStationId: _string(snapshot['destinationStationId']),
      destinationStationName: _string(snapshot['destinationStationName']),
      mobilityType: _string(snapshot['mobilityType']),
      status: _string(snapshot['status'], fallback: 'FOUND'),
      lineId: _string(snapshot['lineId']),
      lineName: _string(snapshot['lineName']),
      score: snapshot['score'] is int ? snapshot['score'] as int : 0,
      routeCreatedAt: _string(snapshot['createdAt']),
      addedAt: addedAt,
    );
  }

  Future<FavoriteRoute> _fallbackFavoriteRoute({
    required String routeId,
    required String originStationId,
    required String destinationStationId,
    required String mobilityType,
    required String addedAt,
  }) async {
    final originName = await _stationName(originStationId);
    final destinationName = await _stationName(destinationStationId);
    return FavoriteRoute(
      userId: _localUserId,
      favoriteRouteId: routeId,
      routeSearchId: routeId,
      originStationId: originStationId,
      originStationName: originName,
      destinationStationId: destinationStationId,
      destinationStationName: destinationName,
      mobilityType: mobilityType,
      status: 'FOUND',
      lineId: '',
      lineName: '',
      score: 0,
      routeCreatedAt: addedAt,
      addedAt: addedAt,
    );
  }

  Future<String> _stationName(String stationId) async {
    final row = await catalogDatabase
        .customSelect(
          'SELECT name_ko FROM stations WHERE id = ?',
          variables: [Variable.withString(stationId)],
          readsFrom: {catalogDatabase.stations},
        )
        .getSingleOrNull();
    return row?.read<String>('name_ko') ?? stationId;
  }

  Future<String> _catalogVersion() async {
    final row = await catalogDatabase
        .customSelect(
          "SELECT value FROM catalog_metadata WHERE key = 'schemaVersion'",
          readsFrom: {catalogDatabase.catalogMetadata},
        )
        .getSingleOrNull();
    return row?.read<String>('value') ?? '';
  }
}

class FavoriteStationBuilder {
  FavoriteStationBuilder({
    required this.stationId,
    required this.nameKo,
    required this.nameEn,
    required this.region,
    required this.dataQualityLevel,
    required this.dataSourceType,
    required this.lastVerifiedAt,
    required this.addedAt,
  });

  final String stationId;
  final String nameKo;
  final String nameEn;
  final String region;
  final String dataQualityLevel;
  final String dataSourceType;
  final String lastVerifiedAt;
  final String addedAt;
  final List<StationSearchLine> lines = [];

  FavoriteStation build() {
    return FavoriteStation(
      userId: _localUserId,
      stationId: stationId,
      nameKo: nameKo,
      nameEn: nameEn,
      region: region,
      dataQualityLevel: dataQualityLevel,
      dataSourceType: dataSourceType,
      lastVerifiedAt: lastVerifiedAt,
      lines: List.unmodifiable(lines),
      addedAt: addedAt,
    );
  }
}

FavoriteRoute _favoriteRouteFromResult({
  required RouteSearchResult result,
  required String favoriteRouteId,
  required String addedAt,
}) {
  return FavoriteRoute(
    userId: _localUserId,
    favoriteRouteId: favoriteRouteId,
    routeSearchId: result.routeSearchId,
    originStationId: result.originStationId,
    originStationName: result.originStationName,
    destinationStationId: result.destinationStationId,
    destinationStationName: result.destinationStationName,
    mobilityType: result.mobilityType,
    status: result.status,
    lineId: result.lineId,
    lineName: result.lineName,
    score: result.score,
    routeCreatedAt: result.createdAt,
    addedAt: addedAt,
  );
}

String _favoriteRouteStorageId({
  required String routeSearchId,
  required RouteSearchResult result,
}) {
  final baseId = routeSearchId.trim().isNotEmpty
      ? routeSearchId.trim()
      : result.routeSearchId.trim();
  final mobilityType = result.mobilityType.trim();
  if (baseId.isEmpty || mobilityType.isEmpty) {
    return baseId;
  }
  return '$baseId::$mobilityType';
}

Map<String, Object?> _routeResultToJson(RouteSearchResult result) {
  return {
    'routeSearchId': result.routeSearchId,
    'originStationId': result.originStationId,
    'originStationName': result.originStationName,
    'destinationStationId': result.destinationStationId,
    'destinationStationName': result.destinationStationName,
    'mobilityType': result.mobilityType,
    'status': result.status,
    'lineId': result.lineId,
    'lineName': result.lineName,
    'score': result.score,
    'burdenCost': result.burdenCost,
    'estimatedDurationSeconds': result.estimatedDurationSeconds,
    'walkingDistanceMeters': result.walkingDistanceMeters,
    'transferCount': result.transferCount,
    'evidenceSummary': result.evidenceSummary,
    'steps': result.steps.map(_routeStepToJson).toList(growable: false),
    'warnings': result.warnings
        .map(_routeWarningToJson)
        .toList(growable: false),
    'recommendationReasons': result.recommendationReasons,
    'blockedReasons': result.blockedReasons,
    'createdAt': result.createdAt,
  };
}

Map<String, Object?> _routeStepToJson(RouteSearchStep step) {
  return {
    'sequence': step.sequence,
    'stepType': step.stepType,
    'title': step.title,
    'description': step.description,
    'lineId': step.lineId,
    'lineName': step.lineName,
    'fromStationId': step.fromStationId,
    'toStationId': step.toStationId,
    'estimatedMinutes': step.estimatedMinutes,
    'distanceMeters': step.distanceMeters,
    'includesStairs': step.includesStairs,
    'requiresAccessibilityCheck': step.requiresAccessibilityCheck,
  };
}

Map<String, Object?> _routeWarningToJson(RouteSearchWarning warning) {
  return {'code': warning.code};
}

String _isoFromSql(DateTime value) => value.toUtc().toIso8601String();

String _isoFromEpoch(int? value) {
  if (value == null) {
    return '';
  }
  return _dateTimeFromEpoch(value).toIso8601String();
}

String _dateLabelFromEpoch(int? value) {
  if (value == null) {
    return '';
  }
  final utc = _dateTimeFromEpoch(value);
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

DateTime _dateTimeFromEpoch(int value) {
  return switch (value.abs()) {
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

String _string(Object? value, {String fallback = ''}) {
  if (value is String) {
    return value;
  }
  return fallback;
}
