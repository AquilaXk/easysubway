import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../application/station_search_controller.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import 'station_line_badges.dart';

const _currentLocationDisabledMessage =
    '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.';
const _currentLocationPermissionMessage = '현재 위치를 사용할 수 없어요.';
const _stationSearchFailureNextAction =
    '역명으로 검색하면 현재 위치를 쓰지 않아도 계속 이용할 수 있습니다.';
const _stationRoleActionPadding = EdgeInsets.fromLTRB(12, 0, 12, 12);
const _stationSearchFacilityCardRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

class StationSearchBody extends StatelessWidget {
  const StationSearchBody({
    super.key,
    required this.state,
    required this.onResultTap,
    required this.isOpeningLocationSettings,
    required this.onOpenLocationSettings,
    this.onSetOrigin,
    this.onSetDestination,
  });

  final StationSearchState state;
  final ValueChanged<StationSearchResult> onResultTap;
  final bool isOpeningLocationSettings;
  final VoidCallback onOpenLocationSettings;
  final ValueChanged<StationSearchResult>? onSetOrigin;
  final ValueChanged<StationSearchResult>? onSetDestination;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationSearchStatus.idle => const SizedBox.shrink(),
      StationSearchStatus.loading => Semantics(
        label: '역 검색 중',
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      StationSearchStatus.empty ||
      StationSearchStatus.failure => _StationSearchFailureMessage(
        message: state.message,
        isOpeningLocationSettings: isOpeningLocationSettings,
        onOpenLocationSettings: onOpenLocationSettings,
      ),
      StationSearchStatus.success => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: state.source == StationSearchResultSource.nearby
                ? '주변 역 ${state.results.length}개'
                : '검색 결과 ${state.results.length}개',
            liveRegion: true,
            child: const SizedBox(width: 1, height: 1),
          ),
          if (state.source == StationSearchResultSource.nearby) ...[
            if (state.results.isEmpty)
              _StationSearchFailureMessage(
                message: '주변 역을 찾지 못했어요.',
                isOpeningLocationSettings: isOpeningLocationSettings,
                onOpenLocationSettings: onOpenLocationSettings,
              )
            else ...[
              _NearbyStationOverview(
                result: state.results.first,
                onTap: () => onResultTap(state.results.first),
                onSetOrigin: onSetOrigin == null
                    ? null
                    : () => onSetOrigin!(state.results.first),
                onSetDestination: onSetDestination == null
                    ? null
                    : () => onSetDestination!(state.results.first),
              ),
              if (state.results.length > 1) ...[
                const SizedBox(height: 18),
                const _StationSearchSectionTitle(title: '다른 주변 역'),
                const SizedBox(height: 12),
              ],
            ],
          ],
          for (final result
              in state.source == StationSearchResultSource.nearby
                  ? state.results.skip(1)
                  : state.results)
            _StationSearchResultTile(
              result: result,
              onTap: () => onResultTap(result),
            ),
        ],
      ),
    };
  }
}

class _NearbyStationOverview extends StatelessWidget {
  const _NearbyStationOverview({
    required this.result,
    required this.onTap,
    this.onSetOrigin,
    this.onSetDestination,
  });

  final StationSearchResult result;
  final VoidCallback onTap;
  final VoidCallback? onSetOrigin;
  final VoidCallback? onSetDestination;

  @override
  Widget build(BuildContext context) {
    final stationName = _stationResultDisplayName(result.nameKo);
    return Card(
      margin: EdgeInsets.zero,
      color: EasySubwayAccessibleColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: _stationSearchFacilityCardRadius,
        side: const BorderSide(color: EasySubwayAccessibleColors.line),
      ),
      child: Column(
        children: [
          Semantics(
            container: true,
            button: true,
            label: '가장 가까운 역, ${_stationResultSemanticLabel(result)}',
            onTap: onTap,
            child: ExcludeSemantics(
              child: InkWell(
                key: const Key('nearbyStationPrimaryCard'),
                borderRadius: _stationSearchFacilityCardRadius,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '가장 가까운 역',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.mutedText,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              stationName,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.text,
                                    fontWeight: FontWeight.w700,
                                    height: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              result.distanceLabel.isEmpty
                                  ? result.lineLabel
                                  : '${result.distanceLabel} · ${result.lineLabel}',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.mutedText,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      StationLineBadges(
                        lines: result.lines,
                        size: 38,
                        maxBadgeCount: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onSetOrigin != null || onSetDestination != null)
            _StationRoleActionBar(
              stationId: result.id,
              stationName: stationName,
              onSetOrigin: onSetOrigin,
              onSetDestination: onSetDestination,
            ),
        ],
      ),
    );
  }
}

class _StationSearchFailureMessage extends StatelessWidget {
  const _StationSearchFailureMessage({
    required this.message,
    required this.isOpeningLocationSettings,
    required this.onOpenLocationSettings,
  });

  final String message;
  final bool isOpeningLocationSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final shouldShowLocationSettings =
        message == _currentLocationDisabledMessage;
    final shouldShowStationSearchNextAction =
        _shouldShowStationSearchFailureNextAction(message);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StationSearchMessage(message: message, liveRegion: true),
        if (shouldShowStationSearchNextAction) ...[
          const SizedBox(height: 8),
          Semantics(
            key: const Key('stationSearchFailureNextAction'),
            container: true,
            excludeSemantics: true,
            label: '도움말, $_stationSearchFailureNextAction',
            child: Text(
              _stationSearchFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.mutedText,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
        if (shouldShowLocationSettings) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('stationSearchOpenLocationSettingsButton'),
            onPressed: isOpeningLocationSettings
                ? null
                : onOpenLocationSettings,
            icon: isOpeningLocationSettings
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.settings),
            label: const Text('위치 설정 열기'),
          ),
        ],
      ],
    );
  }
}

bool _shouldShowStationSearchFailureNextAction(String message) {
  return message == _currentLocationPermissionMessage ||
      message == _currentLocationDisabledMessage ||
      message == '현재 위치를 확인하지 못했어요.' ||
      message == '주변 역을 찾지 못했어요.';
}

class _StationSearchMessage extends StatelessWidget {
  const _StationSearchMessage({required this.message, this.liveRegion = false});

  final String message;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: EasySubwayAccessibleColors.secondaryText,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _StationSearchResultTile extends StatelessWidget {
  const _StationSearchResultTile({required this.result, required this.onTap});

  final StationSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stationName = _stationResultDisplayName(result.nameKo);
    // 역이 지나는 노선마다 한 행씩 표시한다. 각 행은 하단 구분선만 두고
    // 좌측에 무채색 역명, 우측에 해당 노선 배지를 둔다(추가 텍스트·화살표 없음).
    final lines = result.lines;
    if (lines.isEmpty) {
      return _StationSearchResultLineRow(
        key: Key('stationSearchResult-${result.id}'),
        stationName: stationName,
        line: null,
        semanticLabel: '$stationName, 선택',
        onTap: onTap,
      );
    }
    return Column(
      children: [
        for (var i = 0; i < lines.length; i++)
          // 한 역이 여러 노선을 지나면 시각적으로는 노선마다 한 행씩 펼치지만,
          // 각 행이 "역명, 노선명, 선택" 버튼 시맨틱을 노출하면 스크린리더에 같은
          // 선택 버튼이 노선 수만큼 뜬다. 첫 행만 시맨틱 버튼으로 남기고 이후
          // 행들은 ExcludeSemantics 로 감싸 시각 렌더만 유지한다.
          if (i == 0)
            _StationSearchResultLineRow(
              // 첫 행에만 대표 키를 두어 기존 테스트가 단일 위젯을 찾도록 한다.
              key: Key('stationSearchResult-${result.id}'),
              stationName: stationName,
              line: lines[i],
              semanticLabel: '$stationName, ${lines[i].name}, 선택',
              onTap: onTap,
            )
          else
            ExcludeSemantics(
              child: _StationSearchResultLineRow(
                stationName: stationName,
                line: lines[i],
                semanticLabel: '$stationName, ${lines[i].name}, 선택',
                onTap: onTap,
              ),
            ),
      ],
    );
  }
}

class _StationSearchResultLineRow extends StatelessWidget {
  const _StationSearchResultLineRow({
    required this.stationName,
    required this.line,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String stationName;
  final StationSearchLine? line;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = this.line;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
      ),
      child: MergeSemantics(
        child: Semantics(
          label: semanticLabel,
          button: true,
          onTap: onTap,
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onTap,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          stationName,
                          style: const TextStyle(
                            color: EasySubwayAccessibleColors.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (line != null) ...[
                        const SizedBox(width: 12),
                        StationLineBadge(line: line, size: 32),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StationRoleActionBar extends StatelessWidget {
  const _StationRoleActionBar({
    required this.stationId,
    required this.stationName,
    this.onSetOrigin,
    this.onSetDestination,
  });

  final String stationId;
  final String stationName;
  final VoidCallback? onSetOrigin;
  final VoidCallback? onSetDestination;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _stationRoleActionPadding,
      child: Row(
        children: [
          Expanded(
            child: _StationRoleButton(
              key: Key('stationRoleOrigin-$stationId'),
              icon: Icons.trip_origin,
              label: '출발',
              semanticLabel: '$stationName을 출발역으로 설정',
              onPressed: onSetOrigin,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StationRoleButton(
              key: Key('stationRoleDestination-$stationId'),
              icon: Icons.flag_outlined,
              label: '도착',
              semanticLabel: '$stationName을 도착역으로 설정',
              onPressed: onSetDestination,
            ),
          ),
        ],
      ),
    );
  }
}

class _StationRoleButton extends StatelessWidget {
  const _StationRoleButton({
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(EasySubwayTouchTarget.iconOnly),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
          icon: Icon(icon, size: 20),
          label: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

String _stationResultDisplayName(String name) {
  final trimmedName = name.trim();
  // 백엔드 역 이름은 접미사 없이 내려올 수 있어 검색 결과 화면에서만 보정한다.
  if (trimmedName.endsWith('역')) {
    return trimmedName;
  }
  return '$trimmedName역';
}

String _stationResultSemanticLabel(StationSearchResult result) {
  final stationName = _stationResultDisplayName(result.nameKo);
  final distance = result.distanceLabel;
  if (distance.isEmpty) {
    return '$stationName, ${result.lineLabel}, ${result.region}';
  }
  return '$stationName, $distance, ${result.lineLabel}, ${result.region}';
}

class _StationSearchSectionTitle extends StatelessWidget {
  const _StationSearchSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}
