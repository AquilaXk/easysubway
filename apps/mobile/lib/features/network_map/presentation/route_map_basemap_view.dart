import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../domain/map_camera.dart';

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

/// `widget.data.selectedRegion`(한글) → manifest map id. .vec 자산 파일명 결정.
/// 매핑에 없는 region은 basemap 미표시(빈 화면)로 안전 폴백한다(크래시 금지).
const Map<String, String> kRouteMapBasemapRegionToId = {
  '수도권': 'seoul',
  '부산': 'busan',
  '광주': 'gwangju',
  '대구': 'daegu',
  '대전': 'daejeon',
};

/// region → .vec 자산 경로. 매핑에 없으면 null(바탕 미표시 폴백).
String? routeMapBasemapAssetForRegion(String region) {
  final id = kRouteMapBasemapRegionToId[region];
  return id == null ? null : 'assets/datapacks/metro_map_pack/basemap/$id.vec';
}

const TextStyle _attributionStyle = TextStyle(
  color: Color(0xFF466467),
  fontSize: 10,
);

/// 바탕 .vec [picture]를 카메라 transform으로 재생한다(재생 전용).
/// vec는 viewBox=source 좌표라 structured painter와 달리 designScale로 나누지
/// 않는다 — translate 동일 + `canvas.scale(camera.scale)` + drawPicture.
class RouteMapBasemapPainter extends CustomPainter {
  RouteMapBasemapPainter({
    required this.picture,
    required this.camera,
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    this.attributionPainter,
  });

  /// 디코드된 바탕 Picture. 로드 완료 전에는 null이라 바탕을 그리지 않는다.
  final ui.Picture? picture;
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
    final basemap = picture;
    if (basemap != null) {
      canvas.save();
      final vc = camera.viewportSize.center(Offset.zero);
      // viewport = vc + (viewBox − sourceOrigin − camera.center)·scale.
      // vec는 viewBox=source 좌표라 designScale 배율이 없다.
      canvas.translate(
        vc.dx - (camera.center.dx + sourceOrigin.dx) * camera.scale,
        vc.dy - (camera.center.dy + sourceOrigin.dy) * camera.scale,
      );
      canvas.scale(camera.scale);
      canvas.drawPicture(basemap);
      canvas.restore();
    }
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
        !identical(oldDelegate.picture, picture) ||
        oldDelegate.sourceOrigin != sourceOrigin ||
        oldDelegate.attributionText != attributionText ||
        !identical(oldDelegate.attributionPainter, attributionPainter);
  }
}

/// 하이브리드 노선도 바탕층 뷰. [region]에 매핑된 .vec를 런타임 디코드해
/// [ui.Picture]를 State에 캐시하고(region 변경 시에만 재로드), 카메라 변경 시
/// transform만 재생한다.
class RouteMapBasemapView extends StatefulWidget {
  const RouteMapBasemapView({
    required this.region,
    required this.camera,
    this.sourceOrigin = Offset.zero,
    this.attributionText,
    super.key,
  });

  /// 앱 region(한글). 매핑에 없으면 바탕 미표시(빈 화면).
  final String region;
  final MapCameraState camera;

  /// 오버레이·카메라의 geometry origin(#1970).
  final Offset sourceOrigin;

  final String? attributionText;

  @override
  State<RouteMapBasemapView> createState() => _RouteMapBasemapViewState();
}

class _RouteMapBasemapViewState extends State<RouteMapBasemapView> {
  ui.Picture? _picture;
  String? _loadedAsset;
  // 진행 중 로드 토큰. region이 로드 완료 전에 바뀌면 stale 결과를 버린다.
  Object? _loadToken;
  TextPainter? _attributionPainter;
  String? _attributionPainterText;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // initState가 아닌 여기서 로드한다(로드가 inherited widget에 의존할 수 있으므로).
    // region 미변경 시 _ensureBasemap이 조기 반환해 중복 로드가 없다.
    _ensureBasemap();
  }

  @override
  void didUpdateWidget(RouteMapBasemapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.region != widget.region) {
      _ensureBasemap();
    }
  }

  void _ensureBasemap() {
    final asset = routeMapBasemapAssetForRegion(widget.region);
    if (_loadedAsset == asset && (asset == null || _picture != null)) {
      return;
    }
    // 매핑에 없는 region: 바탕 미표시로 안전 폴백(크래시 금지).
    if (asset == null) {
      _loadToken = null;
      _loadedAsset = null;
      final previous = _picture;
      _picture = null;
      previous?.dispose();
      return;
    }
    final token = Object();
    _loadToken = token;
    _loadedAsset = asset;
    // context=null: 바탕은 정적 도식이라 locale/textDirection 의존이 없고, null을
    // 넘겨 inherited widget 의존(및 그로 인한 재로드)을 피한다(플랫폼 로케일·LTR 폴백).
    vg
        .loadPicture(AssetBytesLoader(asset), null)
        .then((info) {
          if (!mounted || !identical(_loadToken, token)) {
            info.picture.dispose();
            return;
          }
          setState(() {
            _picture?.dispose();
            _picture = info.picture;
          });
        })
        .catchError((Object error, StackTrace stack) {
          // 로드 실패 시 바탕만 비고 인터랙션은 계속 동작한다(무해 폴백).
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'network_map',
              context: ErrorDescription('노선도 바탕 .vec 로드 실패($asset)'),
            ),
          );
        });
  }

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
    _loadToken = null;
    _picture?.dispose();
    _attributionPainter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureAttributionPainter();
    // RepaintBoundary로 바탕 레이어를 형제 오버레이 rebuild와 분리한다.
    // isComplex/willChange 힌트로 정적 Picture 재생 레이어의 raster 캐싱을 돕는다.
    return RepaintBoundary(
      child: CustomPaint(
        size: widget.camera.viewportSize,
        isComplex: true,
        willChange: true,
        painter: RouteMapBasemapPainter(
          picture: _picture,
          camera: widget.camera,
          sourceOrigin: widget.sourceOrigin,
          attributionText: widget.attributionText,
          attributionPainter: _attributionPainter,
        ),
      ),
    );
  }
}
