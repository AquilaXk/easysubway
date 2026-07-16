import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';

class StationRecentSearchSection extends StatelessWidget {
  const StationRecentSearchSection({
    super.key,
    required this.queries,
    required this.enabled,
    required this.onQuerySelected,
    required this.onQueryRemoved,
    required this.onClearAll,
  });

  final List<String> queries;
  final bool enabled;
  final ValueChanged<String> onQuerySelected;
  final ValueChanged<String> onQueryRemoved;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('stationRecentSearchSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '최근 검색',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            TextButton.icon(
              key: const Key('stationRecentSearchClearAllButton'),
              style: TextButton.styleFrom(
                foregroundColor: EasySubwayAccessibleColors.mutedText,
              ),
              onPressed: enabled ? onClearAll : null,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('전체 삭제'),
            ),
          ],
        ),
        const Divider(
          height: EasySubwaySpacing.lg,
          color: EasySubwayAccessibleColors.line,
        ),
        Column(
          children: [
            for (final entry in queries.indexed) ...[
              if (entry.$1 > 0)
                const Divider(
                  height: 1,
                  color: EasySubwayAccessibleColors.line,
                ),
              _StationRecentSearchItem(
                query: entry.$2,
                order: entry.$1 + 1,
                enabled: enabled,
                onQuerySelected: onQuerySelected,
                onQueryRemoved: onQueryRemoved,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _StationRecentSearchItem extends StatelessWidget {
  const _StationRecentSearchItem({
    required this.query,
    required this.order,
    required this.enabled,
    required this.onQuerySelected,
    required this.onQueryRemoved,
  });

  final String query;
  final int order;
  final bool enabled;
  final ValueChanged<String> onQuerySelected;
  final ValueChanged<String> onQueryRemoved;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: '최근 검색어 $query 검색, 최근 사용 $order번째',
              button: true,
              enabled: enabled,
              onTap: enabled ? () => onQuerySelected(query) : null,
              child: ExcludeSemantics(
                child: InkWell(
                  key: Key('stationRecentSearchQuery-$query'),
                  onTap: enabled ? () => onQuerySelected(query) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: EasySubwaySpacing.md,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.history,
                          color: EasySubwayAccessibleColors.iconMuted,
                        ),
                        const SizedBox(width: EasySubwaySpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                query,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: EasySubwayAccessibleColors.text,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                              ),
                              Text(
                                '최근 사용 $order번째',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: EasySubwayAccessibleColors.caption,
                                      height: 1.3,
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
          IconButton(
            key: Key('stationRecentSearchRemove-$query'),
            tooltip: '$query 최근 검색 삭제',
            onPressed: enabled ? () => onQueryRemoved(query) : null,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
