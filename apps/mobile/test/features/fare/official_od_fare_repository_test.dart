import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/fare/official_od_fare_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official OD fare repository는 exact 방향만 조회한다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    final repository = OfficialOdFareRepository(catalogDatabase: database);

    await database.customStatement('''
      INSERT INTO stations (
        id, name_ko, name_en, name_sub, normalized_name, region,
        data_quality_level, data_source_type
      ) VALUES
        ('station-sangnoksu', '상록수', '', '', '상록수', '수도권', 'LEVEL_1', 'OFFICIAL_FILE'),
        ('station-sadang', '사당', '', '', '사당', '수도권', 'LEVEL_1', 'OFFICIAL_FILE')
    ''');
    await _insertQuote(database, 'station-sangnoksu', 'station-sadang');
    final forward = await repository.findExact(
      originStationId: 'station-sangnoksu',
      destinationStationId: 'station-sadang',
    );
    final unsupportedReverse = await repository.findExact(
      originStationId: 'station-sadang',
      destinationStationId: 'station-sangnoksu',
    );

    expect(forward, isNotNull);
    expect(forward!.gnrlCardFare, 1950);
    expect(unsupportedReverse, isNull);

    await _insertQuote(database, 'station-sadang', 'station-sangnoksu');
    final reverse = await repository.findExact(
      originStationId: 'station-sadang',
      destinationStationId: 'station-sangnoksu',
    );
    expect(reverse, isNotNull);
    expect(reverse!.destinationStationId, 'station-sangnoksu');
  });

  test('official OD fare repository는 승인되지 않은 provenance를 반환하지 않는다', () async {
    final database = CatalogDatabase.memory();
    addTearDown(database.close);
    final repository = OfficialOdFareRepository(catalogDatabase: database);
    await _insertStations(database);
    await _insertQuote(database, 'station-sangnoksu', 'station-sadang');

    for (final mutation in [
      "UPDATE official_od_fare_quotes SET source_id = 'other-source'",
      "UPDATE official_od_fare_quotes SET source_id = 'seoul-metro-official-od-fares', snapshot_id = 'other-snapshot'",
      "UPDATE official_od_fare_quotes SET snapshot_id = 'seoul-metro-official-od-fares-20260712', mapping_ledger_hash = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'",
    ]) {
      await database.customStatement(mutation);
      expect(
        await repository.findExact(
          originStationId: 'station-sangnoksu',
          destinationStationId: 'station-sadang',
        ),
        isNull,
      );
    }
  });

  test(
    'official OD fare repository는 승인된 수도권 canary와 부산 snapshot을 반환한다',
    () async {
      final database = CatalogDatabase.memory();
      addTearDown(database.close);
      final repository = OfficialOdFareRepository(catalogDatabase: database);
      await database.customStatement('''
      INSERT INTO stations (
        id, name_ko, name_en, name_sub, normalized_name, region,
        data_quality_level, data_source_type
      ) VALUES
        ('station-2af75c3d707b', '서울역', '', '', '서울역', '수도권', 'LEVEL_1', 'OFFICIAL_FILE'),
        ('station-a2d54a5d63d2', '시청', '', '', '시청', '수도권', 'LEVEL_1', 'OFFICIAL_FILE'),
        ('station-fcb7a21e5606', '하단', '', '', '하단', '부산', 'LEVEL_1', 'OFFICIAL_FILE'),
        ('station-dd45c69d3e40', '당리', '', '', '당리', '부산', 'LEVEL_1', 'OFFICIAL_FILE')
    ''');
      await _insertQuote(
        database,
        'station-2af75c3d707b',
        'station-a2d54a5d63d2',
        sourceId: 'seoul-metro-official-od-fare-canary',
        snapshotId: 'seoul-metro-official-od-fare-canary-run-29085674167',
        mappingLedgerHash:
            '58e795e03161e2100cffb2c777efcaa1d09a5e03abc7363676be5f26ae353541',
      );
      await _insertQuote(
        database,
        'station-fcb7a21e5606',
        'station-dd45c69d3e40',
        sourceId: 'busan-transportation-official-od-fares',
        snapshotId: 'busan-transportation-official-od-fares-20260713',
        mappingLedgerHash:
            '9c327840275be5c4583fc9e9cfdd16d2e4ecc06f660d08fd682bf9fe27d72390',
      );

      expect(
        await repository.findExact(
          originStationId: 'station-2af75c3d707b',
          destinationStationId: 'station-a2d54a5d63d2',
        ),
        isNotNull,
      );
      expect(
        await repository.findExact(
          originStationId: 'station-fcb7a21e5606',
          destinationStationId: 'station-dd45c69d3e40',
        ),
        isNotNull,
      );
    },
  );
}

Future<void> _insertStations(CatalogDatabase database) {
  return database.customStatement('''
    INSERT INTO stations (
      id, name_ko, name_en, name_sub, normalized_name, region,
      data_quality_level, data_source_type
    ) VALUES
      ('station-sangnoksu', '상록수', '', '', '상록수', '수도권', 'LEVEL_1', 'OFFICIAL_FILE'),
      ('station-sadang', '사당', '', '', '사당', '수도권', 'LEVEL_1', 'OFFICIAL_FILE')
  ''');
}

Future<void> _insertQuote(
  CatalogDatabase database,
  String originStationId,
  String destinationStationId, {
  String sourceId = 'seoul-metro-official-od-fares',
  String snapshotId = 'seoul-metro-official-od-fares-20260712',
  String mappingLedgerHash =
      '4a487cf9eaacf211a38549f33035555917010b7e6fb0ba6e9a92c30dae50661a',
}) {
  return database.customStatement(
    '''
    INSERT INTO official_od_fare_quotes (
      origin_station_id, destination_station_id, source_id, snapshot_id,
      mapping_ledger_hash, gnrl_card_fare, gnrl_cash_fare, yung_card_fare,
      yung_cash_fare, child_card_fare, child_cash_fare
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      originStationId,
      destinationStationId,
      sourceId,
      snapshotId,
      mappingLedgerHash,
      1950,
      2050,
      1220,
      2050,
      750,
      750,
    ],
  );
}
