import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_client.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:flutter_test/flutter_test.dart';

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
                'signature': {
                  'algorithm': 'sha256-pack-manifest-v1',
                  'value': 'c' * 64,
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
}
