import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

/// 주변역 패널 실시간/시간표 세그먼트 토글 (오너 스펙 2026-07-16, #2200/#2207).
///
/// 두 칸(59×48, 전체 118×48 터치 영역)이 하나의 라운드 컨테이너 안에 붙어 있는
/// 단일 세그먼트 컨트롤이다. 비선택 surface와 secondary content가
/// 두 칸을 하나로 감싸고(세로 inset 상하 8 → 시각 118×32, radius 16), 두 칸 사이
/// 간격은 없다. 선택된 칸만 default surface + secondary border pill(59×32, radius
/// 16)로 그 절반 위에 겹쳐 그린다. 전환 애니메이션·splash는 없다. 비선택 칸을
/// 누르면 [onToggle]로 데이터 소스를 뒤집고, 선택된 칸 탭은 no-op이다.
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
    return SizedBox(
      key: const Key('networkMapNearbyDataSourceToggle'),
      width: 118,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 두 칸을 하나로 감싸는 단일 라운드 배경(118×32). 두 칸 사이 간격 없음.
          Container(
            key: const Key('networkMapNearbyDataSourceToggleTrack'),
            width: 118,
            height: 32,
            decoration: const BoxDecoration(
              color: EasySubwayAccessibleColors.nearbyToggleIdleFill,
              borderRadius: _radius,
            ),
          ),
          Row(
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
          ),
        ],
      ),
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
    // 비활성 상태는 선택 칸의 default surface·secondary border를 걷어내고 글자색을
    // mutedText로 낮춰, 활성 토글과 시각적으로 구분한다(여전히 비탭).
    final bool showPill;
    final Color textColor;
    if (!enabled) {
      showPill = false;
      textColor = EasySubwayAccessibleColors.mutedText;
    } else if (selected) {
      showPill = true;
      textColor = EasySubwayAccessibleColors.brandSignature;
    } else {
      showPill = false;
      textColor = EasySubwayAccessibleColors.nearbyToggleIdleText;
    }
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
              key: ValueKey('networkMapNearbyDataSourceToggleSegment-$label'),
              width: 59,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: showPill
                    ? EasySubwayAccessibleColors.surfaceDefault
                    : Colors.transparent,
                borderRadius: NearbyDataSourceToggle._radius,
                border: showPill
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
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
