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
  Future<FavoriteStation> saveFavoriteStation(String stationId) async {
    return _station;
  }

  @override
  Future<void> removeFavoriteStation(String stationId) async {}
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
  final _queries = <String>['상록수', '사당'];

  @override
  Future<void> recordSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _queries
      ..remove(trimmed)
      ..insert(0, trimmed);
  }

  @override
  Future<List<String>> listRecentQueries() async {
    return List.unmodifiable(_queries);
  }

  @override
  Future<void> removeSearch(String query) async {
    _queries.remove(query.trim());
  }

  @override
  Future<void> clearSearches() async {
    _queries.clear();
  }
}
