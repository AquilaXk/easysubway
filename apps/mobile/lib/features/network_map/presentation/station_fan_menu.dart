import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  _FanSector.departure: Rect.fromLTRB(130, 150, 220, 250),
  _FanSector.waypoint: Rect.fromLTRB(300, 100, 400, 210),
  _FanSector.arrival: Rect.fromLTRB(480, 150, 570, 250),
  _FanSector.close: Rect.fromLTRB(320, 252, 380, 302),
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
    _paintSector(
      canvas,
      _FanSector.departure,
      EasySubwayFanMenuColors.departure,
      EasySubwayFanMenuColors.departureSoft,
    );
    _paintSector(
      canvas,
      _FanSector.waypoint,
      EasySubwayFanMenuColors.waypoint,
      EasySubwayFanMenuColors.waypointSoft,
    );
    _paintSector(
      canvas,
      _FanSector.arrival,
      EasySubwayFanMenuColors.arrival,
      EasySubwayFanMenuColors.arrivalSoft,
    );
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

  Path _pathFor(_FanSector sector) => _pathForSector(geometry, sector);

  bool _disabled(_FanSector sector) => _sectorDisabled(disabledSlots, sector);

  bool _selected(_FanSector sector) {
    final slot = _slotFor(sector);
    return slot != null && selectedSlots.contains(slot);
  }

  void _paintSector(Canvas canvas, _FanSector sector, Color color, Color soft) {
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
    final fill = pressed == _FanSector.close
        ? EasySubwayFanMenuColors.closePressed
        : EasySubwayFanMenuColors.closeSurface;
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
        ..color = EasySubwayFanMenuColors.outline,
    );
    // 섹터 간 경계선(스펙 §비주얼: #D5DAE2). 인접 섹터 경계 line 세그먼트만
    // 재현한다. 섹터 Path 스트로크로 대체하면 공유 경계가 겹쳐 진해지므로,
    // 각 섹터 Path를 얇게 스트로크한다.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = EasySubwayFanMenuColors.border;
    canvas.drawPath(geometry.departure, border);
    canvas.drawPath(geometry.waypoint, border);
    canvas.drawPath(geometry.arrival, border);
    canvas.drawPath(geometry.close, border);
  }

  void _paintIconsAndLabels(Canvas canvas) {
    _paintDepartureIcon(
      canvas,
      _iconColor(_FanSector.departure, EasySubwayFanMenuColors.departure),
    );
    _paintWaypointIcon(
      canvas,
      _iconColor(_FanSector.waypoint, EasySubwayFanMenuColors.waypoint),
    );
    _paintArrivalIcon(
      canvas,
      _iconColor(_FanSector.arrival, EasySubwayFanMenuColors.arrival),
    );
    _paintCloseIcon(canvas);
    _paintLabel(
      canvas,
      '출발',
      const Offset(175, 243),
      _labelColor(_FanSector.departure, EasySubwayFanMenuColors.departure),
    );
    _paintLabel(
      canvas,
      '경유',
      const Offset(350, 195),
      _labelColor(_FanSector.waypoint, EasySubwayFanMenuColors.waypoint),
    );
    _paintLabel(
      canvas,
      '도착',
      const Offset(525, 243),
      _labelColor(_FanSector.arrival, EasySubwayFanMenuColors.arrival),
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
      ..color = EasySubwayFanMenuColors.closeInk;
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
    tp.paint(
      canvas,
      Offset(baseline.dx - tp.width / 2, baseline.dy - tp.height),
    );
  }

  @override
  bool shouldRepaint(_StationFanMenuPainter old) =>
      old.scale != scale ||
      old.pressed != pressed ||
      !setEquals(old.selectedSlots, selectedSlots) ||
      !setEquals(old.disabledSlots, disabledSlots);
}
