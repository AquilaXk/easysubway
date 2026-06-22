import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/main.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:easysubway_mobile/station_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기본 앱은 출시 범위에서 원격 개인 데이터 저장소를 만들지 않는다', () {
    final app = EasySubwayApp(
      repository: _UnusedStationSearchRepository(),
      reportRepository: _UnusedFacilityReportRepository(),
      routeRepository: _UnusedRouteSearchRepository(),
    );

    expect(app.favoriteRepository, isNull);
    expect(app.favoriteFacilityRepository, isNull);
    expect(app.favoriteRouteRepository, isNull);
    expect(app.notificationRepository, isNull);
    expect(app.notificationPermissionProvider, isNull);
  });

  test('푸시 알림을 명시적으로 켜도 인증 없는 원격 저장소는 만들지 않는다', () {
    final app = EasySubwayApp(
      repository: _UnusedStationSearchRepository(),
      reportRepository: _UnusedFacilityReportRepository(),
      routeRepository: _UnusedRouteSearchRepository(),
      enablePushNotifications: true,
    );

    expect(app.favoriteRouteRepository, isNull);
    expect(app.notificationRepository, isNull);
    expect(app.notificationPermissionProvider, isNull);
  });
}

class _UnusedStationSearchRepository implements StationSearchRepository {
  @override
  Future<List<StationSearchResult>> searchStations(String query) {
    throw UnimplementedError();
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
}

class _UnusedFacilityReportRepository implements FacilityReportRepository {
  @override
  Future<FacilityReportResult> createReport(FacilityReportRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) {
    throw UnimplementedError();
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() {
    throw UnimplementedError();
  }
}

class _UnusedRouteSearchRepository implements RouteSearchRepository {
  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) {
    throw UnimplementedError();
  }
}
