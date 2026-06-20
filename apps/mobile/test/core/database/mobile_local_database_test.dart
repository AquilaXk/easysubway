import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:easysubway_mobile/app/app_bootstrap.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database_opener.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database_opener.dart';
import 'package:easysubway_mobile/core/datapack/emergency_override_repository.dart';
import 'package:easysubway_mobile/features/stations/data/drift_station_repository.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
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
          SELECT type, name
          FROM facilities
          WHERE station_id = 'station-sangnoksu'
          ''').get();
    final networkEdges = await database.customSelect('''
          SELECT id, from_node_id, to_node_id, edge_type, service_pattern,
                 includes_stairs, accessibility_status, reliability_score,
                 last_verified_at
          FROM network_edges
          ORDER BY id
          ''').get();

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
    expect(facilities.single.read<String>('type'), 'ELEVATOR');
    expect(facilities.single.read<String>('name'), '1번 출구 엘리베이터');
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
      networkEdges.map((row) => row.read<int>('last_verified_at')).toSet(),
      {1781827200},
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

  test('앱 부트스트랩은 데이터팩 업데이트 후 current pointer로 catalog를 연다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-bootstrap-current-',
    );
    addTearDown(() => directory.delete(recursive: true));

    AppBootstrap? bootstrap;
    addTearDown(() => bootstrap?.close());
    bootstrap = await AppBootstrap.initialize(
      databaseDirectory: directory,
      assetBundle: rootBundle,
      dataPackUpdateRunner:
          ({required supportDirectory, required userDatabase}) async {
            final catalogDirectory = Directory(
              '${supportDirectory.path}/catalog',
            );
            await catalogDirectory.create(recursive: true);
            final updatedPack = File(
              '${catalogDirectory.path}/capital-v19.sqlite',
            );
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

    final metadata = await bootstrap.catalogDatabase.customSelect('''
          SELECT value
          FROM catalog_metadata
          WHERE key = 'activePack'
          ''').getSingle();

    expect(metadata.read<String>('value'), 'capital-v19');
  });

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

  test('user DB는 catalog 데이터팩 교체와 독립적으로 즐겨찾기를 보존한다', () async {
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
    await first.close();

    final catalogFile = File('${directory.path}/datapacks/capital.sqlite');
    await catalogFile.create(recursive: true);
    await catalogFile.writeAsString('replaced catalog pack');

    final reopened = await UserDatabaseOpener(
      databaseDirectory: directory,
    ).open();
    addTearDown(reopened.close);

    final favorites = await reopened.select(reopened.favoriteStations).get();

    expect(favorites, hasLength(1));
    expect(favorites.single.stationId, 'station-sangnoksu');
  });
}
