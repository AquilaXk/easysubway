import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import '../domain/map_camera.dart';
import '../infrastructure/route_map_svg_viewport.dart';

// 하이브리드 노선도 바탕층(#2068 트랙 2번째 PR).
//
// 오너 자작 SVG를 build-time 컴파일한 .vec(vector_graphics 바이너리)를 런타임
// 디코드해 바탕 [ui.Picture]를 얻고, 매 프레임은 카메라 transform + drawPicture만
// 재생한다. .vec의 좌표계는 원본 SVG viewBox(예: sma-v2 `0 0 2400 1800`)를 그대로
// 유지하므로, 인터랙션 좌표(station.position = route_map_positions)와 동일 원점·
// 동일 스케일이다 → designScale 곱셈/나눗셈 없이 카메라 변환만으로 1:1 정렬한다.
//
// [설계 결정: 병존] 이 위젯은 노선 형상과 오너 SVG의 기존 역·환승 심벌을 그리고,
// 구조화 painter는 충돌 회피 역명·뱃지를 같은 카메라 좌표계에 그린다.
// SVG의 제목·범례·역명·미개통 형상은 컴파일 입력에서 제외한다.

const kRouteMapBasemapRegionToId = kRouteMapSvgRegionToId;

String? routeMapBasemapAssetForRegion(String region) =>
    routeMapSvgAssetForRegion(region);

const TextStyle _attributionStyle = TextStyle(
  color: Color(0xFF466467),
  fontSize: 10,
);

/// Native SVG 위의 Flutter attribution overlay painter.
class RouteMapBasemapPainter extends CustomPainter {
  RouteMapBasemapPainter({
    required this.camera,
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    this.attributionPainter,
  });

  final MapCameraState camera;

  /// 오버레이·카메라의 geometry origin(#1970). Picture 재생을 origin-뺀 공간으로
  /// 맞춰 캔버스와 오버레이 좌표계를 일치시킨다.
  final Offset sourceOrigin;

  final String? attributionText;
  final TextPainter? attributionPainter;

  /// viewBox 점 P를 카메라 재생 후 화면(viewport) 좌표로 변환한다. paint()의
  /// 재생 변환과 동일한 단일 수식이며, `camera.sourceToViewportPoint(P −
  /// sourceOrigin)`와 항등이다(#2068 정렬 회귀 방지).
  @visibleForTesting
  Offset sourceToViewport(Offset viewBoxPoint) {
    final vc = camera.viewportSize.center(Offset.zero);
    return vc + (viewBoxPoint - sourceOrigin - camera.center) * camera.scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintAttribution(canvas, size); // 화면 고정.
  }

  void _paintAttribution(Canvas canvas, Size size) {
    final text = attributionText;
    final painter = attributionPainter;
    // painter는 State가 소유·재사용하는 캐시라 여기서 dispose하지 않는다(#1973).
    if (text == null || text.isEmpty || painter == null) {
      return;
    }
    const padding = 4.0;
    final origin = Offset(
      padding + 2,
      math.max(padding, size.height - painter.height - padding - 2),
    );
    final background = Rect.fromLTWH(
      origin.dx - 3,
      origin.dy - 2,
      painter.width + 6,
      painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(background, const Radius.circular(3)),
      Paint()..color = const Color(0xCCFFFFFF),
    );
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(RouteMapBasemapPainter oldDelegate) {
    return oldDelegate.camera.revision != camera.revision ||
        oldDelegate.sourceOrigin != sourceOrigin ||
        oldDelegate.attributionText != attributionText ||
        !identical(oldDelegate.attributionPainter, attributionPainter);
  }
}

/// 하이브리드 노선도 바탕층 뷰. canonical SVG는 native viewport가 그리고,
/// Flutter는 attribution overlay와 map interaction을 소유한다.
class RouteMapBasemapView extends StatefulWidget {
  const RouteMapBasemapView({
    required this.region,
    required this.camera,
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    this.onUnavailable,
    this.rendererKey,
    super.key,
  });

  /// 앱 region(한글). 매핑에 없으면 바탕 미표시(빈 화면).
  final String region;
  final MapCameraState camera;

  /// 오버레이·카메라의 geometry origin(#1970).
  final Offset sourceOrigin;

  final String? attributionText;
  final VoidCallback? onUnavailable;
  final String? rendererKey;

  @override
  State<RouteMapBasemapView> createState() => _RouteMapBasemapViewState();
}

class _RouteMapBasemapViewState extends State<RouteMapBasemapView> {
  TextPainter? _attributionPainter;
  String? _attributionPainterText;

  void _ensureAttributionPainter() {
    final text = widget.attributionText;
    if (text == null || text.isEmpty) {
      if (_attributionPainter != null) {
        _attributionPainter!.dispose();
        _attributionPainter = null;
        _attributionPainterText = null;
      }
      return;
    }
    if (_attributionPainterText == text && _attributionPainter != null) {
      return;
    }
    _attributionPainter?.dispose();
    _attributionPainter = TextPainter(
      text: TextSpan(text: text, style: _attributionStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _attributionPainterText = text;
  }

  @override
  void dispose() {
    _attributionPainter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureAttributionPainter();
    return Stack(
      fit: StackFit.expand,
      children: [
        RouteMapSvgViewport(
          key: ValueKey('${widget.region}:${widget.rendererKey}'),
          region: widget.region,
          camera: widget.camera,
          sourceOrigin: widget.sourceOrigin,
          onUnavailable: widget.onUnavailable ?? () {},
        ),
        IgnorePointer(
          child: CustomPaint(
            size: widget.camera.viewportSize,
            painter: RouteMapBasemapPainter(
              camera: widget.camera,
              sourceOrigin: widget.sourceOrigin,
              attributionText: widget.attributionText,
              attributionPainter: _attributionPainter,
            ),
          ),
        ),
      ],
    );
  }
}
