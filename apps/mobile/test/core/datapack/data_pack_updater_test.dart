import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
// 정준 직렬화는 검증 대상 구현을 그대로 쓴다. 테스트가 규칙을 복제하면 3언어
// 분열(이슈 #2528)을 구조적으로 검출할 수 없다.
import 'package:easysubway_mobile/core/datapack/canonical_json.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_client.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_installer.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_updater.dart';
import 'package:easysubway_mobile/core/datapack/emergency_override_repository.dart';
import 'package:easysubway_mobile/core/datapack/network_condition_source.dart';
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

  test('updater는 손상된 current pointer가 있어도 새 pack으로 복구한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-bad-pointer-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    await File(
      '${catalogDirectory.path}/current.json',
    ).writeAsString('{not-json');
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    final compressedBytes = gzip.encode(sqliteBytes);
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
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 19, 10, 30),
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

    expect(results.single.status, DataPackInstallStatus.installed);
    expect(pointer?.version, '18');
    expect(await stateRepository.readManifestCache(), isNotNull);
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
        ..write(jsonEncode({'ttlSeconds': 60, 'packs': <Object?>[]}))
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

  test('updater는 metered 네트워크에서 다운로드를 보류하고 동의 상태를 저장한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-metered-',
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
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 7, 9, 1),
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
      networkConditionSource: const FixedNetworkConditionSource(
        NetworkCondition.metered,
      ),
      now: () => DateTime.utc(2026, 7, 9, 1),
    );

    final results = await updater.checkForUpdates();
    final policyState = await stateRepository.readPolicyState();

    expect(results, isEmpty);
    expect(requestedPaths, ['/datapacks/catalog/current.json']);
    expect(policyState.pendingConsentBytes, compressedBytes.length);
    expect(await installer.readCurrentPointer(), isNull);
  });

  test('updater는 사용자 동의 trigger에서 metered 다운로드를 통과시킨다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-metered-consent-',
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
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 7, 9, 1),
    );
    await stateRepository.savePolicyState(
      const DataPackUpdatePolicyState(pendingConsentBytes: 1024),
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
      networkConditionSource: const FixedNetworkConditionSource(
        NetworkCondition.metered,
      ),
      now: () => DateTime.utc(2026, 7, 9, 1),
    );

    final results = await updater.checkForUpdates(
      trigger: UpdateTrigger.userConsent,
    );
    final policyState = await stateRepository.readPolicyState();

    expect(results.single.status, DataPackInstallStatus.installed);
    expect(requestedPaths, [
      '/datapacks/catalog/current.json',
      '/datapacks/catalog/capital-v18.sqlite.gz',
    ]);
    expect(policyState.pendingConsentBytes, isNull);
    expect((await installer.readCurrentPointer())?.version, '18');
  });

  test('updater는 userConsent trigger에서 backoff 창을 무시하고 즉시 시도한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-consent-backoff-',
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
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 7, 9, 1),
    );
    // 이전 세션의 pendingConsent + 이번 세션 manifest 실패로 저장된 backoff 창.
    await stateRepository.savePolicyState(
      DataPackUpdatePolicyState(
        pendingConsentBytes: 1024,
        backoffAttempts: 2,
        backoffUntil: DateTime.utc(2026, 7, 9, 1, 30),
        lastFailureReason: 'manifest fetch failed',
      ),
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
      networkConditionSource: const FixedNetworkConditionSource(
        NetworkCondition.metered,
      ),
      now: () => DateTime.utc(2026, 7, 9, 1),
    );

    final results = await updater.checkForUpdates(
      trigger: UpdateTrigger.userConsent,
    );
    final policyState = await stateRepository.readPolicyState();

    expect(results.single.status, DataPackInstallStatus.installed);
    expect(requestedPaths, [
      '/datapacks/catalog/current.json',
      '/datapacks/catalog/capital-v18.sqlite.gz',
    ]);
    expect(policyState.backoffUntil, isNull);
    expect(policyState.pendingConsentBytes, isNull);
    expect(policyState.lastFailureReason, isNull);
    expect((await installer.readCurrentPointer())?.version, '18');
  });

  test('updater는 foregroundResume trigger에서 backoff 창에 차단된다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 7, 9, 1),
    );
    await stateRepository.savePolicyState(
      DataPackUpdatePolicyState(
        pendingConsentBytes: 1024,
        backoffAttempts: 1,
        backoffUntil: DateTime.utc(2026, 7, 9, 1, 30),
      ),
    );
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      requestCount++;
      request.response
        ..statusCode = HttpStatus.ok
        ..close();
    });
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: stateRepository,
      ),
      installer: DataPackInstaller(
        catalogDirectory: Directory.systemTemp,
        userDatabase: userDatabase,
      ),
      now: () => DateTime.utc(2026, 7, 9, 1),
    );

    final results = await updater.checkForUpdates(
      trigger: UpdateTrigger.foregroundResume,
    );

    expect(results, isEmpty);
    expect(requestCount, 0);
  });

  test('updater는 metered 보류 후 userConsent에서 manifest를 다시 받아 설치한다', () async {
    // 회귀 고정: metered 보류 시 manifest 캐시를 저장하지 않아야
    // 동의 시점의 재확인이 fresh cache 조기 반환에 막히지 않는다.
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-consent-refetch-',
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
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 7, 9, 1),
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
      networkConditionSource: const FixedNetworkConditionSource(
        NetworkCondition.metered,
      ),
      now: () => DateTime.utc(2026, 7, 9, 1),
    );

    final held = await updater.checkForUpdates();
    final heldState = await stateRepository.readPolicyState();
    final results = await updater.checkForUpdates(
      trigger: UpdateTrigger.userConsent,
    );

    expect(held, isEmpty);
    expect(heldState.pendingConsentBytes, compressedBytes.length);
    expect(results.single.status, DataPackInstallStatus.installed);
    expect(requestedPaths, [
      '/datapacks/catalog/current.json',
      '/datapacks/catalog/current.json',
      '/datapacks/catalog/capital-v18.sqlite.gz',
    ]);
    expect((await installer.readCurrentPointer())?.version, '18');
  });

  test('updater는 offline 판정이면 manifest 요청 없이 종료한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      requestCount++;
      request.response
        ..statusCode = HttpStatus.ok
        ..close();
    });
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: DataPackUpdateStateRepository(
          userDatabase: userDatabase,
          now: () => DateTime.utc(2026, 7, 9, 1),
        ),
      ),
      installer: DataPackInstaller(
        catalogDirectory: Directory.systemTemp,
        userDatabase: userDatabase,
      ),
      networkConditionSource: const FixedNetworkConditionSource(
        NetworkCondition.offline,
      ),
      now: () => DateTime.utc(2026, 7, 9, 1),
    );

    final results = await updater.checkForUpdates();

    expect(results, isEmpty);
    expect(requestCount, 0);
  });

  test('updater는 foreground resume 6시간 하한 안에서는 재확인하지 않는다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 7, 9, 1),
    );
    await stateRepository.savePolicyState(
      DataPackUpdatePolicyState(lastCheckAt: DateTime.utc(2026, 7, 9)),
    );
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      requestCount++;
      request.response
        ..statusCode = HttpStatus.ok
        ..close();
    });
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: stateRepository,
      ),
      installer: DataPackInstaller(
        catalogDirectory: Directory.systemTemp,
        userDatabase: userDatabase,
      ),
      now: () => DateTime.utc(2026, 7, 9, 1),
    );

    final results = await updater.checkForUpdates(
      trigger: UpdateTrigger.foregroundResume,
    );

    expect(results, isEmpty);
    expect(requestCount, 0);
  });

  test('updater는 pending consent가 있으면 unmetered resume에서 하한을 무시한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-pending-unmetered-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final now = DateTime.utc(2026, 7, 9, 1);
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
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => now,
    );
    await stateRepository.savePolicyState(
      DataPackUpdatePolicyState(
        lastCheckAt: now.subtract(const Duration(hours: 1)),
        pendingConsentBytes: compressedBytes.length,
      ),
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
      networkConditionSource: const FixedNetworkConditionSource(
        NetworkCondition.unmetered,
      ),
      now: () => now,
    );

    final results = await updater.checkForUpdates(
      trigger: UpdateTrigger.foregroundResume,
    );
    final policyState = await stateRepository.readPolicyState();

    expect(results.single.status, DataPackInstallStatus.installed);
    expect(requestedPaths, [
      '/datapacks/catalog/current.json',
      '/datapacks/catalog/capital-v18.sqlite.gz',
    ]);
    expect(policyState.pendingConsentBytes, isNull);
    expect((await installer.readCurrentPointer())?.version, '18');
  });

  test('updater는 만료 임박이면 foreground resume 하한을 무시한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final now = DateTime.utc(2026, 7, 9, 1);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => now,
    );
    await stateRepository.savePolicyState(
      DataPackUpdatePolicyState(
        lastCheckAt: now.subtract(const Duration(hours: 1)),
      ),
    );
    await stateRepository.saveManifestCache(
      etag: 'urgent',
      checkedAt: now.subtract(const Duration(hours: 2)),
      ttl: const Duration(minutes: 1),
      expiresAt: now.add(const Duration(days: 3)),
    );
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      requestCount++;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ttlSeconds': 60, 'packs': <Object?>[]}))
        ..close();
    });
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: stateRepository,
        now: () => now,
      ),
      installer: DataPackInstaller(
        catalogDirectory: Directory.systemTemp,
        userDatabase: userDatabase,
      ),
      now: () => now,
    );

    final results = await updater.checkForUpdates(
      trigger: UpdateTrigger.foregroundResume,
    );

    expect(results, isEmpty);
    expect(requestCount, 1);
  });

  test('updater는 manifest 실패 후 백오프 중이면 재요청하지 않는다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    var now = DateTime.utc(2026, 7, 9, 1);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => now,
    );
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      requestCount++;
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    });
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: stateRepository,
        now: () => now,
      ),
      installer: DataPackInstaller(
        catalogDirectory: Directory.systemTemp,
        userDatabase: userDatabase,
      ),
      now: () => now,
    );

    await expectLater(
      updater.checkForUpdates(),
      throwsA(isA<DataPackClientException>()),
    );
    now = now.add(const Duration(seconds: 30));
    final skipped = await updater.checkForUpdates();
    final policyState = await stateRepository.readPolicyState();

    expect(skipped, isEmpty);
    expect(requestCount, 1);
    expect(policyState.backoffAttempts, 1);
    expect(policyState.backoffUntil, DateTime.utc(2026, 7, 9, 1, 1));
  });

  test('updater는 동시에 들어온 확인 요청을 하나로 합친다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    var requestCount = 0;
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      requestCount++;
      await releaseResponse.future;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ttlSeconds': 60, 'packs': <Object?>[]}));
      await request.response.close();
    });
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: DataPackUpdateStateRepository(
          userDatabase: userDatabase,
          now: () => DateTime.utc(2026, 7, 9, 1),
        ),
      ),
      installer: DataPackInstaller(
        catalogDirectory: Directory.systemTemp,
        userDatabase: userDatabase,
      ),
      now: () => DateTime.utc(2026, 7, 9, 1),
    );

    final first = updater.checkForUpdates();
    final second = updater.checkForUpdates();
    await Future<void>.delayed(Duration.zero);
    releaseResponse.complete();
    await Future.wait([first, second]);

    expect(requestCount, 1);
  });

  test('updater는 fresh cache여도 설치 journal을 먼저 복구한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-journal-fresh-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final now = DateTime.utc(2026, 6, 19, 16);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => now,
    );
    await stateRepository.saveManifestCache(
      etag: 'fresh-etag',
      checkedAt: now,
      ttl: const Duration(minutes: 10),
    );
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    final targetPack = File('${catalogDirectory.path}/capital-v18.sqlite');
    await targetPack.writeAsBytes(sqliteBytes, flush: true);
    final journal = File('${catalogDirectory.path}/current.json.installing');
    await journal.writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': targetPack.path,
        'sha256': sha256.convert(sqliteBytes).toString(),
      }),
      flush: true,
    );
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse('http://127.0.0.1:9/catalog/current.json'),
        stateRepository: stateRepository,
      ),
      installer: installer,
    );

    final results = await updater.checkForUpdates();

    expect(results, isEmpty);
    expect(await journal.exists(), isFalse);
    expect(
      await File('${catalogDirectory.path}/current.json').exists(),
      isTrue,
    );
    expect((await installer.readCurrentPointer())?.version, '18');
  });

  test('updater는 active pack history와 명시 dependency만 다운로드한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-active-only-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    final activeSqliteBytes = await _validCatalogSqliteBytes(directory);
    final activeCompressedBytes = gzip.encode(activeSqliteBytes);
    final dependencySqliteBytes = await _validCatalogSqliteBytes(directory);
    final dependencyCompressedBytes = gzip.encode(dependencySqliteBytes);
    final inactiveSqliteBytes = await _validCatalogSqliteBytes(directory);
    final inactiveCompressedBytes = gzip.encode(inactiveSqliteBytes);
    await catalogDirectory.create(recursive: true);
    await File(
      '${catalogDirectory.path}/common-v2.sqlite',
    ).writeAsString('old dependency v2');
    await File(
      '${catalogDirectory.path}/common-v3.sqlite',
    ).writeAsString('old dependency v3');
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
                'activePack': {'id': 'capital', 'version': '19'},
                'packs': [
                  _packJson(
                    id: 'capital',
                    version: '19',
                    url: 'catalog/capital-v19.sqlite.gz',
                    compressedBytes: activeCompressedBytes,
                    sqliteBytes: activeSqliteBytes,
                    dependencies: const [
                      {'id': 'common', 'version': '1'},
                    ],
                  ),
                  _packJson(
                    id: 'common',
                    version: '1',
                    url: 'catalog/common-v1.sqlite.gz',
                    compressedBytes: dependencyCompressedBytes,
                    sqliteBytes: dependencySqliteBytes,
                  ),
                  _packJson(
                    id: 'busan',
                    version: '9',
                    url: 'catalog/busan-v9.sqlite.gz',
                    compressedBytes: inactiveCompressedBytes,
                    sqliteBytes: inactiveSqliteBytes,
                  ),
                ],
              }),
            )
            ..close();
        case '/datapacks/catalog/capital-v19.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(activeCompressedBytes)
            ..close();
        case '/datapacks/catalog/common-v1.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(dependencyCompressedBytes)
            ..close();
        case '/datapacks/catalog/busan-v9.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.internalServerError
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
          now: () => DateTime.utc(2026, 6, 25, 10),
        ),
      ),
      installer: DataPackInstaller(
        catalogDirectory: catalogDirectory,
        userDatabase: userDatabase,
      ),
    );

    final results = await updater.checkForUpdates();
    final pointer = await updater.installer.readCurrentPointer();

    expect(results, hasLength(2));
    expect(
      results.every(
        (result) => result.status == DataPackInstallStatus.installed,
      ),
      isTrue,
    );
    expect(pointer?.id, 'capital');
    expect(pointer?.version, '19');
    expect(requestedPaths, [
      '/datapacks/catalog/current.json',
      '/datapacks/catalog/capital-v19.sqlite.gz',
      '/datapacks/catalog/common-v1.sqlite.gz',
    ]);
    expect(
      await File('${catalogDirectory.path}/common-v1.sqlite').exists(),
      isTrue,
    );
  });

  test('updater는 active pack과 별도 emergency override pack을 다운로드한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-override-pack-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    final activeSqliteBytes = await _validCatalogSqliteBytes(directory);
    final activeCompressedBytes = gzip.encode(activeSqliteBytes);
    final overrideSqliteBytes = await _validCatalogSqliteBytes(directory);
    final overrideCompressedBytes = gzip.encode(overrideSqliteBytes);
    final dependencySqliteBytes = await _validCatalogSqliteBytes(directory);
    final dependencyCompressedBytes = gzip.encode(dependencySqliteBytes);
    final overrideRepository = EmergencyOverrideRepository(
      userDatabase: userDatabase,
    );
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
                'activePack': {'id': 'capital', 'version': '19'},
                'emergencyOverride': {
                  'id': 'capital-emergency',
                  'version': '7',
                  'reason': '시설 상태 긴급 정정',
                },
                'packs': [
                  _packJson(
                    id: 'capital',
                    version: '19',
                    url: 'catalog/capital-v19.sqlite.gz',
                    compressedBytes: activeCompressedBytes,
                    sqliteBytes: activeSqliteBytes,
                  ),
                  _packJson(
                    id: 'capital-emergency',
                    version: '7',
                    url: 'catalog/capital-emergency-v7.sqlite.gz',
                    compressedBytes: overrideCompressedBytes,
                    sqliteBytes: overrideSqliteBytes,
                    dependencies: const [
                      {'id': 'common-emergency', 'version': '1'},
                    ],
                  ),
                  _packJson(
                    id: 'common-emergency',
                    version: '1',
                    url: 'catalog/common-emergency-v1.sqlite.gz',
                    compressedBytes: dependencyCompressedBytes,
                    sqliteBytes: dependencySqliteBytes,
                  ),
                ],
              }),
            )
            ..close();
        case '/datapacks/catalog/capital-v19.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(activeCompressedBytes)
            ..close();
        case '/datapacks/catalog/capital-emergency-v7.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(overrideCompressedBytes)
            ..close();
        case '/datapacks/catalog/common-emergency-v1.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(dependencyCompressedBytes)
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
          now: () => DateTime.utc(2026, 6, 19, 16),
        ),
      ),
      installer: installer,
      emergencyOverrideRepository: overrideRepository,
    );

    final results = await updater.checkForUpdates();
    final override = await overrideRepository.readOverride();

    expect(
      results.map((result) => result.pointer?.id).whereType<String>().toList(),
      ['capital', 'capital-emergency', 'common-emergency'],
    );
    expect(requestedPaths, [
      '/datapacks/catalog/current.json',
      '/datapacks/catalog/capital-v19.sqlite.gz',
      '/datapacks/catalog/capital-emergency-v7.sqlite.gz',
      '/datapacks/catalog/common-emergency-v1.sqlite.gz',
    ]);
    expect(override?.id, 'capital-emergency');
    expect(override?.version, '7');
  });

  test('updater는 default activePackId의 dependency를 다운로드한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-default-dependency-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    final activeSqliteBytes = await _validCatalogSqliteBytes(directory);
    final activeCompressedBytes = gzip.encode(activeSqliteBytes);
    final dependencySqliteBytes = await _validCatalogSqliteBytes(directory);
    final dependencyCompressedBytes = gzip.encode(dependencySqliteBytes);
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
                    id: 'capital',
                    version: '19',
                    url: 'catalog/capital-v19.sqlite.gz',
                    compressedBytes: activeCompressedBytes,
                    sqliteBytes: activeSqliteBytes,
                    dependencies: const [
                      {'id': 'common', 'version': '1'},
                    ],
                  ),
                  _packJson(
                    id: 'common',
                    version: '1',
                    url: 'catalog/common-v1.sqlite.gz',
                    compressedBytes: dependencyCompressedBytes,
                    sqliteBytes: dependencySqliteBytes,
                  ),
                ],
              }),
            )
            ..close();
        case '/datapacks/catalog/capital-v19.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(activeCompressedBytes)
            ..close();
        case '/datapacks/catalog/common-v1.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(dependencyCompressedBytes)
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

    expect(
      results.map((result) => result.pointer?.id).whereType<String>().toList(),
      ['capital', 'common'],
    );
    expect(requestedPaths, [
      '/datapacks/catalog/current.json',
      '/datapacks/catalog/capital-v19.sqlite.gz',
      '/datapacks/catalog/common-v1.sqlite.gz',
    ]);
  });

  test('updater는 background update prune에서 기존 current pack을 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-prune-current-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final currentPack = File('${catalogDirectory.path}/capital-v17.sqlite');
    await currentPack.writeAsString('open current');
    await File(
      '${catalogDirectory.path}/capital-v18.sqlite',
    ).writeAsString('old installed v18');
    await File(
      '${catalogDirectory.path}/capital-v19.sqlite',
    ).writeAsString('old installed v19');
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({'id': 'capital', 'version': '17', 'path': currentPack.path}),
    );
    final newSqliteBytes = await _validCatalogSqliteBytes(directory);
    final newCompressedBytes = gzip.encode(newSqliteBytes);
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
                'activePack': {'id': 'capital', 'version': '20'},
                'packs': [
                  _packJson(
                    id: 'capital',
                    version: '20',
                    url: 'catalog/capital-v20.sqlite.gz',
                    compressedBytes: newCompressedBytes,
                    sqliteBytes: newSqliteBytes,
                  ),
                ],
              }),
            )
            ..close();
        case '/datapacks/catalog/capital-v20.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(newCompressedBytes)
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
    expect(await currentPack.exists(), isTrue);
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

  test(
    'v2 replay floor는 failed release 뒤 더 높은 rescue sequence로 known-good 내용을 복구한다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-datapack-updater-monotonic-rescue-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final catalogDirectory = Directory('${directory.path}/catalog');
      final knownGoodSqliteBytes = await _catalogSqliteBytesWithMarker(
        directory,
        fileName: 'known-good.sqlite',
        marker: 'known-good',
      );
      final failedSqliteBytes = await _catalogSqliteBytesWithMarker(
        directory,
        fileName: 'failed.sqlite',
        marker: 'failed',
      );
      final knownGoodCompressedBytes = gzip.encode(knownGoodSqliteBytes);
      final failedCompressedBytes = gzip.encode(failedSqliteBytes);
      final corruptBytes = <int>[1, 2, 3, 4];
      var now = DateTime.utc(2026, 7, 15, 1);
      late Map<String, Object?> manifestJson;
      manifestJson = _signedV2PackManifest(
        sequence: 114,
        version: '18',
        compressedBytes: knownGoodCompressedBytes,
        sqliteBytes: knownGoodSqliteBytes,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) {
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
              ..add(knownGoodCompressedBytes)
              ..close();
          case '/datapacks/catalog/capital-v19.sqlite.gz':
            request.response
              ..statusCode = HttpStatus.ok
              ..add(failedCompressedBytes)
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
        now: () => now,
      );

      await updater.checkForUpdates();
      manifestJson = _signedV2PackManifest(
        sequence: 115,
        version: '19',
        compressedBytes: failedCompressedBytes,
        sqliteBytes: failedSqliteBytes,
      );
      now = now.add(const Duration(seconds: 2));
      await updater.checkForUpdates();
      expect((await installer.readCurrentPointer())?.version, '19');

      manifestJson = _signedV2PackManifest(
        sequence: 116,
        version: '18',
        compressedBytes: knownGoodCompressedBytes,
        sqliteBytes: knownGoodSqliteBytes,
        rollbackProvenance: {
          'kind': 'MONOTONIC_RESCUE',
          'currentReleaseSequence': 115,
          'failedReleaseSequence': 115,
          'failedManifestSha256': 'b' * 64,
          'knownGoodReleaseSequence': 114,
          'knownGoodManifestSha256': 'a' * 64,
          'releaseRequestId': 'rollback-request-1',
          'approvedByRole': 'release-manager',
          'approvedAt': '2026-07-15T00:30:00.000Z',
          'reasonCode': 'FAILED_RELEASE',
        },
      );
      now = now.add(const Duration(seconds: 2));
      await updater.checkForUpdates();
      final rescuedPointer = await installer.readCurrentPointer();
      expect(rescuedPointer?.version, '18');
      expect(
        sha256
            .convert(await File(rescuedPointer!.path).readAsBytes())
            .toString(),
        sha256.convert(knownGoodSqliteBytes).toString(),
      );
      expect(
        (await stateRepository.readAcceptedManifestState(
          'production',
        ))?.releaseSequence,
        116,
      );

      now = now.add(const Duration(seconds: 2));
      await updater.checkForUpdates();
      expect((await installer.readCurrentPointer())?.version, '18');
      expect(
        (await stateRepository.readAcceptedManifestState(
          'production',
        ))?.releaseSequence,
        116,
      );

      manifestJson = _signedV2PackManifest(
        sequence: 117,
        version: '20',
        compressedBytes: corruptBytes,
        sqliteBytes: const [5, 6, 7, 8],
      );
      now = now.add(const Duration(seconds: 2));
      final rejected = await updater.checkForUpdates();
      expect(rejected.single.status, DataPackInstallStatus.rejected);
      expect((await installer.readCurrentPointer())?.version, '18');
      expect(
        (await stateRepository.readAcceptedManifestState(
          'production',
        ))?.releaseSequence,
        116,
      );

      manifestJson = _signedV2PackManifest(
        sequence: 114,
        version: '18',
        compressedBytes: knownGoodCompressedBytes,
        sqliteBytes: knownGoodSqliteBytes,
      );
      now = now.add(const Duration(seconds: 2));
      await expectLater(
        updater.checkForUpdates(trigger: UpdateTrigger.userConsent),
        throwsA(isA<DataPackClientException>()),
      );
      expect((await installer.readCurrentPointer())?.version, '18');
      expect(
        (await stateRepository.readAcceptedManifestState(
          'production',
        ))?.releaseSequence,
        116,
      );
    },
  );

  test(
    'updater는 rollback manifest version이 숫자로 같으면 zero-padded pack을 활성화한다',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-datapack-updater-rollback-padded-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final catalogDirectory = Directory('${directory.path}/catalog');
      final v017SqliteBytes = await _validCatalogSqliteBytes(directory);
      final v017CompressedBytes = gzip.encode(v017SqliteBytes);
      final v19SqliteBytes = await _validCatalogSqliteBytes(directory);
      final v19CompressedBytes = gzip.encode(v19SqliteBytes);
      var now = DateTime.utc(2026, 6, 21, 6);
      var manifestJson = <String, Object?>{
        'ttlSeconds': 1,
        'activePack': {'id': 'capital', 'version': '19'},
        'packs': [
          _packJson(
            version: '017',
            url: 'catalog/capital-v017.sqlite.gz',
            compressedBytes: v017CompressedBytes,
            sqliteBytes: v017SqliteBytes,
          ),
          _packJson(
            version: '19',
            url: 'catalog/capital-v19.sqlite.gz',
            compressedBytes: v19CompressedBytes,
            sqliteBytes: v19SqliteBytes,
          ),
        ],
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) {
        switch (request.uri.path) {
          case '/datapacks/catalog/current.json':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(manifestJson))
              ..close();
          case '/datapacks/catalog/capital-v017.sqlite.gz':
            request.response
              ..statusCode = HttpStatus.ok
              ..add(v017CompressedBytes)
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

      await updater.checkForUpdates();

      manifestJson = {
        'ttlSeconds': 1,
        'activePack': {'id': 'capital', 'version': '17'},
        'packs': const [],
      };
      now = now.add(const Duration(seconds: 2));
      await updater.checkForUpdates();
      final rollbackPointer = await installer.readCurrentPointer();

      expect(rollbackPointer?.version, '017');
      expect(rollbackPointer?.path.endsWith('capital-v017.sqlite'), isTrue);
    },
  );

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

  // ─── rollout 버킷 판정 테스트 ────────────────────────────────────────────

  test('updater는 rollout percentage 0일 때 일반 팩 채택을 건너뛴다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-rollout-held-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      if (request.uri.path.endsWith('/current.json')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              _addV2Signature({
                'manifestVersion': 2,
                'channel': 'production',
                'releaseSequence': 1,
                'publishedAt': '2026-07-07T00:00:00.000Z',
                'expiresAt': '2099-01-01T00:00:00.000Z',
                'keyId': 'test-key',
                'ttlSeconds': 60,
                'packs': [
                  {
                    'id': 'capital',
                    'version': '18',
                    'url': 'catalog/capital-v18.sqlite.gz',
                    'sha256': '0' * 64,
                    'sqliteSha256': '0' * 64,
                    'schemaVersion': '1',
                    'requiredTables': ['catalog_metadata'],
                    'artifactKind': 'fixture',
                  },
                ],
                'rollout': {'percentage': 0, 'seed': 'held-out-seed'},
              }),
            ),
          )
          ..close();
        return;
      }
      // 팩 다운로드 요청이 오면 안 됨
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
    });
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: DataPackUpdateStateRepository(
          userDatabase: userDatabase,
          now: () => DateTime.utc(2026, 7, 7, 10),
        ),
      ),
      installer: DataPackInstaller(
        catalogDirectory: Directory('${directory.path}/catalog'),
        userDatabase: userDatabase,
      ),
    );

    final results = await updater.checkForUpdates();

    // heldOut → 일반 팩 채택 없음
    expect(results, isEmpty);
  });

  test('updater는 rollout heldOut이어도 emergencyOverride 팩을 채택한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-rollout-override-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final overrideSqliteBytes = await _validCatalogSqliteBytes(directory);
    final overrideCompressedBytes = gzip.encode(overrideSqliteBytes);
    final overrideCompressedSha256 = sha256
        .convert(overrideCompressedBytes)
        .toString();
    final overrideSqliteSha256 = sha256.convert(overrideSqliteBytes).toString();
    final overrideRepository = EmergencyOverrideRepository(
      userDatabase: userDatabase,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      switch (request.uri.path) {
        case '/datapacks/catalog/current.json':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode(
                _addV2Signature({
                  'manifestVersion': 2,
                  'channel': 'production',
                  'releaseSequence': 1,
                  'publishedAt': '2026-07-07T00:00:00.000Z',
                  'expiresAt': '2099-01-01T00:00:00.000Z',
                  'keyId': 'test-key',
                  'ttlSeconds': 60,
                  'emergencyOverride': {
                    'id': 'capital',
                    'version': '18',
                    'reason': '테스트 긴급 정정',
                  },
                  'packs': [
                    // 일반 팩(v19) — rollout heldOut으로 건너뜀
                    {
                      'id': 'capital',
                      'version': '19',
                      'url': 'catalog/capital-v19.sqlite.gz',
                      'sha256': '0' * 64,
                      'sqliteSha256': '0' * 64,
                      'schemaVersion': '1',
                      'requiredTables': ['catalog_metadata'],
                      'artifactKind': 'fixture',
                    },
                    // override 팩(v18) — rollout 무관, 항상 채택
                    {
                      'id': 'capital',
                      'version': '18',
                      'url': 'catalog/capital-v18.sqlite.gz',
                      'sha256': overrideCompressedSha256,
                      'sqliteSha256': overrideSqliteSha256,
                      'schemaVersion': '1',
                      'requiredTables': ['catalog_metadata'],
                      'artifactKind': 'fixture',
                    },
                  ],
                  'rollout': {'percentage': 0, 'seed': 'held-out-seed'},
                }),
              ),
            )
            ..close();
        case '/datapacks/catalog/capital-v18.sqlite.gz':
          request.response
            ..statusCode = HttpStatus.ok
            ..add(overrideCompressedBytes)
            ..close();
        default:
          // v19 다운로드 요청이 오면 안 됨
          request.response
            ..statusCode = HttpStatus.internalServerError
            ..close();
      }
    });
    final catalogDirectory = Directory('${directory.path}/catalog');
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
          now: () => DateTime.utc(2026, 7, 7, 10),
        ),
      ),
      installer: installer,
      emergencyOverrideRepository: overrideRepository,
    );

    final results = await updater.checkForUpdates();
    final override = await overrideRepository.readOverride();

    // override 팩(v18)만 채택됨
    expect(results.single.status, DataPackInstallStatus.installed);
    expect(results.single.pointer?.id, 'capital');
    expect(results.single.pointer?.version, '18');
    // emergencyOverride 저장됨
    expect(override?.id, 'capital');
    expect(override?.version, '18');
  });

  test('updater는 rollout 부재(v1 manifest) 시 항상 팩을 채택한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-no-rollout-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    final compressedBytes = gzip.encode(sqliteBytes);
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
                    compressedBytes: compressedBytes,
                    sqliteBytes: sqliteBytes,
                  ),
                ],
                // rollout 없음 → 항상 채택
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
          now: () => DateTime.utc(2026, 7, 7, 11),
        ),
      ),
      installer: DataPackInstaller(
        catalogDirectory: catalogDirectory,
        userDatabase: userDatabase,
      ),
    );

    final results = await updater.checkForUpdates();

    // rollout 부재 → 채택(하위 호환)
    expect(results.single.status, DataPackInstallStatus.installed);
  });

  // ─── heldOut + activePack 미설치 크래시 방어 ─────────────────────────────

  test('updater는 rollout heldOut + activePack 미설치 시 예외 없이 그레이스풀 반환한다', () async {
    // 시나리오A: heldOut + manifest.activePack 설정(미설치) + override 없음
    // → checkForUpdates가 예외 없이 반환, 새 팩 미채택, 기존 포인터 유지
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-heldout-activePack-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    // 기존 current pointer(v17) 설정 — 이 포인터가 유지돼야 함
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
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      if (request.uri.path.endsWith('/current.json')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              _addV2Signature({
                'manifestVersion': 2,
                'channel': 'production',
                'releaseSequence': 1,
                'publishedAt': '2026-07-07T00:00:00.000Z',
                'expiresAt': '2099-01-01T00:00:00.000Z',
                'keyId': 'test-key',
                'ttlSeconds': 60,
                // activePack v19 설정 — 단말에 미설치
                'activePack': {'id': 'capital', 'version': '19'},
                'packs': [
                  {
                    'id': 'capital',
                    'version': '19',
                    'url': 'catalog/capital-v19.sqlite.gz',
                    'sha256': '0' * 64,
                    'sqliteSha256': '0' * 64,
                    'schemaVersion': '1',
                    'requiredTables': ['catalog_metadata'],
                    'artifactKind': 'fixture',
                  },
                ],
                // percentage 0 → 이 단말은 항상 heldOut
                'rollout': {'percentage': 0, 'seed': 'held-out-seed'},
              }),
            ),
          )
          ..close();
        return;
      }
      // v19 다운로드 요청이 오면 안 됨
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..close();
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
          now: () => DateTime.utc(2026, 7, 7, 10),
        ),
      ),
      installer: installer,
    );

    // heldOut + activePack 미설치 → 예외 없이 그레이스풀 반환
    final results = await updater.checkForUpdates();
    final pointer = await installer.readCurrentPointer();

    expect(results, isEmpty);
    // v19 미채택 — 기존 v17 포인터 유지
    expect(pointer?.version, '17');
  });

  test('updater는 기준선 없는 activePack을 예외 없이 넘기고 기존 pointer를 유지한다', () async {
    // 롤백 매니페스트가 이미 설치된 이전 버전을 activePack으로 지정하고 packs에는 담지
    // 않으면 기대 해시 원천이 없다(#2532). 예외로 올리면 backoff도 manifest 캐시도 남지
    // 않아 매 세션 같은 실패가 반복된다.
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-activepack-baseline-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final sqliteBytes = await _validCatalogSqliteBytes(directory);
    // 이전 빌드가 설치해 기준선 파일이 없는 팩.
    await File(
      '${catalogDirectory.path}/capital-v18.sqlite',
    ).writeAsBytes(sqliteBytes, flush: true);
    // 해시를 담지 않던 시절의 pointer — 사다리 어느 단에도 기대값이 없다.
    final previousPointer = File('${catalogDirectory.path}/current.json');
    await previousPointer.writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '18',
        'path': '${catalogDirectory.path}/capital-v18.sqlite',
      }),
      flush: true,
    );
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
                'activePack': {'id': 'capital', 'version': '18'},
                'packs': const <Object?>[],
              }),
            )
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
          now: () => DateTime.utc(2026, 7, 26, 10),
        ),
        now: () => DateTime.utc(2026, 7, 26, 10),
      ),
      installer: installer,
    );

    await expectLater(updater.checkForUpdates(), completes);
    final pointer = await installer.readCurrentPointer();

    expect(pointer?.version, '18');
    expect(pointer?.sha256, isNull);
  });

  test('updater는 무결성을 확인하지 못한 override 기록을 지우지 않는다', () async {
    // 이 PR 이전 빌드가 설치해 기준선이 없는 팩이 override 대상인 경우(#2532).
    // "확인 못 함"으로 장애 대응 고정을 해제하면 단말이 문제가 있던 팩으로 되돌아간다.
    final fixture = await _overrideIntegrityFixture(
      'override-baseline-missing-',
    );

    await fixture.updater.checkForUpdates();
    final override = await fixture.overrideRepository.readOverride();

    expect(override?.id, 'capital');
    expect(override?.version, '18');
    expect(override?.reason, '이전 세션 긴급 정정');
  });

  test('updater는 override 팩 해시가 어긋나면 기록을 해제한다', () async {
    final fixture = await _overrideIntegrityFixture('override-mismatch-');
    await File(
      '${fixture.overridePack.path}.sha256',
    ).writeAsString('${'0' * 64}\n', flush: true);

    await fixture.updater.checkForUpdates();
    final override = await fixture.overrideRepository.readOverride();

    expect(override, isNull);
  });

  test(
    'updater는 rollout heldOut + activePack 미설치 시에도 emergencyOverride를 저장한다',
    () async {
      // 시나리오B: heldOut + activePack 미설치 + emergencyOverride 설정
      // → override 팩 채택 + saveOverride 수행(불변식), 예외 없음
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-datapack-updater-heldout-override-activePack-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final overrideRepository = EmergencyOverrideRepository(
        userDatabase: userDatabase,
      );
      final overrideSqliteBytes = await _validCatalogSqliteBytes(directory);
      final overrideCompressedBytes = gzip.encode(overrideSqliteBytes);
      final overrideCompressedSha256 = sha256
          .convert(overrideCompressedBytes)
          .toString();
      final overrideSqliteSha256 = sha256
          .convert(overrideSqliteBytes)
          .toString();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) {
        switch (request.uri.path) {
          case '/datapacks/catalog/current.json':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(
                  _addV2Signature({
                    'manifestVersion': 2,
                    'channel': 'production',
                    'releaseSequence': 1,
                    'publishedAt': '2026-07-07T00:00:00.000Z',
                    'expiresAt': '2099-01-01T00:00:00.000Z',
                    'keyId': 'test-key',
                    'ttlSeconds': 60,
                    // activePack v19 설정 — 단말에 미설치
                    'activePack': {'id': 'capital', 'version': '19'},
                    'emergencyOverride': {
                      'id': 'capital',
                      'version': '18',
                      'reason': '테스트 긴급 정정',
                    },
                    'packs': [
                      // activePack(v19) — heldOut으로 건너뜀
                      {
                        'id': 'capital',
                        'version': '19',
                        'url': 'catalog/capital-v19.sqlite.gz',
                        'sha256': '0' * 64,
                        'sqliteSha256': '0' * 64,
                        'schemaVersion': '1',
                        'requiredTables': ['catalog_metadata'],
                        'artifactKind': 'fixture',
                      },
                      // override 팩(v18) — rollout 무관, 항상 채택
                      {
                        'id': 'capital',
                        'version': '18',
                        'url': 'catalog/capital-v18.sqlite.gz',
                        'sha256': overrideCompressedSha256,
                        'sqliteSha256': overrideSqliteSha256,
                        'schemaVersion': '1',
                        'requiredTables': ['catalog_metadata'],
                        'artifactKind': 'fixture',
                      },
                    ],
                    // percentage 0 → 이 단말은 항상 heldOut
                    'rollout': {'percentage': 0, 'seed': 'held-out-seed'},
                  }),
                ),
              )
              ..close();
          case '/datapacks/catalog/capital-v18.sqlite.gz':
            request.response
              ..statusCode = HttpStatus.ok
              ..add(overrideCompressedBytes)
              ..close();
          default:
            // v19 다운로드 요청이 오면 안 됨
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..close();
        }
      });
      final catalogDirectory = Directory('${directory.path}/catalog');
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
            now: () => DateTime.utc(2026, 7, 7, 10),
          ),
        ),
        installer: installer,
        emergencyOverrideRepository: overrideRepository,
      );

      final results = await updater.checkForUpdates();
      final override = await overrideRepository.readOverride();

      // override 팩(v18)만 채택됨
      expect(results.single.status, DataPackInstallStatus.installed);
      expect(results.single.pointer?.id, 'capital');
      expect(results.single.pointer?.version, '18');
      // emergencyOverride 저장됨(불변식)
      expect(override?.id, 'capital');
      expect(override?.version, '18');
    },
  );
}

class _OverrideIntegrityFixture {
  const _OverrideIntegrityFixture({
    required this.updater,
    required this.overrideRepository,
    required this.overridePack,
  });

  final DataPackUpdater updater;
  final EmergencyOverrideRepository overrideRepository;
  final File overridePack;
}

/// 매니페스트가 emergencyOverride로 지정한 v18이 단말에 이미 설치돼 있고(기준선 없음),
/// 매니페스트 packs에는 v19만 있는 구성. override 대상은 재다운로드되지 않으므로
/// `readInstalledPointer` 판정이 그대로 override 유지/해제로 이어진다.
Future<_OverrideIntegrityFixture> _overrideIntegrityFixture(
  String prefix,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'easysubway-datapack-updater-$prefix',
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
      version: '18',
      reason: '이전 세션 긴급 정정',
    ),
  );
  final catalogDirectory = Directory('${directory.path}/catalog');
  await catalogDirectory.create(recursive: true);
  final sqliteBytes = await _validCatalogSqliteBytes(directory);
  final overridePack = File('${catalogDirectory.path}/capital-v18.sqlite');
  await overridePack.writeAsBytes(sqliteBytes, flush: true);
  final activeCompressedBytes = gzip.encode(sqliteBytes);
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
              'activePack': {'id': 'capital', 'version': '19'},
              'emergencyOverride': {
                'id': 'capital',
                'version': '18',
                'reason': '테스트 긴급 정정',
              },
              'packs': [
                _packJson(
                  version: '19',
                  url: 'catalog/capital-v19.sqlite.gz',
                  compressedBytes: activeCompressedBytes,
                  sqliteBytes: sqliteBytes,
                ),
              ],
            }),
          )
          ..close();
      case '/datapacks/catalog/capital-v19.sqlite.gz':
        request.response
          ..statusCode = HttpStatus.ok
          ..add(activeCompressedBytes)
          ..close();
      default:
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
    }
  });
  return _OverrideIntegrityFixture(
    updater: DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
        ),
        stateRepository: DataPackUpdateStateRepository(
          userDatabase: userDatabase,
          now: () => DateTime.utc(2026, 7, 26, 10),
        ),
      ),
      installer: DataPackInstaller(
        catalogDirectory: catalogDirectory,
        userDatabase: userDatabase,
      ),
      emergencyOverrideRepository: overrideRepository,
    ),
    overrideRepository: overrideRepository,
    overridePack: overridePack,
  );
}

Map<String, Object?> _packJson({
  String id = 'capital',
  required String version,
  required String url,
  required List<int> compressedBytes,
  required List<int> sqliteBytes,
  List<Map<String, String>> dependencies = const [],
}) {
  final compressedSha256 = sha256.convert(compressedBytes).toString();
  final sqliteSha256 = sha256.convert(sqliteBytes).toString();
  return {
    'id': id,
    'version': version,
    'url': url,
    'sha256': compressedSha256,
    'sqliteSha256': sqliteSha256,
    'sizeBytes': compressedBytes.length,
    ..._fixtureManifestMetadata(
      id: id,
      version: version,
      compressedSha256: compressedSha256,
      sqliteSha256: sqliteSha256,
      sizeBytes: compressedBytes.length,
    ),
    'schemaVersion': '1',
    'requiredTables': ['catalog_metadata'],
    if (dependencies.isNotEmpty) 'dependencies': dependencies,
  };
}

Map<String, Object?> _fixtureManifestMetadata({
  String id = 'capital',
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
        id,
        version,
        compressedSha256,
        sqliteSha256,
        sizeBytes,
      ),
    },
    'signature': {
      'algorithm': 'sha256-pack-manifest-v1',
      'value': _signatureValue(
        id,
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

// ─── v2 매니페스트 서명 헬퍼 ────────────────────────────────────────────────

/// 매니페스트 객체(signature 제외)를 받아 sha256-manifest-v2 서명을 추가한다.
Map<String, Object?> _addV2Signature(
  Map<String, Object?> bodyWithoutSignature,
) {
  final canonical = canonicalDataPackJson(bodyWithoutSignature);
  final signatureValue = sha256.convert(utf8.encode(canonical)).toString();
  return {
    ...bodyWithoutSignature,
    'signature': {'algorithm': 'sha256-manifest-v2', 'value': signatureValue},
  };
}

Map<String, Object?> _signedV2PackManifest({
  required int sequence,
  required String version,
  required List<int> compressedBytes,
  required List<int> sqliteBytes,
  Map<String, Object?>? rollbackProvenance,
}) {
  final pack = _packJson(
    version: version,
    url: 'catalog/capital-v$version.sqlite.gz',
    compressedBytes: compressedBytes,
    sqliteBytes: sqliteBytes,
  );
  final signature = pack['signature']! as Map<String, Object?>;
  signature['algorithm'] = 'sha256-pack-manifest-v2';
  return _addV2Signature({
    'manifestVersion': 2,
    'channel': 'production',
    'releaseSequence': sequence,
    'publishedAt': '2026-07-15T00:00:00.000Z',
    'expiresAt': '2099-01-01T00:00:00.000Z',
    'keyId': 'fixture-key',
    'ttlSeconds': 1,
    'activePack': {'id': 'capital', 'version': version},
    'rollbackProvenance': ?rollbackProvenance,
    'packs': [pack],
  });
}

Future<List<int>> _validCatalogSqliteBytes(Directory directory) async {
  final file = File('${directory.path}/fixture.sqlite');
  final database = CatalogDatabase.file(file);
  await database.seedBaselineIfEmpty();
  await database.close();
  return file.readAsBytes();
}

Future<List<int>> _catalogSqliteBytesWithMarker(
  Directory directory, {
  required String fileName,
  required String marker,
}) async {
  final file = File('${directory.path}/$fileName');
  final database = CatalogDatabase.file(file);
  await database.seedBaselineIfEmpty();
  await database.customStatement(
    'INSERT OR REPLACE INTO catalog_metadata(key, value) VALUES (?, ?)',
    ['rescueTestMarker', marker],
  );
  await database.close();
  return file.readAsBytes();
}
