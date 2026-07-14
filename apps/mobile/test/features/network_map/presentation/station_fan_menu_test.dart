import 'dart:ui' show SemanticsAction;

import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  double width = 700,
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
            width: width,
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

// design 좌표를 현재 메뉴 폭에 맞춰 위젯 글로벌 좌표로 변환한다.
Offset _global(WidgetTester tester, Offset design) {
  final topLeft = tester.getTopLeft(find.byType(StationFanMenu));
  final scale = tester.getSize(find.byType(StationFanMenu)).width / 700;
  return topLeft + design * scale;
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

  testWidgets('disabled 섹터 Semantics는 비활성이고 접근성 tap을 무시한다', (tester) async {
    final semantics = tester.ensureSemantics();
    final actions = <RouteDraftSlot>[];
    await _pump(
      tester,
      disabled: const {RouteDraftSlot.destination},
      onAction: actions.add,
      onClose: () {},
    );

    final node = tester.getSemantics(find.bySemanticsLabel('도착역으로 설정'));
    expect(
      node,
      matchesSemantics(
        label: '도착역으로 설정',
        isButton: true,
        hasEnabledState: true,
      ),
    );
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(actions, isEmpty);
    semantics.dispose();
  });

  testWidgets('4개 섹터 Semantics 버튼 라벨을 노출한다', (tester) async {
    await _pump(tester, onAction: (_) {}, onClose: () {});
    expect(find.bySemanticsLabel('출발역으로 설정'), findsOneWidget);
    expect(find.bySemanticsLabel('경유지로 추가'), findsOneWidget);
    expect(find.bySemanticsLabel('도착역으로 설정'), findsOneWidget);
    expect(find.bySemanticsLabel('메뉴 닫기'), findsOneWidget);
  });

  testWidgets('Semantics 탐색 순서는 출발·경유·도착·닫기다', (tester) async {
    await _pump(tester, onAction: (_) {}, onClose: () {});
    final orders = ['출발역으로 설정', '경유지로 추가', '도착역으로 설정', '메뉴 닫기'].map((label) {
      final sortKey = tester.getSemantics(find.bySemanticsLabel(label)).sortKey;
      return (sortKey! as OrdinalSortKey).order;
    });

    expect(orders, [0, 1, 2, 3]);
  });

  testWidgets('#2109 4개 섹터 Semantics 노드 rect는 상호 배제된다(겹침 면적 0)', (
    tester,
  ) async {
    // 회귀 방지: 섹터 Path getBounds() 사각형은 인접 섹터끼리 크게 겹쳐
    // explore-by-touch가 안내와 다른 섹터를 활성화할 수 있었다. 각 접근성 노드
    // rect는 아이콘·라벨 코어 주변의 비겹침 사각형으로 좁혀야 한다.
    await _pump(tester, onAction: (_) {}, onClose: () {});

    Rect rectFor(String label) => tester.getRect(
      find.descendant(
        of: find.bySemanticsLabel(label),
        matching: find.byType(SizedBox),
      ),
    );

    final rects = <Rect>[
      rectFor('출발역으로 설정'),
      rectFor('경유지로 추가'),
      rectFor('도착역으로 설정'),
      rectFor('메뉴 닫기'),
    ];

    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final overlap = rects[i].intersect(rects[j]);
        final area = overlap.isEmpty ? 0.0 : overlap.width * overlap.height;
        expect(area, 0.0, reason: '노드 $i 와 $j 의 접근성 rect가 겹친다(겹침 면적 $area)');
      }
    }
  });

  for (final width in [220.0, 296.0, 340.0]) {
    testWidgets('$width dp 메뉴의 Semantics는 48dp 이상이고 겹치지 않는다', (tester) async {
      await _pump(tester, width: width, onAction: (_) {}, onClose: () {});
      final rects = [
        '출발역으로 설정',
        '경유지로 추가',
        '도착역으로 설정',
        '메뉴 닫기',
      ].map((label) => tester.getRect(find.bySemanticsLabel(label))).toList();

      for (final rect in rects) {
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].intersect(rects[j]).isEmpty, isTrue);
        }
      }
    });
  }

  testWidgets('같은 활성 섹터에서 down/up한 경우에만 action을 실행한다', (tester) async {
    final actions = <RouteDraftSlot>[];
    await _pump(tester, onAction: actions.add, onClose: () {});
    final gesture = await tester.startGesture(
      _global(tester, const Offset(175, 168)),
    );
    await gesture.up();
    await tester.pump();
    expect(actions, [RouteDraftSlot.origin]);
  });

  testWidgets('다른 섹터로 드래그한 뒤 놓으면 action을 취소한다', (tester) async {
    final actions = <RouteDraftSlot>[];
    await _pump(tester, onAction: actions.add, onClose: () {});
    final gesture = await tester.startGesture(
      _global(tester, const Offset(175, 168)),
    );
    await gesture.moveTo(_global(tester, const Offset(350, 93)));
    await gesture.up();
    await tester.pump();
    expect(actions, isEmpty);
  });

  testWidgets('Path 밖 이동과 pointerCancel은 action을 취소한다', (tester) async {
    final actions = <RouteDraftSlot>[];
    await _pump(tester, onAction: actions.add, onClose: () {});
    final outside = await tester.startGesture(
      _global(tester, const Offset(175, 168)),
    );
    await outside.moveTo(_global(tester, const Offset(350, 370)));
    await outside.up();
    final cancelled = await tester.startGesture(
      _global(tester, const Offset(525, 173)),
    );
    await cancelled.cancel();
    await tester.pump();
    expect(actions, isEmpty);
  });

  testWidgets('다른 pointer의 up은 활성 pointer의 action을 완료하지 않는다', (tester) async {
    final actions = <RouteDraftSlot>[];
    await _pump(tester, onAction: actions.add, onClose: () {});
    final first = await tester.startGesture(
      _global(tester, const Offset(175, 168)),
      pointer: 1,
    );
    final second = await tester.startGesture(
      _global(tester, const Offset(350, 93)),
      pointer: 2,
    );
    await second.up();
    await tester.pump();
    expect(actions, isEmpty);
    await first.up();
    await tester.pump();
    expect(actions, [RouteDraftSlot.origin]);
  });
}
