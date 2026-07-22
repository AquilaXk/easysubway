import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../accessible_design.dart';
import '../../../app/app_components.dart';
import '../../../facility_report.dart';
import '../../../favorite_facility.dart';
import '../../../internal_route.dart';
import '../../../mobile_error_reporter.dart';
import '../../../network_map.dart';
import '../../../notification_settings.dart';
import '../../../onboarding.dart';
import '../../../route_search.dart';
import '../../../station_search.dart';
import '../../../user_data_deletion.dart';
import '../../ads/ad_repository.dart';
import '../../favorites/presentation/favorite_home_screen.dart';
import '../../get_off_alarm/get_off_alarm_controller.dart';
import '../../mobility_profile/mobility_preset_labels.dart';
import '../../mobility_profile/mobility_preset_picker.dart';
import '../../mobility_profile/mobility_profile_policy.dart';
import '../../network_map/presentation/region_menu.dart';
import '../../notifications/presentation/new_notification_bar.dart';
import '../../notifications/presentation/notification_inbox_screen.dart';
import '../../realtime/realtime_repository.dart';
import '../../route_draft/application/route_draft_controller.dart';
import '../../route_draft/domain/route_draft.dart';
import '../../service_notice/data/notice_repository.dart';
import '../../service_notice/presentation/notice_controller.dart';
import '../../service_notice/presentation/service_notice_list_screen.dart';
import '../../settings/presentation/app_settings_screen.dart';
import '../../settings/presentation/service_info_screen.dart';
import '../../stations/presentation/station_search_screen.dart';
import '../../support/presentation/support_access_screen.dart';
import '../../train_search/domain/train_search_models.dart';
import '../../train_search/presentation/train_search_screen.dart';

const _mainIconControlRadius = BorderRadius.all(Radius.circular(12));

/// 역 검색 화면 지역 메뉴에 노선도가 아는 지역을 모두 담는다(#2419 리뷰
/// finding). 기본 목록 5개를 우선 유지하고, 맵에만 있는 지역 표시명이 있으면
/// 뒤에 이어붙인다(기본 목록에 없는 지역은 id도 표시명 그대로 쓴다).
List<EasySubwayRegionMenuItem> _stationSearchRegionsForMap(
  List<String> mapRegionLabels,
) {
  final knownLabels = defaultStationSearchRegions
      .map((item) => item.label)
      .toSet();
  final extras = <EasySubwayRegionMenuItem>[
    for (final label in mapRegionLabels)
      if (knownLabels.add(label))
        EasySubwayRegionMenuItem(id: label, label: label),
  ];
  return extras.isEmpty
      ? defaultStationSearchRegions
      : [...defaultStationSearchRegions, ...extras];
}

class HomeScreen extends StatefulWidget {
  HomeScreen({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.routeFeedbackRepository,
    required this.getOffAlarmController,
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    this.adRepository,
    required this.searchHistoryRepository,
    required this.internalRouteRepository,
    required this.networkMapRepository,
    required this.networkMapViewportRepository,
    required this.realtimeRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.locationProvider,
    required this.trainSearchRepository,
    required this.supportAccessInfo,
    required this.supportAccessLauncher,
    required this.userDataDeletionRepository,
    this.noticeRepository,
    required this.onUserDataDeleted,
    required this.onMobilityProfileChanged,
    required this.onViewPreferencesChanged,
    required this.recentRoutesFuture,
    this.viewPreferences = const OnboardingViewPreferences.defaults(),
    this.simpleViewEnabled = true,
    this.facilityReportDraftTargetStore,
    this.bundledDataPackStaleLabel,
    String? initialMobilityType,
    super.key,
  }) : initialMobilityType =
           initialMobilityType ??
           mobilityPresetRepresentativeMobilityType(MobilityPreset.standard);

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final GetOffAlarmController? getOffAlarmController;
  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final AdRepository? adRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final InternalRouteRepository internalRouteRepository;
  final NetworkMapRepository networkMapRepository;
  final NetworkMapViewportRepository? networkMapViewportRepository;
  final RealtimeRepository realtimeRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final TrainSearchRepository trainSearchRepository;
  final SupportAccessInfo supportAccessInfo;
  final SupportAccessLauncher supportAccessLauncher;
  final UserDataDeletionRepository? userDataDeletionRepository;
  final NoticeRepository? noticeRepository;
  final Future<void> Function(UserDataDeletionResult result)? onUserDataDeleted;
  final Future<void> Function(MobilityPreset preset)? onMobilityProfileChanged;
  final Future<void> Function(OnboardingViewPreferences preferences)
  onViewPreferencesChanged;
  final Future<List<FavoriteRoute>>? recentRoutesFuture;
  final String initialMobilityType;
  final OnboardingViewPreferences viewPreferences;
  final bool simpleViewEnabled;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final String? bundledDataPackStaleLabel;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedTabIndex = 0;

  /// 설정 탭 뒤로가기용. 직전에 보던 탭(없으면 홈).
  int? _previousTabIndex;
  late String _mobilityType;
  String? _routeTabMobilityType;
  RouteTransportScope _routeTabTransportScope = RouteTransportScope.subway;
  late final RouteDraftController _routeDraftController;
  Future<List<FavoriteFacility>>? _favoriteFacilitiesFuture;
  late Future<bool> _hasNotificationItemsFuture;
  NoticeController? _noticeController;

  /// #1933 C: 출발·도착이 모두 채워진 draft 조합의 서명. 노선도 위 오버레이(지도 탭·
  /// 역 검색 어느 경로든)에서 둘 다 채워지면 별도 버튼 없이 결과 타임라인으로 자동
  /// 연결한다. 같은 조합으로는 한 번만 자동 전환하고, 사용자가 한쪽을 지우거나 바꿔
  /// 다시 완성하면 서명이 달라져 새로 전환한다.
  String? _autoRoutedDraftSignature;
  Timer? _autoRouteDebounce;

  // #2109 Fix: 풀페이지 검색(햄버거 메뉴 경유) 결과 탭으로 반환된 역. 노선도에
  // focus + 팬 메뉴 + 해당 역 하단 패널을 요청하는 채널이다.
  StationSearchResult? _mapFocusStationRequest;

  /// 풀페이지 역 검색 ↔ 홈 노선도 지역 동기화용.
  final NetworkMapRegionBridge _mapRegionBridge = NetworkMapRegionBridge();

  /// #2419 Fix: 노선도의 현재 지역 표시명. 노선 탭이 draft(출발/도착) 역의
  /// 지역 폴백으로 써서 최근 경로 기록이 항상 스킵되던 결함을 고친다.
  String _currentRegionLabel = '수도권';

  @override
  void initState() {
    super.initState();
    _mobilityType = widget.initialMobilityType;
    _routeDraftController = RouteDraftController();
    _routeDraftController.addListener(_handleRouteDraftChanged);
    final facilitiesFuture = _loadNotificationFacilities();
    _favoriteFacilitiesFuture = facilitiesFuture;
    _hasNotificationItemsFuture = _loadHasNotificationItems(facilitiesFuture);
    final noticeRepository = widget.noticeRepository;
    if (noticeRepository != null) {
      final controller = NoticeController(repository: noticeRepository);
      _noticeController = controller;
      // 앱 시작 시 최초 조회. 이후 조회는 포그라운드 복귀 트리거에서만 일어난다
      // (별도 폴링 주기를 신설하지 않는다).
      unawaited(controller.refresh());
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_noticeController?.refresh());
    }
  }

  @override
  void dispose() {
    if (_noticeController != null) {
      WidgetsBinding.instance.removeObserver(this);
      _noticeController!.dispose();
    }
    _autoRouteDebounce?.cancel();
    _routeDraftController.removeListener(_handleRouteDraftChanged);
    _routeDraftController.dispose();
    super.dispose();
  }

  /// draft가 바뀔 때마다 호출된다. 출발·도착이 모두 채워지면 결과 탭으로 자동
  /// 전환한다. 지도 탭·역 검색이 draft를 여러 번 갱신할 수 있으므로 짧게 debounce해
  /// 마지막 상태로만 전환하고, 같은 조합으로는 중복 전환하지 않는다.
  void _handleRouteDraftChanged() {
    final draft = _routeDraftController.draft;
    final origin = draft.origin;
    final destination = draft.destination;
    if (origin == null || destination == null) {
      // 한쪽이라도 비면 서명을 초기화해, 다시 완성했을 때 재전환되게 한다.
      _autoRoutedDraftSignature = null;
      _autoRouteDebounce?.cancel();
      return;
    }
    final waypoint = draft.waypoint;
    final signature = waypoint == null
        ? '${origin.id} ${destination.id}'
        : '${origin.id} ${waypoint.id} ${destination.id}';
    if (signature == _autoRoutedDraftSignature) {
      return;
    }
    _autoRoutedDraftSignature = signature;
    _autoRouteDebounce?.cancel();
    _autoRouteDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) {
        return;
      }
      // 이미 결과 탭이면 setState만으로도 화면이 최신 draft로 다시 빌드되며
      // RouteSearchScreen이 자동 검색을 이어간다.
      if (_selectedTabIndex != 2) {
        setState(() {
          _routeTabMobilityType = _mobilityType;
          _routeTabTransportScope = RouteTransportScope.subway;
          _selectTab(2);
        });
      } else {
        setState(() {});
      }
      // 자동 전환을 화면 낭독기에 알린다(포커스는 옮기지 않는다).
      SemanticsService.sendAnnouncement(
        View.of(context),
        '출발과 도착이 정해져 경로 결과를 보여드려요.',
        Directionality.of(context),
      );
    });
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_mobilityType == oldWidget.initialMobilityType &&
        widget.initialMobilityType != oldWidget.initialMobilityType) {
      _mobilityType = widget.initialMobilityType;
    }
    if (widget.favoriteFacilityRepository !=
        oldWidget.favoriteFacilityRepository) {
      final facilitiesFuture = _loadNotificationFacilities();
      _favoriteFacilitiesFuture = facilitiesFuture;
      _hasNotificationItemsFuture = _loadHasNotificationItems(facilitiesFuture);
    }
    if (widget.reportRepository != oldWidget.reportRepository ||
        widget.notificationRepository != oldWidget.notificationRepository) {
      if (widget.notificationRepository != oldWidget.notificationRepository) {
        _favoriteFacilitiesFuture = _loadNotificationFacilities();
      }
      _hasNotificationItemsFuture = _loadHasNotificationItems(
        _favoriteFacilitiesFuture,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final reportRepository = widget.reportRepository;
    final routeRepository = widget.routeRepository;
    final favoriteRepository = widget.favoriteRepository;
    final favoriteFacilityRepository = widget.favoriteFacilityRepository;
    final favoriteRouteRepository = widget.favoriteRouteRepository;
    final adRepository = widget.adRepository;
    final searchHistoryRepository = widget.searchHistoryRepository;
    final internalRouteRepository = widget.internalRouteRepository;
    final networkMapRepository = widget.networkMapRepository;
    final realtimeRepository = widget.realtimeRepository;
    final routeFeedbackRepository = widget.routeFeedbackRepository;
    final getOffAlarmController = widget.getOffAlarmController;
    final notificationRepository = widget.notificationRepository;
    final notificationPermissionProvider =
        widget.notificationPermissionProvider;
    final locationProvider = widget.locationProvider;
    final supportAccessInfo = widget.supportAccessInfo;
    final supportAccessLauncher = widget.supportAccessLauncher;
    final userDataDeletionRepository = widget.userDataDeletionRepository;
    final onUserDataDeleted = widget.onUserDataDeleted;
    final simpleViewEnabled = widget.simpleViewEnabled;
    final facilityReportDraftTargetStore =
        widget.facilityReportDraftTargetStore;
    final initialMobilityType = _mobilityType;
    final currentPreset =
        mobilityPresetFromRepresentativeMobilityType(_mobilityType) ??
        MobilityPreset.standard;
    void openSupportAccess() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportAccessScreen(
            accessInfo: supportAccessInfo,
            launcher: supportAccessLauncher,
            userDataDeletionRepository: userDataDeletionRepository,
            onUserDataDeleted: onUserDataDeleted,
          ),
        ),
      );
    }

    void openServiceInfo() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ServiceInfoScreen(accessInfo: supportAccessInfo),
        ),
      );
    }

    void openMyReports() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MyFacilityReportListScreen(repository: reportRepository),
        ),
      );
    }

    void openNotificationInbox() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationInboxScreen(
            favoriteFacilityRepository: favoriteFacilityRepository,
            reportRepository: reportRepository,
            notificationRepository: notificationRepository,
            notificationPermissionProvider: notificationPermissionProvider,
          ),
        ),
      );
    }

    void openHomeTab() {
      if (_selectedTabIndex == 0) {
        return;
      }
      setState(() {
        _selectTab(0);
      });
    }

    void openRouteTab([
      String? mobilityType,
      RouteTransportScope transportScope = RouteTransportScope.subway,
    ]) {
      final nextMobilityType = mobilityType ?? initialMobilityType;
      if (_selectedTabIndex == 2 &&
          _routeTabMobilityType == nextMobilityType &&
          _routeTabTransportScope == transportScope) {
        return;
      }
      setState(() {
        _routeTabMobilityType = nextMobilityType;
        _routeTabTransportScope = transportScope;
        _selectTab(2);
      });
    }

    void openMoreTab() {
      if (_selectedTabIndex == 4) {
        return;
      }
      setState(() {
        _selectTab(4);
      });
    }

    void openSavedTab() {
      if (favoriteRepository == null &&
          favoriteFacilityRepository == null &&
          favoriteRouteRepository == null) {
        openMoreTab();
        return;
      }
      if (_selectedTabIndex == 3) {
        return;
      }
      setState(() {
        _selectTab(3);
      });
    }

    void openPreviousTabOrHome() {
      final previous = _previousTabIndex;
      setState(() {
        if (previous != null && previous != _selectedTabIndex) {
          _selectedTabIndex = previous;
        } else {
          _selectedTabIndex = 0;
        }
      });
    }

    Future<void> refreshHomeState() async {
      final facilitiesFuture = _loadNotificationFacilities();
      final hasNotificationItemsFuture = _loadHasNotificationItems(
        facilitiesFuture,
      );
      setState(() {
        _favoriteFacilitiesFuture = facilitiesFuture;
        _hasNotificationItemsFuture = hasNotificationItemsFuture;
      });
      try {
        await Future.wait<void>([
          if (facilitiesFuture != null) facilitiesFuture.then((_) {}),
          hasNotificationItemsFuture.then((_) {}),
        ]);
      } catch (error, stackTrace) {
        (error, stackTrace);
        // FutureBuilder가 오류 상태를 표시하므로 refresh callback은 정상 종료한다.
      }
    }

    Future<void> openStationSearch(
      String regionLabel,
      List<String> mapRegionLabels,
    ) async {
      // #2109 Fix: 둘러보기 모드 결과 탭은 더 이상 즉시 상세를 밀지 않고
      // 선택한 역 결과를 pop으로 반환한다(_returnStationToMap). 여기서 노선
      // 정보까지 받아 노선도에 focus + 팬 메뉴 + 하단 패널을 요청한다.
      final station = await Navigator.of(context).push<StationSearchResult>(
        MaterialPageRoute<StationSearchResult>(
          builder: (_) => StationSearchScreen(
            repository: repository,
            reportRepository: reportRepository,
            favoriteRepository: favoriteRepository,
            adRepository: adRepository,
            searchHistoryRepository: searchHistoryRepository,
            facilityReportDraftTargetStore: facilityReportDraftTargetStore,
            internalRouteRepository: internalRouteRepository,
            internalRouteMobilityType: initialMobilityType,
            realtimeRepository: realtimeRepository,
            routeDraftController: _routeDraftController,
            regionLabel: regionLabel,
            regions: _stationSearchRegionsForMap(mapRegionLabels),
            onRegionChanged: _mapRegionBridge.selectRegion,
          ),
        ),
      );
      if (!context.mounted) {
        return;
      }
      if (station != null) {
        setState(() => _mapFocusStationRequest = station);
      }
      await refreshHomeState();
    }

    // G4: 노선도 상단 오버레이의 출발/도착 칸 탭 → 기존 역 검색을 "칸 채우기" 모드로
    // 연다. 결과 한 번 탭 = 지도 탭과 같은 _routeDraftController로 수렴한 뒤 닫힌다.
    Future<void> openStationSearchForSlot(
      RouteDraftSlot slot,
      String regionLabel,
      List<String> mapRegionLabels,
    ) async {
      await Navigator.of(context).push(
        MaterialPageRoute<RouteDraftStation>(
          builder: (_) => StationSearchScreen(
            repository: repository,
            reportRepository: reportRepository,
            favoriteRepository: favoriteRepository,
            searchHistoryRepository: searchHistoryRepository,
            facilityReportDraftTargetStore: facilityReportDraftTargetStore,
            internalRouteRepository: internalRouteRepository,
            internalRouteMobilityType: initialMobilityType,
            realtimeRepository: realtimeRepository,
            routeDraftController: _routeDraftController,
            pickSlot: slot,
            regionLabel: regionLabel,
            regions: _stationSearchRegionsForMap(mapRegionLabels),
            onRegionChanged: _mapRegionBridge.selectRegion,
          ),
        ),
      );
      if (!context.mounted) {
        return;
      }
      await refreshHomeState();
    }

    final noticeController = _noticeController;
    void openServiceNotices() {
      if (noticeController == null) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ServiceNoticeListScreen(controller: noticeController),
        ),
      );
    }

    void openTrainSearch() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TrainSearchScreen(repository: widget.trainSearchRepository),
        ),
      );
    }

    Widget rootTab(Widget child) {
      final staleLabel = widget.bundledDataPackStaleLabel;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || _selectedTabIndex == 0) {
            return;
          }
          openHomeTab();
        },
        child: staleLabel == null
            ? child
            : SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Material(
                      color: EasySubwayAccessibleColors.surface,
                      child: Semantics(
                        container: true,
                        liveRegion: true,
                        label: staleLabel,
                        child: Container(
                          key: const Key('bundledDataPackStaleBanner'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: EasySubwayAccessibleColors.line,
                              ),
                            ),
                          ),
                          child: ExcludeSemantics(
                            child: Text(
                              staleLabel,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.text,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
      );
    }

    if (_selectedTabIndex == 0) {
      return rootTab(
        NetworkMapScreen(
          repository: networkMapRepository,
          routeDraftController: _routeDraftController,
          regionBridge: _mapRegionBridge,
          onOpenStationSearch: (regionLabel, mapRegionLabels) =>
              unawaited(openStationSearch(regionLabel, mapRegionLabels)),
          onStationSearchClosed: () => unawaited(refreshHomeState()),
          onPickStationForSlot: (slot, regionLabel, mapRegionLabels) =>
              unawaited(
                openStationSearchForSlot(slot, regionLabel, mapRegionLabels),
              ),
          stationSearchRepository: repository,
          reportRepository: reportRepository,
          favoriteRepository: favoriteRepository,
          adRepository: adRepository,
          searchHistoryRepository: searchHistoryRepository,
          facilityReportDraftTargetStore: facilityReportDraftTargetStore,
          internalRouteRepository: internalRouteRepository,
          internalRouteMobilityType: initialMobilityType,
          locationProvider: locationProvider,
          viewportRepository: widget.networkMapViewportRepository,
          realtimeRepository: widget.realtimeRepository,
          onOpenSavedItems: openSavedTab,
          onOpenTrainSearch: openTrainSearch,
          onOpenSettings: openMoreTab,
          onOpenServiceNotices: noticeController == null
              ? null
              : openServiceNotices,
          disruptionBanner:
              (noticeController == null && notificationRepository == null)
              ? null
              : FutureBuilder<bool>(
                  future: _hasNotificationItemsFuture,
                  builder: (context, snapshot) {
                    return NewNotificationBar(
                      noticeController: noticeController,
                      hasNotificationItems: snapshot.data ?? false,
                      onOpenInbox: openNotificationInbox,
                    );
                  },
                ),
          notificationAction: notificationRepository == null
              ? null
              : FutureBuilder<bool>(
                  future: _hasNotificationItemsFuture,
                  builder: (context, snapshot) {
                    return _HomeNotificationButton(
                      key: const Key('homeNotificationActionButton'),
                      hasNotificationItems: snapshot.data ?? false,
                      onPressed: openNotificationInbox,
                    );
                  },
                ),
          focusStationRequest: _mapFocusStationRequest,
          onFocusStationRequestHandled: () =>
              setState(() => _mapFocusStationRequest = null),
          onRegionLabelChanged: (regionLabel) {
            if (regionLabel == _currentRegionLabel) {
              return;
            }
            setState(() => _currentRegionLabel = regionLabel);
          },
        ),
      );
    }

    if (_selectedTabIndex == 1) {
      // 하단 탭 인덱스 1은 현재 어떤 탭 전환 경로에서도 setState로 선택되지
      // 않는 미도달 분기다(탭 0 노선도 안 "역 검색" 메뉴가 실사용 경로).
      // 지역 상태는 NetworkMapScreen 안에만 있어 이 분기는 알 수 없으므로
      // 홈 기본 지역과 동일한 '수도권'을 명시한다.
      return rootTab(
        StationSearchScreen(
          repository: repository,
          reportRepository: reportRepository,
          favoriteRepository: favoriteRepository,
          adRepository: adRepository,
          searchHistoryRepository: searchHistoryRepository,
          facilityReportDraftTargetStore: facilityReportDraftTargetStore,
          internalRouteRepository: internalRouteRepository,
          internalRouteMobilityType: initialMobilityType,
          realtimeRepository: realtimeRepository,
          routeDraftController: _routeDraftController,
          regionLabel: '수도권',
        ),
      );
    }

    if (_selectedTabIndex == 2) {
      return rootTab(
        RouteSearchScreen(
          repository: routeRepository,
          stationRepository: repository,
          searchHistoryRepository: searchHistoryRepository,
          routeFeedbackRepository: routeFeedbackRepository,
          getOffAlarmController: getOffAlarmController,
          favoriteRouteRepository: favoriteRouteRepository,
          adRepository: adRepository,
          initialMobilityType: _routeTabMobilityType ?? initialMobilityType,
          initialTransportScope: _routeTabTransportScope,
          initialDraft: _routeDraftController.draft,
          regionLabel: _currentRegionLabel,
          simpleViewEnabled: simpleViewEnabled,
          onShellBackToHome: () {
            _routeDraftController.clear();
            openHomeTab();
          },
        ),
      );
    }

    if (_selectedTabIndex == 3) {
      return rootTab(
        FavoriteHomeScreen(
          favoriteRepository: favoriteRepository,
          favoriteFacilityRepository: favoriteFacilityRepository,
          favoriteRouteRepository: favoriteRouteRepository,
          adRepository: adRepository,
          stationRepository: repository,
          reportRepository: reportRepository,
          locationProvider: locationProvider,
          facilityReportDraftTargetStore: facilityReportDraftTargetStore,
          internalRouteRepository: internalRouteRepository,
          realtimeRepository: realtimeRepository,
          routeDraftController: _routeDraftController,
          initialMobilityType: initialMobilityType,
          onOpenRouteSearch: ([mobilityType, transportScope]) async =>
              openRouteTab(
                mobilityType,
                transportScope ?? RouteTransportScope.subway,
              ),
        ),
      );
    }

    if (_selectedTabIndex == 4) {
      return rootTab(
        AppSettingsScreen(
          currentPreset: currentPreset,
          viewPreferences: widget.viewPreferences,
          notificationRepository: notificationRepository,
          notificationPermissionProvider: notificationPermissionProvider,
          onViewPreferencesChanged: widget.onViewPreferencesChanged,
          onOpenMobilityProfile: _openMobilityProfile,
          onOpenSupportAccess: openSupportAccess,
          onOpenServiceInfo: openServiceInfo,
          onOpenMyReports: openMyReports,
          onShellBack: openPreviousTabOrHome,
        ),
      );
    }

    // 탭 셸(0~4)이 모든 경로를 처리하므로 여기까지 도달하지 않는다.
    return const SizedBox.shrink();
  }

  void _selectTab(int index) {
    if (index == _selectedTabIndex) {
      return;
    }
    _previousTabIndex = _selectedTabIndex;
    _selectedTabIndex = index;
  }

  Future<List<FavoriteFacility>>? _loadNotificationFacilities() {
    if (widget.notificationRepository == null) {
      return null;
    }
    return widget.favoriteFacilityRepository?.listFavoriteFacilities();
  }

  Future<bool> _loadHasNotificationItems(
    Future<List<FavoriteFacility>>? facilitiesFuture,
  ) async {
    if (widget.notificationRepository == null) {
      return false;
    }

    if (facilitiesFuture != null) {
      try {
        final facilities = await facilitiesFuture;
        if (facilities.any(isFacilityAlert)) {
          return true;
        }
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '홈 알림 시설 상태를 불러오는 중 예외가 발생했습니다.',
        );
      }
    }

    try {
      final reports = await widget.reportRepository.listMyReports();
      return reports.isNotEmpty;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '홈 알림 제보 상태를 불러오는 중 예외가 발생했습니다.',
      );
    }
    return false;
  }

  Future<MobilityPreset?> _openMobilityProfile() async {
    final currentPreset =
        mobilityPresetFromRepresentativeMobilityType(_mobilityType) ??
        MobilityPreset.standard;
    final selectedPreset = await showMobilityPresetSheet(
      context,
      current: currentPreset,
    );
    if (!mounted || selectedPreset == null) {
      return null;
    }
    // 현재와 동일한 프리셋을 다시 선택하면 저장·토스트 없이 종료한다(불필요한
    // 저장 I/O와 "변경했습니다" 오해 토스트 방지, #1703).
    if (selectedPreset == currentPreset) {
      return null;
    }
    final previousMobilityType = _mobilityType;
    setState(() {
      _mobilityType = mobilityPresetRepresentativeMobilityType(selectedPreset);
    });
    try {
      await widget.onMobilityProfileChanged?.call(selectedPreset);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '이동 조건 저장 중 예외가 발생했습니다.');
      if (!mounted) {
        return null;
      }
      setState(() {
        _mobilityType = previousMobilityType;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이동 조건을 저장하지 못했어요. 이전 조건으로 되돌렸어요.')),
      );
      return null;
    }
    if (!mounted) {
      return null;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${mobilityPresetDisplayName(selectedPreset)} 조건으로 변경했습니다',
        ),
      ),
    );
    return selectedPreset;
  }
}

class _HomeNotificationButton extends StatelessWidget {
  const _HomeNotificationButton({
    required this.hasNotificationItems,
    required this.onPressed,
    super.key,
  });

  final bool hasNotificationItems;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hasNotificationItems ? '알림, 확인할 알림 있음' : '알림, 새 알림이 없어요',
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: '알림',
          child: Badge(
            isLabelVisible: hasNotificationItems,
            smallSize: 10,
            backgroundColor: EasySubwayAccessibleColors.red,
            offset: const Offset(-10, 10),
            child: IconButton.filledTonal(
              onPressed: onPressed,
              iconSize: 26,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                backgroundColor: Colors.white,
                foregroundColor: EasySubwayAccessibleColors.secondaryText,
                side: const BorderSide(
                  color: EasySubwayAccessibleColors.line,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: _mainIconControlRadius,
                ),
              ),
              icon: const Icon(Icons.notifications_none),
            ),
          ),
        ),
      ),
    );
  }
}
