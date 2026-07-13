const approvedOfficialOdFareSourceId = 'seoul-metro-official-od-fares';
const approvedOfficialOdFareSnapshotId =
    'seoul-metro-official-od-fares-20260712';
const approvedOfficialOdFareMappingLedgerHash =
    '4a487cf9eaacf211a38549f33035555917010b7e6fb0ba6e9a92c30dae50661a';

const approvedOfficialOdFareProvenance =
    <String, ({String snapshotId, String mappingLedgerHash})>{
      approvedOfficialOdFareSourceId: (
        snapshotId: approvedOfficialOdFareSnapshotId,
        mappingLedgerHash: approvedOfficialOdFareMappingLedgerHash,
      ),
      'seoul-metro-official-od-fare-canary': (
        snapshotId: 'seoul-metro-official-od-fare-canary-run-29085674167',
        mappingLedgerHash:
            '58e795e03161e2100cffb2c777efcaa1d09a5e03abc7363676be5f26ae353541',
      ),
      'busan-transportation-official-od-fares': (
        snapshotId: 'busan-transportation-official-od-fares-20260713',
        mappingLedgerHash:
            '9c327840275be5c4583fc9e9cfdd16d2e4ecc06f660d08fd682bf9fe27d72390',
      ),
    };

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
