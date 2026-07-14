import 'dart:ui';

/// SVG viewBox="250 210 700 380"를 (250,210) 원점 이동으로 정규화한 design 박스.
/// 위젯은 이 박스를 실제 크기에 uniform scale로 맞춰 그린다.
const Size kFanMenuDesignSize = Size(700, 380);

/// 오너 제작 방사형 액션 메뉴의 섹터별 Path 묶음. 렌더링과 히트테스트가
/// 동일 인스턴스를 공유하도록 이 객체를 단일 출처로 쓴다.
class StationFanMenuGeometry {
  const StationFanMenuGeometry({
    required this.departure,
    required this.waypoint,
    required this.arrival,
    required this.close,
    required this.silhouette,
  });

  final Path departure;
  final Path waypoint;
  final Path arrival;
  final Path close;

  /// 그림자·외곽선용 통합 실루엣(네 섹터를 잇는 연속 윤곽).
  final Path silhouette;
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
const Offset _closeInnerStart = Offset(240.40, 255.40); // 490.40,465.40
const Offset _closeInnerEnd = Offset(459.60, 255.40); //  709.60,465.40
const Offset _closeNotchRight = Offset(382.53, 332.47); // 632.53,542.47
const Offset _closeNotchLeft = Offset(317.47, 332.47); //  567.47,542.47

const double _rOuter = 330;
const double _rInner = 155;
const double _rClose = 46;

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
  // 닫기(하단 노치): M 490.40,465.40 A155 ...1 709.60,465.40 L 632.53,542.47 A46 ...0 567.47,542.47 Z
  final close = Path()
    ..moveTo(_closeInnerStart.dx, _closeInnerStart.dy)
    ..arcToPoint(
      _closeInnerEnd,
      radius: const Radius.circular(_rInner),
      clockwise: true,
    )
    ..lineTo(_closeNotchRight.dx, _closeNotchRight.dy)
    ..arcToPoint(
      _closeNotchLeft,
      radius: const Radius.circular(_rClose),
      clockwise: false,
    )
    ..close();
  // 실루엣(연속 윤곽): SVG 53행 통합 path 그대로 정규화 이식.
  final silhouette = Path()
    ..moveTo(_depOuterStart.dx, _depOuterStart.dy)
    ..arcToPoint(
      _arrOuterEnd,
      radius: const Radius.circular(_rOuter),
      clockwise: true,
    )
    ..lineTo(_arrInnerEnd.dx, _arrInnerEnd.dy)
    ..arcToPoint(
      _closeInnerEnd,
      radius: const Radius.circular(_rInner),
      clockwise: false,
    )
    ..lineTo(_closeNotchRight.dx, _closeNotchRight.dy)
    ..arcToPoint(
      _closeNotchLeft,
      radius: const Radius.circular(_rClose),
      clockwise: false,
    )
    ..lineTo(_closeInnerStart.dx, _closeInnerStart.dy)
    ..arcToPoint(
      _depInnerEnd,
      radius: const Radius.circular(_rInner),
      clockwise: false,
    )
    ..close();
  return StationFanMenuGeometry(
    departure: departure,
    waypoint: waypoint,
    arrival: arrival,
    close: close,
    silhouette: silhouette,
  );
}
