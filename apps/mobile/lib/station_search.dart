import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'accessible_design.dart';
import 'adaptive_layout.dart';
import 'core/external/kakao_map_launcher.dart';
import 'facility_report.dart';
import 'features/ads/active_ad_banner.dart';
import 'features/ads/ad_repository.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'features/realtime/realtime_repository.dart';
import 'features/stations/application/station_detail_controller.dart';
import 'features/stations/application/station_search_controller.dart';
import 'features/stations/domain/station_line.dart';
import 'features/stations/domain/station_models.dart';
import 'features/stations/domain/station_repositories.dart';
import 'features/stations/presentation/station_detail_header.dart';
import 'features/stations/presentation/station_detail_route_actions.dart';
import 'features/stations/presentation/station_exit_card.dart';
import 'features/stations/presentation/station_facility_card.dart';
import 'features/stations/presentation/station_facility_status_summary.dart';
import 'features/stations/presentation/station_info_basis_disclosure.dart';
import 'features/stations/presentation/station_internal_route_guidance.dart';
import 'features/stations/presentation/station_layout_summary.dart';
import 'features/stations/presentation/station_recent_search_section.dart';
import 'features/stations/presentation/station_realtime_summary.dart';
import 'features/stations/presentation/station_search_body.dart';
import 'features/stations/presentation/station_timetable_screen.dart';
import 'internal_route.dart';
import 'mobile_error_reporter.dart';
import 'search_field.dart';

export 'features/stations/application/station_detail_controller.dart';
export 'features/stations/application/station_search_controller.dart';
export 'features/stations/data/current_location_provider.dart';
export 'features/stations/domain/station_line.dart';
export 'features/stations/domain/station_models.dart';
export 'features/stations/domain/station_repositories.dart';
export 'features/stations/presentation/station_recent_search_section.dart';
export 'features/stations/presentation/station_search_body.dart';
export 'features/stations/presentation/station_timetable_screen.dart';

const _searchHistoryChangeErrorMessage = '최근 검색을 지우지 못했어요.';
const _stationSearchPagePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);
const _stationSearchLargePagePadding = EdgeInsets.fromLTRB(24, 24, 24, 40);

class StationSearchScreen extends StatefulWidget {
  const StationSearchScreen({
    required this.repository,
    required this.reportRepository,
    required this.locationProvider,
    this.favoriteRepository,
    this.adRepository,
    this.searchHistoryRepository,
    this.realtimeRepository,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    this.entryMode = StationSearchEntryMode.search,
    this.pickSlot,
    required this.regionLabel,
    this.bottomNavigationBar,
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider locationProvider;
  final FavoriteStationRepository? favoriteRepository;
  final AdRepository? adRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final RealtimeRepository? realtimeRepository;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;
  final StationSearchEntryMode entryMode;

  /// 특정 칸(출발/도착)을 채우려고 검색을 연 경우의 대상 칸. 지정되면 결과를 한 번
  /// 탭하는 즉시 [routeDraftController]의 해당 칸을 설정하고 이 화면을 닫는다. 지도
  /// 탭 경로와 완전히 같은 draft 상태로 수렴시키기 위한 "칸 채우기" 모드다. null이면
  /// 기존 둘러보기(출발/도착 버튼이 각 결과에 딸린 형태) 그대로 동작한다.
  final RouteDraftSlot? pickSlot;

  /// #2082: 검색 화면 상단 필드 우측에 표시하는 현재 지역명. 홈 idle 상단바
  /// [≡ | 검색필드 | 지역표시] 구성과 정합하기 위해, 검색 화면(← + 필드)에도
  /// 같은 위치·스타일의 지역 표시를 둔다. 검색 맥락에서는 지역 변경 UI를 새로
  /// 만들지 않고 표시 전용으로 둔다(오너 지시: "변경은 못해도 알려는 줘야"). 호출부가
  /// 홈이 들고 있는 실제 선택 지역 표시명을 반드시 넘겨야 한다(#2090 배선 누락 수정).
  final String regionLabel;
  final Widget? bottomNavigationBar;

  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

enum StationSearchEntryMode { search, nearby }

class _StationSearchScreenState extends State<StationSearchScreen> {
  late final StationSearchController _controller;
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<String> _recentQueries = const [];
  Timer? _searchDebounce;
  bool _isNearbySearchRunning = false;
  bool _isOpeningLocationSettings = false;

  @override
  void initState() {
    super.initState();
    _controller = StationSearchController(
      repository: widget.repository,
      searchHistoryRepository: widget.searchHistoryRepository,
    );
    _controller.addListener(_handleControllerChanged);
    _queryController.addListener(_handleQueryChanged);
    unawaited(_loadRecentQueries());
    if (widget.entryMode == StationSearchEntryMode.nearby) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_searchNearby());
        }
      });
    }
    // 검색 진입은 화면을 여는 즉시 입력 모드로 들어간다(별도 타이틀 화면 없이 바로
    // 키보드가 뜬다). 이 즉시 포커스는 검색 필드의 autofocus: !isNearbyEntry 가
    // 담당하므로 여기서 별도 requestFocus 는 두지 않는다. 가까운 역 진입은 위치
    // 조회를 먼저 하고 autofocus 도 꺼져 포커스를 가로채지 않는다.
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
      if (!_isNearbySearchRunning &&
          _controller.state.status != StationSearchStatus.idle) {
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

  /// pickSlot·entryMode 조합에 따른 입력 힌트. 큰 타이틀 화면을 없앤 대신, 입력
  /// 필드 자체의 힌트/시맨틱에 "무엇을 고르는 중인지"를 인코딩해 TalkBack이 출발/
  /// 도착/일반 검색 의도를 그대로 전달하게 한다.
  String get _searchInputHint => switch (widget.pickSlot) {
    // #2083 오너 확정: 슬롯 검색 진입 placeholder는 슬롯명 단독.
    RouteDraftSlot.origin => '출발역',
    RouteDraftSlot.destination => '도착역',
    RouteDraftSlot.waypoint => '경유역',
    null => '역 이름을 입력해 주세요',
  };

  @override
  Widget build(BuildContext context) {
    final isNearbyEntry = widget.entryMode == StationSearchEntryMode.nearby;
    final showNearbyRetryButton = isNearbyEntry && !_hasSearchQuery;
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
      autofocus: !isNearbyEntry,
      onSubmitted: _submit,
      onClear: _queryController.clear,
    );
    // 공용 필드는 56 터치타겟 안에 46px 시각 박스를 배치하고, 그 안 단일 줄
    // TextField가 입력 텍스트(fontSize 17)를 세로 contentPadding으로 감싼다. AppBar
    // 기본 toolbarHeight(56)에 그대로 넣으면 시스템 글자 크기를 키웠을 때 필드가
    // 세로로 잘리므로 필드 실제 렌더 높이에 맞춰 툴바를 키운다. 축소는 하지 않아
    // 기본 배율의 레이아웃은 불변이고, titleSpacing·즉시 입력·뒤로가기 leading
    // 동작은 유지된다.
    final textScaler = MediaQuery.textScalerOf(context);
    // #2090: 공용 필드(EasySubwaySearchField)는 배율에 비례해 바깥 터치타겟(56),
    // 시각 박스(46), 입력 필드(48)를 함께 키운다. 필드가 실제로 차지하는 세로
    // 높이는 이 셋의 최댓값이며 항상 터치타겟(56*배율)이 지배한다. 이전
    // 보정 상수(scale(17*1.2)+30)는 새 필드 메트릭을 과소평가해 확대 시 필드가
    // 툴바 아래로 잘렸으므로, 공용 위젯이 쓰는 것과 동일한 상수·산식으로 필드
    // 높이를 재도출해 정합한다.
    final scaledFieldHeight = math.max(
      math.max(
        EasySubwayTouchTarget.general,
        textScaler.scale(EasySubwayTouchTarget.general),
      ),
      math.max(
        easySubwaySearchFieldVisualHeight,
        textScaler.scale(easySubwaySearchFieldVisualHeight),
      ),
    );
    // #2082: title Row를 홈 search row와 동일하게 상하 6px 패딩으로 감싸므로,
    // 툴바 높이도 그만큼(12) 키워 필드가 잘리지 않게 한다(홈 상단바 60 = 필드
    // 46/터치타겟 대비 여백과 같은 원리).
    const stationSearchToolbarVerticalPadding = 12.0;
    final toolbarHeight = math.max(
      kToolbarHeight,
      scaledFieldHeight + stationSearchToolbarVerticalPadding,
    );
    final recentSearchSection = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isSearching =
            _controller.state.status == StationSearchStatus.loading;
        if (isNearbyEntry || _hasSearchQuery || _recentQueries.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: StationRecentSearchSection(
            queries: _recentQueries,
            enabled: !isSearching && !_isNearbySearchRunning,
            onQuerySelected: _searchRecentQuery,
            onQueryRemoved: _removeRecentQuery,
            onClearAll: _clearRecentQueries,
          ),
        );
      },
    );
    final actionButtonSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final isSearching =
                _controller.state.status == StationSearchStatus.loading;
            final isNearbyDisabled = isSearching || _isNearbySearchRunning;
            if (showNearbyRetryButton) {
              return TextButton.icon(
                key: const Key('nearbyStationSearchButton'),
                style: TextButton.styleFrom(
                  foregroundColor: EasySubwayAccessibleColors.text,
                  alignment: Alignment.centerLeft,
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: isNearbyDisabled ? null : _searchNearby,
                icon: const Icon(Icons.my_location),
                label: const Text('내 주변 역 다시 찾기'),
              );
            }
            if (_hasSearchQuery) {
              // 즉시(디바운스) 검색으로 통일했으므로 별도 검색 버튼을 두지 않는다.
              return const SizedBox.shrink();
            }
            return TextButton.icon(
              key: const Key('nearbyStationSearchButton'),
              style: TextButton.styleFrom(
                foregroundColor: EasySubwayAccessibleColors.text,
                alignment: Alignment.centerLeft,
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: isNearbyDisabled ? null : _searchNearby,
              icon: const Icon(Icons.my_location),
              label: const Text('내 주변 역 찾기'),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
    final isPicking = widget.pickSlot != null;
    final resultSection = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return StationSearchBody(
          state: _controller.state,
          // 칸 채우기 모드에서는 결과 한 번 탭 = 해당 칸 설정 후 닫기. 지도 탭과 동일
          // 하게 "출발역 선택 → 도착역 선택" UX로 수렴시킨다. 둘러보기 모드에서는
          // 종전대로 역 상세로 이동한다.
          onResultTap: isPicking ? _pickStation : _returnStationToMap,
          onSetOrigin: isPicking || widget.routeDraftController == null
              ? null
              : _setRouteOrigin,
          onSetDestination: isPicking || widget.routeDraftController == null
              ? null
              : _setRouteDestination,
          isOpeningLocationSettings: _isOpeningLocationSettings,
          onOpenLocationSettings: _openLocationSettings,
        );
      },
    );
    return Scaffold(
      // 큰 타이틀 화면(예: "역 검색")을 없애고 입력 필드 자체가 헤더가 된다. 열리는
      // 즉시 입력 모드로 들어가 탭 두 번을 요구하던 랜딩 단계를 지운다. 뒤로가기는
      // AppBar 기본 leading을 그대로 쓴다(자동 back 버튼 → 입력 필드 순서 유지).
      appBar: AppBar(
        titleSpacing: 0,
        toolbarHeight: toolbarHeight,
        // #2082: 검색 화면 상단바를 홈 idle 상단바 [≡ | 검색필드 | 지역표시]와
        // 픽셀 단위로 정합한다. AppBar 기본 leading/titleSpacing 대신 홈의 search
        // row 구조(Padding.fromLTRB(10,6,10,6) 안 Row[뒤로 56, SB 4, Expanded 필드,
        // SB 8, 지역표시])를 그대로 재현해, ← 버튼이 홈의 ≡ 슬롯과 같은 x를 차지하고
        // 필드의 좌우 시작·끝 x가 홈 idle 필드와 일치하며, 지역 표시가 필드 우측에
        // 홈과 같은 위치·스타일로 온다. 뒤로가기 아이콘·색·탭타깃도 홈 ≡ 버튼과
        // 동일 규격이다. 지역 표시는 홈 지역 선택기 스타일이되 검색 맥락에선 표시
        // 전용이다(오너 지시: "변경은 못해도 알려는 줘야").
        //
        // automaticallyImplyLeading: false + 커스텀 IconButton(아래)을 쓰는 이유:
        // ① 이 앱은 한국어 한정 서비스라(오너 결정) 자동 BackButton이 제공하는
        // MaterialLocalizations 지역화 툴팁("Back" 등)이 불필요하고, 커스텀
        // IconButton으로 한글 tooltip('뒤로')을 직접 지정하는 편이 맥락에 맞는다.
        // ② 자동 BackButton은 크기·패딩이 Material 기본 규격을 따라 위 홈 ≡ 슬롯
        // (56 정사각 탭타깃)과 폭이 정합되지 않는다. 여기서는 minimumSize·
        // tapTargetSize·padding을 홈 ≡ 버튼과 동일 규격으로 명시 통제해야 위 주석의
        // 픽셀 정합이 성립한다. "코드 정리" 목적으로 automaticallyImplyLeading을
        // true로 되돌리거나 IconButton을 BackButton으로 바꾸면 이 폭 정합이 깨진다.
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              IconButton(
                key: const Key('stationSearchBackButton'),
                tooltip: '뒤로',
                onPressed: () => Navigator.of(context).maybePop(),
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(EasySubwayTouchTarget.general),
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
              _StationSearchRegionIndicator(regionLabel: widget.regionLabel),
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
                    actionButtonSection: actionButtonSection,
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
    await _controller.search(query, recordHistory: recordHistory);
    // 최근 검색 목록은 기록한 경우에만 바뀌므로, 디바운스 타이핑 검색에서는
    // 불필요한 재조회를 하지 않는다.
    if (recordHistory) {
      await _loadRecentQueries();
    }
  }

  void _searchRecentQuery(String query) {
    _queryController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _submit(query);
  }

  Future<void> _removeRecentQuery(String query) async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.removeSearch(query);
      await _loadRecentQueries();
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색어 삭제 중 예외가 발생했습니다.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_searchHistoryChangeErrorMessage)),
        );
      }
    }
  }

  Future<void> _clearRecentQueries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.clearSearches();
      await _loadRecentQueries();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '최근 검색어 전체 삭제 중 예외가 발생했습니다.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(_searchHistoryChangeErrorMessage)),
        );
      }
    }
  }

  Future<void> _loadRecentQueries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      final queries = await repository.listRecentQueries();
      if (!mounted) {
        return;
      }
      setState(() => _recentQueries = queries);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색어 조회 중 예외가 발생했습니다.');
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

  void _setRouteOrigin(StationSearchResult result) {
    final station = RouteDraftStation(id: result.id, nameKo: result.nameKo);
    widget.routeDraftController?.setOrigin(station);
    _showRouteDraftSnack('${station.displayName}을 출발역으로 설정했습니다');
  }

  void _setRouteDestination(StationSearchResult result) {
    final station = RouteDraftStation(id: result.id, nameKo: result.nameKo);
    widget.routeDraftController?.setDestination(station);
    _showRouteDraftSnack('${station.displayName}을 도착역으로 설정했습니다');
  }

  void _showRouteDraftSnack(String message) {
    // #1933 요구 3: 별도 길찾기 폼 페이지를 없앴다. 출발·도착을 설정하면 draft로
    // 수렴하고, 둘 다 채워지면 셸이 자동으로 결과 타임라인을 연다. 폼으로 보내던
    // "길찾기 보기" 스낵바 액션은 더 이상 두지 않는다.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _searchNearby() async {
    if (_controller.state.status == StationSearchStatus.loading ||
        _isNearbySearchRunning) {
      return;
    }
    setState(() => _isNearbySearchRunning = true);
    try {
      // 사전 안내 다이얼로그 없이 바로 위치를 요청한다. 거부 시에는 결과 영역의
      // 실패 안내와 '위치 설정 열기'로 재안내하므로 별도 사전 고지가 필요 없다.
      await _controller.searchNearby(widget.locationProvider);
    } finally {
      if (mounted) {
        setState(() => _isNearbySearchRunning = false);
      }
    }
  }

  Future<void> _openLocationSettings() async {
    if (_isOpeningLocationSettings) {
      return;
    }
    setState(() => _isOpeningLocationSettings = true);
    try {
      await widget.locationProvider.openLocationSettings();
    } finally {
      if (mounted) {
        setState(() => _isOpeningLocationSettings = false);
      }
    }
  }
}

/// #2082: 검색 화면 상단 필드 우측 지역 표시. 홈 idle 상단바의 지역 선택기와
/// 같은 위치·스타일(maxWidth 148, 17·w600 회색 텍스트 + 아래 화살표)을 쓰되,
/// 검색 맥락에서는 지역 변경 UI를 새로 열지 않는 표시 전용이다(오너 지시). 탭
/// 동작이 없으므로 스크린리더에는 현재 지역명을 읽어 주는 라벨만 노출한다.
class _StationSearchRegionIndicator extends StatelessWidget {
  const _StationSearchRegionIndicator({required this.regionLabel});

  final String regionLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('stationSearchRegionIndicator'),
      container: true,
      label: '지역: $regionLabel',
      child: ExcludeSemantics(
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
                const SizedBox(width: 2),
                const Icon(
                  Icons.keyboard_arrow_down,
                  color: Color(0xFF606060),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StationSearchAdaptiveContent extends StatelessWidget {
  const _StationSearchAdaptiveContent({
    required this.isLargeScreen,
    required this.recentSearchSection,
    required this.actionButtonSection,
    required this.resultSection,
  });

  final bool isLargeScreen;
  final Widget recentSearchSection;
  final Widget actionButtonSection;
  final Widget resultSection;

  @override
  Widget build(BuildContext context) {
    if (!isLargeScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [recentSearchSection, actionButtonSection, resultSection],
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
                children: [actionButtonSection, resultSection],
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

class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({
    required this.repository,
    required this.reportRepository,
    required this.stationId,
    this.favoriteRepository,
    this.adRepository,
    this.realtimeRepository,
    this.locationProvider,
    this.initiallyFavorite,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteRequest,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    this.mapLauncher = const UrlLauncherKakaoMapLauncher(),
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final AdRepository? adRepository;
  final RealtimeRepository? realtimeRepository;
  final CurrentLocationProvider? locationProvider;
  final String stationId;
  final bool? initiallyFavorite;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final InternalRouteRequest? internalRouteRequest;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;
  final KakaoMapLauncher mapLauncher;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  late final StationDetailController _controller;
  StationFavoriteToggleController? _favoriteController;
  InternalRouteController? _internalRouteController;

  @override
  void initState() {
    super.initState();
    _controller = StationDetailController(
      repository: widget.repository,
      realtimeRepository: widget.realtimeRepository,
    );
    final internalRouteRepository = widget.internalRouteRepository;
    final internalRouteRequest = widget.internalRouteRequest;
    if (internalRouteRepository != null) {
      _internalRouteController = InternalRouteController(
        repository: internalRouteRepository,
      );
      if (internalRouteRequest != null) {
        _internalRouteController!.load(internalRouteRequest);
      } else {
        _internalRouteController!.loadDefault(
          stationId: widget.stationId,
          mobilityType: widget.internalRouteMobilityType,
        );
      }
    }
    final favoriteRepository = widget.favoriteRepository;
    if (favoriteRepository != null) {
      final initiallyFavorite = widget.initiallyFavorite;
      _favoriteController = StationFavoriteToggleController(
        repository: favoriteRepository,
        stationId: widget.stationId,
        initiallyFavorite: initiallyFavorite ?? false,
        initiallyChecking: initiallyFavorite == null,
      );
      if (initiallyFavorite == null) {
        _favoriteController!.load();
      }
    }
    _controller.load(widget.stationId);
  }

  @override
  void dispose() {
    _controller.dispose();
    _favoriteController?.dispose();
    _internalRouteController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('역 상세')),
      body: Semantics(
        container: true,
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _controller,
              ?_internalRouteController,
            ]),
            builder: (context, _) {
              return _StationDetailBody(
                state: _controller.state,
                onRetryRealtime: _controller.retryRealtime,
                internalRouteState: _internalRouteController?.state,
                reportRepository: widget.reportRepository,
                favoriteController: _favoriteController,
                adRepository: widget.adRepository,
                routeDraftController: widget.routeDraftController,
                locationProvider: widget.locationProvider,
                mapLauncher: widget.mapLauncher,
                facilityReportDraftTargetStore:
                    widget.facilityReportDraftTargetStore,
                timetableRepository:
                    widget.repository is StationTimetableRepository
                    ? widget.repository as StationTimetableRepository
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StationDetailBody extends StatelessWidget {
  const _StationDetailBody({
    required this.state,
    required this.onRetryRealtime,
    required this.internalRouteState,
    required this.reportRepository,
    required this.favoriteController,
    required this.adRepository,
    required this.routeDraftController,
    required this.locationProvider,
    required this.mapLauncher,
    required this.facilityReportDraftTargetStore,
    required this.timetableRepository,
  });

  final StationDetailState state;
  final VoidCallback onRetryRealtime;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final AdRepository? adRepository;
  final RouteDraftController? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final KakaoMapLauncher mapLauncher;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final StationTimetableRepository? timetableRepository;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationDetailStatus.loading => Semantics(
        label: '역 안내 불러오는 중',
        liveRegion: true,
        child: const Center(child: CircularProgressIndicator()),
      ),
      StationDetailStatus.failure => Padding(
        padding: const EdgeInsets.all(20),
        child: _StationDetailMessage(message: state.message, liveRegion: true),
      ),
      StationDetailStatus.success => _StationDetailContent(
        detail: state.detail!,
        exits: state.exits,
        facilities: state.prioritizedFacilities,
        facilityAttentionSummary: state.facilityAttentionSummary,
        facilityAttentionSemanticLabel: state.facilityAttentionSemanticLabel,
        layoutSummaryItems: state.layoutSummaryItems,
        layoutSummarySemanticLabel: state.layoutSummarySemanticLabel,
        realtimeSnapshot: state.realtimeSnapshot,
        onRetryRealtime: onRetryRealtime,
        internalRouteState: internalRouteState,
        reportRepository: reportRepository,
        favoriteController: favoriteController,
        adRepository: adRepository,
        routeDraftController: routeDraftController,
        locationProvider: locationProvider,
        mapLauncher: mapLauncher,
        facilityReportDraftTargetStore: facilityReportDraftTargetStore,
        timetableRepository: timetableRepository,
      ),
    };
  }
}

class _StationDetailMessage extends StatelessWidget {
  const _StationDetailMessage({required this.message, this.liveRegion = false});

  final String message;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: EasySubwayAccessibleColors.secondaryText,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _StationDetailContent extends StatelessWidget {
  const _StationDetailContent({
    required this.detail,
    required this.exits,
    required this.facilities,
    required this.facilityAttentionSummary,
    required this.facilityAttentionSemanticLabel,
    required this.layoutSummaryItems,
    required this.layoutSummarySemanticLabel,
    required this.realtimeSnapshot,
    required this.onRetryRealtime,
    required this.internalRouteState,
    required this.reportRepository,
    required this.favoriteController,
    required this.adRepository,
    required this.routeDraftController,
    required this.locationProvider,
    required this.mapLauncher,
    required this.facilityReportDraftTargetStore,
    required this.timetableRepository,
  });

  final StationDetail detail;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;
  final String facilityAttentionSummary;
  final String facilityAttentionSemanticLabel;
  final List<StationLayoutSummaryItem> layoutSummaryItems;
  final String layoutSummarySemanticLabel;
  final RealtimeSnapshot realtimeSnapshot;
  final VoidCallback onRetryRealtime;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final AdRepository? adRepository;
  final RouteDraftController? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final KakaoMapLauncher mapLauncher;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final StationTimetableRepository? timetableRepository;

  @override
  Widget build(BuildContext context) {
    // 정보구조 다이어트(#1497): 첫 화면에서 역 이름·고장 여부·실시간 도착·주요
    // 행동이 보이도록 실시간을 위로, 메타는 맨 아래로, 중복 "지도 위치 목록"과
    // 상시 안전 안내는 제거, "역 안 이동 안내"+"순서"는 한 섹션으로 통합한다.
    final primaryChildren = <Widget>[
      StationDetailHeader(detail: detail),
      const SizedBox(height: 12),
      if (facilityAttentionSummary.isNotEmpty) ...[
        StationFacilityStatusSummary(
          text: facilityAttentionSummary,
          semanticLabel: facilityAttentionSemanticLabel,
        ),
        const SizedBox(height: 16),
      ],
      const _StationDetailSectionTitle(title: '실시간 열차'),
      const SizedBox(height: 12),
      StationRealtimeSummary(
        snapshot: realtimeSnapshot,
        onRetry: onRetryRealtime,
      ),
      const SizedBox(height: 20),
      StationDetailRouteActions(
        detail: detail,
        routeDraftController: routeDraftController,
        favoriteController: favoriteController,
      ),
      const SizedBox(height: 20),
      _StationTimetableEntry(detail: detail, repository: timetableRepository),
    ];
    // 데이터 부재(unavailable) 상태는 화면에 아무것도 그리지 않으므로
    // 역 안 이동 섹션 노출 여부·간격 계산에서도 빈 안내로 취급한다(#1577).
    final internalRouteStateValue = internalRouteState;
    final hasInternalRouteGuidance =
        internalRouteStateValue != null &&
        internalRouteStateValue.status != InternalRouteViewStatus.unavailable;
    final detailChildren = <Widget>[
      if (layoutSummaryItems.isNotEmpty || hasInternalRouteGuidance) ...[
        const _StationDetailSectionTitle(title: '역 안 이동'),
        const SizedBox(height: 12),
        if (layoutSummaryItems.isNotEmpty) ...[
          StationLayoutSummary(
            items: layoutSummaryItems,
            semanticLabel: layoutSummarySemanticLabel,
          ),
          if (hasInternalRouteGuidance) const SizedBox(height: 16),
        ],
        if (hasInternalRouteGuidance)
          StationInternalRouteGuidance(state: internalRouteState!),
        const SizedBox(height: 24),
      ],
      const _StationDetailSectionTitle(title: '출구'),
      const SizedBox(height: 12),
      if (exits.isEmpty)
        const _StationDetailEmptyMessage(message: '출구 안내를 준비 중이에요.')
      else
        for (final exit in exits)
          StationExitCard(
            station: detail,
            exit: exit,
            mapLauncher: mapLauncher,
            locationProvider: locationProvider,
          ),
      const SizedBox(height: 24),
      const _StationDetailSectionTitle(title: '시설'),
      const SizedBox(height: 12),
      if (facilities.isEmpty)
        const _StationDetailEmptyMessage(message: '시설 안내를 준비 중이에요.')
      else
        for (final facility in facilities)
          StationFacilityCard(
            facility: facility,
            station: detail,
            onReportTap: () => _openFacilityReport(context, facility),
          ),
      const SizedBox(height: 24),
      // 메타 정보(안내 출처·마지막 확인)는 맨 아래로.
      StationInfoBasisDisclosure(
        labels: [
          detail.dataSourceLabel,
          '마지막 확인 ${stationVerifiedRelativeLabel(detail.lastVerifiedAt)}',
        ],
      ),
      if (adRepository case final repository?) ...[
        const SizedBox(height: 24),
        ActiveAdBanner(
          key: const Key('stationDetailBottomAdBanner'),
          repository: repository,
          placement: AdPlacement.stationDetailBottom,
        ),
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = EasySubwayAdaptiveLayout.isLargeScreen(
          constraints,
          textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
        );
        return ListView(
          key: const Key('stationDetailList'),
          padding: isLargeScreen
              ? _stationSearchLargePagePadding
              : _stationSearchPagePadding,
          children: isLargeScreen
              ? [
                  _StationDetailAdaptiveContent(
                    primaryChildren: primaryChildren,
                    detailChildren: detailChildren,
                  ),
                ]
              : [
                  ...primaryChildren,
                  const SizedBox(height: 24),
                  ...detailChildren,
                ],
        );
      },
    );
  }

  void _openFacilityReport(BuildContext context, StationFacilityInfo facility) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FacilityReportScreen(
          repository: reportRepository,
          locationLoader: _locationLoader(),
          needsLocationPermissionRequest: _locationPermissionRequestChecker(),
          openLocationSettings: _locationSettingsOpener(),
          draftTargetStore: facilityReportDraftTargetStore,
          target: FacilityReportTarget(
            stationId: detail.id,
            stationName: detail.nameKo,
            facilityId: facility.id,
            facilityName: facility.name,
            facilityTypeLabel: facility.typeLabel,
            facilityStatusLabel: facility.statusLabel,
          ),
        ),
      ),
    );
  }

  FacilityReportLocationLoader? _locationLoader() {
    final provider = locationProvider;
    if (provider == null) {
      return null;
    }
    return () async {
      final CurrentLocation location;
      try {
        location = await provider.currentLocation();
      } on CurrentLocationException catch (error) {
        throw FacilityReportLocationException(error.message);
      }
      return FacilityReportLocation(
        latitude: location.latitude,
        longitude: location.longitude,
      );
    };
  }

  FacilityReportLocationPermissionRequestChecker?
  _locationPermissionRequestChecker() {
    final provider = locationProvider;
    if (provider == null) {
      return null;
    }
    return provider.needsLocationPermissionRequest;
  }

  FacilityReportLocationSettingsOpener? _locationSettingsOpener() {
    final provider = locationProvider;
    if (provider == null) {
      return null;
    }
    return provider.openLocationSettings;
  }
}

class _StationTimetableEntry extends StatefulWidget {
  const _StationTimetableEntry({required this.detail, this.repository});

  final StationDetail detail;
  final StationTimetableRepository? repository;

  @override
  State<_StationTimetableEntry> createState() => _StationTimetableEntryState();
}

class _StationTimetableEntryState extends State<_StationTimetableEntry> {
  StationTimetable? _timetable;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    if (repository != null && widget.detail.lines.isNotEmpty) {
      unawaited(_load(repository, widget.detail.lines));
    }
  }

  Future<void> _load(
    StationTimetableRepository repository,
    List<StationSearchLine> lines,
  ) async {
    try {
      final timetable = await loadFirstAvailableStationTimetable(
        stationId: widget.detail.id,
        lines: lines,
        repository: repository,
        date: debugStationVerifiedClock(),
      );
      if (mounted && timetable != null) {
        setState(() => _timetable = timetable);
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 상세 시간표 요약 조회 중 예외가 발생했습니다.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _timetable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StationDetailSectionTitle(title: '시간표'),
        const SizedBox(height: 8),
        if (timetable != null && timetable.isAvailable)
          for (final direction in timetable.directions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${direction.name} · 첫차 ${direction.firstDeparture.timeLabel} · '
                '막차 ${direction.lastDeparture.timeLabel}',
              ),
            )
        else
          const Text('시간표를 준비 중이에요.'),
        const SizedBox(height: 4),
        TextButton.icon(
          key: const Key('stationTimetableButton'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StationTimetableScreen(
                stationId: widget.detail.id,
                stationName: widget.detail.nameKo,
                lines: widget.detail.lines,
                repository: widget.repository,
              ),
            ),
          ),
          icon: const Icon(Icons.schedule),
          label: const Text('시간표 보기'),
        ),
      ],
    );
  }
}

class _StationDetailAdaptiveContent extends StatelessWidget {
  const _StationDetailAdaptiveContent({
    required this.primaryChildren,
    required this.detailChildren,
  });

  final List<Widget> primaryChildren;
  final List<Widget> detailChildren;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: EasySubwayAdaptiveLayout.largeScreenMaxContentWidth,
        ),
        child: Row(
          key: const Key('stationDetailLargeScreenLayout'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                key: const Key('stationDetailPrimaryColumn'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: primaryChildren,
              ),
            ),
            const SizedBox(
              width: EasySubwayAdaptiveLayout.largeScreenColumnGap,
            ),
            Expanded(
              flex: 5,
              child: Column(
                key: const Key('stationDetailDetailColumn'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: detailChildren,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationDetailSectionTitle extends StatelessWidget {
  const _StationDetailSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}

class _StationDetailEmptyMessage extends StatelessWidget {
  const _StationDetailEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: EasySubwayAccessibleColors.secondaryText,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
  }
}

Uri defaultStationApiBaseUri() {
  const configuredBaseUrl = String.fromEnvironment('EASYSUBWAY_API_BASE_URL');
  return stationApiBaseUriForEnvironment(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: Platform.isAndroid,
    isReleaseMode: kReleaseMode,
  );
}

Uri? defaultOptionalStationApiBaseUri() {
  const configuredBaseUrl = String.fromEnvironment('EASYSUBWAY_API_BASE_URL');
  return optionalStationApiBaseUriForEnvironment(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: Platform.isAndroid,
    isReleaseMode: kReleaseMode,
  );
}

Uri? optionalStationApiBaseUriForEnvironment({
  required String configuredBaseUrl,
  required bool isAndroid,
  required bool isReleaseMode,
}) {
  if (configuredBaseUrl.trim().isEmpty && isReleaseMode) {
    return null;
  }
  return stationApiBaseUriForEnvironment(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: isAndroid,
    isReleaseMode: isReleaseMode,
  );
}

Uri stationApiBaseUriForEnvironment({
  required String configuredBaseUrl,
  required bool isAndroid,
  required bool isReleaseMode,
}) {
  final trimmedBaseUrl = configuredBaseUrl.trim();
  if (trimmedBaseUrl.isNotEmpty) {
    final baseUri = Uri.parse(trimmedBaseUrl);
    if (isReleaseMode && baseUri.scheme != 'https') {
      throw StateError('Release API base URL must use HTTPS.');
    }
    if (isReleaseMode && baseUri.host.isEmpty) {
      throw StateError('Release API base URL must include a host.');
    }
    return baseUri;
  }
  if (isReleaseMode) {
    // 운영 빌드는 로컬 개발 주소로 조용히 떨어지지 않게 빌드 설정 누락을 즉시 드러낸다.
    throw StateError('Release API base URL must be configured.');
  }
  Uri? developmentBaseUri;
  assert(() {
    developmentBaseUri = Uri.parse(
      isAndroid ? 'http://10.0.2.2:8080' : 'http://127.0.0.1:8080',
    );
    return true;
  }());
  if (developmentBaseUri == null) {
    throw StateError('Development API base URL is only available in debug.');
  }
  return developmentBaseUri!;
}
