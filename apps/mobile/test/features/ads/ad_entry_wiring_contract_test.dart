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
    final networkMap = File('lib/network_map.dart').readAsStringSync();

    expect(
      _between(main, 'stationDetailBuilder:', 'child: EasySubwayApp'),
      contains('adRepository: bootstrap.dependencies.adRepository'),
    );
    // #2109 Fix: 검색 결과 탭(임베디드·풀페이지 모두)이 노선도 팬 메뉴로 수렴하면서
    // 상세 진입점이 station_search.dart의 _openStationDetail에서
    // network_map.dart의 _openStationDetailFromMap(팬 메뉴 앵커 역명 라벨 탭)으로
    // 옮겨졌다.
    expect(
      _between(
        networkMap,
        'void _openStationDetailFromMap(NetworkMapStation station)',
        '@override',
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
