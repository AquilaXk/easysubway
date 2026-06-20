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

  test('로컬 내부 이동 repository는 catalog edge metadata를 단계에 보존한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      INSERT INTO internal_route_nodes (id, station_id, label, node_type)
      VALUES
        ('node-concourse', 'station-sangnoksu', '대합실', 'CONCOURSE'),
        ('node-platform', 'station-sangnoksu', '4호선 승강장', 'PLATFORM')
      ''');
    await database.customStatement('''
      INSERT INTO internal_route_edges (
        id,
        from_node_id,
        to_node_id,
        edge_type,
        distance_meters,
        duration_seconds,
        includes_stairs,
        requires_elevator,
        requires_escalator,
        slope_level,
        width_level,
        reliability_score,
        instruction
      )
      VALUES (
        'edge-concourse-platform',
        'node-concourse',
        'node-platform',
        'ELEVATOR',
        38,
        95,
        0,
        1,
        0,
        2,
        3,
        72,
        '엘리베이터를 타고 승강장으로 내려갑니다.'
      )
      ''');

    final repository = LocalInternalRouteRepository(catalogDatabase: database);

    final result = await repository.searchInternalRoute(
      const InternalRouteRequest(
        stationId: 'station-sangnoksu',
        fromNodeId: 'node-concourse',
        toNodeId: 'node-platform',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final step = result.steps.single;
    expect(step.edgeType, 'ELEVATOR');
    expect(step.distanceMeters, 38);
    expect(step.estimatedSeconds, 95);
    expect(step.includesStairs, isFalse);
    expect(step.requiresElevator, isTrue);
    expect(step.requiresEscalator, isFalse);
    expect(step.slopeLevel, 2);
    expect(step.widthLevel, 3);
    expect(step.reliabilityScore, 72);
    expect(result.warnings.map((warning) => warning.code), [
      'LOW_DATA_CONFIDENCE',
    ]);
  });

  test('로컬 내부 이동 repository는 미확인 접근성 edge를 휠체어 경로로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement(
      "ALTER TABLE internal_route_edges ADD COLUMN accessibility_status TEXT NOT NULL DEFAULT 'UNKNOWN'",
    );
    await database.customStatement('''
      INSERT INTO internal_route_nodes (id, station_id, label, node_type)
      VALUES
        ('node-entry-unknown', 'station-sangnoksu', '출입구 엘리베이터', 'ELEVATOR'),
        ('node-platform-unknown', 'station-sangnoksu', '4호선 승강장', 'PLATFORM')
      ''');
    await database.customStatement('''
      INSERT INTO internal_route_edges (
        id,
        from_node_id,
        to_node_id,
        edge_type,
        duration_seconds,
        requires_elevator,
        accessibility_status,
        instruction
      )
      VALUES (
        'edge-entry-platform-unknown',
        'node-entry-unknown',
        'node-platform-unknown',
        'ELEVATOR',
        90,
        1,
        'UNKNOWN',
        '엘리베이터 상태 확인이 필요한 내부 이동 경로입니다.'
      )
      ''');

    final repository = LocalInternalRouteRepository(catalogDatabase: database);

    final result = await repository.searchInternalRoute(
      const InternalRouteRequest(
        stationId: 'station-sangnoksu',
        fromNodeId: 'node-entry-unknown',
        toNodeId: 'node-platform-unknown',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('내부 이동 경로 접근성 상태를 확인할 수 없습니다.'));
  });

  test('로컬 내부 이동 repository는 구스키마 catalog edge를 기본값으로 읽는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('DROP TABLE internal_route_edges');
    await database.customStatement('''
      CREATE TABLE internal_route_edges (
        id TEXT NOT NULL PRIMARY KEY,
        from_node_id TEXT NOT NULL,
        to_node_id TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        instruction TEXT NOT NULL DEFAULT ''
      )
      ''');
    await database.customStatement('''
      INSERT INTO internal_route_nodes (id, station_id, label, node_type)
      VALUES
        ('node-old-entry', 'station-sangnoksu', '구스키마 출입구', 'ENTRANCE'),
        ('node-old-platform', 'station-sangnoksu', '구스키마 승강장', 'PLATFORM')
      ''');
    await database.customStatement('''
      INSERT INTO internal_route_edges (
        id,
        from_node_id,
        to_node_id,
        duration_seconds,
        instruction
      )
      VALUES (
        'edge-old-entry-platform',
        'node-old-entry',
        'node-old-platform',
        80,
        '기존 데이터팩 내부 이동 안내입니다.'
      )
      ''');

    final repository = LocalInternalRouteRepository(catalogDatabase: database);

    final result = await repository.searchInternalRoute(
      const InternalRouteRequest(
        stationId: 'station-sangnoksu',
        fromNodeId: 'node-old-entry',
        toNodeId: 'node-old-platform',
        mobilityType: 'SENIOR',
      ),
    );

    final step = result.steps.single;
    expect(step.edgeType, 'WALK');
    expect(step.distanceMeters, 0);
    expect(step.estimatedSeconds, 80);
    expect(step.includesStairs, isFalse);
    expect(step.requiresElevator, isFalse);
    expect(step.requiresEscalator, isFalse);
    expect(step.slopeLevel, 1);
    expect(step.widthLevel, 2);
    expect(step.reliabilityScore, 100);
    expect(result.warnings, isEmpty);
  });

  test('로컬 내부 이동 데이터가 없으면 API fallback 없이 빈 노드 목록을 반환한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = FallbackInternalRouteRepository(
      localRepository: LocalInternalRouteRepository(catalogDatabase: database),
    );

    final nodes = await repository.listRouteNodes('station-sangnoksu');

    expect(nodes, isEmpty);
  });
}
