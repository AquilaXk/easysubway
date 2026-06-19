import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart'
    hide InternalRouteNode;
import 'package:easysubway_mobile/features/internal_route/data/local_internal_route_repository.dart';
import 'package:easysubway_mobile/internal_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('로컬 내부 이동 repository는 catalog 내부 이동 테이블에서 경로를 계산한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO internal_route_nodes (id, station_id, label, node_type)
      VALUES
        ('node-entry', 'station-sangnoksu', '1번 출구 엘리베이터', 'ELEVATOR'),
        ('node-platform', 'station-sangnoksu', '4호선 승강장', 'PLATFORM')
      ''');
    await database.customStatement('''
      INSERT INTO internal_route_edges (id, from_node_id, to_node_id, duration_seconds, instruction)
      VALUES
        ('edge-entry-platform', 'node-entry', 'node-platform', 90, '엘리베이터와 넓은 통로를 이용합니다.')
      ''');

    final repository = LocalInternalRouteRepository(catalogDatabase: database);

    final nodes = await repository.listRouteNodes('station-sangnoksu');
    final result = await repository.searchInternalRoute(
      const InternalRouteRequest(
        stationId: 'station-sangnoksu',
        fromNodeId: 'node-entry',
        toNodeId: 'node-platform',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(nodes.map((node) => node.displayLabel), ['1번 출구 엘리베이터', '4호선 승강장']);
    expect(result.status, 'FOUND');
    expect(result.totalEstimatedSeconds, 90);
    expect(result.steps.single.edgeId, 'edge-entry-platform');
    expect(result.steps.single.guidance, '엘리베이터와 넓은 통로를 이용합니다.');
  });

  test('로컬 내부 이동 데이터가 없으면 API repository로 fallback한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final apiRepository = _RecordingInternalRouteRepository();
    final repository = FallbackInternalRouteRepository(
      localRepository: LocalInternalRouteRepository(catalogDatabase: database),
      apiRepository: apiRepository,
    );

    final nodes = await repository.listRouteNodes('station-sangnoksu');

    expect(apiRepository.nodeStationIds, ['station-sangnoksu']);
    expect(nodes.single.displayLabel, 'API 내부 노드');
  });
}

class _RecordingInternalRouteRepository implements InternalRouteRepository {
  final nodeStationIds = <String>[];

  @override
  Future<List<InternalRouteNode>> listRouteNodes(String stationId) async {
    nodeStationIds.add(stationId);
    return [
      InternalRouteNode(
        id: 'api-node',
        stationId: stationId,
        type: 'ENTRANCE',
        name: 'API 내부 노드',
        facilityId: '',
        displayLabel: 'API 내부 노드',
      ),
    ];
  }

  @override
  Future<InternalRouteResult> searchInternalRoute(
    InternalRouteRequest request,
  ) async {
    return InternalRouteResult(
      stationId: request.stationId,
      stationName: '상록수',
      fromNodeId: request.fromNodeId,
      fromNodeName: '출발',
      toNodeId: request.toNodeId,
      toNodeName: '도착',
      mobilityType: request.mobilityType,
      status: 'FOUND',
      totalDistanceMeters: 0,
      totalEstimatedSeconds: 0,
      steps: const [],
      warnings: const [],
      blockedReasons: const [],
    );
  }
}
