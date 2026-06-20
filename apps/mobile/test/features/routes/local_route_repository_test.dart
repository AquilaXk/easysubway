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

  test('로컬 경로 추천 이유는 확인되지 않은 접근성 검증을 단정하지 않는다', () async {
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

    final reasons = result.recommendationReasons.join('\n');
    expect(reasons, isNot(contains('확인했어요')));
    expect(reasons, contains('현장 안내'));
  });

  test('로컬 catalog가 모르는 역 경로는 API fallback 없이 차단 결과를 반환한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = FallbackRouteSearchRepository(
      localRepository: LocalRouteRepository(catalogDatabase: database),
    );

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-outside-pack',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.destinationStationName, '확인 필요 역');
    expect(result.isLocalResult, isTrue);
  });

  test('명시적 철도 간선이 없으면 같은 노선 순번만으로 경로를 만들지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.blockedReasons, isNotEmpty);
  });

  test('WALK network edge는 열차 ride 경로로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type
      )
      VALUES (
        'edge-a-c-walk',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'WALK'
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
  });

  test('사용 불가 접근성 edge는 이동 가능 경로로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        accessibility_status
      )
      VALUES (
        'edge-a-c-elevator-down',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE',
        'UNAVAILABLE'
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.blockedReasons, contains('필수 접근성 시설을 사용할 수 없습니다.'));
    expect(result.steps, isEmpty);
  });

  test('확인되지 않은 접근성 edge는 이동 가능 단정 없이 경고를 노출한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        accessibility_status
      )
      VALUES (
        'edge-a-c-unknown-access',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE',
        'UNKNOWN'
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.warnings.map((warning) => warning.code), {
      'LOW_DATA_CONFIDENCE',
      'STALE_ACCESSIBILITY_DATA',
    });
    expect(result.recommendationReasons.join('\n'), isNot(contains('확인했어요')));
  });

  test('구형 catalog의 network_edges는 안전 기본값으로 읽는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('DROP TABLE network_edges');
    await database.customStatement('''
      CREATE TABLE network_edges (
        id TEXT NOT NULL PRIMARY KEY,
        from_node_id TEXT NOT NULL,
        to_node_id TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        edge_type TEXT NOT NULL DEFAULT 'WALK'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type
      )
      VALUES (
        'edge-a-c-legacy',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE'
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.warnings.map((warning) => warning.code), {
      'LOW_DATA_CONFIDENCE',
      'STALE_ACCESSIBILITY_DATA',
    });
  });

  test('service pattern node는 역-노선 node로 뭉개지지 않고 출입구와 연결된다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-b-local',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(
      result.steps.map((step) => step.lineId).where((id) => id.isNotEmpty),
      ['line-test'],
    );
    expect(result.blockedReasons, isEmpty);
  });

  test('service pattern entry가 사용 불가이면 생성 entry로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'entry-a-line-test-local-unavailable',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('필수 접근성 시설을 사용할 수 없습니다.'));
  });

  test('base entry가 사용 불가이면 service pattern entry로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'entry-a-line-test-unavailable',
          'station-a',
          'station-a:line-test',
          90,
          'ENTRY',
          '',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('필수 접근성 시설을 사용할 수 없습니다.'));
  });

  test('명시 service pattern entry는 base entry 확장으로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'entry-a-line-test-available',
          'station-a',
          'station-a:line-test',
          90,
          'ENTRY',
          '',
          'AVAILABLE',
          95
        ),
        (
          'entry-a-line-test-local-unavailable',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('필수 접근성 시설을 사용할 수 없습니다.'));
  });

  test('급행 pattern은 미정차역을 경유한 것처럼 연결하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-c-express',
        'station-a:line-test:EXPRESS',
        'station-c:line-test:EXPRESS',
        150,
        'RIDE',
        'EXPRESS',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final expressResult = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );
    final skippedStopResult = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(expressResult.status, 'FOUND');
    expect(skippedStopResult.status, 'BLOCKED');
    expect(skippedStopResult.steps, isEmpty);
  });

  test('step 소요시간은 접근성 패널티가 아니라 사용된 edge 시간에서 만든다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-b-low-confidence',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'UNKNOWN',
        50
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    final rideStep = result.steps.singleWhere(
      (step) => step.lineId == 'line-test',
    );
    expect(result.status, 'FOUND');
    expect(result.warnings.map((warning) => warning.code), {
      'LOW_DATA_CONFIDENCE',
      'STALE_ACCESSIBILITY_DATA',
    });
    expect(rideStep.estimatedMinutes, 2);
  });

  test('사용 불가 explicit transfer edge는 자동 환승 edge로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test',
          'station-b:line-test',
          'station-a:line-test',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-unavailable',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('필수 접근성 시설을 사용할 수 없습니다.'));
  });

  test('service pattern transfer도 사용 불가 explicit transfer를 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test-local',
          'station-b:line-test:LOCAL',
          'station-a:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-unavailable',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
  });

  test('service pattern explicit transfer는 다른 pattern의 환승을 막지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test-express',
          'station-b:line-test:EXPRESS',
          'station-a:line-test:EXPRESS',
          90,
          'RIDE',
          'EXPRESS',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-local-alt-unavailable',
          'station-a:line-test:LOCAL',
          'station-a:line-alt',
          140,
          'TRANSFER',
          'LOCAL',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'line-test', 'line-alt'},
    );
  });

  test('service pattern ride 뒤 base explicit transfer를 사용할 수 있다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test-local',
          'station-b:line-test:LOCAL',
          'station-a:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-available',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'AVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-b',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'line-test', 'line-alt'},
    );
  });

  test('같은 노선의 서로 다른 service pattern 사이를 환승할 수 있다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        ),
        (
          'edge-b-c-express',
          'station-b:line-test:EXPRESS',
          'station-c:line-test:EXPRESS',
          90,
          'RIDE',
          'EXPRESS',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.blockedReasons, isEmpty);
    expect(
      result.steps.map((step) => step.lineId).where((id) => id.isNotEmpty),
      everyElement('line-test'),
    );
  });

  test('같은 역의 base node와 service pattern node를 연결해 혼합 경로를 찾는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'edge-a-b-base',
          'station-a:line-test',
          'station-b:line-test',
          90,
          'RIDE',
          '',
          'AVAILABLE',
          95
        ),
        (
          'edge-b-c-local',
          'station-b:line-test:LOCAL',
          'station-c:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-c',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.blockedReasons, isEmpty);
    expect(
      result.steps.map((step) => step.lineId).where((id) => id.isNotEmpty),
      everyElement('line-test'),
    );
  });

  test('단방향 explicit transfer가 역방향 환승 경로를 제거하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'edge-c-a-line-alt',
          'station-c:line-alt',
          'station-a:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-available',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'AVAILABLE',
          95
        ),
        (
          'edge-a-b-line-test',
          'station-a:line-test',
          'station-b:line-test',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-c',
        destinationStationId: 'station-b',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'line-test', 'line-alt'},
    );
  });

  test(
    '역방향 service pattern transfer도 사용 불가 explicit transfer를 우회하지 않는다',
    () async {
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await _seedLineWithoutNetworkEdges(database);
      await _addSecondLineForTransferFixture(database);
      await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score
      )
      VALUES
        (
          'edge-c-a-line-alt',
          'station-c:line-alt',
          'station-a:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        ),
        (
          'transfer-a-test-alt-unavailable',
          'station-a:line-test',
          'station-a:line-alt',
          140,
          'TRANSFER',
          '',
          'UNAVAILABLE',
          95
        ),
        (
          'edge-a-b-line-test-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'AVAILABLE',
          95
        )
    ''');
      final repository = LocalRouteRepository(catalogDatabase: database);

      final result = await repository.searchRoute(
        const RouteSearchRequest(
          originStationId: 'station-c',
          destinationStationId: 'station-b',
          mobilityType: 'WHEELCHAIR',
        ),
      );

      expect(result.status, 'BLOCKED');
      expect(result.steps, isEmpty);
    },
  );
}

Future<void> _seedLineWithoutNetworkEdges(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO catalog_metadata (key, value, updated_at)
    VALUES ('schemaVersion', '1', 1771459200000)
  ''');
  await database.customStatement('''
    INSERT INTO operators (id, name_ko, name_en)
    VALUES ('operator-test', '테스트 운영사', 'Test Operator')
  ''');
  await database.customStatement('''
    INSERT INTO lines (id, operator_id, name_ko, name_en, color)
    VALUES ('line-test', 'operator-test', '테스트 노선', 'Test Line', '#123456')
  ''');
  for (final station in const [
    ('station-a', '출발역', 1),
    ('station-b', '중간역', 2),
    ('station-c', '도착역', 3),
  ]) {
    await database.customStatement(
      '''
        INSERT INTO stations (
          id, name_ko, name_en, normalized_name, region,
          data_quality_level, data_source_type
        )
        VALUES (?, ?, ?, ?, '수도권', 'LEVEL_2', 'OFFICIAL_FILE')
      ''',
      [station.$1, station.$2, station.$2, station.$2],
    );
    await database.customStatement(
      '''
        INSERT INTO station_lines (
          station_id, line_id, station_code, line_sequence, platform_info
        )
        VALUES (?, 'line-test', ?, ?, '')
      ''',
      [station.$1, station.$3.toString(), station.$3],
    );
  }
}

Future<void> _addSecondLineForTransferFixture(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO lines (id, operator_id, name_ko, name_en, color)
    VALUES ('line-alt', 'operator-test', '대체 노선', 'Alt Line', '#654321')
  ''');
  for (final station in const [('station-a', 'A1'), ('station-c', 'C2')]) {
    await database.customStatement(
      '''
        INSERT INTO station_lines (
          station_id, line_id, station_code, line_sequence, platform_info
        )
        VALUES (?, 'line-alt', ?, 1, '')
      ''',
      [station.$1, station.$2],
    );
  }
}
