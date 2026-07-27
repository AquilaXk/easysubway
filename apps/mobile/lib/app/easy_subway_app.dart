import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../accessible_design.dart';
import '../core/datapack/bundled_data_pack_freshness.dart';
import '../core/error/error_feedback.dart';
import '../core/datapack/data_pack_metered_consent_gate.dart';
import '../core/datapack/data_pack_update_state.dart';
import '../design_tokens.dart';
import '../facility_report.dart';
import '../favorite_facility.dart';
import '../features/account/presentation/user_data_deletion_screen.dart';
import '../features/ads/ad_repository.dart';
import '../features/get_off_alarm/get_off_alarm_controller.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/mobility_profile/mobility_profile_policy.dart';
import '../features/realtime/realtime_repository.dart';
import '../features/service_notice/data/notice_repository.dart';
import '../features/support/presentation/support_access_screen.dart';
import '../features/train_search/domain/train_search_models.dart';
import '../internal_route.dart';
import '../legacy_credential_cleanup.dart';
import '../mobile_error_reporter.dart';
import '../network_map.dart';
import '../notification_settings.dart';
import '../onboarding.dart';
import '../route_search.dart';
import '../station_search.dart';
import '../user_data_deletion.dart';
import 'accessibility_theme.dart';
import 'app_components.dart';
import 'app_dependencies.dart';
import 'demo_dependencies.dart';

const defaultDemoHomeDataEnabled = bool.fromEnvironment(
  'EASYSUBWAY_DEMO_HOME_DATA',
  defaultValue: false,
);

class EasySubwayApp extends StatelessWidget {
  EasySubwayApp({
    required AppDependencies dependencies,
    Future<List<FavoriteRoute>>? recentRoutesFuture,
    LegacyCredentialCleaner legacyCredentialCleaner =
        const NoLegacyCredentialCleaner(),
    OnboardingResultStore? onboardingStore,
    FacilityReportDraftTargetStore? facilityReportDraftTargetStore,
    FacilityReportLostPhotoRestorer? facilityReportLostPhotoRestorer,
    SupportAccessInfo supportAccessInfo =
        const SupportAccessInfo.fromEnvironment(),
    SupportAccessLauncher supportAccessLauncher =
        const UrlLauncherSupportAccessLauncher(),
    DataPackUpdateStateRepository? dataPackUpdateStateRepository,
    Future<void> Function()? onDataPackMeteredConsent,
    Future<void>? dataPackUpdate,
    BundledDataPackFreshness? bundledDataPackFreshness,
    OnboardingState initialOnboardingState = const OnboardingState.initial(),
    GlobalKey<NavigatorState>? navigatorKey,
    Key? key,
  }) : this._(
         dependencies: dependencies,
         initialOnboardingState: initialOnboardingState,
         onboardingStore: onboardingStore,
         facilityReportDraftTargetStore: facilityReportDraftTargetStore,
         facilityReportLostPhotoRestorer: facilityReportLostPhotoRestorer,
         legacyCredentialCleaner: legacyCredentialCleaner,
         supportAccessInfo: supportAccessInfo.validatedForBuild(
           isReleaseMode: kReleaseMode,
         ),
         supportAccessLauncher: supportAccessLauncher,
         dataPackUpdateStateRepository: dataPackUpdateStateRepository,
         onDataPackMeteredConsent: onDataPackMeteredConsent,
         dataPackUpdate: dataPackUpdate,
         bundledDataPackFreshness: bundledDataPackFreshness,
         recentRoutesFuture:
             recentRoutesFuture ??
             (defaultDemoHomeDataEnabled
                 ? const DemoFavoriteRouteRepository().listFavoriteRoutes()
                 : null),
         navigatorKey: navigatorKey,
         key: key,
       );

  EasySubwayApp._({
    required AppDependencies dependencies,
    required this.initialOnboardingState,
    required this.onboardingStore,
    required this.facilityReportDraftTargetStore,
    required this.facilityReportLostPhotoRestorer,
    required this.legacyCredentialCleaner,
    required this.supportAccessInfo,
    required this.supportAccessLauncher,
    required this.dataPackUpdateStateRepository,
    required this.onDataPackMeteredConsent,
    required this.dataPackUpdate,
    required this.bundledDataPackFreshness,
    required this.recentRoutesFuture,
    this.navigatorKey,
    super.key,
  }) : repository = dependencies.repository,
       reportRepository = dependencies.reportRepository,
       routeRepository = dependencies.routeRepository,
       routeFeedbackRepository = dependencies.routeFeedbackRepository,
       favoriteRepository = dependencies.favoriteRepository,
       favoriteFacilityRepository = dependencies.favoriteFacilityRepository,
       favoriteRouteRepository = dependencies.favoriteRouteRepository,
       adRepository = dependencies.adRepository,
       searchHistoryRepository = dependencies.searchHistoryRepository,
       internalRouteRepository = dependencies.internalRouteRepository,
       networkMapRepository = dependencies.networkMapRepository,
       networkMapViewportRepository = dependencies.networkMapViewportRepository,
       realtimeRepository = dependencies.realtimeRepository,
       notificationRepository = dependencies.notificationRepository,
       notificationPermissionProvider =
           dependencies.notificationPermissionProvider,
       locationProvider = dependencies.locationProvider,
       trainSearchRepository = dependencies.trainSearchRepository,
       userDataDeletionRepository = dependencies.userDataDeletionRepository,
       getOffAlarmController = dependencies.getOffAlarmController,
       noticeRepository = dependencies.noticeRepository;

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
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
  final UserDataDeletionRepository? userDataDeletionRepository;
  final GetOffAlarmController? getOffAlarmController;
  final NoticeRepository? noticeRepository;
  final OnboardingState initialOnboardingState;
  final OnboardingResultStore? onboardingStore;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final FacilityReportLostPhotoRestorer? facilityReportLostPhotoRestorer;
  final LegacyCredentialCleaner legacyCredentialCleaner;
  final SupportAccessInfo supportAccessInfo;
  final SupportAccessLauncher supportAccessLauncher;
  final DataPackUpdateStateRepository? dataPackUpdateStateRepository;
  final Future<void> Function()? onDataPackMeteredConsent;
  final Future<void>? dataPackUpdate;
  final BundledDataPackFreshness? bundledDataPackFreshness;
  final Future<List<FavoriteRoute>>? recentRoutesFuture;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'EasySubway',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const EasySubwayScrollBehavior(),
      theme: ThemeData(
        // fromSeed 파생색 대신 시그니처 역할색을 명시해 JSON 색 계약을 유지한다.
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: EasySubwayAccessibleColors.interactionPrimary,
            ).copyWith(
              primary: EasySubwayAccessibleColors.interactionPrimary,
              onPrimary: EasySubwayAccessibleColors.interactionOnPrimary,
              secondary: EasySubwayAccessibleColors.interactionSecondarySurface,
              onSecondary: EasySubwayAccessibleColors.interactionOnBrand,
              secondaryContainer:
                  EasySubwayAccessibleColors.interactionSecondaryPressedSurface,
              onSecondaryContainer:
                  EasySubwayAccessibleColors.interactionOnBrand,
              surface: EasySubwayAccessibleColors.surfaceDefault,
              onSurface: EasySubwayAccessibleColors.contentPrimary,
              onSurfaceVariant: EasySubwayAccessibleColors.contentSecondary,
              outline: EasySubwayAccessibleColors.borderSubtle,
              outlineVariant: EasySubwayAccessibleColors.borderSubtle,
              error: EasySubwayAccessibleColors.statusDangerContent,
              onError: EasySubwayAccessibleColors.interactionOnPrimary,
              errorContainer: EasySubwayAccessibleColors.statusDangerSurface,
              onErrorContainer: EasySubwayAccessibleColors.statusDangerContent,
            ),
        extensions: const [EasySubwayTokens.light],
        textTheme: easySubwayTextTheme(ThemeData(useMaterial3: true).textTheme),
        scaffoldBackgroundColor: EasySubwayAccessibleColors.surfaceScaffold,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          toolbarHeight: 64,
          // 평평한 상단바: Material3 surfaceTint(액센트 기반 청록 스크림)와
          // 스크롤 elevation 그림자를 끈다. 경계는 화면별 얇은 구분선으로만.
          backgroundColor: EasySubwayAccessibleColors.surfaceBrandChrome,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: EasySubwayAccessibleColors.contentPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        // 주 행동(채움)만 강하게: 높이 60, 진한 채움.
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(EasySubwayTouchTarget.primary),
            shape: const RoundedRectangleBorder(
              borderRadius: mainThemeControlRadius,
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        // 보조 행동은 조용하게: 중립 얇은 보더(line 토큰) + primary 텍스트,
        // 높이는 접근성 최소(56). 고대비 대비는 _themeForPreferences에서 보정.
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(EasySubwayTouchTarget.general),
            foregroundColor: EasySubwayAccessibleColors.interactionOnBrand,
            side: const BorderSide(
              color: EasySubwayAccessibleColors.interactionSecondaryBorder,
              width: 1.5,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: mainThemeControlRadius,
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: DataPackMeteredConsentGate(
        stateRepository: dataPackUpdateStateRepository,
        onAccept: onDataPackMeteredConsent,
        recheckAfter: dataPackUpdate,
        child: _EasySubwayHome(
          repository: repository,
          reportRepository: reportRepository,
          routeRepository: routeRepository,
          routeFeedbackRepository: routeFeedbackRepository,
          getOffAlarmController: getOffAlarmController,
          favoriteRepository: favoriteRepository,
          favoriteFacilityRepository: favoriteFacilityRepository,
          favoriteRouteRepository: favoriteRouteRepository,
          adRepository: adRepository,
          searchHistoryRepository: searchHistoryRepository,
          internalRouteRepository: internalRouteRepository,
          networkMapRepository: networkMapRepository,
          networkMapViewportRepository: networkMapViewportRepository,
          realtimeRepository: realtimeRepository,
          notificationRepository: notificationRepository,
          notificationPermissionProvider: notificationPermissionProvider,
          locationProvider: locationProvider,
          trainSearchRepository: trainSearchRepository,
          initialOnboardingState: initialOnboardingState,
          onboardingStore: onboardingStore,
          facilityReportDraftTargetStore: facilityReportDraftTargetStore,
          facilityReportLostPhotoRestorer: facilityReportLostPhotoRestorer,
          legacyCredentialCleaner: legacyCredentialCleaner,
          supportAccessInfo: supportAccessInfo,
          supportAccessLauncher: supportAccessLauncher,
          userDataDeletionRepository: userDataDeletionRepository,
          noticeRepository: noticeRepository,
          recentRoutesFuture: recentRoutesFuture,
          bundledDataPackFreshness: bundledDataPackFreshness,
        ),
      ),
    );
  }
}

class EasySubwayScrollBehavior extends MaterialScrollBehavior {
  const EasySubwayScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// 앱 시작 시 온보딩 상태를 복원하는 짧은 구간에 보여주는 화면.
///
/// 예전에는 흰 배경 + 스피너만 떠서 네이티브 스플래시(브랜드)에서 홈으로 가는
/// 사이에 흰 화면이 튀어 첫인상을 해쳤다(#1785). 그래서 브랜드 색(당시 파랑)과
/// 앱 이름을 그대로 잇는 풀스크린 화면을 넣었었다. 이후 #1915에서 색 체계가
/// 파랑에서 차콜로 바뀌면서, 이 풀스크린 화면 자체가 "흰 네이티브 스플래시 →
/// 차콜 화면 → 흰 홈 화면" 순으로 색이 튀는 새로운 플래시 버그가 되었다.
///
/// 지금은 화면을 홈/네이티브 스플래시와 동일한 흰 배경으로 맞추고, 복원이
/// 매우 빠르게 끝나는 일반적인 경우에는 아무 시각 요소도 그리지 않아
/// 지각적으로(perceptually) 아예 보이지 않도록 한다. 복원이 드물게 느려질
/// 때만(300ms 초과) 작은 스피너를 표시해 사용자가 대기 상태를 인지하게 한다.
/// 스크린리더용 안내(Semantics)는 시각 스피너와 무관하게 위젯 빌드 즉시
/// 트리에 존재한다.
class _StartupLoadingScreen extends StatefulWidget {
  const _StartupLoadingScreen();

  @override
  State<_StartupLoadingScreen> createState() => _StartupLoadingScreenState();
}

class _StartupLoadingScreenState extends State<_StartupLoadingScreen> {
  static const _spinnerDelay = Duration(milliseconds: 300);

  Timer? _spinnerDelayTimer;
  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();
    _spinnerDelayTimer = Timer(_spinnerDelay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showSpinner = true;
      });
    });
  }

  @override
  void dispose() {
    _spinnerDelayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('startupLoadingScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      body: SafeArea(
        child: Center(
          child: Semantics(
            label: '쉬운 지하철을 불러오는 중',
            liveRegion: true,
            child: ExcludeSemantics(
              child: SizedBox(
                width: 26,
                height: 26,
                child: _showSpinner
                    ? const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          EasySubwayAccessibleColors.mutedText,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EasySubwayHome extends StatefulWidget {
  const _EasySubwayHome({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.routeFeedbackRepository,
    required this.getOffAlarmController,
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    required this.adRepository,
    required this.searchHistoryRepository,
    required this.internalRouteRepository,
    required this.networkMapRepository,
    required this.networkMapViewportRepository,
    required this.realtimeRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.locationProvider,
    required this.trainSearchRepository,
    required this.initialOnboardingState,
    required this.onboardingStore,
    required this.facilityReportDraftTargetStore,
    required this.facilityReportLostPhotoRestorer,
    required this.legacyCredentialCleaner,
    required this.supportAccessInfo,
    required this.supportAccessLauncher,
    required this.userDataDeletionRepository,
    required this.noticeRepository,
    required this.recentRoutesFuture,
    required this.bundledDataPackFreshness,
  });

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
  final OnboardingState initialOnboardingState;
  final OnboardingResultStore? onboardingStore;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final FacilityReportLostPhotoRestorer? facilityReportLostPhotoRestorer;
  final LegacyCredentialCleaner legacyCredentialCleaner;
  final SupportAccessInfo supportAccessInfo;
  final SupportAccessLauncher supportAccessLauncher;
  final UserDataDeletionRepository? userDataDeletionRepository;
  final NoticeRepository? noticeRepository;
  final Future<List<FavoriteRoute>>? recentRoutesFuture;
  final BundledDataPackFreshness? bundledDataPackFreshness;

  @override
  State<_EasySubwayHome> createState() => _EasySubwayHomeState();
}

class _EasySubwayHomeState extends State<_EasySubwayHome>
    with WidgetsBindingObserver {
  // 저장소가 없는 테스트/프리뷰에서도 같은 앱 세션에서는 온보딩 완료 상태를 유지한다.
  late OnboardingState _onboardingState = widget.initialOnboardingState;
  late bool _loadingOnboardingState =
      widget.onboardingStore != null &&
      !widget.initialOnboardingState.isCompleted;
  bool _startScreenDismissed = false;
  bool _pendingFacilityReportPhotoRecoveryStarted = false;
  bool _savingOnboardingResult = false;
  OnboardingResult? _pendingOnboardingResult;
  final _pendingOnboardingSaveCompleters = <Completer<void>>[];
  late OnboardingResult? _lastPersistedOnboardingResult =
      widget.initialOnboardingState.result;
  UserDataDeletionResult? _dataDeletionResult;
  Timer? _bundledFreshnessTimer;
  bool _bundledDataPackStale = false;

  @override
  void initState() {
    super.initState();
    _initializeBundledFreshness();
    unawaited(_clearLegacyCredentialsOnStartup());
    if (_loadingOnboardingState) {
      _restoreOnboardingState();
    }
    _schedulePendingFacilityReportPhotoRecovery();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingOnboardingState) {
      // 스플래시와 홈 사이에 색이 튀지 않도록 흰 배경을 그대로 이어가며, 복원이
      // 빠르게 끝나는 일반적인 경우에는 스피너조차 그리지 않는다(#1785, #1915).
      return const _StartupLoadingScreen();
    }

    final dataDeletionResult = _dataDeletionResult;
    if (dataDeletionResult != null) {
      return UserDataDeletionResultScreen(
        onRestart: () {
          setState(() {
            _dataDeletionResult = null;
          });
        },
      );
    }

    if (!_onboardingState.isCompleted) {
      if (!_startScreenDismissed) {
        return StartScreen(
          onStart: () {
            setState(() {
              _startScreenDismissed = true;
            });
          },
        );
      }
      // #1936: 장황한 중간 소개 화면(OnboardingIntroScreen)을 제거했다. 시작 화면
      // 다음은 곧바로 이동 방식 프리셋 → 권한 단계로 이어진다.
      return OnboardingScreen(
        locationProvider: widget.locationProvider,
        notificationPermissionProvider: widget.notificationPermissionProvider,
        onCompleted: (result) async {
          await _completeOnboarding(result);
        },
      );
    }

    final onboardingResult = _onboardingState.result;
    final preferences =
        onboardingResult?.preferences ??
        const OnboardingViewPreferences.defaults();

    return OnboardingPreferenceScope(
      preferences: preferences,
      child: HomeScreen(
        repository: widget.repository,
        reportRepository: widget.reportRepository,
        routeRepository: widget.routeRepository,
        routeFeedbackRepository: widget.routeFeedbackRepository,
        getOffAlarmController: widget.getOffAlarmController,
        favoriteRepository: widget.favoriteRepository,
        favoriteFacilityRepository: widget.favoriteFacilityRepository,
        favoriteRouteRepository: widget.favoriteRouteRepository,
        adRepository: widget.adRepository,
        searchHistoryRepository: widget.searchHistoryRepository,
        internalRouteRepository: widget.internalRouteRepository,
        networkMapRepository: widget.networkMapRepository,
        networkMapViewportRepository: widget.networkMapViewportRepository,
        realtimeRepository: widget.realtimeRepository,
        notificationRepository: widget.notificationRepository,
        notificationPermissionProvider: widget.notificationPermissionProvider,
        locationProvider: widget.locationProvider,
        trainSearchRepository: widget.trainSearchRepository,
        initialMobilityType: onboardingResult?.mobilityType,
        viewPreferences: preferences,
        simpleViewEnabled: preferences.simpleViewEnabled,
        facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
        supportAccessInfo: widget.supportAccessInfo,
        supportAccessLauncher: widget.supportAccessLauncher,
        userDataDeletionRepository: widget.userDataDeletionRepository,
        noticeRepository: widget.noticeRepository,
        recentRoutesFuture: widget.recentRoutesFuture,
        bundledDataPackStaleLabel: _bundledDataPackStale
            ? BundledDataPackFreshness.staleLabelKo
            : null,
        onUserDataDeleted: _handleUserDataDeleted,
        onMobilityProfileChanged: _saveMobilityProfile,
        onViewPreferencesChanged: _saveViewPreferences,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBundledFreshness();
    }
  }

  @override
  void dispose() {
    _bundledFreshnessTimer?.cancel();
    if (widget.bundledDataPackFreshness != null) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  void _initializeBundledFreshness() {
    final freshness = widget.bundledDataPackFreshness;
    if (freshness == null) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    final now = DateTime.now().toUtc();
    _bundledDataPackStale = freshness.isStaleAt(now);
    _scheduleBundledFreshnessExpiry(freshness, now);
  }

  void _refreshBundledFreshness() {
    final freshness = widget.bundledDataPackFreshness;
    if (freshness == null) {
      return;
    }
    final now = DateTime.now().toUtc();
    final stale = freshness.isStaleAt(now);
    if (stale != _bundledDataPackStale && mounted) {
      setState(() {
        _bundledDataPackStale = stale;
      });
    }
    _scheduleBundledFreshnessExpiry(freshness, now);
  }

  void _scheduleBundledFreshnessExpiry(
    BundledDataPackFreshness freshness,
    DateTime now,
  ) {
    _bundledFreshnessTimer?.cancel();
    if (_bundledDataPackStale) {
      return;
    }
    final delay = freshness.freshnessExpiresAt.toUtc().difference(now);
    if (delay <= Duration.zero) {
      _refreshBundledFreshness();
      return;
    }
    _bundledFreshnessTimer = Timer(delay, () {
      if (!mounted || _bundledDataPackStale) {
        return;
      }
      setState(() {
        _bundledDataPackStale = true;
      });
    });
  }

  Future<void> _handleUserDataDeleted(UserDataDeletionResult result) async {
    try {
      await widget.legacyCredentialCleaner.clear();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '정보 삭제 후 기존 익명 인증 저장값을 정리하는 중 예외가 발생했습니다.',
      );
    }
    await widget.onboardingStore?.clearResult();
    await widget.facilityReportDraftTargetStore?.clearTarget();
    if (!mounted) {
      return;
    }
    setState(() {
      _onboardingState = const OnboardingState.initial();
      _lastPersistedOnboardingResult = null;
      _loadingOnboardingState = false;
      _startScreenDismissed = false;
      _dataDeletionResult = result;
    });
  }

  Future<void> _clearLegacyCredentialsOnStartup() async {
    try {
      await widget.legacyCredentialCleaner.clear();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '기존 익명 인증 저장값을 정리하는 중 예외가 발생했습니다.',
      );
    }
  }

  Future<void> _restoreOnboardingState() async {
    OnboardingResult? storedResult;
    try {
      storedResult = await widget.onboardingStore?.readResult();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '온보딩 설정을 불러오는 중 예외가 발생했습니다.',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _onboardingState = storedResult == null
          ? const OnboardingState.initial()
          : OnboardingState.completed(result: storedResult);
      _lastPersistedOnboardingResult = storedResult;
      _loadingOnboardingState = false;
    });
    _schedulePendingFacilityReportPhotoRecovery();
  }

  Future<void> _persistOnboardingResult(OnboardingResult result) async {
    try {
      await widget.onboardingStore?.saveResult(result);
      _lastPersistedOnboardingResult = result;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '온보딩 설정을 저장하는 중 예외가 발생했습니다.',
      );
      rethrow;
    }
  }

  Future<void> _completeOnboarding(OnboardingResult result) async {
    final previousOnboardingState = _onboardingState;
    final previousStartScreenDismissed = _startScreenDismissed;
    try {
      await _saveOnboardingResult(result);
    } catch (error, stackTrace) {
      assert(() {
        Object.hash(error, stackTrace);
        return true;
      }());
      if (!mounted) {
        return;
      }
      if (_isSameOnboardingResult(_onboardingState.result, result)) {
        setState(() {
          _onboardingState = previousOnboardingState;
          _startScreenDismissed = previousStartScreenDismissed;
        });
      }
      showAnnouncedErrorSnackBar(context, '설정을 저장하지 못했어요. 다시 시도해 주세요.');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _onboardingState = OnboardingState.completed(result: result);
    });
    _schedulePendingFacilityReportPhotoRecovery();
  }

  Future<void> _saveOnboardingResult(OnboardingResult result) async {
    final saveCompleter = Completer<void>();
    _pendingOnboardingResult = result;
    _pendingOnboardingSaveCompleters.add(saveCompleter);
    _applyOnboardingResult(result);
    if (_savingOnboardingResult) {
      return saveCompleter.future;
    }
    _savingOnboardingResult = true;
    try {
      while (mounted) {
        final nextResult = _pendingOnboardingResult;
        final nextCompleters = List<Completer<void>>.of(
          _pendingOnboardingSaveCompleters,
        );
        _pendingOnboardingResult = null;
        _pendingOnboardingSaveCompleters.clear();
        if (nextResult == null) {
          break;
        }
        try {
          await _persistOnboardingResult(nextResult);
          for (final completer in nextCompleters) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        } catch (error, stackTrace) {
          if (_pendingOnboardingResult != null) {
            _pendingOnboardingSaveCompleters.insertAll(0, nextCompleters);
          } else {
            _restoreLastPersistedOnboardingResult();
            for (final completer in nextCompleters.reversed) {
              if (!completer.isCompleted) {
                completer.completeError(error, stackTrace);
              }
            }
          }
        }
      }
    } finally {
      for (final completer in _pendingOnboardingSaveCompleters) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      _pendingOnboardingResult = null;
      _pendingOnboardingSaveCompleters.clear();
      _savingOnboardingResult = false;
    }
    return saveCompleter.future;
  }

  Future<void> _saveMobilityProfile(MobilityPreset preset) async {
    final currentResult = _onboardingState.result;
    if (currentResult == null) {
      return;
    }
    final nextResult = OnboardingResult(
      preset: preset,
      preferences: currentResult.preferences,
    );
    try {
      await _saveOnboardingResult(nextResult);
    } catch (error, stackTrace) {
      if (_isSameOnboardingResult(_onboardingState.result, nextResult)) {
        _applyOnboardingResult(currentResult);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _saveViewPreferences(
    OnboardingViewPreferences preferences,
  ) async {
    final currentResult = _onboardingState.result;
    if (currentResult == null) {
      return;
    }
    final nextResult = OnboardingResult(
      preset: currentResult.preset,
      preferences: preferences,
    );
    try {
      await _saveOnboardingResult(nextResult);
    } catch (error, stackTrace) {
      if (_isSameOnboardingResult(_onboardingState.result, nextResult)) {
        _applyOnboardingResult(currentResult);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _applyOnboardingResult(OnboardingResult result) {
    if (!mounted) {
      return;
    }
    setState(() {
      _onboardingState = OnboardingState.completed(result: result);
    });
  }

  void _restoreLastPersistedOnboardingResult() {
    final persistedResult = _lastPersistedOnboardingResult;
    if (persistedResult == null) {
      return;
    }
    _applyOnboardingResult(persistedResult);
  }

  bool _isSameOnboardingResult(OnboardingResult? left, OnboardingResult right) {
    return left != null &&
        left.preset == right.preset &&
        _isSameViewPreferences(left.preferences, right.preferences);
  }

  void _schedulePendingFacilityReportPhotoRecovery() {
    if (_pendingFacilityReportPhotoRecoveryStarted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_recoverPendingFacilityReportPhoto());
    });
  }

  Future<void> _recoverPendingFacilityReportPhoto() async {
    if (!mounted ||
        _pendingFacilityReportPhotoRecoveryStarted ||
        _loadingOnboardingState ||
        !_onboardingState.isCompleted) {
      return;
    }

    final draftTargetStore = widget.facilityReportDraftTargetStore;
    final lostPhotoRestorer = widget.facilityReportLostPhotoRestorer;
    if (draftTargetStore == null || lostPhotoRestorer == null) {
      return;
    }
    _pendingFacilityReportPhotoRecoveryStarted = true;

    FacilityReportTarget? target;
    FacilityReportPhotoAttachment? photoAttachment;
    try {
      target = await draftTargetStore.readTarget();
      if (target == null) {
        return;
      }

      photoAttachment = await lostPhotoRestorer();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '앱 시작 시 시설 제보 사진 복구 중 예외가 발생했습니다.',
      );
      await _clearFacilityReportDraftTargetQuietly(draftTargetStore);
      return;
    }

    await _clearFacilityReportDraftTargetQuietly(draftTargetStore);

    if (!mounted || photoAttachment == null) {
      return;
    }

    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FacilityReportScreen(
            repository: widget.reportRepository,
            target: target!,
            locationLoader: _facilityReportLocationLoader(
              widget.locationProvider,
            ),
            needsLocationPermissionRequest:
                widget.locationProvider.needsLocationPermissionRequest,
            openLocationSettings: widget.locationProvider.openLocationSettings,
            draftTargetStore: draftTargetStore,
            initialPhotoAttachment: photoAttachment,
          ),
        ),
      ),
    );
  }

  Future<void> _clearFacilityReportDraftTargetQuietly(
    FacilityReportDraftTargetStore draftTargetStore,
  ) async {
    try {
      await draftTargetStore.clearTarget();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 사진 복구 대상 정리 중 예외가 발생했습니다.',
      );
    }
  }
}

FacilityReportLocationLoader _facilityReportLocationLoader(
  CurrentLocationProvider provider,
) {
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

bool _isSameViewPreferences(
  OnboardingViewPreferences left,
  OnboardingViewPreferences right,
) {
  return left.highContrastEnabled == right.highContrastEnabled &&
      left.simpleViewEnabled == right.simpleViewEnabled;
}
