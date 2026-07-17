import 'package:flutter/foundation.dart';

import '../../mobile_error_reporter.dart';
import '../../notification_settings.dart';
import 'data/get_off_alarm_recovery_notice_store.dart';
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

enum GetOffAlarmRefreshResult { refreshed, routeMismatch, skipped }

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
    this.recoveryNoticeStore,
    this.onActivateReconcileWork,
    this.onDeactivateReconcileWork,
    this.policy = GetOffAlarmPolicyDefaults.policy,
    this.now = DateTime.now,
  });

  final GetOffAlarmNotifier notifier;
  final ExactAlarmPermissionGate permissionGate;
  final NotificationPermissionProvider notificationPermissionProvider;
  final GetOffAlarmStateRepository repository;

  /// headless reconcile가 알림 권한 거부로 정리했음을 다음 UI init에 한 번만
  /// 알리는 one-shot 플래그 저장소(없으면 안내를 건너뛴다).
  final GetOffAlarmRecoveryNoticeStore? recoveryNoticeStore;

  /// 활성 구독을 저장/재예약할 때 unique periodic reconcile work를 등록/update한다.
  final Future<void> Function()? onActivateReconcileWork;

  /// off·만료·알림 권한 거부 정리 시 unique periodic reconcile work만 취소한다.
  final Future<void> Function()? onDeactivateReconcileWork;

  final GetOffAlarmPolicy policy;
  final DateTime Function() now;

  GetOffAlarmState _state = GetOffAlarmState.off;
  Future<void> _mutationTail = Future<void>.value();
  bool _disposed = false;

  GetOffAlarmState get state => _state;

  /// 앱 시작 시 영속 구독과 OS 알림 상태를 프롬프트 없이 다시 맞춘다.
  Future<void> restore() => _enqueueMutation(_restore);

  /// 포그라운드 복귀 시 설정에서 변경된 권한·정확도와 OS pending을
  /// 현재 영속 구독에 재조정한다.
  Future<void> reconcile() => _enqueueMutation(_restore);

  /// 재부팅·package replace·포그라운드 복귀 뒤 영속 구독을 OS 상태에 맞춰
  /// 재조정한다. 포그라운드 restore와 headless reconcile이 공유하는 단일 계약이다.
  ///
  /// 분기:
  /// - 구독 없음(사용자가 끔): 복원하지 않고 잔여 pending만 정리한다.
  /// - 알림 권한 거부: 관련 pending 취소·구독 삭제 후 복구 안내 플래그를 기록한다.
  /// - 만료 구독(미래 알림 없음): 관련 pending 취소 후 구독을 삭제한다.
  /// - 미래 구독: 결정적 ID로 전체 idempotent 재예약한다(중복 0건). 정확 알람
  ///   권한이 있으면 exact, 없으면 silent failure 없이 inexact로 복원한다.
  Future<void> _restore() async {
    final subscription = await repository.loadActive();
    if (subscription == null) {
      final recoveryPending = await _consumeRecoveryNotice();
      await _turnOff(
        permissionNotice: recoveryPending
            ? notificationPermissionDeniedNotice
            : null,
      );
      return;
    }
    final notificationPermission = await notificationPermissionProvider
        .notificationPermissionStatus();
    if (notificationPermission != NotificationPermissionStatus.granted) {
      await _cleanUpInactiveSubscription();
      await _recordRecoveryNotice();
      _emit(
        const GetOffAlarmState(
          permissionNotice: notificationPermissionDeniedNotice,
        ),
      );
      return;
    }
    final stops = _stopsFrom(subscription);
    final alarms = computeGetOffAlarms(
      stops: stops,
      policy: policy.copyWith(
        transferAlarmEnabled: subscription.transferAlarmEnabled,
      ),
      now: now(),
    );
    if (alarms.isEmpty) {
      final recoveryPending = await _consumeRecoveryNotice();
      await _cleanUpInactiveSubscription();
      _emit(
        GetOffAlarmState(
          permissionNotice: recoveryPending
              ? notificationPermissionDeniedNotice
              : null,
        ),
      );
      return;
    }
    final permitted = await permissionGate.isExactAlarmPermitted();
    final resolution = resolveGetOffAlarmScheduleMode(
      exactAlarmPermitted: permitted,
    );
    // 활성 구독을 복원하므로 남은 복구 안내 플래그는 조용히 소비해 지운다.
    await _consumeRecoveryNotice();
    // 위에서 만료 판정에 쓴 단일 now 스냅샷 결과를 그대로 넘겨 restore 경로를
    // 원자화한다. _schedule가 now()로 재계산하면 두 스냅샷 사이에 마지막 발화
    // 시각이 지날 때 alarms.isEmpty 분기와 달리 복구 안내 소비 없이 off로
    // 정리되는 계약 분열이 생긴다.
    await _schedule(
      routeId: subscription.routeId,
      stops: stops,
      transferAlarmEnabled: subscription.transferAlarmEnabled,
      resolution: resolution,
      precomputedAlarms: alarms,
    );
  }

  Future<void> _cleanUpInactiveSubscription() async {
    await notifier.cancelAll();
    await repository.clearActive();
    await _deactivateReconcileWork();
  }

  Future<bool> _consumeRecoveryNotice() async {
    final store = recoveryNoticeStore;
    if (store == null) {
      return false;
    }
    return store.consume();
  }

  Future<void> _recordRecoveryNotice() async {
    await recoveryNoticeStore?.record();
  }

  Future<void> _activateReconcileWork() async {
    final activate = onActivateReconcileWork;
    if (activate == null) {
      return;
    }
    try {
      await activate();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '하차 알림 reconcile work 등록 중 예외가 발생했습니다.',
      );
    }
  }

  Future<void> _deactivateReconcileWork() async {
    final deactivate = onDeactivateReconcileWork;
    if (deactivate == null) {
      return;
    }
    try {
      await deactivate();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '하차 알림 reconcile work 취소 중 예외가 발생했습니다.',
      );
    }
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
  Future<GetOffAlarmRefreshResult> refresh({
    required String routeId,
    required List<GetOffAlarmStop> stops,
  }) => _enqueueMutation(() => _refresh(routeId: routeId, stops: stops));

  Future<GetOffAlarmRefreshResult> _refresh({
    required String routeId,
    required List<GetOffAlarmStop> stops,
  }) async {
    if (!_state.enabled) {
      return GetOffAlarmRefreshResult.skipped;
    }
    final activeRouteId = _state.activeRouteId;
    final subscription = await repository.loadActive();
    if (subscription == null ||
        activeRouteId == null ||
        subscription.routeId != activeRouteId ||
        activeRouteId != routeId) {
      if (kDebugMode) {
        debugPrint(
          'get_off_alarm refresh route_mismatch '
          'subscription_route_id=${subscription?.routeId} '
          'active_route_id=$activeRouteId input_route_id=$routeId',
        );
      }
      return GetOffAlarmRefreshResult.routeMismatch;
    }
    if (stops.isEmpty) {
      await _turnOff();
      return GetOffAlarmRefreshResult.refreshed;
    }
    final hasDestination = stops.any(
      (stop) => stop.kind == GetOffAlarmKind.destination,
    );
    if (!hasDestination) {
      return GetOffAlarmRefreshResult.skipped;
    }
    final notificationPermission = await notificationPermissionProvider
        .notificationPermissionStatus();
    if (notificationPermission != NotificationPermissionStatus.granted) {
      await _turnOff(permissionNotice: notificationPermissionDeniedNotice);
      return GetOffAlarmRefreshResult.refreshed;
    }
    final permitted = await permissionGate.isExactAlarmPermitted();
    final resolution = resolveGetOffAlarmScheduleMode(
      exactAlarmPermitted: permitted,
    );
    await _schedule(
      routeId: routeId,
      stops: stops,
      transferAlarmEnabled: subscription.transferAlarmEnabled,
      resolution: resolution,
    );
    return GetOffAlarmRefreshResult.refreshed;
  }

  /// [precomputedAlarms]가 주어지면 그 단일 now 스냅샷 계산 결과를 그대로
  /// 예약한다(restore 경로 원자화용). 없으면 현재 now()로 새로 계산한다
  /// (enable/refresh 경로의 기존 동작).
  Future<void> _schedule({
    required String routeId,
    required List<GetOffAlarmStop> stops,
    required bool transferAlarmEnabled,
    required GetOffAlarmScheduleResolution resolution,
    List<ScheduledGetOffAlarm>? precomputedAlarms,
  }) async {
    final alarms =
        precomputedAlarms ??
        computeGetOffAlarms(
          stops: stops,
          policy: policy.copyWith(transferAlarmEnabled: transferAlarmEnabled),
          now: now(),
        );

    final delivery = await notifier.scheduleAlarms(
      alarms,
      mode: resolution.mode,
    );
    if (delivery.scheduledCount == 0) {
      await repository.clearActive();
      await _deactivateReconcileWork();
      _emit(GetOffAlarmState.off);
      return;
    }
    final subscription = _subscriptionFrom(
      routeId: routeId,
      stops: stops,
      transferAlarmEnabled: transferAlarmEnabled,
      scheduledCount: delivery.scheduledCount,
      scheduleMode: resolution.mode,
      inexactNotice: resolution.inexactNotice,
    );
    try {
      await repository.saveActive(subscription);
    } catch (error, stackTrace) {
      await _compensateFailedSave();
      Error.throwWithStackTrace(error, stackTrace);
    }
    // 활성 구독을 저장했으므로 unique periodic reconcile work를 등록/update한다.
    await _activateReconcileWork();

    _emitSubscription(subscription);
  }

  /// 하차 알림을 끈다: 예약을 취소하고 영속 상태를 지운다. 경로 안내 종료·새
  /// 경로 탐색 시 호출한다.
  Future<void> disable() => _enqueueMutation(_turnOff);

  Future<T> _enqueueMutation<T>(Future<T> Function() mutation) {
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
    await _deactivateReconcileWork();
    _emit(GetOffAlarmState(permissionNotice: permissionNotice));
  }

  Future<void> _compensateFailedSave() async {
    try {
      await notifier.cancelAll();
    } catch (error, stackTrace) {
      _reportCompensationError(error, stackTrace);
    }
    try {
      await repository.clearActive();
    } catch (error, stackTrace) {
      _reportCompensationError(error, stackTrace);
    }
    await _deactivateReconcileWork();
    _emit(GetOffAlarmState.off);
  }

  void _reportCompensationError(Object error, StackTrace stackTrace) {
    reportMobileError(
      error,
      stackTrace,
      context: '하차 알림 저장 실패 보상 정리 중 예외가 발생했습니다.',
    );
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

  List<GetOffAlarmStop> _stopsFrom(GetOffAlarmSubscription subscription) {
    return [
      for (final transfer in subscription.transfers)
        GetOffAlarmStop(
          stationId: transfer.stationId,
          stationName: transfer.stationName,
          arrivalAt: transfer.arrivalAt,
          kind: GetOffAlarmKind.transfer,
        ),
      GetOffAlarmStop(
        stationId: subscription.destination.stationId,
        stationName: subscription.destination.stationName,
        arrivalAt: subscription.destination.arrivalAt,
        kind: GetOffAlarmKind.destination,
      ),
    ];
  }

  void _emitSubscription(GetOffAlarmSubscription subscription) {
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
