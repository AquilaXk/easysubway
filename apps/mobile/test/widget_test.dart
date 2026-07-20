import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/favorite_facility.dart';
import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart'
    hide InternalRouteNode;
import 'package:easysubway_mobile/core/datapack/bundled_data_pack_freshness.dart';
import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/ads/active_ad_banner.dart';
import 'package:easysubway_mobile/features/ads/ad_repository.dart';
import 'package:easysubway_mobile/features/account/presentation/user_data_deletion_screen.dart';
import 'package:easysubway_mobile/features/attribution/presentation/data_source_attribution_screen.dart';
import 'package:easysubway_mobile/features/favorites/presentation/favorite_home_screen.dart';
import 'package:easysubway_mobile/features/support/presentation/support_access_screen.dart';
import 'package:easysubway_mobile/features/fare/official_od_fare_quote.dart';
import 'package:easysubway_mobile/features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import 'package:easysubway_mobile/features/get_off_alarm/exact_alarm_permission.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_controller.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_notifier.dart';
import 'package:easysubway_mobile/features/home/presentation/home_screen.dart';
import 'package:easysubway_mobile/features/settings/presentation/app_settings_screen.dart';
import 'package:easysubway_mobile/features/settings/presentation/service_info_screen.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_schedule_mode.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_scheduler.dart';
import 'package:easysubway_mobile/features/get_off_alarm/get_off_alarm_subscription.dart';
import 'package:easysubway_mobile/features/network_map/domain/map_camera.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:easysubway_mobile/features/route_draft/application/route_draft_controller.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_detail_screen.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_search_screen.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:easysubway_mobile/features/route_draft/domain/route_draft.dart';
import 'package:easysubway_mobile/internal_route.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_preset_labels.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_preset_picker.dart';
import 'package:easysubway_mobile/features/mobility_profile/mobility_profile_policy.dart';
import 'package:easysubway_mobile/legacy_credential_cleanup.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/network_map.dart';
import 'package:easysubway_mobile/search_field.dart';
import 'package:easysubway_mobile/features/network_map/presentation/route_map_basemap_view.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_direction_title.dart';
import 'package:easysubway_mobile/features/network_map/presentation/structured_route_map_painter.dart';
import 'package:easysubway_mobile/notification_settings.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:easysubway_mobile/user_data_deletion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'support/easy_subway_app_fixture.dart';

import 'fake_secure_key_value_storage.dart';
import 'user_copy_guard.dart';

OnboardingState _completedOnboardingState({
  MobilityPreset preset = MobilityPreset.slow,
}) {
  return OnboardingState.completed(
    result: OnboardingResult(
      preset: preset,
      preferences: const OnboardingViewPreferences.defaults(),
    ),
  );
}

OnboardingState _completedOnboardingStateWithPreferences({
  required OnboardingViewPreferences preferences,
  MobilityPreset preset = MobilityPreset.slow,
}) {
  return OnboardingState.completed(
    result: OnboardingResult(preset: preset, preferences: preferences),
  );
}

class _FakeNoticeRepository implements NoticeRepository {
  _FakeNoticeRepository(this._result);

  final ActiveNoticesResult _result;

  @override
  Future<ActiveNoticesResult> activeNotices() async => _result;
}

class _NoInventoryAdApiClient extends ApiClient {
  _NoInventoryAdApiClient()
    : super(baseUri: Uri.parse('https://api.easysubway.example'));

  final paths = <String>[];

  @override
  Future<ApiResponse> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    paths.add(path);
    return const ApiResponse(statusCode: 204, jsonBody: null);
  }
}

Future<void> _openFavoriteList(
  WidgetTester tester, {
  Key? tabKey,
  RouteDraftController? routeDraftController,
  Future<void> Function(RouteDraft draft, String mobilityType)?
  onOpenRouteSearch,
  Future<void> Function(
    RouteDraft draft,
    String mobilityType,
    RouteTransportScope transportScope,
  )?
  onOpenRouteSearchWithScope,
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
          onOpenRouteSearch:
              onOpenRouteSearch == null && onOpenRouteSearchWithScope == null
              ? null
              : ([mobilityType, transportScope]) async {
                  final restoredMobilityType =
                      mobilityType ?? home.initialMobilityType;
                  final restoredTransportScope =
                      transportScope ?? RouteTransportScope.subway;
                  if (onOpenRouteSearchWithScope != null) {
                    await onOpenRouteSearchWithScope(
                      draftController.draft,
                      restoredMobilityType,
                      restoredTransportScope,
                    );
                    return;
                  }
                  await onOpenRouteSearch!(
                    draftController.draft,
                    restoredMobilityType,
                  );
                },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // 즐겨찾기 홈은 단일 리스트라 카테고리 진입 탭이 없다. 항목이 바로 보인다(#1569).
}

Future<void> _pumpStationDetailForTest(
  WidgetTester tester, {
  required StationSearchRepository repository,
  required FacilityReportRepository reportRepository,
  String stationId = 'station-sangnoksu',
  FavoriteStationRepository? favoriteRepository,
  AdRepository? adRepository,
  RealtimeRepository? realtimeRepository,
  CurrentLocationProvider? locationProvider,
  bool? initiallyFavorite,
  FacilityReportDraftTargetStore? facilityReportDraftTargetStore,
  InternalRouteRepository? internalRouteRepository,
  InternalRouteRequest? internalRouteRequest,
  String internalRouteMobilityType = 'SENIOR',
  RouteDraftController? routeDraftController,
  KakaoMapLauncher mapLauncher = const UrlLauncherKakaoMapLauncher(),
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: StationDetailScreen(
        repository: repository,
        reportRepository: reportRepository,
        stationId: stationId,
        favoriteRepository: favoriteRepository,
        adRepository: adRepository,
        realtimeRepository: realtimeRepository,
        locationProvider: locationProvider,
        initiallyFavorite: initiallyFavorite,
        facilityReportDraftTargetStore: facilityReportDraftTargetStore,
        internalRouteRepository: internalRouteRepository,
        internalRouteRequest: internalRouteRequest,
        internalRouteMobilityType: internalRouteMobilityType,
        routeDraftController: routeDraftController,
        mapLauncher: mapLauncher,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }
}

Future<void> _pumpNetworkMapForGpsTest(
  WidgetTester tester, {
  required FakeStationSearchRepository repository,
  required CurrentLocationProvider locationProvider,
  NetworkMapViewportRepository? viewportRepository,
  RealtimeRepository? realtimeRepository,
}) async {
  await tester.pumpWidget(
    buildEasySubwayTestApp(
      repository: repository,
      reportRepository: FakeFacilityReportRepository(),
      routeRepository: FakeRouteSearchRepository(),
      favoriteRepository: FakeFavoriteStationRepository(),
      locationProvider: locationProvider,
      networkMapViewportRepository: viewportRepository,
      realtimeRepository: realtimeRepository,
      initialOnboardingState: _completedOnboardingState(),
    ),
  );
  await tester.pumpAndSettle();
}

// #2109: 노선도 역 액션 메뉴가 다크 텍스트 팝오버에서 부채꼴(방사형) 팬 메뉴로
// 교체됐다. 라벨은 CustomPaint로 그려져 find.text로는 잡히지 않으므로, 각 섹터의
// 접근성 Semantics 라벨로 존재를 확인하고, 히트테스트는 섹터 아이콘 중심(design
// 좌표)에 menu 스케일(260/700)을 곱한 지점을 tapAt으로 눌러 활성화한다.
const _fanOriginLabel = '출발역으로 설정';
const _fanWaypointLabel = '경유지로 추가';
const _fanDestinationLabel = '도착역으로 설정';
const _fanCloseLabel = '메뉴 닫기';

/// 팬 메뉴의 특정 섹터를 접근성 Semantics onTap 액션으로 활성화한다.
/// 섹터 라벨(투명 버튼)에 걸린 onTap을 직접 트리거하므로, 노선도 상단바 등
/// 다른 오버레이가 좌표를 가로채는 문제 없이 안정적으로 활성화된다.
Future<void> _tapFanMenuSector(WidgetTester tester, String label) async {
  final handle = tester.ensureSemantics();
  await tester.pump();
  // 접근성 tap 액션으로 직접 활성화한다: 노선도 상단바 등 다른 오버레이가 좌표를
  // 가로채는 문제 없이 섹터를 누른 효과를 낸다(섹터 Semantics onTap → onAction).
  tester.semantics.tap(find.semantics.byLabel(label));
  handle.dispose();
  await tester.pump();
}

/// 역 노드를 접근성 Semantics onTap 액션으로 탭한다(_StationHitTarget의
/// Semantics(button: true, label: station.displayName, onTap: ...)를 사용).
/// draft pin이 지정된 역은 pin이 노드 바로 위에 겹쳐 그려져 좌표 tap(tester.tap)이
/// pin의 Material에 가로채이므로, 역 재탭 시나리오는 좌표 대신 이 경로를 쓴다.
Future<void> _tapStationByLabel(WidgetTester tester, String label) async {
  final handle = tester.ensureSemantics();
  await tester.pump();
  tester.semantics.tap(find.semantics.byLabel(label));
  handle.dispose();
  await tester.pump();
}

/// #2109: 풀페이지 검색 결과 탭이 focusStationRequestId(null→역 id)를 전이시키는
/// 프로덕션 시퀀스를 모사하기 위한 host. NetworkMapScreen을 마운트한 뒤 setState로
/// id를 채워 부모 didUpdateWidget → 팬 메뉴 채널 수렴 경로를 태운다.
class _FocusRequestHost extends StatefulWidget {
  const _FocusRequestHost({
    required this.repository,
    required this.routeDraftController,
    required this.onHandled,
  });

  final NetworkMapRepository repository;
  final RouteDraftController routeDraftController;
  final VoidCallback onHandled;

  @override
  State<_FocusRequestHost> createState() => _FocusRequestHostState();
}

class _FocusRequestHostState extends State<_FocusRequestHost> {
  String? _requestId;

  void requestFocus(String stationId) {
    setState(() => _requestId = stationId);
  }

  @override
  Widget build(BuildContext context) {
    return NetworkMapScreen(
      repository: widget.repository,
      routeDraftController: widget.routeDraftController,
      onOpenStationSearch: (_) {},
      focusStationRequestId: _requestId,
      onFocusStationRequestHandled: () {
        widget.onHandled();
        setState(() => _requestId = null);
      },
    );
  }
}

/// #1933 요구 3: 별도 길찾기 폼 페이지를 없앴다. 노선도 홈에서 결과 화면에 이르는
/// 정당한 흐름은 "역 탭 팝오버로 출발·도착 지정 → 자동 결과"뿐이다. 이 헬퍼는 기본
/// 노선도(상록수/사당)에서 그 흐름을 그대로 태워 결과 탭까지 데려간다.
Future<void> _openRouteSearchScreen(
  WidgetTester tester, {
  String originStationKey = 'networkMapStation-sangnoksu-seoul-4',
  String destinationStationKey = 'networkMapStation-sadang-seoul-2',
}) async {
  // 노선도(지도·역)가 렌더될 때까지 기다린 뒤 역을 탭한다.
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(originStationKey)));
  await tester.pumpAndSettle();
  await _tapFanMenuSector(tester, _fanOriginLabel);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(destinationStationKey)));
  await tester.pumpAndSettle();
  await _tapFanMenuSector(tester, _fanDestinationLabel);
  // 출발·도착이 모두 차면 셸이 자동으로 결과 타임라인 탭으로 전환한다. 전환은
  // 120ms 디바운스 Timer로 예약되므로 프레임만 도는 pumpAndSettle 전에 Timer를
  // 흘려보낸다.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Future<void> _openSavedItemsScreen(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('networkMapMenuButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('networkMapMenuSavedButton')));
  await tester.pumpAndSettle();
}

/// #1933: 홈 노선도 상단바의 인플레이스 검색은 결과 탭 시 역을 지도에서 포커스하고
/// 하단 팝오버를 띄운다(상세를 열지 않는다). 역 상세/시설 화면을 열려면 좌측 메뉴의
/// "역 검색"으로 탭 진입형 [StationSearchScreen]을 연다(정상 탭 = 상세 열기 유지).
Future<void> _openStationSearchScreenViaMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('networkMapMenuButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('networkMapMenuStationSearchButton')));
  await tester.pumpAndSettle();
}

Future<void> _openSettingsScreen(WidgetTester tester) async {
  final homeContext = tester.element(find.byType(HomeScreen));
  final home = tester.widget<HomeScreen>(find.byType(HomeScreen));
  final currentPreset =
      mobilityPresetFromRepresentativeMobilityType(home.initialMobilityType) ??
      MobilityPreset.standard;
  unawaited(
    Navigator.of(homeContext).push(
      MaterialPageRoute<void>(
        builder: (_) => AppSettingsScreen(
          currentPreset: currentPreset,
          viewPreferences: home.viewPreferences,
          notificationRepository: home.notificationRepository,
          notificationPermissionProvider: home.notificationPermissionProvider,
          onViewPreferencesChanged: home.onViewPreferencesChanged,
          onOpenMobilityProfile: () async {
            final selected = await showMobilityPresetSheet(
              homeContext,
              current: currentPreset,
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
          onOpenServiceInfo: () {
            Navigator.of(homeContext).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    ServiceInfoScreen(accessInfo: home.supportAccessInfo),
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

  // #1951: 노선도 canvas와 데이터 출처 화면이 같은 datapack manifest asset을 각각
  // rootBundle로 로드한다. rootBundle의 문자열 캐시는 테스트 간에 유지되므로, 앞선
  // 테스트에서 manifest가 캐시에 적재되면 뒤 테스트의 FutureBuilder 완료 스케줄이
  // 바뀌어(캐시 히트 시 microtask로 즉시 완료) 순서 의존 회귀가 생긴다. 각 테스트가
  // cold 캐시에서 시작하도록 rootBundle과 모듈 attribution 캐시를 초기화한다.
  tearDown(() {
    rootBundle.clear();
    resetNetworkMapAttributionCacheForTest();
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.text('어떻게 걸으세요?'), findsNothing);
    expect(find.byKey(const Key('bundledDataPackStaleBanner')), findsNothing);
  });

  testWidgets('만료된 bundled datapack은 홈에 stale 안내를 표시한다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        bundledDataPackFreshness: BundledDataPackFreshness(
          status: 'STALE',
          freshnessExpiresAt: DateTime.now().toUtc().subtract(
            const Duration(seconds: 1),
          ),
          reasonCode: 'BUNDLED_PACK_EXPIRED',
          labelKo: BundledDataPackFreshness.staleLabelKo,
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bundledDataPackStaleBanner')), findsOneWidget);
    expect(find.text('저장된 데이터 기준 · 갱신 필요'), findsOneWidget);
    final sharedSafeArea = find
        .ancestor(
          of: find.byKey(const Key('bundledDataPackStaleBanner')),
          matching: find.byType(SafeArea),
        )
        .first;
    expect(
      find.descendant(
        of: sharedSafeArea,
        matching: find.byKey(const Key('networkMapScreen')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('bundled datapack은 앱 실행 중 expiry 경계를 지나면 stale 안내를 표시한다', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        bundledDataPackFreshness: BundledDataPackFreshness(
          status: 'FRESH',
          freshnessExpiresAt: DateTime.now().toUtc().add(
            const Duration(milliseconds: 100),
          ),
          reasonCode: 'NONE',
          labelKo: '',
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    expect(find.byKey(const Key('bundledDataPackStaleBanner')), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byKey(const Key('bundledDataPackStaleBanner')), findsOneWidget);
  });

  testWidgets('stale bundled datapack 안내는 경로 검색 탭에서도 유지된다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        bundledDataPackFreshness: BundledDataPackFreshness(
          status: 'STALE',
          freshnessExpiresAt: DateTime.now().toUtc().subtract(
            const Duration(seconds: 1),
          ),
          reasonCode: 'BUNDLED_PACK_EXPIRED',
          labelKo: BundledDataPackFreshness.staleLabelKo,
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openRouteSearchScreen(tester);

    expect(find.byType(RouteSearchScreen), findsOneWidget);
    expect(find.byKey(const Key('bundledDataPackStaleBanner')), findsOneWidget);
  });

  testWidgets('기본 앱은 저장소가 없어도 노선도 중심 첫 화면을 보여준다', (tester) async {
    final reportedErrors = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
    // #2068: 노선도는 일반/급행 선택 없는 단일 통합 지도라 운행종별 토글이 없다.
    // #2099 DoD: 노선도에 일반/급행 선택 control과 별도 상태는 0건이다. 일반/급행은
    // 선택 UI가 아니라 실제 운행 정보이므로 노선도 뷰 토글을 두지 않는다.
    expect(
      find.byKey(const Key('networkMapServicePatternToggle')),
      findsNothing,
    );
    expect(find.widgetWithText(InkWell, '급행'), findsNothing);
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
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(
          preset: MobilityPreset.stepFree,
        ),
      ),
    );

    // #1933 요구 3: 노선도 팝오버로 출발·도착을 정하면 온보딩에서 고른 이동 조건
    // (휠체어)이 자동 검색에 그대로 반영된다.
    await _openRouteSearchScreen(tester);

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
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    // #1936: 중간 소개 화면 제거 — 시작 → 프리셋 '이대로 시작' → 권한 '나중에 설정'.
    await tester.tap(find.byKey(const Key('startScreenStartButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingPermissionSkipButton')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 1);
    expect(onboardingStore.savedResult, isNull);
    // 저장 실패 시 홈으로 넘어가지 않고 온보딩(권한 단계)에 머문다.
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.text('위치는 나중에도 켤 수 있어요'), findsOneWidget);
    expect(find.text('설정을 저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('온보딩 보기 설정은 완료 뒤 홈 UI에 적용된다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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

    // 1단계: 이동 방식 프리셋 (#1936: 진행은 점 2개로만 표시, 텍스트 카운터 없음)
    expect(find.text('어떻게 걸으세요?'), findsOneWidget);
    expect(find.text('이대로 시작'), findsOneWidget);
    expect(find.text('1 / 2'), findsNothing);
    await tester.tap(find.byKey(const Key('mobilityPresetRow-slow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();

    // 2단계: 권한 — 조건 확인 화면과 옛 CTA는 없다. 알림 provider 미주입이라
    // 알림 요청은 숨고 위치만 남는다(#1579).
    expect(find.text('적용할 조건을 확인하세요'), findsNothing);
    expect(find.text('위치는 나중에도 켤 수 있어요'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
    expect(find.text('선택한 기능 설정하고 시작'), findsNothing);
    expect(find.text('나중에 설정'), findsOneWidget);

    // 뒤로가기 → 프리셋 단계로 복귀.
    await tester.tap(find.byTooltip('이전 단계'));
    await tester.pumpAndSettle();
    expect(find.text('어떻게 걸으세요?'), findsOneWidget);
  });

  testWidgets('노선도 첫 화면은 핵심 이동 행동과 보조 행동을 지도 위에 제공한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
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
      // #1933 요구 3: 별도 길찾기 폼 페이지를 없앴으므로 좌측 메뉴 "길찾기" 항목은
      // 제거됐다. 역 검색은 그대로 남는다.
      expect(
        find.byKey(const Key('networkMapMenuRouteSearchButton')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('networkMapMenuStationSearchButton')),
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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

  testWidgets('홈 검색바는 idle에서 active로 전환돼도 시각 박스 높이가 그대로 유지된다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    final idleHeight = tester
        .getSize(find.byKey(const Key('heroStationSearchButton')))
        .height;

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();

    final activeHeight = tester
        .getSize(find.byKey(const Key('heroStationSearchInputBox')))
        .height;

    expect(idleHeight, 46.0);
    expect(activeHeight, 46.0);
    expect(find.text('역 이름을 입력해 주세요'), findsOneWidget);

    // hint는 부유 라벨이 아니라 박스 내부에 렌더돼야 한다(idle의 '지하철역 검색'
    // 텍스트처럼 박스 안 중앙 부근). 박스 상단 테두리 위로 떠오르는 부유 라벨
    // 회귀를 막는 것이 핵심 계약이다. #2082 실기기 재작업으로 중앙 정렬을
    // 고유 높이 필드 + Center 위젯으로 얻으면서, FlutterTest 테스트 폰트에서는 hint
    // 중심이 박스 중심에서 십수 px 벗어날 수 있으나(실기기 Noto Sans KR에서는
    // 오프셋 0으로 정합 — docs/2082-qa 픽셀 판독이 정본), hint가 박스 세로 범위
    // 안에 온전히 들어오는지(=부유 라벨이 아님)를 폰트 메트릭 독립적으로 검증한다.
    final activeBoxRect = tester.getRect(
      find.byKey(const Key('heroStationSearchInputBox')),
    );
    final hintCenterDy = tester.getCenter(find.text('역 이름을 입력해 주세요')).dy;
    expect(hintCenterDy, greaterThan(activeBoxRect.top));
    expect(hintCenterDy, lessThan(activeBoxRect.bottom));

    // 검색어를 입력하면 지우기 버튼이 나타나고, 시각 박스(46px)와 별개로
    // 실제 렌더 크기가 접근성 최소 탭 타깃(48x48) 이상이어야 한다. 버튼이
    // 나타나도 시각 박스 높이는 46px 그대로 유지돼야 한다.
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();

    // 입력한 편집 텍스트는 시각 박스 안에 렌더돼야 한다. #2082 실기기 재작업:
    // 중앙 정렬을 고유 높이 필드 + Center 위젯으로 얻으며, 실기기(Noto Sans KR)에서
    // 입력 글자·캐럿이 시각 박스 중앙에 오프셋 0으로 정합함을 픽셀 판독으로
    // 확인했다(docs/2082-qa, 정본). FlutterTest 테스트 폰트에서는 InputDecorator
    // 중앙 정렬 오차로 입력 글자 중심이 박스 중심에서 십수 px 벗어날 수 있으므로,
    // 여기서는 입력 글자가 박스 세로 범위 안에 온전히 들어오는지(=상단으로 뜨지
    // 않음)를 폰트 메트릭 독립적으로 계약으로 잡는다.
    final editBoxRect = tester.getRect(
      find.byKey(const Key('heroStationSearchInputBox')),
    );
    final editTextCenterDy = tester.getCenter(find.text('상록수')).dy;
    expect(editTextCenterDy, greaterThan(editBoxRect.top));
    expect(editTextCenterDy, lessThan(editBoxRect.bottom));

    // 세로 중앙 정렬은 레이아웃(Center)으로 달성한다. 편집 텍스트가 여러 줄
    // 필드로 렌더되면 실기기에서 입력 텍스트와 IME 조합 밑줄이 박스 상단에
    // 붙는 회귀가 발생하므로, 단일 줄 필드(maxLines == 1, expands == false)를
    // 계약으로 고정한다.
    final searchField = tester.widget<TextField>(
      find.byKey(const Key('stationSearchInput')),
    );
    expect(searchField.maxLines, 1);
    expect(searchField.expands, isFalse);

    // #2082 재작업: 입력 필드는 고유 높이(글자 줄)로 두고 Center로 시각 박스
    // 중앙에 정렬하되, 바깥 터치타겟 SizedBox(56)와 MergeSemantics로 병합해 입력
    // 필드의 탭 타깃 semantics가 접근성 최소치(≥48)를 유지한다. 그 병합 탭 타깃
    // (=필드를 감싼 터치타겟 SizedBox) 높이가 48 이상인지 계약으로 고정한다.
    final inputTapTarget = find
        .ancestor(
          of: find.byKey(const Key('stationSearchInput')),
          matching: find.byType(SizedBox),
        )
        .first;
    expect(tester.getSize(inputTapTarget).height, greaterThanOrEqualTo(48.0));

    final clearButtonSize = tester.getSize(
      find.widgetWithIcon(IconButton, Icons.close),
    );
    expect(clearButtonSize.width, greaterThanOrEqualTo(48.0));
    expect(clearButtonSize.height, greaterThanOrEqualTo(48.0));
    expect(
      tester.getSize(find.byKey(const Key('heroStationSearchInputBox'))).height,
      46.0,
    );
  });

  testWidgets('#2090 공용 검색 필드는 시스템 글자 배율에 비례해 입력 텍스트가 커지고 잘리지 않는다', (
    tester,
  ) async {
    // #2090: 이전 구현은 안쪽 고정 높이(SizedBox 48) tight constraint 탓에
    // textScaler 1.0/2.0/3.0에서 입력 텍스트 렌더 높이가 18px로 고정돼(WCAG
    // 1.4.4 위반) 배율을 키워도 글자가 커지지 않았다. 배율별로 입력 텍스트
    // 렌더 높이가 비례해 커지고 예외·잘림이 없음을 고정한다.
    final measured = <double, double>{};
    for (final scale in const [1.0, 2.0, 3.0]) {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  child: EasySubwaySearchField(
                    controller: controller,
                    hintText: '역 이름을 입력해 주세요',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.pumpAndSettle();

      // 렌더 중 오버플로 등 예외가 없어야 한다(잘림 금지 우선).
      expect(tester.takeException(), isNull, reason: 'scale $scale');

      // 입력 텍스트 렌더 높이가 배율에 비례해 커진다(더 이상 18px 고정 아님).
      final textHeight = tester.getSize(find.text('상록수')).height;
      measured[scale] = textHeight;
    }

    // 배율이 커질수록 입력 텍스트 렌더 높이가 엄격히 증가한다.
    expect(measured[2.0]!, greaterThan(measured[1.0]!));
    expect(measured[3.0]!, greaterThan(measured[2.0]!));
    // 배율에 대략 비례한다(2.0에서 최소 1.5배 이상 커짐 — 고정 18px 회귀 방지).
    expect(measured[2.0]!, greaterThan(measured[1.0]! * 1.5));
  });

  testWidgets('#2003 상단 내비게이션(검색바·메뉴·힌트 텍스트)이 확대된 안 B 치수를 갖는다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    // idle 검색바의 시각 박스 높이는 46px이어야 한다(#2003 안 B).
    expect(
      tester.getSize(find.byKey(const Key('heroStationSearchButton'))).height,
      46.0,
    );

    // idle 검색바의 힌트 텍스트('지하철역 검색') 폰트 크기는 17이어야 한다.
    final hintText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('heroStationSearchButton')),
        matching: find.text('지하철역 검색'),
      ),
    );
    expect(hintText.style?.fontSize, 17);

    // idle 검색바의 검색 아이콘 크기는 22여야 한다.
    final idleSearchIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('heroStationSearchButton')),
        matching: find.byIcon(Icons.search),
      ),
    );
    expect(idleSearchIcon.size, 22.0);

    // 상단바 햄버거 메뉴 아이콘 크기는 26이어야 한다.
    final menuIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('networkMapMenuButton')),
        matching: find.byIcon(Icons.menu),
      ),
    );
    expect(menuIcon.size, 26.0);

    // in-place 편집 검색 필드로 전환해도 시각 박스 높이가 idle과 동일하게
    // 유지돼야 한다(박스 점프 없음, #1933 계약 확장).
    final idleHeight = tester
        .getSize(find.byKey(const Key('heroStationSearchButton')))
        .height;

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();

    final activeHeight = tester
        .getSize(find.byKey(const Key('heroStationSearchInputBox')))
        .height;
    expect(activeHeight, idleHeight);

    // in-place 입력 TextField의 스타일을 검증한다(폰트 크기 17, w600). #2082:
    // 입력 style은 hint style과 동일 glyph 메트릭을 갖도록 height를 지정하지
    // 않는다(height 1.2를 주면 hint와 편집 텍스트 glyph 중심이 어긋나 편집
    // 텍스트가 시각 박스 중앙보다 위로 뜬다).
    final activeField = tester.widget<TextField>(
      find.byKey(const Key('stationSearchInput')),
    );
    expect(activeField.style?.fontSize, 17);
    expect(activeField.style?.height, isNull);
    expect(activeField.style?.fontWeight, FontWeight.w600);

    // 검색 모드에서 뒤로가기 아이콘 크기는 26이어야 한다(메뉴 아이콘과 같은
    // 슬롯이라 전환 시 크기 점프를 없애는 정합, #2003).
    final backIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('networkMapSearchBackButton')),
        matching: find.byIcon(Icons.arrow_back),
      ),
    );
    expect(backIcon.size, 26.0);
  });

  testWidgets('노선도 검색 중 타이핑은 지도 chrome을 재빌드하지 않는다', (tester) async {
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    // 검색 모드로 진입한다(모드 전환은 부모 setState로 chrome이 한 번
    // 재빌드되므로, 진입 직후를 기준선으로 삼는다).
    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();

    final baseline = debugNetworkMapChromeBuildCount;

    // 한 글자씩 타이핑하며 매 키 입력마다 pump한다. 지도 chrome(상단바+지도
    // canvas를 감싸는 서브트리)은 키 입력 때문에 재빌드되면 안 된다. 키 입력
    // 회귀 격리(#1915): 재빌드가 검색 필드+결과 서브트리로 국한돼야 한다.
    for (final text in const ['ㅅ', '사', '상', '상ㄹ', '상록', '상록수']) {
      await tester.enterText(find.byKey(const Key('stationSearchInput')), text);
      await tester.pump();
    }

    expect(
      debugNetworkMapChromeBuildCount,
      baseline,
      reason: '키 입력마다 지도 chrome이 재빌드되면 입력 지연이 발생한다.',
    );

    // 디바운스가 흘러 결과가 뜨는지도 확인해 회귀 격리가 기능을 깨지 않았음을
    // 보장한다.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('상록수역'), findsOneWidget);
  });

  testWidgets('알림함 시설 상태는 쉬운 안내와 할 일을 함께 보여준다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
    expect(find.byType(RouteMapBasemapView), findsOneWidget);

    expect(find.byKey(const Key('networkMapSurface')), findsOneWidget);
    expect(find.byType(RouteMapBasemapView), findsOneWidget);
  });

  testWidgets('홈 shell 경로 상세 뒤로가기는 결과 목록으로 돌아간다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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

    // #1933 요구 3: 노선도 역 탭(팝오버 출발/도착)으로 출발·도착을 정하면 자동으로
    // 결과 타임라인 화면에 도달한다(별도 폼·제출 버튼 없음).
    await _openRouteSearchScreen(tester);
    await _openFirstRouteResultDetail(tester);
    expect(find.text('이동 순서'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    // #1933 D: 결과 목록은 이동 순서 타임라인을 인라인으로 유지한다.
    expect(find.text('이동 순서'), findsOneWidget);
    expect(find.byKey(const Key('homeBottomNavigationBar')), findsNothing);
  });

  testWidgets('홈 shell 즐겨찾기 경로 다시 찾기는 저장된 이동 조건을 유지한다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: FakeFavoriteRouteRepository(
          favorites: [_favoriteRoute(mobilityType: 'WHEELCHAIR')],
        ),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(
          preset: MobilityPreset.slow,
        ),
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

  testWidgets('노선도에서 출발·도착을 정하면 길찾기 결과 화면으로 전환한다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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

  testWidgets('결과 화면에서 뒤로가기로 홈에 오면 상단바가 빈 검색바로 복귀한다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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

    // 결과 화면에서 시스템 뒤로가기로 홈으로 복귀하면, owner 요구사항: 출발·도착
    // draft가 완전히 초기화되어 상단바가 빈 검색바 상태로 돌아와야 한다(둘 다
    // 채워진 채 홈 지도에 머무는 상태가 있으면 안 된다).
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapRouteDraftOverlay')), findsNothing);
  });

  testWidgets('노선도 메뉴에는 자료 제공 정보를 노출하지 않는다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
    expect(find.text('자료 제공 정보'), findsNothing);
    expect(
      find.byKey(const Key('networkMapMenuDataSourcesButton')),
      findsNothing,
    );
  });

  testWidgets('노선도 지역 메뉴는 선택한 지역으로 지도를 다시 불러온다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['테스트권', '부산'],
    );
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byType(RouteMapBasemapView), findsOneWidget);
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

  testWidgets('노선도 지역 메뉴는 흰 표면·구분선·화면 우측 밀착으로 뜬다 (#1933)', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['테스트권', '부산'],
    );
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('테스트권'));
    await tester.pumpAndSettle();

    // 구분선: 지역 2개 → 행 사이 구분선은 정확히 1개(마지막 행 뒤에는 없음).
    final dividerFinder = find.byKey(const Key('networkMapRegionMenuDivider'));
    expect(dividerFinder, findsOneWidget);
    // 인셋 구분선: 색은 line, 두께 1, 좌우 16 인셋(full-width 절단형 아님).
    final dividerLine = tester.widget<ColoredBox>(
      find.descendant(of: dividerFinder, matching: find.byType(ColoredBox)),
    );
    expect(dividerLine.color, EasySubwayAccessibleColors.line);
    final dividerLineSize = tester.getSize(
      find.descendant(of: dividerFinder, matching: find.byType(ColoredBox)),
    );
    expect(dividerLineSize.height, 1);
    final dividerBoxWidth = tester.getSize(dividerFinder).width;
    // 인셋(좌16+우16=32)만큼 컬러 라인이 구분선 박스보다 좁아야 한다.
    expect(dividerLineSize.width, closeTo(dividerBoxWidth - 32, 0.5));

    // 메뉴 패널의 Material은 '부산' 텍스트의 조상 중 실제로 color/elevation/shape가
    // 세팅된 것(내부 wrapper Material은 color가 null이라 구분해야 함).
    final menuMaterials = find.ancestor(
      of: find.text('부산'),
      matching: find.byType(Material),
    );
    final menuMaterialWidgets = tester
        .widgetList<Material>(menuMaterials)
        .toList();
    final menuMaterialIndex = menuMaterialWidgets.indexWhere(
      (material) => material.color != null,
    );
    final menuMaterialElement = menuMaterialWidgets[menuMaterialIndex];
    final menuRect = tester.getRect(menuMaterials.at(menuMaterialIndex));

    // 메뉴 우측이 화면 우측 끝에 완전 밀착되어 노선도 삐짐이 없어야 한다 —
    // right=0으로 설정하여 overlay 우측과 일치시킨다.
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(menuRect.right, closeTo(screenWidth, 1.0));

    // 표면 스타일: 흰 표면, elevation 0, 라운드 8(좌측만) + line 색 테두리.
    expect(menuMaterialElement.elevation, 0);
    expect(menuMaterialElement.color, EasySubwayAccessibleColors.surface);
    final shape = menuMaterialElement.shape as RoundedRectangleBorder;
    expect(
      shape.borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(8),
        bottomLeft: Radius.circular(8),
        topRight: Radius.zero,
        bottomRight: Radius.zero,
      ),
    );
    expect((shape.side.color), EasySubwayAccessibleColors.line);

    // 행 높이 48 이상 + 콘텐츠 자연폭(강제 최소폭 없이 극단 협폭만 방지).
    final rowSize = tester.getSize(
      find.byKey(const ValueKey('networkMapRegionMenuRow_부산')),
    );
    expect(rowSize.height, greaterThanOrEqualTo(48));
    expect(menuRect.width, greaterThanOrEqualTo(120));

    // 딤 스크림: barrierColor가 투명이 아니라 앱 다이얼로그 관례값과 동일한
    // 딤이어야 한다(참고 07에서 차용하는 것은 주변을 어둡게 하는 스크림뿐).
    final dimBarrier = find.byWidgetPredicate(
      (w) => w is ModalBarrier && w.color == const Color(0x99000000),
    );
    expect(dimBarrier, findsOneWidget);

    // 타이포: 기본 행은 16sp·w500, 선택 행(초기 선택=테스트권)만 w600.
    // 메뉴 행 텍스트로 스코프한다(트리거 라벨과 구분).
    final selectedRow = find.byKey(
      const ValueKey('networkMapRegionMenuRow_테스트권'),
    );
    final busanRow = find.byKey(const ValueKey('networkMapRegionMenuRow_부산'));
    final selectedText = tester.widget<Text>(
      find.descendant(of: selectedRow, matching: find.text('테스트권')),
    );
    expect(selectedText.style?.fontSize, 16);
    expect(selectedText.style?.fontWeight, FontWeight.w600);
    final busanText = tester.widget<Text>(
      find.descendant(of: busanRow, matching: find.text('부산')),
    );
    expect(busanText.style?.fontSize, 16);
    expect(busanText.style?.fontWeight, FontWeight.w500);

    // ✓ 트레일링: 선택 행에만 체크가 있고, 라벨 오른쪽(트레일링)에 위치한다.
    final checkFinder = find.descendant(
      of: selectedRow,
      matching: find.byIcon(Icons.check),
    );
    expect(checkFinder, findsOneWidget);
    expect(
      find.descendant(of: busanRow, matching: find.byIcon(Icons.check)),
      findsNothing,
    );
    // 체크는 라벨보다 오른쪽에 있어야 한다(트레일링 배치).
    final labelRight = tester
        .getRect(find.descendant(of: selectedRow, matching: find.text('테스트권')))
        .right;
    final checkLeft = tester.getRect(checkFinder).left;
    expect(checkLeft, greaterThanOrEqualTo(labelRight));

    await tester.tap(find.text('부산'));
    await tester.pumpAndSettle();
  });

  testWidgets('#2082 저장된 지역(부산)으로 로드된 뒤 역 검색을 열면 지역 표시가 부산을 따른다', (
    tester,
  ) async {
    // 회귀 방지: _currentRegionDisplayName이 _selectedRegion(세션 중 지역
    // 선택기를 조작해야만 채워지는 상태)에만 의존하면, 저장된 지역이 부산인
    // 사용자가 재시작 후 지역 선택기를 건드리지 않고 검색을 열 때 '수도권'이
    // 잘못 표시된다. getNetworkMap(region: null) 호출이 저장된 지역(부산)을
    // 반환하도록 페이크를 구성해, 로드 완료 후 지역 표시가 실제 로드된 지역을
    // 따르는지 검증한다.
    String? openedRegionLabel;
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(
            networkMapRegionNames: const ['부산'],
          ),
          routeDraftController: RouteDraftController(),
          onOpenStationSearch: (regionLabel) {
            openedRegionLabel = regionLabel;
          },
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

    expect(openedRegionLabel, '부산');
  });

  testWidgets('노선도 로드 실패는 재시도만 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(
            networkMapError: StateError('map failed'),
          ),
          routeDraftController: RouteDraftController(),
          onOpenStationSearch: (_) {},
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
      buildEasySubwayTestApp(
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
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
    expect(find.bySemanticsLabel(_fanDestinationLabel), findsOneWidget);
  });

  testWidgets('#2200 노선도 역 탭은 팬 메뉴와 함께 하단 역 정보 패널을 연다', (tester) async {
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();

    // 팬 메뉴는 그대로 뜬다(기존 동작 보존).
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);

    // 하단 역 정보 패널이 탭한 역 기준으로 함께 열린다.
    final panel = find.byKey(const Key('networkMapNearbyStationPanel'));
    expect(panel, findsOneWidget);
    final track = find.byKey(const Key('nearbyStationLineBarTrack'));
    expect(track, findsOneWidget);
    final trackSize = tester.getSize(track);
    expect(trackSize.width, greaterThan(0));
    expect(trackSize.height, greaterThan(0));
    expect(
      find.descendant(of: panel, matching: find.text('상록수')),
      findsOneWidget,
    );
  });

  testWidgets('#2200 검색 결과가 없는 역 탭은 크래시 없이 팬 메뉴만 유지한다', (tester) async {
    // 탭한 역을 StationSearchResult로 해석하지 못하면(데이터 없음) 하단 패널을
    // 열지 않고 기존 팬 메뉴 동작을 그대로 유지한다.
    final repository = FakeStationSearchRepository();
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
    expect(find.byKey(const Key('networkMapNearbyStationPanel')), findsNothing);
  });

  testWidgets(
    '#2109 검색 채널(focusStationRequestId)로 열린 팬 메뉴도 지도 탭과 같은 앵커·패닝 경로를 탄다',
    (tester) async {
      // 회귀 방지: 검색 결과 탭 → focusStationRequestId(null→역 id) 소비 → 팬
      // 메뉴 채널로 수렴할 때, 지도 탭(_selectStation)과 동일하게 팬 메뉴가
      // 뜨고 카메라 anti-clip 패닝 콜백
      // (_NetworkMapCanvas.didUpdateWidget)이 예외 없이 도는지 검증한다. 이전엔
      // 패닝이 _selectStation 경로에서만 예약돼 검색 채널로 열린 메뉴는 경계에서
      // 잘린 채 남을 수 있었다. 프로덕션과 같이 마운트 후 prop이 전이되도록 host
      // StatefulWidget으로 감싸 setState로 id를 채운다.
      final controller = RouteDraftController();
      var handled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: _FocusRequestHost(
            repository: FakeStationSearchRepository(),
            routeDraftController: controller,
            onHandled: () => handled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 초기엔 요청 없음 → 팬 메뉴 미표시.
      expect(handled, isFalse);
      expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);

      // 검색 결과 탭을 모사: focusStationRequestId를 역 id로 전이.
      final hostState = tester.state<_FocusRequestHostState>(
        find.byType(_FocusRequestHost),
      );
      hostState.requestFocus('station-sangnoksu');
      await tester.pumpAndSettle();

      // 검색 채널 요청이 소비되고(부모 통지) 팬 메뉴가 떴다.
      expect(handled, isTrue);
      expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
      expect(find.bySemanticsLabel('상록수역 상세 보기'), findsNothing);
      expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
    },
  );

  testWidgets('노선도 팝오버 출발 선택은 상단바를 출발/도착 입력으로 변신시키고 지우기로 검색바로 돌아온다', (
    tester,
  ) async {
    // #1933 요구 2: 예전엔 검색바 "아래" 별도 카드가 떴다. 이제는 아래 카드 없이
    // 상단바 자체가 출발/도착 2줄 입력으로 변신한다. 이 테스트는 (1) 빈 draft면
    // 상단바가 검색바이고, (2) 출발이 차면 상단바가 draft 입력으로 바뀌며 검색바가
    // 사라지고, (3) 다 비우면 다시 검색바로 돌아옴을 검증한다.
    final routeDraftController = RouteDraftController();
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // draft가 비어 있으면 상단바는 검색바이고 draft 변신은 뜨지 않는다.
    expect(find.byKey(const Key('networkMapRouteDraftOverlay')), findsNothing);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);

    // 역 탭 → 팝오버 → "출발" 선택 → 상단바가 출발/도착 입력으로 변신(G1).
    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();
    await _tapFanMenuSector(tester, _fanOriginLabel);
    await tester.pumpAndSettle();

    expect(routeDraftController.draft.origin?.nameKo, '상록수');
    expect(
      find.byKey(const Key('networkMapRouteDraftOverlay')),
      findsOneWidget,
    );
    // 변신했으므로 검색바는 더 이상 상단바에 없다(아래 별도 카드가 아니라 변신).
    expect(find.byKey(const Key('stationSearchButton')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftOriginRow')),
        matching: find.text('상록수역'),
      ),
      findsOneWidget,
    );
    // #1985: draft 빈 행 placeholder는 '출발역'/'경유역'/'도착역'으로 낭독·표시한다.
    expect(find.text('도착역'), findsOneWidget);
    // owner spec: 라벨 프리픽스 텍스트와 노드 점 커넥터 컬럼은 제거되고, 두 개의
    // 무채색 채움 필드만 남는다.
    expect(find.text('출발역을 탭하거나 검색'), findsNothing);
    expect(find.text('도착역을 탭하거나 검색'), findsNothing);
    expect(
      find.byKey(const Key('networkMapRouteDraftOriginRow')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('networkMapRouteDraftDestinationRow')),
      findsOneWidget,
    );
    // 스왑(⇅) 어포던스가 상단바에 존재한다.
    expect(find.byKey(const Key('networkMapRouteDraftSwap')), findsOneWidget);

    // 출발칸 지우기(✕) → draft에서 출발이 지워지고, 도착도 없으니 상단바는 다시
    // 검색바로 돌아온다.
    await tester.tap(find.byKey(const Key('networkMapRouteDraftClearOrigin')));
    await tester.pumpAndSettle();

    expect(routeDraftController.draft.origin, isNull);
    expect(find.byKey(const Key('networkMapRouteDraftOverlay')), findsNothing);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
  });

  testWidgets('#1948 지정한 출발·경유·도착 역 위에 draft 핀이 뜬다', (tester) async {
    final routeDraftController = RouteDraftController();
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 지정 전에는 어떤 draft 핀도 없다.
    expect(find.byKey(const Key('networkMapDraftPin-origin')), findsNothing);
    expect(find.byKey(const Key('networkMapDraftPin-waypoint')), findsNothing);
    expect(
      find.byKey(const Key('networkMapDraftPin-destination')),
      findsNothing,
    );

    // 역 탭 → 팝오버 → "출발" 선택.
    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();
    await _tapFanMenuSector(tester, _fanOriginLabel);
    await tester.pumpAndSettle();

    // 출발 지정 후 출발 핀이 그 역 위에 뜬다.
    expect(find.byKey(const Key('networkMapDraftPin-origin')), findsOneWidget);
    expect(find.bySemanticsLabel('상록수역, 출발 지정됨'), findsOneWidget);

    // 다른 역 탭 → "경유" 선택 → 경유 핀이 뜬다.
    await tester.tap(find.byKey(const Key('networkMapStation-sadang-seoul-2')));
    await tester.pumpAndSettle();
    await _tapFanMenuSector(tester, _fanWaypointLabel);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('networkMapDraftPin-waypoint')),
      findsOneWidget,
    );
  });

  testWidgets('#2109 팬 메뉴에서 출발 설정한 역을 재탭 → 같은 섹터 재탭하면 출발이 해제된다', (
    tester,
  ) async {
    final routeDraftController = RouteDraftController();
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 역 탭 → 팬 메뉴 → "출발" 선택 → draft.origin 설정 + 메뉴 닫힘.
    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();
    await _tapFanMenuSector(tester, _fanOriginLabel);
    await tester.pumpAndSettle();

    expect(routeDraftController.draft.origin?.nameKo, '상록수');
    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);

    // 같은 역을 다시 탭 → 팬 메뉴가 다시 뜬다(출발 섹터는 selected 상태).
    // 주의: 이 시점엔 출발 draft pin이 역 노드 바로 위에 겹쳐 그려져 있어
    // 좌표 tap(tester.tap)이 draft pin의 Material에 가로채인다. 접근성
    // Semantics onTap 경로(_tapStationByLabel)로 직접 활성화한다.
    await _tapStationByLabel(tester, '상록수역');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);

    // 이미 배정된 출발 섹터를 재탭 → 해제(clear)되고 set은 일어나지 않는다.
    await _tapFanMenuSector(tester, _fanOriginLabel);
    await tester.pumpAndSettle();

    expect(routeDraftController.draft.origin, isNull);
  });

  testWidgets('상단 오버레이 출발칸 검색 선택은 지도 탭과 같은 draft로 수렴한다(G4)', (tester) async {
    final routeDraftController = RouteDraftController();
    final pickedSlots = <RouteDraftSlot>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
          // main.dart의 openStationSearchForSlot 대역: 실제 앱에서는 역 검색을 열어
          // 결과 탭 시 같은 controller에 slot을 설정한다. 여기선 그 계약(어떤 slot을
          // 채우려 열렸는지 + 같은 controller로 수렴)만 검증한다.
          onPickStationForSlot: (slot, _) {
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
              case RouteDraftSlot.waypoint:
                routeDraftController.setWaypoint(
                  const RouteDraftStation(id: 'seolleung', nameKo: '선릉'),
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
    await _tapFanMenuSector(tester, _fanOriginLabel);
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

    // 스왑(⇅): 출발/도착이 맞바뀌어 같은 상단바 입력에 반영된다(#1933 요구 2).
    expect(routeDraftController.draft.destination?.nameKo, '잠실');
    await tester.tap(find.byKey(const Key('networkMapRouteDraftSwap')));
    await tester.pumpAndSettle();
    expect(routeDraftController.draft.origin?.nameKo, '잠실');
    expect(routeDraftController.draft.destination?.nameKo, '강남');
  });

  testWidgets('#1948 상단바 경유 추가 진입점 탭은 출발/도착 사이에 경유 행을 넣고 지우면 추가 버튼이 복귀한다', (
    tester,
  ) async {
    final routeDraftController = RouteDraftController();
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
          onPickStationForSlot: (slot, _) {
            switch (slot) {
              case RouteDraftSlot.origin:
                routeDraftController.setOrigin(
                  const RouteDraftStation(id: 'gangnam', nameKo: '강남'),
                );
              case RouteDraftSlot.destination:
                routeDraftController.setDestination(
                  const RouteDraftStation(id: 'jamsil', nameKo: '잠실'),
                );
              case RouteDraftSlot.waypoint:
                routeDraftController.setWaypoint(
                  const RouteDraftStation(id: 'seolleung', nameKo: '선릉'),
                );
            }
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 출발·도착을 채워 상단바를 draft 입력으로 변신시킨다.
    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();
    await _tapFanMenuSector(tester, _fanOriginLabel);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('networkMapRouteDraftPickDestination')),
    );
    await tester.pumpAndSettle();
    expect(routeDraftController.draft.destination?.nameKo, '잠실');

    // 경유가 없을 때는 경유 행이 없고 '경유 추가' 진입점이 보인다.
    expect(
      find.byKey(const Key('networkMapRouteDraftWaypointRow')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('networkMapRouteDraftAddWaypoint')),
      findsOneWidget,
    );

    // 경유 추가 진입점 탭 → waypoint slot으로 검색이 열려 경유가 채워진다.
    await tester.tap(find.byKey(const Key('networkMapRouteDraftAddWaypoint')));
    await tester.pumpAndSettle();
    expect(routeDraftController.draft.waypoint?.nameKo, '선릉');

    // 경유 행이 출발과 도착 사이에 삽입된다.
    expect(
      find.byKey(const Key('networkMapRouteDraftWaypointRow')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftWaypointRow')),
        matching: find.text('선릉역'),
      ),
      findsOneWidget,
    );
    final originDy = tester
        .getTopLeft(find.byKey(const Key('networkMapRouteDraftOriginRow')))
        .dy;
    final waypointDy = tester
        .getTopLeft(find.byKey(const Key('networkMapRouteDraftWaypointRow')))
        .dy;
    final destinationDy = tester
        .getTopLeft(find.byKey(const Key('networkMapRouteDraftDestinationRow')))
        .dy;
    expect(originDy < waypointDy, isTrue);
    expect(waypointDy < destinationDy, isTrue);

    // 경유가 채워졌으므로 추가 버튼은 사라지고 경유 지우기가 보인다.
    expect(
      find.byKey(const Key('networkMapRouteDraftAddWaypoint')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('networkMapRouteDraftClearWaypoint')),
      findsOneWidget,
    );

    // 경유 지우기 → 경유 행이 사라지고 추가 버튼이 복귀한다.
    await tester.tap(
      find.byKey(const Key('networkMapRouteDraftClearWaypoint')),
    );
    await tester.pumpAndSettle();
    expect(routeDraftController.draft.waypoint, isNull);
    expect(
      find.byKey(const Key('networkMapRouteDraftWaypointRow')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('networkMapRouteDraftAddWaypoint')),
      findsOneWidget,
    );
  });

  testWidgets('#1985 2행 출발→도착 드래그는 두 값을 맞바꾼다', (tester) async {
    final routeDraftController = RouteDraftController()
      ..setOrigin(const RouteDraftStation(id: 'gangnam', nameKo: '강남'))
      ..setDestination(const RouteDraftStation(id: 'jamsil', nameKo: '잠실'));
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final originRow = find.byKey(const Key('networkMapRouteDraftOriginRow'));
    final destinationRow = find.byKey(
      const Key('networkMapRouteDraftDestinationRow'),
    );
    final gesture = await tester.startGesture(tester.getCenter(originRow));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(destinationRow));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(routeDraftController.draft.origin?.id, 'jamsil');
    expect(routeDraftController.draft.destination?.id, 'gangnam');
  });

  testWidgets('#1985 3행 경유→출발 드래그는 두 값을 맞바꾸고 도착을 보존한다', (tester) async {
    final routeDraftController = RouteDraftController()
      ..setOrigin(const RouteDraftStation(id: 'gangnam', nameKo: '강남'))
      ..setDestination(const RouteDraftStation(id: 'jamsil', nameKo: '잠실'))
      ..setWaypoint(const RouteDraftStation(id: 'seolleung', nameKo: '선릉'));
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final originRow = find.byKey(const Key('networkMapRouteDraftOriginRow'));
    final waypointRow = find.byKey(
      const Key('networkMapRouteDraftWaypointRow'),
    );
    final gesture = await tester.startGesture(tester.getCenter(waypointRow));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(originRow));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(routeDraftController.draft.origin?.id, 'seolleung');
    expect(routeDraftController.draft.waypoint?.id, 'gangnam');
    expect(routeDraftController.draft.destination?.id, 'jamsil');
  });

  testWidgets('#1985 채워진 행을 빈 행으로 드래그하면 이동한다', (tester) async {
    final routeDraftController = RouteDraftController()
      ..setOrigin(const RouteDraftStation(id: 'gangnam', nameKo: '강남'));
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final originRow = find.byKey(const Key('networkMapRouteDraftOriginRow'));
    final destinationRow = find.byKey(
      const Key('networkMapRouteDraftDestinationRow'),
    );
    final gesture = await tester.startGesture(tester.getCenter(originRow));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(destinationRow));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(routeDraftController.draft.origin, isNull);
    expect(routeDraftController.draft.destination?.id, 'gangnam');
  });

  testWidgets('#1985 빈 행은 드래그를 시작할 수 없고 채워진 행만 드래그 가능하다', (tester) async {
    final routeDraftController = RouteDraftController()
      ..setOrigin(const RouteDraftStation(id: 'gangnam', nameKo: '강남'));
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 빈 도착 행 하위에는 드래그 소스가 없다.
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftDestinationRow')),
        matching: find.byType(LongPressDraggable<RouteDraftSlot>),
      ),
      findsNothing,
    );
    // 채워진 출발 행 하위에는 드래그 소스가 있다.
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftOriginRow')),
        matching: find.byType(LongPressDraggable<RouteDraftSlot>),
      ),
      findsOneWidget,
    );
  });

  testWidgets('#1985 채워진 출발 행은 도착역으로 이동 시맨틱 액션을 제공한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final routeDraftController = RouteDraftController()
      ..setOrigin(const RouteDraftStation(id: 'gangnam', nameKo: '강남'))
      ..setDestination(const RouteDraftStation(id: 'jamsil', nameKo: '잠실'));
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final node = tester.getSemantics(
      find
          .descendant(
            of: find.byKey(const Key('networkMapRouteDraftOriginRow')),
            matching: find.byType(Semantics),
          )
          .first,
    );
    final labels = node
        .getSemanticsData()
        .customSemanticsActionIds!
        .map((id) => CustomSemanticsAction.getAction(id)?.label)
        .toList();
    expect(labels, contains('도착역으로 이동'));
    semanticsHandle.dispose();
  });

  testWidgets('#1985 빈 출발 행 placeholder는 출발역으로 표시된다', (tester) async {
    final routeDraftController = RouteDraftController()
      ..setDestination(const RouteDraftStation(id: 'jamsil', nameKo: '잠실'));
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRouteDraftOriginRow')),
        matching: find.text('출발역'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('#1948 노선도 팝오버는 [출발][경유][도착][닫기] 순서로 경유 탭을 제공한다', (tester) async {
    final routeDraftController = RouteDraftController();
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
          onPickStationForSlot: (slot, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();

    // #2109: 팬 메뉴에 출발/경유/도착/닫기 섹터가 모두 존재한다(접근성 라벨로
    // 확인 — 라벨은 CustomPaint로 그려져 find.text로는 잡히지 않는다).
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
    expect(find.bySemanticsLabel(_fanWaypointLabel), findsOneWidget);
    expect(find.bySemanticsLabel(_fanDestinationLabel), findsOneWidget);
    expect(find.bySemanticsLabel(_fanCloseLabel), findsOneWidget);

    // 방사형 배치에서 출발(좌하)·경유(상중)·도착(우하)의 좌→우 순서가 유지되고,
    // 닫기는 중앙 노치다(경유와 도착 사이 x 범위).
    final originDx = tester
        .getRect(find.bySemanticsLabel(_fanOriginLabel))
        .center
        .dx;
    final waypointDx = tester
        .getRect(find.bySemanticsLabel(_fanWaypointLabel))
        .center
        .dx;
    final destinationDx = tester
        .getRect(find.bySemanticsLabel(_fanDestinationLabel))
        .center
        .dx;
    final closeDx = tester
        .getRect(find.bySemanticsLabel(_fanCloseLabel))
        .center
        .dx;
    expect(originDx < waypointDx, isTrue);
    expect(waypointDx < destinationDx, isTrue);
    expect(originDx < closeDx && closeDx < destinationDx, isTrue);

    // 경유 탭을 누르면 draft.waypoint가 채워진다.
    await _tapFanMenuSector(tester, _fanWaypointLabel);
    await tester.pumpAndSettle();
    expect(routeDraftController.draft.waypoint?.nameKo, '상록수');
  });

  testWidgets('노선도는 노선별 보기 우회 sheet를 노출하지 않는다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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

    // ① 홈 상단 통합 신규 알림 안내 바(disruption이 트리거). 제목이 아니라
    //    통합 안내 문구를 노출한다(#2200 통합형 결정).
    expect(find.byKey(const Key('newNotificationBar')), findsOneWidget);
    expect(find.text('새로운 알림이 있어요'), findsOneWidget);

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

  testWidgets('알림이 없으면 홈 상단 안내 바를 그리지 않는다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        noticeRepository: _FakeNoticeRepository(
          ActiveNoticesResult(
            notices: [
              ServiceNotice(
                id: 'i1',
                scope: NoticeScope.all,
                title: '정보 공지',
                body: '정보성 안내입니다.',
                severity: NoticeSeverity.info,
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

    // info 공지는 disruption이 아니고 알림함 새 항목도 없으므로 바가 없다.
    expect(find.byKey(const Key('newNotificationBar')), findsNothing);
    expect(find.text('새로운 알림이 있어요'), findsNothing);
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
    // [2026-07-11 #1950] 수도권 정본이 오너 자작(self-drawn)으로 전환되어 공개 URL이
    // 없다 — provenance는 리포 내부 경로(internal:) 스킴으로 표기한다. 공식 출처가 있는
    // 지역은 https를 유지한다. 두 스킴 모두 허용한다.
    bool validSourceScheme(String value) =>
        value.startsWith('https://') || value.startsWith('internal:');
    for (final map in maps) {
      final offline = map['offline'] as Map<String, Object?>;
      final path = offline['path'] as String;
      expect(map['source_url'], isA<String>());
      expect(validSourceScheme(map['source_url'] as String), isTrue);
      // [#2068] 하이브리드 바탕층 전환: 오너 자작 SVG를 build-time 컴파일한
      // vector_graphics 바이너리(.vec)를 basemap/으로 번들한다. offline 블록은
      // 이제 실제 번들 .vec를 가리키고 included=true다.
      expect(offline['included'], isTrue);
      expect(path, startsWith('assets/datapacks/metro_map_pack/basemap/'));
      final extension = path.split('.').last.toLowerCase();
      expect(extension, 'vec');
      expect(offline['type'], 'vector-graphics-vec');
      // 가리키는 .vec가 실제로 번들에 존재해야 한다(offline included 계약 강화).
      expect(File(path).existsSync(), isTrue, reason: '$path가 번들에 없다');
      final license = map['license'] as Map<String, Object?>;
      expect(license['name'], isA<String>());
      expect(license['spdx'], isA<String>());
      expect(validSourceScheme(license['url'] as String), isTrue);
      expect(validSourceScheme(license['source_page'] as String), isTrue);
      expect(license['authors'], isA<List<Object?>>());
      expect(license['changes'], isA<String>());
      expect(license['attributionRequired'], isA<bool>());
      expect(license['commercialUseAllowed'], isA<bool>());
      expect(license['derivativeWorkAllowed'], isA<bool>());
      expect(license['redistributionAllowed'], isA<bool>());
      expect(license['reviewStatus'], isA<String>());
    }
    // [2026-07-12 #2011/#1951] 광주 정본이 오너 자작(self-drawn)으로 전환됐다 —
    // 이전 CC-BY-SA 2.0 KR(kiwitree) attribution 계약은 배포 렌더링이 CC-BY-SA
    // SVG 파생이 아니게 되어 자작 기준(attribution 미표시)으로 전환됐다.
    final gwangju = maps.singleWhere((map) => map['id'] == 'gwangju');
    final license = gwangju['license'] as Map<String, Object?>;
    expect(license['spdx'], 'LicenseRef-Self-Drawn');
    expect(
      license['url'],
      'internal:route-map/route-map-defs/svg-sources/easy-subway-gwangju-v1.svg',
    );
    expect(license['reviewStatus'], 'self-drawn-confirmed');
    expect(license['attributionRequired'], isFalse);
  });

  testWidgets('노선도는 카드가 아니라 공식 지도처럼 전면 캔버스로 보인다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
    expect(find.byType(RouteMapBasemapView), findsOneWidget);
    expect(find.byKey(const Key('networkMapPainter')), findsNothing);
  });

  testWidgets('수도권 노선도는 Android에서 구조화 canvas 렌더러로 전체 크기를 채운다', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 3;
    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
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
      final renderer = tester.getSize(find.byType(RouteMapBasemapView));
      final surface = tester.getSize(
        find.byKey(const Key('networkMapSurface')),
      );
      expect(renderer.width, surface.width);
      expect(renderer.height, surface.height);
      expect(
        tester.widget(find.byType(RouteMapBasemapView)),
        isA<RouteMapBasemapView>(),
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

  // #2099 WP2: 노선도의 일반/급행 뷰 토글과 급행 전용 필터 데이터 경로는
  // 제거됐다(일반/급행은 선택 UI가 아니라 실제 운행 정보). 노선도에 선택 control이
  // 0건임은 '노선도 첫 화면은 하단 광고 위에 지도 조작을 유지한다' 테스트가 지킨다.
  testWidgets('노선도는 일반 급행 선택 없이 모든 노선을 함께 표시한다', (tester) async {
    // #2068: 노선도는 단일 통합 지도다. LOCAL/EXPRESS가 섞인 fixture에서도
    // 운행종별 필터 없이 모든 노선·역·edge를 함께 렌더하고, 일반/급행 선택
    // control(토글·selected semantics)은 어느 상태에서도 만들지 않는다.
    final semanticsHandle = tester.ensureSemantics();
    final fixture = _unifiedRouteMapData();

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(networkMapData: fixture),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    // (a) 단일 통합 basemap 위에 라벨-온리 오버레이만 얹는다. express-only 분기
    // (basemap 없는 경로)는 사라졌다.
    expect(find.byType(RouteMapBasemapView), findsOneWidget);
    final overlay = tester.widget<StructuredRouteMapView>(
      find.byType(StructuredRouteMapView),
    );
    expect(overlay.drawLines, isFalse);
    expect(overlay.drawStationSymbols, isFalse);

    // (a) 입력 NetworkMapData의 노선·역이 필터로 줄지 않는다(개수 불감소).
    expect(
      overlay.map.lines.map((line) => line.lineId).toSet(),
      fixture.lines.map((line) => line.id).toSet(),
    );
    expect(
      overlay.map.stations.length,
      greaterThanOrEqualTo(fixture.stations.length),
    );
    expect(
      overlay.map.stations.map((station) => station.lineId).toSet(),
      fixture.lines.map((line) => line.id).toSet(),
    );

    // (a) edge 양끝 역(일반·급행 각 노선)이 모두 상호작용 대상으로 남는다.
    for (final key in const [
      'networkMapStation-local-a-line-local',
      'networkMapStation-local-b-line-local',
      'networkMapStation-express-a-line-express',
      'networkMapStation-express-b-line-express',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }

    // (b)+(c) 어느 상태에서도 운행종별 토글(일반/급행 선택 control)이 트리에
    // 만들어지지 않는다. 토글은 '일반'/'급행' 세그먼트로 렌더됐으므로 그 부재로
    // 토글 미생성을 확인한다(역 라벨 '일반A' 등은 정확 일치가 아니라 무관).
    expect(find.text('일반'), findsNothing);
    expect(find.text('급행'), findsNothing);
    final servicePatternControlLabels = <String>[];
    void collectServicePatternControls(SemanticsNode node) {
      final label = node.getSemanticsData().label;
      if (label == '일반' || label == '급행') {
        servicePatternControlLabels.add(label);
      }
      node.visitChildren((child) {
        collectServicePatternControls(child);
        return true;
      });
    }

    collectServicePatternControls(
      tester.getSemantics(find.byKey(const Key('networkMapScreen'))),
    );
    expect(servicePatternControlLabels, isEmpty);

    semanticsHandle.dispose();
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
        buildEasySubwayTestApp(
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
      expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('노선도 역을 누르면 출발 도착 설정 sheet를 보여준다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
    expect(find.bySemanticsLabel(_fanDestinationLabel), findsOneWidget);
    // #1933 요구 3: 별도 길찾기 폼 페이지를 없앴으므로 팝오버의 "길찾기" 액션도
    // 제거했다. 출발/도착 지정이 곧 흐름이며, 둘 다 차면 자동으로 결과가 열린다.
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapStationSheet')),
        matching: find.text('길찾기'),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel(_fanCloseLabel), findsOneWidget);
  });

  testWidgets('노선도에서 출발을 지정한 뒤 다른 역을 누르면 팬 메뉴의 도착 섹터를 쓸 수 있다', (tester) async {
    final routeDraftController = RouteDraftController();
    await tester.pumpWidget(
      MaterialApp(
        home: NetworkMapScreen(
          repository: FakeStationSearchRepository(),
          routeDraftController: routeDraftController,
          onOpenStationSearch: (_) {},
          onPickStationForSlot: (slot, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    await _tapFanMenuSector(tester, _fanOriginLabel);
    await tester.pumpAndSettle();
    expect(routeDraftController.draft.origin?.nameKo, '상록수');

    await tester.tap(
      find.byKey(const Key('networkMapStation-sadang-seoul-2')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // #2109: 출발이 이미 정해진 상태에서 다른 역의 팬 메뉴를 열면, 그 역은
    // 어느 슬롯에도 아직 없으므로 도착 섹터가 활성화(dim 아님)돼 탭으로 도착을
    // 지정할 수 있다.
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    await _tapFanMenuSector(tester, _fanDestinationLabel);
    await tester.pumpAndSettle();
    expect(routeDraftController.draft.destination?.nameKo, '사당');
  });

  testWidgets('노선도 역은 스크린리더 tap으로도 설정 sheet를 연다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
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
      expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
      expect(find.bySemanticsLabel(_fanDestinationLabel), findsOneWidget);
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
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
      buildEasySubwayTestApp(
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
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
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
      buildEasySubwayTestApp(
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
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
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
        buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
      expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('홈 화면은 v3 기준 큰 행동과 짧은 상태 카드로 구성된다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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

  testWidgets('홈은 시설 알림과 최근 경로 로드 실패를 인라인 오류 없이 넘긴다', (tester) async {
    final facilityRepository = FakeFavoriteFacilityRepository()
      ..error = const FavoriteFacilityException('시설 알림 실패');
    final routeRepository = FakeFavoriteRouteRepository()
      ..error = const FavoriteRouteException('최근 경로 실패');

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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

  testWidgets('노선도 현재위치 버튼은 최근접 역 팬 메뉴와 하단 패널을 보여준다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      location: _freshCurrentLocation(),
      needsPermissionRequest: false,
    );
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

    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: locationProvider,
    );

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(repository.requestedNearbyLimits, [1]);
    expect(locationProvider.requestCount, 1);
    expect(repository.requestedNearbyLocations, hasLength(1));
    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    expect(find.text('상록수'), findsOneWidget);
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.bySemanticsLabel(_fanOriginLabel), findsOneWidget);
    expect(find.byKey(const Key('networkMapBottomAdBanner')), findsNothing);
  });

  testWidgets('GPS 하단 패널은 환승 호선을 탭으로 구분하고 선택 호선을 재조회한다', (tester) async {
    const lines = [
      StationSearchLine(
        id: 'seoul-2',
        name: '수도권 2호선',
        color: '#00A84D',
        stationCode: '222',
      ),
      StationSearchLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        stationCode: '454',
      ),
    ];
    final realtimeRepository = _RecordingRealtimeRepository();
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권'],
      nearbyResults: [
        _stationResult(id: 'station-sangnoksu', name: '상록수', lines: lines),
      ],
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
      realtimeRepository: realtimeRepository,
    );

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    expect(find.text('상록수'), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyLineTab-seoul-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('networkMapNearbyLineTab-seoul-4')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('networkMapNearbyLineTab-seoul-2'))),
      const Size(48, 48),
    );
    expect(realtimeRepository.queries.last.lineId, 'seoul-2');

    await tester.tap(find.byKey(const Key('networkMapNearbyLineTab-seoul-4')));
    await tester.pumpAndSettle();

    expect(realtimeRepository.queries.last.lineId, 'seoul-4');
  });

  testWidgets('GPS 하단 패널 시간표는 같은 방면의 다음 두 열차를 각각 한 줄로 표시한다', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final now = DateTime.now();
    final departure = StationTimetableDeparture(
      directionName: '오이도',
      seconds:
          now.hour * Duration.secondsPerHour +
          now.minute * Duration.secondsPerMinute +
          now.second +
          120,
    );
    final secondDeparture = StationTimetableDeparture(
      directionName: '오이도',
      seconds: departure.seconds + 300,
    );
    final repository = FakeTimetableStationRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      networkMapRegionNames: const ['수도권'],
      nearbyResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      timetables: {
        for (final dayType in StationTimetableDayType.values)
          dayType: _stationTimetable(
            dayType,
            directions: [
              StationTimetableDirection(
                name: '오이도',
                departures: [departure, secondDeparture],
              ),
            ],
          ),
      },
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
      realtimeRepository: _RecordingRealtimeRepository(),
    );

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();
    // 2버튼 세그먼트 토글(#2200). 초기 선택은 실시간.
    expect(find.bySemanticsLabel('실시간 선택됨'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapNearbyDataSourceToggle')),
        matching: find.text('실시간'),
      ),
      findsOneWidget,
    );

    // 비선택 '시간표' 세그먼트를 눌러 시간표로 전환.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('networkMapNearbyDataSourceToggle')),
        matching: find.text('시간표'),
      ),
    );
    await tester.pumpAndSettle();

    // 방면 제목은 열당 1개 헤더로 올라가고, 그 아래 두 시각이 각각 한 줄.
    expect(find.text('오이도 방면'), findsOneWidget);
    for (final item in [departure, secondDeparture]) {
      final timeFinder = find.text(item.timeLabel);
      expect(timeFinder, findsOneWidget);
      expect(
        tester.widget<Text>(timeFinder).style?.color,
        const Color(0xFFE23D3D),
      );
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(item.semanticLabel))),
        findsOneWidget,
      );
    }
    expect(find.bySemanticsLabel('시간표 선택됨'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('networkMapNearbyDataSourceToggle')))
          .height,
      greaterThanOrEqualTo(48),
    );

    // 다시 '실시간' 세그먼트를 눌러 복귀.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('networkMapNearbyDataSourceToggle')),
        matching: find.text('실시간'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('실시간 선택됨'), findsOneWidget);
  });

  testWidgets('급행 운행 정보는 선택 UI 없이 시간표와 길찾기에 표시된다', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final semanticsHandle = tester.ensureSemantics();
    final now = DateTime.now();
    final baseSeconds =
        now.hour * Duration.secondsPerHour +
        now.minute * Duration.secondsPerMinute +
        now.second;
    final localDeparture = StationTimetableDeparture(
      directionName: '오이도',
      seconds: baseSeconds + 120,
    );
    final expressDeparture = StationTimetableDeparture(
      directionName: '오이도',
      seconds: baseSeconds + 300,
      servicePattern: 'EXPRESS',
      serviceClass: 'SUBWAY',
    );
    final repository = FakeTimetableStationRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      networkMapRegionNames: const ['수도권'],
      nearbyResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      timetables: {
        for (final dayType in StationTimetableDayType.values)
          dayType: _stationTimetable(
            dayType,
            directions: [
              StationTimetableDirection(
                name: '오이도',
                departures: [localDeparture, expressDeparture],
              ),
            ],
          ),
      },
    );

    try {
      await _pumpNetworkMapForGpsTest(
        tester,
        repository: repository,
        locationProvider: FakeCurrentLocationProvider(
          location: _freshCurrentLocation(),
          needsPermissionRequest: false,
        ),
        realtimeRepository: _RecordingRealtimeRepository(),
      );

      await tester.tap(find.byKey(const Key('nearbyStationButton')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('networkMapNearbyDataSourceToggle')),
          matching: find.text('시간표'),
        ),
      );
      await tester.pumpAndSettle();

      // --- 시간표 부분(#2099 WP1) ---
      // 인접역 시간표 패널로 범위를 좁힌다. 노선도 자체의 일반/급행 노선 뷰
      // 전환 컨트롤(networkMapServicePatternToggle)은 시간표 급행 정보와 무관한
      // 별개 기능이므로 이 검증에 섞이지 않게 한다.
      final panel = find.byKey(const Key('networkMapNearbyStationPanel'));
      expect(panel, findsOneWidget);
      // 급행 출발 행에만 배지 1회, 일반 행에는 배지 없음.
      expect(
        find.descendant(
          of: panel,
          matching: find.byKey(const Key('servicePatternExpressBadge')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('급행')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('일반')),
        findsNothing,
      );
      // 두 시각 모두 노출.
      expect(
        find.descendant(
          of: panel,
          matching: find.text(localDeparture.timeLabel),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: panel,
          matching: find.text(expressDeparture.timeLabel),
        ),
        findsOneWidget,
      );
      // TalkBack은 급행을 정확히 한 번만 읽는다(배지는 장식이라 semantics 제외).
      expect(
        find.descendant(
          of: panel,
          matching: find.bySemanticsLabel(RegExp('급행')),
        ),
        findsOneWidget,
      );
      // 급행/일반은 실제 운행 정보다 — 시간표 패널 안에 toggle/chip/filter 선택
      // 컨트롤 0건.
      expect(
        find.descendant(of: panel, matching: find.byType(ChoiceChip)),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(FilterChip)),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.byType(Switch)),
        findsNothing,
      );

      // --- 길찾기 부분(#2099 WP2) ---
      // 같은 급행 배지 위젯을 길찾기 경로 타임라인의 승차 leg에서도 쓴다. SUBWAY/
      // EXPRESS 승차 step에만 `급행` 배지가 1회 붙고, 별도 선택 컨트롤은 없다.
      final routeRepository = FakeRouteSearchRepository(
        result: _sampleRouteSearchResult(
          steps: const [
            RouteSearchStep(
              sequence: 1,
              stepType: 'ride',
              title: '상록수역에서 오이도행 승차',
              description: '승강장에서 열차를 타고 이동합니다.',
              lineId: 'seoul-4',
              lineName: '수도권 4호선',
              fromStationId: 'station-sangnoksu',
              toStationId: 'station-sadang',
              estimatedMinutes: 18,
              distanceMeters: 12000,
              includesStairs: false,
              requiresAccessibilityCheck: false,
              actionTitle: '오이도행 열차 승차',
              serviceClass: 'SUBWAY',
              servicePattern: 'EXPRESS',
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: routeRepository,
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
              lastModifiedAt: DateTime(2026, 7, 17),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 승차 leg에 급행 배지 1회, 시각 텍스트도 1회.
      expect(
        find.byKey(const Key('servicePatternExpressBadge')),
        findsOneWidget,
      );
      expect(find.text('급행'), findsOneWidget);
      // TalkBack은 급행을 정확히 한 번만 읽는다(배지는 장식, 라벨은 승차 leg가 1회).
      expect(find.bySemanticsLabel(RegExp('급행')), findsOneWidget);
      // 급행/일반은 실제 운행 정보다 — 길찾기에도 toggle/chip/filter 선택 컨트롤 0건.
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(Switch), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('길찾기 ITX-청춘 승차 leg은 선택 UI 없이 ITX-청춘 서비스 식별을 표시한다', (
    tester,
  ) async {
    // #1414/#2099: ITX-청춘은 별도 운임의 좌석 지정 서비스라 같은 노선의 일반
    // 전동차와 화면에서 구분되어야 한다. serviceClass=ITX_CHEONGCHUN 승차 step에만
    // `ITX-청춘` 배지가 1회 붙고, generic 급행 배지·선택 컨트롤은 없다.
    final semanticsHandle = tester.ensureSemantics();
    final routeRepository = FakeRouteSearchRepository(
      result: _sampleRouteSearchResult(
        steps: const [
          RouteSearchStep(
            sequence: 1,
            stepType: 'ride',
            title: '상록수역에서 춘천행 승차',
            description: '승강장에서 열차를 타고 이동합니다.',
            lineId: 'gyeongchun',
            lineName: '수도권 경춘',
            fromStationId: 'station-sangnoksu',
            toStationId: 'station-sadang',
            estimatedMinutes: 40,
            distanceMeters: 30000,
            includesStairs: false,
            requiresAccessibilityCheck: false,
            actionTitle: '춘천행 열차 승차',
            serviceClass: 'ITX_CHEONGCHUN',
            servicePattern: 'EXPRESS',
          ),
        ],
      ),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: routeRepository,
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
              lastModifiedAt: DateTime(2026, 7, 17),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 승차 leg에 ITX-청춘 배지 1회, 텍스트도 1회.
      expect(
        find.byKey(const Key('servicePatternItxCheongchunBadge')),
        findsOneWidget,
      );
      expect(find.text('ITX-청춘'), findsOneWidget);
      // TalkBack은 ITX-청춘을 정확히 한 번만 읽는다(배지는 장식, 라벨은 leg가 1회).
      expect(find.bySemanticsLabel(RegExp('ITX-청춘')), findsOneWidget);
      // generic 급행 배지·라벨은 ITX leg에 0건.
      expect(find.byKey(const Key('servicePatternExpressBadge')), findsNothing);
      expect(find.text('급행'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('급행')), findsNothing);
      // 서비스 식별은 실제 운행 정보다 — toggle/chip/filter 선택 컨트롤 0건.
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(Switch), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('길찾기 SUBWAY 승차 leg에는 ITX-청춘 표시가 붙지 않는다', (tester) async {
    // ITX-청춘 식별은 serviceClass=ITX_CHEONGCHUN 승차 leg에만 붙는다. SUBWAY
    // 일반/급행 leg에는 ITX-청춘 배지·텍스트가 0건이어야 한다.
    final routeRepository = FakeRouteSearchRepository(
      result: _sampleRouteSearchResult(
        steps: const [
          RouteSearchStep(
            sequence: 1,
            stepType: 'ride',
            title: '상록수역에서 오이도행 승차',
            description: '승강장에서 열차를 타고 이동합니다.',
            lineId: 'seoul-4',
            lineName: '수도권 4호선',
            fromStationId: 'station-sangnoksu',
            toStationId: 'station-sadang',
            estimatedMinutes: 18,
            distanceMeters: 12000,
            includesStairs: false,
            requiresAccessibilityCheck: false,
            actionTitle: '오이도행 열차 승차',
            serviceClass: 'SUBWAY',
            servicePattern: 'LOCAL',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
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
            lastModifiedAt: DateTime(2026, 7, 17),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('servicePatternItxCheongchunBadge')),
      findsNothing,
    );
    expect(find.text('ITX-청춘'), findsNothing);
  });

  testWidgets('GPS 하단 패널은 열차 정보가 없어도 인접역 두 방면 스켈레톤(제목+대시+구분선)을 유지한다', (
    tester,
  ) async {
    // #2200 QA: 실시간/시간표 데이터가 전무해도 인접역이 둘이면 "○○ 방면" 제목
    // 두 열 + 1×46 구분선을 유지하고, 데이터 없는 열에는 대시('-')만 그린다.
    final repository = FakeTimetableStationRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      networkMapRegionNames: const ['수도권'],
      nearbyResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      timetables: {
        for (final dayType in StationTimetableDayType.values)
          dayType: _stationTimetable(dayType, directions: const []),
      },
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
      realtimeRepository: _RecordingRealtimeRepository(),
    );

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('networkMapNearbyStationPanel'));
    expect(
      find.descendant(of: panel, matching: find.byType(NearbyDirectionTitle)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: panel, matching: find.text('-')),
      findsNWidgets(2),
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(of: panel, matching: find.text('-')).first,
          )
          .style
          ?.color,
      const Color(0xFF2F2F2F),
    );
    expect(
      find.descendant(of: panel, matching: find.byType(VerticalDivider)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('networkMapNearbyDataSourceToggle')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: panel, matching: find.text('-')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: panel, matching: find.byType(VerticalDivider)),
      findsOneWidget,
    );
  });

  testWidgets('GPS 탭은 지도 직접 선택을 즉시 해제하고 카메라를 유지한다', (tester) async {
    final nearbyCompleter = Completer<List<StationSearchResult>>();
    final repository = FakeStationSearchRepository(
      nearbyCompleter: nearbyCompleter,
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
    );

    final station = find.byKey(
      const Key('networkMapStation-sangnoksu-seoul-4'),
    );
    await tester.tap(station);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    final stationCenterBeforeGps = tester.getCenter(station);

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pump();

    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);
    expect(find.byKey(const Key('networkMapSurface')), findsOneWidget);
    expect(tester.getCenter(station), stationCenterBeforeGps);

    nearbyCompleter.complete(const []);
    await tester.pump();
  });

  testWidgets('GPS 재시도는 이전 오류 메시지와 timer를 즉시 지운다', (tester) async {
    var locationAttempts = 0;
    final locationProvider = FakeCurrentLocationProvider(
      needsPermissionRequest: false,
      locationLoader: () async {
        locationAttempts++;
        if (locationAttempts == 1) {
          throw const CurrentLocationException('현재 위치를 확인하지 못했어요.');
        }
        return _freshCurrentLocation();
      },
    );
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권'],
      nearbyResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: locationProvider,
    );

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('현재 위치를 확인하지 못했어요.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();
    expect(find.text('현재 위치를 확인하지 못했어요.'), findsNothing);
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('현재 위치를 확인하지 못했어요.'), findsNothing);
  });

  testWidgets('GPS 최근접 역은 표시 지역명을 정규화한다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['부산권'],
      nearbyResults: [
        _stationResult(id: 'station-sangnoksu', name: '상록수', region: '부산'),
      ],
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
    );
    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(repository.requestedNetworkMapRegions, [null]);
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
  });

  testWidgets('GPS 다른 지역 결과는 지도와 역을 검증한 뒤에만 팬 메뉴를 연다', (tester) async {
    final busanMap = Completer<NetworkMapData>();
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권', '부산권'],
      networkMapCompletersByRegion: {'부산권': busanMap},
      nearbyResults: [
        _stationResult(id: 'station-sangnoksu', name: '상록수', region: '부산'),
      ],
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
    );
    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pump();

    expect(repository.requestedNetworkMapRegions, [null, '부산권']);
    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);

    busanMap.complete(
      _gpsNetworkMapData(selectedRegion: '부산권', regions: const ['수도권', '부산권']),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
  });

  testWidgets('GPS 지역 지도 load 실패는 팬 메뉴를 열지 않는다', (tester) async {
    final busanMap = Completer<NetworkMapData>();
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권', '부산권'],
      networkMapCompletersByRegion: {'부산권': busanMap},
      nearbyResults: [
        _stationResult(id: 'station-sangnoksu', name: '상록수', region: '부산'),
      ],
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
    );

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pump();
    busanMap.completeError(StateError('부산 지도 load 실패'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isA<StateError>());
    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);
    expect(find.text('주변 역을 불러오지 못했어요.'), findsOneWidget);
  });

  testWidgets('GPS 지역 지도에 최근접 역 ID가 없으면 팬 메뉴를 열지 않는다', (tester) async {
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권', '부산권'],
      networkMapDataByRegion: {
        '부산권': _gpsNetworkMapData(
          selectedRegion: '부산권',
          regions: const ['수도권', '부산권'],
          includeNearestStation: false,
        ),
      },
      nearbyResults: [
        _stationResult(id: 'station-sangnoksu', name: '상록수', region: '부산'),
      ],
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
    );

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);
    expect(find.text('주변 역을 불러오지 못했어요.'), findsOneWidget);
  });

  testWidgets('GPS의 오래된 비동기 결과는 일반 지역 전환을 되돌리지 않는다', (tester) async {
    final nearbyCompleter = Completer<List<StationSearchResult>>();
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권', '대구권', '부산권'],
      nearbyCompleter: nearbyCompleter,
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
    );

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pump();
    expect(repository.requestedNetworkMapRegions, [null]);

    await tester.tap(find.byKey(const Key('networkMapRegionDropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('networkMapRegionMenuRow_대구권')));
    await tester.pumpAndSettle();
    expect(repository.requestedNetworkMapRegions, [null, '대구권']);

    nearbyCompleter.complete([
      _stationResult(id: 'station-sangnoksu', name: '상록수', region: '부산'),
    ]);
    await tester.pumpAndSettle();

    expect(repository.requestedNetworkMapRegions, [null, '대구권']);
    expect(
      find.descendant(
        of: find.byKey(const Key('networkMapRegionDropdown')),
        matching: find.text('대구'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('networkMapStationSheet')), findsNothing);
  });

  testWidgets('GPS 지역 전환은 자동 위치 조회를 다시 시작하지 않는다', (tester) async {
    var permissionChecks = 0;
    final locationProvider = FakeCurrentLocationProvider(
      location: _freshCurrentLocation(),
      needsPermissionRequestLoader: () async {
        permissionChecks++;
        return permissionChecks == 1;
      },
    );
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권', '부산권'],
      networkMapDataByRegion: {
        '부산권': _gpsNetworkMapData(
          selectedRegion: '부산권',
          regions: const ['수도권', '부산권'],
        ),
      },
      nearbyResults: [
        _stationResult(id: 'station-sangnoksu', name: '상록수', region: '부산'),
      ],
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: locationProvider,
      viewportRepository: FakeNetworkMapViewportRepository(),
    );

    expect(locationProvider.permissionCheckCount, 1);
    expect(locationProvider.requestCount, 0);

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(repository.requestedNetworkMapRegions, [null, '부산권']);
    expect(locationProvider.permissionCheckCount, 1);
    expect(locationProvider.requestCount, 1);
    expect(repository.requestedNearbyLocations, hasLength(1));
    expect(repository.requestedNearbyLimits, [1]);
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
  });

  testWidgets('노선도 좌측 메뉴 하단에 광고 슬롯이 있다', (tester) async {
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
  });

  testWidgets('노선도 현재위치 실패는 하단 패널 대신 임시 메시지만 보여준다', (tester) async {
    final locationProvider = FakeCurrentLocationProvider(
      error: const CurrentLocationException('현재 위치를 확인하지 못했어요.'),
      needsPermissionRequest: false,
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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

  testWidgets('홈 이동 조건 pill은 모든 프리셋에 맞는 표시명을 보여준다', (tester) async {
    for (final preset in MobilityPreset.values) {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
          key: ValueKey('home-preset-${preset.name}'),
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          notificationRepository: FakeNotificationSettingsRepository(),
          initialOnboardingState: _completedOnboardingState(preset: preset),
        ),
      );
      await tester.pumpAndSettle();

      await _openSettingsScreen(tester);

      expect(find.text(mobilityPresetDisplayName(preset)), findsWidgets);
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
        child: buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
      expect(find.text('천천히'), findsWidgets);
      expect(find.text('여유 있는 걸음 속도로 시간을 계산해요'), findsOneWidget);
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
          '천천히, 여유 있는 걸음 속도로 시간을 계산해요',
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
      await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
      await tester.pumpAndSettle();

      expect(find.text('휠체어 이용'), findsWidgets);
      expect(
        find.text('엘리베이터로만 이동하는 길을 안내해요 · 유아차와 함께일 때도 좋아요'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('notificationSettingsButton')),
        160,
      );
      await tester.pumpAndSettle();

      expect(find.text('알림'), findsOneWidget);
      expect(find.text('내 활동'), findsOneWidget);
      expect(find.text('서비스 정보 및 도움말'), findsOneWidget);
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
        find.byKey(const Key('settingsServiceInfoButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('settingsSupportPrivacyButton')),
        findsOneWidget,
      );
      expect(
        settingsActionSemantics(
          '서비스 정보',
        ).getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
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

      await tester.scrollUntilVisible(
        find.byKey(const Key('settingsServiceInfoButton')),
        120,
      );
      await tester.tap(find.byKey(const Key('settingsServiceInfoButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('serviceInfoScreen')), findsOneWidget);
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

    // #1701: 서울교통공사 환승역거리 소요시간·빠른하차·환승 이동경로 3건 출처가 화면에 표기된다.
    // source-inventory.json에 이미 존재하는 항목이 필터 없이 렌더링됨을 고정한다.
    // 각 출처 카드는 제목과 '제공 기관' 행에 displayName을 두 번(2개 Text) 렌더링하므로 단일 매치를
    // 요구하는 scrollUntilVisible 대신 리스트를 직접 드래그해 lazy 항목을 노출시킨 뒤 findsWidgets로
    // 확인한다. 항목 탐색 전 매번 리스트를 최상단으로 리셋해 렌더 순서에 의존하지 않게 한다.
    final sourceScrollable = find.byType(Scrollable);
    final sourceScrollState = tester.state<ScrollableState>(sourceScrollable);
    for (final displayName in const [
      '환승 이동경로',
      '서울교통공사_빠른하차정보',
      '서울교통공사_환승역거리 소요시간',
    ]) {
      sourceScrollState.position.jumpTo(
        sourceScrollState.position.minScrollExtent,
      );
      await tester.pumpAndSettle();

      final finder = find.textContaining(displayName);
      while (finder.evaluate().length < 2) {
        final position = sourceScrollState.position;
        if (position.pixels >= position.maxScrollExtent) break;
        final previousOffset = position.pixels;
        await tester.drag(sourceScrollable, const Offset(0, -300));
        await tester.pumpAndSettle();
        if (position.pixels <= previousOffset) break;
      }
      expect(finder, findsNWidgets(2));
    }
  });

  testWidgets('설정 화면 보기 옵션은 변경값을 저장하고 다시 실행해도 유지한다', (tester) async {
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        preset: MobilityPreset.slow,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
        preset: MobilityPreset.slow,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveError: StateError('save failed'),
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
        preset: MobilityPreset.slow,
        preferences: const OnboardingViewPreferences.defaults(),
      ),
      saveError: StateError('save failed'),
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
    await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 1);
    // 저장 실패로 이전 프리셋(천천히)으로 되돌아간다 — 새 프리셋(휠체어 이용)은 저장되지 않는다.
    expect(find.text('이동 조건을 저장하지 못했어요. 이전 조건으로 되돌렸어요.'), findsOneWidget);
  });

  testWidgets('설정 화면 보기 옵션은 빠른 연속 변경에서도 마지막 값을 저장한다', (tester) async {
    final firstSave = Completer<void>();
    final latestSave = Completer<void>();
    final onboardingStore = MemoryOnboardingResultStore(
      initialResult: OnboardingResult(
        preset: MobilityPreset.slow,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
        preset: MobilityPreset.slow,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
        preset: MobilityPreset.slow,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
        preset: MobilityPreset.slow,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
        preset: MobilityPreset.slow,
        preferences: const OnboardingViewPreferences(
          largeTextEnabled: false,
          highContrastEnabled: false,
          simpleViewEnabled: true,
        ),
      ),
      saveCompleters: [firstSave, latestSave],
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
    await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
    await tester.pumpAndSettle();

    expect(onboardingStore.saveCount, 1);

    firstSave.complete();
    await tester.pump();
    expect(onboardingStore.saveCount, 2);
    latestSave.complete();
    await tester.pumpAndSettle();

    expect(onboardingStore.savedResult?.preset, MobilityPreset.stepFree);
    expect(find.text('휠체어 이용'), findsWidgets);
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
      buildEasySubwayTestApp(
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

  testWidgets('홈 이동 조건 요약은 현재 프리셋과 변경 결과를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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

    expect(find.text('여유 있는 걸음 속도로 시간을 계산해요'), findsOneWidget);

    await _openMobilityProfileFromSettings(tester);
    await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
    await tester.pumpAndSettle();
    expect(find.text('엘리베이터로만 이동하는 길을 안내해요 · 유아차와 함께일 때도 좋아요'), findsOneWidget);
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
      buildEasySubwayTestApp(
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

  testWidgets('홈은 도움말에서 삭제 요청과 문의 경로를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
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
      expect(find.text('개인정보처리방침'), findsNothing);

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

  testWidgets('도움말은 개인정보 처리방침 진입점을 서비스 정보로 분리한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
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

      expect(find.byKey(const Key('privacyDataUseSummary')), findsNothing);
      expect(find.text('개인정보 사용 안내'), findsNothing);
      expect(find.text('현재 위치는 가까운 역 찾기와 시설 제보 위치 확인에만 사용됩니다.'), findsNothing);
      expect(find.text('법으로 꼭 필요한 기록은 정해진 기간 동안만 보관합니다.'), findsNothing);
      expect(find.text('개인정보처리방침'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('도움말은 이동 전 살펴보기 안내를 함께 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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

  testWidgets('도움말은 고객지원을 메일 앱으로 연결한다', (tester) async {
    final launcher = RecordingSupportAccessLauncher();

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
    await tester.tap(find.byKey(const Key('supportAccessItem')));
    await tester.pump();

    expect(
      find.text('연결할 수 없습니다. 직접 확인해 주세요: support@easysubway.example'),
      findsOneWidget,
    );
  });

  testWidgets('알림 설정 화면은 현재 설정을 불러오고 바꾼 값을 저장한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final notificationRepository = FakeNotificationSettingsRepository();

    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
        repository: FakeStationSearchRepository(),
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteFacilityRepository: FakeFavoriteFacilityRepository(),
        favoriteRouteRepository: favoriteRouteRepository,
        notificationRepository: FakeNotificationSettingsRepository(),
        initialOnboardingState: _completedOnboardingState(
          preset: MobilityPreset.slow,
        ),
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

  testWidgets('즐겨찾기 ITX 경로 다시 찾기는 저장된 transport scope로 연다', (tester) async {
    final favoriteRouteRepository = FakeFavoriteRouteRepository(
      favorites: [
        _favoriteRoute(
          transportScope: RouteTransportScope.subwayAndItxCheongchun,
        ),
      ],
    );
    final routeDraftController = RouteDraftController();
    routeDraftController.setWaypoint(
      const RouteDraftStation(id: 'station-old-waypoint', nameKo: '기존 경유역'),
    );
    RouteTransportScope? restoredTransportScope;
    RouteDraft? restoredDraft;

    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
      onOpenRouteSearchWithScope: (draft, mobilityType, transportScope) async {
        restoredDraft = draft;
        restoredTransportScope = transportScope;
      },
    );
    await tester.tap(find.text('상록수역 → 사당역'));
    await tester.pumpAndSettle();

    expect(restoredTransportScope, RouteTransportScope.subwayAndItxCheongchun);
    expect(restoredDraft?.origin?.id, 'station-sangnoksu');
    expect(restoredDraft?.destination?.id, 'station-sadang');
    expect(restoredDraft?.waypoint, isNull);
  });

  testWidgets('역 검색은 검색 버튼 없이 타이핑(디바운스)만으로 결과를 보여준다', (tester) async {
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );
    await tester.pumpWidget(
      buildEasySubwayTestApp(
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
        buildEasySubwayTestApp(
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
      // #1933 placeholder는 부유 라벨이 아니라 박스 내부 수직 중앙의
      // hintText다. floatingLabelBehavior를 지정하면 실기기에서 hint가
      // 박스 상단 테두리 위로 떠오르는 회귀가 있어 미지정이 계약이다.
      expect(searchInput.decoration?.floatingLabelBehavior, isNull);
      // #2082 실기기 재작업: hint 중앙 정렬은 고유 높이 필드 + Center 위젯으로
      // 얻으며, 실기기(Noto Sans KR)에서는 오프셋 0으로 정합함을 픽셀 판독으로 확인했다
      // (docs/2082-qa, 정본). FlutterTest 테스트 폰트에서는 InputDecorator 중앙
      // 정렬 오차로 hint 중심이 박스 중심에서 십수 px 벗어날 수 있으므로, 여기서는
      // hint가 박스 세로 범위 안에 온전히 들어오는지(=부유 라벨이 아님)를 폰트
      // 메트릭 독립적으로 계약으로 잡는다.
      final searchBoxRect = tester.getRect(
        find.byKey(const Key('heroStationSearchInputBox')),
      );
      final searchHintCenterDy = tester
          .getCenter(find.text('역 이름을 입력해 주세요'))
          .dy;
      expect(searchHintCenterDy, greaterThan(searchBoxRect.top));
      expect(searchHintCenterDy, lessThan(searchBoxRect.bottom));
      expect(find.byKey(const Key('stationSearchSubmitButton')), findsNothing);
      // #1933: 홈 in-place 검색 모드에는 주변 역 버튼이 없다(둘러보기 주변 역은
      // 좌측 메뉴로 연다). ≡는 ←로 바뀌고 지역 선택기는 유지된다.
      expect(find.byKey(const Key('nearbyStationSearchButton')), findsNothing);
      expect(
        find.byKey(const Key('networkMapSearchBackButton')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('networkMapMenuButton')), findsNothing);
      expect(find.byKey(const Key('mapRegionTabs')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('stationSearchInput')),
        '상록수',
      );
      await tester.pump();
      // 검색 버튼은 제거됐고, in-place 모드에는 주변 역 버튼이 없다.
      expect(find.byKey(const Key('stationSearchSubmitButton')), findsNothing);
      expect(find.byKey(const Key('nearbyStationSearchButton')), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(repository.requestedQueries, ['상록수']);
      // #1933: 역이 지나는 노선마다 한 행씩(각 행 우측에 색 배지). '+N' 요약 없음.
      expect(find.byKey(const Key('stationLineBadge-seoul-4')), findsOneWidget);
      expect(
        find.byKey(const Key('stationLineBadge-korail-gyeongui-jungang')),
        findsOneWidget,
      );
      // 부가 텍스트(거리/노선 요약)·지역명은 행에 노출하지 않는다.
      expect(find.text('수도권 4호선, 경의중앙선'), findsNothing);
      expect(find.text('수도권'), findsNothing);
      // 기본 레벨(LEVEL_1) 품질 필러는 목록에서 감춘다(#1477). 시맨틱에는 유지.
      expect(find.text('일부 정보는 확인 중이에요'), findsNothing);
      expect(find.text('출처 확인 필요'), findsNothing);
      expect(find.bySemanticsLabel('검색 결과 1개'), findsOneWidget);
      // 다중 노선 역은 시각적으로 노선마다 한 행씩 펼치지만(배지 2개), 선택 버튼
      // 시맨틱은 첫 행만 노출한다 — 스크린리더에 같은 선택 버튼이 노선 수만큼
      // 중복되지 않도록 이후 행은 ExcludeSemantics 로 감싼다. 첫 행 라벨만 존재하고
      // 두 번째 노선 라벨은 시맨틱 트리에 없다.
      expect(find.bySemanticsLabel('상록수역, 수도권 4호선, 선택'), findsOneWidget);
      expect(find.bySemanticsLabel('상록수역, 경의중앙선, 선택'), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('상록수역, 수도권 4호선, 선택')),
        isSemantics(
          label: '상록수역, 수도권 4호선, 선택',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // 대표 키는 첫 행에만 두어 단일 위젯으로 남는다.
      expect(
        find.byKey(const Key('stationSearchResult-station-sangnoksu')),
        findsOneWidget,
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
      // in-place 모드에는 주변 역 버튼이 없다. 비우면 결과만 사라진다.
      expect(find.byKey(const Key('nearbyStationSearchButton')), findsNothing);
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
        child: buildEasySubwayTestApp(
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

    // #1933: 결과 행은 부가 문구·거리 요약 없이 역명만 노출한다. 환승역은 노선마다
    // 한 행씩 펼치므로 역명 Text가 노선 수만큼 있다. 각 행의 역명은 시스템 글자
    // 크기에서도 한 줄 말줄임으로 고정하지 않는다.
    final nameWidgets = find.text('$longStationName역');
    expect(nameWidgets, findsNWidgets(2));
    for (final nameWidget in tester.widgetList<Text>(nameWidgets)) {
      expect(nameWidget.maxLines, isNot(1));
      expect(nameWidget.overflow, isNot(TextOverflow.ellipsis));
    }
    // 노선 요약 부가 문구는 더 이상 행에 렌더링하지 않는다.
    expect(
      find.text('현재 위치에서 1.3km · 수도권 9호선 급행, 공항철도 직통 일반 공용'),
      findsNothing,
    );
    // 품질 문구 "일부 정보는 확인 중이에요"는 별도 semantic label 테스트에서 유지한다.
  });

  testWidgets('#2109 홈 in-place 검색 결과 탭은 역을 지도에서 포커스하고 팬 메뉴를 연다', (
    tester,
  ) async {
    // #2109: 홈 노선도 상단바 인플레이스 검색에서는 결과 행에 인라인 출발/도착
    // 역할 버튼을 두지 않는다. 결과 행을 탭하면 상세를 밀지 않고 검색을 닫은 뒤
    // 해당 역을 지도에서 포커스하고 부채꼴 팬 메뉴(역 액션 메뉴)를 띄운다. 출발/
    // 도착 지정은 이 팬 메뉴로 수렴한다(역할 버튼 IA는 결과 행에서 제거됨).
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
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

    // 결과 행에는 더 이상 인라인 출발/도착 역할 버튼이 없다.
    expect(
      find.byKey(const Key('stationRoleOrigin-station-sangnoksu')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('stationRoleDestination-station-sangnoksu')),
      findsNothing,
    );
    expect(find.bySemanticsLabel('상록수역을 출발역으로 설정'), findsNothing);

    // 결과 행 탭 = 검색 종료 + 역 포커스 + 팬 메뉴.
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();

    // 상세 라우트를 밀지 않고 인플레이스 검색이 종료되어 노선도로 돌아온다.
    expect(find.byKey(const Key('stationSearchInput')), findsNothing);
    expect(find.byType(StationDetailScreen), findsNothing);
    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    // 포커스한 역의 부채꼴 팬 메뉴와 해당 역 하단 정보 패널이 함께 나타난다.
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    expect(find.text('상록수'), findsOneWidget);
  });

  testWidgets('#2200 검색 선택으로 연 주변역 패널 body가 화면 안에 실제 크기로 렌더된다', (tester) async {
    // 오너 QA 회귀 방지(#2207): 툴바(토글)만 뜨고 하단 body(노선 바)가
    // 사라지는 증상을 막는다. 존재만이 아니라 히트테스트 가능한 크기와 화면
    // 안 배치까지 단언한다.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
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

    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    final track = find.byKey(const Key('nearbyStationLineBarTrack'));
    expect(track, findsOneWidget);
    final trackSize = tester.getSize(track);
    final trackRect = tester.getRect(track);
    expect(trackSize.width, greaterThan(0), reason: '노선 바 폭이 0이면 body가 붕괴한 것');
    expect(
      trackSize.height,
      greaterThan(0),
      reason: '노선 바 높이가 0이면 body가 붕괴한 것',
    );
    expect(trackRect.top, greaterThanOrEqualTo(0), reason: '노선 바가 화면 위로 벗어남');
    expect(
      trackRect.bottom,
      lessThanOrEqualTo(844),
      reason: '노선 바가 화면 아래로 벗어남',
    );
  });

  testWidgets('#2200 GPS 주변역 패널 body가 화면 안에 실제 크기로 렌더된다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권'],
      nearbyResults: [
        _stationResult(
          id: 'station-sangnoksu',
          name: '상록수',
          distanceMeters: 180,
        ),
      ],
    );
    await _pumpNetworkMapForGpsTest(
      tester,
      repository: repository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
      realtimeRepository: _RecordingRealtimeRepository(),
    );
    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    final track = find.byKey(const Key('nearbyStationLineBarTrack'));
    expect(track, findsOneWidget);
    final trackSize = tester.getSize(track);
    final trackRect = tester.getRect(track);
    expect(trackSize.width, greaterThan(0));
    expect(trackSize.height, greaterThan(0));
    expect(trackRect.top, greaterThanOrEqualTo(0));
    expect(trackRect.bottom, lessThanOrEqualTo(844));
  });

  testWidgets('#2109 검색 선택은 지도에서 직접 선택한 역을 교체한다', (tester) async {
    final repository = FakeStationSearchRepository(
      queryResults: {
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('networkMapStation-sangnoksu-seoul-4')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);

    await _openStationSearchScreenViaMenu(tester);
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '사당');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sadang')),
    );
    await tester.pumpAndSettle();

    await _tapFanMenuSector(tester, _fanOriginLabel);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('사당역, 출발 지정됨'), findsOneWidget);
    expect(find.bySemanticsLabel('상록수역, 출발 지정됨'), findsNothing);
  });

  testWidgets('#2109 팬 메뉴에 역명 라벨과 상세 진입이 없다', (tester) async {
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
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

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(find.byType(StationDetailScreen), findsNothing);
    expect(find.bySemanticsLabel('상록수역 상세 보기'), findsNothing);
  });

  testWidgets('#2109 풀페이지 검색(햄버거 메뉴) 결과 탭도 노선도 복귀+팬 메뉴로 수렴한다', (tester) async {
    // #2109 Fix: 좌측 햄버거 메뉴 "역 검색"으로 여는 풀페이지 StationSearchScreen의
    // 일반(둘러보기) 결과 탭도 임베디드 검색과 동일하게 노선도 복귀 → 카메라
    // 포커스 → 팬 메뉴 표시로 수렴해야 한다(오너 승인 스펙: "역을 검색하면 팬
    // 메뉴가 나온다"가 진입점에 무관하게 적용).
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openStationSearchScreenViaMenu(tester);
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sangnoksu')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(StationDetailScreen), findsNothing);
    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    expect(find.text('상록수'), findsOneWidget);
    expect(find.bySemanticsLabel('상록수역 상세 보기'), findsNothing);
  });

  testWidgets('#2109 GPS 패널 뒤 풀페이지 검색 결과 탭은 해당 역 패널로 교체한다', (tester) async {
    // GPS와 풀페이지 검색은 모두 팬 메뉴·하단 패널 채널로 수렴한다. GPS가 먼저
    // 연 상록수 패널 뒤 사당 검색 결과를 탭하면 같은 패널이 사당 정보로 바뀐다.
    final locationProvider = FakeCurrentLocationProvider(
      location: _freshCurrentLocation(),
      needsPermissionRequest: false,
    );
    final repository = FakeStationSearchRepository(
      networkMapRegionNames: const ['수도권'],
      queryResults: {
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
      nearbyResults: [
        _stationResult(
          id: 'station-sangnoksu',
          name: '상록수',
          distanceMeters: 180,
        ),
      ],
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    // GPS는 최근접 역 하나의 팬 메뉴와 하단 패널을 함께 연다.
    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );

    // 햄버거 → 역 검색 → 결과 탭.
    await _openStationSearchScreenViaMenu(tester);
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '사당');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sadang')),
    );
    await tester.pumpAndSettle();

    // 검색 결과도 같은 단일 팬 메뉴로 수렴하고 하단 패널은 사당으로 교체된다.
    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    expect(find.text('사당'), findsOneWidget);
    expect(find.text('상록수'), findsNothing);
  });

  testWidgets('#2109 검색 선택 뒤 늦게 끝난 GPS 요청은 선택 역을 덮지 않는다', (tester) async {
    final nearbyCompleter = Completer<List<StationSearchResult>>();
    final repository = FakeStationSearchRepository(
      queryResults: {
        '사당': [_stationResult(id: 'station-sadang', name: '사당')],
      },
      nearbyCompleter: nearbyCompleter,
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: FakeCurrentLocationProvider(
          location: _freshCurrentLocation(),
          needsPermissionRequest: false,
        ),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nearbyStationButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '사당');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('stationSearchResult-station-sadang')),
    );
    await tester.pumpAndSettle();
    expect(find.text('사당'), findsOneWidget);

    nearbyCompleter.complete([
      _stationResult(id: 'station-sangnoksu', name: '상록수'),
    ]);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapStationSheet')), findsOneWidget);
    expect(
      find.byKey(const Key('networkMapNearbyStationPanel')),
      findsOneWidget,
    );
    expect(find.text('사당'), findsOneWidget);
    expect(find.text('상록수'), findsNothing);
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

      // #1933 요구 3: 별도 길찾기 폼 페이지를 없앴다. 완성된 draft로 진입하면 입력
      // 폼(이동 조건 헤더·계단 토글 스위치·하단 "길찾기" 버튼·최근 도착지) 대신 곧바로
      // 자동 검색이 돌아 결과-우선 화면(조용한 조건 칩 + 이동 순서 타임라인)이 뜬다.
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routeMobilityTypeInput')), findsNothing);
      expect(find.byKey(const Key('routeStrictStepFreeSwitch')), findsNothing);
      expect(find.byKey(const Key('routeConditionChips')), findsOneWidget);
      expect(find.byKey(const Key('routeScopeItxChip')), findsNothing);
      expect(find.text('최근 도착지'), findsNothing);
      expect(find.widgetWithText(FilledButton, '길찾기'), findsNothing);
      expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
      expect(find.text('이동 순서'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('Route V2 transport flag는 explicit ITX 선택에서만 combined 재검색한다', (
    tester,
  ) async {
    final routeRepository = FakeRouteSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          itxTransportScopeEnabled: true,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    expect(
      routeRepository.requests.single.transportScope,
      RouteTransportScope.subway,
    );
    expect(find.byKey(const Key('routeScopeSubwayChip')), findsOneWidget);
    expect(find.byKey(const Key('routeScopeItxChip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('routeScopeItxChip')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(2));
    expect(
      routeRepository.requests.last.transportScope,
      RouteTransportScope.subwayAndItxCheongchun,
    );
  });

  testWidgets('길찾기 기본값은 최단시간(FASTEST)과 지하철(SUBWAY)이다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
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
            lastModifiedAt: DateTime(2026, 7, 17),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    expect(routeRepository.requests.single.objective, RouteObjective.fastest);
    expect(
      routeRepository.requests.single.transportScope,
      RouteTransportScope.subway,
    );
    expect(find.byKey(const Key('routeObjectiveFastestChip')), findsOneWidget);
    expect(
      find.byKey(const Key('routeObjectiveFewestTransfersChip')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('routeObjectiveFastestChip')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('objective 탭을 최소환승으로 바꾸면 scope는 유지한 채 objective만 재검색한다', (
    tester,
  ) async {
    final routeRepository = FakeRouteSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
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
            lastModifiedAt: DateTime(2026, 7, 17),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('routeObjectiveFewestTransfersChip')),
    );
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(2));
    expect(
      routeRepository.requests.last.objective,
      RouteObjective.fewestTransfers,
    );
    // objective만 바뀌고 scope는 SUBWAY로 유지된다(로컬-우선 동작 보존).
    expect(
      routeRepository.requests.last.transportScope,
      RouteTransportScope.subway,
    );
    expect(
      routeRepository.requests.every(
        (request) => request.transportScope == RouteTransportScope.subway,
      ),
      isTrue,
    );
  });

  testWidgets('같은 objective를 다시 눌러도 재검색하지 않는다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
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
            lastModifiedAt: DateTime(2026, 7, 17),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('routeObjectiveFastestChip')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
  });

  testWidgets('objective 탭은 TalkBack 라벨·선택 상태·48dp·글자 확대를 지킨다', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: RouteSearchScreen(
            repository: FakeRouteSearchRepository(),
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
              lastModifiedAt: DateTime(2026, 7, 17),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // TalkBack 라벨은 objective 두 탭 모두 정확히 한 번씩.
      expect(find.bySemanticsLabel('경로 목표, 최단시간'), findsOneWidget);
      expect(find.bySemanticsLabel('경로 목표, 최소환승'), findsOneWidget);
      // 글자 2배·320dp에서도 오버플로 없이 렌더된다.
      expect(tester.takeException(), isNull);
      // 최소 48dp 터치 타깃.
      expect(
        tester
            .getSize(find.byKey(const Key('routeObjectiveFastestChip')))
            .height,
        greaterThanOrEqualTo(48.0),
      );
      // 선택 상태(체크 표시)는 현재 objective에만.
      expect(
        find.descendant(
          of: find.byKey(const Key('routeObjectiveFastestChip')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('routeObjectiveFewestTransfersChip')),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('objective 칩은 재검색 로딩 중 비활성이고 완료 후 재활성된다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final routeRepository = ControlledRouteSearchRepository();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: routeRepository,
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
              lastModifiedAt: DateTime(2026, 7, 17),
            ),
          ),
        ),
      );
      // 자동 검색이 시작돼 로딩 상태로 멈춘다(응답 미완료).
      await tester.pump();
      expect(routeRepository.requests, hasLength(1));

      final chipFinder = find.byKey(
        const Key('routeObjectiveFewestTransfersChip'),
      );
      // 로딩 중: semantics enabled=false, tap 액션 없음.
      final loadingData = tester.getSemantics(chipFinder).getSemanticsData();
      expect(loadingData.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
      expect(loadingData.hasAction(SemanticsAction.tap), isFalse);
      // TalkBack 라벨 계약은 로딩 중에도 불변.
      expect(find.bySemanticsLabel('경로 목표, 최소환승'), findsOneWidget);
      // 로딩 중 tap은 무효 — 재검색이 시작되지 않는다.
      await tester.tap(chipFinder);
      await tester.pump();
      expect(routeRepository.requests, hasLength(1));

      // 검색 완료 → 칩 재활성.
      routeRepository.complete(_sampleRouteSearchResult());
      await tester.pumpAndSettle();
      final readyData = tester.getSemantics(chipFinder).getSemanticsData();
      expect(readyData.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();
      expect(routeRepository.requests.length, greaterThan(1));
      expect(
        routeRepository.requests.last.objective,
        RouteObjective.fewestTransfers,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('ITX 실패는 명시적 지하철만 보기 선택 뒤에만 SUBWAY로 재검색한다', (tester) async {
    final routeRepository = FakeRouteSearchRepository(
      errorForRequest: (request) =>
          request.transportScope == RouteTransportScope.subwayAndItxCheongchun
          ? const RouteSearchOnlineException.unavailable(
              failureReason: 'ITX_TIMETABLE_UNAVAILABLE',
              message: 'ITX 시간표를 불러올 수 없어요',
            )
          : null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          itxTransportScopeEnabled: true,
          initialTransportScope: RouteTransportScope.subwayAndItxCheongchun,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    expect(
      routeRepository.requests.single.transportScope,
      RouteTransportScope.subwayAndItxCheongchun,
    );
    expect(
      find.byKey(const Key('routeSearchSubwayOnlyAction')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('routeSearchSubwayOnlyAction')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(2));
    expect(
      routeRepository.requests.last.transportScope,
      RouteTransportScope.subway,
    );
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
  });

  testWidgets('즐겨찾기에서 복원한 ITX transport scope로 첫 검색을 시작한다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          itxTransportScopeEnabled: true,
          initialTransportScope: RouteTransportScope.subwayAndItxCheongchun,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    expect(
      routeRepository.requests.single.transportScope,
      RouteTransportScope.subwayAndItxCheongchun,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('routeScopeItxChip')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('경유역이 있는 draft는 ITX scope를 fail closed하고 요청하지 않는다', (
    tester,
  ) async {
    final routeRepository = FakeRouteSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          itxTransportScopeEnabled: true,
          initialTransportScope: RouteTransportScope.subwayAndItxCheongchun,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            waypoint: const RouteDraftStation(
              id: 'station-seolleung',
              nameKo: '선릉',
            ),
            lastModifiedAt: DateTime(2026, 7, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(routeRepository.requests, isEmpty);
    expect(find.textContaining('ITX-청춘 경로는 경유역을 지원하지 않아요'), findsOneWidget);
    expect(find.byKey(const Key('routeScopeSubwayChip')), findsOneWidget);
  });

  testWidgets('휠체어 프리셋은 복원된 ITX scope를 SUBWAY로 제한한다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          initialMobilityType: 'WHEELCHAIR',
          itxTransportScopeEnabled: true,
          initialTransportScope: RouteTransportScope.subwayAndItxCheongchun,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 16),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    expect(
      routeRepository.requests.single.transportScope,
      RouteTransportScope.subway,
    );
    expect(find.byKey(const Key('routeScopeItxChip')), findsNothing);
  });

  testWidgets('transport scope 변경은 하차 알림 취소 실패 시 기존 scope와 경로를 유지한다', (
    tester,
  ) async {
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
    final routeRepository = FakeRouteSearchRepository(
      result: _sampleGetOffAlarmRouteResult(),
    );
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: routeRepository,
      controller: controller,
      itxTransportScopeEnabled: true,
    );
    await _enableSampleGetOffAlarm(controller);
    notifier.reset();
    final cancelError = StateError('cancel failed');
    notifier.cancelError = cancelError;
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reports.add, () async {
      await tester.tap(find.byKey(const Key('routeScopeItxChip')));
      await tester.pumpAndSettle();
    });

    expect(reports.single.exception, same(cancelError));
    expect(controller.state.enabled, isTrue);
    expect(routeRepository.requests, hasLength(1));
    expect(
      routeRepository.requests.single.transportScope,
      RouteTransportScope.subway,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('routeScopeSubwayChip')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
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

    // #1933 C/D: 출발·도착이 이미 채워진 draft로 진입하면 자동 검색이 한 번 돈다.
    // 결과-우선 화면에서는 하단 "길찾기" 버튼이 없고, 프리셋 칩으로 휠체어 이용 프리셋을
    // 고르면 그 자리에서 WHEELCHAIR·STRICT_STEP_FREE로 바로 재검색한다.
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routeSearchSubmitButton')), findsNothing);
    await tester.tap(find.byKey(const Key('routeConditionMobilityChip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests.last.mobilityType, 'WHEELCHAIR');
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

  testWidgets('#1948 경유역이 있는 draft는 자동 검색 요청에 waypointStationId를 전달한다', (
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
            waypoint: const RouteDraftStation(
              id: 'station-seolleung',
              nameKo: '선릉',
            ),
            lastModifiedAt: DateTime(2026, 7, 10),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    expect(
      routeRepository.requests.single.waypointStationId,
      'station-seolleung',
    );
  });

  testWidgets('#1948 경유역 없는 draft의 자동 검색 요청은 waypointStationId가 없다', (
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

    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    expect(routeRepository.requests.single.waypointStationId, isNull);
  });

  testWidgets('#1948 같은 출발·도착에 경유역만 추가하면 서명이 바뀌어 자동 검색이 다시 돈다', (tester) async {
    final routeRepository = FakeRouteSearchRepository();
    const origin = RouteDraftStation(id: 'station-sangnoksu', nameKo: '상록수');
    const destination = RouteDraftStation(id: 'station-sadang', nameKo: '사당');

    Widget buildScreen(RouteDraft draft) {
      return MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
          stationRepository: FakeStationSearchRepository(),
          favoriteRouteRepository: FakeFavoriteRouteRepository(),
          initialMobilityType: 'SENIOR',
          initialDraft: draft,
        ),
      );
    }

    await tester.pumpWidget(
      buildScreen(
        RouteDraft(
          origin: origin,
          destination: destination,
          lastModifiedAt: DateTime(2026, 7, 10),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(routeRepository.requests, hasLength(1));

    // 같은 출발·도착에 경유역만 추가한 새 draft로 갱신하면 서명이 달라져 재검색.
    await tester.pumpWidget(
      buildScreen(
        RouteDraft(
          origin: origin,
          destination: destination,
          waypoint: const RouteDraftStation(
            id: 'station-seolleung',
            nameKo: '선릉',
          ),
          lastModifiedAt: DateTime(2026, 7, 11),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(2));
    expect(routeRepository.requests.first.waypointStationId, isNull);
    expect(
      routeRepository.requests.last.waypointStationId,
      'station-seolleung',
    );
  });

  testWidgets('#1933 D 자동 검색된 결과 화면은 결과-우선으로 정리된다', (tester) async {
    final routeRepository = FakeRouteSearchRepository(
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
            requiresAccessibilityCheck: false,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
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
            lastModifiedAt: DateTime(2026, 7, 11),
          ),
        ),
      ),
    );

    // 출발·도착이 채워진 draft는 버튼 없이 자동 검색으로 결과-우선 화면에 도달한다.
    await tester.pumpAndSettle();

    // 1) 하단 중복 "길찾기" 버튼이 없다(자동 검색이 이미 돌았으므로).
    expect(find.byKey(const Key('routeSearchSubmitButton')), findsNothing);
    expect(find.widgetWithText(FilledButton, '길찾기'), findsNothing);

    // 2) 보행 프리셋은 조용한 칩 한 개로 강등된다(폼 헤더·드롭다운·계단 토글 없음).
    expect(find.byKey(const Key('routeConditionChips')), findsOneWidget);
    expect(find.byKey(const Key('routeConditionMobilityChip')), findsOneWidget);
    expect(find.byKey(const Key('routeConditionStepFreeChip')), findsNothing);
    expect(find.byKey(const Key('routeMobilityTypeInput')), findsNothing);
    expect(find.byKey(const Key('routeStrictStepFreeSwitch')), findsNothing);
    expect(find.text('최근 도착지'), findsNothing);

    // 3) 이동 순서 타임라인(#1704)이 카드 탭 없이 인라인으로 펼쳐진다.
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    expect(find.text('이동 순서'), findsOneWidget);
    expect(find.byKey(const Key('routeStepNumber-1')), findsOneWidget);
    expect(find.byKey(const Key('routeStepNumber-2')), findsOneWidget);

    // 4) 상단 얇은 출발·도착은 그대로 남아 탭해서 편집(→ 재검색)할 수 있다.
    expect(find.byKey(const Key('routeOriginPointButton')), findsOneWidget);
    expect(
      find.byKey(const Key('routeDestinationPointButton')),
      findsOneWidget,
    );
  });

  testWidgets('#2066 승차 step에 빠른 하차 칸-문·시설 안내 줄을 그린다', (tester) async {
    final routeRepository = FakeRouteSearchRepository(
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
            requiresAccessibilityCheck: false,
            carDoorCarNumber: 3,
            carDoorDoorNumber: 4,
            carDoorFacilityType: 'ELEVATOR',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
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
            lastModifiedAt: DateTime(2026, 7, 11),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 승차 step에만 빠른 하차 안내 줄이 나온다.
    expect(find.byKey(const Key('routeStepCarDoor-2')), findsOneWidget);
    expect(find.textContaining('빠른 하차 3-4칸'), findsWidgets);
    expect(find.textContaining('엘리베이터'), findsWidgets);
    // 데이터 없는 entry step(sequence 1)에는 줄을 그리지 않는다.
    expect(find.byKey(const Key('routeStepCarDoor-1')), findsNothing);

    // 스크린리더용 시맨틱 라벨은 "번 칸/번 문" 형태로 풀어 읽는다.
    final semanticsHandle = tester.ensureSemantics();
    final node = tester.getSemantics(
      find.byKey(const Key('routeStepCarDoor-2')),
    );
    expect(node.label, contains('3번 칸'));
    expect(node.label, contains('4번 문'));
    expect(node.label, contains('엘리베이터'));
    semanticsHandle.dispose();
  });

  testWidgets('#1948 타임라인은 경유 스텝을 무채색 경유 노드로 그리고 요약을 왜곡하지 않는다', (tester) async {
    final routeRepository = FakeRouteSearchRepository(
      result: _sampleRouteSearchResult(
        steps: const [
          RouteSearchStep(
            sequence: 1,
            stepType: 'ride',
            title: '상록수에서 선릉까지 이동',
            description: '열차를 이용해 이동합니다.',
            lineId: 'seoul-4',
            lineName: '수도권 4호선',
            fromStationId: 'station-sangnoksu',
            toStationId: 'station-seolleung',
            estimatedMinutes: 20,
            distanceMeters: 9000,
            includesStairs: false,
            requiresAccessibilityCheck: false,
          ),
          RouteSearchStep(
            sequence: 2,
            stepType: 'waypoint',
            title: '선릉 경유',
            description: '내리지 않고 이 역을 지나가요',
            actionTitle: '경유',
            lineId: '',
            lineName: '',
            fromStationId: 'station-seolleung',
            toStationId: 'station-seolleung',
            estimatedMinutes: 0,
            distanceMeters: 0,
            includesStairs: false,
            requiresAccessibilityCheck: false,
          ),
          RouteSearchStep(
            sequence: 3,
            stepType: 'ride',
            title: '선릉에서 사당까지 이동',
            description: '열차를 이용해 이동합니다.',
            lineId: 'seoul-2',
            lineName: '수도권 2호선',
            fromStationId: 'station-seolleung',
            toStationId: 'station-sadang',
            estimatedMinutes: 18,
            distanceMeters: 8000,
            includesStairs: false,
            requiresAccessibilityCheck: false,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: routeRepository,
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
            lastModifiedAt: DateTime(2026, 7, 11),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 경유 스텝의 배지 Key는 회귀 없이 유지된다.
    expect(find.byKey(const Key('routeStepNumber-2')), findsOneWidget);

    // 경유 노드는 노선색 승차 배지가 아니라 무채색 more_horiz 노드로 렌더된다.
    final waypointBadge = find.byKey(const Key('routeStepNumber-2'));
    expect(
      find.descendant(
        of: waypointBadge,
        matching: find.byIcon(Icons.more_horiz),
      ),
      findsOneWidget,
    );
    // 경유 노드에는 승차 배지(노선번호 텍스트)나 도보 아이콘이 없다.
    expect(
      find.descendant(
        of: waypointBadge,
        matching: find.byIcon(Icons.directions_walk),
      ),
      findsNothing,
    );

    // 승차 스텝은 노선색 배지(노선번호)로 남아 회귀가 없다.
    expect(find.byKey(const Key('routeStepNumber-1')), findsOneWidget);
    expect(find.byKey(const Key('routeStepNumber-3')), findsOneWidget);

    // #1948: 경유 스텝은 0값 placeholder burdenLabel을 렌더하지 않는다.
    expect(find.text('시간 미확인 · 거리 미확인'), findsNothing);
    expect(find.textContaining('시간 미확인'), findsNothing);
    // #1948: 경유 스텝은 보일러플레이트 기본 안내 문장 대신 간결 카피를 쓴다.
    expect(find.text('안내된 순서대로 이동합니다.'), findsNothing);
    expect(find.text('내리지 않고 이 역을 지나가요'), findsOneWidget);
    // #1948: 경유 스텝은 "경유" 서브라벨(2줄)을 별도로 그리지 않는다(제목에 이미 포함).
    expect(find.text('경유'), findsNothing);

    // #1975: 경유 노드 원의 시각 반경은 8 이하(직경 16 이하)여야 한다.
    // badgeKey가 붙은 내부 Container 크기로 검증한다.
    final waypointNode = tester.getSize(waypointBadge);
    expect(waypointNode.width, lessThanOrEqualTo(16));
    expect(waypointNode.height, lessThanOrEqualTo(16));
  });

  testWidgets('#1933 홈 검색바 탭은 같은 화면에서 in-place 검색 모드로 전환한다', (tester) async {
    final repository = FakeStationSearchRepository();

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();

    // 별도 StationSearchScreen 라우트를 밀지 않고 같은 노선도 화면에 머문다.
    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
    expect(find.byType(StationSearchScreen), findsNothing);
    // ≡ 메뉴 버튼이 ← 뒤로 버튼으로 바뀌고, 지역 선택기는 유지되며, 실제 입력
    // 필드가 나타난다.
    expect(find.byKey(const Key('networkMapMenuButton')), findsNothing);
    expect(find.byKey(const Key('networkMapSearchBackButton')), findsOneWidget);
    expect(find.byKey(const Key('mapRegionTabs')), findsOneWidget);
    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);
  });

  testWidgets('#1933 in-place 검색 입력은 디바운스 후 자동완성 결과를 보여준다', (tester) async {
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    // 버튼 탭·키보드 액션 없이 디바운스(300ms)만 지나면 검색된다.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(repository.requestedQueries, ['상록수']);
    expect(find.text('상록수역'), findsOneWidget);
    // in-place 결과 목록에서도 별도 라우트를 밀지 않는다.
    expect(find.byType(StationSearchScreen), findsNothing);
  });

  testWidgets('#1933 in-place 검색은 ← 또는 시스템 back으로 종료하고 지도로 복귀한다', (
    tester,
  ) async {
    final repository = FakeStationSearchRepository(
      queryResults: {
        '상록수': [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      },
    );

    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await tester.pumpAndSettle();

    // 진입 → 타이핑으로 검색 상태를 만든 뒤 ← 버튼으로 종료한다.
    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('networkMapSearchBackButton')));
    await tester.pumpAndSettle();

    // ≡ 복귀, ← 소멸, 입력 필드 소멸, idle 검색 필드 복귀.
    expect(find.byKey(const Key('networkMapMenuButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapSearchBackButton')), findsNothing);
    expect(find.byKey(const Key('stationSearchInput')), findsNothing);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.byType(StationSearchScreen), findsNothing);

    // 다시 진입 → 시스템 back(handlePopRoute)으로도 종료된다.
    await tester.tap(find.byKey(const Key('stationSearchButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stationSearchInput')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('networkMapMenuButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapSearchBackButton')), findsNothing);
    expect(find.byKey(const Key('stationSearchInput')), findsNothing);
    expect(find.byKey(const Key('stationSearchButton')), findsOneWidget);
    expect(find.byKey(const Key('networkMapScreen')), findsOneWidget);
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
        buildEasySubwayTestApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          locationProvider: locationProvider,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      // #1933: 홈 노선도 검색바 탭은 in-place 검색 모드라 주변 역 버튼이 없다.
      // 둘러보기 "주변 역"은 좌측 메뉴로 StationSearchScreen(nearby)을 연다.
      await tester.tap(find.byKey(const Key('networkMapMenuButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('networkMapMenuNearbyButton')));
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
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    // #1933: 둘러보기 주변 역은 좌측 메뉴로 StationSearchScreen(nearby)을 연다.
    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('networkMapMenuNearbyButton')));
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
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    // #1933: 둘러보기 주변 역은 좌측 메뉴로 StationSearchScreen(nearby)을 연다.
    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('networkMapMenuNearbyButton')));
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
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    // #1933: 둘러보기 주변 역은 좌측 메뉴로 StationSearchScreen(nearby)을 연다.
    // nearby 진입 시 위치 조회가 한 번 자동 시작되고(위치는 completer로 지연),
    // 조회가 진행 중이면 재시도 버튼 중복 탭은 무시된다.
    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('networkMapMenuNearbyButton')));
    // 메뉴 다이얼로그 해제 + StationSearchScreen 라우트 전환을 진행시킨다(위치
    // completer가 열려 있어 pumpAndSettle은 사용할 수 없다).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    // #1933: 둘러보기 주변 역은 좌측 메뉴로 StationSearchScreen(nearby)을 연다.
    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('networkMapMenuNearbyButton')));
    // 메뉴 해제 + 라우트 전환 진행(위치 completer가 열려 있어 settle 불가).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

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
        buildEasySubwayTestApp(
          repository: repository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          locationProvider: locationProvider,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      // #1933: 둘러보기 주변 역은 좌측 메뉴로 StationSearchScreen(nearby)을 연다.
      await tester.tap(find.byKey(const Key('networkMapMenuButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('networkMapMenuNearbyButton')));
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        locationProvider: locationProvider,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    // #1933: 둘러보기 주변 역은 좌측 메뉴로 StationSearchScreen(nearby)을 연다.
    await tester.tap(find.byKey(const Key('networkMapMenuButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('networkMapMenuNearbyButton')));
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

  testWidgets('역 검색 결과는 기본 품질 문구를 숨기고 노선별 선택 Semantics를 제공한다', (tester) async {
    final repository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
    );
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );
    await _openStationSearchScreenViaMenu(tester);
    await tester.enterText(find.byKey(const Key('stationSearchInput')), '상록수');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('일부 정보는 확인 중이에요'), findsNothing);
    expect(find.text('출처 공식 파일'), findsNothing);
    expect(find.bySemanticsLabel('상록수역, 수도권 2호선, 선택'), findsOneWidget);
  });

  testWidgets('역 상세는 출구와 시설 상태를 쉬운 문구로 보여준다', (tester) async {
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
      await _pumpStationDetailForTest(
        tester,
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
      );

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

    await _pumpStationDetailForTest(
      tester,
      repository: repository,
      reportRepository: FakeFacilityReportRepository(),
    );

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
      await _pumpStationDetailForTest(
        tester,
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('stationDetailList')), findsOneWidget);
      expect(
        find.byKey(const Key('stationDetailLargeScreenLayout')),
        findsNothing,
      );
      // 정상 시설은 상태 필 없이 이름으로 조용히, 문제(고장·미확인)만 상태 필로 렌더링.
      var sawNormalQuiet = false;
      var sawBroken = false;
      var sawNeedsCheck = false;
      for (var index = 0; index < 8; index += 1) {
        sawNormalQuiet |= find.text('1번 출구 엘리베이터').evaluate().isNotEmpty;
        sawBroken |= find.text('이용할 수 없어요').evaluate().isNotEmpty;
        sawNeedsCheck |= find.text('상태 미확인').evaluate().isNotEmpty;
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

    await _pumpStationDetailForTest(
      tester,
      repository: repository,
      reportRepository: reportRepository,
      locationProvider: FakeCurrentLocationProvider(
        location: _freshCurrentLocation(),
        needsPermissionRequest: false,
      ),
    );
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

    await _pumpStationDetailForTest(
      tester,
      repository: repository,
      reportRepository: FakeFacilityReportRepository(),
      facilityReportDraftTargetStore: draftTargetStore,
    );
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

  testWidgets('역 상세는 시설 목록이 없으면 시설 섹션을 통째로 숨긴다', (tester) async {
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
      await _pumpStationDetailForTest(
        tester,
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();

      // #2078: 시설 데이터가 없으면 섹션 제목·빈 안내·잔여 간격을 모두 숨긴다.
      expect(find.text('시설'), findsNothing);
      expect(find.text('시설 안내를 준비 중이에요.'), findsNothing);
      expect(find.text('확인 필요 없음'), findsNothing);
      expect(find.bySemanticsLabel('다시 볼 시설 없음'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 상세는 출구 목록이 없으면 시설이 있어도 출구 섹션만 숨긴다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      stationExits: const [],
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

    try {
      await _pumpStationDetailForTest(
        tester,
        repository: repository,
        reportRepository: FakeFacilityReportRepository(),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -520));
      await tester.pumpAndSettle();

      // #2078: 출구는 비고 시설은 있는 비대칭 케이스 — 출구 섹션 제목·빈
      // 안내·잔여 간격만 숨기고, 시설 섹션은 그대로 그린다.
      expect(find.text('출구'), findsNothing);
      expect(find.text('출구 안내를 준비 중이에요.'), findsNothing);
      expect(find.text('시설'), findsOneWidget);
      expect(find.text('1번 출구 엘리베이터'), findsOneWidget);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('역 상세 광고는 성공 content 최하단에 station placement로 배선된다', (
    tester,
  ) async {
    final adRepository = AdRepository(_NoInventoryAdApiClient());
    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          repository: FakeStationSearchRepository(
            stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
          ),
          reportRepository: FakeFacilityReportRepository(),
          adRepository: adRepository,
          stationId: 'station-sangnoksu',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(
      find.byKey(const Key('stationDetailList')),
    );
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    final banner = children.last as ActiveAdBanner;

    expect(banner.repository, same(adRepository));
    expect(banner.placement, AdPlacement.stationDetailBottom);
  });

  testWidgets('역 상세 시간표는 요일과 방향을 바꾸며 첫차·막차와 출발 시각을 읽는다', (tester) async {
    debugStationVerifiedClock = () => DateTime(2026, 7, 6);
    final semanticsHandle = tester.ensureSemantics();
    final repository = FakeTimetableStationRepository(
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
      timetables: {
        StationTimetableDayType.weekday: _stationTimetable(
          StationTimetableDayType.weekday,
          directions: const [
            StationTimetableDirection(
              name: '사당 방면',
              departures: [
                StationTimetableDeparture(
                  directionName: '사당 방면',
                  seconds: 19200,
                ),
                StationTimetableDeparture(
                  directionName: '사당 방면',
                  seconds: 87900,
                ),
              ],
            ),
            StationTimetableDirection(
              name: '오이도 방면',
              departures: [
                StationTimetableDeparture(
                  directionName: '오이도 방면',
                  seconds: 21000,
                ),
              ],
            ),
          ],
        ),
        StationTimetableDayType.saturday: _stationTimetable(
          StationTimetableDayType.saturday,
          directions: const [
            StationTimetableDirection(
              name: '사당 방면',
              departures: [
                StationTimetableDeparture(
                  directionName: '사당 방면',
                  seconds: 33120,
                ),
              ],
            ),
          ],
        ),
      },
    );

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: StationDetailScreen(
            repository: repository,
            reportRepository: FakeFacilityReportRepository(),
            stationId: 'station-sangnoksu',
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('stationTimetableButton')));
      await tester.pumpAndSettle();

      expect(find.text('상록수 시간표'), findsOneWidget);
      expect(find.text('첫차 05:20'), findsOneWidget);
      expect(find.text('막차 다음 날 00:25'), findsOneWidget);
      expect(find.bySemanticsLabel('사당 방면, 다음 날 00시 25분 출발'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('stationTimetableDirection-오이도 방면')),
      );
      await tester.pump();
      expect(find.text('05:50'), findsOneWidget);
      expect(find.text('다음 날 00:25'), findsNothing);

      await tester.tap(find.byKey(const Key('stationTimetableDay-saturday')));
      await tester.pumpAndSettle();
      expect(find.text('첫차 09:12'), findsOneWidget);
      expect(
        repository.requestedDayTypes,
        contains(StationTimetableDayType.saturday),
      );
    } finally {
      semanticsHandle.dispose();
      debugStationVerifiedClock = DateTime.now;
    }
  });

  testWidgets('역 시간표 화면은 일반·급행을 한 목록에 시각순으로 표시하고 급행 행에만 배지를 단다', (
    tester,
  ) async {
    // #2099 WP1: LOCAL 08:00과 EXPRESS 08:03이 한 방향 목록에 시각순으로 함께
    // 놓이고, 08:03에만 급행 배지가 붙으며 방향·첫차·막차 동작은 유지된다.
    debugStationVerifiedClock = () => DateTime(2026, 7, 6); // 월요일(평일)
    const line = StationSearchLine(
      id: 'seoul-4',
      name: '수도권 4호선',
      color: '#00A5DE',
      stationCode: '433',
    );
    final repository = FakeTimetableStationRepository(
      stationDetail: _stationDetail(id: 'station-sadang', name: '사당'),
      timetableLineId: 'seoul-4',
      timetables: {
        for (final dayType in StationTimetableDayType.values)
          dayType: _stationTimetable(
            dayType,
            stationId: 'station-sadang',
            lineId: 'seoul-4',
            directions: const [
              StationTimetableDirection(
                name: '사당 방면',
                departures: [
                  StationTimetableDeparture(
                    directionName: '사당 방면',
                    seconds: 28800, // 08:00 일반
                  ),
                  StationTimetableDeparture(
                    directionName: '사당 방면',
                    seconds: 28980, // 08:03 급행
                    servicePattern: 'EXPRESS',
                    serviceClass: 'SUBWAY',
                  ),
                ],
              ),
            ],
          ),
      },
    );

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: StationTimetableScreen(
            stationId: 'station-sadang',
            stationName: '사당',
            lines: const [line],
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 두 시각이 한 목록에 시각순으로 함께 노출된다.
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('08:03'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('08:00')).dy,
        lessThan(tester.getTopLeft(find.text('08:03')).dy),
      );

      // 첫차·막차 동작 유지.
      expect(find.text('첫차 08:00'), findsOneWidget);
      expect(find.text('막차 08:03'), findsOneWidget);

      // 급행 행에만 배지 1회, 일반 행에는 배지 없음.
      expect(find.text('급행'), findsOneWidget);
      expect(
        find.byKey(const Key('servicePatternExpressBadge')),
        findsOneWidget,
      );
      expect(find.text('일반'), findsNothing);

      // 급행/일반은 실제 운행 정보다 — 선택 컨트롤(칩·필터)로 노출하지 않는다.
      expect(find.widgetWithText(ChoiceChip, '급행'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, '일반'), findsNothing);
      expect(find.widgetWithText(FilterChip, '급행'), findsNothing);
    } finally {
      debugStationVerifiedClock = DateTime.now;
    }
  });

  testWidgets('역 상세 시간표는 로컬 coverage가 없으면 사실형 빈 안내를 보여준다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StationDetailScreen(
          repository: FakeStationSearchRepository(
            stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
          ),
          reportRepository: FakeFacilityReportRepository(),
          stationId: 'station-sangnoksu',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stationTimetableButton')));
    await tester.pumpAndSettle();

    expect(find.text('시간표 정보가 없어요'), findsOneWidget);
    expect(find.textContaining('임시'), findsNothing);
  });

  testWidgets('환승역 시간표는 coverage가 있는 첫 노선을 기본 선택한다', (tester) async {
    debugStationVerifiedClock = () => DateTime(2026, 7, 6);
    const lines = [
      StationSearchLine(
        id: 'seoul-2',
        name: '수도권 2호선',
        color: '#00A84D',
        stationCode: '226',
      ),
      StationSearchLine(
        id: 'seoul-4',
        name: '수도권 4호선',
        color: '#00A5DE',
        stationCode: '433',
      ),
    ];
    final repository = FakeTimetableStationRepository(
      stationDetail: _stationDetail(
        id: 'station-sadang',
        name: '사당',
        lines: lines,
      ),
      timetableLineId: 'seoul-4',
      timetables: {
        StationTimetableDayType.weekday: _stationTimetable(
          StationTimetableDayType.weekday,
          stationId: 'station-sadang',
          lineId: 'seoul-4',
          directions: const [
            StationTimetableDirection(
              name: '상록수 방면',
              departures: [
                StationTimetableDeparture(
                  directionName: '상록수 방면',
                  seconds: 19500,
                ),
              ],
            ),
          ],
        ),
      },
    );

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: StationDetailScreen(
            repository: repository,
            reportRepository: FakeFacilityReportRepository(),
            stationId: 'station-sadang',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('상록수 방면 · 첫차 05:25 · 막차 05:25'), findsOneWidget);
      await tester.tap(find.byKey(const Key('stationTimetableButton')));
      await tester.pumpAndSettle();

      final selectedLine = tester.widget<ChoiceChip>(
        find.byKey(const Key('stationTimetableLine-seoul-4')),
      );
      expect(selectedLine.selected, isTrue);
    } finally {
      debugStationVerifiedClock = DateTime.now;
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

      await tester.scrollUntilVisible(
        find.byKey(const Key('stationExitMapButton-exit-sangnoksu-1')),
        500,
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
    final semanticsHandle = tester.ensureSemantics();
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
    expect(
      find.text('카카오맵 앱에서는 현재 위치와 출구 좌표를, 웹에서는 출구 좌표만 카카오에 전달합니다.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('1번 출구까지 카카오맵 도보 길안내'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        '1번 출구까지 카카오맵 도보 길안내, 앱에서는 현재 위치와 출구 좌표를, 웹에서는 출구 좌표만 카카오에 전달합니다',
      ),
      findsNothing,
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
    semanticsHandle.dispose();
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
    expect(
      find.text('카카오맵 앱에서는 현재 위치와 역 좌표를, 웹에서는 역 좌표만 카카오에 전달합니다.'),
      findsOneWidget,
    );

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

  testWidgets('역 상세는 내부 이동 노드로 기본 안내를 표시한다', (tester) async {
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );
    final internalRouteRepository = FakeInternalRouteRepository(
      nodes: _internalRouteNodes(),
      result: _internalRouteResult(),
    );

    await _pumpStationDetailForTest(
      tester,
      repository: stationRepository,
      reportRepository: FakeFacilityReportRepository(),
      internalRouteRepository: internalRouteRepository,
      internalRouteMobilityType: 'WHEELCHAIR',
    );

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
      await _pumpStationDetailForTest(
        tester,
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        favoriteRepository: favoriteRepository,
      );

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

  testWidgets('저장된 역은 상세에서 해제 버튼으로 시작한다', (tester) async {
    final favoriteRepository = FakeFavoriteStationRepository(
      favorites: [_favoriteStation(id: 'station-sangnoksu', name: '상록수')],
    );
    final stationRepository = FakeStationSearchRepository(
      nextResults: [_stationResult(id: 'station-sangnoksu', name: '상록수')],
      stationDetail: _stationDetail(id: 'station-sangnoksu', name: '상록수'),
    );

    await _pumpStationDetailForTest(
      tester,
      repository: stationRepository,
      reportRepository: FakeFacilityReportRepository(),
      favoriteRepository: favoriteRepository,
    );

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

    await _pumpStationDetailForTest(
      tester,
      repository: stationRepository,
      reportRepository: FakeFacilityReportRepository(),
      favoriteRepository: favoriteRepository,
      settle: false,
    );

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
      buildEasySubwayTestApp(
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

  testWidgets('이동 조건 프리셋 시트는 4개 프리셋을 표시명·부가설명과 함께 고를 수 있다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openMobilityProfileFromSettings(tester);

      expect(find.text('보통 걸음'), findsWidgets);
      expect(find.text('천천히'), findsWidgets);
      expect(find.text('계단 없이'), findsWidgets);
      expect(find.text('휠체어 이용'), findsWidgets);
      // 시트에만 나타나는 프리셋 부가설명(설정 행 뒤 기본값은 천천히라 별개).
      expect(find.text('계단 대신 에스컬레이터·엘리베이터로 안내해요'), findsOneWidget);
      expect(find.text('일반적인 걸음 속도로 안내해요'), findsOneWidget);

      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            '휠체어 이용, 엘리베이터로만 이동하는 길을 안내해요 · 유아차와 함께일 때도 좋아요',
          ),
        ),
        isSemantics(
          label: '휠체어 이용, 엘리베이터로만 이동하는 길을 안내해요 · 유아차와 함께일 때도 좋아요',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      final wheelchairRow = find.byKey(const Key('mobilityPresetRow-stepFree'));
      expect(wheelchairRow, findsOneWidget);
      expect(tester.getSize(wheelchairRow).height, greaterThanOrEqualTo(48));

      await tester.tap(wheelchairRow);
      await tester.pumpAndSettle();

      // 프리셋 시트는 선택 즉시 닫히고, 설정 행 제목이 새 표시명으로 갱신된다.
      expect(find.text('휠체어 이용'), findsWidgets);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('이동 조건 프리셋 시트는 저장된 프리셋을 선택 상태로 연다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(
            preset: MobilityPreset.stepFree,
          ),
        ),
      );

      await _openMobilityProfileFromSettings(tester);

      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            '휠체어 이용, 엘리베이터로만 이동하는 길을 안내해요 · 유아차와 함께일 때도 좋아요',
          ),
        ),
        isSemantics(isSelected: true),
      );
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
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openMobilityProfileFromSettings(tester);
    await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
    await tester.pumpAndSettle();

    expect(onboardingStore.savedResult?.mobilityType, 'WHEELCHAIR');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        onboardingStore: onboardingStore,
      ),
    );
    await tester.pumpAndSettle();

    // #1933 요구 3: 노선도 팝오버로 출발·도착을 정하면 현재 이동 프로필(휠체어)로
    // 자동 검색이 돌아 결과가 온다. 폼·제출 버튼 경로는 제거됐다.
    await _openRouteSearchScreen(tester);

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
        buildEasySubwayTestApp(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: routeRepository,
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      // #1933 요구 3: 노선도 팝오버로 출발·도착을 정하면 자동 검색이 돌아 결과-우선
      // 화면에 도달한다(폼·제출 버튼 없음).
      await _openRouteSearchScreen(tester);

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('길찾기')),
        findsOneWidget,
      );
      expect(find.byType(DropdownButton<String>), findsNothing);

      final originButtonLeft = tester.getTopLeft(
        find.byKey(const Key('routeOriginPointButton')),
      );
      final originTextLeft = tester.getTopLeft(find.text('상록수역'));
      expect(originTextLeft.dx - originButtonLeft.dx, greaterThanOrEqualTo(24));

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
      expect(find.textContaining('천천히'), findsWidgets);
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
      // #1933 D: 결과-우선 화면은 이동 순서 타임라인(#1704)을 카드 탭 없이 인라인으로
      // 편다. 도착 안내도 결과 목록에 함께 인라인으로 노출된다.
      expect(find.text('도착 안내'), findsOneWidget);
      expect(find.text('이동 순서'), findsOneWidget);
      // #1933 E: 요약 카드의 환승·걷기 칩은 바로 위 메타 줄과 겹쳐 걷어냈다.
      // 메타 줄('환승 없이 이동 · 걷기 300m')은 한 번만 남고, 걷기만 담은
      // 별도 칩('걷기 300m')은 더 이상 그리지 않는다. 요약 한 번 → 타임라인.
      expect(find.text('걷기 300m'), findsNothing);

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
      expect(find.text('약 4분 · 180m · 엘리베이터 안내 미확인'), findsOneWidget);
      // 여러 주의는 각주 한 줄로 합쳐 하나의 '주의 확인'만 노출한다(#1577).
      expect(find.text('주의 확인'), findsOneWidget);
      expect(
        find.text('일부 시설 안내는 아직 확인되지 않았어요. · 시설 상태 안내가 오래됐을 수 있어요.'),
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

  testWidgets('경로 상세의 공유 버튼은 표시명 요약과 실제 trigger 영역만 OS 공유에 넘긴다', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('ko');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    String? sharedText;
    Rect? sharedOrigin;
    var failShare = false;
    final result = _sampleRouteSearchResult(
      routeSearchId: 'local-private-route-id',
      etaSource: 'STALE',
      objective: RouteObjective.fewestTransfers,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(result: result),
          stationRepository: FakeStationSearchRepository(),
          routeShareInvoker: (text, origin) async {
            sharedText = text;
            sharedOrigin = origin;
            if (failShare) {
              throw StateError('private share failure');
            }
          },
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapFirstRouteResultListItem(tester);
    await tester.pumpAndSettle();

    final shareButton = find.byKey(const Key('routeShareButton'));
    expect(shareButton, findsOneWidget);
    final shareSemantics = find.bySemanticsLabel('경로 요약 공유');
    expect(shareSemantics, findsOneWidget);
    expect(
      tester
          .getSemantics(shareSemantics)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(sharedText, contains('상록수 → 사당'));
    expect(sharedText, contains('기준: 최소환승'));
    expect(sharedText, contains('시간: 04:20 → 04:27'));
    expect(sharedText, contains('저장된 데이터 기준'));
    expect(sharedText, isNot(contains('local-private-route-id')));
    expect(sharedText, isNot(contains('station-sangnoksu')));
    expect(sharedOrigin, tester.getRect(shareButton));

    failShare = true;
    await tester.tap(shareButton);
    await tester.pumpAndSettle();
    expect(find.text('경로 요약을 공유하지 못했어요.'), findsOneWidget);
    expect(find.textContaining('private share failure'), findsNothing);
  });

  testWidgets('시각 없는 진입·출구 사이 공식 ride 시각을 전체 공유 시각으로 사용한다', (tester) async {
    String? sharedText;
    final result = _sampleRouteSearchResult(
      routeSearchId: 'local-timed-middle-route',
      etaSource: 'STATIC_LOCAL',
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'entry',
          title: '상록수역 승강장으로 이동',
          description: '승강장으로 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sangnoksu',
          estimatedMinutes: 2,
          distanceMeters: 80,
          includesStairs: false,
          requiresAccessibilityCheck: false,
        ),
        RouteSearchStep(
          sequence: 2,
          stepType: 'ride',
          title: '상록수에서 사당까지 4호선 이동',
          description: '4호선 열차로 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sadang',
          estimatedMinutes: 7,
          distanceMeters: 0,
          includesStairs: false,
          requiresAccessibilityCheck: false,
          plannedDepartureTimeIso: '2026-07-18T08:05:00+09:00',
          plannedArrivalTimeIso: '2026-07-18T08:12:00+09:00',
          timeSource: 'OFFICIAL_TIMETABLE',
        ),
        RouteSearchStep(
          sequence: 3,
          stepType: 'exit',
          title: '사당역 출구로 이동',
          description: '출구로 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sadang',
          toStationId: 'station-sadang',
          estimatedMinutes: 2,
          distanceMeters: 80,
          includesStairs: false,
          requiresAccessibilityCheck: false,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(result: result),
          stationRepository: FakeStationSearchRepository(),
          routeShareInvoker: (text, origin) async => sharedText = text,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapFirstRouteResultListItem(tester);
    await tester.pumpAndSettle();
    final shareButton = find.byKey(const Key('routeShareButton'));
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(sharedText, contains('시간: 08:05 → 08:12'));
    expect(sharedText, isNot(contains('시간: 04:20')));
    expect(find.text('경로 요약을 공유하지 못했어요.'), findsNothing);
  });

  testWidgets('시각 필드가 없는 V1 온라인 결과도 조회 시각 기반 요약을 공유한다', (tester) async {
    String? sharedText;

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(),
          ),
          stationRepository: FakeStationSearchRepository(),
          routeShareInvoker: (text, origin) async => sharedText = text,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapFirstRouteResultListItem(tester);
    await tester.pumpAndSettle();
    final shareButton = find.byKey(const Key('routeShareButton'));
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(sharedText, contains('시간: 04:20 → 04:27'));
    expect(sharedText, contains('계획 시간 기준'));
    expect(find.text('경로 요약을 공유하지 못했어요.'), findsNothing);
  });

  testWidgets('서로 다른 offset의 V2 공유 시각을 한국 시간대로 통일한다', (tester) async {
    String? sharedText;
    final result = _sampleRouteSearchResult(
      departureTimeIso: '2026-07-18T09:00:00Z',
      arrivalTimeIso: '2026-07-18T18:30:00+09:00',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(result: result),
          stationRepository: FakeStationSearchRepository(),
          routeShareInvoker: (text, origin) async => sharedText = text,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapFirstRouteResultListItem(tester);
    await tester.pumpAndSettle();
    final shareButton = find.byKey(const Key('routeShareButton'));
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(sharedText, contains('시간: 18:00 → 18:30'));
    expect(sharedText, isNot(contains('시간: 09:00')));
    expect(find.text('경로 요약을 공유하지 못했어요.'), findsNothing);
  });

  testWidgets('영어 기기의 MIXED 로컬 경로도 한국어 사실 안내와 보완 시각으로 공유한다', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    String? sharedText;
    final result = _sampleRouteSearchResult(
      routeSearchId: 'local-planned-arrival-route',
      etaSource: 'MIXED',
      steps: const [
        RouteSearchStep(
          sequence: 1,
          stepType: 'ride',
          title: '상록수에서 사당까지 4호선 이동',
          description: '4호선 열차로 이동합니다.',
          lineId: 'seoul-4',
          lineName: '수도권 4호선',
          fromStationId: 'station-sangnoksu',
          toStationId: 'station-sadang',
          estimatedMinutes: 7,
          distanceMeters: 0,
          includesStairs: false,
          requiresAccessibilityCheck: false,
          plannedArrivalTimeIso: '2026-07-18T08:12:00+09:00',
          timeSource: 'OFFICIAL_TIMETABLE',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(result: result),
          stationRepository: FakeStationSearchRepository(),
          routeShareInvoker: (text, origin) async => sharedText = text,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapFirstRouteResultListItem(tester);
    await tester.pumpAndSettle();
    final shareButton = find.byKey(const Key('routeShareButton'));
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(sharedText, contains('시간: 08:05 → 08:12'));
    expect(sharedText, contains('일부 실시간 정보가 반영'));
    expect(sharedText, isNot(contains('Objective:')));
    expect(find.text('경로 요약을 공유하지 못했어요.'), findsNothing);
  });

  testWidgets('ITX 공식 운임이 없으면 공유 API를 호출하지 않는다', (tester) async {
    var shareCalls = 0;
    final result = _sampleRouteSearchResult(
      etaSource: 'PLANNED',
      departureTimeIso: '2026-07-18T09:00:00+09:00',
      arrivalTimeIso: '2026-07-18T09:07:00+09:00',
      transportScope: RouteTransportScope.subwayAndItxCheongchun,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(result: result),
          stationRepository: FakeStationSearchRepository(),
          routeShareInvoker: (text, origin) async => shareCalls++,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapFirstRouteResultListItem(tester);
    await tester.pumpAndSettle();
    final shareButton = find.byKey(const Key('routeShareButton'));
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pumpAndSettle();

    expect(shareCalls, 0);
    expect(find.text('경로 요약을 공유하지 못했어요.'), findsOneWidget);
  });

  testWidgets('공유 처리 중에는 버튼과 semantics 재진입을 막는다', (tester) async {
    final shareCompleter = Completer<void>();
    var shareCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(),
          ),
          stationRepository: FakeStationSearchRepository(),
          routeShareInvoker: (text, origin) {
            shareCalls++;
            return shareCompleter.future;
          },
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 18),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapFirstRouteResultListItem(tester);
    await tester.pumpAndSettle();

    final shareButton = find.byKey(const Key('routeShareButton'));
    final shareSemantics = find.bySemanticsLabel('경로 요약 공유');
    await tester.ensureVisible(shareButton);
    await tester.tap(shareButton);
    await tester.pump();
    await tester.tap(shareButton, warnIfMissed: false);
    await tester.pump();

    expect(shareCalls, 1);
    expect(tester.widget<OutlinedButton>(shareButton).onPressed, isNull);
    expect(
      tester
          .getSemantics(shareSemantics)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );

    shareCompleter.complete();
    await tester.pumpAndSettle();

    expect(tester.widget<OutlinedButton>(shareButton).onPressed, isNotNull);
    expect(
      tester
          .getSemantics(shareSemantics)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('광고 repository는 경로 결과와 상세에만 같은 placement로 배선된다', (tester) async {
    final apiClient = _NoInventoryAdApiClient();
    final adRepository = AdRepository(apiClient);
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(),
          stationRepository: FakeStationSearchRepository(),
          adRepository: adRepository,
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
            ),
            destination: const RouteDraftStation(
              id: 'station-sadang',
              nameKo: '사당',
            ),
            lastModifiedAt: DateTime(2026, 7, 11),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    var banner = tester.widget<ActiveAdBanner>(
      find.byKey(const Key('routeResultListAdBanner')),
    );
    expect(banner.repository, same(adRepository));
    expect(banner.placement, AdPlacement.routeResultBottom);

    await tester.ensureVisible(find.byKey(const Key('routeResultListItem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routeResultListItem')));
    await tester.pumpAndSettle();

    banner = tester.widget<ActiveAdBanner>(
      find.byKey(const Key('routeDetailAdBanner')),
    );
    expect(banner.repository, same(adRepository));
    expect(banner.placement, AdPlacement.routeResultBottom);

    await tester.ensureVisible(
      find.byKey(const Key('routeStartGuidanceButton')),
    );
    await tester.tap(find.byKey(const Key('routeStartGuidanceButton')));
    await tester.pumpAndSettle();

    expect(find.byType(ActiveAdBanner), findsNothing);
    expect(apiClient.paths, [
      '/api/ads/active?placement=route-result-bottom',
      '/api/ads/active?placement=route-result-bottom',
    ]);
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
    // #1933 D: 완성된 draft는 자동 검색이 돌아 결과-우선 화면이 뜬다(하단 버튼 없음).
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routeSearchSubmitButton')), findsNothing);
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    // 이동 순서 타임라인이 결과 목록에 인라인으로 이미 노출된다.
    expect(find.text('이동 순서'), findsOneWidget);

    await _tapFirstRouteResultListItem(tester);
    await tester.pumpAndSettle();
    expect(find.text('이동 순서'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    // 상세를 닫아도 결과 목록의 인라인 타임라인은 그대로 있다.
    expect(find.text('이동 순서'), findsOneWidget);

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
      buildEasySubwayTestApp(
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

    // #1933 요구 3: 별도 폼(이동 조건 드롭다운)을 없앴다. 노선도 팝오버로 출발·도착을
    // 정해 결과에 도달한 뒤, 결과-우선 화면의 조용한 프리셋 칩으로 프리셋을 바꾸면
    // 그 자리에서 바로 재검색한다.
    await _openRouteSearchScreen(tester);

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byKey(const Key('routeConditionMobilityChip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('routeConditionMobilityChip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests.last.mobilityType, 'WHEELCHAIR');
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
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    // #1933 요구 3: 노선도 팝오버로 출발·도착을 정해 결과에 도달한 뒤, 결과-우선
    // 화면의 프리셋 칩(→ 프리셋 시트)으로 프리셋을 바꾼다. 폼·제출 버튼은 없다.
    await _openRouteSearchScreen(tester);

    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byKey(const Key('routeConditionMobilityChip')), findsOneWidget);

    await tester.tap(find.byKey(const Key('routeConditionMobilityChip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('mobilityPresetRow-standard')), findsOneWidget);
    expect(find.text('계단 대신 에스컬레이터·엘리베이터로 안내해요'), findsOneWidget);
    expect(
      find.bySemanticsLabel('휠체어 이용, 엘리베이터로만 이동하는 길을 안내해요 · 유아차와 함께일 때도 좋아요'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
    await tester.pumpAndSettle();

    expect(routeRepository.requests.last.mobilityType, 'WHEELCHAIR');
  });

  testWidgets('경로 검색 단순 보기 이동 조건은 스크린리더로도 바꿀 수 있다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();

    try {
      await tester.pumpWidget(
        buildEasySubwayTestApp(
          repository: FakeStationSearchRepository(),
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      // #1933 요구 3: 폼의 이동 조건 요약 대신, 결과-우선 화면의 조용한 프리셋 칩이
      // 스크린리더에서 "경로 시간 기준, <표시명>" 버튼으로 남는다.
      await _openRouteSearchScreen(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('경로 시간 기준, 천천히')),
        isSemantics(label: '경로 시간 기준, 천천히', isButton: true, hasTapAction: true),
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
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        favoriteRouteRepository: favoriteRouteRepository,
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openRouteSearchScreen(tester);
    // #1933 요구 3: 출발·도착은 노선도 팝오버로 이미 정해졌고 자동 검색이 결과를
    // 만들었다(폼·제출 버튼 없음).

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

  testWidgets('경로 상세는 공식 OD 요금의 여섯 값을 표시한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: FakeRouteSearchRepository(
              result: _sampleRouteSearchResult(
                officialOdFareQuote: const OfficialOdFareQuote(
                  originStationId: 'station-sangnoksu',
                  destinationStationId: 'station-sadang',
                  sourceId: approvedOfficialOdFareSourceId,
                  snapshotId: approvedOfficialOdFareSnapshotId,
                  mappingLedgerHash: approvedOfficialOdFareMappingLedgerHash,
                  gnrlCardFare: 1550,
                  gnrlCashFare: 1650,
                  yungCardFare: 800,
                  yungCashFare: 900,
                  childCardFare: 500,
                  childCashFare: 500,
                ),
              ),
            ),
            stationRepository: FakeStationSearchRepository(),
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
      await tester.pumpAndSettle();
      await _openFirstRouteResultDetail(tester);

      for (final (label, amount) in const [
        ('일반 카드', 1550),
        ('일반 현금', 1650),
        ('청소년 카드', 800),
        ('청소년 현금', 900),
        ('어린이 카드', 500),
        ('어린이 현금', 500),
      ]) {
        expect(find.text(label, skipOffstage: false), findsOneWidget);
        expect(
          find.text('$amount원', skipOffstage: false),
          amount == 500 ? findsNWidgets(2) : findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            '$label, $amount원, 오프라인 공식 자료',
            skipOffstage: false,
          ),
          findsOneWidget,
        );
      }
      expect(find.text('공식 OD 요금 정보 없음'), findsNothing);
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('부산 공식 OD의 대체 운임은 QR승차권으로 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RouteSearchScreen(
          repository: FakeRouteSearchRepository(
            result: _sampleRouteSearchResult(
              officialOdFareQuote: const OfficialOdFareQuote(
                originStationId: 'station-1fc7a7c971c8',
                destinationStationId: 'station-6b611916f76a',
                sourceId: 'busan-transportation-official-od-fares',
                snapshotId: 'busan-transportation-official-od-fares-20260713',
                mappingLedgerHash:
                    '9c327840275be5c4583fc9e9cfdd16d2e4ecc06f660d08fd682bf9fe27d72390',
                gnrlCardFare: 1800,
                gnrlCashFare: 1900,
                yungCardFare: 1200,
                yungCashFare: 1300,
                childCardFare: 0,
                childCashFare: 800,
              ),
            ),
          ),
          stationRepository: FakeStationSearchRepository(),
          initialDraft: RouteDraft(
            origin: const RouteDraftStation(
              id: 'station-1fc7a7c971c8',
              nameKo: '서면',
            ),
            destination: const RouteDraftStation(
              id: 'station-6b611916f76a',
              nameKo: '장산',
            ),
            lastModifiedAt: DateTime(2026, 7, 13),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openFirstRouteResultDetail(tester);

    for (final label in const ['일반 QR승차권', '청소년 QR승차권', '어린이 QR승차권']) {
      expect(find.text(label, skipOffstage: false), findsOneWidget);
    }
    expect(find.text('일반 현금', skipOffstage: false), findsNothing);
    expect(find.text('청소년 현금', skipOffstage: false), findsNothing);
    expect(find.text('어린이 현금', skipOffstage: false), findsNothing);
  });

  testWidgets('공식 OD 요금이 없으면 unavailable 상태를 알린다', (tester) async {
    final catalogDatabase = CatalogDatabase.memory();
    addTearDown(catalogDatabase.close);
    await catalogDatabase.seedBaselineIfEmpty();
    var apiBaseReads = 0;
    final dependencies = AppDependencies.resolve(
      catalogDatabase: catalogDatabase,
      apiBaseUri: () {
        apiBaseReads += 1;
        return Uri.parse('https://fare-api-must-not-be-used.example');
      },
      enablePushNotifications: false,
    );
    await tester.runAsync(
      () => dependencies.routeRepository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
          mobilityType: 'STANDARD',
        ),
      ),
    );
    final semanticsHandle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: dependencies.routeRepository,
            stationRepository: dependencies.repository,
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
      await tester.pumpAndSettle();
      await _openFirstRouteResultDetail(tester);

      expect(find.text('공식 OD 요금 정보 없음'), findsOneWidget);
      expect(find.text('오프라인 공식 자료에 없는 경로입니다.'), findsOneWidget);
      expect(
        find.text('연락운송 경계 등 승인되지 않은 경로는 요금을 임의로 계산하지 않습니다.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('공식 OD 요금 정보 없음')), findsOneWidget);
      expect(apiBaseReads, 0);
    } finally {
      semanticsHandle.dispose();
    }
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

    // #1933 요구 3: 완성된 draft가 자동 검색을 이미 돌렸다(제출 버튼 없음).
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

    // #1933 요구 3: 완성된 draft가 자동 검색을 이미 돌렸다(제출 버튼 없음).
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
        buildEasySubwayTestApp(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          favoriteRepository: FakeFavoriteStationRepository(),
          favoriteRouteRepository: favoriteRouteRepository,
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openRouteSearchScreen(tester);
      // #1933 요구 3: 출발·도착은 노선도 팝오버로 이미 정해졌고 자동 검색이 결과를
      // 만들었다(폼·제출 버튼 없음).

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
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        routeFeedbackRepository: routeFeedbackRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openRouteSearchScreen(tester);
    // #1933 요구 3: 출발·도착은 노선도 팝오버로 이미 정해졌고 자동 검색이 결과를
    // 만들었다(폼·제출 버튼 없음).

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
    // #1933 요구 3: 완성된 draft는 자동 검색으로 결과-우선 화면에 도달한다. 그 화면의
    // 얇은 출발 헤더를 탭하면 인라인 역 검색 입력이 열려 편집(→ 재검색)할 수 있다.
    await tester.pumpAndSettle();

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
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        routeFeedbackRepository: FakeRouteFeedbackRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openRouteSearchScreen(tester);
    // #1933 요구 3: 출발·도착은 노선도 팝오버로 이미 정해졌고 자동 검색이 결과를
    // 만들었다(폼·제출 버튼 없음).

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

    // #1933 요구 3: 완성된 draft가 자동 검색을 이미 돌렸다(제출 버튼 없음).
    await tester.pumpAndSettle();

    // #1933 E: 결과-우선 헤더는 긴 두 줄 문장 대신 짧은 캡션 한 줄로 축약한다.
    // 강등 사다리의 정직함(저장된 데이터 기준·실시간/시간표 미표기)은 유지한다.
    expect(find.text('예상 소요시간: 저장된 데이터 기준 · 최근 확인 2026-06-19'), findsNothing);
    // 짧은 캡션(그리고 안내 배지)에 '저장된 데이터 기준'만 남는다.
    expect(find.text('저장된 데이터 기준'), findsWidgets);
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

    // #1933 D: 완성된 draft는 자동 검색으로 결과-우선 화면에 도달한다(하단 버튼 없음).
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

  testWidgets('최초 하차 알림은 route 표시명 대신 repository canonical 역명을 저장한다', (
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
        'station-sadang': _stationDetail(id: 'station-sadang', name: '사당'),
      },
    );

    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: FakeRouteSearchRepository(
        result: _sampleGetOffAlarmRouteResult(
          destinationStationName: '경로가 가진 오래된 사당 이름',
        ),
      ),
      controller: controller,
      stationRepository: stationRepository,
    );
    await tester.ensureVisible(find.text('하차 알림'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('하차 알림'));
    await tester.pumpAndSettle();

    expect(stationRepository.requestedDetailStationIds, ['station-sadang']);
    expect(notifier.scheduledAlarms.single.stationName, '사당');
    expect(
      notifier.scheduledAlarms.single.stationName,
      isNot('station-sadang'),
    );
    expect((await stateRepository.loadActive())?.destination.stationName, '사당');
  });

  for (final badName in ['station-sadang', '   ']) {
    final badNameKind = badName.trim().isEmpty ? 'blank' : 'raw ID';
    testWidgets(
      'foreground refresh는 저장된 $badNameKind 역명을 repository canonical 역명으로 치유한다',
      (tester) async {
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
            'station-sadang': _stationDetail(id: 'station-sadang', name: '사당'),
          },
        );
        final routeRepository = FakeRouteSearchRepository(
          result: _sampleGetOffAlarmRouteResult(
            destinationStationName: '경로가 가진 오래된 사당 이름',
          ),
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
              stationName: badName,
              arrivalAt: DateTime.parse('2026-07-06T09:37:30+09:00'),
              kind: GetOffAlarmKind.destination,
            ),
          ],
          transferAlarmEnabled: false,
        );
        notifier.reset();

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(stationRepository.requestedDetailStationIds, ['station-sadang']);
        expect(notifier.scheduledAlarms.single.stationName, '사당');
        expect(
          (await stateRepository.loadActive())?.destination.stationName,
          '사당',
        );
      },
    );
  }

  testWidgets('foreground 역명 조회 실패는 기존 하차 알림과 구독을 보존한다', (tester) async {
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
      stationRepository: FakeStationSearchRepository(
        stationDetails: {
          'station-sadang': _stationDetail(
            id: 'station-sadang',
            name: 'station-sadang',
          ),
        },
      ),
    );
    await _enableSampleGetOffAlarm(controller);
    final subscriptionBefore = await stateRepository.loadActive();
    notifier.reset();
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reports.add, () async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });

    expect(reports, hasLength(1));
    expect(find.text('하차 알림을 새로 맞추지 못했어요. 이전 경로를 유지해요.'), findsOneWidget);
    expect(notifier.scheduleCalls, 0);
    expect(notifier.cancelCalls, 0);
    expect(await stateRepository.loadActive(), same(subscriptionBefore));
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
    expect(stationRepository.requestedDetailStationIds, [
      'station-geumjeong',
      'station-sadang',
    ]);
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

    // #1933 요구 3: 완성된 draft는 자동 검색으로 결과에 도달한다(폼·제출 버튼 없음).
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
          stationRepository: FakeStationSearchRepository(
            stationDetails: {
              'station-geumjeong': _stationDetail(
                id: 'station-geumjeong',
                name: '금정',
              ),
              'station-sadang': _stationDetail(
                id: 'station-sadang',
                name: '사당',
              ),
            },
          ),
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

    // #1933 요구 3: 완성된 draft가 자동 검색을 이미 돌렸다(제출 버튼 없음).
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
    expect(stationRepository.requestedDetailStationIds, [
      'station-geumjeong',
      'station-sadang',
    ]);
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
    // #1933 D: 완성된 draft는 자동 검색으로 결과-우선 화면에 도달한다(하단 버튼 없음).
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

    // 결과-우선 화면에서 프리셋 칩으로 다른 프리셋을 고르면 그 자리에서 재검색이
    // 돌아 활성 하차 알림을 취소한다.
    await tester.tap(find.byKey(const Key('routeConditionMobilityChip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
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
    // #1933 D: 완성된 draft는 자동 검색으로 결과-우선 화면에 도달한다(하단 버튼 없음).
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
    final routeRepository = FakeRouteSearchRepository(
      result: _sampleGetOffAlarmRouteResult(),
    );
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: routeRepository,
      controller: controller,
      simpleViewEnabled: false,
    );
    await _enableSampleGetOffAlarm(controller);
    notifier.reset();

    // #1933 D: 결과-우선 화면에서 프리셋 칩으로 프리셋을 바꾸면 활성 하차 알림을
    // 취소하고 그 자리에서 새 조건으로 재검색한다(결과는 비우지 않고 갱신).
    await tester.tap(find.byKey(const Key('routeConditionMobilityChip')));
    await tester.pumpAndSettle();
    final wheelchairRow = find.byKey(
      const Key('mobilityPresetRow-stepFree'),
      skipOffstage: false,
    );
    await tester.ensureVisible(wheelchairRow);
    await tester.pumpAndSettle();
    await tester.tap(wheelchairRow);
    await tester.pumpAndSettle();

    expect(notifier.cancelCalls, 1);
    expect(controller.state.enabled, isFalse);
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    expect(routeRepository.requests.last.mobilityType, 'WHEELCHAIR');
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
    final routeRepository = FakeRouteSearchRepository(
      result: _sampleGetOffAlarmRouteResult(),
    );
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: routeRepository,
      controller: controller,
    );
    await _enableSampleGetOffAlarm(controller);
    notifier.reset();

    // #1933 D: 결과-우선 화면에서 프리셋 칩으로 휠체어 이용 프리셋을 고르면 활성 하차
    // 알림을 취소하고 STRICT_STEP_FREE로 재검색한다(결과는 비우지 않고 갱신).
    await tester.tap(find.byKey(const Key('routeConditionMobilityChip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityPresetRow-stepFree')));
    await tester.pumpAndSettle();

    expect(notifier.cancelCalls, 1);
    expect(controller.state.enabled, isFalse);
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    expect(
      routeRepository.requests.last.effectiveConstraintMode,
      'STRICT_STEP_FREE',
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

    // #1933 D: 결과-우선 화면에서 프리셋 칩으로 프리셋을 바꾸려다 하차 알림 취소가
    // 실패하면 프리셋 변경·재검색을 하지 않고 기존 조건·경로·알림을 유지한다.
    await runWithMobileErrorReporter(reports.add, () async {
      await tester.tap(find.byKey(const Key('routeConditionMobilityChip')));
      await tester.pumpAndSettle();
      final wheelchairRow = find.byKey(
        const Key('mobilityPresetRow-stepFree'),
        skipOffstage: false,
      );
      await tester.ensureVisible(wheelchairRow);
      await tester.pumpAndSettle();
      await tester.tap(wheelchairRow);
      await tester.pumpAndSettle();
    });

    expect(reports.single.exception, same(cancelError));
    expect(find.text('하차 알림을 취소하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
    expect(controller.state.enabled, isTrue);
    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);
    // 프리셋은 보통 걸음(STANDARD) 그대로다 — 프리셋 칩 라벨로 확인한다.
    expect(
      find.descendant(
        of: find.byKey(const Key('routeConditionMobilityChip')),
        matching: find.text('보통 걸음 기준'),
      ),
      findsOneWidget,
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

    // #1933 D: 결과-우선 화면에서 프리셋 칩을 열어 같은 프리셋을 다시 고르면
    // 조건이 바뀌지 않아 재검색·알림 취소 없이 활성 알림과 경로를 유지한다.
    await tester.tap(find.byKey(const Key('routeConditionMobilityChip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobilityPresetRow-standard')));
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
      // #1933 요구 3: 완성된 draft가 자동 검색을 이미 돌렸다(제출 버튼 없음).
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
      // #1933 요구 3: 완성된 draft가 자동 검색을 이미 돌렸다(제출 버튼 없음).
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

  testWidgets('빈 rideLegs mismatch는 기존 하차 알림과 구독을 보존한다', (tester) async {
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
            result: _sampleRouteSearchResult(routeSearchId: 'route-2'),
          )
          ..refreshResult = RouteRefreshResult(
            routeSearchId: 'route-2',
            status: 'UPDATED_ROUTE',
            result: _sampleRouteSearchResult(
              routeSearchId: 'route-2',
              steps: const [],
            ),
            refreshedAt: '2026-07-06T09:01:00+09:00',
            etaSource: 'PLANNED',
            etaConfidence: 'MEDIUM',
            sourceLabel: '계획 시간 기준',
          );
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: repository,
      controller: controller,
    );
    await _enableSampleGetOffAlarm(controller);
    final subscriptionBefore = await stateRepository.loadActive();
    notifier.reset();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(repository.refreshRouteSearchIds, ['route-2']);
    expect(notifier.scheduleCalls, 0);
    expect(notifier.cancelCalls, 0);
    expect(await stateRepository.loadActive(), same(subscriptionBefore));
    expect(controller.state.activeRouteId, 'route-1');
  });

  testWidgets('경로 mismatch는 새 경로 역명 조회 전에 종료한다', (tester) async {
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
            result: _sampleRouteSearchResult(routeSearchId: 'route-2'),
          )
          ..refreshResult = RouteRefreshResult(
            routeSearchId: 'route-2',
            status: 'UPDATED_ROUTE',
            result: _sampleRouteSearchResult(
              routeSearchId: 'route-2',
              steps: const [
                RouteSearchStep(
                  sequence: 1,
                  stepType: 'ride',
                  title: '상록수에서 환승역까지 이동',
                  description: '열차를 이용해 이동합니다.',
                  lineId: 'seoul-4',
                  lineName: '수도권 4호선',
                  fromStationId: 'station-sangnoksu',
                  toStationId: 'station-new-transfer',
                  estimatedMinutes: 20,
                  distanceMeters: 9000,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                  plannedArrivalTimeIso: '2026-07-06T09:20:00+09:00',
                ),
                RouteSearchStep(
                  sequence: 2,
                  stepType: 'ride',
                  title: '환승역에서 사당까지 이동',
                  description: '열차를 이용해 이동합니다.',
                  lineId: 'seoul-2',
                  lineName: '수도권 2호선',
                  fromStationId: 'station-new-transfer',
                  toStationId: 'station-sadang',
                  estimatedMinutes: 15,
                  distanceMeters: 4500,
                  includesStairs: false,
                  requiresAccessibilityCheck: true,
                  plannedArrivalTimeIso: '2026-07-06T09:37:30+09:00',
                ),
              ],
            ),
            refreshedAt: '2026-07-06T09:01:00+09:00',
            etaSource: 'PLANNED',
            etaConfidence: 'MEDIUM',
            sourceLabel: '계획 시간 기준',
          );
    await _pumpGetOffAlarmRouteScreen(
      tester,
      repository: repository,
      controller: controller,
    );
    await _enableSampleGetOffAlarm(controller);
    final subscriptionBefore = await stateRepository.loadActive();
    notifier.reset();
    final reports = <FlutterErrorDetails>[];

    await runWithMobileErrorReporter(reports.add, () async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });

    expect(reports, isEmpty);
    expect(notifier.scheduleCalls, 0);
    expect(notifier.cancelCalls, 0);
    expect(await stateRepository.loadActive(), same(subscriptionBefore));
    expect(controller.state.activeRouteId, 'route-1');
  });

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
    // #1933 요구 3: 완성된 draft가 자동 검색을 이미 돌렸다(제출 버튼 없음).
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
    // #1933 요구 3: 완성된 draft가 자동 검색을 이미 돌렸다(제출 버튼 없음).
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
      // #1933 요구 3: 완성된 draft가 자동 검색을 이미 돌렸다(제출 버튼 없음).
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
    // #1933 D: 완성된 draft는 자동 검색으로 결과-우선 화면에 도달한다(하단 버튼 없음).
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
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: FakeRouteSearchRepository(),
        routeFeedbackRepository: FakeRouteFeedbackRepository(),
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    await _openRouteSearchScreen(tester);
    // #1933 요구 3: 출발·도착은 노선도 팝오버로 이미 정해졌고 자동 검색이 결과를
    // 만들었다(폼·제출 버튼 없음).

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
        buildEasySubwayTestApp(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: FakeRouteSearchRepository(),
          routeFeedbackRepository: routeFeedbackRepository,
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openRouteSearchScreen(tester);
      // #1933 요구 3: 출발·도착은 노선도 팝오버로 이미 정해졌고 자동 검색이 결과를
      // 만들었다(폼·제출 버튼 없음).

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
          // #1933 요구 3: 완성된 draft로 진입하면 자동 검색이 결과를 만든다(폼 없음).
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
        buildEasySubwayTestApp(
          repository: stationRepository,
          reportRepository: FakeFacilityReportRepository(),
          routeRepository: routeRepository,
          favoriteRepository: FakeFavoriteStationRepository(),
          initialOnboardingState: _completedOnboardingState(),
        ),
      );

      await _openRouteSearchScreen(tester);
      // #1933 요구 3: 출발·도착은 노선도 팝오버로 이미 정해졌고 자동 검색이 결과를
      // 만들었다(폼·제출 버튼 없음).

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
      buildEasySubwayTestApp(
        repository: stationRepository,
        reportRepository: FakeFacilityReportRepository(),
        routeRepository: routeRepository,
        favoriteRepository: FakeFavoriteStationRepository(),
        initialOnboardingState: _completedOnboardingState(),
      ),
    );

    // #1933 요구 3: 노선도 팝오버로 출발·도착을 정하면 자동 검색이 결과를 만든다.
    await _openRouteSearchScreen(tester);

    expect(find.byKey(const Key('routeResultListItem')), findsOneWidget);

    // 얇은 출발 헤더를 탭해 편집을 시작하고 역명을 지우면(선택이 바뀌면), 이전 결과는
    // 곧바로 숨는다. 별도 폼·제출 버튼 없이 인라인 편집으로만 재검색으로 이어진다.
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    await _openRouteOriginStationInput(tester);
    await tester.enterText(
      find.byKey(const Key('routeOriginStationInput')),
      '상록',
    );
    await tester.pumpAndSettle();

    expect(routeRepository.requests, hasLength(1));
    expect(find.text('출발역과 도착역을 검색 결과에서 선택해 주세요.'), findsNothing);
    expect(find.byKey(const Key('routeResultListItem')), findsNothing);
  });

  testWidgets('자동 검색 중에는 결과 목록을 감추고 완료 후 안내 불가 이유를 보여준다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    final routeRepository = ControlledRouteSearchRepository();

    try {
      // #1933 요구 3: 완성된 draft로 진입하면 폼·제출 버튼 없이 자동 검색이 돈다.
      // 검색 중에는 결과 목록이 없고, 완료되면 blocked 안내가 인라인으로 뜬다.
      await tester.pumpWidget(
        MaterialApp(
          home: RouteSearchScreen(
            repository: routeRepository,
            stationRepository: FakeStationSearchRepository(),
            initialMobilityType: 'SENIOR',
            initialDraft: RouteDraft(
              origin: const RouteDraftStation(
                id: 'station-sangnoksu',
                nameKo: '상록수',
              ),
              destination: const RouteDraftStation(
                id: 'station-nowhere',
                nameKo: '없는역',
              ),
              lastModifiedAt: DateTime(2026, 6, 23),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(routeRepository.requests, hasLength(1));
      expect(find.byKey(const Key('routeResultListItem')), findsNothing);

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
      await _pumpStationDetailForTest(
        tester,
        repository: stationRepository,
        reportRepository: reportRepository,
        locationProvider: FakeCurrentLocationProvider(
          location: const CurrentLocation(
            latitude: 37.302421,
            longitude: 126.866221,
          ),
          needsPermissionRequest: false,
        ),
      );
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
      buildEasySubwayTestApp(
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
      buildEasySubwayTestApp(
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

    // #1936: 시작 → 프리셋 '이대로 시작' → 권한 '나중에 설정'으로 온보딩을 통과한다.
    await tester.tap(find.byKey(const Key('startScreenStartButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingDoneButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardingPermissionSkipButton')));
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
        buildEasySubwayTestApp(
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

    await _pumpStationDetailForTest(
      tester,
      repository: stationRepository,
      reportRepository: reportRepository,
      locationProvider: locationProvider,
    );
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

    await _pumpStationDetailForTest(
      tester,
      repository: stationRepository,
      reportRepository: reportRepository,
      locationProvider: locationProvider,
    );
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

    await _pumpStationDetailForTest(
      tester,
      repository: stationRepository,
      reportRepository: reportRepository,
      locationProvider: locationProvider,
    );
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

    await _pumpStationDetailForTest(
      tester,
      repository: stationRepository,
      reportRepository: reportRepository,
      locationProvider: FakeCurrentLocationProvider(
        error: const CurrentLocationException('위치 권한을 허용해 주세요.'),
        needsPermissionRequest: false,
      ),
    );
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

FavoriteRoute _favoriteRoute({
  String mobilityType = 'SENIOR',
  RouteTransportScope transportScope = RouteTransportScope.subway,
}) {
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
    transportScope: transportScope,
  );
}

NetworkMapData _unifiedRouteMapData() {
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
          sourceId: 'fixture-unified-route-map',
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
          sourceId: 'fixture-unified-route-map',
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
          sourceId: 'fixture-unified-route-map',
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
          sourceId: 'fixture-unified-route-map',
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
        id: 'fixture-unified-route-map',
        name: '통합 노선도 fixture',
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
    this.nearbyCompleter,
    this.networkMapDataByRegion = const {},
    this.networkMapCompletersByRegion = const {},
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
  final Completer<List<StationSearchResult>>? nearbyCompleter;
  final Map<String, NetworkMapData> networkMapDataByRegion;
  final Map<String, Completer<NetworkMapData>> networkMapCompletersByRegion;
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
  final requestedNearbyLimits = <int>[];
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
    requestedNearbyLimits.add(limit);
    final results = nearbyCompleter == null
        ? nearbyResults
        : await nearbyCompleter!.future;
    return results.take(limit).toList(growable: false);
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) async {
    requestedDetailStationIds.add(stationId);
    final completer = stationDetailCompleters[stationId];
    if (completer != null) {
      return completer.future;
    }
    return stationDetails[stationId] ??
        (stationDetail.id == stationId
            ? stationDetail
            : stationId == 'station-sadang'
            ? _stationDetail(id: stationId, name: '사당')
            : stationDetail);
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
    final completer = networkMapCompletersByRegion[region];
    if (completer != null) {
      return completer.future;
    }
    final regional = networkMapDataByRegion[region];
    if (regional != null) {
      return regional;
    }
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

class FakeTimetableStationRepository extends FakeStationSearchRepository
    implements StationTimetableRepository {
  FakeTimetableStationRepository({
    required super.stationDetail,
    super.nearbyResults,
    super.networkMapRegionNames,
    required this.timetables,
    this.timetableLineId = 'seoul-2',
  });

  final Map<StationTimetableDayType, StationTimetable> timetables;
  final String timetableLineId;
  final requestedDayTypes = <StationTimetableDayType>[];

  @override
  Future<StationTimetable> loadStationTimetable({
    required String stationId,
    required String lineId,
    required StationTimetableDayType dayType,
    required DateTime referenceDate,
  }) async {
    requestedDayTypes.add(dayType);
    if (lineId != timetableLineId) {
      return StationTimetable(
        stationId: stationId,
        lineId: lineId,
        dayType: dayType,
        directions: const [],
      );
    }
    return timetables[dayType] ??
        StationTimetable(
          stationId: stationId,
          lineId: lineId,
          dayType: dayType,
          directions: const [],
        );
  }

  @override
  Future<StationTimetable> loadStationTimetableForDate({
    required String stationId,
    required String lineId,
    required DateTime date,
  }) {
    final dayType = switch (date.weekday) {
      DateTime.saturday => StationTimetableDayType.saturday,
      DateTime.sunday => StationTimetableDayType.sundayHoliday,
      _ => StationTimetableDayType.weekday,
    };
    return loadStationTimetable(
      stationId: stationId,
      lineId: lineId,
      dayType: dayType,
      referenceDate: date,
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
  String destinationStationName = '사당',
}) {
  return _sampleRouteSearchResult(
    destinationStationName: destinationStationName,
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
  bool itxTransportScopeEnabled = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RouteSearchScreen(
        repository: repository,
        stationRepository: stationRepository ?? FakeStationSearchRepository(),
        getOffAlarmController: controller,
        simpleViewEnabled: simpleViewEnabled,
        itxTransportScopeEnabled: itxTransportScopeEnabled,
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
  // #1933 D: 완성된 draft는 자동 검색으로 결과-우선 화면에 도달한다(하단 버튼 없음).
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
  FakeRouteSearchRepository({
    RouteSearchResult? result,
    this.error,
    this.errorForRequest,
  }) : result = result ?? _sampleRouteSearchResult();

  final RouteSearchResult result;
  final Object? error;
  final Object? Function(RouteSearchRequest request)? errorForRequest;
  final requests = <RouteSearchRequest>[];
  final refreshRouteSearchIds = <String>[];
  RouteRefreshResult? refreshResult;
  Object? refreshError;
  Completer<RouteRefreshResult>? pendingRefresh;

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    requests.add(request);
    final currentError = errorForRequest?.call(request) ?? error;
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

NetworkMapData _gpsNetworkMapData({
  required String selectedRegion,
  required List<String> regions,
  bool includeNearestStation = true,
}) {
  const sourceId = 'fixture-gps-nearest-station';
  const lineId = 'gps-test-line';
  return NetworkMapData(
    regions: [for (final region in regions) NetworkMapRegion(name: region)],
    selectedRegion: selectedRegion,
    lines: [
      NetworkMapLine(
        id: lineId,
        name: '$selectedRegion 테스트선',
        color: '#00A5DE',
        region: selectedRegion,
      ),
    ],
    stations: includeNearestStation
        ? [
            NetworkMapStation(
              id: 'station-sangnoksu',
              nameKo: '상록수',
              nameEn: 'Sangnoksu',
              region: selectedRegion,
              lineId: lineId,
              stationCode: '448',
              sequence: 1,
              position: const NetworkMapPosition(
                x: 200,
                y: 200,
                labelDx: 0,
                labelDy: 0,
                upPath: '',
                downPath: '',
                sourceId: sourceId,
              ),
            ),
          ]
        : const [],
    edges: const [],
    positionSources: const [
      NetworkMapPositionSource(
        id: sourceId,
        name: 'GPS 최근접 역 테스트',
        licenseStatus: 'fixture-only',
      ),
    ],
    stationLineMemberships: includeNearestStation
        ? const [
            NetworkMapStationLineMembership(
              stationId: 'station-sangnoksu',
              lineId: lineId,
            ),
          ]
        : const [],
  );
}

StationSearchResult _stationResult({
  required String id,
  required String name,
  String region = '수도권',
  int? distanceMeters,
  List<StationSearchLine>? lines,
}) {
  return StationSearchResult(
    id: id,
    nameKo: name,
    nameEn: id,
    region: region,
    dataQualityLevel: 'LEVEL_1',
    dataSourceType: 'OFFICIAL_FILE',
    lastVerifiedAt: '2026-06-13',
    distanceMeters: distanceMeters,
    lines:
        lines ??
        const [
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

class _RecordingRealtimeRepository implements RealtimeRepository {
  final queries = <RealtimeStationQuery>[];

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    queries.add(query);
    return const RealtimeSnapshot(
      status: RealtimeSnapshotStatus.fresh,
      arrivals: [],
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
  List<StationSearchLine>? lines,
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
    lines:
        lines ??
        const [
          StationSearchLine(
            id: 'seoul-2',
            name: '수도권 2호선',
            color: '#00A84D',
            stationCode: '222',
          ),
        ],
  );
}

StationTimetable _stationTimetable(
  StationTimetableDayType dayType, {
  required List<StationTimetableDirection> directions,
  String stationId = 'station-sangnoksu',
  String lineId = 'seoul-2',
}) {
  return StationTimetable(
    stationId: stationId,
    lineId: lineId,
    dayType: dayType,
    directions: directions,
  );
}

RouteSearchResult _sampleRouteSearchResult({
  String routeSearchId = 'route-1',
  String status = 'FOUND',
  String mobilityType = 'SENIOR',
  String etaSource = '',
  String sourceUpdatedAt = '',
  String destinationStationName = '사당',
  String departureTimeIso = '',
  String arrivalTimeIso = '',
  RouteObjective objective = RouteObjective.fastest,
  RouteTransportScope transportScope = RouteTransportScope.subway,
  OfficialOdFareQuote? officialOdFareQuote,
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
    destinationStationName: destinationStationName,
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
        message: '일부 시설 안내는 아직 확인되지 않았어요.',
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
    officialOdFareQuote: officialOdFareQuote,
    departureTimeIso: departureTimeIso,
    arrivalTimeIso: arrivalTimeIso,
    objective: objective,
    transportScope: transportScope,
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
