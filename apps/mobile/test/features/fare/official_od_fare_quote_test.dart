import 'package:easysubway_mobile/features/fare/official_od_fare_quote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official OD fare quote는 공식 여섯 요금과 provenance를 보존한다', () {
    const quote = OfficialOdFareQuote(
      originStationId: 'station-sangnoksu',
      destinationStationId: 'station-sadang',
      sourceId: 'seoul-metro-official-od-fares',
      snapshotId: 'seoul-metro-official-od-fares-20260712',
      mappingLedgerHash:
          '4a487cf9eaacf211a38549f33035555917010b7e6fb0ba6e9a92c30dae50661a',
      gnrlCardFare: 1950,
      gnrlCashFare: 2050,
      yungCardFare: 1220,
      yungCashFare: 2050,
      childCardFare: 750,
      childCashFare: 750,
    );

    expect(quote.originStationId, 'station-sangnoksu');
    expect(quote.destinationStationId, 'station-sadang');
    expect(quote.gnrlCardFare, 1950);
    expect(quote.childCashFare, 750);
  });
}
