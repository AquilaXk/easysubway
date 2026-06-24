import 'dart:io';

import 'package:easysubway_mobile/features/stations/domain/station_line.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_line_badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const badgeCases = [
    ('seoul-1', '수도권 1호선', 'seoul_1_compact_256.png'),
    ('seoul-2', '수도권 2호선', 'seoul_2_compact_256.png'),
    ('seoul-3', '수도권 3호선', 'seoul_3_compact_256.png'),
    ('seoul-4', '수도권 4호선', 'seoul_4_compact_256.png'),
    ('seoul-5', '수도권 5호선', 'seoul_5_compact_256.png'),
    ('seoul-6', '수도권 6호선', 'seoul_6_compact_256.png'),
    ('seoul-7', '수도권 7호선', 'seoul_7_compact_256.png'),
    ('seoul-8', '수도권 8호선', 'seoul_8_compact_256.png'),
    ('seoul-9', '수도권 9호선', 'seoul_9_compact_256.png'),
    ('gyeongui-jungang', '수도권 경의중앙선', 'gyeongui_jungang_compact_256.png'),
    ('suin-bundang', '수도권 수인분당선', 'suin_bundang_compact_256.png'),
    ('shinbundang', '수도권 신분당선', 'shinbundang_compact_256.png'),
    ('airport', '수도권 공항철도', 'airport_railroad_compact_256.png'),
    ('incheon-1', '수도권 인천 1호선', 'incheon_1_compact_256.png'),
    ('incheon-2', '수도권 인천 2호선', 'incheon_2_compact_256.png'),
    ('uijeongbu', '수도권 의정부경전철', 'uijeongbu_lrt_compact_256.png'),
    ('ui-sinseol', '수도권 우이신설선', 'ui_sinseol_compact_256.png'),
    ('gimpo-goldline', '수도권 김포골드라인', 'gimpo_goldline_compact_256.png'),
    ('everline', '수도권 용인에버라인', 'everline_compact_256.png'),
    ('sillim', '수도권 신림선', 'sillim_compact_256.png'),
    ('gyeongchun', '수도권 경춘선', 'gyeongchun_compact_256.png'),
    ('gyeonggang', '수도권 경강선', 'gyeonggang_compact_256.png'),
    ('seohae', '수도권 서해선', 'seohae_compact_256.png'),
    ('gtx-a', '수도권 GTX-A', 'gtx_a_compact_256.png'),
    ('busan-1', '1호선', 'busan_1_compact_256.png'),
    ('busan-2', '2호선', 'busan_2_compact_256.png'),
    ('busan-3', '3호선', 'busan_3_compact_256.png'),
    ('busan-4', '4호선', 'busan_4_compact_256.png'),
    ('bgl', '부산김해경전철', 'busan_gimhae_compact_256.png'),
    ('donghae', '동해선', 'donghae_compact_256.png'),
    ('daegu-1', '대구 1호선', 'daegu_1_compact_256.png'),
    ('daegu-2', '대구 2호선', 'daegu_2_compact_256.png'),
    ('daegu-3', '대구 3호선', 'daegu_3_compact_256.png'),
    ('daegyeong', '대구 대경선', 'daegyeong_compact_256.png'),
    ('daejeon-1', '대전 1호선', 'daejeon_1_compact_256.png'),
    ('gwangju-1', '광주 1호선', 'gwangju_1_compact_256.png'),
  ];

  test('전국 노선 심볼은 제공 라이브러리 PNG asset으로 연결된다', () {
    for (final (id, name, asset) in badgeCases) {
      expect(stationLineBadgeAssetNameFor(id: id, name: name), asset);
      expect(
        File('assets/metro_symbols/line_badges/$asset').existsSync(),
        isTrue,
      );
    }

    final assetCount = Directory('assets/metro_symbols/line_badges')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('_compact_256.png'))
        .length;
    expect(assetCount, badgeCases.length);
  });

  testWidgets('노선 심볼 위젯은 제공 PNG를 그대로 렌더링한다', (tester) async {
    final lines = [
      for (final (id, name, _) in badgeCases)
        StationSearchLine(
          id: id,
          name: name,
          color: '#000000',
          stationCode: '',
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StationLineBadges(lines: lines, size: 40)),
      ),
    );

    for (final (id, _, asset) in badgeCases) {
      final finder = find.byKey(Key('stationLineBadge-$id'));
      final image = tester.widget<Image>(
        find.descendant(of: finder, matching: find.byType(Image)),
      );
      expect(tester.getSize(finder), const Size(40, 40));
      expect(
        (image.image as AssetImage).assetName,
        'assets/metro_symbols/line_badges/$asset',
      );
    }

    expect(
      find.descendant(
        of: find.byKey(const Key('stationLineBadge-busan-1')),
        matching: find.byType(ClipRRect),
      ),
      findsOneWidget,
    );
  });
}
