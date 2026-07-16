import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;

import '../../../design_tokens.dart';
import '../../route_draft/domain/route_draft.dart';
import 'station_fan_menu_geometry.dart';

/// 팬 메뉴의 논리 섹터. 닫기는 슬롯이 아니므로 별도 값으로 둔다.
enum _FanSector { departure, waypoint, arrival, close }

RouteDraftSlot? _slotFor(_FanSector sector) => switch (sector) {
  _FanSector.departure => RouteDraftSlot.origin,
  _FanSector.waypoint => RouteDraftSlot.waypoint,
  _FanSector.arrival => RouteDraftSlot.destination,
  _FanSector.close => null,
};

String _semanticsLabel(_FanSector sector) => switch (sector) {
  _FanSector.departure => '출발역으로 설정',
  _FanSector.waypoint => '경유지로 추가',
  _FanSector.arrival => '도착역으로 설정',
  _FanSector.close => '메뉴 닫기',
};

/// 각 섹터 Semantics 노드의 활성 rect(design 좌표). 섹터 Path의 getBounds()
/// 사각형은 인접 섹터끼리 크게 겹쳐 explore-by-touch가 안내와 다른 섹터를
/// 실행할 수 있다(#2109 리뷰). 그래서 접근성 노드 rect는 각 섹터의
/// 아이콘·라벨 코어 주변으로 좁힌 비겹침 사각형으로 둔다. 실제 포인터
/// 히트테스트(Listener + path.contains)는 이 값을 쓰지 않으므로 정확한 부채꼴
/// 경계를 그대로 유지한다.
const Map<_FanSector, Rect> _sectorSemanticsCore = {
  _FanSector.departure: Rect.fromLTWH(92, 122, 153, 153),
  _FanSector.waypoint: Rect.fromLTWH(285, 62, 153, 153),
  _FanSector.arrival: Rect.fromLTWH(478, 122, 153, 153),
  _FanSector.close: Rect.fromLTWH(285, 227, 153, 153),
};

/// State(히트테스트)와 Painter(렌더)가 같은 섹터→Path 매핑을 공유하도록
/// 단일 top-level 헬퍼로 둔다.
Path _pathForSector(StationFanMenuGeometry geometry, _FanSector sector) =>
    switch (sector) {
      _FanSector.departure => geometry.departure,
      _FanSector.waypoint => geometry.waypoint,
      _FanSector.arrival => geometry.arrival,
      _FanSector.close => geometry.close,
    };

/// 섹터가 비활성인지 판정(닫기는 슬롯이 없어 항상 활성). State·Painter 공유.
bool _sectorDisabled(Set<RouteDraftSlot> disabledSlots, _FanSector sector) {
  final slot = _slotFor(sector);
  return slot != null && disabledSlots.contains(slot);
}

class StationFanMenu extends StatefulWidget {
  const StationFanMenu({
    super.key,
    required this.width,
    required this.selectedSlots,
    required this.disabledSlots,
    required this.onAction,
    required this.onClose,
    this.fontFamily,
  });

  final double width;
  final Set<RouteDraftSlot> selectedSlots;
  final Set<RouteDraftSlot> disabledSlots;
  final ValueChanged<RouteDraftSlot> onAction;
  final VoidCallback onClose;
  final String? fontFamily;

  @override
  State<StationFanMenu> createState() => _StationFanMenuState();
}

class _StationFanMenuState extends State<StationFanMenu> {
  final StationFanMenuGeometry _geometry = buildStationFanMenuGeometry();
  int? _activePointer;
  _FanSector? _pressed;

  double get _scale => widget.width / kFanMenuDesignSize.width;
  double get _height =>
      widget.width * (kFanMenuDesignSize.height / kFanMenuDesignSize.width);

  Path _pathFor(_FanSector sector) => _pathForSector(_geometry, sector);

  bool _disabled(_FanSector sector) =>
      _sectorDisabled(widget.disabledSlots, sector);

  /// 글로벌이 아닌 위젯 로컬 좌표(px)를 design 좌표로 되돌려 히트테스트한다.
  _FanSector? _sectorAtLocal(Offset local) {
    final design = local / _scale;
    for (final sector in _FanSector.values) {
      if (_pathFor(sector).contains(design)) {
        return sector;
      }
    }
    return null;
  }

  void _handleTapUp(_FanSector sector) {
    if (_disabled(sector)) {
      return;
    }
    final slot = _slotFor(sector);
    if (slot == null) {
      widget.onClose();
    } else {
      widget.onAction(slot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, _height);
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          Listener(
            onPointerDown: (event) {
              if (_activePointer != null) {
                return;
              }
              final sector = _sectorAtLocal(event.localPosition);
              if (sector != null && !_disabled(sector)) {
                setState(() {
                  _activePointer = event.pointer;
                  _pressed = sector;
                });
              }
            },
            onPointerMove: (event) {
              if (event.pointer != _activePointer || _pressed == null) {
                return;
              }
              if (_sectorAtLocal(event.localPosition) != _pressed) {
                setState(() => _pressed = null);
              }
            },
            onPointerUp: (event) {
              if (event.pointer != _activePointer) {
                return;
              }
              final pressed = _pressed;
              final released = _sectorAtLocal(event.localPosition);
              setState(() {
                _activePointer = null;
                _pressed = null;
              });
              if (pressed != null && released == pressed) {
                _handleTapUp(pressed);
              }
            },
            onPointerCancel: (event) {
              if (event.pointer != _activePointer) {
                return;
              }
              setState(() {
                _activePointer = null;
                _pressed = null;
              });
            },
            behavior: HitTestBehavior.opaque,
            child: CustomPaint(
              size: size,
              painter: _StationFanMenuPainter(
                geometry: _geometry,
                scale: _scale,
                selectedSlots: widget.selectedSlots,
                disabledSlots: widget.disabledSlots,
                pressed: _pressed,
                fontFamily: widget.fontFamily,
              ),
            ),
          ),
          // 스크린리더용 시맨틱: 각 섹터 bounds에 투명 버튼을 겹친다(그리기와
          // 별개 계층이라 시각엔 영향 없음). tap도 위 Listener가 처리하지만
          // Semantics onTap으로 접근성 활성화 경로를 노출한다.
          for (final sector in _FanSector.values) _sectorSemantics(sector),
        ],
      ),
    );
  }

  Widget _sectorSemantics(_FanSector sector) {
    // 접근성 노드 rect는 겹치지 않도록 좁힌 코어 사각형을 스케일해 쓴다
    // (#2109 리뷰: getBounds() 사각형은 인접 섹터끼리 겹쳐 오탭 유발).
    final core = _sectorSemanticsCore[sector]!;
    final rect = Rect.fromLTRB(
      core.left * _scale,
      core.top * _scale,
      core.right * _scale,
      core.bottom * _scale,
    );
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        button: true,
        enabled: !_disabled(sector),
        label: _semanticsLabel(sector),
        sortKey: OrdinalSortKey(sector.index.toDouble()),
        onTap: _disabled(sector) ? null : () => _handleTapUp(sector),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StationFanMenuPainter extends CustomPainter {
  _StationFanMenuPainter({
    required this.geometry,
    required this.scale,
    required this.selectedSlots,
    required this.disabledSlots,
    required this.pressed,
    required this.fontFamily,
  }) {
    _labelPainters = {
      _FanSector.departure: _buildLabelPainter(
        '출발',
        _contentColor(_FanSector.departure),
        fontSize: 34,
        letterSpacing: -0.7,
      ),
      _FanSector.waypoint: _buildLabelPainter(
        '경유',
        _contentColor(_FanSector.waypoint),
        fontSize: 32,
        letterSpacing: -0.6,
      ),
      _FanSector.arrival: _buildLabelPainter(
        '도착',
        _contentColor(_FanSector.arrival),
        fontSize: 34,
        letterSpacing: -0.7,
      ),
      _FanSector.close: _buildLabelPainter(
        '닫기',
        _contentColor(_FanSector.close),
        fontSize: 30,
        letterSpacing: -0.6,
      ),
    };
  }

  final StationFanMenuGeometry geometry;
  final double scale;
  final Set<RouteDraftSlot> selectedSlots;
  final Set<RouteDraftSlot> disabledSlots;
  final _FanSector? pressed;
  final String? fontFamily;
  late final Map<_FanSector, TextPainter> _labelPainters;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    _paintSector(
      canvas,
      _FanSector.departure,
      EasySubwayFanMenuColors.departure,
      EasySubwayFanMenuColors.departureSurface,
      EasySubwayFanMenuColors.departurePressed,
    );
    _paintSector(
      canvas,
      _FanSector.waypoint,
      EasySubwayFanMenuColors.waypoint,
      EasySubwayFanMenuColors.waypointSurface,
      EasySubwayFanMenuColors.waypointPressed,
    );
    _paintSector(
      canvas,
      _FanSector.arrival,
      EasySubwayFanMenuColors.arrival,
      EasySubwayFanMenuColors.arrivalSurface,
      EasySubwayFanMenuColors.arrivalPressed,
    );
    _paintClose(canvas);
    _paintBorders(canvas);
    _paintIconsAndLabels(canvas);
    canvas.restore();
  }

  Path _pathFor(_FanSector sector) => _pathForSector(geometry, sector);

  bool _disabled(_FanSector sector) => _sectorDisabled(disabledSlots, sector);

  bool _selected(_FanSector sector) {
    final slot = _slotFor(sector);
    return slot != null && selectedSlots.contains(slot);
  }

  ({Color fill, Color content, double opacity}) _visualFor(
    _FanSector sector,
    Color selected,
    Color surface,
    Color pressedSurface,
  ) {
    final disabled = _disabled(sector);
    final selectedState = _selected(sector);
    final pressedState = pressed == sector;
    return (
      fill: selectedState
          ? selected
          : (pressedState ? pressedSurface : surface),
      content: selectedState ? Colors.white : selected,
      opacity: disabled
          ? EasySubwayFanMenuColors.disabledOpacity
          : (pressedState ? EasySubwayFanMenuColors.pressedOpacity : 1),
    );
  }

  ({Color fill, Color content, double opacity}) _closeVisual() {
    final pressedState = pressed == _FanSector.close;
    return (
      fill: pressedState
          ? EasySubwayFanMenuColors.closePressed
          : EasySubwayFanMenuColors.closeSurface,
      content: EasySubwayFanMenuColors.closeInk,
      opacity: pressedState ? EasySubwayFanMenuColors.pressedOpacity : 1,
    );
  }

  void _paintSector(
    Canvas canvas,
    _FanSector sector,
    Color selected,
    Color surface,
    Color pressedSurface,
  ) {
    final visual = _visualFor(sector, selected, surface, pressedSurface);
    canvas.drawPath(
      _pathFor(sector),
      Paint()
        ..style = PaintingStyle.fill
        ..color = visual.fill.withValues(alpha: visual.opacity),
    );
  }

  void _paintClose(Canvas canvas) {
    final visual = _closeVisual();
    canvas.drawPath(
      geometry.close,
      Paint()
        ..style = PaintingStyle.fill
        ..color = visual.fill.withValues(alpha: visual.opacity),
    );
  }

  void _paintBorders(Canvas canvas) {
    final bounds = Offset.zero & kFanMenuDesignSize;
    final structuralStrokeWidth = 2.4 / scale;
    // 내부 구분선은 외곽선과 색은 같지만(#2200 절충안) 굵기를 한 단계 가늘게
    // 유지해 실루엣과의 위계를 만든다.
    final dividerStrokeWidth = 1.6 / scale;
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(
      geometry.dividers,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dividerStrokeWidth
        ..color = EasySubwayFanMenuColors.border,
    );
    canvas.drawPath(
      geometry.silhouette,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = structuralStrokeWidth
        ..color = EasySubwayFanMenuColors.outline,
    );

    // SVG sector 방향과 무관하게 right-hand sector도 내부만 clip하도록 한다.
    final disabledMask = Path()..fillType = PathFillType.evenOdd;
    final pressedMask = Path()..fillType = PathFillType.evenOdd;
    for (final sector in _FanSector.values) {
      if (_disabled(sector)) {
        disabledMask.addPath(_pathFor(sector), Offset.zero);
      } else if (pressed == sector) {
        pressedMask.addPath(_pathFor(sector), Offset.zero);
      }
    }

    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
    canvas.drawRect(bounds, Paint()..color = Colors.white);
    if (!pressedMask.getBounds().isEmpty) {
      canvas.save();
      canvas.clipPath(pressedMask);
      canvas.drawRect(
        bounds,
        Paint()
          ..color = Colors.white.withValues(
            alpha: EasySubwayFanMenuColors.pressedOpacity,
          )
          ..blendMode = BlendMode.src,
      );
      canvas.restore();
    }
    if (!disabledMask.getBounds().isEmpty) {
      canvas.save();
      canvas.clipPath(disabledMask);
      canvas.drawRect(
        bounds,
        Paint()
          ..color = Colors.white.withValues(
            alpha: EasySubwayFanMenuColors.disabledOpacity,
          )
          ..blendMode = BlendMode.src,
      );
      canvas.restore();
    }
    canvas.restore();
    canvas.restore();
  }

  void _paintIconsAndLabels(Canvas canvas) {
    _paintDepartureIcon(canvas, _contentColor(_FanSector.departure));
    _paintWaypointIcon(canvas, _contentColor(_FanSector.waypoint));
    _paintArrivalIcon(canvas, _contentColor(_FanSector.arrival));
    _paintCloseIcon(canvas, _contentColor(_FanSector.close));
    _paintLabel(canvas, _FanSector.departure, const Offset(175, 243));
    _paintLabel(
      canvas,
      _FanSector.waypoint,
      const Offset(350.58783, 160.31921),
    );
    _paintLabel(canvas, _FanSector.arrival, const Offset(525, 243));
    _paintLabel(canvas, _FanSector.close, const Offset(350, 302.93903));
  }

  Color _contentColor(_FanSector sector) {
    final visual = switch (sector) {
      _FanSector.departure => _visualFor(
        sector,
        EasySubwayFanMenuColors.departure,
        EasySubwayFanMenuColors.departureSurface,
        EasySubwayFanMenuColors.departurePressed,
      ),
      _FanSector.waypoint => _visualFor(
        sector,
        EasySubwayFanMenuColors.waypoint,
        EasySubwayFanMenuColors.waypointSurface,
        EasySubwayFanMenuColors.waypointPressed,
      ),
      _FanSector.arrival => _visualFor(
        sector,
        EasySubwayFanMenuColors.arrival,
        EasySubwayFanMenuColors.arrivalSurface,
        EasySubwayFanMenuColors.arrivalPressed,
      ),
      _FanSector.close => _closeVisual(),
    };
    return visual.content.withValues(alpha: visual.opacity);
  }

  void _paintDepartureIcon(Canvas canvas, Color color) {
    const origin = Offset(175, 168);
    final outerStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawRRect(
      RRect.fromRectXY(
        Rect.fromLTWH(origin.dx - 24, origin.dy - 28, 48, 48),
        9,
        9,
      ),
      outerStroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx - 14, origin.dy - 16, 28, 16),
        const Radius.circular(2.5),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    final fill = Paint()..color = color;
    canvas.drawCircle(origin + const Offset(-13, 11), 4.2, fill);
    canvas.drawCircle(origin + const Offset(13, 11), 4.2, fill);
    final legStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawLine(
      origin + const Offset(-16, 21),
      origin + const Offset(-23, 30),
      legStroke,
    );
    canvas.drawLine(
      origin + const Offset(16, 21),
      origin + const Offset(23, 30),
      legStroke,
    );
    canvas.drawLine(
      origin + const Offset(-11, 28),
      origin + const Offset(11, 28),
      legStroke,
    );
  }

  void _paintWaypointIcon(Canvas canvas, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = color;
    const origin = Offset(350.58781, 93.31923);
    canvas.drawLine(
      origin + const Offset(-20, 0),
      origin + const Offset(20, 0),
      paint,
    );
    canvas.drawLine(
      origin + const Offset(0, -20),
      origin + const Offset(0, 20),
      paint,
    );
  }

  void _paintArrivalIcon(Canvas canvas, Color color) {
    const origin = Offset(525, 173);
    canvas.drawCircle(
      origin,
      22,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = color,
    );
    canvas.drawCircle(
      origin,
      7.5,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color,
    );
  }

  void _paintCloseIcon(Canvas canvas, Color color) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color;
    const origin = Offset(350, 250.93905);
    canvas.drawLine(
      origin + const Offset(-15, -15),
      origin + const Offset(15, 15),
      paint,
    );
    canvas.drawLine(
      origin + const Offset(15, -15),
      origin + const Offset(-15, 15),
      paint,
    );
  }

  TextPainter _buildLabelPainter(
    String text,
    Color color, {
    required double fontSize,
    required double letterSpacing,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        fontFamily: fontFamily,
        letterSpacing: letterSpacing,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  void _paintLabel(Canvas canvas, _FanSector sector, Offset baseline) {
    final tp = _labelPainters[sector]!;
    final alphabeticBaseline = tp.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    tp.paint(
      canvas,
      Offset(baseline.dx - tp.width / 2, baseline.dy - alphabeticBaseline),
    );
  }

  @override
  bool shouldRepaint(_StationFanMenuPainter old) =>
      old.scale != scale ||
      old.pressed != pressed ||
      old.fontFamily != fontFamily ||
      !setEquals(old.selectedSlots, selectedSlots) ||
      !setEquals(old.disabledSlots, disabledSlots);
}
