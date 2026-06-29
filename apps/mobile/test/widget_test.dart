import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/adaptive_layout.dart';
import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/favorite_facility.dart';
import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/internal_route.dart';
import 'package:easysubway_mobile/legacy_credential_cleanup.dart';
import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:easysubway_mobile/user_data_deletion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_secure_key_value_storage.dart';
import 'user_copy_guard.dart';

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

Future<void> _openFavoriteList(
  WidgetTester tester, {
  Key? tabKey,
  RouteDraftController? routeDraftController,
  Future<void> Function(RouteDraft draft, String mobilityType)?
  onOpenRouteSearch,
}) async {
  final homeContext = tester.element(find.byType(HomeScreen));
  final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
  final draftController = routeDraftController ?? RouteDraftController();
  unawaited(
    Navigator.of(homeContext).push(
      MaterialPageRoute<void>(
        builder: (_) => FavoriteHomeScreen(
          favoriteRepository: home.favoriteRepository,
          favoriteFacilityRepository: home.favoriteFacilityRepository,
          favoriteRouteRepository: home.favoriteRouteRepository,
          stationRepository: home.repository,
          reportRepository: home.reportRepository,
          locationProvider: home.locationProvider,
          facilityReportDraftTargetStore: home.facilityReportDraftTargetStore,
          internalRouteRepository: home.internalRouteRepository,
          realtimeRepository: home.realtimeRepository,
          routeDraftController: draftController,
          initialMobilityType: home.initialMobilityType,
          onOpenRouteSearch: onOpenRouteSearch == null
              ? null
              : ([mobilityType]) => onOpenRouteSearch(
                  draftController.draft,
                  mobilityType ?? home.initialMobilityType,
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (tabKey != null) {
    final targetKey = switch (tabKey) {
      const Key('favoriteStationsTabButton') => const Key(
        'favoriteHomeStationsButton',
      ),
      const Key('favoriteFacilitiesTabButton') => const Key(
        'favoriteHomeFacilitiesButton',
      ),
      _ => const Key('favoriteHomeRoutesButton'),
    };
    await tester.tap(find.byKey(targetKey));
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(find.byKey(const Key('favoriteHomeRoutesButton')));
  await tester.pumpAndSettle();
}

Future<void> _openSettingsScreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('homeProfilePill')));
  await tester.pumpAndSettle();
}

Future<void> _openMyReportsScreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('bottomNavMore')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('myReportsSettingsButton')),
    160,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('myReportsSettingsButton')));
  await tester.pumpAndSettle();
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

Future<void> _openSupportAccessScreen(WidgetTester tester) async {
  await _openSettingsScreen(tester);
  await tester.scrollUntilVisible(
    find.byKey(const Key('settingsSupportPrivacyButton')),
    160,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settingsSupportPrivacyButton')));
  await tester.pumpAndSettle();
}

Future<void> _openRouteOriginStationInput(WidgetTester tester) async {
  if (find.byKey(const Key('routeOriginStationInput')).evaluate().isNotEmpty) {
    return;
  }
  await tester.ensureVisible(find.byKey(const Key('routeOriginPointButton')));
  await tester.tap(find.byKey(const Key('routeOriginPointButton')));
  await tester.pumpAndSettle();
}

Future<void> _openRouteDestinationStationInput(WidgetTester tester) async {
  if (find
      .byKey(const Key('routeDestinationStationInput'))
      .evaluate()
      .isNotEmpty) {
    return;
  }
  await tester.ensureVisible(
    find.byKey(const Key('routeDestinationPointButton')),
  );
  await tester.tap(find.byKey(const Key('routeDestinationPointButton')));
  await tester.pumpAndSettle();
}

Future<void> _openFirstRouteResultDetail(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('routeResultListItem')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('routeResultListItem')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('홈에서 내 신고 화면으로 이동한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository(
      reports: [
        const FacilityReportResult(
          id: 'report-2',
          publicReceiptCode: 'ES-1002',
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

    expect(find.text('내 제보'), findsOneWidget);
    expect(find.text('반영됨'), findsOneWidget);
    expect(find.text('출입문이 막혀 있습니다.'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '내 제보, 폐쇄, 제보 번호 ES-1002, 반영됨, 출입문이 막혀 있습니다., 접수일 2026.06.15',
      ),
      findsOneWidget,
    );
    expect(reportRepository.listMyReportsCount, greaterThanOrEqualTo(1));
  });

  testWidgets('내 신고 항목을 누르면 상세 상태 화면으로 이동한다', (tester) async {
    final reportRepository = FakeFacilityReportRepository(
      reports: [
        const FacilityReportResult(
          id: 'report-2',
          publicReceiptCode: 'ES-1002',
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
        '내 제보, 폐쇄, 제보 번호 ES-1002, 반영됨, 출입문이 막혀 있습니다., 접수일 2026.06.15',
      ),
    );
    expect(
      reportSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(find.byKey(const Key('myReport-report-2')));
    await tester.pumpAndSettle();

    expect(find.text('제보 상세'), findsOneWidget);
    expect(find.text('폐쇄'), findsOneWidget);
    expect(find.text('반영됨'), findsOneWidget);
    expect(find.text('제보 번호'), findsOneWidget);
    expect(find.text('ES-1002'), findsOneWidget);
    expect(find.text('report-2'), findsNothing);
    expect(find.text('접수일'), findsOneWidget);
    expect(find.text('2026.06.15'), findsOneWidget);
    expect(find.text('출입문이 막혀 있습니다.'), findsOneWidget);
    expect(
      find.bySemanticsLabel('내 제보 상세, 폐쇄, 현재 상태 반영됨, 제보 번호 ES-1002'),
      findsOneWidget,
    );
  });

  testWidgets('내 제보 화면은 접수한 제보가 없으면 짧은 빈 상태를 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyFacilityReportListScreen(
          repository: FakeFacilityReportRepository(reports: const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('접수한 제보가 없습니다.'), findsOneWidget);
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
    expect(find.text('어떤 도움이 필요한가요?'), findsNothing);
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
    expect(
      find.byKey(const Key('homeNotificationActionButton')),
      findsOneWidget,
    );

    expect(find.text('자주 가는 곳'), findsNothing);
    expect(find.text('최근 경로'), findsNothing);
    expect(find.text('저장한 경로가 없습니다'), findsNothing);
  });

  testWidgets('홈 최근 경로는 저장소 데이터가 있으면 표시된다', (tester) async {
    final favoriteRouteRepository = FakeFavoriteRouteRepository(
      favorites: [_favoriteRoute()],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRouteRepository: favoriteRouteRepository,
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('최근 경로'),
      find.byKey(const Key('homeContentList')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();

    expect(find.text('최근 경로'), findsOneWidget);
    expect(find.byKey(const Key('homeRecentRouteCard')), findsOneWidget);
    expect(find.text('상록수역'), findsOneWidget);
    expect(find.text('사당역'), findsOneWidget);
    final recentRouteCard = find.byKey(const Key('homeRecentRouteCard'));
    final lineBadges = find.descendant(
      of: recentRouteCard,
      matching: find.byKey(const Key('stationLineBadge-seoul-4')),
    );
    final originText = find.descendant(
      of: recentRouteCard,
      matching: find.text('상록수역'),
    );
    expect(lineBadges, findsNWidgets(2));
    expect(
      tester.getSize(lineBadges.first).height,
      closeTo(tester.getSize(originText).height, 0.5),
    );
    expect(favoriteRouteRepository.listCount, greaterThanOrEqualTo(1));
  });

  testWidgets('홈 스크롤은 하단 내비게이션 높이만큼 여백을 둔다', (tester) async {
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    final homeList = tester.widget<ListView>(
      find.byKey(const Key('homeContentList')),
    );
    expect(homeList.padding?.resolve(TextDirection.ltr).bottom, 96);
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
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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

  testWidgets('온보딩 기본 시작 저장 실패는 안내 화면에 머문다', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('save failed')) {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    final onboardingStore = MemoryOnboardingResultStore(
      saveError: StateError('save failed'),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startScreenStartButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('onboardingIntroSkipButton')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('onboardingIntroSkipButton')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 1);
    expect(onboardingStore.savedResult, isNull);
    expect(find.byKey(const Key('onboardingIntroSkipButton')), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('설정을 저장하지 못했습니다. 다시 시도해 주세요.'), findsOneWidget);
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
      expect(find.text('어디로 가시나요?'), findsOneWidget);
      expect(find.text('안녕하세요, 오늘도 편안하게'), findsNothing);
      expect(find.byKey(const Key('routeSearchButton')), findsOneWidget);
      expect(find.byKey(const Key('heroStationSearchButton')), findsOneWidget);
      expect(find.byKey(const Key('homeRouteDraftPanel')), findsNothing);
      expect(find.text('시설 알림'), findsOneWidget);
      expect(find.text('주의'), findsNothing);
      expect(find.text('대체 1번 출구'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '대체 길 보기'), findsNothing);

      expect(find.byKey(const Key('homeSecondaryActionsGroup')), findsNothing);
      expect(find.byKey(const Key('homeSettingsActionsGroup')), findsNothing);
      expect(find.byKey(const Key('homeMyInfoActionsGroup')), findsNothing);
      expect(find.byKey(const Key('homeTripControlPanel')), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '최근 검색'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '길찾기'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '역 검색'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '설정'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '이동 조건'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '알림 설정'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '즐겨찾기'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '내 신고'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '도움말'), findsNothing);
      expect(
        find.byKey(const Key('homeNotificationActionButton')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('homeBottomNavigationBar')), findsOneWidget);
      expect(find.byKey(const Key('bottomNavHome')), findsOneWidget);
      expect(find.byKey(const Key('bottomNavMap')), findsOneWidget);
      expect(find.byKey(const Key('bottomNavRoute')), findsOneWidget);
      expect(find.byKey(const Key('bottomNavSaved')), findsOneWidget);
      expect(find.text('즐겨찾기'), findsOneWidget);
      expect(find.byKey(const Key('bottomNavMore')), findsOneWidget);
      expect(find.byKey(const Key('homeHelpActionButton')), findsNothing);
      expect(find.widgetWithText(TextButton, '도움말'), findsNothing);
      expect(find.widgetWithText(FilledButton, '내 신고'), findsNothing);
      expect(find.widgetWithText(FilledButton, '알림 설정'), findsNothing);
      expect(find.text('바로가기'), findsNothing);
      expect(find.text('저장한 곳'), findsNothing);
      expect(find.text('즐겨찾기 경로'), findsNothing);
      expect(find.text('즐겨찾기 역'), findsNothing);
      expect(find.text('즐겨찾기 시설'), findsNothing);
      expect(find.textContaining('빠른 길보다'), findsNothing);
      expect(find.text('이동 조건: 천천히 이동 〉'), findsOneWidget);
      expect(
        find.bySemanticsLabel('길찾기와 역 검색, 현재 이동 조건 천천히 이동'),
        findsOneWidget,
      );
      expect(find.textContaining('휠체어'), findsNothing);

      final heroStationButtonSize = tester.getSize(
        find.byKey(const Key('heroStationSearchButton')),
      );
      final routeButtonSize = tester.getSize(
        find.byKey(const Key('routeSearchButton')),
      );

      expect(heroStationButtonSize.height, greaterThanOrEqualTo(64));
      expect(routeButtonSize.height, greaterThanOrEqualTo(104));
      expect(routeButtonSize.height, greaterThan(heroStationButtonSize.height));
      expect(
        tester.getTopLeft(find.byKey(const Key('routeSearchButton'))).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const Key('heroStationSearchButton')))
              .dy,
        ),
      );

      expect(find.text('최근 경로'), findsOneWidget);
      expect(find.text('저장한 경로가 없습니다'), findsNothing);
      expect(find.text('경로를 저장하면 현재 시설 상태와 함께 다시 볼 수 있어요.'), findsNothing);

      await tester.drag(
        find.byKey(const Key('homeContentList')),
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

  testWidgets('홈 화면은 태블릿 landscape에서 핵심 CTA와 보조 영역을 나란히 보여준다', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(
          favorites: [_favoriteRoute()],
        ),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('homeLargeScreenLayout')), findsOneWidget);
    expect(find.byKey(const Key('homeBottomNavigationBar')), findsOneWidget);
    expect(find.byKey(const Key('routeSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('heroStationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('recentSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('homeRecentRouteSection')), findsOneWidget);

    final homeList = tester.widget<ListView>(
      find.byKey(const Key('homeContentList')),
    );
    final padding = homeList.padding!.resolve(TextDirection.ltr);
    expect(padding.left, EasySubwayAdaptiveLayout.largeScreenGutter);
    expect(padding.right, EasySubwayAdaptiveLayout.largeScreenGutter);
    expect(padding.bottom, 112);

    final heroRect = tester.getRect(find.byKey(const Key('homeHeroCard')));
    final recentSearchRect = tester.getRect(
      find.byKey(const Key('recentSearchButton')),
    );

    expect(heroRect.left, lessThan(recentSearchRect.left));
    expect(heroRect.right, lessThan(recentSearchRect.left));
    expect(heroRect.width, lessThan(800));
    expect(recentSearchRect.top, lessThan(heroRect.bottom));
  });

  testWidgets('홈 우측 상단 알림 버튼은 알림함으로 이동한다', (tester) async {
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

    final notificationButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('homeNotificationActionButton')),
        matching: find.byType(IconButton),
      ),
    );
    final notificationButtonSide = notificationButton.style?.side?.resolve(
      <WidgetState>{},
    );
    final notificationBadge = tester.widget<Badge>(
      find.descendant(
        of: find.byKey(const Key('homeNotificationActionButton')),
        matching: find.byType(Badge),
      ),
    );
    expect(notificationButtonSide?.color, EasySubwayAccessibleColors.line);
    expect(notificationButtonSide?.width, 1.5);
    expect(notificationBadge.isLabelVisible, isFalse);
    expect(find.bySemanticsLabel('알림, 새 알림 없음'), findsOneWidget);
    expect(find.bySemanticsLabel('알림, 확인할 알림 있음'), findsNothing);

    await tester.tap(find.byKey(const Key('homeNotificationActionButton')));
    await tester.pumpAndSettle();

    expect(find.text('알림'), findsOneWidget);
    expect(find.text('새 알림이 없습니다'), findsOneWidget);
  });

  testWidgets('홈 알림 버튼은 확인할 알림이 있으면 배지와 상태를 알려준다', (tester) async {
    final favoriteFacilityRepository = FakeFavoriteFacilityRepository(
      favorites: [_favoriteFacility(status: 'USER_REPORTED')],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: favoriteFacilityRepository,
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    final notificationBadge = tester.widget<Badge>(
      find.descendant(
        of: find.byKey(const Key('homeNotificationActionButton')),
        matching: find.byType(Badge),
      ),
    );
    expect(notificationBadge.isLabelVisible, isTrue);
    expect(find.bySemanticsLabel('알림, 확인할 알림 있음'), findsOneWidget);
    expect(find.bySemanticsLabel('알림, 새 알림 없음'), findsNothing);
    expect(favoriteFacilityRepository.listCount, 1);
  });

  testWidgets('홈은 역 검색에서 돌아오면 알림 상태를 다시 불러온다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();

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

    expect(reportRepository.listMyReportsCount, 1);

    await tester.tap(find.byKey(const Key('heroStationSearchButton')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(reportRepository.listMyReportsCount, greaterThanOrEqualTo(2));
  });

  testWidgets('알림함 시설 상태는 심각도와 다음 행동을 함께 보여준다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(
          favorites: [_favoriteFacility(status: 'USER_REPORTED')],
        ),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('homeNotificationActionButton')));
    await tester.pumpAndSettle();

    expect(find.text('상록수역 1번 출구 엘리베이터'), findsOneWidget);
    expect(find.text('점검·제보 · 엘리베이터 제보됨'), findsOneWidget);
    expect(find.text('권장 행동 역무원 도움 요청'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('심각도 점검·제보, .*공식 정보, 권장 행동 역무원 도움 요청')),
      findsOneWidget,
    );
    expectNoForbiddenUserCopy(tester);
  });

  testWidgets('홈 노선도 버튼은 v3 노선도 화면을 연다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(
          networkMapRegionNames: const ['수도권'],
        ),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byKey(const Key('mapRegionTabs')), findsOneWidget);
    expectNoForbiddenUserCopy(tester);
    expect(find.byKey(const Key('networkMapLineFilter')), findsNothing);
    expect(find.byKey(const Key('networkMapZoomInButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapZoomOutButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapOverviewButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapLocateButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapListButton')), findsNothing);
    expect(find.byTooltip('지도 전체 보기'), findsOneWidget);
    expect(find.byTooltip('처음 위치로'), findsOneWidget);
    expect(find.text('노선별로 보기'), findsNothing);
    expect(find.text('노선도별로 보기'), findsNothing);
    expect(find.byTooltip('전체 보기'), findsNothing);
    expect(find.byTooltip('중심 보기'), findsNothing);
    expect(find.text('노선 목록으로 보기'), findsNothing);
    expect(find.byKey(const Key('networkMapSurface')), findsOneWidget);
    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.text('저장'), findsNothing);
    expect(find.text('수도권'), findsOneWidget);
    expect(find.text('전국'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('mapRegionTabs'))).height,
      greaterThanOrEqualTo(EasySubwayTouchTarget.general),
    );
    expect(find.bySemanticsLabel('지역: 수도권'), findsOneWidget);
    expect(find.bySemanticsLabel('노선: 전체 노선'), findsNothing);
    expect(find.text('전체 노선'), findsNothing);
    expect(find.byKey(const Key('networkMapInteractiveViewer')), findsNothing);
    expect(find.byKey(const Key('routeMapViewportRenderer')), findsOneWidget);

    await tester.tap(find.byKey(const Key('networkMapOverviewButton')));
    await tester.pump();

    for (var index = 0; index < 30; index += 1) {
      await tester.tap(find.byKey(const Key('networkMapZoomInButton')));
      await tester.pump();
    }

    for (var index = 0; index < 80; index += 1) {
      await tester.tap(find.byKey(const Key('networkMapZoomOutButton')));
      await tester.pump();
    }
    expect(find.byKey(const Key('networkMapSurface')), findsOneWidget);
    expect(find.byKey(const Key('routeMapViewportRenderer')), findsOneWidget);
  });

  testWidgets('홈 노선도 탭은 같은 shell 안에서 선택 상태를 바꾼다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(
          networkMapRegionNames: const ['수도권'],
        ),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    final navigationBar = tester.widget<NavigationBar>(
      find.byKey(const Key('homeBottomNavigationBar')),
    );
    expect(navigationBar.selectedIndex, 1);

    await tester.tap(find.byKey(const Key('bottomNavHome')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapScreen')), findsNothing);
    final homeNavigationBar = tester.widget<NavigationBar>(
      find.byKey(const Key('homeBottomNavigationBar')),
    );
    expect(homeNavigationBar.selectedIndex, 0);
  });

  testWidgets('홈 하단 탭은 길찾기 즐겨찾기 더보기를 같은 shell에서 전환한다', (tester) async {
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

    Future<void> expectShellTab({
      required Key tabKey,
      required Key screenKey,
      required int selectedIndex,
    }) async {
      await tester.tap(find.byKey(tabKey));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(screenKey), findsOneWidget);
      expect(
        tester
            .widget<NavigationBar>(
              find.byKey(const Key('homeBottomNavigationBar')),
            )
            .selectedIndex,
        selectedIndex,
      );
    }

    await expectShellTab(
      tabKey: const Key('bottomNavRoute'),
      screenKey: const Key('routeSearchScreen'),
      selectedIndex: 2,
    );
    await expectShellTab(
      tabKey: const Key('bottomNavSaved'),
      screenKey: const Key('favoriteHomeScreen'),
      selectedIndex: 3,
    );
    await expectShellTab(
      tabKey: const Key('bottomNavMore'),
      screenKey: const Key('settingsScreen'),
      selectedIndex: 4,
    );

    await tester.tap(find.byKey(const Key('bottomNavHome')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settingsScreen')), findsNothing);
    expect(
      tester
          .widget<NavigationBar>(
            find.byKey(const Key('homeBottomNavigationBar')),
          )
          .selectedIndex,
      0,
    );
  });

  testWidgets('노선도 지역 메뉴는 선택한 지역으로 지도를 다시 불러온다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['테스트권', '부산'],
    );
    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();
    expect(find.text('노선도를 불러오지 못했어요'), findsOneWidget);
    expect(find.text('원본 노선도를 불러올 수 없습니다.'), findsNothing);
    expect(find.byKey(const Key('networkMapLineFilter')), findsNothing);

    await tester.tap(find.text('테스트권'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('부산'));
    await tester.pumpAndSettle();

    expect(repository.requestedNetworkMapRegions, contains('부산'));
    expect(repository.requestedNetworkMapLineIds, isNot(contains('seoul-4')));
    expect(find.bySemanticsLabel('노선: 전체 노선'), findsNothing);
    expect(find.text('부산'), findsOneWidget);
  });

  testWidgets('노선도 로드 실패는 재시도와 역 검색 대안을 보여준다', (tester) async {
    var stationSearchOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(
            networkMapError: StateError('map failed'),
          ),
          routeDraftController: RouteDraftController(),
          onOpenRouteSearch: () async {},
          onOpenStationSearch: () {
            stationSearchOpened = true;
          },
          onOpenSaved: () {},
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('노선도를 불러오지 못했어요'), findsOneWidget);
    expect(find.byKey(const Key('networkMapRetryButton')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapStationSearchFallbackButton')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('networkMapStationSearchFallbackButton')),
    );
    await tester.pumpAndSettle();
    expect(stationSearchOpened, isTrue);
  });

  testWidgets('노선도는 노선 필터 없이 전체 지도에서 역을 선택한다', (tester) async {
    final repository = FakeStationSearchRepository();
    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapLineFilter')), findsNothing);
    expect(find.text('전체 노선'), findsNothing);
    expect(
      find.byKey(const Key('networkMapSelectedLineOverlay')),
      findsNothing,
    );
    expect(repository.requestedNetworkMapLineIds, isNot(contains('seoul-4')));

    await tester.tapAt(
      tester.getCenter(
        find.byKey(const Key('networkMapStation-sadang-seoul-4')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('사당역'), findsOneWidget);
    expect(find.text('2호선'), findsOneWidget);
    expect(find.text('4호선'), findsWidgets);
  });

  testWidgets('노선도는 노선별 보기 우회 sheet를 노출하지 않는다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapListButton')), findsNothing);
    expect(find.byKey(const Key('networkMapListSheet')), findsNothing);
    expect(find.text('노선별로 보기'), findsNothing);
    expect(find.text('노선도별로 보기'), findsNothing);
    expect(find.text('노선별 역 보기'), findsNothing);
    expect(find.text('노선별 목록에서 역을 선택하세요.'), findsNothing);
  });

  test('노선도 camera revision은 같은 gesture update에서도 단조 증가한다', () {
    const current = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 1000, 500),
      viewportSize: Size(250, 125),
      center: Offset(500, 250),
      scale: 0.5,
      minScale: 0.1,
      maxScale: 4,
      revision: 3,
    );

    final first = networkMapCameraWithMonotonicRevision(
      current: current,
      next: current.copyWith(center: const Offset(510, 250), revision: 4),
    );
    final second = networkMapCameraWithMonotonicRevision(
      current: first,
      next: current.copyWith(center: const Offset(520, 250), revision: 4),
    );

    expect(first.revision, 4);
    expect(second.revision, 5);
  });

  test('공식 노선도 초기 화면은 전체 asset bounds에서 시작한다', () {
    expect(
      networkMapInitialOriginalAssetBounds(
        sourceWidth: 5724,
        sourceHeight: 6516,
      ),
      const Rect.fromLTWH(0, 0, 5724, 6516),
    );
  });

  test('노선도 gesture renderer commit은 interval, drift, scale 기준으로 제한한다', () {
    const committed = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 1000, 500),
      viewportSize: Size(250, 125),
      center: Offset(500, 250),
      scale: 0.5,
      minScale: 0.1,
      maxScale: 4,
      revision: 3,
    );

    expect(
      networkMapShouldCommitRendererCamera(
        committed: committed,
        candidate: committed.copyWith(center: const Offset(580, 250)),
        elapsedSinceLastCommit: const Duration(milliseconds: 40),
      ),
      isFalse,
    );
    expect(
      networkMapShouldCommitRendererCamera(
        committed: networkMapOverscannedRendererCamera(committed),
        candidate: networkMapOverscannedRendererCamera(
          committed.copyWith(center: const Offset(560, 250), revision: 4),
        ),
        elapsedSinceLastCommit: const Duration(milliseconds: 40),
      ),
      isFalse,
    );
    expect(
      networkMapShouldCommitRendererCamera(
        committed: committed,
        candidate: committed.copyWith(center: const Offset(930, 250)),
        elapsedSinceLastCommit: const Duration(milliseconds: 40),
      ),
      isTrue,
    );
    expect(
      networkMapShouldCommitRendererCamera(
        committed: committed,
        candidate: committed.copyWith(scale: 1.21),
        elapsedSinceLastCommit: const Duration(milliseconds: 40),
      ),
      isTrue,
    );
    expect(
      networkMapShouldCommitRendererCamera(
        committed: committed,
        candidate: committed,
        elapsedSinceLastCommit: const Duration(milliseconds: 80),
      ),
      isFalse,
    );
    expect(
      networkMapShouldCommitRendererCamera(
        committed: committed,
        candidate: committed,
        elapsedSinceLastCommit: const Duration(milliseconds: 700),
      ),
      isTrue,
    );
  });

  test('노선도 renderer transform은 stale viewBox frame을 최신 camera 위치로 보정한다', () {
    const rendererCamera = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 1000, 500),
      viewportSize: Size(250, 125),
      center: Offset(500, 250),
      scale: 0.5,
      minScale: 0.1,
      maxScale: 4,
      revision: 3,
    );
    final visualCamera = rendererCamera.copyWith(
      center: const Offset(550, 250),
      revision: 4,
    );

    final rendererPoint = rendererCamera.sourceToViewportPoint(
      visualCamera.center,
    );
    final transformed = MatrixUtils.transformPoint(
      networkMapRendererFrameTransform(
        rendererCamera: rendererCamera,
        visualCamera: visualCamera,
      ),
      rendererPoint,
    );

    expect(transformed.dx, moreOrLessEquals(125));
    expect(transformed.dy, moreOrLessEquals(62.5));
  });

  test('노선도 renderer transform은 overscan 범위 밖 edge 노출을 피한다', () {
    const visualCamera = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 2000, 1000),
      viewportSize: Size(250, 125),
      center: Offset(500, 250),
      scale: 0.5,
      minScale: 0.1,
      maxScale: 4,
      revision: 3,
    );
    final rendererCamera = networkMapOverscannedRendererCamera(visualCamera);
    final coveredVisualCamera = visualCamera.copyWith(
      center: const Offset(560, 250),
      revision: 4,
    );
    final uncoveredVisualCamera = visualCamera.copyWith(
      center: const Offset(1200, 250),
      revision: 5,
    );
    final requestedRendererCamera = networkMapOverscannedRendererCamera(
      uncoveredVisualCamera,
    );

    expect(
      networkMapRendererCameraCoversVisual(
        rendererCamera: rendererCamera,
        visualCamera: coveredVisualCamera,
      ),
      isTrue,
    );
    expect(
      networkMapRendererTransformVisualCamera(
        rendererCamera: rendererCamera,
        visualCamera: coveredVisualCamera,
      ),
      same(coveredVisualCamera),
    );
    expect(
      networkMapRendererCameraCoversVisual(
        rendererCamera: rendererCamera,
        visualCamera: uncoveredVisualCamera,
      ),
      isFalse,
    );
    expect(
      networkMapRendererTransformVisualCamera(
        rendererCamera: rendererCamera,
        visualCamera: uncoveredVisualCamera,
      ),
      same(rendererCamera),
    );
    expect(
      networkMapRendererCommitBasisCamera(
        presentedCamera: rendererCamera,
        requestedCamera: requestedRendererCamera,
        visualCamera: uncoveredVisualCamera,
      ),
      same(requestedRendererCamera),
    );
  });

  test('노선도 renderer는 pan reversal 때 stale requested camera를 교체한다', () {
    const visualCamera = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 3000, 1500),
      viewportSize: Size(250, 125),
      center: Offset(1500, 750),
      scale: 0.5,
      minScale: 0.1,
      maxScale: 4,
      revision: 3,
    );
    final staleRequestedCamera = networkMapOverscannedRendererCamera(
      visualCamera.copyWith(center: const Offset(2700, 750), revision: 4),
    );
    final candidateCamera = networkMapOverscannedRendererCamera(
      visualCamera.copyWith(revision: 5),
    );

    expect(
      networkMapRendererCameraCoversVisual(
        rendererCamera: staleRequestedCamera,
        visualCamera: visualCamera,
      ),
      isFalse,
    );
    expect(
      networkMapRendererCameraForSkippedCommit(
        requestedCamera: staleRequestedCamera,
        candidateCamera: candidateCamera,
        visualCamera: visualCamera,
      ),
      same(candidateCamera),
    );
  });

  test('노선도 renderer는 out-of-order presented revision을 무시한다', () {
    const presentedCamera = MapCameraState(
      sourceBounds: Rect.fromLTWH(0, 0, 1000, 500),
      viewportSize: Size(250, 125),
      center: Offset(500, 250),
      scale: 0.5,
      minScale: 0.1,
      maxScale: 4,
      revision: 3,
    );
    final requestedCamera = presentedCamera.copyWith(
      center: const Offset(560, 250),
      revision: 5,
    );

    expect(
      networkMapShouldAcceptPresentedRendererRevision(
        revision: 4,
        presentedCamera: presentedCamera,
        requestedCamera: requestedCamera,
      ),
      isFalse,
    );
    expect(
      networkMapShouldAcceptPresentedRendererRevision(
        revision: 5,
        presentedCamera: presentedCamera,
        requestedCamera: requestedCamera,
      ),
      isTrue,
    );
    expect(
      networkMapShouldAcceptPresentedRendererRevision(
        revision: 2,
        presentedCamera: presentedCamera,
        requestedCamera: null,
      ),
      isFalse,
    );
  });

  test('공식 노선도 데이터팩 manifest는 앱 번들 asset을 가리킨다', () {
    final manifestFile = File('assets/datapacks/metro_map_pack/manifest.json');
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    final requirements =
        manifest['requirements'] as Map<String, Object?>? ?? const {};
    final maps = (manifest['maps'] as List).cast<Map<String, Object?>>();

    expect(manifest['default_display_mode'], 'offline');
    expect(requirements['live_mode_requires_network'], isFalse);
    expect(
      maps.map((map) => map['app_region']),
      containsAll(['수도권', '부산', '광주', '대구', '대전']),
    );
    for (final map in maps) {
      final offline = map['offline'] as Map<String, Object?>;
      final path = offline['path'] as String;
      expect(map['source_url'], isA<String>());
      expect(map['source_url'] as String, startsWith('https://'));
      expect(offline['included'], isTrue);
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(path, startsWith('assets/datapacks/maps/'));
      final extension = path.split('.').last.toLowerCase();
      expect(extension, anyOf('pdf', 'svg'));
      expect(offline['type'], extension);
    }
    final gwangju = maps.singleWhere((map) => map['id'] == 'gwangju');
    final license = gwangju['license'] as Map<String, Object?>;
    expect(license['spdx'], 'CC-BY-SA-2.0-KR');
    expect(
      license['url'],
      'https://creativecommons.org/licenses/by-sa/2.0/kr/',
    );
  });

  testWidgets('노선도는 카드가 아니라 공식 지도처럼 전면 캔버스로 보인다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(
          networkMapRegionNames: const ['수도권'],
        ),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();

    final surface = tester.widget<Container>(
      find.byKey(const Key('networkMapSurface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.border, isNull);
    expect(decoration.borderRadius, isNull);
    expect(find.byKey(const Key('routeMapViewportRenderer')), findsOneWidget);
    expect(find.byKey(const Key('networkMapPainter')), findsNothing);
  });

  testWidgets('수도권 노선도는 Android에서도 viewport renderer를 사용한다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 3;
    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(
            networkMapRegionNames: const ['수도권'],
          ),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bottomNavMap')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('networkMapInteractiveViewer')),
        findsNothing,
      );
      final renderer = tester.getSize(
        find.byKey(const Key('routeMapViewportRenderer')),
      );
      final surface = tester.getSize(
        find.byKey(const Key('networkMapSurface')),
      );
      expect(renderer.width, surface.width);
      expect(renderer.height, surface.height);
      expect(
        tester.widget(find.byKey(const Key('routeMapViewportRenderer'))),
        isA<ColoredBox>(),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetDevicePixelRatio();
    }
  });

  test('Android 노선도 fallback edge resolver는 station-line endpoint를 해석한다', () {
    const stations = [
      NetworkMapStation(
        id: 'station-a',
        nameKo: '출발역',
        nameEn: 'A',
        region: '수도권',
        lineId: 'seoul-4',
        stationCode: '401',
        sequence: 1,
        position: NetworkMapPosition(
          x: 2800,
          y: 3200,
          labelDx: 0,
          labelDy: 40,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-route-map-source-capital-review',
        ),
      ),
      NetworkMapStation(
        id: 'station-a',
        nameKo: '다른노선역',
        nameEn: 'A transfer',
        region: '수도권',
        lineId: 'seoul-2',
        stationCode: '201',
        sequence: 1,
        position: NetworkMapPosition(
          x: 2800,
          y: 3200,
          labelDx: 0,
          labelDy: 40,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-route-map-source-capital-review',
        ),
      ),
    ];

    expect(
      networkMapStationForMapEdgeEndpoint(
        endpoint: 'station-a:seoul-4',
        lineId: 'seoul-4',
        stations: stations,
      )?.stationCode,
      '401',
    );
    expect(
      networkMapStationForMapEdgeEndpoint(
        endpoint: 'station-a',
        lineId: 'seoul-4',
        stations: stations,
      )?.stationCode,
      '401',
    );
  });

  testWidgets('노선도 viewport 밖 station semantics는 생성하지 않는다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    const map = NetworkMapData(
      regions: [NetworkMapRegion(name: '테스트권')],
      selectedRegion: '테스트권',
      lines: [
        NetworkMapLine(
          id: 'seoul-4',
          name: '수도권 4호선',
          color: '#00A5DE',
          region: '테스트권',
        ),
        NetworkMapLine(
          id: 'seoul-2',
          name: '수도권 2호선',
          color: '#00A84D',
          region: '테스트권',
        ),
      ],
      stations: [
        NetworkMapStation(
          id: 'station-visible-a',
          nameKo: '보이는역A',
          nameEn: 'Visible A',
          region: '테스트권',
          lineId: 'seoul-4',
          stationCode: '401',
          sequence: 1,
          position: NetworkMapPosition(
            x: 5000,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'fixture-route-map-source-capital-review',
          ),
        ),
        NetworkMapStation(
          id: 'station-visible-a',
          nameKo: '보이는역A',
          nameEn: 'Visible A',
          region: '테스트권',
          lineId: 'seoul-2',
          stationCode: '201',
          sequence: 1,
          position: NetworkMapPosition(
            x: 7550,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            labelPolygon:
                '[{"x":7550,"y":80},{"x":7650,"y":80},{"x":7650,"y":120},{"x":7550,"y":120}]',
            upPath: '',
            downPath: '',
            sourceId: 'fixture-route-map-source-capital-review',
          ),
        ),
        NetworkMapStation(
          id: 'station-geometry-left',
          nameKo: '왼쪽기준',
          nameEn: 'Geometry Left',
          region: '테스트권',
          lineId: 'geometry-helper',
          stationCode: '000',
          sequence: 0,
          position: NetworkMapPosition(
            x: 0,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'fixture-route-map-source-capital-review',
          ),
        ),
        NetworkMapStation(
          id: 'station-geometry-left-b',
          nameKo: '왼쪽기준B',
          nameEn: 'Geometry Left B',
          region: '테스트권',
          lineId: 'geometry-helper',
          stationCode: '001',
          sequence: 0,
          position: NetworkMapPosition(
            x: 100,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'fixture-route-map-source-capital-review',
          ),
        ),
        NetworkMapStation(
          id: 'station-far-a',
          nameKo: '먼역A',
          nameEn: 'Far A',
          region: '테스트권',
          lineId: 'seoul-4',
          stationCode: '499',
          sequence: 99,
          position: NetworkMapPosition(
            x: 10000,
            y: 100,
            labelDx: 0,
            labelDy: 0,
            upPath: '',
            downPath: '',
            sourceId: 'fixture-route-map-source-capital-review',
          ),
        ),
      ],
      edges: [],
      positionSources: [
        NetworkMapPositionSource(
          id: 'fixture-route-map-source-capital-review',
          name: '수도권 노선도 fixture 좌표 검수',
          licenseStatus: 'fixture-only',
        ),
      ],
      stationLineMemberships: [
        NetworkMapStationLineMembership(
          stationId: 'station-visible-a',
          lineId: 'seoul-4',
        ),
        NetworkMapStationLineMembership(
          stationId: 'station-visible-a',
          lineId: 'seoul-2',
        ),
        NetworkMapStationLineMembership(
          stationId: 'station-far-a',
          lineId: 'seoul-4',
        ),
      ],
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(
            networkMapRegionNames: const ['테스트권'],
            networkMapData: map,
          ),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bottomNavMap')));
      await tester.pumpAndSettle();

      final visibleStation = find.byKey(
        const Key('networkMapStation-visible-a-seoul-4'),
      );
      expect(visibleStation, findsOneWidget);
      expect(
        find.byKey(const Key('networkMapStation-far-a-seoul-4')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('networkMapStation-visible-a-seoul-2')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('먼역A역'), findsNothing);

      final visibleSemantics = tester.getSemantics(visibleStation);
      expect(
        visibleSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      final surfaceCenter = tester.getCenter(
        find.byKey(const Key('networkMapSurface')),
      );
      final firstGesture = await tester.startGesture(
        surfaceCenter - const Offset(24, 0),
        pointer: 1,
      );
      final secondGesture = await tester.startGesture(
        surfaceCenter + const Offset(24, 0),
        pointer: 2,
      );
      await firstGesture.moveBy(const Offset(-80, 0));
      await secondGesture.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(visibleStation, findsNothing);

      await firstGesture.cancel();
      await secondGesture.cancel();
      await tester.pumpAndSettle();
      expect(visibleStation, findsOneWidget);

      final restoredSemantics = tester.getSemantics(visibleStation);
      expect(
        restoredSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      restoredSemantics.owner!.performAction(
        restoredSemantics.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
      expect(find.text('보이는역A역'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('노선도 역을 누르면 출발 도착 설정 sheet를 보여준다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('networkMapSurface')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(
        find.byKey(const Key('networkMapStation-sadang-seoul-4')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('사당역'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '출발로 설정'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '도착으로 설정'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '역 상세'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '길찾기'), findsOneWidget);
  });

  testWidgets('노선도 역은 스크린리더 tap으로도 설정 sheet를 연다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bottomNavMap')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('networkMapSurface')),
        const Offset(0, 180),
      );
      await tester.pumpAndSettle();

      final stationFinder = find.byKey(
        const Key('networkMapStation-sadang-seoul-4'),
      );
      final stationSemantics = tester.getSemantics(stationFinder);
      expect(
        stationSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      stationSemantics.owner!.performAction(
        stationSemantics.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
      expect(find.text('사당역'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '출발로 설정'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '도착으로 설정'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('노선도 역 좌표가 겹쳐도 탭한 위치에서 가장 가까운 역을 선택한다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapData: const NetworkMapData(
        regions: [NetworkMapRegion(name: '테스트권')],
        selectedRegion: '테스트권',
        lines: [
          NetworkMapLine(
            id: 'seoul-6',
            name: '수도권 6호선',
            color: '#CD7C2F',
            region: '테스트권',
          ),
          NetworkMapLine(
            id: 'gtx-a',
            name: '수도권 GTX-A',
            color: '#9A4DA3',
            region: '테스트권',
          ),
        ],
        stations: [
          NetworkMapStation(
            id: 'station-gusan',
            nameKo: '구산',
            nameEn: 'Gusan',
            region: '테스트권',
            lineId: 'seoul-6',
            stationCode: '615',
            sequence: 6,
            position: NetworkMapPosition(
              x: 390,
              y: 320,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'qa-wikimedia-seoul-svg-coordinate',
            ),
          ),
          NetworkMapStation(
            id: 'station-yeonsinnae',
            nameKo: '연신내',
            nameEn: 'Yeonsinnae',
            region: '테스트권',
            lineId: 'gtx-a',
            stationCode: 'X615',
            sequence: 7,
            position: NetworkMapPosition(
              x: 410,
              y: 320,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'qa-wikimedia-seoul-svg-coordinate',
            ),
          ),
        ],
        edges: [],
        positionSources: [
          NetworkMapPositionSource(
            id: 'qa-wikimedia-seoul-svg-coordinate',
            name: '수도권 SVG 좌표',
            licenseStatus: 'reviewed',
          ),
        ],
        stationLineMemberships: [
          NetworkMapStationLineMembership(
            stationId: 'station-gusan',
            lineId: 'seoul-6',
          ),
          NetworkMapStationLineMembership(
            stationId: 'station-yeonsinnae',
            lineId: 'gtx-a',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('networkMapStation-gusan-seoul-6')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('구산역'), findsOneWidget);
    expect(find.text('연신내역'), findsNothing);
  });

  testWidgets('노선도 label polygon 역도 기존 marker 사각형 tap 영역을 유지한다', (
    tester,
  ) async {
    final repository = FakeStationSearchRepository(
      networkMapData: const NetworkMapData(
        regions: [NetworkMapRegion(name: '테스트권')],
        selectedRegion: '테스트권',
        lines: [
          NetworkMapLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A5DE',
            region: '테스트권',
          ),
        ],
        stations: [
          NetworkMapStation(
            id: 'station-polygon',
            nameKo: '다각형',
            nameEn: 'Polygon',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '499',
            sequence: 99,
            position: NetworkMapPosition(
              x: 100,
              y: 100,
              labelDx: 0,
              labelDy: 0,
              labelPolygon:
                  '[{"x":180,"y":80},{"x":300,"y":80},{"x":300,"y":120},{"x":180,"y":120}]',
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
        ],
        edges: [],
        positionSources: [
          NetworkMapPositionSource(
            id: 'fixture-route-map-source-capital-review',
            name: '수도권 노선도 fixture 좌표 검수',
            licenseStatus: 'fixture-only',
          ),
        ],
        stationLineMemberships: [
          NetworkMapStationLineMembership(
            stationId: 'station-polygon',
            lineId: 'seoul-4',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();

    final stationTarget = find.byKey(
      const Key('networkMapStation-polygon-seoul-4'),
    );
    final targetRect = tester.getRect(stationTarget);
    await tester.tapAt(targetRect.topLeft + const Offset(47, 32));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('다각형역'), findsOneWidget);
  });

  testWidgets('노선도 역명 label polygon 영역을 탭하면 해당 역을 선택한다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapData: const NetworkMapData(
        regions: [NetworkMapRegion(name: '테스트권')],
        selectedRegion: '테스트권',
        lines: [
          NetworkMapLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A5DE',
            region: '테스트권',
          ),
        ],
        stations: [
          NetworkMapStation(
            id: 'station-polygon',
            nameKo: '다각형',
            nameEn: 'Polygon',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '499',
            sequence: 99,
            position: NetworkMapPosition(
              x: 100,
              y: 100,
              labelDx: 0,
              labelDy: 0,
              labelPolygon:
                  '[{"x":180,"y":80},{"x":300,"y":80},{"x":300,"y":120},{"x":180,"y":120}]',
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
        ],
        edges: [],
        positionSources: [
          NetworkMapPositionSource(
            id: 'fixture-route-map-source-capital-review',
            name: '수도권 노선도 fixture 좌표 검수',
            licenseStatus: 'fixture-only',
          ),
        ],
        stationLineMemberships: [
          NetworkMapStationLineMembership(
            stationId: 'station-polygon',
            lineId: 'seoul-4',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();
    await tester.tapAt(
      tester.getCenter(
        find.byKey(const Key('networkMapStation-polygon-seoul-4')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('다각형역'), findsOneWidget);
  });

  testWidgets('노선도 배경을 탭하면 가까운 역 sheet를 열지 않는다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapData: const NetworkMapData(
        regions: [NetworkMapRegion(name: '테스트권')],
        selectedRegion: '테스트권',
        lines: [
          NetworkMapLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A5DE',
            region: '테스트권',
          ),
        ],
        stations: [
          NetworkMapStation(
            id: 'station-near',
            nameKo: '가까운역',
            nameEn: 'Near',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '401',
            sequence: 1,
            position: NetworkMapPosition(
              x: 120,
              y: 120,
              labelDx: 0,
              labelDy: 0,
              labelPolygon:
                  '[{"x":300,"y":100},{"x":360,"y":100},{"x":360,"y":140},{"x":300,"y":140}]',
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
        ],
        edges: [],
        positionSources: [
          NetworkMapPositionSource(
            id: 'fixture-route-map-source-capital-review',
            name: '수도권 노선도 fixture 좌표 검수',
            licenseStatus: 'fixture-only',
          ),
        ],
        stationLineMemberships: [
          NetworkMapStationLineMembership(
            stationId: 'station-near',
            lineId: 'seoul-4',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();

    final stationRect = tester.getRect(
      find.byKey(const Key('networkMapStation-near-seoul-4')),
    );
    final nodeCenter = stationRect.topLeft + const Offset(24, 24);
    await tester.tapAt(nodeCenter + const Offset(32, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);
    expect(find.text('가까운역'), findsNothing);

    final surfaceRect = tester.getRect(
      find.byKey(const Key('networkMapSurface')),
    );
    await tester.tapAt(surfaceRect.bottomRight - const Offset(24, 24));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);
    expect(find.text('가까운역'), findsNothing);
  });

  testWidgets('노선도 확대 상태에서도 label 바깥 배경 tap은 sheet를 열지 않는다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapData: const NetworkMapData(
        regions: [NetworkMapRegion(name: '테스트권')],
        selectedRegion: '테스트권',
        lines: [
          NetworkMapLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A5DE',
            region: '테스트권',
          ),
        ],
        stations: [
          NetworkMapStation(
            id: 'station-label',
            nameKo: '라벨역',
            nameEn: 'Label',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '402',
            sequence: 2,
            position: NetworkMapPosition(
              x: 120,
              y: 120,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
        ],
        edges: [],
        positionSources: [
          NetworkMapPositionSource(
            id: 'fixture-route-map-source-capital-review',
            name: '수도권 노선도 fixture 좌표 검수',
            licenseStatus: 'fixture-only',
          ),
        ],
        stationLineMemberships: [
          NetworkMapStationLineMembership(
            stationId: 'station-label',
            lineId: 'seoul-4',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();
    for (var index = 0; index < 3; index += 1) {
      await tester.tap(find.byKey(const Key('networkMapZoomInButton')));
      await tester.pumpAndSettle();
    }

    final stationRect = tester.getRect(
      find.byKey(const Key('networkMapStation-label-seoul-4')),
    );
    await tester.tapAt(stationRect.bottomCenter + const Offset(0, 30));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);
    expect(find.text('라벨역'), findsNothing);
  });

  testWidgets('노선도 label과 marker가 겹치면 marker tap 역을 우선 선택한다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapData: const NetworkMapData(
        regions: [NetworkMapRegion(name: '테스트권')],
        selectedRegion: '테스트권',
        lines: [
          NetworkMapLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A5DE',
            region: '테스트권',
          ),
        ],
        stations: [
          NetworkMapStation(
            id: 'station-a-label',
            nameKo: '가라벨',
            nameEn: 'Label A',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '403',
            sequence: 3,
            position: NetworkMapPosition(
              x: 120,
              y: 120,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
          NetworkMapStation(
            id: 'station-b-node',
            nameKo: '나마커',
            nameEn: 'Marker B',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '404',
            sequence: 4,
            position: NetworkMapPosition(
              x: 150,
              y: 120,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
        ],
        edges: [],
        positionSources: [
          NetworkMapPositionSource(
            id: 'fixture-route-map-source-capital-review',
            name: '수도권 노선도 fixture 좌표 검수',
            licenseStatus: 'fixture-only',
          ),
        ],
        stationLineMemberships: [
          NetworkMapStationLineMembership(
            stationId: 'station-a-label',
            lineId: 'seoul-4',
          ),
          NetworkMapStationLineMembership(
            stationId: 'station-b-node',
            lineId: 'seoul-4',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getCenter(
        find.byKey(const Key('networkMapStation-b-node-seoul-4')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('나마커역'), findsOneWidget);
    expect(find.text('가라벨역'), findsNothing);
  });

  testWidgets('노선도 label끼리 겹치면 tap 위치에 가까운 역을 선택한다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapData: const NetworkMapData(
        regions: [NetworkMapRegion(name: '테스트권')],
        selectedRegion: '테스트권',
        lines: [
          NetworkMapLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A5DE',
            region: '테스트권',
          ),
        ],
        stations: [
          NetworkMapStation(
            id: 'station-a-far',
            nameKo: '먼역',
            nameEn: 'Far',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '405',
            sequence: 5,
            position: NetworkMapPosition(
              x: 120,
              y: 120,
              labelDx: 0,
              labelDy: 60,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
          NetworkMapStation(
            id: 'station-z-near',
            nameKo: '가까운',
            nameEn: 'Near',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '406',
            sequence: 6,
            position: NetworkMapPosition(
              x: 150,
              y: 120,
              labelDx: 0,
              labelDy: 60,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
        ],
        edges: [],
        positionSources: [
          NetworkMapPositionSource(
            id: 'fixture-route-map-source-capital-review',
            name: '수도권 노선도 fixture 좌표 검수',
            licenseStatus: 'fixture-only',
          ),
        ],
        stationLineMemberships: [
          NetworkMapStationLineMembership(
            stationId: 'station-a-far',
            lineId: 'seoul-4',
          ),
          NetworkMapStationLineMembership(
            stationId: 'station-z-near',
            lineId: 'seoul-4',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('bottomNavMap')));
    await tester.pumpAndSettle();

    final farRect = tester.getRect(
      find.byKey(const Key('networkMapStation-a-far-seoul-4')),
    );
    final nearRect = tester.getRect(
      find.byKey(const Key('networkMapStation-z-near-seoul-4')),
    );
    await tester.tapAt(
      Offset(farRect.right - 2, math.min(farRect.bottom, nearRect.bottom) - 20),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('가까운역'), findsOneWidget);
    expect(find.text('먼역역'), findsNothing);
  });

  testWidgets('노선도 동일 station의 여러 line geometry는 visible semantics를 하나로 묶는다', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeStationSearchRepository(
      networkMapData: const NetworkMapData(
        regions: [NetworkMapRegion(name: '테스트권')],
        selectedRegion: '테스트권',
        lines: [
          NetworkMapLine(
            id: 'seoul-2',
            name: '수도권 2호선',
            color: '#00A84D',
            region: '테스트권',
          ),
          NetworkMapLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A5DE',
            region: '테스트권',
          ),
        ],
        stations: [
          NetworkMapStation(
            id: 'station-transfer',
            nameKo: '환승',
            nameEn: 'Transfer',
            region: '테스트권',
            lineId: 'seoul-2',
            stationCode: '201',
            sequence: 1,
            position: NetworkMapPosition(
              x: 120,
              y: 120,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
          NetworkMapStation(
            id: 'station-transfer',
            nameKo: '환승',
            nameEn: 'Transfer',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '401',
            sequence: 2,
            position: NetworkMapPosition(
              x: 180,
              y: 120,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
        ],
        edges: [],
        positionSources: [
          NetworkMapPositionSource(
            id: 'fixture-route-map-source-capital-review',
            name: '수도권 노선도 fixture 좌표 검수',
            licenseStatus: 'fixture-only',
          ),
        ],
        stationLineMemberships: [
          NetworkMapStationLineMembership(
            stationId: 'station-transfer',
            lineId: 'seoul-2',
          ),
          NetworkMapStationLineMembership(
            stationId: 'station-transfer',
            lineId: 'seoul-4',
          ),
        ],
      ),
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bottomNavMap')));
      await tester.pumpAndSettle();

      final canonicalStation = find.byKey(
        const Key('networkMapStation-transfer-seoul-2'),
      );
      expect(canonicalStation, findsOneWidget);
      expect(
        find.byKey(const Key('networkMapStation-transfer-seoul-4')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('환승역'), findsOneWidget);

      final stationSemantics = tester.getSemantics(canonicalStation);
      expect(
        stationSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('노선도 동일 station이라도 떨어진 line geometry는 각각 표시한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeStationSearchRepository(
      networkMapData: const NetworkMapData(
        regions: [NetworkMapRegion(name: '테스트권')],
        selectedRegion: '테스트권',
        lines: [
          NetworkMapLine(
            id: 'seoul-2',
            name: '수도권 2호선',
            color: '#00A84D',
            region: '테스트권',
          ),
          NetworkMapLine(
            id: 'seoul-4',
            name: '수도권 4호선',
            color: '#00A5DE',
            region: '테스트권',
          ),
        ],
        stations: [
          NetworkMapStation(
            id: 'station-transfer',
            nameKo: '환승',
            nameEn: 'Transfer',
            region: '테스트권',
            lineId: 'seoul-2',
            stationCode: '201',
            sequence: 1,
            position: NetworkMapPosition(
              x: 160,
              y: 120,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
          NetworkMapStation(
            id: 'station-center',
            nameKo: '중앙',
            nameEn: 'Center',
            region: '테스트권',
            lineId: 'seoul-2',
            stationCode: '202',
            sequence: 2,
            position: NetworkMapPosition(
              x: 260,
              y: 120,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
          NetworkMapStation(
            id: 'station-transfer',
            nameKo: '환승',
            nameEn: 'Transfer',
            region: '테스트권',
            lineId: 'seoul-4',
            stationCode: '401',
            sequence: 3,
            position: NetworkMapPosition(
              x: 360,
              y: 120,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
        ],
        edges: [],
        positionSources: [
          NetworkMapPositionSource(
            id: 'fixture-route-map-source-capital-review',
            name: '수도권 노선도 fixture 좌표 검수',
            licenseStatus: 'fixture-only',
          ),
        ],
        stationLineMemberships: [
          NetworkMapStationLineMembership(
            stationId: 'station-transfer',
            lineId: 'seoul-2',
          ),
          NetworkMapStationLineMembership(
            stationId: 'station-transfer',
            lineId: 'seoul-4',
          ),
          NetworkMapStationLineMembership(
            stationId: 'station-center',
            lineId: 'seoul-2',
          ),
        ],
      ),
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('bottomNavMap')));
      await tester.pumpAndSettle();

      final firstGeometry = find.byKey(
        const Key('networkMapStation-transfer-seoul-2'),
      );
      final secondGeometry = find.byKey(
        const Key('networkMapStation-transfer-seoul-4'),
      );
      expect(firstGeometry, findsOneWidget);
      expect(secondGeometry, findsOneWidget);
      expect(find.bySemanticsLabel('환승역'), findsNWidgets(2));

      await tester.tapAt(tester.getCenter(secondGeometry));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
      expect(find.text('환승역'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 화면은 v3 기준 큰 행동과 짧은 상태 카드로 구성된다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(
          favorites: [
            _favoriteFacility(
              status: 'NEEDS_CHECK',
              name: '3번 출구 엘리베이터',
              exitId: 'exit-sangnoksu-3',
              description: '3번 출구 앞',
            ),
          ],
        ),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        recentRoutesFuture: Future.value([_favoriteRoute()]),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('어디로 가시나요?'), findsOneWidget);
    expect(find.byKey(const Key('routeSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('heroStationSearchButton')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '길찾기'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '역 검색'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '최근 검색'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '가까운 역'), findsOneWidget);
    expect(find.byKey(const Key('nearbyStationHomeButton')), findsOneWidget);
    expect(find.byKey(const Key('homeHeroCard')), findsOneWidget);
    expect(find.text('시설 알림'), findsOneWidget);
    expect(find.text('상록수역 3번 출구 엘리베이터'), findsOneWidget);
    expect(find.text('정보 확인 필요 · 엘리베이터 확인 필요'), findsOneWidget);
    expect(find.text('주의'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '저장한 시설 보기'), findsOneWidget);
    expect(find.text('대체 1번 출구'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '대체 길 보기'), findsNothing);
    final routeButtonSize = tester.getSize(
      find.byKey(const Key('routeSearchButton')),
    );
    final stationHeroButtonSize = tester.getSize(
      find.byKey(const Key('heroStationSearchButton')),
    );
    expect(routeButtonSize.height, greaterThanOrEqualTo(104));
    expect(stationHeroButtonSize.height, greaterThanOrEqualTo(64));
    expect(routeButtonSize.height, greaterThan(stationHeroButtonSize.height));

    await tester.dragUntilVisible(
      find.text('최근 경로'),
      find.byKey(const Key('homeContentList')),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();
    expect(find.text('최근 경로'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('homeRecentRouteCard')),
      find.byKey(const Key('homeContentList')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(find.text('상록수역'), findsOneWidget);
    expect(find.text('사당역'), findsOneWidget);
    expect(find.text('64분'), findsNothing);
    expect(find.textContaining('이동 점수'), findsNothing);
    expect(find.textContaining('정보 신뢰도'), findsNothing);
    expect(find.byKey(const Key('homeSavedItemsCard')), findsNothing);
  });

  testWidgets('홈 시설 알림은 더 높은 심각도 시설과 다음 행동을 먼저 보여준다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(
          favorites: [
            _favoriteFacility(
              status: 'NEEDS_CHECK',
              name: '3번 출구 엘리베이터',
              exitId: 'exit-sangnoksu-3',
              description: '3번 출구 앞',
            ),
            _favoriteFacility(
              status: 'CLOSED',
              name: '2번 출구 엘리베이터',
              exitId: 'exit-sangnoksu-2',
              description: '2번 출구 앞',
            ),
          ],
        ),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('상록수역 2번 출구 엘리베이터'), findsOneWidget);
    expect(find.text('고장·폐쇄 · 엘리베이터 폐쇄'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '저장한 시설 보기'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('심각도 고장·폐쇄, .*공식 정보, 다음 행동 대체 출구 보기')),
      findsOneWidget,
    );
    expectNoForbiddenUserCopy(tester);
  });

  testWidgets('홈 시설 알림은 주의 상태 시설이 없으면 빈 상태를 보여준다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(
          favorites: [_favoriteFacility()],
        ),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('시설 알림'), findsOneWidget);
    expect(
      find.byKey(const Key('homeFacilityAlertEmptyState')),
      findsOneWidget,
    );
    expect(find.text('확인할 시설 알림이 없어요'), findsOneWidget);
    expect(find.text('정상'), findsNothing);
    expect(find.text('주의'), findsNothing);
    expect(find.byKey(const Key('homeSavedItemsCard')), findsNothing);
  });

  testWidgets('홈은 시설 알림과 최근 경로 로드 실패를 화면에 보여준다', (tester) async {
    final facilityRepository = FakeFavoriteFacilityRepository()
      ..error = const FavoriteFacilityException('시설 알림 실패');
    final routeRepository = FakeFavoriteRouteRepository()
      ..error = const FavoriteRouteException('최근 경로 실패');

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteFacilityRepository: facilityRepository,
        favoriteRouteRepository: routeRepository,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('homeFacilityAlertErrorState')),
      findsOneWidget,
    );
    expect(find.text('시설 알림을 불러오지 못했어요'), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(const Key('homeRecentRouteErrorState')),
      find.byKey(const Key('homeContentList')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(find.text('최근 경로를 불러오지 못했어요'), findsOneWidget);
  });

  testWidgets('홈 가까운 역은 실제 주변 역 검색 화면으로 바로 연결된다', (tester) async {
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

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        locationProvider: locationProvider,
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('가까운 역')),
      findsOneWidget,
    );
    expect(locationProvider.requestCount, 1);
    expect(repository.requestedNearbyLocations, hasLength(1));
    final requested = repository.requestedNearbyLocations.single;
    expect(requested.latitude, closeTo(37.3028, 0.0001));
    expect(requested.longitude, closeTo(126.8665, 0.0001));
    expect(find.text('가장 가까운 역'), findsOneWidget);
    expect(find.text('상록수역'), findsOneWidget);
    expect(find.text('현재 위치 기준 230m · 수도권 2호선'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchInput')), findsNothing);
    expect(find.byKey(const Key('stationRecentSearchSection')), findsNothing);
  });

  testWidgets('가까운 역 화면은 위치 권한 안내 취소 후 재시도 버튼을 유지한다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      location: _freshCurrentLocation(),
      needsPermissionRequest: true,
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        locationProvider: locationProvider,
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('가까운 역')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stationSearchInput')), findsNothing);
    expect(find.byKey(const Key('nearbyStationSearchButton')), findsOneWidget);
    expect(find.text('내 주변 역 다시 찾기'), findsOneWidget);
    expect(locationProvider.requestCount, 0);
  });

  testWidgets('가까운 역 화면은 위치 실패 후 역명 검색 입력을 보여준다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException('현재 위치를 확인하지 못했습니다.'),
      needsPermissionRequest: false,
    );
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        locationProvider: locationProvider,
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(find.text('현재 위치를 확인하지 못했습니다.'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
    expect(find.byKey(const Key('nearbyStationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('stationRecentSearchSection')), findsNothing);

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(repository.requestedQueries, contains('상록수'));
    expect(find.text('상록수역'), findsOneWidget);
  });

  testWidgets('홈 이동 조건 pill은 모든 이동 유형에 맞는 아이콘을 보여준다', (tester) async {
    for (final option in mobilityProfileOptions) {
      await tester.pumpWidget(
        EasySubwayApp(
          key: ValueKey('home-profile-${option.id}'),
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(
            profileId: option.id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('이동 조건: ${option.title} 〉'), findsOneWidget);
      expect(find.byIcon(option.icon), findsOneWidget);
      expect(find.byIcon(Icons.directions_walk), findsNothing);
    }
  });

  testWidgets('홈 핵심 행동은 좁은 화면과 큰 글자에서도 터치 기준을 지킨다', (tester) async {
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

    expect(EasySubwayTouchTarget.iconOnly, 48);
    expect(EasySubwayTouchTarget.general, 56);
    expect(EasySubwayTouchTarget.primary, 60);
    expect(find.text('바로가기'), findsNothing);
    expect(find.byKey(const Key('homeHelpActionButton')), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('routeSearchButton'))).height,
      greaterThanOrEqualTo(104),
    );
    expect(
      tester.getSize(find.byKey(const Key('heroStationSearchButton'))).height,
      greaterThanOrEqualTo(64),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('routeSearchButton'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('heroStationSearchButton'))).dy,
      ),
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('recentSearchButton')),
      find.byKey(const Key('homeContentList')),
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('recentSearchButton'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('homeHeroCard'))).dy,
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('homeProfilePill'))).height,
      greaterThanOrEqualTo(36),
    );
  });

  testWidgets('홈 대화면은 시스템 고대비와 200% 글자에서 핵심 CTA를 유지한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(highContrast: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

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
      await tester.pumpAndSettle();

      final homeContext = tester.element(find.byType(HomeScreen));
      expect(MediaQuery.of(homeContext).highContrast, isTrue);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('routeSearchButton')), findsOneWidget);
      expect(find.byKey(const Key('heroStationSearchButton')), findsOneWidget);
      expect(find.byKey(const Key('homeBottomNavigationBar')), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈은 저장한 경로를 최근 경로로 보여주되 즐겨찾기 카드처럼 보여주지 않는다', (tester) async {
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

      expect(find.text('상록수역 → 사당역'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('최근 경로, 상록수역에서 사당역까지')),
        findsOneWidget,
      );
      expect(find.text('저장한 경로가 없습니다'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈은 저장 경로 재조회 실패를 즐겨찾기 카드로 표시하지 않는다', (tester) async {
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
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('길찾기')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('즐겨찾기한 경로를 불러오지 못했습니다'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '즐겨찾기 경로 보기'), findsNothing);
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

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('설정')),
        findsOneWidget,
      );
      expect(find.text('화면·접근성 설정'), findsNothing);
      expect(find.text('이동 조건'), findsOneWidget);
      expect(find.text('화면 및 접근성'), findsOneWidget);
      expect(find.text('경로 찾기'), findsNothing);
      expect(find.text('기본 지역과 데이터'), findsOneWidget);
      expect(find.text('계단 피하기 · 환승 줄이기 적용 중'), findsOneWidget);
      expect(find.text('계단을 피하고 쉬운 환승을 우선해요'), findsOneWidget);
      expect(find.text('큰 글자'), findsOneWidget);
      expect(find.text('고대비'), findsOneWidget);
      expect(find.text('간편 보기'), findsOneWidget);
      expect(find.text('켜짐'), findsNWidgets(2));
      expect(find.text('꺼짐'), findsOneWidget);
      expect(find.textContaining('데이터팩'), findsNothing);
      expect(find.textContaining('실기기 QA'), findsNothing);
      expect(find.byKey(const Key('mobilityProfileButton')), findsOneWidget);
      expect(
        settingsActionSemantics(
          '계단 피하기 · 환승 줄이기 적용 중, 계단을 피하고 쉬운 환승을 우선해요',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        settingsActionSemantics(
          '큰 글자, 켜짐, 화면 글자와 버튼 설명을 더 크게 보여줘요, 두 번 탭해 끄기',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        settingsActionSemantics(
          '간편 보기, 꺼짐, 필수 행동과 상태 안내를 먼저 보여줘요, 두 번 탭해 켜기',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        settingsActionSemantics(
          '고대비, 켜짐, 버튼과 상태 문구의 대비를 더 강하게 보여줘요, 두 번 탭해 끄기',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('mobilityProfileButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobilityProfileCard-wheelchair')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobilityProfileDoneButton')));
      await tester.pumpAndSettle();

      expect(find.text('계단 피하기 · 엘리베이터 이동 적용 중'), findsOneWidget);
      expect(find.text('계단 없는 길만 안내해요'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('notificationSettingsButton')),
        160,
      );
      await tester.pumpAndSettle();

      expect(find.text('알림'), findsOneWidget);
      expect(find.text('내 활동'), findsOneWidget);
      expect(find.text('개인정보 및 도움말'), findsOneWidget);
      expect(
        find.byKey(const Key('settingsSection-help-privacy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('notificationSettingsButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('offlineDataSettingsButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settingsSupportPrivacyButton')),
        findsOneWidget,
      );
      expect(
        settingsActionSemantics(
          '알림 설정, 시설 상태, 제보 처리, 최신 안내 알림을 관리해요',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
        settingsActionSemantics(
          '도움말·문의, 사용법, 개인정보, 문의 경로를 확인해요',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expectNoForbiddenUserCopy(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('오프라인 데이터 안내는 저장 범위와 품질 제한을 보여준다', (tester) async {
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

    await tester.tap(find.byKey(const Key('bottomNavMore')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('offlineDataSettingsButton')),
      160,
    );
    await tester.ensureVisible(
      find.byKey(const Key('offlineDataSettingsButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offlineDataSettingsButton')));
    await tester.pumpAndSettle();

    expect(find.text('저장된 데이터 상태'), findsOneWidget);
    expect(find.text('지역'), findsOneWidget);
    expect(find.text('수도권 기본 데이터'), findsOneWidget);
    expect(find.text('마지막 갱신'), findsOneWidget);
    expect(find.text('앱에 포함된 기본 데이터'), findsOneWidget);
    expect(find.text('데이터 품질'), findsOneWidget);
    expect(find.text('기본 역·노선 정보 우선'), findsOneWidget);
    expect(find.text('제한 사항'), findsOneWidget);
    expect(find.text('실시간 시설 상태와 제보 전송은 인터넷 연결이 필요해요'), findsOneWidget);
  });

  testWidgets('설정 화면 보기 옵션은 변경값을 저장하고 다시 실행해도 유지한다', (tester) async {
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: true,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);
    await tester.tap(find.byKey(const Key('largeTextSettingsButton')));
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byKey(const Key('largeTextSettingsButton'))),
      ).scale(20),
      closeTo(20, 0.01),
    );
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simpleViewSettingsButton')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 3);
    expect(onboardingStore.savedResult?.preferences.largeTextEnabled, isFalse);
    expect(
      onboardingStore.savedResult?.preferences.highContrastEnabled,
      isTrue,
    );
    expect(onboardingStore.savedResult?.preferences.simpleViewEnabled, isFalse);
    expect(
      find.bySemanticsLabel(RegExp('큰 글자, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('고대비, 켜짐, .*두 번 탭해 끄기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('간편 보기, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final homeContext = tester.element(find.byType(HomeScreen));
    expect(MediaQuery.textScalerOf(homeContext).scale(20), closeTo(20, 0.01));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);
    expect(
      find.bySemanticsLabel(RegExp('큰 글자, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('고대비, 켜짐, .*두 번 탭해 끄기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('간편 보기, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
  });

  testWidgets('설정 화면 보기 옵션 저장 실패는 이전 값으로 되돌린다', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('save failed')) {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: true,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveError: StateError('save failed'),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);
    await tester.tap(find.byKey(const Key('largeTextSettingsButton')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 1);
    expect(onboardingStore.savedResult?.preferences.largeTextEnabled, isTrue);
    expect(
      find.bySemanticsLabel(RegExp('큰 글자, 켜짐, .*두 번 탭해 끄기')),
      findsOneWidget,
    );
    expect(find.text('설정을 저장하지 못했습니다. 이전 값으로 되돌렸어요.'), findsOneWidget);
  });

  testWidgets('설정 화면 이동 조건 저장 실패는 이전 조건으로 되돌린다', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('save failed')) {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences.defaults(),
      ),
      saveError: StateError('save failed'),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);
    await tester.tap(find.byKey(const Key('mobilityProfileButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityProfileCard-wheelchair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityProfileDoneButton')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 1);
    expect(onboardingStore.savedResult?.profile.id, 'elderly');
    expect(find.text('계단 피하기 · 환승 줄이기 적용 중'), findsOneWidget);
    expect(find.text('계단 없는 길만 안내해요'), findsNothing);
    expect(find.text('이동 조건을 저장하지 못했습니다. 이전 조건으로 되돌렸어요.'), findsOneWidget);
  });

  testWidgets('설정 화면 보기 옵션은 빠른 연속 변경에서도 마지막 값을 저장한다', (tester) async {
    final firstSave = Completer<void>();
    final latestSave = Completer<void>();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: true,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);
    await tester.tap(find.byKey(const Key('largeTextSettingsButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('simpleViewSettingsButton')));
    await tester.pump();

    expect(onboardingStore.saveCount, 1);
    expect(
      find.bySemanticsLabel(RegExp('큰 글자, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('고대비, 켜짐, .*두 번 탭해 끄기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('간편 보기, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );

    firstSave.complete();
    await tester.pump();
    expect(onboardingStore.saveCount, 2);
    latestSave.complete();
    await tester.pumpAndSettle();

    expect(onboardingStore.savedResult?.preferences.largeTextEnabled, isFalse);
    expect(
      onboardingStore.savedResult?.preferences.highContrastEnabled,
      isTrue,
    );
    expect(onboardingStore.savedResult?.preferences.simpleViewEnabled, isFalse);
  });

  testWidgets('설정 화면 보기 옵션 첫 저장 실패 뒤에도 마지막 값을 유지한다', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('first save failed')) {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    final firstSave = Completer<void>();
    final latestSave = Completer<void>();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: true,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);
    await tester.tap(find.byKey(const Key('largeTextSettingsButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('simpleViewSettingsButton')));
    await tester.pump();

    firstSave.completeError(StateError('first save failed'));
    await tester.pump();
    expect(onboardingStore.saveCount, 2);
    latestSave.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(onboardingStore.savedResult?.preferences.largeTextEnabled, isFalse);
    expect(
      onboardingStore.savedResult?.preferences.highContrastEnabled,
      isTrue,
    );
    expect(onboardingStore.savedResult?.preferences.simpleViewEnabled, isFalse);
    expect(
      find.bySemanticsLabel(RegExp('큰 글자, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('고대비, 켜짐, .*두 번 탭해 끄기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('간편 보기, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(find.text('설정을 저장하지 못했습니다. 이전 값으로 되돌렸어요.'), findsNothing);
  });

  testWidgets('설정 화면 보기 옵션 마지막 queued 저장 실패는 마지막 변경만 되돌린다', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('latest save failed')) {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    final firstSave = Completer<void>();
    final latestSave = Completer<void>();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: true,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);
    await tester.tap(find.byKey(const Key('largeTextSettingsButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pump();

    firstSave.complete();
    await tester.pump();
    expect(onboardingStore.saveCount, 2);
    latestSave.completeError(StateError('latest save failed'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(onboardingStore.savedResult?.preferences.largeTextEnabled, isFalse);
    expect(
      onboardingStore.savedResult?.preferences.highContrastEnabled,
      isFalse,
    );
    expect(onboardingStore.savedResult?.preferences.simpleViewEnabled, isTrue);
    expect(
      find.bySemanticsLabel(RegExp('큰 글자, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('고대비, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(find.text('설정을 저장하지 못했습니다. 이전 값으로 되돌렸어요.'), findsOneWidget);
  });

  testWidgets('설정 화면 보기 옵션 연속 저장 실패는 마지막 저장값으로 되돌린다', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final exception = details.exceptionAsString();
      if (!exception.contains('first save failed') &&
          !exception.contains('latest save failed')) {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    final firstSave = Completer<void>();
    final latestSave = Completer<void>();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: true,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);
    await tester.tap(find.byKey(const Key('largeTextSettingsButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pump();

    firstSave.completeError(StateError('first save failed'));
    await tester.pump();
    expect(onboardingStore.saveCount, 2);
    latestSave.completeError(StateError('latest save failed'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(onboardingStore.savedResult?.preferences.largeTextEnabled, isTrue);
    expect(
      onboardingStore.savedResult?.preferences.highContrastEnabled,
      isFalse,
    );
    expect(onboardingStore.savedResult?.preferences.simpleViewEnabled, isTrue);
    expect(
      find.bySemanticsLabel(RegExp('큰 글자, 켜짐, .*두 번 탭해 끄기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('고대비, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(find.text('설정을 저장하지 못했습니다. 이전 값으로 되돌렸어요.'), findsOneWidget);
  });

  testWidgets('설정 화면 보기 옵션 저장 중 이동 조건을 바꿔도 마지막 결과를 유지한다', (tester) async {
    final firstSave = Completer<void>();
    final latestSave = Completer<void>();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: true,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);
    await tester.tap(find.byKey(const Key('largeTextSettingsButton')));
    await tester.pump();
    expect(onboardingStore.saveCount, 1);

    await tester.tap(find.byKey(const Key('mobilityProfileButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityProfileCard-wheelchair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityProfileDoneButton')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 1);
    expect(find.text('계단 피하기 · 환승 줄이기 적용 중'), findsOneWidget);

    firstSave.complete();
    await tester.pump();
    expect(onboardingStore.saveCount, 2);
    latestSave.complete();
    await tester.pumpAndSettle();

    expect(onboardingStore.savedResult?.profile.id, 'wheelchair');
    expect(find.text('계단 없는 길만 안내해요'), findsOneWidget);
    expect(onboardingStore.savedResult?.preferences.largeTextEnabled, isFalse);
    expect(
      onboardingStore.savedResult?.preferences.highContrastEnabled,
      isFalse,
    );
    expect(onboardingStore.savedResult?.preferences.simpleViewEnabled, isTrue);
  });

  testWidgets('설정 화면 보기 옵션은 큰 글자에서도 스위치를 조작할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
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
        initialOnboardingState: _completedOnboardingStateWithPreferences(
          preferences: const OnboardingViewPreferences(
            largeTextEnabled: true,
            highContrastEnabled: true,
            simpleViewEnabled: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);

    expect(find.byKey(const Key('largeTextSettingsButton')), findsOneWidget);
    expect(find.byKey(const Key('highContrastSettingsButton')), findsOneWidget);
    expect(find.byKey(const Key('simpleViewSettingsButton')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settingsSection-notification')),
      160,
    );
    await tester.pumpAndSettle();

    expect(find.text('알림은 아직 사용할 수 없어요'), findsOneWidget);
    expect(find.textContaining('실기기 QA'), findsNothing);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
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
    expect(find.text('이동 조건: 천천히 이동 〉'), findsOneWidget);
    expect(find.bySemanticsLabel('길찾기와 역 검색, 현재 이동 조건 천천히 이동'), findsOneWidget);

    await _openMobilityProfileFromSettings(tester);
    await tester.tap(find.byKey(const Key('mobilityProfileCard-wheelchair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityProfileDoneButton')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('routeSearchButton')),
      find.byKey(const Key('homeContentList')),
      const Offset(0, 180),
    );
    await tester.pumpAndSettle();

    expect(find.text('이동 조건: 휠체어 이용 〉'), findsOneWidget);
    expect(find.bySemanticsLabel('길찾기와 역 검색, 현재 이동 조건 휠체어 이용'), findsOneWidget);
    semanticsHandle.dispose();
  });

  testWidgets('홈 즐겨찾기는 하나의 진입점에서 탭 목록을 바로 보여준다', (tester) async {
    final favoriteRepository = FakeFavoriteStationRepository(
      favorites: [_favoriteStation(id: 'station-sangnoksu', name: '상록수')],
    );
    final favoriteFacilityRepository = FakeFavoriteFacilityRepository(
      favorites: [_favoriteFacility()],
    );
    final favoriteRouteRepository = FakeFavoriteRouteRepository(
      favorites: [_favoriteRoute()],
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: favoriteRepository,
        favoriteFacilityRepository: favoriteFacilityRepository,
        favoriteRouteRepository: favoriteRouteRepository,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    expect(find.byKey(const Key('favoritesButton')), findsNothing);
    expect(find.byKey(const Key('favoriteRoutesButton')), findsNothing);
    expect(find.byKey(const Key('favoriteStationsButton')), findsNothing);
    expect(find.byKey(const Key('favoriteFacilitiesButton')), findsNothing);

    await tester.tap(find.byKey(const Key('bottomNavSaved')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('favoriteHomeScreen')), findsOneWidget);
    expect(find.byKey(const Key('favoriteHomeStationsButton')), findsOneWidget);
    expect(
      find.byKey(const Key('favoriteHomeFacilitiesButton')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('favoriteHomeRoutesButton')), findsOneWidget);
    expect(find.text('역 1개'), findsOneWidget);
    expect(find.text('시설 1개'), findsOneWidget);
    expect(find.text('경로 1개'), findsOneWidget);
    expect(favoriteRepository.listCount, greaterThanOrEqualTo(1));
    expect(favoriteFacilityRepository.listCount, greaterThanOrEqualTo(1));
    expect(favoriteRouteRepository.listCount, greaterThanOrEqualTo(1));
    expect(find.byKey(const Key('favoriteRoutesButton')), findsNothing);
    expect(find.byKey(const Key('favoriteStationsButton')), findsNothing);
    expect(find.byKey(const Key('favoriteFacilitiesButton')), findsNothing);
  });

  testWidgets('즐겨찾기 홈 새로고침 실패는 오류 상태로 끝나고 예외를 흘리지 않는다', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('favorite failed')) {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    final favoriteRepository = FakeFavoriteStationRepository()
      ..error = StateError('favorite failed');

    await tester.pumpWidget(
      MaterialApp(
        home: FavoriteHomeScreen(
          favoriteRepository: favoriteRepository,
          favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          stationRepository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          locationProvider: FakeCurrentLocationProvider(),
          facilityReportDraftTargetStore: null,
          internalRouteRepository: FakeInternalRouteRepository(
            result: _internalRouteResult(),
          ),
          realtimeRepository: const UnavailableRealtimeRepository(),
          routeDraftController: RouteDraftController(),
          initialMobilityType: 'SENIOR',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('favoriteHomeErrorState')), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 420));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('favoriteHomeErrorState')), findsOneWidget);
    expect(favoriteRepository.listCount, greaterThanOrEqualTo(2));
  });

  testWidgets('즐겨찾기 하위 화면 복귀 새로고침 실패는 오류 상태로 끝난다', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('favorite failed')) {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    final favoriteRepository = FakeFavoriteStationRepository(
      favorites: [_favoriteStation(id: 'station-sangnoksu', name: '상록수')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: FavoriteHomeScreen(
          favoriteRepository: favoriteRepository,
          favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          stationRepository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          locationProvider: FakeCurrentLocationProvider(),
          facilityReportDraftTargetStore: null,
          internalRouteRepository: FakeInternalRouteRepository(
            result: _internalRouteResult(),
          ),
          realtimeRepository: const UnavailableRealtimeRepository(),
          routeDraftController: RouteDraftController(),
          initialMobilityType: 'SENIOR',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('favoriteHomeStationsButton')));
    await tester.pumpAndSettle();
    favoriteRepository.error = StateError('favorite failed');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('favoriteHomeErrorState')), findsOneWidget);
    expect(favoriteRepository.listCount, greaterThanOrEqualTo(2));
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

      await _openSupportAccessScreen(tester);

      expect(find.text('도움말·문의'), findsOneWidget);
      expect(find.text('개인정보처리방침'), findsOneWidget);
      expect(find.text('https://easysubway.example/privacy'), findsNothing);
      expect(find.text('웹에서 확인'), findsOneWidget);
      final privacyButtonSize = tester.getSize(
        find.byKey(const Key('privacyPolicyAccessItem')),
      );
      expect(privacyButtonSize.height, greaterThanOrEqualTo(60));
      final privacySemantics = tester
          .getSemantics(find.byKey(const Key('privacyPolicyAccessItem')))
          .getSemanticsData();
      expect(
        privacySemantics.label,
        '개인정보처리방침, 웹에서 확인, https://easysubway.example/privacy',
      );
      expect(privacySemantics.hasAction(SemanticsAction.tap), isTrue);

      await tester.scrollUntilVisible(
        find.byKey(const Key('dataDeletionAccessItem')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('데이터 삭제 요청'), findsOneWidget);

      final deletionButtonSize = tester.getSize(
        find.byKey(const Key('dataDeletionAccessItem')),
      );

      expect(deletionButtonSize.height, greaterThanOrEqualTo(60));
      final deletionSemantics = tester
          .getSemantics(find.byKey(const Key('dataDeletionAccessItem')))
          .getSemanticsData();
      expect(
        deletionSemantics.label,
        '데이터 삭제 요청, 이메일 보내기, privacy@easysubway.example, 삭제 범위와 처리 절차를 메일로 문의해요',
      );
      expect(deletionSemantics.hasAction(SemanticsAction.tap), isTrue);

      await tester.scrollUntilVisible(
        find.byKey(const Key('supportAccessItem')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('고객지원'), findsOneWidget);
      expect(find.text('support@easysubway.example'), findsNothing);
      expect(find.text('이메일 보내기'), findsWidgets);
      await tester.scrollUntilVisible(
        find.byKey(const Key('securityContactAccessItem')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('보안 문의'), findsOneWidget);
      expect(find.text('현재 이용할 수 없음 · 준비 중'), findsOneWidget);
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

      await _openSupportAccessScreen(tester);

      expect(find.text('개인정보 사용 안내'), findsOneWidget);
      expect(
        find.text('현재 위치는 가까운 역 찾기와 시설 제보 위치 확인에만 사용됩니다.'),
        findsOneWidget,
      );
      expect(
        find.text('즐겨찾기, 이동 조건, 신고 내용과 사진은 앱 기능 제공에 사용됩니다.'),
        findsOneWidget,
      );
      expect(
        find.text('데이터 삭제 요청은 지원 메일로 삭제 범위와 처리 절차를 문의할 수 있습니다.'),
        findsOneWidget,
      );
      expect(
        find.text('앱 안에서 바로 삭제할 수 없는 데이터는 답변 안내에 따라 처리됩니다.'),
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
        contains('개인정보 사용 안내, 현재 위치는 가까운 역 찾기와 시설 제보 위치 확인에만 사용됩니다.'),
      );
      expect(
        summarySemantics.label,
        contains('앱 안에서 바로 삭제할 수 없는 데이터는 답변 안내에 따라 처리됩니다.'),
      );
      expect(summarySemantics.label, isNot(contains('익명화')));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('도움말은 안전과 데이터 안내를 함께 보여준다', (tester) async {
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

      await _openSupportAccessScreen(tester);

      expect(find.text('안전과 데이터 안내'), findsWidgets);
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

      await _openSupportAccessScreen(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('securityContactNotice')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('보안 문의 안내'), findsOneWidget);
      expect(find.text('취약점이나 개인정보 보호 우려를 발견하면 보안 문의로 알려주세요.'), findsOneWidget);
      expect(find.textContaining('계정 접근'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('securityContactAccessItem')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('보안 문의'), findsOneWidget);
      expect(find.text('security@easysubway.example'), findsNothing);
      expect(find.text('보안 문제 알리기'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const Key('securityContactAccessItem')))
            .getSemanticsData()
            .label,
        '보안 문의, 보안 문제 알리기, security@easysubway.example',
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

    await _openSupportAccessScreen(tester);
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

    await _openSupportAccessScreen(tester);
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

    await _openSupportAccessScreen(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('dataDeletionAccessItem')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('dataDeletionAccessItem')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('dataDeletionStartButton')), findsOneWidget);
    expect(find.text('이 기기의 앱 데이터 삭제'), findsWidgets);
    expect(find.textContaining('즐겨찾기, 최근 검색, 이동 조건, 화면 설정'), findsOneWidget);
    expect(
      find.text('이미 보낸 시설 제보, 사진, 위치 정보는 이 작업으로 삭제되지 않습니다.'),
      findsOneWidget,
    );
    expect(find.text('삭제한 데이터는 앱에서 복구할 수 없습니다.'), findsOneWidget);
    expect(find.textContaining('로그인 정보'), findsNothing);
    expect(find.textContaining('익명화'), findsNothing);

    await tester.tap(find.byKey(const Key('dataDeletionStartButton')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('정말 삭제할까요?'), findsOneWidget);
    expect(find.textContaining('인증 정보'), findsNothing);
    expect(
      find.text('삭제 후에는 이 기기에 저장된 앱 데이터와 설정이 지워지고 되돌릴 수 없습니다.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('dataDeletionConfirmButton')));
    await tester.pumpAndSettle();

    expect(deletionRepository.deleteCount, 1);
    expect(find.text('삭제 완료'), findsOneWidget);
    expect(find.text('내 데이터가 삭제됐어요'), findsOneWidget);
    expect(find.text('즐겨찾기한 역'), findsOneWidget);
    expect(find.text('1개 삭제'), findsWidgets);
    expect(find.text('이 기기의 제보 기록'), findsOneWidget);
    expect(find.text('1건 삭제'), findsOneWidget);
    expect(find.textContaining('연결 정보'), findsNothing);
    expect(find.textContaining('익명화'), findsNothing);
    expect(find.textContaining('local-user'), findsNothing);
    expect(
      find.byKey(const Key('dataDeletionResultStatus-favoriteStations')),
      findsOneWidget,
    );
    final stationIconBadge = tester.widget<Container>(
      find.byKey(const Key('dataDeletionResultIcon-favoriteStations')),
    );
    final stationIconDecoration = stationIconBadge.decoration! as BoxDecoration;
    expect(stationIconDecoration.border, isNotNull);
    expect(stationIconDecoration.color, Colors.white);
    expect(
      (stationIconDecoration.border! as Border).top.color,
      EasySubwayAccessibleColors.mintDark,
    );
    expect((stationIconDecoration.border! as Border).top.width, 2);
    final stationRow = tester.getRect(
      find.byKey(const Key('dataDeletionResultRow-favoriteStations')),
    );
    final facilityRow = tester.getRect(
      find.byKey(const Key('dataDeletionResultRow-favoriteFacilities')),
    );
    expect(facilityRow.top - stationRow.bottom, greaterThanOrEqualTo(16));
    expectNoForbiddenUserCopy(tester);

    await tester.tap(find.byKey(const Key('dataDeletionResultStartButton')));
    await tester.pumpAndSettle();

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
    expect(find.byKey(const Key('startScreenStartButton')), findsOneWidget);
  });

  testWidgets('데이터 삭제 결과 시작 버튼은 Android 시스템 내비게이션 바와 여백을 둔다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MaterialApp(
        home: UserDataDeletionResultScreen(
          result: const UserDataDeletionResult(
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
          ),
          deletionScope: UserDataDeletionScope.deviceOnly,
          onRestart: () {},
        ),
      ),
    );

    final screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final buttonRect = tester.getRect(
      find.byKey(const Key('dataDeletionResultStartButton')),
    );

    expect(screenBottom - buttonRect.bottom, greaterThanOrEqualTo(66));
  });

  testWidgets('도움말은 원격 삭제 저장소에서 서버 삭제 범위를 유지해 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final deletionRepository = UserDataDeletionApiRepository(
      baseUri: Uri.parse('https://api.easysubway.example'),
      authProvider: const NoAuthorizationHeaderProvider(),
    );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          userDataDeletionRepository: deletionRepository,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openSupportAccessScreen(tester);

      expect(
        find.text(
          '서버 데이터 삭제는 즐겨찾기, 신고 접수 기록, 신고 내용과 사진, 위치, 경로 피드백을 삭제하거나 익명화하고 앱의 임시 설정을 초기화합니다.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('이미 보낸 시설 제보, 사진, 위치 정보, 경로 피드백은 서버에서 삭제되거나 익명화됩니다.'),
        findsOneWidget,
      );

      final summarySemantics = tester
          .getSemantics(find.byKey(const Key('privacyDataUseSummary')))
          .getSemanticsData();
      expect(
        summarySemantics.label,
        contains(
          '서버 데이터 삭제는 즐겨찾기, 신고 접수 기록, 신고 내용과 사진, 위치, 경로 피드백을 삭제하거나 익명화하고 앱의 임시 설정을 초기화합니다.',
        ),
      );
      expect(
        summarySemantics.label,
        contains('이미 보낸 시설 제보, 사진, 위치 정보, 경로 피드백은 서버에서 삭제되거나 익명화됩니다.'),
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('dataDeletionAccessItem')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('dataDeletionAccessItem')));
      await tester.pumpAndSettle();

      expect(find.text('서버 데이터 삭제'), findsWidgets);
      expect(
        find.text(
          '데이터 삭제 요청 시 즐겨찾기, 이동 조건, 신고 접수 기록, 신고 내용·사진·위치와 경로 피드백을 삭제하거나 익명화합니다.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('이미 보낸 시설 제보'), findsNothing);
      expect(
        find.text('삭제가 끝나면 서버에 연결된 데이터가 정리되고 앱의 임시 설정이 초기화됩니다.'),
        findsOneWidget,
      );
      expect(find.text('앱은 처음 설정 화면으로 돌아갑니다.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('dataDeletionStartButton')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text(
          '삭제 후에는 서버에 연결된 데이터와 설정이 삭제되거나 익명화되고 앱의 임시 설정이 초기화됩니다. 되돌릴 수 없습니다.',
        ),
        findsOneWidget,
      );
    } finally {
      semanticsHandle.dispose();
    }
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

    await _openSupportAccessScreen(tester);
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

    await _openSupportAccessScreen(tester);

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
      '개인정보처리방침, 현재 이용할 수 없음 · 준비 중',
    );

    await tester.tap(find.byKey(const Key('privacyPolicyAccessItem')));
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
      '데이터 삭제 요청, 현재 이용할 수 없음 · 준비 중, 삭제 범위와 처리 절차를 메일로 문의해요',
    );
    await tester.tap(find.byKey(const Key('dataDeletionAccessItem')));
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
      '고객지원, 현재 이용할 수 없음 · 준비 중',
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
      '보안 문의, 현재 이용할 수 없음 · 준비 중',
    );
    await tester.tap(find.byKey(const Key('securityContactAccessItem')));
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

    await _openSupportAccessScreen(tester);
    await tester.tap(find.byKey(const Key('privacyPolicyAccessItem')));
    await tester.pump();

    expect(
      find.text('연결할 수 없습니다. 직접 확인해 주세요: https://easysubway.example/privacy'),
      findsOneWidget,
    );
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
      expect(find.text('제보 처리 알림'), findsOneWidget);
      expect(find.text('정보 갱신 알림'), findsNothing);
      expect(find.text('최신 안내 알림'), findsOneWidget);
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
        '즐겨찾는 역과 경로의 시설 변경, 제보 처리 상황, 최신 안내를 알려드려요. 알림 설정에서 언제든 끌 수 있습니다.',
      ),
      findsOneWidget,
    );
    expect(notificationPermissionProvider.requestCount, 0);

    await tester.tap(find.text('켜기'));
    await tester.pumpAndSettle();

    expect(notificationPermissionProvider.requestCount, 1);
    expect(find.text('기기 알림이 켜졌습니다.'), findsNothing);
    expect(find.text('알림이 켜졌어요.'), findsOneWidget);
    expect(find.bySemanticsLabel('알림이 켜졌어요.'), findsOneWidget);
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
    expect(find.text('기기 알림 권한을 켜 주세요.'), findsNothing);
    expect(find.text('휴대전화 설정에서 알림을 허용해 주세요.'), findsOneWidget);
    expect(find.bySemanticsLabel('휴대전화 설정에서 알림을 허용해 주세요.'), findsOneWidget);
    expect(find.text('기기 알림 설정과 네트워크 상태를 확인한 뒤 다시 시도해 주세요.'), findsNothing);
  });

  testWidgets('알림 설정 화면은 기기 알림 실패 다음 행동을 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final notificationPermissionProvider = FakeNotificationPermissionProvider(
      nextStatus: NotificationPermissionStatus.denied,
      error: const NotificationSettingsException('알림을 켜지 못했어요.'),
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
      expect(find.text('기기 알림 등록을 마치지 못했습니다.'), findsNothing);
      expect(find.text('알림을 켜지 못했어요.'), findsOneWidget);
      expect(
        find.text('휴대전화 알림 설정과 인터넷 연결을 확인한 뒤 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('다음 행동, 휴대전화 알림 설정과 인터넷 연결을 확인한 뒤 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('notificationRegistrationFailureNextAction')),
        ),
        isSemantics(
          label: '다음 행동, 휴대전화 알림 설정과 인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
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

      expect(find.text('즐겨찾기한 역'), findsOneWidget);
      expect(find.text('상록수'), findsOneWidget);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('기본 정보만 있음'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '출발지로 설정'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '도착지로 설정'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '역 상세 보기'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '시설 상태 확인'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '즐겨찾기 해제'), findsOneWidget);
      expect(
        find.byKey(const Key('favoriteStationTile-station-sangnoksu')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('즐겨찾기 역, 상록수, 수도권 4호선, 수도권, 기본 정보만 있음'),
        findsOneWidget,
      );
      expect(find.text('출처 공식 파일'), findsNothing);

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

  testWidgets('즐겨찾기 역 목록은 경로 draft controller가 없으면 경로 설정 버튼을 숨긴다', (
    tester,
  ) async {
    final favoriteRepository = FakeFavoriteStationRepository(
      favorites: [_favoriteStation(id: 'station-sangnoksu', name: '상록수')],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FavoriteStationListContent(
            repository: favoriteRepository,
            stationRepository: FakeStationSearchRepository(),
            reportRepository: FakeFacilityReportRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('상록수'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '출발지로 설정'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '도착지로 설정'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '역 상세 보기'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '시설 상태 확인'), findsOneWidget);
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

      expect(find.text('즐겨찾기한 시설'), findsOneWidget);
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('이용 가능'), findsOneWidget);
      expect(find.text('상태 확인 필요'), findsOneWidget);
      expect(find.text('정보 신뢰도 높음'), findsNothing);
      expect(find.text('출처 공식 파일'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '상태 제보'), findsOneWidget);
      expect(
        find.byKey(
          const Key('favoriteFacilityTile-facility-sangnoksu-elevator-1'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '즐겨찾기 시설, 1번 출구 엘리베이터, 상록수역, 엘리베이터, 이용 가능, 1번 출구 앞, 최근 확인 2026-06-12, 상태 확인 필요, 다음 행동 상태 제보',
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

  testWidgets('홈 즐겨찾기 시설 제보는 위치 권한 확인 흐름을 유지한다', (tester) async {
    final favoriteFacilityRepository = FakeFavoriteFacilityRepository(
      favorites: [_favoriteFacility()],
    );
    final locationProvider = FakeCurrentLocationProvider(
      needsPermissionRequest: true,
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: favoriteFacilityRepository,
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openFavoriteList(
      tester,
      tabKey: const Key('favoriteFacilitiesTabButton'),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '상태 제보'));
    await tester.pumpAndSettle();

    expect(locationProvider.permissionCheckCount, 1);
    expect(locationProvider.requestCount, 0);
    expect(find.text('현재 위치 사용'), findsOneWidget);
    expect(find.text('가까운 역 찾기와 시설 제보 위치 확인에만 현재 위치를 사용합니다.'), findsOneWidget);
  });

  testWidgets('홈 즐겨찾기 경로는 저장한 경로를 큰 목록으로 보여주고 삭제한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final favoriteRouteRepository = FakeFavoriteRouteRepository(
      favorites: [_favoriteRoute()],
    );
    final routeDraftController = RouteDraftController();
    RouteDraft? searchAgainDraft;
    String? searchAgainMobilityType;

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

      await _openFavoriteList(
        tester,
        routeDraftController: routeDraftController,
        onOpenRouteSearch: (draft, mobilityType) async {
          searchAgainDraft = draft;
          searchAgainMobilityType = mobilityType;
        },
      );

      expect(find.text('즐겨찾기한 경로'), findsOneWidget);
      expect(find.text('상록수에서 사당까지'), findsOneWidget);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('천천히 이동'), findsOneWidget);
      expect(find.text('이동 편의도 92점'), findsNothing);
      expect(find.text('상세 이동 정보는 다시 검색해 확인'), findsOneWidget);
      expect(
        find.text('기준: 천천히 이동, 수도권 4호선, 최근 확인 2026-06-13'),
        findsOneWidget,
      );
      expect(find.text('예상 시간 확인 필요 · 환승 확인 필요 · 도보 확인 필요'), findsOneWidget);
      expect(find.text('계단 정보 확인 필요 · 엘리베이터 연결 확인 필요'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '즐겨찾기 경로, 상록수에서 사당까지, 수도권 4호선, 천천히 이동, 상세 이동 정보는 다시 검색해 확인, 기준 천천히 이동, 수도권 4호선, 최근 확인 2026-06-13, 예상 시간 확인 필요, 환승 확인 필요, 도보 확인 필요, 계단 정보 확인 필요, 엘리베이터 연결 확인 필요',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('상록수에서 사당까지 더 보기'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('상록수에서 사당까지 더 보기')),
        isSemantics(
          label: '상록수에서 사당까지 더 보기',
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(
        find.byKey(const Key('favoriteRouteSearchAgain-route-1')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('favoriteRouteSearchAgain-route-1')),
      );
      await tester.pumpAndSettle();

      expect(searchAgainDraft?.origin?.id, 'station-sangnoksu');
      expect(searchAgainDraft?.origin?.nameKo, '상록수');
      expect(searchAgainDraft?.destination?.id, 'station-sadang');
      expect(searchAgainDraft?.destination?.nameKo, '사당');
      expect(searchAgainMobilityType, 'SENIOR');

      await _openFavoriteList(
        tester,
        routeDraftController: routeDraftController,
        onOpenRouteSearch: (draft, mobilityType) async {
          searchAgainDraft = draft;
          searchAgainMobilityType = mobilityType;
        },
      );

      await tester.tap(find.byKey(const Key('favoriteRouteMore-route-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('favoriteRouteRemove-route-1')));
      await tester.pumpAndSettle();
      expect(find.text('즐겨찾기 경로 삭제'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('favoriteRouteRemoveConfirm-route-1')),
      );
      await tester.pumpAndSettle();

      expect(favoriteRouteRepository.removedFavoriteRouteIds, ['route-1']);
      expect(find.text('즐겨찾기한 경로가 없습니다.'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('경로 0개'), findsOneWidget);
      expect(find.text('최근 경로'), findsNothing);

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

    await tester.tap(find.byKey(const Key('favoriteRouteMore-route-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favoriteRouteRemove-route-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('favoriteRouteRemoveConfirm-route-1')),
    );
    await tester.pump();

    expect(favoriteRouteRepository.removedFavoriteRouteIds, ['route-1']);
    expect(find.text('삭제 중'), findsOneWidget);
    expect(find.bySemanticsLabel('상록수에서 사당까지 더 보기, 삭제 중'), findsOneWidget);

    await tester.tap(find.byKey(const Key('favoriteRouteMore-route-1')));
    await tester.pump();

    expect(favoriteRouteRepository.removedFavoriteRouteIds, ['route-1']);

    removeCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('즐겨찾기한 경로가 없습니다.'), findsOneWidget);
  });

  testWidgets('즐겨찾기 경로 다시 찾기는 저장된 이동 조건으로 연다', (tester) async {
    final favoriteRouteRepository = FakeFavoriteRouteRepository(
      favorites: [_favoriteRoute(mobilityType: 'WHEELCHAIR')],
    );
    final routeDraftController = RouteDraftController();
    RouteDraft? searchAgainDraft;
    String? searchAgainMobilityType;

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: favoriteRouteRepository,
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(profileId: 'elderly'),
      ),
    );

    await _openFavoriteList(
      tester,
      routeDraftController: routeDraftController,
      onOpenRouteSearch: (draft, mobilityType) async {
        searchAgainDraft = draft;
        searchAgainMobilityType = mobilityType;
      },
    );

    await tester.tap(find.byKey(const Key('favoriteRouteSearchAgain-route-1')));
    await tester.pumpAndSettle();

    expect(searchAgainDraft?.origin?.id, 'station-sangnoksu');
    expect(searchAgainDraft?.destination?.id, 'station-sadang');
    expect(searchAgainMobilityType, 'WHEELCHAIR');
  });

  testWidgets('즐겨찾기 경로 목록 실패는 다음 행동을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final favoriteRouteRepository = FakeFavoriteRouteRepository()
      ..error = const FavoriteRouteException('즐겨찾기 경로를 불러오지 못했습니다.');

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FavoriteRouteListContent(repository: favoriteRouteRepository),
          ),
        ),
      );
      await tester.pumpAndSettle();

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
      expect(
        find.byKey(const Key('stationLineBadge-korail-gyeongui-jungang')),
        findsOneWidget,
      );
      expect(find.text('수도권 4호선, 경의중앙선'), findsOneWidget);
      expect(find.text('수도권'), findsNothing);
      expect(find.text('기본 정보만 있음'), findsOneWidget);
      expect(find.text('출처 확인 필요'), findsNothing);
      expect(find.bySemanticsLabel('검색 결과 1개'), findsOneWidget);
      expect(
        find.bySemanticsLabel('상록수역, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 있음'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('상록수역, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 있음'),
        ),
        isSemantics(
          label: '상록수역, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 있음',
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

      final lineBadgeImage = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('stationLineBadge-seoul-4')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (lineBadgeImage.image as AssetImage).assetName,
        'assets/metro_symbols/line_badges/seoul_4_compact_256.png',
      );

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

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('길찾기')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('routeOriginPointButton')),
        matching: find.text('상록수역'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('routeDestinationPointButton')),
        matching: find.text('사당역'),
      ),
      findsOneWidget,
    );
    expect(find.text('노선 정보 없음'), findsNothing);
    final semanticsHandle = tester.ensureSemantics();
    try {
      expect(find.bySemanticsLabel('출발 상록수역'), findsOneWidget);
      expect(find.bySemanticsLabel('도착 사당역'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('경로 검색 첫 화면은 v3 출발 도착 입력 구조를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: FakeRouteSearchRepository(),
            stationRepository: FakeStationSearchRepository(),
            favoriteRouteRepository: FakeFavoriteRouteRepository(
              favorites: [_favoriteRoute()],
            ),
            initialMobilityType: 'SENIOR',
            initialDraft: RouteDraft(
              origin: const RouteDraftStation(
                id: 'station-sangnoksu',
                nameKo: '상록수',
              ),
              destination: const RouteDraftStation(
                id: 'station-sadang',
                nameKo: '사당',
              ),
              lastModifiedAt: DateTime(2026, 6, 23),
            ),
          ),
        ),
      );

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('길찾기')),
        findsOneWidget,
      );
      expect(find.text('출발·도착 입력'), findsNothing);
      expect(find.text('출'), findsNothing);
      expect(find.text('도'), findsNothing);
      expect(find.text('출발역'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('routeOriginPointButton')),
          matching: find.text('상록수역'),
        ),
        findsOneWidget,
      );
      expect(find.text('도착역'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('routeDestinationPointButton')),
          matching: find.text('사당역'),
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('routeOriginPointButton')), findsOneWidget);
      expect(
        find.byKey(const Key('routeDestinationPointButton')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('출발 도착 바꾸기'), findsOneWidget);
      expect(find.text('이동 조건'), findsOneWidget);
      expect(find.text('계단 피하기 · 환승 줄이기'), findsWidgets);
      expect(find.widgetWithText(FilledButton, '길찾기'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(find.text('최근 도착지'), findsOneWidget);
      expect(find.text('사당역'), findsWidgets);
      expect(
        find.byKey(const Key('routeRecentLineMark-line-4')),
        findsOneWidget,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('경로 검색은 출발 도착 선택 전 CTA 사유와 입력창 검색 아이콘을 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: FakeRouteSearchRepository(),
            stationRepository: FakeStationSearchRepository(),
            favoriteRouteRepository: FakeFavoriteRouteRepository(),
            initialMobilityType: 'SENIOR',
          ),
        ),
      );

      final submitButton = tester.widget<FilledButton>(
        find.byKey(const Key('routeSearchSubmitButton')),
      );
      expect(submitButton.onPressed, isNull);
      expect(
        find.bySemanticsLabel('길찾기, 출발역과 도착역을 먼저 선택해 주세요'),
        findsOneWidget,
      );

      await _openRouteOriginStationInput(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('routePointPickerCard')),
          matching: find.byKey(const Key('routeOriginStationInput')),
        ),
        findsOneWidget,
      );
      final originInput = tester.widget<TextField>(
        find.byKey(const Key('routeOriginStationInput')),
      );
      expect(originInput.decoration?.suffixIcon, isNotNull);
      expect(
        find.descendant(
          of: find.byKey(const Key('routePointPickerCard')),
          matching: find.byKey(const Key('routeOriginStationSearchButton')),
        ),
        findsOneWidget,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('길찾기 하단 버튼은 Android 시스템 내비게이션 바와 여백을 둔다', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(),
          stationRepository: FakeStationSearchRepository(),
          initialMobilityType: 'SENIOR',
        ),
      ),
    );

    final screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final buttonRect = tester.getRect(
      find.byKey(const Key('routeSearchSubmitButton')),
    );

    expect(screenBottom - buttonRect.bottom, greaterThanOrEqualTo(66));
  });

  testWidgets('길찾기 하단 버튼은 가로 safe-area 안쪽에 배치된다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(
      left: 44,
      right: 56,
      bottom: 34,
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(),
          stationRepository: FakeStationSearchRepository(),
          initialMobilityType: 'SENIOR',
        ),
      ),
    );

    final buttonRect = tester.getRect(
      find.byKey(const Key('routeSearchSubmitButton')),
    );

    expect(buttonRect.left, greaterThanOrEqualTo(44));
    expect(390 - buttonRect.right, greaterThanOrEqualTo(56));
  });

  testWidgets('길찾기 하단 버튼은 키보드가 열려도 가려지지 않는다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(),
          stationRepository: FakeStationSearchRepository(),
          initialMobilityType: 'SENIOR',
        ),
      ),
    );

    final visibleBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        tester.view.viewInsets.bottom;
    final buttonRect = tester.getRect(
      find.byKey(const Key('routeSearchSubmitButton')),
    );

    expect(visibleBottom - buttonRect.bottom, greaterThanOrEqualTo(20));
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

      await tester.tap(find.byKey(const Key('recentSearchButton')));
      await tester.pumpAndSettle();

      expect(find.text('최근 검색'), findsOneWidget);
      expect(find.byKey(const Key('stationSearchInput')), findsNothing);
      expect(
        find.byKey(const Key('stationRecentSearchSection')),
        findsOneWidget,
      );
      expect(find.text('최근 사용 순서 · 2개'), findsOneWidget);
      expect(find.bySemanticsLabel('최근 사용 순서로 2개 표시'), findsOneWidget);
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

  testWidgets('역 검색 최근 검색은 개별 삭제와 전체 삭제 및 빈 상태 CTA를 제공한다', (tester) async {
    final searchHistoryRepository = FakeSearchHistoryRepository(['상록수', '사당']);

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        searchHistoryRepository: searchHistoryRepository,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('recentSearchButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stationRecentSearchRemove-상록수')));
    await tester.pumpAndSettle();

    expect(searchHistoryRepository.removedQueries, ['상록수']);
    expect(find.byKey(const Key('stationRecentSearchQuery-상록수')), findsNothing);
    expect(find.text('최근 사용 순서 · 1개'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('stationRecentSearchClearAllButton')),
    );
    await tester.pumpAndSettle();

    expect(searchHistoryRepository.clearCount, 1);
    expect(
      find.byKey(const Key('stationRecentSearchEmptyState')),
      findsOneWidget,
    );
    expect(find.text('최근 검색한 역이 없습니다.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '역 검색하기'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('stationRecentSearchEmptySearchButton')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
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

    expect(find.byKey(const Key('stationLineBadge-seoul-4')), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(find.text('경의중앙'), findsNothing);

    final resultTileSize = tester.getSize(
      find.byKey(const Key('stationSearchResult-station-transfer')),
    );
    expect(resultTileSize.height, lessThanOrEqualTo(112));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  });

  testWidgets('역 검색 노선 필터는 지역을 먼저 고르고 전체 노선은 바텀시트로 연다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeStationSearchRepository(
      lineOptions: const [
        SubwayLineOption(
          id: 'busan-1',
          name: '부산 1호선',
          color: '#F06A00',
          region: '부산',
          lineCode: '1',
          active: true,
        ),
        SubwayLineOption(
          id: 'seoul-4',
          name: '수도권 4호선',
          color: '#00A5DE',
          region: '수도권',
          lineCode: '4',
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

      expect(find.byKey(const Key('stationLineFilterPanel')), findsOneWidget);
      expect(find.byKey(const Key('stationLineRegion-수도권')), findsOneWidget);
      expect(find.byKey(const Key('stationLineRegion-부산')), findsOneWidget);
      expect(
        find.byKey(const Key('stationLineFilter-seoul-4')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stationLineFilter-busan-1')), findsNothing);
      expect(find.text('운행 중지 노선'), findsNothing);

      await tester.tap(find.byKey(const Key('stationLineRegion-부산')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('stationLineFilter-busan-1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stationLineFilter-seoul-4')), findsNothing);
      expect(find.bySemanticsLabel('부산 1호선 선택 안 됨'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stationLineFilterMoreButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stationLineAllSheet')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('stationLineAllSheet')),
          matching: find.text('전체 노선 보기'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationLineFilter-seoul-4')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stationLineFilter-busan-1')), findsWidgets);
      expect(find.text('운행 중지 노선'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색 결과는 입력창 바로 아래에 먼저 보이고 필터는 접을 수 있다', (tester) async {
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
    await tester.pumpAndSettle();

    final resultTop = tester
        .getTopLeft(
          find.byKey(const Key('stationSearchResult-station-sangnoksu')),
        )
        .dy;
    final filterTop = tester
        .getTopLeft(find.byKey(const Key('stationLineFilterPanel')))
        .dy;
    expect(resultTop, lessThan(filterTop));
    expect(find.text('노선 필터 펼치기'), findsOneWidget);
    expect(find.byKey(const Key('stationLineFilter-seoul-4')), findsNothing);

    await tester.tap(find.byKey(const Key('stationLineFilterToggle')));
    await tester.pumpAndSettle();

    expect(find.text('노선 필터 접기'), findsOneWidget);
    expect(find.byKey(const Key('stationLineFilter-seoul-4')), findsOneWidget);
  });

  testWidgets('역 검색은 태블릿 landscape에서 결과와 필터를 나란히 보여준다', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationSearchLargeScreenLayout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stationLineFilterPanel')), findsOneWidget);
    expect(find.text('노선 필터 펼치기'), findsOneWidget);

    final resultRect = tester.getRect(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    final filterRect = tester.getRect(
      find.byKey(const Key('stationLineFilterPanel')),
    );
    final inputRect = tester.getRect(
      find.byKey(const Key('stationSearchInput')),
    );

    expect(inputRect.right, lessThan(filterRect.left));
    expect(resultRect.right, lessThan(filterRect.left));
    expect(filterRect.top, lessThan(resultRect.bottom));
  });

  testWidgets('역 검색 대화면은 경계 폭 큰 글씨와 긴 노선명에서 렌더링된다', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = FakeStationSearchRepository(
      lineOptions: const [
        SubwayLineOption(
          id: 'gyeongui-jungang',
          name: '경의중앙선',
          color: '#77C4A3',
          region: '수도권',
          lineCode: '경의중앙',
          active: true,
        ),
        SubwayLineOption(
          id: 'ui-sinseol',
          name: '우이신설선',
          color: '#B7C452',
          region: '수도권',
          lineCode: '우이신설',
          active: true,
        ),
        SubwayLineOption(
          id: 'gimpo-gold',
          name: '김포골드라인',
          color: '#AD8605',
          region: '수도권',
          lineCode: '김포골드',
          active: true,
        ),
        SubwayLineOption(
          id: 'airport-railroad',
          name: '공항철도',
          color: '#0090D2',
          region: '수도권',
          lineCode: '공항',
          active: true,
        ),
        SubwayLineOption(
          id: 'shinbundang',
          name: '신분당선',
          color: '#D31145',
          region: '수도권',
          lineCode: '신분당',
          active: true,
        ),
      ],
      nextResults: [
        const StationSearchResult(
          id: 'station-transfer',
          nameKo: '디지털미디어시티',
          nameEn: 'Digital Media City',
          region: '수도권',
          dataQualityLevel: 'LEVEL_1',
          lastVerifiedAt: '2026-06-12',
          lines: [
            StationSearchLine(
              id: 'gyeongui-jungang',
              name: '경의중앙선',
              color: '#77C4A3',
              stationCode: 'K316',
            ),
            StationSearchLine(
              id: 'airport-railroad',
              name: '공항철도',
              color: '#0090D2',
              stationCode: 'A04',
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
        initialOnboardingState: _completedOnboardingStateWithPreferences(
          preferences: const OnboardingViewPreferences(
            largeTextEnabled: true,
            highContrastEnabled: true,
            simpleViewEnabled: false,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '디지털');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('stationSearchLargeScreenLayout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationSearchResult-station-transfer')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stationLineFilterPanel')), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
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
      final lineFilterImage = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('stationLineFilter-seoul-4')),
          matching: find.byType(Image),
        ),
      );
      expect(
        (lineFilterImage.image as AssetImage).assetName,
        'assets/metro_symbols/line_badges/seoul_4_compact_256.png',
      );
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

      await tester.tap(find.byKey(const Key('stationLineFilterToggle')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('stationLineFilter-all')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stationLineFilter-all')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('stationSearchSubmitButton')),
      );
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
      expect(find.byKey(const Key('nearbyStationPrimaryCard')), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '가장 가까운 역, 상록수역, 현재 위치 기준 230m, 수도권 2호선, 수도권, 기본 정보만 있음',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('상록수역을 출발역으로 설정'), findsOneWidget);
      expect(find.bySemanticsLabel('상록수역을 도착역으로 설정'), findsOneWidget);

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

  testWidgets('주변 역은 첫 결과를 대표 카드로 분리하고 나머지만 목록에 보여준다', (tester) async {
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
        _stationResult(id: 'station-sadang', name: '사당', distanceMeters: 520),
        _stationResult(id: 'station-gangnam', name: '강남', distanceMeters: 790),
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

    final primaryCard = find.byKey(const Key('nearbyStationPrimaryCard'));
    expect(primaryCard, findsOneWidget);
    expect(
      find.descendant(of: primaryCard, matching: find.text('상록수역')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: primaryCard, matching: find.text('사당역')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      findsNothing,
    );
    expect(find.text('다른 주변 역'), findsOneWidget);
    expect(
      find.byKey(const Key('stationSearchResult-station-sadang')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('stationSearchResult-station-gangnam')),
      findsOneWidget,
    );
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
    expect(find.text('가까운 역 찾기와 시설 제보 위치 확인에만 현재 위치를 사용합니다.'), findsOneWidget);
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
        '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
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

    expect(find.text('휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
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
        StationFacilityInfo(
          id: 'facility-sangnoksu-info-needed',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-3',
          type: 'ESCALATOR',
          name: '3번 출구 에스컬레이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '3번 출구 앞',
          status: 'NEEDS_CHECK',
          dataConfidence: 'LOW',
          dataSourceType: 'OFFICIAL_FILE',
          lastUpdatedAt: '2026-06-10',
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
      expect(find.text('기본 정보만 있음'), findsOneWidget);
      expect(find.text('출처 공식 파일'), findsNothing);
      expect(
        find.bySemanticsLabel('상록수역, 수도권 2호선, 수도권, 기본 정보만 있음'),
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
      expect(find.text('마지막 확인 2026-06-13'), findsOneWidget);
      expect(find.text('출처 공식 파일'), findsNothing);
      expect(find.text('이동 전 현장 안내와 역무원 안내를 확인해 주세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('안전 안내, 이동 전 현장 안내와 역무원 안내를 확인해 주세요.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '상록수역 상세 정보, 수도권 2호선, 기본 정보만 있음, 마지막 확인 2026-06-13',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, '정보 기준 보기'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '정보 기준 보기'));
      await tester.pumpAndSettle();
      expect(find.text('정보 기준'), findsOneWidget);
      expect(find.text('공식 정보'), findsOneWidget);
      expectNoForbiddenUserCopy(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, '정보 기준 접기'));
      await tester.pumpAndSettle();
      expect(find.text('출처 공식 파일'), findsNothing);
      expect(find.text('이동 구조'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('승강장'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
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
          '상록수역 상세 정보, 수도권 2호선, 기본 정보만 있음, 마지막 확인 2026-06-13, 지도 위치',
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
        find.bySemanticsLabel('1번 출구, 엘리베이터 연결, 계단 없는 이동 가능, 시설 상태 확인됨, 지도 위치'),
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
          '1번 출구 엘리베이터, 엘리베이터, 이용 가능, 1번 출구 앞, 최근 확인 2026-06-12, 시설 상태 확인됨, 다음 행동 상태 제보, 지도 위치',
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
        find.bySemanticsLabel('1번 출구, 엘리베이터 연결, 계단 없는 이동 가능, 시설 상태 확인됨'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('시설'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('시설'), findsOneWidget);
      expect(find.text('2번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('엘리베이터'), findsWidgets);
      expect(find.text('이용 불가 확인'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(
          const Key('stationFacilityCard-facility-sangnoksu-info-needed'),
        ),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('3번 출구 에스컬레이터'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const Key('stationFacilityCard-facility-sangnoksu-info-needed'),
          ),
          matching: find.text('정보 확인 필요'),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(
          const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
        ),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('이용 가능'), findsOneWidget);
      expect(find.text('1번 출구 앞'), findsOneWidget);
      expect(find.text('최근 확인 2026-06-12'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '1번 출구 엘리베이터, 엘리베이터, 이용 가능, 1번 출구 앞, 최근 확인 2026-06-12, 시설 상태 확인됨, 다음 행동 상태 제보',
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

  testWidgets('역 상세는 태블릿 landscape에서 요약과 시설 정보를 나란히 보여준다', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
          description: '1번 출구 앞',
          status: 'NORMAL',
          dataConfidence: 'HIGH',
          dataSourceType: 'OFFICIAL_FILE',
          lastUpdatedAt: '2026-06-12',
          fieldValidationStatus: 'VERIFIED',
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
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('stationDetailLargeScreenLayout')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('stationDetailPrimaryColumn')), findsOneWidget);
    expect(find.byKey(const Key('stationDetailDetailColumn')), findsOneWidget);
    expect(find.text('상록수역'), findsOneWidget);
    expect(
      find.byKey(
        const Key('stationFacilityCard-facility-sangnoksu-elevator-1'),
      ),
      findsOneWidget,
    );

    final primaryRect = tester.getRect(
      find.byKey(const Key('stationDetailPrimaryColumn')),
    );
    final detailRect = tester.getRect(
      find.byKey(const Key('stationDetailDetailColumn')),
    );
    final facilityRect = tester.getRect(
      find.byKey(
        const Key('stationFacilityCard-facility-sangnoksu-elevator-1'),
      ),
    );

    expect(primaryRect.right, lessThan(detailRect.left));
    expect(facilityRect.left, greaterThan(primaryRect.right));
    expect(detailRect.top, lessThan(primaryRect.bottom));
  });

  testWidgets('역 상세 대화면은 큰 글씨에서 시설 상태 3종을 렌더링한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final repository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationFacilities: const [
        StationFacilityInfo(
          id: 'facility-normal',
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
        StationFacilityInfo(
          id: 'facility-broken',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-2',
          type: 'ELEVATOR',
          name: '2번 출구 엘리베이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '2번 출구 앞',
          status: 'BROKEN',
          dataConfidence: 'HIGH',
          lastUpdatedAt: '2026-06-12',
        ),
        StationFacilityInfo(
          id: 'facility-needs-check',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-3',
          type: 'ESCALATOR',
          name: '3번 출구 에스컬레이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '3번 출구 앞',
          status: 'NEEDS_CHECK',
          dataConfidence: 'LOW',
          lastUpdatedAt: '2026-06-12',
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
          initialOnboardingState: _completedOnboardingStateWithPreferences(
            preferences: const OnboardingViewPreferences(
              largeTextEnabled: true,
              highContrastEnabled: true,
              simpleViewEnabled: false,
            ),
          ),
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

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('stationDetailLargeScreenLayout')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationFacilityCard-facility-normal')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('stationFacilityCard-facility-broken')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('stationFacilityCard-facility-needs-check')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();

      expect(find.text('이용 가능'), findsOneWidget);
      expect(find.text('이용 불가 확인'), findsOneWidget);
      expect(find.text('정보 확인 필요'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('시설 상세는 실제 시설 데이터로 위치 상태 제보 진입을 보여준다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final repository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationFacilities: const [
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

    await tester.pumpWidget(
      EasySubwayApp(
        repository: repository,
        reportRepository: reportRepository,
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: FakeCurrentLocationProvider(
          location: _freshCurrentLocation(),
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
    await tester.scrollUntilVisible(
      find.byKey(
        const Key('stationFacilityCard-facility-sangnoksu-elevator-2'),
      ),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('stationFacilityCard-facility-sangnoksu-elevator-2'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('시설 상세')),
      findsOneWidget,
    );
    expect(find.text('상록수역'), findsOneWidget);
    expect(find.text('2번 출구 엘리베이터'), findsOneWidget);
    expect(find.text('이용 불가 확인'), findsOneWidget);
    expect(find.text('고장·폐쇄 · 고장'), findsOneWidget);
    expect(find.text('현장 상태를 확인하고 정보가 다르면 상태 제보로 알려 주세요.'), findsOneWidget);
    expect(find.text('연결 위치 B1 ↔ 1F'), findsOneWidget);
    expect(find.text('2번 출구 앞'), findsOneWidget);
    expect(find.text('최근 확인 2026-06-14'), findsOneWidget);
    expect(find.text('정보 신뢰도 높음'), findsNothing);
    expect(find.text('출처 공식 파일'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '정보 기준 보기'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '정보 기준 보기'));
    await tester.pumpAndSettle();
    expect(find.text('정보 기준'), findsOneWidget);
    expect(find.text('최근 확인됨'), findsOneWidget);
    expect(find.text('확인 수준 높음'), findsOneWidget);
    expect(find.text('공식 정보'), findsOneWidget);
    expectNoForbiddenUserCopy(tester);

    await tester.scrollUntilVisible(
      find.byKey(
        const Key('facilityDetailReportButton-facility-sangnoksu-elevator-2'),
      ),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('facilityDetailReportButton-facility-sangnoksu-elevator-2'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('시설 상태 제보'), findsOneWidget);
    expect(find.text('2번 출구 엘리베이터'), findsOneWidget);
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
    expect(find.text('역 안 이동 순서'), findsOneWidget);
    expect(find.text('역 안 이동 경로를 찾았어요'), findsOneWidget);
    expect(find.text('1번 출구 엘리베이터에서 개찰구까지'), findsWidgets);
    expect(find.text('약 1분 15초 · 28m'), findsOneWidget);
    expect(find.text('엘리베이터에서 개찰구까지 이동합니다.'), findsOneWidget);
    expect(
      find.text('약 1분 15초 · 28m · 최근 확인 정보 없음 · 엘리베이터를 이용해요'),
      findsOneWidget,
    );
    expect(find.text('내부 이동 경로를 찾았습니다'), findsNothing);
    expect(find.text('현장 검증 전'), findsNothing);
    expect(find.text('엘리베이터 필요'), findsNothing);
    expect(
      find.bySemanticsLabel(
        '역 안 이동 순서, 역 안 이동 경로를 찾았어요, 1번 출구 엘리베이터에서 개찰구까지, 약 1분 15초 · 28m, 이동 단계 1번 역 안 이동, 1번 출구 엘리베이터에서 개찰구까지, 약 1분 15초 · 28m · 최근 확인 정보 없음 · 엘리베이터를 이용해요, 엘리베이터에서 개찰구까지 이동합니다.',
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
    expect(find.text('역 안 이동 순서'), findsOneWidget);
    expect(find.text('역 안 이동 경로를 찾았어요'), findsOneWidget);
    expect(find.text('내부 이동 경로를 찾았습니다'), findsNothing);
  });

  testWidgets('역 상세는 역 안 이동 정보가 부족하면 쉬운 안내를 보여준다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );
    final internalRouteRepository = FakeInternalRouteRepository(
      nodes: const [],
      result: _internalRouteResult(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          stationId: 'station-sangnoksu',
          internalRouteRepository: internalRouteRepository,
          internalRouteMobilityType: 'WHEELCHAIR',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(internalRouteRepository.nodeStationIds, ['station-sangnoksu']);
    expect(find.text('역 안 이동 순서'), findsOneWidget);
    expect(find.text('역 안 길 안내에 필요한 정보를 찾지 못했어요.'), findsOneWidget);
    expect(find.textContaining('기준점'), findsNothing);
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
        '상록수역 상세 정보, 수도권 2호선, 기본 정보만 있음, 마지막 확인 2026-06-13',
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

    expect(find.text('즐겨찾기한 역이 없습니다.'), findsOneWidget);
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
      expect(find.text('천천히 이동'), findsOneWidget);
      expect(find.text('유모차 이용'), findsOneWidget);
      expect(find.text('휠체어 이용'), findsOneWidget);
      expect(find.text('임신 중'), findsOneWidget);
      expect(find.text('부상·회복 중'), findsOneWidget);
      expect(find.text('큰 짐이 있음'), findsOneWidget);
      expect(find.text('계단을 피하고 쉬운 환승을 우선해요'), findsOneWidget);
      expect(find.text('엘리베이터와 넓은 길을 우선해요'), findsOneWidget);
      expect(find.text('계단 없는 길만 안내해요'), findsOneWidget);

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('휠체어 이용 선택 가능, 계단 없는 길만 안내해요'),
        ),
        isSemantics(
          label: '휠체어 이용 선택 가능, 계단 없는 길만 안내해요',
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

      expect(
        find.bySemanticsLabel('휠체어 이용 선택됨, 계단 없는 길만 안내해요'),
        findsOneWidget,
      );
      expect(find.text('휠체어 이용 조건을 선택했습니다'), findsOneWidget);
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

      expect(
        find.bySemanticsLabel('휠체어 이용 선택됨, 계단 없는 길만 안내해요'),
        findsOneWidget,
      );
      expect(find.text('휠체어 이용 조건을 선택했습니다'), findsOneWidget);
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
    expect(find.text('휠체어 이용'), findsOneWidget);
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('길찾기')),
        findsOneWidget,
      );
      expect(find.text('출발역 선택'), findsOneWidget);
      expect(find.text('도착역 선택'), findsOneWidget);
      expect(find.text('출발역 ID'), findsNothing);
      expect(find.text('도착역 ID'), findsNothing);
      expect(find.text('적용 중인 조건'), findsNothing);
      expect(find.text('천천히 이동'), findsOneWidget);
      expect(
        find.byKey(const Key('routeSimpleMobilityTypeButton')),
        findsOneWidget,
      );
      expect(find.byType(DropdownButton<String>), findsNothing);

      await _openRouteOriginStationInput(tester);
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
      await _openRouteDestinationStationInput(tester);
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

      final originButtonLeft = tester.getTopLeft(
        find.byKey(const Key('routeOriginPointButton')),
      );
      final originTextLeft = tester.getTopLeft(find.text('상록수역'));
      expect(originTextLeft.dx - originButtonLeft.dx, greaterThanOrEqualTo(24));

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
      expect(find.text('추천 경로'), findsOneWidget);
      expect(find.text('추천 경로 목록'), findsNothing);
      expect(find.text('편한 순'), findsNothing);
      expect(find.text('빠른 순'), findsNothing);
      expect(find.text('환승 적은 순'), findsNothing);
      expect(find.text('상록수 → 사당'), findsNothing);
      expect(find.text('계단 피하기 · 환승 줄이기'), findsWidgets);
      expect(find.text('계단 여부 확인 필요'), findsWidgets);
      expect(find.text('계단 없음'), findsNothing);
      expect(find.text('엘리베이터 이용'), findsNothing);
      expect(find.text('7분'), findsOneWidget);
      expect(find.text('환승 없음 · 걷기 300m'), findsOneWidget);
      expect(find.text('추천'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.textContaining('이동 점수'), findsNothing);
      expect(find.text('추천 이유'), findsNothing);
      expect(find.text('엘리베이터 동선을 우선했어요'), findsNothing);
      expect(find.text('계단 없는 출구를 확인했어요'), findsNothing);
      expect(find.text('천천히 이동하기 쉬운 동선을 확인했어요'), findsNothing);
      expect(find.text('경로 상세'), findsNothing);
      expect(find.text('도착 안내'), findsNothing);
      expect(find.text('이동 순서'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('routeResultListItem')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routeResultListItem')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();

      expect(find.text('경로 목록'), findsOneWidget);
      expect(find.text('추천 경로 1개'), findsNothing);
      expect(find.text('가장 추천'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('이동 순서'), findsOneWidget);
      expect(find.text('도착 안내'), findsOneWidget);
      expect(find.text('도착역에서 계단 없는 출구 동선을 확인합니다.'), findsOneWidget);
      expect(find.byKey(const Key('routeStepNumber-1')), findsOneWidget);
      expect(find.text('열차 이동'), findsOneWidget);
      expect(find.text('선택한 경로 기준으로 안내합니다.'), findsOneWidget);
      expect(find.textContaining('edge:'), findsNothing);
      expect(find.textContaining('STATIC_ESTIMATE'), findsNothing);
      expect(find.textContaining('MEASURED'), findsNothing);
      expect(find.text('계단 없는 승강장 접근 동선을 확인해 이동합니다.'), findsOneWidget);
      expect(find.text('약 4분 · 180m · 접근성 확인'), findsOneWidget);
      expect(find.text('일부 시설 정보는 확인이 필요합니다.'), findsOneWidget);
      expect(find.text('접근성 시설 정보가 최근 확인되지 않았습니다.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('routeDarkSummaryChip-계단 여부 확인 필요')),
          matching: find.byIcon(Icons.help_outline),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('routeDarkSummaryChip-계단 여부 확인 필요')),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );

      await tester.ensureVisible(
        find.byKey(const Key('routeStartGuidanceButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routeStartGuidanceButton')));
      await tester.pumpAndSettle();

      expect(find.text('단계별 안내'), findsOneWidget);
      expect(find.text('계단 없는 승강장 접근 동선을 확인해 이동합니다.'), findsOneWidget);
      expect(find.text('다음'), findsOneWidget);
      expect(
        find.byKey(const Key('routeOpenInternalRouteButton')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('routeOpenInternalRouteButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routeOpenInternalRouteButton')));
      await tester.pumpAndSettle();

      expect(find.text('역 안 이동 순서'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('이동 점수')), findsNothing);
      expectNoForbiddenUserCopy(tester);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('경로 결과 단계는 시스템 뒤로가기를 화면 내 뒤로가기와 맞춘다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(),
          stationRepository: FakeStationSearchRepository(),
          routeFeedbackRepository: FakeRouteFeedbackRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 6, 29),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);

    await tester.tap(find.byKey(const Key('routeResultListItem')));
    await tester.pumpAndSettle();
    expect(find.text('이동 순서'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    expect(find.text('이동 순서'), findsNothing);

    await tester.tap(find.byKey(const Key('routeResultListItem')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('routeStartGuidanceButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeStartGuidanceButton')));
    await tester.pumpAndSettle();
    expect(find.text('전체 순서'), findsWidgets);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('이동 순서'), findsOneWidget);
    expect(find.byKey(const Key('routeStartGuidanceButton')), findsOneWidget);
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
    await tester.tap(find.text('휠체어 이용').last);
    await tester.pumpAndSettle();
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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
    expect(find.text('천천히 이동'), findsOneWidget);

    await tester.tap(find.byKey(const Key('routeSimpleMobilityTypeButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeMobilityOptionsList')), findsOneWidget);
    expect(find.text('계단을 피하고 쉬운 환승을 우선해요'), findsOneWidget);
    expect(find.byKey(const Key('routeMobilityApplyButton')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('routeMobilityOption-WHEELCHAIR')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const Key('routeMobilityOptionsList')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('계단 없는 길만 안내해요'), findsOneWidget);
    expect(
      find.bySemanticsLabel('휠체어 이용 선택 가능, 계단 없는 길만 안내해요, 계단 피하기 · 엘리베이터 이동'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('routeMobilityOption-WHEELCHAIR')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeMobilityApplyButton')), findsOneWidget);
    expect(
      find.bySemanticsLabel('휠체어 이용 현재 선택, 계단 없는 길만 안내해요, 계단 피하기 · 엘리베이터 이동'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('routeMobilityApplyButton')));
    await tester.pumpAndSettle();

    expect(find.text('휠체어 이용'), findsOneWidget);
    expect(find.text('계단 피하기 · 엘리베이터 이동'), findsOneWidget);
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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
        find.bySemanticsLabel('현재 이동 조건 천천히 이동, 계단 피하기 · 환승 줄이기'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('이동 조건 바꾸기, 현재 천천히 이동')),
        isSemantics(
          label: '이동 조건 바꾸기, 현재 천천히 이동',
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
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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

    await _openFirstRouteResultDetail(tester);

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

  testWidgets('경로 검색 UNKNOWN 결과는 저장과 안내 시작 행동을 숨긴다', (tester) async {
    final favoriteRouteRepository = FakeFavoriteRouteRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(status: 'UNKNOWN'),
          ),
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: favoriteRouteRepository,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 6, 26),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();
    await _openFirstRouteResultDetail(tester);

    expect(find.byKey(const Key('routeFavoriteSaveButton')), findsNothing);
    expect(find.bySemanticsLabel('자주 쓰는 경로 저장'), findsNothing);
    expect(find.byKey(const Key('routeStartGuidanceButton')), findsNothing);
    expect(favoriteRouteRepository.savedRouteSearchIds, isEmpty);
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
      await _openRouteOriginStationInput(tester);
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
      await _openRouteDestinationStationInput(tester);
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

      await _openFirstRouteResultDetail(tester);

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
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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

    await _openFirstRouteResultDetail(tester);
    await tester.ensureVisible(
      find.byKey(const Key('routeOpenFeedbackButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeOpenFeedbackButton')));
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

  testWidgets('선택한 출발역을 수정해도 역 검색 입력은 닫히지 않는다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '사': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(),
          stationRepository: stationRepository,
          initialMobilityType: 'SENIOR',
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 6, 23),
          ),
        ),
      ),
    );

    await _openRouteOriginStationInput(tester);
    await tester.enterText(
      find.byKey(const Key('routeOriginStationInput')),
      '사',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeOriginStationInput')), findsOneWidget);

    await tester.tap(find.byKey(const Key('routeOriginStationSearchButton')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('routeOriginStationOption-station-sadang')),
      findsOneWidget,
    );
  });

  testWidgets('로컬 경로 결과는 서버 피드백 행동을 숨긴다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeRepository = FakeRouteSearchRepository(
      result: _sampleRouteSearchResult(
        routeSearchId: 'local-station-sangnoksu-station-sadang',
      ),
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        routeFeedbackRepository: FakeRouteFeedbackRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchButton')));
    await tester.pumpAndSettle();
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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

    await _openFirstRouteResultDetail(tester);

    expect(find.byKey(const Key('routeOpenFeedbackButton')), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('routeStartGuidanceButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeStartGuidanceButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeGuidanceFeedbackButton')), findsNothing);
    expect(find.byKey(const Key('routeOpenBlockedButton')), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(
      find.byKey(const Key('routeOpenInternalRouteButton')),
      findsOneWidget,
    );
  });

  testWidgets('추천 경로 항목은 스크린리더에서 상세 진입 버튼으로 남는다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: FakeRouteSearchRepository(),
            stationRepository: FakeStationSearchRepository(),
            initialMobilityType: 'SENIOR',
            initialDraft: RouteDraft(
              origin: const RouteDraftStation(
                id: 'station-sangnoksu',
                nameKo: '상록수',
              ),
              destination: const RouteDraftStation(
                id: 'station-sadang',
                nameKo: '사당',
              ),
              lastModifiedAt: DateTime(2026, 6, 23),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
      final routeItemSemantics = tester
          .getSemantics(find.byKey(const Key('routeResultListItem')))
          .getSemanticsData();
      expect(routeItemSemantics.hasAction(SemanticsAction.tap), isTrue);
      expect(routeItemSemantics.label, contains('계단 여부 확인 필요'));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('경로 요약은 stepType 기반 환승과 보행 거리만 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(
              steps: const [
                RouteSearchStep(
                  sequence: 1,
                  stepType: 'entry',
                  title: '출발역 승강장 접근',
                  description: '엘리베이터로 승강장까지 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sangnoksu',
                  toStationId: 'station-sangnoksu',
                  estimatedMinutes: 2,
                  distanceMeters: 180,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                ),
                RouteSearchStep(
                  sequence: 2,
                  stepType: 'ride',
                  title: '사당역까지 이동',
                  description: '같은 4호선 열차로 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sangnoksu',
                  toStationId: 'station-sadang',
                  estimatedMinutes: 20,
                  distanceMeters: 10000,
                  includesStairs: false,
                  requiresAccessibilityCheck: false,
                  actionTitle: '열차 이동',
                ),
                RouteSearchStep(
                  sequence: 3,
                  stepType: 'transfer',
                  title: '노선 변경 준비',
                  description: '다음 열차 승강장으로 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sadang',
                  toStationId: 'station-sadang',
                  estimatedMinutes: 4,
                  distanceMeters: 120,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                ),
              ],
            ),
          ),
          stationRepository: FakeStationSearchRepository(),
          initialMobilityType: 'SENIOR',
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 6, 23),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.text('환승 1회 · 걷기 300m'), findsOneWidget);
    expect(find.textContaining('걷기 10.3km'), findsNothing);
  });

  testWidgets('길이 막혔어요는 성공 경로를 blocked 화면으로 바꾸지 않는다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );

    await tester.pumpWidget(
      EasySubwayApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        routeFeedbackRepository: FakeRouteFeedbackRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchButton')));
    await tester.pumpAndSettle();
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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

    await _openFirstRouteResultDetail(tester);
    await tester.ensureVisible(
      find.byKey(const Key('routeStartGuidanceButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeStartGuidanceButton')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('routeOpenBlockedButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeOpenBlockedButton')));
    await tester.pumpAndSettle();

    expect(find.text('방금 안내가\n실제 이동에 도움이 됐나요?'), findsOneWidget);
    expect(find.text('계단 없는 경로가 없습니다'), findsNothing);
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
      await _openRouteOriginStationInput(tester);
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
      await _openRouteDestinationStationInput(tester);
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

      await _openFirstRouteResultDetail(tester);
      await tester.ensureVisible(
        find.byKey(const Key('routeOpenFeedbackButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routeOpenFeedbackButton')));
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
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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

    await tester.ensureVisible(find.byKey(const Key('routeResultListItem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeResultListItem')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeStartGuidanceButton')), findsNothing);
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
    await _openRouteOriginStationInput(tester);
    await tester.enterText(
      find.byKey(const Key('routeOriginStationInput')),
      '상록수',
    );
    await _openRouteDestinationStationInput(tester);
    await tester.enterText(
      find.byKey(const Key('routeDestinationStationInput')),
      '사당',
    );
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests, isEmpty);
    final submitButton = tester.widget<FilledButton>(
      find.byKey(const Key('routeSearchSubmitButton')),
    );
    expect(submitButton.onPressed, isNull);
    expect(find.text('출발역과 도착역을 검색 결과에서 선택해 주세요.'), findsNothing);
    expect(find.text('역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.'), findsNothing);
  });

  testWidgets('경로 검색 실패는 다음 행동을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
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
      await _openRouteOriginStationInput(tester);
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
      await _openRouteDestinationStationInput(tester);
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
    await _openRouteOriginStationInput(tester);
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
    await _openRouteDestinationStationInput(tester);
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

    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    await _openRouteOriginStationInput(tester);
    await tester.enterText(
      find.byKey(const Key('routeOriginStationInput')),
      '상록',
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    final submitButton = tester.widget<FilledButton>(
      find.byKey(const Key('routeSearchSubmitButton')),
    );
    expect(submitButton.onPressed, isNull);
    expect(find.text('출발역과 도착역을 검색 결과에서 선택해 주세요.'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeResultListItem')), findsNothing);
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
      await _openRouteOriginStationInput(tester);
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
      await _openRouteDestinationStationInput(tester);
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
      expect(find.widgetWithText(FilledButton, '경로 검색 중'), findsOneWidget);
      final loadingButton = tester.widget<FilledButton>(
        find.byKey(const Key('routeSearchSubmitButton')),
      );
      expect(loadingButton.onPressed, isNull);

      routeRepository.complete(_blockedRouteSearchResult());
      await tester.pumpAndSettle();

      expect(find.text('계단 없는 경로가 없습니다'), findsOneWidget);
      expect(find.text('추천 이유'), findsNothing);
      expect(find.text('엘리베이터 동선을 우선했어요'), findsNothing);
      expect(find.text('안내 가능한 경로를 찾지 못했습니다.'), findsOneWidget);
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

      expect(find.text('시설 상태 제보'), findsOneWidget);
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
      expect(find.text('제보를 보냈어요.'), findsOneWidget);
      expect(find.bySemanticsLabel('제보를 보냈어요.'), findsOneWidget);
      expect(find.text('제보 번호'), findsOneWidget);
      expect(find.text('ES-1001'), findsOneWidget);
      expect(find.text('report-1'), findsNothing);
      expect(find.text('처리 상태'), findsOneWidget);
      expect(find.text('접수됨'), findsOneWidget);
      expect(find.bySemanticsLabel('제보 번호 ES-1001, 현재 상태 접수됨'), findsOneWidget);
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
      expect(find.bySemanticsLabel('제보 번호 ES-1001, 현재 상태 반영됨'), findsOneWidget);
      expectNoForbiddenUserCopy(tester);

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
    expect(find.text('사진은 제보 내용을 확인하는 데만 사용해요.'), findsOneWidget);
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
    expect(find.text('시설 상태 제보'), findsOneWidget);
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

  testWidgets('앱은 서비스 소개에서 바로 시작해도 저장된 시설 신고 사진을 복구한다', (tester) async {
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
        onboardingStore: MemoryOnboardingResultStore(),
        facilityReportDraftTargetStore: draftTargetStore,
        facilityReportLostPhotoRestorer: () async {
          restoreCount++;
          return const FacilityReportPhotoAttachment(
            fileName: 'restored-toilet.webp',
            contentType: 'image/webp',
            dataBase64: 'cmVzdG9yZWQ=',
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('startScreenStartButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('onboardingIntroSkipButton')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('onboardingIntroSkipButton')));
    await tester.pumpAndSettle();

    expect(restoreCount, 1);
    expect(draftTargetStore.clearCount, 1);
    expect(find.text('시설 상태 제보'), findsOneWidget);
    expect(
      find.bySemanticsLabel('상록수역, 장애인 화장실, 장애인 화장실, 현재 확인 필요'),
      findsOneWidget,
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
    expect(find.text('시설 상태 제보'), findsOneWidget);
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
    expect(find.text('사진과 제보 위치는 시설 제보 확인에만 사용됩니다.'), findsOneWidget);
    expect(
      find.text('제보 내용은 접수 담당자에게 전달되며 앱 사용자에게 공개되지 않습니다.'),
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
    expect(find.text('가까운 역 찾기와 시설 제보 위치 확인에만 현재 위치를 사용합니다.'), findsOneWidget);
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
                '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
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
          '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
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

    expect(find.text('휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
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

  testWidgets('시설 신고 화면은 GPS가 꺼져 있으면 위치 없이 제보를 선택할 수 있다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException(
        '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
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

    expect(find.text('휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
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
    expect(
      find.byKey(const Key('facilityReportSubmitWithoutLocationButton')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('facilityReportSubmitWithoutLocationButton')),
    );
    await tester.pumpAndSettle();
    expect(find.text('위치 없이 제보합니다. 현장 위치 확인이 늦어질 수 있어요.'), findsOneWidget);

    final noLocationSubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(noLocationSubmitButton.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pumpAndSettle();
    expect(find.text('사진·위치 확인'), findsOneWidget);
    expect(
      find.text('현재 위치 없이 제보하면 담당자가 현장 위치를 다시 확인해야 할 수 있습니다.'),
      findsOneWidget,
    );
    await tester.tap(find.text('보내기'));
    await tester.pumpAndSettle();

    expect(reportRepository.requests, hasLength(1));
    expect(reportRepository.requests.single.latitude, isNull);
    expect(reportRepository.requests.single.longitude, isNull);
  });

  testWidgets('시설 신고 화면은 GPS가 꺼져 있으면 위치 설정으로 이동할 수 있다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException(
        '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
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

    expect(find.text('휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
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
              '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
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

    expect(find.text('시설 상태 제보'), findsOneWidget);
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
    expect(find.text('사진과 제보 위치는 시설 제보 확인에만 사용됩니다.'), findsOneWidget);
    expect(
      find.text('제보 내용은 접수 담당자에게 전달되며 앱 사용자에게 공개되지 않습니다.'),
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
    expect(
      find.byKey(const Key('facilityReportSubmitWithoutLocationButton')),
      findsOneWidget,
    );
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

FavoriteFacility _favoriteFacility({
  String status = 'NORMAL',
  String name = '1번 출구 엘리베이터',
  String exitId = 'exit-sangnoksu-1',
  String description = '1번 출구 앞',
}) {
  return FavoriteFacility(
    userId: 'anonymous-user-1',
    facilityId: 'facility-sangnoksu-elevator-1',
    stationId: 'station-sangnoksu',
    stationNameKo: '상록수',
    stationNameEn: 'Sangnoksu',
    exitId: exitId,
    type: 'ELEVATOR',
    name: name,
    floorFrom: '1F',
    floorTo: 'B1',
    description: description,
    status: status,
    dataConfidence: 'HIGH',
    dataSourceType: 'OFFICIAL_FILE',
    lastUpdatedAt: '2026-06-12',
    addedAt: '2026-06-14T10:00:00',
  );
}

FavoriteRoute _favoriteRoute({String mobilityType = 'SENIOR'}) {
  return FavoriteRoute(
    userId: 'anonymous-user-1',
    favoriteRouteId: 'route-1',
    routeSearchId: 'route-1',
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-sadang',
    destinationStationName: '사당',
    mobilityType: mobilityType,
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
    implements
        StationSearchRepository,
        StationLineFilterRepository,
        NetworkMapRepository {
  FakeStationSearchRepository({
    this.nextResults = const [],
    this.nearbyResults = const [],
    this.queryResults = const {},
    this.lineOptions = const [],
    this.networkMapRegionNames = const ['테스트권'],
    this.networkMapData,
    this.networkMapError,
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
  final List<String> networkMapRegionNames;
  final NetworkMapData? networkMapData;
  final Object? networkMapError;
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
  final requestedNetworkMapRegions = <String?>[];
  final requestedNetworkMapLineIds = <String?>[];

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

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    requestedNetworkMapRegions.add(region);
    requestedNetworkMapLineIds.add(lineId);
    final mapError = networkMapError;
    if (mapError != null) {
      throw mapError;
    }
    final customMapData = networkMapData;
    if (customMapData != null) {
      return customMapData;
    }
    final selectedRegion = region ?? networkMapRegionNames.first;
    const lines = [
      NetworkMapLine(
        id: 'seoul-2',
        name: '수도권 2호선',
        color: '#00A84D',
        region: '테스트권',
      ),
      NetworkMapLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        region: '테스트권',
      ),
    ];
    const stations = [
      NetworkMapStation(
        id: 'station-sadang',
        nameKo: '사당',
        nameEn: 'Sadang',
        region: '테스트권',
        lineId: 'seoul-2',
        stationCode: '226',
        sequence: 33,
        position: NetworkMapPosition(
          x: 390,
          y: 320,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-route-map-source-capital-review',
        ),
      ),
      NetworkMapStation(
        id: 'station-sadang',
        nameKo: '사당',
        nameEn: 'Sadang',
        region: '테스트권',
        lineId: 'seoul-4',
        stationCode: '433',
        sequence: 33,
        position: NetworkMapPosition(
          x: 390,
          y: 320,
          labelDx: 0,
          labelDy: 0,
          upPath: 'M 390 320 L 156 250',
          downPath: '',
          sourceId: 'fixture-route-map-source-capital-review',
        ),
      ),
      NetworkMapStation(
        id: 'station-sangnoksu',
        nameKo: '상록수',
        nameEn: 'Sangnoksu',
        region: '수도권',
        lineId: 'seoul-4',
        stationCode: '448',
        sequence: 48,
        position: NetworkMapPosition(
          x: 156,
          y: 250,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: 'M 156 250 L 390 320',
          sourceId: 'fixture-route-map-source-capital-review',
        ),
      ),
    ];
    final filteredStations = [
      for (final station in stations)
        if (lineId == null || station.lineId == lineId) station,
    ];
    final filteredStationKeys = {
      for (final station in filteredStations) '${station.id}:${station.lineId}',
    };
    const edges = [
      NetworkMapEdge(
        id: 'map-edge-seoul-4-station-sadang-station-sangnoksu',
        lineId: 'seoul-4',
        fromStationId: 'station-sadang:seoul-4',
        toStationId: 'station-sangnoksu:seoul-4',
        accessibilityStatus: 'AVAILABLE',
        reliabilityScore: 100,
      ),
    ];
    return NetworkMapData(
      regions: [
        for (final regionName in networkMapRegionNames)
          NetworkMapRegion(name: regionName),
      ],
      selectedRegion: selectedRegion,
      lines: lines,
      stations: filteredStations,
      edges: [
        for (final edge in edges)
          if (filteredStationKeys.contains(edge.fromStationId) &&
              filteredStationKeys.contains(edge.toStationId))
            edge,
      ],
      positionSources: const [
        NetworkMapPositionSource(
          id: 'fixture-route-map-source-capital-review',
          name: '수도권 노선도 fixture 좌표 검수',
          licenseStatus: 'fixture-only',
        ),
      ],
      stationLineMemberships: const [
        NetworkMapStationLineMembership(
          stationId: 'station-sadang',
          lineId: 'seoul-2',
        ),
        NetworkMapStationLineMembership(
          stationId: 'station-sadang',
          lineId: 'seoul-4',
        ),
        NetworkMapStationLineMembership(
          stationId: 'station-sangnoksu',
          lineId: 'seoul-4',
        ),
      ],
    );
  }
}

class FakeSearchHistoryRepository implements SearchHistoryRepository {
  FakeSearchHistoryRepository(List<String> queries) : queries = [...queries];

  final List<String> queries;
  final recordedQueries = <String>[];
  final removedQueries = <String>[];
  int clearCount = 0;
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

  @override
  Future<void> removeSearch(String query) async {
    final trimmed = query.trim();
    removedQueries.add(trimmed);
    queries.remove(trimmed);
  }

  @override
  Future<void> clearSearches() async {
    clearCount++;
    queries.clear();
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
      publicReceiptCode: 'ES-100${requests.length}',
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
      publicReceiptCode: 'ES-1001',
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
  int listCount = 0;
  final savedStationIds = <String>[];
  final removedStationIds = <String>[];
  Object? error;

  @override
  Future<List<FavoriteStation>> listFavoriteStations() async {
    listCount++;
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
  int listCount = 0;
  Object? error;

  @override
  Future<List<FavoriteFacility>> listFavoriteFacilities() async {
    listCount++;
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
  int listCount = 0;
  final savedRouteSearchIds = <String>[];
  final removedFavoriteRouteIds = <String>[];
  Object? error;

  @override
  Future<List<FavoriteRoute>> listFavoriteRoutes() async {
    listCount++;
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
    this.saveError,
    this.saveCompleters = const [],
  }) : savedResult = initialResult;

  OnboardingResult? savedResult;
  final bool throwOnRead;
  final Object? saveError;
  final List<Completer<void>> saveCompleters;
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
    final saveCompleter = saveCount < saveCompleters.length
        ? saveCompleters[saveCount]
        : null;
    saveCount++;
    final error = saveError;
    if (error != null) {
      throw error;
    }
    await saveCompleter?.future;
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
  String routeSearchId = 'route-1',
  String status = 'FOUND',
  String mobilityType = 'SENIOR',
  List<RouteSearchStep>? steps,
  List<String> recommendationReasons = const [
    '엘리베이터 동선을 우선했어요',
    '계단 없는 출구를 확인했어요',
    '천천히 이동하기 쉬운 동선을 확인했어요',
  ],
}) {
  return RouteSearchResult(
    routeSearchId: routeSearchId,
    originStationId: 'station-sangnoksu',
    originStationName: '상록수',
    destinationStationId: 'station-sadang',
    destinationStationName: '사당',
    mobilityType: mobilityType,
    status: status,
    lineId: 'seoul-4',
    lineName: '수도권 4호선',
    score: 92,
    steps:
        steps ??
        const [
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
            stepType: 'entry',
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
            stepType: 'exit',
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
