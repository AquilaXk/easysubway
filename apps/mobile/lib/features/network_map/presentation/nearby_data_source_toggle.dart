import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

/// 주변역 패널 실시간/시간표 2버튼 세그먼트 토글 (오너 스펙 2026-07-16, #2200).
///
/// 각 세그먼트 59×48(전체 118×48), 시각 높이 32, radius 16. 비선택은 옅은 회색
/// 배경, 선택은 흰 배경 + brandSignature 2dp 테두리. 전환 애니메이션은 없다.
/// 비선택 세그먼트를 누르면 [onToggle]로 데이터 소스를 뒤집고, 선택된 세그먼트
/// 탭은 no-op이다.
class NearbyDataSourceToggle extends StatelessWidget {
  const NearbyDataSourceToggle({
    required this.isRealtime,
    required this.enabled,
    required this.onToggle,
    super.key,
  });

  static const _radius = BorderRadius.all(Radius.circular(16));

  final bool isRealtime;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('networkMapNearbyDataSourceToggle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _Segment(
          label: '실시간',
          selected: isRealtime,
          enabled: enabled,
          onToggle: onToggle,
        ),
        _Segment(
          label: '시간표',
          selected: !isRealtime,
          enabled: enabled,
          onToggle: onToggle,
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onToggle,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tappable = enabled && !selected;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '$label${selected ? ' 선택됨' : '로 전환'}',
      onTap: tappable ? onToggle : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: tappable ? onToggle : null,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: SizedBox(
          width: 59,
          height: 48,
          child: Center(
            child: Container(
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white
                    : EasySubwayAccessibleColors.nearbyToggleIdleFill,
                borderRadius: NearbyDataSourceToggle._radius,
                border: selected
                    ? Border.all(
                        color: EasySubwayAccessibleColors.brandSignature,
                        width: 2,
                      )
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? EasySubwayAccessibleColors.brandSignature
                      : EasySubwayAccessibleColors.nearbyToggleIdleText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
