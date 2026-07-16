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

  Future<void> search(
    String query, {
    String? lineId,
    bool recordHistory = true,
  }) async {
    final requestId = ++_searchRequestId;
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      _state = const StationSearchState.idle();
      _notifyIfActive(requestId);
      return;
    }

    _state = const StationSearchState(
      status: StationSearchStatus.loading,
      results: [],
    );
    _notifyIfActive(requestId);

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
      // 디바운스 타이핑 검색은 최근 검색에 기록하지 않는다(부분 입력 기록 방지).
      // 키보드 검색·최근 검색 선택 등 명시적 검색만 기록한다.
      if (recordHistory) {
        await _recordSearch(trimmedQuery);
      }
      if (results.isEmpty) {
        _state = const StationSearchState(
          status: StationSearchStatus.empty,
          results: [],
          message: '검색 결과가 없습니다.',
        );
      } else {
        _state = StationSearchState(
          status: StationSearchStatus.success,
          results: results,
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

  Future<void> _recordSearch(String query) async {
    final repository = searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.recordSearch(query);
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
