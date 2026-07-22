import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EasySubwayTokens', () {
    testWidgets('theme 등록이 없어도 of(context)는 light 값을 돌려준다', (tester) async {
      late EasySubwayTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              tokens = EasySubwayTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(tokens, EasySubwayTokens.light);
    });

    test('light 토큰 값은 기존 공용 팔레트와 일치한다 — 기준 화면 룩 불변 증명', () {
      const tokens = EasySubwayTokens.light;
      expect(tokens.ink, EasySubwayAccessibleColors.text);
      expect(tokens.inkSecondary, EasySubwayAccessibleColors.secondaryText);
      expect(tokens.inkMuted, EasySubwayAccessibleColors.mutedText);
      expect(tokens.line, EasySubwayAccessibleColors.line);
      expect(tokens.surface, EasySubwayAccessibleColors.surface);
      expect(tokens.scaffold, EasySubwayAccessibleColors.scaffoldSurface);
      expect(tokens.accent, EasySubwayAccessibleColors.primary);
      expect(tokens.good, EasySubwayAccessibleColors.mint);
      expect(tokens.warn, EasySubwayAccessibleColors.amber);
      expect(tokens.danger, EasySubwayAccessibleColors.red);
      // 지도 오버레이 전용 톤 — 기준 화면(network_map)의 기존 값 그대로.
      expect(tokens.mapSelectionAccent, const Color(0xFF13B8D6));
      expect(tokens.mapRegionAccent, const Color(0xFF006FD6));
    });

    testWidgets('앱 theme에 extension으로 등록되어 of(context)로 조회된다', (tester) async {
      late EasySubwayTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [EasySubwayTokens.light],
            useMaterial3: true,
          ),
          home: Builder(
            builder: (context) {
              tokens = EasySubwayTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(identical(tokens, EasySubwayTokens.light), isTrue);
    });
  });

  group('easySubwayTextTheme', () {
    test('타이포 위계 — 타이틀만 w800, 본문 w500, 라벨 w600', () {
      final theme = easySubwayTextTheme(
        ThemeData(useMaterial3: true).textTheme,
      );
      expect(theme.titleLarge?.fontWeight, FontWeight.w800);
      expect(theme.titleMedium?.fontWeight, FontWeight.w700);
      expect(theme.bodyLarge?.fontWeight, FontWeight.w500);
      expect(theme.bodyMedium?.fontWeight, FontWeight.w500);
      expect(theme.labelLarge?.fontWeight, FontWeight.w600);
    });
  });

  group('EasySubwaySpacing / EasySubwayRadius', () {
    test('간격·radius 스케일 고정', () {
      expect(EasySubwaySpacing.xs, 4.0);
      expect(EasySubwaySpacing.sm, 8.0);
      expect(EasySubwaySpacing.md, 12.0);
      expect(EasySubwaySpacing.lg, 16.0);
      expect(EasySubwaySpacing.xl, 24.0);
      expect(EasySubwaySpacing.xxl, 32.0);
      expect(EasySubwayRadius.control, 8.0);
      expect(EasySubwayRadius.card, 12.0);
      expect(EasySubwayRadius.sheet, 16.0);
    });
  });

  test('부채꼴 메뉴 v2 색상과 opacity를 고정한다', () {
    expect(EasySubwayFanMenuColors.disabledOpacity, 0.40);
    expect(EasySubwayFanMenuColors.pressedOpacity, 0.84);
    expect(EasySubwayFanMenuColors.departure, const Color(0xFF0A84FF));
    expect(EasySubwayFanMenuColors.departureSurface, const Color(0xFFF2F8FF));
    expect(EasySubwayFanMenuColors.departurePressed, const Color(0xFFE1F0FF));
    expect(EasySubwayFanMenuColors.waypoint, const Color(0xFFFF9F0A));
    expect(EasySubwayFanMenuColors.waypointSurface, const Color(0xFFFFF8ED));
    expect(EasySubwayFanMenuColors.waypointPressed, const Color(0xFFFFEFCC));
    expect(EasySubwayFanMenuColors.arrival, const Color(0xFFFF3B30));
    expect(EasySubwayFanMenuColors.arrivalSurface, const Color(0xFFFFF5F4));
    expect(EasySubwayFanMenuColors.arrivalPressed, const Color(0xFFFFE8E6));
    expect(EasySubwayFanMenuColors.pinShadow, const Color(0x40000000));
    expect(EasySubwayFanMenuColors.pinEdgeDeparture, const Color(0xFF0654A1));
    expect(EasySubwayFanMenuColors.pinEdgeWaypoint, const Color(0xFFA16506));
    expect(EasySubwayFanMenuColors.pinEdgeArrival, const Color(0xFFA1251E));
    expect(EasySubwayFanMenuColors.pinClearBg, const Color(0xFFFFFFFF));
    expect(EasySubwayFanMenuColors.pinClearBorder, const Color(0xFFE5E5E5));
    expect(EasySubwayFanMenuColors.pinClearInk, const Color(0xFF666666));
    expect(EasySubwayFanMenuColors.pinClearShadow, const Color(0x26000000));
    expect(EasySubwayFanMenuColors.closeSurface, const Color(0xFFF5F7FA));
    expect(EasySubwayFanMenuColors.closePressed, const Color(0xFFE9EDF2));
    expect(EasySubwayFanMenuColors.closeInk, const Color(0xFF475467));
    expect(EasySubwayFanMenuColors.border, const Color(0xE8404445));
    expect(EasySubwayFanMenuColors.outline, const Color(0xE8404445));
  });
}
