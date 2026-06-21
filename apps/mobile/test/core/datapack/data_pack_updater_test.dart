import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_client.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_installer.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_updater.dart';
import 'package:easysubway_mobile/core/datapack/emergency_override_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _representativeRouteRegressions = [
  {
    'id': 'direct-local-capital',
    'pattern': 'DIRECT',
    'fromNodeId': 'station-a-line-1',
    'toNodeId': 'station-b-line-1',
    'requiredEdgeIds': ['edge-a-b'],
  },
  {
    'id': 'transfer-capital',
    'pattern': 'TRANSFER',
    'fromNodeId': 'station-a-line-1',
    'toNodeId': 'station-c-line-2',
    'requiredEdgeIds': ['edge-a-b', 'edge-b-transfer', 'edge-b-c'],
  },
  {
    'id': 'multi-transfer-capital',
    'pattern': 'MULTI_TRANSFER',
    'fromNodeId': 'station-a-line-1',
    'toNodeId': 'station-d-line-3',
    'requiredEdgeIds': [
      'edge-a-b',
      'edge-b-transfer',
      'edge-c-transfer',
      'edge-c-d',
    ],
  },
  {
    'id': 'loop-branch-capital',
    'pattern': 'LOOP_BRANCH',
    'fromNodeId': 'station-branch-line-2',
    'toNodeId': 'station-c-line-2',
    'requiredEdgeIds': ['edge-branch-loop', 'edge-loop-c'],
  },
  {
    'id': 'express-local-capital',
    'pattern': 'EXPRESS_LOCAL',
    'fromNodeId': 'station-a-line-1-express',
    'toNodeId': 'station-b-line-1-express',
    'requiredEdgeIds': ['edge-a-b-express'],
  },
];

void main() {
  test('updater는 서버가 손상 pack을 내려주면 기존 current를 유지한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-corrupt-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final oldPack = File('${catalogDirectory.path}/capital-v17.sqlite');
    await oldPack.writeAsString('old pack');
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '17',
        'path': oldPack.path,
        'sha256': 'old-sha',
      }),
    );
    final corruptBytes = [1, 2, 3, 4];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      if (request.uri.path == '/manifest.json') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'ttlSeconds': 60,
              'packs': [
                {
                  'id': 'capital',
                  'version': '18',
                  'url': 'capital-v18.sqlite.gz',
                  'sha256': sha256.convert(corruptBytes).toString(),
                  'sqliteSha256': '1' * 64,
                  'sizeBytes': corruptBytes.length,
                  ..._fixtureManifestMetadata(
                    version: '18',
                    compressedSha256: sha256.convert(corruptBytes).toString(),
                    sqliteSha256: '1' * 64,
                    sizeBytes: corruptBytes.length,
                  ),
                  'schemaVersion': '1',
                  'requiredTables': ['catalog_metadata'],
                },
              ],
            }),
          )
          ..close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..add(corruptBytes)
        ..close();
    });
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 19, 10),
    );
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/manifest.json',
        ),
        stateRepository: stateRepository,
      ),
      installer: installer,
    );

    final results = await updater.checkForUpdates();
    final pointer = await installer.readCurrentPointer();
    final manifestCache = await stateRepository.readManifestCache();

    expect(results.single.status, DataPackInstallStatus.rejected);
    expect(
      results.single.reason,
      DataPackInstallRejectionReason.invalidArchive,
    );
    expect(pointer?.version, '17');
    expect(await oldPack.exists(), isTrue);
    expect(manifestCache, isNull);
  });

  test('updater는 manifest에서 emergency override가 해제되면 저장값을 지운다', () async {
    final userDatabase = user_db.UserDatabase.memory();
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
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ttlSeconds': 60, 'packs': []}))
        ..close();
    });
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 19, 15),
    );
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/manifest.json',
        ),
        stateRepository: stateRepository,
      ),
      installer: DataPackInstaller(
        catalogDirectory: Directory.systemTemp,
        userDatabase: userDatabase,
      ),
      emergencyOverrideRepository: overrideRepository,
    );

    await updater.checkForUpdates();

    expect(await overrideRepository.readOverride(), isNull);
    expect(await stateRepository.readManifestCache(), isNotNull);
  });

  test('updater는 pack URL을 데이터팩 base URL 기준으로 해석한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-url-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    final compressedBytes = gzip.encode(sqliteBytes);
    final requestedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      requestedPaths.add(request.uri.path);
      switch (request.uri.path) {
        case '/datapacks/catalog/current.json':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'ttlSeconds': 60,
                'packs': [
                  _packJson(
                    version: '18',
                    url: 'catalog/capital-v18.sqlite.gz',
                    compressedBytes: compressedBytes,
                    sqliteBytes: sqliteBytes,
                  ),
                ],
              }),
            )
            ..close();
        case '/datapacks/catalog/capital-v18.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(compressedBytes)
            ..close();
        default:
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
      }
    });
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: DataPackUpdateStateRepository(
          userDatabase: userDatabase,
          now: () => DateTime.utc(2026, 6, 19, 16),
        ),
      ),
      installer: DataPackInstaller(
        catalogDirectory: catalogDirectory,
        userDatabase: userDatabase,
      ),
    );

    final results = await updater.checkForUpdates();

    expect(results.single.status, DataPackInstallStatus.installed);
    expect(requestedPaths, [
      '/datapacks/catalog/current.json',
      '/datapacks/catalog/capital-v18.sqlite.gz',
    ]);
  });

  test('updater는 multi-pack 실패 시 기존 current pointer를 유지한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-partial-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final oldPack = File('${catalogDirectory.path}/capital-v17.sqlite');
    await oldPack.writeAsString('old pack');
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '17',
        'path': oldPack.path,
        'sha256': 'old-sha',
      }),
    );
    final validSqliteBytes = await _validCatalogSqliteBytes(directory);
    final validCompressedBytes = gzip.encode(validSqliteBytes);
    final secondSqliteBytes = await _validCatalogSqliteBytes(directory);
    final secondCompressedBytes = gzip.encode(secondSqliteBytes);
    final corruptBytes = gzip.encode(<int>[]);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      switch (request.uri.path) {
        case '/datapacks/catalog/current.json':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'ttlSeconds': 60,
                'packs': [
                  _packJson(
                    version: '18',
                    url: 'catalog/capital-v18.sqlite.gz',
                    compressedBytes: validCompressedBytes,
                    sqliteBytes: validSqliteBytes,
                  ),
                  _packJson(
                    version: '19',
                    url: 'catalog/capital-v19.sqlite.gz',
                    compressedBytes: secondCompressedBytes,
                    sqliteBytes: secondSqliteBytes,
                  ),
                  _packJson(
                    version: '20',
                    url: 'catalog/capital-v20.sqlite.gz',
                    compressedBytes: corruptBytes,
                    sqliteBytes: const <int>[],
                  ),
                ],
              }),
            )
            ..close();
        case '/datapacks/catalog/capital-v18.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(validCompressedBytes)
            ..close();
        case '/datapacks/catalog/capital-v19.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(secondCompressedBytes)
            ..close();
        case '/datapacks/catalog/capital-v20.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(corruptBytes)
            ..close();
        default:
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
      }
    });
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 19, 17),
    );
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: stateRepository,
      ),
      installer: installer,
    );

    final results = await updater.checkForUpdates();
    final pointer = await installer.readCurrentPointer();

    expect(results.map((result) => result.status), [
      DataPackInstallStatus.installed,
      DataPackInstallStatus.installed,
      DataPackInstallStatus.rejected,
    ]);
    expect(pointer?.version, '17');
    expect(await oldPack.exists(), isTrue);
    expect(
      await File('${catalogDirectory.path}/capital-v18.sqlite').exists(),
      isTrue,
    );
    expect(await stateRepository.readManifestCache(), isNull);
  });

  test('updater는 manifest 순서와 무관하게 최신 capital pack을 current로 선택한다', () async {
    // activePack이 없는 manifest에서는 기본 pack id의 최신 version을 current로 선택한다.
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-active-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    final olderSqliteBytes = await _validCatalogSqliteBytes(directory);
    final olderCompressedBytes = gzip.encode(olderSqliteBytes);
    final newerSqliteBytes = await _validCatalogSqliteBytes(directory);
    final newerCompressedBytes = gzip.encode(newerSqliteBytes);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      switch (request.uri.path) {
        case '/datapacks/catalog/current.json':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'ttlSeconds': 60,
                'packs': [
                  _packJson(
                    version: '19',
                    url: 'catalog/capital-v19.sqlite.gz',
                    compressedBytes: newerCompressedBytes,
                    sqliteBytes: newerSqliteBytes,
                  ),
                  _packJson(
                    version: '18',
                    url: 'catalog/capital-v18.sqlite.gz',
                    compressedBytes: olderCompressedBytes,
                    sqliteBytes: olderSqliteBytes,
                  ),
                ],
              }),
            )
            ..close();
        case '/datapacks/catalog/capital-v18.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(olderCompressedBytes)
            ..close();
        case '/datapacks/catalog/capital-v19.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(newerCompressedBytes)
            ..close();
        default:
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
      }
    });
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: DataPackUpdateStateRepository(
          userDatabase: userDatabase,
          now: () => DateTime.utc(2026, 6, 19, 18, 30),
        ),
      ),
      installer: installer,
    );

    final results = await updater.checkForUpdates();
    final pointer = await installer.readCurrentPointer();

    expect(
      results.every(
        (result) => result.status == DataPackInstallStatus.installed,
      ),
      isTrue,
    );
    expect(pointer?.version, '19');
  });

  test('updater는 rollback manifest가 이미 설치된 이전 pack을 current로 활성화한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-rollback-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    final v18SqliteBytes = await _validCatalogSqliteBytes(directory);
    final v18CompressedBytes = gzip.encode(v18SqliteBytes);
    final v19SqliteBytes = await _validCatalogSqliteBytes(directory);
    final v19CompressedBytes = gzip.encode(v19SqliteBytes);
    var now = DateTime.utc(2026, 6, 21, 5);
    var manifestJson = <String, Object?>{
      'ttlSeconds': 1,
      'activePack': {'id': 'capital', 'version': '19'},
      'packs': [
        _packJson(
          version: '18',
          url: 'catalog/capital-v18.sqlite.gz',
          compressedBytes: v18CompressedBytes,
          sqliteBytes: v18SqliteBytes,
        ),
        _packJson(
          version: '19',
          url: 'catalog/capital-v19.sqlite.gz',
          compressedBytes: v19CompressedBytes,
          sqliteBytes: v19SqliteBytes,
        ),
      ],
    };
    final requestedPaths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      requestedPaths.add(request.uri.path);
      switch (request.uri.path) {
        case '/datapacks/catalog/current.json':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(manifestJson))
            ..close();
        case '/datapacks/catalog/capital-v18.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(v18CompressedBytes)
            ..close();
        case '/datapacks/catalog/capital-v19.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(v19CompressedBytes)
            ..close();
        default:
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
      }
    });
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => now,
    );
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: stateRepository,
        now: () => now,
      ),
      installer: installer,
    );

    final installResults = await updater.checkForUpdates();
    final installedPointer = await installer.readCurrentPointer();
    final requestCountAfterInstall = requestedPaths.length;

    manifestJson = {
      'ttlSeconds': 1,
      'activePack': {'id': 'capital', 'version': '18'},
      'packs': const [],
    };
    now = now.add(const Duration(seconds: 2));
    final rollbackResults = await updater.checkForUpdates();
    final rollbackPointer = await installer.readCurrentPointer();

    expect(
      installResults.every(
        (result) => result.status == DataPackInstallStatus.installed,
      ),
      isTrue,
    );
    expect(installedPointer?.version, '19');
    expect(rollbackResults, isEmpty);
    expect(rollbackPointer?.version, '18');
    expect(
      await File('${catalogDirectory.path}/capital-v18.sqlite').exists(),
      isTrue,
    );
    expect(
      await File('${catalogDirectory.path}/capital-v19.sqlite').exists(),
      isTrue,
    );
    expect(requestedPaths.skip(requestCountAfterInstall), [
      '/datapacks/catalog/current.json',
    ]);
  });

  test('updater는 zero-padded activePack 이전 version을 prune하지 않는다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-active-prune-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    final v017SqliteBytes = await _validCatalogSqliteBytes(directory);
    final v017CompressedBytes = gzip.encode(v017SqliteBytes);
    final v18SqliteBytes = await _validCatalogSqliteBytes(directory);
    final v18CompressedBytes = gzip.encode(v18SqliteBytes);
    final v19SqliteBytes = await _validCatalogSqliteBytes(directory);
    final v19CompressedBytes = gzip.encode(v19SqliteBytes);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      switch (request.uri.path) {
        case '/datapacks/catalog/current.json':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'ttlSeconds': 60,
                'activePack': {'id': 'capital', 'version': '017'},
                'packs': [
                  _packJson(
                    version: '19',
                    url: 'catalog/capital-v19.sqlite.gz',
                    compressedBytes: v19CompressedBytes,
                    sqliteBytes: v19SqliteBytes,
                  ),
                  _packJson(
                    version: '18',
                    url: 'catalog/capital-v18.sqlite.gz',
                    compressedBytes: v18CompressedBytes,
                    sqliteBytes: v18SqliteBytes,
                  ),
                  _packJson(
                    version: '017',
                    url: 'catalog/capital-v017.sqlite.gz',
                    compressedBytes: v017CompressedBytes,
                    sqliteBytes: v017SqliteBytes,
                  ),
                ],
              }),
            )
            ..close();
        case '/datapacks/catalog/capital-v017.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(v017CompressedBytes)
            ..close();
        case '/datapacks/catalog/capital-v18.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(v18CompressedBytes)
            ..close();
        case '/datapacks/catalog/capital-v19.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(v19CompressedBytes)
            ..close();
        default:
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
      }
    });
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: DataPackUpdateStateRepository(
          userDatabase: userDatabase,
          now: () => DateTime.utc(2026, 6, 19, 18, 45),
        ),
      ),
      installer: installer,
    );

    final results = await updater.checkForUpdates();
    final pointer = await installer.readCurrentPointer();

    expect(
      results.every(
        (result) => result.status == DataPackInstallStatus.installed,
      ),
      isTrue,
    );
    expect(pointer?.version, '017');
    expect(
      await File('${catalogDirectory.path}/capital-v017.sqlite').exists(),
      isTrue,
    );
    expect(
      await File('${catalogDirectory.path}/capital-v18.sqlite').exists(),
      isTrue,
    );
    expect(
      await File('${catalogDirectory.path}/capital-v19.sqlite').exists(),
      isTrue,
    );
  });

  test('updater는 pack 검증 실패 시 기존 emergency override를 유지한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-override-fail-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
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
    final corruptBytes = [1, 2, 3, 4];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      switch (request.uri.path) {
        case '/datapacks/catalog/current.json':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'ttlSeconds': 60,
                'packs': [
                  {
                    'id': 'capital',
                    'version': '18',
                    'url': 'catalog/capital-v18.sqlite.gz',
                    'sha256': sha256.convert(corruptBytes).toString(),
                    'sqliteSha256': '1' * 64,
                    'sizeBytes': corruptBytes.length,
                    ..._fixtureManifestMetadata(
                      version: '18',
                      compressedSha256: sha256.convert(corruptBytes).toString(),
                      sqliteSha256: '1' * 64,
                      sizeBytes: corruptBytes.length,
                    ),
                    'schemaVersion': '1',
                    'requiredTables': ['catalog_metadata'],
                  },
                ],
              }),
            )
            ..close();
        case '/datapacks/catalog/capital-v18.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(corruptBytes)
            ..close();
        default:
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
      }
    });
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: DataPackUpdateStateRepository(
          userDatabase: userDatabase,
          now: () => DateTime.utc(2026, 6, 19, 18),
        ),
      ),
      installer: DataPackInstaller(
        catalogDirectory: Directory('${directory.path}/catalog'),
        userDatabase: userDatabase,
      ),
      emergencyOverrideRepository: overrideRepository,
    );

    final results = await updater.checkForUpdates();
    final override = await overrideRepository.readOverride();

    expect(results.single.status, DataPackInstallStatus.rejected);
    expect(override?.version, '17');
    expect(override?.reason, '시설 상태 긴급 정정');
  });
}

Map<String, Object?> _packJson({
  required String version,
  required String url,
  required List<int> compressedBytes,
  required List<int> sqliteBytes,
}) {
  final compressedSha256 = sha256.convert(compressedBytes).toString();
  final sqliteSha256 = sha256.convert(sqliteBytes).toString();
  return {
    'id': 'capital',
    'version': version,
    'url': url,
    'sha256': compressedSha256,
    'sqliteSha256': sqliteSha256,
    'sizeBytes': compressedBytes.length,
    ..._fixtureManifestMetadata(
      version: version,
      compressedSha256: compressedSha256,
      sqliteSha256: sqliteSha256,
      sizeBytes: compressedBytes.length,
    ),
    'schemaVersion': '1',
    'requiredTables': ['catalog_metadata'],
  };
}

Map<String, Object?> _fixtureManifestMetadata({
  required String version,
  required String compressedSha256,
  required String sqliteSha256,
  required int sizeBytes,
}) {
  return {
    'artifactKind': 'fixture',
    'representativeRouteRegressions': _representativeRouteRegressions,
    'representativeRouteRegressionSignature': {
      'algorithm': 'sha256-route-regression-v1',
      'value': _routeRegressionSignatureValue(
        'capital',
        version,
        compressedSha256,
        sqliteSha256,
        sizeBytes,
      ),
    },
    'signature': {
      'algorithm': 'sha256-pack-manifest-v1',
      'value': _signatureValue(
        'capital',
        version,
        compressedSha256,
        sqliteSha256,
        sizeBytes,
      ),
    },
    'sourceInventory': [
      {
        'id': 'fixture-capital-catalog',
        'owner': '테스트',
        'url': 'https://example.invalid/fixture',
        'license': 'fixture-only',
        'licenseStatus': 'fixture-only',
        'redistributionAllowed': false,
        'updateFrequency': 'manual',
        'updatedAt': '2026-06-19T00:00:00.000Z',
        'fields': ['stations'],
      },
    ],
    'regionalQualityMetrics': {
      'stationCount': 2,
      'facilityCoverageRatio': 0.5,
      'edgeCount': 2,
      'unknownAccessibilityRatio': 0.0,
    },
  };
}

String _signatureValue(
  String id,
  String version,
  String compressedSha256,
  String sqliteSha256,
  int sizeBytes,
) {
  return sha256
      .convert(
        utf8.encode('$id:$version:$compressedSha256:$sqliteSha256:$sizeBytes'),
      )
      .toString();
}

String _routeRegressionSignatureValue(
  String id,
  String version,
  String compressedSha256,
  String sqliteSha256,
  int sizeBytes,
) {
  return sha256
      .convert(
        utf8.encode(
          '$id:$version:$compressedSha256:$sqliteSha256:$sizeBytes:${jsonEncode(_representativeRouteRegressions)}',
        ),
      )
      .toString();
}

Future<List<int>> _validCatalogSqliteBytes(Directory directory) async {
  final file = File('${directory.path}/fixture.sqlite');
  final database = CatalogDatabase.file(file);
  await database.seedBaselineIfEmpty();
  await database.close();
  return file.readAsBytes();
}
