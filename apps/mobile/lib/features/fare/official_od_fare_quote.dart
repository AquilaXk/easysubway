const approvedOfficialOdFareSourceId = 'seoul-metro-official-od-fares';
const approvedOfficialOdFareSnapshotId =
    'seoul-metro-official-od-fares-20260712';
const approvedOfficialOdFareMappingLedgerHash =
    '4a487cf9eaacf211a38549f33035555917010b7e6fb0ba6e9a92c30dae50661a';

final class OfficialOdFareQuote {
  const OfficialOdFareQuote({
    required this.originStationId,
    required this.destinationStationId,
    required this.sourceId,
    required this.snapshotId,
    required this.mappingLedgerHash,
    required this.gnrlCardFare,
    required this.gnrlCashFare,
    required this.yungCardFare,
    required this.yungCashFare,
    required this.childCardFare,
    required this.childCashFare,
  });

  final String originStationId;
  final String destinationStationId;
  final String sourceId;
  final String snapshotId;
  final String mappingLedgerHash;
  final int gnrlCardFare;
  final int gnrlCashFare;
  final int yungCardFare;
  final int yungCashFare;
  final int childCardFare;
  final int childCashFare;
}
