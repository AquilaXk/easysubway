import 'dart:io' show Platform;

import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpMenu(
  WidgetTester tester, {
  Set<RouteDraftSlot> selected = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F7F7),
        body: Center(
          child: StationFanMenu(
            width: 350,
            selectedSlots: selected,
            disabledSlots: const {},
            onAction: (_) {},
            onClose: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // golden 비교는 macOS 호스트 래스터라이저에서만 (CI 크로스플랫폼 오탐 방지).
  // testWidgets의 skip은 bool?만 받으므로(test()의 Object?와 달리 사유 문자열을
  // 못 담는다) 조건만 유지한다.
  final skipReason = !Platform.isMacOS;

  testWidgets('기본 상태', (tester) async {
    await _pumpMenu(tester);
    await expectLater(
      find.byType(StationFanMenu),
      matchesGoldenFile('goldens/station_fan_menu_default.png'),
    );
  }, skip: skipReason);

  testWidgets('출발 selected', (tester) async {
    await _pumpMenu(tester, selected: const {RouteDraftSlot.origin});
    await expectLater(
      find.byType(StationFanMenu),
      matchesGoldenFile('goldens/station_fan_menu_origin_selected.png'),
    );
  }, skip: skipReason);

  testWidgets('도착 selected', (tester) async {
    await _pumpMenu(tester, selected: const {RouteDraftSlot.destination});
    await expectLater(
      find.byType(StationFanMenu),
      matchesGoldenFile('goldens/station_fan_menu_destination_selected.png'),
    );
  }, skip: skipReason);
}
