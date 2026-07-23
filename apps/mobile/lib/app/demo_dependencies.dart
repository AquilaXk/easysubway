import '../favorite_facility.dart';
import '../route_search.dart';
import '../station_search.dart';

class DemoFavoriteStationRepository implements FavoriteStationRepository {
  const DemoFavoriteStationRepository();

  static const _station = FavoriteStation(
    userId: 'demo-user',
    stationId: 'station-sangnoksu',
    nameKo: '상록수',
    nameEn: 'Sangnoksu',
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    dataSourceType: 'OFFICIAL_FILE',
    lastVerifiedAt: '2026-06-13',
    lines: [
      StationSearchLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        stationCode: '448',
      ),
    ],
    addedAt: '2026-06-13T10:00:00',
  );

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    return const [_station];
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(
    String stationId, {
    String? lineId,
  }) async {
    return _station;
  }

  @override
  Future<void> removeFavoriteStation(
    String stationId, {
    String? lineId,
  }) async {}
}

class DemoFavoriteFacilityRepository implements FavoriteFacilityRepository {
  const DemoFavoriteFacilityRepository();

  static const _facility = FavoriteFacility(
    userId: 'demo-user',
    facilityId: 'facility-sangnoksu-elevator-3',
    stationId: 'station-sangnoksu',
    stationNameKo: '상록수',
    stationNameEn: 'Sangnoksu',
    exitId: 'exit-sangnoksu-3',
    type: 'ELEVATOR',
    name: '3번 출구 엘리베이터',
    floorFrom: '1F',
    floorTo: 'B1',
    description: '3번 출구 앞',
    status: 'NEEDS_CHECK',
    dataConfidence: 'HIGH',
    dataSourceType: 'OFFICIAL_FILE',
    lastUpdatedAt: '2026-06-12',
    addedAt: '2026-06-14T10:00:00',
  );

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    return const [_facility];
  }

  @override
  Future<FavoriteFacility> saveFavoriteFacility(String facilityId) async {
    return _facility;
  }

  @override
  Future<void> removeFavoriteFacility(String facilityId) async {}
}

class DemoFavoriteRouteRepository implements FavoriteRouteRepository {
  const DemoFavoriteRouteRepository();

  static const _route = FavoriteRoute(
    userId: 'demo-user',
    favoriteRouteId: 'route-1',
    routeSearchId: 'route-1',
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-sadang',
    destinationStationName: '사당',
    mobilityType: 'SENIOR',
    status: 'FOUND',
    lineId: 'seoul-4',
    lineName: '수도권 4호선',
    score: 92,
    routeCreatedAt: '2026-06-13T09:00:00',
    addedAt: '2026-06-14T10:00:00',
  );

  @override
  Future<List<FavoriteRoute>> listFavoriteRoutes() async {
    return const [_route];
  }

  @override
  Future<FavoriteRoute> saveFavoriteRoute(
    String routeSearchId, {
    RouteSearchResult? result,
  }) async {
    return _route;
  }

  @override
  Future<void> removeFavoriteRoute(String favoriteRouteId) async {}
}

class DemoSearchHistoryRepository implements SearchHistoryRepository {
  DemoSearchHistoryRepository() {
    _addStation('사당', region: '수도권');
    _addStation('상록수', region: '수도권');
  }

  final _stations = <RecentStationSearchEntry>[];
  final _routes = <RecentRouteSearchEntry>[];
  int _clock = 0;

  DateTime _tick() =>
      DateTime.fromMillisecondsSinceEpoch(++_clock, isUtc: true);

  void _addStation(
    String query, {
    required String region,
    List<StationSearchLine> lines = const [],
  }) {
    _stations.removeWhere(
      (entry) => entry.query == query && (entry.region?.trim() ?? '') == region,
    );
    _stations.insert(
      0,
      RecentStationSearchEntry(
        query: query,
        region: region,
        searchedAt: _tick(),
        lines: lines,
      ),
    );
  }

  @override
  Future<void> recordSearch(
    String query, {
    String? region,
    String? stationId,
    StationSearchLine? line,
  }) async {
    final trimmed = query.trim();
    final normalizedRegion = region?.trim() ?? '';
    if (trimmed.isEmpty || normalizedRegion.isEmpty) {
      return;
    }
    _addStation(
      trimmed,
      region: normalizeStationRegion(normalizedRegion),
      lines: line == null || line.id.trim().isEmpty ? const [] : [line],
    );
  }

  @override
  Future<void> recordRouteSearch(RecentRouteSearchEntry entry) async {
    final region = entry.region.trim();
    if (region.isEmpty) {
      return;
    }
    _routes.removeWhere(
      (existing) => existing.identityKey == entry.identityKey,
    );
    _routes.insert(
      0,
      RecentRouteSearchEntry(
        originStationId: entry.originStationId,
        originStationName: entry.originStationName,
        originLines: entry.originLines,
        waypointStationId: entry.waypointStationId,
        waypointStationName: entry.waypointStationName,
        waypointLines: entry.waypointLines,
        destinationStationId: entry.destinationStationId,
        destinationStationName: entry.destinationStationName,
        destinationLines: entry.destinationLines,
        region: entry.region,
        searchedAt: _tick(),
      ),
    );
  }

  @override
  Future<List<String>> listRecentQueries() async {
    return _stations.map((entry) => entry.query).toList(growable: false);
  }

  @override
  Future<List<RecentSearchEntry>> listRecentEntries({
    String? region,
    int limit = 10,
  }) async {
    final filter = region?.trim();
    final entries = <RecentSearchEntry>[
      ..._stations.where((entry) => _stationMatches(entry.region, filter)),
      ..._routes.where(
        (entry) =>
            filter == null ||
            filter.isEmpty ||
            stationBelongsToRegion(entry.region, filter),
      ),
    ]..sort((a, b) => b.searchedAt.compareTo(a.searchedAt));
    return entries.take(limit).toList(growable: false);
  }

  @override
  Future<void> removeSearch(String query, {String? region}) async {
    final trimmed = query.trim();
    final normalizedRegion = region?.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (normalizedRegion == null || normalizedRegion.isEmpty) {
      _stations.removeWhere((entry) => entry.query == trimmed);
      return;
    }
    final filter = normalizeStationRegion(normalizedRegion);
    _stations.removeWhere(
      (entry) =>
          entry.query == trimmed &&
          stationBelongsToRegion(entry.region ?? '', filter),
    );
  }

  @override
  Future<void> removeRouteSearch(RecentRouteSearchEntry entry) async {
    _routes.removeWhere(
      (existing) => existing.identityKey == entry.identityKey,
    );
  }

  @override
  Future<void> clearSearches() async {
    _stations.clear();
    _routes.clear();
  }

  bool _stationMatches(String? rowRegion, String? filter) {
    if (filter == null || filter.isEmpty) {
      return true;
    }
    if (rowRegion == null || rowRegion.isEmpty) {
      return false;
    }
    return stationBelongsToRegion(rowRegion, filter);
  }
}
