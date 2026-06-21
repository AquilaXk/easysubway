import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_installer.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installer는 손상 gzip이면 기존 current pointer를 유지한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-corrupt-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final oldPack = File('${catalogDirectory.path}/capital-v17.sqlite');
    await oldPack.writeAsString('old pack');
    final current = File('${catalogDirectory.path}/current.json');
    await current.writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '17',
        'path': oldPack.path,
        'sha256': 'old-sha',
      }),
    );
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );

    final corruptBytes = [1, 2, 3, 4];
    final result = await installer.install(
      pack: _pack(
        version: '18',
        sha256: sha256.convert(corruptBytes).toString(),
        sqliteSha256: '1' * 64,
        sizeBytes: corruptBytes.length,
      ),
      compressedBytes: corruptBytes,
    );
    final pointer = await installer.readCurrentPointer();

    expect(result.status, DataPackInstallStatus.rejected);
    expect(result.reason, DataPackInstallRejectionReason.invalidArchive);
    expect(pointer?.version, '17');
    expect(await oldPack.exists(), isTrue);
  });

  test('installer는 빈 sqlite payload를 rejected로 처리하고 임시 파일을 지운다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-empty-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );
    final sqliteBytes = <int>[];
    final compressedBytes = gzip.encode(sqliteBytes);

    final result = await installer.install(
      pack: _pack(
        version: '18',
        sha256: sha256.convert(compressedBytes).toString(),
        sqliteSha256: sha256.convert(sqliteBytes).toString(),
        sizeBytes: compressedBytes.length,
      ),
      compressedBytes: compressedBytes,
    );

    expect(result.status, DataPackInstallStatus.rejected);
    expect(result.reason, DataPackInstallRejectionReason.invalidSqliteHeader);
    expect(
      await File('${catalogDirectory.path}/capital-v18.sqlite.tmp').exists(),
      isFalse,
    );
    expect(
      await File('${catalogDirectory.path}/current.json').exists(),
      isFalse,
    );
  });

  test('installer는 검증된 sqlite pack을 버전별 파일로 설치하고 current를 전환한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-install-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    final compressedBytes = gzip.encode(sqliteBytes);
    final installer = DataPackInstaller(
      catalogDirectory: Directory('${directory.path}/catalog'),
      userDatabase: userDatabase,
    );

    final result = await installer.install(
      pack: _pack(
        version: '18',
        sha256: sha256.convert(compressedBytes).toString(),
        sqliteSha256: sha256.convert(sqliteBytes).toString(),
        sizeBytes: compressedBytes.length,
      ),
      compressedBytes: compressedBytes,
    );
    final pointer = await installer.readCurrentPointer();
    final installedRows = await userDatabase
        .select(userDatabase.installedDataPacks)
        .get();

    expect(result.status, DataPackInstallStatus.installed);
    expect(pointer?.path.endsWith('catalog/capital-v18.sqlite'), isTrue);
    expect(File(pointer!.path).existsSync(), isTrue);
    expect(installedRows.single.packId, 'capital');
    expect(installedRows.single.version, '18');
  });

  test('installer는 legacy manifest에 sizeBytes가 없으면 길이 검사를 건너뛴다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-legacy-size-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    final compressedBytes = gzip.encode(sqliteBytes);
    final installer = DataPackInstaller(
      catalogDirectory: Directory('${directory.path}/catalog'),
      userDatabase: userDatabase,
    );

    final result = await installer.install(
      pack: _pack(
        version: '18',
        sha256: sha256.convert(compressedBytes).toString(),
        sqliteSha256: sha256.convert(sqliteBytes).toString(),
        sizeBytes: null,
      ),
      compressedBytes: compressedBytes,
    );

    expect(result.status, DataPackInstallStatus.installed);
    expect(result.pointer?.version, '18');
  });

  test('installer는 새 pack 설치 후 같은 pack의 오래된 버전을 정리한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-prune-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final oldest = File('${catalogDirectory.path}/capital-v16.sqlite');
    final previous = File('${catalogDirectory.path}/capital-v17.sqlite');
    await oldest.writeAsString('oldest');
    await previous.writeAsString('previous');
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    final compressedBytes = gzip.encode(sqliteBytes);
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );

    await installer.install(
      pack: _pack(
        version: '18',
        sha256: sha256.convert(compressedBytes).toString(),
        sqliteSha256: sha256.convert(sqliteBytes).toString(),
        sizeBytes: compressedBytes.length,
      ),
      compressedBytes: compressedBytes,
    );

    expect(await oldest.exists(), isFalse);
    expect(await previous.exists(), isTrue);
    expect(
      await File('${catalogDirectory.path}/capital-v18.sqlite').exists(),
      isTrue,
    );
  });

  test('installer는 emergency override 대상 버전을 정리하지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-prune-override-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final overridePack = File('${catalogDirectory.path}/capital-v17.sqlite');
    final previous = File('${catalogDirectory.path}/capital-v18.sqlite');
    await overridePack.writeAsString('override');
    await previous.writeAsString('previous');
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    final compressedBytes = gzip.encode(sqliteBytes);
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );

    await installer.install(
      pack: _pack(
        version: '19',
        sha256: sha256.convert(compressedBytes).toString(),
        sqliteSha256: sha256.convert(sqliteBytes).toString(),
        sizeBytes: compressedBytes.length,
      ),
      compressedBytes: compressedBytes,
      protectedVersions: const {'17'},
    );

    expect(await overridePack.exists(), isTrue);
    expect(
      await File('${catalogDirectory.path}/capital-v19.sqlite').exists(),
      isTrue,
    );
  });

  test('installer는 staged install 중 기존 current pack을 정리하지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-stage-prune-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final currentPack = File('${catalogDirectory.path}/capital-v16.sqlite');
    final previousPack = File('${catalogDirectory.path}/capital-v17.sqlite');
    await currentPack.writeAsString('current');
    await previousPack.writeAsString('previous');
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '16',
        'path': currentPack.path,
        'sha256': 'current-sha',
      }),
    );
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    final compressedBytes = gzip.encode(sqliteBytes);
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );

    final result = await installer.install(
      pack: _pack(
        version: '18',
        sha256: sha256.convert(compressedBytes).toString(),
        sqliteSha256: sha256.convert(sqliteBytes).toString(),
        sizeBytes: compressedBytes.length,
      ),
      compressedBytes: compressedBytes,
      activateCurrent: false,
    );

    expect(result.status, DataPackInstallStatus.installed);
    expect(await currentPack.exists(), isTrue);
    expect(await previousPack.exists(), isTrue);
    expect(
      await File('${catalogDirectory.path}/capital-v18.sqlite').exists(),
      isTrue,
    );
  });
}

DataPackManifestEntry _pack({
  required String version,
  required String sha256,
  required String sqliteSha256,
  required int? sizeBytes,
}) {
  return DataPackManifestEntry(
    id: 'capital',
    version: version,
    url: Uri.parse('capital-v$version.sqlite.gz'),
    compressedSha256: sha256,
    sqliteSha256: sqliteSha256,
    sizeBytes: sizeBytes,
    artifactKind: DataPackArtifactKind.fixture,
    signature: const DataPackSignature(
      algorithm: 'sha256-pack-manifest-v1',
      value: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
    sourceInventory: [
      DataPackSourceInventoryEntry(
        id: 'fixture-capital-catalog',
        owner: '테스트',
        url: Uri.parse('https://example.invalid/fixture'),
        license: 'fixture-only',
        licenseStatus: 'fixture-only',
        redistributionAllowed: false,
        updateFrequency: 'manual',
        updatedAt: '2026-06-19T00:00:00.000Z',
        fields: ['stations'],
      ),
    ],
    regionalQualityMetrics: const RegionalQualityMetrics(
      stationCount: 2,
      facilityCoverageRatio: 0.5,
      edgeCount: 2,
      unknownAccessibilityRatio: 0,
    ),
    representativeRouteRegressions: const [],
    schemaVersion: '1',
    requiredTables: const ['catalog_metadata', 'stations', 'station_lines'],
    minimumTableRows: const {'stations': 2},
  );
}

Future<List<int>> _validCatalogSqliteBytes(Directory directory) async {
  final file = File('${directory.path}/fixture.sqlite');
  final database = CatalogDatabase.file(file);
  await database.seedBaselineIfEmpty();
  await database.close();
  return file.readAsBytes();
}
