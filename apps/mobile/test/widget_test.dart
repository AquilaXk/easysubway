import 'dart:async';

import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('홈 화면은 핵심 행동만 간결하게 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          routeRepository: FakeRouteSearchRepository(),
        ),
      );

      expect(find.text('역 찾기'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '역 검색'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '경로 검색'), findsOneWidget);
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
      final routeButtonSize = tester.getSize(
        find.byKey(const Key('routeSearchButton')),
      );
      final profileButtonSize = tester.getSize(
        find.byKey(const Key('mobilityProfileButton')),
      );

      expect(stationButtonSize.height, greaterThanOrEqualTo(60));
      expect(routeButtonSize.height, greaterThanOrEqualTo(60));
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
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          routeRepository: FakeRouteSearchRepository(),
        ),
      );

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

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        routeRepository: FakeRouteSearchRepository(),
      ),
    );

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

  testWidgets('이동 조건 화면은 큰 선택 카드로 사용자 상황을 고를 수 있다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          routeRepository: FakeRouteSearchRepository(),
        ),
      );

      await tester.tap(find.byKey(const Key('mobilityProfileButton')));
      await tester.pumpAndSettle();

      expect(find.text('이동 조건'), findsOneWidget);
      expect(find.text('고령자'), findsOneWidget);
      expect(find.text('유모차'), findsOneWidget);
      expect(find.text('휠체어'), findsOneWidget);
      expect(find.text('임산부'), findsOneWidget);
      expect(find.text('일시 부상'), findsOneWidget);
      expect(find.text('큰 짐'), findsOneWidget);
      expect(find.text('계단을 피하고 쉬운 환승을 우선해요'), findsOneWidget);
      expect(find.text('엘리베이터와 넓은 길을 우선해요'), findsOneWidget);
      expect(find.text('계단 없는 길만 안내해요'), findsOneWidget);

      expect(
        tester.getSemantics(find.bySemanticsLabel('휠체어 선택 가능, 계단 없는 길만 안내해요')),
        isSemantics(
          label: '휠체어 선택 가능, 계단 없는 길만 안내해요',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      final wheelchairCard = find.byKey(
        const Key('mobilityProfileCard-wheelchair'),
      );
      expect(wheelchairCard, findsOneWidget);
      expect(tester.getSize(wheelchairCard).height, greaterThanOrEqualTo(76));

      await tester.tap(wheelchairCard);
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('휠체어 선택됨, 계단 없는 길만 안내해요'), findsOneWidget);
      expect(find.text('휠체어 조건을 선택했습니다'), findsOneWidget);
      expect(find.bySemanticsLabel('선택 완료'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('경로 검색 화면은 쉬운 경로 결과와 경고를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeRepository = FakeRouteSearchRepository();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: stationRepository,
          routeRepository: routeRepository,
        ),
      );

      await tester.tap(find.byKey(const Key('routeSearchButton')));
      await tester.pumpAndSettle();

      expect(find.text('경로 검색'), findsOneWidget);
      expect(find.text('출발역'), findsOneWidget);
      expect(find.text('도착역'), findsOneWidget);
      expect(find.text('출발역 ID'), findsNothing);
      expect(find.text('도착역 ID'), findsNothing);
      expect(find.text('이동 조건'), findsOneWidget);

      final originInput = tester.widget<TextField>(
        find.byKey(const Key('routeOriginStationInput')),
      );
      expect(originInput.decoration?.hintText, '역 이름을 입력해 주세요');

      await tester.enterText(
        find.byKey(const Key('routeOriginStationInput')),
        '상록수',
      );
      await tester.tap(find.byKey(const Key('routeOriginStationSearchButton')));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('출발역 선택, 상록수, 수도권 2호선, 수도권, 기본 정보만 확인됨'),
        ),
        isSemantics(
          label: '출발역 선택, 상록수, 수도권 2호선, 수도권, 기본 정보만 확인됨',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(
        find.byKey(const Key('routeOriginStationOption-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('routeDestinationStationInput')),
        '사당',
      );
      await tester.tap(
        find.byKey(const Key('routeDestinationStationSearchButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('routeDestinationStationOption-station-sadang')),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -360));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
      await tester.pumpAndSettle();

      expect(stationRepository.requestedQueries, ['상록수', '사당']);
      expect(routeRepository.requests, hasLength(1));
      expect(
        routeRepository.requests.single.originStationId,
        'station-sangnoksu',
      );
      expect(
        routeRepository.requests.single.destinationStationId,
        'station-sadang',
      );
      expect(routeRepository.requests.single.mobilityType, 'SENIOR');
      expect(find.text('상록수에서 사당까지'), findsOneWidget);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('이동 점수 92점'), findsOneWidget);
      expect(find.text('상록수역에서 4호선 승강장으로 이동'), findsOneWidget);
      expect(find.text('일부 시설 정보는 확인이 필요합니다.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('출발역 선택됨, 상록수, 수도권 2호선, 수도권, 기본 정보만 확인됨'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('도착역 선택됨, 사당, 수도권 2호선, 수도권, 기본 정보만 확인됨'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '경로 검색 결과, 경로를 찾았습니다, 상록수에서 사당까지, 수도권 4호선, 이동 점수 92점, '
          '주의 일부 시설 정보는 확인이 필요합니다., '
          '이동 안내 1번 상록수역에서 4호선 승강장으로 이동, 엘리베이터를 이용해 승강장으로 이동합니다.',
        ),
        findsOneWidget,
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('경로 검색은 입력만 하고 선택하지 않은 역을 쉬운 문구로 안내한다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        routeRepository: routeRepository,
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchButton')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('routeOriginStationInput')),
      '상록수',
    );
    await tester.enterText(
      find.byKey(const Key('routeDestinationStationInput')),
      '사당',
    );
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests, isEmpty);
    expect(find.text('출발역과 도착역을 검색 결과에서 선택해 주세요.'), findsOneWidget);
  });

  testWidgets('경로 검색은 역 선택이 바뀌면 이전 결과를 숨긴다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeRepository = FakeRouteSearchRepository();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        routeRepository: routeRepository,
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchButton')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('routeOriginStationInput')),
      '상록수',
    );
    await tester.tap(find.byKey(const Key('routeOriginStationSearchButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('routeOriginStationOption-station-sangnoksu')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('routeDestinationStationInput')),
      '사당',
    );
    await tester.tap(
      find.byKey(const Key('routeDestinationStationSearchButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('routeDestinationStationOption-station-sadang')),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.text('상록수에서 사당까지'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('routeOriginStationInput')),
      '상록',
    );
    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
    final submitButton = tester.widget<FilledButton>(
      find.byKey(const Key('routeSearchSubmitButton')),
    );
    submitButton.onPressed!();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    expect(find.text('출발역과 도착역을 검색 결과에서 선택해 주세요.'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('상록수에서 사당까지'), findsNothing);
  });

  testWidgets('경로 검색 중에는 버튼을 비활성화하고 안내 불가 이유를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '없는역': [_stationResult(id: 'station-nowhere', name: '없는역')],
      },
    );
    final routeRepository = ControlledRouteSearchRepository();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: stationRepository,
          routeRepository: routeRepository,
        ),
      );

      await tester.tap(find.byKey(const Key('routeSearchButton')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('routeOriginStationInput')),
        '상록수',
      );
      await tester.tap(find.byKey(const Key('routeOriginStationSearchButton')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('routeOriginStationOption-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('routeDestinationStationInput')),
        '없는역',
      );
      await tester.tap(
        find.byKey(const Key('routeDestinationStationSearchButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('routeDestinationStationOption-station-nowhere')),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -360));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
      await tester.pump();

      expect(routeRepository.requests, hasLength(1));
      expect(find.bySemanticsLabel('경로 검색 중'), findsOneWidget);
      final loadingButton = tester.widget<FilledButton>(
        find.byKey(const Key('routeSearchSubmitButton')),
      );
      expect(loadingButton.onPressed, isNull);

      routeRepository.complete(_blockedRouteSearchResult());
      await tester.pumpAndSettle();

      expect(find.text('안내할 수 있는 경로가 없습니다'), findsOneWidget);
      expect(find.text('휠체어로 이동 가능한 엘리베이터가 없습니다.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '경로 검색 결과, 안내할 수 있는 경로가 없습니다, 상록수에서 없는역까지, 노선 확인 필요, 이동 점수 0점, '
          '안내 불가 이유 휠체어로 이동 가능한 엘리베이터가 없습니다.',
        ),
        findsOneWidget,
      );
      final completedButton = tester.widget<FilledButton>(
        find.byKey(const Key('routeSearchSubmitButton')),
      );
      expect(completedButton.onPressed, isNotNull);
    } finally {
      semanticsHandle.dispose();
    }
  });
}

class FakeStationSearchRepository implements StationSearchRepository {
  FakeStationSearchRepository({
    this.nextResults = const [],
    this.queryResults = const {},
  });

  final List<StationSearchResult> nextResults;
  final Map<String, List<StationSearchResult>> queryResults;
  final requestedQueries = <String>[];

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    requestedQueries.add(query);
    return queryResults[query] ?? nextResults;
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

class FakeRouteSearchRepository implements RouteSearchRepository {
  final requests = <RouteSearchRequest>[];

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    requests.add(request);
    return _sampleRouteSearchResult();
  }
}

class ControlledRouteSearchRepository implements RouteSearchRepository {
  final requests = <RouteSearchRequest>[];
  final _completer = Completer<RouteSearchResult>();

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) {
    requests.add(request);
    return _completer.future;
  }

  void complete(RouteSearchResult result) {
    _completer.complete(result);
  }
}

StationSearchResult _stationResult({required String id, required String name}) {
  return StationSearchResult(
    id: id,
    nameKo: name,
    nameEn: id,
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    lastVerifiedAt: '2026-06-13',
    lines: const [
      StationSearchLine(
        id: 'seoul-2',
        name: '수도권 2호선',
        color: '#00A84D',
        stationCode: '222',
      ),
    ],
  );
}

RouteSearchResult _sampleRouteSearchResult() {
  return const RouteSearchResult(
    routeSearchId: 'route-1',
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-sadang',
    destinationStationName: '사당',
    mobilityType: 'SENIOR',
    status: 'FOUND',
    lineId: 'seoul-4',
    lineName: '수도권 4호선',
    score: 92,
    steps: [
      RouteSearchStep(
        sequence: 1,
        title: '상록수역에서 4호선 승강장으로 이동',
        description: '엘리베이터를 이용해 승강장으로 이동합니다.',
        lineId: 'seoul-4',
        lineName: '수도권 4호선',
        fromStationId: 'station-sangnoksu',
        toStationId: 'station-sadang',
      ),
    ],
    warnings: [
      RouteSearchWarning(
        code: 'LOW_DATA_CONFIDENCE',
        message: '일부 시설 정보는 확인이 필요합니다.',
      ),
    ],
    blockedReasons: [],
    createdAt: '2026-06-13T04:20:00',
  );
}

RouteSearchResult _blockedRouteSearchResult() {
  return const RouteSearchResult(
    routeSearchId: 'route-blocked',
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-nowhere',
    destinationStationName: '없는역',
    mobilityType: 'WHEELCHAIR',
    status: 'BLOCKED',
    lineId: '',
    lineName: '',
    score: 0,
    steps: [],
    warnings: [],
    blockedReasons: ['휠체어로 이동 가능한 엘리베이터가 없습니다.'],
    createdAt: '2026-06-13T04:25:00',
  );
}
