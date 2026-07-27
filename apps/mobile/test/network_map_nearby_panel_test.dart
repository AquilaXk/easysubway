import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_data_source_toggle.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_direction_columns.dart';
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
  VoidCallback? onLeftNameTap,
  VoidCallback? onRightNameTap,
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
            onLeftNameTap: onLeftNameTap,
            onRightNameTap: onRightNameTap,
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
    testWidgets('이전·다음 역 이름을 탭하면 콜백이 호출된다', (tester) async {
      var leftTaps = 0;
      var rightTaps = 0;
      await tester.pumpWidget(
        _hostBar(
          lineColor: _line2Green,
          onLeftNameTap: () => leftTaps++,
          onRightNameTap: () => rightTaps++,
        ),
      );

      await tester.tap(find.byKey(const Key('nearbyStationLineBarLeftName')));
      await tester.tap(find.byKey(const Key('nearbyStationLineBarRightName')));
      await tester.pump();

      expect(leftTaps, 1);
      expect(rightTaps, 1);
    });

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
        find.byKey(ValueKey('networkMapNearbyDataSourceToggleSegment-$label')),
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
      // 선택 칸만 흰 배경 + brandSignature 2dp pill이다.
      expect(realtimeDeco.color, Colors.white);
      expect(
        (realtimeDeco.border! as Border).top.color,
        EasySubwayAccessibleColors.brandSignature,
      );
      expect((realtimeDeco.border! as Border).top.width, 2);
      // 비선택 칸은 pill을 그리지 않는다(단일 배경 track이 뒤에서 감싼다).
      expect(timetableDeco.color, Colors.transparent);
      expect(timetableDeco.border, isNull);
    });

    testWidgets('두 칸이 간격 없이 하나의 단일 배경 track 안에 붙어 있다', (tester) async {
      await tester.pumpWidget(hostToggle(isRealtime: true));

      // 단일 라운드 배경이 두 칸을 하나로 감싼다(시각 118×32, radius 16).
      final track = tester.widget<Container>(
        find.byKey(const Key('networkMapNearbyDataSourceToggleTrack')),
      );
      final trackDeco = track.decoration! as BoxDecoration;
      expect(trackDeco.color, EasySubwayAccessibleColors.nearbyToggleIdleFill);
      expect(
        trackDeco.borderRadius,
        const BorderRadius.all(Radius.circular(16)),
      );
      expect(
        tester.getSize(
          find.byKey(const Key('networkMapNearbyDataSourceToggleTrack')),
        ),
        const Size(118, 32),
      );

      // 두 칸 사이 간격이 0이다: 왼쪽 칸의 오른쪽 끝과 오른쪽 칸의 왼쪽 끝이 맞닿는다.
      final realtimeRect = tester.getRect(find.text('실시간'));
      final timetableRect = tester.getRect(find.text('시간표'));
      final leftSegment = tester.getRect(
        find.byKey(
          const ValueKey('networkMapNearbyDataSourceToggleSegment-실시간'),
        ),
      );
      final rightSegment = tester.getRect(
        find.byKey(
          const ValueKey('networkMapNearbyDataSourceToggleSegment-시간표'),
        ),
      );
      expect(realtimeRect.center.dx, lessThan(timetableRect.center.dx));
      expect(rightSegment.left - leftSegment.right, moreOrLessEquals(0));
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

    testWidgets('시간표 선택 세그먼트도 Semantics selected를 노출한다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(hostToggle(isRealtime: false));

      final selected = tester
          .getSemantics(find.bySemanticsLabel('시간표 선택됨'))
          .getSemanticsData();
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
      final unselected = tester
          .getSemantics(find.bySemanticsLabel('실시간로 전환'))
          .getSemanticsData();
      expect(unselected.flagsCollection.isSelected, isNot(Tristate.isTrue));
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
        Colors.transparent,
        reason: '비활성 선택 세그먼트는 흰 pill을 그리지 않는다',
      );
      expect(
        realtimeDeco.border,
        isNull,
        reason: '비활성은 brandSignature 테두리를 걷어낸다',
      );
      // 단일 배경 track은 비활성에서도 idleFill을 유지한다.
      final trackDeco =
          tester
                  .widget<Container>(
                    find.byKey(
                      const Key('networkMapNearbyDataSourceToggleTrack'),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(trackDeco.color, EasySubwayAccessibleColors.nearbyToggleIdleFill);

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

    testWidgets('"방면"으로 끝나면 역명은 노선색, " 방면"은 본문 역할색으로 분리한다', (tester) async {
      await tester.pumpWidget(hostTitle('성수 방면', _line2Green));

      final spans = spansOf(tester).cast<TextSpan>();
      expect(spans[0].text, '성수');
      expect(spans[0].style!.color, _line2Green);
      expect(spans[1].text, ' 방면');
      expect(spans[1].style!.color, EasySubwayAccessibleColors.contentPrimary);
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
    testWidgets('"○○행"은 13sp w700 본문 역할색, 도착 안내는 12sp w600으로 유지된다', (
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
      expect(dest.style!.color, EasySubwayAccessibleColors.contentPrimary);

      final eta = tester.widget<Text>(find.text('약 3분'));
      expect(eta.style!.fontSize, 12);
      expect(eta.style!.fontWeight, FontWeight.w600);
      expect(eta.style!.color, EasySubwayAccessibleColors.secondaryText);
    });
  });

  // 실시간·시간표 패널이 공유하는 열 구성 로직(#2200 QA): 열차 정보가 없어도
  // 인접역에서 방면 제목을 유도해 두 열 스켈레톤을 유지한다.
  group('resolveNearbyColumnSlots (#2200 QA)', () {
    test('(a) 데이터 전무 + 인접 2개 → 좌(이전)-우(다음) 두 대시 열', () {
      final slots = resolveNearbyColumnSlots(
        dataTitles: const [],
        leftName: '건대입구',
        rightName: '한양대',
      );
      expect(slots.map((s) => s.title).toList(), ['건대입구 방면', '한양대 방면']);
      expect(slots.every((s) => s.dataIndex == null), isTrue);
    });

    test('(b) 데이터 1방면 + 인접 2개 → 데이터 열 + 대시 열(포함되지 않은 인접역)', () {
      // 라벨에 어느 인접역도 없으면 rightName을 대시 열로(오른쪽에) 배치한다.
      final slots = resolveNearbyColumnSlots(
        dataTitles: const ['성수 방면'],
        leftName: '건대입구',
        rightName: '뚝섬',
      );
      expect(slots.length, 2);
      expect(slots[0].title, '성수 방면');
      expect(slots[0].dataIndex, 0);
      expect(slots[1].title, '뚝섬 방면');
      expect(slots[1].dataIndex, isNull);
    });

    test('(b\') 데이터 라벨에 포함된 인접역은 대시 열에서 제외한다(contains)', () {
      // 라벨이 rightName(뚝섬)을 포함 → 대시 열은 leftName(건대입구), 왼쪽 배치.
      final slots = resolveNearbyColumnSlots(
        dataTitles: const ['뚝섬 방면'],
        leftName: '건대입구',
        rightName: '뚝섬',
      );
      expect(slots.length, 2);
      expect(slots[0].title, '건대입구 방면');
      expect(slots[0].dataIndex, isNull);
      expect(slots[1].title, '뚝섬 방면');
      expect(slots[1].dataIndex, 0);
    });

    test('(b\'\') 인접역 판단 불가(모두 라벨 포함)면 rightName을 대시 열로 우선한다', () {
      final slots = resolveNearbyColumnSlots(
        dataTitles: const ['성수·건대입구 방면'],
        leftName: '건대입구',
        rightName: '성수',
      );
      expect(slots.length, 2);
      expect(slots.firstWhere((s) => s.dataIndex == null).title, '성수 방면');
    });

    test('(c) 인접 1개(종착) → 한 열만(구분선 없음)', () {
      final slots = resolveNearbyColumnSlots(
        dataTitles: const [],
        leftName: '건대입구',
        rightName: null,
      );
      expect(slots.length, 1);
      expect(slots.single.title, '건대입구 방면');
      expect(slots.single.dataIndex, isNull);
    });

    test('(c\'\') 종착(다음역만)도 한 열만이다', () {
      final slots = resolveNearbyColumnSlots(
        dataTitles: const [],
        leftName: null,
        rightName: '한양대',
      );
      expect(slots.length, 1);
      expect(slots.single.title, '한양대 방면');
      expect(slots.single.dataIndex, isNull);
    });

    test('(c\') 데이터 1방면 + 인접 0개 → 데이터 한 열만', () {
      final slots = resolveNearbyColumnSlots(
        dataTitles: const ['성수 방면'],
        leftName: null,
        rightName: null,
      );
      expect(slots.length, 1);
      expect(slots.single.dataIndex, 0);
    });

    test('(d) 인접 0개 + 데이터 0개 → 빈 리스트(호출부 대시 폴백)', () {
      final slots = resolveNearbyColumnSlots(
        dataTitles: const [],
        leftName: null,
        rightName: '   ',
      );
      expect(slots, isEmpty);
    });

    test('(e) 데이터 2방면 → 인접역과 무관하게 기존 두 데이터 열 유지', () {
      final slots = resolveNearbyColumnSlots(
        dataTitles: const ['성수 방면', '신도림 방면'],
        leftName: '건대입구',
        rightName: '한양대',
      );
      expect(slots.map((s) => s.title).toList(), ['성수 방면', '신도림 방면']);
      expect(slots.map((s) => s.dataIndex).toList(), [0, 1]);
    });
  });

  group('NearbyPanelColumns (#2200 QA)', () {
    Widget host(List<NearbyPanelColumn> columns) {
      return MaterialApp(
        home: Scaffold(
          body: NearbyPanelColumns(columns: columns, lineColor: _line2Green),
        ),
      );
    }

    testWidgets('데이터 없는 두 열은 제목 + 대시 + 1개 구분선을 그린다', (tester) async {
      await tester.pumpWidget(
        host(const [
          NearbyPanelColumn(title: '건대입구 방면'),
          NearbyPanelColumn(title: '한양대 방면'),
        ]),
      );

      expect(find.byType(NearbyDirectionTitle), findsNWidgets(2));
      expect(find.text('-'), findsNWidgets(2));
      expect(find.byType(VerticalDivider), findsOneWidget);
    });

    testWidgets('데이터 열 + 대시 열: 데이터 열은 도착 행, 나머지는 대시', (tester) async {
      await tester.pumpWidget(
        host(const [
          NearbyPanelColumn(
            title: '성수 방면',
            rows: [NearbyArrivalRow(destination: '성수', eta: '약 3분')],
          ),
          NearbyPanelColumn(title: '뚝섬 방면'),
        ]),
      );

      expect(find.text('성수행'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
      expect(find.byType(VerticalDivider), findsOneWidget);
    });

    testWidgets('한 열만 있으면 구분선을 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        host(const [NearbyPanelColumn(title: '건대입구 방면')]),
      );
      expect(find.byType(VerticalDivider), findsNothing);
      expect(find.text('-'), findsOneWidget);
    });

    testWidgets('종착역(인접 1개) 슬롯은 한 열·대시만 그리고 구분선이 없다', (tester) async {
      final slots = resolveNearbyColumnSlots(
        dataTitles: const [],
        leftName: '건대입구',
        rightName: null,
      );
      await tester.pumpWidget(
        host([for (final slot in slots) NearbyPanelColumn(title: slot.title)]),
      );

      expect(find.byType(NearbyDirectionTitle), findsOneWidget);
      expect(find.text('건대입구 방면'), findsOneWidget);
      expect(find.text('-'), findsOneWidget);
      expect(find.byType(VerticalDivider), findsNothing);
    });

    testWidgets('대시 스타일은 16sp w700 본문 역할색이다', (tester) async {
      await tester.pumpWidget(
        host(const [NearbyPanelColumn(title: '건대입구 방면')]),
      );
      final dash = tester.widget<Text>(find.text('-'));
      expect(dash.style!.fontSize, 16);
      expect(dash.style!.fontWeight, FontWeight.w700);
      expect(dash.style!.color, EasySubwayAccessibleColors.contentPrimary);
    });

    testWidgets('대시 열은 열 단위 Semantics 라벨을 쓰고 대시 문자는 제외한다', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(const [
          NearbyPanelColumn(title: '건대입구 방면'),
          NearbyPanelColumn(title: '한양대 방면'),
        ]),
      );

      expect(find.bySemanticsLabel('건대입구 방면 정보 없음'), findsOneWidget);
      expect(find.bySemanticsLabel('한양대 방면 정보 없음'), findsOneWidget);
      // 시각 대시('-')는 ExcludeSemantics라 단독 Semantics 라벨로 노출되지 않는다.
      expect(find.bySemanticsLabel('-'), findsNothing);
      handle.dispose();
    });
  });
}
