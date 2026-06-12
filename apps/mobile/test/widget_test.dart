import 'package:easysubway_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders concise home screen actions', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(const EasySubwayApp());

      expect(find.text('역 찾기'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '가까운 역'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '이동 조건'), findsOneWidget);
      expect(find.text('이동 프로필'), findsOneWidget);
      expect(find.text('시설 정보'), findsOneWidget);
      expect(find.text('신고'), findsOneWidget);
      expect(find.textContaining('빠른 길보다'), findsNothing);
      expect(find.textContaining('고령자'), findsNothing);
      expect(find.textContaining('휠체어'), findsNothing);
      expect(find.bySemanticsLabel('이동 프로필, 이동 조건 저장'), findsOneWidget);
      expect(find.bySemanticsLabel('시설 정보, 엘리베이터와 경사로'), findsOneWidget);
      expect(find.bySemanticsLabel('신고, 불편 신고'), findsOneWidget);

      final stationButtonSize = tester.getSize(
        find.byKey(const Key('stationSearchButton')),
      );
      final profileButtonSize = tester.getSize(
        find.byKey(const Key('mobilityProfileButton')),
      );

      expect(stationButtonSize.height, greaterThanOrEqualTo(60));
      expect(profileButtonSize.height, greaterThanOrEqualTo(60));
    } finally {
      semanticsHandle.dispose();
    }
  });
}
