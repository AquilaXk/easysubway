import 'package:flutter/material.dart';

import '../../../design_tokens.dart';
import '../domain/service_notice.dart';
import 'notice_controller.dart';

/// 좌측 메뉴 "운행 공지"에서 여는 목록 화면. 활성 공지 전체(info·disruption)를
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
    final tokens = EasySubwayTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.surface,
      appBar: AppBar(
        title: const Text('운행 공지'),
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
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
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
                      color: tokens.line,
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
    final tokens = EasySubwayTokens.of(context);
    return Container(
      key: const Key('serviceNoticeStaleBar'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.scaffold,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: tokens.inkMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '오프라인 · $label',
              style: TextStyle(
                color: tokens.inkMuted,
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
    final tokens = EasySubwayTokens.of(context);
    final isDisruption = notice.isDisruption;
    final accent = isDisruption
        ? tokens.warn
        : tokens.accent;
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
                style: TextStyle(
                  color: tokens.inkMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            notice.title,
            style: TextStyle(
              color: tokens.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (notice.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              notice.body,
              style: TextStyle(
                color: tokens.inkSecondary,
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
    final tokens = EasySubwayTokens.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (staleLabel != null) _StaleBar(label: staleLabel!),
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
        Icon(
          Icons.check_circle_outline_rounded,
          size: 44,
          color: tokens.inkMuted,
        ),
        const SizedBox(height: 14),
        Text(
          '지금은 운행 공지가 없어요',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: tokens.ink,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '운행 장애나 안내가 생기면 여기에 표시돼요',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: tokens.inkMuted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
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
