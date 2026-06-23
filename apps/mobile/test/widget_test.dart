import 'dart:async';
import 'dart:ui';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/favorite_facility.dart';
import 'package:easysubway_mobile/internal_route.dart';
import 'package:easysubway_mobile/legacy_credential_cleanup.dart';
import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:easysubway_mobile/user_data_deletion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_secure_key_value_storage.dart';

OnboardingState _completedOnboardingState({String profileId = 'elderly'}) {
  return OnboardingState.completed(
    result: OnboardingResult(
      profile: mobilityProfileOptions.firstWhere(
        (option) => option.id == profileId,
      ),
      preferences: const OnboardingViewPreferences.defaults(),
    ),
  );
}

OnboardingState _completedOnboardingStateWithPreferences({
  required OnboardingViewPreferences preferences,
  String profileId = 'elderly',
}) {
  return OnboardingState.completed(
    result: OnboardingResult(
      profile: mobilityProfileOptions.firstWhere(
        (option) => option.id == profileId,
      ),
      preferences: preferences,
    ),
  );
}

Future<void> _openFavoriteList(WidgetTester tester, {Key? tabKey}) async {
  await _scrollHomeActionIntoView(tester, const Key('favoritesButton'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('favoritesButton')));
  await tester.pumpAndSettle();
  if (tabKey != null) {
    await tester.tap(find.byKey(tabKey));
    await tester.pumpAndSettle();
  }
}

Future<void> _openSettingsScreen(WidgetTester tester) async {
  await _scrollHomeActionIntoView(tester, const Key('appSettingsButton'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('appSettingsButton')));
  await tester.pumpAndSettle();
}

Future<void> _openMyReportsScreen(WidgetTester tester) async {
  await _scrollHomeActionIntoView(tester, const Key('myReportsButton'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('myReportsButton')));
  await tester.pumpAndSettle();
}

Future<void> _scrollHomeActionIntoView(WidgetTester tester, Key key) async {
  await tester.dragUntilVisible(
    find.byKey(key),
    find.byKey(const Key('homePrototypeList')),
    const Offset(0, -180),
  );
}

Future<void> _openMobilityProfileFromSettings(WidgetTester tester) async {
  await _openSettingsScreen(tester);
  await tester.tap(find.byKey(const Key('mobilityProfileButton')));
  await tester.pumpAndSettle();
}

Future<void> _openNotificationSettings(WidgetTester tester) async {
  await _openSettingsScreen(tester);
  await tester.scrollUntilVisible(
    find.byKey(const Key('notificationSettingsButton')),
    160,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('notificationSettingsButton')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('홈에서 내 신고 화면으로 이동한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository(
      reports: [
        const FacilityReportResult(
          id: 'report-2',
          stationId: 'station-sangnoksu',
          facilityId: 'facility-sangnoksu-elevator-1',
          reportType: 'CLOSED',
          description: '출입문이 막혀 있습니다.',
          status: 'ACCEPTED',
          createdAt: '2026-06-15T09:00:00',
        ),
      ],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: reportRepository,
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await _openMyReportsScreen(tester);

    expect(find.text('내 신고'), findsOneWidget);
    expect(find.text('반영됨'), findsOneWidget);
    expect(find.text('출입문이 막혀 있습니다.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '내 신고, 폐쇄, 접수번호 report-2, 반영됨, 출입문이 막혀 있습니다., 접수일 2026.06.15',
      ),
      findsOneWidget,
    );
    expect(reportRepository.listMyReportsCount, 1);
  });

  testWidgets('내 신고 항목을 누르면 상세 상태 화면으로 이동한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository(
      reports: [
        const FacilityReportResult(
          id: 'report-2',
          stationId: 'station-sangnoksu',
          facilityId: 'facility-sangnoksu-elevator-1',
          reportType: 'CLOSED',
          description: '출입문이 막혀 있습니다.',
          status: 'ACCEPTED',
          createdAt: '2026-06-15T09:00:00',
        ),
      ],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: reportRepository,
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await _openMyReportsScreen(tester);
    final reportSemantics = tester.getSemantics(
      find.bySemanticsLabel(
        '내 신고, 폐쇄, 접수번호 report-2, 반영됨, 출입문이 막혀 있습니다., 접수일 2026.06.15',
      ),
    );
    expect(
      reportSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('myReport-report-2')));
    await tester.pumpAndSettle();

    expect(find.text('신고 상세'), findsOneWidget);
    expect(find.text('폐쇄'), findsOneWidget);
    expect(find.text('반영됨'), findsOneWidget);
    expect(find.text('접수번호'), findsOneWidget);
    expect(find.text('report-2'), findsOneWidget);
    expect(find.text('접수일'), findsOneWidget);
    expect(find.text('2026.06.15'), findsOneWidget);
    expect(find.text('출입문이 막혀 있습니다.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('내 신고 상세, 폐쇄, 현재 상태 반영됨, 접수번호 report-2'),
      findsOneWidget,
    );
  });

  testWidgets('내 신고 화면은 접수한 신고가 없으면 짧은 빈 상태를 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyFacilityReportListScreen(
          repository: FakeFacilityReportRepository(reports: const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('접수한 신고가 없습니다.'), findsOneWidget);
    expect(find.byKey(const Key('myReportsRetryButton')), findsNothing);
  });

  testWidgets('온보딩을 마친 앱 세션은 홈을 바로 보여준다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsNothing);
  });

  testWidgets('기본 앱은 사진 복구 저장소가 없어도 플랫폼 오류 없이 홈을 보여준다', (tester) async {
    final reportedErrors = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );
      await tester.pumpAndSettle();
    });

    expect(reportedErrors, isEmpty);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('바로가기'),
      find.byKey(const Key('homePrototypeList')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();

    expect(find.text('자주 가는 곳'), findsNothing);
    expect(find.byKey(const Key('homeSavedRouteSection')), findsNothing);
    expect(find.text('저장한 경로가 없습니다'), findsNothing);
  });

  testWidgets('온보딩 이동 조건은 경로 검색 기본값으로 이어진다', (tester) async {
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
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(
          profileId: 'wheelchair',
        ),
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
    await tester.ensureVisible(
      find.byKey(const Key('routeDestinationStationOption-station-sadang')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('routeDestinationStationOption-station-sadang')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('routeSearchSubmitButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests.single.mobilityType, 'WHEELCHAIR');
  });

  testWidgets('온보딩 보기 설정은 완료 뒤 홈 UI에 적용된다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingStateWithPreferences(
          preferences: const OnboardingViewPreferences(
            largeTextEnabled: true,
            highContrastEnabled: true,
            simpleViewEnabled: true,
          ),
        ),
      ),
    );

    final homeContext = tester.element(find.byType(HomeScreen));

    expect(MediaQuery.textScalerOf(homeContext).scale(20), closeTo(23.6, 0.01));
    expect(Theme.of(homeContext).colorScheme.primary, const Color(0xFF003D40));
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.text('이동 프로필'), findsNothing);
    expect(find.text('시설 정보'), findsNothing);
    expect(find.text('신고'), findsNothing);
  });

  testWidgets('홈 화면은 핵심 행동과 보조 행동을 나누어 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingStateWithPreferences(
            preferences: const OnboardingViewPreferences(
              largeTextEnabled: true,
              highContrastEnabled: false,
              simpleViewEnabled: false,
            ),
          ),
        ),
      );

      expect(find.text('안녕하세요'), findsNothing);
      expect(find.text('어디로 가시나요?'), findsNothing);
      expect(find.text('안녕하세요, 오늘도 편안하게'), findsNothing);
      expect(find.text('길찾기'), findsOneWidget);
      expect(find.text('길찾기 시작'), findsOneWidget);
      expect(find.byKey(const Key('homeRouteDraftPanel')), findsNothing);
      expect(find.text('지금 주변 상태'), findsOneWidget);
      expect(find.text('주변 시설 상태 없음'), findsOneWidget);
      expect(
        tester.getSize(find.widgetWithText(OutlinedButton, '주변 역 보기')).height,
        greaterThanOrEqualTo(EasySubwayTouchTarget.general),
      );

      expect(find.byKey(const Key('homeSecondaryActionsGroup')), findsNothing);
      expect(find.byKey(const Key('homeSettingsActionsGroup')), findsNothing);
      expect(find.byKey(const Key('homeMyInfoActionsGroup')), findsNothing);
      expect(find.byKey(const Key('homeTripControlPanel')), findsNothing);
      expect(find.widgetWithText(FilledButton, '역 검색'), findsNothing);
      expect(find.widgetWithText(FilledButton, '길찾기 시작'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '설정'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '이동 조건'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '알림 설정'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '즐겨찾기'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '내 신고'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '도움말'), findsNothing);
      expect(find.byKey(const Key('homeHelpActionButton')), findsOneWidget);
      expect(find.widgetWithText(TextButton, '도움말'), findsNothing);
      expect(find.widgetWithText(FilledButton, '내 신고'), findsNothing);
      expect(find.widgetWithText(FilledButton, '알림 설정'), findsNothing);
      expect(find.text('즐겨찾기 경로'), findsNothing);
      expect(find.text('즐겨찾기 역'), findsNothing);
      expect(find.text('즐겨찾기 시설'), findsNothing);
      expect(find.textContaining('빠른 길보다'), findsNothing);
      expect(find.text('고령자'), findsOneWidget);
      expect(find.bySemanticsLabel('길찾기 시작, 현재 이동 조건 고령자'), findsOneWidget);
      expect(find.textContaining('휠체어'), findsNothing);

      final stationButtonSize = tester.getSize(
        find.byKey(const Key('stationSearchButton')),
      );
      final routeButtonSize = tester.getSize(
        find.byKey(const Key('routeSearchButton')),
      );

      expect(stationButtonSize.height, greaterThanOrEqualTo(48));
      expect(routeButtonSize.height, greaterThanOrEqualTo(52));
      expect(routeButtonSize.width, greaterThan(stationButtonSize.width));

      await tester.scrollUntilVisible(find.text('저장한 경로가 없습니다'), 180);
      await tester.pumpAndSettle();
      expect(find.text('저장한 경로가 없습니다'), findsOneWidget);
      expect(find.text('경로를 저장하면 현재 시설 상태와 함께 다시 볼 수 있어요.'), findsNothing);

      await tester.dragUntilVisible(
        find.text('바로가기'),
        find.byKey(const Key('homePrototypeList')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      expect(find.text('바로가기'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('설정'),
        find.byKey(const Key('homePrototypeList')),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();

      expect(find.text('가까운 역'), findsOneWidget);
      expect(find.text('내 신고'), findsOneWidget);
      expect(find.text('저장한 곳'), findsOneWidget);
      expect(find.text('설정'), findsOneWidget);

      final settingsButtonSize = tester.getSize(
        find.byKey(const Key('appSettingsButton')),
      );
      final myReportsButtonSize = tester.getSize(
        find.byKey(const Key('myReportsButton')),
      );
      expect(settingsButtonSize.height, greaterThanOrEqualTo(100));
      expect(myReportsButtonSize.height, greaterThanOrEqualTo(100));

      await tester.drag(
        find.byKey(const Key('homePrototypeList')),
        const Offset(0, -620),
      );
      await tester.pumpAndSettle();

      expect(find.text('이동 프로필'), findsNothing);
      expect(find.text('시설 정보'), findsNothing);
      expect(find.text('신고'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 보조 행동은 좁은 화면과 큰 글자에서도 줄임표 없이 터치 기준을 지킨다', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3.2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('appSettingsButton')),
      find.byKey(const Key('homePrototypeList')),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();

    final settingsButton = find.byKey(const Key('appSettingsButton'));
    final favoritesButton = find.byKey(const Key('favoritesButton'));

    expect(EasySubwayTouchTarget.iconOnly, 48);
    expect(EasySubwayTouchTarget.general, 56);
    expect(EasySubwayTouchTarget.primary, 60);
    expect(find.text('설정'), findsOneWidget);
    expect(favoritesButton, findsOneWidget);
    expect(tester.getSize(settingsButton).height, greaterThan(56));
    expect(tester.getSize(favoritesButton).height, greaterThan(56));
    expect(tester.getSize(settingsButton).width, greaterThan(280));
    expect(tester.getSize(favoritesButton).width, greaterThan(280));
    expect(tester.getSize(settingsButton).height, greaterThanOrEqualTo(60));
  });

  testWidgets('홈 자주 가는 곳은 저장한 경로가 있으면 빈 상태 대신 경로를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(
            favorites: [_favoriteRoute()],
          ),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('상록수 → 사당'), 180);
      await tester.pumpAndSettle();

      expect(find.text('상록수 → 사당'), findsOneWidget);
      expect(
        find.bySemanticsLabel('저장한 경로, 상록수에서 사당까지, 수도권 4호선, 고령자, 이동 점수 92점'),
        findsOneWidget,
      );
      expect(find.text('저장한 경로가 없습니다'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 저장 경로 재조회 실패는 카드 오류로만 표시된다', (tester) async {
    final favoriteRouteRepository = FakeFavoriteRouteRepository()
      ..error = const FavoriteRouteException('즐겨찾기 경로를 불러오지 못했습니다.');

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteRouteRepository: favoriteRouteRepository,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routeSearchButton')));
    await tester.pumpAndSettle();
    expect(find.text('경로 검색'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('저장한 경로를 불러오지 못했습니다'), 180);
    await tester.pumpAndSettle();
    expect(find.text('저장한 경로를 불러오지 못했습니다'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, '저장한 경로 보기')).height,
      greaterThanOrEqualTo(EasySubwayTouchTarget.general),
    );
  });

  testWidgets('설정 화면은 교통약자 사용 맥락별 섹션과 기존 설정 진입점을 제공한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingStateWithPreferences(
            preferences: const OnboardingViewPreferences(
              largeTextEnabled: true,
              highContrastEnabled: true,
              simpleViewEnabled: false,
            ),
          ),
        ),
      );

      await _openSettingsScreen(tester);

      settingsActionSemantics(String label) {
        return tester.getSemantics(
          find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == label,
          ),
        );
      }

      expect(find.text('설정'), findsOneWidget);
      expect(find.text('내 이동 조건'), findsOneWidget);
      expect(find.text('화면과 읽기'), findsOneWidget);
      expect(find.text('경로 찾기'), findsOneWidget);
      expect(find.text('지역과 데이터'), findsOneWidget);
      expect(find.text('고령자'), findsOneWidget);
      expect(find.text('계단을 피하고 쉬운 환승을 우선해요'), findsNWidgets(2));
      expect(find.text('큰 글자 켜짐'), findsOneWidget);
      expect(find.text('고대비 표시를 사용해요'), findsOneWidget);
      expect(find.text('전체 보기 켜짐'), findsOneWidget);
      expect(find.byKey(const Key('mobilityProfileButton')), findsOneWidget);
      expect(
        settingsActionSemantics(
          '고령자, 계단을 피하고 쉬운 환승을 우선해요',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('mobilityProfileButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobilityProfileCard-wheelchair')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobilityProfileDoneButton')));
      await tester.pumpAndSettle();

      expect(find.text('휠체어'), findsOneWidget);
      expect(find.text('계단 없는 길만 안내해요'), findsNWidgets(2));

      await tester.scrollUntilVisible(
        find.byKey(const Key('notificationSettingsButton')),
        160,
      );
      await tester.pumpAndSettle();

      expect(find.text('알림'), findsOneWidget);
      expect(
        find.byKey(const Key('settingsSection-help-privacy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notificationSettingsButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settingsSupportPrivacyButton')),
        findsOneWidget,
      );
      expect(
        settingsActionSemantics(
          '알림 설정, 시설 상태, 신고 처리, 정보 갱신 알림을 관리해요',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        settingsActionSemantics(
          '도움말과 개인정보, 지원, 개인정보 처리방침, 데이터 삭제 안내를 확인해요',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 이동 조건 요약은 현재 profile과 변경 결과를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('homeTripControlPanel')), findsNothing);
    expect(find.text('고령자'), findsOneWidget);
    expect(find.bySemanticsLabel('길찾기 시작, 현재 이동 조건 고령자'), findsOneWidget);

    await _openMobilityProfileFromSettings(tester);
    await tester.tap(find.byKey(const Key('mobilityProfileCard-wheelchair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityProfileDoneButton')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('길찾기'),
      find.byKey(const Key('homePrototypeList')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();

    expect(find.text('휠체어'), findsOneWidget);
    expect(find.bySemanticsLabel('길찾기 시작, 현재 이동 조건 휠체어'), findsOneWidget);
    semanticsHandle.dispose();
  });

  testWidgets('홈 즐겨찾기는 하나의 진입점에서 탭 목록을 바로 보여준다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _scrollHomeActionIntoView(tester, const Key('favoritesButton'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('favoritesButton')), findsOneWidget);
    expect(find.byKey(const Key('favoriteRoutesButton')), findsNothing);
    expect(find.byKey(const Key('favoriteStationsButton')), findsNothing);
    expect(find.byKey(const Key('favoriteFacilitiesButton')), findsNothing);

    await tester.tap(find.byKey(const Key('favoritesButton')));
    await tester.pumpAndSettle();

    expect(find.text('즐겨찾기'), findsOneWidget);
    expect(find.byKey(const Key('favoriteRoutesTabButton')), findsOneWidget);
    expect(find.byKey(const Key('favoriteStationsTabButton')), findsOneWidget);
    expect(
      find.byKey(const Key('favoriteFacilitiesTabButton')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('favoriteRoutesButton')), findsNothing);
    expect(find.byKey(const Key('favoriteStationsButton')), findsNothing);
    expect(find.byKey(const Key('favoriteFacilitiesButton')), findsNothing);
  });

  testWidgets('홈은 도움말에서 개인정보와 삭제 요청 경로를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          supportAccessInfo: const SupportAccessInfo(
            privacyPolicyUrl: 'https://easysubway.example/privacy',
            supportEmail: 'support@easysubway.example',
            dataDeletionEmail: 'privacy@easysubway.example',
          ),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('homeHelpActionButton')));
      await tester.pumpAndSettle();

      expect(find.text('도움말'), findsOneWidget);
      expect(find.text('개인정보처리방침'), findsOneWidget);
      expect(find.text('https://easysubway.example/privacy'), findsOneWidget);
      expect(find.text('고객지원'), findsOneWidget);
      expect(find.text('support@easysubway.example'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('securityContactAccessItem')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('보안 문의'), findsOneWidget);
      expect(find.text('준비 중입니다.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('dataDeletionAccessItem')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('데이터 삭제 요청'), findsOneWidget);

      final privacyButtonSize = tester.getSize(
        find.byKey(const Key('privacyPolicyAccessItem')),
      );
      final deletionButtonSize = tester.getSize(
        find.byKey(const Key('dataDeletionAccessItem')),
      );

      expect(privacyButtonSize.height, greaterThanOrEqualTo(60));
      expect(deletionButtonSize.height, greaterThanOrEqualTo(60));
      final privacySemantics = tester
          .getSemantics(find.byKey(const Key('privacyPolicyAccessItem')))
          .getSemanticsData();
      expect(
        privacySemantics.label,
        '개인정보처리방침, https://easysubway.example/privacy',
      );
      expect(privacySemantics.hasAction(SemanticsAction.tap), isTrue);
      final deletionSemantics = tester
          .getSemantics(find.byKey(const Key('dataDeletionAccessItem')))
          .getSemanticsData();
      expect(deletionSemantics.label, '데이터 삭제 요청, privacy@easysubway.example');
      expect(deletionSemantics.hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('도움말은 개인정보 사용 목적과 삭제 요청 대상을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          supportAccessInfo: const SupportAccessInfo(
            privacyPolicyUrl: 'https://easysubway.example/privacy',
            supportEmail: 'support@easysubway.example',
            dataDeletionEmail: 'privacy@easysubway.example',
          ),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('homeHelpActionButton')));
      await tester.pumpAndSettle();

      expect(find.text('개인정보 사용 안내'), findsOneWidget);
      expect(
        find.text('현재 위치는 가까운 역 찾기와 시설 신고 위치 확인에만 사용됩니다.'),
        findsOneWidget,
      );
      expect(
        find.text('즐겨찾기, 이동 조건, 신고 내용과 사진은 앱 기능 제공에 사용됩니다.'),
        findsOneWidget,
      );
      expect(
        find.text(
          '데이터 삭제 요청 시 즐겨찾기, 이동 조건, 신고 접수 기록, 신고 내용·사진·위치와 경로 피드백을 삭제하거나 익명화합니다.',
        ),
        findsOneWidget,
      );
      expect(find.text('법적·보안상 필요한 최소 기록은 정해진 기간 동안만 보관합니다.'), findsOneWidget);

      final summarySize = tester.getSize(
        find.byKey(const Key('privacyDataUseSummary')),
      );
      expect(summarySize.height, greaterThanOrEqualTo(120));

      final summarySemantics = tester
          .getSemantics(find.byKey(const Key('privacyDataUseSummary')))
          .getSemanticsData();
      expect(
        summarySemantics.label,
        contains('개인정보 사용 안내, 현재 위치는 가까운 역 찾기와 시설 신고 위치 확인에만 사용됩니다.'),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('도움말은 안전 고지와 데이터 한계를 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          supportAccessInfo: const SupportAccessInfo(
            privacyPolicyUrl: 'https://easysubway.example/privacy',
            supportEmail: 'support@easysubway.example',
            dataDeletionEmail: 'privacy@easysubway.example',
          ),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('homeHelpActionButton')));
      await tester.pumpAndSettle();

      expect(find.text('안전과 데이터 안내'), findsOneWidget);
      expect(find.text('경로와 시설 정보는 이동을 돕는 참고 정보입니다.'), findsOneWidget);
      expect(
        find.text('실제 이동 전에는 현장 안내, 역무원 안내, 운영기관 공지를 먼저 확인해 주세요.'),
        findsOneWidget,
      );
      expect(find.text('실시간 상태나 무조건 안전한 경로를 보장하지 않습니다.'), findsOneWidget);

      final noticeSize = tester.getSize(
        find.byKey(const Key('safetyDataNotice')),
      );
      expect(noticeSize.height, greaterThanOrEqualTo(120));

      final noticeSemantics = tester
          .getSemantics(find.byKey(const Key('safetyDataNotice')))
          .getSemanticsData();
      expect(
        noticeSemantics.label,
        '안전과 데이터 안내, 경로와 시설 정보는 이동을 돕는 참고 정보입니다. 실제 이동 전에는 현장 안내, 역무원 안내, 운영기관 공지를 먼저 확인해 주세요. 실시간 상태나 무조건 안전한 경로를 보장하지 않습니다.',
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('도움말은 보안 문의와 취약점 접수 경로를 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final launcher = RecordingSupportAccessLauncher();
    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          supportAccessLauncher: launcher,
          supportAccessInfo: const SupportAccessInfo(
            privacyPolicyUrl: 'https://easysubway.example/privacy',
            supportEmail: 'support@easysubway.example',
            dataDeletionEmail: 'privacy@easysubway.example',
            securityEmail: 'security@easysubway.example',
          ),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('homeHelpActionButton')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('securityContactNotice')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('보안 문의 안내'), findsOneWidget);
      expect(find.text('취약점이나 개인정보 보호 우려를 발견하면 보안 문의로 알려주세요.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('securityContactAccessItem')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('보안 문의'), findsOneWidget);
      expect(find.text('security@easysubway.example'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const Key('securityContactAccessItem')))
            .getSemanticsData()
            .label,
        '보안 문의, security@easysubway.example',
      );

      await tester.tap(find.byKey(const Key('securityContactAccessItem')));
      await tester.pumpAndSettle();

      expect(launcher.openedUris.single.scheme, 'mailto');
      expect(launcher.openedUris.single.path, 'security@easysubway.example');
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('도움말은 개인정보 링크를 값 복사 화면이 아니라 외부 연결로 처리한다', (tester) async {
    final launcher = RecordingSupportAccessLauncher();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        supportAccessLauncher: launcher,
        supportAccessInfo: const SupportAccessInfo(
          privacyPolicyUrl: 'https://easysubway.example/privacy',
          supportEmail: 'support@easysubway.example',
          dataDeletionEmail: 'privacy@easysubway.example',
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('homeHelpActionButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacyPolicyAccessItem')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      launcher.openedUris.single.toString(),
      'https://easysubway.example/privacy',
    );
  });

  testWidgets('도움말은 고객지원을 메일 앱으로 연결한다', (tester) async {
    final launcher = RecordingSupportAccessLauncher();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        supportAccessLauncher: launcher,
        supportAccessInfo: const SupportAccessInfo(
          privacyPolicyUrl: 'https://easysubway.example/privacy',
          supportEmail: 'support@easysubway.example',
          dataDeletionEmail: 'privacy@easysubway.example',
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('homeHelpActionButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('supportAccessItem')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('supportAccessItem')));
    await tester.pumpAndSettle();
    expect(launcher.openedUris, hasLength(1));
    expect(launcher.openedUris.single.scheme, 'mailto');
    expect(launcher.openedUris.single.path, 'support@easysubway.example');
  });

  testWidgets('도움말은 앱 안에서 데이터 삭제를 재확인하고 로컬 상태를 정리한다', (tester) async {
    final deletionRepository = FakeUserDataDeletionRepository();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: _completedOnboardingState().result,
    );
    final draftTargetStore = MemoryFacilityReportDraftTargetStore(
      const FacilityReportTarget(
        stationId: 'station-1',
        stationName: '상록수',
        facilityId: 'facility-1',
        facilityName: '1번 엘리베이터',
        facilityTypeLabel: '엘리베이터',
        facilityStatusLabel: '정상',
      ),
    );
    final legacyCredentialStorage = FakeSecureKeyValueStorage()
      ..values[SecureLegacyCredentialCleaner.legacyAuthCredentialsKey] =
          'legacy-token-payload';

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        userDataDeletionRepository: deletionRepository,
        legacyCredentialCleaner: SecureLegacyCredentialCleaner(
          storage: legacyCredentialStorage,
        ),
        onboardingStore: onboardingStore,
        facilityReportDraftTargetStore: draftTargetStore,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('homeHelpActionButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('dataDeletionAccessItem')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('dataDeletionAccessItem')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dataDeletionStartButton')), findsOneWidget);
    expect(find.textContaining('즐겨찾기, 이동 조건, 신고 접수 기록'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dataDeletionStartButton')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('정말 삭제할까요?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dataDeletionConfirmButton')));
    await tester.pumpAndSettle();

    expect(deletionRepository.deleteCount, 1);
    expect(
      legacyCredentialStorage.deletedKeys,
      contains(SecureLegacyCredentialCleaner.legacyAuthCredentialsKey),
    );
    expect(
      legacyCredentialStorage.values,
      isNot(contains(SecureLegacyCredentialCleaner.legacyAuthCredentialsKey)),
    );
    expect(onboardingStore.savedResult, isNull);
    expect(draftTargetStore.target, isNull);
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsOneWidget);
  });

  testWidgets('데이터 삭제 실패 시 로컬 상태를 유지하고 오류를 안내한다', (tester) async {
    final deletionRepository = FakeUserDataDeletionRepository(
      error: const UserDataDeletionException(
        '데이터 삭제를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      ),
    );
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: _completedOnboardingState().result,
    );
    final draftTargetStore = MemoryFacilityReportDraftTargetStore(
      const FacilityReportTarget(
        stationId: 'station-1',
        stationName: '상록수',
        facilityId: 'facility-1',
        facilityName: '1번 엘리베이터',
        facilityTypeLabel: '엘리베이터',
        facilityStatusLabel: '정상',
      ),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        userDataDeletionRepository: deletionRepository,
        onboardingStore: onboardingStore,
        facilityReportDraftTargetStore: draftTargetStore,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('homeHelpActionButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('dataDeletionAccessItem')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('dataDeletionAccessItem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dataDeletionStartButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dataDeletionConfirmButton')));
    await tester.pumpAndSettle();

    expect(deletionRepository.deleteCount, 1);
    expect(onboardingStore.savedResult, isNotNull);
    expect(draftTargetStore.target, isNotNull);
    expect(find.text('데이터 삭제를 완료하지 못했습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('도움말은 연결값이 비어 있으면 준비 중으로 보여주고 실행하지 않는다', (tester) async {
    final launcher = RecordingSupportAccessLauncher();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        supportAccessLauncher: launcher,
        supportAccessInfo: const SupportAccessInfo(
          privacyPolicyUrl: '',
          supportEmail: '',
          dataDeletionEmail: '',
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('homeHelpActionButton')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('privacyPolicyAccessItem')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const Key('privacyPolicyAccessItem')))
          .getSemanticsData()
          .label,
      '개인정보처리방침, 준비 중입니다.',
    );

    await tester.tap(find.byKey(const Key('privacyPolicyAccessItem')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('supportAccessItem')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const Key('supportAccessItem')))
          .getSemanticsData()
          .label,
      '고객지원, 준비 중입니다.',
    );
    await tester.tap(find.byKey(const Key('supportAccessItem')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('securityContactAccessItem')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const Key('securityContactAccessItem')))
          .getSemanticsData()
          .label,
      '보안 문의, 준비 중입니다.',
    );
    await tester.tap(find.byKey(const Key('securityContactAccessItem')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('dataDeletionAccessItem')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const Key('dataDeletionAccessItem')))
          .getSemanticsData()
          .label,
      '데이터 삭제 요청, 준비 중입니다.',
    );
    await tester.tap(find.byKey(const Key('dataDeletionAccessItem')));
    await tester.pumpAndSettle();

    expect(launcher.openedUris, isEmpty);
  });

  testWidgets('도움말은 외부 연결 실패를 짧게 안내한다', (tester) async {
    final launcher = RecordingSupportAccessLauncher(openResult: false);

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        supportAccessLauncher: launcher,
        supportAccessInfo: const SupportAccessInfo(
          privacyPolicyUrl: 'https://easysubway.example/privacy',
          supportEmail: 'support@easysubway.example',
          dataDeletionEmail: 'privacy@easysubway.example',
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('homeHelpActionButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacyPolicyAccessItem')));
    await tester.pump();

    expect(find.text('연결할 수 없습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('알림 설정 화면은 현재 설정을 불러오고 바꾼 값을 저장한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final notificationRepository = FakeNotificationSettingsRepository();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: notificationRepository,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openNotificationSettings(tester);

      expect(find.text('알림 설정'), findsOneWidget);
      expect(find.text('역 시설 알림'), findsOneWidget);
      expect(find.text('경로 시설 알림'), findsOneWidget);
      expect(find.text('신고 처리 알림'), findsOneWidget);
      expect(find.text('정보 갱신 알림'), findsOneWidget);
      expect(find.bySemanticsLabel('역 시설 알림 켜짐'), findsOneWidget);
      expect(find.bySemanticsLabel('경로 시설 알림 꺼짐'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('notificationSwitch-favoriteRouteFacilityAlerts')),
      );
      await tester.tap(
        find.byKey(const Key('notificationSwitch-dataQualityAlerts')),
      );
      await tester.tap(find.byKey(const Key('notificationSettingsSaveButton')));
      await tester.pumpAndSettle();

      expect(notificationRepository.savedSettings, hasLength(1));
      expect(
        notificationRepository.savedSettings.single.favoriteRouteFacilityAlerts,
        isTrue,
      );
      expect(
        notificationRepository.savedSettings.single.dataQualityAlerts,
        isTrue,
      );
      expect(find.text('알림 설정을 저장했습니다.'), findsOneWidget);
      expect(find.bySemanticsLabel('알림 설정을 저장했습니다.'), findsOneWidget);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('알림 설정 화면은 기기 알림 권한을 사용자 확인 뒤 요청한다', (tester) async {
    final notificationPermissionProvider = FakeNotificationPermissionProvider(
      nextStatus: NotificationPermissionStatus.granted,
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        notificationPermissionProvider: notificationPermissionProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openNotificationSettings(tester);

    await tester.tap(find.byKey(const Key('notificationPermissionButton')));
    await tester.pumpAndSettle();

    expect(find.text('알림 받기'), findsOneWidget);
    expect(
      find.text(
        '즐겨찾는 역과 경로의 시설 상태, 내 신고 처리 결과, 정보 갱신을 알려드립니다. 알림 설정에서 언제든 끌 수 있습니다.',
      ),
      findsOneWidget,
    );
    expect(notificationPermissionProvider.requestCount, 0);

    await tester.tap(find.text('켜기'));
    await tester.pumpAndSettle();

    expect(notificationPermissionProvider.requestCount, 1);
    expect(find.text('기기 알림이 켜졌습니다.'), findsOneWidget);
    expect(find.bySemanticsLabel('기기 알림이 켜졌습니다.'), findsOneWidget);
  });

  testWidgets('알림 설정 화면은 기기 알림 권한 거부를 짧게 안내한다', (tester) async {
    final notificationPermissionProvider = FakeNotificationPermissionProvider(
      nextStatus: NotificationPermissionStatus.denied,
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        notificationPermissionProvider: notificationPermissionProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openNotificationSettings(tester);
    await tester.tap(find.byKey(const Key('notificationPermissionButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('켜기'));
    await tester.pumpAndSettle();

    expect(notificationPermissionProvider.requestCount, 1);
    expect(find.text('기기 알림 권한을 켜 주세요.'), findsOneWidget);
    expect(find.bySemanticsLabel('기기 알림 권한을 켜 주세요.'), findsOneWidget);
    expect(find.text('기기 알림 설정과 네트워크 상태를 확인한 뒤 다시 시도해 주세요.'), findsNothing);
  });

  testWidgets('알림 설정 화면은 기기 알림 실패 다음 행동을 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final notificationPermissionProvider = FakeNotificationPermissionProvider(
      nextStatus: NotificationPermissionStatus.denied,
      error: const NotificationSettingsException('기기 알림 등록을 마치지 못했습니다.'),
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          notificationPermissionProvider: notificationPermissionProvider,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openNotificationSettings(tester);
      await tester.tap(find.byKey(const Key('notificationPermissionButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('켜기'));
      await tester.pumpAndSettle();

      expect(notificationPermissionProvider.requestCount, 1);
      expect(find.text('기기 알림 등록을 마치지 못했습니다.'), findsOneWidget);
      expect(find.text('기기 알림 설정과 네트워크 상태를 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('다음 행동, 기기 알림 설정과 네트워크 상태를 확인한 뒤 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('notificationRegistrationFailureNextAction')),
        ),
        isSemantics(
          label: '다음 행동, 기기 알림 설정과 네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
          isLiveRegion: true,
        ),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 즐겨찾기는 저장한 역을 큰 목록으로 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final favoriteRepository = FakeFavoriteStationRepository(
      favorites: [_favoriteStation(id: 'station-sangnoksu', name: '상록수')],
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: favoriteRepository,
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openFavoriteList(
        tester,
        tabKey: const Key('favoriteStationsTabButton'),
      );

      expect(find.text('역'), findsOneWidget);
      expect(find.text('상록수'), findsOneWidget);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('기본 정보만 있음'), findsOneWidget);
      expect(
        find.byKey(const Key('favoriteStationTile-station-sangnoksu')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('즐겨찾기 역, 상록수, 수도권 4호선, 수도권, 기본 정보만 있음, 출처 공식 파일'),
        findsOneWidget,
      );
      expect(find.text('출처 공식 파일'), findsOneWidget);

      final tileSize = tester.getSize(
        find.byKey(const Key('favoriteStationTile-station-sangnoksu')),
      );
      expect(tileSize.height, greaterThanOrEqualTo(72));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 즐겨찾기 시설은 저장한 시설을 큰 목록으로 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final favoriteFacilityRepository = FakeFavoriteFacilityRepository(
      favorites: [_favoriteFacility()],
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          favoriteFacilityRepository: favoriteFacilityRepository,
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openFavoriteList(
        tester,
        tabKey: const Key('favoriteFacilitiesTabButton'),
      );

      expect(find.text('시설'), findsOneWidget);
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('정상'), findsOneWidget);
      expect(find.text('정보 신뢰도 높음'), findsOneWidget);
      expect(find.text('출처 공식 파일'), findsOneWidget);
      expect(
        find.byKey(
          const Key('favoriteFacilityTile-facility-sangnoksu-elevator-1'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '즐겨찾기 시설, 1번 출구 엘리베이터, 상록수역, 엘리베이터, 정상, 1번 출구 앞, 정보 신뢰도 높음, 출처 공식 파일',
        ),
        findsOneWidget,
      );

      final tileSize = tester.getSize(
        find.byKey(
          const Key('favoriteFacilityTile-facility-sangnoksu-elevator-1'),
        ),
      );
      expect(tileSize.height, greaterThanOrEqualTo(72));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 즐겨찾기 경로는 저장한 경로를 큰 목록으로 보여주고 삭제한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final favoriteRouteRepository = FakeFavoriteRouteRepository(
      favorites: [_favoriteRoute()],
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
          favoriteRouteRepository: favoriteRouteRepository,
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openFavoriteList(tester);

      expect(find.text('경로'), findsOneWidget);
      expect(find.text('상록수에서 사당까지'), findsOneWidget);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('고령자'), findsOneWidget);
      expect(find.text('이동 점수 92점'), findsOneWidget);
      expect(
        find.bySemanticsLabel('즐겨찾기 경로, 상록수에서 사당까지, 수도권 4호선, 고령자, 이동 점수 92점'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('상록수에서 사당까지 삭제'), findsOneWidget);

      await tester.tap(find.byKey(const Key('favoriteRouteRemove-route-1')));
      await tester.pumpAndSettle();

      expect(favoriteRouteRepository.removedFavoriteRouteIds, ['route-1']);
      expect(find.text('저장한 경로가 없습니다.'), findsOneWidget);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 즐겨찾기 경로 삭제 중에는 같은 항목을 다시 누를 수 없다', (tester) async {
    final removeCompleter = Completer<void>();
    final favoriteRouteRepository = FakeFavoriteRouteRepository(
      favorites: [_favoriteRoute()],
      removeCompleter: removeCompleter,
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: favoriteRouteRepository,
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openFavoriteList(tester);

    final removeButton = find.byKey(const Key('favoriteRouteRemove-route-1'));
    await tester.tap(removeButton);
    await tester.pump();

    expect(favoriteRouteRepository.removedFavoriteRouteIds, ['route-1']);
    expect(find.text('삭제 중'), findsOneWidget);
    expect(find.bySemanticsLabel('상록수에서 사당까지 삭제 중'), findsOneWidget);

    await tester.tap(removeButton);
    await tester.pump();

    expect(favoriteRouteRepository.removedFavoriteRouteIds, ['route-1']);

    removeCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('저장한 경로가 없습니다.'), findsOneWidget);
  });

  testWidgets('즐겨찾기 경로 목록 실패는 다음 행동을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final favoriteRouteRepository = FakeFavoriteRouteRepository()
      ..error = const FavoriteRouteException('즐겨찾기 경로를 불러오지 못했습니다.');

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
          favoriteRouteRepository: favoriteRouteRepository,
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openFavoriteList(tester);

      expect(find.text('즐겨찾기 경로를 불러오지 못했습니다.'), findsOneWidget);
      expect(find.text('네트워크 상태를 확인한 뒤 다시 불러와 주세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('다음 행동, 네트워크 상태를 확인한 뒤 다시 불러와 주세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('favoriteRouteLoadFailureNextAction')),
        ),
        isSemantics(
          label: '다음 행동, 네트워크 상태를 확인한 뒤 다시 불러와 주세요.',
          isLiveRegion: true,
        ),
      );
      expect(
        find.byKey(const Key('favoriteRoutesRetryButton')),
        findsOneWidget,
      );
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
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
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
      expect(find.bySemanticsLabel('역 이름을 입력해 주세요'), findsOneWidget);
      expect(find.bySemanticsLabel('역 이름 입력'), findsNothing);
      expect(
        searchInput.decoration?.floatingLabelBehavior,
        FloatingLabelBehavior.always,
      );
      expect(find.byKey(const Key('stationSearchSubmitButton')), findsNothing);
      expect(
        find.byKey(const Key('nearbyStationSearchButton')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('stationSearchSubmitButton')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('nearbyStationSearchButton')), findsNothing);
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
      expect(find.text('수도권'), findsNothing);
      expect(find.text('기본 정보만 있음'), findsNothing);
      expect(find.text('기본 정보만 있음 · 출처 확인 필요'), findsOneWidget);
      expect(find.bySemanticsLabel('검색 결과 1개'), findsOneWidget);
      expect(
        find.bySemanticsLabel('상록수역, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 있음, 출처 확인 필요'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            '상록수역, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 있음, 출처 확인 필요',
          ),
        ),
        isSemantics(
          label: '상록수역, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 있음, 출처 확인 필요',
          isButton: true,
          hasTapAction: true,
        ),
      );
      final resultTileSize = tester.getSize(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      expect(resultTileSize.height, lessThanOrEqualTo(112));

      final lineBadgeSize = tester.getSize(
        find.byKey(const Key('stationLineBadge-seoul-4')),
      );
      expect(lineBadgeSize.width, 32);
      expect(lineBadgeSize.height, 32);

      final lineNumber = tester.widget<Text>(find.text('4'));
      expect(lineNumber.style?.fontSize, 20);
      expect(lineNumber.style?.color, const Color(0xFF102A2C));

      final namedLine = tester.widget<Text>(find.text('경의중앙'));
      expect(namedLine.style?.fontSize, 12);

      await tester.enterText(find.byKey(const Key('stationSearchInput')), '');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stationSearchSubmitButton')), findsNothing);
      expect(
        find.byKey(const Key('nearbyStationSearchButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
        findsNothing,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색 결과에서 출발 도착 역할을 지정하면 홈 이어하기가 표시된다', (tester) async {
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    expect(find.byKey(const Key('homeRouteDraftPanel')), findsNothing);

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationRoleOrigin-station-sangnoksu')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationRoleDestination-station-sangnoksu')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('상록수역을 출발역으로 설정'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('상록수역을 출발역으로 설정'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(
      find.byKey(const Key('stationRoleOrigin-station-sangnoksu')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '사당');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationRoleDestination-station-sadang')),
    );
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('homeRouteDraftPanel')), findsOneWidget);
    expect(find.text('출발·도착 정하기'), findsOneWidget);
    expect(find.text('출발 상록수역 → 도착 사당역'), findsOneWidget);

    await tester.tap(find.byKey(const Key('homeRouteDraftPanel')));
    await tester.pumpAndSettle();

    expect(find.text('경로 검색'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('routeOriginStationInput')))
          .controller
          ?.text,
      '상록수',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('routeDestinationStationInput')),
          )
          .controller
          ?.text,
      '사당',
    );
    expect(find.text('출발역 상록수'), findsOneWidget);
    expect(find.text('도착역 사당'), findsOneWidget);
    expect(find.text('노선 정보 없음'), findsNothing);
    final semanticsHandle = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel('출발역 선택됨, 상록수'), findsOneWidget);
      expect(find.bySemanticsLabel('도착역 선택됨, 사당'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색 화면은 최근 검색어를 탭해 빠르게 다시 검색한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );
    final searchHistoryRepository = FakeSearchHistoryRepository(['상록수', '사당']);

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          searchHistoryRepository: searchHistoryRepository,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('stationRecentSearchSection')),
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
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationRoleOrigin-station-sangnoksu')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationRoleDestination-station-sangnoksu')),
        findsOneWidget,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색 결과는 환승 노선 배지를 대표 노선과 추가 개수로 줄인다', (tester) async {
    final repository = FakeStationSearchRepository(
      nextResults: [
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
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '환승');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.text('4'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('경의중앙'), findsNothing);

    final resultTileSize = tester.getSize(
      find.byKey(const Key('stationSearchResult-station-transfer')),
    );
    expect(resultTileSize.height, lessThanOrEqualTo(112));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  });

  testWidgets('역 검색은 노선을 선택해 결과를 좁힌다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeStationSearchRepository(
      lineOptions: const [
        SubwayLineOption(
          id: 'seoul-4',
          name: '수도권 4호선',
          color: '#00A5DE',
          region: '수도권',
          lineCode: '4',
          active: true,
        ),
        SubwayLineOption(
          id: 'korail-gyeongui-jungang',
          name: '경의중앙선',
          color: '#75C5A1',
          region: '수도권',
          lineCode: '경의중앙',
          active: true,
        ),
        SubwayLineOption(
          id: 'inactive-line',
          name: '운행 중지 노선',
          color: '#777777',
          region: '수도권',
          lineCode: '중지',
          active: false,
        ),
      ],
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
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stationLineFilter-all')), findsOneWidget);
      expect(
        find.byKey(const Key('stationLineFilter-seoul-4')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationLineFilter-inactive-line')),
        findsNothing,
      );
      expect(find.text('운행 중지 노선'), findsNothing);
      expect(find.text('4'), findsOneWidget);
      expect(find.bySemanticsLabel('수도권 4호선 선택 안 됨'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stationLineFilter-seoul-4')));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('수도권 4호선 선택됨'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();

      expect(repository.requestedQueries, ['상록수']);
      expect(repository.requestedLineIds, ['seoul-4']);
      expect(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('stationLineFilter-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();

      expect(repository.requestedQueries, ['상록수', '상록수']);
      expect(repository.requestedLineIds, ['seoul-4', null]);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색은 검색 중 노선 선택을 바꾸지 않는다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final searchCompleter = Completer<List<StationSearchResult>>();
    final repository = FakeStationSearchRepository(
      lineOptions: const [
        SubwayLineOption(
          id: 'seoul-4',
          name: '수도권 4호선',
          color: '#00A5DE',
          region: '수도권',
          lineCode: '4',
          active: true,
        ),
        SubwayLineOption(
          id: 'korail-gyeongui-jungang',
          name: '경의중앙선',
          color: '#75C5A1',
          region: '수도권',
          lineCode: '경의중앙',
          active: true,
        ),
        SubwayLineOption(
          id: 'inactive-line',
          name: '운행 중지 노선',
          color: '#777777',
          region: '수도권',
          lineCode: '중지',
          active: false,
        ),
      ],
      searchCompleter: searchCompleter,
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('stationLineFilter-inactive-line')),
        findsNothing,
      );
      expect(find.text('운행 중지 노선'), findsNothing);

      await tester.tap(find.byKey(const Key('stationLineFilter-seoul-4')));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('수도권 4호선 선택됨')),
        isSemantics(
          label: '수도권 4호선 선택됨',
          isButton: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('stationLineFilter-korail-gyeongui-jungang')),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('수도권 4호선 선택됨'), findsOneWidget);
      expect(find.bySemanticsLabel('경의중앙선 선택 안 됨'), findsOneWidget);

      searchCompleter.complete([
        _stationResult(id: 'station-sangnoksu', name: '상록수'),
      ]);
      await tester.pumpAndSettle();

      expect(repository.requestedLineIds, ['seoul-4']);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색은 현재 위치 주변 역을 큰 버튼으로 찾고 거리를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final locationProvider = FakeCurrentLocationProvider(
      location: _freshCurrentLocation(),
      needsPermissionRequest: false,
    );
    final repository = FakeStationSearchRepository(
      nearbyResults: [
        _stationResult(
          id: 'station-sangnoksu',
          name: '상록수',
          distanceMeters: 230,
        ),
      ],
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          locationProvider: locationProvider,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nearbyStationSearchButton')));
      await tester.pumpAndSettle();

      expect(find.text('현재 위치 사용'), findsNothing);
      expect(locationProvider.requestCount, 1);
      expect(repository.requestedNearbyLocations.single.latitude, 37.3028);
      expect(repository.requestedNearbyLocations.single.longitude, 126.8665);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('현재 위치 기준 230m · 수도권 2호선'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '상록수역, 현재 위치 기준 230m, 수도권 2호선, 수도권, 기본 정보만 있음, 출처 공식 파일',
        ),
        findsOneWidget,
      );

      final nearbyButtonSize = tester.getSize(
        find.byKey(const Key('nearbyStationSearchButton')),
      );
      expect(nearbyButtonSize.height, greaterThanOrEqualTo(60));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색은 첫 위치 권한 요청 전에 사용 목적을 안내한다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      location: _freshCurrentLocation(),
    );
    final repository = FakeStationSearchRepository(
      nearbyResults: [
        _stationResult(
          id: 'station-sangnoksu',
          name: '상록수',
          distanceMeters: 230,
        ),
      ],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nearbyStationSearchButton')));
    await tester.pumpAndSettle();

    expect(locationProvider.permissionCheckCount, 1);
    expect(locationProvider.requestCount, 0);
    expect(find.text('현재 위치 사용'), findsOneWidget);
    expect(find.text('가까운 역 찾기와 시설 신고 위치 확인에만 현재 위치를 사용합니다.'), findsOneWidget);
    expect(
      find.text('위치 권한을 거부해도 역명 검색, 즐겨찾기, 접근성 정보 조회는 계속 사용할 수 있습니다.'),
      findsOneWidget,
    );

    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();

    expect(locationProvider.requestCount, 1);
    expect(repository.requestedNearbyLocations, hasLength(1));
    expect(find.text('상록수역'), findsOneWidget);
  });

  testWidgets('역 검색은 주변 역 확인 중 중복 탭을 무시한다', (tester) async {
    final locationCompleter = Completer<CurrentLocation>();
    final locationProvider = FakeCurrentLocationProvider(
      locationLoader: () => locationCompleter.future,
      needsPermissionRequest: false,
    );
    final repository = FakeStationSearchRepository(
      nearbyResults: [
        _stationResult(
          id: 'station-sangnoksu',
          name: '상록수',
          distanceMeters: 230,
        ),
      ],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nearbyStationSearchButton')));
    await tester.tap(find.byKey(const Key('nearbyStationSearchButton')));
    await tester.pump();

    expect(locationProvider.permissionCheckCount, 1);
    expect(locationProvider.requestCount, 1);

    locationCompleter.complete(_freshCurrentLocation());
    await tester.pumpAndSettle();

    expect(repository.requestedNearbyLocations, hasLength(1));
  });

  testWidgets('역 검색은 주변 역 확인 중 입력을 지워도 결과를 유지한다', (tester) async {
    final locationCompleter = Completer<CurrentLocation>();
    final locationProvider = FakeCurrentLocationProvider(
      locationLoader: () => locationCompleter.future,
      needsPermissionRequest: false,
    );
    final repository = FakeStationSearchRepository(
      nearbyResults: [
        _stationResult(
          id: 'station-sangnoksu',
          name: '상록수',
          distanceMeters: 230,
        ),
      ],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nearbyStationSearchButton')));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '');
    await tester.pump();

    locationCompleter.complete(_freshCurrentLocation());
    await tester.pumpAndSettle();

    expect(repository.requestedNearbyLocations, hasLength(1));
    expect(find.text('상록수역'), findsOneWidget);
    expect(find.text('현재 위치 기준 230m · 수도권 2호선'), findsOneWidget);
  });

  testWidgets('역 검색은 현재 위치를 확인하지 못하면 짧은 안내를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException('위치 권한을 확인해 주세요.'),
      needsPermissionRequest: false,
    );
    final repository = FakeStationSearchRepository();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          locationProvider: locationProvider,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nearbyStationSearchButton')));
      await tester.pumpAndSettle();

      expect(locationProvider.requestCount, 1);
      expect(repository.requestedNearbyLocations, isEmpty);
      expect(find.text('위치 권한을 확인해 주세요.'), findsOneWidget);
      expect(find.bySemanticsLabel('위치 권한을 확인해 주세요.'), findsOneWidget);
      expect(find.text('역명으로 검색하면 위치 권한 없이도 계속 이용할 수 있습니다.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('다음 행동, 역명으로 검색하면 위치 권한 없이도 계속 이용할 수 있습니다.'),
        findsOneWidget,
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역명 검색 빈 결과에는 위치 권한 대안 안내를 보여주지 않는다', (tester) async {
    final repository = FakeStationSearchRepository();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '없는역');
    await tester.pump();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(repository.requestedQueries, ['없는역']);
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);
    expect(find.text('역명으로 검색하면 위치 권한 없이도 계속 이용할 수 있습니다.'), findsNothing);
    expect(
      find.bySemanticsLabel('다음 행동, 역명으로 검색하면 위치 권한 없이도 계속 이용할 수 있습니다.'),
      findsNothing,
    );
  });

  testWidgets('역 검색은 GPS가 꺼져 있으면 위치 설정으로 이동할 수 있다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException(
        '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
      ),
      needsPermissionRequest: false,
    );
    final repository = FakeStationSearchRepository();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nearbyStationSearchButton')));
    await tester.pumpAndSettle();

    expect(find.text('기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
    expect(
      find.byKey(const Key('stationSearchOpenLocationSettingsButton')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('stationSearchOpenLocationSettingsButton')),
    );
    await tester.pumpAndSettle();

    expect(locationProvider.openSettingsCount, 1);
    expect(repository.requestedNearbyLocations, isEmpty);
  });

  testWidgets('역 검색 결과를 누르면 출구와 시설 상태를 쉬운 문구로 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(
        id: 'station-sangnoksu',
        name: '상록수',
        latitude: 37.302795,
        longitude: 126.866489,
      ),
      stationExits: const [
        StationExitInfo(
          id: 'exit-sangnoksu-1',
          stationId: 'station-sangnoksu',
          exitNumber: '1',
          name: '1번 출구',
          latitude: 37.3021,
          longitude: 126.8661,
          hasElevatorConnection: true,
          hasStairOnlyPath: false,
          dataConfidence: 'HIGH',
          dataSourceType: 'OFFICIAL_FILE',
          fieldValidationStatus: 'VERIFIED',
        ),
      ],
      stationFacilities: const [
        StationFacilityInfo(
          id: 'facility-sangnoksu-elevator-1',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-1',
          type: 'ELEVATOR',
          name: '1번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          latitude: 37.3022,
          longitude: 126.8662,
          description: '1번 출구 앞',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          dataSourceType: 'OFFICIAL_FILE',
          lastUpdatedAt: '2026-06-12',
          fieldValidationStatus: 'VERIFIED',
        ),
        StationFacilityInfo(
          id: 'facility-sangnoksu-elevator-2',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-2',
          type: 'ELEVATOR',
          name: '2번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '2번 출구 앞',
          status: 'BROKEN',
          dataConfidence: 'HIGH',
          dataSourceType: 'OFFICIAL_FILE',
          lastUpdatedAt: '2026-06-14',
          fieldValidationStatus: 'VERIFIED',
        ),
      ],
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();
      expect(find.text('기본 정보만 있음 · 출처 공식 파일'), findsOneWidget);
      expect(
        find.bySemanticsLabel('상록수역, 수도권 2호선, 수도권, 기본 정보만 있음, 출처 공식 파일'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      expect(repository.requestedDetailStationIds, ['station-sangnoksu']);
      expect(repository.requestedExitStationIds, ['station-sangnoksu']);
      expect(repository.requestedFacilityStationIds, ['station-sangnoksu']);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('수도권 2호선'), findsOneWidget);
      expect(find.text('기본 정보만 있음'), findsOneWidget);
      expect(find.text('출처 공식 파일'), findsWidgets);
      expect(find.text('마지막 확인 2026-06-13'), findsOneWidget);
      expect(find.text('이동 전 현장 안내와 역무원 안내를 확인해 주세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('안전 안내, 이동 전 현장 안내와 역무원 안내를 확인해 주세요.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '상록수역 상세 정보, 수도권 2호선, 기본 정보만 있음, 출처 공식 파일, 마지막 확인 2026-06-13',
        ),
        findsOneWidget,
      );
      expect(find.text('이동 구조'), findsOneWidget);
      expect(find.text('승강장'), findsOneWidget);
      expect(find.bySemanticsLabel('이동 구조, 1번 출구, 엘리베이터, 승강장'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('지도 위치 목록'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('지도 위치 목록'), findsOneWidget);
      expect(find.text('지도를 열 수 없어도 아래 위치 목록으로 확인할 수 있습니다.'), findsOneWidget);
      expect(find.text('상록수역'), findsWidgets);
      expect(find.text('1번 출구'), findsWidgets);
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('2번 출구'), findsNothing);
      expect(find.bySemanticsLabel('지도 대체 위치 목록'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('stationMapTextFallbackItem-station-sangnoksu')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          '상록수역 상세 정보, 수도권 2호선, 기본 정보만 있음, 출처 공식 파일, 마지막 확인 2026-06-13, 지도 위치',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('stationMapTextFallbackItem-exit-sangnoksu-1')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          '1번 출구, 엘리베이터 연결, 계단 없는 이동 가능, 현장 검증됨, 정보 신뢰도 높음, 출처 공식 파일, 지도 위치',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(
          const Key('stationMapTextFallbackItem-facility-sangnoksu-elevator-1'),
        ),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(
          '1번 출구 엘리베이터, 엘리베이터, 정상, 1번 출구 앞, 최근 확인 2026-06-12, 현장 검증됨, 정보 신뢰도 높음, 출처 공식 파일, 지도 위치',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('출구'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('출구'), findsOneWidget);
      expect(find.text('1번 출구'), findsWidgets);
      expect(find.text('엘리베이터 연결'), findsOneWidget);
      expect(find.text('계단 없는 이동 가능'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '1번 출구, 엘리베이터 연결, 계단 없는 이동 가능, 현장 검증됨, 정보 신뢰도 높음, 출처 공식 파일',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('시설'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('시설'), findsOneWidget);
      expect(find.text('확인 필요 1개'), findsOneWidget);
      expect(find.bySemanticsLabel('확인이 필요한 시설 1개'), findsOneWidget);
      expect(find.text('2번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('엘리베이터'), findsWidgets);
      expect(find.text('고장'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(
          const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
        ),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('정상'), findsOneWidget);
      expect(find.text('1번 출구 앞'), findsOneWidget);
      expect(find.text('최근 확인 2026-06-12'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '1번 출구 엘리베이터, 엘리베이터, 정상, 1번 출구 앞, 최근 확인 2026-06-12, 현장 검증됨, 정보 신뢰도 높음, 출처 공식 파일',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('1번 출구 엘리베이터 상태 신고'), findsOneWidget);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 상세에서 연 시설 신고는 앱에 주입한 사진 복구 대상을 저장한다', (tester) async {
    final repository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationFacilities: const [
        StationFacilityInfo(
          id: 'facility-sangnoksu-elevator-1',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-1',
          type: 'ELEVATOR',
          name: '1번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '1번 출구 앞',
          status: 'BROKEN',
          dataConfidence: 'HIGH',
          dataSourceType: 'OFFICIAL_FILE',
          lastUpdatedAt: '2026-06-14',
        ),
      ],
    );
    final draftTargetStore = MemoryFacilityReportDraftTargetStore();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        facilityReportDraftTargetStore: draftTargetStore,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportAddPhotoButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('facilityReportAddPhotoButton')));
    await tester.pump();
    await _continuePhotoUse(tester, settle: false);

    expect(draftTargetStore.saveCount, 1);
    expect(
      draftTargetStore.savedTargets.single.facilityId,
      'facility-sangnoksu-elevator-1',
    );
  });

  testWidgets('역 상세는 시설 목록이 없으면 확인 필요 요약을 숨긴다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationExits: const [
        StationExitInfo(
          id: 'exit-sangnoksu-1',
          stationId: 'station-sangnoksu',
          exitNumber: '1',
          name: '1번 출구',
          hasElevatorConnection: true,
          hasStairOnlyPath: false,
          dataConfidence: 'HIGH',
          dataSourceType: 'OFFICIAL_FILE',
        ),
      ],
      stationFacilities: const [],
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();

      expect(find.text('시설'), findsOneWidget);
      expect(find.text('시설 정보가 아직 없습니다.'), findsOneWidget);
      expect(find.text('확인 필요 없음'), findsNothing);
      expect(find.bySemanticsLabel('확인이 필요한 시설 없음'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 상세는 주입된 내부 이동 경로를 쉬운 단계 안내로 보여준다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );
    final internalRouteRepository = FakeInternalRouteRepository(
      result: _internalRouteResult(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          stationId: 'station-sangnoksu',
          internalRouteRepository: internalRouteRepository,
          internalRouteRequest: const InternalRouteRequest(
            stationId: 'station-sangnoksu',
            fromNodeId: 'node-sangnoksu-elevator-1',
            toNodeId: 'node-sangnoksu-faregate',
            mobilityType: 'WHEELCHAIR',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(internalRouteRepository.requests, hasLength(1));
    expect(find.text('내부 이동 안내'), findsOneWidget);
    expect(find.text('내부 이동 경로를 찾았습니다'), findsOneWidget);
    expect(find.text('1번 출구 엘리베이터에서 개찰구까지'), findsWidgets);
    expect(find.text('약 1분 15초 · 28m'), findsOneWidget);
    expect(find.text('엘리베이터에서 개찰구까지 이동합니다.'), findsOneWidget);
    expect(find.text('약 1분 15초 · 28m · 현장 검증 전 · 엘리베이터 필요'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '내부 이동 안내, 내부 이동 경로를 찾았습니다, 1번 출구 엘리베이터에서 개찰구까지, 약 1분 15초 · 28m, 이동 단계 1번 내부 이동, 1번 출구 엘리베이터에서 개찰구까지, 약 1분 15초 · 28m · 현장 검증 전 · 엘리베이터 필요, 엘리베이터에서 개찰구까지 이동합니다.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('앱 역 검색 흐름은 내부 이동 노드로 기본 안내를 표시한다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );
    final internalRouteRepository = FakeInternalRouteRepository(
      nodes: _internalRouteNodes(),
      result: _internalRouteResult(),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        internalRouteRepository: internalRouteRepository,
        initialOnboardingState: _completedOnboardingState(
          profileId: 'wheelchair',
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();

    expect(internalRouteRepository.nodeStationIds, ['station-sangnoksu']);
    expect(internalRouteRepository.requests, hasLength(1));
    expect(
      internalRouteRepository.requests.single.fromNodeId,
      'node-sangnoksu-elevator-1',
    );
    expect(
      internalRouteRepository.requests.single.toNodeId,
      'node-sangnoksu-faregate',
    );
    expect(internalRouteRepository.requests.single.mobilityType, 'WHEELCHAIR');
    expect(find.text('내부 이동 안내'), findsOneWidget);
    expect(find.text('내부 이동 경로를 찾았습니다'), findsOneWidget);
  });

  testWidgets('역 상세는 현재 역을 즐겨찾기에 저장하고 해제한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final favoriteRepository = FakeFavoriteStationRepository();
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: favoriteRepository,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, '즐겨찾기 저장'), findsOneWidget);
      expect(find.bySemanticsLabel('상록수역 즐겨찾기 저장'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stationFavoriteToggleButton')));
      await tester.pumpAndSettle();

      expect(favoriteRepository.savedStationIds, ['station-sangnoksu']);
      expect(find.text('즐겨찾기에 저장했습니다.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '즐겨찾기 해제'), findsOneWidget);
      expect(find.bySemanticsLabel('상록수역 즐겨찾기 해제'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stationFavoriteToggleButton')));
      await tester.pumpAndSettle();

      expect(favoriteRepository.removedStationIds, ['station-sangnoksu']);
      expect(find.text('즐겨찾기에서 해제했습니다.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '즐겨찾기 저장'), findsOneWidget);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('검색 결과의 저장된 역은 상세에서 해제 버튼으로 시작한다', (tester) async {
    final favoriteRepository = FakeFavoriteStationRepository(
      favorites: [_favoriteStation(id: 'station-sangnoksu', name: '상록수')],
    );
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: favoriteRepository,
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '즐겨찾기 해제'), findsOneWidget);
    expect(find.bySemanticsLabel('상록수역 즐겨찾기 해제'), findsOneWidget);
  });

  testWidgets('역 상세는 즐겨찾기 확인을 기다리지 않고 열린다', (tester) async {
    final favoriteRepository = ControlledFavoriteStationRepository();
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: favoriteRepository,
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(
      find.bySemanticsLabel(
        '상록수역 상세 정보, 수도권 2호선, 기본 정보만 있음, 출처 공식 파일, 마지막 확인 2026-06-13',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, '확인 중'), findsOneWidget);

    favoriteRepository.complete([
      _favoriteStation(id: 'station-sangnoksu', name: '상록수'),
    ]);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '즐겨찾기 해제'), findsOneWidget);
  });

  testWidgets('즐겨찾기 목록은 상세에서 해제하고 돌아오면 다시 불러온다', (tester) async {
    final favoriteRepository = FakeFavoriteStationRepository(
      favorites: [_favoriteStation(id: 'station-sangnoksu', name: '상록수')],
    );
    final stationRepository = FakeStationSearchRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: favoriteRepository,
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openFavoriteList(
      tester,
      tabKey: const Key('favoriteStationsTabButton'),
    );
    await tester.tap(
      find.byKey(const Key('favoriteStationTile-station-sangnoksu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationFavoriteToggleButton')));
    await tester.pumpAndSettle();

    expect(favoriteRepository.removedStationIds, ['station-sangnoksu']);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('저장한 역이 없습니다.'), findsOneWidget);
    expect(
      find.byKey(const Key('favoriteStationTile-station-sangnoksu')),
      findsNothing,
    );
  });

  testWidgets('검색 요청 중에는 검색 버튼을 비활성화한다', (tester) async {
    final repository = ControlledStationSearchRepository();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
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
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openMobilityProfileFromSettings(tester);

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

  testWidgets('홈 이동 조건 화면은 저장된 profile을 선택 상태로 연다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(
            profileId: 'wheelchair',
          ),
        ),
      );

      await _openMobilityProfileFromSettings(tester);

      expect(find.bySemanticsLabel('휠체어 선택됨, 계단 없는 길만 안내해요'), findsOneWidget);
      expect(find.text('휠체어 조건을 선택했습니다'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈에서 바꾼 이동 조건은 재시작 뒤 다음 경로 요청에 반영된다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeRepository = FakeRouteSearchRepository();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: _completedOnboardingState().result,
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openMobilityProfileFromSettings(tester);
    await tester.tap(find.byKey(const Key('mobilityProfileCard-wheelchair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityProfileDoneButton')));
    await tester.pumpAndSettle();

    expect(onboardingStore.savedResult?.profile.mobilityType, 'WHEELCHAIR');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routeSearchButton')));
    await tester.pumpAndSettle();
    expect(find.text('휠체어'), findsOneWidget);

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

    expect(routeRepository.requests.single.mobilityType, 'WHEELCHAIR');
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
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: routeRepository,
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('routeSearchButton')));
      await tester.pumpAndSettle();

      expect(find.text('경로 검색'), findsOneWidget);
      expect(find.text('출발역'), findsOneWidget);
      expect(find.text('도착역'), findsOneWidget);
      expect(find.text('출발역 ID'), findsNothing);
      expect(find.text('도착역 ID'), findsNothing);
      expect(find.text('적용 중인 이동 조건'), findsOneWidget);
      expect(find.text('고령자'), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);

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
          find.bySemanticsLabel('출발역 선택, 상록수, 수도권 2호선, 수도권, 기본 정보만 있음'),
        ),
        isSemantics(
          label: '출발역 선택, 상록수, 수도권 2호선, 수도권, 기본 정보만 있음',
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
      expect(find.text('추천 경로 1개'), findsOneWidget);
      expect(find.text('시설 상태와 신뢰도를 함께 계산했어요'), findsOneWidget);
      expect(find.text('이동 편한 순'), findsNothing);
      expect(find.text('짧은 시간 순'), findsNothing);
      expect(find.text('환승 적은 순'), findsNothing);
      expect(find.text('상록수 → 사당'), findsOneWidget);
      expect(find.text('고령자 · 계단 회피 · 쉬운 환승'), findsOneWidget);
      expect(find.text('7분'), findsOneWidget);
      expect(find.text('환승 없음 · 이동 300m'), findsOneWidget);
      expect(find.text('가장 추천'), findsOneWidget);
      expect(find.text('이동 편함 92점'), findsOneWidget);
      expect(find.text('추천 이유'), findsOneWidget);
      expect(find.text('엘리베이터 동선을 우선했어요'), findsOneWidget);
      expect(find.text('계단 없는 출구를 확인했어요'), findsOneWidget);
      expect(find.text('천천히 이동하기 쉬운 동선을 확인했어요'), findsOneWidget);
      expect(find.text('도착 안내'), findsOneWidget);
      expect(find.text('2번 출구의 엘리베이터를 먼저 확인하세요.'), findsOneWidget);
      expect(find.text('이동 순서'), findsOneWidget);
      expect(find.byKey(const Key('routeStepNumber-1')), findsOneWidget);
      expect(find.text('열차 이동'), findsOneWidget);
      expect(
        find.text('선택된 경로 edge:edge-sangnoksu-sadang 근거로 안내합니다.'),
        findsOneWidget,
      );
      expect(find.text('시간 정적 추정 · 거리 측정값 · 높은 신뢰도'), findsOneWidget);
      expect(find.text('상록수역에서 4호선 승강장으로 이동'), findsOneWidget);
      expect(find.text('약 4분 · 180m · 접근성 확인'), findsOneWidget);
      expect(find.text('일부 시설 정보는 확인이 필요합니다.'), findsOneWidget);
      expect(
        find.text('접근성 시설 정보가 최근 30일 이내 확인되지 않았습니다. 이동 전 역 상세 정보를 확인하세요.'),
        findsOneWidget,
      );
      expect(find.text('왜 가장 빠른 길이 첫 번째가 아닌가요?'), findsOneWidget);
      expect(find.text('계단과 시설 상태, 걷는 거리를 먼저 고려했어요.'), findsOneWidget);
      expect(find.text('안전 안내'), findsOneWidget);
      expect(find.text('이동 전 현장 안내와 역무원 안내를 확인해 주세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '경로 검색 결과, 이동할 수 있는 경로, 고령자, 상록수에서 사당까지, 수도권 4호선, 이동 점수 92점, 주의 확인, '
          '추천 이유 엘리베이터 동선을 우선했어요, 계단 없는 출구를 확인했어요, 천천히 이동하기 쉬운 동선을 확인했어요, '
          '도착 안내 2번 출구의 엘리베이터를 먼저 확인하세요., '
          '주의 일부 시설 정보는 확인이 필요합니다., 접근성 시설 정보가 최근 30일 이내 확인되지 않았습니다. 이동 전 역 상세 정보를 확인하세요., '
          '이동 안내 1번 열차 이동, 엘리베이터를 이용해 승강장으로 이동합니다., 선택된 경로 edge:edge-sangnoksu-sadang 근거로 안내합니다., 약 4분 · 180m · 접근성 확인, 시간 정적 추정, 거리 측정값, 높은 신뢰도, 근거 edge:edge-sangnoksu-sadang, '
          '안전 안내 이동 전 현장 안내와 역무원 안내를 확인해 주세요.',
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

  testWidgets('경로 검색 단순 보기를 끄면 화면에서 이동 조건을 바꿀 수 있다', (tester) async {
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
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingStateWithPreferences(
          preferences: const OnboardingViewPreferences(
            largeTextEnabled: true,
            highContrastEnabled: false,
            simpleViewEnabled: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchButton')));
    await tester.pumpAndSettle();

    expect(find.text('이동 조건'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('휠체어').last);
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

    expect(routeRepository.requests.single.mobilityType, 'WHEELCHAIR');
  });

  testWidgets('경로 검색 단순 보기에서도 이동 조건을 바꿀 수 있다', (tester) async {
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
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchButton')));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('고령자'), findsOneWidget);

    await tester.tap(find.byKey(const Key('routeSimpleMobilityTypeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeMobilityOption-WHEELCHAIR')));
    await tester.pumpAndSettle();

    expect(find.text('휠체어'), findsOneWidget);

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

    expect(routeRepository.requests.single.mobilityType, 'WHEELCHAIR');
  });

  testWidgets('경로 검색 단순 보기 이동 조건은 스크린리더로도 바꿀 수 있다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('routeSearchButton')));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.bySemanticsLabel('이동 조건 바꾸기, 현재 고령자')),
        isSemantics(
          label: '이동 조건 바꾸기, 현재 고령자',
          isButton: true,
          hasTapAction: true,
        ),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('경로 검색 결과는 이동 가능한 경로만 즐겨찾기에 저장한다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final favoriteRouteRepository = FakeFavoriteRouteRepository();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteRouteRepository: favoriteRouteRepository,
        initialOnboardingState: _completedOnboardingState(),
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

    expect(find.bySemanticsLabel('자주 쓰는 경로 저장'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('routeFavoriteSaveButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeFavoriteSaveButton')));
    await tester.pumpAndSettle();

    expect(favoriteRouteRepository.savedRouteSearchIds, ['route-1']);
    expect(find.text('자주 쓰는 경로에 저장했습니다.'), findsOneWidget);
  });

  testWidgets('즐겨찾기 경로 저장 실패는 다음 행동을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final favoriteRouteRepository = FakeFavoriteRouteRepository()
      ..error = const FavoriteRouteException('즐겨찾기 경로를 처리하지 못했습니다.');

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          favoriteRouteRepository: favoriteRouteRepository,
          initialOnboardingState: _completedOnboardingState(),
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

      await tester.ensureVisible(
        find.byKey(const Key('routeFavoriteSaveButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routeFavoriteSaveButton')));
      await tester.pumpAndSettle();

      expect(find.text('즐겨찾기 경로를 처리하지 못했습니다.'), findsOneWidget);
      expect(
        find.text('네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('다음 행동, 네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('favoriteRouteSaveFailureNextAction')),
        ),
        isSemantics(
          label: '다음 행동, 네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요.',
          isLiveRegion: true,
        ),
      );
    } finally {
      semanticsHandle.dispose();
    }

    expect(favoriteRouteRepository.savedRouteSearchIds, ['route-1']);
  });

  testWidgets('경로 검색 결과는 큰 버튼으로 추천 피드백을 보낸다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeFeedbackRepository = FakeRouteFeedbackRepository();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        routeFeedbackRepository: routeFeedbackRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
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

    await tester.ensureVisible(
      find.byKey(const Key('routeFeedbackHelpfulButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeFeedbackHelpfulButton')));
    await tester.pumpAndSettle();

    expect(routeFeedbackRepository.requests, hasLength(1));
    expect(routeFeedbackRepository.requests.single.routeSearchId, 'route-1');
    expect(
      routeFeedbackRepository.requests.single.rating,
      RouteFeedbackRating.helpful,
    );
    expect(routeFeedbackRepository.requests.single.comment, '추천이 도움이 됐어요');
    expect(find.text('의견을 보냈습니다.'), findsOneWidget);

    final helpfulButton = tester.widget<FilledButton>(
      find.byKey(const Key('routeFeedbackHelpfulButton')),
    );
    expect(helpfulButton.onPressed, isNull);
  });

  testWidgets('경로 피드백 실패는 다음 행동을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeFeedbackRepository = FakeRouteFeedbackRepository()
      ..error = const RouteFeedbackException('의견을 보내지 못했습니다.');

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          routeFeedbackRepository: routeFeedbackRepository,
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
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

      await tester.ensureVisible(
        find.byKey(const Key('routeFeedbackNotHelpfulButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routeFeedbackNotHelpfulButton')));
      await tester.pumpAndSettle();

      expect(find.text('의견을 보내지 못했습니다.'), findsOneWidget);
      expect(find.text('잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('다음 행동, 잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('routeFeedbackFailureNextAction')),
        ),
        isSemantics(
          label: '다음 행동, 잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요.',
          isLiveRegion: true,
        ),
      );
    } finally {
      semanticsHandle.dispose();
    }

    expect(
      routeFeedbackRepository.requests.single.rating,
      RouteFeedbackRating.notHelpful,
    );
    expect(find.text('의견을 보내지 못했습니다.'), findsOneWidget);
  });

  testWidgets('경로 안내 칩은 좁은 화면과 큰 글자에서도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });

    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeRepository = FakeRouteSearchRepository(
      result: _sampleRouteSearchResult(
        status: 'REVIEW_REQUIRED',
        mobilityType: 'UNKNOWN_MOBILITY_TYPE',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
          stationRepository: stationRepository,
          initialMobilityType: 'SENIOR',
        ),
      ),
    );

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

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('routeGuidanceMobilityChip')), findsOneWidget);
    expect(find.text('이동 조건 확인 필요'), findsOneWidget);
  });

  testWidgets('경로 검색은 입력만 하고 선택하지 않은 역을 쉬운 문구로 안내한다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
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
    expect(find.text('역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.'), findsNothing);
  });

  testWidgets('경로 검색 실패는 다음 행동을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeRepository = FakeRouteSearchRepository(
      error: const RouteSearchException('경로 정보를 불러오지 못했습니다.'),
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: routeRepository,
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
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

      expect(routeRepository.requests, hasLength(1));
      expect(find.text('경로 정보를 불러오지 못했습니다.'), findsOneWidget);
      expect(
        find.text('역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('다음 행동, 역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('routeSearchFailureNextAction')),
        ),
        isSemantics(
          label: '다음 행동, 역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.',
          isLiveRegion: true,
        ),
      );
    } finally {
      semanticsHandle.dispose();
    }
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
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
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

    expect(find.text('상록수 → 사당'), findsOneWidget);

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

    expect(find.text('상록수 → 사당'), findsNothing);
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
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: routeRepository,
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
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

      expect(find.text('다른 경로가 필요합니다'), findsOneWidget);
      expect(
        find.byKey(const Key('routeGuidanceMobilityChip')),
        findsOneWidget,
      );
      expect(find.text('안내할 수 있는 경로가 없습니다'), findsOneWidget);
      expect(find.text('추천 이유'), findsNothing);
      expect(find.text('엘리베이터 동선을 우선했어요'), findsNothing);
      expect(find.text('휠체어로 이동 가능한 엘리베이터가 없습니다.'), findsOneWidget);
      expect(find.text('이동 전 현장 안내와 역무원 안내를 확인해 주세요.'), findsOneWidget);
      expect(
        find.text('역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.'),
        findsOneWidget,
      );
      final nextActionNotice = find.byKey(
        const Key('routeBlockedNextActionNotice'),
      );
      expect(nextActionNotice, findsOneWidget);
      expect(tester.getSize(nextActionNotice).height, greaterThanOrEqualTo(44));
      expect(
        find.bySemanticsLabel('다음 행동, 역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.'),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(
          '경로 검색 결과, 다른 경로가 필요합니다, 휠체어, 상록수에서 없는역까지, 노선 확인 필요, 이동 점수 0점, '
          '안내 불가 이유 휠체어로 이동 가능한 엘리베이터가 없습니다., '
          '다음 행동 역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요., '
          '안전 안내 이동 전 현장 안내와 역무원 안내를 확인해 주세요.',
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

  testWidgets('시설 신고 화면은 신고 유형과 내용을 보내고 접수 결과를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final reportRepository = FakeFacilityReportRepository();
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationFacilities: const [
        StationFacilityInfo(
          id: 'facility-sangnoksu-elevator-1',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-1',
          type: 'ELEVATOR',
          name: '1번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '1번 출구 앞',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-06-12',
        ),
      ],
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: stationRepository,
          reportRepository: reportRepository,
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          locationProvider: FakeCurrentLocationProvider(
            location: const CurrentLocation(
              latitude: 37.302421,
              longitude: 126.866221,
            ),
            needsPermissionRequest: false,
          ),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(
          const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('시설 신고'), findsOneWidget);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('무엇을 알려드릴까요?'), findsOneWidget);
      expect(find.bySemanticsLabel('고장 선택됨'), findsOneWidget);

      await tester.tap(find.byKey(const Key('facilityReportType-CLOSED')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('facilityReportDescriptionInput')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('facilityReportDescriptionInput')),
        '출입문이 막혀 있습니다.',
      );
      expect(
        find.byKey(const Key('facilityReportPhotoUrlInput')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
      await tester.pumpAndSettle();

      expect(find.text('사진·위치 확인'), findsOneWidget);
      await tester.tap(find.text('보내기'));
      await tester.pumpAndSettle();

      expect(reportRepository.requests, hasLength(1));
      expect(reportRepository.requests.single.stationId, 'station-sangnoksu');
      expect(
        reportRepository.requests.single.facilityId,
        'facility-sangnoksu-elevator-1',
      );
      expect(reportRepository.requests.single.reportType, 'CLOSED');
      expect(reportRepository.requests.single.description, '출입문이 막혀 있습니다.');
      expect(reportRepository.requests.single.photoFileName, isNull);
      expect(reportRepository.requests.single.photoContentType, isNull);
      expect(reportRepository.requests.single.photoDataBase64, isNull);
      expect(find.text('신고가 접수되었습니다.'), findsOneWidget);
      expect(find.bySemanticsLabel('신고가 접수되었습니다.'), findsOneWidget);
      expect(find.text('접수번호'), findsOneWidget);
      expect(find.text('report-1'), findsOneWidget);
      expect(find.text('처리 상태'), findsOneWidget);
      expect(find.text('접수됨'), findsOneWidget);
      expect(
        find.bySemanticsLabel('신고 접수번호 report-1, 현재 상태 접수됨'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('facilityReportPhotoUrlInput')),
        findsNothing,
      );

      reportRepository.nextReportStatus = 'ACCEPTED';
      await tester.ensureVisible(
        find.byKey(const Key('facilityReportRefreshButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('facilityReportRefreshButton')));
      await tester.pumpAndSettle();

      expect(reportRepository.loadedReportIds, ['report-1']);
      expect(find.text('처리 상태를 확인했습니다.'), findsOneWidget);
      expect(find.text('반영됨'), findsOneWidget);
      expect(
        find.bySemanticsLabel('신고 접수번호 report-1, 현재 상태 반영됨'),
        findsOneWidget,
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('시설 신고 실패는 다음 행동을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final reportRepository = FakeFacilityReportRepository()
      ..error = const FacilityReportException('신고를 보내지 못했습니다.');

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: FacilityReportScreen(
            repository: reportRepository,
            target: const FacilityReportTarget(
              stationId: 'station-sangnoksu',
              stationName: '상록수',
              facilityId: 'facility-sangnoksu-elevator-1',
              facilityName: '1번 출구 엘리베이터',
              facilityTypeLabel: '엘리베이터',
              facilityStatusLabel: '정상',
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('facilityReportDescriptionInput')),
        '출입문이 막혀 있습니다.',
      );
      await tester.dragUntilVisible(
        find.byKey(const Key('facilityReportSubmitButton')),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
      await tester.pumpAndSettle();

      expect(reportRepository.requests, hasLength(1));
      expect(find.text('신고를 보내지 못했습니다.'), findsOneWidget);
      expect(find.text('내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('다음 행동, 내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('facilityReportFailureNextAction')),
        ),
        isSemantics(
          label: '다음 행동, 내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요.',
          isLiveRegion: true,
        ),
      );
      expect(
        find.byKey(const Key('facilityReportRefreshButton')),
        findsNothing,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('시설 신고 화면은 사진 선택 전에 짧은 개인정보 안내를 보여준다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    var pickerCallCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          locationLoader: () async => const FacilityReportLocation(
            latitude: 37.302421,
            longitude: 126.866221,
          ),
          needsLocationPermissionRequest: () async => false,
          photoPicker: () async {
            pickerCallCount++;
            return const FacilityReportPhotoAttachment(
              fileName: 'elevator-door.jpg',
              contentType: 'image/jpeg',
              dataBase64: 'aW1hZ2UtYnl0ZXM=',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportAddPhotoButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('facilityReportAddPhotoButton')));
    await tester.pumpAndSettle();

    expect(find.text('사진 확인'), findsOneWidget);
    expect(find.text('사진은 신고 확인에만 사용됩니다.'), findsOneWidget);
    expect(find.text('얼굴이나 전화번호가 보이면 가려 주세요.'), findsOneWidget);
    expect(pickerCallCount, 0);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(find.text('사진 1장 추가됨'), findsNothing);
    expect(pickerCallCount, 0);

    await tester.tap(find.byKey(const Key('facilityReportAddPhotoButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();

    expect(pickerCallCount, 1);
    expect(find.text('사진 1장 추가됨'), findsOneWidget);
  });

  testWidgets('시설 신고 화면은 사진 확인 중 빠른 중복 탭을 무시한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    var pickerCallCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          locationLoader: () async => const FacilityReportLocation(
            latitude: 37.302421,
            longitude: 126.866221,
          ),
          needsLocationPermissionRequest: () async => false,
          photoPicker: () async {
            pickerCallCount++;
            return const FacilityReportPhotoAttachment(
              fileName: 'elevator-door.jpg',
              contentType: 'image/jpeg',
              dataBase64: 'aW1hZ2UtYnl0ZXM=',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportAddPhotoButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final addPhotoButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('facilityReportAddPhotoButton')),
    );
    addPhotoButton.onPressed!();
    addPhotoButton.onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('사진 확인'), findsOneWidget);

    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();

    expect(pickerCallCount, 1);
    expect(find.text('사진 확인'), findsNothing);
    expect(find.text('사진 1장 추가됨'), findsOneWidget);
  });

  testWidgets('시설 신고 화면은 사진을 직접 추가해서 보낸다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final reportRepository = FakeFacilityReportRepository();

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: FacilityReportScreen(
            repository: reportRepository,
            target: const FacilityReportTarget(
              stationId: 'station-sangnoksu',
              stationName: '상록수',
              facilityId: 'facility-sangnoksu-elevator-1',
              facilityName: '1번 출구 엘리베이터',
              facilityTypeLabel: '엘리베이터',
              facilityStatusLabel: '정상',
            ),
            locationLoader: () async => const FacilityReportLocation(
              latitude: 37.302421,
              longitude: 126.866221,
            ),
            needsLocationPermissionRequest: () async => false,
            photoPicker: () async => const FacilityReportPhotoAttachment(
              fileName: 'elevator-door.jpg',
              contentType: 'image/jpeg',
              dataBase64: 'aW1hZ2UtYnl0ZXM=',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('facilityReportPhotoUrlInput')),
        findsNothing,
      );
      await tester.dragUntilVisible(
        find.byKey(const Key('facilityReportAddPhotoButton')),
        find.byType(Scrollable).first,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('사진 추가'), findsOneWidget);

      await tester.tap(find.byKey(const Key('facilityReportAddPhotoButton')));
      await tester.pumpAndSettle();
      await _continuePhotoUse(tester);

      expect(find.text('사진 1장 추가됨'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('facilityReportDescriptionInput')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('facilityReportDescriptionInput')),
        '문이 열리지 않습니다.',
      );
      await tester.ensureVisible(
        find.byKey(const Key('facilityReportSubmitButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('보내기'));
      await tester.pumpAndSettle();

      expect(reportRepository.requests, hasLength(1));
      expect(
        reportRepository.requests.single.photoFileName,
        'elevator-door.jpg',
      );
      expect(reportRepository.requests.single.photoContentType, 'image/jpeg');
      expect(
        reportRepository.requests.single.photoDataBase64,
        'aW1hZ2UtYnl0ZXM=',
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('시설 신고 화면은 복구된 사진을 첨부 상태로 보여준다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    var restoreCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          lostPhotoRestorer: () async {
            restoreCount++;
            return const FacilityReportPhotoAttachment(
              fileName: 'restored-photo.webp',
              contentType: 'image/webp',
              dataBase64: 'cmVzdG9yZWQ=',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(restoreCount, 1);
    await tester.dragUntilVisible(
      find.bySemanticsLabel('사진 1장 추가됨'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('사진 1장 추가됨'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('facilityReportDescriptionInput')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '선택했던 사진입니다.',
    );
    await tester.ensureVisible(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.text('사진·위치 확인'), findsOneWidget);
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();

    expect(reportRepository.requests, hasLength(1));
    expect(
      reportRepository.requests.single.photoFileName,
      'restored-photo.webp',
    );
    expect(reportRepository.requests.single.photoContentType, 'image/webp');
    expect(reportRepository.requests.single.photoDataBase64, 'cmVzdG9yZWQ=');
  });

  testWidgets('시설 신고 화면은 사진 선택 전 대상 정보를 저장하고 정상 복귀하면 지운다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final draftTargetStore = MemoryFacilityReportDraftTargetStore();

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-toilet-1',
            facilityName: '장애인 화장실',
            facilityTypeLabel: '장애인 화장실',
            facilityStatusLabel: '확인 필요',
          ),
          draftTargetStore: draftTargetStore,
          photoPicker: () async => const FacilityReportPhotoAttachment(
            fileName: 'toilet-door.jpg',
            contentType: 'image/jpeg',
            dataBase64: 'cGhvdG8=',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportAddPhotoButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('facilityReportAddPhotoButton')));
    await tester.pumpAndSettle();
    await _continuePhotoUse(tester);

    expect(draftTargetStore.saveCount, 1);
    expect(draftTargetStore.clearCount, 1);
    expect(
      draftTargetStore.savedTargets.single.facilityId,
      'facility-sangnoksu-toilet-1',
    );
    expect(draftTargetStore.target, isNull);
    expect(find.text('사진 1장 추가됨'), findsOneWidget);
  });

  testWidgets('앱은 재시작 후 복구된 사진을 저장된 시설 신고 화면에 연결한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final draftTargetStore = MemoryFacilityReportDraftTargetStore(
      const FacilityReportTarget(
        stationId: 'station-sangnoksu',
        stationName: '상록수',
        facilityId: 'facility-sangnoksu-toilet-1',
        facilityName: '장애인 화장실',
        facilityTypeLabel: '장애인 화장실',
        facilityStatusLabel: '확인 필요',
      ),
    );
    var restoreCount = 0;

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: reportRepository,
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        locationProvider: FakeCurrentLocationProvider(
          location: const CurrentLocation(
            latitude: 37.302421,
            longitude: 126.866221,
          ),
          needsPermissionRequest: false,
        ),
        facilityReportDraftTargetStore: draftTargetStore,
        facilityReportLostPhotoRestorer: () async {
          restoreCount++;
          return const FacilityReportPhotoAttachment(
            fileName: 'restored-toilet.webp',
            contentType: 'image/webp',
            dataBase64: 'cmVzdG9yZWQ=',
          );
        },
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(restoreCount, 1);
    expect(draftTargetStore.clearCount, 1);
    expect(find.text('시설 신고'), findsOneWidget);
    expect(
      find.bySemanticsLabel('상록수역, 장애인 화장실, 장애인 화장실, 현재 확인 필요'),
      findsOneWidget,
    );

    await tester.dragUntilVisible(
      find.bySemanticsLabel('사진 1장 추가됨'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('사진 1장 추가됨'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('facilityReportDescriptionInput')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '앱 재시작 후 복구된 사진입니다.',
    );
    await tester.ensureVisible(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();

    expect(reportRepository.requests, hasLength(1));
    expect(reportRepository.requests.single.stationId, 'station-sangnoksu');
    expect(
      reportRepository.requests.single.facilityId,
      'facility-sangnoksu-toilet-1',
    );
    expect(
      reportRepository.requests.single.photoFileName,
      'restored-toilet.webp',
    );
  });

  testWidgets('앱은 사진 복구 대상 정리에 실패해도 복구 화면을 연다', (tester) async {
    final reportedErrors = <FlutterErrorDetails>[];
    final draftTargetStore = MemoryFacilityReportDraftTargetStore(
      const FacilityReportTarget(
        stationId: 'station-sangnoksu',
        stationName: '상록수',
        facilityId: 'facility-sangnoksu-toilet-1',
        facilityName: '장애인 화장실',
        facilityTypeLabel: '장애인 화장실',
        facilityStatusLabel: '확인 필요',
      ),
    )..throwOnClear = true;

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          locationProvider: FakeCurrentLocationProvider(
            location: const CurrentLocation(
              latitude: 37.302421,
              longitude: 126.866221,
            ),
            needsPermissionRequest: false,
          ),
          facilityReportDraftTargetStore: draftTargetStore,
          facilityReportLostPhotoRestorer: () async {
            return const FacilityReportPhotoAttachment(
              fileName: 'restored-toilet.webp',
              contentType: 'image/webp',
              dataBase64: 'cmVzdG9yZWQ=',
            );
          },
          initialOnboardingState: _completedOnboardingState(),
        ),
      );
      await tester.pumpAndSettle();
    });

    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, isA<StateError>());
    expect(draftTargetStore.clearCount, 1);
    expect(find.text('시설 신고'), findsOneWidget);
    await tester.dragUntilVisible(
      find.bySemanticsLabel('사진 1장 추가됨'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('사진 1장 추가됨'), findsOneWidget);
  });

  testWidgets('시설 신고 화면은 사진과 위치를 보내기 전에 공개 범위를 안내한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          locationLoader: () async => const FacilityReportLocation(
            latitude: 37.302421,
            longitude: 126.866221,
          ),
          needsLocationPermissionRequest: () async => false,
          photoPicker: () async => const FacilityReportPhotoAttachment(
            fileName: 'elevator-door.jpg',
            contentType: 'image/jpeg',
            dataBase64: 'aW1hZ2UtYnl0ZXM=',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportAddPhotoButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('facilityReportAddPhotoButton')));
    await tester.pumpAndSettle();
    await _continuePhotoUse(tester);

    await tester.ensureVisible(
      find.byKey(const Key('facilityReportDescriptionInput')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '문 앞에 안내문이 붙어 있습니다.',
    );
    await tester.ensureVisible(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.text('사진·위치 확인'), findsOneWidget);
    expect(find.text('사진과 신고 위치는 시설 신고 확인과 운영 검수에만 사용됩니다.'), findsOneWidget);
    expect(
      find.text('신고 내용은 접수 담당자에게 전달되며 앱 사용자에게 공개되지 않습니다.'),
      findsOneWidget,
    );
    expect(find.text('사진 확인'), findsNothing);
    expect(reportRepository.requests, isEmpty);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(reportRepository.requests, isEmpty);

    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();

    expect(reportRepository.requests, hasLength(1));
    expect(reportRepository.requests.single.photoFileName, 'elevator-door.jpg');
    expect(reportRepository.requests.single.latitude, 37.302421);
    expect(reportRepository.requests.single.longitude, 126.866221);
  });

  testWidgets('시설 신고 화면은 진입하면 현재 위치를 자동으로 확인한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    var requestCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          locationLoader: () async {
            requestCount++;
            return const FacilityReportLocation(
              latitude: 37.302421,
              longitude: 126.866221,
            );
          },
          needsLocationPermissionRequest: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(find.text('현재 위치 사용'), findsNothing);
    expect(find.text('현재 위치로 가까운 역을 찾습니다.'), findsNothing);
    expect(
      find.byKey(const Key('facilityReportRetryLocationButton')),
      findsNothing,
    );
  });

  testWidgets('시설 신고 화면은 첫 위치 권한 요청 전에 사용 목적을 안내한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    var requestCount = 0;
    var permissionCheckCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          needsLocationPermissionRequest: () async {
            permissionCheckCount++;
            return true;
          },
          locationLoader: () async {
            requestCount++;
            return const FacilityReportLocation(
              latitude: 37.302421,
              longitude: 126.866221,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(permissionCheckCount, 1);
    expect(requestCount, 0);
    expect(find.text('현재 위치 사용'), findsOneWidget);
    expect(find.text('가까운 역 찾기와 시설 신고 위치 확인에만 현재 위치를 사용합니다.'), findsOneWidget);
    expect(
      find.text('위치 권한을 거부해도 역명 검색, 즐겨찾기, 접근성 정보 조회는 계속 사용할 수 있습니다.'),
      findsOneWidget,
    );
    expect(find.text('현재 위치 첨부됨'), findsNothing);

    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();

    expect(requestCount, 1);

    await tester.ensureVisible(
      find.byKey(const Key('facilityReportDescriptionInput')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '권한 요청 후 바로 확인된 위치입니다.',
    );
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.text('사진·위치 확인'), findsOneWidget);
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();

    expect(reportRepository.requests, hasLength(1));
    expect(reportRepository.requests.single.latitude, 37.302421);
    expect(reportRepository.requests.single.longitude, 126.866221);
  });

  testWidgets('시설 신고 화면은 위치 재확인 중 중복 탭을 무시한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    var requestCount = 0;
    final retryCompleter = Completer<FacilityReportLocation>();

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          locationLoader: () async {
            requestCount++;
            if (requestCount == 1) {
              throw const FacilityReportLocationException(
                '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
              );
            }
            if (requestCount == 2) {
              return retryCompleter.future;
            }
            return const FacilityReportLocation(
              latitude: 37.302421,
              longitude: 126.866221,
            );
          },
          needsLocationPermissionRequest: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requestCount, 1);

    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportRetryLocationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('facilityReportRetryLocationButton')),
    );
    await tester.tap(
      find.byKey(const Key('facilityReportRetryLocationButton')),
    );
    await tester.pump();

    expect(requestCount, 2);

    retryCompleter.complete(
      const FacilityReportLocation(latitude: 37.302421, longitude: 126.866221),
    );
    await tester.pumpAndSettle();

    expect(requestCount, 2);
  });

  testWidgets('시설 신고 화면은 위치 실패 후 다시 확인할 수 있다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    var requestCount = 0;

    Future<FacilityReportLocation> locationLoader() async {
      requestCount++;
      if (requestCount == 1) {
        throw const FacilityReportLocationException(
          '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
        );
      }
      return const FacilityReportLocation(
        latitude: 37.302421,
        longitude: 126.866221,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          locationLoader: locationLoader,
          needsLocationPermissionRequest: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportSubmitButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
    final failedLocationSubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(failedLocationSubmitButton.onPressed, isNull);
    expect(
      find.byKey(const Key('facilityReportRetryLocationButton')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('facilityReportRetryLocationButton')),
    );
    await tester.pumpAndSettle();

    expect(requestCount, 2);
    expect(find.text('위치 확인됨'), findsNothing);
    final readySubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(readySubmitButton.onPressed, isNotNull);
  });

  testWidgets('시설 신고 화면은 GPS가 꺼져 있으면 위치 확인을 요청하고 제출을 막는다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException(
        '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
      ),
      needsPermissionRequest: false,
    );
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationFacilities: const [
        StationFacilityInfo(
          id: 'facility-sangnoksu-elevator-1',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-1',
          type: 'ELEVATOR',
          name: '1번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '1번 출구 앞',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-06-12',
        ),
      ],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: reportRepository,
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(locationProvider.requestCount, 1);
    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportRetryLocationButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
    expect(find.text('현재 위치 첨부됨'), findsNothing);
    expect(find.text('현재 위치가 첨부되었습니다.'), findsNothing);
    expect(find.text('위치 확인됨'), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('facilityReportDescriptionInput')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '위치가 다르게 표시됩니다.',
    );
    final failedLocationSubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(failedLocationSubmitButton.onPressed, isNull);
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pump();

    expect(reportRepository.requests, isEmpty);
  });

  testWidgets('시설 신고 화면은 GPS가 꺼져 있으면 위치 설정으로 이동할 수 있다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException(
        '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
      ),
      needsPermissionRequest: false,
    );
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationFacilities: const [
        StationFacilityInfo(
          id: 'facility-sangnoksu-elevator-1',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-1',
          type: 'ELEVATOR',
          name: '1번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '1번 출구 앞',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-06-12',
        ),
      ],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: reportRepository,
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportOpenLocationSettingsButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(find.text('기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
    expect(
      find.byKey(const Key('facilityReportOpenLocationSettingsButton')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('facilityReportOpenLocationSettingsButton')),
    );
    await tester.pumpAndSettle();

    expect(locationProvider.openSettingsCount, 1);
    expect(reportRepository.requests, isEmpty);
  });

  testWidgets('시설 신고 화면은 위치 설정을 여는 중 위치 재확인을 막는다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final openSettingsCompleter = Completer<bool>();
    var requestCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          locationLoader: () async {
            requestCount++;
            throw const FacilityReportLocationException(
              '기기 위치(GPS)를 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
            );
          },
          needsLocationPermissionRequest: () async => false,
          openLocationSettings: () => openSettingsCompleter.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportOpenLocationSettingsButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('facilityReportOpenLocationSettingsButton')),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('facilityReportRetryLocationButton')),
    );
    await tester.tap(
      find.byKey(const Key('facilityReportRetryLocationButton')),
    );
    await tester.pump();

    expect(requestCount, 1);

    openSettingsCompleter.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('시설 신고 화면은 현재 위치를 보내기 전에 공개 범위를 안내한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final locationProvider = FakeCurrentLocationProvider(
      location: const CurrentLocation(
        latitude: 37.302421,
        longitude: 126.866221,
      ),
      needsPermissionRequest: false,
    );
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationFacilities: const [
        StationFacilityInfo(
          id: 'facility-sangnoksu-elevator-1',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-1',
          type: 'ELEVATOR',
          name: '1번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '1번 출구 앞',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-06-12',
        ),
      ],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: reportRepository,
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('시설 신고'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('facilityReportDescriptionInput')),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('현재 위치 첨부됨'), findsNothing);
    expect(find.text('현재 위치가 첨부되었습니다.'), findsNothing);
    expect(find.text('위치 확인됨'), findsNothing);
    expect(locationProvider.requestCount, 1);

    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '승강기 앞에서 확인했습니다.',
    );
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.text('사진·위치 확인'), findsOneWidget);
    expect(find.text('사진과 신고 위치는 시설 신고 확인과 운영 검수에만 사용됩니다.'), findsOneWidget);
    expect(
      find.text('신고 내용은 접수 담당자에게 전달되며 앱 사용자에게 공개되지 않습니다.'),
      findsOneWidget,
    );
    expect(reportRepository.requests, isEmpty);

    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();

    expect(reportRepository.requests, hasLength(1));
    expect(reportRepository.requests.single.latitude, 37.302421);
    expect(reportRepository.requests.single.longitude, 126.866221);
  });

  testWidgets('시설 신고 화면은 현재 위치 확인 중 제출을 막는다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final locationCompleter = Completer<FacilityReportLocation>();

    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: reportRepository,
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-elevator-1',
            facilityName: '1번 출구 엘리베이터',
            facilityTypeLabel: '엘리베이터',
            facilityStatusLabel: '정상',
          ),
          locationLoader: () => locationCompleter.future,
          needsLocationPermissionRequest: () async => false,
        ),
      ),
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('facilityReportDescriptionInput')),
    );
    await tester.pumpAndSettle();

    final loadingSubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(loadingSubmitButton.onPressed, isNull);
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pump();
    expect(reportRepository.requests, isEmpty);

    locationCompleter.complete(
      const FacilityReportLocation(latitude: 37.302421, longitude: 126.866221),
    );
    await tester.pumpAndSettle();

    final readySubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(readySubmitButton.onPressed, isNotNull);
  });

  testWidgets('시설 신고 화면은 현재 위치 실패 안내를 그대로 보여준다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationFacilities: const [
        StationFacilityInfo(
          id: 'facility-sangnoksu-elevator-1',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-1',
          type: 'ELEVATOR',
          name: '1번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '1번 출구 앞',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-06-12',
        ),
      ],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: reportRepository,
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: FakeCurrentLocationProvider(
          error: const CurrentLocationException('위치 권한을 허용해 주세요.'),
          needsPermissionRequest: false,
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('facilityReportDescriptionInput')),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('위치 권한을 허용해 주세요.'), findsOneWidget);
    expect(find.text('현재 위치를 확인하지 못했습니다.'), findsNothing);
    final failedLocationSubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(failedLocationSubmitButton.onPressed, isNull);
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pump();
    expect(reportRepository.requests, isEmpty);
  });
}

Future<void> _continuePhotoUse(
  WidgetTester tester, {
  bool settle = true,
}) async {
  expect(find.text('사진 확인'), findsOneWidget);
  await tester.tap(find.text('계속'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

FavoriteStation _favoriteStation({required String id, required String name}) {
  return FavoriteStation(
    userId: 'anonymous-user-1',
    stationId: id,
    nameKo: name,
    nameEn: id,
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    dataSourceType: 'OFFICIAL_FILE',
    lastVerifiedAt: '2026-06-13',
    lines: const [
      StationSearchLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        stationCode: '448',
      ),
    ],
    addedAt: '2026-06-13T10:00:00',
  );
}

FavoriteFacility _favoriteFacility() {
  return const FavoriteFacility(
    userId: 'anonymous-user-1',
    facilityId: 'facility-sangnoksu-elevator-1',
    stationId: 'station-sangnoksu',
    stationNameKo: '상록수',
    stationNameEn: 'Sangnoksu',
    exitId: 'exit-sangnoksu-1',
    type: 'ELEVATOR',
    name: '1번 출구 엘리베이터',
    floorFrom: '1F',
    floorTo: 'B1',
    description: '1번 출구 앞',
    status: 'NORMAL',
    dataConfidence: 'HIGH',
    dataSourceType: 'OFFICIAL_FILE',
    lastUpdatedAt: '2026-06-12',
    addedAt: '2026-06-14T10:00:00',
  );
}

FavoriteRoute _favoriteRoute() {
  return const FavoriteRoute(
    userId: 'anonymous-user-1',
    favoriteRouteId: 'route-1',
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
    routeCreatedAt: '2026-06-13T04:20:00',
    addedAt: '2026-06-14T10:00:00',
  );
}

InternalRouteResult _internalRouteResult({
  String status = 'FOUND',
  List<String> blockedReasons = const [],
}) {
  return InternalRouteResult(
    stationId: 'station-sangnoksu',
    stationName: '상록수',
    fromNodeId: 'node-sangnoksu-elevator-1',
    fromNodeName: '1번 출구 엘리베이터',
    toNodeId: 'node-sangnoksu-faregate',
    toNodeName: '개찰구',
    mobilityType: 'WHEELCHAIR',
    status: status,
    totalDistanceMeters: status == 'FOUND' ? 28 : 0,
    totalEstimatedSeconds: status == 'FOUND' ? 75 : 0,
    steps: status == 'FOUND'
        ? const [
            InternalRouteStep(
              sequence: 1,
              edgeId: 'edge-sangnoksu-elevator-to-faregate',
              fromNodeId: 'node-sangnoksu-elevator-1',
              fromNodeName: '1번 출구 엘리베이터',
              toNodeId: 'node-sangnoksu-faregate',
              toNodeName: '개찰구',
              edgeType: 'WALK',
              distanceMeters: 28,
              estimatedSeconds: 75,
              includesStairs: false,
              requiresElevator: true,
              requiresEscalator: false,
              slopeLevel: 1,
              widthLevel: 2,
              reliabilityScore: 92,
              guidance: '엘리베이터에서 개찰구까지 이동합니다.',
            ),
          ]
        : const [],
    warnings: const [],
    blockedReasons: blockedReasons,
  );
}

List<InternalRouteNode> _internalRouteNodes() {
  return const [
    InternalRouteNode(
      id: 'node-sangnoksu-elevator-1',
      stationId: 'station-sangnoksu',
      type: 'ELEVATOR',
      name: '1번 출구 엘리베이터',
      facilityId: 'facility-sangnoksu-elevator-1',
      displayLabel: '1번 출구 승강기',
    ),
    InternalRouteNode(
      id: 'node-sangnoksu-faregate',
      stationId: 'station-sangnoksu',
      type: 'FAREGATE',
      name: '개찰구',
      facilityId: '',
      displayLabel: '개찰구',
    ),
  ];
}

class FakeStationSearchRepository
    implements StationSearchRepository, StationLineFilterRepository {
  FakeStationSearchRepository({
    this.nextResults = const [],
    this.nearbyResults = const [],
    this.queryResults = const {},
    this.lineOptions = const [],
    this.searchCompleter,
    StationDetail? stationDetail,
    this.stationExits = const [],
    this.stationFacilities = const [],
  }) : stationDetail =
           stationDetail ??
           _stationDetail(id: 'station-sangnoksu', name: '상록수');

  final List<StationSearchResult> nextResults;
  final List<StationSearchResult> nearbyResults;
  final Map<String, List<StationSearchResult>> queryResults;
  final List<SubwayLineOption> lineOptions;
  final Completer<List<StationSearchResult>>? searchCompleter;
  final StationDetail stationDetail;
  final List<StationExitInfo> stationExits;
  final List<StationFacilityInfo> stationFacilities;
  final requestedQueries = <String>[];
  final requestedLineIds = <String?>[];
  final requestedNearbyLocations = <CurrentLocation>[];
  final requestedDetailStationIds = <String>[];
  final requestedExitStationIds = <String>[];
  final requestedFacilityStationIds = <String>[];

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    requestedQueries.add(query);
    requestedLineIds.add(null);
    final delayedResults = searchCompleter;
    if (delayedResults != null) {
      return delayedResults.future;
    }
    return queryResults[query] ?? nextResults;
  }

  @override
  Future<List<StationSearchResult>> searchStationsOnLine(
    String query,
    String lineId,
  ) async {
    requestedQueries.add(query);
    requestedLineIds.add(lineId);
    final delayedResults = searchCompleter;
    if (delayedResults != null) {
      return delayedResults.future;
    }
    return queryResults[query] ?? nextResults;
  }

  @override
  Future<List<SubwayLineOption>> listLines() async {
    return lineOptions;
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    requestedNearbyLocations.add(location);
    return nearbyResults;
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    requestedDetailStationIds.add(stationId);
    return stationDetail;
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) async {
    requestedExitStationIds.add(stationId);
    return stationExits;
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(
    String stationId,
  ) async {
    requestedFacilityStationIds.add(stationId);
    return stationFacilities;
  }
}

class FakeSearchHistoryRepository implements SearchHistoryRepository {
  FakeSearchHistoryRepository(List<String> queries) : queries = [...queries];

  final List<String> queries;
  final recordedQueries = <String>[];
  int listRequestCount = 0;

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
  Future<List<String>> listRecentQueries() async {
    listRequestCount++;
    return [...queries];
  }
}

class FakeInternalRouteRepository implements InternalRouteRepository {
  FakeInternalRouteRepository({
    required this.result,
    this.nodes = const [],
    this.error,
  });

  final InternalRouteResult result;
  final List<InternalRouteNode> nodes;
  final InternalRouteException? error;
  final nodeStationIds = <String>[];
  final requests = <InternalRouteRequest>[];

  @override
  Future<List<InternalRouteNode>> listRouteNodes(String stationId) async {
    nodeStationIds.add(stationId);
    final routeError = error;
    if (routeError != null) {
      throw routeError;
    }
    return nodes;
  }

  @override
  Future<InternalRouteResult> searchInternalRoute(
    InternalRouteRequest request,
  ) async {
    requests.add(request);
    final routeError = error;
    if (routeError != null) {
      throw routeError;
    }
    return result;
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

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(String stationId) {
    throw UnimplementedError();
  }

  void complete(List<StationSearchResult> results) {
    _completer.complete(results);
  }
}

class FakeRouteSearchRepository implements RouteSearchRepository {
  FakeRouteSearchRepository({RouteSearchResult? result, this.error})
    : result = result ?? _sampleRouteSearchResult();

  final RouteSearchResult result;
  final Object? error;
  final requests = <RouteSearchRequest>[];

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    requests.add(request);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return result;
  }
}

class FakeRouteFeedbackRepository implements RouteFeedbackRepository {
  final requests = <RouteFeedbackRequest>[];
  Object? error;

  @override
  Future<void> submitRouteFeedback(RouteFeedbackRequest request) async {
    requests.add(request);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
  }
}

class FakeFacilityReportRepository implements FacilityReportRepository {
  FakeFacilityReportRepository({this.reports = const []});

  final requests = <FacilityReportRequest>[];
  final loadedReportIds = <String>[];
  final List<FacilityReportResult> reports;
  String nextReportStatus = 'SUBMITTED';
  int listMyReportsCount = 0;
  Object? error;

  @override
  Future<FacilityReportResult> createReport(
    FacilityReportRequest request,
  ) async {
    requests.add(request);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return FacilityReportResult(
      id: 'report-${requests.length}',
      stationId: request.stationId,
      facilityId: request.facilityId,
      reportType: request.reportType,
      description: request.description,
      status: 'SUBMITTED',
      createdAt: '2026-06-13T10:00:00',
    );
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) async {
    loadedReportIds.add(reportId);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return FacilityReportResult(
      id: reportId,
      stationId: 'station-sangnoksu',
      facilityId: 'facility-sangnoksu-elevator-1',
      reportType: 'CLOSED',
      description: '출입문이 막혀 있습니다.',
      status: nextReportStatus,
      createdAt: '2026-06-13T10:00:00',
    );
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() async {
    listMyReportsCount++;
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return reports;
  }
}

class FakeFavoriteStationRepository implements FavoriteStationRepository {
  FakeFavoriteStationRepository({this.favorites = const []});

  List<FavoriteStation> favorites;
  final savedStationIds = <String>[];
  final removedStationIds = <String>[];
  Object? error;

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return favorites;
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(String stationId) async {
    savedStationIds.add(stationId);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    final favorite = _favoriteStation(id: stationId, name: '상록수');
    favorites = [favorite];
    return favorite;
  }

  @override
  Future<void> removeFavoriteStation(String stationId) async {
    removedStationIds.add(stationId);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    favorites = favorites
        .where((favorite) => favorite.stationId != stationId)
        .toList(growable: false);
  }
}

class FakeNotificationSettingsRepository
    implements NotificationSettingsRepository {
  NotificationSettings settings = const NotificationSettings(
    userId: 'anonymous-user-1',
    favoriteStationFacilityAlerts: true,
    favoriteRouteFacilityAlerts: false,
    reportStatusAlerts: true,
    dataQualityAlerts: false,
    updatedAt: '2026-06-14T09:00:00',
  );
  final savedSettings = <NotificationSettings>[];
  Object? error;

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return settings;
  }

  @override
  Future<NotificationSettings> saveNotificationSettings(
    NotificationSettings settings,
  ) async {
    savedSettings.add(settings);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    this.settings = settings.copyWith(updatedAt: '2026-06-14T09:05:00');
    return this.settings;
  }
}

class FakeNotificationPermissionProvider
    implements NotificationPermissionProvider {
  FakeNotificationPermissionProvider({required this.nextStatus, this.error});

  final NotificationPermissionStatus nextStatus;
  final Object? error;
  int requestCount = 0;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() async {
    requestCount++;
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return nextStatus;
  }
}

class FakeFavoriteFacilityRepository implements FavoriteFacilityRepository {
  FakeFavoriteFacilityRepository({this.favorites = const []});

  List<FavoriteFacility> favorites;
  Object? error;

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return favorites;
  }

  @override
  Future<FavoriteFacility> saveFavoriteFacility(String facilityId) async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    final favorite = _favoriteFacility();
    favorites = [favorite];
    return favorite;
  }

  @override
  Future<void> removeFavoriteFacility(String facilityId) async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    favorites = favorites
        .where((favorite) => favorite.facilityId != facilityId)
        .toList(growable: false);
  }
}

class FakeFavoriteRouteRepository implements FavoriteRouteRepository {
  FakeFavoriteRouteRepository({
    this.favorites = const [],
    this.removeCompleter,
  });

  List<FavoriteRoute> favorites;
  final Completer<void>? removeCompleter;
  final savedRouteSearchIds = <String>[];
  final removedFavoriteRouteIds = <String>[];
  Object? error;

  @override
  Future<List<FavoriteRoute>> listFavoriteRoutes() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return favorites;
  }

  @override
  Future<FavoriteRoute> saveFavoriteRoute(
    String routeSearchId, {
    RouteSearchResult? result,
  }) async {
    savedRouteSearchIds.add(routeSearchId);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    final favorite = _favoriteRoute();
    favorites = [favorite];
    return favorite;
  }

  @override
  Future<void> removeFavoriteRoute(String favoriteRouteId) async {
    removedFavoriteRouteIds.add(favoriteRouteId);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    final currentRemoveCompleter = removeCompleter;
    if (currentRemoveCompleter != null) {
      await currentRemoveCompleter.future;
    }
    favorites = favorites
        .where((favorite) => favorite.favoriteRouteId != favoriteRouteId)
        .toList(growable: false);
  }
}

class ControlledFavoriteStationRepository implements FavoriteStationRepository {
  final _favoritesCompleter = Completer<List<FavoriteStation>>();

  @override
  Future<List<FavoriteStation>> listFavoriteStations() {
    return _favoritesCompleter.future;
  }

  @override
  Future<FavoriteStation> saveFavoriteStation(String stationId) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeFavoriteStation(String stationId) {
    throw UnimplementedError();
  }

  void complete(List<FavoriteStation> favorites) {
    _favoritesCompleter.complete(favorites);
  }
}

class FakeUserDataDeletionRepository implements UserDataDeletionRepository {
  FakeUserDataDeletionRepository({this.error});

  final UserDataDeletionException? error;
  int deleteCount = 0;

  @override
  Future<UserDataDeletionResult> deleteCurrentUserData() async {
    deleteCount++;
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return const UserDataDeletionResult(
      userId: 'anonymous-user-1',
      deletedFavoriteStationCount: 1,
      deletedFavoriteFacilityCount: 1,
      deletedFavoriteRouteCount: 1,
      anonymizedRouteFeedbackCount: 1,
      notificationSettingsDeleted: true,
      deletedRegisteredDeviceCount: 1,
      deletedPushNotificationCount: 1,
      mobilityProfileDeleted: true,
      anonymizedReportCount: 1,
    );
  }
}

class MemoryOnboardingResultStore implements OnboardingResultStore {
  MemoryOnboardingResultStore({
    OnboardingResult? initialResult,
    this.throwOnRead = false,
  }) : savedResult = initialResult;

  OnboardingResult? savedResult;
  final bool throwOnRead;
  int readCount = 0;
  int saveCount = 0;

  @override
  Future<OnboardingResult?> readResult() async {
    readCount++;
    if (throwOnRead) {
      throw const FormatException('broken onboarding result');
    }
    return savedResult;
  }

  @override
  Future<void> saveResult(OnboardingResult result) async {
    saveCount++;
    savedResult = result;
  }

  @override
  Future<void> clearResult() async {
    savedResult = null;
  }
}

class MemoryFacilityReportDraftTargetStore
    implements FacilityReportDraftTargetStore {
  MemoryFacilityReportDraftTargetStore([this.target]);

  FacilityReportTarget? target;
  final savedTargets = <FacilityReportTarget>[];
  int readCount = 0;
  int saveCount = 0;
  int clearCount = 0;
  bool throwOnClear = false;

  @override
  Future<FacilityReportTarget?> readTarget() async {
    readCount++;
    return target;
  }

  @override
  Future<void> saveTarget(FacilityReportTarget target) async {
    saveCount++;
    savedTargets.add(target);
    this.target = target;
  }

  @override
  Future<void> clearTarget() async {
    clearCount++;
    if (throwOnClear) {
      throw StateError('draft target clear failed');
    }
    target = null;
  }
}

class RecordingSupportAccessLauncher implements SupportAccessLauncher {
  RecordingSupportAccessLauncher({this.openResult = true});

  final bool openResult;
  final openedUris = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    openedUris.add(uri);
    return openResult;
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

StationSearchResult _stationResult({
  required String id,
  required String name,
  int? distanceMeters,
}) {
  return StationSearchResult(
    id: id,
    nameKo: name,
    nameEn: id,
    region: '수도권',
    dataQualityLevel: 'LEVEL_1',
    dataSourceType: 'OFFICIAL_FILE',
    lastVerifiedAt: '2026-06-13',
    distanceMeters: distanceMeters,
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

CurrentLocation _freshCurrentLocation({
  double latitude = 37.3028,
  double longitude = 126.8665,
}) {
  return CurrentLocation(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: 25,
    measuredAt: DateTime.now(),
    provider: 'test',
    permissionPrecision: LocationPermissionPrecision.precise,
  );
}

class FakeCurrentLocationProvider implements CurrentLocationProvider {
  FakeCurrentLocationProvider({
    this.location,
    this.error,
    this.locationLoader,
    this.needsPermissionRequest = true,
    this.needsPermissionRequestLoader,
  });

  final CurrentLocation? location;
  final Object? error;
  final Future<CurrentLocation> Function()? locationLoader;
  final bool needsPermissionRequest;
  final Future<bool> Function()? needsPermissionRequestLoader;
  int permissionCheckCount = 0;
  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<bool> needsLocationPermissionRequest() async {
    permissionCheckCount++;
    final loader = needsPermissionRequestLoader;
    if (loader != null) {
      return loader();
    }
    return needsPermissionRequest;
  }

  @override
  Future<CurrentLocation> currentLocation() async {
    requestCount++;
    final loader = locationLoader;
    if (loader != null) {
      return loader();
    }
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return location ?? _freshCurrentLocation();
  }

  @override
  Future<bool> openLocationSettings() async {
    openSettingsCount++;
    return true;
  }
}

StationDetail _stationDetail({
  required String id,
  required String name,
  double? latitude,
  double? longitude,
}) {
  return StationDetail(
    id: id,
    nameKo: name,
    nameEn: id,
    region: '수도권',
    latitude: latitude,
    longitude: longitude,
    dataQualityLevel: 'LEVEL_1',
    dataSourceType: 'OFFICIAL_FILE',
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

RouteSearchResult _sampleRouteSearchResult({
  String status = 'FOUND',
  String mobilityType = 'SENIOR',
  List<String> recommendationReasons = const [
    '엘리베이터 동선을 우선했어요',
    '계단 없는 출구를 확인했어요',
    '천천히 이동하기 쉬운 동선을 확인했어요',
  ],
}) {
  return RouteSearchResult(
    routeSearchId: 'route-1',
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-sadang',
    destinationStationName: '사당',
    mobilityType: mobilityType,
    status: status,
    lineId: 'seoul-4',
    lineName: '수도권 4호선',
    score: 92,
    steps: const [
      RouteSearchStep(
        sequence: 1,
        title: '상록수역에서 4호선 승강장으로 이동',
        description: '엘리베이터를 이용해 승강장으로 이동합니다.',
        lineId: 'seoul-4',
        lineName: '수도권 4호선',
        fromStationId: 'station-sangnoksu',
        toStationId: 'station-sadang',
        estimatedMinutes: 4,
        distanceMeters: 180,
        includesStairs: false,
        requiresAccessibilityCheck: true,
        actionTitle: '열차 이동',
        actionDetail: '엘리베이터를 이용해 승강장으로 이동합니다.',
        reason: '선택된 경로 edge:edge-sangnoksu-sadang 근거로 안내합니다.',
        evidenceSources: ['edge:edge-sangnoksu-sadang'],
        timeSource: 'STATIC_ESTIMATE',
        distanceSource: 'MEASURED',
        confidenceLabel: '높은 신뢰도',
      ),
      RouteSearchStep(
        sequence: 2,
        title: '사당역에서 출구 접근성 정보를 확인',
        description: '2번 출구의 엘리베이터를 먼저 확인하세요.',
        lineId: 'seoul-4',
        lineName: '수도권 4호선',
        fromStationId: 'station-sadang',
        toStationId: 'station-sadang',
        estimatedMinutes: 3,
        distanceMeters: 120,
        includesStairs: false,
        requiresAccessibilityCheck: true,
      ),
    ],
    warnings: const [
      RouteSearchWarning(
        code: 'LOW_DATA_CONFIDENCE',
        message: '일부 시설 정보는 확인이 필요합니다.',
      ),
      RouteSearchWarning(
        code: 'STALE_ACCESSIBILITY_DATA',
        message: '접근성 시설 정보가 최근 30일 이내 확인되지 않았습니다. 이동 전 역 상세 정보를 확인하세요.',
      ),
    ],
    recommendationReasons: recommendationReasons,
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
    recommendationReasons: [],
    blockedReasons: ['휠체어로 이동 가능한 엘리베이터가 없습니다.'],
    createdAt: '2026-06-13T04:25:00',
  );
}
