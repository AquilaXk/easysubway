import 'package:flutter/material.dart';

import '../../../facility_status.dart';
import '../../../mobile_error_reporter.dart';
import '../../realtime/realtime_repository.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';

const _favoriteStationStatusErrorMessage = '즐겨찾기를 확인하지 못했어요.';
const _favoriteStationChangeErrorMessage = '즐겨찾기를 바꾸지 못했어요.';

class StationLayoutSummaryItem {
  const StationLayoutSummaryItem({required this.icon, required this.text});

  final IconData icon;
  final String text;
}

extension StationFacilityLayoutPresentation on StationFacilityInfo {
  bool get isLayoutSummaryTarget {
    return switch (type) {
      'ELEVATOR' ||
      'WHEELCHAIR_LIFT' ||
      'RAMP' ||
      'ACCESSIBLE_TOILET' ||
      'NURSING_ROOM' ||
      'CUSTOMER_CENTER' ||
      'STATION_OFFICE' => true,
      _ => false,
    };
  }

  IconData get layoutSummaryIcon {
    return switch (type) {
      'ELEVATOR' => Icons.elevator,
      'WHEELCHAIR_LIFT' => Icons.accessible_forward,
      'RAMP' => Icons.accessible,
      'ACCESSIBLE_TOILET' => Icons.wc,
      'NURSING_ROOM' => Icons.child_care,
      'CUSTOMER_CENTER' || 'STATION_OFFICE' => Icons.support_agent,
      _ => Icons.place,
    };
  }

  int get layoutSummaryPriority {
    return switch (type) {
      'ELEVATOR' => 10,
      'WHEELCHAIR_LIFT' => 20,
      'RAMP' => 30,
      'ACCESSIBLE_TOILET' => 40,
      'NURSING_ROOM' => 50,
      'CUSTOMER_CENTER' || 'STATION_OFFICE' => 60,
      _ => 90,
    };
  }
}

enum StationDetailStatus { loading, success, failure }

class StationDetailState {
  const StationDetailState({
    required this.status,
    this.detail,
    this.exits = const [],
    this.facilities = const [],
    this.realtimeSnapshot = const RealtimeSnapshot.unavailable(),
    this.message = '',
  });

  const StationDetailState.loading()
    : status = StationDetailStatus.loading,
      detail = null,
      exits = const [],
      facilities = const [],
      realtimeSnapshot = const RealtimeSnapshot.unavailable(),
      message = '';

  final StationDetailStatus status;
  final StationDetail? detail;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;
  final RealtimeSnapshot realtimeSnapshot;
  final String message;

  List<StationFacilityInfo> get prioritizedFacilities {
    final sorted = List<StationFacilityInfo>.of(facilities);
    sorted.sort((left, right) {
      // 이동에 영향을 주는 시설 상태를 먼저 보여 사용자가 우회 여부를 빨리 판단하게 한다.
      final priority = left.statusPriority.compareTo(right.statusPriority);
      if (priority != 0) {
        return priority;
      }
      return left.name.compareTo(right.name);
    });
    return List.unmodifiable(sorted);
  }

  int get attentionFacilityCount {
    return facilities.where((facility) => facility.needsAttention).length;
  }

  String get facilityAttentionSummary {
    final count = attentionFacilityCount;
    if (count == 0) {
      return '';
    }
    return buildFacilityAttentionSummary(
      facilities.map((facility) => facility.status),
    );
  }

  String get facilityAttentionSemanticLabel {
    final count = attentionFacilityCount;
    if (count == 0) {
      return '다시 볼 시설이 없어요';
    }
    return buildFacilityAttentionSemanticLabel(
      facilities.map((facility) => facility.status),
    );
  }

  List<StationLayoutSummaryItem> get layoutSummaryItems {
    final items = <StationLayoutSummaryItem>[];
    // 역 전체 구조를 짧게 보여주기 위해 엘리베이터 연결 출구를 우선 시작점으로 삼는다.
    final accessibleExit = exits
        .where((exit) => exit.hasElevatorConnection)
        .firstOrNull;
    final firstExit = exits.isNotEmpty ? exits.first : null;
    final exit = accessibleExit ?? firstExit;
    if (exit != null) {
      items.add(
        StationLayoutSummaryItem(icon: Icons.exit_to_app, text: exit.name),
      );
    }

    for (final facility in _layoutSummaryFacilities()) {
      items.add(
        StationLayoutSummaryItem(
          icon: facility.layoutSummaryIcon,
          text: facility.typeLabel,
        ),
      );
    }

    if (items.isNotEmpty) {
      items.add(const StationLayoutSummaryItem(icon: Icons.train, text: '승강장'));
    }
    return List.unmodifiable(items);
  }

  String get layoutSummarySemanticLabel {
    final items = layoutSummaryItems;
    if (items.isEmpty) {
      return '역 안 이동 안내가 아직 없어요';
    }
    return '역 안 이동 안내, ${items.map((item) => item.text).join(', ')}';
  }

  List<StationFacilityInfo> _layoutSummaryFacilities() {
    final seenTypes = <String>{};
    final summaryFacilities = <StationFacilityInfo>[];
    final candidates = facilities
        .where((facility) => facility.isLayoutSummaryTarget)
        .toList();
    candidates.sort((left, right) {
      // 고장 여부보다 시설 유형 순서를 먼저 고정해 이동 흐름이 매번 같은 순서로 보이게 한다.
      final typePriority = left.layoutSummaryPriority.compareTo(
        right.layoutSummaryPriority,
      );
      if (typePriority != 0) {
        return typePriority;
      }
      final statusPriority = left.statusPriority.compareTo(
        right.statusPriority,
      );
      if (statusPriority != 0) {
        return statusPriority;
      }
      return left.name.compareTo(right.name);
    });

    for (final facility in candidates) {
      if (seenTypes.contains(facility.type)) {
        continue;
      }
      seenTypes.add(facility.type);
      summaryFacilities.add(facility);
      if (summaryFacilities.length == 3) {
        break;
      }
    }
    return summaryFacilities;
  }
}

class StationDetailController extends ChangeNotifier {
  StationDetailController({required this.repository, this.realtimeRepository});

  final StationSearchRepository repository;
  final RealtimeRepository? realtimeRepository;

  StationDetailState _state = const StationDetailState.loading();
  bool _isDisposed = false;

  StationDetailState get state => _state;

  Future<void> load(String stationId) async {
    _state = const StationDetailState.loading();
    notifyListeners();

    try {
      // 상세 화면은 요약, 출구, 시설을 함께 읽되 느린 네트워크에서 대기 시간이 합산되지 않게 병렬로 요청한다.
      final responses = await Future.wait<Object>([
        repository.getStationDetail(stationId),
        repository.listStationExits(stationId),
        repository.listStationFacilities(stationId),
      ]);
      if (_isDisposed) {
        return;
      }
      final detail = responses[0] as StationDetail;
      _state = StationDetailState(
        status: StationDetailStatus.success,
        detail: detail,
        exits: responses[1] as List<StationExitInfo>,
        facilities: responses[2] as List<StationFacilityInfo>,
        realtimeSnapshot: const RealtimeSnapshot.loading(),
      );
      notifyListeners();
      await _refreshRealtimeSnapshot(detail);
      return;
    } on StationSearchException {
      if (_isDisposed) {
        return;
      }
      _state = const StationDetailState(
        status: StationDetailStatus.failure,
        message: '역 안내를 불러오지 못했어요.',
      );
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 상세 화면 로드 중 예외가 발생했습니다.');
      if (_isDisposed) {
        return;
      }
      _state = const StationDetailState(
        status: StationDetailStatus.failure,
        message: '역 안내를 불러오지 못했어요.',
      );
    }

    notifyListeners();
  }

  // 실시간 조회가 실패로 끝났을 때 사용자가 직접 다시 시도할 수 있게 한다.
  // 현재 역 상세를 유지한 채 실시간만 로딩 상태로 되돌린 뒤 재조회한다.
  Future<void> retryRealtime() async {
    final detail = _state.detail;
    if (_isDisposed || detail == null) {
      return;
    }
    _state = StationDetailState(
      status: _state.status,
      detail: detail,
      exits: _state.exits,
      facilities: _state.facilities,
      realtimeSnapshot: const RealtimeSnapshot.loading(),
      message: _state.message,
    );
    notifyListeners();
    await _refreshRealtimeSnapshot(detail);
  }

  Future<void> _refreshRealtimeSnapshot(StationDetail detail) async {
    final realtimeSnapshot = await _loadRealtimeSnapshot(detail);
    if (_isDisposed || _state.detail?.id != detail.id) {
      return;
    }
    _state = StationDetailState(
      status: _state.status,
      detail: _state.detail,
      exits: _state.exits,
      facilities: _state.facilities,
      realtimeSnapshot: realtimeSnapshot,
      message: _state.message,
    );
    notifyListeners();
  }

  Future<RealtimeSnapshot> _loadRealtimeSnapshot(StationDetail detail) async {
    final repository = realtimeRepository;
    if (repository == null) {
      return const RealtimeSnapshot.unavailable();
    }
    final firstLine = detail.lines.isEmpty ? null : detail.lines.first;
    if (firstLine == null) {
      return const RealtimeSnapshot(
        status: RealtimeSnapshotStatus.unsupported,
        fallbackCode: 'LINE_MAPPING_MISSING',
        message: '이 노선은 아직 실시간 열차 안내가 어려워요.',
        receivedAt: '',
        arrivals: [],
      );
    }
    try {
      return await repository.arrivals(
        RealtimeStationQuery(
          stationId: detail.id,
          lineId: firstLine.id,
          providerLineId: firstLine.stationCode.isEmpty
              ? firstLine.id
              : firstLine.stationCode,
          stationQueryName: detail.nameKo,
        ),
      );
    } on RealtimeException catch (error) {
      return RealtimeSnapshot(
        status: RealtimeSnapshotStatus.unavailable,
        fallbackCode: 'PROVIDER_ERROR',
        message: '${error.message} 역 정보와 경로 검색은 계속 이용할 수 있습니다.',
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 상세 실시간 열차 조회 중 예외가 발생했습니다.',
      );
      return const RealtimeSnapshot.unavailable();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

enum StationFavoriteToggleStatus { checking, ready, saving, removing, failure }

class StationFavoriteToggleState {
  const StationFavoriteToggleState({
    required this.status,
    required this.isFavorite,
    this.message = '',
  });

  const StationFavoriteToggleState.ready({required this.isFavorite})
    : status = StationFavoriteToggleStatus.ready,
      message = '';

  const StationFavoriteToggleState.checking({required this.isFavorite})
    : status = StationFavoriteToggleStatus.checking,
      message = '';

  final StationFavoriteToggleStatus status;
  final bool isFavorite;
  final String message;

  bool get isBusy {
    return status == StationFavoriteToggleStatus.checking ||
        status == StationFavoriteToggleStatus.saving ||
        status == StationFavoriteToggleStatus.removing;
  }

  bool get isChanging {
    return status == StationFavoriteToggleStatus.saving ||
        status == StationFavoriteToggleStatus.removing;
  }
}

class StationFavoriteToggleController extends ChangeNotifier {
  StationFavoriteToggleController({
    required this.repository,
    required this.stationId,
    bool initiallyFavorite = false,
    bool initiallyChecking = false,
  }) : _state = initiallyChecking
           ? StationFavoriteToggleState.checking(isFavorite: initiallyFavorite)
           : StationFavoriteToggleState.ready(isFavorite: initiallyFavorite);

  final FavoriteStationRepository repository;
  final String stationId;

  StationFavoriteToggleState _state;
  bool _isDisposed = false;

  StationFavoriteToggleState get state => _state;

  Future<void> load() async {
    if (_state.isChanging) {
      return;
    }

    _emitState(
      StationFavoriteToggleState.checking(isFavorite: _state.isFavorite),
    );

    try {
      final favorites = await repository.listFavoriteStations();
      final isFavorite = favorites.any(
        (favorite) => favorite.stationId == stationId,
      );
      _emitState(StationFavoriteToggleState.ready(isFavorite: isFavorite));
    } on FavoriteStationException catch (error) {
      _emitFailure(error.message);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 즐겨찾기 상태 확인 중 예외가 발생했습니다.',
      );
      _emitFailure(_favoriteStationStatusErrorMessage);
    }
  }

  Future<void> save() async {
    if (_state.isBusy) {
      return;
    }

    _emitState(
      StationFavoriteToggleState(
        status: StationFavoriteToggleStatus.saving,
        isFavorite: _state.isFavorite,
      ),
    );

    try {
      await repository.saveFavoriteStation(stationId);
      _emitState(
        const StationFavoriteToggleState(
          status: StationFavoriteToggleStatus.ready,
          isFavorite: true,
          message: '즐겨찾기에 저장했습니다.',
        ),
      );
    } on FavoriteStationException catch (error) {
      _emitFailure(error.message);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 즐겨찾기 저장 중 예외가 발생했습니다.');
      _emitFailure(_favoriteStationChangeErrorMessage);
    }
  }

  Future<void> remove() async {
    if (_state.isBusy) {
      return;
    }

    _emitState(
      StationFavoriteToggleState(
        status: StationFavoriteToggleStatus.removing,
        isFavorite: _state.isFavorite,
      ),
    );

    try {
      await repository.removeFavoriteStation(stationId);
      _emitState(
        const StationFavoriteToggleState(
          status: StationFavoriteToggleStatus.ready,
          isFavorite: false,
          message: '즐겨찾기에서 해제했습니다.',
        ),
      );
    } on FavoriteStationException catch (error) {
      _emitFailure(error.message);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 즐겨찾기 해제 중 예외가 발생했습니다.');
      _emitFailure(_favoriteStationChangeErrorMessage);
    }
  }

  void _emitFailure(String message) {
    _emitState(
      StationFavoriteToggleState(
        status: StationFavoriteToggleStatus.failure,
        isFavorite: _state.isFavorite,
        message: message,
      ),
    );
  }

  void _emitState(StationFavoriteToggleState nextState) {
    if (_isDisposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
