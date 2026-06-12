import 'package:easysubway_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders accessibility guidance home screen', (tester) async {
    await tester.pumpWidget(const EasySubwayApp());

    expect(find.text('접근성 이동 안내'), findsOneWidget);
    expect(find.text('빠른 길보다, 갈 수 있는 길을 먼저 안내합니다.'), findsOneWidget);
    expect(find.textContaining('고령자, 임산부, 장애인'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '가까운 역 찾기'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '이동 조건 선택'), findsOneWidget);
    expect(find.text('이동 프로필'), findsOneWidget);
    expect(find.text('시설 정보'), findsOneWidget);
    expect(find.text('신고와 검수'), findsOneWidget);

    final stationButtonSize = tester.getSize(
      find.byKey(const Key('stationSearchButton')),
    );
    final profileButtonSize = tester.getSize(
      find.byKey(const Key('mobilityProfileButton')),
    );

    expect(stationButtonSize.height, greaterThanOrEqualTo(60));
    expect(profileButtonSize.height, greaterThanOrEqualTo(60));
  });
}
