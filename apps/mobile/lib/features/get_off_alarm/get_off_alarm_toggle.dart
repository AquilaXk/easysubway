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
  final String Function(String stationId) stationName;

  @override
  State<GetOffAlarmToggle> createState() => _GetOffAlarmToggleState();
}

class _GetOffAlarmToggleState extends State<GetOffAlarmToggle> {
  bool _busy = false;

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

  void _onControllerChanged() {
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
    setState(() => _busy = true);
    try {
      if (enabled) {
        final stops = getOffAlarmStopsFromRideLegs(
          rideLegs: widget.rideLegs,
          stationName: widget.stationName,
        );
        await widget.controller.enable(
          routeId: widget.routeId,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = _isOnForThisRoute;
    final notice = on ? widget.controller.state.inexactNotice : null;

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
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              notice,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
