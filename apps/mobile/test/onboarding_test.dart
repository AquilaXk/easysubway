import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/design_tokens.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_preset_labels.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
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

    expect(preferences.largeTextEnabled, isFalse);
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

  testWidgets('시작 화면은 부연 설명 문장 없이 핵심 가치 카피 3행과 단일 CTA만 둔다', (tester) async {
    // #2081: 브랜드 심볼/워드마크를 걷어내고, 시작 화면은 가치 카피 3행 +
    // "시작하기" CTA만 남긴다(카피 중심).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: StartScreen(onStart: () {})));

    expect(find.text('빠른 길보다\n갈 수 있는 길을\n안내합니다'), findsOneWidget);
    expect(find.byKey(const Key('startScreenStartButton')), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
    // #2081: 상단 브랜드 심볼/워드마크는 제거됐다 — 시작 화면에는 워드마크가 없다.
    expect(find.text('쉬운 지하철'), findsNothing);
    expect(find.bySemanticsLabel('쉬운 지하철'), findsNothing);
    // 부연 설명 문장은 전면 삭제됐다(#1936).
    expect(find.textContaining('먼저 안내해요'), findsNothing);
    expect(find.textContaining('엘리베이터와 출구까지'), findsNothing);
    expect(find.text('계단 없는 길을\n먼저 찾습니다'), findsNothing);
  });

  testWidgets('시작 화면 가치 타이틀은 header 시맨틱스로 노출되는 카피 3행이다', (tester) async {
    // #2081: 심볼 제거 후에도 가치 타이틀은 header 시맨틱스를 유지한다.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(MaterialApp(home: StartScreen(onStart: () {})));

    // 가치 타이틀은 header 시맨틱스로 노출된다.
    expect(
      tester.getSemantics(find.text('빠른 길보다\n갈 수 있는 길을\n안내합니다')),
      matchesSemantics(
        label: '빠른 길보다\n갈 수 있는 길을\n안내합니다',
        isHeader: true,
      ),
    );

    semanticsHandle.dispose();
  });

  testWidgets('시작 화면 타이틀은 "갈 수 있는 길"까지만 브랜드 색이고 조사 "을"·1·3행은 잉크 토큰이다', (
    tester,
  ) async {
    // #2089(오너 실기기 검수): 강조는 2행 중 "갈 수 있는 길"까지로 고정하고
    // 조사 "을"은 잉크로 남긴다. Text.rich 전환 후에도 스크린리더가 읽는 전체
    // 문자열은 그대로 유지되고, span별 색만 브랜드/잉크로 갈린다.
    await tester.pumpWidget(MaterialApp(home: StartScreen(onStart: () {})));

    final titleWidget = tester.widget<Text>(
      find.text('빠른 길보다\n갈 수 있는 길을\n안내합니다'),
    );
    final rootSpan = titleWidget.textSpan! as TextSpan;
    final children = rootSpan.children!.cast<TextSpan>();

    // 3개 span으로 나뉘고, 합친 평문은 기존 카피 3행과 동일하다.
    expect(children, hasLength(3));
    expect(rootSpan.toPlainText(), '빠른 길보다\n갈 수 있는 길을\n안내합니다');

    // 1행: 브랜드 색을 쓰지 않는다(루트 스타일의 잉크 토큰 상속).
    expect(children[0].text, '빠른 길보다\n');
    expect(children[0].style?.color, isNull);
    // 2행 강조: "갈 수 있는 길"까지만 시그니처 브랜드 색.
    expect(children[1].text, '갈 수 있는 길');
    expect(children[1].style?.color, EasySubwayAccessibleColors.brandSignature);
    // 조사 "을"과 3행: 브랜드 색을 쓰지 않는다.
    expect(children[2].text, '을\n안내합니다');
    expect(children[2].style?.color, isNull);

    // 루트 스타일은 기존 잉크 토큰을 유지한다.
    expect(titleWidget.style?.color, EasySubwayAccessibleColors.text);
  });

  testWidgets('시작 화면 CTA는 시그니처 브랜드 색 채움 + 흰 글자 + 키운 라벨이다', (tester) async {
    // #2089: '시작하기' CTA만 브랜드 색으로 채우고 글자는 흰색(대비 5.7:1, AA).
    // 오너 실기기 검수 2차로 라벨을 더 키운다(22/w700).
    await tester.pumpWidget(MaterialApp(home: StartScreen(onStart: () {})));

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('startScreenStartButton')),
    );
    final style = button.style!;
    expect(
      style.backgroundColor?.resolve(<WidgetState>{}),
      EasySubwayAccessibleColors.brandSignature,
    );
    expect(
      style.foregroundColor?.resolve(<WidgetState>{}),
      EasySubwayAccessibleColors.surface,
    );
    // 라벨을 키워 58px 버튼과 균형을 맞춘다.
    final textStyle = style.textStyle?.resolve(<WidgetState>{});
    expect(textStyle?.fontSize, 22);
    expect(textStyle?.fontWeight, FontWeight.w700);
  });

  testWidgets('시작 화면은 소형 화면(320×568)에서도 카피 3행과 CTA를 오버플로 없이 렌더한다', (
    tester,
  ) async {
    // #2081: 타이틀 확대(40)·카피 3행이 소형 화면에서 레이아웃 예외를 일으키지
    // 않는지 확인한다(SingleChildScrollView 구조가 오버플로를 흡수한다).
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: StartScreen(onStart: () {})));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('빠른 길보다\n갈 수 있는 길을\n안내합니다'), findsOneWidget);
    expect(find.byKey(const Key('startScreenStartButton')), findsOneWidget);
  });

  testWidgets('시작 화면은 소형 화면(320×568)+확대 텍스트에서도 스크롤로 CTA에 닿는다', (
    tester,
  ) async {
    // #2081 리뷰 finding: 기본 배율(320×568)에서는 콘텐츠가 화면에 다 들어가
    // maxScrollExtent가 0이라 SingleChildScrollView 구조가 제거돼도 이전
    // 테스트가 green일 수 있었다. textScaler를 키워 실제로 오버플로가
    // 발생하는 조건을 만든 뒤, Scrollable이 그 초과분을 흡수해 CTA까지
    // 스크롤·탭할 수 있음을 직접 검증한다.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: StartScreen(onStart: () => tapped = true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // 확대된 텍스트가 화면 높이를 넘어서 스크롤이 실제로 필요한 상태인지
    // 먼저 확인한다(회귀 시 이 값이 0으로 떨어져 아래 단언들이 무의미해지는
    // 것을 방지).
    final scrollPosition = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    expect(scrollPosition.maxScrollExtent, greaterThan(0));

    // ensureVisible로 스크롤해야 CTA를 탭할 수 있고, 탭이 실제로 콜백을
    // 호출한다 — SingleChildScrollView 구조가 제거되면 오버플로 예외로
    // 이 흐름 자체가 실패한다.
    await tester.ensureVisible(
      find.byKey(const Key('startScreenStartButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startScreenStartButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tapped, isTrue);
  });

  testWidgets('온보딩 시작 버튼은 Android 시스템 내비게이션 바와 여백을 둔다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(MaterialApp(home: StartScreen(onStart: () {})));

    final screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final buttonRect = tester.getRect(
      find.byKey(const Key('startScreenStartButton')),
    );

    // SafeArea 인셋(34) + 앱 토큰 여백(xxl*2)만 기대한다. 이중 가산 금지.
    // #2089: 오너 실기기 검수로 CTA 하단 여백을 xxl*2로 올렸다.
    expect(
      screenBottom - buttonRect.bottom,
      closeTo(34 + EasySubwaySpacing.xxl * 2, 0.5),
    );
  });

  testWidgets('온보딩은 이동 조건과 보기 설정을 선택한 뒤 완료 결과를 반환한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    OnboardingResult? completedResult;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: OnboardingScreen(
            notificationPermissionProvider:
                _FakeNotificationPermissionProvider(),
            onCompleted: (result) {
              completedResult = result;
            },
          ),
        ),
      );

      expect(find.text('쉬운 지하철'), findsOneWidget);
      expect(find.text('어떻게 걸으세요?'), findsOneWidget);
      expect(find.text('보통 걸음'), findsOneWidget);
      expect(find.text('휠체어 이용'), findsOneWidget);
      // #1703: 온보딩 step0은 표시명과 부가설명을 함께 노출한다.
      expect(find.text('엘리베이터로만 이동하는 길을 안내해요 · 유아차와 함께일 때도 좋아요'), findsOneWidget);

      // #1703: 기본 선택(보통 걸음)이라 '이대로 시작'으로 바로 통과할 수 있다.
      final doneButton = tester.widget<FilledButton>(
        find.byKey(const Key('onboardingDoneButton')),
      );
      expect(doneButton.onPressed, isNotNull);
      expect(find.text('이대로 시작'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('mobilityPresetRow-stepFree')),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          '휠체어 이용, 엘리베이터로만 이동하는 길을 안내해요 · 유아차와 함께일 때도 좋아요',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('onboardingDoneButton')));
      await tester.pumpAndSettle();

      // 조건 확인·보기 설정 단계는 제거됐다(#1563). 프로필 다음은 바로 권한 단계.
      expect(find.text('적용할 조건을 확인하세요'), findsNothing);
      expect(find.text('위치와 알림은 나중에도 켤 수 있어요'), findsOneWidget);
      expect(find.text('필요한 권한을 나중에 켤 수 있어요'), findsNothing);
      expect(find.text('현재 위치'), findsOneWidget);
      expect(find.text('알림'), findsOneWidget);
      expect(find.bySemanticsLabel('현재 위치 꺼짐'), findsOneWidget);
      expect(find.bySemanticsLabel('알림 꺼짐'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboardingPermissionSkipButton')));
      await tester.pumpAndSettle();

      expect(completedResult?.preset, MobilityPreset.stepFree);
      expect(completedResult?.mobilityType, 'WHEELCHAIR');
      // 보기 설정은 온보딩에서 더는 고르지 않으므로 기본값이 반환된다(#1563).
      expect(completedResult?.preferences.largeTextEnabled, isFalse);
      expect(completedResult?.preferences.highContrastEnabled, isFalse);
      expect(completedResult?.preferences.simpleViewEnabled, isTrue);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('온보딩 권한 단계는 박스 없이 라인 아이콘 행 + 구분선으로 항목을 나열한다', (tester) async {
    // #1936(전체 워크플로우 일관성): 권한 항목이 Card(박스)가 아니라 프로필
    // 리스트와 같은 행+Divider 언어여야 한다. 무채색 라인 아이콘 + 라벨 + 스위치.
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          notificationPermissionProvider: _FakeNotificationPermissionProvider(),
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('mobilityPresetRow-slow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    // 권한 항목은 무채색 라인 아이콘으로 시각 리듬을 준다(위치·알림).
    expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);

    // 두 항목 사이에는 박스 대신 무채색 구분선이 있다.
    final permissionDividers = tester
        .widgetList<Divider>(find.byType(Divider))
        .where((divider) => divider.color == EasySubwayAccessibleColors.line);
    expect(permissionDividers, isNotEmpty);

    // 권한 아이콘도 무채색 잉크 토큰만 쓴다(초록/민트 금지).
    final locationIcon = tester.widget<Icon>(
      find.byIcon(Icons.location_on_outlined),
    );
    expect(
      locationIcon.color,
      anyOf(
        EasySubwayAccessibleColors.text,
        EasySubwayAccessibleColors.mutedText,
      ),
    );

    // "나중에 설정" skip이 명확히 노출돼 몇 초 내 홈으로 통과할 수 있다.
    expect(
      find.byKey(const Key('onboardingPermissionSkipButton')),
      findsOneWidget,
    );
    expect(find.text('나중에 설정'), findsOneWidget);
  });

  testWidgets('온보딩 프로필 프리셋 행은 무채색 라인 아이콘과 라벨을 함께 둔다', (tester) async {
    // #1936(프리미엄 다듬기): personalization 리스트에 무채색 라인 아이콘으로
    // 시각 리듬을 준다. 아이콘은 색(초록/틴트) 없이 잉크 톤만 쓴다.
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onCompleted: (_) {})),
    );

    // 프리셋 행에는 라벨 옆에 무채색 라인 아이콘이 있다.
    final slowIcon = mobilityPresetIcon(MobilityPreset.slow);
    final rowFinder = find.byKey(const Key('mobilityPresetRow-slow'));
    expect(
      find.descendant(of: rowFinder, matching: find.byIcon(slowIcon)),
      findsOneWidget,
    );

    // 아이콘 색은 무채색 잉크 토큰만 쓴다(초록/민트/틴트 금지).
    final icon = tester.widget<Icon>(
      find.descendant(of: rowFinder, matching: find.byIcon(slowIcon)),
    );
    expect(
      icon.color,
      anyOf(
        EasySubwayAccessibleColors.text,
        EasySubwayAccessibleColors.mutedText,
      ),
    );
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

    await tester.tap(find.byKey(const Key('mobilityPresetRow-slow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    expect(find.text('위치와 알림은 나중에도 켤 수 있어요'), findsOneWidget);
    expect(find.text('필요한 권한을 나중에 켤 수 있어요'), findsNothing);
    await tester.tap(find.byKey(const Key('onboardingPermissionSkipButton')));
    await tester.pumpAndSettle();

    expect(completedResult, isNotNull);
    expect(completedResult?.preset, MobilityPreset.slow);
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

    await tester.tap(find.byKey(const Key('mobilityPresetRow-slow')));
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
    expect(completedResult?.preset, MobilityPreset.slow);
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
    expect(completedResult?.preset, MobilityPreset.slow);
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
    expect(completedResult?.preset, MobilityPreset.slow);
  });

  testWidgets('온보딩은 알림 권한 요청 실패 도움말을 안내한다', (tester) async {
    final notificationPermissionProvider = _FakeNotificationPermissionProvider(
      error: const NotificationSettingsException('알림 권한을 확인하지 못했어요.'),
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
      find.bySemanticsLabel('도움말, 나중에 알림 설정에서 다시 켤 수 있습니다.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('onboardingNotificationFailureNextAction')),
      findsOneWidget,
    );
  });

  testWidgets('온보딩 2·3단계는 이전 단계로 돌아갈 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          notificationPermissionProvider: _FakeNotificationPermissionProvider(),
          onCompleted: (_) {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('mobilityPresetRow-slow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    // 2단계 흐름: 프로필 → 권한. 권한에서 이전으로 돌아가면 프로필 단계로 온다(#1563).
    expect(find.text('위치와 알림은 나중에도 켤 수 있어요'), findsOneWidget);
    await tester.tap(find.byTooltip('이전 단계'));
    await tester.pumpAndSettle();
    expect(find.text('어떻게 걸으세요?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();
    expect(find.text('위치와 알림은 나중에도 켤 수 있어요'), findsOneWidget);
    expect(find.text('필요한 권한을 나중에 켤 수 있어요'), findsNothing);
  });

  testWidgets('온보딩 단계별로 하단 CTA 고정과 스크롤 여백을 확보한다', (tester) async {
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onCompleted: (_) {})),
    );

    final firstStepList = tester.widget<ListView>(find.byType(ListView));
    expect(firstStepList.padding?.resolve(TextDirection.ltr).bottom, 104);

    await tester.tap(find.byKey(const Key('mobilityPresetRow-slow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    // #1936: 권한 단계는 시작 화면과 같은 하단 고정 CTA 리듬을 쓴다 —
    // ListView 대신 스크롤 가능한 Column + Spacer로 두 CTA를 하단에 고정한다.
    expect(find.byType(ListView), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      find.byKey(const Key('onboardingPermissionAllowButton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('onboardingPermissionSkipButton')),
      findsOneWidget,
    );

    // 하단 인셋은 SafeArea가 적용하므로 패딩은 토큰(xxl)만 쓴다.
    final scrollPadding = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(IntrinsicHeight),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(
      scrollPadding.padding.resolve(TextDirection.ltr).bottom,
      moreOrLessEquals(EasySubwaySpacing.xxl),
    );
  });

  test('온보딩 완료 결과는 선택한 프리셋과 보기 설정을 함께 담는다', () {
    final result = OnboardingResult(
      preset: MobilityPreset.slow,
      preferences: const OnboardingViewPreferences(
        largeTextEnabled: false,
        highContrastEnabled: true,
        simpleViewEnabled: false,
      ),
    );

    expect(result.preset, MobilityPreset.slow);
    expect(result.mobilityType, 'SENIOR');
    expect(result.preferences.largeTextEnabled, isFalse);
    expect(result.preferences.highContrastEnabled, isTrue);
    expect(result.preferences.simpleViewEnabled, isFalse);
  });

  test('온보딩 완료 결과는 로컬 저장용 문자열로 변환하고 다시 읽는다', () {
    final result = OnboardingResult(
      preset: MobilityPreset.stepFree,
      preferences: const OnboardingViewPreferences(
        largeTextEnabled: false,
        highContrastEnabled: true,
        simpleViewEnabled: false,
      ),
    );

    final decoded = OnboardingResult.decode(result.encode());

    expect(decoded.preset, MobilityPreset.stepFree);
    expect(decoded.mobilityType, 'WHEELCHAIR');
    expect(decoded.preferences.largeTextEnabled, isFalse);
    expect(decoded.preferences.highContrastEnabled, isTrue);
    expect(decoded.preferences.simpleViewEnabled, isFalse);
  });

  test('온보딩 완료 결과는 새 preset 저장 포맷을 그대로 복원한다', () {
    final decoded = OnboardingResult.decode(
      '{"preset":"NO_STAIRS","preferences":{"largeTextEnabled":false,"highContrastEnabled":false,"simpleViewEnabled":true}}',
    );

    expect(decoded.preset, MobilityPreset.noStairs);
    expect(decoded.mobilityType, 'LUGGAGE');
  });

  test('온보딩 완료 결과는 구 profileId 저장값을 프리셋으로 승계한다(데이터 소실 없음)', () {
    const migrations = <String, MobilityPreset>{
      'elderly': MobilityPreset.slow,
      'pregnant': MobilityPreset.slow,
      'injured': MobilityPreset.slow,
      'luggage': MobilityPreset.noStairs,
      'stroller': MobilityPreset.stepFree,
      'wheelchair': MobilityPreset.stepFree,
    };
    migrations.forEach((profileId, expectedPreset) {
      final decoded = OnboardingResult.decode(
        '{"profileId":"$profileId","preferences":{"largeTextEnabled":false,"highContrastEnabled":false,"simpleViewEnabled":true}}',
      );
      expect(decoded.preset, expectedPreset, reason: profileId);
    });
  });

  test('온보딩 완료 결과는 알 수 없는 이동 조건 저장값을 거부한다', () {
    expect(
      () => OnboardingResult.decode(
        '{"profileId":"unknown","preferences":{"largeTextEnabled":true,"highContrastEnabled":false,"simpleViewEnabled":true}}',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => OnboardingResult.decode(
        '{"preset":"UNKNOWN","preferences":{"largeTextEnabled":true,"highContrastEnabled":false,"simpleViewEnabled":true}}',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('온보딩 완료 결과는 손상된 보기 설정 저장값을 거부한다', () {
    expect(
      () => OnboardingResult.decode(
        '{"preset":"SLOW","preferences":{"largeTextEnabled":"yes","highContrastEnabled":false,"simpleViewEnabled":true}}',
      ),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => OnboardingResult.decode('{"preset":"SLOW","preferences":{}}'),
      throwsA(isA<FormatException>()),
    );
  });
}

Future<void> _moveToPermissionStep(WidgetTester tester) async {
  // 2단계 흐름(#1563): 프로필 → '다음' 한 번이면 바로 권한 단계.
  await tester.tap(find.byKey(const Key('mobilityPresetRow-slow')));
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
  Future<NotificationPermissionStatus> notificationPermissionStatus() async =>
      NotificationPermissionStatus.granted;

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
