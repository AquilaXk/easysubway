import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/domain/station_repositories.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_search_screen.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/easy_subway_app_fixture.dart';

const _completedOnboardingState = OnboardingState.completed(
  result: OnboardingResult(
    preset: MobilityPreset.standard,
    preferences: OnboardingViewPreferences.defaults(),
  ),
);

void main() {
  testWidgets('#2083 역 검색 화면은 홈 편집 모드와 같은 46px 시각 박스·중앙 정렬 입력 필드를 렌더한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
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
    // 검색 결과 지역 필터용 선택기 — 홈과 같은 화살표 스타일 + 탭 가능.
    expect(
      find.descendant(
        of: indicator,
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationSearchRegionDropdown')),
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

  testWidgets('역 검색 지역 선택은 결과 필터와 함께 홈 노선도 동기화 콜백을 호출한다', (tester) async {
    final repository = _EmptyStationSearchRepository(
      queryResults: {
        '중앙': [
          _stationResult(),
          const StationSearchResult(
            id: 'station-busan-jungang',
            nameKo: '중앙',
            nameEn: 'Jungang',
            region: '부산권',
            dataQualityLevel: 'LEVEL_1',
            lastVerifiedAt: '2026-06-13',
            lines: [
              StationSearchLine(
                id: 'busan-1',
                name: '부산 1호선',
                color: '#F73A3A',
                stationCode: '119',
              ),
            ],
          ),
        ],
      },
    );
    final changedRegions = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: repository,
          reportRepository: const UnavailableFacilityReportRepository(),
          regionLabel: '수도권',
          onRegionChanged: changedRegions.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '중앙');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // 수도권 필터: 수도권 역만 남는다.
    expect(find.text('상록수역'), findsOneWidget);
    expect(
      find.byKey(
        const Key('stationSearchResult-station-busan-jungang-busan-1'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('stationSearchRegionDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('networkMapRegionMenuRow_부산')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('stationSearchRegionIndicator')),
        matching: find.text('부산'),
      ),
      findsOneWidget,
    );
    // 부산 필터: 부산권 역만 남고, 홈 노선도 동기화용 콜백도 같은 지역 키를 받는다.
    expect(find.text('상록수역'), findsNothing);
    expect(
      find.byKey(
        const Key('stationSearchResult-station-busan-jungang-busan-1'),
      ),
      findsOneWidget,
    );
    expect(changedRegions, ['부산']);
  });

  testWidgets('출발·도착·경유 중 하나라도 있으면 지역 변경과 ▾을 막는다', (tester) async {
    final draftController = RouteDraftController()
      ..setOrigin(const RouteDraftStation(id: 'station-a', nameKo: '상록수'));
    final changedRegions = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          routeDraftController: draftController,
          pickSlot: RouteDraftSlot.destination,
          regionLabel: '수도권',
          onRegionChanged: changedRegions.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    expect(find.bySemanticsLabel('지역: 수도권'), findsOneWidget);
    expect(find.bySemanticsLabel('지역: 수도권, 지역 변경'), findsNothing);

    await tester.tap(find.byKey(const Key('stationSearchRegionDropdown')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('networkMapRegionMenuRow_부산')),
      findsNothing,
    );
    expect(changedRegions, isEmpty);
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
    // 상단바 세로 범위 안에 온전히 들어가야 한다.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
        child: MaterialApp(
          home: StationSearchScreen(
            repository: _EmptyStationSearchRepository(),
            reportRepository: const UnavailableFacilityReportRepository(),
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

    final topBarFinder = find.byKey(const Key('stationSearchAppBar'));
    expect(topBarFinder, findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('stationSearchTopBarContent')))
          .height,
      greaterThan(easySubwayTopBarContentHeight),
    );

    final topBarRect = tester.getRect(topBarFinder);
    final boxRect = tester.getRect(
      find.byKey(const Key('heroStationSearchInputBox')),
    );
    // 시각 박스가 상단바 세로 범위 안에 온전히 들어간다(위/아래로 잘리지 않음).
    expect(boxRect.bottom, lessThanOrEqualTo(topBarRect.bottom + 0.5));
    expect(boxRect.top, greaterThanOrEqualTo(topBarRect.top - 0.5));
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

  testWidgets('앱 메뉴 검색 진입은 최근 검색 저장소를 화면에 전달한다', (tester) async {
    final searchHistoryRepository = _MemorySearchHistoryRepository(['상록수']);

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: _EmptyStationSearchRepository(),
        reportRepository: const UnavailableFacilityReportRepository(),
        searchHistoryRepository: searchHistoryRepository,
        initialOnboardingState: _completedOnboardingState,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationRecentSearchQuery-상록수')),
      findsOneWidget,
    );
  });

  testWidgets('역 검색 화면에는 내 주변 역 찾기 버튼이 없다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: _EmptyStationSearchRepository(),
        reportRepository: const UnavailableFacilityReportRepository(),
        initialOnboardingState: _completedOnboardingState,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nearbyStationSearchButton')), findsNothing);
    expect(find.text('내 주변 역 찾기'), findsNothing);
    expect(find.text('내 주변 역 다시 찾기'), findsNothing);
    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
  });

  testWidgets('최근 검색이 없으면 빈 상태 안내를 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          searchHistoryRepository: _MemorySearchHistoryRepository(const []),
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationRecentSearchEmptyState')),
      findsOneWidget,
    );
    expect(find.text('최근 검색 내역이 없습니다.'), findsOneWidget);
    expect(
      find.byKey(const Key('stationRecentSearchEmptyImage')),
      findsOneWidget,
    );
    // 내역이 없으면 헤더(최근 검색 / 모두 지우기)는 숨긴다.
    expect(find.text('최근 검색'), findsNothing);
    expect(find.text('모두 지우기'), findsNothing);
    expect(
      find.byKey(const Key('stationRecentSearchClearAllButton')),
      findsNothing,
    );
  });

  testWidgets('역 검색 화면 상단바 입력 필드는 시스템 글자 크기를 키워도 잘리지 않는다', (tester) async {
    // #1962: 고정 높이 검색 필드가 큰 글자 배율에서도 상단바 경계를 넘지 않아야 한다.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: buildEasySubwayTestApp(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          initialOnboardingState: _completedOnboardingState,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final inputFinder = find.byKey(const Key('stationSearchInput'));
    expect(inputFinder, findsOneWidget);

    final topBarFinder = find.byKey(const Key('stationSearchAppBar'));
    expect(topBarFinder, findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('stationSearchTopBarContent')))
          .height,
      greaterThan(easySubwayTopBarContentHeight),
    );

    final topBarRect = tester.getRect(topBarFinder);
    final inputRect = tester.getRect(inputFinder);
    expect(inputRect.bottom, lessThanOrEqualTo(topBarRect.bottom + 0.5));
    expect(inputRect.top, greaterThanOrEqualTo(topBarRect.top - 0.5));
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
      expect(find.text('모두 보기'), findsNothing);
      expect(find.text('모두 지우기'), findsOneWidget);
      expect(
        find.byKey(const Key('stationRecentSearchViewAllButton')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('stationRecentSearchClearAllButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationRecentSearchQuery-상록수')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('최근 검색어 상록수 검색'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('최근 검색어 상록수 검색'))
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
        find.byKey(const Key('stationSearchResult-station-sangnoksu-seoul-4')),
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

  testWidgets('역 검색 화면 안에서 최근 검색을 개별 삭제한다', (tester) async {
    final searchHistoryRepository = _MemorySearchHistoryRepository([
      '상록수',
      '사당',
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          searchHistoryRepository: searchHistoryRepository,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationRecentSearchClearAllButton')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('stationRecentSearchRemove-상록수')));
    await tester.pumpAndSettle();

    expect(searchHistoryRepository.removedQueries, ['상록수']);
    expect(find.byKey(const Key('stationRecentSearchQuery-상록수')), findsNothing);
    expect(
      find.byKey(const Key('stationRecentSearchQuery-사당')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stationRecentSearchSection')), findsOneWidget);
    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
  });

  testWidgets('역 검색 최근 목록은 현재 지역 항목만 보여준다', (tester) async {
    final searchHistoryRepository = _MemorySearchHistoryRepository(const []);
    await searchHistoryRepository.recordSearch('상록수', region: '수도권');
    await searchHistoryRepository.recordSearch('서면', region: '부산');

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          searchHistoryRepository: searchHistoryRepository,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 수도권을 보는 동안 부산 검색어는 목록에 없다.
    expect(
      find.byKey(const Key('stationRecentSearchQuery-상록수')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stationRecentSearchQuery-서면')), findsNothing);
  });

  testWidgets('최근 경로 항목은 화살표 라벨로 통합 목록에 표시된다', (tester) async {
    final searchHistoryRepository = _MemorySearchHistoryRepository(const [])
      ..seedRoute(
        RecentRouteSearchEntry(
          originStationId: 'station-sangnoksu',
          originStationName: '상록수',
          destinationStationId: 'station-sadang',
          destinationStationName: '사당',
          region: '수도권',
          searchedAt: DateTime.utc(2026, 7, 21),
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: StationSearchScreen(
          repository: _EmptyStationSearchRepository(),
          reportRepository: const UnavailableFacilityReportRepository(),
          searchHistoryRepository: searchHistoryRepository,
          regionLabel: '수도권',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('상록수역 → 사당역'), findsOneWidget);
    expect(
      find.byKey(
        const Key('recentRouteSearch-station-sangnoksu--station-sadang'),
      ),
      findsOneWidget,
    );
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
      find.byKey(const Key('stationSearchResult-station-transfer-seoul-4')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key(
          'stationSearchResult-station-transfer-korail-gyeongui-jungang',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key('stationSearchResult-station-transfer-suin-bundang'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationSearchResult-station-transfer-shinbundang')),
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
  }) async => const [];

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    requestedQueries.add(query);
    return queryResults[query] ?? [];
  }
}

class _MemorySearchHistoryRepository implements SearchHistoryRepository {
  _MemorySearchHistoryRepository(
    List<String> queries, {
    String? seedRegion = '수도권',
  }) {
    for (final query in queries.reversed) {
      _addStation(query, region: seedRegion);
    }
  }

  final _stations = <RecentStationSearchEntry>[];
  final _routes = <RecentRouteSearchEntry>[];
  final recordedQueries = <String>[];
  final removedQueries = <String>[];
  int clearCount = 0;
  int _clock = 0;

  DateTime _tick() =>
      DateTime.fromMillisecondsSinceEpoch(++_clock, isUtc: true);

  void _addStation(String query, {String? region}) {
    final normalized = region?.trim() ?? '';
    _stations.removeWhere(
      (entry) =>
          entry.query == query && (entry.region?.trim() ?? '') == normalized,
    );
    _stations.insert(
      0,
      RecentStationSearchEntry(
        query: query,
        region: normalized.isEmpty ? null : normalized,
        searchedAt: _tick(),
      ),
    );
  }

  void seedRoute(RecentRouteSearchEntry entry) {
    _routes.insert(
      0,
      RecentRouteSearchEntry(
        originStationId: entry.originStationId,
        originStationName: entry.originStationName,
        waypointStationId: entry.waypointStationId,
        waypointStationName: entry.waypointStationName,
        destinationStationId: entry.destinationStationId,
        destinationStationName: entry.destinationStationName,
        region: entry.region,
        searchedAt: _tick(),
      ),
    );
  }

  @override
  Future<void> clearSearches() async {
    clearCount++;
    _stations.clear();
    _routes.clear();
  }

  @override
  Future<List<String>> listRecentQueries() async =>
      _stations.map((entry) => entry.query).toList(growable: false);

  @override
  Future<List<RecentSearchEntry>> listRecentEntries({
    String? region,
    int limit = 10,
  }) async {
    final filter = region?.trim();
    final entries = <RecentSearchEntry>[
      for (final entry in _stations)
        if (_stationMatches(entry.region, filter)) entry,
      for (final entry in _routes)
        if (filter == null ||
            filter.isEmpty ||
            stationBelongsToRegion(entry.region, filter))
          entry,
    ]..sort((a, b) => b.searchedAt.compareTo(a.searchedAt));
    return entries.take(limit).toList(growable: false);
  }

  @override
  Future<void> recordSearch(String query, {String? region}) async {
    final trimmed = query.trim();
    final normalized = region?.trim() ?? '';
    if (trimmed.isEmpty || normalized.isEmpty) {
      return;
    }
    recordedQueries.add(trimmed);
    _addStation(trimmed, region: normalized);
  }

  @override
  Future<void> recordRouteSearch(RecentRouteSearchEntry entry) async {
    _routes.removeWhere(
      (existing) => existing.identityKey == entry.identityKey,
    );
    seedRoute(entry);
  }

  @override
  Future<void> removeSearch(String query, {String? region}) async {
    final trimmed = query.trim();
    removedQueries.add(trimmed);
    final normalized = region?.trim();
    if (normalized == null || normalized.isEmpty) {
      _stations.removeWhere((entry) => entry.query == trimmed);
      return;
    }
    _stations.removeWhere(
      (entry) =>
          entry.query == trimmed &&
          stationBelongsToRegion(entry.region ?? '', normalized),
    );
  }

  @override
  Future<void> removeRouteSearch(RecentRouteSearchEntry entry) async {
    _routes.removeWhere(
      (existing) => existing.identityKey == entry.identityKey,
    );
  }

  bool _stationMatches(String? rowRegion, String? filter) {
    if (filter == null || filter.isEmpty) {
      return true;
    }
    if (rowRegion == null || rowRegion.isEmpty) {
      return false;
    }
    return stationBelongsToRegion(rowRegion, filter);
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
