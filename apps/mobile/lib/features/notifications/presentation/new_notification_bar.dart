import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../service_notice/presentation/notice_controller.dart';

/// 노선도 홈 상단바 바로 아래 얹는 통합 신규 알림 안내 바 (오너 스펙 2026-07-16, #2200).
///
/// 운행 공지 disruption([NoticeController.topDisruption])이 있거나 알림함에
/// 새 항목([hasNotificationItems])이 있으면 전체 너비 바로 안내한다. 둘 다 없으면
/// 빈 공간 없이 사라진다. 바를 누르면 알림함으로 이동한다(단일 탭 경로).
class NewNotificationBar extends StatelessWidget {
  const NewNotificationBar({
    required this.noticeController,
    required this.hasNotificationItems,
    required this.onOpenInbox,
    super.key,
  });

  final NoticeController? noticeController;
  final bool hasNotificationItems;
  final VoidCallback onOpenInbox;

  @override
  Widget build(BuildContext context) {
    final controller = noticeController;
    if (controller == null) {
      return _buildBar(visible: hasNotificationItems);
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final visible =
            controller.topDisruption != null || hasNotificationItems;
        return _buildBar(visible: visible);
      },
    );
  }

  Widget _buildBar({required bool visible}) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    return Semantics(
      button: true,
      label: '새로운 알림이 있어요, 알림 보기',
      onTap: onOpenInbox,
      child: ExcludeSemantics(
        child: Material(
          key: const Key('newNotificationBar'),
          color: EasySubwayAccessibleColors.noticeBarSurface,
          child: InkWell(
            onTap: onOpenInbox,
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: EasySubwayAccessibleColors.noticeBarBorder,
                  ),
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 22),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_none,
                        size: 20,
                        color: EasySubwayAccessibleColors.noticeBarAccent,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '새로운 알림이 있어요',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: EasySubwayAccessibleColors.noticeBarText,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: const [
                            Text(
                              '알림 보기',
                              style: TextStyle(
                                color:
                                    EasySubwayAccessibleColors.noticeBarAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 3),
                            SizedBox(
                              height: 1,
                              child: ColoredBox(
                                color:
                                    EasySubwayAccessibleColors.noticeBarAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
