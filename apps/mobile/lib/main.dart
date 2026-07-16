import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'features/account/presentation/user_data_deletion_screen.dart';
import 'features/get_off_alarm/get_off_alarm_controller.dart';
import 'features/ads/ad_repository.dart';
import 'features/attribution/presentation/data_source_attribution_screen.dart';
import 'features/favorites/presentation/favorite_home_screen.dart';
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
import 'features/settings/presentation/app_settings_screen.dart';
import 'onboarding.dart';
import 'route_search.dart';
import 'station_search.dart';
import 'mobile_error_reporter.dart';
import 'user_data_deletion.dart';

export 'app/app_components.dart' show FeatureTile;
export 'features/account/presentation/user_data_deletion_screen.dart'
    show
        UserDataDeletionScope,
        UserDataDeletionScreen,
        UserDataDeletionResultScreen;
export 'features/attribution/presentation/data_source_attribution_screen.dart'
    show DataSourceAttributionScreen;
export 'features/notifications/presentation/notification_inbox_screen.dart'
    show NotificationInboxScreen;
export 'features/favorites/presentation/favorite_home_screen.dart'
    show FavoriteHomeScreen;
export 'features/settings/presentation/app_settings_screen.dart'
    show AppSettingsScreen;

const defaultPushNotificationsEnabled = bool.fromEnvironment(
  'EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS',
  defaultValue: false,
);
const defaultDemoHomeDataEnabled = bool.fromEnvironment(
  'EASYSUBWAY_DEMO_HOME_DATA',
  defaultValue: false,
);
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

bool _isSameViewPreferences(
  OnboardingViewPreferences left,
  OnboardingViewPreferences right,
) {
  return left.highContrastEnabled == right.highContrastEnabled &&
      left.simpleViewEnabled == right.simpleViewEnabled;
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
    final deletionScope = userDataDeletionScope(userDataDeletionRepository);
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
                  UserDataDeletionAccessItem(
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
