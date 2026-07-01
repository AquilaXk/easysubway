import 'dart:math' as math;
import 'dart:ui';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:easysubway_mobile/onboarding.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('접근성 색상 토큰은 일반 텍스트 대비 기준을 넘는다', () {
    const appBackground = Color(0xFFF6F8F9);

    expect(
      _contrastRatio(EasySubwayAccessibleColors.mint, Colors.white),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrastRatio(EasySubwayAccessibleColors.mutedText, appBackground),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('모바일 접근성 QA 기준선은 시스템 접근성과 고대비 홈 화면을 검증한다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(
          boldText: true,
          disableAnimations: true,
          reduceMotion: true,
        );

    try {
      await tester.pumpWidget(
        EasySubwayApp(
          repository: _AccessibilityStationSearchRepository(),
          reportRepository: _AccessibilityFacilityReportRepository(),
          routeRepository: _AccessibilityRouteSearchRepository(),
          locationProvider: _AccessibilityCurrentLocationProvider(),
          initialOnboardingState: _completedOnboardingState(
            preferences: const OnboardingViewPreferences(
              largeTextEnabled: false,
              highContrastEnabled: true,
              simpleViewEnabled: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final homeContext = tester.element(find.byType(HomeScreen));
      expect(MediaQuery.of(homeContext).highContrast, isTrue);
      expect(MediaQuery.boldTextOf(homeContext), isTrue);
      expect(MediaQuery.disableAnimationsOf(homeContext), isTrue);
      expect(MediaQuery.textScalerOf(homeContext).scale(20), closeTo(20, 0.01));
      expect(
        Theme.of(homeContext).colorScheme.primary,
        const Color(0xFF003D40),
      );
      expect(
        Theme.of(homeContext).textTheme.bodyLarge?.fontWeight,
        FontWeight.w700,
      );
      expect(
        Theme.of(homeContext).appBarTheme.titleTextStyle?.fontWeight,
        FontWeight.w900,
      );
      expect(
        Theme.of(homeContext).filledButtonTheme.style?.textStyle
            ?.resolve(<WidgetState>{})
            ?.fontWeight,
        FontWeight.w900,
      );
      expect(find.bySemanticsLabel('지하철역 검색'), findsOneWidget);

      final menuSemantics = tester
          .getSemantics(find.byKey(const Key('networkMapMenuButton')))
          .getSemanticsData();
      final stationSearchSemantics = tester
          .getSemantics(find.byKey(const Key('stationSearchButton')))
          .getSemanticsData();
      final nearbyStationSemantics = tester
          .getSemantics(find.byKey(const Key('nearbyStationButton')))
          .getSemanticsData();

      expect(menuSemantics.hasAction(SemanticsAction.tap), isTrue);
      expect(stationSearchSemantics.label, contains('지하철역 검색'));
      expect(stationSearchSemantics.hasAction(SemanticsAction.tap), isTrue);
      expect(nearbyStationSemantics.label, contains('현재 위치로 주변 역 찾기'));
      expect(nearbyStationSemantics.hasAction(SemanticsAction.tap), isTrue);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      semanticsHandle.dispose();
    }
  });
}

double _contrastRatio(Color foreground, Color background) {
  final light = math.max(
    _relativeLuminance(foreground),
    _relativeLuminance(background),
  );
  final dark = math.min(
    _relativeLuminance(foreground),
    _relativeLuminance(background),
  );
  return (light + 0.05) / (dark + 0.05);
}

double _relativeLuminance(Color color) {
  final red = _linearRgb(color.r);
  final green = _linearRgb(color.g);
  final blue = _linearRgb(color.b);
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

double _linearRgb(double channel) {
  return channel <= 0.03928
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

OnboardingState _completedOnboardingState({
  required OnboardingViewPreferences preferences,
}) {
  return OnboardingState.completed(
    result: OnboardingResult(
      profile: mobilityProfileOptions.first,
      preferences: preferences,
    ),
  );
}

class _AccessibilityStationSearchRepository implements StationSearchRepository {
  @override
  Future<List<StationSearchResult>> searchStations(String query) {
    throw UnimplementedError('접근성 기준선 테스트는 역 검색 API를 호출하지 않는다.');
  }

  @override
  Future<List<StationSearchResult>> searchNearbyStations(
    CurrentLocation location, {
    int radiusMeters = 2000,
    int limit = 10,
  }) {
    throw UnimplementedError('접근성 기준선 테스트는 주변 역 API를 호출하지 않는다.');
  }

  @override
  Future<StationDetail> getStationDetail(String stationId) {
    throw UnimplementedError('접근성 기준선 테스트는 역 상세 API를 호출하지 않는다.');
  }

  @override
  Future<List<StationExitInfo>> listStationExits(String stationId) {
    throw UnimplementedError('접근성 기준선 테스트는 출구 API를 호출하지 않는다.');
  }

  @override
  Future<List<StationFacilityInfo>> listStationFacilities(String stationId) {
    throw UnimplementedError('접근성 기준선 테스트는 시설 API를 호출하지 않는다.');
  }
}

class _AccessibilityRouteSearchRepository implements RouteSearchRepository {
  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) {
    throw UnimplementedError('접근성 기준선 테스트는 경로 검색 API를 호출하지 않는다.');
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) {
    throw UnimplementedError('접근성 기준선 테스트는 경로 refresh API를 호출하지 않는다.');
  }
}

class _AccessibilityFacilityReportRepository
    implements FacilityReportRepository {
  @override
  Future<FacilityReportResult> createReport(FacilityReportRequest request) {
    throw UnimplementedError('접근성 기준선 테스트는 신고 API를 호출하지 않는다.');
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) {
    throw UnimplementedError('접근성 기준선 테스트는 신고 상세 API를 호출하지 않는다.');
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() {
    throw UnimplementedError('접근성 기준선 테스트는 내 신고 API를 호출하지 않는다.');
  }
}

class _AccessibilityCurrentLocationProvider implements CurrentLocationProvider {
  @override
  Future<bool> needsLocationPermissionRequest() async => false;

  @override
  Future<CurrentLocation> currentLocation() async {
    return const CurrentLocation(latitude: 37.3028, longitude: 126.8665);
  }

  @override
  Future<bool> openLocationSettings() async => true;
}
