import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../application/station_search_controller.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import 'station_line_badges.dart';

class StationSearchBody extends StatelessWidget {
  const StationSearchBody({
    super.key,
    required this.state,
    required this.onResultTap,
  });

  final StationSearchState state;
  final ValueChanged<StationSearchResult> onResultTap;

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
      StationSearchStatus.empty || StationSearchStatus.failure =>
        _StationSearchMessage(message: state.message, liveRegion: true),
      StationSearchStatus.success => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: '검색 결과 ${state.results.length}개',
            liveRegion: true,
            child: const SizedBox(width: 1, height: 1),
          ),
          for (final result in state.results)
            _StationSearchResultTile(
              result: result,
              onTap: () => onResultTap(result),
            ),
        ],
      ),
    };
  }
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
              semanticLabel:
                  '$stationName, ${lines.map((line) => line.name).join(', ')}, 선택',
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

String _stationResultDisplayName(String name) {
  final trimmedName = name.trim();
  // 백엔드 역 이름은 접미사 없이 내려올 수 있어 검색 결과 화면에서만 보정한다.
  if (trimmedName.endsWith('역')) {
    return trimmedName;
  }
  return '$trimmedName역';
}
