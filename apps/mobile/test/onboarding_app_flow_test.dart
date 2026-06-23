import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/legacy_credential_cleanup.dart';
import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_secure_key_value_storage.dart';

void main() {
  testWidgets('첫 실행 앱은 온보딩을 완료한 뒤 홈으로 이동한다', (tester) async {
    final onboardingStore = MemoryOnboardingResultStore();
    final legacyCredentialStorage = FakeSecureKeyValueStorage()
      ..values[SecureLegacyCredentialCleaner.legacyAuthCredentialsKey] =
          'legacy-token-payload';

    await tester.pumpWidget(
      _testApp(
        onboardingStore: onboardingStore,
        legacyCredentialCleaner: SecureLegacyCredentialCleaner(
          storage: legacyCredentialStorage,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('쉬운 지하철'), findsOneWidget);
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsNothing);

    await tester.tap(find.byKey(const Key('onboardingProfileCard-elderly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsNothing);
    expect(
      legacyCredentialStorage.deletedKeys,
      contains(SecureLegacyCredentialCleaner.legacyAuthCredentialsKey),
    );
    expect(
      legacyCredentialStorage.values,
      isNot(contains(SecureLegacyCredentialCleaner.legacyAuthCredentialsKey)),
    );
    expect(onboardingStore.savedResult?.profile.id, 'elderly');
    expect(onboardingStore.saveCount, 1);
  });

  testWidgets('첫 실행 앱은 온보딩에서 위치 권한을 준비할 수 있다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      location: _freshCurrentLocation(),
    );

    await tester.pumpWidget(
      _testApp(
        onboardingStore: MemoryOnboardingResultStore(),
        locationProvider: locationProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('onboardingLocationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboardingLocationButton')));
    await tester.pumpAndSettle();

    expect(locationProvider.requestCount, 1);
    expect(find.text('위치 준비 완료'), findsOneWidget);
  });

  testWidgets('첫 실행 앱은 온보딩에서 알림 권한을 준비할 수 있다', (tester) async {
    final notificationPermissionProvider = FakeNotificationPermissionProvider(
      nextStatus: NotificationPermissionStatus.granted,
    );

    await tester.pumpWidget(
      _testApp(
        notificationPermissionProvider: notificationPermissionProvider,
        onboardingStore: MemoryOnboardingResultStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('onboardingNotificationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboardingNotificationButton')));
    await tester.pumpAndSettle();

    expect(notificationPermissionProvider.requestCount, 1);
    expect(find.text('알림 준비 완료'), findsOneWidget);
  });

  testWidgets('첫 실행 앱은 온보딩 알림 권한 실패 다음 행동을 안내한다', (tester) async {
    final notificationPermissionProvider = FakeNotificationPermissionProvider(
      nextStatus: NotificationPermissionStatus.denied,
      error: const NotificationSettingsException('알림 권한을 확인하지 못했습니다.'),
    );

    await tester.pumpWidget(
      _testApp(
        notificationPermissionProvider: notificationPermissionProvider,
        onboardingStore: MemoryOnboardingResultStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('onboardingNotificationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboardingNotificationButton')));
    await tester.pumpAndSettle();

    expect(notificationPermissionProvider.requestCount, 1);
    expect(find.text('알림 권한을 확인하지 못했습니다.'), findsOneWidget);
    expect(find.text('나중에 알림 설정에서 다시 켤 수 있습니다.'), findsOneWidget);
  });

  testWidgets('첫 실행 앱은 알림 설정이 꺼진 구성에서 온보딩 알림 권한을 요청하지 않는다', (tester) async {
    await tester.pumpWidget(
      _testApp(
        notificationRepository: null,
        onboardingStore: MemoryOnboardingResultStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -1300));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboardingNotificationButton')), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '알림 켜기'), findsNothing);
  });

  testWidgets('첫 실행 앱은 알림 권한 제공자가 직접 주입되면 온보딩 알림 권한을 요청한다', (tester) async {
    final notificationPermissionProvider = FakeNotificationPermissionProvider(
      nextStatus: NotificationPermissionStatus.granted,
    );

    await tester.pumpWidget(
      _testApp(
        notificationRepository: null,
        notificationPermissionProvider: notificationPermissionProvider,
        onboardingStore: MemoryOnboardingResultStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('onboardingNotificationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboardingNotificationButton')));
    await tester.pumpAndSettle();

    expect(notificationPermissionProvider.requestCount, 1);
    expect(find.text('알림 준비 완료'), findsOneWidget);
  });

  testWidgets('앱은 저장된 온보딩 설정으로 홈을 바로 보여준다', (tester) async {
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.firstWhere(
          (option) => option.id == 'wheelchair',
        ),
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: true,
          highContrastEnabled: true,
          simpleViewEnabled: true,
        ),
      ),
    );

    await tester.pumpWidget(_testApp(onboardingStore: onboardingStore));
    await tester.pumpAndSettle();

    final homeContext = tester.element(find.byType(HomeScreen));

    expect(onboardingStore.readCount, 1);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsNothing);
    expect(MediaQuery.textScalerOf(homeContext).scale(20), closeTo(23.6, 0.01));
    expect(Theme.of(homeContext).colorScheme.primary, const Color(0xFF003D40));
  });

  testWidgets('앱은 온보딩 저장소를 읽지 못하면 다시 설정을 고르게 한다', (tester) async {
    final reportedErrors = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await tester.pumpWidget(
        _testApp(
          onboardingStore: MemoryOnboardingResultStore(throwOnRead: true),
        ),
      );
      await tester.pumpAndSettle();
    });

    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, isA<FormatException>());
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsNothing);
  });
}

EasySubwayApp _testApp({
  OnboardingResultStore? onboardingStore,
  LegacyCredentialCleaner legacyCredentialCleaner =
      const NoLegacyCredentialCleaner(),
  NotificationSettingsRepository? notificationRepository =
      const _DefaultNotificationSettingsRepository(),
  NotificationPermissionProvider? notificationPermissionProvider,
  CurrentLocationProvider? locationProvider,
}) {
  return EasySubwayApp(
    repository: FakeStationSearchRepository(),
    reportRepository: FakeFacilityReportRepository(),
    routeRepository: FakeRouteSearchRepository(),
    favoriteRepository: FakeFavoriteStationRepository(),
    notificationRepository: notificationRepository,
    notificationPermissionProvider: notificationPermissionProvider,
    onboardingStore: onboardingStore,
    locationProvider: locationProvider,
    legacyCredentialCleaner: legacyCredentialCleaner,
  );
}

class FakeStationSearchRepository implements StationSearchRepository {
  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    return const [];
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    return const [];
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    return const [];
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    return const [];
  }
}

class FakeFacilityReportRepository implements FacilityReportRepository {
  @override
  Future<FacilityReportResult> createReport(
    FacilityReportRequest request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) {
    throw UnimplementedError();
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() async {
    return const [];
  }
}

class FakeRouteSearchRepository implements RouteSearchRepository {
  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) {
    throw UnimplementedError();
  }
}

class FakeFavoriteStationRepository implements FavoriteStationRepository {
  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    return const [];
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeFavoriteStation(String stationId) async {}
}

class _DefaultNotificationSettingsRepository
    implements NotificationSettingsRepository {
  const _DefaultNotificationSettingsRepository();

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    return const NotificationSettings(
      userId: 'anonymous-user-1',
      favoriteStationFacilityAlerts: true,
      favoriteRouteFacilityAlerts: false,
      reportStatusAlerts: true,
      dataQualityAlerts: false,
      updatedAt: '2026-06-14T09:00:00',
    );
  }

  @override
  Future<NotificationSettings> saveNotificationSettings(
    NotificationSettings settings,
  ) {
    throw UnimplementedError();
  }
}

class FakeNotificationPermissionProvider
    implements NotificationPermissionProvider {
  FakeNotificationPermissionProvider({required this.nextStatus, this.error});

  final NotificationPermissionStatus nextStatus;
  final Object? error;
  int requestCount = 0;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async {
    requestCount++;
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return nextStatus;
  }
}

class MemoryOnboardingResultStore implements OnboardingResultStore {
  MemoryOnboardingResultStore({
    OnboardingResult? initialResult,
    this.throwOnRead = false,
  }) : savedResult = initialResult;

  OnboardingResult? savedResult;
  final bool throwOnRead;
  int readCount = 0;
  int saveCount = 0;

  @override
  Future<OnboardingResult?> readResult() async {
    readCount++;
    if (throwOnRead) {
      throw const FormatException('broken onboarding result');
    }
    return savedResult;
  }

  @override
  Future<void> saveResult(OnboardingResult result) async {
    saveCount++;
    savedResult = result;
  }

  @override
  Future<void> clearResult() async {
    savedResult = null;
  }
}

CurrentLocation _freshCurrentLocation({
  double latitude = 37.3028,
  double longitude = 126.8665,
}) {
  return CurrentLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: 25,
    measuredAt: DateTime.now(),
    provider: 'test',
    permissionPrecision: LocationPermissionPrecision.precise,
  );
}

class FakeCurrentLocationProvider implements CurrentLocationProvider {
  FakeCurrentLocationProvider({this.location});

  final CurrentLocation? location;
  int requestCount = 0;

  @override
  Future<bool> needsLocationPermissionRequest() async {
    return true;
  }

  @override
  Future<CurrentLocation> currentLocation() async {
    requestCount++;
    return location ?? _freshCurrentLocation();
  }

  @override
  Future<bool> openLocationSettings() async {
    return true;
  }
}
