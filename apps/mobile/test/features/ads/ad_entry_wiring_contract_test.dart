import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, isNonNegative, reason: start);
  expect(endIndex, greaterThan(startIndex), reason: end);
  return source.substring(startIndex, endIndex);
}

void main() {
  test('세 station detail 진입점이 같은 광고 repository를 전달한다', () {
    final main = File('lib/main.dart').readAsStringSync();
    final stationSearch = File('lib/station_search.dart').readAsStringSync();

    expect(
      _between(main, 'stationDetailBuilder:', 'child: EasySubwayApp'),
      contains('adRepository: bootstrap.dependencies.adRepository'),
    );
    expect(
      _between(
        stationSearch,
        'void _openStationDetail(StationSearchResult result)',
        'class StationRecentSearchSection',
      ),
      contains('adRepository: widget.adRepository'),
    );
    expect(
      _between(
        main,
        'Future<void> _openStationDetailFromFavorite',
        'Future<void> _openFacilityReportFromFavorite',
      ),
      contains('adRepository: widget.adRepository'),
    );
  });
}
