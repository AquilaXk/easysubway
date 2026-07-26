import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_codec/vector_graphics_codec.dart';

// #2068 오너 종점 칩 **글자 크기·앵커** 게이트(컴파일 seoul.vec 직접 대조).
//
// [왜 다시 썼나] 종전 게이트는 seoul.vec을 래스터라이즈해 "흰 픽셀 = 글자 잉크"로
// 보고 잉크 bbox 높이를 **실측으로 맞춘 비율**(숫자 0.733·0.752, 한글 0.914)과
// 비교했다. 두 전제가 모두 무너졌다:
//   1) 전량 반입 계약(오너 최종 지시 "100% 동일하게")으로 오너 SVG의
//      `page-background`(전면 흰 rect)가 바탕층에 들어온다 — 크롭 전체가 흰색이라
//      잉크 판정이 의미를 잃는다(실측: 칩 3개의 잉크 비율이 모두 동일한 1.578).
//   2) 기대치 0.733/0.752/0.914는 제거된 `0.35 × fontSize` 보정 시대에 맞춘 값이라
//      새 계약에서 근거가 없다. 오너 원칙은 "맞춘 계수 금지"다.
//
// [무엇을 대신 보나] 래스터 대신 **.vec에 실린 값 자체를 오너 SVG에서 유도한 값과
// 대조**한다 — 배경·안티에일리어싱·폰트 렌더링에 의존하지 않는다.
//   (A) 글자 크기: `.vec` TextConfig.fontSize == 오너 SVG의 유효 로컬 font-size ×
//       그 텍스트의 조상 transform 누적 균일 스케일. #2068 반려 사유(칩 글자가 오너
//       값과 다른 크기로 렌더)를 정면으로 고정한다.
//   (B) 앵커 x: `.vec` 텍스트 위치 x == 오너 SVG 좌표에 조상 transform을 적용한 값.
//   (C) 세로 담김: baseline y가 **그 칩 자신의 캡슐 rect 세로 범위** 안에 있다.
//       캡슐에서 유도한 구조적 판정이라 맞춘 상수가 없다.
//
// 라벨 좌표 게이트(basemap_vec_label_position_gate_test)는 역명 라벨 레이어의
// **좌표**만 본다 — 칩 텍스트와 **font-size 축**은 이 게이트가 유일하게 덮는다.

const double _epsilon = 0.05;
const double _fontEpsilon = 0.001;

const _svgPath =
    '../../tools/route-map/route-map-defs/svg-sources/easy-subway-sma-v4.svg';
const _vecPath = 'assets/datapacks/metro_map_pack/basemap/seoul.vec';
const _chipLayerId = 'terminal-route-badges-layer';

// ── 최소 SVG 트리 파서(이 게이트 전용) ───────────────────────────────────────

final RegExp _tagPattern = RegExp(r'<(/?)([A-Za-z][\w:.\-]*)\b([^>]*?)(/?)>');

class _Element {
  _Element(this.name, this.attrs, this.start, this.openEnd, this.parent);

  final String name;
  final String attrs;
  final int start;
  final int openEnd;
  final _Element? parent;
  final List<_Element> children = <_Element>[];
  int innerEnd = -1;
}

_Element _parseElements(String svg) {
  final root = _Element('#root', '', 0, 0, null)..innerEnd = svg.length;
  final stack = <_Element>[root];
  for (final match in _tagPattern.allMatches(svg)) {
    if (match.group(1)!.isNotEmpty) {
      if (stack.length > 1) {
        stack.last.innerEnd = match.start;
        stack.removeLast();
      }
      continue;
    }
    final element = _Element(
      match.group(2)!,
      match.group(3)!,
      match.start,
      match.end,
      stack.last,
    );
    stack.last.children.add(element);
    if (match.group(4)!.isEmpty) {
      stack.add(element);
    } else {
      element.innerEnd = match.end;
    }
  }
  return root;
}

String? _attr(String attrs, String name) =>
    RegExp('(?:^|\\s)$name="([^"]*)"').firstMatch(attrs)?.group(1);

double? _length(String? raw) =>
    raw == null ? null : double.tryParse(raw.replaceAll('px', '').trim());

double? _firstCoordinate(String? value) {
  if (value == null) return null;
  final tokens = value.trim().split(RegExp(r'[\s,]+'));
  if (tokens.isEmpty || tokens.first.isEmpty) return null;
  return double.tryParse(tokens.first);
}

const List<double> _identity = <double>[1, 0, 0, 1, 0, 0];

List<double> _multiply(List<double> a, List<double> b) => <double>[
  a[0] * b[0] + a[2] * b[1],
  a[1] * b[0] + a[3] * b[1],
  a[0] * b[2] + a[2] * b[3],
  a[1] * b[2] + a[3] * b[3],
  a[0] * b[4] + a[2] * b[5] + a[4],
  a[1] * b[4] + a[3] * b[5] + a[5],
];

List<double> _transformMatrix(String? value) {
  if (value == null) return _identity;
  var matrix = _identity;
  for (final match in RegExp(r'([A-Za-z]+)\s*\(([^)]*)\)').allMatches(value)) {
    final args = match
        .group(2)!
        .trim()
        .split(RegExp(r'[,\s]+'))
        .map(double.parse)
        .toList();
    final List<double> step;
    switch (match.group(1)!) {
      case 'translate':
        step = <double>[1, 0, 0, 1, args[0], args.length > 1 ? args[1] : 0];
      case 'scale':
        step = <double>[
          args[0],
          0,
          0,
          args.length > 1 ? args[1] : args[0],
          0,
          0,
        ];
      case 'matrix':
        step = args;
      case 'rotate':
        final radians = args[0] * math.pi / 180;
        final rotation = <double>[
          math.cos(radians),
          math.sin(radians),
          -math.sin(radians),
          math.cos(radians),
          0,
          0,
        ];
        step = args.length >= 3
            ? _multiply(
                _multiply(<double>[1, 0, 0, 1, args[1], args[2]], rotation),
                <double>[1, 0, 0, 1, -args[1], -args[2]],
              )
            : rotation;
      default:
        throw StateError('게이트 파서가 모르는 transform: ${match.group(1)}');
    }
    matrix = _multiply(matrix, step);
  }
  return matrix;
}

/// 루트부터 [node] 자신까지의 transform 합성.
List<double> _chainMatrix(_Element node) {
  final chain = <_Element>[];
  for (_Element? p = node; p != null && p.name != '#root'; p = p.parent) {
    chain.insert(0, p);
  }
  var matrix = _identity;
  for (final element in chain) {
    matrix = _multiply(
      matrix,
      _transformMatrix(_attr(element.attrs, 'transform')),
    );
  }
  return matrix;
}

({double x, double y}) _apply(List<double> m, double x, double y) =>
    (x: m[0] * x + m[2] * y + m[4], y: m[1] * x + m[3] * y + m[5]);

/// 균일 스케일 성분(비균일·기울임이면 던진다 — 컴파일 파이프라인과 같은 전제).
double _uniformScale(List<double> m, String describe) {
  final sx = math.sqrt(m[0] * m[0] + m[1] * m[1]);
  final sy = math.sqrt(m[2] * m[2] + m[3] * m[3]);
  if ((sx - sy).abs() > 1e-9 * math.max(sx, 1)) {
    throw StateError('$describe: 균일 스케일이 아닌 transform이라 대조할 수 없습니다.');
  }
  return sx;
}

String _normalizeText(String raw) =>
    raw.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), '');

String _textOf(String svg, _Element element) =>
    _normalizeText(svg.substring(element.openEnd, element.innerEnd));

_Element _findById(_Element root, String id) {
  _Element? found;
  void walk(_Element node) {
    if (found != null) return;
    for (final child in node.children) {
      if (_attr(child.attrs, 'id') == id) {
        found = child;
        return;
      }
      walk(child);
      if (found != null) return;
    }
  }

  walk(root);
  final element = found;
  if (element == null) throw StateError('오너 SVG에서 id=$id를 찾지 못했습니다.');
  return element;
}

// ── font-size 캐스케이드 해석(게이트 독립 구현) ───────────────────────────────
//
// 칩 글자의 유효 로컬 font-size는 인라인 style · presentation attribute · `<style>`
// 규칙 중 하나에서 온다. SVG/CSS 명세상 우선순위는
//   presentation attribute < `<style>` 규칙(특이도·소스 순서) < 인라인 style
// 이다. 실제로 오너 수도권 칩 다수는 attribute `font-size="10.5"`만 갖고
// `.ui-chip text { font-size:12px }` 규칙이 그것을 이긴다 — attribute만 읽으면
// 게이트가 틀린 기대치를 만든다(실측으로 확인).
//
// 여기서는 **font-size를 선언하는 규칙만** 골라 자손 결합자 기반 단순 선택자를
// 해석한다. 그 문법 밖 선택자가 font-size를 선언하면 조용히 넘기지 않고 던진다.
class _FontSizeRule {
  _FontSizeRule(this.parts, this.specificity, this.order, this.value);

  /// 문서 앞→뒤 순서의 compound 목록(자손 결합자만).
  final List<({String? tag, String? id, List<String> classes})> parts;
  final int specificity;
  final int order;
  final double value;
}

({String? tag, String? id, List<String> classes}) _parseCompound(String raw) {
  String? tag;
  String? id;
  final classes = <String>[];
  final typeMatch = RegExp(r'^[A-Za-z][\w-]*').firstMatch(raw);
  var rest = raw;
  if (typeMatch != null) {
    tag = typeMatch.group(0);
    rest = raw.substring(typeMatch.end);
  }
  while (rest.isNotEmpty) {
    final match = RegExp(r'^([.#])([A-Za-z_][\w-]*)').firstMatch(rest);
    if (match == null) {
      throw StateError(
        'font-size를 선언하는 CSS 선택자에 이 게이트가 모르는 조각이 있습니다: "$raw" '
        '— 틀린 기대치를 만들지 않도록 실패합니다.',
      );
    }
    if (match.group(1) == '.') {
      classes.add(match.group(2)!);
    } else {
      id = match.group(2);
    }
    rest = rest.substring(match.end);
  }
  return (tag: tag, id: id, classes: classes);
}

List<_FontSizeRule> _fontSizeRules(String svg) {
  final css = RegExp(r'<style\b[^>]*>([\s\S]*?)</style>')
      .allMatches(svg)
      .map((m) => m.group(1)!)
      .join('\n')
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final rules = <_FontSizeRule>[];
  var order = 0;
  for (final block in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(css)) {
    final declaration = RegExp(
      r'(?:^|;)\s*font-size\s*:\s*([^;]+)',
    ).firstMatch(block.group(2)!);
    if (declaration == null) continue;
    final value = _length(declaration.group(1)!.trim());
    if (value == null) {
      throw StateError('해석할 수 없는 CSS font-size: "${declaration.group(1)}"');
    }
    for (final rawSelector in block.group(1)!.split(',')) {
      final selector = rawSelector.trim();
      if (selector.isEmpty) continue;
      if (RegExp(r'[>+~\[\]:]').hasMatch(selector)) {
        throw StateError(
          'font-size를 선언하는 선택자 "$selector"는 이 게이트의 자손 결합자 문법 밖입니다 '
          '— 실패합니다.',
        );
      }
      final parts = selector
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .map(_parseCompound)
          .toList();
      final specificity = parts.fold<int>(
        0,
        (sum, part) =>
            sum +
            (part.id != null ? 100 : 0) +
            part.classes.length * 10 +
            (part.tag != null ? 1 : 0),
      );
      rules.add(_FontSizeRule(parts, specificity, order++, value));
    }
  }
  return rules;
}

bool _matchesCompound(
  _Element node,
  ({String? tag, String? id, List<String> classes}) compound,
) {
  if (compound.tag != null && compound.tag != node.name) return false;
  if (compound.id != null && _attr(node.attrs, 'id') != compound.id) return false;
  if (compound.classes.isEmpty) return true;
  final classes = (_attr(node.attrs, 'class') ?? '')
      .split(RegExp(r'\s+'))
      .where((name) => name.isNotEmpty)
      .toSet();
  return compound.classes.every(classes.contains);
}

bool _matchesRule(_Element node, _FontSizeRule rule) {
  if (!_matchesCompound(node, rule.parts.last)) return false;
  var current = node.parent;
  for (var index = rule.parts.length - 2; index >= 0; index -= 1) {
    var found = false;
    while (current != null && current.name != '#root') {
      if (_matchesCompound(current, rule.parts[index])) {
        found = true;
        current = current.parent;
        break;
      }
      current = current.parent;
    }
    if (!found) return false;
  }
  return true;
}

/// SVG 명세 우선순위대로 유효 로컬 font-size를 정한다.
double? _effectiveFontSize(_Element node, List<_FontSizeRule> rules) {
  final inline = _attr(node.attrs, 'style');
  if (inline != null) {
    final declared = RegExp(
      r'(?:^|;)\s*font-size\s*:\s*([^;]+)',
    ).firstMatch(inline);
    if (declared != null) return _length(declared.group(1)!.trim());
  }
  _FontSizeRule? winner;
  for (final rule in rules) {
    if (!_matchesRule(node, rule)) continue;
    if (winner == null ||
        rule.specificity > winner.specificity ||
        (rule.specificity == winner.specificity && rule.order > winner.order)) {
      winner = rule;
    }
  }
  if (winner != null) return winner.value;
  return _length(_attr(node.attrs, 'font-size'));
}

// ── 대조 기대치(오너 SVG에서 유도) ────────────────────────────────────────────

class _Expectation {
  _Expectation({
    required this.label,
    required this.text,
    required this.anchorX,
    required this.fontSize,
    required this.capsuleTop,
    required this.capsuleBottom,
  });

  final String label;
  final String text;

  /// 조상 transform을 적용한 절대 앵커 x(.vec 텍스트 위치와 같은 좌표계).
  final double anchorX;

  /// 오너 유효 로컬 font-size × 누적 균일 스케일 = 렌더돼야 할 크기.
  final double fontSize;

  /// 이 텍스트가 담겨야 할 캡슐 rect의 세로 범위(절대 좌표).
  final double capsuleTop;
  final double capsuleBottom;
}

/// `<g>` 하나가 담은 `<text>`와 그 배경 rect로 기대치를 만든다.
List<_Expectation> _expectationsFrom(
  String svg,
  _Element group,
  List<_FontSizeRule> fontSizeRules,
) {
  final results = <_Expectation>[];
  void walk(_Element node) {
    final texts = node.children.where((c) => c.name == 'text').toList();
    if (texts.isNotEmpty) {
      final shapes = node.children.where((c) => c.name == 'rect').toList();
      if (shapes.isEmpty) {
        throw StateError(
          '텍스트를 담은 칩 그룹(${_attr(node.attrs, 'id') ?? 'id 없음'})에 캡슐 rect가 없어 '
          '세로 담김을 판정할 수 없습니다.',
        );
      }
      final shape = shapes.first;
      final shapeMatrix = _chainMatrix(shape);
      final shapeX = double.parse(_attr(shape.attrs, 'x')!);
      final shapeY = double.parse(_attr(shape.attrs, 'y')!);
      final shapeH = double.parse(_attr(shape.attrs, 'height')!);
      final top = _apply(shapeMatrix, shapeX, shapeY);
      final bottom = _apply(shapeMatrix, shapeX, shapeY + shapeH);
      for (final text in texts) {
        final matrix = _chainMatrix(text);
        final id = _attr(text.attrs, 'id') ?? 'id 없음';
        final scale = _uniformScale(matrix, id);
        final localFontSize = _effectiveFontSize(text, fontSizeRules);
        if (localFontSize == null) {
          throw StateError('$id: font-size 선언이 없어 렌더 크기를 유도할 수 없습니다.');
        }
        final x = _firstCoordinate(_attr(text.attrs, 'x'));
        final y = _firstCoordinate(_attr(text.attrs, 'y'));
        if (x == null || y == null) {
          throw StateError('$id: x·y 선언이 없어 앵커를 유도할 수 없습니다.');
        }
        results.add(
          _Expectation(
            label: id,
            text: _textOf(svg, text),
            anchorX: _apply(matrix, x, y).x,
            fontSize: localFontSize * scale,
            capsuleTop: math.min(top.y, bottom.y),
            capsuleBottom: math.max(top.y, bottom.y),
          ),
        );
      }
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  walk(group);
  return results;
}

// ── .vec 디코드(텍스트 위치 + fontSize) ──────────────────────────────────────

class _VecTextDraw {
  _VecTextDraw(this.text, this.x, this.y, this.fontSize);

  final String text;
  final double x;
  final double y;
  final double fontSize;
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

class _VecTextListener extends VectorGraphicsCodecListener {
  final List<_TextPositionRecord> _positions = <_TextPositionRecord>[];
  final Map<int, ({String text, double fontSize})> _texts =
      <int, ({String text, double fontSize})>{};
  final List<_VecTextDraw> draws = <_VecTextDraw>[];

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
      _VecTextDraw(config?.text ?? '', x, y, config?.fontSize ?? double.nan),
    );
  }

  // ── 대조에 쓰지 않는 명령 ──────────────────────────────────────────────────
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

List<_VecTextDraw> _vecTextDraws(String path) {
  final bytes = File(path).readAsBytesSync();
  final listener = _VecTextListener();
  const VectorGraphicsCodec().decode(ByteData.sublistView(bytes), listener);
  return listener.draws;
}

void main() {
  test('#2068 오너 종점 칩 글자 크기·앵커가 오너 SVG 값과 일치한다', () {
    final svg = File(_svgPath).readAsStringSync();
    final root = _parseElements(svg);
    final expectations = _expectationsFrom(
      svg,
      _findById(root, _chipLayerId),
      _fontSizeRules(svg),
    );
    expect(
      expectations,
      isNotEmpty,
      reason: '$_chipLayerId에서 칩 텍스트를 하나도 못 읽었다 — 게이트 파서가 죽었다',
    );

    final draws = _vecTextDraws(_vecPath);
    final failures = <String>[];
    var worstFontDelta = 0.0;
    var worstAnchorDelta = 0.0;

    for (final expectation in expectations) {
      final candidates = draws
          .where(
            (draw) =>
                !draw.claimed &&
                _normalizeText(draw.text) == expectation.text &&
                (draw.x - expectation.anchorX).abs() < _epsilon,
          )
          .toList();
      if (candidates.isEmpty) {
        failures.add(
          '${expectation.label}("${expectation.text}"): 앵커 x='
          '${expectation.anchorX.toStringAsFixed(3)}에 같은 글자의 .vec 텍스트가 없다.',
        );
        continue;
      }
      // 같은 x에 동명 칩이 여럿이면 자기 캡슐 안에 baseline이 있는 후보를 집는다.
      final draw = candidates.firstWhere(
        (candidate) =>
            candidate.y >= expectation.capsuleTop &&
            candidate.y <= expectation.capsuleBottom,
        orElse: () => candidates.first,
      );
      draw.claimed = true;

      final fontDelta = (draw.fontSize - expectation.fontSize).abs();
      worstFontDelta = math.max(worstFontDelta, fontDelta);
      worstAnchorDelta = math.max(
        worstAnchorDelta,
        (draw.x - expectation.anchorX).abs(),
      );
      if (fontDelta >= _fontEpsilon) {
        failures.add(
          '${expectation.label}("${expectation.text}"): 렌더 font-size 이탈 — '
          '.vec ${draw.fontSize.toStringAsFixed(4)} ↔ 오너 SVG 유도 '
          '${expectation.fontSize.toStringAsFixed(4)} '
          '(Δ=${fontDelta.toStringAsFixed(4)}).',
        );
      }
      if (draw.y < expectation.capsuleTop ||
          draw.y > expectation.capsuleBottom) {
        failures.add(
          '${expectation.label}("${expectation.text}"): baseline y='
          '${draw.y.toStringAsFixed(3)}가 캡슐 세로 범위 '
          '[${expectation.capsuleTop.toStringAsFixed(3)}, '
          '${expectation.capsuleBottom.toStringAsFixed(3)}] 밖이다 — 글자가 배지를 벗어난다.',
        );
      }
    }

    // ignore: avoid_print
    print(
      '[basemap-chip-text] 칩 텍스트 ${expectations.length}건 대조 · '
      '최대 font-size Δ ${worstFontDelta.toStringAsFixed(6)} · '
      '최대 앵커 Δ ${worstAnchorDelta.toStringAsFixed(6)}',
    );
    expect(
      failures,
      isEmpty,
      reason:
          '오너 종점 칩 글자가 오너 SVG 값과 다르게 컴파일됐다 — #2068 반려 사유 그대로다:\n'
          '${failures.join('\n')}',
    );
  });
}
