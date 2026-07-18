import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../../../support/pretendard_test_font.dart';

// #2068 배지 텍스트 세로 중심 게이트 (전 권역, 컴파일 .vec 픽셀 실측).
//
// 오너 강반려(수도권): 마곡나루 환승 캡슐의 9호선 배지 "9"가 원 하단으로 쏠려
// 원 밖으로 이탈. 원인은 그 배지가 scale(-1)+rotate(180) 중첩 프레임에 있어
// compile-basemap-vec.mjs의 central-baseline 보정(+0.35*fontSize)이 렌더에서
// 반대 방향으로 작동한 것(전 권역 유일한 반전 배지). 소스에서 두 배지를
// alphabetic 기준 y로 사전 중심 정렬하고 central/middle 속성을 제거해 보정
// 대상에서 뺐다.
//
// 이 게이트는 앱과 동일 경로(번들 Pretendard + vector_graphics 런타임)로
// 컴파일된 .vec을 디코드→렌더→픽셀 실측해 배지 잉크의 세로 중심이 원 중심과
// 정렬됨을 고정한다. 검증 방식이 SVG 헤드리스가 아니라 실제 .vec 렌더라는 점이
// 핵심이다(오너가 본 실기기 렌더와 동일 파이프라인).
//
// 측정: 원 중심을 이미지 중심에 두고, 원 반경 마스크 안에서 잉크(흰/어두운)
// 픽셀 세로 centroid의 원 중심 대비 오프셋을 fontSize(렌더) 비로 구한다.

class _Badge {
  const _Badge(
    this.label,
    this.region,
    this.cx,
    this.cy,
    this.fontLocal,
    this.discR,
    this.inkWhite,
    this.k,
    this.tolerance,
  );
  final String label;
  final String region; // vec 파일 stem
  final double cx; // scale 레이어 로컬 좌표(원 중심)
  final double cy;
  final double fontLocal;
  final double discR;
  final bool inkWhite; // true=흰 잉크, false=#333D4B 어두운 잉크
  final double k; // scale 레이어 배율(수도권 0.455, 그 외 1)
  final double tolerance; // |ratio| 상한
}

// 수도권(오너 반려 권역) 배지로 게이트한다. 수도권 배지는 scale(0.455) 레이어
// 안에 있어 컴파일 시 텍스트가 축정렬 transform과 함께 path로 outline되므로
// 렌더가 폰트 로드에 무관하게 결정적이다 — 픽셀 실측이 신뢰 가능하다.
//
// (타 권역 SVG는 scale 레이어가 없어 배지 텍스트가 런타임 drawParagraph로 남고,
//  배지 텍스트에 font-family가 없어 flutter_test 런타임에서 기본 폰트(Ahem 등)로
//  tofu 렌더된다 — 픽셀 실측 불가. 타 권역 배지는 반전 배지가 전무하고 동일한
//  normalizeTextBaselineAndScale(+0.35) 경로를 타므로, 이 게이트의 종점 숫자
//  검증이 그 계수 정합성을 대표한다. 타 권역 회귀는 compile --verify(2회 sha256
//  동일)와 매치율·정렬 게이트가 담당한다.)
//
// 정상(비반전) 종점 숫자 배지: 오차 ≤ fontSize의 5%(task 기준). 실측 ~2~3%.
// 마곡 반전 배지(수정본): 원 반경 마스크로 캡슐 흰 링을 배제한 잉크 centroid.
// 실측 9=+0.047, 공항=-0.017. 상한 0.12(글리프 잉크 비대칭 여유)로 두어 오너가
// 반려한 '원 하단/밖 이탈'(반전 버그 재발 시 ratio ≳ 0.5)을 확실히 잡는다.
// seoul 좌표는 scale(0.455)+translate(70,138) 적용 전 로컬, 마곡 좌표는
// rotate(180,1268.3843,1433.5031) 적용 후 렌더 로컬.
const _badges = <_Badge>[
  // 수도권 레퍼런스 종점 숫자(비반전).
  _Badge(
    'seoul 종점1(흰)',
    'seoul',
    1535.7,
    2563.0,
    22.5,
    19.5,
    true,
    0.455,
    0.05,
  ),
  _Badge(
    'seoul 종점9(어두움)',
    'seoul',
    1024.5,
    1282.8,
    22.5,
    19.5,
    false,
    0.455,
    0.05,
  ),
  // 수도권 마곡 환승 배지(반전, 수정 대상).
  // #2068 유클리드 재간격(간격 패스 3라운드)으로 마곡나루 캡슐이
  // translate(86.862,-55.908)만큼 이동(간격 정합 패스, 신방화/가양/증미
  // 인접 붕괴 해소) — rotate 적용 후 로컬 좌표에 동일 델타를 가산.
  //
  // #2068 라운드 4(8선형 run 재작도)로 마곡나루가 렌더 공간에서 추가로
  // (0,-16)px 이동(실측: route_map_positions HEAD (694,768)→라운드4
  // (694,752)). local delta = 16/0.455 ≈ 35.1648(scale 0.455 역산) — 회전
  // 180° 후 로컬 좌표에서 cy만 감소(cx는 dx=0이라 불변).
  _Badge(
    'seoul 마곡9(반전)',
    'seoul',
    1371.6535,
    1363.6164,
    18,
    12,
    true,
    0.455,
    0.12,
  ),
  _Badge(
    'seoul 마곡공항(반전)',
    'seoul',
    1371.6535,
    1337.0665,
    10.3,
    12,
    true,
    0.455,
    0.12,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('전 권역 배지 텍스트 세로 중심 정렬(컴파일 .vec 픽셀 실측)', (tester) async {
    await loadPretendardTestFont();
    await tester.runAsync(() async {
      final pictures = <String, ui.Picture>{};
      for (final region in {for (final b in _badges) b.region}) {
        final info = await vg.loadPicture(
          AssetBytesLoader(
            'assets/datapacks/metro_map_pack/basemap/$region.vec',
          ),
          null,
        );
        pictures[region] = info.picture;
      }

      const double s = 24.0;
      final failures = <String>[];
      for (final b in _badges) {
        final picture = pictures[b.region]!;
        final tx = b.region == 'seoul' ? 70.0 : 0.0;
        final ty = b.region == 'seoul' ? 138.0 : 0.0;
        final cx = tx + b.k * b.cx;
        final cy = ty + b.k * b.cy;
        final discRpx = b.discR * b.k * s;
        final maskR = discRpx * 1.0; // 원 반경(캡슐 흰 링·이웃 배제)
        final half = (discRpx * 1.35).ceil();
        final w = half * 2, h = half * 2;
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        canvas.translate(w / 2, h / 2);
        canvas.scale(s);
        canvas.translate(-cx, -cy);
        canvas.drawPicture(picture);
        final img = await rec.endRecording().toImage(w, h);
        final data = (await img.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        double sy = 0;
        int cnt = 0;
        for (int py = 0; py < h; py++) {
          for (int px = 0; px < w; px++) {
            final dx = px - w / 2, dy = py - h / 2;
            if (dx * dx + dy * dy > maskR * maskR) continue;
            final o = (py * w + px) * 4;
            final r = data[o], g = data[o + 1], bl = data[o + 2];
            final ink = b.inkWhite
                ? (r > 200 && g > 200 && bl > 200)
                : (r < 110 && g < 110 && bl < 120);
            if (ink) {
              sy += py;
              cnt++;
            }
          }
        }
        img.dispose();
        expect(
          cnt,
          greaterThan(200),
          reason:
              '${b.label}: 잉크 픽셀이 거의 없음 — 배지가 원 밖으로 이탈했거나 '
              '좌표/색 판정이 어긋남(cnt=$cnt).',
        );
        final fontRendered = b.fontLocal * b.k;
        final ratio = ((sy / cnt) - h / 2) / s / fontRendered;
        // ignore: avoid_print
        print(
          '[badge-center] ${b.label}: cnt=$cnt '
          'ratio=${ratio.toStringAsFixed(4)} (상한 ${b.tolerance})',
        );
        if (ratio.abs() > b.tolerance) {
          failures.add(
            '${b.label}: |ratio|=${ratio.abs().toStringAsFixed(4)} '
            '> ${b.tolerance}',
          );
        }
      }

      for (final p in pictures.values) {
        p.dispose();
      }
      expect(
        failures,
        isEmpty,
        reason: '배지 텍스트 세로 중심 이탈:\n${failures.join('\n')}',
      );
    });
  });
}
