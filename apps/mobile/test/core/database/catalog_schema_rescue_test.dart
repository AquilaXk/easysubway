import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database_opener.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_schema_diagnostics.dart';
import 'package:easysubway_mobile/features/routes/data/local_route_repository.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('설치 팩에 결측된 구제 가능 테이블을 열기 경로에서 만든다', () async {
    final directory = await _temporaryDirectory('rescue-installed-');
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final pack = File('${catalogDirectory.path}/capital-v18.sqlite');
    await _buildInstalledPack(pack, activePack: 'capital-v18');
    _dropTables(pack, rescuableCatalogTableNames.toList());
    await _writeCurrentPointer(catalogDirectory, version: '18', file: pack);

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);
    final tables = await _tableNames(database);
    final activePack = await _activePack(database);

    expect(opener.openedBundledDataPack, isFalse);
    expect(activePack, 'capital-v18');
    expect(tables, containsAll(rescuableCatalogTableNames));
  });

  test('구제 가능 테이블은 빈 테이블로 만들어져 조회를 소거하지 않는다', () async {
    final directory = await _temporaryDirectory('rescue-empty-');
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final pack = File('${catalogDirectory.path}/capital-v18.sqlite');
    await _buildInstalledPack(pack, activePack: 'capital-v18');
    _dropTables(pack, [
      'station_facility_evidence',
      'facility_status_snapshots',
    ]);
    await _writeCurrentPointer(catalogDirectory, version: '18', file: pack);

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);
    final evidenceCount = await database
        .customSelect('SELECT COUNT(*) AS count FROM station_facility_evidence')
        .getSingle();
    final stopTimeCount = await database
        .customSelect('SELECT COUNT(*) AS count FROM transit_stop_times')
        .getSingle();
    final stationCount = await database
        .customSelect('SELECT COUNT(*) AS count FROM stations')
        .getSingle();

    expect(evidenceCount.read<int>('count'), 0);
    expect(stopTimeCount.read<int>('count'), 0);
    expect(stationCount.read<int>('count'), greaterThan(0));
  });

  test('구제 불가 테이블이 결측이면 설치 팩을 열지 않고 known-good으로 강등한다', () async {
    final directory = await _temporaryDirectory('rescue-blocked-known-good-');
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final knownGood = File('${catalogDirectory.path}/capital-v17.sqlite');
    await _buildInstalledPack(knownGood, activePack: 'capital-v17');
    final broken = File('${catalogDirectory.path}/capital-v18.sqlite');
    await _buildInstalledPack(broken, activePack: 'capital-v18');
    _dropTables(broken, ['transit_stop_times']);
    await _writeCurrentPointer(catalogDirectory, version: '18', file: broken);

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);
    final activePack = await _activePack(database);

    expect(opener.openedBundledDataPack, isFalse);
    expect(activePack, 'capital-v17');
    // 거부한 팩에는 DDL을 실행하지 않는다.
    expect(_rawTableNames(broken), isNot(contains('transit_stop_times')));
  });

  test('구제 불가 결측에 known-good도 없으면 번들 팩으로 강등한다', () async {
    final directory = await _temporaryDirectory('rescue-blocked-bundled-');
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final broken = File('${catalogDirectory.path}/capital-v18.sqlite');
    await _buildInstalledPack(broken, activePack: 'capital-v18');
    _dropTables(broken, ['transit_stop_times']);
    await _writeCurrentPointer(catalogDirectory, version: '18', file: broken);

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);

    expect(opener.openedBundledDataPack, isTrue);
  });

  test('번들 팩을 열면 앱이 선언한 테이블이 모두 존재한다', () async {
    final directory = await _temporaryDirectory('rescue-bundled-');

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);
    final declared = database.allTables
        .map((table) => table.actualTableName)
        .toSet();
    final tables = await _tableNames(database);

    expect(opener.openedBundledDataPack, isTrue);
    expect(declared.length, 33);
    expect(tables, containsAll(declared));
  });

  test('결측 테이블 조회 신호는 세션당 한 번만 로그를 남기고 횟수는 누적한다', () {
    final logged = <String>[];
    CatalogSchemaDiagnostics.replaceForTest(logged.add);
    addTearDown(CatalogSchemaDiagnostics.reset);

    for (var attempt = 0; attempt < 5; attempt += 1) {
      CatalogSchemaDiagnostics.instance.recordMissingTableRead(
        'station_facility_evidence',
      );
    }
    CatalogSchemaDiagnostics.instance.recordMissingTableRead(
      'facility_status_snapshots',
    );

    expect(logged, hasLength(2));
    expect(logged.first, contains('station_facility_evidence'));
    expect(CatalogSchemaDiagnostics.instance.missingTableReadCounts, {
      'station_facility_evidence': 5,
      'facility_status_snapshots': 1,
    });
  });

  test('결측 테이블 가드가 걸리면 경로 조회가 진단 신호를 남긴다', () async {
    final logged = <String>[];
    CatalogSchemaDiagnostics.replaceForTest(logged.add);
    addTearDown(CatalogSchemaDiagnostics.reset);
    final directory = await _temporaryDirectory('rescue-diagnostics-');
    final pack = File('${directory.path}/capital.sqlite');
    await _buildInstalledPack(pack, activePack: 'capital');
    _dropTables(pack, [
      'station_facility_evidence',
      'facility_status_snapshots',
    ]);

    final database = CatalogDatabase.file(pack);
    addTearDown(database.close);
    final route = await LocalRouteRepository(catalogDatabase: database)
        .searchRoute(
          const RouteSearchRequest(
            originStationId: 'station-sangnoksu',
            destinationStationId: 'station-sadang',
            mobilityType: 'WHEELCHAIR',
          ),
        );
    final counts = CatalogSchemaDiagnostics.instance.missingTableReadCounts;

    expect(route.steps, isNotEmpty);
    expect(counts['station_facility_evidence'], greaterThanOrEqualTo(1));
    expect(counts['facility_status_snapshots'], greaterThanOrEqualTo(1));
    expect(
      logged.where((line) => line.contains('station_facility_evidence')),
      hasLength(1),
    );
  });
}

Future<Directory> _temporaryDirectory(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(
    'easysubway-catalog-$prefix',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}

Future<void> _buildInstalledPack(
  File file, {
  required String activePack,
}) async {
  final database = CatalogDatabase.file(file);
  await database.seedBaselineIfEmpty();
  await database
      .into(database.catalogMetadata)
      .insertOnConflictUpdate(
        CatalogMetadataCompanion.insert(
          key: 'activePack',
          value: activePack,
          updatedAt: Value(DateTime.utc(2026, 6, 19, 12)),
        ),
      );
  await database.close();
}

void _dropTables(File file, List<String> tableNames) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    for (final tableName in tableNames) {
      raw.execute('DROP TABLE IF EXISTS $tableName');
    }
    raw.execute('PRAGMA user_version = $catalogDatabaseSchemaVersion');
  } finally {
    raw.close();
  }
}

Set<String> _rawTableNames(File file) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    return {
      for (final row in raw.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      ))
        row['name'] as String,
    };
  } finally {
    raw.close();
  }
}

Future<Set<String>> _tableNames(CatalogDatabase database) async {
  final rows = await database
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return {for (final row in rows) row.read<String>('name')};
}

Future<String> _activePack(CatalogDatabase database) async {
  final row = await database
      .customSelect(
        "SELECT value FROM catalog_metadata WHERE key = 'activePack'",
      )
      .getSingle();
  return row.read<String>('value');
}

Future<void> _writeCurrentPointer(
  Directory catalogDirectory, {
  required String version,
  required File file,
}) async {
  await File('${catalogDirectory.path}/current.json').writeAsString(
    jsonEncode({
      'id': 'capital',
      'version': version,
      'path': file.path,
      'sha256': 'local-fixture',
    }),
  );
}
