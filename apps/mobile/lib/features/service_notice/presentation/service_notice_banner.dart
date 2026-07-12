import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import 'notice_controller.dart';

/// 노선도 홈 상단에 얹는 disruption 공지 1줄 배너.
///
/// - disruption 심각도만 승격한다(info는 목록에서만 본다).
/// - 모달이 아니라 닫기 가능한 얇은 바다. 본문을 누르면 목록으로 이동한다.
/// - 오프라인 강등이면 "N시간 전 기준" 라벨을 함께 붙인다.
class ServiceNoticeBanner extends StatelessWidget {
  const ServiceNoticeBanner({
    required this.controller,
    required this.onOpenList,
    this.now = DateTime.now,
    super.key,
  });

  final NoticeController controller;
  final VoidCallback onOpenList;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final tokens = EasySubwayTokens.of(context);
        final notice = controller.topDisruption;
        if (notice == null) {
          return const SizedBox.shrink();
        }
        final staleLabel = controller.staleLabel(now());
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            key: const Key('serviceNoticeBanner'),
            color: EasySubwayAccessibleColors.amberSoft,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: tokens.warn,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      key: const Key('serviceNoticeBannerBody'),
                      onTap: onOpenList,
                      child: Semantics(
                        button: true,
                        label: '운행 공지: ${notice.title}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  notice.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: tokens.warn,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              if (staleLabel != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  staleLabel,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: tokens.inkMuted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('serviceNoticeBannerDismiss'),
                    onPressed: () => controller.dismissBanner(notice.id),
                    iconSize: 20,
                    color: tokens.warn,
                    visualDensity: VisualDensity.compact,
                    tooltip: '공지 닫기',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
