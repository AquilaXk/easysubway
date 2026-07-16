import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accessible_design.dart';
import 'app/accessibility_theme.dart';
import 'app/app_components.dart';
import 'app/app_bootstrap.dart';
import 'app/app_dependencies.dart';
import 'app/demo_dependencies.dart';
import 'core/datapack/data_pack_metered_consent_gate.dart';
import 'core/datapack/bundled_data_pack_freshness.dart';
import 'core/datapack/data_pack_update_state.dart';
import 'design_tokens.dart';
import 'features/get_off_alarm/get_off_alarm_controller.dart';
import 'features/ads/ad_repository.dart';
import 'features/home_widget/home_widget_link_handler.dart';
import 'features/home_widget/next_train_widget_repository.dart';
import 'features/home_widget/next_train_widget_runtime.dart'
    as next_train_widget_runtime;
import 'facility_report.dart';
import 'favorite_facility.dart';
import 'features/realtime/realtime_repository.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'features/mobility_profile/mobility_preset_labels.dart';
import 'features/mobility_profile/mobility_preset_picker.dart';
import 'features/mobility_profile/mobility_profile_policy.dart';
import 'features/notifications/presentation/notification_inbox_screen.dart';
import 'internal_route.dart';
import 'legacy_credential_cleanup.dart';
import 'network_map.dart';
import 'notification_settings.dart';
import 'features/service_notice/data/notice_repository.dart';
import 'features/service_notice/presentation/notice_controller.dart';
import 'features/service_notice/presentation/service_notice_banner.dart';
import 'features/service_notice/presentation/service_notice_list_screen.dart';
import 'onboarding.dart';
import 'route_search.dart';
import 'station_search.dart';
import 'mobile_error_reporter.dart';
import 'user_data_deletion.dart';

export 'app/app_components.dart' show FeatureTile;
export 'features/notifications/presentation/notification_inbox_screen.dart'
    show NotificationInboxScreen;

const defaultPushNotificationsEnabled = bool.fromEnvironment(
  'EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS',
  defaultValue: false,
);
const defaultDemoHomeDataEnabled = bool.fromEnvironment(
  'EASYSUBWAY_DEMO_HOME_DATA',
  defaultValue: false,
);
const _settingsPagePadding = EdgeInsets.fromLTRB(20, 16, 20, 32);
const _mainIconControlRadius = BorderRadius.all(Radius.circular(12));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  validateReleaseBuildFlags(
    isReleaseMode: kReleaseMode,
    demoHomeDataEnabled: defaultDemoHomeDataEnabled,
  );
  final bootstrap = await AppBootstrap.initialize(
    enablePushNotifications: defaultPushNotificationsEnabled,
    favoriteRepository: defaultDemoHomeDataEnabled
        ? const DemoFavoriteStationRepository()
        : null,
    favoriteFacilityRepository: defaultDemoHomeDataEnabled
        ? const DemoFavoriteFacilityRepository()
        : null,
    favoriteRouteRepository: defaultDemoHomeDataEnabled
        ? const DemoFavoriteRouteRepository()
        : null,
    searchHistoryRepository: defaultDemoHomeDataEnabled
        ? DemoSearchHistoryRepository()
        : null,
  );
  await restoreGetOffAlarmState(bootstrap.dependencies.getOffAlarmController);
  final nextTrainWidgetRepository = NextTrainWidgetRepository(
    catalogDatabase: bootstrap.catalogDatabase,
    userDatabase: bootstrap.userDatabase,
  );
  await next_train_widget_runtime.runNextTrainWidgetStartup(
    installedWidgetIds: next_train_widget_runtime.installedNextTrainWidgetIds,
    registerRefresh: next_train_widget_runtime.initializeNextTrainWidgetRefresh,
    cancelRefresh: next_train_widget_runtime.cancelNextTrainWidgetRefresh,
    refresh: (widgetIds) => next_train_widget_runtime.refreshNextTrainWidgets(
      nextTrainWidgetRepository,
      widgetIds: widgetIds,
    ),
    reportError: (error, stackTrace) =>
        reportMobileError(error, stackTrace, context: '홈 위젯 초기화 중 예외가 발생했습니다.'),
  );
  final photoPicker = ImagePickerFacilityReportPhotoPicker();
  final navigatorKey = GlobalKey<NavigatorState>();
  final onboardingStore = const SecureOnboardingResultStore();
  final draftTargetStore = const SecureFacilityReportDraftTargetStore();
  runApp(
    AppBootstrapLifecycle(
      close: bootstrap.close,
      resumeDataPackUpdate: () async {
        await bootstrap.resumeDataPackUpdate();
        await next_train_widget_runtime.runNextTrainWidgetOperationSafely(
          operation: () => next_train_widget_runtime.refreshNextTrainWidgets(
            nextTrainWidgetRepository,
          ),
          reportError: (error, stackTrace) => reportMobileError(
            error,
            stackTrace,
            context: '홈 위젯 갱신 중 예외가 발생했습니다.',
          ),
        );
      },
      resumeGetOffAlarmState: () => reconcileGetOffAlarmState(
        bootstrap.dependencies.getOffAlarmController,
      ),
      child: HomeWidgetLinkHandler(
        clicks: next_train_widget_runtime.homeWidgetClicks(),
        navigatorKey: navigatorKey,
        stationDetailBuilder: (stationId) => StationDetailScreen(
          repository: bootstrap.dependencies.repository,
          reportRepository: bootstrap.dependencies.reportRepository,
          favoriteRepository: bootstrap.dependencies.favoriteRepository,
          adRepository: bootstrap.dependencies.adRepository,
          realtimeRepository: bootstrap.dependencies.realtimeRepository,
          locationProvider: bootstrap.dependencies.locationProvider,
          stationId: stationId,
          facilityReportDraftTargetStore: draftTargetStore,
          internalRouteRepository:
              bootstrap.dependencies.internalRouteRepository,
        ),
        child: EasySubwayApp(
          navigatorKey: navigatorKey,
          dependencies: bootstrap.dependencies,
          onboardingStore: onboardingStore,
          facilityReportDraftTargetStore: draftTargetStore,
          facilityReportLostPhotoRestorer: photoPicker.retrieveLostPhoto,
          legacyCredentialCleaner: const SecureLegacyCredentialCleaner(),
          dataPackUpdateStateRepository: DataPackUpdateStateRepository(
            userDatabase: bootstrap.userDatabase,
          ),
          onDataPackMeteredConsent: bootstrap.acceptMeteredDataPackUpdate,
          dataPackUpdate: bootstrap.dataPackUpdate,
          bundledDataPackFreshness: bootstrap.bundledDataPackFreshness,
        ),
      ),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> configureMain() => next_train_widget_runtime.configureMain();

@visibleForTesting
Future<void> restoreGetOffAlarmState(GetOffAlarmController? controller) async {
  try {
    await controller?.restore();
  } catch (error, stackTrace) {
    reportMobileError(
      error,
      stackTrace,
      context: '하차 알림 시작 상태 복원 중 예외가 발생했습니다.',
    );
  }
}

@visibleForTesting
Future<void> reconcileGetOffAlarmState(
  GetOffAlarmController? controller,
) async {
  try {
    await controller?.reconcile();
  } catch (error, stackTrace) {
    reportMobileError(
      error,
      stackTrace,
      context: '하차 알림 foreground 상태 재조정 중 예외가 발생했습니다.',
    );
  }
}

void validateReleaseBuildFlags({
  required bool isReleaseMode,
  required bool demoHomeDataEnabled,
}) {
  if (isReleaseMode && demoHomeDataEnabled) {
    throw StateError('EASYSUBWAY_DEMO_HOME_DATA is not allowed in release.');
  }
}

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
        // fromSeed는 시드의 미세한 hue를 M3 톤 팔레트로 증폭해 액센트를 채도
        // 있는 색으로 만든다(무채색 시드도 청록끼로 샌다). 무채색 잉크 원칙을
        // 지키려 primary/secondary 계열을 명시적 무채색으로 덮어쓴다.
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: EasySubwayAccessibleColors.primary,
            ).copyWith(
              primary: EasySubwayAccessibleColors.primary,
              onPrimary: Colors.white,
              secondary: EasySubwayAccessibleColors.primary,
              onSecondary: Colors.white,
            ),
        extensions: const [EasySubwayTokens.light],
        textTheme: easySubwayTextTheme(ThemeData(useMaterial3: true).textTheme),
        scaffoldBackgroundColor: EasySubwayAccessibleColors.scaffoldSurface,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          toolbarHeight: 64,
          // 평평한 상단바: Material3 surfaceTint(액센트 기반 청록 스크림)와
          // 스크롤 elevation 그림자를 끈다. 경계는 화면별 얇은 구분선으로만.
          backgroundColor: EasySubwayAccessibleColors.scaffoldSurface,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: EasySubwayAccessibleColors.text,
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
            foregroundColor: EasySubwayAccessibleColors.primary,
            side: const BorderSide(
              color: EasySubwayAccessibleColors.line,
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

abstract interface class SupportAccessLauncher {
  Future<bool> open(Uri uri);
}

class UrlLauncherSupportAccessLauncher implements SupportAccessLauncher {
  const UrlLauncherSupportAccessLauncher();

  @override
  Future<bool> open(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class SupportAccessInfo {
  const SupportAccessInfo({
    required this.privacyPolicyUrl,
    required this.supportEmail,
    required this.dataDeletionEmail,
    this.securityEmail = '',
  });

  const SupportAccessInfo.fromEnvironment()
    : privacyPolicyUrl = const String.fromEnvironment(
        'EASYSUBWAY_PRIVACY_POLICY_URL',
      ),
      supportEmail = const String.fromEnvironment('EASYSUBWAY_SUPPORT_EMAIL'),
      dataDeletionEmail = const String.fromEnvironment(
        'EASYSUBWAY_DATA_DELETION_EMAIL',
      ),
      securityEmail = const String.fromEnvironment('EASYSUBWAY_SECURITY_EMAIL');

  final String privacyPolicyUrl;
  final String supportEmail;
  final String dataDeletionEmail;
  final String securityEmail;

  SupportAccessInfo validatedForBuild({required bool isReleaseMode}) {
    if (!isReleaseMode) {
      return this;
    }
    _validateHttpsUrl(label: 'privacy policy URL', value: privacyPolicyUrl);
    _validateEmail(label: 'support email', value: supportEmail);
    _validateEmail(label: 'data deletion email', value: dataDeletionEmail);
    _validateEmail(label: 'security email', value: securityEmail);
    return this;
  }

  static void _validateHttpsUrl({
    required String label,
    required String value,
  }) {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      throw StateError('Release $label must be configured.');
    }
    final uri = Uri.tryParse(normalizedValue);
    if (uri == null || uri.scheme != 'https') {
      throw StateError('Release $label must use HTTPS.');
    }
    if (uri.host.isEmpty) {
      throw StateError('Release $label must include a host.');
    }
  }

  static void _validateEmail({required String label, required String value}) {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      throw StateError('Release $label must be configured.');
    }
    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(normalizedValue)) {
      throw StateError('Release $label must be a valid email address.');
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장하지 못했어요. 다시 시도해 주세요.')),
      );
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
          _selectedTabIndex = 2;
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
        _selectedTabIndex = 0;
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
        _selectedTabIndex = 2;
      });
    }

    void openMoreTab() {
      if (_selectedTabIndex == 4) {
        return;
      }
      setState(() {
        _selectedTabIndex = 4;
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
        _selectedTabIndex = 3;
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
      String regionLabel, [
      StationSearchEntryMode entryMode = StationSearchEntryMode.search,
    ]) async {
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
            locationProvider: locationProvider,
            facilityReportDraftTargetStore: facilityReportDraftTargetStore,
            internalRouteRepository: internalRouteRepository,
            internalRouteMobilityType: initialMobilityType,
            realtimeRepository: realtimeRepository,
            routeDraftController: _routeDraftController,
            entryMode: entryMode,
            regionLabel: regionLabel,
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
    ) async {
      await Navigator.of(context).push(
        MaterialPageRoute<RouteDraftStation>(
          builder: (_) => StationSearchScreen(
            repository: repository,
            reportRepository: reportRepository,
            favoriteRepository: favoriteRepository,
            searchHistoryRepository: searchHistoryRepository,
            locationProvider: locationProvider,
            facilityReportDraftTargetStore: facilityReportDraftTargetStore,
            internalRouteRepository: internalRouteRepository,
            internalRouteMobilityType: initialMobilityType,
            realtimeRepository: realtimeRepository,
            routeDraftController: _routeDraftController,
            pickSlot: slot,
            regionLabel: regionLabel,
          ),
        ),
      );
      if (!context.mounted) {
        return;
      }
      await refreshHomeState();
    }

    void openDataSources() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const DataSourceAttributionScreen(),
        ),
      );
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
          onOpenStationSearch: (regionLabel) =>
              unawaited(openStationSearch(regionLabel)),
          onStationSearchClosed: () => unawaited(refreshHomeState()),
          onPickStationForSlot: (slot, regionLabel) =>
              unawaited(openStationSearchForSlot(slot, regionLabel)),
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
          onOpenNearbyStations: (regionLabel) => unawaited(
            openStationSearch(regionLabel, StationSearchEntryMode.nearby),
          ),
          onOpenSettings: openMoreTab,
          onOpenDataSources: openDataSources,
          onOpenServiceNotices: noticeController == null
              ? null
              : openServiceNotices,
          disruptionBanner: noticeController == null
              ? null
              : ServiceNoticeBanner(
                  controller: noticeController,
                  onOpenList: openServiceNotices,
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
          locationProvider: locationProvider,
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
          routeFeedbackRepository: routeFeedbackRepository,
          getOffAlarmController: getOffAlarmController,
          favoriteRouteRepository: favoriteRouteRepository,
          adRepository: adRepository,
          initialMobilityType: _routeTabMobilityType ?? initialMobilityType,
          initialTransportScope: _routeTabTransportScope,
          initialDraft: _routeDraftController.draft,
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
          onOpenMyReports: openMyReports,
        ),
      );
    }

    // 탭 셸(0~4)이 모든 경로를 처리하므로 여기까지 도달하지 않는다.
    return const SizedBox.shrink();
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

class _HomeSavedRouteCard extends StatelessWidget {
  const _HomeSavedRouteCard({
    required this.route,
    required this.onTap,
    this.onRemove,
  });

  final FavoriteRoute route;
  final VoidCallback onTap;
  // 즐겨찾기 목록에서 바로 삭제할 수 있게 오른쪽 액션을 준다. null이면 진입 화살표만.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final originName = _stationNameWithSuffix(route.originStationName);
    final destinationName = _stationNameWithSuffix(
      route.destinationStationName,
    );
    final tappable = Semantics(
      button: true,
      label:
          '즐겨찾기 경로, $originName에서 $destinationName까지, ${route.lineLabel}, ${route.mobilityLabel}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              const Icon(
                Icons.route_outlined,
                color: EasySubwayAccessibleColors.primary,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$originName → $destinationName',
                      style: const TextStyle(
                        color: EasySubwayAccessibleColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _HomeMiniBadge(route.lineLabel),
                        _HomeMiniBadge(route.mobilityLabel),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return AppCard(
      showBorder: true,
      child: Row(
        children: [
          Expanded(child: tappable),
          const SizedBox(width: 8),
          if (onRemove != null)
            IconButton(
              key: Key('favoriteRouteRemoveButton-${route.favoriteRouteId}'),
              onPressed: onRemove,
              icon: const Icon(
                Icons.delete_outline,
                color: EasySubwayAccessibleColors.mutedText,
              ),
              tooltip: '즐겨찾기 경로 삭제',
            )
          else
            const Icon(
              Icons.chevron_right,
              color: EasySubwayAccessibleColors.brand,
            ),
        ],
      ),
    );
  }
}

String _stationNameWithSuffix(String name) {
  return name.endsWith('역') ? name : '$name역';
}

class _HomeMiniBadge extends StatelessWidget {
  const _HomeMiniBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: EasySubwayAccessibleColors.surface,
      side: const BorderSide(color: EasySubwayAccessibleColors.line),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      labelStyle: const TextStyle(
        color: EasySubwayAccessibleColors.secondaryText,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    required this.currentPreset,
    required this.viewPreferences,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.onViewPreferencesChanged,
    required this.onOpenMobilityProfile,
    required this.onOpenSupportAccess,
    required this.onOpenMyReports,
    this.bottomNavigationBar,
    super.key,
  });

  final MobilityPreset currentPreset;
  final OnboardingViewPreferences viewPreferences;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final Future<void> Function(OnboardingViewPreferences preferences)
  onViewPreferencesChanged;
  final Future<MobilityPreset?> Function() onOpenMobilityProfile;
  final VoidCallback onOpenSupportAccess;
  final VoidCallback onOpenMyReports;
  final Widget? bottomNavigationBar;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late MobilityPreset _preset = widget.currentPreset;
  late OnboardingViewPreferences _viewPreferences = widget.viewPreferences;

  @override
  void didUpdateWidget(AppSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewPreferences != widget.viewPreferences) {
      _viewPreferences = widget.viewPreferences;
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingPreferenceScope(
      preferences: _viewPreferences,
      child: Scaffold(
        key: const Key('settingsScreen'),
        appBar: AppBar(title: const Text('더보기')),
        bottomNavigationBar: widget.bottomNavigationBar,
        body: SafeArea(
          child: ListView(
            padding: _settingsPagePadding,
            children: [
              _AppSettingsSection(
                key: const Key('settingsSection-mobility'),
                title: '이동 조건',
                children: [
                  _AppSettingsActionTile(
                    key: const Key('mobilityProfileButton'),
                    icon: Icons.directions_walk,
                    title: mobilityPresetDisplayName(_preset),
                    subtitle: mobilityPresetDescription(_preset),
                    onTap: () async {
                      final selected = await widget.onOpenMobilityProfile();
                      if (!mounted || selected == null) {
                        return;
                      }
                      setState(() {
                        _preset = selected;
                      });
                    },
                  ),
                ],
              ),
              _AppSettingsSection(
                key: const Key('settingsSection-reading'),
                title: '화면 및 접근성',
                children: [
                  _AppSettingsPreferenceTile(
                    key: const Key('simpleViewSettingsButton'),
                    icon: Icons.visibility_outlined,
                    title: '간편 보기',
                    subtitle: '필수 행동과 상태 안내를 먼저 보여줘요',
                    enabled: _viewPreferences.simpleViewEnabled,
                    onChanged: (value) {
                      _updateViewPreferences(
                        _viewPreferences.copyWith(simpleViewEnabled: value),
                      );
                    },
                  ),
                  _AppSettingsPreferenceTile(
                    key: const Key('highContrastSettingsButton'),
                    icon: Icons.contrast,
                    title: '고대비',
                    subtitle: '버튼과 상태 문구의 대비를 더 강하게 보여줘요',
                    enabled: _viewPreferences.highContrastEnabled,
                    onChanged: (value) {
                      _updateViewPreferences(
                        _viewPreferences.copyWith(highContrastEnabled: value),
                      );
                    },
                  ),
                ],
              ),
              // 오프라인 안내 섹션·화면은 완전히 제거됐다(#1570): 오프라인 동작은
              // 설명 없이 그냥 되는 것이고, 데이터·지도 출처는 도움말·문의 하위에 이미 있다.
              if (widget.notificationRepository != null)
                _AppSettingsSection(
                  key: const Key('settingsSection-notification'),
                  title: '알림',
                  children: [
                    _AppSettingsActionTile(
                      key: const Key('notificationSettingsButton'),
                      icon: Icons.notifications_active_outlined,
                      title: '알림 설정',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => NotificationSettingsScreen(
                              repository: widget.notificationRepository!,
                              notificationPermissionProvider:
                                  widget.notificationPermissionProvider,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              _AppSettingsSection(
                key: const Key('settingsSection-activity'),
                title: '내 활동',
                children: [
                  _AppSettingsActionTile(
                    key: const Key('myReportsSettingsButton'),
                    icon: Icons.receipt_long_outlined,
                    title: '내 제보',
                    onTap: widget.onOpenMyReports,
                  ),
                ],
              ),
              _AppSettingsSection(
                key: const Key('settingsSection-help-privacy'),
                title: '개인정보 및 도움말',
                children: [
                  _AppSettingsActionTile(
                    key: const Key('settingsSupportPrivacyButton'),
                    icon: Icons.help_outline,
                    title: '도움말·문의',
                    onTap: widget.onOpenSupportAccess,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateViewPreferences(
    OnboardingViewPreferences preferences,
  ) async {
    final previous = _viewPreferences;
    setState(() {
      _viewPreferences = preferences;
    });
    try {
      await widget.onViewPreferencesChanged(preferences);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '설정 화면 보기 옵션 저장 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      if (_isSameViewPreferences(_viewPreferences, preferences)) {
        setState(() {
          _viewPreferences = previous;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장하지 못했어요. 이전 값으로 되돌렸어요.')),
      );
    }
  }
}

class _AppSettingsSection extends StatelessWidget {
  const _AppSettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: textTheme.titleMedium?.copyWith(
                color: EasySubwayAccessibleColors.text,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _AppSettingsActionTile extends StatelessWidget {
  const _AppSettingsActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  // 제목만으로 자명한 행은 회색 부가설명을 생략한다(#1570).
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Semantics(
      button: true,
      label: subtitle == null ? title : '$title, $subtitle',
      onTap: onTap,
      child: ExcludeSemantics(
        child: ListTile(
          onTap: onTap,
          minVerticalPadding: 12,
          minLeadingWidth: 32,
          leading: Icon(icon, color: EasySubwayAccessibleColors.primary),
          title: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.mutedText,
                    height: 1.3,
                  ),
                ),
          trailing: const Icon(Icons.chevron_right),
          shape: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppSettingsPreferenceTile extends StatelessWidget {
  const _AppSettingsPreferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = enabled ? '켜짐' : '꺼짐';
    final action = enabled ? '끄기' : '켜기';
    return Semantics(
      label: '$title, $value, $subtitle, 두 번 탭해 $action',
      toggled: enabled,
      onTap: () => onChanged(!enabled),
      child: ExcludeSemantics(
        child: ListTile(
          onTap: () => onChanged(!enabled),
          minVerticalPadding: 12,
          minLeadingWidth: 32,
          leading: Icon(icon, color: EasySubwayAccessibleColors.primary),
          title: Text(
            title,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.mutedText,
              height: 1.3,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: enabled,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: EasySubwayAccessibleColors.switchActiveTrack,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor:
                    EasySubwayAccessibleColors.switchInactiveTrack,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ],
          ),
          shape: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class FavoriteHomeScreen extends StatefulWidget {
  const FavoriteHomeScreen({
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    this.adRepository,
    required this.stationRepository,
    required this.reportRepository,
    required this.locationProvider,
    required this.facilityReportDraftTargetStore,
    required this.internalRouteRepository,
    required this.realtimeRepository,
    required this.routeDraftController,
    required this.initialMobilityType,
    this.onOpenRouteSearch,
    this.bottomNavigationBar,
    super.key,
  });

  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final AdRepository? adRepository;
  final StationSearchRepository stationRepository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository internalRouteRepository;
  final RealtimeRepository realtimeRepository;
  final RouteDraftController routeDraftController;
  final String initialMobilityType;
  final Future<void> Function([
    String? mobilityType,
    RouteTransportScope? transportScope,
  ])?
  onOpenRouteSearch;
  final Widget? bottomNavigationBar;

  @override
  State<FavoriteHomeScreen> createState() => _FavoriteHomeScreenState();
}

class _FavoriteHomeScreenState extends State<FavoriteHomeScreen> {
  late Future<_FavoriteHomeData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('favoriteHomeScreen'),
      appBar: AppBar(title: const Text('즐겨찾기')),
      bottomNavigationBar: widget.bottomNavigationBar,
      body: SafeArea(
        child: FutureBuilder<_FavoriteHomeData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data ?? const _FavoriteHomeData();
            final hasError = snapshot.hasError;
            return RefreshIndicator(
              onRefresh: () async {
                final next = _loadData();
                setState(() {
                  _dataFuture = next;
                });
                try {
                  await next;
                } catch (error, stackTrace) {
                  reportMobileError(
                    error,
                    stackTrace,
                    context: '즐겨찾기 새로고침 중 예외가 발생했습니다.',
                  );
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: mainListPagePadding,
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator(minHeight: 3),
                  if (hasError)
                    HomeStateCard(
                      key: const Key('favoriteHomeErrorState'),
                      icon: Icons.error_outline,
                      title: '즐겨찾기를 불러오지 못했어요',
                      subtitle: '잠시 후 다시 불러와 주세요.',
                      actionLabel: '다시 시도',
                      onAction: () {
                        setState(() {
                          _dataFuture = _loadData();
                        });
                      },
                    )
                  else if (data.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: AppCard(
                        child: AppInfoRow(
                          icon: Icons.bookmark_border,
                          iconColor: EasySubwayAccessibleColors.mutedText,
                          title: '즐겨찾기한 항목이 없습니다',
                          subtitle: '역, 시설, 경로에서 즐겨찾기를 추가해 주세요.',
                        ),
                      ),
                    )
                  else ...[
                    // 카테고리 카드·개수 없이 저장한 항목을 바로 나열한다. 섹션
                    // 헤더는 해당 항목이 있을 때만 보여준다(#1569).
                    if (data.stations.isNotEmpty) ...[
                      const AppSectionTitle(title: '역'),
                      for (final station in data.stations)
                        _FavoriteHomeStationRow(
                          station: station,
                          onTap: widget.favoriteRepository == null
                              ? null
                              : () => _openStationDetailFromFavorite(station),
                        ),
                    ],
                    if (data.routes.isNotEmpty) ...[
                      const AppSectionTitle(title: '경로'),
                      for (final route in data.routes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _HomeSavedRouteCard(
                            route: route,
                            onTap: () => _openRouteSearchFromFavorite(route),
                            onRemove: widget.favoriteRouteRepository == null
                                ? null
                                : () => _removeFavoriteRoute(route),
                          ),
                        ),
                    ],
                    if (data.facilities.isNotEmpty) ...[
                      const AppSectionTitle(title: '시설'),
                      for (final facility in data.facilities)
                        _FavoriteHomeFacilityRow(
                          facility: facility,
                          onReportTap: () =>
                              _openFacilityReportFromFavorite(facility),
                        ),
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<_FavoriteHomeData> _loadData() async {
    final stations =
        await widget.favoriteRepository?.listFavoriteStations() ??
        const <FavoriteStation>[];
    final facilities =
        await widget.favoriteFacilityRepository?.listFavoriteFacilities() ??
        const <FavoriteFacility>[];
    final routes =
        await widget.favoriteRouteRepository?.listFavoriteRoutes() ??
        const <FavoriteRoute>[];
    return _FavoriteHomeData(
      stations: stations,
      facilities: facilities,
      routes: routes,
    );
  }

  void _openRouteSearchFromFavorite(FavoriteRoute favorite) {
    widget.routeDraftController.clear();
    widget.routeDraftController.setOrigin(
      RouteDraftStation(
        id: favorite.originStationId,
        nameKo: favorite.originStationName,
      ),
    );
    widget.routeDraftController.setDestination(
      RouteDraftStation(
        id: favorite.destinationStationId,
        nameKo: favorite.destinationStationName,
      ),
    );
    final openRouteSearch = widget.onOpenRouteSearch;
    if (openRouteSearch == null) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(openRouteSearch(favorite.mobilityType, favorite.transportScope));
  }

  Future<void> _removeFavoriteRoute(FavoriteRoute favorite) async {
    final repository = widget.favoriteRouteRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.removeFavoriteRoute(favorite.favoriteRouteId);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '즐겨찾기 경로 삭제 중 예외가 발생했습니다.');
    }
    await _reloadFavoritesAfterReturn();
  }

  Future<void> _openStationDetailFromFavorite(FavoriteStation favorite) async {
    final repository = widget.favoriteRepository;
    if (repository == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StationDetailScreen(
          repository: widget.stationRepository,
          reportRepository: widget.reportRepository,
          favoriteRepository: repository,
          adRepository: widget.adRepository,
          locationProvider: widget.locationProvider,
          realtimeRepository: widget.realtimeRepository,
          stationId: favorite.stationId,
          facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
          internalRouteRepository: widget.internalRouteRepository,
          internalRouteMobilityType: widget.initialMobilityType,
          routeDraftController: widget.routeDraftController,
          // 즐겨찾기에서 들어온 역은 이미 저장 상태로 열어 바로 해제할 수 있게 한다.
          initiallyFavorite: true,
        ),
      ),
    );
    await _reloadFavoritesAfterReturn();
  }

  Future<void> _openFacilityReportFromFavorite(
    FavoriteFacility favorite,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FacilityReportScreen(
          repository: widget.reportRepository,
          locationLoader: _facilityReportLocationLoader(
            widget.locationProvider,
          ),
          needsLocationPermissionRequest:
              widget.locationProvider.needsLocationPermissionRequest,
          openLocationSettings: widget.locationProvider.openLocationSettings,
          draftTargetStore: widget.facilityReportDraftTargetStore,
          target: FacilityReportTarget(
            stationId: favorite.stationId,
            stationName: favorite.stationNameKo,
            facilityId: favorite.facilityId,
            facilityName: favorite.name,
            facilityTypeLabel: favorite.typeLabel,
            facilityStatusLabel: favorite.statusLabel,
          ),
        ),
      ),
    );
    await _reloadFavoritesAfterReturn();
  }

  Future<void> _reloadFavoritesAfterReturn() async {
    if (!mounted) {
      return;
    }
    final next = _loadData();
    setState(() {
      _dataFuture = next;
    });
    try {
      await next;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 화면 복귀 후 새로고침 중 예외가 발생했습니다.',
      );
    }
  }
}

bool _isSameViewPreferences(
  OnboardingViewPreferences left,
  OnboardingViewPreferences right,
) {
  return left.highContrastEnabled == right.highContrastEnabled &&
      left.simpleViewEnabled == right.simpleViewEnabled;
}

class _FavoriteHomeData {
  const _FavoriteHomeData({
    this.stations = const [],
    this.facilities = const [],
    this.routes = const [],
  });

  final List<FavoriteStation> stations;
  final List<FavoriteFacility> facilities;
  final List<FavoriteRoute> routes;

  bool get isEmpty => stations.isEmpty && facilities.isEmpty && routes.isEmpty;
}

class _FavoriteHomeStationRow extends StatelessWidget {
  const _FavoriteHomeStationRow({required this.station, required this.onTap});

  final FavoriteStation station;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = _stationNameWithSuffix(station.nameKo);
    final lineLabel = station.lineLabel;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: lineLabel.isEmpty ? '즐겨찾기 역, $name' : '즐겨찾기 역, $name, $lineLabel',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          key: Key('favoriteHomeStationRow-${station.stationId}'),
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EasySubwayAccessibleColors.line),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.train_outlined,
                  color: EasySubwayAccessibleColors.primary,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: EasySubwayAccessibleColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      if (lineLabel.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        _HomeMiniBadge(lineLabel),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: EasySubwayAccessibleColors.brand,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteHomeFacilityRow extends StatelessWidget {
  const _FavoriteHomeFacilityRow({
    required this.facility,
    required this.onReportTap,
  });

  final FavoriteFacility facility;
  final VoidCallback? onReportTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.elevator_outlined,
            color: EasySubwayAccessibleColors.primary,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  facility.name,
                  style: const TextStyle(
                    color: EasySubwayAccessibleColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  facility.stationLabel,
                  style: const TextStyle(
                    color: EasySubwayAccessibleColors.mutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          if (onReportTap != null)
            TextButton(
              key: Key('favoriteFacilityReportButton-${facility.facilityId}'),
              onPressed: onReportTap,
              child: const Text('시설 알려주기'),
            ),
        ],
      ),
    );
  }
}

class SupportAccessScreen extends StatelessWidget {
  const SupportAccessScreen({
    required this.accessInfo,
    required this.launcher,
    required this.userDataDeletionRepository,
    required this.onUserDataDeleted,
    super.key,
  });

  final SupportAccessInfo accessInfo;
  final SupportAccessLauncher launcher;
  final UserDataDeletionRepository? userDataDeletionRepository;
  final Future<void> Function(UserDataDeletionResult result)? onUserDataDeleted;

  @override
  Widget build(BuildContext context) {
    final deletionScope = _userDataDeletionScope(userDataDeletionRepository);
    return Scaffold(
      appBar: AppBar(title: const Text('도움말·문의')),
      body: SafeArea(
        child: ListView(
          padding: mainPagePadding,
          children: [
            const _SupportSectionTitle(title: '내 정보와 개인정보'),
            _SupportGroupCard(
              children: [
                if (_httpsUri(accessInfo.privacyPolicyUrl) != null)
                  _SupportAccessItem(
                    key: const Key('privacyPolicyAccessItem'),
                    icon: Icons.privacy_tip_outlined,
                    title: '개인정보처리방침',
                    value: accessInfo.privacyPolicyUrl,
                    displayValue: '웹에서 확인',
                    uri: _httpsUri(accessInfo.privacyPolicyUrl),
                    launcher: launcher,
                  ),
                if (userDataDeletionRepository != null)
                  _UserDataDeletionAccessItem(
                    repository: userDataDeletionRepository!,
                    deletionScope: deletionScope,
                    onDeleted: onUserDataDeleted,
                  )
                else if (_mailtoUri(
                      accessInfo.dataDeletionEmail,
                      '쉬운 지하철 내 정보 삭제 요청',
                    ) !=
                    null)
                  _SupportAccessItem(
                    key: const Key('dataDeletionAccessItem'),
                    icon: Icons.delete_outline,
                    title: '내 정보 삭제 요청',
                    value: accessInfo.dataDeletionEmail,
                    displayValue: '이메일 보내기',
                    uri: _mailtoUri(
                      accessInfo.dataDeletionEmail,
                      '쉬운 지하철 내 정보 삭제 요청',
                    ),
                    launcher: launcher,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SupportSectionTitle(title: '이동 전 살펴보기'),
            const _SafetyDataNotice(),
            const SizedBox(height: 12),
            _SupportGroupCard(
              children: [
                _SupportNavRow(
                  key: const Key('supportDataSourceAttributionButton'),
                  icon: Icons.source_outlined,
                  title: '데이터 및 지도 출처',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DataSourceAttributionScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            const _SupportSectionTitle(title: '문의'),
            _SupportGroupCard(
              children: [
                if (_mailtoUri(accessInfo.supportEmail, '쉬운 지하철 고객지원 문의') !=
                    null)
                  _SupportAccessItem(
                    key: const Key('supportAccessItem'),
                    icon: Icons.support_agent,
                    title: '고객지원',
                    value: accessInfo.supportEmail,
                    displayValue: '이메일 보내기',
                    uri: _mailtoUri(accessInfo.supportEmail, '쉬운 지하철 고객지원 문의'),
                    launcher: launcher,
                  ),
                if (_mailtoUri(accessInfo.securityEmail, '쉬운 지하철 보안 문의') !=
                    null)
                  _SupportAccessItem(
                    key: const Key('securityContactAccessItem'),
                    icon: Icons.security_outlined,
                    title: '보안 문의',
                    value: accessInfo.securityEmail,
                    displayValue: '보안 문제 알리기',
                    uri: _mailtoUri(accessInfo.securityEmail, '쉬운 지하철 보안 문의'),
                    launcher: launcher,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const _SecurityContactNotice(),
          ],
        ),
      ),
    );
  }
}

class _SupportSectionTitle extends StatelessWidget {
  const _SupportSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class _SupportGroupCard extends StatelessWidget {
  const _SupportGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // 연결 가능한 항목이 없으면(전 항목 숨김) 빈 테두리 카드를 그리지 않는다.
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          const Divider(height: 1, color: EasySubwayAccessibleColors.line),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        border: Border.all(color: EasySubwayAccessibleColors.line),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

class _SupportNavRow extends StatelessWidget {
  const _SupportNavRow({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 24, color: EasySubwayAccessibleColors.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: EasySubwayAccessibleColors.mutedText,
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

class _UserDataDeletionAccessItem extends StatelessWidget {
  const _UserDataDeletionAccessItem({
    required this.repository,
    required this.deletionScope,
    required this.onDeleted,
  });

  final UserDataDeletionRepository repository;
  final UserDataDeletionScope deletionScope;
  final Future<void> Function(UserDataDeletionResult result)? onDeleted;

  @override
  Widget build(BuildContext context) {
    final copy = _UserDataDeletionCopy.forScope(deletionScope);
    void openDeletionScreen() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserDataDeletionScreen(
            repository: repository,
            deletionScope: deletionScope,
            onDeleted: onDeleted,
          ),
        ),
      );
    }

    return Semantics(
      key: const Key('dataDeletionAccessItem'),
      button: true,
      label: '${copy.title}, ${copy.helperText}',
      onTap: openDeletionScreen,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: openDeletionScreen,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.delete_outline,
                    color: EasySubwayAccessibleColors.red,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    copy.title,
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: EasySubwayAccessibleColors.mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum UserDataDeletionScope {
  requestOnly,
  deviceOnly,
  remoteOnly,
  remoteAndDevice,
}

UserDataDeletionScope _userDataDeletionScope(
  UserDataDeletionRepository? repository,
) {
  if (repository == null) {
    return UserDataDeletionScope.requestOnly;
  }
  if (repository is UserDataDeletionCompositeRepository) {
    return UserDataDeletionScope.remoteAndDevice;
  }
  if (repository is UserDataDeletionApiRepository) {
    return UserDataDeletionScope.remoteOnly;
  }
  return UserDataDeletionScope.deviceOnly;
}

class _UserDataDeletionCopy {
  const _UserDataDeletionCopy({
    required this.title,
    required this.helperText,
    required this.deletedSummary,
    required this.confirmText,
    this.exceptionNote,
  });

  factory _UserDataDeletionCopy.forScope(UserDataDeletionScope scope) {
    return switch (scope) {
      UserDataDeletionScope.requestOnly => const _UserDataDeletionCopy(
        title: '내 정보 삭제 요청',
        helperText: '메일로 삭제를 문의합니다.',
        deletedSummary: '삭제가 필요한 정보와 방법을 지원 메일로 문의합니다.',
        confirmText: '내 정보 삭제 요청 메일을 보낼까요?',
      ),
      UserDataDeletionScope.deviceOnly => const _UserDataDeletionCopy(
        title: '이 기기의 앱 정보 삭제',
        helperText: '이 기기에서 지울 정보를 확인합니다.',
        deletedSummary: '즐겨찾기, 최근 검색, 이동 조건, 화면 설정이 이 기기에서 지워져요.',
        exceptionNote: '이미 보낸 시설 제보와 사진은 그대로 남아요.',
        confirmText: '이 기기의 즐겨찾기·최근 검색·설정이 지워지고 되돌릴 수 없어요.',
      ),
      UserDataDeletionScope.remoteOnly => const _UserDataDeletionCopy(
        title: '보낸 정보 삭제',
        helperText: '보낸 정보 삭제 범위를 확인합니다.',
        deletedSummary: '보낸 제보와 사진·위치, 즐겨찾기, 이동 조건이 삭제되거나 익명 처리돼요.',
        confirmText: '보낸 정보와 설정이 삭제·익명 처리되고 되돌릴 수 없어요.',
      ),
      UserDataDeletionScope.remoteAndDevice => const _UserDataDeletionCopy(
        title: '내 정보 삭제',
        helperText: '삭제 범위를 확인합니다.',
        deletedSummary: '이 기기의 즐겨찾기·최근 검색·설정과 보낸 제보·사진이 삭제되거나 익명 처리돼요.',
        confirmText: '이 기기와 보낸 정보가 삭제·익명 처리되고 되돌릴 수 없어요.',
      ),
    };
  }

  final String title;
  final String helperText;
  final String deletedSummary;
  final String? exceptionNote;
  final String confirmText;

  static const irreversibleLine = '삭제 후에는 되돌릴 수 없어요.';
}

class UserDataDeletionScreen extends StatefulWidget {
  const UserDataDeletionScreen({
    required this.repository,
    required this.deletionScope,
    required this.onDeleted,
    super.key,
  });

  final UserDataDeletionRepository repository;
  final UserDataDeletionScope deletionScope;
  final Future<void> Function(UserDataDeletionResult result)? onDeleted;

  @override
  State<UserDataDeletionScreen> createState() => _UserDataDeletionScreenState();
}

class _UserDataDeletionScreenState extends State<UserDataDeletionScreen> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final copy = _UserDataDeletionCopy.forScope(widget.deletionScope);
    return Scaffold(
      appBar: AppBar(title: Text(copy.title)),
      bottomNavigationBar: Padding(
        padding: easySubwayBottomActionInsets(context),
        child: FilledButton.icon(
          key: const Key('dataDeletionStartButton'),
          onPressed: _isDeleting ? null : _confirmAndDelete,
          icon: _isDeleting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.delete_forever_outlined),
          label: Text(_isDeleting ? '삭제 중' : copy.title),
          style: FilledButton.styleFrom(
            backgroundColor: EasySubwayAccessibleColors.red,
            foregroundColor: EasySubwayAccessibleColors.surface,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: mainPagePadding,
          children: [
            Semantics(
              header: true,
              child: Text(
                '삭제 전에 확인해 주세요',
                style: textTheme.headlineSmall?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              copy.deletedSummary,
              style: textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _UserDataDeletionCopy.irreversibleLine,
              style: textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.red,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            if (copy.exceptionNote != null) ...[
              const SizedBox(height: 10),
              Text(
                copy.exceptionNote!,
                style: textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('정말 삭제할까요?'),
        content: Text(
          _UserDataDeletionCopy.forScope(widget.deletionScope).confirmText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('dataDeletionConfirmButton'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: EasySubwayAccessibleColors.red,
              foregroundColor: EasySubwayAccessibleColors.surface,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteCurrentUserData();
    }
  }

  Future<void> _deleteCurrentUserData() async {
    setState(() {
      _isDeleting = true;
    });
    try {
      final result = await widget.repository.deleteCurrentUserData();
      await widget.onDeleted?.call(result);
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on UserDataDeletionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '사용자 정보 삭제 처리 중 예외가 발생했습니다.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(userDataDeletionErrorMessage)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
}

class UserDataDeletionResultScreen extends StatelessWidget {
  const UserDataDeletionResultScreen({required this.onRestart, super.key});

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('삭제 완료'),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: Padding(
        padding: easySubwayBottomActionInsets(context),
        child: FilledButton.icon(
          key: const Key('dataDeletionResultStartButton'),
          onPressed: onRestart,
          icon: const Icon(Icons.restart_alt),
          label: const Text('처음부터 시작'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: mainPagePadding,
          children: [
            AppCard(
              backgroundColor: EasySubwayAccessibleColors.surface,
              borderColor: EasySubwayAccessibleColors.line,
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: EasySubwayAccessibleColors.mintDark,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '내 정보가 삭제됐어요',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '앱이 처음 사용하는 상태로 돌아갑니다.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const AppCard(
              showBorder: true,
              child: AppInfoRow(
                icon: Icons.map_outlined,
                iconColor: EasySubwayAccessibleColors.primary,
                title: '노선도와 역 정보는 계속 이용할 수 있어요',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityContactNotice extends StatelessWidget {
  const _SecurityContactNotice();

  static const _title = '보안 문의 안내';
  static const _contactNotice = '앱 보안이나 개인정보가 걱정되면 문의로 알려주세요.';
  static const _scopeNotice = '위치, 제보 사진, 알림, 개인정보 관련 걱정을 함께 보낼 수 있습니다.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      key: const Key('securityContactNotice'),
      container: true,
      label: '$_title, $_contactNotice $_scopeNotice',
      child: ExcludeSemantics(
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: EasySubwayAccessibleColors.line),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.security_outlined,
                      color: EasySubwayAccessibleColors.brand,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _title,
                        style: textTheme.titleMedium?.copyWith(
                          color: EasySubwayAccessibleColors.text,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _SecurityContactNoticeLine(text: _contactNotice),
                const _SecurityContactNoticeLine(text: _scopeNotice),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecurityContactNoticeLine extends StatelessWidget {
  const _SecurityContactNoticeLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(
              Icons.circle,
              size: 7,
              color: EasySubwayAccessibleColors.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyDataNotice extends StatelessWidget {
  const _SafetyDataNotice();

  static const _title = '이동 전 살펴보기';
  static const _referenceNotice = '경로와 시설 정보는 이동을 돕는 참고 정보입니다.';
  static const _fieldNotice = '실제 이동 전에는 현장 안내, 역무원 안내, 운영기관 공지를 먼저 확인해 주세요.';
  static const _limitationNotice = '실시간 상태나 무조건 안전한 경로를 보장하지 않습니다.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      key: const Key('safetyDataNotice'),
      container: true,
      label: '$_title, $_referenceNotice $_fieldNotice $_limitationNotice',
      child: ExcludeSemantics(
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: EasySubwayAccessibleColors.line),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: EasySubwayAccessibleColors.amber,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _title,
                        style: textTheme.titleMedium?.copyWith(
                          color: EasySubwayAccessibleColors.text,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _SafetyDataNoticeLine(text: _referenceNotice),
                const _SafetyDataNoticeLine(text: _fieldNotice),
                const _SafetyDataNoticeLine(text: _limitationNotice),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SafetyDataNoticeLine extends StatelessWidget {
  const _SafetyDataNoticeLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(
              Icons.circle,
              size: 7,
              color: EasySubwayAccessibleColors.amber,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DataSourceAttributionScreen extends StatefulWidget {
  const DataSourceAttributionScreen({
    super.key,
    this.initialManifest,
    this.initialInventory,
  }) : assert(
         (initialManifest == null) == (initialInventory == null),
         'initialManifest and initialInventory must be provided together.',
       );

  final Map<String, Object?>? initialManifest;
  final Map<String, Object?>? initialInventory;

  @override
  State<DataSourceAttributionScreen> createState() =>
      _DataSourceAttributionScreenState();
}

class _DataSourceAttributionScreenState
    extends State<DataSourceAttributionScreen> {
  static const _mapManifestAsset =
      'assets/datapacks/metro_map_pack/manifest.json';
  static const _sourceInventoryAsset = 'assets/datapacks/source-inventory.json';

  late final Future<
    ({Map<String, Object?> manifest, Map<String, Object?> inventory})
  >
  _future = _load();

  Future<({Map<String, Object?> manifest, Map<String, Object?> inventory})>
  _load() async {
    final initialManifest = widget.initialManifest;
    final initialInventory = widget.initialInventory;
    if (initialManifest != null && initialInventory != null) {
      return (manifest: initialManifest, inventory: initialInventory);
    }
    final [manifestText, inventoryText] = await Future.wait([
      rootBundle.loadString(_mapManifestAsset),
      rootBundle.loadString(_sourceInventoryAsset),
    ]);
    return (
      manifest: jsonDecode(manifestText) as Map<String, Object?>,
      inventory: jsonDecode(inventoryText) as Map<String, Object?>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('dataSourceAttributionScreen'),
      appBar: AppBar(title: const Text('데이터 및 지도 출처')),
      body: SafeArea(
        child:
            FutureBuilder<
              ({Map<String, Object?> manifest, Map<String, Object?> inventory})
            >(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ListView(
                    padding: mainPagePadding,
                    children: const [
                      AppCard(
                        child: AppInfoRow(
                          icon: Icons.error_outline,
                          iconColor: EasySubwayAccessibleColors.amber,
                          title: '자료 제공 정보를 불러오지 못했어요',
                          subtitle: '앱을 다시 열고, 계속 보이지 않으면 고객지원에 알려 주세요.',
                        ),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final manifest = snapshot.data!.manifest;
                final inventory = snapshot.data!.inventory;
                final maps = (manifest['maps'] as List)
                    .cast<Map<String, Object?>>();
                final sources = (inventory['sources'] as List)
                    .cast<Map<String, Object?>>()
                    .toList(growable: false);
                return ListView(
                  padding: mainPagePadding,
                  children: [
                    const AppCard(
                      child: AppInfoRow(
                        icon: Icons.fact_check_outlined,
                        iconColor: EasySubwayAccessibleColors.amber,
                        title: '현재 앱 표시',
                        // 내부 거버넌스 언어(pilot·"~보장한다고 말하지 않아요") 대신
                        // 어떤 자료로 무엇을 확인했는지 사실·metadata로 표현한다(#1765).
                        subtitle:
                            '지도와 길·시설 안내는 공식·공개 자료를 바탕으로 해요. 상록수·사당역은 현장 확인까지 마쳤고, 나머지 역은 자료를 바탕으로 안내해요.',
                      ),
                    ),
                    const AppSectionTitle(title: '지도 표시용 asset'),
                    for (final map in maps) _AttributionCard.map(map, manifest),
                    const AppSectionTitle(title: '데이터 품질 Level'),
                    const AppCard(
                      child: AppInfoRow(
                        icon: Icons.verified_outlined,
                        iconColor: EasySubwayAccessibleColors.mintDark,
                        title: 'Level 1-4 품질 기준',
                        subtitle:
                            'Level 1은 역·노선 수, Level 2는 필수 시설 근거, Level 3은 운행상태와 최신 여부, Level 4는 현장 또는 운영기관이 확인한 쉬운 길을 봐요.',
                      ),
                    ),
                    const AppCard(
                      child: AppInfoRow(
                        icon: Icons.analytics_outlined,
                        iconColor: EasySubwayAccessibleColors.amber,
                        title: '품질 지표',
                        subtitle:
                            '필수 시설 근거 비율, 운행상태 확인 비율, 최신 정보 비율, 확인된 쉬운 길 비율, 현장 확인 경로 비율을 함께 확인해요.',
                      ),
                    ),
                    const AppSectionTitle(title: '경로·시설 안내용 데이터'),
                    for (final source in sources)
                      _AttributionCard.source(source),
                  ],
                );
              },
            ),
      ),
    );
  }
}

class _AttributionCard extends StatelessWidget {
  const _AttributionCard._({
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  factory _AttributionCard.map(
    Map<String, Object?> map,
    Map<String, Object?> manifest,
  ) {
    final license = (map['license'] as Map<String, Object?>?) ?? const {};
    final offline = (map['offline'] as Map<String, Object?>?) ?? const {};
    return _AttributionCard._(
      title: _text(map['name_ko']),
      subtitle: '제공·소유: ${_text(map['operator'])}',
      rows: [
        ('제공 기관', _text(license['source'], _text(map['name_ko']))),
        ('라이선스', '${_text(license['name'])} (${_text(license['spdx'])})'),
        ('작성자', _text(license['authors'])),
        ('라이선스 링크', _text(license['url'])),
        ('표기 필요', _yesNo(license['attributionRequired'])),
        ('가져온 날짜', _text(license['date'])),
        ('확인한 날짜', _text(manifest['generated_at_utc'])),
        (
          '상업적 이용 / 재배포',
          '${_allowed(license['commercialUseAllowed'])} / ${_allowed(license['redistributionAllowed'])}',
        ),
        ('검토 상태', _text(license['reviewStatus'])),
        ('변경 사항', _text(license['changes'])),
        ('파일 경로', _text(offline['path'])),
      ],
    );
  }

  factory _AttributionCard.source(Map<String, Object?> source) {
    final license = (source['license'] as Map<String, Object?>?) ?? const {};
    return _AttributionCard._(
      title: _text(source['displayName']),
      subtitle:
          '제공·소유: ${_text(source['provider'])} / ${_text(source['owner'])}',
      rows: [
        ('제공 기관', _text(source['displayName'])),
        ('라이선스', '${_text(license['name'])} (${_text(license['type'])})'),
        ('라이선스 링크', _text(license['evidenceUrl'])),
        ('표기 필요', _text(license['attribution'])),
        ('가져온 날짜', _text(source['retrievedAt'])),
        ('확인한 날짜', _text(source['observedDataUpdatedAt'])),
        (
          '상업적 이용 / 재배포',
          '${_allowed(license['commercialUseAllowed'])} / ${_allowed(license['redistributionAllowed'])}',
        ),
        (
          '변경 사항',
          source.containsKey('changes')
              ? _text(source['changes'])
              : '자료 목록에 별도 변경 고지 없음',
        ),
      ],
    );
  }

  final String title;
  final String subtitle;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = [
      title,
      subtitle,
      for (final row in rows) '${row.$1}: ${row.$2}',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: semanticLabel,
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              for (final row in rows)
                _AttributionRow(label: row.$1, value: row.$2),
            ],
          ),
        ),
      ),
    );
  }

  static String _text(Object? value, [String fallback = '미기록']) {
    if (value is List) {
      final joined = value
          .whereType<Object>()
          .map((item) => '$item')
          .join(', ');
      return joined.isEmpty ? fallback : joined;
    }
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static String _yesNo(Object? value) {
    if (value == true) {
      return '예';
    }
    if (value == false) {
      return '아니오';
    }
    return '미확정';
  }

  static String _allowed(Object? value) {
    if (value == true) {
      return '가능';
    }
    if (value == false) {
      return '불가';
    }
    return '미확정';
  }
}

class _AttributionRow extends StatelessWidget {
  const _AttributionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: EasySubwayAccessibleColors.secondaryText,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportAccessItem extends StatelessWidget {
  const _SupportAccessItem({
    required this.icon,
    required this.title,
    required this.value,
    required this.uri,
    required this.launcher,
    this.displayValue,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;
  final Uri? uri;
  final SupportAccessLauncher launcher;
  final String? displayValue;

  @override
  Widget build(BuildContext context) {
    final targetUri = uri;
    final targetText = value.trim();
    final displayValue = this.displayValue ?? targetText;
    final semanticLabelParts = [title, displayValue];
    if (targetUri != null && displayValue != targetText) {
      semanticLabelParts.add(targetText);
    }
    return Semantics(
      button: true,
      enabled: targetUri != null,
      label: semanticLabelParts.join(', '),
      onTap: targetUri == null
          ? null
          : () => unawaited(_openTarget(context, targetUri, targetText)),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: targetUri == null
              ? null
              : () => unawaited(_openTarget(context, targetUri, targetText)),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    icon,
                    size: 24,
                    color: targetUri == null
                        ? EasySubwayAccessibleColors.mutedText
                        : EasySubwayAccessibleColors.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: EasySubwayAccessibleColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        displayValue,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: EasySubwayAccessibleColors.secondaryText,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (targetUri != null) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: EasySubwayAccessibleColors.mutedText,
                    size: 22,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTarget(
    BuildContext context,
    Uri uri,
    String targetText,
  ) async {
    bool opened = false;
    try {
      opened = await launcher.open(uri);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '도움말 외부 연결 실행 중 예외가 발생했습니다.',
      );
    }

    if (!context.mounted || opened) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('연결할 수 없습니다. 직접 확인해 주세요: $targetText')),
    );
  }
}

Uri? _httpsUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return null;
  }
  return uri;
}

Uri? _mailtoUri(String value, String subject) {
  final email = value.trim();
  if (email.isEmpty) {
    return null;
  }
  return Uri(
    scheme: 'mailto',
    path: email,
    queryParameters: {'subject': subject},
  );
}
