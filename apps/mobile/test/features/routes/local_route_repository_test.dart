import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/internal_route/data/local_internal_route_repository.dart';
import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog DB가 있으면 기본 경로 repository는 route API 대신 로컬 구현을 사용한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: database,
      enableAnonymousAuth: false,
      enablePushNotifications: false,
    );

    expect(dependencies.routeRepository, isA<FallbackRouteSearchRepository>());
    expect(
      dependencies.internalRouteRepository,
      isA<FallbackInternalRouteRepository>(),
    );
  });

  test('로컬 경로 repository는 baseline catalog에서 상록수-사당 경로를 계산한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();

    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.originStationName, '상록수');
    expect(result.destinationStationName, '사당');
    expect(result.lineId, 'seoul-4');
    expect(result.lineName, '수도권 4호선');
    expect(result.isLocalResult, isTrue);
    expect(
      result.steps.map((step) => step.lineId).where((id) => id.isNotEmpty),
      ['seoul-4'],
    );
    expect(result.blockedReasons, isEmpty);
  });

  test('로컬 catalog가 모르는 역 경로는 API repository로 fallback한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final apiRepository = _RecordingRouteSearchRepository();
    final repository = FallbackRouteSearchRepository(
      localRepository: LocalRouteRepository(catalogDatabase: database),
      apiRepository: apiRepository,
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-outside-pack',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(apiRepository.requests, hasLength(1));
    expect(
      apiRepository.requests.single.destinationStationId,
      'station-outside-pack',
    );
    expect(result.routeSearchId, 'api-route-1');
    expect(result.isLocalResult, isFalse);
  });
}

class _RecordingRouteSearchRepository implements RouteSearchRepository {
  final requests = <RouteSearchRequest>[];

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    requests.add(request);
    return RouteSearchResult(
      routeSearchId: 'api-route-1',
      originStationId: request.originStationId,
      originStationName: '상록수',
      destinationStationId: request.destinationStationId,
      destinationStationName: '외부역',
      mobilityType: request.mobilityType,
      status: 'FOUND',
      lineId: 'api-line',
      lineName: 'API 노선',
      score: 80,
      steps: const [],
      warnings: const [],
      blockedReasons: const [],
      createdAt: '2026-06-19T00:00:00',
    );
  }
}
