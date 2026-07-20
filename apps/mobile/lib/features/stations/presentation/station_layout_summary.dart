import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../application/station_detail_controller.dart';

const _stationLayoutSummaryRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

class StationLayoutSummary extends StatelessWidget {
  const StationLayoutSummary({
    required this.items,
    required this.semanticLabel,
    super.key,
  });

  final List<StationLayoutSummaryItem> items;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final item in items)
                  _StationLayoutStep(
                    item: item,
                    textTheme: textTheme,
                    width: itemWidth,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StationLayoutStep extends StatelessWidget {
  const _StationLayoutStep({
    required this.item,
    required this.textTheme,
    required this.width,
  });

  final StationLayoutSummaryItem item;
  final TextTheme textTheme;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: _stationLayoutSummaryRadius,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: EasySubwayAccessibleColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.text,
              style: textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
