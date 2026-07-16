import 'station_models.dart';

abstract class StationSearchRepository {
  Future<List<StationSearchResult>> searchStations(String query);

  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  });

  Future<StationDetail> getStationDetail(String stationId);

  Future<List<StationExitInfo>> listStationExits(String stationId);

  Future<List<StationFacilityInfo>> listStationFacilities(String stationId);
}

abstract class SearchHistoryRepository {
  Future<void> recordSearch(String query);

  Future<List<String>> listRecentQueries();

  Future<void> removeSearch(String query);

  Future<void> clearSearches();
}

abstract class StationLineFilterRepository {
  Future<List<SubwayLineOption>> listLines();

  Future<List<StationSearchResult>> searchStationsOnLine(
    String query,
    String lineId,
  );
}

abstract class StationTimetableRepository {
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  });

  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  });
}

abstract class CurrentLocationProvider {
  Future<bool> needsLocationPermissionRequest();

  Future<CurrentLocation> currentLocation();

  Future<bool> openLocationSettings();
}

class CurrentLocationException implements Exception {
  const CurrentLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StationSearchException implements Exception {
  const StationSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class FavoriteStationRepository {
  Future<List<FavoriteStation>> listFavoriteStations();

  Future<FavoriteStation> saveFavoriteStation(String stationId);

  Future<void> removeFavoriteStation(String stationId);
}

class FavoriteStationException implements Exception {
  const FavoriteStationException(this.message);

  final String message;

  @override
  String toString() => message;
}
