import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'anonymous_auth.dart';
import 'auth_headers.dart';
import 'facility_report.dart';
import 'favorite_facility.dart';
import 'mobility_profile.dart';
import 'notification_settings.dart';
import 'onboarding.dart';
import 'route_search.dart';
import 'station_search.dart';
import 'mobile_error_reporter.dart';

void main() {
  final photoPicker = ImagePickerFacilityReportPhotoPicker();
  runApp(
    EasySubwayApp(
      onboardingStore: const SecureOnboardingResultStore(),
      facilityReportDraftTargetStore:
          const SecureFacilityReportDraftTargetStore(),
      facilityReportLostPhotoRestorer: photoPicker.retrieveLostPhoto,
    ),
  );
}

class EasySubwayApp extends StatelessWidget {
  EasySubwayApp({
    StationSearchRepository? repository,
    FacilityReportRepository? reportRepository,
    RouteSearchRepository? routeRepository,
    RouteFeedbackRepository? routeFeedbackRepository,
    FavoriteStationRepository? favoriteRepository,
    FavoriteFacilityRepository? favoriteFacilityRepository,
    FavoriteRouteRepository? favoriteRouteRepository,
    NotificationSettingsRepository? notificationRepository,
    NotificationPermissionProvider? notificationPermissionProvider,
    CurrentLocationProvider? locationProvider,
    AnonymousAuthRepository? anonymousAuthRepository,
    OnboardingResultStore? onboardingStore,
    FacilityReportDraftTargetStore? facilityReportDraftTargetStore,
    FacilityReportLostPhotoRestorer? facilityReportLostPhotoRestorer,
    SupportAccessInfo supportAccessInfo =
        const SupportAccessInfo.fromEnvironment(),
    SupportAccessLauncher supportAccessLauncher =
        const UrlLauncherSupportAccessLauncher(),
    OnboardingState initialOnboardingState = const OnboardingState.initial(),
    bool enableAnonymousAuth = true,
    Key? key,
  }) : this._(
         dependencies: _EasySubwayAppDependencies.resolve(
           repository: repository,
           reportRepository: reportRepository,
           routeRepository: routeRepository,
           routeFeedbackRepository: routeFeedbackRepository,
           favoriteRepository: favoriteRepository,
           favoriteFacilityRepository: favoriteFacilityRepository,
           favoriteRouteRepository: favoriteRouteRepository,
           notificationRepository: notificationRepository,
           notificationPermissionProvider: notificationPermissionProvider,
           locationProvider: locationProvider,
           anonymousAuthRepository: anonymousAuthRepository,
           enableAnonymousAuth: enableAnonymousAuth,
         ),
         initialOnboardingState: initialOnboardingState,
         onboardingStore: onboardingStore,
         facilityReportDraftTargetStore: facilityReportDraftTargetStore,
         facilityReportLostPhotoRestorer: facilityReportLostPhotoRestorer,
         supportAccessInfo: supportAccessInfo,
         supportAccessLauncher: supportAccessLauncher,
         key: key,
       );

  EasySubwayApp._({
    required _EasySubwayAppDependencies dependencies,
    required this.initialOnboardingState,
    required this.onboardingStore,
    required this.facilityReportDraftTargetStore,
    required this.facilityReportLostPhotoRestorer,
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
       notificationRepository = dependencies.notificationRepository,
       notificationPermissionProvider =
           dependencies.notificationPermissionProvider,
       locationProvider = dependencies.locationProvider;

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final OnboardingState initialOnboardingState;
  final OnboardingResultStore? onboardingStore;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final FacilityReportLostPhotoRestorer? facilityReportLostPhotoRestorer;
  final SupportAccessInfo supportAccessInfo;
  final SupportAccessLauncher supportAccessLauncher;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasySubway',
      debugShowCheckedModeBanner: false,
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
        notificationRepository: notificationRepository,
        notificationPermissionProvider: notificationPermissionProvider,
        locationProvider: locationProvider,
        initialOnboardingState: initialOnboardingState,
        onboardingStore: onboardingStore,
        facilityReportDraftTargetStore: facilityReportDraftTargetStore,
        facilityReportLostPhotoRestorer: facilityReportLostPhotoRestorer,
        supportAccessInfo: supportAccessInfo,
        supportAccessLauncher: supportAccessLauncher,
      ),
    );
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
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.locationProvider,
    required this.initialOnboardingState,
    required this.onboardingStore,
    required this.facilityReportDraftTargetStore,
    required this.facilityReportLostPhotoRestorer,
    required this.supportAccessInfo,
    required this.supportAccessLauncher,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final OnboardingState initialOnboardingState;
  final OnboardingResultStore? onboardingStore;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final FacilityReportLostPhotoRestorer? facilityReportLostPhotoRestorer;
  final SupportAccessInfo supportAccessInfo;
  final SupportAccessLauncher supportAccessLauncher;

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
        notificationRepository: widget.notificationRepository,
        notificationPermissionProvider: widget.notificationPermissionProvider,
        locationProvider: widget.locationProvider,
        initialMobilityType: onboardingResult?.profile.mobilityType,
        simpleViewEnabled: preferences.simpleViewEnabled,
        facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
        supportAccessInfo: widget.supportAccessInfo,
        supportAccessLauncher: widget.supportAccessLauncher,
      ),
    );
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

class _EasySubwayAppDependencies {
  const _EasySubwayAppDependencies({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.routeFeedbackRepository,
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.locationProvider,
  });

  factory _EasySubwayAppDependencies.resolve({
    StationSearchRepository? repository,
    FacilityReportRepository? reportRepository,
    RouteSearchRepository? routeRepository,
    RouteFeedbackRepository? routeFeedbackRepository,
    FavoriteStationRepository? favoriteRepository,
    FavoriteFacilityRepository? favoriteFacilityRepository,
    FavoriteRouteRepository? favoriteRouteRepository,
    NotificationSettingsRepository? notificationRepository,
    NotificationPermissionProvider? notificationPermissionProvider,
    CurrentLocationProvider? locationProvider,
    AnonymousAuthRepository? anonymousAuthRepository,
    required bool enableAnonymousAuth,
  }) {
    final baseUri = defaultStationApiBaseUri();
    final sharedAuthProvider = _defaultAuthorizationHeaderProvider(
      baseUri: baseUri,
      anonymousAuthRepository: anonymousAuthRepository,
      enableAnonymousAuth: enableAnonymousAuth,
    );
    final resolvedNotificationRepository =
        notificationRepository ??
        _defaultNotificationSettingsRepository(
          baseUri: baseUri,
          authProvider: sharedAuthProvider,
        );
    final resolvedNotificationPermissionProvider =
        notificationPermissionProvider ??
        (resolvedNotificationRepository == null
            ? null
            : MethodChannelNotificationPermissionProvider());

    return _EasySubwayAppDependencies(
      repository: repository ?? StationSearchApiRepository(baseUri: baseUri),
      reportRepository:
          reportRepository ??
          FacilityReportApiRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      routeRepository:
          routeRepository ?? RouteSearchApiRepository(baseUri: baseUri),
      routeFeedbackRepository:
          routeFeedbackRepository ??
          _defaultRouteFeedbackRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      favoriteRepository:
          favoriteRepository ??
          _defaultFavoriteStationRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      favoriteFacilityRepository:
          favoriteFacilityRepository ??
          _defaultFavoriteFacilityRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      favoriteRouteRepository:
          favoriteRouteRepository ??
          _defaultFavoriteRouteRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      notificationRepository: resolvedNotificationRepository,
      notificationPermissionProvider: resolvedNotificationPermissionProvider,
      locationProvider:
          locationProvider ?? MethodChannelCurrentLocationProvider(),
    );
  }

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
}

AuthorizationHeaderProvider? _defaultAuthorizationHeaderProvider({
  required Uri baseUri,
  required bool enableAnonymousAuth,
  AnonymousAuthRepository? anonymousAuthRepository,
}) {
  if (!enableAnonymousAuth) {
    return null;
  }
  return AnonymousAuthSession(
    repository:
        anonymousAuthRepository ?? AnonymousAuthApiRepository(baseUri: baseUri),
  );
}

FavoriteStationRepository? _defaultFavoriteStationRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return FavoriteStationApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}

FavoriteFacilityRepository? _defaultFavoriteFacilityRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return FavoriteFacilityApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}

FavoriteRouteRepository? _defaultFavoriteRouteRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return FavoriteRouteApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}

RouteFeedbackRepository? _defaultRouteFeedbackRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return RouteFeedbackApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}

NotificationSettingsRepository? _defaultNotificationSettingsRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return NotificationSettingsApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}

class HomeScreen extends StatelessWidget {
  HomeScreen({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.routeFeedbackRepository,
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.locationProvider,
    required this.supportAccessInfo,
    required this.supportAccessLauncher,
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
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final SupportAccessInfo supportAccessInfo;
  final SupportAccessLauncher supportAccessLauncher;
  final String initialMobilityType;
  final bool simpleViewEnabled;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final favoriteRepository = this.favoriteRepository;
    final favoriteFacilityRepository = this.favoriteFacilityRepository;
    final favoriteRouteRepository = this.favoriteRouteRepository;
    final routeFeedbackRepository = this.routeFeedbackRepository;
    final notificationRepository = this.notificationRepository;
    final notificationPermissionProvider = this.notificationPermissionProvider;
    final hasFavorites =
        favoriteRepository != null ||
        favoriteFacilityRepository != null ||
        favoriteRouteRepository != null;
    void openSupportAccess() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportAccessScreen(
            accessInfo: supportAccessInfo,
            launcher: supportAccessLauncher,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('쉬운 지하철'),
        actions: [
          TextButton.icon(
            key: const Key('homeHelpActionButton'),
            onPressed: openSupportAccess,
            icon: const Icon(Icons.help_outline),
            label: const Text('도움말'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              minimumSize: const Size(96, 48),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              '안녕하세요',
              style: textTheme.titleLarge?.copyWith(
                color: const Color(0xFF466467),
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Semantics(
              header: true,
              child: Text(
                '어디로 가시나요?',
                style: textTheme.headlineMedium?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 22),
            _HomePrimaryActionButton(
              key: const Key('stationSearchButton'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StationSearchScreen(
                      repository: repository,
                      reportRepository: reportRepository,
                      favoriteRepository: favoriteRepository,
                      locationProvider: locationProvider,
                      facilityReportDraftTargetStore:
                          facilityReportDraftTargetStore,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.search),
              label: '역 검색',
            ),
            const SizedBox(height: 12),
            _HomePrimaryActionButton(
              key: const Key('routeSearchButton'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RouteSearchScreen(
                      repository: routeRepository,
                      stationRepository: repository,
                      routeFeedbackRepository: routeFeedbackRepository,
                      favoriteRouteRepository: favoriteRouteRepository,
                      initialMobilityType: initialMobilityType,
                      simpleViewEnabled: simpleViewEnabled,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.route),
              label: '길찾기',
            ),
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _HomeActionSection(
              title: '개인 설정',
              groupKey: const Key('homeSettingsActionsGroup'),
              children: [
                _HomeSecondaryActionButton(
                  key: const Key('mobilityProfileButton'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<MobilityProfileOption>(
                        builder: (_) => const MobilityProfileScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.accessibility_new),
                  label: '이동 조건',
                ),
                if (notificationRepository != null)
                  _HomeSecondaryActionButton(
                    key: const Key('notificationSettingsButton'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => NotificationSettingsScreen(
                            repository: notificationRepository,
                            notificationPermissionProvider:
                                notificationPermissionProvider,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: '알림 설정',
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _HomeActionSection(
              title: '내 정보',
              groupKey: const Key('homeMyInfoActionsGroup'),
              children: [
                if (hasFavorites)
                  _HomeSecondaryActionButton(
                    key: const Key('favoritesButton'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FavoriteHomeScreen(
                            favoriteRepository: favoriteRepository,
                            favoriteFacilityRepository:
                                favoriteFacilityRepository,
                            favoriteRouteRepository: favoriteRouteRepository,
                            stationRepository: repository,
                            reportRepository: reportRepository,
                            locationProvider: locationProvider,
                            facilityReportDraftTargetStore:
                                facilityReportDraftTargetStore,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.star_outline),
                    label: '즐겨찾기',
                  ),
                _HomeSecondaryActionButton(
                  key: const Key('myReportsButton'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MyFacilityReportListScreen(
                          repository: reportRepository,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: '내 신고',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePrimaryActionButton extends StatelessWidget {
  const _HomePrimaryActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    super.key,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(92),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
      icon: IconTheme.merge(data: const IconThemeData(size: 30), child: icon),
      label: Text(label, maxLines: 1),
    );
  }
}

class _HomeActionSection extends StatelessWidget {
  const _HomeActionSection({
    required this.title,
    required this.groupKey,
    required this.children,
  });

  final String title;
  final Key groupKey;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleMedium?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 10.0;
            final itemWidth = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              key: groupKey,
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final child in children)
                  SizedBox(width: itemWidth, height: 56, child: child),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HomeSecondaryActionButton extends StatelessWidget {
  const _HomeSecondaryActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    super.key,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.center,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF006D77),
        side: BorderSide(color: colorScheme.outlineVariant),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      icon: IconTheme.merge(data: const IconThemeData(size: 22), child: icon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    super.key,
  });

  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final StationSearchRepository stationRepository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;

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
    super.key,
  });

  final SupportAccessInfo accessInfo;
  final SupportAccessLauncher launcher;

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
            _SupportAccessItem(
              key: const Key('dataDeletionAccessItem'),
              icon: Icons.delete_outline,
              title: '데이터 삭제 요청',
              value: accessInfo.dataDeletionEmail,
              uri: _mailtoUri(accessInfo.dataDeletionEmail, '쉬운 지하철 데이터 삭제 요청'),
              launcher: launcher,
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
  static const _appDataPurpose =
      '즐겨찾기, 이동 조건, 신고 내용과 사진, 알림 설정은 앱 기능 제공에 사용됩니다.';
  static const _deletionScope =
      '데이터 삭제 요청 시 즐겨찾기, 이동 조건, 익명 인증, 기기 알림 정보, 신고 내용·사진·위치와 경로 피드백을 삭제하거나 익명화합니다.';
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
