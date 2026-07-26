import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../../../support/pretendard_test_font.dart';

// #2068 바탕층 라벨 paint-order 회귀 게이트(컴파일 .vec 픽셀 실측, 2026-07-26).
//
// [막는 회귀] 오너 SVG의 역명 라벨은 `paint-order:stroke fill` + 흰 halo를 쓴다
// (busan `.station-name` stroke 5.747px @ font-size 48.85px, daegu 5px @ 34px).
// vector_graphics_compiler 1.2.6은 paint-order를 읽지 않고, 런타임
// vector_graphics 1.2.2는 fill → stroke 순서로 그린다. 그대로 컴파일하면 흰
// stroke가 글자 fill을 덮어 **속이 빈 유령 글자**가 된다 — 오너 실기기 실측에서
// 대구는 역명이 화면에서 사실상 소멸했고 부산은 일반역명이 파편화됐다.
// compile-basemap-vec.mjs의 decomposePaintOrder가 해당 요소를
// `stroke 전용 사본 → fill 전용 사본` 두 형제로 분해해 halo를 글자 뒤에 깐다.
//
// [측정] 대표 라벨의 글리프 상자만 잘라 렌더하고 픽셀을 분류한다.
//   core  = 라벨 fill 색 계열(어두운 남색 #14293D / #344258) 픽셀 — **글자 코어**
//   halo  = 흰색 계열 픽셀 — halo stroke
// 순서가 뒤집히면 core가 사실상 0이 된다(halo가 코어를 덮음). 따라서
//   (1) core 픽셀 수 ≥ 하한, (2) core/(core+halo) ≥ 하한
// 두 축으로 고정한다. 하한은 수정 후 실측값의 60% 선으로 잡아 폰트 렌더 미세
// 변동에는 둔감하고 순서 뒤집힘에는 즉시 red가 되게 한다.
//
// [대표 라벨 선정] labels.json 앵커에서 이웃 라벨과의 여백(clearance)이 큰 역을
// 권역·role별로 하나씩 골랐다 — 창 안에 이웃 라벨 잉크가 섞이지 않게 하기 위함.
// halo가 없는 3권역(수도권·대전·광주)은 같은 측정으로 **불변 가드**로 쓴다:
// 이 권역 라벨은 stroke 자체가 컴파일 입력에 없어 core만 존재해야 한다.

class _LabelProbe {
  const _LabelProbe({
    required this.region,
    required this.asset,
    required this.station,
    required this.role,
    required this.minCorePixels,
    required this.minCoreRatio,
  });

  final String region;
  final String asset;
  final String station;
  final String role;

  /// 창 안 core(글자 코어) 픽셀 수 하한.
  final int minCorePixels;

  /// core / (core + halo) 하한. halo가 코어를 덮으면 0에 수렴한다.
  final double minCoreRatio;
}

const _probes = <_LabelProbe>[
  // ── halo 있는 권역(회귀 당사자) ──────────────────────────────────────────
  _LabelProbe(
    region: 'busan',
    asset: 'assets/datapacks/metro_map_pack/basemap/busan.vec',
    station: '공항',
    role: 'ordinary',
    minCorePixels: 2400,
    minCoreRatio: 0.30,
  ),
  _LabelProbe(
    region: 'busan',
    asset: 'assets/datapacks/metro_map_pack/basemap/busan.vec',
    station: '거제',
    role: 'transfer',
    minCorePixels: 2800,
    minCoreRatio: 0.30,
  ),
  _LabelProbe(
    region: 'daegu',
    asset: 'assets/datapacks/metro_map_pack/basemap/daegu.vec',
    station: '남산',
    role: 'ordinary',
    minCorePixels: 1100,
    minCoreRatio: 0.25,
  ),
  _LabelProbe(
    region: 'daegu',
    asset: 'assets/datapacks/metro_map_pack/basemap/daegu.vec',
    station: '동대구역',
    role: 'transfer',
    minCorePixels: 2400,
    minCoreRatio: 0.25,
  ),
  // ── halo 없는 3권역(불변 가드) ───────────────────────────────────────────
  _LabelProbe(
    region: 'seoul',
    asset: 'assets/datapacks/metro_map_pack/basemap/seoul.vec',
    station: '청라국제도시',
    role: 'ordinary',
    minCorePixels: 400,
    minCoreRatio: 0.60,
  ),
  // 대전은 이 픽셀 창 기법의 대상에서 뺀다 — labels.json 앵커와 .vec 실제
  // 렌더 위치가 map wrapper `translate(0 88)`만큼 어긋나 있다(#2068 핫픽스
  // 조사 중 발견한 **별건 선재 결함**: 역 심벌은 +88이 정확히 반영되는데
  // 역명 라벨만 +176 위치에 그려진다). 이 핫픽스는 대전 .vec을 1바이트도
  // 바꾸지 않으므로(정규화 산출 동일) 대전 불변은 tools/route-map의
  // basemap-paint-order-gate.test.mjs가 구조적으로 고정한다.
  _LabelProbe(
    region: 'gwangju',
    asset: 'assets/datapacks/metro_map_pack/basemap/gwangju.vec',
    station: '금남로4가',
    role: 'ordinary',
    minCorePixels: 1200,
    minCoreRatio: 0.60,
  ),
];

/// 픽셀/소스유닛. 글리프 획을 픽셀로 충분히 분해하되 창이 과대해지지 않는 값.
const double _pixelsPerUnit = 2.0;

Map<String, dynamic> _labelsSidecar() {
  final file = File('assets/datapacks/metro_map_pack/basemap/labels.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, dynamic> _labelEntry(
  Map<String, dynamic> sidecar,
  _LabelProbe probe,
) {
  final regions = sidecar['regions'] as Map<String, dynamic>;
  final entries = (regions[probe.region] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where(
        (entry) =>
            entry['station'] == probe.station && entry['role'] == probe.role,
      )
      .toList();
  if (entries.length != 1) {
    throw StateError(
      '${probe.region} ${probe.station}(${probe.role}) 라벨이 sidecar에 '
      '${entries.length}건 — 대표 라벨을 다시 고르세요.',
    );
  }
  return entries.single;
}

/// 라벨 글리프 상자(viewBox 좌표). 한글 글리프는 대략 1em 폭이라 rune 수 × fontSize를
/// 폭으로, baseline 기준 위 0.95em·아래 0.30em을 높이로 잡는다.
ui.Rect _glyphBox(Map<String, dynamic> entry) {
  final double x = (entry['x'] as num).toDouble();
  final double y = (entry['y'] as num).toDouble();
  final double fontSize = (entry['fontSizePx'] as num).toDouble();
  final int runes = (entry['station'] as String).runes.length;
  final double width = runes * fontSize;
  final double left = switch (entry['anchor'] as String) {
    'middle' => x - width / 2,
    'end' => x - width,
    _ => x,
  };
  return ui.Rect.fromLTRB(
    left,
    y - fontSize * 0.95,
    left + width,
    y + fontSize * 0.30,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('#2068 역명 라벨의 글자 코어가 halo에 덮이지 않는다(.vec 픽셀 실측)', (tester) async {
    await loadPretendardTestFont();
    final sidecar = _labelsSidecar();
    final failures = <String>[];

    await tester.runAsync(() async {
      final pictures = <String, ui.Picture>{};
      for (final probe in _probes) {
        pictures[probe.asset] ??= (await vg.loadPicture(
          AssetBytesLoader(probe.asset),
          null,
        )).picture;
      }

      for (final probe in _probes) {
        final entry = _labelEntry(sidecar, probe);
        final box = _glyphBox(entry);
        final width = (box.width * _pixelsPerUnit).ceil();
        final height = (box.height * _pixelsPerUnit).ceil();

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.scale(_pixelsPerUnit);
        canvas.translate(-box.left, -box.top);
        canvas.drawPicture(pictures[probe.asset]!);
        final image = await recorder.endRecording().toImage(width, height);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        image.dispose();

        var core = 0;
        var halo = 0;
        for (var offset = 0; offset < bytes.length; offset += 4) {
          final r = bytes[offset];
          final g = bytes[offset + 1];
          final b = bytes[offset + 2];
          final a = bytes[offset + 3];
          if (a < 128) continue;
          // 라벨 fill: ordinary #14293D(20,41,61) / transfer #344258(52,66,88).
          if (r < 120 && g < 120 && b < 140) {
            core++;
          } else if (r > 220 && g > 220 && b > 220) {
            halo++;
          }
        }
        final ratio = (core + halo) == 0 ? 0.0 : core / (core + halo);
        // ignore: avoid_print
        print(
          '[paint-order] ${probe.region} ${probe.station}(${probe.role}): '
          'core=$core halo=$halo ratio=${ratio.toStringAsFixed(3)} '
          '(하한 core≥${probe.minCorePixels}, ratio≥${probe.minCoreRatio}) '
          'window=${width}x$height',
        );
        if (core < probe.minCorePixels) {
          failures.add(
            '${probe.region} ${probe.station}(${probe.role}): 글자 코어 잉크 '
            'core=$core < ${probe.minCorePixels} — 흰 halo가 글자를 덮었습니다'
            '(paint-order 분해 누락 의심).',
          );
        }
        if (ratio < probe.minCoreRatio) {
          failures.add(
            '${probe.region} ${probe.station}(${probe.role}): core 비율 '
            '${ratio.toStringAsFixed(3)} < ${probe.minCoreRatio} '
            '(core=$core halo=$halo) — halo가 코어를 잠식했습니다.',
          );
        }
      }
    });

    expect(failures, isEmpty, reason: failures.join('\n'));
  });
}
