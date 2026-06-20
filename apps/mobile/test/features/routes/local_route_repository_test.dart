import 'dart:io';

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

  test('기존 baseline catalog는 비어 있는 철도 간선을 열 때 보강한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-route-catalog-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/catalog.sqlite');
    final originalDatabase = CatalogDatabase.file(file);
    await originalDatabase.seedBaselineIfEmpty();
    await originalDatabase.customStatement('DELETE FROM network_edges');
    await originalDatabase.close();

    final reopenedDatabase = CatalogDatabase.file(file);
    addTearDown(reopenedDatabase.close);
    final repository = LocalRouteRepository(catalogDatabase: reopenedDatabase);

    final result = await repository.searchRoute(
      const RouteSearchRequest(
        originStationId: 'station-sangnoksu',
        destinationStationId: 'station-sadang',
        mobilityType: 'WHEELCHAIR',
      ),
    );

    expect(result.status, 'FOUND');
    expect(result.lineId, 'seoul-4');
    final edgeCount = await reopenedDatabase
        .customSelect('SELECT COUNT(*) AS count FROM network_edges')
        .getSingle();
    expect(edgeCount.read<int>('count'), greaterThanOrEqualTo(2));
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
