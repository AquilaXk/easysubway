import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'accessible_design.dart';

/// 실광고 연동 전까지 사용하는 공용 배너 슬롯.
///
/// 노출 규칙(전 화면 공통):
/// - release 빌드: 로드된 실광고([child])가 없으면 슬롯을 렌더링하지 않는다.
///   빈 박스·"광고" 텍스트 플레이스홀더를 release에 상시 노출하지 않는다.
/// - debug/internal 빌드: 자리 확인용 플레이스홀더만 노출한다.
///
/// 실광고 SDK를 연동하면 로드된 배너를 [child]로 전달한다. 로드 실패·무재고면
/// 상위에서 이 위젯을 렌더링하지 않거나 [child]를 null로 두면 슬롯이 collapse된다.
class AdBannerSlot extends StatelessWidget {
  const AdBannerSlot({
    required this.slotKey,
    this.height = 52,
    this.showTopDivider = true,
    this.child,
    super.key,
  });

  final Key slotKey;
  final double height;
  final bool showTopDivider;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ad = child;
    // 실광고가 없는 상태에서 release면 슬롯 자체를 숨긴다(collapse).
    if (ad == null && kReleaseMode) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: '광고',
      child: Container(
        key: slotKey,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surface,
          border: showTopDivider
              ? const Border(
                  top: BorderSide(color: EasySubwayAccessibleColors.line),
                )
              : null,
        ),
        child:
            ad ??
            const Text(
              '광고 미리보기 (개발용)',
              style: TextStyle(
                color: EasySubwayAccessibleColors.mutedText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
      ),
    );
  }
}
