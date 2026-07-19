import 'dart:async';

import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_models.dart';
import 'package:easysubway_mobile/features/train_search/domain/train_search_scope_policy.dart';
import 'package:easysubway_mobile/features/train_search/presentation/train_search_screen.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTrainSearchRepository implements TrainSearchRepository {
  _FakeTrainSearchRepository({
    this.stationsCompleter,
    this.searchCompleter,
    this.error,
    TrainSearchResult? result,
  }) : result = result ?? _result();

  final Completer<List<TrainStation>>? stationsCompleter;
  final Completer<TrainSearchResult>? searchCompleter;
  final TrainSearchException? error;
  final TrainSearchResult result;
  var searchCalls = 0;
  TrainSearchCriteria? lastCriteria;

  @override
  Future<List<TrainStation>> stations(
    String query, {
    TrainSearchTrainType? type,
  }) async {
    if (stationsCompleter case final Completer<List<TrainStation>> completer) {
      return completer.future;
    }
    if (query.contains('서울')) {
      return const [TrainStation(id: 'NAT010000', name: '서울')];
    }
    if (query.contains('대전')) {
      return const [TrainStation(id: 'NAT011668', name: '대전')];
    }
    return const [];
  }

  @override
  Future<TrainSearchResult> search(TrainSearchCriteria criteria) async {
    searchCalls++;
    lastCriteria = criteria;
    if (error case final TrainSearchException error) throw error;
    if (searchCompleter case final Completer<TrainSearchResult> completer) {
      return completer.future;
    }
    return result;
  }
}

TrainSearchResult _result() => TrainSearchResult(
  observedAt: DateTime.parse('2026-07-19T12:00:00Z'),
  outbound: [
    TrainJourney(
      trainNumber: '101',
      trainType: TrainSearchTrainType.ktx,
      departureStationId: 'NAT010000',
      departureStationName: '서울',
      departureAt: DateTime.parse('2026-07-20T09:00:00+09:00'),
      arrivalStationId: 'NAT011668',
      arrivalStationName: '대전',
      arrivalAt: DateTime.parse('2026-07-20T10:02:00+09:00'),
      durationMinutes: 62,
      adultFareWon: 23700,
    ),
  ],
  inbound: const [],
);

Future<void> _selectStations(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('trainSearchDepartureField')),
    '서울',
  );
  await tester.pump();
  await tester.tap(
    find.byKey(const Key('trainSearchStationSuggestion-departure-NAT010000')),
  );
  await tester.enterText(
    find.byKey(const Key('trainSearchArrivalField')),
    '대전',
  );
  await tester.pump();
  await tester.tap(
    find.byKey(const Key('trainSearchStationSuggestion-arrival-NAT011668')),
  );
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('trainSearchScrollView')),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(
    find.byKey(const Key('trainSearchSubmitButton')),
    240,
    scrollable: scrollable,
  );
  await tester.ensureVisible(find.byKey(const Key('trainSearchSubmitButton')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('trainSearchSubmitButton')));
}

void main() {
  testWidgets('역 선택 후 검색하면 KTX 시간·성인 1인 운임을 표시한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('trainSearchResults')),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('trainSearchScrollView')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(repository.searchCalls, 1);
    expect(find.text('KTX 101'), findsOneWidget);
    expect(find.text('23,700원'), findsOneWidget);
    expect(find.text('서울 → 대전'), findsOneWidget);
    expect(find.text('09:00 → 10:02 · 62분'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                '서울 출발, 대전 도착, KTX 101, '
                    '09:00 출발, 10:02 도착, 62분 소요, 성인 1인 23,700원',
      ),
      findsOneWidget,
    );
  });

  testWidgets('한국시간 03시 이후에는 새 service day를 기본 검색일로 사용한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: _FakeTrainSearchRepository(),
          now: () => DateTime.utc(2026, 7, 19, 18, 30),
        ),
      ),
    );

    expect(find.text('가는 날  2026.07.20'), findsOneWidget);
  });

  testWidgets('출발·도착을 바꾸고 왕복 날짜를 검색 조건에 반영한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);

    await tester.tap(find.byKey(const Key('trainSearchSwapButton')));
    await tester.tap(find.text('왕복'));
    await tester.pump();
    expect(
      find.byKey(const Key('trainSearchReturnDateButton')),
      findsOneWidget,
    );

    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(repository.lastCriteria!.departure.name, '대전');
    expect(repository.lastCriteria!.arrival.name, '서울');
    expect(repository.lastCriteria!.returnDate, DateTime(2026, 7, 19));
  });

  testWidgets('왕복 결과는 오는 열차가 없어도 빈 오는 편을 표시한다', (tester) async {
    final repository = _FakeTrainSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);
    await tester.tap(find.text('왕복'));
    await tester.pump();
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('오는 열차'), findsOneWidget);
    expect(find.text('운행 열차가 없습니다.'), findsOneWidget);
  });

  testWidgets('자정을 넘는 열차는 다음 날 도착을 화면과 semantics에 표시한다', (tester) async {
    final overnight = TrainSearchResult(
      observedAt: DateTime.parse('2026-07-19T12:00:00Z'),
      outbound: [
        TrainJourney(
          trainNumber: '999',
          trainType: TrainSearchTrainType.ktx,
          departureStationId: 'NAT010000',
          departureStationName: '서울',
          departureAt: DateTime.parse('2026-07-20T23:30:00+09:00'),
          arrivalStationId: 'NAT011668',
          arrivalStationName: '대전',
          arrivalAt: DateTime.parse('2026-07-21T00:30:00+09:00'),
          durationMinutes: 60,
          adultFareWon: 23700,
        ),
      ],
      inbound: const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: _FakeTrainSearchRepository(result: overnight),
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('23:30 → 다음 날 00:30 · 60분'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label?.contains(
                  '23:30 출발, 다음 날 00:30 도착, 60분 소요',
                ) ==
                true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('역 교환은 진행 중인 자동완성 응답을 무효화한다', (tester) async {
    final completer = Completer<List<TrainStation>>();
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: _FakeTrainSearchRepository(stationsCompleter: completer),
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('trainSearchDepartureField')),
      '서울',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('trainSearchSwapButton')));
    completer.complete(const [TrainStation(id: 'NAT010000', name: '서울')]);
    await tester.pump();

    expect(
      find.byKey(const Key('trainSearchStationSuggestion-departure-NAT010000')),
      findsNothing,
    );
  });

  testWidgets('검색 중 중복 제출을 막고 loading 상태를 알린다', (tester) async {
    final completer = Completer<TrainSearchResult>();
    final repository = _FakeTrainSearchRepository(searchCompleter: completer);
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);

    await _tapSubmit(tester);
    await tester.pump();
    await tester.tap(find.byKey(const Key('trainSearchSubmitButton')));
    await tester.pump();

    expect(repository.searchCalls, 1);
    expect(find.byKey(const Key('trainSearchLoading')), findsOneWidget);
    completer.complete(_result());
    await tester.pumpAndSettle();
  });

  testWidgets('unavailable은 이전 결과 없이 명시적 오류와 재시도를 표시한다', (tester) async {
    final repository = _FakeTrainSearchRepository(
      error: const TrainSearchException(
        TrainSearchFailureKind.unavailable,
        '기차 검색을 일시적으로 사용할 수 없습니다.',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trainSearchError')), findsOneWidget);
    expect(find.text('기차 검색을 일시적으로 사용할 수 없습니다.'), findsOneWidget);
    expect(find.text('KTX 101'), findsNothing);
  });

  testWidgets('검색 결과가 없으면 empty 상태를 명시한다', (tester) async {
    final repository = _FakeTrainSearchRepository(
      result: TrainSearchResult(
        observedAt: DateTime.parse('2026-07-19T12:00:00Z'),
        outbound: const [],
        inbound: const [],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TrainSearchScreen(
          repository: repository,
          now: () => DateTime.utc(2026, 7, 19, 3),
        ),
      ),
    );
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('trainSearchEmpty')), findsOneWidget);
  });

  testWidgets('200% 글자 크기에서도 검색 폼과 결과가 overflow 없이 스크롤된다', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: TrainSearchScreen(
            repository: _FakeTrainSearchRepository(),
            now: () => DateTime.utc(2026, 7, 19, 3),
          ),
        ),
      ),
    );
    await _selectStations(tester);
    await _tapSubmit(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsWidgets);
  });

  testWidgets('노선도 메뉴의 가까운 역 바로 아래 기차 검색이 callback을 연다', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: const _EmptyNetworkMapRepository(),
          routeDraftController: RouteDraftController(),
          onOpenStationSearch: (_) {},
          onOpenNearbyStations: (_) {},
          onOpenTrainSearch: () => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();

    final nearby = tester.getTopLeft(
      find.byKey(const Key('networkMapMenuNearbyButton')),
    );
    final train = tester.getTopLeft(
      find.byKey(const Key('networkMapMenuTrainSearchButton')),
    );
    expect(train.dy, greaterThan(nearby.dy));

    await tester.tap(find.byKey(const Key('networkMapMenuTrainSearchButton')));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });
}

class _EmptyNetworkMapRepository implements NetworkMapRepository {
  const _EmptyNetworkMapRepository();

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    return const NetworkMapData(
      regions: [NetworkMapRegion(name: '수도권')],
      selectedRegion: '수도권',
      lines: [],
      stations: [],
      edges: [],
      positionSources: [],
    );
  }
}
