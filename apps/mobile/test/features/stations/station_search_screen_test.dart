import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('#2083 역 검색 화면은 홈 편집 모드와 같은 46px 시각 박스·중앙 정렬 입력 필드를 렌더한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          locationProvider: const _FixedCurrentLocationProvider(),
          pickSlot: RouteDraftSlot.origin,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 홈 편집 모드와 동일한 공용 시각 박스(46px)를 렌더한다.
    expect(
      tester.getSize(find.byKey(const Key('heroStationSearchInputBox'))).height,
      46.0,
    );

    // pickSlot별 힌트가 placeholder(이자 TalkBack 라벨)로 렌더된다. #2083 오너
    // 확정: 슬롯 검색 진입 placeholder는 슬롯명 단독.
    expect(find.text('출발역'), findsOneWidget);

    // 입력 필드 탭 타깃(병합된 터치타겟 SizedBox)은 최소 탭 타깃(≥48)을 유지한다.
    final originInputTapTarget = find
        .ancestor(
          of: find.byKey(const Key('stationSearchInput')),
          matching: find.byType(SizedBox),
        )
        .first;
    expect(
      tester.getSize(originInputTapTarget).height,
      greaterThanOrEqualTo(48.0),
    );

    // 편집 텍스트가 46px 시각 박스 안에 렌더돼야 한다(#2082 수정을 공용 위젯이
    // 소비함을 검증). #2082 실기기 재작업: 중앙 정렬은 고유 높이 필드 + Center
    // 위젯으로 얻으며 실기기(Noto Sans KR)에서 오프셋 0으로 정합함을 픽셀 판독으로
    // 확인했다(docs/2082-qa, 정본). FlutterTest 테스트 폰트·AppBar toolbar 배치
    // 오차로 중심이 박스 중심에서 십수 px 벗어날 수 있으므로, 입력 글자가 박스
    // 세로 범위 안에 온전히 들어오는지를 폰트 메트릭 독립적으로 계약으로 잡는다.
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    final searchScreenBoxRect = tester.getRect(
      find.byKey(const Key('heroStationSearchInputBox')),
    );
    final searchScreenTextCenterDy = tester.getCenter(find.text('상록수')).dy;
    expect(searchScreenTextCenterDy, greaterThan(searchScreenBoxRect.top));
    expect(searchScreenTextCenterDy, lessThan(searchScreenBoxRect.bottom));

    final searchField = tester.widget<TextField>(
      find.byKey(const Key('stationSearchInput')),
    );
    expect(searchField.maxLines, 1);
    expect(searchField.expands, isFalse);
  });

  testWidgets('#2082 역 검색 화면은 필드 우측에 지역 표시를 두고 필드가 그 앞에서 끝난다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          locationProvider: const _FixedCurrentLocationProvider(),
          pickSlot: RouteDraftSlot.origin,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // #3: 홈과 동일하게 검색 화면 우측에 현재 지역명을 표시한다.
    final indicator = find.byKey(const Key('stationSearchRegionIndicator'));
    expect(indicator, findsOneWidget);
    expect(
      find.descendant(of: indicator, matching: find.text('수도권')),
      findsOneWidget,
    );
    // 표시 전용이라 지역 변경 화살표(아래 방향)를 홈과 같은 스타일로 둔다.
    expect(
      find.descendant(
        of: indicator,
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsOneWidget,
    );

    // #2: 검색 필드가 우측 끝까지 꽉 차지 않고 지역 표시 앞에서 끝난다
    // (홈 idle [≡ | 필드 | 지역표시] 구성과 정합).
    final fieldRight = tester
        .getRect(find.byKey(const Key('heroStationSearchInputBox')))
        .right;
    final indicatorLeft = tester.getRect(indicator).left;
    expect(fieldRight, lessThanOrEqualTo(indicatorLeft));

    // ← 뒤로가기 버튼이 홈 ≡ 슬롯과 같은 위치(필드 왼쪽)에 남는다.
    expect(find.byKey(const Key('stationSearchBackButton')), findsOneWidget);
  });

  testWidgets('#2090 수도권 외 지역(부산) 선택 상태에서 열어도 검색 화면 지역 표시가 실제 선택 지역을 따른다', (
    tester,
  ) async {
    // 회귀 방지: 직전 구현은 regionLabel 기본값이 '수도권' 고정이고 호출부가
    // 실제 선택 지역을 주입하지 않아, 부산 선택 상태에서 검색을 열어도
    // '수도권'이 잘못 표시됐다. 이제 호출부가 NetworkMapScreen의 현재 선택
    // 지역 표시명을 regionLabel로 넘기므로 실제 지역 반영 결과를 검증한다.
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          locationProvider: const _FixedCurrentLocationProvider(),
          pickSlot: RouteDraftSlot.origin,
          regionLabel: '부산',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final indicator = find.byKey(const Key('stationSearchRegionIndicator'));
    expect(indicator, findsOneWidget);
    expect(
      find.descendant(of: indicator, matching: find.text('부산')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: indicator, matching: find.text('수도권')),
      findsNothing,
    );
  });

  testWidgets('#2090 배율 3.0에서 역 검색 화면 필드가 툴바 안에서 잘리지 않는다', (tester) async {
    // 툴바 높이 보정 상수가 필드 메트릭과 정합돼 큰 배율에서도 필드가
    // AppBar 세로 범위 안에 온전히 들어가야 한다.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
        child: MaterialApp(
          home: StationSearchScreen(
            repository: _EmptyStationSearchRepository(),
            reportRepository: const UnavailableFacilityReportRepository(),
            locationProvider: const _FixedCurrentLocationProvider(),
            pickSlot: RouteDraftSlot.origin,
            regionLabel: '수도권',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final inputFinder = find.byKey(const Key('stationSearchInput'));
    final appBarFinder = find.ancestor(
      of: inputFinder,
      matching: find.byType(AppBar),
    );
    final appBar = tester.widget<AppBar>(appBarFinder);
    expect(appBar.toolbarHeight, greaterThan(kToolbarHeight));

    final appBarRect = tester.getRect(appBarFinder);
    final boxRect = tester.getRect(
      find.byKey(const Key('heroStationSearchInputBox')),
    );
    // 시각 박스가 툴바 세로 범위 안에 온전히 들어간다(위/아래로 잘리지 않음).
    expect(boxRect.bottom, lessThanOrEqualTo(appBarRect.bottom + 0.5));
    expect(boxRect.top, greaterThanOrEqualTo(appBarRect.top - 0.5));
  });

  testWidgets('#2090 역 검색 필드는 입력 후에도 슬롯 맥락 semantics 라벨을 유지한다', (tester) async {
    // 이전 floating label이 유지하던 슬롯 맥락("출발역") 라벨이 입력 후에도
    // 스크린리더 semantics 트리에 남아야 한다.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          locationProvider: const _FixedCurrentLocationProvider(),
          pickSlot: RouteDraftSlot.origin,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 입력 전에는 hint 노드와 라벨 래퍼 때문에 하나 이상 존재한다.
    expect(find.bySemanticsLabel('출발역'), findsWidgets);

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    // hint가 사라진 뒤에도 라벨 래퍼가 슬롯 맥락을 유지한다.
    expect(find.bySemanticsLabel('출발역'), findsOneWidget);

    handle.dispose();
  });

  testWidgets('#2090 도착역 슬롯은 도착역 맥락 semantics 라벨을 노출한다', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          locationProvider: const _FixedCurrentLocationProvider(),
          pickSlot: RouteDraftSlot.destination,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '사당');
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('도착역'), findsOneWidget);
    // 출발역 맥락이 새어 나오지 않는다.
    expect(find.bySemanticsLabel('출발역'), findsNothing);
    handle.dispose();
  });

  testWidgets('역 검색 화면은 최근 검색어를 탭해 빠르게 다시 검색한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = _EmptyStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult()],
      },
    );
    final searchHistoryRepository = _MemorySearchHistoryRepository([
      '상록수',
      '사당',
    ]);

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: StationSearchScreen(
            repository: repository,
            reportRepository: const UnavailableFacilityReportRepository(),
            locationProvider: const _FixedCurrentLocationProvider(),
            searchHistoryRepository: searchHistoryRepository,
            regionLabel: '수도권',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
      expect(
        find.byKey(const Key('stationRecentSearchSection')),
        findsOneWidget,
      );
      expect(find.text('최근 검색'), findsOneWidget);
      expect(find.textContaining('최근 사용 순서'), findsNothing);
      expect(find.text('최근 사용 1번째'), findsOneWidget);
      expect(
        find.byKey(const Key('stationRecentSearchQuery-상록수')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('최근 검색어 상록수 검색, 최근 사용 1번째'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('최근 검색어 상록수 검색, 최근 사용 1번째'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );

      await tester.tap(find.byKey(const Key('stationRecentSearchQuery-상록수')));
      await tester.pumpAndSettle();

      final searchInput = tester.widget<TextField>(
        find.byKey(const Key('stationSearchInput')),
      );
      expect(searchInput.controller?.text, '상록수');
      expect(repository.requestedQueries, ['상록수']);
      expect(searchHistoryRepository.recordedQueries, ['상록수']);
      expect(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationRoleOrigin-station-sangnoksu')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('stationRoleDestination-station-sangnoksu')),
        findsNothing,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색 화면 안에서 최근 검색을 개별·전체 삭제한다', (tester) async {
    final searchHistoryRepository = _MemorySearchHistoryRepository([
      '상록수',
      '사당',
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          locationProvider: const _FixedCurrentLocationProvider(),
          searchHistoryRepository: searchHistoryRepository,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stationRecentSearchRemove-상록수')));
    await tester.pumpAndSettle();

    expect(searchHistoryRepository.removedQueries, ['상록수']);
    expect(find.byKey(const Key('stationRecentSearchQuery-상록수')), findsNothing);
    expect(find.byKey(const Key('stationRecentSearchSection')), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('stationRecentSearchClearAllButton')),
    );
    await tester.pumpAndSettle();

    expect(searchHistoryRepository.clearCount, 1);
    expect(find.byKey(const Key('stationRecentSearchSection')), findsNothing);
    expect(find.text('최근 검색한 역이 없습니다.'), findsNothing);
    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
  });

  testWidgets('역 검색 결과는 환승 역을 노선마다 한 행으로 펼쳐 보여준다', (tester) async {
    final repository = _EmptyStationSearchRepository(
      queryResults: {
        '환승': [
          const StationSearchResult(
            id: 'station-transfer',
            nameKo: '환승역',
            nameEn: 'Transfer',
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
              StationSearchLine(
                id: 'suin-bundang',
                name: '수인분당선',
                color: '#F5A200',
                stationCode: 'K249',
              ),
              StationSearchLine(
                id: 'shinbundang',
                name: '신분당선',
                color: '#D4003B',
                stationCode: 'D14',
              ),
            ],
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: repository,
          reportRepository: const UnavailableFacilityReportRepository(),
          locationProvider: const _FixedCurrentLocationProvider(),
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '환승');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stationLineBadge-seoul-4')), findsOneWidget);
    expect(
      find.byKey(const Key('stationLineBadge-korail-gyeongui-jungang')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationLineBadge-suin-bundang')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationLineBadge-shinbundang')),
      findsOneWidget,
    );
    expect(find.text('+3'), findsNothing);
    expect(find.byKey(const Key('stationLineBadgeOverflow')), findsNothing);
    expect(
      find.byKey(const Key('stationSearchResult-station-transfer')),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  });
}

class _EmptyStationSearchRepository implements StationSearchRepository {
  _EmptyStationSearchRepository({this.queryResults = const {}});

  final Map<String, List<StationSearchResult>> queryResults;
  final requestedQueries = <String>[];

  @override
  Future<StationDetail> getStationDetail(String stationId) =>
      throw UnimplementedError();

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async => [];

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async => [];

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async => [];

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    requestedQueries.add(query);
    return queryResults[query] ?? [];
  }
}

class _MemorySearchHistoryRepository implements SearchHistoryRepository {
  _MemorySearchHistoryRepository(List<String> queries) : queries = [...queries];

  final List<String> queries;
  final recordedQueries = <String>[];
  final removedQueries = <String>[];
  int clearCount = 0;

  @override
  Future<void> clearSearches() async {
    clearCount++;
    queries.clear();
  }

  @override
  Future<List<String>> listRecentQueries() async => [...queries];

  @override
  Future<void> recordSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return;
    }
    recordedQueries.add(trimmed);
    queries
      ..remove(trimmed)
      ..insert(0, trimmed);
  }

  @override
  Future<void> removeSearch(String query) async {
    final trimmed = query.trim();
    removedQueries.add(trimmed);
    queries.remove(trimmed);
  }
}

StationSearchResult _stationResult() {
  return const StationSearchResult(
    id: 'station-sangnoksu',
    nameKo: '상록수',
    nameEn: 'Sangnoksu',
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    lastVerifiedAt: '2026-06-13',
    lines: [
      StationSearchLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        stationCode: '448',
      ),
    ],
  );
}

class _FixedCurrentLocationProvider implements CurrentLocationProvider {
  const _FixedCurrentLocationProvider();

  @override
  Future<CurrentLocation> currentLocation() async => CurrentLocation(
    latitude: 37.3028,
    longitude: 126.8665,
    accuracyMeters: 25,
    measuredAt: DateTime.now(),
    provider: 'test',
    permissionPrecision: LocationPermissionPrecision.precise,
  );

  @override
  Future<bool> needsLocationPermissionRequest() async => false;

  @override
  Future<bool> openLocationSettings() async => true;
}
