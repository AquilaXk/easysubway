import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/favorite_facility.dart';
import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/internal_route.dart';
import 'package:easysubway_mobile/legacy_credential_cleanup.dart';
import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:easysubway_mobile/user_data_deletion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

class _FakeNoticeRepository implements NoticeRepository {
  _FakeNoticeRepository(this._result);

  final ActiveNoticesResult _result;

  @override
  Future<ActiveNoticesResult> activeNotices() async => _result;
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
  // 즐겨찾기 홈은 단일 리스트라 카테고리 진입 탭이 없다. 항목이 바로 보인다(#1569).
}

Future<void> _openRouteSearchScreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('networkMapMenuButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('networkMapMenuRouteSearchButton')));
  await tester.pumpAndSettle();
}

Future<void> _openSavedItemsScreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('networkMapMenuButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('networkMapMenuSavedButton')));
  await tester.pumpAndSettle();
}

Future<void> _openSettingsScreen(WidgetTester tester) async {
  final homeContext = tester.element(find.byType(HomeScreen));
  final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
  final currentProfile = mobilityProfileOptions.firstWhere(
    (option) => option.mobilityType == home.initialMobilityType,
    orElse: () => mobilityProfileOptions.first,
  );
  unawaited(
    Navigator.of(homeContext).push(
      MaterialPageRoute<void>(
        builder: (_) => AppSettingsScreen(
          currentProfile: currentProfile,
          viewPreferences: home.viewPreferences,
          notificationRepository: home.notificationRepository,
          notificationPermissionProvider: home.notificationPermissionProvider,
          onViewPreferencesChanged: home.onViewPreferencesChanged,
          onOpenMobilityProfile: () async {
            final selected = await Navigator.of(homeContext)
                .push<MobilityProfileOption>(
                  MaterialPageRoute<MobilityProfileOption>(
                    builder: (_) =>
                        MobilityProfileScreen(initialSelection: currentProfile),
                  ),
                );
            if (selected != null) {
              try {
                await home.onMobilityProfileChanged?.call(selected);
              } catch (_) {
                if (homeContext.mounted) {
                  ScaffoldMessenger.of(homeContext).showSnackBar(
                    const SnackBar(
                      content: Text('이동 조건을 저장하지 못했어요. 이전 조건으로 되돌렸어요.'),
                    ),
                  );
                }
                return null;
              }
            }
            return selected;
          },
          onOpenSupportAccess: () {
            Navigator.of(homeContext).push(
              MaterialPageRoute<void>(
                builder: (_) => SupportAccessScreen(
                  accessInfo: home.supportAccessInfo,
                  launcher: home.supportAccessLauncher,
                  userDataDeletionRepository: home.userDataDeletionRepository,
                  onUserDataDeleted: home.onUserDataDeleted,
                ),
              ),
            );
          },
          onOpenMyReports: () {
            Navigator.of(homeContext).push(
              MaterialPageRoute<void>(
                builder: (_) => MyFacilityReportListScreen(
                  repository: home.reportRepository,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMyReportsScreen(WidgetTester tester) async {
  final homeContext = tester.element(find.byType(HomeScreen));
  final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
  unawaited(
    Navigator.of(homeContext).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            MyFacilityReportListScreen(repository: home.reportRepository),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMobilityProfileFromSettings(WidgetTester tester) async {
  if (find.byKey(const Key('mobilityProfileButton')).evaluate().isEmpty) {
    await _openSettingsScreen(tester);
  }
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
  await _tapFirstRouteResultListItem(tester);
  await tester.pumpAndSettle();
}

Future<void> _tapFirstRouteResultListItem(WidgetTester tester) async {
  final routeResult = find.byKey(
    const Key('routeResultListItem'),
    skipOffstage: false,
  );
  await tester.ensureVisible(routeResult);
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getTopLeft(routeResult) + const Offset(24, 24));
}

void main() {
  // 상대 확인 시점을 쓰는 테스트가 기준 시각을 고정한 뒤 항상 원래대로 되돌린다.
  tearDown(() {
    debugStationVerifiedClock = DateTime.now;
  });

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
        const FacilityReportResult(
          id: 'report-3',
          publicReceiptCode: 'ES-1003',
          stationId: 'station-sangnoksu',
          facilityId: 'facility-sangnoksu-elevator-2',
          reportType: 'BROKEN',
          description: '이미 접수된 제보입니다.',
          status: 'DUPLICATE',
          createdAt: '2026-06-15T10:00:00',
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
    expect(find.text('중복 제보'), findsOneWidget);
    expect(find.byIcon(Icons.content_copy_outlined), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
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

  testWidgets('기본 앱은 저장소가 없어도 노선도 중심 첫 화면을 보여준다', (tester) async {
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
    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapMenuButton')), findsOneWidget);
    expect(find.byKey(const Key('routeSearchButton')), findsNothing);
    expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
    expect(find.text('노선도'), findsNothing);
    expect(find.text('역 검색'), findsNothing);
    expect(find.text('길찾기'), findsNothing);
    expect(find.text('저장'), findsNothing);
    expect(find.text('더보기'), findsNothing);
    expect(find.text('시설 알림'), findsNothing);
    expect(find.text('최근 경로'), findsNothing);
  });

  testWidgets('저장 탭은 저장된 경로를 목록에서 보여준다', (tester) async {
    final favoriteRouteRepository = FakeFavoriteRouteRepository(
      favorites: [_favoriteRoute()],
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
    await tester.pumpAndSettle();

    await _openSavedItemsScreen(tester);

    // 카테고리 진입 없이 경로가 인라인 카드로 바로 보인다(#1569).
    expect(find.text('경로'), findsOneWidget);
    expect(find.text('상록수역 → 사당역'), findsOneWidget);
    expect(
      find.byKey(const Key('favoriteRouteRemoveButton-route-1')),
      findsOneWidget,
    );
    expect(favoriteRouteRepository.listCount, greaterThanOrEqualTo(1));
  });

  testWidgets('노선도 첫 화면은 하단 광고 위에 지도 조작을 유지한다', (tester) async {
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byKey(const Key('networkMapSurface')), findsOneWidget);
    expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('nearbyStationButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapBottomAdBanner')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapServicePatternToggle')),
      findsOneWidget,
    );
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

    await _openRouteSearchScreen(tester);
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
    expect(find.text('설정을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
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
            largeTextEnabled: false,
            highContrastEnabled: true,
            simpleViewEnabled: true,
          ),
        ),
      ),
    );

    final homeContext = tester.element(find.byType(HomeScreen));

    expect(MediaQuery.textScalerOf(homeContext).scale(20), closeTo(20, 0.01));
    expect(Theme.of(homeContext).colorScheme.primary, const Color(0xFF1A1D1E));
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.text('이동 프로필'), findsNothing);
    expect(find.text('시설 정보'), findsNothing);
    expect(find.text('신고'), findsNothing);
  });

  testWidgets('온보딩은 조건 확인 단계 없이 도움 선택 → 권한 2단계로 끝난다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onCompleted: (_) {})),
    );
    await tester.pumpAndSettle();

    // 1단계: 도움 선택
    expect(find.text('어떤 도움이 필요한가요?'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboardingProfileCard-elderly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    // 2단계: 권한 — 조건 확인 화면과 옛 CTA는 없다. 알림 provider 미주입이라
    // 알림 요청은 숨고 위치만 남는다(#1579).
    expect(find.text('적용할 조건을 확인하세요'), findsNothing);
    expect(find.text('위치는 나중에도 켤 수 있어요'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
    expect(find.text('선택한 기능 설정하고 시작'), findsNothing);
    expect(find.text('나중에 설정'), findsOneWidget);

    // 뒤로가기 → 도움 선택으로 복귀.
    await tester.tap(find.byTooltip('이전 단계'));
    await tester.pumpAndSettle();
    expect(find.text('어떤 도움이 필요한가요?'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('노선도 첫 화면은 핵심 이동 행동과 보조 행동을 지도 위에 제공한다', (tester) async {
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
              largeTextEnabled: false,
              highContrastEnabled: false,
              simpleViewEnabled: false,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
      expect(find.text('안녕하세요'), findsNothing);
      expect(find.text('어디로 가시나요?'), findsNothing);
      expect(find.byKey(const Key('routeSearchButton')), findsNothing);
      expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
      expect(find.byKey(const Key('homeRouteDraftPanel')), findsNothing);
      expect(find.text('시설 알림'), findsNothing);
      expect(find.text('주의'), findsNothing);
      expect(find.text('대체 1번 출구'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '대체 길 보기'), findsNothing);

      expect(find.byKey(const Key('homeSecondaryActionsGroup')), findsNothing);
      expect(find.byKey(const Key('homeSettingsActionsGroup')), findsNothing);
      expect(find.byKey(const Key('homeMyInfoActionsGroup')), findsNothing);
      expect(find.byKey(const Key('homeTripControlPanel')), findsNothing);
      expect(find.byKey(const Key('networkMapMenuButton')), findsOneWidget);
      expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
      expect(find.byKey(const Key('nearbyStationButton')), findsOneWidget);
      expect(find.byKey(const Key('networkMapBottomAdBanner')), findsOneWidget);
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
      expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
      expect(find.byKey(const Key('bottomNavHome')), findsNothing);
      expect(find.byKey(const Key('bottomNavMap')), findsNothing);
      expect(find.byKey(const Key('bottomNavRoute')), findsNothing);
      expect(find.byKey(const Key('bottomNavSaved')), findsNothing);
      expect(find.text('즐겨찾기'), findsNothing);
      expect(find.text('저장'), findsNothing);
      expect(find.byKey(const Key('bottomNavMore')), findsNothing);
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
      expect(find.text('이동 조건: 천천히 이동 〉'), findsNothing);
      expect(find.bySemanticsLabel('지하철역 검색'), findsOneWidget);
      expect(find.textContaining('휠체어'), findsNothing);

      final stationButtonSize = tester.getSize(
        find.byKey(const Key('stationSearchButton')),
      );
      expect(stationButtonSize.height, greaterThanOrEqualTo(38));

      await tester.tap(find.byKey(const Key('networkMapMenuButton')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('networkMapMenuRouteSearchButton')),
        findsOneWidget,
      );
      expect(find.text('최근 경로'), findsNothing);
      expect(find.text('저장한 경로가 없습니다'), findsNothing);
      expect(find.text('경로를 저장하면 현재 시설 상태와 함께 다시 볼 수 있어요.'), findsNothing);

      expect(find.text('이동 프로필'), findsNothing);
      expect(find.text('시설 정보'), findsNothing);
      expect(find.text('신고'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('노선도 첫 화면은 태블릿 landscape에서도 지도와 overlay를 유지한다', (tester) async {
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byKey(const Key('networkMapSurface')), findsOneWidget);
    expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
    expect(find.byKey(const Key('routeSearchButton')), findsNothing);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('nearbyStationButton')), findsOneWidget);
    expect(find.byKey(const Key('homeRecentRouteSection')), findsNothing);

    final surfaceRect = tester.getRect(
      find.byKey(const Key('networkMapSurface')),
    );
    final searchRect = tester.getRect(
      find.byKey(const Key('stationSearchButton')),
    );
    final nearbyButtonRect = tester.getRect(
      find.byKey(const Key('nearbyStationButton')),
    );

    expect(surfaceRect.width, greaterThan(900));
    expect(searchRect.top, lessThan(nearbyButtonRect.top));
    expect(nearbyButtonRect.right, lessThanOrEqualTo(1280));
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
    expect(find.bySemanticsLabel('알림, 새 알림이 없어요'), findsOneWidget);
    expect(find.bySemanticsLabel('알림, 확인할 알림 있음'), findsNothing);

    await tester.tap(find.byKey(const Key('homeNotificationActionButton')));
    await tester.pumpAndSettle();

    expect(find.text('알림'), findsOneWidget);
    expect(find.text('새 알림이 없습니다'), findsOneWidget);
  });

  testWidgets('알림함은 로드 실패를 빈 알림으로 숨기지 않는다', (tester) async {
    final reportedErrors = <FlutterErrorDetails>[];
    final reportRepository = FakeFacilityReportRepository()
      ..error = Exception('network');

    await runWithMobileErrorReporter(reportedErrors.add, () async {
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

      await tester.tap(find.byKey(const Key('homeNotificationActionButton')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notificationInboxErrorState')),
        findsOneWidget,
      );
      expect(find.text('알림을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('새 알림이 없습니다'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, '다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('알림을 불러오지 못했어요'), findsOneWidget);
      expect(find.text('새 알림이 없습니다'), findsNothing);

      reportRepository.error = null;
      await tester.tap(find.widgetWithText(OutlinedButton, '다시 시도'));
      await tester.pumpAndSettle();

      expect(find.text('알림을 불러오지 못했어요'), findsNothing);
      expect(find.text('새 알림이 없습니다'), findsOneWidget);
    });
    expect(reportedErrors, isNotEmpty);
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
    expect(find.bySemanticsLabel('알림, 새 알림이 없어요'), findsNothing);
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

  testWidgets('알림함 시설 상태는 쉬운 안내와 할 일을 함께 보여준다', (tester) async {
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
    expect(find.text('가기 전 살펴보기 · 엘리베이터 제보됨'), findsOneWidget);
    expect(find.text('역무원 도움 요청'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('가기 전 살펴보기, .*공식 안내, 역무원 도움 요청')),
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byKey(const Key('mapRegionTabs')), findsOneWidget);
    expectNoForbiddenUserCopy(tester);
    expect(find.byKey(const Key('networkMapLineFilter')), findsNothing);
    expect(find.byKey(const Key('networkMapZoomInButton')), findsNothing);
    expect(find.byKey(const Key('networkMapZoomOutButton')), findsNothing);
    expect(find.byKey(const Key('networkMapOverviewButton')), findsNothing);
    expect(find.byKey(const Key('networkMapLocateButton')), findsNothing);
    expect(find.byKey(const Key('networkMapListButton')), findsNothing);
    expect(find.byTooltip('지도 전체 보기'), findsNothing);
    expect(find.byTooltip('처음 위치로'), findsNothing);
    expect(find.text('노선별로 보기'), findsNothing);
    expect(find.text('노선도별로 보기'), findsNothing);
    expect(find.byTooltip('전체 보기'), findsNothing);
    expect(find.byTooltip('중심 보기'), findsNothing);
    expect(find.text('노선 목록으로 보기'), findsNothing);
    expect(find.byKey(const Key('networkMapSurface')), findsOneWidget);
    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.text('저장'), findsNothing);
    expect(find.text('수도권'), findsOneWidget);
    final regionText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('mapRegionTabs')),
        matching: find.text('수도권'),
      ),
    );
    // 지역명은 FittedBox 축소 대신 말줄임으로 가독성을 유지한다(#1487).
    expect(regionText.overflow, TextOverflow.ellipsis);
    expect(find.text('전국'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('mapRegionTabs'))).height,
      greaterThanOrEqualTo(40),
    );
    expect(find.bySemanticsLabel('지역: 수도권, 지역 변경'), findsOneWidget);
    expect(find.bySemanticsLabel('노선: 전체 노선'), findsNothing);
    expect(find.text('전체 노선'), findsNothing);
    expect(find.byKey(const Key('networkMapInteractiveViewer')), findsNothing);
    expect(find.byType(StructuredRouteMapView), findsOneWidget);

    expect(find.byKey(const Key('networkMapSurface')), findsOneWidget);
    expect(find.byType(StructuredRouteMapView), findsOneWidget);
  });

  testWidgets('홈 shell 경로 상세 뒤로가기는 결과 목록으로 돌아간다', (tester) async {
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
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await _openRouteSearchScreen(tester);
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
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();
    await _openFirstRouteResultDetail(tester);
    expect(find.text('이동 순서'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    expect(find.text('이동 순서'), findsNothing);
    expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
  });

  testWidgets('홈 shell 즐겨찾기 경로 다시 찾기는 저장된 이동 조건을 유지한다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(
          favorites: [_favoriteRoute(mobilityType: 'WHEELCHAIR')],
        ),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(profileId: 'elderly'),
      ),
    );
    await tester.pumpAndSettle();

    await _openSavedItemsScreen(tester);
    // 경로 행을 탭하면 저장된 이동 조건으로 길찾기 화면이 열린다(#1569).
    await tester.tap(find.text('상록수역 → 사당역'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeSearchScreen')), findsOneWidget);
    expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
    // #1933 C: 저장된 조합(출발·도착 확정)으로 진입하면 저장된 이동 조건 그대로
    // 자동 검색까지 이어진다.
    await tester.pumpAndSettle();

    expect(routeRepository.requests.last.mobilityType, 'WHEELCHAIR');
  });

  testWidgets('노선도 메뉴 길찾기는 길찾기 화면으로 전환한다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await _openRouteSearchScreen(tester);

    expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('길찾기')),
      findsOneWidget,
    );
  });

  testWidgets('노선도 메뉴에서 데이터 및 지도 출처 화면으로 이동한다', (tester) async {
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

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('networkMapMenuDataSourcesButton')),
      120,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('networkMapMenuDataSourcesButton')),
        matching: find.byType(InkWell),
      ),
    );
    for (var attempt = 0; attempt < 30; attempt += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('지도 표시용 asset').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(
      find.byKey(const Key('dataSourceAttributionScreen')),
      findsOneWidget,
    );
    expect(find.text('데이터 및 지도 출처'), findsOneWidget);
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(find.text('지도 표시용 asset'), 240);
    expect(find.text('지도 표시용 asset'), findsOneWidget);
    expect(find.text('지금은 상록수역·사당역 구간을 안내해요'), findsNothing);
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byType(StructuredRouteMapView), findsOneWidget);
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

  testWidgets('노선도 로드 실패는 재시도만 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(
            networkMapError: StateError('map failed'),
          ),
          routeDraftController: RouteDraftController(),
          onOpenRouteSearch: () async {},
          onOpenStationSearch: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('노선도를 불러오지 못했어요'), findsOneWidget);
    expect(find.byKey(const Key('networkMapRetryButton')), findsOneWidget);
    expect(find.text('역명으로 검색'), findsNothing);
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

    expect(find.byKey(const Key('networkMapLineFilter')), findsNothing);
    expect(find.text('전체 노선'), findsNothing);
    expect(
      find.byKey(const Key('networkMapSelectedLineOverlay')),
      findsNothing,
    );
    expect(repository.requestedNetworkMapLineIds, isNot(contains('seoul-4')));

    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
  });

  testWidgets('노선도 팝오버 출발 선택은 상단 오버레이에 역명을 띄우고 지우기로 사라진다', (tester) async {
    final routeDraftController = RouteDraftController();
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenRouteSearch: () async {},
          onOpenStationSearch: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // draft가 비어 있으면 상단 오버레이는 뜨지 않는다.
    expect(find.byKey(const Key('networkMapRouteDraftOverlay')), findsNothing);

    // 역 탭 → 팝오버 → "출발" 선택 → 상단 오버레이에 출발역명이 즉시 뜬다(G1).
    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('출발'));
    await tester.pumpAndSettle();

    expect(routeDraftController.draft.origin?.nameKo, '상록수');
    expect(
      find.byKey(const Key('networkMapRouteDraftOverlay')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftOriginRow')),
        matching: find.text('상록수역'),
      ),
      findsOneWidget,
    );
    expect(find.text('도착역을 탭하거나 검색'), findsOneWidget);

    // 출발칸 지우기(✕) → draft에서 출발이 지워지고, 도착도 없으니 오버레이가 사라진다.
    await tester.tap(find.byKey(const Key('networkMapRouteDraftClearOrigin')));
    await tester.pumpAndSettle();

    expect(routeDraftController.draft.origin, isNull);
    expect(find.byKey(const Key('networkMapRouteDraftOverlay')), findsNothing);
  });

  testWidgets('상단 오버레이 출발칸 검색 선택은 지도 탭과 같은 draft로 수렴한다(G4)', (tester) async {
    final routeDraftController = RouteDraftController();
    final pickedSlots = <RouteDraftSlot>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenRouteSearch: () async {},
          onOpenStationSearch: () {},
          // main.dart의 openStationSearchForSlot 대역: 실제 앱에서는 역 검색을 열어
          // 결과 탭 시 같은 controller에 slot을 설정한다. 여기선 그 계약(어떤 slot을
          // 채우려 열렸는지 + 같은 controller로 수렴)만 검증한다.
          onPickStationForSlot: (slot) {
            pickedSlots.add(slot);
            switch (slot) {
              case RouteDraftSlot.origin:
                routeDraftController.setOrigin(
                  const RouteDraftStation(id: 'gangnam', nameKo: '강남'),
                );
              case RouteDraftSlot.destination:
                routeDraftController.setDestination(
                  const RouteDraftStation(id: 'jamsil', nameKo: '잠실'),
                );
            }
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 먼저 지도 탭 경로로 출발역을 넣는다 → 오버레이가 뜬다.
    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('출발'));
    await tester.pumpAndSettle();
    expect(routeDraftController.draft.origin?.nameKo, '상록수');

    // 도착 칸(검색 진입 버튼)을 탭하면 도착 slot으로 검색이 열린다.
    await tester.tap(
      find.byKey(const Key('networkMapRouteDraftPickDestination')),
    );
    await tester.pumpAndSettle();

    // 텍스트 검색으로 넣은 도착이 지도 탭 출발과 같은 오버레이 상태로 수렴한다.
    expect(pickedSlots, [RouteDraftSlot.destination]);
    expect(routeDraftController.draft.origin?.nameKo, '상록수');
    expect(routeDraftController.draft.destination?.nameKo, '잠실');
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftDestinationRow')),
        matching: find.text('잠실역'),
      ),
      findsOneWidget,
    );

    // 반대로 출발 칸도 검색으로 교체 가능(같은 controller로 수렴).
    await tester.tap(find.byKey(const Key('networkMapRouteDraftPickOrigin')));
    await tester.pumpAndSettle();
    expect(pickedSlots, [RouteDraftSlot.destination, RouteDraftSlot.origin]);
    expect(routeDraftController.draft.origin?.nameKo, '강남');
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftOriginRow')),
        matching: find.text('강남역'),
      ),
      findsOneWidget,
    );
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

    expect(find.byKey(const Key('networkMapListButton')), findsNothing);
    expect(find.byKey(const Key('networkMapListSheet')), findsNothing);
    expect(find.text('노선별로 보기'), findsNothing);
    expect(find.text('노선도별로 보기'), findsNothing);
    expect(find.text('노선별 역 보기'), findsNothing);
    expect(find.text('노선별 목록에서 역을 선택하세요.'), findsNothing);
  });

  testWidgets('운행 공지 disruption은 홈 배너·좌측 메뉴·목록까지 배선된다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        noticeRepository: _FakeNoticeRepository(
          ActiveNoticesResult(
            notices: [
              ServiceNotice(
                id: 'n1',
                scope: NoticeScope.all,
                title: '2호선 강남–역삼 지연 — 우회 경로를 확인하세요',
                body: '상행 지연이 이어지고 있어요.',
                severity: NoticeSeverity.disruption,
                publishedAt: DateTime(2026, 7, 6, 9, 0, 0),
              ),
            ],
            stale: false,
          ),
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    // ① 홈 상단 disruption 배너.
    expect(find.byKey(const Key('serviceNoticeBanner')), findsOneWidget);
    expect(find.text('2호선 강남–역삼 지연 — 우회 경로를 확인하세요'), findsOneWidget);

    // ② 좌측 메뉴 "운행 공지" 진입점 → 목록 화면.
    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('networkMapMenuServiceNoticesButton')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('networkMapMenuServiceNoticesButton')),
    );
    await tester.pumpAndSettle();
    expect(find.text('운행 공지'), findsOneWidget); // 목록 화면 AppBar 제목.
    expect(find.text('상행 지연이 이어지고 있어요.'), findsOneWidget);
  });

  testWidgets('운행 공지 배너는 닫기로 사라진다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        noticeRepository: _FakeNoticeRepository(
          ActiveNoticesResult(
            notices: [
              ServiceNotice(
                id: 'n1',
                scope: NoticeScope.all,
                title: '1호선 지연 안내',
                body: '지연이 이어지고 있어요.',
                severity: NoticeSeverity.disruption,
                publishedAt: DateTime(2026, 7, 6, 9, 0, 0),
              ),
            ],
            stale: false,
          ),
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('serviceNoticeBanner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('serviceNoticeBannerDismiss')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('serviceNoticeBanner')), findsNothing);
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

  test('공식 노선도 초기 화면은 중앙 확대 bounds에서 시작한다', () {
    final bounds = networkMapInitialOriginalAssetBounds(
      sourceWidth: 5724,
      sourceHeight: 6516,
    );

    expect(bounds.left, closeTo(1202.04, 0.01));
    expect(bounds.top, closeTo(1368.36, 0.01));
    expect(bounds.width, closeTo(3319.92, 0.01));
    expect(bounds.height, closeTo(3779.28, 0.01));
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
        candidate: committed.copyWith(center: const Offset(1200, 250)),
        elapsedSinceLastCommit: const Duration(milliseconds: 40),
      ),
      isTrue,
    );
    expect(
      networkMapShouldCommitRendererCamera(
        committed: committed,
        candidate: committed.copyWith(scale: 1.75),
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
        elapsedSinceLastCommit: const Duration(milliseconds: 1100),
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
      // #1641: SVG 이미지는 더 이상 번들하지 않는다(canvas 렌더). 소스 경로와
      // 라이선스 속성표기만 유지된다(광주 CC-BY-SA 등).
      expect(offline['included'], isFalse);
      expect(path, startsWith('assets/datapacks/maps/'));
      final extension = path.split('.').last.toLowerCase();
      expect(extension, anyOf('pdf', 'svg'));
      expect(offline['type'], extension);
      final license = map['license'] as Map<String, Object?>;
      expect(license['name'], isA<String>());
      expect(license['spdx'], isA<String>());
      expect(license['url'], startsWith('https://'));
      expect(license['source_page'], startsWith('https://'));
      expect(license['authors'], isA<List<Object?>>());
      expect(license['changes'], isA<String>());
      expect(license['attributionRequired'], isA<bool>());
      expect(license['commercialUseAllowed'], isA<bool>());
      expect(license['derivativeWorkAllowed'], isA<bool>());
      expect(license['redistributionAllowed'], isA<bool>());
      expect(license['reviewStatus'], isA<String>());
    }
    final gwangju = maps.singleWhere((map) => map['id'] == 'gwangju');
    final license = gwangju['license'] as Map<String, Object?>;
    expect(license['spdx'], 'CC-BY-SA-2.0-KR');
    expect(
      license['url'],
      'https://creativecommons.org/licenses/by-sa/2.0/kr/',
    );
    expect(license['reviewStatus'], 'legal-review-required');
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

    final surface = tester.widget<Container>(
      find.byKey(const Key('networkMapSurface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(decoration.border, isNull);
    expect(decoration.borderRadius, isNull);
    expect(find.byType(StructuredRouteMapView), findsOneWidget);
    expect(find.byKey(const Key('networkMapPainter')), findsNothing);
  });

  testWidgets('수도권 노선도는 Android에서 구조화 canvas 렌더러로 전체 크기를 채운다', (tester) async {
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

      expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

      expect(
        find.byKey(const Key('networkMapInteractiveViewer')),
        findsNothing,
      );
      final renderer = tester.getSize(find.byType(StructuredRouteMapView));
      final surface = tester.getSize(
        find.byKey(const Key('networkMapSurface')),
      );
      expect(renderer.width, surface.width);
      expect(renderer.height, surface.height);
      expect(
        tester.widget(find.byType(StructuredRouteMapView)),
        isA<StructuredRouteMapView>(),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetDevicePixelRatio();
    }
  });

  test('Android 노선도 edge resolver는 station-line endpoint를 해석한다', () {
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

  test('급행 노선도 필터는 station-line endpoint edge를 유지한다', () {
    final expressMap = networkMapExpressOnlyMapData(_expressFilterMapData());

    expect(expressMap.lines.map((line) => line.id), ['line-express']);
    expect(expressMap.stations.map((station) => station.lineId).toSet(), {
      'line-express',
    });
    expect(expressMap.edges, hasLength(1));
    expect(
      expressMap.edges.single.fromStationId,
      'station-express-a:line-express',
    );
    expect(
      expressMap.edges.single.toStationId,
      'station-express-b:line-express',
    );
  });

  testWidgets('노선도 급행 전환은 필터 밖 선택 역 탭을 숨긴다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(
          networkMapData: _expressFilterMapData(),
        ),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('networkMapStation-local-a-line-local')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);

    await tester.tap(find.text('급행'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);
    expect(
      find.byKey(const Key('networkMapStation-express-a-line-express')),
      findsOneWidget,
    );
  });

  testWidgets('노선도 viewport 밖 station semantics는 생성하지 않는다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    // #1764 E: 소규모 지역(역 40 이하)은 초기에 전체를 조망하므로 viewport
    // culling이 없다. 밖 역 semantics 미생성(culling)은 대형 지역에서만 유효하므로,
    // 도심에 filler 역을 채워 대형 지역(역 40 초과) 경로로 검증한다.
    final map = NetworkMapData(
      regions: const [NetworkMapRegion(name: '테스트권')],
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
        // 도심(x≈4900)에 filler를 채워 역 40 초과 → 대형 지역 culling 경로(#1764 E).
        for (var i = 0; i < 45; i += 1)
          NetworkMapStation(
            id: 'station-filler-$i',
            nameKo: '채움$i',
            nameEn: 'Filler $i',
            region: '테스트권',
            lineId: 'geometry-helper',
            stationCode: 'F$i',
            sequence: i,
            position: NetworkMapPosition(
              x: 4900 + i,
              y: 100,
              labelDx: 0,
              labelDy: 0,
              upPath: '',
              downPath: '',
              sourceId: 'fixture-route-map-source-capital-review',
            ),
          ),
      ],
      edges: const [],
      positionSources: [
        NetworkMapPositionSource(
          id: 'fixture-route-map-source-capital-review',
          name: '수도권 노선도 fixture 좌표 확인',
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

      expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

      // culling(밖 역 semantics 미생성)은 대형 지역 경로에서만 유효하다. filler로
      // 임계를 넘겨 대형 지역임을 명시 단정 — 임계 상향으로 소규모 경로가 되면
      // 이 단정이 깨져 vacuous pass를 막는다(#1764 E).
      expect(
        networkMapUsesWholeRegionInitialView(map.stations.length),
        isFalse,
        reason: 'filler로 대형 지역(전체 조망 아님) 경로를 유지해야 culling이 유효',
      );

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
      expect(find.text('출발'), findsOneWidget);
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
    expect(find.text('도착'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapStationSheet')),
        matching: find.text('길찾기'),
      ),
      findsOneWidget,
    );
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

      expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
      final stationFinder = find.byKey(
        const Key('networkMapStation-sangnoksu-seoul-4'),
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
      expect(find.text('출발'), findsOneWidget);
      expect(find.text('도착'), findsOneWidget);
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('networkMapStation-gusan-seoul-6')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
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
            name: '수도권 노선도 fixture 좌표 확인',
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

    final stationTarget = find.byKey(
      const Key('networkMapStation-polygon-seoul-4'),
    );
    final targetRect = tester.getRect(stationTarget);
    await tester.tapAt(targetRect.topLeft + const Offset(47, 32));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
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
            name: '수도권 노선도 fixture 좌표 확인',
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('networkMapStation-polygon-seoul-4')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
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
            name: '수도권 노선도 fixture 좌표 확인',
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

    final surfaceRect = tester.getRect(
      find.byKey(const Key('networkMapSurface')),
    );
    await tester.tapAt(surfaceRect.bottomCenter - const Offset(0, 54));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);
    expect(find.text('가까운역'), findsNothing);

    await tester.tapAt(surfaceRect.centerRight - const Offset(54, 0));
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
            name: '수도권 노선도 fixture 좌표 확인',
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
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
    await firstGesture.up();
    await secondGesture.up();
    await tester.pumpAndSettle();

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
            name: '수도권 노선도 fixture 좌표 확인',
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

    await tester.tap(find.byKey(const Key('networkMapStation-b-node-seoul-4')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.text('출발'), findsOneWidget);
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
            name: '수도권 노선도 fixture 좌표 확인',
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

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
    expect(find.text('출발'), findsOneWidget);
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
            name: '수도권 노선도 fixture 좌표 확인',
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

      expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

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
            name: '수도권 노선도 fixture 좌표 확인',
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

      expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);

      final firstGeometry = find.byKey(
        const Key('networkMapStation-transfer-seoul-2'),
      );
      final secondGeometry = find.byKey(
        const Key('networkMapStation-transfer-seoul-4'),
      );
      expect(firstGeometry, findsOneWidget);
      expect(secondGeometry, findsOneWidget);
      expect(find.bySemanticsLabel('환승역'), findsNWidgets(2));

      await tester.tap(secondGeometry);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
      expect(find.text('출발'), findsOneWidget);
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byKey(const Key('routeSearchButton')), findsNothing);
    expect(find.byKey(const Key('heroStationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapMenuButton')), findsOneWidget);
    expect(find.byKey(const Key('nearbyStationButton')), findsOneWidget);
    expect(find.byKey(const Key('homeHeroCard')), findsNothing);
    expect(find.text('시설 알림'), findsNothing);
    expect(find.text('상록수역 3번 출구 엘리베이터'), findsNothing);
    expect(find.text('주의'), findsNothing);
    expect(find.text('대체 1번 출구'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '대체 길 보기'), findsNothing);
    final stationHeroButtonSize = tester.getSize(
      find.byKey(const Key('heroStationSearchButton')),
    );
    expect(stationHeroButtonSize.height, greaterThanOrEqualTo(38));
    expect(find.text('최근 경로'), findsNothing);
    expect(find.text('64분'), findsNothing);
    expect(find.textContaining('이동 점수'), findsNothing);
    expect(find.textContaining('정보 신뢰도'), findsNothing);
    expect(find.byKey(const Key('homeSavedItemsCard')), findsNothing);
  });

  testWidgets('홈 즐겨찾기는 여러 시설을 인라인 행으로 나열한다', (tester) async {
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

    expect(find.text('시설 알림'), findsNothing);
    await _openSavedItemsScreen(tester);
    // 카테고리 진입·알림 카드 없이 시설이 인라인 행으로 바로 보인다(#1569).
    expect(find.text('시설'), findsOneWidget);
    expect(find.text('3번 출구 엘리베이터'), findsOneWidget);
    expect(find.text('2번 출구 엘리베이터'), findsOneWidget);
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

    expect(find.text('시설 알림'), findsNothing);
    await _openSavedItemsScreen(tester);
    expect(find.byKey(const Key('favoriteHomeScreen')), findsOneWidget);
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

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.text('시설 알림을 불러오지 못했어요'), findsNothing);
    expect(find.text('최근 경로를 불러오지 못했어요'), findsNothing);
  });

  testWidgets('노선도 현재위치 버튼은 지도 위 액션 탭과 하단 주변역 패널을 보여준다', (tester) async {
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
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('networkMapBottomAdBanner')), findsNothing);
    expect(locationProvider.requestCount, 1);
    expect(repository.requestedNearbyLocations, hasLength(1));
    final requested = repository.requestedNearbyLocations.single;
    expect(requested.latitude, closeTo(37.3028, 0.0001));
    expect(requested.longitude, closeTo(126.8665, 0.0001));
    // 실시간 미연동(UnavailableRealtimeRepository) 상태에서는 "실시간" 뱃지와
    // "-" 자리표시 대신 한 줄 안내만 보여준다.
    expect(find.text('실시간'), findsNothing);
    expect(find.text('상록수'), findsOneWidget);
    expect(find.textContaining('반월'), findsOneWidget);
    expect(find.textContaining('한대앞'), findsOneWidget);
    expect(find.textContaining('이용할 수 있습니다'), findsOneWidget);
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
  });

  testWidgets('노선도 좌측 메뉴 하단에 광고 슬롯이 있다', (tester) async {
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

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();

    // debug 빌드에서는 자리 확인용 슬롯이 패널 하단에 렌더링된다.
    // (release에서는 실광고가 없으면 collapse — 노출 규칙은 #1485)
    expect(find.byKey(const Key('networkMapMenuAdBanner')), findsOneWidget);
  });

  testWidgets('노선도 chrome은 시스템 글자 크기를 따른다', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byKey(const Key('networkMapRegionDropdown'))),
      ).scale(15),
      closeTo(30, 0.01),
    );

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(
      MediaQuery.textScalerOf(
        tester.element(find.byKey(const Key('networkMapNearbyStationPanel'))),
      ).scale(12),
      closeTo(24, 0.01),
    );
  });

  testWidgets('노선도 현재위치 실패는 하단 패널 대신 임시 메시지만 보여준다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException('현재 위치를 확인하지 못했어요.'),
      needsPermissionRequest: false,
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('networkMapNearbyStationPanel')), findsNothing);
    expect(find.byKey(const Key('networkMapBottomAdBanner')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyLookupMessage')),
      findsOneWidget,
    );
    expect(find.text('현재 위치를 확인하지 못했어요.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('현재 위치를 확인하지 못했어요.'), findsNothing);
    expect(find.byKey(const Key('networkMapNearbyStationPanel')), findsNothing);
  });

  testWidgets('노선도 주변역 패널은 실시간 도착 정보를 방향별로 보여준다', (tester) async {
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
        realtimeRepository: const _FreshNearbyRealtimeRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    // FRESH 상태에서만 "실시간" 뱃지가 노출되고, 도착 정보가 방향별로 표시된다.
    expect(find.text('실시간'), findsOneWidget);
    expect(find.text('상행'), findsOneWidget);
    expect(find.text('하행'), findsOneWidget);
    expect(find.text('한대앞행'), findsOneWidget);
    expect(find.text('사당행'), findsOneWidget);
    expect(find.text('약 3분'), findsOneWidget);
    expect(find.text('약 5분'), findsOneWidget);
  });

  testWidgets('노선도는 위치 권한이 이미 있으면 가까운 역 중심 viewport를 저장한다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      location: _freshCurrentLocation(),
      needsPermissionRequest: false,
    );
    final viewportRepository = FakeNetworkMapViewportRepository();
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권'],
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
        networkMapViewportRepository: viewportRepository,
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(locationProvider.permissionCheckCount, 1);
    expect(locationProvider.requestCount, 1);
    expect(repository.requestedNearbyLocations, hasLength(1));
    expect(viewportRepository.loadedRegions, contains('수도권'));
    expect(viewportRepository.savedViewports['수도권'], isNotNull);
    expect(find.byKey(const Key('networkMapNearbyStationPanel')), findsNothing);
  });

  testWidgets('노선도 좌측 메뉴에서 설정 화면으로 들어갈 수 있다', (tester) async {
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

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('networkMapMenuSettingsButton')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('networkMapMenuSettingsButton')));
    await tester.pumpAndSettle();

    expect(find.byType(AppSettingsScreen), findsOneWidget);
  });

  testWidgets('가까운 역 화면은 위치 실패 후 역명 검색 입력을 보여준다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException('현재 위치를 확인하지 못했어요.'),
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

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('networkMapMenuNearbyButton')));
    await tester.pumpAndSettle();

    expect(find.text('현재 위치를 확인하지 못했어요.'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
    expect(find.byKey(const Key('nearbyStationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('stationRecentSearchSection')), findsNothing);

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
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

      await _openSettingsScreen(tester);

      expect(find.text(option.appliedConditionLabel), findsOneWidget);
      expect(find.byIcon(Icons.directions_walk), findsOneWidget);
    }
  });

  testWidgets('홈 핵심 행동은 좁은 화면과 시스템 글자 크기에서도 터치 기준을 지킨다', (tester) async {
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
      tester.getSize(find.byKey(const Key('networkMapMenuButton'))).height,
      greaterThanOrEqualTo(40),
    );
    expect(
      tester.getSize(find.byKey(const Key('heroStationSearchButton'))).height,
      greaterThanOrEqualTo(38),
    );
    expect(find.byKey(const Key('networkMapMenuButton')), findsOneWidget);
    expect(find.byKey(const Key('homeProfilePill')), findsNothing);
  });

  testWidgets('홈 최근 경로 역명은 말줄임으로 자르지 않는다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(),
        recentRoutesFuture: Future.value([_favoriteRoute()]),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('homeRecentRouteCard')), findsNothing);
    expect(find.text('최근 경로'), findsNothing);
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
              largeTextEnabled: false,
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
      expect(find.byKey(const Key('homeLargeScreenLayout')), findsNothing);
      expect(find.byKey(const Key('networkMapMenuButton')), findsOneWidget);
      expect(find.byKey(const Key('heroStationSearchButton')), findsOneWidget);
      expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 200% 글자 screenshot smoke는 핵심 CTA 렌더 이미지를 만든다', (tester) async {
    final screenshotKey = GlobalKey();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingStateWithPreferences(
            preferences: const OnboardingViewPreferences(
              largeTextEnabled: false,
              highContrastEnabled: true,
              simpleViewEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('networkMapMenuButton')), findsOneWidget);
    expect(find.byKey(const Key('heroStationSearchButton')), findsOneWidget);

    final boundary =
        screenshotKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    addTearDown(image.dispose);
    expect(image.width, 390);
    expect(image.height, 844);
  });

  testWidgets('홈 즐겨찾기는 저장한 경로를 인라인 카드로 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
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
          initialOnboardingState: _completedOnboardingState(),
        ),
      );
      await tester.pumpAndSettle();

      await _openSavedItemsScreen(tester);

      // 카테고리 진입 없이 경로가 인라인 카드로 바로 보인다(#1569).
      expect(find.text('경로'), findsOneWidget);
      expect(find.text('상록수역 → 사당역'), findsOneWidget);
      expect(find.text('저장한 경로가 없습니다'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈은 저장 경로 재조회 실패를 즐겨찾기 카드로 표시하지 않는다', (tester) async {
    final favoriteRouteRepository = FakeFavoriteRouteRepository()
      ..error = const FavoriteRouteException('즐겨찾기 경로를 불러오지 못했어요.');

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

    await _openRouteSearchScreen(tester);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('길찾기')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('즐겨찾기한 경로를 불러오지 못했어요'), findsNothing);
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
              largeTextEnabled: false,
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
        find.descendant(of: find.byType(AppBar), matching: find.text('더보기')),
        findsOneWidget,
      );
      expect(find.text('화면·접근성 설정'), findsNothing);
      expect(find.text('이동 조건'), findsOneWidget);
      expect(find.text('화면 및 접근성'), findsOneWidget);
      expect(find.text('경로 찾기'), findsNothing);
      // '저장된 안내'(인터넷 없이 이용·데이터 출처) 섹션은 제거됐다(#1570).
      expect(find.text('저장된 안내'), findsNothing);
      expect(find.text('계단 피하기 · 환승 줄이기 적용 중'), findsOneWidget);
      expect(find.text('계단을 피하고 쉬운 환승을 우선해요'), findsOneWidget);
      expect(find.text('큰 글자'), findsNothing);
      expect(find.text('고대비'), findsOneWidget);
      expect(find.text('간편 보기'), findsOneWidget);
      expect(find.text('켜짐'), findsWidgets);
      expect(find.text('꺼짐'), findsWidgets);
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
      // 오프라인·데이터 출처 진입점은 더보기에서 제거됐다(#1570).
      expect(find.byKey(const Key('offlineDataSettingsButton')), findsNothing);
      expect(
        find.byKey(const Key('dataSourceAttributionSettingsButton')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('settingsSupportPrivacyButton')),
        findsOneWidget,
      );
      expect(
        settingsActionSemantics(
          '알림 설정',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      // 자명한 행은 부가설명 없이 제목만 시맨틱에 담는다(#1570·#1572).
      expect(
        settingsActionSemantics(
          '도움말·문의',
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

  testWidgets('데이터 및 지도 출처 화면은 manifest와 source inventory를 보여준다', (
    tester,
  ) async {
    final manifest =
        jsonDecode(
              File(
                'assets/datapacks/metro_map_pack/manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final inventory =
        jsonDecode(
              File('assets/datapacks/source-inventory.json').readAsStringSync(),
            )
            as Map<String, Object?>;

    await tester.pumpWidget(
      MaterialApp(
        home: DataSourceAttributionScreen(
          initialManifest: manifest,
          initialInventory: inventory,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('dataSourceAttributionScreen')),
      findsOneWidget,
    );
    expect(find.text('데이터 및 지도 출처'), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
    expect(find.text('현재 앱 표시'), findsOneWidget);
    expect(find.textContaining('공식·공개 자료를 바탕으로'), findsOneWidget);
    // 내부 거버넌스 언어(pilot·"~보장한다고 말하지 않아요")는 사용자 화면에
    // 노출하지 않는다(#1765).
    expect(find.textContaining('pilot'), findsNothing);
    expect(find.textContaining('보장한다고 말하지 않아요'), findsNothing);
    await tester.scrollUntilVisible(find.text('데이터 품질 Level'), 160);
    await tester.pumpAndSettle();
    expect(find.text('데이터 품질 Level'), findsOneWidget);
    expect(find.text('Level 1-4 품질 기준'), findsOneWidget);
    expect(
      find.textContaining('Level 4는 현장 또는 운영기관이 확인한 쉬운 길'),
      findsOneWidget,
    );
    expect(find.text('품질 지표'), findsOneWidget);
    expect(find.textContaining('필수 시설 근거 비율'), findsOneWidget);
    expect(find.textContaining('현장 확인 경로 비율'), findsOneWidget);

    final maps = (manifest['maps'] as List).cast<Map<String, Object?>>();
    final sources = (inventory['sources'] as List).cast<Map<String, Object?>>();

    expect(maps.map((map) => map['app_region']), contains('수도권'));
    expect(sources, isNotEmpty);
  });

  testWidgets('설정 화면 보기 옵션은 변경값을 저장하고 다시 실행해도 유지한다', (tester) async {
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
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
    expect(find.byKey(const Key('largeTextSettingsButton')), findsNothing);
    expect(find.text('큰 글자'), findsNothing);
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('simpleViewSettingsButton')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 2);
    expect(onboardingStore.savedResult?.preferences.largeTextEnabled, isFalse);
    expect(
      onboardingStore.savedResult?.preferences.highContrastEnabled,
      isTrue,
    );
    expect(onboardingStore.savedResult?.preferences.simpleViewEnabled, isFalse);
    expect(find.text('큰 글자'), findsNothing);
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
    expect(find.byKey(const Key('largeTextSettingsButton')), findsNothing);
    expect(find.text('큰 글자'), findsNothing);
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
          largeTextEnabled: false,
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
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 1);
    expect(onboardingStore.savedResult?.preferences.largeTextEnabled, isFalse);
    expect(
      onboardingStore.savedResult?.preferences.highContrastEnabled,
      isFalse,
    );
    expect(
      find.bySemanticsLabel(RegExp('고대비, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(find.text('설정을 저장하지 못했어요. 이전 값으로 되돌렸어요.'), findsOneWidget);
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
    expect(find.text('이동 조건을 저장하지 못했어요. 이전 조건으로 되돌렸어요.'), findsOneWidget);
  });

  testWidgets('설정 화면 보기 옵션은 빠른 연속 변경에서도 마지막 값을 저장한다', (tester) async {
    final firstSave = Completer<void>();
    final latestSave = Completer<void>();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
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
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('simpleViewSettingsButton')));
    await tester.pump();

    expect(onboardingStore.saveCount, 1);
    expect(find.text('큰 글자'), findsNothing);
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
          largeTextEnabled: false,
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
    expect(find.text('큰 글자'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('고대비, 켜짐, .*두 번 탭해 끄기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('간편 보기, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(find.text('설정을 저장하지 못했어요. 이전 값으로 되돌렸어요.'), findsNothing);
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
          largeTextEnabled: false,
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
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('simpleViewSettingsButton')));
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
      isTrue,
    );
    expect(onboardingStore.savedResult?.preferences.simpleViewEnabled, isTrue);
    expect(find.text('큰 글자'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('고대비, 켜짐, .*두 번 탭해 끄기')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('간편 보기, 켜짐, .*두 번 탭해 끄기')),
      findsOneWidget,
    );
    expect(find.text('설정을 저장하지 못했어요. 이전 값으로 되돌렸어요.'), findsOneWidget);
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
          largeTextEnabled: false,
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
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('simpleViewSettingsButton')));
    await tester.pump();

    firstSave.completeError(StateError('first save failed'));
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
    expect(find.text('큰 글자'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('고대비, 꺼짐, .*두 번 탭해 켜기')),
      findsOneWidget,
    );
    expect(find.text('설정을 저장하지 못했어요. 이전 값으로 되돌렸어요.'), findsOneWidget);
  });

  testWidgets('설정 화면 보기 옵션 저장 중 이동 조건을 바꿔도 마지막 결과를 유지한다', (tester) async {
    final firstSave = Completer<void>();
    final latestSave = Completer<void>();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.first,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
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
    await tester.tap(find.byKey(const Key('highContrastSettingsButton')));
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
      isTrue,
    );
    expect(onboardingStore.savedResult?.preferences.simpleViewEnabled, isTrue);
  });

  testWidgets('설정 화면 보기 옵션은 시스템 글자 크기에서도 스위치를 조작할 수 있다', (tester) async {
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
            largeTextEnabled: false,
            highContrastEnabled: true,
            simpleViewEnabled: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openSettingsScreen(tester);

    expect(find.byKey(const Key('largeTextSettingsButton')), findsNothing);
    expect(find.text('큰 글자'), findsNothing);
    expect(find.byKey(const Key('highContrastSettingsButton')), findsOneWidget);
    expect(find.byKey(const Key('simpleViewSettingsButton')), findsOneWidget);
    // 알림 미구현 고지 섹션은 제거됐다(#1570). 알림 저장소가 없으면 섹션 자체가 없다.
    expect(find.byKey(const Key('settingsSection-notification')), findsNothing);
    expect(find.text('알림은 아직 사용할 수 없어요'), findsNothing);
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
    await _openSettingsScreen(tester);

    expect(find.text('계단 피하기 · 환승 줄이기 적용 중'), findsOneWidget);

    await _openMobilityProfileFromSettings(tester);
    await tester.tap(find.byKey(const Key('mobilityProfileCard-wheelchair')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityProfileDoneButton')));
    await tester.pumpAndSettle();
    expect(find.text('계단 피하기 · 엘리베이터 이동 적용 중'), findsOneWidget);
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
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('favoritesButton')), findsNothing);
    expect(find.byKey(const Key('favoriteRoutesButton')), findsNothing);
    expect(find.byKey(const Key('favoriteStationsButton')), findsNothing);
    expect(find.byKey(const Key('favoriteFacilitiesButton')), findsNothing);

    await _openSavedItemsScreen(tester);

    expect(find.byKey(const Key('favoriteHomeScreen')), findsOneWidget);
    // 카테고리 카드·개수 없이 저장 항목이 섹션별로 바로 나열된다(#1569).
    expect(find.byKey(const Key('favoriteHomeStationsButton')), findsNothing);
    expect(find.byKey(const Key('favoriteHomeFacilitiesButton')), findsNothing);
    expect(find.byKey(const Key('favoriteHomeRoutesButton')), findsNothing);
    expect(find.text('역'), findsOneWidget);
    expect(find.text('경로'), findsOneWidget);
    expect(find.text('시설'), findsOneWidget);
    expect(find.text('상록수역'), findsWidgets);
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

    // 역 행 → 상세 화면(하위)로 진입 후 복귀 시 새로고침이 실패하면 오류 상태(#1569).
    await tester.tap(
      find.byKey(const Key('favoriteHomeStationRow-station-sangnoksu')),
    );
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
            securityEmail: 'security@easysubway.example',
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
      expect(find.text('내 정보 삭제 요청'), findsOneWidget);

      final deletionButtonSize = tester.getSize(
        find.byKey(const Key('dataDeletionAccessItem')),
      );

      expect(deletionButtonSize.height, greaterThanOrEqualTo(60));
      final deletionSemantics = tester
          .getSemantics(find.byKey(const Key('dataDeletionAccessItem')))
          .getSemanticsData();
      expect(
        deletionSemantics.label,
        '내 정보 삭제 요청, 이메일 보내기, privacy@easysubway.example',
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
      expect(find.text('아직 준비 중이에요'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('도움말은 개인정보 안내를 불릿 대신 처리방침 링크로 위임한다', (tester) async {
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

      // 개인정보 안내는 화면 카피(불릿) 대신 처리방침 링크로 위임한다.
      expect(find.byKey(const Key('privacyDataUseSummary')), findsNothing);
      expect(find.text('개인정보 사용 안내'), findsNothing);
      expect(find.text('현재 위치는 가까운 역 찾기와 시설 제보 위치 확인에만 사용됩니다.'), findsNothing);
      expect(find.text('법으로 꼭 필요한 기록은 정해진 기간 동안만 보관합니다.'), findsNothing);
      expect(find.text('개인정보처리방침'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('도움말은 이동 전 살펴보기 안내를 함께 보여준다', (tester) async {
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

      expect(find.text('이동 전 살펴보기'), findsWidgets);
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
        '이동 전 살펴보기, 경로와 시설 정보는 이동을 돕는 참고 정보입니다. 실제 이동 전에는 현장 안내, 역무원 안내, 운영기관 공지를 먼저 확인해 주세요. 실시간 상태나 무조건 안전한 경로를 보장하지 않습니다.',
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('도움말은 보안과 개인정보 문의 경로를 안내한다', (tester) async {
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
      expect(find.text('앱 보안이나 개인정보가 걱정되면 문의로 알려주세요.'), findsOneWidget);
      expect(
        find.text('위치, 제보 사진, 알림, 개인정보 관련 걱정을 함께 보낼 수 있습니다.'),
        findsOneWidget,
      );
      expect(find.textContaining('취약점'), findsNothing);
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
    expect(find.text('이 기기의 앱 정보 삭제'), findsWidgets);
    expect(find.textContaining('즐겨찾기, 최근 검색, 이동 조건, 화면 설정'), findsOneWidget);
    expect(find.text('이미 보낸 시설 제보와 사진은 그대로 남아요.'), findsOneWidget);
    expect(find.text('삭제 후에는 되돌릴 수 없어요.'), findsOneWidget);
    expect(find.textContaining('로그인 정보'), findsNothing);
    expect(find.textContaining('익명화'), findsNothing);

    await tester.tap(find.byKey(const Key('dataDeletionStartButton')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('정말 삭제할까요?'), findsOneWidget);
    expect(find.textContaining('인증 정보'), findsNothing);
    expect(find.text('이 기기의 즐겨찾기·최근 검색·설정이 지워지고 되돌릴 수 없어요.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dataDeletionConfirmButton')));
    await tester.pumpAndSettle();

    expect(deletionRepository.deleteCount, 1);
    expect(find.text('삭제 완료'), findsOneWidget);
    expect(find.text('내 정보가 삭제됐어요'), findsOneWidget);
    expect(find.text('앱이 처음 사용하는 상태로 돌아갑니다.'), findsOneWidget);
    expect(find.text('노선도와 역 정보는 계속 이용할 수 있어요'), findsOneWidget);
    // 내부 처리 카테고리 카운트·시스템 독백은 결과 화면에서 사라진다(#1580).
    expect(find.textContaining('개 삭제'), findsNothing);
    expect(find.textContaining('건 삭제'), findsNothing);
    expect(find.textContaining('누구의 정보인지 알 수 없게'), findsNothing);
    expect(
      find.byKey(const Key('dataDeletionResultRow-favoriteStations')),
      findsNothing,
    );
    expect(find.textContaining('연결 정보'), findsNothing);
    expect(find.textContaining('익명화'), findsNothing);
    expect(find.textContaining('local-user'), findsNothing);
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
      MaterialApp(home: UserDataDeletionResultScreen(onRestart: () {})),
    );

    final screenBottom =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final buttonRect = tester.getRect(
      find.byKey(const Key('dataDeletionResultStartButton')),
    );

    expect(screenBottom - buttonRect.bottom, greaterThanOrEqualTo(66));
  });

  testWidgets('데이터 삭제 결과는 완료 안내와 다음 행동만 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: UserDataDeletionResultScreen(onRestart: () {})),
    );

    expect(find.text('내 정보가 삭제됐어요'), findsOneWidget);
    expect(find.text('노선도와 역 정보는 계속 이용할 수 있어요'), findsOneWidget);
    expect(
      find.byKey(const Key('dataDeletionResultStartButton')),
      findsOneWidget,
    );
    // 내부 처리 카테고리·시스템 독백은 노출하지 않는다(#1580).
    expect(find.text('삭제 결과'), findsNothing);
    expect(find.text('알림 설정은 이미 비어 있어요'), findsNothing);
    expect(find.textContaining('누구의 정보인지 알 수 없게'), findsNothing);
    expectNoForbiddenUserCopy(tester);
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

      // 개인정보 요약 불릿은 제거됐다(처리방침 링크로 위임).
      expect(find.byKey(const Key('privacyDataUseSummary')), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('dataDeletionAccessItem')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('dataDeletionAccessItem')));
      await tester.pumpAndSettle();

      expect(find.text('보낸 정보 삭제'), findsWidgets);
      expect(
        find.text('보낸 제보와 사진·위치, 즐겨찾기, 이동 조건이 삭제되거나 익명 처리돼요.'),
        findsOneWidget,
      );
      expect(find.text('삭제 후에는 되돌릴 수 없어요.'), findsOneWidget);
      expect(find.textContaining('이미 보낸 시설 제보'), findsNothing);

      await tester.tap(find.byKey(const Key('dataDeletionStartButton')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('보낸 정보와 설정이 삭제·익명 처리되고 되돌릴 수 없어요.'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('데이터 삭제 실패 시 로컬 상태를 유지하고 오류를 안내한다', (tester) async {
    final deletionRepository = FakeUserDataDeletionRepository(
      error: const UserDataDeletionException(
        '정보 삭제를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
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
    expect(find.text('정보 삭제를 완료하지 못했어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('도움말은 연결값이 비어 있으면 항목을 숨기고 준비 중 문구를 내보내지 않는다', (tester) async {
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

    // 연결값이 없으면 '준비 중' 문구 대신 항목 자체를 숨긴다.
    expect(find.text('아직 준비 중이에요'), findsNothing);
    expect(find.byKey(const Key('privacyPolicyAccessItem')), findsNothing);
    expect(find.byKey(const Key('dataDeletionAccessItem')), findsNothing);
    expect(find.byKey(const Key('supportAccessItem')), findsNothing);
    expect(find.byKey(const Key('securityContactAccessItem')), findsNothing);
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
      expect(find.text('제보 진행 알림'), findsOneWidget);
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
        '즐겨찾는 역과 경로의 시설 변경, 제보 진행 상황, 최신 안내를 알려드려요. 알림 설정에서 언제든 끌 수 있습니다.',
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

  testWidgets('알림 설정 화면은 기기 알림 실패 도움말을 안내한다', (tester) async {
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
      expect(find.text('기기 알림 등록을 마치지 못했어요.'), findsNothing);
      expect(find.text('알림을 켜지 못했어요.'), findsOneWidget);
      expect(
        find.text('휴대전화 알림 설정과 인터넷 연결을 확인한 뒤 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('도움말, 휴대전화 알림 설정과 인터넷 연결을 확인한 뒤 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('notificationRegistrationFailureNextAction')),
        ),
        isSemantics(
          label: '도움말, 휴대전화 알림 설정과 인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
          isLiveRegion: true,
        ),
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 즐겨찾기는 즐겨찾기한 역을 큰 목록으로 보여준다', (tester) async {
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

      // 카테고리 진입 없이 역이 인라인 행으로 바로 보인다(#1569).
      expect(find.text('즐겨찾기한 역'), findsNothing);
      expect(find.text('역'), findsOneWidget);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('일부 정보는 확인 중이에요'), findsNothing);
      // 목록 행의 상세·출발/도착 액션은 상세 화면(즐겨찾기 토글 포함)으로 옮겨졌다.
      expect(find.widgetWithText(OutlinedButton, '출발지로 설정'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '역 상세 보기'), findsNothing);
      expect(
        find.byKey(const Key('favoriteHomeStationRow-station-sangnoksu')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('즐겨찾기 역, 상록수역, 수도권 4호선'), findsOneWidget);
      expect(find.text('출처 공식 파일'), findsNothing);

      final tileSize = tester.getSize(
        find.byKey(const Key('favoriteHomeStationRow-station-sangnoksu')),
      );
      expect(tileSize.height, greaterThanOrEqualTo(44));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 즐겨찾기 시설은 즐겨찾기한 시설을 큰 목록으로 보여준다', (tester) async {
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

      // 시설도 카테고리 진입 없이 인라인 행으로 흡수됐다(#1569).
      expect(find.text('즐겨찾기한 시설'), findsNothing);
      expect(find.text('시설'), findsOneWidget);
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('정보 신뢰도 높음'), findsNothing);
      expect(find.text('출처 공식 파일'), findsNothing);
      expect(find.widgetWithText(TextButton, '시설 알려주기'), findsOneWidget);
      expect(
        find.byKey(
          const Key(
            'favoriteFacilityReportButton-facility-sangnoksu-elevator-1',
          ),
        ),
        findsOneWidget,
      );
      expectNoForbiddenUserCopy(tester);
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
    await tester.tap(find.widgetWithText(TextButton, '시설 알려주기'));
    await tester.pumpAndSettle();

    // 진입 시에는 위치 권한 확인·요청을 하지 않는다.
    expect(locationProvider.permissionCheckCount, 0);
    expect(locationProvider.requestCount, 0);

    // 위치 첨부를 켤 때 권한 사용 안내(사용 목적)를 유지한다.
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();

    expect(locationProvider.permissionCheckCount, 1);
    expect(locationProvider.requestCount, 0);
    expect(find.text('현재 위치 사용'), findsOneWidget);
    expect(find.text('가까운 역 찾기와 시설 제보 위치 확인에만 현재 위치를 사용합니다.'), findsOneWidget);
  });

  testWidgets('홈 즐겨찾기 경로는 즐겨찾기한 경로를 큰 목록으로 보여주고 삭제한다', (tester) async {
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

      // 경로가 인라인 카드로 바로 보인다(#1569). 카테고리·하위 목록 화면 없음.
      expect(find.text('즐겨찾기한 경로'), findsNothing);
      expect(find.text('경로'), findsOneWidget);
      expect(find.text('상록수역 → 사당역'), findsOneWidget);
      expect(find.text('다시 찾으면 자세히 볼 수 있어요'), findsNothing);
      expect(
        find.byKey(const Key('favoriteRouteRemoveButton-route-1')),
        findsOneWidget,
      );

      // 행 탭 → 저장된 출발/도착·이동 조건으로 다시 길찾기.
      await tester.tap(find.text('상록수역 → 사당역'));
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

      // 오른쪽 삭제 아이콘 → 확인 다이얼로그 없이 바로 삭제하고 리스트를 갱신한다.
      await tester.tap(
        find.byKey(const Key('favoriteRouteRemoveButton-route-1')),
      );
      await tester.pumpAndSettle();

      expect(favoriteRouteRepository.removedFavoriteRouteIds, ['route-1']);
      expect(find.text('즐겨찾기한 항목이 없습니다'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
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

    await tester.tap(find.text('상록수역 → 사당역'));
    await tester.pumpAndSettle();

    expect(searchAgainDraft?.origin?.id, 'station-sangnoksu');
    expect(searchAgainDraft?.destination?.id, 'station-sadang');
    expect(searchAgainMobilityType, 'WHEELCHAIR');
  });

  testWidgets('역 검색은 검색 버튼 없이 타이핑(디바운스)만으로 결과를 보여준다', (tester) async {
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
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    // 버튼 탭·키보드 액션 없이 디바운스 시간만 지나면 검색된다.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(repository.requestedQueries, ['상록수']);
    expect(find.text('상록수역'), findsOneWidget);
    // 검색창 아래 검색 버튼·노선 필터·전체 노선 진입이 없다.
    expect(find.byKey(const Key('stationSearchSubmitButton')), findsNothing);
    expect(find.text('노선 필터 펼치기'), findsNothing);
    expect(find.text('전체 노선'), findsNothing);
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

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('지금은 상록수역·사당역 구간을 안내해요'),
        ),
        findsNothing,
      );
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
      await tester.pump();
      // 검색 버튼은 제거됐고, 입력이 있으면 주변 역 버튼도 감춘다.
      expect(find.byKey(const Key('stationSearchSubmitButton')), findsNothing);
      expect(find.byKey(const Key('nearbyStationSearchButton')), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(repository.requestedQueries, ['상록수']);
      expect(find.byKey(const Key('stationLineBadge-seoul-4')), findsOneWidget);
      expect(
        find.byKey(const Key('stationLineBadge-korail-gyeongui-jungang')),
        findsOneWidget,
      );
      expect(find.text('수도권 4호선, 경의중앙선'), findsOneWidget);
      expect(find.text('수도권'), findsNothing);
      // 기본 레벨(LEVEL_1) 품질 필러는 목록에서 감춘다(#1477). 시맨틱에는 유지.
      expect(find.text('일부 정보는 확인 중이에요'), findsNothing);
      expect(find.text('출처 확인 필요'), findsNothing);
      expect(find.bySemanticsLabel('검색 결과 1개'), findsOneWidget);
      expect(
        find.bySemanticsLabel('상록수역, 수도권 4호선, 경의중앙선, 수도권'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('상록수역, 수도권 4호선, 경의중앙선, 수도권')),
        isSemantics(
          label: '상록수역, 수도권 4호선, 경의중앙선, 수도권',
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

  testWidgets('역 검색 결과 핵심 문구는 시스템 글자 크기에서 한 줄 말줄임으로 고정하지 않는다', (tester) async {
    final longStationName = '김포공항국제선환승센터';
    final repository = FakeStationSearchRepository(
      queryResults: {
        '김포': [
          StationSearchResult(
            id: 'station-gimpo-airport',
            nameKo: longStationName,
            nameEn: 'gimpo-airport',
            region: '수도권',
            dataQualityLevel: 'LEVEL_1',
            dataSourceType: 'OFFICIAL_FILE',
            lastVerifiedAt: '2026-06-13',
            distanceMeters: 1280,
            lines: const [
              StationSearchLine(
                id: 'seoul-9',
                name: '수도권 9호선 급행',
                color: '#BDB092',
                stationCode: '902',
              ),
              StationSearchLine(
                id: 'airport-railroad',
                name: '공항철도 직통 일반 공용',
                color: '#006D9D',
                stationCode: 'A05',
              ),
            ],
          ),
        ],
      },
    );

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: EasySubwayApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '김포');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    for (final text in [
      '$longStationName역',
      '현재 위치에서 1.3km · 수도권 9호선 급행, 공항철도 직통 일반 공용',
    ]) {
      final widget = tester.widget<Text>(find.text(text));
      expect(widget.maxLines, isNot(1));
      expect(widget.overflow, isNot(TextOverflow.ellipsis));
    }
    // 품질 문구 "일부 정보는 확인 중이에요"는 별도 semantic label 테스트에서 유지한다.
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationRoleDestination-station-sadang')),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(SnackBarAction, '길찾기 보기'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, '길찾기 보기'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('길찾기')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
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
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('지금은 상록수역·사당역 구간을 안내해요'),
        ),
        findsNothing,
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
      // 폼 요약은 조건명만 남기고 중복 조건 요약 부제·협박형 캡션을 제거했다(#1568).
      expect(find.text('천천히 이동'), findsWidgets);
      expect(find.text('계단 피하기 · 환승 줄이기'), findsNothing);
      expect(find.text('계단 없는 길만'), findsOneWidget);
      expect(find.text('켜면 경로가 줄거나 없을 수 있어요.'), findsNothing);
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

  testWidgets('경로 검색 strict switch는 STRICT_STEP_FREE 요청을 보낸다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
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
            lastModifiedAt: DateTime(2026, 6, 30),
          ),
        ),
      ),
    );

    // #1933 C: 출발·도착이 이미 채워진 draft로 진입하면 자동 검색이 한 번 돈다.
    // 계단 토글을 켜고 다시 "길찾기"를 누르면 STRICT_STEP_FREE로 재검색한다.
    await tester.tap(find.byKey(const Key('routeStrictStepFreeSwitch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests.last.mobilityType, 'SENIOR');
    expect(
      routeRepository.requests.last.effectiveConstraintMode,
      'STRICT_STEP_FREE',
    );
  });

  testWidgets('#1933 C 출발·도착이 모두 채워진 draft는 버튼 없이 자동 검색으로 결과 타임라인을 연다', (
    tester,
  ) async {
    final routeRepository = FakeRouteSearchRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
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
            lastModifiedAt: DateTime(2026, 7, 10),
          ),
        ),
      ),
    );

    // "길찾기" 버튼을 누르지 않았는데도 자동 검색이 돌아 결과가 온다.
    await tester.pumpAndSettle();

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
    // 이동 조건 기본값(계단 없는 길 선호)이 자동 검색에도 그대로 승계된다.
    expect(
      routeRepository.requests.single.effectiveConstraintMode,
      'PREFER_STEP_FREE',
    );
    // 결과 목록(세로 타임라인, #1704)이 렌더된다.
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
  });

  testWidgets('경로 검색 최근 도착지 실패는 빈 화면으로 숨기지 않는다', (tester) async {
    final favoriteRouteRepository = FakeFavoriteRouteRepository(
      favorites: [_favoriteRoute()],
    )..error = Exception('network');

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(),
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: favoriteRouteRepository,
          initialMobilityType: 'SENIOR',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('최근 도착지를 불러오지 못했어요.'), findsOneWidget);
    expect(
      find.byKey(const Key('routeRecentDestinationRetryButton')),
      findsOneWidget,
    );

    favoriteRouteRepository.error = null;
    await tester.tap(
      find.byKey(const Key('routeRecentDestinationRetryButton')),
    );
    await tester.pumpAndSettle();

    expect(find.text('최근 도착지를 불러오지 못했어요.'), findsNothing);
    expect(find.text('최근 도착지'), findsOneWidget);
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

      await tester.tap(find.byKey(const Key('networkMapMenuButton')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('networkMapMenuStationSearchButton')),
      );
      await tester.pumpAndSettle();

      // 최근 검색은 역 검색 화면의 빈 상태 섹션으로 통합됐다(#1581).
      expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
      expect(
        find.byKey(const Key('stationRecentSearchSection')),
        findsOneWidget,
      );
      expect(find.text('최근 검색'), findsOneWidget);
      // 시스템 캡션('최근 사용 순서 …')은 제거됐다(#1581).
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

  testWidgets('역 검색 화면 안에서 최근 검색을 개별·전체 삭제한다', (tester) async {
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

    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('networkMapMenuStationSearchButton')),
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

    // 최근 검색이 비면 전용 빈 상태 대신 섹션이 사라지고 검색 입력만 남는다(#1581).
    expect(searchHistoryRepository.clearCount, 1);
    expect(find.byKey(const Key('stationRecentSearchSection')), findsNothing);
    expect(find.text('최근 검색한 역이 없습니다.'), findsNothing);
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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
      expect(find.text('현재 위치에서 230m · 수도권 2호선'), findsOneWidget);
      expect(find.byKey(const Key('nearbyStationPrimaryCard')), findsOneWidget);
      expect(
        find.bySemanticsLabel('가장 가까운 역, 상록수역, 현재 위치에서 230m, 수도권 2호선, 수도권'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('상록수역을 출발역으로 설정'), findsOneWidget);
      expect(find.bySemanticsLabel('상록수역을 도착역으로 설정'), findsOneWidget);

      final nearbyButtonSize = tester.getSize(
        find.byKey(const Key('nearbyStationSearchButton')),
      );
      expect(
        nearbyButtonSize.height,
        greaterThanOrEqualTo(EasySubwayTouchTarget.general),
      );

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

  testWidgets('역 검색은 사전 안내 다이얼로그 없이 바로 위치를 요청한다', (tester) async {
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

    // 사전 rationale 다이얼로그(제목·본문·계속/취소) 없이 곧바로 위치를 요청한다.
    expect(find.text('현재 위치 사용'), findsNothing);
    expect(find.text('계속'), findsNothing);
    expect(find.text('취소'), findsNothing);
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
    expect(find.text('현재 위치에서 230m · 수도권 2호선'), findsOneWidget);
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
      expect(find.text('현재 위치를 사용할 수 없어요.'), findsOneWidget);
      expect(find.bySemanticsLabel('현재 위치를 사용할 수 없어요.'), findsOneWidget);
      expect(
        find.text('역명으로 검색하면 현재 위치를 쓰지 않아도 계속 이용할 수 있습니다.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('도움말, 역명으로 검색하면 현재 위치를 쓰지 않아도 계속 이용할 수 있습니다.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationSearchOpenLocationSettingsButton')),
        findsNothing,
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(repository.requestedQueries, ['없는역']);
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);
    expect(find.text('역명으로 검색하면 현재 위치를 쓰지 않아도 계속 이용할 수 있습니다.'), findsNothing);
    expect(
      find.bySemanticsLabel('도움말, 역명으로 검색하면 현재 위치를 쓰지 않아도 계속 이용할 수 있습니다.'),
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
    debugStationVerifiedClock = () => DateTime(2026, 6, 15);
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
          id: 'facility-sangnoksu-operation-unknown',
          stationId: 'station-sangnoksu',
          exitId: 'exit-sangnoksu-3',
          type: 'ESCALATOR',
          name: '3번 출구 에스컬레이터',
          floorFrom: 'B1',
          floorTo: '1F',
          description: '3번 출구 앞',
          status: 'UNKNOWN',
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
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      // 기본 레벨(LEVEL_1) 품질 필러는 목록에서 감춘다(#1477). 시맨틱에는 유지.
      expect(find.text('일부 정보는 확인 중이에요'), findsNothing);
      expect(find.text('출처 공식 파일'), findsNothing);
      expect(find.bySemanticsLabel('상록수역, 수도권 2호선, 수도권'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      expect(repository.requestedDetailStationIds, ['station-sangnoksu']);
      expect(repository.requestedExitStationIds, ['station-sangnoksu']);
      expect(repository.requestedFacilityStationIds, ['station-sangnoksu']);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('수도권 2호선'), findsOneWidget);
      // 상세 헤더는 데이터 품질 문구를 노출하지 않는다(간결화, 시맨틱 라벨에는 유지).
      expect(find.text('일부 정보는 확인 중이에요'), findsNothing);
      // '마지막 확인'은 역명 우측에 라벨/상대시간 두 줄로 표시된다(#1567 후속).
      expect(find.text('마지막 확인'), findsOneWidget);
      expect(find.text('2일 전'), findsOneWidget);
      expect(find.text('출처 공식 파일'), findsNothing);
      // 상시 안전 안내는 제거됐다(#1497).
      expect(find.text('이동 전 현장 안내와 역무원 안내를 확인해 주세요.'), findsNothing);
      expect(
        find.bySemanticsLabel('상록수역 자세한 안내, 수도권 2호선, 마지막 확인 2일 전'),
        findsOneWidget,
      );
      // 역 안 이동 안내·순서는 "역 안 이동" 한 섹션으로 통합됐다(#1497).
      await tester.scrollUntilVisible(
        find.text('역 안 이동'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('역 안 이동'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('승강장'),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('승강장'), findsOneWidget);
      final platformText = tester.widget<Text>(find.text('승강장'));
      expect(platformText.maxLines, isNot(2));
      expect(platformText.overflow, isNot(TextOverflow.ellipsis));
      expect(
        find.bySemanticsLabel('역 안 이동 안내, 1번 출구, 엘리베이터, 승강장'),
        findsOneWidget,
      );
      // 중복 "지도 위치 목록" 섹션은 제거됐다(#1497).
      expect(find.text('지도 위치 목록'), findsNothing);
      expect(
        find.byKey(const Key('stationMapTextListItem-station-sangnoksu')),
        findsNothing,
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
        find.bySemanticsLabel('1번 출구, 엘리베이터 연결, 계단 없는 이동 가능'),
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
      // 시설 종류 필은 제거(이름에 포함). 문제 상태만 상태 필로 노출.
      expect(find.text('엘리베이터'), findsNothing);
      expect(find.text('이용할 수 없어요'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(
          const Key('stationFacilityCard-facility-sangnoksu-operation-unknown'),
        ),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('3번 출구 에스컬레이터'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const Key(
              'stationFacilityCard-facility-sangnoksu-operation-unknown',
            ),
          ),
          matching: find.text('설치 확인 · 운행상태 미확인'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(
            const Key(
              'stationFacilityCard-facility-sangnoksu-operation-unknown',
            ),
          ),
          matching: find.text('이용 가능'),
        ),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(
          '3번 출구 에스컬레이터, 에스컬레이터, 설치 확인 · 운행상태 미확인, 3번 출구 앞, 최근 확인 5일 전, 자세히 보기',
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
      // 정상 시설은 상태 필 없이 이름+위치+확인 시점만 조용히 표시.
      expect(find.text('이용 가능'), findsNothing);
      expect(find.text('1번 출구 앞'), findsOneWidget);
      expect(find.text('최근 확인 3일 전'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '1번 출구 엘리베이터, 엘리베이터, 이용 가능, 1번 출구 앞, 최근 확인 3일 전, 시설 알려주기',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('1번 출구 엘리베이터 시설 알려주기'), findsOneWidget);
      // #1567: 카드 전체 탭이 상세를 열므로 중복 '상세 보기' 텍스트는 없애고,
      // 보조 액션 '시설 알려주기'는 아웃라인 대신 텍스트 버튼 수준으로 낮춘다.
      expect(find.text('상세 보기'), findsNothing);
      expect(find.widgetWithText(TextButton, '시설 알려주기'), findsWidgets);

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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('지금은 상록수역·사당역 구간을 안내해요'),
      ),
      findsNothing,
    );
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

  testWidgets('역 상세 대화면은 정상은 조용히·문제 시설만 상태 필로 렌더링한다', (tester) async {
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
              largeTextEnabled: false,
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
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('stationDetailList')), findsOneWidget);
      expect(
        find.byKey(const Key('stationDetailLargeScreenLayout')),
        findsNothing,
      );
      // 정상 시설은 상태 필 없이 이름으로 조용히, 문제(고장·확인 중)만 상태 필로 렌더링.
      var sawNormalQuiet = false;
      var sawBroken = false;
      var sawNeedsCheck = false;
      for (var index = 0; index < 8; index += 1) {
        sawNormalQuiet |= find.text('1번 출구 엘리베이터').evaluate().isNotEmpty;
        sawBroken |= find.text('이용할 수 없어요').evaluate().isNotEmpty;
        sawNeedsCheck |= find.text('상태를 확인하고 있어요').evaluate().isNotEmpty;
        if (sawNormalQuiet && sawBroken && sawNeedsCheck) {
          break;
        }
        await tester.drag(
          find.byKey(const Key('stationDetailList')),
          const Offset(0, -260),
        );
        await tester.pumpAndSettle();
      }
      expect(sawNormalQuiet, isTrue);
      expect(sawBroken, isTrue);
      expect(sawNeedsCheck, isTrue);
      // 정상 시설의 '이용 가능' 상태 필은 노출하지 않는다.
      expect(find.text('이용 가능'), findsNothing);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('시설 상세는 실제 시설 데이터로 시설 알려주기 진입을 보여준다', (tester) async {
    debugStationVerifiedClock = () => DateTime(2026, 6, 15);
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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
    expect(find.text('이용할 수 없어요'), findsOneWidget);
    expect(find.text('고장·폐쇄 · 고장'), findsOneWidget);
    expect(find.text('현장 안내와 다르면 시설 알려주기로 알려 주세요.'), findsOneWidget);
    expect(find.text('연결 위치 B1 ↔ 1F'), findsOneWidget);
    expect(find.text('2번 출구 앞'), findsOneWidget);
    expect(find.text('최근 확인 어제'), findsOneWidget);
    expect(find.text('정보 신뢰도 높음'), findsNothing);
    expect(find.text('출처 공식 파일'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '안내 확인 방법 보기'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '안내 확인 방법 보기'));
    await tester.pumpAndSettle();
    expect(find.text('안내 확인 방법'), findsOneWidget);
    expect(find.text('최근 확인했어요'), findsNothing);
    expect(find.text('최근 확인된 정보예요'), findsNothing);
    expect(find.text('공식 안내'), findsOneWidget);
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

    expect(find.text('시설 알려주기'), findsOneWidget);
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();

      expect(find.text('시설'), findsOneWidget);
      expect(find.text('시설 안내를 준비 중이에요.'), findsOneWidget);
      expect(find.text('확인 필요 없음'), findsNothing);
      expect(find.bySemanticsLabel('다시 볼 시설 없음'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 상세는 좌표 있는 출구에만 카카오맵 버튼을 보여준다', (tester) async {
    debugStationVerifiedClock = () => DateTime(2026, 7, 9);
    final semanticsHandle = tester.ensureSemantics();
    final mapLauncher = _FakeKakaoMapLauncher();
    final stationRepository = FakeStationSearchRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
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
          lastVerifiedAt: '2026-06-19',
        ),
        StationExitInfo(
          id: 'exit-sangnoksu-2',
          stationId: 'station-sangnoksu',
          exitNumber: '2',
          name: '2번 출구',
          hasElevatorConnection: false,
          hasStairOnlyPath: true,
          dataConfidence: 'LOW',
          dataSourceType: 'OFFICIAL_FILE',
        ),
      ],
    );

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: StationDetailScreen(
            repository: stationRepository,
            reportRepository: FakeFacilityReportRepository(),
            stationId: 'station-sangnoksu',
            mapLauncher: mapLauncher,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('stationExitMapButton-exit-sangnoksu-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('stationExitMapButton-exit-sangnoksu-2')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel('1번 출구, 엘리베이터 연결, 계단 없는 이동 가능, 최근 확인 2주 전'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('stationExitMapButton-exit-sangnoksu-1')),
        500,
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('1번 출구 카카오맵에서 보기, 새 앱이 열립니다'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('카카오맵에서 보기'), findsNothing);

      await tester.tap(
        find.byKey(const Key('stationExitMapButton-exit-sangnoksu-1')),
      );
      await tester.pumpAndSettle();

      expect(mapLauncher.lookTargets, hasLength(1));
      expect(mapLauncher.lookTargets.single.label, '상록수역 1번 출구');
      expect(mapLauncher.lookTargets.single.latitude, 37.3021);
      expect(mapLauncher.lookTargets.single.longitude, 126.8661);
      expect(find.text('카카오맵을 열었습니다.'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 상세는 현재 위치 기준 출구 직선거리와 카카오맵 도보 길안내를 보여준다', (tester) async {
    final mapLauncher = _FakeKakaoMapLauncher();
    var locationRequestCount = 0;
    final locationProvider = FakeCurrentLocationProvider(
      locationLoader: () async {
        locationRequestCount++;
        return locationRequestCount == 1
            ? _freshCurrentLocation(latitude: 37.3028, longitude: 126.8665)
            : _freshCurrentLocation(latitude: 37.3032, longitude: 126.8671);
      },
      needsPermissionRequest: false,
    );
    final stationRepository = FakeStationSearchRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
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
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          stationId: 'station-sangnoksu',
          locationProvider: locationProvider,
          mapLauncher: mapLauncher,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('stationExitDistanceButton-exit-sangnoksu-1')),
      500,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationExitDistanceButton-exit-sangnoksu-1')),
    );
    await tester.pumpAndSettle();

    expect(locationProvider.requestCount, 1);
    expect(find.textContaining('현재 위치에서 직선'), findsOneWidget);
    expect(
      find.byKey(const Key('stationExitWalkingRouteButton-exit-sangnoksu-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('stationExitWalkingRouteButton-exit-sangnoksu-1')),
    );
    await tester.pumpAndSettle();

    expect(locationProvider.requestCount, 2);
    expect(mapLauncher.routeTargets, hasLength(1));
    expect(mapLauncher.routeTargets.single.start.latitude, 37.3032);
    expect(mapLauncher.routeTargets.single.start.longitude, 126.8671);
    expect(mapLauncher.routeTargets.single.end.label, '상록수역 1번 출구');
    expect(mapLauncher.routeTargets.single.end.latitude, 37.3021);
    expect(mapLauncher.routeTargets.single.end.longitude, 126.8661);
    expect(find.text('카카오맵 도보 길안내를 열었습니다.'), findsOneWidget);
  });

  testWidgets('역 상세는 출구 좌표가 없으면 역 좌표 기준으로 직선거리와 도보 길안내를 강등한다', (tester) async {
    final mapLauncher = _FakeKakaoMapLauncher(
      routeResult: KakaoMapLaunchResult.copied,
    );
    final locationProvider = FakeCurrentLocationProvider(
      location: _freshCurrentLocation(),
      needsPermissionRequest: false,
    );
    final stationRepository = FakeStationSearchRepository(
      stationDetail: _stationDetail(
        id: 'station-sangnoksu',
        name: '상록수',
        latitude: 37.3024,
        longitude: 126.8662,
      ),
      stationExits: const [
        StationExitInfo(
          id: 'exit-sangnoksu-2',
          stationId: 'station-sangnoksu',
          exitNumber: '2',
          name: '2번 출구',
          hasElevatorConnection: false,
          hasStairOnlyPath: true,
          dataConfidence: 'LOW',
          dataSourceType: 'OFFICIAL_FILE',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          stationId: 'station-sangnoksu',
          locationProvider: locationProvider,
          mapLauncher: mapLauncher,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('stationExitDistanceButton-exit-sangnoksu-2')),
      500,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationExitDistanceButton-exit-sangnoksu-2')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('현재 위치에서 역까지 직선'), findsOneWidget);
    expect(find.text('출구 좌표가 없어 역 위치 기준으로 안내합니다.'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('stationExitWalkingRouteButton-exit-sangnoksu-2')),
    );
    await tester.pumpAndSettle();

    expect(mapLauncher.routeTargets, hasLength(1));
    expect(mapLauncher.routeTargets.single.end.label, '상록수역');
    expect(mapLauncher.routeTargets.single.end.latitude, 37.3024);
    expect(mapLauncher.routeTargets.single.end.longitude, 126.8662);
    expect(find.text('역 좌표를 복사했습니다. 지도 앱에서 붙여넣어 주세요.'), findsOneWidget);
  });

  testWidgets('역 상세는 현재 위치 확인 실패 시 도보 길안내를 열지 않고 쉬운 문구로 안내한다', (tester) async {
    final mapLauncher = _FakeKakaoMapLauncher();
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException('현재 위치를 확인하지 못했어요.'),
      needsPermissionRequest: false,
    );
    final stationRepository = FakeStationSearchRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
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
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          stationId: 'station-sangnoksu',
          locationProvider: locationProvider,
          mapLauncher: mapLauncher,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('stationExitDistanceButton-exit-sangnoksu-1')),
      500,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationExitDistanceButton-exit-sangnoksu-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('현재 위치를 확인하지 못했어요.'), findsOneWidget);
    expect(
      find.byKey(const Key('stationExitWalkingRouteButton-exit-sangnoksu-1')),
      findsNothing,
    );
    expect(mapLauncher.routeTargets, isEmpty);
  });

  testWidgets('역 상세는 오래된 위치를 출구 안내용 문구로 막는다', (tester) async {
    final mapLauncher = _FakeKakaoMapLauncher();
    final locationProvider = FakeCurrentLocationProvider(
      location: CurrentLocation(
        latitude: 37.3028,
        longitude: 126.8665,
        accuracyMeters: 25,
        measuredAt: DateTime.now().subtract(const Duration(minutes: 20)),
        provider: 'gps',
        permissionPrecision: LocationPermissionPrecision.precise,
      ),
      needsPermissionRequest: false,
    );
    final stationRepository = FakeStationSearchRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
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
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          stationId: 'station-sangnoksu',
          locationProvider: locationProvider,
          mapLauncher: mapLauncher,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('stationExitDistanceButton-exit-sangnoksu-1')),
      500,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationExitDistanceButton-exit-sangnoksu-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('현재 위치가 오래되어 출구까지 안내하기 어려워요. 다시 확인해 주세요.'),
      findsOneWidget,
    );
    expect(find.textContaining('출발역을 직접 선택'), findsNothing);
    expect(
      find.byKey(const Key('stationExitWalkingRouteButton-exit-sangnoksu-1')),
      findsNothing,
    );
    expect(mapLauncher.routeTargets, isEmpty);
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
    expect(find.text('역 안 이동'), findsOneWidget);
    expect(find.text('역 안 이동 경로를 찾았어요'), findsOneWidget);
    expect(find.text('1번 출구 엘리베이터에서 개찰구까지'), findsWidgets);
    expect(find.text('약 1분 15초 · 28m'), findsOneWidget);
    expect(find.text('엘리베이터에서 개찰구까지 이동합니다.'), findsOneWidget);
    expect(find.text('약 1분 15초 · 28m · 엘리베이터를 이용해요'), findsOneWidget);
    expect(find.text('내부 이동 경로를 찾았습니다'), findsNothing);
    expect(find.text('현장 검증 전'), findsNothing);
    expect(find.text('엘리베이터 필요'), findsNothing);
    expect(
      find.bySemanticsLabel(
        '역 안 이동 순서, 역 안 이동 경로를 찾았어요, 1번 출구 엘리베이터에서 개찰구까지, 약 1분 15초 · 28m, 이동 단계 1번 역 안 이동, 1번 출구 엘리베이터에서 개찰구까지, 약 1분 15초 · 28m · 엘리베이터를 이용해요, 엘리베이터에서 개찰구까지 이동합니다.',
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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
    await tester.scrollUntilVisible(find.text('역 안 이동'), 500);
    await tester.pumpAndSettle();
    expect(find.text('역 안 이동'), findsOneWidget);
    expect(find.text('역 안 이동 경로를 찾았어요'), findsOneWidget);
    expect(find.text('내부 이동 경로를 찾았습니다'), findsNothing);
  });

  testWidgets('역 상세는 역 안 이동 정보가 없으면 관련 안내를 숨긴다', (tester) async {
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
    // 데이터가 없으면 사과 문구 대신 역 안 이동 안내를 통째로 숨긴다(#1577).
    expect(find.text('역 안 길 안내에 필요한 정보를 찾지 못했어요.'), findsNothing);
    expect(find.text('역 안 이동'), findsNothing);
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
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, '저장'), findsOneWidget);
      expect(find.bySemanticsLabel('상록수역 즐겨찾기 저장'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stationFavoriteToggleButton')));
      await tester.pumpAndSettle();

      expect(favoriteRepository.savedStationIds, ['station-sangnoksu']);
      expect(find.text('즐겨찾기에 저장했습니다.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '저장됨'), findsOneWidget);
      expect(find.bySemanticsLabel('상록수역 즐겨찾기 해제'), findsOneWidget);

      await tester.tap(find.byKey(const Key('stationFavoriteToggleButton')));
      await tester.pumpAndSettle();

      expect(favoriteRepository.removedStationIds, ['station-sangnoksu']);
      expect(find.text('즐겨찾기에서 해제했습니다.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '저장'), findsOneWidget);

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
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '저장됨'), findsOneWidget);
    expect(find.bySemanticsLabel('상록수역 즐겨찾기 해제'), findsOneWidget);
  });

  testWidgets('역 상세는 즐겨찾기 확인을 기다리지 않고 열린다', (tester) async {
    debugStationVerifiedClock = () => DateTime(2026, 6, 15);
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(
      find.bySemanticsLabel('상록수역 자세한 안내, 수도권 2호선, 마지막 확인 2일 전'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, '확인 중'), findsOneWidget);

    favoriteRepository.complete([
      _favoriteStation(id: 'station-sangnoksu', name: '상록수'),
    ]);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '저장됨'), findsOneWidget);
  });

  testWidgets('역 상세 실시간 확인 불가는 다시 시도로 도착 정보를 불러온다', (tester) async {
    final realtimeRepository = _RetryRealtimeRepository();
    final stationRepository = FakeStationSearchRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          stationId: 'station-sangnoksu',
          realtimeRepository: realtimeRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 첫 조회는 실패해 '실시간 정보 확인 불가'와 다시 시도 버튼을 보여준다.
    expect(find.text('실시간 정보 확인 불가'), findsOneWidget);
    final retryButton = find.byKey(const Key('stationRealtimeRetryButton'));
    expect(retryButton, findsOneWidget);
    expect(realtimeRepository.callCount, 1);

    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    // 재시도가 성공하면 도착 정보로 바뀌고 버튼은 사라진다.
    expect(realtimeRepository.callCount, 2);
    expect(find.text('도착 정보'), findsOneWidget);
    expect(find.text('실시간 정보 확인 불가'), findsNothing);
    expect(retryButton, findsNothing);
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
    // 역 행 → 상세 → 즐겨찾기 해제 → 복귀 시 리스트가 갱신돼 빈 상태가 된다(#1569).
    await tester.tap(
      find.byKey(const Key('favoriteHomeStationRow-station-sangnoksu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stationFavoriteToggleButton')));
    await tester.pumpAndSettle();

    expect(favoriteRepository.removedStationIds, ['station-sangnoksu']);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('즐겨찾기한 항목이 없습니다'), findsOneWidget);
    expect(
      find.byKey(const Key('favoriteHomeStationRow-station-sangnoksu')),
      findsNothing,
    );
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
      // 선택 상태는 카드 '선택됨' 시맨틱이 알리므로 문장형 헤더는 제거됐다(#1568).
      expect(find.text('휠체어 이용 조건을 선택했습니다'), findsNothing);
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
      expect(find.text('휠체어 이용 조건을 선택했습니다'), findsNothing);
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

    await _openRouteSearchScreen(tester);
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

      await _openRouteSearchScreen(tester);

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
        tester.getSemantics(find.bySemanticsLabel('출발역 선택, 상록수, 수도권 2호선, 수도권')),
        isSemantics(
          label: '출발역 선택, 상록수, 수도권 2호선, 수도권',
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
      // 결과 목록 끝에 광고 슬롯(#1496).
      expect(find.byKey(const Key('routeResultListAdBanner')), findsOneWidget);
      expect(find.text('추천 경로 목록'), findsNothing);
      expect(find.text('편한 순'), findsNothing);
      expect(find.text('빠른 순'), findsNothing);
      expect(find.text('환승 적은 순'), findsNothing);
      expect(find.text('상록수 → 사당'), findsNothing);
      // 폼 요약의 조건 요약 부제는 제거됐다(#1568). 조건명만 노출.
      expect(find.text('계단 피하기 · 환승 줄이기'), findsNothing);
      expect(find.text('천천히 이동'), findsWidgets);
      expect(find.text('계단 여부를 확인하고 있어요'), findsWidgets);
      expect(find.text('계단 없음'), findsNothing);
      expect(find.text('엘리베이터 이용'), findsNothing);
      expect(find.text('7분'), findsOneWidget);
      expect(find.text('환승 없이 이동 · 걷기 300m'), findsOneWidget);
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
      await _tapFirstRouteResultListItem(tester);
      await tester.pumpAndSettle();
      // 상세는 이제 별도 화면(SingleChildScrollView)으로 push된다.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 600),
      );
      await tester.pumpAndSettle();

      expect(find.text('경로 목록'), findsOneWidget);
      expect(find.text('추천 경로 1개'), findsNothing);
      expect(find.text('가장 추천'), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.text('이동 순서'), findsOneWidget);
      expect(find.text('도착 안내'), findsOneWidget);
      expect(find.text('도착역에서 계단 없는 출구 동선을 확인합니다.'), findsOneWidget);
      expect(find.textContaining('접근성 정보'), findsNothing);
      expect(find.byKey(const Key('routeStepNumber-1')), findsOneWidget);
      expect(find.text('열차 이동'), findsOneWidget);
      expect(find.text('선택한 길을 따라 안내합니다.'), findsOneWidget);
      expect(find.textContaining('edge:'), findsNothing);
      expect(find.textContaining('STATIC_ESTIMATE'), findsNothing);
      expect(find.textContaining('MEASURED'), findsNothing);
      expect(find.text('계단 없는 승강장 접근 동선을 확인해 이동합니다.'), findsOneWidget);
      expect(find.text('약 4분 · 180m · 엘리베이터 안내 준비 중'), findsOneWidget);
      // 여러 주의는 각주 한 줄로 합쳐 하나의 '주의 확인'만 노출한다(#1577).
      expect(find.text('주의 확인'), findsOneWidget);
      expect(
        find.text('일부 시설 안내를 준비 중이에요. · 시설 상태 안내가 오래됐을 수 있어요.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('routeDarkSummaryChip-계단 여부를 확인하고 있어요')),
          matching: find.byIcon(Icons.help_outline),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('routeDarkSummaryChip-계단 여부를 확인하고 있어요')),
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
      // 안내 진행 화면에는 광고 슬롯이 노출되지 않는다(#1496).
      expect(find.byKey(const Key('routeResultListAdBanner')), findsNothing);
      expect(find.byKey(const Key('routeDetailAdBanner')), findsNothing);
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

    await _tapFirstRouteResultListItem(tester);
    await tester.pumpAndSettle();
    expect(find.text('이동 순서'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    expect(find.text('이동 순서'), findsNothing);

    await _tapFirstRouteResultListItem(tester);
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

    await tester.tap(find.byKey(const Key('routeStartGuidanceButton')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('routeOpenInternalRouteButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeOpenInternalRouteButton')));
    await tester.pumpAndSettle();
    expect(find.text('역 안 이동 순서'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('전체 순서'), findsWidgets);
    expect(
      find.byKey(const Key('routeOpenInternalRouteButton')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('이동 순서'), findsOneWidget);
    expect(find.byKey(const Key('routeOpenFeedbackButton')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('routeOpenFeedbackButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeOpenFeedbackButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routeFeedbackHelpfulButton')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('이동 순서'), findsOneWidget);
    expect(find.byKey(const Key('routeOpenFeedbackButton')), findsOneWidget);
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
            largeTextEnabled: false,
            highContrastEnabled: false,
            simpleViewEnabled: false,
          ),
        ),
      ),
    );

    await _openRouteSearchScreen(tester);

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

    await _openRouteSearchScreen(tester);

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

    // 폼 요약은 조건명만 남기고 조건 요약 부제는 제거했다(#1568).
    expect(find.text('휠체어 이용'), findsOneWidget);
    expect(find.text('계단 피하기 · 엘리베이터 이동'), findsNothing);
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

      await _openRouteSearchScreen(tester);

      expect(find.bySemanticsLabel('현재 이동 조건 천천히 이동'), findsOneWidget);
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

    await _openRouteSearchScreen(tester);
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

  testWidgets('경로 검색 UNKNOWN 결과는 이동 가능 화면 문구로 보이지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(status: 'UNKNOWN'),
          ),
          stationRepository: FakeStationSearchRepository(),
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
            lastModifiedAt: DateTime(2026, 6, 26),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();
    await _openFirstRouteResultDetail(tester);

    expect(find.text('경로 상태를 확인하고 있어요'), findsWidgets);
    expect(find.text('확인 후 이동'), findsOneWidget);
    expect(find.text('추천 경로'), findsNothing);
    expect(find.textContaining('이동할 수 있는 경로'), findsNothing);
    expect(find.byKey(const Key('routeFavoriteSaveButton')), findsNothing);
    expect(find.byKey(const Key('routeStartGuidanceButton')), findsNothing);
  });

  testWidgets('즐겨찾기 경로 저장 실패는 도움말을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final favoriteRouteRepository = FakeFavoriteRouteRepository()
      ..error = const FavoriteRouteException('즐겨찾기 경로를 바꾸지 못했어요.');

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

      await _openRouteSearchScreen(tester);
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

      expect(find.text('즐겨찾기 경로를 바꾸지 못했어요.'), findsOneWidget);
      expect(
        find.text('네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('도움말, 네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('favoriteRouteSaveFailureNextAction')),
        ),
        isSemantics(
          label: '도움말, 네트워크 상태를 확인한 뒤 자주 쓰는 경로 저장을 다시 눌러 주세요.',
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

    await _openRouteSearchScreen(tester);
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

    await _openRouteSearchScreen(tester);
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

  testWidgets('로컬 경로 결과는 저장된 데이터 source를 실시간이나 시간표로 표시하지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(
              routeSearchId: 'local-station-sangnoksu-station-sadang',
              etaSource: 'STATIC_LOCAL',
              sourceUpdatedAt: '2026-06-19T00:00:00Z',
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

    expect(find.text('예상 소요시간: 저장된 데이터 기준 · 최근 확인 2026-06-19'), findsOneWidget);
    expect(find.textContaining('실시간'), findsNothing);
    expect(find.textContaining('시간표'), findsNothing);
  });

  test('하차 알림 refresh rollback은 사용자 action으로 현재 결과가 바뀌면 적용하지 않는다', () async {
    final repository = FakeRouteSearchRepository(
      result: _sampleGetOffAlarmRouteResult(),
    );
    final controller = RouteSearchController(repository: repository);
    addTearDown(controller.dispose);
    await controller.search(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'SENIOR',
      ),
    );
    final previousState = controller.state;
    repository.refreshResult = RouteRefreshResult(
      routeSearchId: 'route-1',
      status: 'UPDATED_ETA',
      result: _sampleGetOffAlarmRouteResult(
        realtimeArrivalTimeIso: '2026-07-06T09:40:00+09:00',
      ),
      refreshedAt: '2026-07-06T09:01:00+09:00',
      etaSource: 'REALTIME',
      etaConfidence: 'HIGH',
      sourceLabel: '실시간 도착 정보 기준',
    );
    final outcome = await controller.refreshCurrentRoute();
    controller.reset();

    final rolledBack = controller.rollbackRefreshAfterAlarmFailure(
      previousState: previousState,
      expectedCurrentResult: outcome.result!,
      refreshMessage: '하차 알림을 갱신하지 못해 이전 경로를 유지해요.',
    );

    expect(rolledBack, isFalse);
    expect(controller.state.status, RouteSearchViewStatus.idle);
    expect(controller.state.result, isNull);
  });

  testWidgets('planned 승차 시간이 있는 경로 결과는 하차 알림 토글을 보여준다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(
              steps: const [
                RouteSearchStep(
                  sequence: 1,
                  stepType: 'entry',
                  title: '상록수 승강장 접근',
                  description: '승강장까지 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sangnoksu',
                  toStationId: 'station-sangnoksu',
                  estimatedMinutes: 6,
                  distanceMeters: 180,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                ),
                RouteSearchStep(
                  sequence: 2,
                  stepType: 'ride',
                  title: '상록수에서 사당까지 이동',
                  description: '열차를 이용해 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sangnoksu',
                  toStationId: 'station-sadang',
                  estimatedMinutes: 32,
                  distanceMeters: 13500,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                  plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
                ),
              ],
              etaSource: 'STATIC_BACKEND_ESTIMATE',
            ),
          ),
          stationRepository: FakeStationSearchRepository(),
          getOffAlarmController: controller,
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
            lastModifiedAt: DateTime(2026, 7, 6),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.text('하차 알림'), findsOneWidget);
    expect(find.text('폰을 보지 않아도 내릴 때 알려드려요.'), findsOneWidget);

    await tester.ensureVisible(find.text('하차 알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('하차 알림'));
    await tester.pumpAndSettle();

    expect(notifier.scheduledAlarms.single.stationName, '사당');
    expect((await stateRepository.loadActive())?.destination.stationName, '사당');
  });

  testWidgets('여러 승차 구간 최초 하차 알림은 공식 환승역과 도착역 이름을 저장한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    final stationRepository = FakeStationSearchRepository(
      stationDetails: {
        'station-geumjeong': _stationDetail(
          id: 'station-geumjeong',
          name: '금정',
        ),
      },
    );
    final routeRepository = FakeRouteSearchRepository(
      result: _sampleRouteSearchResult(
        steps: const [
          RouteSearchStep(
            sequence: 1,
            stepType: 'ride',
            title: '상록수에서 금정까지 이동',
            description: '열차를 이용해 이동합니다.',
            lineId: 'seoul-4',
            lineName: '수도권 4호선',
            fromStationId: 'station-sangnoksu',
            toStationId: 'station-geumjeong',
            estimatedMinutes: 15,
            distanceMeters: 6300,
            includesStairs: false,
            requiresAccessibilityCheck: true,
            plannedArrivalTimeIso: '2026-07-06T09:20:00+09:00',
          ),
          RouteSearchStep(
            sequence: 2,
            stepType: 'ride',
            title: '금정에서 사당까지 이동',
            description: '열차를 이용해 이동합니다.',
            lineId: 'seoul-4',
            lineName: '수도권 4호선',
            fromStationId: 'station-geumjeong',
            toStationId: 'station-sadang',
            estimatedMinutes: 17,
            distanceMeters: 7200,
            includesStairs: false,
            requiresAccessibilityCheck: true,
            plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
          ),
        ],
      ),
    );

    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: routeRepository,
      controller: controller,
      stationRepository: stationRepository,
    );
    await tester.ensureVisible(find.text('하차 알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('하차 알림'));
    await tester.pumpAndSettle();

    expect(notifier.scheduledAlarms.map((alarm) => alarm.stationName), [
      '금정',
      '사당',
    ]);
    final active = await stateRepository.loadActive();
    expect(active?.transfers.map((stop) => stop.stationName), ['금정']);
    expect(active?.destination.stationName, '사당');
    expect(stationRepository.requestedDetailStationIds, ['station-geumjeong']);
  });

  testWidgets('ride 중 하나의 공식 도착이 없으면 부분 하차 알림을 보이지 않는다', (tester) async {
    final controller = GetOffAlarmController(
      notifier: _RecordingGetOffAlarmNotifier(),
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: _MemoryGetOffAlarmStateRepository(),
      now: () => DateTime(2026, 7, 6, 9),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(
              steps: const [
                RouteSearchStep(
                  sequence: 1,
                  stepType: 'ride',
                  title: '상록수에서 금정까지 이동',
                  description: '열차를 이용해 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sangnoksu',
                  toStationId: 'station-geumjeong',
                  estimatedMinutes: 15,
                  distanceMeters: 6300,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                  plannedArrivalTimeIso: '2026-07-06T09:20:00+09:00',
                ),
                RouteSearchStep(
                  sequence: 2,
                  stepType: 'ride',
                  title: '금정에서 사당까지 이동',
                  description: '열차를 이용해 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-geumjeong',
                  toStationId: 'station-sadang',
                  estimatedMinutes: 17,
                  distanceMeters: 7200,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                ),
              ],
            ),
          ),
          stationRepository: FakeStationSearchRepository(),
          getOffAlarmController: controller,
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
            lastModifiedAt: DateTime(2026, 7, 6),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(find.text('하차 알림'), findsNothing);
  });

  testWidgets('foreground 복귀는 활성 하차 알림을 현재 경로 시간으로 재예약한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final now = DateTime.parse('2026-07-06T09:00:00+09:00');
    final transferArrivalAt = DateTime.parse('2026-07-06T09:20:00+09:00');
    final arrivalAt = DateTime.parse('2026-07-06T09:37:30+09:00');
    final fireAt = DateTime.parse('2026-07-06T09:38:00+09:00');
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => now,
    );
    addTearDown(controller.dispose);
    final repository = FakeRouteSearchRepository(
      result: _sampleRouteSearchResult(
        steps: const [
          RouteSearchStep(
            sequence: 1,
            stepType: 'ride',
            title: '상록수에서 금정까지 이동',
            description: '열차를 이용해 이동합니다.',
            lineId: 'seoul-4',
            lineName: '수도권 4호선',
            fromStationId: 'station-sangnoksu',
            toStationId: 'station-geumjeong',
            estimatedMinutes: 15,
            distanceMeters: 6300,
            includesStairs: false,
            requiresAccessibilityCheck: true,
            plannedArrivalTimeIso: '2026-07-06T09:20:00+09:00',
          ),
          RouteSearchStep(
            sequence: 2,
            stepType: 'ride',
            title: '금정에서 사당까지 이동',
            description: '열차를 이용해 이동합니다.',
            lineId: 'seoul-4',
            lineName: '수도권 4호선',
            fromStationId: 'station-geumjeong',
            toStationId: 'station-sadang',
            estimatedMinutes: 17,
            distanceMeters: 7200,
            includesStairs: false,
            requiresAccessibilityCheck: true,
            plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
          ),
        ],
        etaSource: 'STATIC_BACKEND_ESTIMATE',
      ),
    );
    repository.refreshResult = RouteRefreshResult(
      routeSearchId: 'route-1',
      status: 'UNCHANGED',
      result: _sampleRouteSearchResult(
        steps: const [
          RouteSearchStep(
            sequence: 1,
            stepType: 'ride',
            title: '수도권 4호선으로 금정역까지 이동',
            description: '열차를 이용해 이동합니다.',
            lineId: 'seoul-4',
            lineName: '수도권 4호선',
            fromStationId: 'station-sangnoksu',
            toStationId: 'station-geumjeong',
            estimatedMinutes: 15,
            distanceMeters: 6300,
            includesStairs: false,
            requiresAccessibilityCheck: true,
            plannedArrivalTimeIso: '2026-07-06T09:20:00+09:00',
          ),
          RouteSearchStep(
            sequence: 2,
            stepType: 'ride',
            title: '수도권 4호선으로 사당역까지 이동',
            description: '열차를 이용해 이동합니다.',
            lineId: 'seoul-4',
            lineName: '수도권 4호선',
            fromStationId: 'station-geumjeong',
            toStationId: 'station-sadang',
            estimatedMinutes: 17,
            distanceMeters: 7200,
            includesStairs: false,
            requiresAccessibilityCheck: true,
            realtimeArrivalTimeIso: '2026-07-06T09:40:00+09:00',
          ),
        ],
        etaSource: 'STATIC_BACKEND_ESTIMATE',
      ),
      refreshedAt: '2026-07-06T09:01:00+09:00',
      etaSource: 'STATIC_BACKEND_ESTIMATE',
      etaConfidence: 'LOW',
      sourceLabel: '상수 추정 기준',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: repository,
          stationRepository: FakeStationSearchRepository(),
          getOffAlarmController: controller,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 6),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();
    await controller.enable(
      routeId: 'route-1',
      stops: [
        GetOffAlarmStop(
          stationId: 'station-geumjeong',
          stationName: '금정',
          arrivalAt: transferArrivalAt,
          kind: GetOffAlarmKind.transfer,
        ),
        GetOffAlarmStop(
          stationId: 'station-sadang',
          stationName: '사당',
          arrivalAt: arrivalAt,
          kind: GetOffAlarmKind.destination,
        ),
      ],
      transferAlarmEnabled: false,
    );
    notifier.reset();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(repository.refreshRouteSearchIds, ['route-1']);
    expect(notifier.scheduleCalls, 1);
    expect(notifier.scheduledMode, GetOffAlarmScheduleMode.exact);
    expect(notifier.scheduledAlarms.single.stationId, 'station-sadang');
    expect(notifier.scheduledAlarms.single.stationName, '사당');
    expect(
      notifier.scheduledAlarms.single.fireAt.isAtSameMomentAs(fireAt),
      isTrue,
    );
    expect((await stateRepository.loadActive())?.transferAlarmEnabled, isFalse);
    expect((await stateRepository.loadActive())?.destination.stationName, '사당');
  });

  testWidgets('새 환승역이 생긴 foreground refresh는 공식 역명으로 알림과 구독을 갱신한다', (
    tester,
  ) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    final stationRepository = FakeStationSearchRepository(
      stationDetails: {
        'station-geumjeong': _stationDetail(
          id: 'station-geumjeong',
          name: '금정',
        ),
      },
    );
    final routeRepository =
        FakeRouteSearchRepository(result: _sampleGetOffAlarmRouteResult())
          ..refreshResult = RouteRefreshResult(
            routeSearchId: 'route-1',
            status: 'UPDATED_ROUTE',
            result: _sampleRouteSearchResult(
              steps: const [
                RouteSearchStep(
                  sequence: 1,
                  stepType: 'ride',
                  title: '상록수에서 금정까지 이동',
                  description: '열차를 이용해 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sangnoksu',
                  toStationId: 'station-geumjeong',
                  estimatedMinutes: 15,
                  distanceMeters: 6300,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                  plannedArrivalTimeIso: '2026-07-06T09:20:00+09:00',
                ),
                RouteSearchStep(
                  sequence: 2,
                  stepType: 'ride',
                  title: '금정에서 사당까지 이동',
                  description: '열차를 이용해 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-geumjeong',
                  toStationId: 'station-sadang',
                  estimatedMinutes: 17,
                  distanceMeters: 7200,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                  plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
                  realtimeArrivalTimeIso: '2026-07-06T09:40:00+09:00',
                ),
              ],
            ),
            refreshedAt: '2026-07-06T09:01:00+09:00',
            etaSource: 'REALTIME',
            etaConfidence: 'HIGH',
            sourceLabel: '실시간 도착 정보 기준',
          );

    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: routeRepository,
      controller: controller,
      stationRepository: stationRepository,
    );
    await controller.enable(
      routeId: 'route-1',
      stops: [
        GetOffAlarmStop(
          stationId: 'station-sadang',
          stationName: '사당',
          arrivalAt: DateTime.parse('2026-07-06T09:37:30+09:00'),
          kind: GetOffAlarmKind.destination,
        ),
      ],
      transferAlarmEnabled: true,
    );
    notifier.reset();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(notifier.scheduledAlarms.map((alarm) => alarm.stationName), [
      '금정',
      '사당',
    ]);
    final active = await stateRepository.loadActive();
    expect(active?.transfers.map((stop) => stop.stationName), ['금정']);
    expect(active?.destination.stationName, '사당');
    expect(stationRepository.requestedDetailStationIds, ['station-geumjeong']);
  });

  testWidgets('pull-to-refresh는 활성 하차 알림을 새 ETA로 재예약한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    final repository =
        FakeRouteSearchRepository(result: _sampleGetOffAlarmRouteResult())
          ..refreshResult = RouteRefreshResult(
            routeSearchId: 'route-1',
            status: 'UPDATED_ETA',
            result: _sampleGetOffAlarmRouteResult(
              realtimeArrivalTimeIso: '2026-07-06T09:40:00+09:00',
            ),
            refreshedAt: '2026-07-06T09:01:00+09:00',
            etaSource: 'REALTIME',
            etaConfidence: 'HIGH',
            sourceLabel: '실시간 도착 정보 기준',
          );
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: repository,
      controller: controller,
    );
    await _enableSampleGetOffAlarm(controller);
    notifier.reset();

    await tester.drag(find.byType(ListView).first, const Offset(0, 500));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(repository.refreshRouteSearchIds, ['route-1']);
    expect(notifier.scheduleCalls, 1);
    expect(
      notifier.scheduledAlarms.single.arrivalAt.isAtSameMomentAs(
        DateTime.parse('2026-07-06T09:40:00+09:00'),
      ),
      isTrue,
    );
    expect(
      notifier.scheduledAlarms.single.fireAt.isAtSameMomentAs(
        DateTime.parse('2026-07-06T09:38:00+09:00'),
      ),
      isTrue,
    );
  });

  testWidgets('새 경로 검색은 활성 하차 알림을 취소한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: _MemoryGetOffAlarmStateRepository(),
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(
              steps: const [
                RouteSearchStep(
                  sequence: 1,
                  stepType: 'ride',
                  title: '상록수에서 사당까지 이동',
                  description: '열차를 이용해 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sangnoksu',
                  toStationId: 'station-sadang',
                  estimatedMinutes: 32,
                  distanceMeters: 13500,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                  plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
                ),
              ],
            ),
          ),
          stationRepository: FakeStationSearchRepository(),
          getOffAlarmController: controller,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 6),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();
    await controller.enable(
      routeId: 'route-1',
      stops: [
        GetOffAlarmStop(
          stationId: 'station-sadang',
          stationName: '사당',
          arrivalAt: DateTime.parse('2026-07-06T09:37:30+09:00'),
          kind: GetOffAlarmKind.destination,
        ),
      ],
      transferAlarmEnabled: false,
    );
    notifier.reset();

    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();

    expect(notifier.cancelCalls, 1);
    expect(controller.state.enabled, isFalse);
  });

  testWidgets('경로 reset은 활성 하차 알림을 취소한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: _MemoryGetOffAlarmStateRepository(),
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(),
          stationRepository: FakeStationSearchRepository(),
          getOffAlarmController: controller,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 6),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();
    await controller.enable(
      routeId: 'route-1',
      stops: [
        GetOffAlarmStop(
          stationId: 'station-sadang',
          stationName: '사당',
          arrivalAt: DateTime.parse('2026-07-06T09:37:30+09:00'),
          kind: GetOffAlarmKind.destination,
        ),
      ],
      transferAlarmEnabled: false,
    );
    notifier.reset();

    await tester.tap(find.byKey(const Key('routeSwapStationsButton')));
    await tester.pumpAndSettle();

    expect(notifier.cancelCalls, 1);
    expect(controller.state.enabled, isFalse);
  });

  testWidgets('일반 보기 이동 조건 변경은 활성 하차 알림과 이전 경로 결과를 정리한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: _MemoryGetOffAlarmStateRepository(),
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: FakeRouteSearchRepository(
        result: _sampleGetOffAlarmRouteResult(),
      ),
      controller: controller,
      simpleViewEnabled: false,
    );
    await _enableSampleGetOffAlarm(controller);
    notifier.reset();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('휠체어 이용').last);
    await tester.pumpAndSettle();

    expect(notifier.cancelCalls, 1);
    expect(controller.state.enabled, isFalse);
    expect(find.byKey(const Key('routeResultListItem')), findsNothing);
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      'WHEELCHAIR',
    );
  });

  testWidgets('계단 없는 길 조건 변경은 활성 하차 알림과 이전 경로 결과를 정리한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: _MemoryGetOffAlarmStateRepository(),
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: FakeRouteSearchRepository(
        result: _sampleGetOffAlarmRouteResult(),
      ),
      controller: controller,
    );
    await _enableSampleGetOffAlarm(controller);
    notifier.reset();

    await tester.ensureVisible(
      find.byKey(const Key('routeStrictStepFreeSwitch')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeStrictStepFreeSwitch')));
    await tester.pumpAndSettle();

    expect(notifier.cancelCalls, 1);
    expect(controller.state.enabled, isFalse);
    expect(find.byKey(const Key('routeResultListItem')), findsNothing);
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('routeStrictStepFreeSwitch')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('일반 보기 이동 조건 변경은 하차 알림 취소 실패 시 기존 조건과 경로를 유지한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: _MemoryGetOffAlarmStateRepository(),
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: FakeRouteSearchRepository(
        result: _sampleGetOffAlarmRouteResult(),
      ),
      controller: controller,
      simpleViewEnabled: false,
    );
    await _enableSampleGetOffAlarm(controller);
    notifier.reset();
    final cancelError = StateError('cancel failed');
    notifier.cancelError = cancelError;
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reports.add, () async {
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('휠체어 이용').last);
      await tester.pumpAndSettle();
    });

    expect(reports.single.exception, same(cancelError));
    expect(find.text('하차 알림을 취소하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(controller.state.enabled, isTrue);
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      'SENIOR',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('단순 보기에서 현재 이동 조건을 다시 적용하면 활성 알림과 경로를 유지한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: _MemoryGetOffAlarmStateRepository(),
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: FakeRouteSearchRepository(
        result: _sampleGetOffAlarmRouteResult(),
      ),
      controller: controller,
    );
    await _enableSampleGetOffAlarm(controller);
    notifier.reset();

    await tester.tap(find.byKey(const Key('routeSimpleMobilityTypeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeMobilityApplyButton')));
    await tester.pumpAndSettle();

    expect(notifier.cancelCalls, 0);
    expect(controller.state.enabled, isTrue);
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
  });

  testWidgets(
    'pending enable 중 shell route exit는 disable 완료 뒤 경로와 하차 알림을 끝낸다',
    (tester) async {
      final notifier = _RecordingGetOffAlarmNotifier();
      final stateRepository = _MemoryGetOffAlarmStateRepository();
      final permissionProvider = _BlockingNotificationPermissionProvider();
      final controller = GetOffAlarmController(
        notifier: notifier,
        permissionGate: _StubExactAlarmPermissionGate(),
        notificationPermissionProvider: permissionProvider,
        repository: stateRepository,
        now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
      );
      addTearDown(controller.dispose);
      var exitCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: FakeRouteSearchRepository(
              result: _sampleRouteSearchResult(
                steps: const [
                  RouteSearchStep(
                    sequence: 1,
                    stepType: 'ride',
                    title: '상록수에서 사당까지 이동',
                    description: '열차를 이용해 이동합니다.',
                    lineId: 'seoul-4',
                    lineName: '수도권 4호선',
                    fromStationId: 'station-sangnoksu',
                    toStationId: 'station-sadang',
                    estimatedMinutes: 32,
                    distanceMeters: 13500,
                    includesStairs: false,
                    requiresAccessibilityCheck: true,
                    plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
                  ),
                ],
              ),
            ),
            stationRepository: FakeStationSearchRepository(),
            getOffAlarmController: controller,
            onShellBackToHome: () => exitCount += 1,
            initialDraft: RouteDraft(
              origin: const RouteDraftStation(
                id: 'station-sangnoksu',
                nameKo: '상록수',
              ),
              destination: const RouteDraftStation(
                id: 'station-sadang',
                nameKo: '사당',
              ),
              lastModifiedAt: DateTime(2026, 7, 6),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('하차 알림'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('하차 알림'));
      await tester.pump();
      await permissionProvider.started.future;

      expect(controller.state.enabled, isFalse);
      expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(exitCount, 0);
      expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);

      permissionProvider.result.complete(NotificationPermissionStatus.granted);
      await tester.pumpAndSettle();

      expect(permissionProvider.requestCount, 1);
      expect(notifier.cancelCalls, greaterThanOrEqualTo(1));
      expect(controller.state.enabled, isFalse);
      expect(await stateRepository.loadActive(), isNull);
      expect(exitCount, 1);
      expect(find.byKey(const Key('routeResultListItem')), findsNothing);
    },
  );

  testWidgets('shell route exit는 하차 알림 취소 실패를 보고하고 현재 화면을 유지한다', (
    tester,
  ) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    await controller.enable(
      routeId: 'route-1',
      stops: [
        GetOffAlarmStop(
          stationId: 'station-sadang',
          stationName: '사당',
          arrivalAt: DateTime.parse('2026-07-06T09:37:30+09:00'),
          kind: GetOffAlarmKind.destination,
        ),
      ],
      transferAlarmEnabled: false,
    );
    notifier.reset();
    final cancelError = StateError('cancel failed');
    notifier.cancelError = cancelError;
    final reports = <FlutterErrorDetails>[];
    var exitCount = 0;

    await runWithMobileErrorReporter(reports.add, () async {
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: FakeRouteSearchRepository(),
            stationRepository: FakeStationSearchRepository(),
            getOffAlarmController: controller,
            onShellBackToHome: () => exitCount += 1,
            initialDraft: RouteDraft(
              origin: const RouteDraftStation(
                id: 'station-sangnoksu',
                nameKo: '상록수',
              ),
              destination: const RouteDraftStation(
                id: 'station-sadang',
                nameKo: '사당',
              ),
              lastModifiedAt: DateTime(2026, 7, 6),
            ),
          ),
        ),
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    });

    expect(reports.single.exception, same(cancelError));
    expect(reports.single.context.toString(), '하차 알림 취소 중 예외가 발생했습니다.');
    expect(find.text('하차 알림을 취소하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(exitCount, 0);
    expect(find.byKey(const Key('routeSearchScreen')), findsOneWidget);
    expect(controller.state.enabled, isTrue);
    expect(await stateRepository.loadActive(), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'offline foreground refresh는 stale realtime 대신 PLANNED 하차 알림을 사용한다',
    (tester) async {
      final previousDebugPrint = debugPrint;
      final logs = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message != null) {
          logs.add(message);
        }
      };
      addTearDown(() => debugPrint = previousDebugPrint);

      final notifier = _RecordingGetOffAlarmNotifier();
      final stateRepository = _MemoryGetOffAlarmStateRepository();
      final controller = GetOffAlarmController(
        notifier: notifier,
        permissionGate: _StubExactAlarmPermissionGate(),
        notificationPermissionProvider: FakeNotificationPermissionProvider(
          nextStatus: NotificationPermissionStatus.granted,
        ),
        repository: stateRepository,
        now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
      );
      addTearDown(controller.dispose);
      final repository = FakeRouteSearchRepository(
        result: _sampleRouteSearchResult(
          steps: const [
            RouteSearchStep(
              sequence: 1,
              stepType: 'ride',
              title: '상록수에서 사당까지 이동',
              description: '열차를 이용해 이동합니다.',
              lineId: 'seoul-4',
              lineName: '수도권 4호선',
              fromStationId: 'station-sangnoksu',
              toStationId: 'station-sadang',
              estimatedMinutes: 32,
              distanceMeters: 13500,
              includesStairs: false,
              requiresAccessibilityCheck: true,
              plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
              realtimeArrivalTimeIso: '2026-07-06T09:40:00+09:00',
            ),
          ],
        ),
      )..refreshError = const RouteSearchException('offline');

      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: repository,
            stationRepository: FakeStationSearchRepository(),
            getOffAlarmController: controller,
            initialDraft: RouteDraft(
              origin: const RouteDraftStation(
                id: 'station-sangnoksu',
                nameKo: '상록수',
              ),
              destination: const RouteDraftStation(
                id: 'station-sadang',
                nameKo: '사당',
              ),
              lastModifiedAt: DateTime(2026, 7, 6),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
      await tester.pumpAndSettle();
      await controller.enable(
        routeId: 'route-1',
        stops: [
          GetOffAlarmStop(
            stationId: 'station-sadang',
            stationName: '사당',
            arrivalAt: DateTime.parse('2026-07-06T09:40:00+09:00'),
            kind: GetOffAlarmKind.destination,
          ),
        ],
        transferAlarmEnabled: false,
      );
      notifier.reset();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      debugPrint = previousDebugPrint;

      expect(repository.refreshRouteSearchIds, ['route-1']);
      expect(notifier.scheduleCalls, 1);
      expect(
        notifier.scheduledAlarms.single.arrivalAt.isAtSameMomentAs(
          DateTime.parse('2026-07-06T09:37:30+09:00'),
        ),
        isTrue,
      );
      expect(
        logs.singleWhere(
          (log) => log.startsWith('get_off_alarm foreground_refresh'),
        ),
        'get_off_alarm foreground_refresh changed=true '
        'delta_seconds=-150 source=planned mode=exact scheduled_count=1',
      );
    },
  );

  testWidgets('성공한 foreground refresh에 usable ride가 없으면 활성 하차 알림을 취소한다', (
    tester,
  ) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    final repository =
        FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(
              steps: const [
                RouteSearchStep(
                  sequence: 1,
                  stepType: 'ride',
                  title: '상록수에서 사당까지 이동',
                  description: '열차를 이용해 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sangnoksu',
                  toStationId: 'station-sadang',
                  estimatedMinutes: 32,
                  distanceMeters: 13500,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                  plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
                ),
              ],
            ),
          )
          ..refreshResult = RouteRefreshResult(
            routeSearchId: 'route-1',
            status: 'UPDATED_ROUTE',
            result: _sampleRouteSearchResult(steps: const []),
            refreshedAt: '2026-07-06T09:01:00+09:00',
            etaSource: 'PLANNED',
            etaConfidence: 'MEDIUM',
            sourceLabel: '계획 시간 기준',
          );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: repository,
          stationRepository: FakeStationSearchRepository(),
          getOffAlarmController: controller,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 6),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();
    await controller.enable(
      routeId: 'route-1',
      stops: [
        GetOffAlarmStop(
          stationId: 'station-sadang',
          stationName: '사당',
          arrivalAt: DateTime.parse('2026-07-06T09:37:30+09:00'),
          kind: GetOffAlarmKind.destination,
        ),
      ],
      transferAlarmEnabled: false,
    );
    notifier.reset();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(repository.refreshRouteSearchIds, ['route-1']);
    expect(notifier.cancelCalls, 1);
    expect(controller.state.enabled, isFalse);
    expect(await stateRepository.loadActive(), isNull);
  });

  testWidgets('usable ride 없는 refresh의 알림 취소 실패는 이전 경로와 구독을 복원한다', (
    tester,
  ) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    final routeRepository =
        FakeRouteSearchRepository(result: _sampleGetOffAlarmRouteResult())
          ..refreshResult = RouteRefreshResult(
            routeSearchId: 'route-1',
            status: 'UPDATED_ROUTE',
            result: _sampleRouteSearchResult(steps: const []),
            refreshedAt: '2026-07-06T09:01:00+09:00',
            etaSource: 'PLANNED',
            etaConfidence: 'MEDIUM',
            sourceLabel: '계획 시간 기준',
          );
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: routeRepository,
      controller: controller,
    );
    await _enableSampleGetOffAlarm(controller);
    final cancelCallsBeforeRefresh = notifier.cancelCalls;
    final cancelError = StateError('cancel failed');
    notifier.cancelError = cancelError;
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reports.add, () async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });

    expect(reports.single.exception, same(cancelError));
    expect(find.text('하차 알림을 갱신하지 못해 이전 경로를 유지해요.'), findsOneWidget);
    expect(find.text('도착·환승 전에 알려드려요.'), findsOneWidget);
    expect(controller.state.enabled, isTrue);
    expect((await stateRepository.loadActive())?.destination.stationName, '사당');
    expect(notifier.cancelCalls, cancelCallsBeforeRefresh + 1);
    expect(notifier.scheduleCalls, 1);
    expect(notifier.scheduledAlarms.single.stationName, '사당');
  });

  testWidgets('foreground 알림 재예약 실패는 이전 경로와 pending 구독을 복원한다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    final routeRepository =
        FakeRouteSearchRepository(result: _sampleGetOffAlarmRouteResult())
          ..refreshResult = RouteRefreshResult(
            routeSearchId: 'route-1',
            status: 'UPDATED_ETA',
            result: _sampleGetOffAlarmRouteResult(
              realtimeArrivalTimeIso: '2026-07-06T09:40:00+09:00',
            ),
            refreshedAt: '2026-07-06T09:01:00+09:00',
            etaSource: 'REALTIME',
            etaConfidence: 'HIGH',
            sourceLabel: '실시간 도착 정보 기준',
          );
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: routeRepository,
      controller: controller,
    );
    await _enableSampleGetOffAlarm(controller);
    final scheduleError = StateError('station-sadang schedule failed');
    notifier.scheduleError = scheduleError;
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reports.add, () async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });

    expect(reports, hasLength(1));
    expect(reports.single.exception, same(scheduleError));
    expect(
      reports.single.context.toString(),
      '하차 알림 foreground 재예약 중 예외가 발생했습니다.',
    );
    expect(find.text('하차 알림을 새로 맞추지 못했어요. 이전 경로를 유지해요.'), findsOneWidget);
    expect(find.text('하차 알림을 갱신하지 못해 이전 경로를 유지해요.'), findsOneWidget);
    expect(find.text('도착·환승 전에 알려드려요.'), findsOneWidget);
    expect(controller.state.enabled, isTrue);
    final active = await stateRepository.loadActive();
    expect(active?.destination.stationName, '사당');
    expect(
      active?.destination.arrivalAt.isAtSameMomentAs(
        DateTime.parse('2026-07-06T09:37:30+09:00'),
      ),
      isTrue,
    );
    expect(notifier.scheduleCalls, 2);
    expect(notifier.scheduledAlarms.single.stationName, '사당');
    expect(
      notifier.scheduledAlarms.single.arrivalAt.isAtSameMomentAs(
        DateTime.parse('2026-07-06T09:37:30+09:00'),
      ),
      isTrue,
    );
  });

  testWidgets('중복 foreground 하차 알림 refresh는 진행 중 예약을 건너뛴다', (tester) async {
    final notifier = _RecordingGetOffAlarmNotifier();
    final stateRepository = _MemoryGetOffAlarmStateRepository();
    final controller = GetOffAlarmController(
      notifier: notifier,
      permissionGate: _StubExactAlarmPermissionGate(),
      notificationPermissionProvider: FakeNotificationPermissionProvider(
        nextStatus: NotificationPermissionStatus.granted,
      ),
      repository: stateRepository,
      now: () => DateTime.parse('2026-07-06T09:00:00+09:00'),
    );
    addTearDown(controller.dispose);
    final pendingRefresh = Completer<RouteRefreshResult>();
    final repository = FakeRouteSearchRepository(
      result: _sampleRouteSearchResult(
        steps: const [
          RouteSearchStep(
            sequence: 1,
            stepType: 'ride',
            title: '상록수에서 사당까지 이동',
            description: '열차를 이용해 이동합니다.',
            lineId: 'seoul-4',
            lineName: '수도권 4호선',
            fromStationId: 'station-sangnoksu',
            toStationId: 'station-sadang',
            estimatedMinutes: 32,
            distanceMeters: 13500,
            includesStairs: false,
            requiresAccessibilityCheck: true,
            plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
            realtimeArrivalTimeIso: '2026-07-06T09:39:00+09:00',
          ),
        ],
      ),
    )..pendingRefresh = pendingRefresh;

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: repository,
          stationRepository: FakeStationSearchRepository(),
          getOffAlarmController: controller,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 6),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
    await tester.pumpAndSettle();
    await controller.enable(
      routeId: 'route-1',
      stops: [
        GetOffAlarmStop(
          stationId: 'station-sadang',
          stationName: '사당',
          arrivalAt: DateTime.parse('2026-07-06T09:39:00+09:00'),
          kind: GetOffAlarmKind.destination,
        ),
      ],
      transferAlarmEnabled: false,
    );
    notifier.reset();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(repository.refreshRouteSearchIds, ['route-1']);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(notifier.scheduleCalls, 0);

    pendingRefresh.complete(
      RouteRefreshResult(
        routeSearchId: 'route-1',
        status: 'UPDATED_ETA',
        result: _sampleRouteSearchResult(
          steps: const [
            RouteSearchStep(
              sequence: 1,
              stepType: 'ride',
              title: '상록수에서 사당까지 이동',
              description: '열차를 이용해 이동합니다.',
              lineId: 'seoul-4',
              lineName: '수도권 4호선',
              fromStationId: 'station-sangnoksu',
              toStationId: 'station-sadang',
              estimatedMinutes: 32,
              distanceMeters: 13500,
              includesStairs: false,
              requiresAccessibilityCheck: true,
              plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
              realtimeArrivalTimeIso: '2026-07-06T09:40:00+09:00',
            ),
          ],
        ),
        refreshedAt: '2026-07-06T09:01:00+09:00',
        etaSource: 'REALTIME',
        etaConfidence: 'HIGH',
        sourceLabel: '실시간 도착 정보 기준',
      ),
    );
    await tester.pumpAndSettle();

    expect(notifier.scheduleCalls, 1);
    expect(
      notifier.scheduledAlarms.single.arrivalAt.isAtSameMomentAs(
        DateTime.parse('2026-07-06T09:40:00+09:00'),
      ),
      isTrue,
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
      expect(routeItemSemantics.label, contains('계단 여부를 확인하고 있어요'));
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

    await _openRouteSearchScreen(tester);
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

  testWidgets('경로 피드백 실패는 도움말을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeFeedbackRepository = FakeRouteFeedbackRepository()
      ..error = const RouteFeedbackException('의견을 보내지 못했어요.');

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

      await _openRouteSearchScreen(tester);
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

      expect(find.text('의견을 보내지 못했어요.'), findsOneWidget);
      expect(find.text('잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('도움말, 잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('routeFeedbackFailureNextAction')),
        ),
        isSemantics(
          label: '도움말, 잠시 후 다시 보내거나 경로 조건을 바꿔 다시 찾아보세요.',
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
    expect(find.text('의견을 보내지 못했어요.'), findsOneWidget);
  });

  testWidgets('경로 안내 칩은 좁은 화면과 시스템 글자 크기에서도 넘치지 않는다', (tester) async {
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
    expect(find.text('이동 조건을 다시 선택해 주세요'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('routeResultListItem')));
    await tester.pumpAndSettle();
    await _tapFirstRouteResultListItem(tester);
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

    await _openRouteSearchScreen(tester);
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

  testWidgets('경로 검색 실패는 도움말을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    final routeRepository = FakeRouteSearchRepository(
      error: const RouteSearchException('경로 정보를 불러오지 못했어요.'),
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

      await _openRouteSearchScreen(tester);
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
      expect(find.text('경로 정보를 불러오지 못했어요.'), findsOneWidget);
      expect(
        find.text('역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('도움말, 역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('routeSearchFailureNextAction')),
        ),
        isSemantics(
          label: '도움말, 역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.',
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

    await _openRouteSearchScreen(tester);
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

      await _openRouteSearchScreen(tester);
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
      expect(find.text('안내할 수 있는 경로를 아직 찾지 못했어요.'), findsOneWidget);
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
        find.bySemanticsLabel('도움말, 역을 다시 선택하거나 이동 조건을 바꾼 뒤 경로를 다시 찾아보세요.'),
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
      await tester.testTextInput.receiveAction(TextInputAction.search);
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

      expect(find.text('시설 알려주기'), findsOneWidget);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('무엇을 알려드릴까요?'), findsOneWidget);
      expect(find.bySemanticsLabel('고장 선택됨'), findsOneWidget);

      await tester.tap(find.byKey(const Key('facilityReportType-CLOSED')));
      await tester.pumpAndSettle();
      await _showFacilityReportDescriptionInput(tester);
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

      // 사진·위치를 첨부하지 않았으므로 별도 공개 범위 확인 없이 바로 접수된다.
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
      expect(find.text('진행 상황'), findsOneWidget);
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
      expect(find.text('제보 진행 상황을 확인했어요.'), findsOneWidget);
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

  testWidgets('시설 신고 실패는 도움말을 쉬운 문구로 안내한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final reportRepository = FakeFacilityReportRepository()
      ..error = const FacilityReportException('신고를 보내지 못했어요.');

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

      await _showFacilityReportDescriptionInput(tester);
      await tester.enterText(
        find.byKey(const Key('facilityReportDescriptionInput')),
        '출입문이 막혀 있습니다.',
      );
      await _showFacilityReportSubmitButton(tester);
      await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
      await tester.pumpAndSettle();

      expect(reportRepository.requests, hasLength(1));
      expect(find.text('신고를 보내지 못했어요.'), findsOneWidget);
      expect(find.text('내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요.'), findsOneWidget);
      expect(
        find.bySemanticsLabel('도움말, 내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요.'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.byKey(const Key('facilityReportFailureNextAction')),
        ),
        isSemantics(
          label: '도움말, 내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요.',
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

  testWidgets('시설 제보 화면은 에스컬레이터 정상 상태에 유효한 유형만 노출한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FacilityReportScreen(
          repository: FakeFacilityReportRepository(),
          target: const FacilityReportTarget(
            stationId: 'station-sangnoksu',
            stationName: '상록수',
            facilityId: 'facility-sangnoksu-escalator-1',
            facilityName: '1번 출구 에스컬레이터',
            facilityTypeLabel: '에스컬레이터',
            facilityStatusLabel: '정상',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 유효 유형만 노출한다.
    expect(find.text('고장'), findsOneWidget);
    expect(find.text('공사 중'), findsOneWidget);
    expect(find.text('폐쇄'), findsOneWidget);
    expect(find.text('위치가 달라요'), findsOneWidget);
    expect(find.text('정보가 달라요'), findsOneWidget);
    // 경로/역 수준·엘리베이터 전용 유형과, 정상 시설의 '다시 정상'은 숨긴다.
    expect(find.text('계단이 있어요'), findsNothing);
    expect(find.text('환승이 어려워요'), findsNothing);
    expect(find.text('도착 시간이 달라요'), findsNothing);
    expect(find.text('경로가 막혔어요'), findsNothing);
    expect(find.text('엘리베이터 이용 불가'), findsNothing);
    expect(find.text('다시 정상'), findsNothing);
  });

  group('facilityReportTypeOptionsFor', () {
    test('에스컬레이터 정상은 경로/역 수준·다시 정상을 제외한다', () {
      expect(
        facilityReportTypeOptionsFor(
          facilityTypeLabel: '에스컬레이터',
          facilityStatusLabel: '정상',
        ),
        const [
          FacilityReportTypeOption.broken,
          FacilityReportTypeOption.underConstruction,
          FacilityReportTypeOption.closed,
          FacilityReportTypeOption.locationWrong,
          FacilityReportTypeOption.informationWrong,
        ],
      );
    });

    test('엘리베이터에는 엘리베이터 이용 불가를 노출한다', () {
      final options = facilityReportTypeOptionsFor(
        facilityTypeLabel: '엘리베이터',
        facilityStatusLabel: '정상',
      );
      expect(options, contains(FacilityReportTypeOption.elevatorUnavailable));
      expect(options, isNot(contains(FacilityReportTypeOption.recovered)));
    });

    test('고장 상태는 고장을 숨기고 다시 정상을 노출한다', () {
      final options = facilityReportTypeOptionsFor(
        facilityTypeLabel: '에스컬레이터',
        facilityStatusLabel: '고장',
      );
      expect(options, isNot(contains(FacilityReportTypeOption.broken)));
      expect(options, contains(FacilityReportTypeOption.recovered));
    });

    test('알 수 없는 타입도 경로/역 수준 유형은 제외한다', () {
      final options = facilityReportTypeOptionsFor(
        facilityTypeLabel: '고객센터',
        facilityStatusLabel: '상태를 확인하고 있어요',
      );
      expect(options, isNot(contains(FacilityReportTypeOption.routeBlocked)));
      expect(options, isNot(contains(FacilityReportTypeOption.stairsPresent)));
      expect(
        options,
        isNot(contains(FacilityReportTypeOption.transferImpossible)),
      );
      expect(options, isNot(contains(FacilityReportTypeOption.etaInaccurate)));
      // 정상이 아니므로 '다시 정상'은 노출한다.
      expect(options, contains(FacilityReportTypeOption.recovered));
    });
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

      await _showFacilityReportDescriptionInput(tester);
      await tester.enterText(
        find.byKey(const Key('facilityReportDescriptionInput')),
        '문이 열리지 않습니다.',
      );
      await _showFacilityReportSubmitButton(tester);
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

    await _showFacilityReportDescriptionInput(tester);
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '선택했던 사진입니다.',
    );
    await _showFacilityReportSubmitButton(tester);
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
            facilityStatusLabel: '상태를 확인하고 있어요',
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
        facilityStatusLabel: '상태를 확인하고 있어요',
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
    expect(find.text('시설 알려주기'), findsOneWidget);
    expect(
      find.bySemanticsLabel('상록수역, 장애인 화장실, 장애인 화장실, 현재 상태를 확인하고 있어요'),
      findsOneWidget,
    );

    await tester.dragUntilVisible(
      find.bySemanticsLabel('사진 1장 추가됨'),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.text('사진 1장 추가됨'), findsOneWidget);

    await _showFacilityReportDescriptionInput(tester);
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '앱 재시작 후 복구된 사진입니다.',
    );
    await _showFacilityReportSubmitButton(tester);
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
        facilityStatusLabel: '상태를 확인하고 있어요',
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
    expect(find.text('시설 알려주기'), findsOneWidget);
    expect(
      find.bySemanticsLabel('상록수역, 장애인 화장실, 장애인 화장실, 현재 상태를 확인하고 있어요'),
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
        facilityStatusLabel: '상태를 확인하고 있어요',
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
    expect(find.text('시설 알려주기'), findsOneWidget);
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

    // 위치 첨부(선택)를 켜서 사진과 위치를 함께 보낸다.
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();

    await _showFacilityReportDescriptionInput(tester);
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '문 앞에 안내문이 붙어 있습니다.',
    );
    await _showFacilityReportSubmitButton(tester);

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

  testWidgets('시설 신고 화면은 진입 시 위치를 자동 요청하지 않고 버튼을 눌러야 첨부한다', (tester) async {
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

    // 진입 즉시 위치 요청·다이얼로그가 뜨지 않는다.
    expect(requestCount, 0);
    expect(find.text('현재 위치 사용'), findsNothing);

    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(find.text('현재 위치를 첨부했어요'), findsOneWidget);
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

    // 진입 시에는 권한 확인·요청을 하지 않는다.
    expect(permissionCheckCount, 0);
    expect(requestCount, 0);
    expect(find.text('현재 위치 사용'), findsNothing);

    // 위치 첨부를 켤 때 사용 목적을 먼저 안내한다.
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();

    expect(permissionCheckCount, 1);
    expect(requestCount, 0);
    expect(find.text('현재 위치 사용'), findsOneWidget);
    expect(find.text('가까운 역 찾기와 시설 제보 위치 확인에만 현재 위치를 사용합니다.'), findsOneWidget);
    expect(
      find.text('위치 사용을 허용하지 않아도 역명 검색, 즐겨찾기, 엘리베이터와 시설 안내는 계속 사용할 수 있습니다.'),
      findsOneWidget,
    );

    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();

    expect(requestCount, 1);

    await _showFacilityReportDescriptionInput(tester);
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

  testWidgets('시설 신고 화면은 위치 권한 확인 중 제출을 막는다', (tester) async {
    final reportRepository = FakeFacilityReportRepository();
    final permissionCheckCompleter = Completer<bool>();
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
          needsLocationPermissionRequest: () => permissionCheckCompleter.future,
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

    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pump();

    final pendingSubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(pendingSubmitButton.onPressed, isNull);
    expect(reportRepository.requests, isEmpty);
    expect(requestCount, 0);

    permissionCheckCompleter.complete(false);
    await tester.pumpAndSettle();

    final readySubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(readySubmitButton.onPressed, isNotNull);
    expect(requestCount, 1);
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
    expect(requestCount, 0);

    // 첫 첨부 시도 → 실패, 버튼이 "위치 다시 찾기"로 바뀐다(같은 키).
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();
    expect(requestCount, 1);

    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
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

    // 첫 첨부 시도 → 실패.
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();

    expect(requestCount, 1);
    expect(find.text('휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
    // 위치는 선택이므로 실패해도 제보 버튼은 활성 상태다.
    await _showFacilityReportSubmitButton(tester);
    final failedLocationSubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(failedLocationSubmitButton.onPressed, isNotNull);

    // 같은 버튼(라벨 "위치 다시 찾기")으로 다시 시도 → 성공.
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();

    expect(requestCount, 2);
    expect(find.text('현재 위치를 첨부했어요'), findsOneWidget);
  });

  testWidgets('시설 신고 화면은 위치 실패 후 위치 없이 제출하면 실패 안내를 지운다', (tester) async {
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
          locationLoader: () async {
            throw const FacilityReportLocationException(
              '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.',
            );
          },
          needsLocationPermissionRequest: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();

    expect(find.text('휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsOneWidget);
    await _showFacilityReportDescriptionInput(tester);
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '위치 없이 바로 제보합니다.',
    );
    await _showFacilityReportSubmitButton(tester);
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
    await tester.pumpAndSettle();

    expect(reportRepository.requests, hasLength(1));
    expect(reportRepository.requests.single.latitude, isNull);
    expect(reportRepository.requests.single.longitude, isNull);
    expect(find.text('휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.'), findsNothing);
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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

    // 진입 시 위치를 자동 요청하지 않는다.
    expect(locationProvider.requestCount, 0);

    // 위치를 첨부하지 않아도 제보를 보낼 수 있다(위치는 선택).
    await _showFacilityReportDescriptionInput(tester);
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '위치 없이 빠르게 알립니다.',
    );
    await _showFacilityReportSubmitButton(tester);
    final submitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(submitButton.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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

    // 진입 시 자동 요청하지 않고, 첨부 시도 시 GPS 꺼짐 실패 → 설정 열기 버튼 노출.
    expect(locationProvider.requestCount, 0);
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
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

    // 첨부 시도 → GPS 꺼짐 실패.
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();
    expect(requestCount, 1);

    await tester.dragUntilVisible(
      find.byKey(const Key('facilityReportOpenLocationSettingsButton')),
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    // 설정을 여는 중에는 위치 재확인(다시 찾기) 버튼이 눌리지 않는다.
    await tester.tap(
      find.byKey(const Key('facilityReportOpenLocationSettingsButton')),
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
      warnIfMissed: false,
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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

    expect(find.text('시설 알려주기'), findsOneWidget);
    // 위치는 자동 요청되지 않는다. 첨부 버튼으로 켠 뒤 첨부된다.
    expect(locationProvider.requestCount, 0);
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();
    expect(locationProvider.requestCount, 1);
    expect(find.text('현재 위치를 첨부했어요'), findsOneWidget);

    await _showFacilityReportDescriptionInput(tester);
    await tester.enterText(
      find.byKey(const Key('facilityReportDescriptionInput')),
      '승강기 앞에서 확인했습니다.',
    );
    await _showFacilityReportSubmitButton(tester);
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

    // 위치 첨부를 켜면 확인 중(로딩 스피너)에는 제출이 잠시 막힌다.
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pump();

    final loadingSubmitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(loadingSubmitButton.onPressed, isNull);
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

  testWidgets('시설 신고 화면은 현재 위치 실패 안내를 쉬운 문구로 보여준다', (tester) async {
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
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

    // 첨부 시도 → 권한 거부 실패 안내를 쉬운 문구로 보여준다.
    await _showFacilityReportAttachLocationButton(tester);
    await tester.tap(
      find.byKey(const Key('facilityReportAttachLocationButton')),
    );
    await tester.pumpAndSettle();

    expect(find.text('현재 위치를 사용할 수 없어요.'), findsOneWidget);
    // GPS off가 아닌 권한 거부라 설정 버튼은 없고, 위치 없이도 제출할 수 있다.
    expect(
      find.byKey(const Key('facilityReportOpenLocationSettingsButton')),
      findsNothing,
    );
    await _showFacilityReportSubmitButton(tester);
    final submitButton = tester.widget<FilledButton>(
      find.byKey(const Key('facilityReportSubmitButton')),
    );
    expect(submitButton.onPressed, isNotNull);
  });
}

Future<void> _showFacilityReportAttachLocationButton(
  WidgetTester tester,
) async {
  final finder = find.byKey(const Key('facilityReportAttachLocationButton'));
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
  } else {
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _showFacilityReportDescriptionInput(WidgetTester tester) async {
  final finder = find.byKey(const Key('facilityReportDescriptionInput'));
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
  } else {
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _showFacilityReportSubmitButton(WidgetTester tester) async {
  final finder = find.byKey(const Key('facilityReportSubmitButton'));
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
  } else {
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
  }
  await tester.pumpAndSettle();
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

NetworkMapData _expressFilterMapData() {
  return const NetworkMapData(
    regions: [NetworkMapRegion(name: '테스트권')],
    selectedRegion: '테스트권',
    lines: [
      NetworkMapLine(
        id: 'line-local',
        name: '일반 노선',
        color: '#444444',
        region: '테스트권',
      ),
      NetworkMapLine(
        id: 'line-express',
        name: '급행 노선',
        color: '#D71920',
        region: '테스트권',
      ),
    ],
    stations: [
      NetworkMapStation(
        id: 'station-local-a',
        nameKo: '일반A',
        nameEn: 'Local A',
        region: '테스트권',
        lineId: 'line-local',
        stationCode: 'L01',
        sequence: 1,
        position: NetworkMapPosition(
          x: 100,
          y: 100,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-express-filter',
        ),
      ),
      NetworkMapStation(
        id: 'station-local-b',
        nameKo: '일반B',
        nameEn: 'Local B',
        region: '테스트권',
        lineId: 'line-local',
        stationCode: 'L02',
        sequence: 2,
        position: NetworkMapPosition(
          x: 180,
          y: 100,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-express-filter',
        ),
      ),
      NetworkMapStation(
        id: 'station-express-a',
        nameKo: '급행A',
        nameEn: 'Express A',
        region: '테스트권',
        lineId: 'line-express',
        stationCode: 'E01',
        sequence: 1,
        position: NetworkMapPosition(
          x: 100,
          y: 180,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-express-filter',
        ),
      ),
      NetworkMapStation(
        id: 'station-express-b',
        nameKo: '급행B',
        nameEn: 'Express B',
        region: '테스트권',
        lineId: 'line-express',
        stationCode: 'E02',
        sequence: 2,
        position: NetworkMapPosition(
          x: 180,
          y: 180,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: '',
          sourceId: 'fixture-express-filter',
        ),
      ),
    ],
    edges: [
      NetworkMapEdge(
        id: 'edge-local',
        lineId: 'line-local',
        fromStationId: 'station-local-a:line-local',
        toStationId: 'station-local-b:line-local',
        accessibilityStatus: 'AVAILABLE',
        reliabilityScore: 100,
      ),
      NetworkMapEdge(
        id: 'edge-express',
        lineId: 'line-express',
        fromStationId: 'station-express-a:line-express',
        toStationId: 'station-express-b:line-express',
        accessibilityStatus: 'AVAILABLE',
        reliabilityScore: 100,
      ),
    ],
    positionSources: [
      NetworkMapPositionSource(
        id: 'fixture-express-filter',
        name: '급행 필터 fixture',
        licenseStatus: 'fixture-only',
      ),
    ],
    stationLineMemberships: [],
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
    this.stationDetails = const {},
    this.stationDetailCompleters = const {},
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
  final Map<String, StationDetail> stationDetails;
  final Map<String, Completer<StationDetail>> stationDetailCompleters;
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
    final completer = stationDetailCompleters[stationId];
    if (completer != null) {
      return completer.future;
    }
    return stationDetails[stationId] ?? stationDetail;
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
        id: 'station-banwol',
        nameKo: '반월',
        nameEn: 'Banwol',
        region: '테스트권',
        lineId: 'seoul-4',
        stationCode: '447',
        sequence: 47,
        position: NetworkMapPosition(
          x: 120,
          y: 250,
          labelDx: 0,
          labelDy: 0,
          upPath: 'M 120 250 L 156 250',
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
      NetworkMapStation(
        id: 'station-handaeap',
        nameKo: '한대앞',
        nameEn: 'Hanyang Univ. at Ansan',
        region: '수도권',
        lineId: 'seoul-4',
        stationCode: '449',
        sequence: 49,
        position: NetworkMapPosition(
          x: 200,
          y: 250,
          labelDx: 0,
          labelDy: 0,
          upPath: '',
          downPath: 'M 156 250 L 200 250',
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
        id: 'map-edge-seoul-4-station-banwol-station-sangnoksu',
        lineId: 'seoul-4',
        fromStationId: 'station-banwol:seoul-4',
        toStationId: 'station-sangnoksu:seoul-4',
        accessibilityStatus: 'AVAILABLE',
        reliabilityScore: 100,
      ),
      NetworkMapEdge(
        id: 'map-edge-seoul-4-station-sangnoksu-station-handaeap',
        lineId: 'seoul-4',
        fromStationId: 'station-sangnoksu:seoul-4',
        toStationId: 'station-handaeap:seoul-4',
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
          name: '수도권 노선도 fixture 좌표 확인',
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

class _FakeKakaoMapLauncher implements KakaoMapLauncher {
  _FakeKakaoMapLauncher({this.routeResult = KakaoMapLaunchResult.app});

  final lookTargets = <KakaoMapTarget>[];
  final routeTargets = <KakaoWalkingRouteTarget>[];
  final KakaoMapLaunchResult routeResult;

  @override
  Future<KakaoMapLaunchResult> openLook(KakaoMapTarget target) async {
    lookTargets.add(target);
    return KakaoMapLaunchResult.app;
  }

  @override
  Future<KakaoMapLaunchResult> openWalkingRoute(
    KakaoWalkingRouteTarget target,
  ) async {
    routeTargets.add(target);
    return routeResult;
  }
}

RouteSearchResult _sampleGetOffAlarmRouteResult({
  String plannedArrivalTimeIso = '2026-07-06T09:37:30+09:00',
  String realtimeArrivalTimeIso = '',
}) {
  return _sampleRouteSearchResult(
    steps: [
      RouteSearchStep(
        sequence: 1,
        stepType: 'ride',
        title: '상록수에서 사당까지 이동',
        description: '열차를 이용해 이동합니다.',
        lineId: 'seoul-4',
        lineName: '수도권 4호선',
        fromStationId: 'station-sangnoksu',
        toStationId: 'station-sadang',
        estimatedMinutes: 32,
        distanceMeters: 13500,
        includesStairs: false,
        requiresAccessibilityCheck: true,
        plannedArrivalTimeIso: plannedArrivalTimeIso,
        realtimeArrivalTimeIso: realtimeArrivalTimeIso,
      ),
    ],
  );
}

Future<void> _pumpGetOffAlarmRouteScreen(
  WidgetTester tester, {
  required FakeRouteSearchRepository repository,
  required GetOffAlarmController controller,
  StationSearchRepository? stationRepository,
  bool simpleViewEnabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RouteSearchScreen(
        repository: repository,
        stationRepository: stationRepository ?? FakeStationSearchRepository(),
        getOffAlarmController: controller,
        simpleViewEnabled: simpleViewEnabled,
        initialDraft: RouteDraft(
          origin: const RouteDraftStation(
            id: 'station-sangnoksu',
            nameKo: '상록수',
          ),
          destination: const RouteDraftStation(
            id: 'station-sadang',
            nameKo: '사당',
          ),
          lastModifiedAt: DateTime(2026, 7, 6),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('routeSearchSubmitButton')));
  await tester.pumpAndSettle();
}

Future<void> _enableSampleGetOffAlarm(GetOffAlarmController controller) {
  return controller.enable(
    routeId: 'route-1',
    stops: [
      GetOffAlarmStop(
        stationId: 'station-sadang',
        stationName: '사당',
        arrivalAt: DateTime.parse('2026-07-06T09:37:30+09:00'),
        kind: GetOffAlarmKind.destination,
      ),
    ],
    transferAlarmEnabled: false,
  );
}

class FakeRouteSearchRepository implements RouteSearchRepository {
  FakeRouteSearchRepository({RouteSearchResult? result, this.error})
    : result = result ?? _sampleRouteSearchResult();

  final RouteSearchResult result;
  final Object? error;
  final requests = <RouteSearchRequest>[];
  final refreshRouteSearchIds = <String>[];
  RouteRefreshResult? refreshResult;
  Object? refreshError;
  Completer<RouteRefreshResult>? pendingRefresh;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    requests.add(request);
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return result;
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) async {
    refreshRouteSearchIds.add(routeSearchId);
    final currentError = refreshError;
    if (currentError != null) {
      throw currentError;
    }
    final pending = pendingRefresh;
    if (pending != null) {
      return pending.future;
    }
    return refreshResult ??
        RouteRefreshResult(
          routeSearchId: routeSearchId,
          status: 'UNCHANGED',
          result: result,
          refreshedAt: '2026-07-01T15:30:00',
          etaSource: 'PLANNED',
          etaConfidence: 'MEDIUM',
          sourceLabel: '계획 시간 기준',
        );
  }
}

class _RecordingGetOffAlarmNotifier implements GetOffAlarmNotifier {
  int scheduleCalls = 0;
  int cancelCalls = 0;
  List<ScheduledGetOffAlarm> scheduledAlarms = const [];
  GetOffAlarmScheduleMode? scheduledMode;
  Object? cancelError;
  Object? scheduleError;

  void reset() {
    scheduleCalls = 0;
    cancelCalls = 0;
    scheduledAlarms = const [];
    scheduledMode = null;
  }

  @override
  Future<void> cancelAll() async {
    cancelCalls += 1;
    final error = cancelError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<int> pendingAlarmCount() async => scheduledAlarms.length;

  @override
  Future<ScheduleDeliveryResult> scheduleAlarms(
    List<ScheduledGetOffAlarm> alarms, {
    required GetOffAlarmScheduleMode mode,
  }) async {
    scheduleCalls += 1;
    final error = scheduleError;
    if (error != null) {
      throw error;
    }
    scheduledAlarms = alarms;
    scheduledMode = mode;
    return ScheduleDeliveryResult(
      scheduledCount: alarms.length,
      failedCount: 0,
    );
  }
}

class _StubExactAlarmPermissionGate implements ExactAlarmPermissionGate {
  @override
  Future<bool> isExactAlarmPermitted() async => true;

  @override
  Future<bool> requestExactAlarmPermission() async => true;
}

class _MemoryGetOffAlarmStateRepository implements GetOffAlarmStateRepository {
  GetOffAlarmSubscription? _active;

  @override
  Future<void> clearActive() async => _active = null;

  @override
  Future<GetOffAlarmSubscription?> loadActive() async => _active;

  @override
  Future<void> saveActive(GetOffAlarmSubscription subscription) async {
    _active = subscription;
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
  Future<NotificationPermissionStatus> notificationPermissionStatus() async {
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return nextStatus;
  }

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

class _BlockingNotificationPermissionProvider
    implements NotificationPermissionProvider {
  final started = Completer<void>();
  final result = Completer<NotificationPermissionStatus>();
  int requestCount = 0;

  @override
  Future<NotificationPermissionStatus> notificationPermissionStatus() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<NotificationPermissionStatus> requestNotificationPermission() {
    requestCount += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    return result.future;
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

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) {
    throw UnimplementedError();
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

class _RetryRealtimeRepository implements RealtimeRepository {
  int callCount = 0;

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    callCount++;
    if (callCount == 1) {
      throw const RealtimeException('실시간 정보를 불러오지 못했어요.');
    }
    return const RealtimeSnapshot(
      status: RealtimeSnapshotStatus.fresh,
      receivedAt: '방금',
      arrivals: [
        RealtimeArrival(
          lineId: 'seoul-2',
          stationName: '상록수',
          destination: '사당',
          direction: '하행',
          trainNo: '2002',
          message: '곧 도착',
          etaSeconds: 120,
        ),
      ],
    );
  }
}

class _FreshNearbyRealtimeRepository implements RealtimeRepository {
  const _FreshNearbyRealtimeRepository();

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    return const RealtimeSnapshot(
      status: RealtimeSnapshotStatus.fresh,
      receivedAt: '방금',
      arrivals: [
        RealtimeArrival(
          lineId: 'seoul-2',
          stationName: '상록수',
          destination: '한대앞',
          direction: '상행',
          trainNo: '2001',
          message: '',
          etaSeconds: 180,
        ),
        RealtimeArrival(
          lineId: 'seoul-2',
          stationName: '상록수',
          destination: '사당',
          direction: '하행',
          trainNo: '2002',
          message: '',
          etaSeconds: 300,
        ),
      ],
    );
  }
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

class FakeNetworkMapViewportRepository implements NetworkMapViewportRepository {
  FakeNetworkMapViewportRepository({Map<String, Rect>? viewports})
    : savedViewports = {...?viewports};

  final Map<String, Rect> savedViewports;
  final loadedRegions = <String>[];

  @override
  Future<Rect?> loadViewport(String region) async {
    loadedRegions.add(region);
    return savedViewports[region];
  }

  @override
  Future<void> saveViewport({
    required String region,
    required Rect viewport,
  }) async {
    savedViewports[region] = viewport;
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
  String etaSource = '',
  String sourceUpdatedAt = '',
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
            confidenceLabel: '확인된 정보예요',
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
        message: '일부 시설 안내를 준비 중이에요.',
      ),
      RouteSearchWarning(
        code: 'STALE_ACCESSIBILITY_DATA',
        message: '엘리베이터와 시설 안내가 오래됐을 수 있어요.',
      ),
    ],
    recommendationReasons: recommendationReasons,
    blockedReasons: [],
    createdAt: '2026-06-13T04:20:00',
    etaSource: etaSource,
    sourceUpdatedAt: sourceUpdatedAt,
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
