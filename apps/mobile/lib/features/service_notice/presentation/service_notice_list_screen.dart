import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../domain/service_notice.dart';
import 'notice_controller.dart';

/// 좌측 메뉴 "공지사항"에서 여는 목록 화면. 활성 공지 전체(info·disruption)를
/// 보여주고, 오프라인 강등이면 마지막 수신 시각을 함께 알린다.
class ServiceNoticeListScreen extends StatelessWidget {
  const ServiceNoticeListScreen({
    required this.controller,
    this.now = DateTime.now,
    super.key,
  });

  final NoticeController controller;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('serviceNoticeAppBar'),
        title: const Text('공지사항'),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider(
            key: Key('serviceNoticeHeaderDivider'),
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final notices = controller.notices;
          final staleLabel = controller.staleLabel(now());
          if (notices.isEmpty) {
            return RefreshIndicator(
              onRefresh: controller.refresh,
              child: _EmptyNotices(staleLabel: staleLabel),
            );
          }
          // stale 바는 리스트 항목이 아니라 헤더로 둔다 — 항목 인덱스가 notices와
          // 1:1이라 offset 산술이 사라진다.
          return RefreshIndicator(
            onRefresh: controller.refresh,
            child: Column(
              children: [
                if (staleLabel != null) _StaleBar(label: staleLabel),
                Expanded(
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: notices.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: EasySubwayAccessibleColors.line,
                    ),
                    itemBuilder: (context, index) =>
                        _NoticeItem(notice: notices[index]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StaleBar extends StatelessWidget {
  const _StaleBar({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('serviceNoticeStaleBar'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.scaffoldSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: EasySubwayAccessibleColors.mutedText,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '오프라인 · $label',
              style: const TextStyle(
                color: EasySubwayAccessibleColors.mutedText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeItem extends StatelessWidget {
  const _NoticeItem({required this.notice});

  final ServiceNotice notice;

  @override
  Widget build(BuildContext context) {
    final isDisruption = notice.isDisruption;
    final accent = isDisruption
        ? EasySubwayAccessibleColors.amber
        : EasySubwayAccessibleColors.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isDisruption ? '운행 장애' : '안내',
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
              const Spacer(),
              Text(
                _formatPublishedAt(notice.publishedAt),
                style: const TextStyle(
                  color: EasySubwayAccessibleColors.brandSignature,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            notice.title,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (notice.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              notice.body,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.secondaryText,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyNotices extends StatelessWidget {
  const _EmptyNotices({this.staleLabel});

  final String? staleLabel;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (staleLabel != null)
          SliverToBoxAdapter(child: _StaleBar(label: staleLabel!)),
        SliverFillRemaining(
          key: const Key('serviceNoticeEmptyFill'),
          hasScrollBody: false,
          child: Align(
            key: const Key('serviceNoticeEmptyContent'),
            alignment: const Alignment(0, -0.28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/illustrations/empty_notices.png',
                  key: const Key('serviceNoticeEmptyImage'),
                  width: 80,
                  height: 80,
                  color: EasySubwayAccessibleColors.brandSignature,
                  colorBlendMode: BlendMode.srcIn,
                ),
                const SizedBox(height: 16),
                const Text(
                  '지금은 공지사항이 없어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: EasySubwayAccessibleColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _formatPublishedAt(DateTime publishedAt) {
  final local = publishedAt.toLocal();
  final month = local.month;
  final day = local.day;
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month월 $day일 $hour:$minute';
}
