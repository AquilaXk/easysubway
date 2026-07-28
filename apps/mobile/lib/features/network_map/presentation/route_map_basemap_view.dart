import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import '../domain/map_camera.dart';
import '../infrastructure/route_map_svg_viewport.dart';

// 하이브리드 노선도 바탕층(#2068 트랙 2번째 PR).
//
// canonical SVG의 시각·텍스트·표장은 native viewport가 그대로 그리고, Flutter
// sibling은 station interaction overlay만 담당한다.

const kRouteMapBasemapRegionToId = kRouteMapSvgRegionToId;

String? routeMapBasemapAssetForRegion(String region) =>
    routeMapSvgAssetForRegion(region);

const TextStyle _attributionStyle = TextStyle(
  color: Color(0xFF466467),
  fontSize: 10,
);

/// Native SVG 위의 Flutter attribution overlay painter.
class RouteMapBasemapPainter extends CustomPainter {
  RouteMapBasemapPainter({this.attributionText, this.attributionPainter});

  final String? attributionText;
  final TextPainter? attributionPainter;

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
    return oldDelegate.attributionText != attributionText ||
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
    this.onFramePresented,
    this.overlay,
    super.key,
  });

  /// 앱 region(한글). 매핑에 없으면 onUnavailable을 거쳐 explicit unavailable을 보인다.
  final String region;
  final MapCameraState camera;

  /// 오버레이·카메라의 geometry origin(#1970).
  final Offset sourceOrigin;

  final String? attributionText;
  final VoidCallback? onUnavailable;
  final ValueChanged<int>? onFramePresented;
  final Widget? overlay;

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
    return RouteMapSvgViewport(
      key: ValueKey(widget.region),
      region: widget.region,
      camera: widget.camera,
      sourceOrigin: widget.sourceOrigin,
      onUnavailable: widget.onUnavailable ?? () {},
      onFramePresented: widget.onFramePresented,
      overlay: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              size: widget.camera.viewportSize,
              painter: RouteMapBasemapPainter(
                attributionText: widget.attributionText,
                attributionPainter: _attributionPainter,
              ),
            ),
          ),
          ?widget.overlay,
        ],
      ),
    );
  }
}
