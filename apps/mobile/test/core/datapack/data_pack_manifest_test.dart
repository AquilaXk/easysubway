import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('데이터팩 manifest는 TTL과 pack 검증 조건을 파싱한다', () {
    final manifest = DataPackManifest.fromJson({
      'ttlSeconds': 3600,
      'activePack': {'id': 'capital', 'version': '18'},
      'packs': [
        {
          'id': 'capital',
          'version': '18',
          'url': 'catalog/capital-v18.sqlite.gz',
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
              'fields': ['stations', 'network_edges'],
            },
          ],
          'regionalQualityMetrics': {
            'stationCount': 2,
            'facilityCoverageRatio': 0.5,
            'edgeCount': 2,
            'unknownAccessibilityRatio': 0.0,
          },
          'schemaVersion': '1',
          'requiredTables': ['catalog_metadata', 'stations'],
          'minimumTableRows': {'stations': 2},
        },
      ],
      'emergencyOverride': {
        'id': 'capital',
        'version': '17',
        'reason': '시설 상태 긴급 정정',
      },
    });

    expect(manifest.ttl, const Duration(hours: 1));
    expect(manifest.activePack?.id, 'capital');
    expect(manifest.activePack?.version, '18');
    expect(manifest.packs.single.id, 'capital');
    expect(manifest.packs.single.version, '18');
    expect(
      manifest.packs.single.url,
      Uri.parse('catalog/capital-v18.sqlite.gz'),
    );
    expect(manifest.packs.single.requiredTables, [
      'catalog_metadata',
      'stations',
    ]);
    expect(manifest.packs.single.sizeBytes, 1024);
    expect(manifest.packs.single.artifactKind, DataPackArtifactKind.fixture);
    expect(
      manifest.packs.single.signature.algorithm,
      'sha256-pack-manifest-v1',
    );
    expect(
      manifest.packs.single.sourceInventory.single.licenseStatus,
      'fixture-only',
    );
    expect(manifest.packs.single.regionalQualityMetrics.stationCount, 2);
    expect(manifest.packs.single.minimumTableRows, {'stations': 2});
    expect(manifest.emergencyOverride?.version, '17');
  });

  test('production 데이터팩 manifest는 HTTPS URL과 source inventory가 필요하다', () {
    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [
          {
            'id': 'capital',
            'version': '18',
            'url': 'catalog/capital-v18.sqlite.gz',
            'sha256': 'a' * 64,
            'sqliteSha256': 'b' * 64,
            'sizeBytes': 1024,
            'artifactKind': 'production',
            'signature': {
              'algorithm': 'sha256-pack-manifest-v1',
              'value': 'c' * 64,
            },
            'sourceInventory': [
              {
                'id': 'capital-official-stations',
                'owner': '수도권 운영기관',
                'url': 'https://example.invalid/source',
                'license': '공공데이터 이용허락',
                'licenseStatus': 'redistributable',
                'redistributionAllowed': true,
                'updateFrequency': 'daily',
                'updatedAt': '2026-06-19T00:00:00.000Z',
                'fields': ['stations'],
              },
            ],
            'regionalQualityMetrics': {
              'stationCount': 300,
              'facilityCoverageRatio': 0.8,
              'edgeCount': 600,
              'unknownAccessibilityRatio': 0.1,
            },
            'schemaVersion': '1',
            'requiredTables': ['catalog_metadata'],
          },
        ],
      }),
      throwsFormatException,
    );

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [
          {
            'id': 'capital',
            'version': '18',
            'url':
                'https://cdn.easysubway.example/catalog/capital-v18.sqlite.gz',
            'sha256': 'a' * 64,
            'sqliteSha256': 'b' * 64,
            'sizeBytes': 1024,
            'artifactKind': 'production',
            'signature': {
              'algorithm': 'sha256-pack-manifest-v1',
              'value': 'c' * 64,
            },
            'sourceInventory': <Object?>[],
            'regionalQualityMetrics': {
              'stationCount': 300,
              'facilityCoverageRatio': 0.8,
              'edgeCount': 600,
              'unknownAccessibilityRatio': 0.1,
            },
            'schemaVersion': '1',
            'requiredTables': ['catalog_metadata'],
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('데이터팩 manifest는 pack URL 경로 이탈을 거부한다', () {
    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [
          {
            'id': 'capital',
            'version': '18',
            'url': '../capital-v18.sqlite.gz',
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
      throwsFormatException,
    );
  });

  test('데이터팩 manifest는 SQL 식별자로 안전하지 않은 테이블명을 거부한다', () {
    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [
          {
            'id': 'capital',
            'version': '18',
            'url': 'catalog/capital-v18.sqlite.gz',
            'sha256': 'a' * 64,
            'sqliteSha256': 'b' * 64,
            'schemaVersion': '1',
            'requiredTables': ['catalog_metadata'],
            'minimumTableRows': {'stations; DROP TABLE stations;': 1},
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('데이터팩 manifest는 파일 경로로 안전하지 않은 pack id와 version을 거부한다', () {
    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [
          {
            'id': '../capital',
            'version': '18',
            'url': 'catalog/capital-v18.sqlite.gz',
            'sha256': 'a' * 64,
            'sqliteSha256': 'b' * 64,
            'schemaVersion': '1',
            'requiredTables': ['catalog_metadata'],
          },
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [
          {
            'id': 'capital',
            'version': '../18',
            'url': 'catalog/capital-v18.sqlite.gz',
            'sha256': 'a' * 64,
            'sqliteSha256': 'b' * 64,
            'schemaVersion': '1',
            'requiredTables': ['catalog_metadata'],
          },
        ],
        'emergencyOverride': {
          'id': 'capital',
          'version': '../17',
          'reason': '시설 상태 긴급 정정',
        },
      }),
      throwsFormatException,
    );
  });
}
