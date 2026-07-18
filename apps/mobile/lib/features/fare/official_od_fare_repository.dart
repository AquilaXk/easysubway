import 'package:drift/drift.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/features/fare/official_od_fare_quote.dart';

final class OfficialOdFareRepository {
  const OfficialOdFareRepository({required this.catalogDatabase});

  final CatalogDatabase catalogDatabase;

  Future<OfficialOdFareQuote?> findExact({
    required String originStationId,
    required String destinationStationId,
  }) async {
    if (originStationId.isEmpty ||
        destinationStationId.isEmpty ||
        originStationId == destinationStationId) {
      return null;
    }
    final row = await catalogDatabase
        .customSelect(
          '''
      SELECT origin_station_id, destination_station_id, source_id, snapshot_id,
             mapping_ledger_hash, gnrl_card_fare, gnrl_cash_fare,
             yung_card_fare, yung_cash_fare, child_card_fare, child_cash_fare
      FROM official_od_fare_quotes
      WHERE origin_station_id = ? AND destination_station_id = ?
      LIMIT 1
      ''',
          variables: [
            Variable.withString(originStationId),
            Variable.withString(destinationStationId),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _approvedQuote(row);
  }

  Future<Map<String, OfficialOdFareQuote>> loadAllApproved() async {
    final rows = await catalogDatabase.customSelect('''
      SELECT origin_station_id, destination_station_id, source_id, snapshot_id,
             mapping_ledger_hash, gnrl_card_fare, gnrl_cash_fare,
             yung_card_fare, yung_cash_fare, child_card_fare, child_cash_fare
      FROM official_od_fare_quotes
      ORDER BY origin_station_id, destination_station_id
      ''').get();
    final quotes = <String, OfficialOdFareQuote>{};
    for (final row in rows) {
      final quote = _approvedQuote(row);
      if (quote != null) {
        quotes['${quote.originStationId}->${quote.destinationStationId}'] =
            quote;
      }
    }
    return Map.unmodifiable(quotes);
  }

  OfficialOdFareQuote? _approvedQuote(QueryRow row) {
    final sourceId = row.read<String>('source_id');
    final snapshotId = row.read<String>('snapshot_id');
    final mappingLedgerHash = row.read<String>('mapping_ledger_hash');
    final approvedProvenance = approvedOfficialOdFareProvenance[sourceId];
    final fares = [
      row.read<int>('gnrl_card_fare'),
      row.read<int>('gnrl_cash_fare'),
      row.read<int>('yung_card_fare'),
      row.read<int>('yung_cash_fare'),
      row.read<int>('child_card_fare'),
      row.read<int>('child_cash_fare'),
    ];
    if (approvedProvenance == null ||
        snapshotId != approvedProvenance.snapshotId ||
        mappingLedgerHash != approvedProvenance.mappingLedgerHash ||
        fares.any((fare) => fare < 0)) {
      return null;
    }
    return OfficialOdFareQuote(
      originStationId: row.read<String>('origin_station_id'),
      destinationStationId: row.read<String>('destination_station_id'),
      sourceId: sourceId,
      snapshotId: snapshotId,
      mappingLedgerHash: mappingLedgerHash,
      gnrlCardFare: fares[0],
      gnrlCashFare: fares[1],
      yungCardFare: fares[2],
      yungCashFare: fares[3],
      childCardFare: fares[4],
      childCashFare: fares[5],
    );
  }
}
