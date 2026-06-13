import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:easysubway_mobile/onboarding.dart';
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
}
