import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../domain/station_models.dart';

/// 급행 운행 정보 배지.
///
/// 일반/급행은 선택 컨트롤이 아니라 실제 운행 정보다. `serviceClass=SUBWAY`이고
/// `servicePattern=EXPRESS`인 출발 행에만 `급행` 텍스트 배지를 노출하고,
/// 일반(LOCAL)에는 아무 배지도 붙이지 않는다. 시간표 화면과 노선도 하단 패널이
/// 같은 배지를 공유해 표시 규칙을 일치시킨다.
///
/// 시각 원칙: 무채색 중립 아웃라인 pill(각진 radius 8, 그림자 0). 눌러도 상태가
/// 바뀌지 않으며 toggle/chip/filter semantics를 갖지 않는다. 배지는 장식이므로
/// semantics에서 제외하고, TalkBack용 `급행`은 행 semanticLabel이 한 번만 제공한다.
class ServicePatternBadge extends StatelessWidget {
  const ServicePatternBadge({required this.departure, super.key})
    : _alwaysExpress = false;

  /// 시간표 출발 행이 아닌 곳(길찾기 승차 leg 등)에서 급행 배지를 재사용하기 위한
  /// 생성자. 호출부가 `serviceClass=SUBWAY && servicePattern=EXPRESS`를 이미 판정한
  /// 뒤 항상 배지를 그린다. 시각·semantics 규칙은 시간표 배지와 동일하다.
  const ServicePatternBadge.express({super.key})
    : departure = null,
      _alwaysExpress = true;

  final StationTimetableDeparture? departure;
  final bool _alwaysExpress;

  @override
  Widget build(BuildContext context) {
    final isExpress = _alwaysExpress || (departure?.isExpress ?? false);
    if (!isExpress) {
      return const SizedBox.shrink();
    }
    return ExcludeSemantics(
      child: Container(
        key: const Key('servicePatternExpressBadge'),
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surface,
          borderRadius: BorderRadius.circular(EasySubwayRadius.control),
          border: Border.all(color: EasySubwayAccessibleColors.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          '급행',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: EasySubwayAccessibleColors.secondaryText,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}
