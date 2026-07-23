import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../domain/station_line.dart';
import '../domain/station_repositories.dart';
import 'station_line_badges.dart';

/// 최근 검색 모두 지우기 확인 다이얼로그. `true`면 지우기.
Future<bool?> confirmClearRecentSearches(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('최근 검색 모두 지우기'),
        content: const Text('이 지역의 최근 검색·경로 기록을 모두 지울까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            key: const Key('stationRecentSearchClearAllConfirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('지우기'),
          ),
        ],
      );
    },
  );
}

/// 역 검색 화면·노선도 임베디드 검색의 최근 목록. 역·경로를 한 시간순 목록으로
/// 통합한다. 상단은 `최근 검색` / `모두 지우기` 헤더다.
///
/// 항목 사이·헤더 아래에는 구분선을 **추가하지 않는다**(상단 네비바 아래
/// 기존 구분선은 화면 레이아웃이 담당하며 여기서 건드리지 않는다).
/// 지역 필터는 호출부가 [entries]를 좁혀 전달한다.
class StationRecentSearchSection extends StatelessWidget {
  const StationRecentSearchSection({
    super.key,
    required this.entries,
    required this.enabled,
    required this.onStationSelected,
    required this.onRouteSelected,
    required this.onRemove,
    required this.onClearAll,
  });

  final List<RecentSearchEntry> entries;
  final bool enabled;
  final ValueChanged<RecentStationSearchEntry> onStationSelected;
  final ValueChanged<RecentRouteSearchEntry> onRouteSelected;
  final ValueChanged<RecentSearchEntry> onRemove;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final hasEntries = entries.isNotEmpty;
    return Column(
      key: const Key('stationRecentSearchSection'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 내역이 없을 때는 헤더(최근 검색 / 모두 지우기)를 숨긴다.
        if (hasEntries)
          _RecentSearchHeader(enabled: enabled, onClearAll: onClearAll),
        if (!hasEntries)
          const _RecentSearchEmptyState()
        else
          for (final entry in entries)
            _RecentSearchItem(
              entry: entry,
              enabled: enabled,
              onStationSelected: onStationSelected,
              onRouteSelected: onRouteSelected,
              onRemove: onRemove,
            ),
      ],
    );
  }
}

class _RecentSearchHeader extends StatelessWidget {
  const _RecentSearchHeader({required this.enabled, required this.onClearAll});

  final bool enabled;
  final VoidCallback onClearAll;

  static const _titleStyle = TextStyle(
    fontSize: 16,
    // #1915: 섹션 헤더는 w800 금지. 화면 타이틀 전용 ratchet 유지.
    fontWeight: FontWeight.w700,
    height: 1.0,
    color: EasySubwayAccessibleColors.text,
  );

  static const _clearStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.0,
    color: EasySubwayAccessibleColors.brandSignature,
  );

  @override
  Widget build(BuildContext context) {
    // #2419 리뷰: GestureDetector만으로는 버튼 semantics·최소 터치 영역(48px)이
    // 없었다. InkWell + Semantics(button)로 복원하고, baseline 대신 center로
    // 정렬한다(48px 터치 영역이 텍스트보다 커서 baseline이 어긋난다).
    return Padding(
      padding: const EdgeInsets.only(bottom: EasySubwaySpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(child: Text('최근 검색', style: _titleStyle)),
          Semantics(
            button: true,
            enabled: enabled,
            label: '모두 지우기',
            onTap: enabled ? onClearAll : null,
            child: ExcludeSemantics(
              child: InkWell(
                key: const Key('stationRecentSearchClearAllButton'),
                onTap: enabled ? onClearAll : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: EasySubwayTouchTarget.iconOnly,
                    minHeight: EasySubwayTouchTarget.iconOnly,
                  ),
                  child: const Center(
                    child: Text('모두 지우기', style: _clearStyle),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSearchEmptyState extends StatelessWidget {
  const _RecentSearchEmptyState();

  static const _message = '최근 검색 내역이 없습니다.';
  // 카카오메트로 빈 상태와 같은 연회색. 크기는 살짝 더 큼(아이콘 56·글자 16).
  static const _iconSize = 56.0;
  static const _emptyTone = EasySubwayAccessibleColors.disclosure;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final minHeight =
        (media.size.height -
                media.padding.top -
                media.viewInsets.bottom -
                easySubwayTopBarContentHeight -
                48)
            .clamp(220.0, 640.0);

    return Semantics(
      key: const Key('stationRecentSearchEmptyState'),
      container: true,
      label: _message,
      child: SizedBox(
        width: double.infinity,
        height: minHeight,
        child: Align(
          // 정중앙보다 위: 키보드 있으면 더 위, 없으면 상단 1/3 부근.
          alignment: Alignment(0, keyboardOpen ? -0.75 : -0.55),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/illustrations/empty_recent_search_warning.png',
                key: const Key('stationRecentSearchEmptyImage'),
                width: _iconSize,
                height: _iconSize,
                color: _emptyTone,
                colorBlendMode: BlendMode.srcIn,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: EasySubwaySpacing.md),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _emptyTone,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSearchItem extends StatelessWidget {
  const _RecentSearchItem({
    required this.entry,
    required this.enabled,
    required this.onStationSelected,
    required this.onRouteSelected,
    required this.onRemove,
  });

  final RecentSearchEntry entry;
  final bool enabled;
  final ValueChanged<RecentStationSearchEntry> onStationSelected;
  final ValueChanged<RecentRouteSearchEntry> onRouteSelected;
  final ValueChanged<RecentSearchEntry> onRemove;

  static const _badgeSize = 26.0;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: EasySubwayAccessibleColors.text,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );
    final (
      itemKey,
      removeKey,
      removeTooltip,
      semanticsLabel,
      leading,
      title,
    ) = switch (entry) {
      RecentStationSearchEntry() => (
        Key('stationRecentSearchQuery-${entry.query}'),
        Key('stationRecentSearchRemove-${entry.query}'),
        '${entry.query} 최근 검색 삭제',
        '최근 검색어 ${entry.query} 검색',
        _stationLeading(entry.lines),
        Text(entry.query, style: titleStyle),
      ),
      RecentRouteSearchEntry() => (
        Key(
          'recentRouteSearch-${entry.originStationId}-'
          '${entry.waypointStationId ?? ''}-${entry.destinationStationId}',
        ),
        Key(
          'recentRouteSearchRemove-${entry.originStationId}-'
          '${entry.waypointStationId ?? ''}-${entry.destinationStationId}',
        ),
        '${entry.displayLabel} 최근 경로 삭제',
        '최근 경로 ${entry.displayLabel} 다시 찾기',
        null,
        _RouteStationsLabel(entry: entry, textStyle: titleStyle),
      ),
    };

    void onTap() {
      switch (entry) {
        case RecentStationSearchEntry():
          onStationSelected(entry);
        case RecentRouteSearchEntry():
          onRouteSelected(entry);
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: semanticsLabel,
              button: true,
              enabled: enabled,
              onTap: enabled ? onTap : null,
              child: ExcludeSemantics(
                child: InkWell(
                  key: itemKey,
                  onTap: enabled ? onTap : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: EasySubwaySpacing.xs,
                    ),
                    child: Row(
                      children: [
                        if (leading != null) ...[
                          leading,
                          const SizedBox(width: EasySubwaySpacing.sm),
                        ],
                        Expanded(child: title),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            key: removeKey,
            tooltip: removeTooltip,
            onPressed: enabled ? () => onRemove(entry) : null,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  static Widget _stationLeading(List<StationSearchLine> lines) {
    if (lines.isEmpty) {
      return const Icon(
        Icons.train_outlined,
        color: EasySubwayAccessibleColors.iconMuted,
      );
    }
    return StationLineBadges(lines: lines, size: _badgeSize, maxBadgeCount: 3);
  }
}

class _RouteStationsLabel extends StatelessWidget {
  const _RouteStationsLabel({required this.entry, required this.textStyle});

  final RecentRouteSearchEntry entry;
  final TextStyle? textStyle;

  static const _badgeSize = 26.0;
  static const _arrowStyle = TextStyle(
    color: EasySubwayAccessibleColors.mutedText,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  @override
  Widget build(BuildContext context) {
    final waypointName = entry.waypointStationName?.trim();
    final hasWaypoint = waypointName != null && waypointName.isNotEmpty;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _station(entry.originStationName, entry.originLines),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('→', style: _arrowStyle),
          ),
          if (hasWaypoint) ...[
            _station(waypointName, entry.waypointLines),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('→', style: _arrowStyle),
            ),
          ],
          _station(entry.destinationStationName, entry.destinationLines),
        ],
      ),
    );
  }

  Widget _station(String name, List<StationSearchLine> lines) {
    final label = _withStationSuffix(name);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lines.isNotEmpty) ...[
          StationLineBadges(lines: lines, size: _badgeSize, maxBadgeCount: 2),
          const SizedBox(width: 6),
        ],
        Text(label, style: textStyle),
      ],
    );
  }
}

String _withStationSuffix(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.endsWith('역')) {
    return trimmed;
  }
  return '$trimmed역';
}
