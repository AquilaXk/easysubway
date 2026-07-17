import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../domain/station_models.dart';

/// 운행 정보 배지.
///
/// 일반/급행은 선택 컨트롤이 아니라 실제 운행 정보다. `serviceClass=SUBWAY`이고
/// `servicePattern=EXPRESS`인 출발 행에만 `급행` 텍스트 배지를 노출하고,
/// 일반(LOCAL)에는 아무 배지도 붙이지 않는다. 시간표 화면과 노선도 하단 패널이
/// 같은 배지를 공유해 표시 규칙을 일치시킨다.
///
/// 같은 중립 pill을 길찾기 승차 leg의 서비스 식별에도 재사용한다. `급행`(SUBWAY/
/// EXPRESS) 외에 `ITX-청춘`(serviceClass=ITX_CHEONGCHUN)처럼 별도 운임의 좌석 지정
/// 서비스를 일반 전동차와 구분해 표시한다. 배지 텍스트만 다르고 시각·semantics
/// 규칙은 동일하다.
///
/// 시각 원칙: 무채색 중립 아웃라인 pill(각진 radius 8, 그림자 0). 눌러도 상태가
/// 바뀌지 않으며 toggle/chip/filter semantics를 갖지 않는다. 배지는 장식이므로
/// semantics에서 제외하고, TalkBack용 라벨은 행/leg semanticLabel이 한 번만 제공한다.
class ServicePatternBadge extends StatelessWidget {
  const ServicePatternBadge({required this.departure, super.key})
    : _forcedLabel = null,
      _badgeKey = _expressBadgeKey;

  /// 시간표 출발 행이 아닌 곳(길찾기 승차 leg 등)에서 급행 배지를 재사용하기 위한
  /// 생성자. 호출부가 `serviceClass=SUBWAY && servicePattern=EXPRESS`를 이미 판정한
  /// 뒤 항상 배지를 그린다. 시각·semantics 규칙은 시간표 배지와 동일하다.
  const ServicePatternBadge.express({super.key})
    : departure = null,
      _forcedLabel = '급행',
      _badgeKey = _expressBadgeKey;

  /// 길찾기 승차 leg에서 ITX-청춘 좌석 지정 서비스를 같은 중립 pill로 식별 표시하는
  /// 생성자. 호출부가 `serviceClass=ITX_CHEONGCHUN`을 이미 판정한 뒤 항상 배지를
  /// 그린다. 일반 전동차와 화면상 구분되지 않으면 오인 위험이 있어 별도 표시한다.
  const ServicePatternBadge.itxCheongchun({super.key})
    : departure = null,
      _forcedLabel = 'ITX-청춘',
      _badgeKey = _itxCheongchunBadgeKey;

  static const Key _expressBadgeKey = Key('servicePatternExpressBadge');
  static const Key _itxCheongchunBadgeKey = Key(
    'servicePatternItxCheongchunBadge',
  );

  final StationTimetableDeparture? departure;
  final String? _forcedLabel;
  final Key _badgeKey;

  @override
  Widget build(BuildContext context) {
    final label =
        _forcedLabel ?? ((departure?.isExpress ?? false) ? '급행' : null);
    if (label == null) {
      return const SizedBox.shrink();
    }
    return ExcludeSemantics(
      child: Container(
        key: _badgeKey,
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surface,
          borderRadius: BorderRadius.circular(EasySubwayRadius.control),
          border: Border.all(color: EasySubwayAccessibleColors.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          label,
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
