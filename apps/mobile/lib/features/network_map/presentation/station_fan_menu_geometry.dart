import 'dart:ui';

/// SVG viewBox="250 210 700 380"를 (250,210) 원점 이동으로 정규화한 design 박스.
/// 위젯은 이 박스를 실제 크기에 uniform scale로 맞춰 그린다.
const Size kFanMenuDesignSize = Size(700, 380);

/// v3 말풍선 꼬리 팁(design 좌표). 닫기 섹터·실루엣 하단 베지어의 t=0.5 접점이며
/// 이 점이 앵커 역 노드 정중앙에 닿도록 배치한다(팬 메뉴 placement가 소비하는
/// 단일 출처 — 배치식이 좌표를 재하드코딩하지 않게 한다).
const Offset kFanMenuTailTip = Offset(350, 375);

/// 오너 제작 방사형 액션 메뉴의 섹터별 Path 묶음. 렌더링과 히트테스트가
/// 동일 인스턴스를 공유하도록 이 객체를 단일 출처로 쓴다.
class StationFanMenuGeometry {
  const StationFanMenuGeometry({
    required this.departure,
    required this.waypoint,
    required this.arrival,
    required this.close,
    required this.silhouette,
    required this.dividers,
  });

  final Path departure;
  final Path waypoint;
  final Path arrival;
  final Path close;

  /// 그림자·외곽선용 통합 실루엣(네 섹터를 잇는 연속 윤곽).
  final Path silhouette;

  /// SVG의 방사형 2개와 닫기 arc 1개를 합친 내부 구분선.
  final Path dividers;
}

// 정규화(원본 - (250,210)) 좌표. 스펙 §컴포넌트의 arc d 좌표에서 그대로 이식.
const Offset _depOuterStart = Offset(50.92, 225.54); // 300.92,435.54
const Offset _depOuterEnd = Offset(221.06, 61.23); //  471.06,271.23
const Offset _wayOuterEnd = Offset(478.94, 61.23); //  728.94,271.23
const Offset _arrOuterEnd = Offset(649.08, 225.54); // 899.08,435.54
const Offset _depInnerStart = Offset(289.44, 222.32); // 539.44,432.32
const Offset _arrInnerStart = Offset(410.56, 222.32); // 660.56,432.32
const Offset _depInnerEnd = Offset(209.52, 299.49); //  459.52,509.49
const Offset _arrInnerEnd = Offset(490.48, 299.49); //  740.48,509.49
const Offset _closeNotchRight = Offset(391.69, 345.56); // 641.69,555.56
const Offset _closeNotchLeft = Offset(308.31, 345.56); // 558.31,555.56

const double _rOuter = 330;
const double _rInner = 155;

/// v3 닫기 섹터·실루엣 하단의 말풍선 꼬리(큐빅 베지어 3세그먼트, design 좌표).
/// notch 오른쪽 점([_closeNotchRight])에서 시작한다고 가정하고 왼쪽 점
/// ([_closeNotchLeft])까지 잇는다. 두 번째 세그먼트의 t=0.5 접점이
/// [kFanMenuTailTip]=(350,375)이다. 닫기 Path와 실루엣이 동일 꼬리를 쓰도록
/// 단일 헬퍼로 둔다(좌표 중복 하드코딩 방지).
Path _appendCloseTail(Path path) => path
  ..cubicTo(374, 352, 360, 362, 354, 372)
  ..cubicTo(352, 376, 348, 376, 346, 372)
  ..cubicTo(340, 362, 326, 352, _closeNotchLeft.dx, _closeNotchLeft.dy);

Path _sector({
  required Offset outerStart,
  required Offset outerEnd,
  required Offset innerStart,
  required Offset innerEnd,
}) {
  // SVG: M outerStart A rOuter 0 0 1 outerEnd L innerStart A rInner 0 0 0 innerEnd Z
  return Path()
    ..moveTo(outerStart.dx, outerStart.dy)
    ..arcToPoint(
      outerEnd,
      radius: const Radius.circular(_rOuter),
      clockwise: true,
    )
    ..lineTo(innerStart.dx, innerStart.dy)
    ..arcToPoint(
      innerEnd,
      radius: const Radius.circular(_rInner),
      clockwise: false,
    )
    ..close();
}

StationFanMenuGeometry buildStationFanMenuGeometry() {
  // 출발(좌): M 300.92,435.54 A330 ...1 471.06,271.23 L 539.44,432.32 A155 ...0 459.52,509.49 Z
  final departure = _sector(
    outerStart: _depOuterStart,
    outerEnd: _depOuterEnd,
    innerStart: _depInnerStart,
    innerEnd: _depInnerEnd,
  );
  // 경유(중): M 471.06,271.23 A330 ...1 728.94,271.23 L 660.56,432.32 A155 ...0 539.44,432.32 Z
  final waypoint = _sector(
    outerStart: _depOuterEnd,
    outerEnd: _wayOuterEnd,
    innerStart: _arrInnerStart,
    innerEnd: _depInnerStart,
  );
  // 도착(우): M 728.94,271.23 A330 ...1 899.08,435.54 L 740.48,509.49 A155 ...0 660.56,432.32 Z
  final arrival = _sector(
    outerStart: _wayOuterEnd,
    outerEnd: _arrOuterEnd,
    innerStart: _arrInnerEnd,
    innerEnd: _arrInnerStart,
  );
  // 닫기(하단 말풍선 꼬리, v3): M 459.52,509.49 A155 ...1 740.48,509.49
  //   L 641.69,555.56 C… 꼬리 …→ 558.31,555.56 Z
  final close = _appendCloseTail(
    Path()
      ..moveTo(_depInnerEnd.dx, _depInnerEnd.dy)
      ..arcToPoint(
        _arrInnerEnd,
        radius: const Radius.circular(_rInner),
        clockwise: true,
      )
      ..lineTo(_closeNotchRight.dx, _closeNotchRight.dy),
  )..close();
  // 실루엣(연속 윤곽): SVG fan-outline path 그대로 정규화 이식(하단 v3 꼬리 포함).
  final silhouette = _appendCloseTail(
    Path()
      ..moveTo(_depOuterStart.dx, _depOuterStart.dy)
      ..arcToPoint(
        _arrOuterEnd,
        radius: const Radius.circular(_rOuter),
        clockwise: true,
      )
      ..lineTo(_arrInnerEnd.dx, _arrInnerEnd.dy)
      ..lineTo(_closeNotchRight.dx, _closeNotchRight.dy),
  )..close();
  final dividers = Path()
    ..moveTo(_depInnerStart.dx, _depInnerStart.dy)
    ..lineTo(_depOuterEnd.dx, _depOuterEnd.dy)
    ..moveTo(_arrInnerStart.dx, _arrInnerStart.dy)
    ..lineTo(_wayOuterEnd.dx, _wayOuterEnd.dy)
    ..moveTo(_depInnerEnd.dx, _depInnerEnd.dy)
    ..arcToPoint(
      _arrInnerEnd,
      radius: const Radius.circular(_rInner),
      clockwise: true,
    );
  return StationFanMenuGeometry(
    departure: departure,
    waypoint: waypoint,
    arrival: arrival,
    close: close,
    silhouette: silhouette,
    dividers: dividers,
  );
}
