import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../domain/station_line.dart';

class StationLineBadges extends StatelessWidget {
  const StationLineBadges({
    required this.lines,
    this.size = 40,
    this.maxBadgeCount,
    super.key,
  });

  final List<StationSearchLine> lines;
  final double size;
  final int? maxBadgeCount;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxCount = maxBadgeCount;
    final shouldCollapse = maxCount != null && lines.length > maxCount;
    final visibleLineCount = shouldCollapse
        ? (maxCount - 1).clamp(1, lines.length).toInt()
        : lines.length;
    final hiddenLineCount = lines.length - visibleLineCount;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final line in lines.take(visibleLineCount))
          StationLineBadge(line: line, size: size),
        if (hiddenLineCount > 0)
          _StationLineOverflowBadge(count: hiddenLineCount, size: size),
      ],
    );
  }
}

class StationLineBadge extends StatelessWidget {
  const StationLineBadge({required this.line, this.size = 40, super.key});

  final StationSearchLine line;
  final double size;

  @override
  Widget build(BuildContext context) {
    final assetPath = line.badgeAssetPath;
    if (assetPath != null) {
      final image = Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
      return SizedBox(
        key: Key('stationLineBadge-${line.id}'),
        width: size,
        height: size,
        child: stationLineBadgeNeedsRoundedCorners(assetPath)
            ? ClipRRect(
                borderRadius: BorderRadius.circular(size * 0.16),
                child: image,
              )
            : image,
      );
    }

    final backgroundColor = line.badgeColor;
    final foregroundColor = stationLineTextColor(backgroundColor);
    final badgeText = line.badgeText;
    final scale = size / 40;
    final badgeFontSize = RegExp(r'^\d+$').hasMatch(badgeText)
        ? 25.0 * scale
        : 15.0 * scale;

    return Container(
      key: Key('stationLineBadge-${line.id}'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Text(
        badgeText,
        textAlign: TextAlign.center,
        maxLines: 2,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: foregroundColor,
          fontSize: badgeFontSize,
          fontWeight: FontWeight.w900,
          height: 1.05,
        ),
      ),
    );
  }
}

class _StationLineOverflowBadge extends StatelessWidget {
  const _StationLineOverflowBadge({required this.count, required this.size});

  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('stationLineBadgeOverflow'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.skySoft,
        shape: BoxShape.circle,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Text(
        '+$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: EasySubwayAccessibleColors.mutedText,
          fontSize: 13 * (size / 32),
          fontWeight: FontWeight.w900,
          height: 1.0,
        ),
      ),
    );
  }
}
