import 'dart:async';

import 'package:easysubway_mobile/anonymous_auth.dart';
import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/favorite_facility.dart';
import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  testWidgets('첫 실행 앱은 온보딩을 완료한 뒤 홈으로 이동한다', (tester) async {
    final onboardingStore = MemoryOnboardingResultStore();

    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('쉬운 지하철'), findsOneWidget);
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsNothing);

    await tester.tap(find.byKey(const Key('onboardingProfileCard-elderly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    expect(find.text('역 찾기'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsNothing);
    expect(onboardingStore.savedResult?.profile.id, 'elderly');
    expect(onboardingStore.saveCount, 1);
  });

  testWidgets('앱은 저장된 온보딩 설정으로 홈을 바로 보여준다', (tester) async {
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        profile: mobilityProfileOptions.firstWhere(
          (option) => option.id == 'wheelchair',
        ),
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: true,
          highContrastEnabled: true,
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
        notificationRepository: FakeNotificationSettingsRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    final homeContext = tester.element(find.byType(HomeScreen));

    expect(onboardingStore.readCount, 1);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsNothing);
    expect(MediaQuery.textScalerOf(homeContext).scale(20), closeTo(23.6, 0.01));
    expect(Theme.of(homeContext).colorScheme.primary, const Color(0xFF003D40));
  });

  testWidgets('앱은 온보딩 저장소를 읽지 못하면 다시 설정을 고르게 한다', (tester) async {
    final reportedErrors = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          onboardingStore: MemoryOnboardingResultStore(throwOnRead: true),
        ),
      );
      await tester.pumpAndSettle();
    });

    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, isA<FormatException>());
    expect(find.text('먼저 이동 조건을 골라 주세요'), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsNothing);
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

  testWidgets('홈 화면은 핵심 행동만 간결하게 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
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

      expect(find.text('역 찾기'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '역 검색'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '경로 검색'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '즐겨찾기 역'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '알림 설정'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '이동 조건'), findsOneWidget);
      expect(find.textContaining('빠른 길보다'), findsNothing);
      expect(find.textContaining('고령자'), findsNothing);
      expect(find.textContaining('휠체어'), findsNothing);

      final stationButtonSize = tester.getSize(
        find.byKey(const Key('stationSearchButton')),
      );
      final routeButtonSize = tester.getSize(
        find.byKey(const Key('routeSearchButton')),
      );
      final profileButtonSize = tester.getSize(
        find.byKey(const Key('mobilityProfileButton')),
      );
      final notificationButtonSize = tester.getSize(
        find.byKey(const Key('notificationSettingsButton')),
      );

      expect(stationButtonSize.height, greaterThanOrEqualTo(60));
      expect(routeButtonSize.height, greaterThanOrEqualTo(60));
      expect(notificationButtonSize.height, greaterThanOrEqualTo(60));
      expect(profileButtonSize.height, greaterThanOrEqualTo(60));

      await tester.drag(find.byType(ListView), const Offset(0, -620));
      await tester.pumpAndSettle();

      expect(find.text('이동 프로필'), findsOneWidget);
      expect(find.text('시설 정보'), findsOneWidget);
      expect(find.text('신고'), findsOneWidget);
      expect(find.bySemanticsLabel('이동 프로필, 이동 조건 저장'), findsOneWidget);
      expect(find.bySemanticsLabel('시설 정보, 엘리베이터와 경사로'), findsOneWidget);
      expect(find.bySemanticsLabel('신고, 불편 신고'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('인증 저장소가 없으면 홈 즐겨찾기를 노출하지 않는다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        enableAnonymousAuth: false,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    expect(find.byKey(const Key('favoriteStationsButton')), findsNothing);
    expect(find.widgetWithText(FilledButton, '즐겨찾기 역'), findsNothing);
    expect(find.byKey(const Key('favoriteRoutesButton')), findsNothing);
    expect(find.widgetWithText(FilledButton, '즐겨찾기 경로'), findsNothing);
    expect(find.byKey(const Key('notificationSettingsButton')), findsNothing);
    expect(find.widgetWithText(FilledButton, '알림 설정'), findsNothing);
  });

  testWidgets('기본 홈 화면은 익명 인증으로 즐겨찾기를 노출한다', (tester) async {
    await tester.pumpWidget(
      EasySubwayApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        anonymousAuthRepository: FakeAnonymousAuthRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    expect(find.byKey(const Key('favoriteRoutesButton')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '즐겨찾기 경로'), findsOneWidget);
    expect(find.byKey(const Key('favoriteStationsButton')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '즐겨찾기 역'), findsOneWidget);
    expect(find.byKey(const Key('notificationSettingsButton')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '알림 설정'), findsOneWidget);
  });

  test('기본 앱은 즐겨찾기와 알림 설정에 같은 익명 인증 세션을 주입한다', () {
    final app = EasySubwayApp(
      repository: FakeStationSearchRepository(),
      reportRepository: FakeFacilityReportRepository(),
      routeRepository: FakeRouteSearchRepository(),
      anonymousAuthRepository: FakeAnonymousAuthRepository(),
      initialOnboardingState: _completedOnboardingState(),
    );

    final favoriteRepository =
        app.favoriteRepository as FavoriteStationApiRepository;
    final favoriteFacilityRepository =
        app.favoriteFacilityRepository as FavoriteFacilityApiRepository;
    final favoriteRouteRepository =
        app.favoriteRouteRepository as FavoriteRouteApiRepository;
    final notificationRepository =
        app.notificationRepository as NotificationSettingsApiRepository;

    expect(
      identical(
        favoriteRepository.authProvider,
        favoriteFacilityRepository.authProvider,
      ),
      isTrue,
    );
    expect(
      identical(
        favoriteFacilityRepository.authProvider,
        favoriteRouteRepository.authProvider,
      ),
      isTrue,
    );
    expect(
      identical(
        favoriteRouteRepository.authProvider,
        notificationRepository.authProvider,
      ),
      isTrue,
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

      await tester.ensureVisible(
        find.byKey(const Key('notificationSettingsButton')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notificationSettingsButton')));
      await tester.pumpAndSettle();

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
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('favoriteStationsButton')));
      await tester.pumpAndSettle();

      expect(find.text('즐겨찾기 역'), findsOneWidget);
      expect(find.text('상록수'), findsOneWidget);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('기본 정보만 확인됨'), findsOneWidget);
      expect(
        find.byKey(const Key('favoriteStationTile-station-sangnoksu')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '즐겨찾기 역, 상록수, 수도권 4호선, 수도권, 기본 정보만 확인됨, 출처 공식 파일',
        ),
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
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('favoriteFacilitiesButton')));
      await tester.pumpAndSettle();

      expect(find.text('즐겨찾기 시설'), findsOneWidget);
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

      await tester.tap(find.byKey(const Key('favoriteRoutesButton')));
      await tester.pumpAndSettle();

      expect(find.text('즐겨찾기 경로'), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('favoriteRoutesButton')));
    await tester.pumpAndSettle();

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
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('상록수, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 확인됨'),
        ),
        isSemantics(
          label: '상록수, 수도권 4호선, 경의중앙선, 수도권, 기본 정보만 확인됨',
          isButton: true,
          hasTapAction: true,
        ),
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

  testWidgets('역 검색은 현재 위치 주변 역을 큰 버튼으로 찾고 거리를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final locationProvider = FakeCurrentLocationProvider(
      location: const CurrentLocation(latitude: 37.3028, longitude: 126.8665),
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

      expect(locationProvider.requestCount, 1);
      expect(repository.requestedNearbyLocations.single.latitude, 37.3028);
      expect(repository.requestedNearbyLocations.single.longitude, 126.8665);
      expect(find.text('상록수'), findsOneWidget);
      expect(find.text('230m 거리'), findsOneWidget);
      expect(
        find.bySemanticsLabel('상록수, 230m 거리, 수도권 2호선, 수도권, 기본 정보만 확인됨'),
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

  testWidgets('역 검색은 현재 위치를 확인하지 못하면 짧은 안내를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException('위치 권한을 확인해 주세요.'),
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

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 검색 결과를 누르면 출구와 시설 상태를 쉬운 문구로 보여준다', (tester) async {
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
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
      await tester.pumpAndSettle();

      expect(repository.requestedDetailStationIds, ['station-sangnoksu']);
      expect(repository.requestedExitStationIds, ['station-sangnoksu']);
      expect(repository.requestedFacilityStationIds, ['station-sangnoksu']);
      expect(find.text('상록수역'), findsOneWidget);
      expect(find.text('수도권 2호선'), findsOneWidget);
      expect(find.text('기본 정보만 확인됨'), findsOneWidget);
      expect(find.text('출처 공식 파일'), findsWidgets);
      expect(find.text('마지막 확인 2026-06-13'), findsOneWidget);
      expect(find.text('출구'), findsOneWidget);
      expect(find.text('1번 출구'), findsOneWidget);
      expect(find.text('엘리베이터 연결'), findsOneWidget);
      expect(find.text('계단 없는 이동 가능'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '상록수역 상세 정보, 수도권 2호선, 기본 정보만 확인됨, 출처 공식 파일, 마지막 확인 2026-06-13',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          '1번 출구, 엘리베이터 연결, 계단 없는 이동 가능, 정보 신뢰도 높음, 출처 공식 파일',
        ),
        findsOneWidget,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pumpAndSettle();
      expect(find.text('시설'), findsOneWidget);
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
      expect(find.text('엘리베이터'), findsOneWidget);
      expect(find.text('정상'), findsOneWidget);
      expect(find.text('1번 출구 앞'), findsOneWidget);
      expect(find.text('최근 확인 2026-06-12'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '1번 출구 엘리베이터, 엘리베이터, 정상, 1번 출구 앞, 최근 확인 2026-06-12, 정보 신뢰도 높음, 출처 공식 파일',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(
          const Key('facilityReportButton-facility-sangnoksu-elevator-1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, '상태 신고'), findsOneWidget);
      expect(find.bySemanticsLabel('1번 출구 엘리베이터 상태 신고'), findsOneWidget);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      semanticsHandle.dispose();
    }
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
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
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
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.text('상록수역'), findsOneWidget);
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
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await tester.tap(find.byKey(const Key('favoriteStationsButton')));
    await tester.pumpAndSettle();
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
      expect(find.text('이동할 수 있는 경로'), findsOneWidget);
      expect(
        find.byKey(const Key('routeGuidanceMobilityChip')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('routeGuidanceAttentionChip')),
        findsOneWidget,
      );
      expect(find.text('상록수에서 사당까지'), findsOneWidget);
      expect(find.text('수도권 4호선'), findsOneWidget);
      expect(find.text('이동 점수 92점'), findsOneWidget);
      expect(find.text('이동 순서'), findsOneWidget);
      expect(find.byKey(const Key('routeStepNumber-1')), findsOneWidget);
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
          '경로 검색 결과, 이동할 수 있는 경로, 고령자, 상록수에서 사당까지, 수도권 4호선, 이동 점수 92점, 주의 확인, '
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
    expect(find.text('확인이 필요합니다'), findsWidgets);
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
      expect(find.text('휠체어로 이동 가능한 엘리베이터가 없습니다.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          '경로 검색 결과, 다른 경로가 필요합니다, 휠체어, 상록수에서 없는역까지, 노선 확인 필요, 이동 점수 0점, '
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
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await tester.tap(find.byKey(const Key('stationSearchButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.tap(find.byKey(const Key('stationSearchSubmitButton')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
      );
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
      await tester.tap(find.byKey(const Key('facilityReportSubmitButton')));
      await tester.pumpAndSettle();

      expect(reportRepository.requests, hasLength(1));
      expect(reportRepository.requests.single.stationId, 'station-sangnoksu');
      expect(
        reportRepository.requests.single.facilityId,
        'facility-sangnoksu-elevator-1',
      );
      expect(reportRepository.requests.single.reportType, 'CLOSED');
      expect(reportRepository.requests.single.description, '출입문이 막혀 있습니다.');
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

class FakeStationSearchRepository implements StationSearchRepository {
  FakeStationSearchRepository({
    this.nextResults = const [],
    this.nearbyResults = const [],
    this.queryResults = const {},
    StationDetail? stationDetail,
    this.stationExits = const [],
    this.stationFacilities = const [],
  }) : stationDetail =
           stationDetail ??
           _stationDetail(id: 'station-sangnoksu', name: '상록수');

  final List<StationSearchResult> nextResults;
  final List<StationSearchResult> nearbyResults;
  final Map<String, List<StationSearchResult>> queryResults;
  final StationDetail stationDetail;
  final List<StationExitInfo> stationExits;
  final List<StationFacilityInfo> stationFacilities;
  final requestedQueries = <String>[];
  final requestedNearbyLocations = <CurrentLocation>[];
  final requestedDetailStationIds = <String>[];
  final requestedExitStationIds = <String>[];
  final requestedFacilityStationIds = <String>[];

  @override
  Future<List<StationSearchResult>> searchStations(String query) async {
    requestedQueries.add(query);
    return queryResults[query] ?? nextResults;
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
  FakeRouteSearchRepository({RouteSearchResult? result})
    : result = result ?? _sampleRouteSearchResult();

  final RouteSearchResult result;
  final requests = <RouteSearchRequest>[];

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    requests.add(request);
    return result;
  }
}

class FakeFacilityReportRepository implements FacilityReportRepository {
  final requests = <FacilityReportRequest>[];
  final loadedReportIds = <String>[];
  String nextReportStatus = 'SUBMITTED';
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
  Future<FavoriteRoute> saveFavoriteRoute(String routeSearchId) async {
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

class FakeAnonymousAuthRepository implements AnonymousAuthRepository {
  int issueCount = 0;

  @override
  bool get canReuseStoredCredentials => true;

  @override
  Future<AnonymousAuthCredentials> issueAnonymousUser() async {
    issueCount++;
    return const AnonymousAuthCredentials(
      userId: 'anonymous-user-1',
      password: 'user-test-password',
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

class FakeCurrentLocationProvider implements CurrentLocationProvider {
  FakeCurrentLocationProvider({this.location, this.error});

  final CurrentLocation? location;
  final Object? error;
  int requestCount = 0;

  @override
  Future<CurrentLocation> currentLocation() async {
    requestCount++;
    final currentError = error;
    if (currentError != null) {
      throw currentError;
    }
    return location ??
        const CurrentLocation(latitude: 37.3028, longitude: 126.8665);
  }
}

StationDetail _stationDetail({required String id, required String name}) {
  return StationDetail(
    id: id,
    nameKo: name,
    nameEn: id,
    region: '수도권',
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
      ),
    ],
    warnings: const [
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
