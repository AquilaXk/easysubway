import 'package:drift/drift.dart';

import 'catalog_database.dart';

extension CanonicalStationIdQuery on CatalogDatabase {
  Future<String?> findCanonicalStationId(String stationId) async {
    final rows = await customSelect(
      '''
      SELECT id AS station_id FROM stations WHERE id = ?
      UNION
      SELECT sa.station_id
      FROM station_aliases sa
      JOIN stations s ON s.id = sa.station_id
      WHERE sa.alias = ? AND sa.alias LIKE 'station-%'
      LIMIT 2
      ''',
      variables: [
        Variable.withString(stationId),
        Variable.withString(stationId),
      ],
      readsFrom: {stations, stationAliases},
    ).get();
    return rows.length == 1 ? rows.single.read<String>('station_id') : null;
  }

  Future<String> resolveCanonicalStationId(String stationId) async {
    return await findCanonicalStationId(stationId) ?? stationId;
  }
}
