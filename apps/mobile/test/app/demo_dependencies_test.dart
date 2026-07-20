import 'package:easysubway_mobile/app/demo_dependencies.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo 즐겨찾기 역 repository는 고정 fixture와 no-op 변경 계약을 유지한다', () async {
    const repository = DemoFavoriteStationRepository();

    final stations = await repository.listFavoriteStations();
    expect(stations, hasLength(1));
    final station = stations.single;
    expect(station.userId, 'demo-user');
    expect(station.stationId, 'station-sangnoksu');
    expect(station.nameKo, '상록수');
    expect(station.nameEn, 'Sangnoksu');
    expect(station.region, '수도권');
    expect(station.dataQualityLevel, 'LEVEL_1');
    expect(station.dataSourceType, 'OFFICIAL_FILE');
    expect(station.lastVerifiedAt, '2026-06-13');
    expect(station.addedAt, '2026-06-13T10:00:00');
    expect(station.lines, hasLength(1));
    expect(station.lines.single.id, 'seoul-4');
    expect(station.lines.single.name, '수도권 4호선');
    expect(station.lines.single.color, '#00A5DE');
    expect(station.lines.single.stationCode, '448');

    expect(
      (await repository.saveFavoriteStation('ignored')).stationId,
      'station-sangnoksu',
    );
    await repository.removeFavoriteStation('station-sangnoksu');
    expect(await repository.listFavoriteStations(), hasLength(1));
  });

  test('demo 즐겨찾기 시설 repository는 고정 fixture와 no-op 변경 계약을 유지한다', () async {
    const repository = DemoFavoriteFacilityRepository();

    final facilities = await repository.listFavoriteFacilities();
    expect(facilities, hasLength(1));
    final facility = facilities.single;
    expect(facility.userId, 'demo-user');
    expect(facility.facilityId, 'facility-sangnoksu-elevator-3');
    expect(facility.stationId, 'station-sangnoksu');
    expect(facility.stationNameKo, '상록수');
    expect(facility.stationNameEn, 'Sangnoksu');
    expect(facility.exitId, 'exit-sangnoksu-3');
    expect(facility.type, 'ELEVATOR');
    expect(facility.name, '3번 출구 엘리베이터');
    expect(facility.floorFrom, '1F');
    expect(facility.floorTo, 'B1');
    expect(facility.description, '3번 출구 앞');
    expect(facility.status, 'NEEDS_CHECK');
    expect(facility.dataConfidence, 'HIGH');
    expect(facility.dataSourceType, 'OFFICIAL_FILE');
    expect(facility.fieldValidationStatus, 'UNKNOWN');
    expect(facility.lastUpdatedAt, '2026-06-12');
    expect(facility.addedAt, '2026-06-14T10:00:00');

    expect(
      (await repository.saveFavoriteFacility('ignored')).facilityId,
      'facility-sangnoksu-elevator-3',
    );
    await repository.removeFavoriteFacility('facility-sangnoksu-elevator-3');
    expect(await repository.listFavoriteFacilities(), hasLength(1));
  });

  test('demo 즐겨찾기 경로 repository는 고정 fixture와 no-op 변경 계약을 유지한다', () async {
    const repository = DemoFavoriteRouteRepository();

    final routes = await repository.listFavoriteRoutes();
    expect(routes, hasLength(1));
    final route = routes.single;
    expect(route.userId, 'demo-user');
    expect(route.favoriteRouteId, 'route-1');
    expect(route.routeSearchId, 'route-1');
    expect(route.originStationId, 'station-sangnoksu');
    expect(route.originStationName, '상록수');
    expect(route.destinationStationId, 'station-sadang');
    expect(route.destinationStationName, '사당');
    expect(route.mobilityType, 'SENIOR');
    expect(route.status, 'FOUND');
    expect(route.lineId, 'seoul-4');
    expect(route.lineName, '수도권 4호선');
    expect(route.score, 92);
    expect(route.routeCreatedAt, '2026-06-13T09:00:00');
    expect(route.addedAt, '2026-06-14T10:00:00');

    expect(
      (await repository.saveFavoriteRoute('ignored')).favoriteRouteId,
      'route-1',
    );
    await repository.removeFavoriteRoute('route-1');
    expect(await repository.listFavoriteRoutes(), hasLength(1));
  });

  test('demo 검색 기록은 최신순과 중복 제거 및 삭제 계약을 유지한다', () async {
    final repository = DemoSearchHistoryRepository();

    expect(await repository.listRecentQueries(), ['상록수', '사당']);
    await repository.recordSearch(' 사당 ');
    expect(await repository.listRecentQueries(), ['사당', '상록수']);
    await repository.recordSearch('  ');
    expect(await repository.listRecentQueries(), ['사당', '상록수']);
    await repository.recordSearch('강남');
    expect(await repository.listRecentQueries(), ['강남', '사당', '상록수']);
    await repository.removeSearch(' 사당 ');
    expect(await repository.listRecentQueries(), ['강남', '상록수']);
    await repository.clearSearches();
    expect(await repository.listRecentQueries(), isEmpty);
  });
}
