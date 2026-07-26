import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics_codec/vector_graphics_codec.dart';

// #2068 바탕층 역명 라벨 좌표 대조 게이트 — **오너 SVG 원본 좌표 ↔ 컴파일 .vec
// 좌표**를 5권역 전수로 기계 대조한다.
//
// 배경(2026-07-26 실측): vector_graphics_compiler 1.2.6의
// `TextPositionNode.computeTextPosition`은 그 노드가 x·y(또는 dx·dy)를 **둘 다**
// 선언했을 때만 조상 transform을 좌표로 흡수한다. 오너 라벨 마크업
// `<text x y><tspan x dy="0">역명</tspan></text>`은 부모만 흡수하고 자식은
// transform을 .vec에 그대로 실어, vector_graphics 1.2.2 런타임
// (`_flushPendingTextChunk`의 `canvas.transform`)이 같은 변환을 한 번 더 적용했다
// — 대전 라벨 22건이 map wrapper translate(0 88)를 두 번 먹어 +88px, 부산 라벨
// 런 60건이 라벨 자신의 translate를 두 번 먹어 최대 +968px 어긋났다(컴파일 입력
// 기준 교정 대상 tspan은 대전 22·부산 63 — 중첩 tspan 라벨은 런보다 tspan이 많다).
//
// 종전 게이트(tools/route-map/basemap-svg-fidelity-gate.test.mjs)는 라벨이
// 바탕층에 **들어갔는지**(텍스트 전수)와 labels.json 앵커만 봤고, .vec에 실린
// 텍스트가 **어디에 그려지는지**는 아무도 보지 않았다 — 그래서 이중 적용이
// green으로 통과했다. 이 게이트가 그 구멍을 메운다.
//
// 대조 방식:
//   (1) 오너 SVG의 역명 라벨 레이어를 독립 파서로 훑어 텍스트 런(=`<text>` 또는
//       그 안의 `<tspan>`)마다 절대 앵커를 계산한다(조상·자신 transform 전체를
//       행렬로 합성).
//   (2) 컴파일 산출 .vec를 vector_graphics_codec으로 디코드하고
//       vector_graphics 1.2.2 런타임의 텍스트 위치 갱신 규칙을 그대로 재현해
//       각 draw의 최종 앵커(텍스트 transform 적용 후)를 얻는다.
//   (3) (1)의 모든 런이 같은 글자·같은 좌표(ε)로 (2)에 1:1로 존재해야 한다.
//
// 한계(의도): .vec 쪽 앵커는 각 런이 자기 x를 선언한다는 전제로 청크 원점을
// 그리기 시점의 펜 x로 본다. 글리프 진행폭에 의존하는 "계속 청크"가 생기면 좌표가
// 어긋나 이 게이트가 red가 된다 — 조용히 통과하지 않는다.

const _epsilon = 0.05;

const _svgSourceDir = '../../tools/route-map/route-map-defs/svg-sources';
const _basemapDir = 'assets/datapacks/metro_map_pack/basemap';

const _regions = <({String id, String svg})>[
  (id: 'seoul', svg: 'easy-subway-sma-v4.svg'),
  (id: 'busan', svg: 'easy-subway-busan-v3.svg'),
  (id: 'daegu', svg: 'easy-subway-daegu-v3.svg'),
  (id: 'daejeon', svg: 'easy-subway-daejeon-v3.svg'),
  (id: 'gwangju', svg: 'easy-subway-gwangju-v3.svg'),
];

// 실측 기준선(2026-07-26). svgRuns는 오너 SVG 역명 라벨 레이어의 텍스트 런 수,
// vecTexts는 .vec에 실린 텍스트 draw **전체** 수(라벨 + 배지·중간표기·칩 글자,
// paint-order 분해 사본 포함)다. 좌표 대조만으로는 잡히지 않는 "조용한 누락·중복
// 반입"을 개수로 못 박는다.
const _expectedCounts = <String, ({int svgRuns, int vecTexts})>{
  'seoul': (svgRuns: 729, vecTexts: 1057),
  'busan': (svgRuns: 155, vecTexts: 342),
  'daegu': (svgRuns: 104, vecTexts: 226),
  // 대전·광주는 `#station-name-labels-layer text { paint-order:stroke; stroke:#FFFFFF; … }`
  // 규칙이 자손 결합자라 종전 CSS 인라이너가 통째로 버렸다 — 라벨 halo가 조용히
  // 빠져 있었다. 캐스케이드를 사양대로 전개하면서 라벨 전량이 halo/글자 두 사본으로
  // 분해돼 .vec 텍스트 draw가 22·20건씩 늘었다(라벨 런 수는 그대로).
  'daejeon': (svgRuns: 22, vecTexts: 47),
  'gwangju': (svgRuns: 20, vecTexts: 42),
};

// ── 독립 SVG 파서(게이트 전용) ───────────────────────────────────────────────

final RegExp _tagPattern = RegExp(r'<(/?)([A-Za-z][\w:.\-]*)\b([^>]*?)(/?)>');

class _Element {
  _Element(this.name, this.attrs, this.start, this.openEnd, this.parent);

  final String name;
  final String attrs;
  final int start;
  final int openEnd;
  final _Element? parent;
  final List<_Element> children = <_Element>[];

  /// 여는 태그와 닫는 태그 사이 본문의 끝(자기폐쇄면 [openEnd]).
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

/// 글리프별 좌표 리스트(`x="10 20 30"`)는 첫 토큰만 쓴다(컴파일 입력 정규화와 동일).
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

String _normalizeText(String raw) =>
    raw.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), '');

bool _isHidden(String attrs) =>
    _attr(attrs, 'display') == 'none' ||
    RegExp(r'display\s*:\s*none').hasMatch(_attr(attrs, 'style') ?? '');

bool _isUnbuilt(String attrs) =>
    RegExp(r'data-(?:status|state)="(?:construction|planned)"').hasMatch(attrs);

/// 오너 SVG 역명 라벨 레이어의 텍스트 런 전수(절대 앵커).
class _SvgRun {
  _SvgRun(this.text, this.x, this.y);

  final String text;
  final double x;
  final double y;
}

String _labelLayerId(String svg) {
  if (svg.contains('id="station-name-labels-layer"')) {
    return 'station-name-labels-layer';
  }
  final match = RegExp(
    r'<g\b(?=[^>]*\bclass="[^"]*\blabel-layer\b[^"]*")[^>]*\bid="([^"]+)"',
  ).firstMatch(svg);
  if (match == null) {
    throw StateError('역명 라벨 레이어를 찾지 못했습니다.');
  }
  return match.group(1)!;
}

_Element _findLayer(_Element root, String layerId) {
  _Element? found;
  void walk(_Element node) {
    if (found != null) return;
    for (final child in node.children) {
      if (child.name == 'g' && _attr(child.attrs, 'id') == layerId) {
        found = child;
        return;
      }
      walk(child);
      if (found != null) return;
    }
  }

  walk(root);
  final layer = found;
  if (layer == null) {
    throw StateError('역명 라벨 레이어 $layerId 노드를 찾지 못했습니다.');
  }
  return layer;
}

List<_SvgRun> _svgLabelRuns(
  String svg,
  List<String> failures,
  String regionId,
) {
  final root = _parseElements(svg);
  final layer = _findLayer(root, _labelLayerId(svg));
  final runs = <_SvgRun>[];

  bool hiddenChain(_Element node) {
    for (_Element? p = node; p != null && p != layer.parent; p = p.parent) {
      if (_isHidden(p.attrs)) return true;
    }
    return false;
  }

  bool unbuiltChain(_Element node) {
    for (_Element? p = node; p != null && p != layer.parent; p = p.parent) {
      if (_isUnbuilt(p.attrs)) return true;
    }
    return false;
  }

  void walk(_Element node) {
    for (final child in node.children) {
      if (child.name != 'text') {
        walk(child);
        continue;
      }
      if (hiddenChain(child) || unbuiltChain(child)) continue;
      // SVG 텍스트 펜은 `<text>` 하나 안에서 이어진다(중첩 tspan 포함). 각 요소의
      // **직접 문자 데이터**만 하나의 런으로 낸다 — 컴파일러도 텍스트를 담은
      // 요소마다 draw 하나를 내므로(중첩 tspan의 바깥 껍데기는 draw가 없다)
      // 이렇게 세야 1:1이 성립한다(수도권 총신대입구·부산 벡스코·광주 광주송정역이
      // 실제로 중첩 tspan을 쓴다).
      var penX = _firstCoordinate(_attr(child.attrs, 'x'));
      var penY = _firstCoordinate(_attr(child.attrs, 'y'));

      void emit(_Element node) {
        final text = _directText(svg, node);
        if (text.isNotEmpty) {
          if (penX == null || penY == null) {
            failures.add(
              '$regionId/$text: 절대 x·y를 계산할 수 없습니다 '
              '(직전 글리프 진행폭 의존 — 게이트 파서 확장 필요).',
            );
          } else {
            final point = _apply(_chainMatrix(node), penX!, penY!);
            runs.add(_SvgRun(text, point.x, point.y));
          }
        }
        for (final tspan in node.children) {
          if (tspan.name != 'tspan') continue;
          if (tspan.innerEnd == tspan.openEnd) continue; // 자기폐쇄 — 내용 없음.
          final x = _firstCoordinate(_attr(tspan.attrs, 'x')) ?? penX;
          final y = _firstCoordinate(_attr(tspan.attrs, 'y')) ?? penY;
          final dx = _firstCoordinate(_attr(tspan.attrs, 'dx')) ?? 0;
          final dy = _firstCoordinate(_attr(tspan.attrs, 'dy')) ?? 0;
          penX = x == null ? null : x + dx;
          penY = y == null ? null : y + dy;
          emit(tspan);
        }
      }

      emit(child);
    }
  }

  walk(layer);
  return runs;
}

/// [element]의 **직접** 문자 데이터(자식 요소 내용 제외)를 공백 제거해 돌려준다.
String _directText(String svg, _Element element) {
  final buffer = StringBuffer();
  var cursor = element.openEnd;
  for (final child in element.children) {
    if (child.start < cursor) continue;
    buffer.write(svg.substring(cursor, child.start));
    cursor = child.innerEnd == child.openEnd
        ? child.openEnd
        : child.innerEnd + child.name.length + 3; // `</name>`
  }
  if (cursor < element.innerEnd) {
    buffer.write(svg.substring(cursor, element.innerEnd));
  }
  return _normalizeText(buffer.toString());
}

// ── .vec 디코드 + vector_graphics 런타임 텍스트 위치 재현 ────────────────────

class _VecDraw {
  _VecDraw(this.text, this.x, this.y);

  final String text;
  final double x;
  final double y;
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
  final Map<int, String> _texts = <int, String>{};
  final List<_VecDraw> draws = <_VecDraw>[];

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
    _texts[id] = text;
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
    draws.add(_VecDraw(_texts[textId] ?? '', x, y));
  }

  // ── 좌표 대조에 쓰지 않는 명령 ─────────────────────────────────────────────
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

List<_VecDraw> _vecTextDraws(String path) {
  final bytes = File(path).readAsBytesSync();
  final listener = _VecTextListener();
  const VectorGraphicsCodec().decode(ByteData.sublistView(bytes), listener);
  return listener.draws;
}

void main() {
  test('#2068 오너 SVG 역명 라벨 좌표 ↔ 컴파일 .vec 좌표 5권역 전수 대조', () {
    final failures = <String>[];
    final summary = <String>[];

    for (final region in _regions) {
      final svg = File('$_svgSourceDir/${region.svg}').readAsStringSync();
      final runs = _svgLabelRuns(svg, failures, region.id);
      expect(
        runs,
        isNotEmpty,
        reason: '${region.id}: 오너 SVG에서 역명 라벨 런을 하나도 못 읽었다 — 파서가 죽었다',
      );

      final draws = _vecTextDraws('$_basemapDir/${region.id}.vec');
      final byText = <String, List<_VecDraw>>{};
      for (final draw in draws) {
        byText
            .putIfAbsent(_normalizeText(draw.text), () => <_VecDraw>[])
            .add(draw);
      }

      var worst = 0.0;
      var mismatched = 0;
      for (final run in runs) {
        final candidates = byText[run.text] ?? const <_VecDraw>[];
        _VecDraw? best;
        var bestDistance = double.infinity;
        for (final candidate in candidates) {
          if (candidate.claimed) continue;
          final distance =
              ((candidate.x - run.x).abs() + (candidate.y - run.y).abs());
          if (distance < bestDistance) {
            bestDistance = distance;
            best = candidate;
          }
        }
        if (best == null) {
          mismatched += 1;
          failures.add(
            '${region.id}/${run.text}: .vec에 같은 글자의 미사용 텍스트가 없다 '
            '(SVG 앵커 ${run.x.toStringAsFixed(3)}, ${run.y.toStringAsFixed(3)}).',
          );
          continue;
        }
        final dx = best.x - run.x;
        final dy = best.y - run.y;
        worst = worst > bestDistance ? worst : bestDistance;
        if (dx.abs() >= _epsilon || dy.abs() >= _epsilon) {
          // ε 밖 후보는 **claim하지 않는다** — 잘못 짝지어진 draw를 소비해 버리면
          // 뒤따르는 동명 런이 연쇄로 실패해 원인이 흐려진다. 실패만 기록하고
          // 후보는 남겨 둔다(정상 데이터에서는 런마다 ε 안 후보가 정확히 하나라
          // 순회 순서와 무관하게 결과가 같다).
          mismatched += 1;
          if (mismatched <= 5) {
            failures.add(
              '${region.id}/${run.text}: SVG 원본 '
              '(${run.x.toStringAsFixed(3)}, ${run.y.toStringAsFixed(3)}) ↔ '
              '.vec (${best.x.toStringAsFixed(3)}, ${best.y.toStringAsFixed(3)}) '
              'Δ=(${dx.toStringAsFixed(3)}, ${dy.toStringAsFixed(3)})',
            );
          }
          continue;
        }
        best.claimed = true;
      }
      if (mismatched > 5) {
        failures.add('${region.id}: 좌표 불일치 총 $mismatched건(위 5건만 표시).');
      }

      // 역방향 고정: SVG 라벨 런 수와 .vec 텍스트 draw 수를 실측 기준선으로 못
      // 박는다. "짝을 못 찾은 draw가 있으면 실패"로는 잡을 수 없다 — .vec에는
      // 역명 라벨 말고도 노선 번호 배지·중간 표기·종점 칩 글자가 있고, #2584의
      // paint-order 분해가 halo/글자 두 사본을 내므로 라벨 하나가 draw 둘이 되는
      // 권역도 있다(busan·daegu). 그래서 "잉여 draw = 실패"가 아니라 **개수 자체를
      // 고정**해, 라벨이 조용히 사라지거나 텍스트가 중복 반입되면 red가 되게 한다.
      // 오너가 SVG에 역을 추가·삭제하면 여기도 함께 실측으로 갱신한다.
      final expected = _expectedCounts[region.id]!;
      if (runs.length != expected.svgRuns ||
          draws.length != expected.vecTexts) {
        failures.add(
          '${region.id}: 텍스트 개수 기준선 이탈 — SVG 라벨 런 ${runs.length}건'
          '(기준 ${expected.svgRuns}) / .vec 텍스트 ${draws.length}건'
          '(기준 ${expected.vecTexts}). 라벨이 빠졌는지·중복 반입됐는지 먼저 규명하고 '
          '정당한 변화면 기준선을 실측으로 갱신하세요.',
        );
      }
      summary.add(
        '${region.id}: SVG 라벨 런 ${runs.length}건 / .vec 텍스트 ${draws.length}건 '
        '/ 최대 Δ ${worst.toStringAsFixed(4)}',
      );
    }

    // ignore: avoid_print
    print('[basemap-vec-label-position] ${summary.join(' · ')}');
    expect(
      failures,
      isEmpty,
      reason:
          '오너 SVG 라벨 좌표와 컴파일 .vec 좌표가 어긋났다 — 바탕층이 오너 도식과 다른 '
          '자리에 역명을 그린다:\n${failures.join('\n')}',
    );
  });
}
