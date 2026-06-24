import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_secure_key_value_storage.dart';

void main() {
  test('온보딩 보기 설정은 쉬운 기본값으로 시작한다', () {
    const preferences = OnboardingViewPreferences.defaults();

    expect(preferences.largeTextEnabled, isTrue);
    expect(preferences.highContrastEnabled, isFalse);
    expect(preferences.simpleViewEnabled, isTrue);
  });

  test('온보딩 저장소는 secure storage 복원 실패 시 저장값을 지운다', () async {
    final storage = FakeSecureKeyValueStorage(
      readError: StateError('restored Android KeyStore value is invalid'),
    );
    final store = SecureOnboardingResultStore(storage: storage);

    final result = await store.readResult();

    expect(result, isNull);
    expect(storage.deletedKeys, hasLength(1));
  });

  test('온보딩 저장소는 secure storage 삭제 실패에도 null로 복구한다', () async {
    final storage = FakeSecureKeyValueStorage(
      readError: StateError('restored Android KeyStore value is invalid'),
      deleteError: StateError('secure storage delete failed'),
    );
    final store = SecureOnboardingResultStore(storage: storage);

    final result = await store.readResult();

    expect(result, isNull);
    expect(storage.deletedKeys, isEmpty);
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
      expect(find.text('어떤 도움이 필요한가요?'), findsOneWidget);
      expect(find.text('천천히 이동'), findsOneWidget);
      expect(find.text('휠체어 이용'), findsOneWidget);

      final disabledDoneButton = tester.widget<FilledButton>(
        find.byKey(const Key('onboardingDoneButton')),
      );
      expect(disabledDoneButton.onPressed, isNull);

      await tester.tap(
        find.byKey(const Key('onboardingProfileCard-wheelchair')),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('휠체어 선택됨, 계단 없는 길만 안내해요'), findsOneWidget);

      await tester.tap(find.byKey(const Key('onboardingDoneButton')));
      await tester.pumpAndSettle();

      expect(find.text('적용할 조건을 확인하세요'), findsOneWidget);
      expect(find.text('계단 피하기'), findsOneWidget);
      expect(find.text('엘리베이터 이용'), findsOneWidget);
      expect(find.text('우선 적용'), findsWidgets);
      expect(find.text('보기 설정'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('계단 피하기 우선 적용, 계단 없는 길')),
        isSemantics(label: '계단 피하기 우선 적용, 계단 없는 길'),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('onboardingPreference-highContrast')),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(
          find.byKey(const Key('onboardingPreference-highContrast')),
        ),
        isSemantics(hasTapAction: true),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('onboardingPreference-highContrast')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboardingDoneButton')));
      await tester.pumpAndSettle();

      expect(find.text('필요한 권한을 나중에 켤 수 있어요'), findsOneWidget);
      expect(find.text('현재 위치'), findsOneWidget);
      expect(find.text('알림'), findsOneWidget);
      expect(find.bySemanticsLabel('현재 위치 꺼짐'), findsOneWidget);
      expect(find.bySemanticsLabel('알림 꺼짐'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboardingPermissionSkipButton')));
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

  testWidgets('온보딩 권한 단계는 나중에 설정을 누르면 권한 요청 없이 완료한다', (tester) async {
    final locationProvider = _FakeCurrentLocationProvider();
    final notificationPermissionProvider =
        _FakeNotificationPermissionProvider();
    OnboardingResult? completedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          locationProvider: locationProvider,
          notificationPermissionProvider: notificationPermissionProvider,
          onCompleted: (result) => completedResult = result,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('onboardingProfileCard-elderly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    expect(find.text('필요한 권한을 나중에 켤 수 있어요'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboardingPermissionSkipButton')));
    await tester.pumpAndSettle();

    expect(completedResult, isNotNull);
    expect(completedResult?.profile.id, 'elderly');
    expect(locationProvider.requestCount, 0);
    expect(notificationPermissionProvider.requestCount, 0);
  });

  testWidgets('온보딩 권한 단계는 켠 권한 provider를 호출한 뒤 완료한다', (tester) async {
    final locationProvider = _FakeCurrentLocationProvider();
    final notificationPermissionProvider =
        _FakeNotificationPermissionProvider();
    OnboardingResult? completedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          locationProvider: locationProvider,
          notificationPermissionProvider: notificationPermissionProvider,
          onCompleted: (result) => completedResult = result,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('onboardingProfileCard-elderly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch).first);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingPermissionAllowButton')));
    await tester.pumpAndSettle();

    expect(locationProvider.requestCount, 1);
    expect(notificationPermissionProvider.requestCount, 1);
    expect(completedResult?.profile.id, 'elderly');
  });

  testWidgets('온보딩 권한 단계는 알림만 켜면 알림 provider만 호출한다', (tester) async {
    final locationProvider = _FakeCurrentLocationProvider();
    final notificationPermissionProvider =
        _FakeNotificationPermissionProvider();
    OnboardingResult? completedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          locationProvider: locationProvider,
          notificationPermissionProvider: notificationPermissionProvider,
          onCompleted: (result) => completedResult = result,
        ),
      ),
    );

    await _moveToPermissionStep(tester);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingPermissionAllowButton')));
    await tester.pumpAndSettle();

    expect(locationProvider.requestCount, 0);
    expect(notificationPermissionProvider.requestCount, 1);
    expect(completedResult?.profile.id, 'elderly');
  });

  testWidgets('온보딩 권한 단계는 위치만 켜면 위치 provider만 호출한다', (tester) async {
    final locationProvider = _FakeCurrentLocationProvider();
    final notificationPermissionProvider =
        _FakeNotificationPermissionProvider();
    OnboardingResult? completedResult;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          locationProvider: locationProvider,
          notificationPermissionProvider: notificationPermissionProvider,
          onCompleted: (result) => completedResult = result,
        ),
      ),
    );

    await _moveToPermissionStep(tester);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingPermissionAllowButton')));
    await tester.pumpAndSettle();

    expect(locationProvider.requestCount, 1);
    expect(notificationPermissionProvider.requestCount, 0);
    expect(completedResult?.profile.id, 'elderly');
  });

  testWidgets('온보딩은 알림 권한 요청 실패 다음 행동을 안내한다', (tester) async {
    final notificationPermissionProvider = _FakeNotificationPermissionProvider(
      error: const NotificationSettingsException('알림 권한을 확인하지 못했습니다.'),
    );
    OnboardingResult? completedResult;

    final reportedErrors = <FlutterErrorDetails>[];
    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            notificationPermissionProvider: notificationPermissionProvider,
            onCompleted: (result) => completedResult = result,
          ),
        ),
      );

      await _moveToPermissionStep(tester);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('onboardingPermissionAllowButton')),
      );
      await tester.pumpAndSettle();
    });

    expect(reportedErrors, hasLength(1));
    expect(completedResult, isNull);
    expect(find.text('나중에 알림 설정에서 다시 켤 수 있습니다.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('다음 행동, 나중에 알림 설정에서 다시 켤 수 있습니다.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('onboardingNotificationFailureNextAction')),
      findsOneWidget,
    );
  });

  testWidgets('온보딩 2·3단계는 이전 단계로 돌아갈 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onCompleted: (_) {})),
    );

    await tester.tap(find.byKey(const Key('onboardingProfileCard-elderly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    expect(find.text('적용할 조건을 확인하세요'), findsOneWidget);
    expect(find.text('우선 적용'), findsWidgets);
    expect(find.text('기본 적용'), findsWidgets);
    await tester.tap(find.byTooltip('이전 단계'));
    await tester.pumpAndSettle();
    expect(find.text('어떤 도움이 필요한가요?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    expect(find.text('필요한 권한을 나중에 켤 수 있어요'), findsOneWidget);
    await tester.tap(find.byTooltip('이전 단계'));
    await tester.pumpAndSettle();
    expect(find.text('적용할 조건을 확인하세요'), findsOneWidget);
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

Future<void> _moveToPermissionStep(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('onboardingProfileCard-elderly')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('onboardingDoneButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('onboardingDoneButton')));
  await tester.pumpAndSettle();
}

class _FakeCurrentLocationProvider implements CurrentLocationProvider {
  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<bool> needsLocationPermissionRequest() async {
    return false;
  }

  @override
  Future<CurrentLocation> currentLocation() async {
    requestCount++;
    return const CurrentLocation(latitude: 37.5665, longitude: 126.9780);
  }

  @override
  Future<bool> openLocationSettings() async {
    openSettingsCount++;
    return true;
  }
}

class _FakeNotificationPermissionProvider
    implements NotificationPermissionProvider {
  _FakeNotificationPermissionProvider({this.error});

  final NotificationSettingsException? error;
  int requestCount = 0;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async {
    requestCount++;
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return NotificationPermissionStatus.granted;
  }
}
