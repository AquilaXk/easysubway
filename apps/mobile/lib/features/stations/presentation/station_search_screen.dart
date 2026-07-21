import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../adaptive_layout.dart';
import '../../../facility_report.dart';
import '../../../internal_route.dart';
import '../../../mobile_error_reporter.dart';
import '../../../search_field.dart';
import '../../ads/ad_repository.dart';
import '../../network_map/presentation/region_menu.dart';
import '../../realtime/realtime_repository.dart';
import '../../route_draft/application/route_draft_controller.dart';
import '../../route_draft/domain/route_draft.dart';
import '../application/station_search_controller.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'station_recent_search_section.dart';
import 'station_search_body.dart';

const _searchHistoryChangeErrorMessage = '최근 검색을 지우지 못했어요.';
const _stationSearchPagePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);
const _stationSearchLargePagePadding = EdgeInsets.fromLTRB(24, 24, 24, 40);

/// 홈 노선도 지역 메뉴와 같은 기본 목록. 호출부가 regions를 안 넘기면 쓴다.
/// 호출부(홈)가 맵에만 있는 지역을 이 기본 목록에 병합할 때도 재사용한다
/// (#2419 리뷰 finding — 검색 메뉴가 맵 지역을 무시하던 문제).
const defaultStationSearchRegions = <EasySubwayRegionMenuItem>[
  EasySubwayRegionMenuItem(id: '수도권', label: '수도권'),
  EasySubwayRegionMenuItem(id: '광주', label: '광주'),
  EasySubwayRegionMenuItem(id: '대구', label: '대구'),
  EasySubwayRegionMenuItem(id: '대전', label: '대전'),
  EasySubwayRegionMenuItem(id: '부산', label: '부산'),
];

class StationSearchScreen extends StatefulWidget {
  const StationSearchScreen({
    required this.repository,
    required this.reportRepository,
    this.favoriteRepository,
    this.adRepository,
    this.searchHistoryRepository,
    this.realtimeRepository,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    this.pickSlot,
    required this.regionLabel,
    this.onRegionChanged,
    this.regions = defaultStationSearchRegions,
    this.bottomNavigationBar,
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final AdRepository? adRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final RealtimeRepository? realtimeRepository;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;

  /// 특정 칸(출발/도착)을 채우려고 검색을 연 경우의 대상 칸. 지정되면 결과를 한 번
  /// 탭하는 즉시 [routeDraftController]의 해당 칸을 설정하고 이 화면을 닫는다. 지도
  /// 탭 경로와 완전히 같은 draft 상태로 수렴시키기 위한 "칸 채우기" 모드다. null이면
  /// 기존 둘러보기(출발/도착 버튼이 각 결과에 딸린 형태) 그대로 동작한다.
  final RouteDraftSlot? pickSlot;

  /// 검색 화면 상단 우측 지역 트리거의 초기 표시명. 홈 노선도와 같은 지역을
  /// 쓰며, 여기서 바꾸면 결과 필터와 함께 [onRegionChanged]로 홈 노선도 지역도
  /// 맞춘다.
  final String regionLabel;

  /// 지역 메뉴에서 고른 원본 지역 키(예: `부산`, `부산권`). 홈 노선도 동기화용.
  final ValueChanged<String>? onRegionChanged;

  /// 지역 메뉴 항목. 비우면 [defaultStationSearchRegions]를 쓴다.
  final List<EasySubwayRegionMenuItem> regions;
  final Widget? bottomNavigationBar;

  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

class _StationSearchScreenState extends State<StationSearchScreen> {
  late final StationSearchController _controller;
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<RecentSearchEntry> _recentEntries = const [];
  Timer? _searchDebounce;
  late String _regionLabel;

  @override
  void initState() {
    super.initState();
    _regionLabel = widget.regionLabel;
    _controller = StationSearchController(
      repository: widget.repository,
      searchHistoryRepository: widget.searchHistoryRepository,
    );
    _controller.addListener(_handleControllerChanged);
    _queryController.addListener(_handleQueryChanged);
    unawaited(_loadRecentEntries());
    // 검색 진입은 화면을 여는 즉시 입력 모드로 들어간다. autofocus가 담당한다.
  }

  @override
  void didUpdateWidget(covariant StationSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.regionLabel == widget.regionLabel) {
      return;
    }
    if (widget.regionLabel == _regionLabel) {
      return;
    }
    setState(() => _regionLabel = widget.regionLabel);
    unawaited(_loadRecentEntries());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    _queryController.removeListener(_handleQueryChanged);
    _queryController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleQueryChanged() {
    if (!mounted) {
      return;
    }
    _searchDebounce?.cancel();
    if (!_hasSearchQuery) {
      if (_controller.state.status != StationSearchStatus.idle) {
        _controller.search('');
      }
    } else {
      // 타이핑 즉시(디바운스) 검색으로 통일한다. 부분 입력은 최근 검색에 기록하지 않는다.
      final query = _queryController.text;
      _searchDebounce = Timer(
        const Duration(milliseconds: 300),
        () => unawaited(_runSearch(query, recordHistory: false)),
      );
    }
    setState(() {});
  }

  bool get _hasSearchQuery => _queryController.text.trim().isNotEmpty;

  /// pickSlot 조합에 따른 입력 힌트. 큰 타이틀 화면을 없앤 대신, 입력 필드 자체의
  /// 힌트/시맨틱에 "무엇을 고르는 중인지"를 인코딩해 TalkBack이 출발/도착/일반
  /// 검색 의도를 그대로 전달하게 한다.
  String get _searchInputHint => switch (widget.pickSlot) {
    // #2083 오너 확정: 슬롯 검색 진입 placeholder는 슬롯명 단독.
    RouteDraftSlot.origin => '출발역',
    RouteDraftSlot.destination => '도착역',
    RouteDraftSlot.waypoint => '경유역',
    null => '역 이름을 입력해 주세요',
  };

  @override
  Widget build(BuildContext context) {
    // #2083 홈 편집 모드와 동일한 공용 검색 필드를 쓴다. pickSlot별 힌트는
    // hintText로 전달돼 placeholder이자 TalkBack 라벨 역할을 유지하고, 즉시
    // (디바운스) 검색은 _queryController를, 지우기는 onClear를 통해 보존된다.
    // AppBar leading(자동 뒤로가기)은 title 왼쪽에 그대로 남아 "← + 46px 필드"
    // 구성이 홈 편집 모드와 일치한다.
    final searchInputField = EasySubwaySearchField(
      controller: _queryController,
      focusNode: _searchFocusNode,
      hintText: _searchInputHint,
      // #2090: hint는 입력이 있으면 InputDecorator가 지워 "출발/도착/경유역 이름을
      // 입력해 주세요" 슬롯 맥락이 입력 후 스크린리더에서 소실된다. floating label
      // 회귀(#1933) 없이 맥락을 유지하도록 동일 문구를 semantics 라벨로 전달해
      // 필드를 감싼다. 홈 검색은 이 파라미터를 쓰지 않아 라벨 이중 낭독이 없다.
      semanticsLabel: _searchInputHint,
      autofocus: true,
      onSubmitted: _submit,
      onClear: _queryController.clear,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final scaledFieldHeight = math.max(
      EasySubwayTouchTarget.general,
      scaler.scale(EasySubwayTouchTarget.general),
    );
    // 기본 배율은 홈 노선도와 동일한 60. 글자 배율이 커져 필드+상하 패딩(6+6)이
    // 60을 넘을 때만 키워 #2090 잘림을 막는다.
    final topBarHeight = scaledFieldHeight <= EasySubwayTouchTarget.general
        ? easySubwayTopBarContentHeight
        : math.max(easySubwayTopBarContentHeight, scaledFieldHeight + 12);
    final recentSearchSection = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isSearching =
            _controller.state.status == StationSearchStatus.loading;
        if (_hasSearchQuery) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StationRecentSearchSection(
            entries: _recentEntries,
            enabled: !isSearching,
            onStationSelected: _searchRecentEntry,
            onRouteSelected: _selectRecentRoute,
            onRemove: (entry) => unawaited(_removeRecentEntry(entry)),
            onClearAll: () => unawaited(_clearAllRecentEntries()),
          ),
        );
      },
    );
    final isPicking = widget.pickSlot != null;
    final resultSection = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return StationSearchBody(
          state: _controller.state,
          // 칸 채우기 모드에서는 결과 한 번 탭 = 해당 칸 설정 후 닫기. 지도 탭과 동일
          // 하게 "출발역 선택 → 도착역 선택" UX로 수렴시킨다. 둘러보기 모드에서는
          // 선택한 역을 지도로 반환한다.
          onResultTap: isPicking ? _pickStation : _returnStationToMap,
        );
      },
    );
    // 홈 `_NetworkMapTopBar`와 동일 골격(Material + SafeArea + 고정/배율 높이 +
    // Positioned 구분선). AppBar toolbar 슬롯을 쓰지 않아 콘텐츠 높이·구분선
    // Y·그림자가 홈과 픽셀 단위로 맞는다. 왼쪽만 메뉴→뒤로 아이콘이 다르다.
    final topPadding = MediaQuery.paddingOf(context).top;
    return Scaffold(
      key: const Key('stationSearchScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(topPadding + topBarHeight),
        child: Material(
          key: const Key('stationSearchAppBar'),
          color: EasySubwayAccessibleColors.topBarSurface,
          elevation: 0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SafeArea(
                bottom: false,
                child: SizedBox(
                  key: const Key('stationSearchTopBarContent'),
                  height: topBarHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('stationSearchBackButton'),
                          tooltip: '뒤로',
                          onPressed: () => Navigator.of(context).maybePop(),
                          style: IconButton.styleFrom(
                            minimumSize: const Size.square(
                              EasySubwayTouchTarget.general,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.zero,
                          ),
                          icon: const Icon(
                            Icons.arrow_back,
                            size: 26,
                            color: Color(0xFF4B4B4B),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(child: searchInputField),
                        const SizedBox(width: 8),
                        ListenableBuilder(
                          listenable:
                              widget.routeDraftController ??
                              const _NullListenable(),
                          builder: (context, _) {
                            final regionLocked = _isRegionLocked;
                            return _StationSearchRegionSelector(
                              regionLabel: _regionLabel,
                              regions: widget.regions.isEmpty
                                  ? defaultStationSearchRegions
                                  : widget.regions,
                              canChangeRegion: !regionLocked,
                              onRegionSelected: _onRegionSelected,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: EasySubwayHeaderDivider(
                  key: Key('stationSearchHeaderDivider'),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: widget.bottomNavigationBar,
      body: Semantics(
        container: true,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isLargeScreen = EasySubwayAdaptiveLayout.isLargeScreen(
                constraints,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
              );
              return ListView(
                padding: isLargeScreen
                    ? _stationSearchLargePagePadding
                    : _stationSearchPagePadding,
                children: [
                  _StationSearchAdaptiveContent(
                    isLargeScreen: isLargeScreen,
                    recentSearchSection: recentSearchSection,
                    resultSection: resultSection,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _submit(String query) {
    // 키보드 검색 액션 등 명시적 검색: 디바운스를 취소하고 최근 검색에 기록한다.
    _searchDebounce?.cancel();
    if (_controller.state.status == StationSearchStatus.loading) {
      return;
    }
    unawaited(_runSearch(query));
  }

  Future<void> _runSearch(String query, {bool recordHistory = true}) async {
    await _controller.search(
      query,
      region: _regionLabel,
      recordHistory: recordHistory,
    );
    // 최근 검색 목록은 기록한 경우에만 바뀌므로, 디바운스 타이핑 검색에서는
    // 불필요한 재조회를 하지 않는다.
    if (recordHistory) {
      await _loadRecentEntries();
    }
  }

  /// 출발·도착·경유 중 하나라도 채워지면 지역을 바꿀 수 없다(경로 지역 고정).
  bool get _isRegionLocked {
    final draft = widget.routeDraftController?.draft;
    return draft != null && !draft.isEmpty;
  }

  void _onRegionSelected(String regionId) {
    if (_isRegionLocked) {
      return;
    }
    final regions = widget.regions.isEmpty
        ? defaultStationSearchRegions
        : widget.regions;
    EasySubwayRegionMenuItem? match;
    for (final item in regions) {
      if (item.id == regionId || item.label == regionId) {
        match = item;
        break;
      }
    }
    final nextLabel = match?.label ?? normalizeStationRegion(regionId);
    if (nextLabel == _regionLabel) {
      return;
    }
    setState(() => _regionLabel = nextLabel);
    // 홈 노선도 지역도 같은 키로 맞춘다(메뉴 id — 저장형 `부산권` 또는 `부산`).
    widget.onRegionChanged?.call(match?.id ?? regionId);
    if (_hasSearchQuery) {
      unawaited(_runSearch(_queryController.text, recordHistory: false));
    } else {
      // 검색어가 없을 때는 목록이 새 지역 기준으로 다시 필터돼야 한다.
      unawaited(_loadRecentEntries());
    }
  }

  void _searchRecentEntry(RecentStationSearchEntry entry) {
    final query = entry.query;
    _queryController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _submit(query);
  }

  /// 최근 경로 항목을 탭하면 draft에 출발·경유·도착을 채우고 화면을 닫는다.
  /// 홈이 draft 변화를 감지해 자동으로 경로 결과 탭으로 전환한다.
  void _selectRecentRoute(RecentRouteSearchEntry entry) {
    final controller = widget.routeDraftController;
    if (controller == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('경로를 다시 찾을 수 없어요.')));
      }
      return;
    }
    controller.clear();
    controller.setOrigin(
      RouteDraftStation(
        id: entry.originStationId,
        nameKo: entry.originStationName,
      ),
    );
    controller.setDestination(
      RouteDraftStation(
        id: entry.destinationStationId,
        nameKo: entry.destinationStationName,
      ),
    );
    final waypointId = entry.waypointStationId;
    final waypointName = entry.waypointStationName;
    if (waypointId != null &&
        waypointId.isNotEmpty &&
        waypointName != null &&
        waypointName.isNotEmpty) {
      controller.setWaypoint(
        RouteDraftStation(id: waypointId, nameKo: waypointName),
      );
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _removeRecentEntry(RecentSearchEntry entry) async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      switch (entry) {
        case RecentStationSearchEntry():
          await repository.removeSearch(entry.query, region: entry.region);
        case RecentRouteSearchEntry():
          await repository.removeRouteSearch(entry);
      }
      await _loadRecentEntries();
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색 삭제 중 예외가 발생했습니다.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_searchHistoryChangeErrorMessage)),
        );
      }
    }
  }

  Future<void> _clearAllRecentEntries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    final confirmed = await confirmClearRecentSearches(context);
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      final entries = await repository.listRecentEntries(
        region: _regionLabel,
        limit: 50,
      );
      for (final entry in entries) {
        switch (entry) {
          case RecentStationSearchEntry():
            await repository.removeSearch(entry.query, region: entry.region);
          case RecentRouteSearchEntry():
            await repository.removeRouteSearch(entry);
        }
      }
      await _loadRecentEntries();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '최근 검색 전체 삭제 중 예외가 발생했습니다.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_searchHistoryChangeErrorMessage)),
        );
      }
    }
  }

  Future<void> _loadRecentEntries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      final entries = await repository.listRecentEntries(region: _regionLabel);
      if (!mounted) {
        return;
      }
      setState(() => _recentEntries = entries);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색 조회 중 예외가 발생했습니다.');
    }
  }

  /// 칸 채우기 모드: 결과를 탭하면 지정된 칸을 [routeDraftController]에 설정하고
  /// 화면을 닫으면서 선택한 역을 반환한다. 지도 탭 경로와 같은 컨트롤러·같은 draft로
  /// 수렴한다.
  void _pickStation(StationSearchResult result) {
    final slot = widget.pickSlot;
    if (slot == null) {
      return;
    }
    final station = RouteDraftStation(id: result.id, nameKo: result.nameKo);
    switch (slot) {
      case RouteDraftSlot.origin:
        widget.routeDraftController?.setOrigin(station);
      case RouteDraftSlot.destination:
        widget.routeDraftController?.setDestination(station);
      case RouteDraftSlot.waypoint:
        widget.routeDraftController?.setWaypoint(station);
    }
    Navigator.of(context).pop(station);
  }

  /// #2109 둘러보기(비픽) 모드: 결과를 탭하면 상세를 밀지 않고 선택한 역 결과를
  /// 반환하며 화면을 닫는다. 호출부(main.dart openStationSearch)가 이 결과를
  /// 받아 노선도 focus + 팬 메뉴 + 해당 역 하단 패널을 트리거한다(임베디드
  /// 검색과 동일한 흐름으로 수렴).
  void _returnStationToMap(StationSearchResult result) {
    Navigator.of(context).pop(result);
  }
}

/// 검색 화면 상단 필드 우측 지역 선택기. 홈과 같은 위치·스타일이지만, 선택은
/// 노선도 전환이 아니라 **검색 결과 지역 필터**에만 쓰인다.
/// [canChangeRegion]이 false면 표시만 하고 ▾·메뉴를 막는다.
class _StationSearchRegionSelector extends StatelessWidget {
  const _StationSearchRegionSelector({
    required this.regionLabel,
    required this.regions,
    required this.onRegionSelected,
    this.canChangeRegion = true,
  });

  final String regionLabel;
  final List<EasySubwayRegionMenuItem> regions;
  final ValueChanged<String> onRegionSelected;
  final bool canChangeRegion;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (triggerContext) => Semantics(
        key: const Key('stationSearchRegionIndicator'),
        container: true,
        button: canChangeRegion,
        label: canChangeRegion ? '지역: $regionLabel, 지역 변경' : '지역: $regionLabel',
        onTap: canChangeRegion ? () => _openMenu(triggerContext) : null,
        child: ExcludeSemantics(
          child: InkWell(
            key: const Key('stationSearchRegionDropdown'),
            onTap: canChangeRegion ? () => _openMenu(triggerContext) : null,
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 148),
              child: SizedBox(
                height: EasySubwayTouchTarget.general,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        regionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF606060),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (canChangeRegion) ...[
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF606060),
                        size: 22,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(BuildContext triggerContext) {
    return showEasySubwayRegionMenu(
      triggerContext: triggerContext,
      regions: regions,
      selectedRegion: regionLabel,
      onRegionSelected: onRegionSelected,
    );
  }
}

/// [ListenableBuilder]에 null 컨트롤러를 넘길 때 쓰는 빈 리스너.
class _NullListenable extends Listenable {
  const _NullListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class _StationSearchAdaptiveContent extends StatelessWidget {
  const _StationSearchAdaptiveContent({
    required this.isLargeScreen,
    required this.recentSearchSection,
    required this.resultSection,
  });

  final bool isLargeScreen;
  final Widget recentSearchSection;
  final Widget resultSection;

  @override
  Widget build(BuildContext context) {
    if (!isLargeScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [recentSearchSection, resultSection],
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: EasySubwayAdaptiveLayout.largeScreenMaxContentWidth,
        ),
        child: Row(
          key: const Key('stationSearchLargeScreenLayout'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [resultSection],
              ),
            ),
            const SizedBox(
              width: EasySubwayAdaptiveLayout.largeScreenColumnGap,
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [recentSearchSection],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
