import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../route_draft/domain/route_draft.dart';
import 'station_fan_menu_geometry.dart';

const _departureColor = Color(0xFF176FD1);
const _departureSoft = Color(0xFFEAF3FF);
const _waypointColor = Color(0xFFF57C00);
const _waypointSoft = Color(0xFFFFF3E6);
const _arrivalColor = Color(0xFFEE2C35);
const _arrivalSoft = Color(0xFFFFF0F1);
const _closeSurface = Color(0xFFF1F3F6);
const _closePressed = Color(0xFFE4E7EC);
const _closeInk = Color(0xFF343A43);
const _borderColor = Color(0xFFD5DAE2);
const _outlineColor = Color(0xFFC9D0DA);

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

class StationFanMenu extends StatefulWidget {
  const StationFanMenu({
    super.key,
    required this.width,
    required this.selectedSlots,
    required this.disabledSlots,
    required this.onAction,
    required this.onClose,
  });

  final double width;
  final Set<RouteDraftSlot> selectedSlots;
  final Set<RouteDraftSlot> disabledSlots;
  final ValueChanged<RouteDraftSlot> onAction;
  final VoidCallback onClose;

  @override
  State<StationFanMenu> createState() => _StationFanMenuState();
}

class _StationFanMenuState extends State<StationFanMenu> {
  final StationFanMenuGeometry _geometry = buildStationFanMenuGeometry();
  _FanSector? _pressed;

  double get _scale => widget.width / kFanMenuDesignSize.width;
  double get _height =>
      widget.width * (kFanMenuDesignSize.height / kFanMenuDesignSize.width);

  Path _pathFor(_FanSector sector) => switch (sector) {
    _FanSector.departure => _geometry.departure,
    _FanSector.waypoint => _geometry.waypoint,
    _FanSector.arrival => _geometry.arrival,
    _FanSector.close => _geometry.close,
  };

  bool _disabled(_FanSector sector) {
    final slot = _slotFor(sector);
    return slot != null && widget.disabledSlots.contains(slot);
  }

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
              final sector = _sectorAtLocal(event.localPosition);
              if (sector != null && !_disabled(sector)) {
                setState(() => _pressed = sector);
              }
            },
            onPointerUp: (event) {
              final sector = _sectorAtLocal(event.localPosition);
              setState(() => _pressed = null);
              if (sector != null) {
                _handleTapUp(sector);
              }
            },
            onPointerCancel: (_) => setState(() => _pressed = null),
            behavior: HitTestBehavior.opaque,
            child: CustomPaint(
              size: size,
              painter: _StationFanMenuPainter(
                geometry: _geometry,
                scale: _scale,
                selectedSlots: widget.selectedSlots,
                disabledSlots: widget.disabledSlots,
                pressed: _pressed,
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
    final bounds = _pathFor(sector).getBounds();
    final rect = Rect.fromLTRB(
      bounds.left * _scale,
      bounds.top * _scale,
      bounds.right * _scale,
      bounds.bottom * _scale,
    );
    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        button: true,
        enabled: !_disabled(sector),
        label: _semanticsLabel(sector),
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
  });

  final StationFanMenuGeometry geometry;
  final double scale;
  final Set<RouteDraftSlot> selectedSlots;
  final Set<RouteDraftSlot> disabledSlots;
  final _FanSector? pressed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    _paintShadow(canvas);
    _paintSector(canvas, _FanSector.departure, _departureColor, _departureSoft);
    _paintSector(canvas, _FanSector.waypoint, _waypointColor, _waypointSoft);
    _paintSector(canvas, _FanSector.arrival, _arrivalColor, _arrivalSoft);
    _paintClose(canvas);
    _paintBorders(canvas);
    _paintIconsAndLabels(canvas);
    canvas.restore();
  }

  void _paintShadow(Canvas canvas) {
    // 스펙 menuShadow: dy12 blur13 .18 + dy3 blur3 .08.
    for (final layer in const [
      [12.0, 13.0, 0.18],
      [3.0, 3.0, 0.08],
    ]) {
      final paint = Paint()
        ..color = const Color(0xFF101828).withValues(alpha: layer[2])
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, layer[1]);
      canvas.save();
      canvas.translate(0, layer[0]);
      canvas.drawPath(geometry.silhouette, paint);
      canvas.restore();
    }
  }

  Path _pathFor(_FanSector sector) => switch (sector) {
    _FanSector.departure => geometry.departure,
    _FanSector.waypoint => geometry.waypoint,
    _FanSector.arrival => geometry.arrival,
    _FanSector.close => geometry.close,
  };

  bool _disabled(_FanSector sector) {
    final slot = _slotFor(sector);
    return slot != null && disabledSlots.contains(slot);
  }

  bool _selected(_FanSector sector) {
    final slot = _slotFor(sector);
    return slot != null && selectedSlots.contains(slot);
  }

  void _paintSector(
    Canvas canvas,
    _FanSector sector,
    Color color,
    Color soft,
  ) {
    final path = _pathFor(sector);
    final Color fill;
    if (_selected(sector)) {
      fill = color;
    } else if (pressed == sector && !_disabled(sector)) {
      fill = soft;
    } else {
      fill = Colors.white;
    }
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = _disabled(sector) ? fill.withValues(alpha: 0.4) : fill;
    canvas.drawPath(path, paint);
  }

  void _paintClose(Canvas canvas) {
    final fill = pressed == _FanSector.close ? _closePressed : _closeSurface;
    canvas.drawPath(
      geometry.close,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fill,
    );
  }

  void _paintBorders(Canvas canvas) {
    canvas.drawPath(
      geometry.silhouette,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = _outlineColor,
    );
    // 섹터 간 경계선(스펙 §비주얼: #D5DAE2). 인접 섹터 경계 line 세그먼트만
    // 재현한다. 섹터 Path 스트로크로 대체하면 공유 경계가 겹쳐 진해지므로,
    // 각 섹터 Path를 얇게 스트로크한다.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = _borderColor;
    canvas.drawPath(geometry.departure, border);
    canvas.drawPath(geometry.waypoint, border);
    canvas.drawPath(geometry.arrival, border);
    canvas.drawPath(geometry.close, border);
  }

  void _paintIconsAndLabels(Canvas canvas) {
    _paintDepartureIcon(
      canvas,
      _iconColor(_FanSector.departure, _departureColor),
    );
    _paintWaypointIcon(canvas, _iconColor(_FanSector.waypoint, _waypointColor));
    _paintArrivalIcon(canvas, _iconColor(_FanSector.arrival, _arrivalColor));
    _paintCloseIcon(canvas);
    _paintLabel(
      canvas,
      '출발',
      const Offset(175, 243),
      _labelColor(_FanSector.departure, _departureColor),
    );
    _paintLabel(
      canvas,
      '경유',
      const Offset(350, 195),
      _labelColor(_FanSector.waypoint, _waypointColor),
    );
    _paintLabel(
      canvas,
      '도착',
      const Offset(525, 243),
      _labelColor(_FanSector.arrival, _arrivalColor),
    );
  }

  Color _iconColor(_FanSector sector, Color base) {
    if (_selected(sector)) return Colors.white;
    final c = base;
    return _disabled(sector) ? c.withValues(alpha: 0.4) : c;
  }

  Color _labelColor(_FanSector sector, Color base) => _iconColor(sector, base);

  void _paintDepartureIcon(Canvas canvas, Color color) {
    // translate(175,173), stroke-width 10. ↗ 화살표 2패스.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    const o = Offset(175, 173);
    canvas.drawPath(
      Path()
        ..moveTo(o.dx - 24, o.dy + 22)
        ..lineTo(o.dx + 20, o.dy - 22),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(o.dx - 4, o.dy - 22)
        ..lineTo(o.dx + 20, o.dy - 22)
        ..lineTo(o.dx + 20, o.dy + 2),
      paint,
    );
  }

  void _paintWaypointIcon(Canvas canvas, Color color) {
    // translate(600→350,337→127), plus, stroke-width 10.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = color;
    const o = Offset(350, 127);
    canvas.drawLine(Offset(o.dx - 24, o.dy), Offset(o.dx + 24, o.dy), paint);
    canvas.drawLine(Offset(o.dx, o.dy - 24), Offset(o.dx, o.dy + 24), paint);
  }

  void _paintArrivalIcon(Canvas canvas, Color color) {
    // translate(525,173): 이중 원. 외곽 r24 stroke9 + 채움 r8.
    const o = Offset(525, 173);
    canvas.drawCircle(
      o,
      24,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..color = color,
    );
    canvas.drawCircle(
      o,
      8,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color,
    );
  }

  void _paintCloseIcon(Canvas canvas) {
    // translate(350,277): X, stroke-width 9, #343A43.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = _closeInk;
    const o = Offset(350, 277);
    canvas.drawLine(
      Offset(o.dx - 17, o.dy - 17),
      Offset(o.dx + 17, o.dy + 17),
      paint,
    );
    canvas.drawLine(
      Offset(o.dx + 17, o.dy - 17),
      Offset(o.dx - 17, o.dy + 17),
      paint,
    );
  }

  void _paintLabel(Canvas canvas, String text, Offset baseline, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 34,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // SVG y는 baseline. TextPainter는 top 기준이라 대략 fontSize만큼 위로 올린다.
    tp.paint(canvas, Offset(baseline.dx - tp.width / 2, baseline.dy - tp.height));
  }

  @override
  bool shouldRepaint(_StationFanMenuPainter old) =>
      old.scale != scale ||
      old.pressed != pressed ||
      !setEquals(old.selectedSlots, selectedSlots) ||
      !setEquals(old.disabledSlots, disabledSlots);
}
