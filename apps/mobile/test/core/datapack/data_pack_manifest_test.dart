import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('데이터팩 manifest는 TTL과 pack 검증 조건을 파싱한다', () {
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
    expect(manifest.packs.single.minimumTableRows, {'stations': 2});
    expect(manifest.emergencyOverride?.version, '17');
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
