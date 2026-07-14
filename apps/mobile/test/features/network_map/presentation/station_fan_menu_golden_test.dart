import 'dart:io' show File, Platform;
import 'dart:typed_data' show ByteData;

import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu.dart';
import 'package:easysubway_mobile/features/network_map/presentation/station_fan_menu_geometry.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

const _goldenFontFamily = 'NanumGothicGolden';
const _menuBoundaryKey = ValueKey('station-fan-menu-golden-boundary');
const _menuWidth = 260.0;

Future<void> _pumpMenu(
  WidgetTester tester, {
  double width = _menuWidth,
  Set<RouteDraftSlot> selected = const {},
  Set<RouteDraftSlot> disabled = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F7F7),
        body: Center(
          child: RepaintBoundary(
            key: _menuBoundaryKey,
            child: ColoredBox(
              color: const Color(0xFFF4F7F7),
              child: StationFanMenu(
                width: width,
                selectedSlots: selected,
                disabledSlots: disabled,
                fontFamily: _goldenFontFamily,
                onAction: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final bytes = await File(
      'test/assets/fonts/NanumGothic-Regular.ttf',
    ).readAsBytes();
    await (FontLoader(
      _goldenFontFamily,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  // golden 비교는 macOS 호스트 래스터라이저에서만 (CI 크로스플랫폼 오탐 방지).
  // testWidgets의 skip은 bool?만 받으므로(test()의 Object?와 달리 사유 문자열을
  // 못 담는다) 조건만 유지한다.
  final skipReason = !Platform.isMacOS;

  testWidgets('기본 상태', (tester) async {
    await _pumpMenu(tester);
    await expectLater(
      find.byKey(_menuBoundaryKey),
      matchesGoldenFile('goldens/station_fan_menu_default.png'),
    );
  }, skip: skipReason);

  testWidgets('비교 너비 296dp 기본 상태', (tester) async {
    await _pumpMenu(tester, width: 296);
    await expectLater(
      find.byKey(_menuBoundaryKey),
      matchesGoldenFile('goldens/station_fan_menu_default_296.png'),
    );
  }, skip: skipReason);

  testWidgets('출발 selected', (tester) async {
    await _pumpMenu(tester, selected: const {RouteDraftSlot.origin});
    await expectLater(
      find.byKey(_menuBoundaryKey),
      matchesGoldenFile('goldens/station_fan_menu_origin_selected.png'),
    );
  }, skip: skipReason);

  testWidgets('도착 selected', (tester) async {
    await _pumpMenu(tester, selected: const {RouteDraftSlot.destination});
    await expectLater(
      find.byKey(_menuBoundaryKey),
      matchesGoldenFile('goldens/station_fan_menu_destination_selected.png'),
    );
  }, skip: skipReason);

  testWidgets('도착 disabled', (tester) async {
    await _pumpMenu(tester, disabled: const {RouteDraftSlot.destination});
    await expectLater(
      find.byKey(_menuBoundaryKey),
      matchesGoldenFile('goldens/station_fan_menu_destination_disabled.png'),
    );
  }, skip: skipReason);

  testWidgets('출발 pressed', (tester) async {
    await _pumpMenu(tester);
    final menu = find.byType(StationFanMenu);
    final topLeft = tester.getTopLeft(menu);
    final gesture = await tester.startGesture(
      topLeft +
          const Offset(175, 168) * (_menuWidth / kFanMenuDesignSize.width),
    );
    addTearDown(gesture.cancel);
    await tester.pump();
    await expectLater(
      find.byKey(_menuBoundaryKey),
      matchesGoldenFile('goldens/station_fan_menu_departure_pressed.png'),
    );
  }, skip: skipReason);
}
