import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'accessible_design.dart';

/// 표준 배너 규격(아이콘 + 제목/부제 + CTA) 기준 슬롯 높이 (#1931).
const double kAdBannerSlotStandardHeight = 96;

/// 실광고 연동 전까지 사용하는 공용 배너 슬롯.
///
/// 노출 규칙(전 화면 공통):
/// - release 빌드: 로드된 실광고([child])가 없으면 슬롯을 렌더링하지 않는다.
///   빈 박스·"광고" 텍스트 플레이스홀더를 release에 상시 노출하지 않는다.
/// - debug/internal 빌드: 자리 확인용 플레이스홀더만 노출한다. 표준 배너
///   규격(아이콘·제목/부제·CTA)을 그대로 반영해 실제 배치 시 크기를 체감할
///   수 있게 한다.
///
/// 실광고 SDK를 연동하면 로드된 배너를 [child]로 전달한다. 로드 실패·무재고면
/// 상위에서 이 위젯을 렌더링하지 않거나 [child]를 null로 두면 슬롯이 collapse된다.
class AdBannerSlot extends StatelessWidget {
  const AdBannerSlot({
    required this.slotKey,
    this.height = kAdBannerSlotStandardHeight,
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
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surface,
          border: showTopDivider
              ? const Border(
                  top: BorderSide(color: EasySubwayAccessibleColors.line),
                )
              : null,
        ),
        child: ad ?? const _AdBannerSlotDevPlaceholder(),
      ),
    );
  }
}

/// 개발 빌드 전용 플레이스홀더 — 표준 배너 레이아웃(아이콘/제목·부제/CTA)만
/// 중립 블록으로 보여준다. 실제 광고 콘텐츠·브랜드 요소는 없다.
class _AdBannerSlotDevPlaceholder extends StatelessWidget {
  const _AdBannerSlotDevPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      child: Row(
        children: [
          // 아이콘 영역 플레이스홀더.
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.line,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.image_outlined,
              color: EasySubwayAccessibleColors.mutedText,
            ),
          ),
          const SizedBox(width: 12),
          // 제목/부제 플레이스홀더. 시스템 글자 크기가 커도 슬롯 높이를 넘지 않도록
          // 각 줄을 FittedBox로 축소한다(장식용 자리표시 텍스트, 실제 정보 없음).
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '광고 미리보기 (개발용)',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                  ),
                ),
                SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '표준 배너 규격 자리표시 텍스트',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // CTA 버튼 영역 플레이스홀더.
          Container(
            width: 64,
            height: 32,
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.line,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}
