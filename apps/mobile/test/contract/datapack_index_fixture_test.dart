import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/datapack/data_pack_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('번들 datapack index fixture를 DataPackIndex가 decode한다', () {
    final raw = File(
      '../../apps/mobile/assets/datapacks/index.json',
    ).readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, Object?>;

    final index = DataPackIndex.fromJson(decoded);

    expect(index.schemaVersion, 1);
    expect(index.builtAt, DateTime.utc(2026, 7, 12));
    expect(index.qualityAsOf, DateTime.utc(2026, 7, 12));
    expect(index.freshnessExpiresAt, DateTime.utc(2026, 8, 11));
    expect(index.sourceSnapshotSetHash, hasLength(64));
    expect(index.schemaIdentity, 'catalog-schema-v1');
    expect(index.packs.map((pack) => pack.id), contains('capital'));
  });

  test('schemaVersion 2 인덱스는 명시적으로 거부한다', () {
    final future = <String, Object?>{'schemaVersion': 2, 'packs': <Object?>[]};

    expect(
      () => DataPackIndex.fromJson(future),
      throwsA(isA<UnsupportedDatapackSchemaException>()),
    );
  });
}
