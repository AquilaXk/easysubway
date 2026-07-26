import 'package:flutter_test/flutter_test.dart';

import '../../../support/basemap_vec_text_draws.dart';

// #2068 바탕층 라벨 paint-order 회귀 게이트(컴파일 .vec 그리기 순서 실측).
//
// [막는 회귀] 오너 SVG의 역명 라벨은 `paint-order:stroke fill` + 흰 halo를 쓴다
// (busan `.station-name` stroke 5.747px @ font-size 48.85px, daegu 5px @ 34px,
//  daejeon·gwangju `#station-name-labels-layer text` stroke 4px).
// vector_graphics_compiler 1.2.6은 paint-order를 읽지 않고, 런타임
// vector_graphics 1.2.2는 fill → stroke 순서로 그린다. 그대로 컴파일하면 흰
// stroke가 글자 fill을 덮어 **속이 빈 유령 글자**가 된다 — 오너 실기기 실측에서
// 대구는 역명이 화면에서 사실상 소멸했고 부산은 일반역명이 파편화됐다.
// compile-basemap-vec.mjs의 decomposePaintOrder가 해당 요소를
// `stroke 전용 사본 → fill 전용 사본` 두 형제로 분해해 halo를 글자 뒤에 깐다.
//
// [왜 픽셀 측정을 버렸나] 종전 게이트는 대표 라벨 6건의 창을 래스터라이즈해
// "흰 픽셀 = halo, 남색 픽셀 = 글자 코어"로 분류하고 core 비율을 실측으로 맞춘
// 하한(0.25~0.6)과 비교했다. 전량 반입 계약(오너 최종 지시 "100% 동일하게")으로
// 오너 SVG의 `page-background`(전면 흰 rect)가 바탕층에 들어오면서 **배경과 halo가
// 같은 흰색**이 됐다 — 흰 픽셀로 halo를 셀 수 없다(실측: 수도권 청라국제도시
// core 비율이 0.090으로 붕괴, 라벨 자체는 정상). 맞춘 하한값도 근거가 사라졌다.
//
// [무엇을 대신 보나] 이 게이트가 지켜야 하는 명제는 "halo가 글자보다 **먼저**
// 그려진다"이다. 그것은 .vec의 **그리기 순서**로 직접 확인할 수 있다 — 래스터·
// 폰트·배경과 무관하고 맞춘 상수도 없다. 같은 글자·같은 앵커에 stroke 전용 draw와
// fill 전용 draw가 짝으로 있으면 stroke가 먼저여야 한다. 대표 6건이 아니라
// **5권역 전수**로 본다.
//
// 컴파일 입력 층위(분해가 일어났는가·두 사본이 paint 외 동일한가)는
// tools/route-map/basemap-paint-order-gate.test.mjs가 따로 고정한다. 이 게이트는
// 그 분해가 **배포 바이트까지 순서 그대로 살아남았는지**를 본다.

const _basemapDir = 'assets/datapacks/metro_map_pack/basemap';

// 실측 기준선(2026-07-26). 각 권역 .vec에 실린 halo/글자 짝의 수다. 세는 단위는
// `<text>` 요소가 아니라 **텍스트 런**이다 — 다줄 라벨은 tspan마다 draw가 하나씩
// 나오므로 요소 수(부산 147·대구 97)보다 크고, 라벨 좌표 게이트의 "SVG 라벨 런"
// 수(부산 155·대구 104)와 정확히 일치한다.
//   busan·daegu     : `.station-name`/`.transfer-name` 클래스 규칙이 stroke를 준다.
//   daejeon·gwangju : `#station-name-labels-layer text` **자손 결합자** 규칙이
//     stroke를 준다 — 종전 단순 class 인라이너가 이 규칙을 통째로 버려 halo가
//     조용히 빠져 있었고, 캐스케이드를 사양대로 전개하면서 복원됐다.
//   seoul           : 라벨 CSS가 stroke를 주지 않아 텍스트 분해가 0건이다
//     (공항 아이콘 path 6건만 분해되며 텍스트가 아니다).
const _expectedPairs = <String, int>{
  'seoul': 0,
  'busan': 155,
  'daegu': 104,
  'daejeon': 22,
  'gwangju': 20,
};

/// 같은 글자·같은 앵커를 가리키는 키(부동소수 흔들림을 흡수한다).
String _anchorKey(BasemapVecTextDraw draw) =>
    '${draw.text}@${draw.x.toStringAsFixed(3)},${draw.y.toStringAsFixed(3)}';

void main() {
  test('#2068 halo(stroke) 사본이 글자(fill) 사본보다 먼저 그려진다 — 5권역 전수', () {
    final failures = <String>[];
    final summary = <String>[];

    for (final entry in _expectedPairs.entries) {
      final draws = basemapVecTextDraws('$_basemapDir/${entry.key}.vec');
      expect(
        draws,
        isNotEmpty,
        reason: '${entry.key}: .vec에서 텍스트 draw를 하나도 못 읽었다 — 디코더가 죽었다',
      );

      final byAnchor = <String, List<BasemapVecTextDraw>>{};
      for (final draw in draws) {
        byAnchor
            .putIfAbsent(_anchorKey(draw), () => <BasemapVecTextDraw>[])
            .add(draw);
      }

      var pairs = 0;
      for (final group in byAnchor.values) {
        final strokeOnly = group
            .where((draw) => draw.hasStroke && !draw.hasFill)
            .toList();
        final fillOnly = group
            .where((draw) => draw.hasFill && !draw.hasStroke)
            .toList();
        if (strokeOnly.isEmpty || fillOnly.isEmpty) continue;
        pairs += 1;
        final firstStroke = strokeOnly
            .map((draw) => draw.index)
            .reduce((a, b) => a < b ? a : b);
        final firstFill = fillOnly
            .map((draw) => draw.index)
            .reduce((a, b) => a < b ? a : b);
        if (firstStroke > firstFill) {
          failures.add(
            '${entry.key}/"${group.first.text}": halo(stroke) draw #$firstStroke가 '
            '글자(fill) draw #$firstFill보다 뒤다 — 흰 halo가 글자를 덮어 유령 글자가 된다.',
          );
        }
      }

      if (pairs != entry.value) {
        failures.add(
          '${entry.key}: halo/글자 짝 $pairs건(기준 ${entry.value}). 라벨 halo가 '
          '빠졌는지·중복인지 먼저 규명하고 정당한 변화면 기준선을 실측으로 갱신하세요.',
        );
      }
      summary.add('${entry.key}: 짝 $pairs건 / 텍스트 draw ${draws.length}건');
    }

    // ignore: avoid_print
    print('[label-paint-order] ${summary.join(' · ')}');
    expect(
      failures,
      isEmpty,
      reason:
          '바탕층 라벨의 halo가 글자보다 뒤에 그려진다 — 오너 실기기 유령 글자 회귀다:\n'
          '${failures.join('\n')}',
    );
  });
}
