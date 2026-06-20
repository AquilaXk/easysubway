import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _productionSigningPublicKey = DataPackSigningPublicKey(
  modulusBase64Url:
      'itNBIH_FyHbqONXe_z8LNzWes4rh3veI4_8RY76rb7onamA-WDoJlvFyvBG-ihBOl7LtgW1rV54hCLHz95VFLmm028-tll9ThDzSs3Bu9ychED-m0vny16tK8ZgB6gf7sJkjGBJn8MLDaiVWoVvD5TEjv433f_vMFIljdNUKZC2Xf0qHYlYv18dAwbJHKeOsmJkky13HNVn40HuEn5FWEJvFI5qqVgpJ-k1V3ip39ga2-Ek5SOVHAL6U44ypjSXUjo7NCKVpuQRwN7hAnvlYutXDdrEQ6Oa3iUtbQJIgkl-ZmTwNkYHCEIhd_ZLB9n_EEHdvyJAmUKCtAKLX5FOa9w',
  exponentBase64Url: 'AQAB',
);
const _productionSignatureValue =
    'f91YXZn2gD_RBLHjx2ICz5JPd4IXFWpcjESaegXjChW_-Ve3M_7GLqTAbQAYhkM0m2_d-xF7VysLCDhoZ65cuiez4PORyIyEXKp3uhQMssaQOrM52rH1bOHgZgwSxsNtNkAfBZn55YikbU9rdWKFWjk1IwM6XXBzoosXXrabaxX10Piapi76lnMF72c6u_1LL7yVMqK_U05y_Fa2ubDfKJjPbIhd-Jmex6ZtuebAbmf4A-vNVPeDDIxKmumg1pnUNDck0xsYCiLs_rvpaj3BrhiiNYOhSpm6xcpxVuO5GGZb8NcisaI-nWqQ8jHN0ev2MpPKsu4jaUKKfUQyH7R2Hw';

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
            'value': _signatureValue('capital', '18', 'a' * 64, 'b' * 64, 1024),
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
            'url':
                'https://cdn.easysubway.example/catalog/capital-v18.sqlite.gz',
            'sha256': 'a' * 64,
            'sqliteSha256': 'b' * 64,
            'artifactKind': 'production',
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
            'url': 'catalog/capital-v18.sqlite.gz',
            'sha256': 'a' * 64,
            'sqliteSha256': 'b' * 64,
            'sizeBytes': 1024,
            'artifactKind': 'production',
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
              'value': _signatureValue(
                'capital',
                '18',
                'a' * 64,
                'b' * 64,
                1024,
              ),
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

  test('production 데이터팩 manifest는 signature와 source URL 출처 계약을 검증한다', () {
    final validManifest = DataPackManifest.fromJson({
      'ttlSeconds': 3600,
      'packs': [_productionPack()],
    }, productionSigningPublicKey: _productionSigningPublicKey);
    expect(
      validManifest.packs.single.artifactKind,
      DataPackArtifactKind.production,
    );

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_productionPack(signatureValue: 'c' * 64)],
      }, productionSigningPublicKey: _productionSigningPublicKey),
      throwsFormatException,
    );

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_productionPack(sourceUrl: 'http://example.invalid/source')],
      }, productionSigningPublicKey: _productionSigningPublicKey),
      throwsFormatException,
    );

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_productionPack(url: 'https:catalog/capital-v18.sqlite.gz')],
      }, productionSigningPublicKey: _productionSigningPublicKey),
      throwsFormatException,
    );

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_productionPack(sourceUrl: 'https://')],
      }, productionSigningPublicKey: _productionSigningPublicKey),
      throwsFormatException,
    );

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_productionPack()],
      }),
      throwsFormatException,
    );
  });

  test('legacy fixture manifest는 신규 metadata 없이도 파싱된다', () {
    final manifest = DataPackManifest.fromJson({
      'ttlSeconds': 3600,
      'packs': [
        {
          'id': 'capital',
          'version': '18',
          'url': 'catalog/capital-v18.sqlite.gz',
          'sha256': 'a' * 64,
          'sqliteSha256': 'b' * 64,
          'schemaVersion': '1',
          'requiredTables': ['catalog_metadata', 'stations'],
        },
      ],
    });

    final pack = manifest.packs.single;
    expect(pack.artifactKind, DataPackArtifactKind.fixture);
    expect(pack.sizeBytes, isNull);
    expect(pack.signature.value, '0' * 64);
    expect(pack.sourceInventory.single.id, 'legacy-fixture-manifest');
    expect(pack.regionalQualityMetrics.stationCount, 0);
  });

  test('production key가 설정되면 fixture manifest를 거부한다', () {
    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_fixturePack()],
      }, productionSigningPublicKey: _productionSigningPublicKey),
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
      throwsFormatException,
    );

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_fixturePack(url: 'catalog/%2e%2e/evil.sqlite.gz')],
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

Map<String, Object?> _fixturePack({
  String url = 'catalog/capital-v18.sqlite.gz',
}) {
  const id = 'capital';
  const version = '18';
  final compressedSha256 = 'a' * 64;
  final sqliteSha256 = 'b' * 64;
  const sizeBytes = 1024;
  return {
    'id': id,
    'version': version,
    'url': url,
    'sha256': compressedSha256,
    'sqliteSha256': sqliteSha256,
    'sizeBytes': sizeBytes,
    'artifactKind': 'fixture',
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
    'schemaVersion': '1',
    'requiredTables': ['catalog_metadata'],
  };
}

Map<String, Object?> _productionPack({
  String url = 'https://cdn.easysubway.example/catalog/capital-v18.sqlite.gz',
  String? signatureValue,
  String sourceUrl = 'https://example.invalid/source',
}) {
  const id = 'capital';
  const version = '18';
  final compressedSha256 = 'a' * 64;
  final sqliteSha256 = 'b' * 64;
  const sizeBytes = 1024;
  return {
    'id': id,
    'version': version,
    'url': url,
    'sha256': compressedSha256,
    'sqliteSha256': sqliteSha256,
    'sizeBytes': sizeBytes,
    'artifactKind': 'production',
    'signature': {
      'algorithm': 'rsa-sha256-pack-manifest-v1',
      'value': signatureValue ?? _productionSignatureValue,
    },
    'sourceInventory': [
      {
        'id': 'capital-official-stations',
        'owner': '수도권 운영기관',
        'url': sourceUrl,
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
