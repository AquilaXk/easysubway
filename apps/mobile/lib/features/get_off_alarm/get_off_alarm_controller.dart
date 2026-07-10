import 'package:flutter/foundation.dart';

import '../../notification_settings.dart';
import 'data/get_off_alarm_state_repository.dart';
import 'exact_alarm_permission.dart';
import 'get_off_alarm_notifier.dart';
import 'get_off_alarm_policy.dart';
import 'get_off_alarm_schedule_mode.dart';
import 'get_off_alarm_scheduler.dart';
import 'get_off_alarm_subscription.dart';

/// 하차 알림의 현재 상태(화면 표시용).
@immutable
class GetOffAlarmState {
  const GetOffAlarmState({
    this.enabled = false,
    this.activeRouteId,
    this.scheduleMode,
    this.inexactNotice,
    this.permissionNotice,
    this.scheduledCount = 0,
  });

  final bool enabled;
  final String? activeRouteId;
  final GetOffAlarmScheduleMode? scheduleMode;

  /// 부정확 예약으로 강등됐을 때의 오차 고지 문구(없으면 null).
  final String? inexactNotice;

  /// 휴대전화 알림 권한이 거부됐을 때의 사용자 안내 문구(없으면 null).
  final String? permissionNotice;
  final int scheduledCount;

  static const GetOffAlarmState off = GetOffAlarmState();
}

/// 하차 알림 엔진을 화면·수명주기와 연결하는 오케스트레이션 컨트롤러.
///
/// 순수 계산([computeGetOffAlarms])·강등 판정([resolveGetOffAlarmScheduleMode])·
/// 예약 어댑터([GetOffAlarmNotifier])·영속 저장([GetOffAlarmStateRepository])을
/// 조합만 한다. 결과 화면의 진입점(#1704 타임라인)이 [enable]/[disable]을
/// 호출하고, 포그라운드 복귀 시 [refresh]로 실시간 보정 재예약을 트리거한다.
class GetOffAlarmController extends ChangeNotifier {
  static const String notificationPermissionDeniedNotice =
      '휴대전화 알림 권한을 허용해 주세요.';

  GetOffAlarmController({
    required this.notifier,
    required this.permissionGate,
    required this.notificationPermissionProvider,
    required this.repository,
    this.policy = GetOffAlarmPolicyDefaults.policy,
    this.now = DateTime.now,
  });

  final GetOffAlarmNotifier notifier;
  final ExactAlarmPermissionGate permissionGate;
  final NotificationPermissionProvider notificationPermissionProvider;
  final GetOffAlarmStateRepository repository;
  final GetOffAlarmPolicy policy;
  final DateTime Function() now;

  GetOffAlarmState _state = GetOffAlarmState.off;
  Future<void> _mutationTail = Future<void>.value();
  bool _disposed = false;

  GetOffAlarmState get state => _state;

  /// 앱 시작 시 영속된 활성 구독을 켜진 상태로 복원한다. OS가 이미 알람을
  /// 들고 있으므로 재예약하지 않고 상태만 반영한다.
  Future<void> restore() => _enqueueMutation(_restore);

  Future<void> _restore() async {
    final subscription = await repository.loadActive();
    if (subscription == null) {
      await _turnOff();
      return;
    }
    _emit(
      GetOffAlarmState(
        enabled: true,
        activeRouteId: subscription.routeId,
        scheduleMode: subscription.scheduleMode,
        inexactNotice: subscription.inexactNotice,
        scheduledCount: subscription.scheduledCount,
      ),
    );
  }

  /// 하차 알림을 켠다: 정확 알람 권한을 확인해 강등 여부를 정하고, 알림을
  /// 계산·예약한 뒤 활성 구독을 영속 저장한다.
  Future<void> enable({
    required String routeId,
    required List<GetOffAlarmStop> stops,
    required bool transferAlarmEnabled,
  }) => _enqueueMutation(
    () => _enable(
      routeId: routeId,
      stops: stops,
      transferAlarmEnabled: transferAlarmEnabled,
    ),
  );

  Future<void> _enable({
    required String routeId,
    required List<GetOffAlarmStop> stops,
    required bool transferAlarmEnabled,
  }) async {
    // destination 스톱이 없는 stops는 하차 알림 대상이 아니다. 예약·저장을
    // 건너뛰어 아래 _subscriptionFrom의 firstWhere가 StateError를 던지지 않게
    // 조기 반환한다.
    final hasDestination = stops.any(
      (stop) => stop.kind == GetOffAlarmKind.destination,
    );
    if (!hasDestination) {
      return;
    }
    final notificationPermission = await notificationPermissionProvider
        .requestNotificationPermission();
    if (notificationPermission != NotificationPermissionStatus.granted) {
      await _turnOff(permissionNotice: notificationPermissionDeniedNotice);
      return;
    }
    final permitted = await permissionGate.requestExactAlarmPermission();
    final resolution = resolveGetOffAlarmScheduleMode(
      exactAlarmPermitted: permitted,
    );
    await _schedule(
      routeId: routeId,
      stops: stops,
      transferAlarmEnabled: transferAlarmEnabled,
      resolution: resolution,
    );
  }

  /// 실시간 보정(#1416)·포그라운드 복귀 시 갱신된 도착 시각으로 재예약한다.
  Future<void> refresh({
    required List<GetOffAlarmStop> stops,
    required bool transferAlarmEnabled,
  }) => _enqueueMutation(
    () => _refresh(stops: stops, transferAlarmEnabled: transferAlarmEnabled),
  );

  Future<void> _refresh({
    required List<GetOffAlarmStop> stops,
    required bool transferAlarmEnabled,
  }) async {
    final routeId = _state.activeRouteId;
    if (!_state.enabled || routeId == null) {
      return;
    }
    final permitted = await permissionGate.isExactAlarmPermitted();
    final resolution = resolveGetOffAlarmScheduleMode(
      exactAlarmPermitted: permitted,
    );
    await _schedule(
      routeId: routeId,
      stops: stops,
      transferAlarmEnabled: transferAlarmEnabled,
      resolution: resolution,
    );
  }

  Future<void> _schedule({
    required String routeId,
    required List<GetOffAlarmStop> stops,
    required bool transferAlarmEnabled,
    required GetOffAlarmScheduleResolution resolution,
  }) async {
    final effectivePolicy = policy.copyWith(
      transferAlarmEnabled: transferAlarmEnabled,
    );
    final alarms = computeGetOffAlarms(
      stops: stops,
      policy: effectivePolicy,
      now: now(),
    );

    final delivery = await notifier.scheduleAlarms(
      alarms,
      mode: resolution.mode,
    );
    if (delivery.scheduledCount == 0) {
      await repository.clearActive();
      _emit(GetOffAlarmState.off);
      return;
    }
    await repository.saveActive(
      _subscriptionFrom(
        routeId: routeId,
        stops: stops,
        transferAlarmEnabled: transferAlarmEnabled,
        scheduledCount: delivery.scheduledCount,
        scheduleMode: resolution.mode,
        inexactNotice: resolution.inexactNotice,
      ),
    );

    _emit(
      GetOffAlarmState(
        enabled: true,
        activeRouteId: routeId,
        scheduleMode: resolution.mode,
        inexactNotice: resolution.inexactNotice,
        scheduledCount: delivery.scheduledCount,
      ),
    );
  }

  /// 하차 알림을 끈다: 예약을 취소하고 영속 상태를 지운다. 경로 안내 종료·새
  /// 경로 탐색 시 호출한다.
  Future<void> disable() => _enqueueMutation(_turnOff);

  Future<void> _enqueueMutation(Future<void> Function() mutation) {
    final result = _mutationTail.then((_) => mutation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _turnOff({String? permissionNotice}) async {
    await notifier.cancelAll();
    await repository.clearActive();
    _emit(GetOffAlarmState(permissionNotice: permissionNotice));
  }

  GetOffAlarmSubscription _subscriptionFrom({
    required String routeId,
    required List<GetOffAlarmStop> stops,
    required bool transferAlarmEnabled,
    required int scheduledCount,
    required GetOffAlarmScheduleMode scheduleMode,
    required String? inexactNotice,
  }) {
    final destination = stops.firstWhere(
      (stop) => stop.kind == GetOffAlarmKind.destination,
    );
    final transfers = stops
        .where((stop) => stop.kind == GetOffAlarmKind.transfer)
        .map(
          (stop) => GetOffAlarmStopRef(
            stationId: stop.stationId,
            stationName: stop.stationName,
            arrivalAt: stop.arrivalAt,
          ),
        )
        .toList();
    return GetOffAlarmSubscription(
      routeId: routeId,
      transferAlarmEnabled: transferAlarmEnabled,
      scheduledCount: scheduledCount,
      scheduleMode: scheduleMode,
      inexactNotice: inexactNotice,
      destination: GetOffAlarmStopRef(
        stationId: destination.stationId,
        stationName: destination.stationName,
        arrivalAt: destination.arrivalAt,
      ),
      transfers: transfers,
    );
  }

  void _emit(GetOffAlarmState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
