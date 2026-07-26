import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
// 정준 직렬화는 검증 대상 구현을 그대로 쓴다. 테스트가 규칙을 복제하면 3언어
// 분열(이슈 #2528)을 구조적으로 검출할 수 없다.
import 'package:easysubway_mobile/core/datapack/canonical_json.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_client.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
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
const _productionSigningPublicKey = DataPackSigningPublicKey(
  modulusBase64Url: 'AQ',
  exponentBase64Url: 'AQAB',
);

void main() {
  test('manifest client는 TTL 안에서는 네트워크를 호출하지 않는다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 19, 10, 30),
    );
    await stateRepository.saveManifestCache(
      etag: 'etag-v18',
      checkedAt: DateTime.utc(2026, 6, 19, 10),
      ttl: const Duration(hours: 1),
    );
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      requestCount++;
      request.response
        ..statusCode = HttpStatus.ok
        ..write('{}')
        ..close();
    });

    final client = DataPackClient(
      manifestUri: Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      ),
      stateRepository: stateRepository,
    );

    final result = await client.fetchManifestIfNeeded();

    expect(result.status, DataPackManifestFetchStatus.freshCache);
    expect(result.manifest, isNull);
    expect(requestCount, 0);
  });

  test('manifest client는 TTL 만료 후 ETag 요청 결과를 성공 후 저장한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 19, 12),
    );
    await stateRepository.saveManifestCache(
      etag: 'etag-v17',
      checkedAt: DateTime.utc(2026, 6, 19, 10),
      ttl: const Duration(minutes: 30),
    );
    String? ifNoneMatch;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      ifNoneMatch = request.headers.value(HttpHeaders.ifNoneMatchHeader);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set(HttpHeaders.etagHeader, 'etag-v18')
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'ttlSeconds': 60,
            'packs': [
              {
                'id': 'capital',
                'version': '18',
                'url': 'capital-v18.sqlite.gz',
                'sha256': 'a' * 64,
                'sqliteSha256': 'b' * 64,
                'sizeBytes': 1024,
                'artifactKind': 'fixture',
                'representativeRouteRegressions':
                    _representativeRouteRegressions,
                'representativeRouteRegressionSignature': {
                  'algorithm': 'sha256-route-regression-v1',
                  'value': _routeRegressionSignatureValue(
                    'capital',
                    '18',
                    'a' * 64,
                    'b' * 64,
                    1024,
                  ),
                },
                'signature': {
                  'algorithm': 'sha256-pack-manifest-v1',
                  'value': _signatureValue(
                    'capital',
                    '18',
                    'a' * 64,
                    'b' * 64,
                    1024,
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
                'schemaVersion': '1',
                'requiredTables': ['catalog_metadata'],
              },
            ],
          }),
        )
        ..close();
    });

    final client = DataPackClient(
      manifestUri: Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      ),
      stateRepository: stateRepository,
    );

    final result = await client.fetchManifestIfNeeded();
    await client.saveManifestCache(result);
    final cache = await stateRepository.readManifestCache();

    expect(ifNoneMatch, 'etag-v17');
    expect(result.status, DataPackManifestFetchStatus.updated);
    expect(result.manifest?.packs.single.version, '18');
    expect(cache?.etag, 'etag-v18');
    expect(cache?.ttl, const Duration(minutes: 1));
  });

  test('manifest client는 만료된 v2 manifest를 거부하고 기존 cache를 유지한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 27, 12),
    );
    await stateRepository.saveManifestCache(
      etag: 'etag-v18',
      checkedAt: DateTime.utc(2026, 6, 27, 10),
      ttl: const Duration(minutes: 30),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set(HttpHeaders.etagHeader, 'etag-v19')
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(
            _v2ManifestJson(
              sequence: 43,
              version: '19',
              expiresAt: '2026-06-26T00:00:00.000Z',
            ),
          ),
        )
        ..close();
    });

    final client = DataPackClient(
      manifestUri: Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      ),
      stateRepository: stateRepository,
      now: () => DateTime.utc(2026, 6, 27, 12),
    );

    await expectLater(
      client.fetchManifestIfNeeded(),
      throwsA(isA<DataPackClientException>()),
    );
    final cache = await stateRepository.readManifestCache();
    expect(cache?.etag, 'etag-v18');
  });

  test(
    'manifest client는 production key에서 fixture manifest를 client 오류로 거부한다',
    () async {
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final stateRepository = DataPackUpdateStateRepository(
        userDatabase: userDatabase,
        now: () => DateTime.utc(2026, 6, 27, 12),
      );
      await stateRepository.saveManifestCache(
        etag: 'etag-v18',
        checkedAt: DateTime.utc(2026, 6, 27, 10),
        ttl: const Duration(minutes: 30),
      );
      var requestCount = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) {
        requestCount++;
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set(HttpHeaders.etagHeader, 'etag-v19')
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_v2ManifestJson(sequence: 43, version: '19')))
          ..close();
      });

      final client = DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/manifest.json',
        ),
        stateRepository: stateRepository,
        productionSigningPublicKey: _productionSigningPublicKey,
        now: () => DateTime.utc(2026, 6, 27, 12),
      );

      await expectLater(
        client.fetchManifestIfNeeded(),
        throwsA(
          isA<DataPackClientException>().having(
            (error) => error.message,
            'message',
            '이동 정보 형식이 올바르지 않습니다.',
          ),
        ),
      );
      final cache = await stateRepository.readManifestCache();
      expect(requestCount, 1);
      expect(cache?.etag, 'etag-v18');
    },
  );

  test('manifest client는 v2 manifest cache TTL을 expiresAt으로 제한한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 25, 12),
    );
    final checkedAt = DateTime.utc(2026, 6, 25, 12);
    final manifest = DataPackManifest.fromJson(
      _v2ManifestJson(
        sequence: 44,
        version: '20',
        expiresAt: '2026-06-25T12:05:00.000Z',
      ),
    );
    final client = DataPackClient(
      manifestUri: Uri.parse(
        'https://cdn.easysubway.example/catalog/current.json',
      ),
      stateRepository: stateRepository,
      now: () => checkedAt,
    );

    await client.saveManifestCache(
      DataPackManifestFetchResult(
        status: DataPackManifestFetchStatus.updated,
        manifest: manifest,
        etag: 'etag-v20',
        checkedAt: checkedAt,
      ),
    );
    final cache = await stateRepository.readManifestCache();
    expect(cache?.ttl, const Duration(minutes: 5));
    expect(cache?.expiresAt, DateTime.utc(2026, 6, 25, 12, 5));
  });

  test('evaluationAt이 expiry와 같으면 bundled pack은 stale이다', () {
    expect(
      evaluateDataPackFreshness(
        evaluationAt: DateTime.utc(2026, 8, 11),
        freshnessExpiresAt: DateTime.utc(2026, 8, 11),
      ),
      DataPackFreshnessState.stale,
    );
    expect(
      evaluateDataPackFreshness(
        evaluationAt: DateTime.utc(2026, 8, 10, 23, 59, 59, 999),
        freshnessExpiresAt: DateTime.utc(2026, 8, 11),
      ),
      DataPackFreshnessState.fresh,
    );
  });

  test('manifest client는 v2 replay floor를 cache보다 먼저 저장한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = _RecordingUpdateStateRepository(
      userDatabase: userDatabase,
    );
    final checkedAt = DateTime.utc(2026, 6, 25, 12);
    final manifest = _v2Manifest(sequence: 44, version: '20');
    final client = DataPackClient(
      manifestUri: Uri.parse(
        'https://cdn.easysubway.example/catalog/current.json',
      ),
      stateRepository: stateRepository,
      now: () => checkedAt,
    );

    await client.saveManifestCache(
      DataPackManifestFetchResult(
        status: DataPackManifestFetchStatus.updated,
        manifest: manifest,
        etag: 'etag-v20',
        checkedAt: checkedAt,
      ),
    );

    expect(stateRepository.calls, ['accepted', 'cache']);
  });

  test('manifest client는 expected channel과 다른 v2 manifest를 거부한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = _RecordingUpdateStateRepository(
      userDatabase: userDatabase,
    );
    final checkedAt = DateTime.utc(2026, 6, 25, 12);
    final manifest = DataPackManifest.fromJson(
      _v2ManifestJson(sequence: 1, version: '1', channel: 'staging'),
    );
    final client = DataPackClient(
      manifestUri: Uri.parse(
        'https://cdn.easysubway.example/catalog/current.json',
      ),
      stateRepository: stateRepository,
      expectedManifestChannel: 'production',
      now: () => checkedAt,
    );

    await expectLater(
      client.saveManifestCache(
        DataPackManifestFetchResult(
          status: DataPackManifestFetchStatus.updated,
          manifest: manifest,
          etag: 'etag-staging',
          checkedAt: checkedAt,
        ),
      ),
      throwsA(isA<DataPackClientException>()),
    );
    expect(stateRepository.calls, isEmpty);
  });

  test('manifest client는 만료된 v2 cache를 304 응답으로 연장하지 않는다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 25, 12, 6),
    );
    await stateRepository.saveManifestCache(
      etag: 'etag-v20',
      checkedAt: DateTime.utc(2026, 6, 25, 12),
      ttl: const Duration(minutes: 5),
      expiresAt: DateTime.utc(2026, 6, 25, 12, 5),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.notModified
        ..close();
    });
    final client = DataPackClient(
      manifestUri: Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      ),
      stateRepository: stateRepository,
      now: () => DateTime.utc(2026, 6, 25, 12, 6),
    );

    await expectLater(
      client.fetchManifestIfNeeded(),
      throwsA(isA<DataPackClientException>()),
    );
    final cache = await stateRepository.readManifestCache();
    expect(cache?.checkedAt, DateTime.utc(2026, 6, 25, 12));
  });

  test('rollout salt는 최초 생성 후 안정적으로 재사용된다', () async {
    final db = user_db.UserDatabase.memory();
    addTearDown(db.close);
    final repo = DataPackUpdateStateRepository(userDatabase: db);
    final s1 = await repo.readOrCreateRolloutSalt();
    final s2 = await repo.readOrCreateRolloutSalt();
    expect(s1, matches(RegExp(r'^[a-f0-9]{32}$')));
    expect(s2, s1); // 안정
  });

  test('update policy state는 확인·백오프·동의 보류·실패 사유를 저장한다', () async {
    final db = user_db.UserDatabase.memory();
    addTearDown(db.close);
    final repo = DataPackUpdateStateRepository(userDatabase: db);

    await repo.savePolicyState(
      DataPackUpdatePolicyState(
        lastCheckAt: DateTime.utc(2026, 7, 9, 1),
        backoffUntil: DateTime.utc(2026, 7, 9, 1, 8),
        backoffAttempts: 2,
        pendingConsentBytes: 12 * 1024 * 1024,
        lastFailureReason: 'download',
      ),
    );

    final state = await repo.readPolicyState();

    expect(state.lastCheckAt, DateTime.utc(2026, 7, 9, 1));
    expect(state.backoffUntil, DateTime.utc(2026, 7, 9, 1, 8));
    expect(state.backoffAttempts, 2);
    expect(state.pendingConsentBytes, 12 * 1024 * 1024);
    expect(state.lastFailureReason, 'download');
  });

  test('update state는 v2 manifest downgrade와 equivocation을 거부한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 25, 12),
    );
    final accepted = _v2Manifest(sequence: 42, version: '18');
    await stateRepository.saveAcceptedManifestState(accepted);

    final state = await stateRepository.readAcceptedManifestState('production');
    expect(state?.releaseSequence, 42);
    expect(state?.manifestHash, accepted.manifestHash);

    await expectLater(
      stateRepository.ensureManifestCanBeAccepted(
        _v2Manifest(sequence: 41, version: '17'),
      ),
      throwsA(isA<DataPackManifestReplayException>()),
    );
    await expectLater(
      stateRepository.ensureManifestCanBeAccepted(
        _v2Manifest(sequence: 42, version: '19'),
      ),
      throwsA(isA<DataPackManifestReplayException>()),
    );
    await expectLater(
      stateRepository.ensureManifestCanBeAccepted(_v1Manifest(version: '17')),
      throwsA(isA<DataPackManifestReplayException>()),
    );
    await stateRepository.ensureManifestCanBeAccepted(accepted);
  });

  test('update state는 신규 설치 단말에도 절대 순번 하한을 적용한다', () async {
    // 이슈 #2531: 수락 이력이 비어 있는 단말(재설치 포함)이 리플레이 방어의 사각이었다.
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      minimumReleaseSequence: 42,
      now: () => DateTime.utc(2026, 6, 25, 12),
    );

    expect(await stateRepository.hasAcceptedManifestState(), isFalse);

    // (a) 하한 이상인 최신 v2는 그대로 수락한다.
    await stateRepository.ensureManifestCanBeAccepted(
      _v2Manifest(sequence: 42, version: '18'),
    );
    await stateRepository.ensureManifestCanBeAccepted(
      _v2Manifest(sequence: 43, version: '19'),
    );

    // (b) 하한 아래는 수락 이력이 없어도 거부한다.
    await expectLater(
      stateRepository.ensureManifestCanBeAccepted(
        _v2Manifest(sequence: 41, version: '17'),
      ),
      throwsA(isA<DataPackManifestReplayException>()),
    );

    // (c) v1 봉투는 순번을 증명할 수 없으므로 이력 유무와 무관하게 거부한다.
    await expectLater(
      stateRepository.ensureManifestCanBeAccepted(_v1Manifest(version: '17')),
      throwsA(isA<DataPackManifestReplayException>()),
    );
    expect(await stateRepository.hasAcceptedManifestState(), isFalse);
  });

  test('update state는 하한이 없는 개발 빌드의 신규 설치 동작을 유지한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 25, 12),
    );

    expect(stateRepository.minimumReleaseSequence, isNull);
    await stateRepository.ensureManifestCanBeAccepted(
      _v2Manifest(sequence: 1, version: '17'),
    );
    await stateRepository.ensureManifestCanBeAccepted(
      _v1Manifest(version: '17'),
    );
  });
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

DataPackManifest _v2Manifest({required int sequence, required String version}) {
  return DataPackManifest.fromJson(
    _v2ManifestJson(sequence: sequence, version: version),
  );
}

DataPackManifest _v1Manifest({required String version}) {
  final json = _v2ManifestJson(sequence: 1, version: version);
  json.remove('manifestVersion');
  json.remove('channel');
  json.remove('releaseSequence');
  json.remove('publishedAt');
  json.remove('expiresAt');
  json.remove('keyId');
  json.remove('signature');
  final packs = json['packs']! as List<Object?>;
  final pack = packs.single as Map<String, Object?>;
  pack['signature'] = {
    'algorithm': 'sha256-pack-manifest-v1',
    'value': _signatureValue('capital', version, 'a' * 64, 'b' * 64, 1024),
  };
  return DataPackManifest.fromJson(json);
}

Map<String, Object?> _v2ManifestJson({
  required int sequence,
  required String version,
  String channel = 'production',
  String expiresAt = '2026-06-26T00:00:00.000Z',
}) {
  final manifest = <String, Object?>{
    'manifestVersion': 2,
    'channel': channel,
    'releaseSequence': sequence,
    'publishedAt': '2026-06-25T00:00:00.000Z',
    'expiresAt': expiresAt,
    'ttlSeconds': 3600,
    'keyId': 'fixture-key',
    'activePack': {'id': 'capital', 'version': version},
    'packs': [
      {
        'id': 'capital',
        'version': version,
        'url': 'capital-v$version.sqlite.gz',
        'sha256': 'a' * 64,
        'sqliteSha256': 'b' * 64,
        'sizeBytes': 1024,
        'artifactKind': 'fixture',
        'representativeRouteRegressions': _representativeRouteRegressions,
        'representativeRouteRegressionSignature': {
          'algorithm': 'sha256-route-regression-v1',
          'value': _routeRegressionSignatureValue(
            'capital',
            version,
            'a' * 64,
            'b' * 64,
            1024,
          ),
        },
        'signature': {
          'algorithm': 'sha256-pack-manifest-v2',
          'value': _signatureValue(
            'capital',
            version,
            'a' * 64,
            'b' * 64,
            1024,
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
        'schemaVersion': '1',
        'requiredTables': ['catalog_metadata'],
      },
    ],
  };
  manifest['signature'] = {
    'algorithm': 'sha256-manifest-v2',
    'value': sha256
        .convert(utf8.encode(canonicalDataPackJson(manifest)))
        .toString(),
  };
  return manifest;
}

class _RecordingUpdateStateRepository extends DataPackUpdateStateRepository {
  _RecordingUpdateStateRepository({required super.userDatabase});

  final List<String> calls = [];

  @override
  Future<void> saveAcceptedManifestState(DataPackManifest manifest) async {
    calls.add('accepted');
  }

  @override
  Future<void> saveManifestCache({
    required String? etag,
    required DateTime checkedAt,
    required Duration ttl,
    DateTime? expiresAt,
  }) async {
    calls.add('cache');
  }
}
