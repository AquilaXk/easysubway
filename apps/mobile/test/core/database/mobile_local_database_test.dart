import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:easysubway_mobile/app/app_bootstrap.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database_opener.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database_opener.dart';
import 'package:easysubway_mobile/core/datapack/emergency_override_repository.dart';
import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('앱 부트스트랩 owner는 제거될 때 열린 DB 자원을 닫는다', (tester) async {
    final closeCalled = Completer<void>();

    await tester.pumpWidget(
      AppBootstrapLifecycle(
        close: () {
          closeCalled.complete();
          return Future<void>.value();
        },
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    await closeCalled.future;
    expect(closeCalled.isCompleted, isTrue);
  });

  test('catalog DB는 앱 시작에 필요한 schema와 index를 만든다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);

    final objects = await database.customSelect('''
          SELECT name
          FROM sqlite_master
          WHERE type IN ('table', 'index')
            AND name NOT LIKE 'sqlite_%'
          ORDER BY name
          ''').get();
    final names = objects.map((row) => row.read<String>('name')).toSet();

    expect(
      names,
      containsAll({
        'catalog_metadata',
        'operators',
        'lines',
        'stations',
        'station_aliases',
        'station_lines',
        'network_edges',
        'station_exits',
        'facilities',
        'station_accessibility_summaries',
        'internal_route_nodes',
        'internal_route_edges',
        'data_quality_records',
        'idx_stations_normalized_name',
        'idx_station_lines_line_sequence',
        'idx_network_edges_from_node',
        'idx_facilities_station',
        'idx_internal_route_edges_from',
      }),
    );
  });

  test('내장 baseline 데이터팩은 schemaVersion과 상록수/사당 fixture를 제공한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();
    final stations = await database.customSelect('''
          SELECT id, name_ko, latitude, longitude
          FROM stations
          WHERE id IN ('station-sangnoksu', 'station-sadang')
          ORDER BY name_ko
          ''').get();
    final aliases = await database.customSelect('''
          SELECT alias
          FROM station_aliases
          WHERE station_id = 'station-sangnoksu'
          ORDER BY alias
          ''').get();
    final exits = await database.customSelect('''
          SELECT exit_number
          FROM station_exits
          WHERE station_id = 'station-sangnoksu'
          ''').get();
    final facilities = await database.customSelect('''
          SELECT id, type, name
          FROM facilities
          WHERE station_id = 'station-sangnoksu'
          ORDER BY id
          ''').get();
    final fieldValidationRecords = await database.customSelect('''
          SELECT target_type, target_id, quality_level, checked_at
          FROM data_quality_records
          WHERE target_id IN (
            'exit-sangnoksu-1',
            'facility-sangnoksu-elevator-1',
            'facility-sangnoksu-escalator-1',
            'facility-sangnoksu-accessible-toilet-1',
            'edge-sangnoksu-concourse-exit-1'
          )
          ORDER BY target_id
          ''').get();
    final networkEdges = await database.customSelect('''
          SELECT id, from_node_id, to_node_id, edge_type, service_pattern,
                 includes_stairs, accessibility_status, reliability_score,
                 facility_id, last_verified_at, distance_meters
          FROM network_edges
          WHERE id IN (
            'edge-sangnoksu-sadang-seoul-4',
            'edge-sadang-sangnoksu-seoul-4'
          )
          ORDER BY id
          ''').get();
    final internalRouteEdges = await database.customSelect('''
          SELECT id, edge_type, accessibility_status
          FROM internal_route_edges
          ORDER BY id
          ''').get();
    final routeMapPosition = await database.customSelect('''
          SELECT label_polygon
          FROM route_map_positions
          WHERE station_id = 'station-sangnoksu'
            AND line_id = 'seoul-4'
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    expect(stations.map((row) => row.read<String>('name_ko')).toList(), [
      '사당',
      '상록수',
    ]);
    final sangnoksu = stations.firstWhere(
      (row) => row.read<String>('id') == 'station-sangnoksu',
    );
    expect(sangnoksu.read<double>('latitude'), closeTo(37.3028, 0.001));
    expect(sangnoksu.read<double>('longitude'), closeTo(126.8666, 0.001));
    expect(aliases.map((row) => row.read<String>('alias')), [
      '448',
      '4호선 상록수',
      'Sangnoksu',
      '상록수역',
    ]);
    expect(exits.single.read<String>('exit_number'), '1');
    expect(facilities.map((row) => row.read<String>('type')).toSet(), {
      'ACCESSIBLE_TOILET',
      'ELEVATOR',
      'ESCALATOR',
    });
    expect(
      facilities.map((row) => row.read<String>('name')),
      containsAll(['1번 출구 엘리베이터', '1번 출구 에스컬레이터', '대합실 장애인 화장실']),
    );
    expect(
      fieldValidationRecords
          .map((row) => row.read<String>('target_type'))
          .toSet(),
      {'facility', 'internal_route_edge', 'station_exit'},
    );
    expect(
      fieldValidationRecords
          .map((row) => row.read<String>('quality_level'))
          .toSet(),
      {'FIELD_STALE', 'FIELD_UNKNOWN', 'FIELD_VERIFIED'},
    );
    final expectedFieldValidationRecords = {
      'exit-sangnoksu-1': ('station_exit', 'FIELD_VERIFIED'),
      'facility-sangnoksu-elevator-1': ('facility', 'FIELD_VERIFIED'),
      'facility-sangnoksu-escalator-1': ('facility', 'FIELD_UNKNOWN'),
      'facility-sangnoksu-accessible-toilet-1': ('facility', 'FIELD_STALE'),
      'edge-sangnoksu-concourse-exit-1': (
        'internal_route_edge',
        'FIELD_VERIFIED',
      ),
    };
    expect(
      fieldValidationRecords,
      hasLength(expectedFieldValidationRecords.length),
    );
    for (final row in fieldValidationRecords) {
      final targetId = row.read<String>('target_id');
      final expectedRecord = expectedFieldValidationRecords[targetId];
      expect(expectedRecord == null, isFalse, reason: targetId);
      expect(row.read<String>('target_type'), expectedRecord!.$1);
      final qualityLevel = row.read<String>('quality_level');
      expect(qualityLevel, expectedRecord.$2);
      if (qualityLevel == 'FIELD_VERIFIED') {
        expect(row.read<int?>('checked_at') == null, isFalse, reason: targetId);
      }
    }
    expect(networkEdges, hasLength(2));
    expect(networkEdges.map((row) => row.read<String>('edge_type')).toSet(), {
      'RIDE',
    });
    expect(
      networkEdges.map((row) => row.read<String>('service_pattern')).toSet(),
      {'LOCAL'},
    );
    expect(
      networkEdges.map((row) => row.read<bool>('includes_stairs')).toSet(),
      {false},
    );
    expect(
      networkEdges
          .map((row) => row.read<String>('accessibility_status'))
          .toSet(),
      {'AVAILABLE'},
    );
    expect(
      networkEdges.map((row) => row.read<int>('reliability_score')).toSet(),
      {90},
    );
    expect(
      networkEdges
          .map((row) => row.readNullable<String>('facility_id'))
          .toSet(),
      {null},
    );
    expect(
      networkEdges.map((row) => row.read<int>('last_verified_at')).toSet(),
      {1781827200},
    );
    expect(
      networkEdges.map((row) => row.read<int>('distance_meters')).toSet(),
      {18600},
    );
    expect(
      networkEdges
          .map(
            (row) =>
                '${row.read<String>('from_node_id')}->'
                '${row.read<String>('to_node_id')}',
          )
          .toSet(),
      {
        'station-sangnoksu:seoul-4->station-sadang:seoul-4',
        'station-sadang:seoul-4->station-sangnoksu:seoul-4',
      },
    );
    expect(
      internalRouteEdges
          .map((row) => row.read<String>('accessibility_status'))
          .toSet(),
      {'AVAILABLE'},
    );
    expect(
      routeMapPosition.read<String>('label_polygon'),
      '[{"x":2318.642,"y":4961.953},{"x":2355.324,"y":4925.272},{"x":2372.294,"y":4942.242},{"x":2335.613,"y":4978.923}]',
    );
    expect(
      File('${directory.path}/datapacks/core.sqlite').existsSync(),
      isTrue,
    );
    expect(
      File('${directory.path}/datapacks/capital.sqlite').existsSync(),
      isTrue,
    );
  });

  test('내장 데이터팩은 로컬 역 검색 repository에서 역 번호 검색을 제공한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-search-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);
    final repository = DriftStationRepository(database: database);

    final results = await repository.searchStations('448');

    expect(results, hasLength(1));
    expect(results.single.id, 'station-sangnoksu');
  });

  test('내장 데이터팩은 설치된 파일이 손상되어 있으면 번들 asset으로 교체한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-corrupt-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final installedCapitalPack = File(
      '${directory.path}/datapacks/capital.sqlite',
    );
    await installedCapitalPack.create(recursive: true);
    await installedCapitalPack.writeAsString('broken sqlite file');

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    expect(
      await installedCapitalPack.openRead(0, 16).first,
      'SQLite format 3'.codeUnits.followedBy([0]).toList(),
    );
  });

  test('catalog opener는 업데이트된 current pointer가 있으면 해당 데이터팩을 연다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-current-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
    final updatedDatabase = CatalogDatabase.file(updatedPack);
    await updatedDatabase.seedBaselineIfEmpty();
    await updatedDatabase
        .into(updatedDatabase.catalogMetadata)
        .insertOnConflictUpdate(
          CatalogMetadataCompanion.insert(
            key: 'activePack',
            value: 'capital-v18',
            updatedAt: Value(DateTime.utc(2026, 6, 19, 12)),
          ),
        );
    await updatedDatabase.close();
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': updatedPack.path,
        'sha256': 'local-fixture',
      }),
    );

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v18');
  });

  test('catalog opener는 설치된 current pack의 제거된 access edge를 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-current-access-backfill-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
    final updatedDatabase = CatalogDatabase.file(updatedPack);
    await updatedDatabase.seedBaselineIfEmpty();
    await updatedDatabase.customStatement('''
      DELETE FROM network_edges
      WHERE edge_type IN ('ENTRY', 'EXIT')
    ''');
    await updatedDatabase.close();
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': updatedPack.path,
        'sha256': 'local-fixture',
      }),
    );

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);
    final accessEdgeCount = await database.customSelect('''
      SELECT COUNT(*) AS count
      FROM network_edges
      WHERE id IN (
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''').getSingle();
    final route = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    expect(accessEdgeCount.read<int>('count'), 0);
    expect(route.status, 'UNKNOWN');
  });

  test('catalog opener는 부분 적용된 current pack access edge를 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-current-access-backfill-partial-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
    final updatedDatabase = CatalogDatabase.file(updatedPack);
    await updatedDatabase.seedBaselineIfEmpty();
    await updatedDatabase.customStatement('''
      DELETE FROM network_edges
      WHERE edge_type IN ('ENTRY', 'EXIT')
    ''');
    await updatedDatabase.customStatement('''
      INSERT INTO network_edges (
        id, from_node_id, to_node_id, duration_seconds, edge_type,
        stair_access_state, accessibility_status, reliability_score,
        last_verified_at
      )
      VALUES (
        'entry-sangnoksu-seoul-4',
        'station-sangnoksu',
        'station-sangnoksu:seoul-4',
        90,
        'ENTRY',
        'STEP_FREE',
        'AVAILABLE',
        90,
        1781827200
      )
    ''');
    await updatedDatabase.close();
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': updatedPack.path,
        'sha256': 'local-fixture',
      }),
    );

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);
    final accessEdgeCount = await database.customSelect('''
      SELECT COUNT(*) AS count
      FROM network_edges
      WHERE id IN (
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''').getSingle();

    expect(accessEdgeCount.read<int>('count'), 1);
  });

  test(
    'catalog opener는 baseline보다 큰 current pack에 access edge를 주입하지 않는다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-current-access-backfill-skip-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
      final updatedDatabase = CatalogDatabase.file(updatedPack);
      await updatedDatabase.seedBaselineIfEmpty();
      await updatedDatabase.customStatement('''
      DELETE FROM network_edges
      WHERE edge_type IN ('ENTRY', 'EXIT')
    ''');
      await updatedDatabase
          .into(updatedDatabase.stations)
          .insert(
            StationsCompanion.insert(
              id: 'station-extra',
              nameKo: '추가역',
              normalizedName: '추가역',
            ),
          );
      await updatedDatabase.close();
      await File('${catalogDirectory.path}/current.json').writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '18',
          'path': updatedPack.path,
          'sha256': 'local-fixture',
        }),
      );

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);
      final accessEdgeCount = await database.customSelect('''
      SELECT COUNT(*) AS count
      FROM network_edges
      WHERE id IN (
        'entry-sangnoksu-seoul-4',
        'exit-sangnoksu-seoul-4',
        'entry-sadang-seoul-4',
        'exit-sadang-seoul-4'
      )
    ''').getSingle();
      final route = await LocalRouteRepository(catalogDatabase: database)
          .searchRoute(
            const RouteSearchRequest(
              originStationId: 'station-sangnoksu',
              destinationStationId: 'station-sadang',
              mobilityType: 'WHEELCHAIR',
            ),
          );

      expect(accessEdgeCount.read<int>('count'), 0);
      expect(route.status, 'UNKNOWN');
    },
  );

  test(
    'catalog opener는 이전 컨테이너 경로의 current pointer도 현재 catalog에서 복원한다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-current-relocated-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      final updatedPack = File('${catalogDirectory.path}/capital-v18.sqlite');
      final updatedDatabase = CatalogDatabase.file(updatedPack);
      await updatedDatabase.seedBaselineIfEmpty();
      await updatedDatabase
          .into(updatedDatabase.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: 'capital-v18-relocated',
              updatedAt: Value(DateTime.utc(2026, 6, 19, 15)),
            ),
          );
      await updatedDatabase.close();
      await File('${catalogDirectory.path}/current.json').writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '18',
          'path': '/stale/mobile/container/catalog/capital-v18.sqlite',
          'sha256': 'local-fixture',
        }),
      );

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);

      final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

      expect(metadata.read<String>('value'), 'capital-v18-relocated');
    },
  );

  test('catalog opener는 emergency override가 있으면 current보다 우선한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-override-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = UserDatabase.memory();
    addTearDown(userDatabase.close);
    final overrideRepository = EmergencyOverrideRepository(
      userDatabase: userDatabase,
    );
    await overrideRepository.saveOverride(
      const EmergencyDataPackOverride(
        id: 'capital',
        version: '17',
        reason: '시설 상태 긴급 정정',
      ),
    );
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final overridePack = File('${catalogDirectory.path}/capital-v17.sqlite');
    final currentPack = File('${catalogDirectory.path}/capital-v18.sqlite');
    for (final entry in [
      (file: overridePack, activePack: 'capital-v17'),
      (file: currentPack, activePack: 'capital-v18'),
    ]) {
      final database = CatalogDatabase.file(entry.file);
      await database.seedBaselineIfEmpty();
      if (entry.file == overridePack) {
        await database.customStatement('''
          DELETE FROM network_edges
          WHERE edge_type IN ('ENTRY', 'EXIT')
        ''');
      }
      await database
          .into(database.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: entry.activePack,
              updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
            ),
          );
      await database.close();
    }
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': currentPack.path,
        'sha256': 'current-fixture',
      }),
    );

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      emergencyOverrideRepository: overrideRepository,
    ).open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v17');
    final accessEdgeCount = await database.customSelect('''
          SELECT COUNT(*) AS count
          FROM network_edges
          WHERE id IN (
            'entry-sangnoksu-seoul-4',
            'exit-sangnoksu-seoul-4',
            'entry-sadang-seoul-4',
            'exit-sadang-seoul-4'
          )
          ''').getSingle();
    final route = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );

    expect(accessEdgeCount.read<int>('count'), 0);
    expect(route.status, 'UNKNOWN');
  });

  test('catalog opener는 current pointer가 없어도 emergency override를 연다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-override-no-current-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = UserDatabase.memory();
    addTearDown(userDatabase.close);
    final overrideRepository = EmergencyOverrideRepository(
      userDatabase: userDatabase,
    );
    await overrideRepository.saveOverride(
      const EmergencyDataPackOverride(
        id: 'capital',
        version: '17',
        reason: '시설 상태 긴급 정정',
      ),
    );
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final overridePack = File('${catalogDirectory.path}/capital-v17.sqlite');
    final overrideDatabase = CatalogDatabase.file(overridePack);
    await overrideDatabase.seedBaselineIfEmpty();
    await overrideDatabase
        .into(overrideDatabase.catalogMetadata)
        .insertOnConflictUpdate(
          CatalogMetadataCompanion.insert(
            key: 'activePack',
            value: 'capital-v17',
            updatedAt: Value(DateTime.utc(2026, 6, 19, 16)),
          ),
        );
    await overrideDatabase.close();

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      emergencyOverrideRepository: overrideRepository,
    ).open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v17');
  });

  test('앱 부트스트랩은 데이터팩 업데이트를 기다리지 않고 catalog를 연다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-bootstrap-nonblocking-update-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final updateStarted = Completer<void>();
    final finishUpdate = Completer<void>();
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final updatedPack = File('${catalogDirectory.path}/capital-v19.sqlite');
    final updatedDatabase = CatalogDatabase.file(updatedPack);
    await updatedDatabase.seedBaselineIfEmpty();
    await updatedDatabase
        .into(updatedDatabase.catalogMetadata)
        .insertOnConflictUpdate(
          CatalogMetadataCompanion.insert(
            key: 'activePack',
            value: 'capital-v19',
            updatedAt: Value(DateTime.utc(2026, 6, 19, 13)),
          ),
        );
    await updatedDatabase.close();

    AppBootstrap? bootstrap;
    addTearDown(() => bootstrap?.close());
    final bootstrapFuture = AppBootstrap.initialize(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      dataPackUpdateRunner:
          ({required supportDirectory, required userDatabase}) async {
            updateStarted.complete();
            await finishUpdate.future;
            await File('${catalogDirectory.path}/current.json').writeAsString(
              jsonEncode({
                'id': 'capital',
                'version': '19',
                'path': updatedPack.path,
                'sha256': 'bootstrap-fixture',
              }),
            );
          },
      enablePushNotifications: false,
    );
    bootstrap = await bootstrapFuture.timeout(const Duration(seconds: 5));
    await updateStarted.future.timeout(const Duration(seconds: 5));
    expect(finishUpdate.isCompleted, isFalse);

    final metadata = await bootstrap.catalogDatabase.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    finishUpdate.complete();
  });

  test(
    'catalog opener는 current pointer가 깨지면 최신 known-good pack으로 복구한다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-known-good-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      final stalePack = File('${catalogDirectory.path}/capital-v17.sqlite');
      await stalePack.writeAsString('missing current target');
      final knownGoodPack = File('${catalogDirectory.path}/capital-v18.sqlite');
      final knownGoodDatabase = CatalogDatabase.file(knownGoodPack);
      await knownGoodDatabase.seedBaselineIfEmpty();
      await knownGoodDatabase
          .into(knownGoodDatabase.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: 'capital-v18',
              updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
            ),
          );
      await knownGoodDatabase.close();
      await File('${catalogDirectory.path}/current.json').writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '19',
          'path': '${catalogDirectory.path}/capital-v19.sqlite',
          'sha256': 'missing',
        }),
      );

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);

      final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

      expect(metadata.read<String>('value'), 'capital-v18');
    },
  );

  test(
    'catalog opener는 current id와 같은 known-good pack만 fallback으로 연다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-known-good-same-id-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      for (final entry in [
        (
          file: File('${catalogDirectory.path}/common-v99.sqlite'),
          activePack: 'common-v99',
        ),
        (
          file: File('${catalogDirectory.path}/capital-v18.sqlite'),
          activePack: 'capital-v18',
        ),
      ]) {
        final database = CatalogDatabase.file(entry.file);
        await database.seedBaselineIfEmpty();
        await database
            .into(database.catalogMetadata)
            .insertOnConflictUpdate(
              CatalogMetadataCompanion.insert(
                key: 'activePack',
                value: entry.activePack,
                updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
              ),
            );
        await database.close();
      }
      await File('${catalogDirectory.path}/current.json').writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '19',
          'path': '${catalogDirectory.path}/capital-v19.sqlite',
          'sha256': 'missing',
        }),
      );

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);

      final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

      expect(metadata.read<String>('value'), 'capital-v18');
    },
  );

  test('catalog opener는 rollback pointer보다 최신 pack으로 fallback하지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-known-good-version-bound-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    for (final entry in [
      (
        file: File('${catalogDirectory.path}/capital-v17.sqlite'),
        activePack: 'capital-v17',
      ),
      (
        file: File('${catalogDirectory.path}/capital-v19.sqlite'),
        activePack: 'capital-v19',
      ),
    ]) {
      final database = CatalogDatabase.file(entry.file);
      await database.seedBaselineIfEmpty();
      await database
          .into(database.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: entry.activePack,
              updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
            ),
          );
      await database.close();
    }
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': '${catalogDirectory.path}/capital-v18.sqlite',
        'sha256': 'missing',
      }),
    );

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);

    final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v17');
  });

  test('catalog opener는 설치 journal을 복구한 뒤 current pack을 연다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-catalog-journal-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final targetPack = File('${catalogDirectory.path}/capital-v19.sqlite');
    final database = CatalogDatabase.file(targetPack);
    await database.seedBaselineIfEmpty();
    await database
        .into(database.catalogMetadata)
        .insertOnConflictUpdate(
          CatalogMetadataCompanion.insert(
            key: 'activePack',
            value: 'capital-v19',
            updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
          ),
        );
    await database.close();
    await File(
      '${catalogDirectory.path}/current.json.installing',
    ).writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '19',
        'path': targetPack.path,
        'sha256': sha256.convert(await targetPack.readAsBytes()).toString(),
      }),
      flush: true,
    );

    final opened = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(opened.close);

    final metadata = await opened.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v19');
    expect(
      await File('${catalogDirectory.path}/current.json').exists(),
      isTrue,
    );
    expect(
      await File('${catalogDirectory.path}/current.json.installing').exists(),
      isFalse,
    );
  });

  test(
    'catalog opener는 malformed current에서 다른 id pack으로 fallback하지 않는다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-catalog-malformed-current-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final catalogDirectory = Directory('${directory.path}/catalog');
      await catalogDirectory.create(recursive: true);
      final otherPack = File('${catalogDirectory.path}/common-v99.sqlite');
      final otherDatabase = CatalogDatabase.file(otherPack);
      await otherDatabase.seedBaselineIfEmpty();
      await otherDatabase
          .into(otherDatabase.catalogMetadata)
          .insertOnConflictUpdate(
            CatalogMetadataCompanion.insert(
              key: 'activePack',
              value: 'common-v99',
              updatedAt: Value(DateTime.utc(2026, 6, 19, 14)),
            ),
          );
      await otherDatabase.close();
      await File(
        '${catalogDirectory.path}/current.json',
      ).writeAsString(jsonEncode(['not-a-pointer']));

      final database = await CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      ).open();
      addTearDown(database.close);

      final metadata = await database.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingleOrNull();

      expect(metadata?.read<String>('value'), isNot('common-v99'));
    },
  );

  test('앱 부트스트랩은 데이터팩 업데이트 실패 시 내장 catalog로 계속 시작한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-bootstrap-update-failure-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final reports = <FlutterErrorDetails>[];

    AppBootstrap? bootstrap;
    addTearDown(() => bootstrap?.close());
    bootstrap = await runWithMobileErrorReporter(
      reports.add,
      () => AppBootstrap.initialize(
        databaseDirectory: directory,
        assetBundle: rootBundle,
        dataPackUpdateRunner:
            ({required supportDirectory, required userDatabase}) async {
              throw const SocketException('manifest unavailable');
            },
        enablePushNotifications: false,
      ),
    );

    final metadata = await bootstrap!.catalogDatabase.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    expect(reports, hasLength(1));
    expect(
      reports.single.context.toString(),
      contains('데이터팩 업데이트 확인 중 예외가 발생했습니다.'),
    );
  });

  test('앱 부트스트랩은 API와 데이터팩 base가 없어도 HTTP request를 열지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-bootstrap-no-network-',
    );
    addTearDown(() => directory.delete(recursive: true));
    var httpRequestCount = 0;

    AppBootstrap? bootstrap;
    addTearDown(() => bootstrap?.close());
    bootstrap = await HttpOverrides.runZoned(
      () => AppBootstrap.initialize(
        databaseDirectory: directory,
        assetBundle: rootBundle,
        enablePushNotifications: false,
      ),
      createHttpClient: (context) {
        return _RequestCountingHttpClient(() {
          httpRequestCount++;
        });
      },
    );

    final metadata = await bootstrap!.catalogDatabase.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'schemaVersion'
          ''').getSingle();

    expect(metadata.read<String>('value'), '1');
    expect(httpRequestCount, 0);
  });

  test('user DB는 catalog 데이터팩 교체와 독립적으로 즐겨찾기와 신고 receipt를 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp('easysubway-user-');
    addTearDown(() => directory.delete(recursive: true));

    final first = await UserDatabaseOpener(databaseDirectory: directory).open();
    await first
        .into(first.favoriteStations)
        .insert(
          FavoriteStationsCompanion.insert(
            stationId: 'station-sangnoksu',
            addedAt: DateTime.parse('2026-06-19T10:00:00Z'),
          ),
        );
    await first
        .into(first.reportReceipts)
        .insert(
          ReportReceiptsCompanion.insert(
            receiptId: 'receipt-1',
            reportId: const Value('report-1'),
            status: 'RECEIVED',
            createdAt: DateTime.parse('2026-06-19T10:05:00Z'),
          ),
        );
    await first.close();

    final catalogFile = File('${directory.path}/datapacks/capital.sqlite');
    await catalogFile.create(recursive: true);
    await catalogFile.writeAsString('replaced catalog pack');

    final reopened = await UserDatabaseOpener(
      databaseDirectory: directory,
    ).open();
    addTearDown(reopened.close);

    final favorites = await reopened.select(reopened.favoriteStations).get();
    final receipts = await reopened.select(reopened.reportReceipts).get();

    expect(favorites, hasLength(1));
    expect(favorites.single.stationId, 'station-sangnoksu');
    expect(receipts, hasLength(1));
    expect(receipts.single.receiptId, 'receipt-1');
    expect(receipts.single.reportId, 'report-1');
    expect(receipts.single.status, 'RECEIVED');
  });

  test('user DB migration은 v1 사용자 데이터를 현재 schema로 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-user-migration-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final strategyDatabase = UserDatabase.memory();
    final strategy = strategyDatabase.migration;
    expect(strategy.beforeOpen, isNot(equals(null)));
    expect(strategy.onUpgrade, isNot(equals(null)));
    await strategyDatabase.close();

    final first = await UserDatabaseOpener(databaseDirectory: directory).open();
    await first
        .into(first.favoriteStations)
        .insert(
          FavoriteStationsCompanion.insert(
            stationId: 'station-sangnoksu',
            addedAt: DateTime.parse('2026-06-19T10:00:00Z'),
          ),
        );
    await first
        .into(first.searchHistory)
        .insert(
          SearchHistoryCompanion.insert(
            query: '상록수',
            searchedAt: DateTime.parse('2026-06-19T10:01:00Z'),
          ),
        );
    await first
        .into(first.reportReceipts)
        .insert(
          ReportReceiptsCompanion.insert(
            receiptId: 'receipt-migration-1',
            reportId: const Value('report-migration-1'),
            status: 'RECEIVED',
            createdAt: DateTime.parse('2026-06-19T10:05:00Z'),
          ),
        );
    await first.close();

    final reopened = await UserDatabaseOpener(
      databaseDirectory: directory,
    ).open();
    addTearDown(reopened.close);

    final favorites = await reopened.select(reopened.favoriteStations).get();
    final searchRows = await reopened
        .customSelect(
          'SELECT query FROM search_history ORDER BY searched_at DESC',
        )
        .get();
    final receipts = await reopened.select(reopened.reportReceipts).get();

    expect(favorites.single.stationId, 'station-sangnoksu');
    expect(searchRows.single.read<String>('query'), '상록수');
    expect(receipts.single.receiptId, 'receipt-migration-1');
    expect(receipts.single.reportId, 'report-migration-1');
  });
}

class _RequestCountingHttpClient implements HttpClient {
  _RequestCountingHttpClient(this.onRequest);

  final void Function() onRequest;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    onRequest();
    throw StateError('startup must not open HTTP request: $method $url');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
