import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_data_source_toggle.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_direction_title.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_station_line_bar.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _line2Green = Color(0xFF00A84D);
const _line1Blue = Color(0xFF0052A4);

Widget _hostBar({
  required Color lineColor,
  String? leftName = '건대입구',
  String? rightName = '한양대',
  String stationName = '왕십리',
  String badgeText = '2',
  double width = 375,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: NearbyStationLineBar(
            leftName: leftName,
            rightName: rightName,
            stationName: stationName,
            badgeText: badgeText,
            lineColor: lineColor,
          ),
        ),
      ),
    ),
  );
}

BoxDecoration _decoration(WidgetTester tester, Key key) {
  return tester.widget<Container>(find.byKey(key)).decoration! as BoxDecoration;
}

void main() {
  group('NearbyStationLineBar (Task 3)', () {
    testWidgets('2호선 선택 시 좌우 바가 모두 동일 노선색(#00A84D)이다', (tester) async {
      await tester.pumpWidget(_hostBar(lineColor: _line2Green));

      final track = _decoration(tester, const Key('nearbyStationLineBarTrack'));
      expect(track.color, _line2Green);

      final capsule = _decoration(
        tester,
        const Key('nearbyStationLineBarCapsule'),
      );
      expect((capsule.border! as Border).top.color, _line2Green);
      expect((capsule.border! as Border).top.width, 3);
    });

    testWidgets('노선 변경 시 바·캡슐 테두리가 함께 갱신된다', (tester) async {
      await tester.pumpWidget(_hostBar(lineColor: _line2Green));
      expect(
        _decoration(tester, const Key('nearbyStationLineBarTrack')).color,
        _line2Green,
      );

      await tester.pumpWidget(_hostBar(lineColor: _line1Blue, badgeText: '1'));
      expect(
        _decoration(tester, const Key('nearbyStationLineBarTrack')).color,
        _line1Blue,
      );
      expect(
        (_decoration(tester, const Key('nearbyStationLineBarCapsule')).border!
                as Border)
            .top
            .color,
        _line1Blue,
      );
    });

    testWidgets('긴 역명은 한 줄 ellipsis로 자른다', (tester) async {
      await tester.pumpWidget(
        _hostBar(lineColor: _line2Green, stationName: '아주 긴 역이름 테스트 역명입니다'),
      );

      final text = tester.widget<Text>(find.text('아주 긴 역이름 테스트 역명입니다'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('320/375/480dp 너비에서 overflow가 없다', (tester) async {
      for (final width in const [320.0, 375.0, 480.0]) {
        await tester.pumpWidget(_hostBar(lineColor: _line2Green, width: width));
        expect(tester.takeException(), isNull, reason: 'width=$width overflow');
      }
    });

    Finder badgeCircleFinder() {
      return find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
      );
    }

    testWidgets('badgeText가 있으면 원형 노선 배지를 그린다', (tester) async {
      await tester.pumpWidget(_hostBar(lineColor: _line2Green, badgeText: '2'));
      expect(badgeCircleFinder(), findsOneWidget);
    });

    testWidgets('badgeText가 비면 빈 원 배지를 그리지 않고 역명만 남긴다', (tester) async {
      await tester.pumpWidget(_hostBar(lineColor: _line2Green, badgeText: ''));
      expect(badgeCircleFinder(), findsNothing);
      expect(find.text('왕십리'), findsOneWidget);
    });

    testWidgets('노선 바 전체가 하나의 Semantics 그룹 라벨을 노출한다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_hostBar(lineColor: _line2Green));

      expect(
        find.bySemanticsLabel('이전역 건대입구, 현재역 2 왕십리, 다음역 한양대'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('이전/다음역이 null이면 그룹 라벨에서 생략한다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _hostBar(lineColor: _line2Green, leftName: null, rightName: null),
      );

      expect(find.bySemanticsLabel('현재역 2 왕십리'), findsOneWidget);
      handle.dispose();
    });
  });

  group('NearbyDataSourceToggle (Task 4)', () {
    Widget hostToggle({
      required bool isRealtime,
      bool enabled = true,
      VoidCallback? onToggle,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: NearbyDataSourceToggle(
              isRealtime: isRealtime,
              enabled: enabled,
              onToggle: onToggle ?? () {},
            ),
          ),
        ),
      );
    }

    Container segmentContainer(WidgetTester tester, String label) {
      return tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: find.byType(Container)),
      );
    }

    testWidgets('두 세그먼트를 렌더하고 선택 세그먼트만 brandSignature 테두리를 갖는다', (
      tester,
    ) async {
      await tester.pumpWidget(hostToggle(isRealtime: true));

      expect(find.text('실시간'), findsOneWidget);
      expect(find.text('시간표'), findsOneWidget);

      final realtimeDeco =
          segmentContainer(tester, '실시간').decoration! as BoxDecoration;
      final timetableDeco =
          segmentContainer(tester, '시간표').decoration! as BoxDecoration;
      expect(realtimeDeco.color, Colors.white);
      expect(
        (realtimeDeco.border! as Border).top.color,
        EasySubwayAccessibleColors.brandSignature,
      );
      expect(
        timetableDeco.color,
        EasySubwayAccessibleColors.nearbyToggleIdleFill,
      );
      expect(timetableDeco.border, isNull);
    });

    testWidgets('선택 세그먼트는 Semantics selected를 노출한다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(hostToggle(isRealtime: true));

      final data = tester
          .getSemantics(find.bySemanticsLabel('실시간 선택됨'))
          .getSemanticsData();
      expect(data.flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('비선택 세그먼트 탭은 onToggle, 선택 세그먼트 탭은 no-op이다', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        hostToggle(isRealtime: true, onToggle: () => calls++),
      );

      await tester.tap(find.text('시간표'));
      await tester.pump();
      expect(calls, 1);

      await tester.tap(find.text('실시간'));
      await tester.pump();
      expect(calls, 1, reason: '선택된 세그먼트 탭은 no-op');
    });

    testWidgets('enabled:false면 양쪽 세그먼트 탭이 onToggle을 호출하지 않는다', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        hostToggle(isRealtime: true, enabled: false, onToggle: () => calls++),
      );

      await tester.tap(find.text('실시간'));
      await tester.pump();
      await tester.tap(find.text('시간표'));
      await tester.pump();
      expect(calls, 0, reason: '비활성 토글은 어느 세그먼트도 탭되지 않는다');
    });

    testWidgets('enabled:false면 선택 세그먼트도 비활성 시각(흰 배경·테두리 제거, mutedText)이다', (
      tester,
    ) async {
      await tester.pumpWidget(hostToggle(isRealtime: true, enabled: false));

      final realtimeDeco =
          segmentContainer(tester, '실시간').decoration! as BoxDecoration;
      expect(
        realtimeDeco.color,
        EasySubwayAccessibleColors.nearbyToggleIdleFill,
        reason: '비활성 선택 세그먼트는 흰 배경을 쓰지 않는다',
      );
      expect(
        realtimeDeco.border,
        isNull,
        reason: '비활성은 brandSignature 테두리를 걷어낸다',
      );

      final realtimeText = tester.widget<Text>(find.text('실시간'));
      expect(realtimeText.style!.color, EasySubwayAccessibleColors.mutedText);
    });

    testWidgets('전환 애니메이션 위젯이 없다', (tester) async {
      await tester.pumpWidget(hostToggle(isRealtime: true));
      expect(
        find.descendant(
          of: find.byType(NearbyDataSourceToggle),
          matching: find.byType(AnimatedContainer),
        ),
        findsNothing,
      );
      expect(find.byIcon(Icons.refresh), findsNothing);
    });
  });

  group('NearbyDirectionTitle (Task 5)', () {
    Widget hostTitle(String label, Color lineColor) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: NearbyDirectionTitle(label: label, lineColor: lineColor),
          ),
        ),
      );
    }

    List<InlineSpan> spansOf(WidgetTester tester) {
      final text = tester.widget<Text>(find.byType(Text));
      final root = text.textSpan! as TextSpan;
      return root.children!;
    }

    testWidgets('"방면"으로 끝나면 역명은 노선색, " 방면"은 #2F2F2F로 분리한다', (tester) async {
      await tester.pumpWidget(hostTitle('성수 방면', _line2Green));

      final spans = spansOf(tester).cast<TextSpan>();
      expect(spans[0].text, '성수');
      expect(spans[0].style!.color, _line2Green);
      expect(spans[1].text, ' 방면');
      expect(spans[1].style!.color, const Color(0xFF2F2F2F));
    });

    testWidgets('2호선 선택 시 방면 역명이 #00A84D이다', (tester) async {
      await tester.pumpWidget(hostTitle('건대입구 방면', _line2Green));
      final spans = spansOf(tester).cast<TextSpan>();
      expect(spans[0].text, '건대입구');
      expect(spans[0].style!.color, _line2Green);
    });

    testWidgets('"방면"으로 끝나지 않으면 전체를 노선색으로 그린다(텍스트 무변경)', (tester) async {
      await tester.pumpWidget(hostTitle('내선순환', _line2Green));
      final spans = spansOf(tester).cast<TextSpan>();
      expect(spans.length, 1);
      expect(spans[0].text, '내선순환');
      expect(spans[0].style!.color, _line2Green);
    });

    testWidgets('제목 스타일은 14sp w900이다', (tester) async {
      await tester.pumpWidget(hostTitle('성수 방면', _line2Green));
      final text = tester.widget<Text>(find.byType(Text));
      final root = text.textSpan! as TextSpan;
      expect(root.style!.fontSize, 14);
      expect(root.style!.fontWeight, FontWeight.w900);
    });
  });

  group('NearbyArrivalRow 회귀 (Task 5 무변경 고정)', () {
    testWidgets('"○○행"은 13sp w700 #2F2F2F, 도착 안내는 12sp w600으로 유지된다', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NearbyArrivalRow(destination: '성수', eta: '약 3분'),
          ),
        ),
      );

      final dest = tester.widget<Text>(find.text('성수행'));
      expect(dest.style!.fontSize, 13);
      expect(dest.style!.fontWeight, FontWeight.w700);
      expect(dest.style!.color, const Color(0xFF2F2F2F));

      final eta = tester.widget<Text>(find.text('약 3분'));
      expect(eta.style!.fontSize, 12);
      expect(eta.style!.fontWeight, FontWeight.w600);
      expect(eta.style!.color, EasySubwayAccessibleColors.secondaryText);
    });
  });
}
