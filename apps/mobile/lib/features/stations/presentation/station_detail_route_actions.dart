import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../../route_draft/application/route_draft_controller.dart';
import '../../route_draft/domain/route_draft.dart';
import '../application/station_detail_controller.dart';
import '../domain/station_models.dart';

const _stationDetailActionButtonRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.card),
);

class StationDetailRouteActions extends StatelessWidget {
  const StationDetailRouteActions({
    required this.detail,
    required this.routeDraftController,
    required this.favoriteController,
    super.key,
  });

  final StationDetail detail;
  final RouteDraftController? routeDraftController;
  final StationFavoriteToggleController? favoriteController;

  @override
  Widget build(BuildContext context) {
    // 상용 지도·교통 앱처럼 출발·도착·저장을 한 줄의 동등한 액션으로 묶는다.
    final draftController = routeDraftController;
    final favController = favoriteController;
    final station = RouteDraftStation(id: detail.id, nameKo: detail.nameKo);
    final buttons = <Widget>[
      if (draftController != null) ...[
        _StationPointButton(
          key: const Key('stationDetailSetOriginButton'),
          icon: Icons.trip_origin,
          label: '출발',
          onPressed: () {
            draftController.setOrigin(station);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${station.displayName}을 출발역으로 설정했습니다')),
            );
          },
        ),
        _StationPointButton(
          key: const Key('stationDetailSetDestinationButton'),
          icon: Icons.flag_outlined,
          label: '도착',
          onPressed: () {
            draftController.setDestination(station);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${station.displayName}을 도착역으로 설정했습니다')),
            );
          },
        ),
      ],
      if (favController != null)
        _StationFavoriteButton(detail: detail, controller: favController),
    ];
    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }
}

class _StationFavoriteButton extends StatelessWidget {
  const _StationFavoriteButton({
    required this.detail,
    required this.controller,
  });

  final StationDetail detail;
  final StationFavoriteToggleController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final isFavorite = state.isFavorite;
        final label = switch (state.status) {
          StationFavoriteToggleStatus.checking => '확인 중',
          StationFavoriteToggleStatus.saving => '저장 중',
          StationFavoriteToggleStatus.removing => '해제 중',
          StationFavoriteToggleStatus.ready ||
          StationFavoriteToggleStatus.failure => isFavorite ? '저장됨' : '저장',
        };
        final actionLabel = state.status == StationFavoriteToggleStatus.checking
            ? '즐겨찾기 확인 중'
            : isFavorite
            ? '즐겨찾기 해제'
            : '즐겨찾기 저장';
        final onPressed = state.isBusy
            ? null
            : () async {
                if (isFavorite) {
                  await controller.remove();
                } else {
                  await controller.save();
                }
                if (!context.mounted) {
                  return;
                }
                // 연속 토글에서도 가장 최근 저장·해제 결과만 바로 알린다.
                final message = controller.state.message;
                if (message.isNotEmpty) {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(content: Text(message)));
                }
              };
        return Semantics(
          container: true,
          label: '${detail.nameKo}역 $actionLabel',
          button: true,
          onTap: onPressed,
          child: ExcludeSemantics(
            child: _StationPointButton(
              key: const Key('stationFavoriteToggleButton'),
              icon: isFavorite ? Icons.star : Icons.star_border,
              label: label,
              onPressed: onPressed,
            ),
          ),
        );
      },
    );
  }
}

class _StationPointButton extends StatelessWidget {
  const _StationPointButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(EasySubwayTouchTarget.general),
        backgroundColor: Colors.white,
        foregroundColor: EasySubwayAccessibleColors.primary,
        side: const BorderSide(color: EasySubwayAccessibleColors.line),
        shape: const RoundedRectangleBorder(
          borderRadius: _stationDetailActionButtonRadius,
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      icon: Icon(icon, size: 22),
      label: Text(label),
    );
  }
}
