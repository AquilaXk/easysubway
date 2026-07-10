import 'package:flutter/material.dart';

import '../../mobile_error_reporter.dart';
import 'get_off_alarm_controller.dart';
import 'get_off_alarm_route_mapping.dart';

/// 경로 결과에 붙는 하차 알림 진입점(임시). #1704 타임라인 개편 시 그 컴포넌트로
/// 이관하기 쉽도록 로직·표현을 이 위젯 안에 국소화한다 — route_search에는 이
/// 위젯 삽입 1곳과 좁은 인터페이스(controller·leg 투영)만 스레딩한다.
class GetOffAlarmToggle extends StatefulWidget {
  const GetOffAlarmToggle({
    required this.controller,
    required this.routeId,
    required this.rideLegs,
    required this.stationName,
    super.key,
  });

  final GetOffAlarmController controller;
  final String routeId;
  final List<RideLegArrival> rideLegs;
  final Future<String?> Function(String stationId) stationName;

  @override
  State<GetOffAlarmToggle> createState() => _GetOffAlarmToggleState();
}

class _GetOffAlarmToggleState extends State<GetOffAlarmToggle> {
  bool _busy = false;
  int _operationGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GetOffAlarmToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _operationGeneration += 1;
      return;
    }
    if (oldWidget.routeId != widget.routeId ||
        !_sameRideLegs(oldWidget.rideLegs, widget.rideLegs)) {
      _operationGeneration += 1;
    }
  }

  void _onControllerChanged() {
    _operationGeneration += 1;
    if (mounted) {
      setState(() {});
    }
  }

  bool get _isOnForThisRoute {
    final state = widget.controller.state;
    return state.enabled && state.activeRouteId == widget.routeId;
  }

  Future<void> _onToggle(bool enabled) async {
    if (_busy) {
      return;
    }
    final operationGeneration = ++_operationGeneration;
    final routeId = widget.routeId;
    final rideLegs = List<RideLegArrival>.unmodifiable(widget.rideLegs);
    final stationName = widget.stationName;
    setState(() => _busy = true);
    try {
      if (enabled) {
        final stationNames = await _resolveStationNames(
          rideLegs: rideLegs,
          resolveStationName: stationName,
        );
        if (!mounted ||
            operationGeneration != _operationGeneration ||
            widget.routeId != routeId) {
          return;
        }
        final stops = getOffAlarmStopsFromRideLegs(
          rideLegs: rideLegs,
          stationName: (stationId) => stationNames[stationId]!,
          source:
              rideLegs.any((leg) => leg.realtimeArrivalIso?.isNotEmpty ?? false)
              ? GetOffAlarmTimeSource.realtime
              : GetOffAlarmTimeSource.planned,
        );
        await widget.controller.enable(
          routeId: routeId,
          stops: stops,
          transferAlarmEnabled: true,
        );
      } else {
        await widget.controller.disable();
      }
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '하차 알림 설정 중 예외가 발생했습니다.');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('하차 알림을 바꾸지 못했어요. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<Map<String, String>> _resolveStationNames({
    required List<RideLegArrival> rideLegs,
    required Future<String?> Function(String stationId) resolveStationName,
  }) async {
    final stationNames = <String, String>{};
    for (final leg in rideLegs) {
      final stationId = leg.toStationId;
      if (stationNames.containsKey(stationId)) {
        continue;
      }
      final rawName = await resolveStationName(stationId);
      final resolvedStationName = rawName?.trim();
      if (resolvedStationName == null ||
          resolvedStationName.isEmpty ||
          resolvedStationName == stationId) {
        throw StateError('하차 알림 역명을 확인하지 못했습니다.');
      }
      stationNames[stationId] = resolvedStationName;
    }
    return stationNames;
  }

  bool _sameRideLegs(List<RideLegArrival> before, List<RideLegArrival> after) {
    if (before.length != after.length) {
      return false;
    }
    for (var index = 0; index < before.length; index++) {
      final previous = before[index];
      final current = after[index];
      if (previous.toStationId != current.toStationId ||
          previous.plannedArrivalIso != current.plannedArrivalIso ||
          previous.realtimeArrivalIso != current.realtimeArrivalIso) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = _isOnForThisRoute;
    final state = widget.controller.state;
    final notice = on ? state.inexactNotice : state.permissionNotice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: on,
          onChanged: _busy ? null : _onToggle,
          title: const Text('하차 알림'),
          subtitle: Text(
            on ? '도착·환승 전에 알려드려요.' : '폰을 보지 않아도 내릴 때 알려드려요.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (notice != null)
          Semantics(
            key: const Key('getOffAlarmNotice'),
            container: true,
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                notice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
