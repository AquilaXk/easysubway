import 'dart:io' show File;
import 'dart:typed_data' show ByteData;

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

// #2068: basemap 라벨 게이트가 앱과 동일한 Pretendard 메트릭으로 라벨 폭을
// 실측하도록 번들 폰트(pubspec.yaml family 'Pretendard')를 FontLoader로 로드한다.
//
// flutter test 환경은 번들 폰트를 자동 로드하지 않는다 — 로드하지 않으면
// fontFamily:'Pretendard'가 테스트 폴백 폰트로 떨어져 자폭 측정이 무의미해진다
// (게이트가 SVG-앱 자폭 일치를 검증하지 못함). 따라서 각 웨이트 파일의 존재를
// assert해 로드 성공을 보장한다.
const List<String> _pretendardFontFiles = [
  'fonts/Pretendard-Regular.otf', // weight 400
  'fonts/Pretendard-SemiBold.otf', // weight 600
  'fonts/Pretendard-Bold.otf', // weight 700
];

/// 3웨이트(400/600/700)를 family 'Pretendard'로 로드한다. 웨이트 선택은 각 OTF의
/// 내부 메타(OS/2)로 이뤄지므로 TextStyle.fontWeight가 올바른 파일에 매핑된다.
Future<void> loadPretendardTestFont() async {
  final loader = FontLoader('Pretendard');
  for (final path in _pretendardFontFiles) {
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'Pretendard 폰트 자산 누락: $path — 번들 폰트 없이는 basemap 라벨 게이트가 '
          '앱과 다른 폰트로 측정된다(측정 무의미).',
    );
    loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  }
  await loader.load();
}
