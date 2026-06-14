import 'package:flutter/material.dart';

import 'anonymous_auth.dart';
import 'auth_headers.dart';
import 'facility_report.dart';
import 'mobility_profile.dart';
import 'notification_settings.dart';
import 'onboarding.dart';
import 'route_search.dart';
import 'station_search.dart';
import 'mobile_error_reporter.dart';

void main() {
  runApp(EasySubwayApp(onboardingStore: const SecureOnboardingResultStore()));
}

class EasySubwayApp extends StatelessWidget {
  EasySubwayApp({
    StationSearchRepository? repository,
    FacilityReportRepository? reportRepository,
    RouteSearchRepository? routeRepository,
    FavoriteStationRepository? favoriteRepository,
    NotificationSettingsRepository? notificationRepository,
    AnonymousAuthRepository? anonymousAuthRepository,
    OnboardingResultStore? onboardingStore,
    OnboardingState initialOnboardingState = const OnboardingState.initial(),
    bool enableAnonymousAuth = true,
    Key? key,
  }) : this._(
         dependencies: _EasySubwayAppDependencies.resolve(
           repository: repository,
           reportRepository: reportRepository,
           routeRepository: routeRepository,
           favoriteRepository: favoriteRepository,
           notificationRepository: notificationRepository,
           anonymousAuthRepository: anonymousAuthRepository,
           enableAnonymousAuth: enableAnonymousAuth,
         ),
         initialOnboardingState: initialOnboardingState,
         onboardingStore: onboardingStore,
         key: key,
       );

  EasySubwayApp._({
    required _EasySubwayAppDependencies dependencies,
    required this.initialOnboardingState,
    required this.onboardingStore,
    super.key,
  }) : repository = dependencies.repository,
       reportRepository = dependencies.reportRepository,
       routeRepository = dependencies.routeRepository,
       favoriteRepository = dependencies.favoriteRepository,
       notificationRepository = dependencies.notificationRepository;

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final FavoriteStationRepository? favoriteRepository;
  final NotificationSettingsRepository? notificationRepository;
  final OnboardingState initialOnboardingState;
  final OnboardingResultStore? onboardingStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasySubway',
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
        favoriteRepository: favoriteRepository,
        notificationRepository: notificationRepository,
        initialOnboardingState: initialOnboardingState,
        onboardingStore: onboardingStore,
      ),
    );
  }
}

class _EasySubwayHome extends StatefulWidget {
  const _EasySubwayHome({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.favoriteRepository,
    required this.notificationRepository,
    required this.initialOnboardingState,
    required this.onboardingStore,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final FavoriteStationRepository? favoriteRepository;
  final NotificationSettingsRepository? notificationRepository;
  final OnboardingState initialOnboardingState;
  final OnboardingResultStore? onboardingStore;

  @override
  State<_EasySubwayHome> createState() => _EasySubwayHomeState();
}

class _EasySubwayHomeState extends State<_EasySubwayHome> {
  // 저장소가 없는 테스트/프리뷰에서도 같은 앱 세션에서는 온보딩 완료 상태를 유지한다.
  late OnboardingState _onboardingState = widget.initialOnboardingState;
  late bool _loadingOnboardingState =
      widget.onboardingStore != null &&
      !widget.initialOnboardingState.isCompleted;

  @override
  void initState() {
    super.initState();
    if (_loadingOnboardingState) {
      _restoreOnboardingState();
    }
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
        onCompleted: (result) async {
          await _saveOnboardingResult(result);
          setState(() {
            _onboardingState = OnboardingState.completed(result: result);
          });
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
        favoriteRepository: widget.favoriteRepository,
        notificationRepository: widget.notificationRepository,
        initialMobilityType: onboardingResult?.profile.mobilityType,
        simpleViewEnabled: preferences.simpleViewEnabled,
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
        data: _themeForPreferences(Theme.of(context), preferences),
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

class _EasySubwayAppDependencies {
  const _EasySubwayAppDependencies({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.favoriteRepository,
    required this.notificationRepository,
  });

  factory _EasySubwayAppDependencies.resolve({
    StationSearchRepository? repository,
    FacilityReportRepository? reportRepository,
    RouteSearchRepository? routeRepository,
    FavoriteStationRepository? favoriteRepository,
    NotificationSettingsRepository? notificationRepository,
    AnonymousAuthRepository? anonymousAuthRepository,
    required bool enableAnonymousAuth,
  }) {
    final baseUri = defaultStationApiBaseUri();
    final sharedAuthProvider = _defaultAuthorizationHeaderProvider(
      baseUri: baseUri,
      anonymousAuthRepository: anonymousAuthRepository,
      enableAnonymousAuth: enableAnonymousAuth,
    );

    return _EasySubwayAppDependencies(
      repository: repository ?? StationSearchApiRepository(baseUri: baseUri),
      reportRepository:
          reportRepository ?? FacilityReportApiRepository(baseUri: baseUri),
      routeRepository:
          routeRepository ?? RouteSearchApiRepository(baseUri: baseUri),
      favoriteRepository:
          favoriteRepository ??
          _defaultFavoriteStationRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      notificationRepository:
          notificationRepository ??
          _defaultNotificationSettingsRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
    );
  }

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final FavoriteStationRepository? favoriteRepository;
  final NotificationSettingsRepository? notificationRepository;
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
    required this.favoriteRepository,
    required this.notificationRepository,
    this.simpleViewEnabled = true,
    String? initialMobilityType,
    super.key,
  }) : initialMobilityType =
           initialMobilityType ?? mobilityProfileOptions.first.mobilityType;

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final FavoriteStationRepository? favoriteRepository;
  final NotificationSettingsRepository? notificationRepository;
  final String initialMobilityType;
  final bool simpleViewEnabled;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final favoriteRepository = this.favoriteRepository;
    final notificationRepository = this.notificationRepository;

    return Scaffold(
      appBar: AppBar(title: const Text('쉬운 지하철')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Semantics(
              header: true,
              child: Text(
                '역 찾기',
                style: textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('stationSearchButton'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StationSearchScreen(
                      repository: repository,
                      reportRepository: reportRepository,
                      favoriteRepository: favoriteRepository,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.search),
              label: const Text('역 검색'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('routeSearchButton'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RouteSearchScreen(
                      repository: routeRepository,
                      stationRepository: repository,
                      initialMobilityType: initialMobilityType,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.route),
              label: const Text('경로 검색'),
            ),
            const SizedBox(height: 12),
            if (favoriteRepository != null) ...[
              FilledButton.icon(
                key: const Key('favoriteStationsButton'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FavoriteStationListScreen(
                        repository: favoriteRepository,
                        stationRepository: repository,
                        reportRepository: reportRepository,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.star),
                label: const Text('즐겨찾기'),
              ),
              const SizedBox(height: 12),
            ],
            if (notificationRepository != null) ...[
              FilledButton.icon(
                key: const Key('notificationSettingsButton'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NotificationSettingsScreen(
                        repository: notificationRepository,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('알림 설정'),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              key: const Key('mobilityProfileButton'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<MobilityProfileOption>(
                    builder: (_) => const MobilityProfileScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.accessibility_new),
              label: const Text('이동 조건'),
            ),
            if (!simpleViewEnabled) ...[
              const SizedBox(height: 24),
              const FeatureTile(
                icon: Icons.accessible_forward,
                title: '이동 프로필',
                semanticLabel: '이동 프로필, 이동 조건 저장',
              ),
              const FeatureTile(
                icon: Icons.elevator,
                title: '시설 정보',
                semanticLabel: '시설 정보, 엘리베이터와 경사로',
              ),
              const FeatureTile(
                icon: Icons.report_outlined,
                title: '신고',
                semanticLabel: '신고, 불편 신고',
              ),
            ],
          ],
        ),
      ),
    );
  }
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
