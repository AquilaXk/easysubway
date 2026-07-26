import 'dart:convert';

import 'package:crypto/crypto.dart';
// 정준 직렬화는 검증 대상 구현을 그대로 쓴다. 테스트가 규칙을 복제하면 3언어
// 분열(이슈 #2528)을 구조적으로 검출할 수 없다.
import 'package:easysubway_mobile/core/datapack/canonical_json.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _productionSigningPublicKey = DataPackSigningPublicKey(
  modulusBase64Url:
      'itNBIH_FyHbqONXe_z8LNzWes4rh3veI4_8RY76rb7onamA-WDoJlvFyvBG-ihBOl7LtgW1rV54hCLHz95VFLmm028-tll9ThDzSs3Bu9ychED-m0vny16tK8ZgB6gf7sJkjGBJn8MLDaiVWoVvD5TEjv433f_vMFIljdNUKZC2Xf0qHYlYv18dAwbJHKeOsmJkky13HNVn40HuEn5FWEJvFI5qqVgpJ-k1V3ip39ga2-Ek5SOVHAL6U44ypjSXUjo7NCKVpuQRwN7hAnvlYutXDdrEQ6Oa3iUtbQJIgkl-ZmTwNkYHCEIhd_ZLB9n_EEHdvyJAmUKCtAKLX5FOa9w',
  exponentBase64Url: 'AQAB',
);
const _productionSignatureValue =
    'iF48gj_9CEV0os3gJMEO2qdn0aAcBXT71zl8Qz6KIWQZ2qm1A0TmCb7f6wTJEoP3cFSZQdgmXcj7IPFNv9gLE9O_s0-DmwniFX7OIv8icwGe1BKHNJfFmHCqWyLs0uuUVZTmY6RwqS_YnElf_0caT1qDS7L32uu5zYXnWGTg5ul2xeRuBgDGW9gFs9I4UkvdF-MbNjVxCby4tyuCsQSHxUhpFLSLKluLGWc7lY4u688Ss2dR9Zs-zlYiWb4GQ6lxKU_lfx_0FSl3yipgrhX7OpAihyVBuxh-PA_MA5KAqJ0C5HqxAJ_lYZhgYKb5zvJ3eChI7uWc2OhyZ2ZyE-jYdw';
const _productionRouteRegressionSignatureValue =
    'UmI9-5bLdUMmyxNcnOJb5Tyirv4KvKKvxXKcr-MgwCQhfI4baUYXvq2igeS6PVZsgBMv4nXD6BNeF5L8VW49afvfU9ZT15NXftD1wg986tEMwjf0YSXXDjriKWy_u-3cbsNIhHOW3oqvnAwCOb0ofvJ8I26bTcVQFjVh4QjXtSiwzCQqr8WHDGvBc2UbOk-3TOuPR7U3YwsNcXUl2uvo7qn5IwEgCh62k5NQPx222y2khlQz5p9do5DzaJKuHXM3kfwcXA-mJDKptx6pZIqx3n5brahAcPjX4dd6Kr6mYDiWU38y-23redacmWk-YgA8gXXXHSH92SLlqXEedOIiDg';
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
          'representativeRouteRegressions': _representativeRouteRegressions,
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

  test('manifest v2는 envelope signature로 active pack 선택을 보호한다', () {
    final json = _v2FixtureManifest();
    final manifest = DataPackManifest.fromJson(json);

    expect(manifest.manifestVersion, 2);
    expect(manifest.channel, 'production');
    expect(manifest.releaseSequence, 42);
    expect(manifest.activePack?.version, '18');
    expect(manifest.signature?.algorithm, 'sha256-manifest-v2');
    expect(
      manifest.packs.single.signature.algorithm,
      'sha256-pack-manifest-v2',
    );

    final tampered = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
    tampered['activePack'] = {'id': 'capital', 'version': '17'};

    expect(() => DataPackManifest.fromJson(tampered), throwsFormatException);
    expect(
      () => DataPackManifest.fromJson(
        json,
        productionSigningPublicKey: _productionSigningPublicKey,
      ),
      throwsFormatException,
    );
  });

  test('manifest v2 replay hash는 signed payload만 사용한다', () {
    final json = _v2FixtureManifest();
    final manifest = DataPackManifest.fromJson(json);
    final signedCanonical = canonicalDataPackJson({
      for (final entry in json.entries)
        if (entry.key != 'signature') entry.key: entry.value,
    });

    expect(
      manifest.manifestHash,
      sha256.convert(utf8.encode(signedCanonical)).toString(),
    );

    // 이슈 #2531(DP-05): signature 객체는 봉투에서 유일하게 서명 대상 밖에 있는
    // 자리다. 아래 추가 필드는 정준 문자열을 전혀 바꾸지 않는다(= 서명은 그대로
    // 유효하다). 그래서 서명되지 않은 값이 몰래 실려 오는 것을 막으려면 파싱이
    // fail closed로 거부하는 수밖에 없다.
    final signature = json['signature']! as Map<String, Object?>;
    signature['unsignedTrace'] = 'debug';

    expect(
      canonicalDataPackJson({
        for (final entry in json.entries)
          if (entry.key != 'signature') entry.key: entry.value,
      }),
      signedCanonical,
    );
    expect(() => DataPackManifest.fromJson(json), throwsFormatException);
  });

  test('manifest v2는 timezone 없는 timestamp를 거부한다', () {
    final json = _v2FixtureManifest();
    json['publishedAt'] = '2026-06-25T00:00:00';
    json['signature'] = {
      'algorithm': 'sha256-manifest-v2',
      'value': sha256
          .convert(utf8.encode(canonicalDataPackJson(json)))
          .toString(),
    };

    expect(() => DataPackManifest.fromJson(json), throwsFormatException);
  });

  test('manifest는 SQLite catalog 외 self-update payload를 거부한다', () {
    final json = _fixturePack();
    json['payloadKind'] = 'flutter_dart_code';
    json['signature'] = {
      'algorithm': 'sha256-pack-manifest-v1',
      'value': _signatureValue('capital', '18', 'a' * 64, 'b' * 64, 1024),
    };
    json['representativeRouteRegressionSignature'] = {
      'algorithm': 'sha256-route-regression-v1',
      'value': _routeRegressionSignatureValue(
        'capital',
        '18',
        'a' * 64,
        'b' * 64,
        1024,
      ),
    };

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [json],
      }),
      throwsFormatException,
    );
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
    // 이슈 #2531(DP-05) 이후 v1 봉투는 공개키가 주입되면 봉투 단계에서 거부되므로,
    // 팩 단위 계약은 팩 파서로 직접 확인한다(검증 대상이 봉투가 아니라 팩이다).
    final validPack = DataPackManifestEntry.fromJson(
      _productionPack(),
      productionSigningPublicKey: _productionSigningPublicKey,
    );
    expect(validPack.artifactKind, DataPackArtifactKind.production);

    final uppercaseHostPack = DataPackManifestEntry.fromJson(
      _productionPack(
        url: 'https://CDN.easysubway.example/catalog/capital-v18.sqlite.gz',
      ),
      productionSigningPublicKey: _productionSigningPublicKey,
    );
    expect(
      uppercaseHostPack.url.toString(),
      'https://cdn.easysubway.example/catalog/capital-v18.sqlite.gz',
    );

    expect(
      () => DataPackManifestEntry.fromJson(
        _productionPack(signatureValue: 'c' * 64),
        productionSigningPublicKey: _productionSigningPublicKey,
      ),
      throwsFormatException,
    );

    expect(
      () => DataPackManifestEntry.fromJson(
        _productionPack(sourceUrl: 'http://example.invalid/source'),
        productionSigningPublicKey: _productionSigningPublicKey,
      ),
      throwsFormatException,
    );

    expect(
      () => DataPackManifestEntry.fromJson(
        _productionPack(
          url:
              'https://mirror.easysubway.example/catalog/capital-v18.sqlite.gz',
        ),
        productionSigningPublicKey: _productionSigningPublicKey,
      ),
      throwsFormatException,
    );

    final changedRouteContract = _productionPack();
    changedRouteContract['representativeRouteRegressions'] = [
      {
        'id': 'direct-local-capital',
        'pattern': 'DIRECT',
        'fromNodeId': 'station-a-line-1',
        'toNodeId': 'station-c-line-1',
        'requiredEdgeIds': ['edge-a-c'],
      },
    ];
    expect(
      () => DataPackManifestEntry.fromJson(
        changedRouteContract,
        productionSigningPublicKey: _productionSigningPublicKey,
      ),
      throwsFormatException,
    );

    final missingPatternContract = _productionPack();
    missingPatternContract['representativeRouteRegressions'] =
        _representativeRouteRegressions
            .where((route) => route['pattern'] != 'MULTI_TRANSFER')
            .toList(growable: false);
    missingPatternContract['representativeRouteRegressionSignature'] = {
      'algorithm': 'rsa-sha256-route-regression-v1',
      'value': _productionRouteRegressionSignatureValue,
    };
    expect(
      () => DataPackManifestEntry.fromJson(
        missingPatternContract,
        productionSigningPublicKey: _productionSigningPublicKey,
      ),
      throwsFormatException,
    );

    expect(
      () => DataPackManifestEntry.fromJson(
        _productionPack(url: 'https:catalog/capital-v18.sqlite.gz'),
        productionSigningPublicKey: _productionSigningPublicKey,
      ),
      throwsFormatException,
    );

    expect(
      () => DataPackManifestEntry.fromJson(
        _productionPack(sourceUrl: 'https://'),
        productionSigningPublicKey: _productionSigningPublicKey,
      ),
      throwsFormatException,
    );

    // 공개키가 없으면 production 팩 서명을 검증할 수 없어 v1 봉투 단계에서도 거부된다.
    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_productionPack()],
      }),
      throwsFormatException,
    );

    // 공개키가 주입되면 같은 문서가 봉투 버전 때문에 거부된다(이슈 #2531).
    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_productionPack()],
      }, productionSigningPublicKey: _productionSigningPublicKey),
      throwsFormatException,
    );
  });

  test('legacy fixture manifest는 신규 metadata 없이도 파싱된다', () {
    final manifest = DataPackManifest.fromJson({
      'manifestVersion': 1,
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
    expect(manifest.manifestVersion, 1);
    expect(pack.artifactKind, DataPackArtifactKind.fixture);
    expect(pack.sizeBytes, isNull);
    expect(pack.signature.value, '0' * 64);
    expect(pack.sourceInventory.single.id, 'legacy-fixture-manifest');
    expect(pack.regionalQualityMetrics.stationCount, 0);
  });

  test('legacy fixture manifest는 sizeBytes와 기존 서명만 있어도 파싱된다', () {
    const id = 'capital';
    const version = '18';
    final compressedSha256 = 'a' * 64;
    final sqliteSha256 = 'b' * 64;
    const sizeBytes = 1024;

    final manifest = DataPackManifest.fromJson({
      'ttlSeconds': 3600,
      'packs': [
        {
          'id': id,
          'version': version,
          'url': 'catalog/capital-v18.sqlite.gz',
          'sha256': compressedSha256,
          'sqliteSha256': sqliteSha256,
          'sizeBytes': sizeBytes,
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
          'schemaVersion': '1',
          'requiredTables': ['catalog_metadata', 'stations'],
        },
      ],
    });

    final pack = manifest.packs.single;
    expect(pack.artifactKind, DataPackArtifactKind.fixture);
    expect(pack.sizeBytes, sizeBytes);
    expect(pack.representativeRouteRegressions, isEmpty);
    expect(pack.representativeRouteRegressionSignature.value, '0' * 64);
  });

  test('manifest는 route regression claim이 없으면 빈 회귀 목록을 허용한다', () {
    final packJson = _fixturePack();
    packJson['representativeRouteRegressions'] = <Object?>[];
    packJson['representativeRouteRegressionSignature'] = {
      'algorithm': 'sha256-route-regression-v1',
      'value': '0' * 64,
    };

    final manifest = DataPackManifest.fromJson({
      'ttlSeconds': 3600,
      'packs': [packJson],
    });

    final pack = manifest.packs.single;
    expect(pack.artifactKind, DataPackArtifactKind.fixture);
    expect(pack.representativeRouteRegressions, isEmpty);
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

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [_fixturePack(url: 'catalog/../evil.sqlite.gz')],
      }),
      throwsFormatException,
    );

    expect(
      () => DataPackManifest.fromJson({
        'ttlSeconds': 3600,
        'packs': [
          _productionPack(
            url: 'https://cdn.easysubway.example/catalog/../evil.sqlite.gz',
          ),
        ],
      }, productionSigningPublicKey: _productionSigningPublicKey),
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

  test('rollout 필드를 파싱한다(부재 시 null)', () {
    final withR = DataPackManifest.fromJson(
      _v2ManifestJson(rollout: {'percentage': 10, 'seed': 'a' * 32}),
    );
    expect(withR.rollout!.percentage, 10);
    expect(withR.rollout!.seed, 'a' * 32);
    final without = DataPackManifest.fromJson(_v2ManifestJson());
    expect(without.rollout, isNull);
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
    'representativeRouteRegressions': _representativeRouteRegressions,
    'representativeRouteRegressionSignature': {
      'algorithm': 'rsa-sha256-route-regression-v1',
      'value': _productionRouteRegressionSignatureValue,
    },
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

Map<String, Object?> _v2ManifestJson({Map<String, Object?>? rollout}) {
  final manifest = <String, Object?>{
    'manifestVersion': 2,
    'channel': 'production',
    'releaseSequence': 42,
    'publishedAt': '2026-06-25T00:00:00.000Z',
    'expiresAt': '2026-06-26T00:00:00.000Z',
    'ttlSeconds': 3600,
    'keyId': 'fixture-key',
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
        'representativeRouteRegressions': _representativeRouteRegressions,
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
          'algorithm': 'sha256-pack-manifest-v2',
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
      },
    ],
    'rollout': ?rollout,
  };
  manifest['signature'] = {
    'algorithm': 'sha256-manifest-v2',
    'value': sha256
        .convert(utf8.encode(canonicalDataPackJson(manifest)))
        .toString(),
  };
  return manifest;
}

Map<String, Object?> _v2FixtureManifest() {
  final manifest = <String, Object?>{
    'manifestVersion': 2,
    'channel': 'production',
    'releaseSequence': 42,
    'publishedAt': '2026-06-25T00:00:00.000Z',
    'expiresAt': '2026-06-26T00:00:00.000Z',
    'ttlSeconds': 3600,
    'keyId': 'fixture-key',
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
        'representativeRouteRegressions': _representativeRouteRegressions,
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
          'algorithm': 'sha256-pack-manifest-v2',
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
