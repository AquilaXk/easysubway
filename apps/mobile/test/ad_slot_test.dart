import 'package:easysubway_mobile/ad_slot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('광고 슬롯은 debug 표준 placeholder를 지킨다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    const slotKey = Key('adSlotTest');
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(width: 400, child: AdBannerSlot(slotKey: slotKey)),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(slotKey)).height, 96);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '광고',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.text('광고 미리보기 (개발용)'), findsOneWidget);
    expect(find.text('표준 배너 규격 자리표시 텍스트'), findsOneWidget);
    expect(find.byType(Column), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('광고 미리보기 (개발용)'),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    semanticsHandle.dispose();
  });
}
