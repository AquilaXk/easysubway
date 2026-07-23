import 'package:flutter/foundation.dart';

import '../../../mobile_error_reporter.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';

const _currentLocationPermissionMessage = '현재 위치를 사용할 수 없어요.';

enum StationSearchStatus { idle, loading, success, empty, failure }

enum StationSearchResultSource { search, nearby }

class StationSearchState {
  const StationSearchState({
    required this.status,
    required this.results,
    this.message = '',
    this.source = StationSearchResultSource.search,
  });

  const StationSearchState.idle()
    : status = StationSearchStatus.idle,
      results = const [],
      message = '',
      source = StationSearchResultSource.search;

  final StationSearchStatus status;
  final List<StationSearchResult> results;
  final String message;
  final StationSearchResultSource source;
}

class StationSearchController extends ChangeNotifier {
  StationSearchController({
    required this.repository,
    this.searchHistoryRepository,
  });

  final StationSearchRepository repository;
  final SearchHistoryRepository? searchHistoryRepository;

  StationSearchState _state = const StationSearchState.idle();
  int _searchRequestId = 0;
  bool _isDisposed = false;

  StationSearchState get state => _state;

  /// 한글 조합 중·검색 대기 UI. 성공 결과가 있으면 유지하고, empty/idle이면
  /// loading으로 바꿔 "검색 결과가 없습니다" 깜빡임을 막는다.
  void showPendingSearch() {
    if (_isDisposed) {
      return;
    }
    if (_state.source == StationSearchResultSource.search &&
        _state.results.isNotEmpty &&
        (_state.status == StationSearchStatus.success ||
            _state.status == StationSearchStatus.loading)) {
      return;
    }
    if (_state.status == StationSearchStatus.loading) {
      return;
    }
    _state = const StationSearchState(
      status: StationSearchStatus.loading,
      results: [],
    );
    notifyListeners();
  }

  Future<void> search(
    String query, {
    String? lineId,
    String? region,
    String? recordRegion,
    bool recordHistory = true,
  }) async {
    final requestId = ++_searchRequestId;
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      _state = const StationSearchState.idle();
      _notifyIfActive(requestId);
      return;
    }

    // 타이핑 재검색: 이전 검색 결과를 비우지 않는다. 스피너로 갈아끼우면
    // 글자마다 목록이 깜빡인다. 첫 검색(결과 없음)만 loading을 노출한다.
    // empty 상태에서 다음 글자를 칠 때도 empty를 유지하지 않고 loading으로 간다.
    final keepPreviousResults =
        _state.source == StationSearchResultSource.search &&
        _state.results.isNotEmpty &&
        (_state.status == StationSearchStatus.success ||
            _state.status == StationSearchStatus.loading);
    if (!keepPreviousResults) {
      _state = const StationSearchState(
        status: StationSearchStatus.loading,
        results: [],
      );
      _notifyIfActive(requestId);
    }

    try {
      final selectedLineId = lineId?.trim();
      final results =
          selectedLineId != null &&
              selectedLineId.isNotEmpty &&
              repository is StationLineFilterRepository
          ? await (repository as StationLineFilterRepository)
                .searchStationsOnLine(trimmedQuery, selectedLineId)
          : await repository.searchStations(trimmedQuery);
      if (!_isActiveRequest(requestId)) {
        return;
      }
      // 지역이 주어지면 해당 지역 역만 남긴다(홈 노선도·풀페이지 검색 공통).
      final filtered = _filterByRegion(results, region);
      // 디바운스 타이핑은 기록하지 않는다. 명시적 검색은 현재 지역에 실제
      // 결과가 있을 때만 기록해 타 지역 역이 잘못된 지역 이력으로 남지 않게 한다.
      if (recordHistory && filtered.isNotEmpty) {
        await _recordSearch(trimmedQuery, recordRegion ?? region);
      }
      if (filtered.isEmpty) {
        _state = const StationSearchState(
          status: StationSearchStatus.empty,
          results: [],
          message: '검색 결과가 없습니다.',
        );
      } else {
        _state = StationSearchState(
          status: StationSearchStatus.success,
          results: filtered,
          source: StationSearchResultSource.search,
        );
      }
    } on StationSearchException catch (error) {
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = StationSearchState(
        status: StationSearchStatus.failure,
        results: const [],
        message: error.message,
      );
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 검색 화면 처리 중 예외가 발생했습니다.');
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = const StationSearchState(
        status: StationSearchStatus.failure,
        results: [],
        message: '역 정보를 불러오지 못했어요.',
      );
    }
    _notifyIfActive(requestId);
  }

  Future<void> _recordSearch(String query, String? region) async {
    final repository = searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.recordSearch(query, region: region);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색어 저장 중 예외가 발생했습니다.');
    }
  }

  Future<void> searchNearby(CurrentLocationProvider locationProvider) async {
    final requestId = ++_searchRequestId;
    _state = const StationSearchState(
      status: StationSearchStatus.loading,
      results: [],
    );
    _notifyIfActive(requestId);

    try {
      final location = await locationProvider.currentLocation();
      final blockedMessage = location.nearbySearchBlockedMessage();
      if (blockedMessage != null) {
        if (!_isActiveRequest(requestId)) {
          return;
        }
        _state = StationSearchState(
          status: StationSearchStatus.failure,
          results: const [],
          message: blockedMessage,
        );
        _notifyIfActive(requestId);
        return;
      }
      final results = await repository.searchNearbyStations(location);
      if (!_isActiveRequest(requestId)) {
        return;
      }
      if (results.isEmpty) {
        _state = const StationSearchState(
          status: StationSearchStatus.empty,
          results: [],
          message: '주변 역을 찾지 못했어요.',
        );
      } else {
        _state = StationSearchState(
          status: StationSearchStatus.success,
          results: results,
          source: StationSearchResultSource.nearby,
        );
      }
    } on CurrentLocationException catch (error) {
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = StationSearchState(
        status: StationSearchStatus.failure,
        results: const [],
        message: _friendlyCurrentLocationErrorMessage(error.message),
      );
    } on StationSearchException catch (error) {
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = StationSearchState(
        status: StationSearchStatus.failure,
        results: const [],
        message: error.message,
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '주변 역 검색 화면 처리 중 예외가 발생했습니다.',
      );
      if (!_isActiveRequest(requestId)) {
        return;
      }
      _state = const StationSearchState(
        status: StationSearchStatus.failure,
        results: [],
        message: '역 정보를 불러오지 못했어요.',
      );
    }
    _notifyIfActive(requestId);
  }

  List<StationSearchResult> _filterByRegion(
    List<StationSearchResult> results,
    String? region,
  ) {
    final trimmed = region?.trim() ?? '';
    if (trimmed.isEmpty) {
      return results;
    }
    return results
        .where((result) => stationBelongsToRegion(result.region, trimmed))
        .toList(growable: false);
  }

  bool _isActiveRequest(int requestId) {
    return !_isDisposed && requestId == _searchRequestId;
  }

  void _notifyIfActive(int requestId) {
    if (_isActiveRequest(requestId)) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _searchRequestId++;
    super.dispose();
  }
}

String _friendlyCurrentLocationErrorMessage(String message) {
  if (message.contains('권한')) {
    return _currentLocationPermissionMessage;
  }
  return message.isEmpty ? '현재 위치를 확인하지 못했어요.' : message;
}
