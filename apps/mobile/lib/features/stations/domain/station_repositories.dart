import 'station_line.dart';
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

/// 로컬 카탈로그 검색 인덱스를 미리 올리는 선택 계약.
/// 첫 글자 입력 전에 SQLite·정규화 비용을 걷긴다.
abstract interface class StationSearchCache {
  Future<void> warmSearchCache();
}

Future<void> warmStationSearchCacheIfSupported(
  StationSearchRepository repository,
) {
  final cache = repository is StationSearchCache
      ? repository as StationSearchCache
      : null;
  if (cache == null) {
    return Future<void>.value();
  }
  return cache.warmSearchCache();
}

/// 최근 검색 목록의 한 항목. 역 검색과 경로 검색을 같은 시간순 목록에 섞기
/// 위한 공통 타입이다.
sealed class RecentSearchEntry {
  const RecentSearchEntry();

  DateTime get searchedAt;
}

/// 역 검색 한 건. [region]은 검색 당시 선택 지역이며, 지역 정보 없이 저장된
/// 레거시 항목은 null이다(지역 필터 목록에서 제외).
///
/// [lines]는 표시용 호선 마크. 저장소에는 없고 조회 직후 카탈로그로 채운다.
class RecentStationSearchEntry extends RecentSearchEntry {
  const RecentStationSearchEntry({
    required this.query,
    required this.region,
    required this.searchedAt,
    this.lines = const [],
  });

  final String query;
  final String? region;
  final List<StationSearchLine> lines;

  @override
  final DateTime searchedAt;

  RecentStationSearchEntry withLines(List<StationSearchLine> lines) {
    return RecentStationSearchEntry(
      query: query,
      region: region,
      searchedAt: searchedAt,
      lines: lines,
    );
  }
}

/// 경로 검색 한 건. [displayLabel]은 `출발역 → 도착역` 또는
/// `출발역 → 경유역 → 도착역` 형태이며, 역 접미사 보정은 검색 결과 화면과
/// 같은 규칙(끝이 `역`이 아니면 붙임)을 쓴다.
///
/// `*Lines`는 표시용 호선 마크. 저장소에는 없고 조회 직후 카탈로그로 채운다.
class RecentRouteSearchEntry extends RecentSearchEntry {
  const RecentRouteSearchEntry({
    required this.originStationId,
    required this.originStationName,
    this.waypointStationId,
    this.waypointStationName,
    required this.destinationStationId,
    required this.destinationStationName,
    required this.region,
    required this.searchedAt,
    this.originLines = const [],
    this.waypointLines = const [],
    this.destinationLines = const [],
  });

  final String originStationId;
  final String originStationName;
  final String? waypointStationId;
  final String? waypointStationName;
  final String destinationStationId;
  final String destinationStationName;
  final String region;
  final List<StationSearchLine> originLines;
  final List<StationSearchLine> waypointLines;
  final List<StationSearchLine> destinationLines;

  @override
  final DateTime searchedAt;

  RecentRouteSearchEntry withLines({
    List<StationSearchLine> originLines = const [],
    List<StationSearchLine> waypointLines = const [],
    List<StationSearchLine> destinationLines = const [],
  }) {
    return RecentRouteSearchEntry(
      originStationId: originStationId,
      originStationName: originStationName,
      waypointStationId: waypointStationId,
      waypointStationName: waypointStationName,
      destinationStationId: destinationStationId,
      destinationStationName: destinationStationName,
      region: region,
      searchedAt: searchedAt,
      originLines: originLines,
      waypointLines: waypointLines,
      destinationLines: destinationLines,
    );
  }

  String get displayLabel {
    final origin = _withStationSuffix(originStationName);
    final destination = _withStationSuffix(destinationStationName);
    final waypoint = waypointStationName?.trim();
    if (waypoint != null && waypoint.isNotEmpty) {
      return '$origin → ${_withStationSuffix(waypoint)} → $destination';
    }
    return '$origin → $destination';
  }

  /// 같은 경로(출발·경유·도착·지역)인지 식별하는 키. 중복 제거·개별 삭제에 쓴다.
  String get identityKey =>
      '$originStationId|${waypointStationId ?? ''}|$destinationStationId|$region';
}

String _withStationSuffix(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.endsWith('역')) {
    return trimmed;
  }
  return '$trimmed역';
}

abstract class SearchHistoryRepository {
  /// 역 검색을 기록한다. [region]은 검색 당시 선택 지역(예: `수도권`, `부산`)이며,
  /// 지역별 최근 목록 필터에 쓴다.
  ///
  /// 결과에서 고른 호선이 있으면 [stationId]/[line]을 함께 넘겨 최근 목록에
  /// 그 호선 마크만 보이게 한다. 검색어만 기록할 때는 호선 필드를 비운다.
  Future<void> recordSearch(
    String query, {
    String? region,
    String? stationId,
    StationSearchLine? line,
  });

  /// 경로 검색을 기록한다.
  Future<void> recordRouteSearch(RecentRouteSearchEntry entry) async {}

  Future<List<String>> listRecentQueries();

  /// 역·경로 최근 검색을 시간순으로 통합한 목록. [region]이 주어지면 해당 지역
  /// 항목만 남긴다(레거시 지역 null 역 항목은 제외).
  ///
  /// 기본 구현은 [listRecentQueries]를 역 항목으로 감싼다(지역 필터 없음). 실제
  /// 지역 필터와 경로 통합은 Drift·Demo 구현이 오버라이드한다.
  Future<List<RecentSearchEntry>> listRecentEntries({
    String? region,
    int limit = 10,
  }) async {
    final queries = await listRecentQueries();
    final now = DateTime.now();
    var offset = queries.length;
    return [
      for (final query in queries)
        RecentStationSearchEntry(
          query: query,
          region: null,
          searchedAt: now.subtract(Duration(microseconds: offset--)),
        ),
    ].take(limit).toList(growable: false);
  }

  /// 역 최근 검색 한 건을 지운다. [region]이 있으면 그 지역 행만, 없으면
  /// 같은 검색어의 모든 지역 행을 지운다.
  Future<void> removeSearch(String query, {String? region});

  /// 경로 최근 검색 한 건을 삭제한다(출발·경유·도착·지역 일치).
  Future<void> removeRouteSearch(RecentRouteSearchEntry entry) async {}

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

  /// [lineId]가 있으면 호선+역 단위로 저장. 없거나 빈 값이면 역 전체(레거시).
  Future<FavoriteStation> saveFavoriteStation(
    String stationId, {
    String? lineId,
  });

  /// [lineId]가 있으면 해당 호선만 해제. 없거나 빈 값이면 그 역 전체 해제.
  Future<void> removeFavoriteStation(String stationId, {String? lineId});
}

class FavoriteStationException implements Exception {
  const FavoriteStationException(this.message);

  final String message;

  @override
  String toString() => message;
}
