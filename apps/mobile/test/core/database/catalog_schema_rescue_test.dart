import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database_opener.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_schema_diagnostics.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_installer.dart';
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

  test('팩 스키마 원본으로 만든 설치 팩도 같은 구제 경로를 탄다', () async {
    final directory = await _temporaryDirectory('rescue-pack-schema-');
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final pack = File('${catalogDirectory.path}/capital-v18.sqlite');
    // 실제 배포 팩은 tools/datapack/build-datapack.mjs가 catalog-schema.sql을 exec해 만든다.
    // drift onCreate 산출물과 제약이 다르므로 회귀 테스트도 배포되는 스키마로 한 번은 돌려야 한다.
    _buildPackSchemaPack(pack, activePack: 'capital-v18');
    _dropTables(pack, [
      'station_facility_evidence',
      'facility_status_snapshots',
    ]);
    await _writeCurrentPointer(catalogDirectory, version: '18', file: pack);

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);
    final tables = await _tableNames(database);

    expect(opener.openedBundledDataPack, isFalse);
    expect(await _activePack(database), 'capital-v18');
    expect(
      tables,
      containsAll(['station_facility_evidence', 'facility_status_snapshots']),
    );
  });

  test('구제 불가 테이블이 결측이면 설치 팩을 열지 않고 known-good으로 강등한다', () async {
    final logged = <String>[];
    CatalogSchemaDiagnostics.replaceForTest(logged.add);
    addTearDown(CatalogSchemaDiagnostics.reset);
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
    expect(
      CatalogSchemaDiagnostics.instance.rejectedPackCounts,
      containsPair('capital-v18.sqlite', greaterThanOrEqualTo(1)),
    );
    expect(
      logged.where((line) => line.contains('capital-v18.sqlite')),
      hasLength(1),
    );
    expect(logged.first, contains('transit_stop_times'));
  });

  test('known-good 후보를 훑는 동안 탐색 대상 파일에는 DDL을 실행하지 않는다', () async {
    final directory = await _temporaryDirectory('rescue-probe-readonly-');
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    // v18은 구제 불가 결측으로 거부되고, v17은 구제 가능 결측만 있어 활성 팩이 된다.
    final probed = File('${catalogDirectory.path}/capital-v18.sqlite');
    await _buildInstalledPack(probed, activePack: 'capital-v18');
    _dropTables(probed, ['transit_stop_times', 'station_facility_evidence']);
    final activated = File('${catalogDirectory.path}/capital-v17.sqlite');
    await _buildInstalledPack(activated, activePack: 'capital-v17');
    _dropTables(activated, ['station_facility_evidence']);
    await _writeCurrentPointer(catalogDirectory, version: '18', file: probed);

    final database = await CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    ).open();
    addTearDown(database.close);

    expect(await _activePack(database), 'capital-v17');
    // 거부된 후보는 구제 가능 테이블도 만들어지지 않은 채 그대로 남는다.
    expect(
      _rawTableNames(probed),
      isNot(contains('station_facility_evidence')),
    );
    expect(_rawTableNames(activated), contains('station_facility_evidence'));
  });

  test('구제 불가 결측이 있어도 구제 가능 테이블과 요금 backfill은 살아 있다', () async {
    final directory = await _temporaryDirectory('rescue-blocked-fare-');
    final file = File('${directory.path}/capital.sqlite');
    await _buildInstalledPack(file, activePack: 'capital');
    // 번들 경로는 blocked여도 팩을 그대로 연다. 무관한 테이블 하나의 결측이 요금 도메인을
    // 함께 끄지 않아야 한다.
    _dropTables(file, [
      'transit_stop_times',
      'fare_zones',
      'fare_rules',
      'fare_discounts',
      'station_fare_zones',
    ]);

    final database = CatalogDatabase.file(file);
    addTearDown(database.close);
    final plan = await database.rescueMissingCatalogTables();
    await database.seedBaselineIfEmpty();
    final tables = await _tableNames(database);
    final fareRules = await database
        .customSelect('SELECT COUNT(*) AS count FROM fare_rules')
        .getSingle();

    expect(plan.isBlocked, isTrue);
    expect(plan.blockingMissingTables, contains('transit_stop_times'));
    expect(
      tables,
      containsAll([
        'fare_zones',
        'fare_rules',
        'fare_discounts',
        'station_fare_zones',
      ]),
    );
    expect(fareRules.read<int>('count'), greaterThan(0));
  });

  test('결측을 허용하는 테이블은 만들지도 막지도 않는다', () async {
    final directory = await _temporaryDirectory('rescue-tolerated-');
    final file = File('${directory.path}/capital.sqlite');
    _buildPackSchemaPack(file, activePack: 'capital');
    _dropTables(file, ['transit_feed_info']);

    final database = CatalogDatabase.file(file);
    addTearDown(database.close);
    final plan = await database.rescueMissingCatalogTables();
    final tables = await _tableNames(database);

    expect(plan.isBlocked, isFalse);
    expect(plan.toleratedMissingTables, {'transit_feed_info'});
    // 빈 테이블을 만들면 시간표 EXISTS 필터가 항상 거짓이 되므로 만들지 않는다(#2530).
    expect(tables, isNot(contains('transit_feed_info')));
  });

  test('노선도 테이블 결측은 구제하고 다른 도메인 데이터는 그대로 둔다', () async {
    final directory = await _temporaryDirectory('rescue-route-map-');
    final file = File('${directory.path}/capital.sqlite');
    _buildPackSchemaPack(file, activePack: 'capital');
    _dropTables(file, ['route_map_positions', 'route_map_line_tracks']);

    final database = CatalogDatabase.file(file);
    addTearDown(database.close);
    final plan = await database.rescueMissingCatalogTables();
    final positions = await database
        .customSelect('SELECT COUNT(*) AS count FROM route_map_positions')
        .getSingle();
    final indexes = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL",
        )
        .get();

    expect(plan.isBlocked, isFalse);
    expect(plan.rescuableMissingTables, {
      'route_map_positions',
      'route_map_line_tracks',
    });
    expect(positions.read<int>('count'), 0);
    expect({
      for (final row in indexes) row.read<String>('name'),
    }, contains('idx_route_map_positions_region_line'));
  });

  test('구제 실행은 세션당 한 번 신호를 남기고 테이블별 횟수를 누적한다', () async {
    final logged = <String>[];
    CatalogSchemaDiagnostics.replaceForTest(logged.add);
    addTearDown(CatalogSchemaDiagnostics.reset);
    final directory = await _temporaryDirectory('rescue-signal-');
    final first = File('${directory.path}/first.sqlite');
    await _buildInstalledPack(first, activePack: 'capital');
    _dropTables(first, ['station_facility_evidence']);
    final second = File('${directory.path}/second.sqlite');
    await _buildInstalledPack(second, activePack: 'capital');
    _dropTables(second, ['facility_status_snapshots']);

    final firstDatabase = CatalogDatabase.file(first);
    addTearDown(firstDatabase.close);
    await firstDatabase.rescueMissingCatalogTables();
    final secondDatabase = CatalogDatabase.file(second);
    addTearDown(secondDatabase.close);
    await secondDatabase.rescueMissingCatalogTables();

    expect(CatalogSchemaDiagnostics.instance.rescuedTableCounts, {
      'station_facility_evidence': 1,
      'facility_status_snapshots': 1,
    });
    expect(logged.where((line) => line.contains('빈 테이블로 구제함')), hasLength(1));
    expect(logged.first, contains('station_facility_evidence'));
  });

  test('같은 팩의 스키마 거부와 무결성 거부는 각각 신호를 남긴다', () async {
    final logged = <String>[];
    CatalogSchemaDiagnostics.replaceForTest(logged.add);
    addTearDown(CatalogSchemaDiagnostics.reset);

    CatalogSchemaDiagnostics.instance.recordPackRejected(
      artifact: 'capital-v18.sqlite',
      blockingTableNames: const {'transit_stop_times'},
    );
    CatalogSchemaDiagnostics.instance.recordPackIntegrityRejected(
      artifact: 'capital-v18.sqlite',
      expectedSha256: '0' * 64,
      actualSha256: '1' * 64,
    );

    expect(
      CatalogSchemaDiagnostics
          .instance
          .rejectedPackCounts['capital-v18.sqlite'],
      2,
    );
    expect(logged.where((line) => line.contains('필수 테이블 결측')), hasLength(1));
    expect(logged.where((line) => line.contains('무결성')), hasLength(1));
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
    final required = database.requiredCatalogTableNames;
    final tables = await _tableNames(database);

    expect(opener.openedBundledDataPack, isTrue);
    // drift 선언 33 + raw SQL 3. 이 수가 바뀌었다면 숫자만 고치지 말고 함께 갱신할 대상을
    // 확인하라 — contracts/datapack/pack-app-schema-parity-allowlist.json,
    // contracts/datapack/catalog-raw-sql-tables.json, rescuableCatalogTableNames,
    // 그리고 새 테이블이 팩에 없다면 팩 재빌드까지다.
    expect(required.length, 36);
    expect(
      tables,
      containsAll(required.difference(absenceTolerantCatalogTableNames)),
    );
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

  test('구제 DDL이 팩 파일을 바꾸면 무결성 기준선을 함께 갱신한다', () async {
    // 구제는 활성 팩 파일에 DDL을 쓴다(#2527). 기록된 기대 해시를 그대로 두면
    // 재활성화 해시 대조(#2532)가 정상 팩을 거부한다.
    final directory = await _temporaryDirectory('rescue-integrity-');
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final pack = File('${catalogDirectory.path}/capital-v18.sqlite');
    await _buildInstalledPack(pack, activePack: 'capital-v18');
    _dropTables(pack, ['station_facility_evidence']);
    final installedSha256 = sha256.convert(await pack.readAsBytes()).toString();
    await File(
      '${pack.path}.sha256',
    ).writeAsString('$installedSha256\n', flush: true);
    await _writeCurrentPointer(catalogDirectory, version: '18', file: pack);
    final userDatabase = UserDatabase.memory();
    addTearDown(userDatabase.close);

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);
    final rescuedSha256 = sha256.convert(await pack.readAsBytes()).toString();
    final lookup = await DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    ).readInstalledPointer(id: 'capital', version: '18');

    expect(opener.openedBundledDataPack, isFalse);
    expect(rescuedSha256, isNot(installedSha256));
    expect(
      await File('${pack.path}.sha256').readAsString(),
      '$rescuedSha256\n',
    );
    expect(lookup.pointer?.sha256, rescuedSha256);
  });

  test('스캔 중 거부한 후보의 기준선도 마이그레이션 뒤 값으로 맞춘다', () async {
    // drift onUpgrade는 후보 판정의 첫 질의에서 이미 실행된다. 거부돼 닫히는 후보도
    // 파일은 바뀐 채 남으므로 기준선을 갱신하지 않으면 나중에 영구 거부가 된다(#2532).
    final directory = await _temporaryDirectory('rescue-scan-integrity-');
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final rejected = File('${catalogDirectory.path}/capital-v19.sqlite');
    await _buildInstalledPack(rejected, activePack: 'capital-v19');
    _dropTables(rejected, ['transit_stop_times']);
    _setUserVersion(rejected, catalogDatabaseSchemaVersion - 1);
    final knownGood = File('${catalogDirectory.path}/capital-v18.sqlite');
    await _buildInstalledPack(knownGood, activePack: 'capital-v18');
    final installedSha256 = sha256
        .convert(await rejected.readAsBytes())
        .toString();
    await File(
      '${rejected.path}.sha256',
    ).writeAsString('$installedSha256\n', flush: true);
    await _writeCurrentPointer(catalogDirectory, version: '19', file: rejected);
    final userDatabase = UserDatabase.memory();
    addTearDown(userDatabase.close);

    final opener = CatalogDatabaseOpener(
      databaseDirectory: directory,
      assetBundle: rootBundle,
    );
    final database = await opener.open();
    addTearDown(database.close);
    final migratedSha256 = sha256
        .convert(await rejected.readAsBytes())
        .toString();
    final lookup = await DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    ).readInstalledPointer(id: 'capital', version: '19');

    expect(opener.openedBundledDataPack, isFalse);
    expect(await _activePack(database), 'capital-v18');
    expect(migratedSha256, isNot(installedSha256));
    expect(lookup.pointer?.sha256, migratedSha256);
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

/// 실제 배포 팩과 같은 경로로 fixture를 만든다.
///
/// `tools/datapack/build-datapack.mjs`가 `catalog-schema.sql`을 그대로 exec하므로 fixture도
/// 같은 파일을 exec한다. drift `onCreate` 산출물과는 FK·CHECK·nullability가 다르다.
void _buildPackSchemaPack(File file, {required String activePack}) {
  final schema = File(
    '../../tools/datapack/schema/catalog-schema.sql',
  ).readAsStringSync();
  final raw = sqlite.sqlite3.open(file.path);
  try {
    raw.execute(schema);
    raw.execute(
      "INSERT INTO catalog_metadata (key, value) VALUES ('schemaVersion', '1')",
    );
    raw.execute('INSERT INTO catalog_metadata (key, value) VALUES (?, ?)', [
      'activePack',
      activePack,
    ]);
  } finally {
    raw.close();
  }
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

/// 팩 `user_version`을 앱 스키마보다 낮게 만들어 여는 것만으로 drift `onUpgrade`가
/// 실행되도록 한다. 설치 검증이 `user_version <= 앱 버전`을 허용하므로 정상 팩에서도
/// 생기는 상태다.
void _setUserVersion(File file, int userVersion) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    raw.execute('PRAGMA user_version = $userVersion');
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
