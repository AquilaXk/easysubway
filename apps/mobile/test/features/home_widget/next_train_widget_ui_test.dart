import 'dart:async';

import 'package:easysubway_mobile/features/home_widget/home_widget_link_handler.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_configuration_screen.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('시간표가 있는 즐겨찾기를 선택하면 해당 widget을 구성한다', (tester) async {
    WidgetStationSelection? configured;
    await tester.pumpWidget(
      MaterialApp(
        home: NextTrainWidgetConfigurationScreen(
          loadSelections: () async => const [_selection],
          configure: (selection) async => configured = selection,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('사당'));
    await tester.pumpAndSettle();

    expect(configured, same(_selection));
  });

  testWidgets('지원 시간표가 없으면 선택지를 만들지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NextTrainWidgetConfigurationScreen(
          loadSelections: () async => const [],
          configure: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('시간표가 있는 즐겨찾기 역이 없어요.'), findsOneWidget);
  });

  testWidgets('widget deep link는 같은 station 상세를 연다', (tester) async {
    final clicks = StreamController<Uri?>();
    addTearDown(clicks.close);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: HomeWidgetLinkHandler(
          clicks: clicks.stream,
          navigatorKey: navigatorKey,
          stationDetailBuilder: (stationId) => Scaffold(body: Text(stationId)),
          child: const Scaffold(body: Text('홈')),
        ),
      ),
    );

    clicks.add(
      Uri.parse(
        'easysubway://station/detail?stationId=station-sadang&lineId=seoul-4',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('station-sadang'), findsOneWidget);
  });
}

const _selection = WidgetStationSelection(
  stationId: 'station-sadang',
  lineId: 'seoul-4',
  stationName: '사당',
  lineName: '수도권 4호선',
);
