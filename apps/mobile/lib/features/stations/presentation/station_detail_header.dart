import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../domain/station_models.dart';
import 'station_line_badges.dart';

class StationDetailHeader extends StatelessWidget {
  const StationDetailHeader({required this.detail, super.key});

  final StationDetail detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: detail.semanticLabel,
      header: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StationLineBadges(lines: detail.lines, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${detail.nameKo}역',
                      style: textTheme.headlineSmall?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    // 부역명은 분리된 값이 있을 때만 역명 아래 보조 표기로 노출한다.
                    if (detail.nameSub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail.nameSub,
                        style: textTheme.bodyMedium?.copyWith(
                          color: EasySubwayAccessibleColors.secondaryText,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      detail.lineLabel,
                      style: textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.secondaryText,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    '마지막 확인',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stationVerifiedRelativeLabel(detail.lastVerifiedAt),
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
