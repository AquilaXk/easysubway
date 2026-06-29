import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accessible_design.dart';
import 'adaptive_layout.dart';
import 'app/app_bootstrap.dart';
import 'app/app_dependencies.dart';
import 'facility_report.dart';
import 'facility_status.dart';
import 'favorite_facility.dart';
import 'features/realtime/realtime_repository.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'features/stations/presentation/station_line_badges.dart';
import 'internal_route.dart';
import 'legacy_credential_cleanup.dart';
import 'mobility_profile.dart';
import 'network_map.dart';
import 'notification_settings.dart';
import 'onboarding.dart';
import 'route_search.dart';
import 'station_search.dart';
import 'mobile_error_reporter.dart';
import 'user_data_deletion.dart';

const defaultPushNotificationsEnabled = bool.fromEnvironment(
  'EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS',
  defaultValue: false,
);
const defaultDemoHomeDataEnabled = bool.fromEnvironment(
  'EASYSUBWAY_DEMO_HOME_DATA',
  defaultValue: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  validateReleaseBuildFlags(
    isReleaseMode: kReleaseMode,
    demoHomeDataEnabled: defaultDemoHomeDataEnabled,
  );
  final bootstrap = await AppBootstrap.initialize(
    enablePushNotifications: defaultPushNotificationsEnabled,
    favoriteRepository: defaultDemoHomeDataEnabled
        ? const _DemoFavoriteStationRepository()
        : null,
    favoriteFacilityRepository: defaultDemoHomeDataEnabled
        ? const _DemoFavoriteFacilityRepository()
        : null,
    favoriteRouteRepository: defaultDemoHomeDataEnabled
        ? const _DemoFavoriteRouteRepository()
        : null,
    searchHistoryRepository: defaultDemoHomeDataEnabled
        ? _DemoSearchHistoryRepository()
        : null,
  );
  final photoPicker = ImagePickerFacilityReportPhotoPicker();
  runApp(
    AppBootstrapLifecycle(
      close: bootstrap.close,
      child: EasySubwayApp(
        dependencies: bootstrap.dependencies,
        onboardingStore: const SecureOnboardingResultStore(),
        facilityReportDraftTargetStore:
            const SecureFacilityReportDraftTargetStore(),
        facilityReportLostPhotoRestorer: photoPicker.retrieveLostPhoto,
        legacyCredentialCleaner: const SecureLegacyCredentialCleaner(),
      ),
    ),
  );
}

void validateReleaseBuildFlags({
  required bool isReleaseMode,
  required bool demoHomeDataEnabled,
}) {
  if (isReleaseMode && demoHomeDataEnabled) {
    throw StateError('EASYSUBWAY_DEMO_HOME_DATA is not allowed in release.');
  }
}

class _DemoFavoriteStationRepository implements FavoriteStationRepository {
  const _DemoFavoriteStationRepository();

  static const _station = FavoriteStation(
    userId: 'demo-user',
    stationId: 'station-sangnoksu',
    nameKo: '상록수',
    nameEn: 'Sangnoksu',
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    dataSourceType: 'OFFICIAL_FILE',
    lastVerifiedAt: '2026-06-13',
    lines: [
      StationSearchLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        stationCode: '448',
      ),
    ],
    addedAt: '2026-06-13T10:00:00',
  );

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    return const [_station];
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(String stationId) async {
    return _station;
  }

  @override
  Future<void> removeFavoriteStation(String stationId) async {}
}

class _DemoFavoriteFacilityRepository implements FavoriteFacilityRepository {
  const _DemoFavoriteFacilityRepository();

  static const _facility = FavoriteFacility(
    userId: 'demo-user',
    facilityId: 'facility-sangnoksu-elevator-3',
    stationId: 'station-sangnoksu',
    stationNameKo: '상록수',
    stationNameEn: 'Sangnoksu',
    exitId: 'exit-sangnoksu-3',
    type: 'ELEVATOR',
    name: '3번 출구 엘리베이터',
    floorFrom: '1F',
    floorTo: 'B1',
    description: '3번 출구 앞',
    status: 'NEEDS_CHECK',
    dataConfidence: 'HIGH',
    dataSourceType: 'OFFICIAL_FILE',
    lastUpdatedAt: '2026-06-12',
    addedAt: '2026-06-14T10:00:00',
  );

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    return const [_facility];
  }

  @override
  Future<FavoriteFacility> saveFavoriteFacility(String facilityId) async {
    return _facility;
  }

  @override
  Future<void> removeFavoriteFacility(String facilityId) async {}
}

class _DemoFavoriteRouteRepository implements FavoriteRouteRepository {
  const _DemoFavoriteRouteRepository();

  static const _route = FavoriteRoute(
    userId: 'demo-user',
    favoriteRouteId: 'route-1',
    routeSearchId: 'route-1',
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-sadang',
    destinationStationName: '사당',
    mobilityType: 'SENIOR',
    status: 'FOUND',
    lineId: 'seoul-4',
    lineName: '수도권 4호선',
    score: 92,
    routeCreatedAt: '2026-06-13T09:00:00',
    addedAt: '2026-06-14T10:00:00',
  );

  @override
  Future<List<FavoriteRoute>> listFavoriteRoutes() async {
    return const [_route];
  }

  @override
  Future<FavoriteRoute> saveFavoriteRoute(
    String routeSearchId, {
    RouteSearchResult? result,
  }) async {
    return _route;
  }

  @override
  Future<void> removeFavoriteRoute(String favoriteRouteId) async {}
}

class _DemoSearchHistoryRepository implements SearchHistoryRepository {
  final _queries = <String>['상록수', '사당'];

  @override
  Future<void> recordSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _queries
      ..remove(trimmed)
      ..insert(0, trimmed);
  }

  @override
  Future<List<String>> listRecentQueries() async {
    return List.unmodifiable(_queries);
  }

  @override
  Future<void> removeSearch(String query) async {
    _queries.remove(query.trim());
  }

  @override
  Future<void> clearSearches() async {
    _queries.clear();
  }
}

class EasySubwayApp extends StatelessWidget {
  EasySubwayApp({
    AppDependencies? dependencies,
    StationSearchRepository? repository,
    FacilityReportRepository? reportRepository,
    RouteSearchRepository? routeRepository,
    RouteFeedbackRepository? routeFeedbackRepository,
    FavoriteStationRepository? favoriteRepository,
    FavoriteFacilityRepository? favoriteFacilityRepository,
    FavoriteRouteRepository? favoriteRouteRepository,
    Future<List<FavoriteRoute>>? recentRoutesFuture,
    SearchHistoryRepository? searchHistoryRepository,
    InternalRouteRepository? internalRouteRepository,
    NetworkMapRepository? networkMapRepository,
    RealtimeRepository? realtimeRepository,
    NotificationSettingsRepository? notificationRepository,
    NotificationPermissionProvider? notificationPermissionProvider,
    CurrentLocationProvider? locationProvider,
    UserDataDeletionRepository? userDataDeletionRepository,
    LegacyCredentialCleaner legacyCredentialCleaner =
        const NoLegacyCredentialCleaner(),
    OnboardingResultStore? onboardingStore,
    FacilityReportDraftTargetStore? facilityReportDraftTargetStore,
    FacilityReportLostPhotoRestorer? facilityReportLostPhotoRestorer,
    SupportAccessInfo supportAccessInfo =
        const SupportAccessInfo.fromEnvironment(),
    SupportAccessLauncher supportAccessLauncher =
        const UrlLauncherSupportAccessLauncher(),
    OnboardingState initialOnboardingState = const OnboardingState.initial(),
    bool enablePushNotifications = defaultPushNotificationsEnabled,
    Key? key,
  }) : this._(
         dependencies:
             dependencies ??
             AppDependencies.resolve(
               repository: repository,
               reportRepository: reportRepository,
               routeRepository: routeRepository,
               routeFeedbackRepository: routeFeedbackRepository,
               favoriteRepository: favoriteRepository,
               favoriteFacilityRepository: favoriteFacilityRepository,
               favoriteRouteRepository: favoriteRouteRepository,
               searchHistoryRepository: searchHistoryRepository,
               internalRouteRepository: internalRouteRepository,
               networkMapRepository: networkMapRepository,
               realtimeRepository: realtimeRepository,
               notificationRepository: notificationRepository,
               notificationPermissionProvider: notificationPermissionProvider,
               locationProvider: locationProvider,
               userDataDeletionRepository: userDataDeletionRepository,
               enablePushNotifications: enablePushNotifications,
             ),
         initialOnboardingState: initialOnboardingState,
         onboardingStore: onboardingStore,
         facilityReportDraftTargetStore: facilityReportDraftTargetStore,
         facilityReportLostPhotoRestorer: facilityReportLostPhotoRestorer,
         legacyCredentialCleaner: legacyCredentialCleaner,
         supportAccessInfo: supportAccessInfo.validatedForBuild(
           isReleaseMode: kReleaseMode,
         ),
         supportAccessLauncher: supportAccessLauncher,
         recentRoutesFuture:
             recentRoutesFuture ??
             (defaultDemoHomeDataEnabled
                 ? const _DemoFavoriteRouteRepository().listFavoriteRoutes()
                 : null),
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
    required this.recentRoutesFuture,
    super.key,
  }) : repository = dependencies.repository,
       reportRepository = dependencies.reportRepository,
       routeRepository = dependencies.routeRepository,
       routeFeedbackRepository = dependencies.routeFeedbackRepository,
       favoriteRepository = dependencies.favoriteRepository,
       favoriteFacilityRepository = dependencies.favoriteFacilityRepository,
       favoriteRouteRepository = dependencies.favoriteRouteRepository,
       searchHistoryRepository = dependencies.searchHistoryRepository,
       internalRouteRepository = dependencies.internalRouteRepository,
       networkMapRepository = dependencies.networkMapRepository,
       realtimeRepository = dependencies.realtimeRepository,
       notificationRepository = dependencies.notificationRepository,
       notificationPermissionProvider =
           dependencies.notificationPermissionProvider,
       locationProvider = dependencies.locationProvider,
       userDataDeletionRepository = dependencies.userDataDeletionRepository;

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final InternalRouteRepository internalRouteRepository;
  final NetworkMapRepository networkMapRepository;
  final RealtimeRepository realtimeRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final UserDataDeletionRepository? userDataDeletionRepository;
  final OnboardingState initialOnboardingState;
  final OnboardingResultStore? onboardingStore;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final FacilityReportLostPhotoRestorer? facilityReportLostPhotoRestorer;
  final LegacyCredentialCleaner legacyCredentialCleaner;
  final SupportAccessInfo supportAccessInfo;
  final SupportAccessLauncher supportAccessLauncher;
  final Future<List<FavoriteRoute>>? recentRoutesFuture;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasySubway',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const EasySubwayScrollBehavior(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006D77)),
        scaffoldBackgroundColor: const Color(0xFFF6F8F9),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          toolbarHeight: 64,
          titleTextStyle: TextStyle(
            color: Color(0xFF102A2C),
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            side: const BorderSide(color: Color(0xFF006D77), width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: _EasySubwayHome(
        repository: repository,
        reportRepository: reportRepository,
        routeRepository: routeRepository,
        routeFeedbackRepository: routeFeedbackRepository,
        favoriteRepository: favoriteRepository,
        favoriteFacilityRepository: favoriteFacilityRepository,
        favoriteRouteRepository: favoriteRouteRepository,
        searchHistoryRepository: searchHistoryRepository,
        internalRouteRepository: internalRouteRepository,
        networkMapRepository: networkMapRepository,
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
        recentRoutesFuture: recentRoutesFuture,
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

class _EasySubwayHome extends StatefulWidget {
  const _EasySubwayHome({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.routeFeedbackRepository,
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    required this.searchHistoryRepository,
    required this.internalRouteRepository,
    required this.networkMapRepository,
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
    required this.recentRoutesFuture,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final InternalRouteRepository internalRouteRepository;
  final NetworkMapRepository networkMapRepository;
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
  final Future<List<FavoriteRoute>>? recentRoutesFuture;

  @override
  State<_EasySubwayHome> createState() => _EasySubwayHomeState();
}

class _EasySubwayHomeState extends State<_EasySubwayHome> {
  // 저장소가 없는 테스트/프리뷰에서도 같은 앱 세션에서는 온보딩 완료 상태를 유지한다.
  late OnboardingState _onboardingState = widget.initialOnboardingState;
  late bool _loadingOnboardingState =
      widget.onboardingStore != null &&
      !widget.initialOnboardingState.isCompleted;
  bool _startScreenDismissed = false;
  bool _introScreenDismissed = false;
  bool _pendingFacilityReportPhotoRecoveryStarted = false;
  bool _savingOnboardingResult = false;
  OnboardingResult? _pendingOnboardingResult;
  final _pendingOnboardingSaveCompleters = <Completer<void>>[];
  late OnboardingResult? _lastPersistedOnboardingResult =
      widget.initialOnboardingState.result;
  UserDataDeletionResult? _dataDeletionResult;
  UserDataDeletionScope _dataDeletionScope = UserDataDeletionScope.deviceOnly;

  @override
  void initState() {
    super.initState();
    unawaited(_clearLegacyCredentialsOnStartup());
    if (_loadingOnboardingState) {
      _restoreOnboardingState();
    }
    _schedulePendingFacilityReportPhotoRecovery();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingOnboardingState) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final dataDeletionResult = _dataDeletionResult;
    if (dataDeletionResult != null) {
      return UserDataDeletionResultScreen(
        result: dataDeletionResult,
        deletionScope: _dataDeletionScope,
        onRestart: () {
          setState(() {
            _dataDeletionResult = null;
            _dataDeletionScope = UserDataDeletionScope.deviceOnly;
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
      if (!_introScreenDismissed) {
        return OnboardingIntroScreen(
          onConfigure: () {
            setState(() {
              _introScreenDismissed = true;
            });
          },
          onSkip: () async {
            final result = OnboardingResult(
              profile: mobilityProfileOptions.first,
              preferences: const OnboardingViewPreferences.defaults(),
            );
            await _completeOnboarding(result);
          },
        );
      }
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

    return _OnboardingPreferenceScope(
      preferences: preferences,
      child: HomeScreen(
        repository: widget.repository,
        reportRepository: widget.reportRepository,
        routeRepository: widget.routeRepository,
        routeFeedbackRepository: widget.routeFeedbackRepository,
        favoriteRepository: widget.favoriteRepository,
        favoriteFacilityRepository: widget.favoriteFacilityRepository,
        favoriteRouteRepository: widget.favoriteRouteRepository,
        searchHistoryRepository: widget.searchHistoryRepository,
        internalRouteRepository: widget.internalRouteRepository,
        networkMapRepository: widget.networkMapRepository,
        realtimeRepository: widget.realtimeRepository,
        notificationRepository: widget.notificationRepository,
        notificationPermissionProvider: widget.notificationPermissionProvider,
        locationProvider: widget.locationProvider,
        initialMobilityType: onboardingResult?.profile.mobilityType,
        viewPreferences: preferences,
        simpleViewEnabled: preferences.simpleViewEnabled,
        facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
        supportAccessInfo: widget.supportAccessInfo,
        supportAccessLauncher: widget.supportAccessLauncher,
        userDataDeletionRepository: widget.userDataDeletionRepository,
        recentRoutesFuture: widget.recentRoutesFuture,
        onUserDataDeleted: _handleUserDataDeleted,
        onMobilityProfileChanged: _saveMobilityProfile,
        onViewPreferencesChanged: _saveViewPreferences,
      ),
    );
  }

  Future<void> _handleUserDataDeleted(UserDataDeletionResult result) async {
    try {
      await widget.legacyCredentialCleaner.clear();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '데이터 삭제 후 기존 익명 인증 저장값을 정리하는 중 예외가 발생했습니다.',
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
      _introScreenDismissed = false;
      _dataDeletionResult = result;
      _dataDeletionScope = _userDataDeletionScope(
        widget.userDataDeletionRepository,
      );
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
    final previousIntroScreenDismissed = _introScreenDismissed;
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
          _introScreenDismissed = previousIntroScreenDismissed;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장하지 못했습니다. 다시 시도해 주세요.')),
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

  Future<void> _saveMobilityProfile(MobilityProfileOption profile) async {
    final currentResult = _onboardingState.result;
    if (currentResult == null) {
      return;
    }
    final nextResult = OnboardingResult(
      profile: profile,
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
      profile: currentResult.profile,
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
        left.profile.id == right.profile.id &&
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
        context: '앱 시작 시 시설 신고 사진 복구 중 예외가 발생했습니다.',
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
        context: '시설 신고 사진 복구 대상 정리 중 예외가 발생했습니다.',
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

class _OnboardingPreferenceScope extends StatelessWidget {
  const _OnboardingPreferenceScope({
    required this.preferences,
    required this.child,
  });

  final OnboardingViewPreferences preferences;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final textScaler = preferences.largeTextEnabled
        ? mediaQuery.textScaler.clamp(minScaleFactor: 1.18)
        : mediaQuery.textScaler;

    return MediaQuery(
      data: mediaQuery.copyWith(
        highContrast:
            preferences.highContrastEnabled || mediaQuery.highContrast,
        textScaler: textScaler,
      ),
      child: Theme(
        data: _themeForPlatformAccessibility(
          _themeForPreferences(Theme.of(context), preferences),
          mediaQuery,
        ),
        child: child,
      ),
    );
  }
}

ThemeData _themeForPreferences(
  ThemeData baseTheme,
  OnboardingViewPreferences preferences,
) {
  if (!preferences.highContrastEnabled) {
    return baseTheme;
  }

  const textColor = Color(0xFF000000);
  final colorScheme = baseTheme.colorScheme.copyWith(
    primary: const Color(0xFF003D40),
    onPrimary: Colors.white,
    secondary: const Color(0xFF005E68),
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: textColor,
    outline: textColor,
  );

  return baseTheme.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: baseTheme.appBarTheme.copyWith(
      backgroundColor: Colors.white,
      foregroundColor: textColor,
      titleTextStyle: baseTheme.appBarTheme.titleTextStyle?.copyWith(
        color: textColor,
      ),
    ),
  );
}

ThemeData _themeForPlatformAccessibility(
  ThemeData baseTheme,
  MediaQueryData mediaQuery,
) {
  if (!mediaQuery.boldText) {
    return baseTheme;
  }

  return baseTheme.copyWith(
    textTheme: _boldTextTheme(baseTheme.textTheme),
    primaryTextTheme: _boldTextTheme(baseTheme.primaryTextTheme),
    appBarTheme: baseTheme.appBarTheme.copyWith(
      titleTextStyle: _boldTextStyle(baseTheme.appBarTheme.titleTextStyle),
      toolbarTextStyle: _boldTextStyle(baseTheme.appBarTheme.toolbarTextStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _boldButtonTextStyle(baseTheme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _boldButtonTextStyle(baseTheme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _boldButtonTextStyle(baseTheme.textButtonTheme.style),
    ),
  );
}

TextTheme _boldTextTheme(TextTheme textTheme) {
  return textTheme.copyWith(
    displayLarge: _boldTextStyle(textTheme.displayLarge),
    displayMedium: _boldTextStyle(textTheme.displayMedium),
    displaySmall: _boldTextStyle(textTheme.displaySmall),
    headlineLarge: _boldTextStyle(textTheme.headlineLarge),
    headlineMedium: _boldTextStyle(textTheme.headlineMedium),
    headlineSmall: _boldTextStyle(textTheme.headlineSmall),
    titleLarge: _boldTextStyle(textTheme.titleLarge),
    titleMedium: _boldTextStyle(textTheme.titleMedium),
    titleSmall: _boldTextStyle(textTheme.titleSmall),
    bodyLarge: _boldTextStyle(textTheme.bodyLarge),
    bodyMedium: _boldTextStyle(textTheme.bodyMedium),
    bodySmall: _boldTextStyle(textTheme.bodySmall),
    labelLarge: _boldTextStyle(textTheme.labelLarge),
    labelMedium: _boldTextStyle(textTheme.labelMedium),
    labelSmall: _boldTextStyle(textTheme.labelSmall),
  );
}

ButtonStyle _boldButtonTextStyle(ButtonStyle? baseStyle) {
  return (baseStyle ?? const ButtonStyle()).copyWith(
    textStyle: WidgetStateProperty.resolveWith((states) {
      return _boldTextStyle(baseStyle?.textStyle?.resolve(states));
    }),
  );
}

TextStyle _boldTextStyle(TextStyle? style) {
  final currentWeight = style?.fontWeight ?? FontWeight.w400;
  final currentIndex = FontWeight.values.indexOf(currentWeight);
  final minimumBoldIndex = FontWeight.values.indexOf(FontWeight.w700);
  final nextIndex = math.min(
    FontWeight.values.length - 1,
    math.max(currentIndex + 2, minimumBoldIndex),
  );
  return (style ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.values[nextIndex],
  );
}

class HomeScreen extends StatefulWidget {
  HomeScreen({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.routeFeedbackRepository,
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    required this.searchHistoryRepository,
    required this.internalRouteRepository,
    required this.networkMapRepository,
    required this.realtimeRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.locationProvider,
    required this.supportAccessInfo,
    required this.supportAccessLauncher,
    required this.userDataDeletionRepository,
    required this.onUserDataDeleted,
    required this.onMobilityProfileChanged,
    required this.onViewPreferencesChanged,
    required this.recentRoutesFuture,
    this.viewPreferences = const OnboardingViewPreferences.defaults(),
    this.simpleViewEnabled = true,
    this.facilityReportDraftTargetStore,
    String? initialMobilityType,
    super.key,
  }) : initialMobilityType =
           initialMobilityType ?? mobilityProfileOptions.first.mobilityType;

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final InternalRouteRepository internalRouteRepository;
  final NetworkMapRepository networkMapRepository;
  final RealtimeRepository realtimeRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final SupportAccessInfo supportAccessInfo;
  final SupportAccessLauncher supportAccessLauncher;
  final UserDataDeletionRepository? userDataDeletionRepository;
  final Future<void> Function(UserDataDeletionResult result)? onUserDataDeleted;
  final Future<void> Function(MobilityProfileOption profile)?
  onMobilityProfileChanged;
  final Future<void> Function(OnboardingViewPreferences preferences)
  onViewPreferencesChanged;
  final Future<List<FavoriteRoute>>? recentRoutesFuture;
  final String initialMobilityType;
  final OnboardingViewPreferences viewPreferences;
  final bool simpleViewEnabled;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTabIndex = 0;
  late String _mobilityType;
  late final RouteDraftController _routeDraftController;
  Future<List<FavoriteRoute>>? _recentRoutesFuture;
  Future<List<FavoriteFacility>>? _favoriteFacilitiesFuture;
  late Future<bool> _hasNotificationItemsFuture;

  @override
  void initState() {
    super.initState();
    _mobilityType = widget.initialMobilityType;
    _routeDraftController = RouteDraftController();
    _recentRoutesFuture = _loadRecentRoutes();
    final facilitiesFuture = widget.favoriteFacilityRepository
        ?.listFavoriteFacilities();
    _favoriteFacilitiesFuture = facilitiesFuture;
    _hasNotificationItemsFuture = _loadHasNotificationItems(facilitiesFuture);
  }

  @override
  void dispose() {
    _routeDraftController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_mobilityType == oldWidget.initialMobilityType &&
        widget.initialMobilityType != oldWidget.initialMobilityType) {
      _mobilityType = widget.initialMobilityType;
    }
    if (widget.recentRoutesFuture != oldWidget.recentRoutesFuture ||
        widget.favoriteRouteRepository != oldWidget.favoriteRouteRepository) {
      _recentRoutesFuture = _loadRecentRoutes();
    }
    if (widget.favoriteFacilityRepository !=
        oldWidget.favoriteFacilityRepository) {
      final facilitiesFuture = widget.favoriteFacilityRepository
          ?.listFavoriteFacilities();
      _favoriteFacilitiesFuture = facilitiesFuture;
      _hasNotificationItemsFuture = _loadHasNotificationItems(facilitiesFuture);
    }
    if (widget.reportRepository != oldWidget.reportRepository ||
        widget.notificationRepository != oldWidget.notificationRepository) {
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
    final searchHistoryRepository = widget.searchHistoryRepository;
    final internalRouteRepository = widget.internalRouteRepository;
    final networkMapRepository = widget.networkMapRepository;
    final realtimeRepository = widget.realtimeRepository;
    final routeFeedbackRepository = widget.routeFeedbackRepository;
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
    final currentProfile = mobilityProfileOptions.firstWhere(
      (option) => option.mobilityType == _mobilityType,
      orElse: () => mobilityProfileOptions.first,
    );
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

    void openSettings() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AppSettingsScreen(
            currentProfile: currentProfile,
            viewPreferences: widget.viewPreferences,
            notificationRepository: notificationRepository,
            notificationPermissionProvider: notificationPermissionProvider,
            onViewPreferencesChanged: widget.onViewPreferencesChanged,
            onOpenMobilityProfile: _openMobilityProfile,
            onOpenSupportAccess: openSupportAccess,
            onOpenMyReports: openMyReports,
          ),
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

    void openRouteTab() {
      if (_selectedTabIndex == 2) {
        return;
      }
      setState(() {
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
      final facilitiesFuture = widget.favoriteFacilityRepository
          ?.listFavoriteFacilities();
      final routesFuture = _loadRecentRoutes();
      final hasNotificationItemsFuture = _loadHasNotificationItems(
        facilitiesFuture,
      );
      setState(() {
        _favoriteFacilitiesFuture = facilitiesFuture;
        _recentRoutesFuture = routesFuture;
        _hasNotificationItemsFuture = hasNotificationItemsFuture;
      });
      try {
        await Future.wait<void>([
          if (facilitiesFuture != null) facilitiesFuture.then((_) {}),
          if (routesFuture != null) routesFuture.then((_) {}),
          hasNotificationItemsFuture.then((_) {}),
        ]);
      } catch (error, stackTrace) {
        (error, stackTrace);
        // FutureBuilder가 오류 상태를 표시하므로 refresh callback은 정상 종료한다.
      }
    }

    Future<void> openStationSearch([
      StationSearchEntryMode entryMode = StationSearchEntryMode.search,
    ]) async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
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
            entryMode: entryMode,
          ),
        ),
      );
      if (!context.mounted) {
        return;
      }
      await refreshHomeState();
    }

    Future<void> openRouteSearch([String? mobilityType]) async {
      final routeSearchMobilityType = mobilityType ?? initialMobilityType;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RouteSearchScreen(
            repository: routeRepository,
            stationRepository: repository,
            routeFeedbackRepository: routeFeedbackRepository,
            favoriteRouteRepository: favoriteRouteRepository,
            initialMobilityType: routeSearchMobilityType,
            initialDraft: _routeDraftController.draft,
            simpleViewEnabled: simpleViewEnabled,
          ),
        ),
      );
      if (!context.mounted) {
        return;
      }
      await refreshHomeState();
    }

    Future<void> openFavorites() async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FavoriteHomeScreen(
            favoriteRepository: favoriteRepository,
            favoriteFacilityRepository: favoriteFacilityRepository,
            favoriteRouteRepository: favoriteRouteRepository,
            stationRepository: repository,
            reportRepository: reportRepository,
            locationProvider: locationProvider,
            facilityReportDraftTargetStore: facilityReportDraftTargetStore,
            internalRouteRepository: internalRouteRepository,
            realtimeRepository: realtimeRepository,
            routeDraftController: _routeDraftController,
            initialMobilityType: initialMobilityType,
            onOpenRouteSearch: openRouteSearch,
          ),
        ),
      );
      if (!context.mounted) {
        return;
      }
      await refreshHomeState();
    }

    void openSavedItems() {
      if (favoriteRepository == null &&
          favoriteFacilityRepository == null &&
          favoriteRouteRepository == null) {
        openSettings();
        return;
      }
      unawaited(openFavorites());
    }

    void openNetworkMap() {
      if (_selectedTabIndex == 1) {
        return;
      }
      setState(() {
        _selectedTabIndex = 1;
      });
    }

    final heroSection = _HomeHero(
      profile: currentProfile,
      onRouteSearch: openRouteTab,
      onStationSearch: () => unawaited(openStationSearch()),
      onProfileTap: openSettings,
    );
    final routeDraftSection = AnimatedBuilder(
      animation: _routeDraftController,
      builder: (context, _) {
        final draft = _routeDraftController.draft;
        if (draft.origin == null && draft.destination == null) {
          return const SizedBox.shrink();
        }
        return _HomeRouteDraftCard(draft: draft, onTap: openRouteSearch);
      },
    );
    final stationActions = _HomeStationActionRow(
      onRecentSearch: () =>
          unawaited(openStationSearch(StationSearchEntryMode.recent)),
      onNearbyStations: () =>
          unawaited(openStationSearch(StationSearchEntryMode.nearby)),
    );
    final facilitySection = _HomeFacilityAlertSection(
      facilitiesFuture: _favoriteFacilitiesFuture,
      onOpenFacilities: openSavedItems,
      onRetry: () => unawaited(refreshHomeState()),
    );
    final recentRouteSection = _HomeRecentRouteSection(
      key: const Key('homeRecentRouteSection'),
      routesFuture: _recentRoutesFuture,
      onTap: openRouteSearch,
      onRetry: () => unawaited(refreshHomeState()),
    );
    final bottomNavigationBar = NavigationBar(
      key: const Key('homeBottomNavigationBar'),
      selectedIndex: _selectedTabIndex,
      height: 72,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            openHomeTab();
            break;
          case 1:
            openNetworkMap();
            break;
          case 2:
            openRouteTab();
            break;
          case 3:
            openSavedTab();
            break;
          case 4:
            openMoreTab();
            break;
        }
      },
      destinations: const [
        NavigationDestination(
          key: Key('bottomNavHome'),
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: '홈',
        ),
        NavigationDestination(
          key: Key('bottomNavMap'),
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: '노선도',
        ),
        NavigationDestination(
          key: Key('bottomNavRoute'),
          icon: Icon(Icons.route_outlined),
          selectedIcon: Icon(Icons.route),
          label: '길찾기',
        ),
        NavigationDestination(
          key: Key('bottomNavSaved'),
          icon: Icon(Icons.star_border),
          selectedIcon: Icon(Icons.star),
          label: '즐겨찾기',
        ),
        NavigationDestination(
          key: Key('bottomNavMore'),
          icon: Icon(Icons.more_horiz),
          selectedIcon: Icon(Icons.more),
          label: '더보기',
        ),
      ],
    );

    if (_selectedTabIndex == 1) {
      return NetworkMapScreen(
        repository: networkMapRepository,
        routeDraftController: _routeDraftController,
        onOpenRouteSearch: openRouteSearch,
        onOpenStationSearch: () => unawaited(openStationSearch()),
        bottomNavigationBar: bottomNavigationBar,
      );
    }

    if (_selectedTabIndex == 2) {
      return RouteSearchScreen(
        repository: routeRepository,
        stationRepository: repository,
        routeFeedbackRepository: routeFeedbackRepository,
        favoriteRouteRepository: favoriteRouteRepository,
        initialMobilityType: initialMobilityType,
        initialDraft: _routeDraftController.draft,
        simpleViewEnabled: simpleViewEnabled,
        shellNavigationBar: bottomNavigationBar,
      );
    }

    if (_selectedTabIndex == 3) {
      return FavoriteHomeScreen(
        favoriteRepository: favoriteRepository,
        favoriteFacilityRepository: favoriteFacilityRepository,
        favoriteRouteRepository: favoriteRouteRepository,
        stationRepository: repository,
        reportRepository: reportRepository,
        locationProvider: locationProvider,
        facilityReportDraftTargetStore: facilityReportDraftTargetStore,
        internalRouteRepository: internalRouteRepository,
        realtimeRepository: realtimeRepository,
        routeDraftController: _routeDraftController,
        initialMobilityType: initialMobilityType,
        onOpenRouteSearch: ([mobilityType]) async => openRouteTab(),
        bottomNavigationBar: bottomNavigationBar,
      );
    }

    if (_selectedTabIndex == 4) {
      return AppSettingsScreen(
        currentProfile: currentProfile,
        viewPreferences: widget.viewPreferences,
        notificationRepository: notificationRepository,
        notificationPermissionProvider: notificationPermissionProvider,
        onViewPreferencesChanged: widget.onViewPreferencesChanged,
        onOpenMobilityProfile: _openMobilityProfile,
        onOpenSupportAccess: openSupportAccess,
        onOpenMyReports: openMyReports,
        bottomNavigationBar: bottomNavigationBar,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('쉬운 지하철'),
        actions: [
          FutureBuilder<bool>(
            future: _hasNotificationItemsFuture,
            builder: (context, snapshot) {
              return _HomeNotificationButton(
                key: const Key('homeNotificationActionButton'),
                hasNotificationItems: snapshot.data ?? false,
                onPressed: notificationRepository == null
                    ? openSettings
                    : openNotificationInbox,
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isLargeScreen = EasySubwayAdaptiveLayout.isLargeScreen(
              constraints,
            );
            return RefreshIndicator(
              key: const Key('homeRefreshIndicator'),
              onRefresh: refreshHomeState,
              child: ListView(
                key: const Key('homeContentList'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: isLargeScreen
                    ? const EdgeInsets.fromLTRB(24, 24, 24, 112)
                    : const EdgeInsets.fromLTRB(17, 18, 17, 96),
                children: [
                  _HomeAdaptiveContent(
                    isLargeScreen: isLargeScreen,
                    heroSection: heroSection,
                    routeDraftSection: routeDraftSection,
                    stationActions: stationActions,
                    facilitySection: facilitySection,
                    recentRouteSection: recentRouteSection,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }

  Future<List<FavoriteRoute>>? _loadRecentRoutes() {
    return widget.recentRoutesFuture ??
        widget.favoriteRouteRepository?.listFavoriteRoutes();
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
        if (facilities.any(_isFacilityAlert)) {
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

  Future<MobilityProfileOption?> _openMobilityProfile() async {
    final currentProfile = mobilityProfileOptions.firstWhere(
      (option) => option.mobilityType == _mobilityType,
      orElse: () => mobilityProfileOptions.first,
    );
    final selectedProfile = await Navigator.of(context).push(
      MaterialPageRoute<MobilityProfileOption>(
        builder: (_) => MobilityProfileScreen(initialSelection: currentProfile),
      ),
    );
    if (!mounted || selectedProfile == null) {
      return null;
    }
    final previousMobilityType = _mobilityType;
    setState(() {
      _mobilityType = selectedProfile.mobilityType;
    });
    try {
      await widget.onMobilityProfileChanged?.call(selectedProfile);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '이동 조건 저장 중 예외가 발생했습니다.');
      if (!mounted) {
        return null;
      }
      setState(() {
        _mobilityType = previousMobilityType;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이동 조건을 저장하지 못했습니다. 이전 조건으로 되돌렸어요.')),
      );
      return null;
    }
    if (!mounted) {
      return null;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selectedProfile.title} 조건으로 변경했습니다')),
    );
    return selectedProfile;
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
      label: hasNotificationItems ? '알림, 확인할 알림 있음' : '알림, 새 알림 없음',
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
                foregroundColor: EasySubwayAccessibleColors.mintDark,
                side: const BorderSide(
                  color: EasySubwayAccessibleColors.line,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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

class _HomeAdaptiveContent extends StatelessWidget {
  const _HomeAdaptiveContent({
    required this.isLargeScreen,
    required this.heroSection,
    required this.routeDraftSection,
    required this.stationActions,
    required this.facilitySection,
    required this.recentRouteSection,
  });

  final bool isLargeScreen;
  final Widget heroSection;
  final Widget routeDraftSection;
  final Widget stationActions;
  final Widget facilitySection;
  final Widget recentRouteSection;

  @override
  Widget build(BuildContext context) {
    if (!isLargeScreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heroSection,
          routeDraftSection,
          stationActions,
          facilitySection,
          recentRouteSection,
        ],
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: EasySubwayAdaptiveLayout.largeScreenMaxContentWidth,
        ),
        child: Row(
          key: const Key('homeLargeScreenLayout'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: heroSection),
            const SizedBox(
              width: EasySubwayAdaptiveLayout.largeScreenColumnGap,
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  routeDraftSection,
                  stationActions,
                  facilitySection,
                  recentRouteSection,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({
    required this.favoriteFacilityRepository,
    required this.reportRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    super.key,
  });

  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FacilityReportRepository reportRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;

  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  late Future<List<_NotificationInboxItem>> _itemsFuture;

  @override
  void initState() {
    super.initState();
    _itemsFuture = _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          if (widget.notificationRepository != null)
            IconButton(
              tooltip: '알림 설정',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<_NotificationInboxItem>>(
          future: _itemsFuture,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <_NotificationInboxItem>[];
            return RefreshIndicator(
              onRefresh: () async {
                final next = _loadItems();
                setState(() {
                  _itemsFuture = next;
                });
                await next;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(17, 18, 17, 32),
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator(minHeight: 3),
                  if (items.isEmpty)
                    const _AppCard(
                      child: _AppInfoRow(
                        icon: Icons.notifications_none,
                        iconBackground: EasySubwayAccessibleColors.mintSoft,
                        iconColor: EasySubwayAccessibleColors.mintDark,
                        title: '새 알림이 없습니다',
                        subtitle: '즐겨찾기 시설과 제보 상태가 바뀌면 여기에서 볼 수 있어요.',
                      ),
                    )
                  else ...[
                    _NotificationInboxChips(items: items),
                    const SizedBox(height: 12),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _NotificationInboxCard(item: item),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<List<_NotificationInboxItem>> _loadItems() async {
    final items = <_NotificationInboxItem>[];
    final favoriteFacilityRepository = widget.favoriteFacilityRepository;
    if (favoriteFacilityRepository != null) {
      try {
        final facilities = await favoriteFacilityRepository
            .listFavoriteFacilities();
        for (final facility in facilities.where(_isFacilityAlert)) {
          items.add(_NotificationInboxItem.facility(facility));
        }
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '알림함 즐겨찾기 시설 상태를 불러오는 중 예외가 발생했습니다.',
        );
      }
    }

    try {
      final reports = await widget.reportRepository.listMyReports();
      for (final report in reports) {
        items.add(_NotificationInboxItem.report(report));
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '알림함 제보 상태를 불러오는 중 예외가 발생했습니다.',
      );
    }
    return items;
  }

  void _openSettings() {
    final repository = widget.notificationRepository;
    if (repository == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationSettingsScreen(
          repository: repository,
          notificationPermissionProvider: widget.notificationPermissionProvider,
        ),
      ),
    );
  }
}

class _NotificationInboxItem {
  const _NotificationInboxItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.kind,
    this.report,
    this.severity = FacilityStatusSeverity.normal,
    this.actionLabel = '',
  });

  factory _NotificationInboxItem.facility(FavoriteFacility facility) {
    final name = facility.name.trim().isEmpty
        ? facility.typeLabel
        : facility.name;
    return _NotificationInboxItem(
      icon: _facilityIcon(facility.type),
      title: '${facility.stationLabel} $name',
      subtitle:
          '${facility.severityLabel} · ${facility.typeLabel} ${facility.statusLabel}',
      semanticLabel:
          '${facility.stationLabel} $name, ${facility.typeLabel} ${facility.statusLabel}, ${facility.severityLabel}, ${facility.updatedLabel}, ${facility.dataSourceLabel}, ${facility.nextActionLabel}',
      kind: '시설',
      severity: facility.statusPresentation.severity,
      actionLabel: facility.nextActionLabel,
    );
  }

  factory _NotificationInboxItem.report(FacilityReportResult report) {
    return _NotificationInboxItem(
      icon: Icons.report_outlined,
      title: '제보 ${report.statusLabel}',
      subtitle: '제보 번호 ${report.displayReceiptCode}',
      semanticLabel:
          '제보 ${report.statusLabel}, 제보 번호 ${report.displayReceiptCode}',
      kind: '제보',
      report: report,
    );
  }

  final IconData icon;
  final String title;
  final String subtitle;
  final String semanticLabel;
  final String kind;
  final FacilityReportResult? report;
  final FacilityStatusSeverity severity;
  final String actionLabel;
}

class _NotificationInboxChips extends StatelessWidget {
  const _NotificationInboxChips({required this.items});

  final List<_NotificationInboxItem> items;

  @override
  Widget build(BuildContext context) {
    final facilityCount = items.where((item) => item.kind == '시설').length;
    final reportCount = items.length - facilityCount;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _HomeMiniBadge('전체 ${items.length}'),
        if (facilityCount > 0) _HomeMiniBadge('시설 $facilityCount'),
        if (reportCount > 0) _HomeMiniBadge('제보 $reportCount'),
      ],
    );
  }
}

class _NotificationInboxCard extends StatelessWidget {
  const _NotificationInboxCard({required this.item});

  final _NotificationInboxItem item;

  @override
  Widget build(BuildContext context) {
    void open() {
      final report = item.report;
      if (report == null) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MyFacilityReportDetailScreen(report: report),
        ),
      );
    }

    final accent = _facilitySeverityAccent(item.severity);
    final card = _AppCard(
      backgroundColor: accent.backgroundColor,
      borderColor: accent.borderColor,
      showBorder: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AppInfoRow(
            icon: item.icon,
            iconBackground: Colors.white,
            iconColor: accent.iconColor,
            title: item.title,
            subtitle: item.subtitle,
            subtitleColor: accent.iconColor,
            trailing: item.kind,
          ),
          if (item.actionLabel.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              item.actionLabel,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
    if (item.report == null) {
      return Semantics(label: item.semanticLabel, child: card);
    }
    return Semantics(
      button: true,
      label: item.semanticLabel,
      onTap: open,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(20),
          child: card,
        ),
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.profile,
    required this.onRouteSearch,
    required this.onStationSearch,
    required this.onProfileTap,
  });

  final MobilityProfileOption profile;
  final VoidCallback onRouteSearch;
  final VoidCallback onStationSearch;
  final VoidCallback onProfileTap;

  static const double _cardRadius = 18;
  static const double _buttonRadius = 12;
  static const FontWeight _heroTitleWeight = FontWeight.w800;
  static const FontWeight _primaryActionWeight = FontWeight.w800;
  static const FontWeight _secondaryActionWeight = FontWeight.w700;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '길찾기와 역 검색, 현재 이동 조건 ${profile.title}',
      child: Material(
        key: const Key('homeHeroCard'),
        color: EasySubwayAccessibleColors.brand,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Text(
                  '어디로 가시나요?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: _heroTitleWeight,
                    height: 1.28,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: _HomeProfilePill(profile: profile, onTap: onProfileTap),
              ),
              const SizedBox(height: 18),
              Semantics(
                key: const Key('routeSearchButton'),
                button: true,
                label: '길찾기',
                onTap: onRouteSearch,
                child: ExcludeSemantics(
                  child: FilledButton.icon(
                    onPressed: onRouteSearch,
                    style: FilledButton.styleFrom(
                      backgroundColor: EasySubwayAccessibleColors.brandDark,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(104),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_buttonRadius),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 22,
                        fontWeight: _primaryActionWeight,
                      ),
                    ),
                    icon: const Icon(Icons.route),
                    label: const Text('길찾기'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              KeyedSubtree(
                key: const Key('heroStationSearchButton'),
                child: Semantics(
                  key: const Key('stationSearchButton'),
                  button: true,
                  label: '역 검색',
                  onTap: onStationSearch,
                  child: ExcludeSemantics(
                    child: OutlinedButton.icon(
                      onPressed: onStationSearch,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: EasySubwayAccessibleColors.brandDark,
                        side: const BorderSide(
                          color: EasySubwayAccessibleColors.line,
                        ),
                        minimumSize: const Size.fromHeight(68),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_buttonRadius),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: _secondaryActionWeight,
                        ),
                      ),
                      icon: const Icon(Icons.search),
                      label: const Text('역 검색'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeStationActionRow extends StatelessWidget {
  const _HomeStationActionRow({
    required this.onRecentSearch,
    required this.onNearbyStations,
  });

  final VoidCallback onRecentSearch;
  final VoidCallback onNearbyStations;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: _HomeStationActionButton(
              key: const Key('recentSearchButton'),
              icon: Icons.search,
              label: '최근 검색',
              onPressed: onRecentSearch,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: KeyedSubtree(
              key: const Key('nearbyStationHomeButton'),
              child: _HomeStationActionButton(
                key: const Key('nearbyStationButton'),
                icon: Icons.location_on_outlined,
                label: '가까운 역',
                onPressed: onNearbyStations,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeStationActionButton extends StatelessWidget {
  const _HomeStationActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: EasySubwayAccessibleColors.brandDark,
        side: const BorderSide(color: EasySubwayAccessibleColors.line),
        minimumSize: const Size.fromHeight(72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 28),
      label: Text(label),
    );
  }
}

class _HomeProfilePill extends StatelessWidget {
  const _HomeProfilePill({required this.profile, required this.onTap});

  final MobilityProfileOption profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '이동 조건: ${profile.title}, 변경',
      onTap: onTap,
      child: ExcludeSemantics(
        child: OutlinedButton.icon(
          key: const Key('homeProfilePill'),
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            backgroundColor: Colors.white.withValues(alpha: 0.11),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.26)),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: Icon(profile.icon, size: 16),
          label: Text(
            '이동 조건: ${profile.title} 〉',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _HomeRouteDraftCard extends StatelessWidget {
  const _HomeRouteDraftCard({required this.draft, required this.onTap});

  final RouteDraft draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasOrigin = draft.origin != null;
    final hasDestination = draft.destination != null;
    final summary = hasOrigin || hasDestination
        ? '${draft.originLabel} → ${draft.destinationLabel}'
        : '출발역과 도착역을 선택해 주세요';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        button: true,
        label: '출발 도착 정하기, $summary',
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            key: const Key('homeRouteDraftPanel'),
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: _AppCard(
              backgroundColor: EasySubwayAccessibleColors.skySoft,
              borderColor: const Color(0xFFB7DDF4),
              borderRadius: 18,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.route_outlined,
                      color: EasySubwayAccessibleColors.brand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '출발·도착 정하기',
                          style: TextStyle(
                            color: EasySubwayAccessibleColors.brand,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          summary,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: EasySubwayAccessibleColors.text,
                                fontWeight: FontWeight.w900,
                                height: 1.35,
                              ),
                        ),
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
      ),
    );
  }
}

class _AppSectionTitle extends StatelessWidget {
  const _AppSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 22, 1, 11),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w900,
          height: 1.2,
        ),
      ),
    );
  }
}

class _HomeFacilityAlertSection extends StatelessWidget {
  const _HomeFacilityAlertSection({
    required this.facilitiesFuture,
    required this.onOpenFacilities,
    required this.onRetry,
  });

  final Future<List<FavoriteFacility>>? facilitiesFuture;
  final VoidCallback onOpenFacilities;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final facilitiesFuture = this.facilitiesFuture;
    if (facilitiesFuture == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<FavoriteFacility>>(
      future: facilitiesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _HomeStateSection(
            title: '시설 알림',
            child: _HomeStateCard(
              key: Key('homeFacilityAlertLoadingState'),
              icon: Icons.hourglass_empty,
              title: '저장한 시설 상태를 확인하고 있어요',
              subtitle: '잠시 후 고장·공사 알림을 보여드릴게요.',
            ),
          );
        }
        if (snapshot.hasError) {
          return _HomeStateSection(
            title: '시설 알림',
            child: _HomeStateCard(
              key: const Key('homeFacilityAlertErrorState'),
              icon: Icons.error_outline,
              title: '시설 알림을 불러오지 못했어요',
              subtitle: '네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
              actionLabel: '다시 시도',
              onAction: onRetry,
            ),
          );
        }
        final alert = _firstFacilityAlert(
          snapshot.data ?? const <FavoriteFacility>[],
        );
        if (alert == null) {
          return const _HomeStateSection(
            title: '시설 알림',
            child: _HomeStateCard(
              key: Key('homeFacilityAlertEmptyState'),
              icon: Icons.check_circle_outline,
              title: '확인할 시설 알림이 없어요',
              subtitle: '저장한 시설에 고장·공사 알림이 생기면 여기에서 알려드려요.',
            ),
          );
        }
        return _HomeStateSection(
          title: '시설 알림',
          child: _HomeFacilityAlertCard(
            facility: alert,
            onOpenFacilities: onOpenFacilities,
          ),
        );
      },
    );
  }
}

class _HomeFacilityAlertCard extends StatelessWidget {
  const _HomeFacilityAlertCard({
    required this.facility,
    required this.onOpenFacilities,
  });

  final FavoriteFacility facility;
  final VoidCallback onOpenFacilities;

  @override
  Widget build(BuildContext context) {
    final facilityName = facility.name.trim().isEmpty
        ? facility.typeLabel
        : facility.name;
    final accent = _facilitySeverityAccent(
      facility.statusPresentation.severity,
    );
    final semanticLabel =
        '${facility.stationLabel} $facilityName, ${facility.typeLabel} ${facility.statusLabel}, ${facility.severityLabel}, ${facility.updatedLabel}, ${facility.dataSourceLabel}, ${facility.nextActionLabel}';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: _AppCard(
        backgroundColor: accent.backgroundColor,
        borderColor: accent.borderColor,
        showBorder: true,
        child: Column(
          children: [
            _AppInfoRow(
              icon: _facilityIcon(facility.type),
              iconBackground: Colors.white,
              iconColor: accent.iconColor,
              title: '${facility.stationLabel} $facilityName',
              subtitle:
                  '${facility.severityLabel} · ${facility.typeLabel} ${facility.statusLabel}',
              subtitleColor: accent.iconColor,
              iconBoxSize: 56,
              iconSize: 30,
            ),
            const SizedBox(height: 13),
            _HomeFacilityNoticeMessage(
              facility: facility,
              onOpenFacilities: onOpenFacilities,
            ),
          ],
        ),
      ),
    );
  }
}

class _FacilitySeverityAccent {
  const _FacilitySeverityAccent({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
}

_FacilitySeverityAccent _facilitySeverityAccent(
  FacilityStatusSeverity severity,
) {
  return switch (severity) {
    FacilityStatusSeverity.blocked => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.redSoft,
      borderColor: EasySubwayAccessibleColors.red,
      iconColor: EasySubwayAccessibleColors.red,
    ),
    FacilityStatusSeverity.caution => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.amberSoft,
      borderColor: Color(0xFFF1D49A),
      iconColor: EasySubwayAccessibleColors.amber,
    ),
    FacilityStatusSeverity.needsInfo => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.skySoft,
      borderColor: Color(0xFFC8E6F8),
      iconColor: EasySubwayAccessibleColors.brand,
    ),
    FacilityStatusSeverity.normal => const _FacilitySeverityAccent(
      backgroundColor: Colors.white,
      borderColor: EasySubwayAccessibleColors.line,
      iconColor: EasySubwayAccessibleColors.mintDark,
    ),
  };
}

class _HomeFacilityNoticeMessage extends StatelessWidget {
  const _HomeFacilityNoticeMessage({
    required this.facility,
    required this.onOpenFacilities,
  });

  final FavoriteFacility facility;
  final VoidCallback onOpenFacilities;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              facility.nextActionDescription,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('homeFacilityActionButton'),
              onPressed: onOpenFacilities,
              icon: const Icon(Icons.open_in_new),
              label: const Text('저장한 시설 보기'),
            ),
            const SizedBox(height: 8),
            Text(
              '${facility.updatedLabel} · ${facility.dataSourceLabel}',
              style: const TextStyle(
                color: EasySubwayAccessibleColors.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isFacilityAlert(FavoriteFacility facility) {
  return facility.needsAttention;
}

FavoriteFacility? _firstFacilityAlert(List<FavoriteFacility> facilities) {
  final alerts = facilities.where(_isFacilityAlert).toList(growable: false);
  if (alerts.isEmpty) {
    return null;
  }
  alerts.sort((left, right) {
    final priority = left.statusPriority.compareTo(right.statusPriority);
    if (priority != 0) {
      return priority;
    }
    return left.name.compareTo(right.name);
  });
  return alerts.first;
}

IconData _facilityIcon(String type) {
  return switch (type) {
    'ELEVATOR' => Icons.elevator_outlined,
    'ESCALATOR' => Icons.escalator_warning_outlined,
    'WHEELCHAIR_LIFT' => Icons.accessible_forward,
    'RAMP' => Icons.accessible,
    'ACCESSIBLE_TOILET' || 'TOILET' => Icons.wc_outlined,
    _ => Icons.warning_amber_outlined,
  };
}

class _HomeRecentRouteSection extends StatelessWidget {
  const _HomeRecentRouteSection({
    super.key,
    required this.routesFuture,
    required this.onTap,
    required this.onRetry,
  });

  final Future<List<FavoriteRoute>>? routesFuture;
  final Future<void> Function() onTap;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final routesFuture = this.routesFuture;
    if (routesFuture == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<FavoriteRoute>>(
      future: routesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _HomeStateSection(
            title: '최근 경로',
            child: _HomeStateCard(
              key: Key('homeRecentRouteLoadingState'),
              icon: Icons.hourglass_empty,
              title: '최근 경로를 확인하고 있어요',
              subtitle: '저장된 경로가 있으면 바로 이어서 보여드릴게요.',
            ),
          );
        }
        if (snapshot.hasError) {
          return _HomeStateSection(
            title: '최근 경로',
            child: _HomeStateCard(
              key: const Key('homeRecentRouteErrorState'),
              icon: Icons.error_outline,
              title: '최근 경로를 불러오지 못했어요',
              subtitle: '저장된 경로를 확인하려면 다시 시도해 주세요.',
              actionLabel: '다시 시도',
              onAction: onRetry,
            ),
          );
        }
        final routes = snapshot.data ?? const <FavoriteRoute>[];
        if (routes.isEmpty) {
          return _HomeStateSection(
            title: '최근 경로',
            child: _HomeStateCard(
              key: const Key('homeRecentRouteEmptyState'),
              icon: Icons.route_outlined,
              title: '최근 경로가 아직 없어요',
              subtitle: '길찾기를 한 번 사용하면 자주 확인하는 경로를 이어서 볼 수 있어요.',
              actionLabel: '길찾기 시작',
              onAction: () => unawaited(onTap()),
            ),
          );
        }
        return _HomeStateSection(
          title: '최근 경로',
          child: _HomeRecentRouteCard(route: routes.first, onTap: onTap),
        );
      },
    );
  }
}

class _HomeStateSection extends StatelessWidget {
  const _HomeStateSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppSectionTitle(title: title),
        child,
      ],
    );
  }
}

class _HomeStateCard extends StatelessWidget {
  const _HomeStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final actionLabel = this.actionLabel;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title, $subtitle',
      child: _AppCard(
        showBorder: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AppInfoRow(
              icon: icon,
              iconBackground: EasySubwayAccessibleColors.mintSoft,
              iconColor: EasySubwayAccessibleColors.mintDark,
              title: title,
              subtitle: subtitle,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeRecentRouteCard extends StatelessWidget {
  const _HomeRecentRouteCard({required this.route, required this.onTap});

  final FavoriteRoute route;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final originName = _stationNameWithSuffix(route.originStationName);
    final destinationName = _stationNameWithSuffix(
      route.destinationStationName,
    );
    return Semantics(
      button: true,
      label: '최근 경로, $originName에서 $destinationName까지, ${route.lineLabel}',
      onTap: () => unawaited(onTap()),
      child: ExcludeSemantics(
        child: InkWell(
          key: const Key('homeRecentRouteCard'),
          onTap: () => unawaited(onTap()),
          borderRadius: BorderRadius.circular(26),
          child: _AppCard(
            borderRadius: 26,
            showBorder: true,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _HomeRouteStationLabel(
                    stationName: originName,
                    route: route,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 20,
                    color: EasySubwayAccessibleColors.text,
                  ),
                ),
                Expanded(
                  child: _HomeRouteStationLabel(
                    stationName: destinationName,
                    route: route,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeRouteStationLabel extends StatelessWidget {
  const _HomeRouteStationLabel({
    required this.stationName,
    required this.route,
  });

  static const double _stationFontSize = 17;
  static const double _stationLineHeight = 1.2;
  static const double _lineSymbolSize = _stationFontSize * _stationLineHeight;

  final String stationName;
  final FavoriteRoute route;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final lineSymbolSize = textScaler.scale(_lineSymbolSize);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HomeLineSymbol(route: route, size: lineSymbolSize),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            stationName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.text,
              fontSize: _stationFontSize,
              fontWeight: FontWeight.w600,
              height: _stationLineHeight,
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeSavedRouteCard extends StatelessWidget {
  const _HomeSavedRouteCard({required this.route, required this.onTap});

  final FavoriteRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final originName = _stationNameWithSuffix(route.originStationName);
    final destinationName = _stationNameWithSuffix(
      route.destinationStationName,
    );
    return Semantics(
      button: true,
      label:
          '즐겨찾기 경로, $originName에서 $destinationName까지, ${route.lineLabel}, ${route.mobilityLabel}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: _AppCard(
            showBorder: true,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 21,
                  backgroundColor: EasySubwayAccessibleColors.mintSoft,
                  child: const Icon(
                    Icons.route_outlined,
                    color: EasySubwayAccessibleColors.mintDark,
                  ),
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
                          fontWeight: FontWeight.w900,
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

class _HomeLineSymbol extends StatelessWidget {
  const _HomeLineSymbol({required this.route, required this.size});

  final FavoriteRoute route;
  final double size;

  @override
  Widget build(BuildContext context) {
    return StationLineBadge(
      line: StationSearchLine(
        id: route.lineId,
        name: route.lineName,
        color: _lineColorForRoute(route),
        stationCode: '',
      ),
      size: size,
    );
  }
}

String _lineColorForRoute(FavoriteRoute route) {
  final lineId = route.lineId.toLowerCase();
  final lineName = route.lineName;
  if (lineId.contains('4') || lineName.contains('4호선')) {
    return '#00A5DE';
  }
  if (lineId.contains('1') || lineName.contains('1호선')) {
    return '#0052A4';
  }
  if (lineId.contains('2') || lineName.contains('2호선')) {
    return '#00A84D';
  }
  if (lineId.contains('3') || lineName.contains('3호선')) {
    return '#EF7C1C';
  }
  return '#006D77';
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
      backgroundColor: EasySubwayAccessibleColors.mintSoft,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
        color: EasySubwayAccessibleColors.mintDark,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        height: 1.2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({
    required this.child,
    this.backgroundColor = Colors.white,
    this.borderColor = EasySubwayAccessibleColors.line,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
    this.showBorder = false,
  });

  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: backgroundColor,
      elevation: 2,
      shadowColor: const Color(0x0A071B2F),
      shape: RoundedRectangleBorder(
        side: showBorder ? BorderSide(color: borderColor) : BorderSide.none,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

class _AppInfoRow extends StatelessWidget {
  const _AppInfoRow({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleColor = EasySubwayAccessibleColors.mutedText,
    this.iconBoxSize = 43,
    this.iconSize = 22,
    this.trailing,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color subtitleColor;
  final double iconBoxSize;
  final double iconSize;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final leading = Container(
      width: iconBoxSize,
      height: iconBoxSize,
      decoration: BoxDecoration(
        color: iconBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: iconColor, size: iconSize),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: EasySubwayAccessibleColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              color: subtitleColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    if (textScale >= 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: content),
            ],
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 55),
              child: Text(
                trailing!,
                style: const TextStyle(
                  color: EasySubwayAccessibleColors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      );
    }
    return Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(child: content),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            trailing!,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
    );
  }
}

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    required this.currentProfile,
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

  final MobilityProfileOption currentProfile;
  final OnboardingViewPreferences viewPreferences;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final Future<void> Function(OnboardingViewPreferences preferences)
  onViewPreferencesChanged;
  final Future<MobilityProfileOption?> Function() onOpenMobilityProfile;
  final VoidCallback onOpenSupportAccess;
  final VoidCallback onOpenMyReports;
  final Widget? bottomNavigationBar;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late MobilityProfileOption _profile = widget.currentProfile;
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
    return _OnboardingPreferenceScope(
      preferences: _viewPreferences,
      child: Scaffold(
        key: const Key('settingsScreen'),
        appBar: AppBar(title: const Text('설정')),
        bottomNavigationBar: widget.bottomNavigationBar,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _AppSettingsSection(
                key: const Key('settingsSection-mobility'),
                title: '이동 조건',
                children: [
                  _AppSettingsActionTile(
                    key: const Key('mobilityProfileButton'),
                    icon: Icons.directions_walk,
                    title: _profile.appliedConditionLabel,
                    subtitle: _profile.summary,
                    onTap: () async {
                      final selected = await widget.onOpenMobilityProfile();
                      if (!mounted || selected == null) {
                        return;
                      }
                      setState(() {
                        _profile = selected;
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
                    key: const Key('largeTextSettingsButton'),
                    icon: Icons.text_fields,
                    title: '큰 글자',
                    subtitle: '화면 글자와 버튼 설명을 더 크게 보여줘요',
                    enabled: _viewPreferences.largeTextEnabled,
                    onChanged: (value) {
                      _updateViewPreferences(
                        _viewPreferences.copyWith(largeTextEnabled: value),
                      );
                    },
                  ),
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
              _AppSettingsSection(
                key: const Key('settingsSection-region-data'),
                title: '저장된 안내',
                children: [
                  const _AppSettingsInfoTile(
                    icon: Icons.public,
                    title: '수도권 우선',
                    subtitle: '인터넷이 불안정해도 주요 역 정보를 먼저 보여줘요',
                  ),
                  _AppSettingsActionTile(
                    key: const Key('offlineDataSettingsButton'),
                    icon: Icons.offline_pin_outlined,
                    title: '인터넷 없이 이용',
                    subtitle: '노선도와 역 정보 사용 범위를 확인해요',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OfflineDataScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              _AppSettingsSection(
                key: const Key('settingsSection-notification'),
                title: '알림',
                children: [
                  if (widget.notificationRepository == null)
                    const _AppSettingsInfoTile(
                      icon: Icons.notifications_off_outlined,
                      title: '알림은 아직 사용할 수 없어요',
                      subtitle: '시설 상태와 제보 처리 안내는 앱 안에서 확인할 수 있어요',
                    )
                  else
                    _AppSettingsActionTile(
                      key: const Key('notificationSettingsButton'),
                      icon: Icons.notifications_active_outlined,
                      title: '알림 설정',
                      subtitle: '시설 상태, 제보 처리, 최신 안내 알림을 관리해요',
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
                    subtitle: '접수한 시설 제보와 처리 상태를 확인해요',
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
                    subtitle: '사용법, 개인정보, 문의 경로를 확인해요',
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
        const SnackBar(content: Text('설정을 저장하지 못했습니다. 이전 값으로 되돌렸어요.')),
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
                fontWeight: FontWeight.w900,
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
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$title, $subtitle',
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
              fontWeight: FontWeight.w800,
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

class _AppSettingsInfoTile extends StatelessWidget {
  const _AppSettingsInfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ListTile(
        minVerticalPadding: 12,
        minLeadingWidth: 32,
        leading: Icon(icon, color: EasySubwayAccessibleColors.mutedText),
        title: Text(
          title,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w800,
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
        shape: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
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
              fontWeight: FontWeight.w800,
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
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: enabled,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF0D8A6D),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFC8D3DC),
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
  final StationSearchRepository stationRepository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository internalRouteRepository;
  final RealtimeRepository realtimeRepository;
  final RouteDraftController routeDraftController;
  final String initialMobilityType;
  final Future<void> Function([String? mobilityType])? onOpenRouteSearch;
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
                padding: const EdgeInsets.fromLTRB(17, 18, 17, 32),
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator(minHeight: 3),
                  const _AppSectionTitle(title: '즐겨찾기한 항목'),
                  if (hasError)
                    _HomeStateCard(
                      key: const Key('favoriteHomeErrorState'),
                      icon: Icons.error_outline,
                      title: '즐겨찾기를 불러오지 못했어요',
                      subtitle: '저장한 역, 시설, 경로를 다시 확인해 주세요.',
                      actionLabel: '다시 시도',
                      onAction: () {
                        setState(() {
                          _dataFuture = _loadData();
                        });
                      },
                    )
                  else ...[
                    _FavoriteHomeQuickGrid(
                      stationCount: data.stations.length,
                      facilityCount: data.facilities.length,
                      routeCount: data.routes.length,
                      onStations: widget.favoriteRepository == null
                          ? null
                          : _openFavoriteStations,
                      onFacilities: widget.favoriteFacilityRepository == null
                          ? null
                          : _openFavoriteFacilities,
                      onRoutes: widget.favoriteRouteRepository == null
                          ? null
                          : _openFavoriteRoutes,
                    ),
                    if (_firstFacilityAlert(data.facilities)
                        case final alert?) ...[
                      const _AppSectionTitle(title: '확인 필요'),
                      _HomeFacilityAlertCard(
                        facility: alert,
                        onOpenFacilities: _openFavoriteFacilities,
                      ),
                    ],
                    if (data.routes.isNotEmpty) ...[
                      const _AppSectionTitle(title: '최근 경로'),
                      _HomeSavedRouteCard(
                        route: data.routes.first,
                        onTap: _openFavoriteRoutes,
                      ),
                    ],
                    if (data.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: _AppCard(
                          child: _AppInfoRow(
                            icon: Icons.bookmark_border,
                            iconBackground: EasySubwayAccessibleColors.mintSoft,
                            iconColor: EasySubwayAccessibleColors.mintDark,
                            title: '즐겨찾기한 항목이 없습니다',
                            subtitle: '역, 시설, 경로에서 즐겨찾기를 추가해 주세요.',
                          ),
                        ),
                      ),
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

  void _openFavoriteRoutes() {
    final repository = widget.favoriteRouteRepository;
    if (repository == null) {
      return;
    }
    unawaited(
      _openFavoriteListScreen(
        title: '즐겨찾기한 경로',
        child: FavoriteRouteListContent(
          repository: repository,
          onSearchAgain: widget.onOpenRouteSearch == null
              ? null
              : _openRouteSearchFromFavorite,
        ),
      ),
    );
  }

  void _openRouteSearchFromFavorite(FavoriteRoute favorite) {
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
    unawaited(openRouteSearch(favorite.mobilityType));
  }

  void _openFavoriteStations() {
    final repository = widget.favoriteRepository;
    if (repository == null) {
      return;
    }
    unawaited(
      _openFavoriteListScreen(
        title: '즐겨찾기한 역',
        child: FavoriteStationListContent(
          repository: repository,
          stationRepository: widget.stationRepository,
          reportRepository: widget.reportRepository,
          locationProvider: widget.locationProvider,
          facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
          internalRouteRepository: widget.internalRouteRepository,
          realtimeRepository: widget.realtimeRepository,
          routeDraftController: widget.routeDraftController,
          internalRouteMobilityType: widget.initialMobilityType,
        ),
      ),
    );
  }

  void _openFavoriteFacilities() {
    final repository = widget.favoriteFacilityRepository;
    if (repository == null) {
      return;
    }
    unawaited(
      _openFavoriteListScreen(
        title: '즐겨찾기한 시설',
        child: FavoriteFacilityListContent(
          repository: repository,
          reportRepository: widget.reportRepository,
          locationLoader: _facilityReportLocationLoader(
            widget.locationProvider,
          ),
          needsLocationPermissionRequest:
              widget.locationProvider.needsLocationPermissionRequest,
          openLocationSettings: widget.locationProvider.openLocationSettings,
          facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
        ),
      ),
    );
  }

  Future<void> _openFavoriteListScreen({
    required String title,
    required Widget child,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FavoriteListScreen(title: title, child: child),
      ),
    );
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
  return left.largeTextEnabled == right.largeTextEnabled &&
      left.highContrastEnabled == right.highContrastEnabled &&
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

class _FavoriteHomeQuickGrid extends StatelessWidget {
  const _FavoriteHomeQuickGrid({
    required this.stationCount,
    required this.facilityCount,
    required this.routeCount,
    required this.onStations,
    required this.onFacilities,
    required this.onRoutes,
  });

  final int stationCount;
  final int facilityCount;
  final int routeCount;
  final VoidCallback? onStations;
  final VoidCallback? onFacilities;
  final VoidCallback? onRoutes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FavoriteHomeQuickCard(
          key: const Key('favoriteHomeStationsButton'),
          icon: Icons.train_outlined,
          label: '역',
          countLabel: _countLabel(stationCount),
          subtitle: '출발지·도착지 설정과 시설 상태를 확인해요',
          onTap: onStations,
        ),
        const SizedBox(height: 10),
        _FavoriteHomeQuickCard(
          key: const Key('favoriteHomeFacilitiesButton'),
          icon: Icons.elevator_outlined,
          label: '시설',
          countLabel: _countLabel(facilityCount),
          subtitle: '고장·공사 상태와 최근 확인 시각을 봐요',
          onTap: onFacilities,
        ),
        const SizedBox(height: 10),
        _FavoriteHomeQuickCard(
          key: const Key('favoriteHomeRoutesButton'),
          icon: Icons.route_outlined,
          label: '경로',
          countLabel: _countLabel(routeCount),
          subtitle: '이동 조건과 저장한 경로를 다시 확인해요',
          onTap: onRoutes,
        ),
      ],
    );
  }
}

class _FavoriteHomeQuickCard extends StatelessWidget {
  const _FavoriteHomeQuickCard({
    required this.icon,
    required this.label,
    required this.countLabel,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final String countLabel;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = '$label $countLabel, $subtitle';
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: _AppCard(
            backgroundColor: Colors.white,
            borderRadius: 8,
            showBorder: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: EasySubwayAccessibleColors.mintSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      icon,
                      color: EasySubwayAccessibleColors.mintDark,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$label $countLabel',
                        style: const TextStyle(
                          color: EasySubwayAccessibleColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: EasySubwayAccessibleColors.mutedText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
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

String _countLabel(int count) => '$count개';

class _FavoriteListScreen extends StatelessWidget {
  const _FavoriteListScreen({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: child),
    );
  }
}

class OfflineDataScreen extends StatelessWidget {
  const OfflineDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('인터넷 없이 이용')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: const [
            _AppCard(
              backgroundColor: EasySubwayAccessibleColors.mintSoft,
              borderColor: EasySubwayAccessibleColors.mintBorder,
              child: _AppInfoRow(
                icon: Icons.check_circle_outline,
                iconBackground: Colors.white,
                iconColor: EasySubwayAccessibleColors.mintDark,
                title: '인터넷 없이도 이용할 수 있어요',
                subtitle: '마지막으로 받은 노선도와 역 정보를 보여줍니다.',
              ),
            ),
            _AppSectionTitle(title: '저장된 데이터 상태'),
            _AppCard(
              child: Column(
                children: [
                  _AppInfoRow(
                    icon: Icons.public,
                    iconBackground: EasySubwayAccessibleColors.mintSoft,
                    iconColor: EasySubwayAccessibleColors.mintDark,
                    title: '지역',
                    subtitle: '수도권 역과 노선',
                    trailing: '저장됨',
                  ),
                  _AppInfoRow(
                    icon: Icons.update,
                    iconBackground: EasySubwayAccessibleColors.skySoft,
                    iconColor: EasySubwayAccessibleColors.brand,
                    title: '마지막 갱신',
                    subtitle: '앱 설치 때 함께 받은 안내',
                    trailing: '다시 확인',
                  ),
                  _AppInfoRow(
                    icon: Icons.verified_outlined,
                    iconBackground: EasySubwayAccessibleColors.skySoft,
                    iconColor: EasySubwayAccessibleColors.brand,
                    title: '안내 범위',
                    subtitle: '주요 역·노선 안내를 먼저 보여줘요',
                    trailing: '일부',
                  ),
                  _AppInfoRow(
                    icon: Icons.info_outline,
                    iconBackground: EasySubwayAccessibleColors.amberSoft,
                    iconColor: EasySubwayAccessibleColors.amber,
                    title: '제한 사항',
                    subtitle: '실시간 시설 상태와 제보 전송은 인터넷 연결이 필요해요',
                    trailing: '주의',
                  ),
                ],
              ),
            ),
            _AppSectionTitle(title: '이용 가능'),
            _AppCard(
              child: Column(
                children: [
                  _AppInfoRow(
                    icon: Icons.map_outlined,
                    iconBackground: EasySubwayAccessibleColors.mintSoft,
                    iconColor: EasySubwayAccessibleColors.mintDark,
                    title: '노선도',
                    subtitle: '지역·노선·역 보기',
                    trailing: '가능',
                  ),
                  _AppInfoRow(
                    icon: Icons.train_outlined,
                    iconBackground: EasySubwayAccessibleColors.mintSoft,
                    iconColor: EasySubwayAccessibleColors.mintDark,
                    title: '역·시설 정보',
                    subtitle: '출구와 엘리베이터 보기',
                    trailing: '가능',
                  ),
                  _AppInfoRow(
                    icon: Icons.bookmark_border,
                    iconBackground: EasySubwayAccessibleColors.mintSoft,
                    iconColor: EasySubwayAccessibleColors.mintDark,
                    title: '즐겨찾기한 항목',
                    subtitle: '역·시설·경로 보기',
                    trailing: '가능',
                  ),
                ],
              ),
            ),
            _AppSectionTitle(title: '인터넷 연결 필요'),
            _AppCard(
              child: Column(
                children: [
                  _AppInfoRow(
                    icon: Icons.report_outlined,
                    iconBackground: EasySubwayAccessibleColors.amberSoft,
                    iconColor: EasySubwayAccessibleColors.amber,
                    title: '시설 제보',
                    subtitle: '사진과 제보 보내기',
                    trailing: '연결 필요',
                  ),
                  _AppInfoRow(
                    icon: Icons.refresh,
                    iconBackground: EasySubwayAccessibleColors.amberSoft,
                    iconColor: EasySubwayAccessibleColors.amber,
                    title: '시설 상태 새로 확인',
                    subtitle: '최신 고장·복구 확인',
                    trailing: '연결 필요',
                  ),
                ],
              ),
            ),
          ],
        ),
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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const _SupportSectionTitle(title: '개인정보 및 데이터'),
            _PrivacyDataUseSummary(deletionScope: deletionScope),
            const SizedBox(height: 12),
            _SupportAccessItem(
              key: const Key('privacyPolicyAccessItem'),
              icon: Icons.privacy_tip_outlined,
              title: '개인정보처리방침',
              value: accessInfo.privacyPolicyUrl,
              displayValue: '웹에서 확인',
              uri: _httpsUri(accessInfo.privacyPolicyUrl),
              launcher: launcher,
            ),
            const SizedBox(height: 12),
            if (userDataDeletionRepository == null)
              _SupportAccessItem(
                key: const Key('dataDeletionAccessItem'),
                icon: Icons.delete_outline,
                title: '데이터 삭제 요청',
                value: accessInfo.dataDeletionEmail,
                displayValue: '이메일 보내기',
                helperText: '삭제 범위와 처리 절차를 메일로 문의해요',
                uri: _mailtoUri(
                  accessInfo.dataDeletionEmail,
                  '쉬운 지하철 데이터 삭제 요청',
                ),
                launcher: launcher,
              )
            else
              _UserDataDeletionAccessItem(
                repository: userDataDeletionRepository!,
                deletionScope: deletionScope,
                onDeleted: onUserDataDeleted,
              ),
            const SizedBox(height: 20),
            const _SupportSectionTitle(title: '안전과 데이터 안내'),
            const _SafetyDataNotice(),
            const SizedBox(height: 20),
            const _SupportSectionTitle(title: '문의'),
            _SupportAccessItem(
              key: const Key('supportAccessItem'),
              icon: Icons.support_agent,
              title: '고객지원',
              value: accessInfo.supportEmail,
              displayValue: '이메일 보내기',
              uri: _mailtoUri(accessInfo.supportEmail, '쉬운 지하철 고객지원 문의'),
              launcher: launcher,
            ),
            const SizedBox(height: 12),
            const _SecurityContactNotice(),
            const SizedBox(height: 12),
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
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w900,
            height: 1.25,
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
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: openDeletionScreen,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.delete_outline,
                    color: Color(0xFF8B1E1E),
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.title,
                          style: const TextStyle(
                            color: Color(0xFF102A2C),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          copy.helperText,
                          style: const TextStyle(
                            color: Color(0xFF466467),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Color(0xFF466467)),
                ],
              ),
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
    required this.body,
    required this.notices,
    required this.confirmText,
  });

  factory _UserDataDeletionCopy.forScope(UserDataDeletionScope scope) {
    return switch (scope) {
      UserDataDeletionScope.requestOnly => const _UserDataDeletionCopy(
        title: '데이터 삭제 요청',
        helperText: '삭제 범위와 처리 절차를 메일로 문의합니다.',
        body: '삭제가 필요한 데이터와 처리 절차를 지원 메일로 문의합니다.',
        notices: [
          '앱 안에서 바로 삭제할 수 없는 데이터는 답변 안내에 따라 처리됩니다.',
          '요청 전 개인정보처리방침에서 보관 범위와 기간을 확인할 수 있습니다.',
        ],
        confirmText: '데이터 삭제 요청 메일을 보낼까요?',
      ),
      UserDataDeletionScope.deviceOnly => const _UserDataDeletionCopy(
        title: '이 기기의 앱 데이터 삭제',
        helperText: '로컬 삭제 범위와 복구 불가 여부를 확인하고 진행합니다.',
        body:
            '즐겨찾기, 최근 검색, 이동 조건, 화면 설정, 이 기기에 저장된 제보 접수 확인 정보와 작성 중인 제보를 삭제합니다.',
        notices: [
          '이미 보낸 시설 제보, 사진, 위치 정보는 이 작업으로 삭제되지 않습니다.',
          '삭제가 끝나면 이동 조건과 화면 설정이 초기화되고 처음 설정 화면으로 돌아갑니다.',
          '삭제한 데이터는 앱에서 복구할 수 없습니다.',
          '삭제를 완료하지 못하면 오류 안내를 보고 다시 시도할 수 있습니다.',
          '법적·보안상 필요한 최소 기록은 정해진 기간 동안만 보관될 수 있습니다.',
        ],
        confirmText: '삭제 후에는 이 기기에 저장된 앱 데이터와 설정이 지워지고 되돌릴 수 없습니다.',
      ),
      UserDataDeletionScope.remoteOnly => const _UserDataDeletionCopy(
        title: '서버 데이터 삭제',
        helperText: '서버 삭제 범위와 앱 초기화 여부를 확인하고 진행합니다.',
        body:
            '데이터 삭제 요청 시 즐겨찾기, 이동 조건, 신고 접수 기록, 신고 내용·사진·위치와 경로 피드백을 삭제하거나 익명화합니다.',
        notices: [
          '삭제가 끝나면 서버에 연결된 데이터가 정리되고 앱의 임시 설정이 초기화됩니다.',
          '앱은 처음 설정 화면으로 돌아갑니다.',
          '삭제한 데이터는 앱에서 복구할 수 없습니다.',
          '네트워크 오류가 나면 기존 데이터는 지우지 않고 다시 시도할 수 있습니다.',
          '법적·보안상 필요한 최소 기록은 정해진 기간 동안만 보관될 수 있습니다.',
        ],
        confirmText:
            '삭제 후에는 서버에 연결된 데이터와 설정이 삭제되거나 익명화되고 앱의 임시 설정이 초기화됩니다. 되돌릴 수 없습니다.',
      ),
      UserDataDeletionScope.remoteAndDevice => const _UserDataDeletionCopy(
        title: '내 데이터 삭제',
        helperText: '삭제 범위와 복구 불가 여부를 확인하고 진행합니다.',
        body:
            '데이터 삭제 요청 시 즐겨찾기, 이동 조건, 신고 접수 기록, 신고 내용·사진·위치와 경로 피드백을 삭제하거나 익명화합니다.',
        notices: [
          '삭제가 끝나면 이 기기와 서버에 연결된 데이터가 함께 정리됩니다.',
          '삭제한 데이터는 앱에서 복구할 수 없습니다.',
          '네트워크 오류가 나면 기존 데이터는 지우지 않고 다시 시도할 수 있습니다.',
          '법적·보안상 필요한 최소 기록은 정해진 기간 동안만 보관될 수 있습니다.',
        ],
        confirmText: '삭제 후에는 이 기기와 서버에 연결된 데이터와 설정이 삭제되거나 익명화되고 되돌릴 수 없습니다.',
      ),
    };
  }

  final String title;
  final String helperText;
  final String body;
  final List<String> notices;
  final String confirmText;
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
            backgroundColor: const Color(0xFF8B1E1E),
            foregroundColor: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Semantics(
              header: true,
              child: Text(
                '삭제 전에 확인해 주세요',
                style: textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              copy.body,
              style: textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF102A2C),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            for (final notice in copy.notices)
              _DataDeletionNoticeLine(text: notice),
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
              backgroundColor: const Color(0xFF8B1E1E),
              foregroundColor: Colors.white,
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
        context: '사용자 데이터 삭제 처리 중 예외가 발생했습니다.',
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

class _DataDeletionNoticeLine extends StatelessWidget {
  const _DataDeletionNoticeLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 7, color: Color(0xFF8B1E1E)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF3B2020),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserDataDeletionResultScreen extends StatelessWidget {
  const UserDataDeletionResultScreen({
    required this.result,
    required this.deletionScope,
    required this.onRestart,
    super.key,
  });

  final UserDataDeletionResult result;
  final UserDataDeletionScope deletionScope;
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
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _AppCard(
              backgroundColor: EasySubwayAccessibleColors.mintSoft,
              borderColor: EasySubwayAccessibleColors.mintBorder,
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: EasySubwayAccessibleColors.mintDark,
                    size: 56,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '내 데이터가 삭제됐어요',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w900,
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
            const _AppSectionTitle(title: '처리 결과'),
            _AppCard(
              child: Column(
                children: [
                  _DataDeletionResultRow(
                    id: 'favoriteStations',
                    icon: Icons.train_outlined,
                    title: '즐겨찾기한 역',
                    value: '${result.deletedFavoriteStationCount}개 삭제',
                  ),
                  const SizedBox(height: 16),
                  _DataDeletionResultRow(
                    id: 'favoriteFacilities',
                    icon: Icons.elevator_outlined,
                    title: '즐겨찾기한 시설',
                    value: '${result.deletedFavoriteFacilityCount}개 삭제',
                  ),
                  const SizedBox(height: 16),
                  _DataDeletionResultRow(
                    id: 'favoriteRoutes',
                    icon: Icons.route_outlined,
                    title: '즐겨찾기한 경로',
                    value: '${result.deletedFavoriteRouteCount}개 삭제',
                  ),
                  const SizedBox(height: 16),
                  _DataDeletionResultRow(
                    id: 'notifications',
                    icon: Icons.notifications_none,
                    title: '알림 설정',
                    value: result.notificationSettingsDeleted
                        ? '삭제'
                        : '삭제할 항목 없음',
                  ),
                  const SizedBox(height: 12),
                  _DataDeletionResultRow(
                    id: 'reportReceipts',
                    icon: Icons.report_outlined,
                    title: deletionScope == UserDataDeletionScope.deviceOnly
                        ? '이 기기의 제보 기록'
                        : '제보 연결 정보',
                    value: deletionScope == UserDataDeletionScope.deviceOnly
                        ? '${result.anonymizedReportCount}건 삭제'
                        : '${result.anonymizedReportCount}건 익명화',
                  ),
                  if (deletionScope != UserDataDeletionScope.deviceOnly)
                    const SizedBox(height: 16),
                  if (deletionScope != UserDataDeletionScope.deviceOnly)
                    _DataDeletionResultRow(
                      id: 'routeFeedback',
                      icon: Icons.rate_review_outlined,
                      title: '경로 의견 연결 정보',
                      value: '${result.anonymizedRouteFeedbackCount}건 익명화',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _AppCard(
              backgroundColor: EasySubwayAccessibleColors.skySoft,
              borderColor: Color(0xFFB7DDF4),
              child: _AppInfoRow(
                icon: Icons.map_outlined,
                iconBackground: Colors.white,
                iconColor: EasySubwayAccessibleColors.brand,
                title: '노선도와 역 정보는 계속 이용할 수 있어요',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataDeletionResultRow extends StatelessWidget {
  const _DataDeletionResultRow({
    required this.id,
    required this.icon,
    required this.title,
    required this.value,
  });

  final String id;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context).scale(1);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(
            color: EasySubwayAccessibleColors.mutedText,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    final statusBadge = Container(
      key: Key('dataDeletionResultStatus-$id'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFDFF4EC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8AC7B7)),
      ),
      child: const Text(
        '완료',
        style: TextStyle(
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    return Semantics(
      key: Key('dataDeletionResultRow-$id'),
      container: true,
      label: '$title, $value, 완료',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              key: Key('dataDeletionResultIcon-$id'),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: EasySubwayAccessibleColors.mintDark,
                  width: 2,
                ),
              ),
              child: Icon(
                icon,
                color: EasySubwayAccessibleColors.mintDark,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: textScaler >= 1.5
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        content,
                        const SizedBox(height: 8),
                        statusBadge,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: content),
                        const SizedBox(width: 12),
                        statusBadge,
                      ],
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
  static const _scopeNotice = '위치, 신고 사진, 알림, 개인정보 관련 걱정을 함께 보낼 수 있습니다.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      key: const Key('securityContactNotice'),
      container: true,
      label: '$_title, $_contactNotice $_scopeNotice',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2FF),
            border: Border.all(color: const Color(0xFFC3C9E8)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.security_outlined,
                      color: Color(0xFF23306E),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _title,
                        style: textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF17204B),
                          fontWeight: FontWeight.w800,
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
            child: Icon(Icons.circle, size: 7, color: Color(0xFF30408F)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF27315C),
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

  static const _title = '안전과 데이터 안내';
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
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E8),
            border: Border.all(color: const Color(0xFFE3C37D)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFF6B4D00),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _title,
                        style: textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF2C2200),
                          fontWeight: FontWeight.w800,
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
            child: Icon(Icons.circle, size: 7, color: Color(0xFF8A6400)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF3A2A00),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyDataUseSummary extends StatelessWidget {
  const _PrivacyDataUseSummary({required this.deletionScope});

  final UserDataDeletionScope deletionScope;

  static const _title = '개인정보 사용 안내';
  static const _locationPurpose = '현재 위치는 가까운 역 찾기와 시설 제보 위치 확인에만 사용됩니다.';
  static const _appDataPurpose = '즐겨찾기, 이동 조건, 신고 내용과 사진은 앱 기능 제공에 사용됩니다.';
  static const _requestDeletionScope =
      '데이터 삭제 요청은 지원 메일로 삭제 범위와 처리 절차를 문의할 수 있습니다.';
  static const _deviceDeletionScope =
      '이 기기의 앱 데이터 삭제는 즐겨찾기, 최근 검색, 이동 조건, 화면 설정, 제보 접수 확인 정보와 작성 중인 제보만 지웁니다.';
  static const _remoteDeletionScope =
      '서버 데이터 삭제는 즐겨찾기, 신고 접수 기록, 신고 내용과 사진, 위치, 경로 피드백을 삭제하거나 익명화하고 앱의 임시 설정을 초기화합니다.';
  static const _combinedDeletionScope =
      '내 데이터 삭제는 이 기기의 즐겨찾기, 최근 검색, 이동 조건, 화면 설정과 서버에 연결된 신고 내용·사진·위치, 경로 피드백 정보를 삭제하거나 익명화합니다.';
  static const _requestNotice = '앱 안에서 바로 삭제할 수 없는 데이터는 답변 안내에 따라 처리됩니다.';
  static const _deviceSentReportNotice =
      '이미 보낸 시설 제보, 사진, 위치 정보는 이 작업으로 삭제되지 않습니다.';
  static const _remoteSentReportNotice =
      '이미 보낸 시설 제보, 사진, 위치 정보, 경로 피드백은 서버에서 삭제되거나 익명화됩니다.';
  static const _retentionNotice = '법적·보안상 필요한 최소 기록은 정해진 기간 동안만 보관합니다.';

  String get _deletionScopeText {
    return switch (deletionScope) {
      UserDataDeletionScope.requestOnly => _requestDeletionScope,
      UserDataDeletionScope.deviceOnly => _deviceDeletionScope,
      UserDataDeletionScope.remoteOnly => _remoteDeletionScope,
      UserDataDeletionScope.remoteAndDevice => _combinedDeletionScope,
    };
  }

  String get _sentReportNoticeText {
    return switch (deletionScope) {
      UserDataDeletionScope.requestOnly => _requestNotice,
      UserDataDeletionScope.deviceOnly => _deviceSentReportNotice,
      UserDataDeletionScope.remoteOnly ||
      UserDataDeletionScope.remoteAndDevice => _remoteSentReportNotice,
    };
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final deletionScopeText = _deletionScopeText;
    final sentReportNoticeText = _sentReportNoticeText;
    return Semantics(
      key: const Key('privacyDataUseSummary'),
      container: true,
      label:
          '$_title, $_locationPurpose $_appDataPurpose $deletionScopeText $sentReportNoticeText $_retentionNotice',
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEAF5F4),
            border: Border.all(color: const Color(0xFFB7D7D3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF102A2C),
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),
                const _PrivacyDataUseLine(text: _locationPurpose),
                const _PrivacyDataUseLine(text: _appDataPurpose),
                _PrivacyDataUseLine(text: deletionScopeText),
                _PrivacyDataUseLine(text: sentReportNoticeText),
                const _PrivacyDataUseLine(text: _retentionNotice),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyDataUseLine extends StatelessWidget {
  const _PrivacyDataUseLine({required this.text});

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
            child: Icon(Icons.circle, size: 7, color: Color(0xFF006D77)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF29484B),
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
    this.helperText,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;
  final Uri? uri;
  final SupportAccessLauncher launcher;
  final String? displayValue;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final targetUri = uri;
    final fallbackTarget = value.trim();
    final displayValue = targetUri == null
        ? '현재 이용할 수 없음 · 준비 중'
        : this.displayValue ?? fallbackTarget;
    final secondaryText = helperText;
    final semanticLabelParts = [title, displayValue];
    if (targetUri != null && displayValue != fallbackTarget) {
      semanticLabelParts.add(fallbackTarget);
    }
    if (secondaryText != null) {
      semanticLabelParts.add(secondaryText);
    }
    return Semantics(
      button: true,
      enabled: targetUri != null,
      label: semanticLabelParts.join(', '),
      onTap: targetUri == null
          ? null
          : () => unawaited(_openTarget(context, targetUri, fallbackTarget)),
      child: ExcludeSemantics(
        child: OutlinedButton.icon(
          onPressed: targetUri == null
              ? null
              : () =>
                    unawaited(_openTarget(context, targetUri, fallbackTarget)),
          icon: Icon(icon),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title),
                  const SizedBox(height: 4),
                  Text(
                    displayValue,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFF29484B),
                      height: 1.25,
                    ),
                  ),
                  if (secondaryText != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      secondaryText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF466467),
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTarget(
    BuildContext context,
    Uri uri,
    String fallbackTarget,
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
      SnackBar(content: Text('연결할 수 없습니다. 직접 확인해 주세요: $fallbackTarget')),
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

class FeatureTile extends StatelessWidget {
  const FeatureTile({
    required this.icon,
    required this.title,
    required this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MergeSemantics(
      child: Semantics(
        label: semanticLabel,
        child: ExcludeSemantics(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD5E2E4)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: colorScheme.primary, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF102A2C),
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
