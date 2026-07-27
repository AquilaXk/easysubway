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
      final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
      final image = Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
      );
      return SizedBox(
        key: Key('stationLineBadge-${line.id}'),
        width: size,
        height: size,
        child: stationLineBadgeNeedsRoundedCorners(assetPath)
            ? ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(size * 0.16)),
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
          fontWeight: FontWeight.w800,
          height: 1.05,
        ),
      ),
    );
  }
}

/// 호선 선택 탭. [StationLineBadge]와 동일 마크에 선택 밑줄만 얹는다.
class StationLineBadgeTab extends StatelessWidget {
  const StationLineBadgeTab({
    required this.line,
    required this.selected,
    required this.onTap,
    this.size = 28,
    super.key,
  });

  final StationSearchLine line;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${line.name} 선택',
      child: InkWell(
        key: Key('stationLineBadgeTab-${line.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              StationLineBadge(line: line, size: size),
              const SizedBox(height: 4),
              Container(
                width: 30,
                height: 2,
                color: selected
                    ? EasySubwayAccessibleColors.interactionPrimary
                    : Colors.transparent,
              ),
            ],
          ),
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
        color: EasySubwayAccessibleColors.scaffoldSurface,
        shape: BoxShape.circle,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Text(
        '+$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: EasySubwayAccessibleColors.mutedText,
          fontSize: 13 * (size / 32),
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}
