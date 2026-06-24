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

    expect(find.text('빠른 길보다,\n갈 수 있는 길을\n먼저 안내해요.'), findsOneWidget);
    expect(find.text('이동약자를 위한 지하철 안내'), findsNothing);
    expect(find.text('계단과 고장 시설을 미리 확인하고'), findsNothing);
    expect(find.text('로그인 없이도 이용할 수 있어요'), findsNothing);
    expect(find.bySemanticsLabel('쉬운 지하철 앱 아이콘'), findsNothing);
    await tester.tap(find.byKey(const Key('startScreenStartButton')));
    await tester.pumpAndSettle();
    expect(find.text('계단 없는 길을\n먼저 찾습니다'), findsOneWidget);
    await _tapIntroConfigure(tester);

    expect(find.text('어떤 도움이 필요한가요?'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsNothing);

    await tester.tap(find.byKey(const Key('onboardingProfileCard-elderly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();
    expect(find.text('원하는 조건을 고르세요'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();
    expect(find.text('권한을 선택하세요'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboardingPermissionSkipButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.text('어떤 도움이 필요한가요?'), findsNothing);
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

  testWidgets('첫 실행 앱은 권한 선택을 끄고 건너뛰면 수동 설정 방법을 안내한다', (tester) async {
    await tester.pumpWidget(
      _testApp(onboardingStore: MemoryOnboardingResultStore()),
    );
    await tester.pumpAndSettle();
    await _openOnboarding(tester);
    await _continueFromProfileToPermission(tester);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingPermissionSkipButton')));
    await tester.pumpAndSettle();

    expect(find.text('수동 설정 방법'), findsOneWidget);
    expect(find.textContaining('가까운 역 찾기와 시설 고장 알림은 제한됩니다'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('첫 실행 앱은 알림 설정 저장소가 없어도 권한 선택 화면을 유지한다', (tester) async {
    await tester.pumpWidget(
      _testApp(
        notificationRepository: null,
        onboardingStore: MemoryOnboardingResultStore(),
      ),
    );
    await tester.pumpAndSettle();
    await _openOnboarding(tester);
    await _continueFromProfileToPermission(tester);

    expect(find.text('권한을 선택하세요'), findsOneWidget);
    expect(find.text('현재 위치'), findsOneWidget);
    expect(find.text('알림'), findsOneWidget);
    expect(
      find.byKey(const Key('onboardingPermissionSkipButton')),
      findsOneWidget,
    );
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
    expect(find.text('어떤 도움이 필요한가요?'), findsNothing);
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
    await _openOnboarding(tester);
    expect(find.text('어떤 도움이 필요한가요?'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsNothing);
  });
}

Future<void> _openOnboarding(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('startScreenStartButton')));
  await tester.pumpAndSettle();
  await _tapIntroConfigure(tester);
}

Future<void> _tapIntroConfigure(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('onboardingIntroConfigureButton')),
    120,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.byKey(const Key('onboardingIntroConfigureButton')));
  await tester.pumpAndSettle();
}

Future<void> _continueFromProfileToPermission(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('onboardingProfileCard-elderly')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('onboardingDoneButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('onboardingDoneButton')));
  await tester.pumpAndSettle();
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
