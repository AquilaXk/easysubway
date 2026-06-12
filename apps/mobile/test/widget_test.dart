import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders concise home screen actions', (tester) async {
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

  testWidgets('searches stations and shows accessible backend results', (
    tester,
  ) async {
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
          ],
        ),
      ],
    );

    try {
      await tester.pumpWidget(EasySubwayApp(repository: repository));

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();

      expect(repository.requestedQueries, ['상록수']);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('데이터 수준 1'), findsOneWidget);
      expect(
        find.bySemanticsLabel('상록수, 수도권 4호선, 수도권, 데이터 수준 1'),
        findsOneWidget,
      );
    } finally {
      semanticsHandle.dispose();
    }
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
