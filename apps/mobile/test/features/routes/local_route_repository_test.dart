import 'package:easysubway_mobile/app/app_dependencies.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog DB가 있으면 기본 경로 repository는 API 주소 없이 로컬 결과를 반환한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();

    final dependencies = AppDependencies.resolve(
      catalogDatabase: database,
      reportRepository: const UnavailableFacilityReportRepository(),
      apiBaseUri: () {
        throw StateError('Local route defaults must not read API base URL.');
      },
      enablePushNotifications: false,
    );

    final routeResult = await dependencies.routeRepository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );
    final internalNodes = await dependencies.internalRouteRepository
        .listRouteNodes('station-sangnoksu');

    expect(routeResult.status, 'FOUND');
    expect(routeResult.isLocalResult, isTrue);
    expect(internalNodes, isEmpty);
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
    expect(result.score, greaterThan(100));
    expect(result.burdenCost, result.score);
    expect(
      result.estimatedDurationSeconds,
      result.steps.fold<int>(
        0,
        (sum, step) => sum + step.estimatedMinutes * 60,
      ),
    );
    expect(
      result.walkingDistanceMeters,
      result.steps
          .where((step) => step.isWalkingStep)
          .fold<int>(0, (sum, step) => sum + step.distanceMeters),
    );
    expect(result.transferCount, 0);
    expect(result.evidenceSummary, contains('DURATION_ESTIMATED'));
    expect(result.evidenceSummary, contains('DISTANCE_UNKNOWN'));
    expect(
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'seoul-4'},
    );
    expect(result.blockedReasons, isEmpty);
  });

  test('기존 baseline catalog도 명시 access edge를 보강해 휠체어 경로를 유지한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      DELETE FROM network_edges
      WHERE id IN (
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''');

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
    expect(result.blockedReasons, isEmpty);
    expect(
      result.steps.map((step) => step.stepType),
      containsAll(['entry', 'exit']),
    );
    expect(result.steps.expand((step) => step.evidenceSources), isEmpty);
  });

  test('기존 baseline access edge 값은 보강 과정에서 덮어쓰지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    await database.customStatement('''
      UPDATE network_edges
      SET accessibility_status = 'UNAVAILABLE',
          duration_seconds = 999,
          reliability_score = 30
      WHERE id = 'entry-sangnoksu-seoul-4'
    ''');

    await database.seedBaselineIfEmpty();

    final edge = await database.customSelect('''
            SELECT accessibility_status, duration_seconds, reliability_score
            FROM network_edges
            WHERE id = 'entry-sangnoksu-seoul-4'
          ''').getSingle();
    expect(edge.read<String>('accessibility_status'), 'UNAVAILABLE');
    expect(edge.read<int>('duration_seconds'), 999);
    expect(edge.read<int>('reliability_score'), 30);
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

  test('로컬 경로 단계는 행동 이유 근거와 시간 거리 출처를 함께 제공한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, distance_meters,
        edge_type, stair_access_state, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-b-local',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        830,
        'RIDE',
        'STEP_FREE',
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

    final rideStep = result.steps.singleWhere(
      (step) => step.stepType == 'ride',
    );
    expect(rideStep.actionTitle, '열차 이동');
    expect(rideStep.actionDetail, contains('출발역에서 중간역까지'));
    expect(rideStep.reason, '선택한 경로 기준으로 안내합니다.');
    expect(rideStep.evidenceSources, isEmpty);
    expect(rideStep.timeSource, 'STATIC_ESTIMATE');
    expect(rideStep.distanceSource, 'MEASURED');
    expect(rideStep.confidenceLabel, '높은 신뢰도');
  });

  test('계단 없는 동선 여부가 미확인인 선택 경로는 높은 신뢰도로 표시하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
    );
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, distance_meters,
        edge_type, stair_access_state, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-b-unknown-stair',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        830,
        'RIDE',
        'UNKNOWN',
        'AVAILABLE',
        95
      )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    final rideStep = result.steps.singleWhere(
      (step) => step.lineId == 'line-test',
    );
    expect(result.status, 'FOUND');
    expect(
      result.warnings.map((warning) => warning.code),
      contains('STAIR_ONLY_ACCESS_UNKNOWN'),
    );
    expect(rideStep.confidenceLabel, '확인 필요');
  });

  test('로컬 경로 추천 이유와 음성 안내는 선택 경로에 없는 계단 차단 근거를 말하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES (
        'edge-a-b-local',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'STEP_FREE',
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

    const unusedEvidenceClaim = '차단된 계단 구간은 제외했습니다.';
    expect(result.status, 'FOUND');
    expect(result.steps.any((step) => step.includesStairs), isFalse);
    expect(
      result.recommendationReasons.join('\n'),
      isNot(contains(unusedEvidenceClaim)),
    );
    expect(result.semanticLabel, isNot(contains(unusedEvidenceClaim)));
  });

  test('로컬 catalog가 모르는 역 경로는 API fallback 없이 차단 결과를 반환한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await database.seedBaselineIfEmpty();
    final repository = LocalFirstRouteSearchRepository(
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
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state
      )
      VALUES (
        'edge-a-c-walk',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'WALK',
        'STEP_FREE'
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
        stair_access_state, accessibility_status
      )
      VALUES (
        'edge-a-c-elevator-down',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE',
        'STEP_FREE',
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

  test('확인되지 않은 접근성 edge는 휠체어 경로에서 이동 가능으로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status
      )
      VALUES (
        'edge-a-c-unknown-access',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE',
        'STEP_FREE',
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

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('접근성 시설 이용 가능 여부를 확인할 수 없습니다.'));
    expect(result.warnings, isEmpty);
    expect(result.recommendationReasons.join('\n'), isNot(contains('확인했어요')));
  });

  test('구형 catalog의 network_edges는 미확인 접근성 상태로 안전하게 차단한다', () async {
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

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('계단 없는 동선 여부를 확인할 수 없습니다.'));
    expect(result.warnings, isEmpty);
  });

  test('구형 catalog의 계단 여부 false 기본값은 계단 없는 경로로 단정하지 않는다', () async {
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
        edge_type TEXT NOT NULL DEFAULT 'WALK',
        includes_stairs INTEGER NOT NULL DEFAULT 0,
        accessibility_status TEXT NOT NULL DEFAULT 'AVAILABLE'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        includes_stairs, accessibility_status
      )
      VALUES (
        'edge-a-c-legacy-stair-default',
        'station-a:line-test',
        'station-c:line-test',
        180,
        'RIDE',
        0,
        'AVAILABLE'
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
    expect(result.blockedReasons, contains('계단 없는 동선 여부를 확인할 수 없습니다.'));
    expect(result.warnings, isEmpty);
  });

  test('구형 catalog schema는 baseline access backfill 없이 계속 열린다', () async {
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

    await database.seedBaselineIfEmpty();

    final rows = await database
        .customSelect(
          "SELECT id FROM network_edges WHERE id LIKE 'entry-%' OR id LIKE 'exit-%'",
        )
        .get();
    expect(rows, isEmpty);
  });

  test('service pattern node는 역-노선 node로 뭉개지지 않고 출입구와 연결된다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES (
        'edge-a-b-local',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'STEP_FREE',
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
      result.steps
          .map((step) => step.lineId)
          .where((id) => id.isNotEmpty)
          .toSet(),
      {'line-test'},
    );
    expect(result.blockedReasons, isEmpty);
  });

  test('생성 access edge만 있는 휠체어 경로는 검증된 경로로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
    );
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status, reliability_score
      )
      VALUES (
        'edge-a-b-step-free',
        'station-a:line-test',
        'station-b:line-test',
        120,
        'RIDE',
        'STEP_FREE',
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
    expect(result.blockedReasons, contains('계단 없는 동선 여부를 확인할 수 없습니다.'));
  });

  test('생성 transfer edge만 있는 휠체어 환승 경로는 검증된 경로로 안내하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(
      database,
      includeExplicitAccessEdges: false,
    );
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status, reliability_score
      )
      VALUES
        (
          'entry-b-line-test-explicit',
          'station-b',
          'station-b:line-test',
          90,
          'ENTRY',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-b-a-line-test',
          'station-b:line-test',
          'station-a:line-test',
          90,
          'RIDE',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-a-c-line-alt',
          'station-a:line-alt',
          'station-c:line-alt',
          90,
          'RIDE',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'exit-c-line-alt-explicit',
          'station-c:line-alt',
          'station-c',
          60,
          'EXIT',
          'STEP_FREE',
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
    expect(result.blockedReasons, contains('계단 없는 동선 여부를 확인할 수 없습니다.'));
  });

  test('service pattern entry가 사용 불가이면 생성 entry로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'entry-a-line-test-local-unavailable',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
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
          'STEP_FREE',
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
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'entry-a-line-test-unavailable',
          'station-a',
          'station-a:line-test',
          90,
          'ENTRY',
          '',
          'STEP_FREE',
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
          'STEP_FREE',
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

  test('고장 시설에 연결된 entry edge는 접근 가능 경로에서 제외한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'OUT_OF_SERVICE',
        'B1',
        '1F',
        '점검 중'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          NULL
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

  test('사용 불가 edge는 연결 시설 확인 필요 상태로 약화하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'CHECK_REQUIRED',
        'B1',
        '1F',
        '확인 필요'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'UNAVAILABLE',
          95,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          NULL
        )
    ''');
    final repository = LocalRouteRepository(catalogDatabase: database);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'SENIOR',
      ),
    );

    expect(result.status, 'BLOCKED');
    expect(result.steps, isEmpty);
    expect(result.blockedReasons, contains('필수 접근성 시설을 사용할 수 없습니다.'));
  });

  test('검수 완료 시설에 연결된 available edge는 이동 가능하게 유지한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'ADMIN_VERIFIED',
        'B1',
        '1F',
        '관리자 검수 완료'
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          NULL
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
    expect(result.blockedReasons, isEmpty);
    expect(result.warnings, isEmpty);
  });

  test('낮은 시설 품질 레코드는 연결된 edge의 신뢰도와 갱신 시각으로 전파된다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'NORMAL',
        'B1',
        '1F',
        ''
      )
    ''');
    await database.customStatement('''
      INSERT INTO data_quality_records (
        id, target_type, target_id, quality_level, checked_at
      )
      VALUES (
        'quality-facility-a-elevator',
        'facility',
        'facility-a-elevator',
        'LEVEL_1',
        0
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, last_verified_at, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          NULL
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
    expect(result.warnings.map((warning) => warning.code), {
      'LOW_DATA_CONFIDENCE',
      'STALE_ACCESSIBILITY_DATA',
    });
  });

  test('최고 시설 품질 레코드는 낮은 신뢰도 경고를 만들지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'NORMAL',
        'B1',
        '1F',
        ''
      )
    ''');
    await database.customStatement('''
      INSERT INTO data_quality_records (
        id, target_type, target_id, quality_level, checked_at
      )
      VALUES (
        'quality-facility-a-elevator',
        'facility',
        'facility-a-elevator',
        'LEVEL_4',
        1781827200
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, last_verified_at, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          NULL
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
      result.warnings.map((warning) => warning.code),
      isNot(contains('LOW_DATA_CONFIDENCE')),
    );
  });

  test('시설 품질 테이블이 없는 catalog도 연결 시설 경로를 계산한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addFacilityIdColumnIfMissing(database);
    await database.customStatement('DROP TABLE data_quality_records');
    await database.customStatement('''
      INSERT INTO facilities (
        id, station_id, type, name, status, floor_from, floor_to, description
      )
      VALUES (
        'facility-a-elevator',
        'station-a',
        'ELEVATOR',
        '출발역 엘리베이터',
        'NORMAL',
        'B1',
        '1F',
        ''
      )
    ''');
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score, last_verified_at, facility_id
      )
      VALUES
        (
          'entry-a-line-test-elevator',
          'station-a',
          'station-a:line-test:LOCAL',
          90,
          'ENTRY',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          'facility-a-elevator'
        ),
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          120,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95,
          1781827200,
          NULL
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
    expect(result.warnings, isEmpty);
  });

  test('명시 service pattern entry는 base entry 확장으로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'entry-a-line-test-available',
          'station-a',
          'station-a:line-test',
          90,
          'ENTRY',
          '',
          'STEP_FREE',
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
          'STEP_FREE',
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
          'STEP_FREE',
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
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES (
        'edge-a-c-express',
        'station-a:line-test:EXPRESS',
        'station-c:line-test:EXPRESS',
        150,
        'RIDE',
        'EXPRESS',
        'STEP_FREE',
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

  test(
    'service pattern 방향 suffix가 있는 node도 entry와 ride edge를 같은 node로 연결한다',
    () async {
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      await _seedLineWithoutNetworkEdges(database);
      await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-a-b-local-clockwise',
          'station-a:line-test:LOCAL:CLOCKWISE',
          'station-b:line-test:LOCAL:CLOCKWISE',
          90,
          'RIDE',
          'LOCAL:CLOCKWISE',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'edge-b-c-local-clockwise',
          'station-b:line-test:LOCAL:CLOCKWISE',
          'station-c:line-test:LOCAL:CLOCKWISE',
          90,
          'RIDE',
          'LOCAL:CLOCKWISE',
          'STEP_FREE',
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
        result.steps.map((step) => step.fromStationId),
        contains('station-a'),
      );
      expect(
        result.steps.map((step) => step.toStationId),
        contains('station-c'),
      );
      expect(
        result.steps.map((step) => step.lineId).where((id) => id.isNotEmpty),
        everyElement('line-test'),
      );
    },
  );

  test('step 소요시간은 접근성 패널티가 아니라 사용된 edge 시간에서 만든다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score,
        stair_access_state, last_verified_at
      )
      VALUES (
        'edge-a-b-low-confidence',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'AVAILABLE',
        50,
        'STEP_FREE',
        0
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
      (step) => step.stepType == 'ride',
    );
    expect(result.status, 'FOUND');
    expect(result.warnings.map((warning) => warning.code), {
      'LOW_DATA_CONFIDENCE',
      'STALE_ACCESSIBILITY_DATA',
    });
    expect(rideStep.estimatedMinutes, 2);
  });

  test('step 소요시간은 측정값이 없으면 ranking fallback 시간으로 표시하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addDistanceMetersColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, distance_meters,
        edge_type, service_pattern, accessibility_status, reliability_score,
        stair_access_state, last_verified_at
      )
      VALUES (
        'edge-a-b-duration-unknown',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        0,
        850,
        'RIDE',
        'LOCAL',
        'AVAILABLE',
        100,
        'STEP_FREE',
        1700000000
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
      (step) => step.stepType == 'ride',
    );
    expect(result.status, 'FOUND');
    expect(rideStep.estimatedMinutes, 0);
    expect(rideStep.distanceMeters, 850);
  });

  test('step 거리는 ranking cost에서 만들지 않고 측정값이 없으면 미확인으로 둔다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, accessibility_status, reliability_score,
        stair_access_state, last_verified_at
      )
      VALUES (
        'edge-a-b-low-confidence-distance-unknown',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        'RIDE',
        'LOCAL',
        'AVAILABLE',
        50,
        'STEP_FREE',
        0
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
      (step) => step.stepType == 'ride',
    );
    expect(result.status, 'FOUND');
    expect(rideStep.estimatedMinutes, 2);
    expect(rideStep.distanceMeters, 0);
  });

  test('step 거리는 catalog 측정값이 있으면 ranking cost 대신 그 값을 사용한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addDistanceMetersColumnIfMissing(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, distance_meters,
        edge_type, service_pattern, accessibility_status, reliability_score,
        stair_access_state, last_verified_at
      )
      VALUES (
        'edge-a-b-measured-distance',
        'station-a:line-test:LOCAL',
        'station-b:line-test:LOCAL',
        120,
        850,
        'RIDE',
        'LOCAL',
        'AVAILABLE',
        50,
        'STEP_FREE',
        0
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
      (step) => step.stepType == 'ride',
    );
    expect(result.status, 'FOUND');
    expect(rideStep.estimatedMinutes, 2);
    expect(rideStep.distanceMeters, 850);
  });

  test('사용 불가 explicit transfer edge는 자동 환승 edge로 우회하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    await _seedLineWithoutNetworkEdges(database);
    await _addSecondLineForTransferFixture(database);
    await database.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test',
          'station-b:line-test',
          'station-a:line-test',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
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
          'STEP_FREE',
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
          'STEP_FREE',
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
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test-local',
          'station-b:line-test:LOCAL',
          'station-a:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
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
          'STEP_FREE',
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
          'STEP_FREE',
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
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test-express',
          'station-b:line-test:EXPRESS',
          'station-a:line-test:EXPRESS',
          90,
          'RIDE',
          'EXPRESS',
          'STEP_FREE',
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
          'STEP_FREE',
          'UNAVAILABLE',
          95
        ),
        (
          'transfer-a-express-alt-available',
          'station-a:line-test:EXPRESS',
          'station-a:line-alt',
          140,
          'TRANSFER',
          'EXPRESS',
          'STEP_FREE',
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
          'STEP_FREE',
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
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-b-a-line-test-local',
          'station-b:line-test:LOCAL',
          'station-a:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
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
          'STEP_FREE',
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
          'STEP_FREE',
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
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-a-b-local',
          'station-a:line-test:LOCAL',
          'station-b:line-test:LOCAL',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-b-local-express',
          'station-b:line-test:LOCAL',
          'station-b:line-test:EXPRESS',
          140,
          'TRANSFER',
          'LOCAL',
          'STEP_FREE',
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
          'STEP_FREE',
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
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-a-b-base',
          'station-a:line-test',
          'station-b:line-test',
          90,
          'RIDE',
          '',
          'STEP_FREE',
          'AVAILABLE',
          95
        ),
        (
          'transfer-b-base-local',
          'station-b:line-test',
          'station-b:line-test:LOCAL',
          140,
          'TRANSFER',
          '',
          'STEP_FREE',
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
          'STEP_FREE',
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
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-c-a-line-alt',
          'station-c:line-alt',
          'station-a:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
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
          'STEP_FREE',
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
          'STEP_FREE',
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
        service_pattern, stair_access_state, accessibility_status,
        reliability_score
      )
      VALUES
        (
          'edge-c-a-line-alt',
          'station-c:line-alt',
          'station-a:line-alt',
          90,
          'RIDE',
          'LOCAL',
          'STEP_FREE',
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
          'STEP_FREE',
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
          'STEP_FREE',
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

Future<void> _seedLineWithoutNetworkEdges(
  CatalogDatabase database, {
  bool includeExplicitAccessEdges = true,
}) async {
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
  if (includeExplicitAccessEdges) {
    await _addExplicitAccessEdges(database);
  }
}

Future<void> _addExplicitAccessEdges(CatalogDatabase database) async {
  await database.customStatement('''
    INSERT INTO network_edges (
      id, from_node_id, to_node_id, duration_seconds, edge_type,
      stair_access_state, accessibility_status, reliability_score
    )
    VALUES
      (
        'entry-station-a-line-test',
        'station-a',
        'station-a:line-test',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95
      ),
      (
        'exit-station-a-line-test',
        'station-a:line-test',
        'station-a',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95
      ),
      (
        'entry-station-b-line-test',
        'station-b',
        'station-b:line-test',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95
      ),
      (
        'exit-station-b-line-test',
        'station-b:line-test',
        'station-b',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95
      ),
      (
        'entry-station-c-line-test',
        'station-c',
        'station-c:line-test',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95
      ),
      (
        'exit-station-c-line-test',
        'station-c:line-test',
        'station-c',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95
      )
  ''');
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
  await database.customStatement('''
    INSERT INTO network_edges (
      id, from_node_id, to_node_id, duration_seconds, edge_type,
      stair_access_state, accessibility_status, reliability_score
    )
    VALUES
      (
        'entry-station-a-line-alt',
        'station-a',
        'station-a:line-alt',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95
      ),
      (
        'exit-station-a-line-alt',
        'station-a:line-alt',
        'station-a',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95
      ),
      (
        'entry-station-c-line-alt',
        'station-c',
        'station-c:line-alt',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        95
      ),
      (
        'exit-station-c-line-alt',
        'station-c:line-alt',
        'station-c',
        60,
        'EXIT',
        'STEP_FREE',
        'AVAILABLE',
        95
      )
  ''');
}

Future<void> _addFacilityIdColumnIfMissing(CatalogDatabase database) async {
  final columns = await database
      .customSelect('PRAGMA table_info(network_edges)')
      .get();
  final hasFacilityId = columns.any(
    (row) => row.read<String>('name') == 'facility_id',
  );
  if (!hasFacilityId) {
    await database.customStatement(
      'ALTER TABLE network_edges ADD COLUMN facility_id TEXT',
    );
  }
}

Future<void> _addDistanceMetersColumnIfMissing(CatalogDatabase database) async {
  final columns = await database
      .customSelect('PRAGMA table_info(network_edges)')
      .get();
  final hasDistanceMeters = columns.any(
    (row) => row.read<String>('name') == 'distance_meters',
  );
  if (!hasDistanceMeters) {
    await database.customStatement(
      'ALTER TABLE network_edges ADD COLUMN distance_meters INTEGER NOT NULL DEFAULT 0',
    );
  }
}
