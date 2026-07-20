import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../../../internal_route.dart';
import 'station_detail_info_row.dart';

const _stationInternalRouteRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

class StationInternalRouteGuidance extends StatelessWidget {
  const StationInternalRouteGuidance({required this.state, super.key});

  final InternalRouteState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      InternalRouteViewStatus.loading => Semantics(
        label: '역 안 이동 순서 불러오는 중',
        liveRegion: true,
        child: const StationDetailInfoRow(
          icon: Icons.sync,
          text: '역 안 이동 순서를 불러오는 중입니다.',
        ),
      ),
      InternalRouteViewStatus.failure => Semantics(
        label: state.message,
        liveRegion: true,
        child: StationDetailInfoRow(
          icon: Icons.error_outline,
          text: state.message,
        ),
      ),
      InternalRouteViewStatus.success => _StationInternalRouteResultCard(
        result: state.result!,
      ),
      // 데이터 부재는 사과 문구 없이 숨긴다(#1577).
      InternalRouteViewStatus.unavailable => const SizedBox.shrink(),
    };
  }
}

class _StationInternalRouteResultCard extends StatelessWidget {
  const _StationInternalRouteResultCard({required this.result});

  final InternalRouteResult result;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: result.semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: EasySubwayAccessibleColors.surface,
            borderRadius: _stationInternalRouteRadius,
            border: Border.all(color: EasySubwayAccessibleColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StationDetailInfoRow(
                icon: result.statusIcon,
                text: result.statusLabel,
              ),
              const SizedBox(height: 8),
              Text(
                result.summaryLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result.totalBurdenLabel,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: EasySubwayAccessibleColors.secondaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              if (result.warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final warning in result.warnings)
                  StationDetailInfoRow(
                    icon: Icons.warning_amber,
                    text: warning.message,
                  ),
              ],
              if (result.steps.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final step in result.steps)
                  _StationInternalRouteStepTile(step: step),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StationInternalRouteStepTile extends StatelessWidget {
  const _StationInternalRouteStepTile({required this.step});

  final InternalRouteStep step;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: step.semanticLabel,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                step.title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.burdenLabel,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.secondaryText,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                step.guidance,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
