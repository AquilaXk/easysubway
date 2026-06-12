import 'dart:async';

import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('홈 화면은 핵심 행동만 간결하게 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        EasySubwayApp(repository: FakeStationSearchRepository()),
      );

      expect(find.text('역 찾기'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '역 검색'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '이동 조건'), findsOneWidget);
      expect(find.text('이동 프로필'), findsOneWidget);
      expect(find.text('시설 정보'), findsOneWidget);
      expect(find.text('신고'), findsOneWidget);
      expect(find.textContaining('빠른 길보다'), findsNothing);
      expect(find.textContaining('고령자'), findsNothing);
      expect(find.textContaining('휠체어'), findsNothing);
      expect(find.bySemanticsLabel('이동 프로필, 이동 조건 저장'), findsOneWidget);
      expect(find.bySemanticsLabel('시설 정보, 엘리베이터와 경사로'), findsOneWidget);
      expect(find.bySemanticsLabel('신고, 불편 신고'), findsOneWidget);

      final stationButtonSize = tester.getSize(
        find.byKey(const Key('stationSearchButton')),
      );
      final profileButtonSize = tester.getSize(
        find.byKey(const Key('mobilityProfileButton')),
      );

      expect(stationButtonSize.height, greaterThanOrEqualTo(60));
      expect(profileButtonSize.height, greaterThanOrEqualTo(60));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색은 접근성 표시가 포함된 백엔드 결과를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeStationSearchRepository(
      nextResults: [
        const StationSearchResult(
          id: 'station-sangnoksu',
          nameKo: '상록수',
          nameEn: 'Sangnoksu',
          region: '수도권',
          dataQualityLevel: 'LEVEL_1',
          lastVerifiedAt: '2026-06-12',
          lines: [
            StationSearchLine(
              id: 'seoul-4',
              name: '수도권 4호선',
              color: '#00A5DE',
              stationCode: '448',
            ),
            StationSearchLine(
              id: 'korail-gyeongui-jungang',
              name: '경의중앙선',
              color: '#75C5A1',
              stationCode: 'K232',
            ),
          ],
        ),
      ],
    );

    try {
      await tester.pumpWidget(EasySubwayApp(repository: repository));

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();

      final searchInput = tester.widget<TextField>(
        find.byKey(const Key('stationSearchInput')),
      );
      expect(searchInput.decoration?.hintText, '역 이름을 입력해 주세요');
      expect(searchInput.decoration?.hintText, isNot('예: 상록수'));
      expect(find.text('역 이름을 입력해 주세요.'), findsNothing);
      expect(
        searchInput.decoration?.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );

      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();

      expect(repository.requestedQueries, ['상록수']);
      expect(find.byKey(const Key('stationLineBadge-seoul-4')), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(
        find.byKey(const Key('stationLineBadge-korail-gyeongui-jungang')),
        findsOneWidget,
      );
      expect(find.text('경의중앙'), findsOneWidget);
      expect(find.text('수도권 4호선, 경의중앙선'), findsOneWidget);
      expect(find.text('기본 정보만 확인됨'), findsOneWidget);
      expect(find.bySemanticsLabel('검색 결과 1개'), findsOneWidget);
      expect(
        find.bySemanticsLabel('상록수, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 확인됨'),
        findsOneWidget,
      );
      final resultSemantics = tester.getSemantics(
        find.bySemanticsLabel('상록수, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 확인됨'),
      );
      expect(
        resultSemantics.getSemanticsData().flagsCollection.isButton,
        isFalse,
      );

      final lineBadgeSize = tester.getSize(
        find.byKey(const Key('stationLineBadge-seoul-4')),
      );
      expect(lineBadgeSize.width, 40);
      expect(lineBadgeSize.height, 40);

      final lineNumber = tester.widget<Text>(find.text('4'));
      expect(lineNumber.style?.fontSize, 24);
      expect(lineNumber.style?.color, const Color(0xFF102A2C));

      final namedLine = tester.widget<Text>(find.text('경의중앙'));
      expect(namedLine.style?.fontSize, 15);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('검색 요청 중에는 검색 버튼을 비활성화한다', (tester) async {
    final repository = ControlledStationSearchRepository();

    await tester.pumpWidget(EasySubwayApp(repository: repository));

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pump();

    expect(repository.requestedQueries, ['상록수']);
    final loadingButton = tester.widget<FilledButton>(
      find.byKey(const Key('stationSearchSubmitButton')),
    );
    expect(loadingButton.onPressed, isNull);

    repository.complete(const []);
    await tester.pumpAndSettle();

    final completedButton = tester.widget<FilledButton>(
      find.byKey(const Key('stationSearchSubmitButton')),
    );
    expect(completedButton.onPressed, isNotNull);
  });
}

class FakeStationSearchRepository implements StationSearchRepository {
  FakeStationSearchRepository({this.nextResults = const []});

  final List<StationSearchResult> nextResults;
  final requestedQueries = <String>[];

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    requestedQueries.add(query);
    return nextResults;
  }
}

class ControlledStationSearchRepository implements StationSearchRepository {
  final requestedQueries = <String>[];
  final _completer = Completer<List<StationSearchResult>>();

  @override
  Future<List<StationSearchResult>> searchStations(String query) {
    requestedQueries.add(query);
    return _completer.future;
  }

  void complete(List<StationSearchResult> results) {
    _completer.complete(results);
  }
}
