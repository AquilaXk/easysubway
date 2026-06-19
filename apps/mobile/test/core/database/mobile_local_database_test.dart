import 'dart:io';

import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database_opener.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database_opener.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
          SELECT name_ko
          FROM stations
          WHERE id IN ('station-sangnoksu', 'station-sadang')
          ORDER BY name_ko
          ''').get();

    expect(metadata.read<String>('value'), '1');
    expect(stations.map((row) => row.read<String>('name_ko')).toList(), [
      '사당',
      '상록수',
    ]);
    expect(
      File('${directory.path}/datapacks/core.sqlite').existsSync(),
      isTrue,
    );
    expect(
      File('${directory.path}/datapacks/capital.sqlite').existsSync(),
      isTrue,
    );
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
