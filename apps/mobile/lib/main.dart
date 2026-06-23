import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'accessible_design.dart';
import 'app/app_bootstrap.dart';
import 'app/app_dependencies.dart';
import 'facility_report.dart';
import 'favorite_facility.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'internal_route.dart';
import 'legacy_credential_cleanup.dart';
import 'mobility_profile.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrap = await AppBootstrap.initialize(
    enablePushNotifications: defaultPushNotificationsEnabled,
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
    SearchHistoryRepository? searchHistoryRepository,
    InternalRouteRepository? internalRouteRepository,
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
            side: const BorderSide(color: Color(0xFF006D77), width: 1.5),
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

  @override
  State<_EasySubwayHome> createState() => _EasySubwayHomeState();
}

class _EasySubwayHomeState extends State<_EasySubwayHome> {
  // 저장소가 없는 테스트/프리뷰에서도 같은 앱 세션에서는 온보딩 완료 상태를 유지한다.
  late OnboardingState _onboardingState = widget.initialOnboardingState;
  late bool _loadingOnboardingState =
      widget.onboardingStore != null &&
      !widget.initialOnboardingState.isCompleted;
  bool _pendingFacilityReportPhotoRecoveryStarted = false;

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

    if (!_onboardingState.isCompleted) {
      return OnboardingScreen(
        locationProvider: widget.locationProvider,
        notificationPermissionProvider: widget.notificationPermissionProvider,
        onCompleted: (result) async {
          await _saveOnboardingResult(result);
          setState(() {
            _onboardingState = OnboardingState.completed(result: result);
          });
          _schedulePendingFacilityReportPhotoRecovery();
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
        onUserDataDeleted: _handleUserDataDeleted,
        onMobilityProfileChanged: _saveMobilityProfile,
      ),
    );
  }

  Future<void> _handleUserDataDeleted() async {
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
      _loadingOnboardingState = false;
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
      _loadingOnboardingState = false;
    });
    _schedulePendingFacilityReportPhotoRecovery();
  }

  Future<void> _saveOnboardingResult(OnboardingResult result) async {
    try {
      await widget.onboardingStore?.saveResult(result);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '온보딩 설정을 저장하는 중 예외가 발생했습니다.',
      );
    }
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
    await _saveOnboardingResult(nextResult);
    if (!mounted) {
      return;
    }
    setState(() {
      _onboardingState = OnboardingState.completed(result: nextResult);
    });
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
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.locationProvider,
    required this.supportAccessInfo,
    required this.supportAccessLauncher,
    required this.userDataDeletionRepository,
    required this.onUserDataDeleted,
    required this.onMobilityProfileChanged,
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
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final SupportAccessInfo supportAccessInfo;
  final SupportAccessLauncher supportAccessLauncher;
  final UserDataDeletionRepository? userDataDeletionRepository;
  final Future<void> Function()? onUserDataDeleted;
  final Future<void> Function(MobilityProfileOption profile)?
  onMobilityProfileChanged;
  final String initialMobilityType;
  final OnboardingViewPreferences viewPreferences;
  final bool simpleViewEnabled;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late String _mobilityType;
  late final RouteDraftController _routeDraftController;
  Future<List<FavoriteRoute>>? _favoriteRoutesFuture;

  @override
  void initState() {
    super.initState();
    _mobilityType = widget.initialMobilityType;
    _routeDraftController = RouteDraftController();
    _favoriteRoutesFuture = widget.favoriteRouteRepository
        ?.listFavoriteRoutes();
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
    if (widget.favoriteRouteRepository != oldWidget.favoriteRouteRepository) {
      _favoriteRoutesFuture = widget.favoriteRouteRepository
          ?.listFavoriteRoutes();
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
    final hasFavorites =
        favoriteRepository != null ||
        favoriteFacilityRepository != null ||
        favoriteRouteRepository != null;
    final hasFavoriteRoutes = favoriteRouteRepository != null;
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

    void openSettings() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AppSettingsScreen(
            currentProfile: currentProfile,
            viewPreferences: widget.viewPreferences,
            notificationRepository: notificationRepository,
            notificationPermissionProvider: notificationPermissionProvider,
            onOpenMobilityProfile: _openMobilityProfile,
            onOpenSupportAccess: openSupportAccess,
          ),
        ),
      );
    }

    void openStationSearch() {
      Navigator.of(context).push(
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
            routeDraftController: _routeDraftController,
          ),
        ),
      );
    }

    Future<void> refreshHomeState() async {
      final repository = widget.favoriteRouteRepository;
      if (repository == null) {
        return;
      }
      final routesFuture = repository.listFavoriteRoutes();
      setState(() {
        _favoriteRoutesFuture = routesFuture;
      });
      try {
        await routesFuture;
      } catch (error, stackTrace) {
        (error, stackTrace);
        // FutureBuilder가 오류 상태를 표시하므로 refresh callback은 정상 종료한다.
      }
    }

    Future<void> openRouteSearch() async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RouteSearchScreen(
            repository: routeRepository,
            stationRepository: repository,
            routeFeedbackRepository: routeFeedbackRepository,
            favoriteRouteRepository: favoriteRouteRepository,
            initialMobilityType: initialMobilityType,
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
            initialMobilityType: initialMobilityType,
          ),
        ),
      );
      if (!context.mounted) {
        return;
      }
      await refreshHomeState();
    }

    void openReports() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              MyFacilityReportListScreen(repository: reportRepository),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('쉬운 지하철'),
        actions: [
          IconButton(
            key: const Key('homeHelpActionButton'),
            onPressed: openSupportAccess,
            icon: const Icon(Icons.help_outline),
            tooltip: '도움말',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          key: const Key('homeRefreshIndicator'),
          onRefresh: refreshHomeState,
          child: ListView(
            key: const Key('homePrototypeList'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(17, 18, 17, 32),
            children: [
              _HomePrototypeHero(
                profile: currentProfile,
                onRouteSearch: openRouteSearch,
                onStationSearch: openStationSearch,
              ),
              AnimatedBuilder(
                animation: _routeDraftController,
                builder: (context, _) {
                  final draft = _routeDraftController.draft;
                  if (draft.origin == null && draft.destination == null) {
                    return const SizedBox.shrink();
                  }
                  return _HomeRouteDraftCard(
                    draft: draft,
                    onTap: openRouteSearch,
                  );
                },
              ),
              _HomePrototypeSection(
                title: '지금 주변 상태',
                action: TextButton(
                  onPressed: openStationSearch,
                  child: const Text('주변 역 보기'),
                ),
              ),
              _HomeStatusUnavailableCard(onTap: openStationSearch),
              if (hasFavoriteRoutes) ...[
                _HomePrototypeSection(title: '자주 가는 곳'),
                _HomeSavedRouteSection(
                  key: const Key('homeSavedRouteSection'),
                  routesFuture: _favoriteRoutesFuture,
                  onOpenFavorites: openFavorites,
                ),
              ],
              const _HomePrototypeSection(title: '바로가기'),
              _HomeShortcutGrid(
                hasFavorites: hasFavorites,
                onNearby: openStationSearch,
                onReports: openReports,
                onFavorites: openFavorites,
                onSettings: openSettings,
              ),
            ],
          ),
        ),
      ),
    );
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
    setState(() {
      _mobilityType = selectedProfile.mobilityType;
    });
    await widget.onMobilityProfileChanged?.call(selectedProfile);
    if (!mounted) {
      return null;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selectedProfile.title} 조건으로 변경했습니다')),
    );
    return selectedProfile;
  }
}

class _HomePrototypeHero extends StatelessWidget {
  const _HomePrototypeHero({
    required this.profile,
    required this.onRouteSearch,
    required this.onStationSearch,
  });

  final MobilityProfileOption profile;
  final VoidCallback onRouteSearch;
  final VoidCallback onStationSearch;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '길찾기 시작, 현재 이동 조건 ${profile.title}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              EasySubwayAccessibleColors.brandDark,
              EasySubwayAccessibleColors.brand,
            ],
          ),
          borderRadius: BorderRadius.circular(25),
          boxShadow: const [
            BoxShadow(
              color: Color(0x240B2947),
              blurRadius: 30,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        '길찾기',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              height: 1.28,
                            ),
                      ),
                    ),
                  ),
                  _HomeProfilePill(profile: profile),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      key: const Key('routeSearchButton'),
                      button: true,
                      label: '길찾기',
                      onTap: onRouteSearch,
                      child: ExcludeSemantics(
                        child: FilledButton.icon(
                          onPressed: onRouteSearch,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor:
                                EasySubwayAccessibleColors.brandDark,
                            minimumSize: const Size.fromHeight(
                              EasySubwayTouchTarget.primary,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          icon: const Icon(Icons.route),
                          label: const Text('길찾기 시작'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  SizedBox(
                    width: 55,
                    height: 52,
                    child: Semantics(
                      key: const Key('stationSearchButton'),
                      button: true,
                      label: '역 검색',
                      onTap: onStationSearch,
                      child: ExcludeSemantics(
                        child: OutlinedButton(
                          onPressed: onStationSearch,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x59FFFFFF)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Icon(Icons.search, size: 22),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeProfilePill extends StatelessWidget {
  const _HomeProfilePill({required this.profile});

  final MobilityProfileOption profile;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_walk, size: 16, color: Colors.white),
            const SizedBox(width: 7),
            Text(
              profile.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
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
        key: const Key('homeRouteDraftPanel'),
        button: true,
        label: '출발 도착 정하기, $summary',
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: _PrototypeCard(
              backgroundColor: EasySubwayAccessibleColors.skySoft,
              borderColor: const Color(0xFFB7DDF4),
              borderRadius: 18,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(
                        Icons.route_outlined,
                        color: EasySubwayAccessibleColors.brand,
                      ),
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

class _HomePrototypeSection extends StatelessWidget {
  const _HomePrototypeSection({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 22, 1, 11),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
            ],
          );
          if (action == null) {
            return titleBlock;
          }
          if (constraints.maxWidth < 340) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: action!),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: titleBlock),
              action!,
            ],
          );
        },
      ),
    );
  }
}

class _HomeStatusUnavailableCard extends StatelessWidget {
  const _HomeStatusUnavailableCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PrototypeCard(
      backgroundColor: const Color(0xFFFFFAF0),
      borderColor: const Color(0xFFF1D49A),
      child: Column(
        children: [
          const _PrototypeInfoRow(
            icon: Icons.info_outline,
            iconBackground: EasySubwayAccessibleColors.amberSoft,
            iconColor: EasySubwayAccessibleColors.amber,
            title: '주변 시설 상태 없음',
            trailing: '확인 필요',
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  EasySubwayTouchTarget.general,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('주변 역 보기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSavedRouteSection extends StatelessWidget {
  const _HomeSavedRouteSection({
    super.key,
    required this.routesFuture,
    required this.onOpenFavorites,
  });

  final Future<List<FavoriteRoute>>? routesFuture;
  final VoidCallback onOpenFavorites;

  @override
  Widget build(BuildContext context) {
    final routesFuture = this.routesFuture;
    if (routesFuture == null) {
      return const _HomeSavedRouteEmptyCard();
    }
    return FutureBuilder<List<FavoriteRoute>>(
      future: routesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _HomeSavedRouteLoadingCard();
        }
        if (snapshot.hasError) {
          return _HomeSavedRouteErrorCard(onTap: onOpenFavorites);
        }
        final routes = snapshot.data ?? const <FavoriteRoute>[];
        if (routes.isEmpty) {
          return const _HomeSavedRouteEmptyCard();
        }
        return _HomeSavedRouteCard(route: routes.first, onTap: onOpenFavorites);
      },
    );
  }
}

class _HomeSavedRouteLoadingCard extends StatelessWidget {
  const _HomeSavedRouteLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const _PrototypeCard(
      backgroundColor: EasySubwayAccessibleColors.skySoft,
      borderColor: Color(0xFFB7DDF4),
      child: _PrototypeInfoRow(
        icon: Icons.bookmark_border,
        iconBackground: Colors.white,
        iconColor: EasySubwayAccessibleColors.brand,
        title: '저장한 경로 확인 중',
        subtitle: '자주 가는 경로를 불러오고 있어요',
        trailing: '잠시만요',
      ),
    );
  }
}

class _HomeSavedRouteErrorCard extends StatelessWidget {
  const _HomeSavedRouteErrorCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PrototypeCard(
      backgroundColor: const Color(0xFFFFFAF0),
      borderColor: const Color(0xFFF1D49A),
      child: Column(
        children: [
          const _PrototypeInfoRow(
            icon: Icons.bookmark_border,
            iconBackground: EasySubwayAccessibleColors.amberSoft,
            iconColor: EasySubwayAccessibleColors.amber,
            title: '저장한 경로를 불러오지 못했습니다',
            subtitle: '즐겨찾기 화면에서 다시 확인해 주세요',
            trailing: '확인 필요',
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(
                  EasySubwayTouchTarget.general,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('저장한 경로 보기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSavedRouteCard extends StatelessWidget {
  const _HomeSavedRouteCard({required this.route, required this.onTap});

  final FavoriteRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label:
          '저장한 경로, ${route.summaryTitle}, ${route.lineLabel}, ${route.mobilityLabel}, ${route.scoreLabel}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: _PrototypeCard(
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: EasySubwayAccessibleColors.mintSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(
                      Icons.route_outlined,
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
                        '${route.originStationName} → ${route.destinationStationName}',
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
                          _HomeMiniBadge(route.scoreLabel),
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

class _HomeMiniBadge extends StatelessWidget {
  const _HomeMiniBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.mintSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(
            color: EasySubwayAccessibleColors.mintDark,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _HomeSavedRouteEmptyCard extends StatelessWidget {
  const _HomeSavedRouteEmptyCard();

  @override
  Widget build(BuildContext context) {
    return _PrototypeCard(
      backgroundColor: EasySubwayAccessibleColors.skySoft,
      borderColor: const Color(0xFFB7DDF4),
      child: Semantics(
        container: true,
        label: '저장한 경로가 없습니다.',
        child: const ExcludeSemantics(
          child: Row(
            children: [
              Icon(
                Icons.bookmark_add_outlined,
                color: EasySubwayAccessibleColors.brand,
                size: 30,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '저장한 경로가 없습니다',
                      style: TextStyle(
                        color: EasySubwayAccessibleColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeShortcutGrid extends StatelessWidget {
  const _HomeShortcutGrid({
    required this.hasFavorites,
    required this.onNearby,
    required this.onReports,
    required this.onFavorites,
    required this.onSettings,
  });

  final bool hasFavorites;
  final VoidCallback onNearby;
  final VoidCallback onReports;
  final VoidCallback onFavorites;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _HomeQuickCard(
        key: const Key('nearbyStationButton'),
        icon: Icons.location_on_outlined,
        title: '가까운 역',
        onTap: onNearby,
      ),
      _HomeQuickCard(
        key: const Key('myReportsButton'),
        icon: Icons.report_outlined,
        title: '내 신고',
        onTap: onReports,
      ),
      if (hasFavorites)
        _HomeQuickCard(
          key: const Key('favoritesButton'),
          icon: Icons.bookmark_border,
          title: '저장한 곳',
          onTap: onFavorites,
        ),
      _HomeQuickCard(
        key: const Key('appSettingsButton'),
        icon: Icons.settings_outlined,
        title: '설정',
        onTap: onSettings,
      ),
    ];
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    if (textScale >= 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < cards.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            cards[index],
          ],
        ],
      );
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.18,
      children: cards,
    );
  }
}

class _HomeQuickCard extends StatelessWidget {
  const _HomeQuickCard({
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
          borderRadius: BorderRadius.circular(18),
          child: _PrototypeCard(
            borderRadius: 18,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: EasySubwayAccessibleColors.mintSoft,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: SizedBox(
                    width: 39,
                    height: 39,
                    child: Icon(
                      icon,
                      color: EasySubwayAccessibleColors.mintDark,
                      size: 21,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: EasySubwayAccessibleColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
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

class _PrototypeCard extends StatelessWidget {
  const _PrototypeCard({
    required this.child,
    this.backgroundColor = Colors.white,
    this.borderColor = EasySubwayAccessibleColors.line,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A071B2F),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _PrototypeInfoRow extends StatelessWidget {
  const _PrototypeInfoRow({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color iconBackground;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final leading = DecoratedBox(
      decoration: BoxDecoration(
        color: iconBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        width: 43,
        height: 43,
        child: Icon(icon, color: iconColor, size: 22),
      ),
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
            style: const TextStyle(
              color: EasySubwayAccessibleColors.mutedText,
              fontSize: 12,
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
    required this.onOpenMobilityProfile,
    required this.onOpenSupportAccess,
    super.key,
  });

  final MobilityProfileOption currentProfile;
  final OnboardingViewPreferences viewPreferences;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final Future<MobilityProfileOption?> Function() onOpenMobilityProfile;
  final VoidCallback onOpenSupportAccess;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late MobilityProfileOption _profile = widget.currentProfile;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _AppSettingsSection(
              key: const Key('settingsSection-mobility'),
              title: '내 이동 조건',
              children: [
                _AppSettingsActionTile(
                  key: const Key('mobilityProfileButton'),
                  icon: Icons.directions_walk,
                  title: _profile.title,
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
              title: '화면과 읽기',
              children: [
                _AppSettingsInfoTile(
                  icon: Icons.text_fields,
                  title: widget.viewPreferences.largeTextEnabled
                      ? '큰 글자 켜짐'
                      : '기본 글자 크기',
                  subtitle: widget.viewPreferences.highContrastEnabled
                      ? '고대비 표시를 사용해요'
                      : '기본 대비로 표시해요',
                ),
                _AppSettingsInfoTile(
                  icon: Icons.visibility_outlined,
                  title: widget.viewPreferences.simpleViewEnabled
                      ? '간편 보기 켜짐'
                      : '전체 보기 켜짐',
                  subtitle: '핵심 행동을 먼저 보여줘요',
                ),
              ],
            ),
            _AppSettingsSection(
              key: const Key('settingsSection-route'),
              title: '경로 찾기',
              children: [
                _AppSettingsInfoTile(
                  icon: Icons.route,
                  title: '${_profile.title} 조건 적용 중',
                  subtitle: _profile.summary,
                ),
              ],
            ),
            _AppSettingsSection(
              key: const Key('settingsSection-region-data'),
              title: '지역과 데이터',
              children: const [
                _AppSettingsInfoTile(
                  icon: Icons.public,
                  title: '수도권 우선',
                  subtitle: '오프라인 데이터팩과 검증된 출처를 먼저 사용해요',
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
                    title: '알림 설정 대기 중',
                    subtitle: '실기기 QA 전에는 푸시 알림을 켜지 않아요',
                  )
                else
                  _AppSettingsActionTile(
                    key: const Key('notificationSettingsButton'),
                    icon: Icons.notifications_active_outlined,
                    title: '알림 설정',
                    subtitle: '시설 상태, 신고 처리, 정보 갱신 알림을 관리해요',
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
              key: const Key('settingsSection-help-privacy'),
              title: '도움말과 개인정보',
              children: [
                _AppSettingsActionTile(
                  key: const Key('settingsSupportPrivacyButton'),
                  icon: Icons.privacy_tip_outlined,
                  title: '도움말과 개인정보',
                  subtitle: '지원, 개인정보 처리방침, 데이터 삭제 안내를 확인해요',
                  onTap: widget.onOpenSupportAccess,
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

class FavoriteHomeScreen extends StatelessWidget {
  const FavoriteHomeScreen({
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    required this.stationRepository,
    required this.reportRepository,
    required this.locationProvider,
    required this.facilityReportDraftTargetStore,
    required this.internalRouteRepository,
    required this.initialMobilityType,
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
  final String initialMobilityType;

  @override
  Widget build(BuildContext context) {
    final sections = _favoriteSections(context);
    return DefaultTabController(
      length: sections.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('즐겨찾기'),
          bottom: TabBar(tabs: [for (final section in sections) section.tab]),
        ),
        body: TabBarView(
          children: [for (final section in sections) section.content],
        ),
      ),
    );
  }

  List<_FavoriteSection> _favoriteSections(BuildContext context) {
    final sections = <_FavoriteSection>[];
    final favoriteRouteRepository = this.favoriteRouteRepository;
    final favoriteRepository = this.favoriteRepository;
    final favoriteFacilityRepository = this.favoriteFacilityRepository;
    if (favoriteRouteRepository != null) {
      sections.add(
        _FavoriteSection(
          tab: const Tab(key: Key('favoriteRoutesTabButton'), text: '경로'),
          content: FavoriteRouteListContent(
            repository: favoriteRouteRepository,
          ),
        ),
      );
    }
    if (favoriteRepository != null) {
      sections.add(
        _FavoriteSection(
          tab: const Tab(key: Key('favoriteStationsTabButton'), text: '역'),
          content: FavoriteStationListContent(
            repository: favoriteRepository,
            stationRepository: stationRepository,
            reportRepository: reportRepository,
            locationProvider: locationProvider,
            facilityReportDraftTargetStore: facilityReportDraftTargetStore,
            internalRouteRepository: internalRouteRepository,
            internalRouteMobilityType: initialMobilityType,
          ),
        ),
      );
    }
    if (favoriteFacilityRepository != null) {
      sections.add(
        _FavoriteSection(
          tab: const Tab(key: Key('favoriteFacilitiesTabButton'), text: '시설'),
          content: FavoriteFacilityListContent(
            repository: favoriteFacilityRepository,
          ),
        ),
      );
    }
    return sections;
  }
}

class _FavoriteSection {
  const _FavoriteSection({required this.tab, required this.content});

  final Tab tab;
  final Widget content;
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
  final Future<void> Function()? onUserDataDeleted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('도움말')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const _PrivacyDataUseSummary(),
            const SizedBox(height: 12),
            const _SafetyDataNotice(),
            const SizedBox(height: 12),
            _SupportAccessItem(
              key: const Key('privacyPolicyAccessItem'),
              icon: Icons.privacy_tip_outlined,
              title: '개인정보처리방침',
              value: accessInfo.privacyPolicyUrl,
              uri: _httpsUri(accessInfo.privacyPolicyUrl),
              launcher: launcher,
            ),
            const SizedBox(height: 12),
            _SupportAccessItem(
              key: const Key('supportAccessItem'),
              icon: Icons.support_agent,
              title: '고객지원',
              value: accessInfo.supportEmail,
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
              uri: _mailtoUri(accessInfo.securityEmail, '쉬운 지하철 보안 문의'),
              launcher: launcher,
            ),
            const SizedBox(height: 12),
            if (userDataDeletionRepository == null)
              _SupportAccessItem(
                key: const Key('dataDeletionAccessItem'),
                icon: Icons.delete_outline,
                title: '데이터 삭제 요청',
                value: accessInfo.dataDeletionEmail,
                uri: _mailtoUri(
                  accessInfo.dataDeletionEmail,
                  '쉬운 지하철 데이터 삭제 요청',
                ),
                launcher: launcher,
              )
            else
              _UserDataDeletionAccessItem(
                repository: userDataDeletionRepository!,
                onDeleted: onUserDataDeleted,
              ),
          ],
        ),
      ),
    );
  }
}

class _UserDataDeletionAccessItem extends StatelessWidget {
  const _UserDataDeletionAccessItem({
    required this.repository,
    required this.onDeleted,
  });

  final UserDataDeletionRepository repository;
  final Future<void> Function()? onDeleted;

  @override
  Widget build(BuildContext context) {
    void openDeletionScreen() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserDataDeletionScreen(
            repository: repository,
            onDeleted: onDeleted,
          ),
        ),
      );
    }

    return Semantics(
      key: const Key('dataDeletionAccessItem'),
      button: true,
      label: '데이터 삭제 요청, 앱 안에서 삭제를 진행합니다.',
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
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline,
                    color: Color(0xFF8B1E1E),
                    size: 28,
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '데이터 삭제 요청',
                          style: TextStyle(
                            color: Color(0xFF102A2C),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '앱 안에서 삭제 대상을 확인하고 직접 요청합니다.',
                          style: TextStyle(
                            color: Color(0xFF466467),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Color(0xFF466467)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UserDataDeletionScreen extends StatefulWidget {
  const UserDataDeletionScreen({
    required this.repository,
    required this.onDeleted,
    super.key,
  });

  final UserDataDeletionRepository repository;
  final Future<void> Function()? onDeleted;

  @override
  State<UserDataDeletionScreen> createState() => _UserDataDeletionScreenState();
}

class _UserDataDeletionScreenState extends State<UserDataDeletionScreen> {
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('내 데이터 삭제')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
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
          label: Text(_isDeleting ? '삭제 중' : '내 데이터 삭제'),
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
              '즐겨찾기, 이동 조건, 신고 접수 기록, 신고 내용과 위치, 경로 피드백을 삭제하거나 익명화합니다.',
              style: textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF102A2C),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            const _DataDeletionNoticeLine(
              text: '삭제가 끝나면 현재 로그인 정보는 지워지고 처음 설정 화면으로 돌아갑니다.',
            ),
            const _DataDeletionNoticeLine(
              text: '네트워크 오류가 나면 기존 데이터는 지우지 않고 다시 시도할 수 있습니다.',
            ),
            const _DataDeletionNoticeLine(
              text: '법적·보안상 필요한 최소 기록은 정해진 기간 동안만 보관될 수 있습니다.',
            ),
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
        content: const Text('삭제 후에는 앱에 저장된 인증 정보와 설정이 지워지고 되돌릴 수 없습니다.'),
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
      await widget.repository.deleteCurrentUserData();
      await widget.onDeleted?.call();
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

class _SecurityContactNotice extends StatelessWidget {
  const _SecurityContactNotice();

  static const _title = '보안 문의 안내';
  static const _contactNotice = '취약점이나 개인정보 보호 우려를 발견하면 보안 문의로 알려주세요.';
  static const _scopeNotice = '위치, 신고 사진, 알림, 계정 접근 문제를 함께 접수할 수 있습니다.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      key: const Key('securityContactNotice'),
      container: true,
      label: '$_title, $_contactNotice $_scopeNotice',
      child: ExcludeSemantics(
        child: DecoratedBox(
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
        child: DecoratedBox(
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
  const _PrivacyDataUseSummary();

  static const _title = '개인정보 사용 안내';
  static const _locationPurpose = '현재 위치는 가까운 역 찾기와 시설 신고 위치 확인에만 사용됩니다.';
  static const _appDataPurpose = '즐겨찾기, 이동 조건, 신고 내용과 사진은 앱 기능 제공에 사용됩니다.';
  static const _deletionScope =
      '데이터 삭제 요청 시 즐겨찾기, 이동 조건, 신고 접수 기록, 신고 내용·사진·위치와 경로 피드백을 삭제하거나 익명화합니다.';
  static const _retentionNotice = '법적·보안상 필요한 최소 기록은 정해진 기간 동안만 보관합니다.';

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      key: const Key('privacyDataUseSummary'),
      container: true,
      label:
          '$_title, $_locationPurpose $_appDataPurpose $_deletionScope $_retentionNotice',
      child: ExcludeSemantics(
        child: DecoratedBox(
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
                const _PrivacyDataUseLine(text: _deletionScope),
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
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;
  final Uri? uri;
  final SupportAccessLauncher launcher;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? '준비 중입니다.' : value.trim();
    final targetUri = uri;
    return Semantics(
      button: true,
      enabled: targetUri != null,
      label: '$title, $displayValue',
      onTap: targetUri == null
          ? null
          : () => unawaited(_openTarget(context, targetUri)),
      child: ExcludeSemantics(
        child: OutlinedButton.icon(
          onPressed: targetUri == null
              ? null
              : () => unawaited(_openTarget(context, targetUri)),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openTarget(BuildContext context, Uri uri) async {
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
      const SnackBar(content: Text('연결할 수 없습니다. 잠시 후 다시 시도해 주세요.')),
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
