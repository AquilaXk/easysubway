import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../../realtime/realtime_repository.dart';

const _stationRealtimeSummaryRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

class StationRealtimeSummary extends StatelessWidget {
  const StationRealtimeSummary({
    required this.snapshot,
    required this.onRetry,
    super.key,
  });

  final RealtimeSnapshot snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final title = switch (snapshot.status) {
      RealtimeSnapshotStatus.fresh => '도착 정보',
      RealtimeSnapshotStatus.stale => '최근 도착 정보',
      RealtimeSnapshotStatus.unsupported => '실시간 정보 미지원',
      RealtimeSnapshotStatus.unavailable => '실시간 정보 확인 불가',
      RealtimeSnapshotStatus.loading => '실시간 정보 확인 중',
    };
    // 실시간 조회가 실패로 끝난 경우에만 다시 시도를 권한다. 미지원 노선은
    // 재시도해도 결과가 같으므로 버튼을 노출하지 않는다.
    final canRetry = snapshot.status == RealtimeSnapshotStatus.unavailable;
    final summary = snapshot.summaryText.trim().isEmpty
        ? '역 정보와 경로 검색은 계속 이용할 수 있습니다.'
        : snapshot.summaryText.trim();
    final updatedLabel = snapshot.receivedAt.trim().isEmpty
        ? ''
        : '마지막 갱신 ${snapshot.receivedAt}';
    final semanticParts = [
      '실시간 열차',
      title,
      summary,
      if (updatedLabel.isNotEmpty) updatedLabel,
      if (canRetry) '다시 시도할 수 있어요',
    ];
    return Semantics(
      label: semanticParts.join(', '),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surfaceDefault,
          borderRadius: _stationRealtimeSummaryRadius,
          border: Border.all(color: EasySubwayAccessibleColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.schedule,
                  color: EasySubwayAccessibleColors.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              summary,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (updatedLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                updatedLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  height: 1.3,
                ),
              ),
            ],
            if (canRetry) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('stationRealtimeRetryButton'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 20),
                  label: const Text('다시 시도'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
