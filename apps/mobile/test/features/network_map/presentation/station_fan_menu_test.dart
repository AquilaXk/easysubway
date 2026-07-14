import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  Set<RouteDraftSlot> selected = const {},
  Set<RouteDraftSlot> disabled = const {},
  required void Function(RouteDraftSlot) onAction,
  required VoidCallback onClose,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: StationFanMenu(
            width: 700, // design 1:1 스케일이라 design 좌표=위젯 좌표
            selectedSlots: selected,
            disabledSlots: disabled,
            onAction: onAction,
            onClose: onClose,
          ),
        ),
      ),
    ),
  );
}

// width=700 → 위젯 로컬 좌표 = design 좌표. Center 배치이므로 위젯 좌상단
// 오프셋을 더해 글로벌 좌표로 변환한다.
Offset _global(WidgetTester tester, Offset design) {
  final topLeft = tester.getTopLeft(find.byType(StationFanMenu));
  return topLeft + design;
}

void main() {
  testWidgets('각 섹터 아이콘 중심 탭은 올바른 슬롯을 onAction으로 보낸다', (tester) async {
    final actions = <RouteDraftSlot>[];
    var closed = 0;
    await _pump(tester, onAction: actions.add, onClose: () => closed++);

    await tester.tapAt(_global(tester, const Offset(175, 173))); // 출발
    await tester.tapAt(_global(tester, const Offset(350, 127))); // 경유
    await tester.tapAt(_global(tester, const Offset(525, 173))); // 도착
    await tester.pump();
    expect(actions, [
      RouteDraftSlot.origin,
      RouteDraftSlot.waypoint,
      RouteDraftSlot.destination,
    ]);
    expect(closed, 0);
  });

  testWidgets('닫기 노치 탭은 onClose를 부른다', (tester) async {
    final actions = <RouteDraftSlot>[];
    var closed = 0;
    await _pump(tester, onAction: actions.add, onClose: () => closed++);
    await tester.tapAt(_global(tester, const Offset(350, 277))); // 닫기
    await tester.pump();
    expect(actions, isEmpty);
    expect(closed, 1);
  });

  testWidgets('disabled 슬롯 섹터 탭은 무시된다', (tester) async {
    final actions = <RouteDraftSlot>[];
    await _pump(
      tester,
      disabled: const {RouteDraftSlot.destination},
      onAction: actions.add,
      onClose: () {},
    );
    await tester.tapAt(_global(tester, const Offset(525, 173))); // 도착(disabled)
    await tester.pump();
    expect(actions, isEmpty);
  });

  testWidgets('4개 섹터 Semantics 버튼 라벨을 노출한다', (tester) async {
    await _pump(tester, onAction: (_) {}, onClose: () {});
    expect(find.bySemanticsLabel('출발역으로 설정'), findsOneWidget);
    expect(find.bySemanticsLabel('경유지로 추가'), findsOneWidget);
    expect(find.bySemanticsLabel('도착역으로 설정'), findsOneWidget);
    expect(find.bySemanticsLabel('메뉴 닫기'), findsOneWidget);
  });
}
