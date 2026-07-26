import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../../../support/pretendard_test_font.dart';

// #2408 수도권 종점 표현 게이트(컴파일 seoul.vec 픽셀 실측).
//
// 오너가 직접 제작한 종점 노선 심볼(캡슐 배지, terminal-route-badges-layer)을
// 기계 이식 배지(line-terminal-badges-layer, #2408에서 제거) 대신 그대로 렌더한다.
// 오너 칩 그룹은 matrix(2.198,…)/translate…scale(2.198)… 축정렬 스케일을 갖는데,
// vector_graphics_compiler 1.2.6이 그 그룹 스케일을 텍스트 fontSize엔 반영하지
// 않는 버그가 있어 compile-basemap-vec.mjs의 foldTerminalChipScale가 fontSize를
// 그룹 스케일만큼 선보정한다(안 하면 캡슐 대비 글자가 ~2.198× 작게 렌더). 이
// 게이트는 앱과 동일 경로(번들 Pretendard + vector_graphics 런타임)로 컴파일된
// seoul.vec을 디코드→렌더→픽셀 실측해 다음을 고정한다:
//   (A) 오너 칩: 캡슐 안에 흰 글자 잉크가 존재하고(선보정 누락 시 사실상 소멸),
//       세로 중심이 캡슐 중심과 정렬되며(baseline 보정), 글자가 캡슐 좌우 폭 안에
//       들어온다(넘침 없음).
//   (B) 마곡 환승 배지: scale(-1) 반전 프레임의 오너 원본 배지(구 마곡나루 버그와
//       동일 위험군). #2068에서 소스 사전 중심정렬로 회귀 가드에 편입, 그대로 유지.
//
// seoul 좌표는 scale(0.455)+translate(...) 적용 전 scale-레이어 로컬(오너 기준본
// viewBox). translate는 소스 SVG에서 직접 파싱해 좌표가 바뀌어도 게이트가 따라간다.
({double tx, double ty}) _seoulScaleLayerTranslate() {
  final svg = File(
    '../../tools/route-map/route-map-defs/svg-sources/easy-subway-sma-v4.svg',
  ).readAsStringSync();
  final groupMatch = RegExp(
    r'<g\b(?=[^>]*\bid="main-map-scaled-layer")(?=[^>]*\btransform="([^"]+)")[^>]*>',
  ).firstMatch(svg);
  if (groupMatch == null) {
    throw StateError('main-map-scaled-layer transform을 소스 SVG에서 못 찾음');
  }
  final transformValue = groupMatch.group(1)!;
  final translateMatches = RegExp(
    r'translate\(\s*(-?[\d.]+)[,\s]+(-?[\d.]+)\s*\)',
  ).allMatches(transformValue);
  double dx = 0, dy = 0;
  for (final m in translateMatches) {
    dx += double.parse(m.group(1)!);
    dy += double.parse(m.group(2)!);
  }
  return (tx: dx, ty: dy);
}

// 오너 종점 칩(캡슐). cx/cy는 chip transform 적용 후·wrapper 적용 전 scale-레이어
// 로컬 좌표(rect 중심). capHalfW/H는 로컬 rect 반폭/반높이 × 그룹 스케일.
// fontRender는 최종 렌더 fontSize(= 로컬 fontSize × 그룹 스케일 × k).
class _OwnerChip {
  const _OwnerChip(
    this.label,
    this.cx,
    this.cy,
    this.capHalfWLocal,
    this.capHalfHLocal,
    this.fontRender,
    this.inkHeightRatio,
  );
  final String label;
  final double cx; // scale-레이어 로컬(캡슐 중심)
  final double cy;
  final double capHalfWLocal; // = rect.w/2 × 그룹 스케일 (로컬 단위)
  final double capHalfHLocal; // = rect.h/2 × 그룹 스케일 (로컬 단위)
  final double fontRender; // 렌더 fontSize
  /// 잉크 높이 / [fontRender]. 글리프 집합에 따른 실측 비율(숫자 "1"·"9"는
  /// 0.73~0.75, 한글 "신분당"은 0.91 — 한글이 세로로 더 꽉 찬다).
  /// 오너가 칩 크기를 바꾸면 fontRender와 함께 이 값도 재실측해 갱신한다.
  final double inkHeightRatio;
}

const double _k = 0.455; // 수도권 scale 레이어 배율.

// 대표 칩 3개: 단자리 숫자(신창 1·개화 9)와 다자 캡슐(광교 신분당). 글자 fill 전부
// #FFFFFF. 값은 오너 SVG 칩 transform 실측(foldTerminalChipScale 경로).
//
// #2068 오너 v4(2026-07-25) 재실측: 오너가 칩 그룹 배치를
// `translate(...) scale(2.198) translate(...)` 에서 `matrix(2.7475,0,0,2.7475,e,f)`
// 로 바꿨다 — 그룹 스케일 s가 2.198→2.7475로 커졌다(캡슐 rect 로컬 크기
// 30×23·48×23과 로컬 font-size 10.5는 불변). 아래 상수는 전부 s에서 파생된
// 실측값이라 함께 갱신한다(게이트 임계 0.15·폭 여유는 불변):
//   capHalfW/H = rect 반폭·반높이 × s, fontRender = 10.5 × s × k.
//   cx/cy = 칩 transform 적용 후 rect 중심(scale-레이어 로컬) — 신창·개화는
//   v2와 같은 자리, 광교는 캡슐이 넓어지며 중심이 31.5px 좌측으로 옮겨졌다.
const _ownerChips = <_OwnerChip>[
  _OwnerChip('신창(1)', 6150.1812, 4417.5457, 41.212, 31.596, 13.1262, 0.733),
  _OwnerChip('개화(9)', -138.3960, 634.7052, 41.212, 31.596, 13.1262, 0.752),
  _OwnerChip('광교(신분당)', 2447.4280, 3472.1745, 65.940, 31.596, 13.1262, 0.914),
];

// 마곡 환승 배지(반전, 오너 원본 구조 transform="scale(-1)"). #2068 회귀 가드 유지.
class _DiscBadge {
  const _DiscBadge(
    this.label,
    this.cx,
    this.cy,
    this.fontLocal,
    this.discR,
    this.tolerance,
  );
  final String label;
  final double cx;
  final double cy;
  final double fontLocal;
  final double discR;
  final double tolerance;
}

const _discBadges = <_DiscBadge>[
  _DiscBadge('마곡9(반전)', 382.2393, 1027.5074, 18, 12, 0.12),
  _DiscBadge('마곡공항(반전)', 355.6894, 1027.5075, 10.3, 12, 0.12),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('#2408 오너 종점 칩 + 마곡 반전 배지 세로 중심 정렬(컴파일 .vec 픽셀 실측)', (
    tester,
  ) async {
    await loadPretendardTestFont();
    await tester.runAsync(() async {
      final info = await vg.loadPicture(
        const AssetBytesLoader(
          'assets/datapacks/metro_map_pack/basemap/seoul.vec',
        ),
        null,
      );
      final picture = info.picture;
      final t = _seoulScaleLayerTranslate();
      const double s = 24.0; // 픽셀/유닛
      final failures = <String>[];

      // (A) 오너 종점 칩: 흰 글자 존재 + 세로 중심 정렬 + 수평 캡슐 내 포함.
      for (final c in _ownerChips) {
        final cx = t.tx + _k * c.cx;
        final cy = t.ty + _k * c.cy;
        final halfWpx = c.capHalfWLocal * _k * s;
        final halfHpx = c.capHalfHLocal * _k * s;
        // 창: 캡슐보다 살짝 크게(포함 판정용 좌우 여유 3유닛).
        final winHalfW = (halfWpx + 3 * _k * s).ceil();
        // 세로는 캡슐 중앙 밴드(둥근 끝단 근처 이웃 잉크 배제).
        final winHalfH = (halfHpx * 0.72).ceil();
        final w = winHalfW * 2, h = winHalfH * 2;
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
        int cnt = 0, minX = w, maxX = -1, minY = h, maxY = -1;
        for (int py = 0; py < h; py++) {
          for (int px = 0; px < w; px++) {
            final o = (py * w + px) * 4;
            if (data[o] > 232 && data[o + 1] > 232 && data[o + 2] > 232) {
              sy += py;
              cnt++;
              minX = math.min(minX, px);
              maxX = math.max(maxX, px);
              minY = math.min(minY, py);
              maxY = math.max(maxY, py);
            }
          }
        }
        img.dispose();
        if (cnt < 150) {
          failures.add(
            '${c.label}: 흰 글자 잉크 거의 없음(cnt=$cnt) — 그룹 스케일 '
            'fontSize 선보정 누락 의심.',
          );
          continue;
        }
        // 세로 중심 정렬: 잉크 centroid의 캡슐 중심 대비 오프셋 / 렌더 fontSize.
        final ratio = ((sy / cnt) - h / 2) / s / c.fontRender;
        // 수평 포함: 글자 반폭이 캡슐 반폭(± 여유) 안.
        final textHalfWpx = (maxX - minX) / 2;
        final overflowX = textHalfWpx - halfWpx;
        // ignore: avoid_print
        print(
          '[owner-chip] ${c.label}: cnt=$cnt ratio=${ratio.toStringAsFixed(4)} '
          'overflowXpx=${overflowX.toStringAsFixed(1)} '
          '(여유 ${(0.6 * _k * s).toStringAsFixed(1)})',
        );
        if (ratio.abs() > 0.15) {
          failures.add(
            '${c.label}: 세로 중심 이탈 |ratio|='
            '${ratio.abs().toStringAsFixed(4)} > 0.15',
          );
        }
        if (overflowX > 0.6 * _k * s) {
          failures.add(
            '${c.label}: 글자가 캡슐 폭 초과 '
            '(${overflowX.toStringAsFixed(1)}px)',
          );
        }
        // #2068 오너 디자인 보존 축: 렌더 글자 **크기**를 직접 고정한다.
        // 중심 정렬 비율만 보면 글자가 통째로 축소·확대돼도(예: 맵 스케일 k를
        // 이중 적용해 0.455배) 게이트가 통과한다 — 실제로 v4에서 칩 글자가
        // 1.25배 부푼 채 ratio만 어긋났다. 잉크 높이를 오너 의도 렌더
        // fontSize(L×s×k = fontRender)에 대한 비율로 묶어 두 방향 모두 막는다.
        final inkHeight = (maxY - minY) / s;
        final inkRatio = inkHeight / c.fontRender;
        // ignore: avoid_print
        print(
          '[owner-chip-size] ${c.label}: inkHeight=${inkHeight.toStringAsFixed(2)} '
          'fontRender=${c.fontRender.toStringAsFixed(3)} '
          'ratio=${inkRatio.toStringAsFixed(3)} (기대 ${c.inkHeightRatio} ±0.10)',
        );
        if ((inkRatio - c.inkHeightRatio).abs() > 0.10) {
          failures.add(
            '${c.label}: 렌더 글자 크기 이탈 — 잉크 높이/의도 fontSize='
            '${inkRatio.toStringAsFixed(3)} (기대 ${c.inkHeightRatio} ±0.10). '
            '오너 의도 렌더 fontSize=${c.fontRender.toStringAsFixed(3)}',
          );
        }
      }

      // (B) 마곡 반전 배지: 원 반경 마스크 안 잉크 centroid(구 반전 버그 회귀 가드).
      for (final b in _discBadges) {
        final cx = t.tx + _k * b.cx;
        final cy = t.ty + _k * b.cy;
        final discRpx = b.discR * _k * s;
        final maskR = discRpx;
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
            if (data[o] > 200 && data[o + 1] > 200 && data[o + 2] > 200) {
              sy += py;
              cnt++;
            }
          }
        }
        img.dispose();
        if (cnt < 200) {
          failures.add('${b.label}: 잉크 픽셀 거의 없음(cnt=$cnt).');
          continue;
        }
        final ratio = ((sy / cnt) - h / 2) / s / (b.fontLocal * _k);
        // ignore: avoid_print
        print(
          '[disc-badge] ${b.label}: cnt=$cnt ratio=${ratio.toStringAsFixed(4)} '
          '(상한 ${b.tolerance})',
        );
        if (ratio.abs() > b.tolerance) {
          failures.add(
            '${b.label}: |ratio|=${ratio.abs().toStringAsFixed(4)} > ${b.tolerance}',
          );
        }
      }

      picture.dispose();
      expect(failures, isEmpty, reason: '종점 표현 렌더 이탈:\n${failures.join('\n')}');
    });
  });
}
