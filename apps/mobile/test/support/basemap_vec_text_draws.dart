import 'dart:io';
import 'dart:typed_data';

import 'package:vector_graphics_codec/vector_graphics_codec.dart';

/// 컴파일 산출 `.vec`에서 **텍스트 draw 명령**을 문서 순서대로 뽑는다.
///
/// vector_graphics 1.2.2 런타임(`listener.dart`)의 텍스트 위치 갱신 규칙을 그대로
/// 재현해 각 draw의 최종 앵커를 계산한다 — 래스터라이즈에 의존하지 않으므로 배경·
/// 안티에일리어싱·폰트 렌더링과 무관하게 결정적이다.
///
/// 여러 바탕층 게이트가 같은 디코드를 필요로 해 여기 한 벌만 둔다.
class BasemapVecTextDraw {
  BasemapVecTextDraw({
    required this.index,
    required this.text,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.hasFill,
    required this.hasStroke,
  });

  /// .vec 안에서의 그리기 순서(0부터).
  final int index;
  final String text;
  final double x;
  final double y;
  final double fontSize;

  /// fill paint로 그려지는 draw인가(paint-order 분해의 "글자" 사본).
  final bool hasFill;

  /// stroke paint로 그려지는 draw인가(paint-order 분해의 "halo" 사본).
  final bool hasStroke;

  /// 게이트가 1:1 대조에서 이미 소비한 draw인지 표시하는 작업용 플래그.
  bool claimed = false;
}

class _TextPositionRecord {
  _TextPositionRecord(
    this.x,
    this.y,
    this.dx,
    this.dy,
    this.reset,
    this.transform,
  );

  final double? x;
  final double? y;
  final double? dx;
  final double? dy;
  final bool reset;
  final Float64List? transform;
}

class _TextDrawListener extends VectorGraphicsCodecListener {
  final List<_TextPositionRecord> _positions = <_TextPositionRecord>[];
  final Map<int, ({String text, double fontSize})> _texts =
      <int, ({String text, double fontSize})>{};
  final List<BasemapVecTextDraw> draws = <BasemapVecTextDraw>[];

  double? _penX;
  double _penY = 0;
  Float64List? _transform;

  @override
  void onTextPosition(
    int textPositionId,
    double? x,
    double? y,
    double? dx,
    double? dy,
    bool reset,
    Float64List? transform,
  ) {
    _positions.add(_TextPositionRecord(x, y, dx, dy, reset, transform));
  }

  @override
  void onUpdateTextPosition(int textPositionId) {
    final position = _positions[textPositionId];
    if (position.reset) {
      _penX = 0;
      _penY = 0;
    }
    if (position.x != null) _penX = position.x;
    if (position.y != null) _penY = position.y!;
    if (position.dx != null) _penX = (_penX ?? 0) + position.dx!;
    if (position.dy != null) _penY = _penY + position.dy!;
    _transform = position.transform;
  }

  @override
  void onTextConfig(
    String text,
    String? fontFamily,
    double xAnchorMultiplier,
    int fontWeight,
    double fontSize,
    int decoration,
    int decorationStyle,
    int decorationColor,
    int id,
  ) {
    _texts[id] = (text: text, fontSize: fontSize);
  }

  @override
  void onDrawText(int textId, int? fillId, int? strokeId, int? patternId) {
    var x = _penX ?? 0;
    var y = _penY;
    final transform = _transform;
    if (transform != null) {
      // 런타임은 그리기 직전 canvas.transform(4x4 열 우선)을 적용한다.
      final tx = transform[0] * x + transform[4] * y + transform[12];
      final ty = transform[1] * x + transform[5] * y + transform[13];
      x = tx;
      y = ty;
    }
    final config = _texts[textId];
    draws.add(
      BasemapVecTextDraw(
        index: draws.length,
        text: config?.text ?? '',
        x: x,
        y: y,
        fontSize: config?.fontSize ?? double.nan,
        hasFill: fillId != null,
        hasStroke: strokeId != null,
      ),
    );
  }

  // ── 텍스트 대조에 쓰지 않는 명령 ───────────────────────────────────────────
  @override
  void onSize(double width, double height) {}
  @override
  void onPaintObject({
    required int color,
    required int? strokeCap,
    required int? strokeJoin,
    required int blendMode,
    required double? strokeMiterLimit,
    required double? strokeWidth,
    required int paintStyle,
    required int id,
    required int? shaderId,
  }) {}
  @override
  void onPathStart(int id, int fillType) {}
  @override
  void onPathMoveTo(double x, double y) {}
  @override
  void onPathLineTo(double x, double y) {}
  @override
  void onPathCubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {}
  @override
  void onPathClose() {}
  @override
  void onPathFinished() {}
  @override
  void onDrawPath(int pathId, int? paintId, int? patternId) {}
  @override
  void onDrawVertices(
    Float32List vertices,
    Uint16List? indices,
    int? paintId,
  ) {}
  @override
  void onSaveLayer(int paintId) {}
  @override
  void onClipPath(int pathId) {}
  @override
  void onRestoreLayer() {}
  @override
  void onMask() {}
  @override
  void onRadialGradient(
    double centerX,
    double centerY,
    double radius,
    double? focalX,
    double? focalY,
    Int32List colors,
    Float32List? offsets,
    Float64List? transform,
    int tileMode,
    int id,
  ) {}
  @override
  void onLinearGradient(
    double fromX,
    double fromY,
    double toX,
    double toY,
    Int32List colors,
    Float32List? offsets,
    int tileMode,
    int id,
  ) {}
  @override
  void onImage(
    int imageId,
    int format,
    Uint8List data, {
    VectorGraphicsErrorListener? onError,
  }) {}
  @override
  void onDrawImage(
    int imageId,
    double x,
    double y,
    double width,
    double height,
    Float64List? transform,
  ) {}
  @override
  void onPatternStart(
    int patternId,
    double x,
    double y,
    double width,
    double height,
    Float64List transform,
  ) {}
}

/// [path]의 `.vec`를 디코드해 텍스트 draw를 그리기 순서대로 돌려준다.
List<BasemapVecTextDraw> basemapVecTextDraws(String path) {
  final bytes = File(path).readAsBytesSync();
  final listener = _TextDrawListener();
  const VectorGraphicsCodec().decode(ByteData.sublistView(bytes), listener);
  return listener.draws;
}
