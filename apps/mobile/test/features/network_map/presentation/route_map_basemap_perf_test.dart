import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';

// #2068 하이브리드 바탕층 성능 계측(계측 위주, 느슨한 assert).
//
// 바탕 .vec 런타임 로드+디코드 시간과 파일 크기를 측정해 print한다. 컴파일 시간은
// 셸 `time`으로 별도 측정하므로 여기에 넣지 않는다. structured recordRouteMapPicture
// 대비 비교는 데이터 로드가 무거워 생략하고 vec 로드만 계측한다(범위 밖 노이즈 회피).
//
// flutter test cwd는 apps/mobile다 — 자산 경로를 그 기준 상대경로로 연다.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const seoulAsset = 'assets/datapacks/metro_map_pack/basemap/seoul.vec';

  testWidgets('seoul 바탕 .vec 로드+디코드 시간과 파일 크기 계측', (tester) async {
    // 파일 크기(bytes) — File.lengthSync는 cwd(apps/mobile) 기준 상대경로로 연다.
    final vecFile = File(seoulAsset);
    expect(vecFile.existsSync(), isTrue, reason: '$seoulAsset가 번들에 있어야 한다');
    final sizeBytes = vecFile.lengthSync();

    // 로드+디코드 시간 — 실제 async 자산 로드가 완료되도록 runAsync 안에서 잰다.
    late final Duration loadDuration;
    await tester.runAsync(() async {
      final stopwatch = Stopwatch()..start();
      final info = await vg.loadPicture(
        const AssetBytesLoader(seoulAsset),
        null,
      );
      stopwatch.stop();
      loadDuration = stopwatch.elapsed;
      info.picture.dispose();
    });

    // ignore: avoid_print
    print(
      '[#2068 perf] seoul.vec 크기=${sizeBytes}B(${(sizeBytes / 1024).toStringAsFixed(1)}KB) '
      '로드+디코드=${loadDuration.inMicroseconds}us(${loadDuration.inMilliseconds}ms)',
    );

    // 느슨한 회귀 상한(계측이 주목적) — 로드가 2초를 넘으면 이상 신호.
    expect(loadDuration.inMilliseconds, lessThan(2000));
    expect(sizeBytes, greaterThan(0));
  });
}
