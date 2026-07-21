import 'package:drift/drift.dart';

import '../../../core/database/user/user_database.dart' as user_db;
import '../../../station_search.dart';

class DriftSearchHistoryRepository implements SearchHistoryRepository {
  DriftSearchHistoryRepository({
    required this.userDatabase,
    this.maxEntries = 10,
  });

  final user_db.UserDatabase userDatabase;
  final int maxEntries;

  @override
  Future<void> recordSearch(String query, {String? region}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final normalizedRegion = _normalizeRegion(region);
    // 지역 없는 기록은 지역 필터 목록에 안 보이므로 저장하지 않는다.
    if (normalizedRegion == null || normalizedRegion.isEmpty) {
      return;
    }

    await userDatabase.transaction(() async {
      // 같은 검색어라도 지역이 다르면 별도 행으로 유지한다.
      await userDatabase.customStatement(
        '''
        DELETE FROM search_history
        WHERE query = ?
          AND IFNULL(region, '') = ?
        ''',
        [trimmed, normalizedRegion],
      );
      await userDatabase
          .into(userDatabase.searchHistory)
          .insert(
            user_db.SearchHistoryCompanion.insert(
              query: trimmed,
              region: Value(normalizedRegion),
              searchedAt: DateTime.now().toUtc(),
            ),
          );
      await _pruneUnified();
    });
  }

  @override
  Future<void> recordRouteSearch(RecentRouteSearchEntry entry) async {
    final region = _normalizeRegion(entry.region);
    // 지역이 없는 경로는 지역 필터 목록에 절대 노출되지 않으므로 저장하지 않는다.
    if (region == null || region.isEmpty) {
      return;
    }
    final originId = entry.originStationId.trim();
    final destinationId = entry.destinationStationId.trim();
    if (originId.isEmpty || destinationId.isEmpty) {
      return;
    }
    final waypointId = entry.waypointStationId?.trim();
    final waypointName = entry.waypointStationName?.trim();

    await userDatabase.transaction(() async {
      // 같은 경로(출발·경유·도착·지역)는 기존 항목을 지우고 다시 넣어 최신순으로 올린다.
      await userDatabase.customStatement(
        '''
        DELETE FROM route_search_history
        WHERE origin_station_id = ?
          AND destination_station_id = ?
          AND region = ?
          AND IFNULL(waypoint_station_id, '') = ?
        ''',
        [originId, destinationId, region, waypointId ?? ''],
      );
      await userDatabase
          .into(userDatabase.routeSearchHistory)
          .insert(
            user_db.RouteSearchHistoryCompanion.insert(
              originStationId: originId,
              originStationName: entry.originStationName.trim(),
              waypointStationId: Value(
                waypointId == null || waypointId.isEmpty ? null : waypointId,
              ),
              waypointStationName: Value(
                waypointName == null || waypointName.isEmpty
                    ? null
                    : waypointName,
              ),
              destinationStationId: destinationId,
              destinationStationName: entry.destinationStationName.trim(),
              region: region,
              searchedAt: DateTime.now().toUtc(),
            ),
          );
      await _pruneUnified();
    });
  }

  @override
  Future<List<String>> listRecentQueries() async {
    final rows = await userDatabase
        .customSelect(
          '''
          SELECT query
          FROM search_history
          ORDER BY searched_at DESC, id DESC
          LIMIT ?
          ''',
          variables: [Variable.withInt(maxEntries)],
          readsFrom: {userDatabase.searchHistory},
        )
        .get();
    return rows.map((row) => row.read<String>('query')).toList(growable: false);
  }

  @override
  Future<List<RecentSearchEntry>> listRecentEntries({
    String? region,
    int limit = 10,
  }) async {
    final filterRegion = _normalizeRegion(region);
    // 지역 없는 레거시 행은 v3 마이그레이션에서 한 번만 정리된다(#2419).
    // 조회는 아래 _stationMatchesRegion 필터로 결과에서만 제외한다.
    final stationRows = await userDatabase
        .customSelect(
          '''
          SELECT query, region, searched_at
          FROM search_history
          ORDER BY searched_at DESC, id DESC
          ''',
          readsFrom: {userDatabase.searchHistory},
        )
        .get();
    final routeRows = await userDatabase
        .customSelect(
          '''
          SELECT origin_station_id, origin_station_name,
                 waypoint_station_id, waypoint_station_name,
                 destination_station_id, destination_station_name,
                 region, searched_at
          FROM route_search_history
          ORDER BY searched_at DESC, id DESC
          ''',
          readsFrom: {userDatabase.routeSearchHistory},
        )
        .get();

    final entries = <RecentSearchEntry>[];
    for (final row in stationRows) {
      final rowRegion = row.read<String?>('region');
      if (!_stationMatchesRegion(rowRegion, filterRegion)) {
        continue;
      }
      entries.add(
        RecentStationSearchEntry(
          query: row.read<String>('query'),
          region: rowRegion,
          searchedAt: row.read<DateTime>('searched_at'),
        ),
      );
    }
    for (final row in routeRows) {
      final rowRegion = row.read<String>('region');
      if (filterRegion != null &&
          filterRegion.isNotEmpty &&
          !stationBelongsToRegion(rowRegion, filterRegion)) {
        continue;
      }
      entries.add(
        RecentRouteSearchEntry(
          originStationId: row.read<String>('origin_station_id'),
          originStationName: row.read<String>('origin_station_name'),
          waypointStationId: row.read<String?>('waypoint_station_id'),
          waypointStationName: row.read<String?>('waypoint_station_name'),
          destinationStationId: row.read<String>('destination_station_id'),
          destinationStationName: row.read<String>('destination_station_name'),
          region: rowRegion,
          searchedAt: row.read<DateTime>('searched_at'),
        ),
      );
    }

    entries.sort((a, b) => b.searchedAt.compareTo(a.searchedAt));
    return entries.take(limit).toList(growable: false);
  }

  @override
  Future<void> removeSearch(String query, {String? region}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final normalizedRegion = _normalizeRegion(region);
    if (normalizedRegion == null || normalizedRegion.isEmpty) {
      await userDatabase.customStatement(
        'DELETE FROM search_history WHERE query = ?',
        [trimmed],
      );
      return;
    }
    await userDatabase.customStatement(
      '''
      DELETE FROM search_history
      WHERE query = ?
        AND IFNULL(region, '') = ?
      ''',
      [trimmed, normalizedRegion],
    );
  }

  @override
  Future<void> removeRouteSearch(RecentRouteSearchEntry entry) async {
    final region = _normalizeRegion(entry.region);
    await userDatabase.customStatement(
      '''
      DELETE FROM route_search_history
      WHERE origin_station_id = ?
        AND destination_station_id = ?
        AND region = ?
        AND IFNULL(waypoint_station_id, '') = ?
      ''',
      [
        entry.originStationId.trim(),
        entry.destinationStationId.trim(),
        region ?? '',
        entry.waypointStationId?.trim() ?? '',
      ],
    );
  }

  @override
  Future<void> clearSearches() async {
    await userDatabase.transaction(() async {
      await userDatabase.delete(userDatabase.searchHistory).go();
      await userDatabase.delete(userDatabase.routeSearchHistory).go();
    });
  }

  /// 역·경로를 합친 통합 목록이 [maxEntries]를 넘으면 오래된 것부터 지운다.
  Future<void> _pruneUnified() async {
    // 리뷰 finding E: 지역 없는 레거시 행(v3 마이그레이션 이전에 생긴 것 등)이
    // 남아 있으면 통합 prune 슬롯을 차지해 정상 행을 밀어낸다. prune마다 먼저
    // 지운다(listRecentEntries 읽기 경로에는 넣지 않음 — 이전 리뷰에서 마이그
    // 레이션으로 옮긴 결정 유지).
    await userDatabase.customStatement('''
          DELETE FROM search_history WHERE region IS NULL OR region = ''
          ''');
    final rows = await userDatabase.customSelect('''
          SELECT id, 'station' AS kind, searched_at FROM search_history
          UNION ALL
          SELECT id, 'route' AS kind, searched_at FROM route_search_history
          ORDER BY searched_at DESC, id DESC, kind ASC
          ''').get();
    if (rows.length <= maxEntries) {
      return;
    }
    final overflow = rows.skip(maxEntries);
    final stationIds = <int>[];
    final routeIds = <int>[];
    for (final row in overflow) {
      final id = row.read<int>('id');
      if (row.read<String>('kind') == 'station') {
        stationIds.add(id);
      } else {
        routeIds.add(id);
      }
    }
    if (stationIds.isNotEmpty) {
      await userDatabase.customStatement(
        'DELETE FROM search_history WHERE id IN (${_placeholders(stationIds.length)})',
        stationIds,
      );
    }
    if (routeIds.isNotEmpty) {
      await userDatabase.customStatement(
        'DELETE FROM route_search_history WHERE id IN (${_placeholders(routeIds.length)})',
        routeIds,
      );
    }
  }

  bool _stationMatchesRegion(String? rowRegion, String? filterRegion) {
    if (filterRegion == null || filterRegion.isEmpty) {
      return true;
    }
    if (rowRegion == null || rowRegion.isEmpty) {
      return false;
    }
    return stationBelongsToRegion(rowRegion, filterRegion);
  }

  String? _normalizeRegion(String? region) {
    final trimmed = region?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return normalizeStationRegion(trimmed);
  }

  String _placeholders(int count) => List.filled(count, '?').join(', ');
}
