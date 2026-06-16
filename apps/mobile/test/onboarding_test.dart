import 'dart:async';

import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('온보딩 보기 설정은 쉬운 기본값으로 시작한다', () {
    const preferences = OnboardingViewPreferences.defaults();

    expect(preferences.largeTextEnabled, isTrue);
    expect(preferences.highContrastEnabled, isFalse);
    expect(preferences.simpleViewEnabled, isTrue);
  });

  testWidgets('온보딩은 이동 조건과 보기 설정을 선택한 뒤 완료 결과를 반환한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    OnboardingResult? completedResult;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            onCompleted: (result) {
              completedResult = result;
            },
          ),
        ),
      );

      expect(find.text('쉬운 지하철'), findsOneWidget);
      expect(find.text('먼저 이동 조건을 골라 주세요'), findsOneWidget);
      expect(find.text('고령자'), findsOneWidget);
      expect(find.text('휠체어'), findsOneWidget);

      final disabledDoneButton = tester.widget<FilledButton>(
        find.byKey(const Key('onboardingDoneButton')),
      );
      expect(disabledDoneButton.onPressed, isNull);

      await tester.tap(
        find.byKey(const Key('onboardingProfileCard-wheelchair')),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('휠체어 선택됨, 계단 없는 길만 안내해요'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();

      expect(find.text('보기 설정'), findsOneWidget);
      expect(find.text('큰 글씨'), findsOneWidget);
      expect(find.text('고대비'), findsOneWidget);
      expect(find.text('단순 보기'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('고대비 꺼짐')),
        isSemantics(label: '고대비 꺼짐', hasTapAction: true),
      );

      await tester.tap(
        find.byKey(const Key('onboardingPreference-highContrast')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onboardingDoneButton')));
      await tester.pumpAndSettle();

      expect(completedResult?.profile.id, 'wheelchair');
      expect(completedResult?.profile.mobilityType, 'WHEELCHAIR');
      expect(completedResult?.preferences.largeTextEnabled, isTrue);
      expect(completedResult?.preferences.highContrastEnabled, isTrue);
      expect(completedResult?.preferences.simpleViewEnabled, isTrue);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('온보딩은 사용자가 누르면 위치 권한 준비를 시작한다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      location: const CurrentLocation(latitude: 37.3028, longitude: 126.8665),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          locationProvider: locationProvider,
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('onboardingLocationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('가까운 역을 자동으로 찾으려면 GPS가 필요합니다.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboardingLocationButton')));
    await tester.pumpAndSettle();

    expect(locationProvider.requestCount, 1);
    expect(find.text('위치 준비 완료'), findsOneWidget);
  });

  testWidgets('온보딩은 GPS가 꺼져 있으면 위치 설정을 열 수 있다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException(
        '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          locationProvider: locationProvider,
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('onboardingLocationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboardingLocationButton')));
    await tester.pumpAndSettle();

    expect(find.text('기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
    expect(
      find.byKey(const Key('onboardingOpenLocationSettingsButton')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('onboardingOpenLocationSettingsButton')),
    );
    await tester.pumpAndSettle();

    expect(locationProvider.openSettingsCount, 1);
  });

  testWidgets('온보딩은 위치 설정을 여는 동안 위치 확인을 다시 시작하지 않는다', (tester) async {
    final openSettingsCompleter = Completer<bool>();
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException(
        '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
      ),
      openSettingsLoader: () => openSettingsCompleter.future,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          locationProvider: locationProvider,
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('onboardingLocationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboardingLocationButton')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('onboardingOpenLocationSettingsButton')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboardingLocationButton')));
    await tester.pump();

    expect(locationProvider.requestCount, 1);
    expect(locationProvider.openSettingsCount, 1);

    openSettingsCompleter.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('온보딩은 사용자가 누르면 알림 권한 준비를 시작한다', (tester) async {
    final notificationPermissionProvider = FakeNotificationPermissionProvider(
      status: NotificationPermissionStatus.granted,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          notificationPermissionProvider: notificationPermissionProvider,
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('onboardingNotificationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('시설 고장과 신고 결과를 알려드려요.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboardingNotificationButton')));
    await tester.pumpAndSettle();

    expect(notificationPermissionProvider.requestCount, 1);
    expect(find.text('알림 준비 완료'), findsOneWidget);
  });

  testWidgets('온보딩은 알림 권한을 거부하면 짧게 안내한다', (tester) async {
    final notificationPermissionProvider = FakeNotificationPermissionProvider(
      status: NotificationPermissionStatus.denied,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          notificationPermissionProvider: notificationPermissionProvider,
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('onboardingNotificationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboardingNotificationButton')));
    await tester.pumpAndSettle();

    expect(notificationPermissionProvider.requestCount, 1);
    expect(find.text('알림 권한을 켜 주세요.'), findsOneWidget);
  });

  test('온보딩 완료 결과는 선택한 이동 조건과 보기 설정을 함께 담는다', () {
    final result = OnboardingResult(
      profile: mobilityProfileOptions.firstWhere(
        (option) => option.id == 'pregnant',
      ),
      preferences: const OnboardingViewPreferences(
        largeTextEnabled: false,
        highContrastEnabled: true,
        simpleViewEnabled: false,
      ),
    );

    expect(result.profile.title, '임산부');
    expect(result.preferences.largeTextEnabled, isFalse);
    expect(result.preferences.highContrastEnabled, isTrue);
    expect(result.preferences.simpleViewEnabled, isFalse);
  });

  test('온보딩 완료 결과는 로컬 저장용 문자열로 변환하고 다시 읽는다', () {
    final result = OnboardingResult(
      profile: mobilityProfileOptions.firstWhere(
        (option) => option.id == 'wheelchair',
      ),
      preferences: const OnboardingViewPreferences(
        largeTextEnabled: true,
        highContrastEnabled: true,
        simpleViewEnabled: false,
      ),
    );

    final decoded = OnboardingResult.decode(result.encode());

    expect(decoded.profile.id, 'wheelchair');
    expect(decoded.profile.mobilityType, 'WHEELCHAIR');
    expect(decoded.preferences.largeTextEnabled, isTrue);
    expect(decoded.preferences.highContrastEnabled, isTrue);
    expect(decoded.preferences.simpleViewEnabled, isFalse);
  });

  test('온보딩 완료 결과는 알 수 없는 이동 조건 저장값을 거부한다', () {
    expect(
      () => OnboardingResult.decode(
        '{"profileId":"unknown","preferences":{"largeTextEnabled":true,"highContrastEnabled":false,"simpleViewEnabled":true}}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('온보딩 완료 결과는 손상된 보기 설정 저장값을 거부한다', () {
    expect(
      () => OnboardingResult.decode(
        '{"profileId":"elderly","preferences":{"largeTextEnabled":"yes","highContrastEnabled":false,"simpleViewEnabled":true}}',
      ),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => OnboardingResult.decode('{"profileId":"elderly","preferences":{}}'),
      throwsA(isA<FormatException>()),
    );
  });
}

class FakeCurrentLocationProvider implements CurrentLocationProvider {
  FakeCurrentLocationProvider({
    this.location,
    this.error,
    this.openSettingsLoader,
  });

  final CurrentLocation? location;
  final Object? error;
  final Future<bool> Function()? openSettingsLoader;
  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<bool> needsLocationPermissionRequest() async => true;

  @override
  Future<CurrentLocation> currentLocation() async {
    requestCount++;
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return location ??
        const CurrentLocation(latitude: 37.3028, longitude: 126.8665);
  }

  @override
  Future<bool> openLocationSettings() async {
    openSettingsCount++;
    final loader = openSettingsLoader;
    if (loader != null) {
      return loader();
    }
    return true;
  }
}

class FakeNotificationPermissionProvider
    implements NotificationPermissionProvider {
  FakeNotificationPermissionProvider({required this.status});

  final NotificationPermissionStatus status;
  int requestCount = 0;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async {
    requestCount++;
    return status;
  }
}
