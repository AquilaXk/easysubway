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
  String destinationStationId,
) {
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
      'seoul-metro-official-od-fares',
      'seoul-metro-official-od-fares-20260712',
      '4a487cf9eaacf211a38549f33035555917010b7e6fb0ba6e9a92c30dae50661a',
      1950,
      2050,
      1220,
      2050,
      750,
      750,
    ],
  );
}
