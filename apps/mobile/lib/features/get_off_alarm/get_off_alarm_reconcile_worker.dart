import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager_android/workmanager_android.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import '../../core/database/user/user_database.dart';
import '../../core/database/user/user_database_opener.dart';
import '../../notification_settings.dart';
import 'data/get_off_alarm_recovery_notice_store.dart';
import 'data/get_off_alarm_state_repository.dart';
import 'exact_alarm_permission.dart';
import 'get_off_alarm_controller.dart';
import 'get_off_alarm_notifier.dart';

/// unique periodic work 이름과 task 이름. process-wide dispatcher는 하나만
/// 유지하며(다음 열차 위젯과 공유), 이 task 이름으로 하차 알림 reconcile handler에
/// 라우팅된다.
const getOffAlarmReconcileTask = 'getOffAlarmReconcile';
const getOffAlarmReconcileUniqueName = 'get-off-alarm-reconcile';

/// 재조정 주기. 네트워크 제약은 두지 않는다(순수·위치 미사용 로컬 계산).
const getOffAlarmReconcileFrequency = Duration(minutes: 15);

/// 활성 구독 저장/재예약 시 unique periodic reconcile work를 등록/update한다.
///
/// WorkManager initialize는 여기서 하지 않는다(app bootstrap에서 정확히 1회).
/// 이미 등록돼 있으면 [ExistingPeriodicWorkPolicy.update]로 갱신만 한다.
Future<void> registerGetOffAlarmReconcile() async {
  if (!Platform.isAndroid) {
    return;
  }
  await WorkmanagerAndroid().registerPeriodicTask(
    getOffAlarmReconcileUniqueName,
    getOffAlarmReconcileTask,
    frequency: getOffAlarmReconcileFrequency,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}

/// off·만료·알림 권한 거부 정리 시 하차 알림 unique work만 취소한다. 다음 열차
/// 위젯의 periodic work(`next-train-widget-refresh`)는 건드리지 않는다.
Future<void> cancelGetOffAlarmReconcile() async {
  if (!Platform.isAndroid) {
    return;
  }
  await WorkmanagerAndroid().cancelByUniqueName(getOffAlarmReconcileUniqueName);
}

/// headless reconcile의 순수 오케스트레이션. 성공·예외와 무관하게 [close]로
/// 리소스(DB·notifier)를 반드시 닫고, 예외는 fail-closed로 false를 돌려준다.
Future<bool> reconcileGetOffAlarmHeadless({
  required Future<void> Function() reconcile,
  required Future<void> Function() close,
  required void Function(Object error, StackTrace stackTrace) reportError,
}) async {
  try {
    await reconcile();
    return true;
  } on Object catch (error, stackTrace) {
    reportError(error, stackTrace);
    return false;
  } finally {
    await close();
  }
}

/// WorkManager headless isolate에서 실행되는 프로덕션 진입점. Drift user DB를 열고
/// 컨트롤러를 조립해 단일 활성 구독을 재조정한 뒤, finally에서 DB·컨트롤러를 닫는다.
///
/// [openUserDatabase]·[createController]는 프로덕션 DB opener·컨트롤러 조립을
/// 기본값으로 갖는 주입 seam이다(테스트에서 close 경로 — controller.dispose와
/// userDatabase.close 호출 — 를 성공·예외 양쪽에서 고정하기 위함). 프로덕션
/// 기본값 동작은 불변이다.
Future<bool> runGetOffAlarmReconcileTask({
  required void Function(Object error, StackTrace stackTrace) reportError,
  Future<UserDatabase> Function() openUserDatabase = _openUserDatabase,
  GetOffAlarmController Function(UserDatabase userDatabase) createController =
      _createReconcileController,
}) async {
  final UserDatabase userDatabase = await openUserDatabase();
  final controller = createController(userDatabase);
  return reconcileGetOffAlarmHeadless(
    reconcile: controller.reconcile,
    close: () async {
      controller.dispose();
      await userDatabase.close();
    },
    reportError: reportError,
  );
}

/// headless reconcile용 프로덕션 컨트롤러 조립. [userDatabase]를 공유해 상태
/// 저장소·복구 안내 저장소를 구성한다.
GetOffAlarmController _createReconcileController(UserDatabase userDatabase) {
  return GetOffAlarmController(
    notifier: LocalGetOffAlarmNotifier(FlutterLocalNotificationsPlugin()),
    permissionGate: PluginExactAlarmPermissionGate(
      FlutterLocalNotificationsPlugin(),
    ),
    notificationPermissionProvider:
        MethodChannelNotificationPermissionProvider(),
    repository: DriftGetOffAlarmStateRepository(userDatabase: userDatabase),
    recoveryNoticeStore: DriftGetOffAlarmRecoveryNoticeStore(
      userDatabase: userDatabase,
    ),
    onActivateReconcileWork: registerGetOffAlarmReconcile,
    onDeactivateReconcileWork: cancelGetOffAlarmReconcile,
  );
}

Future<UserDatabase> _openUserDatabase() async {
  final supportDirectory = await getApplicationSupportDirectory();
  return UserDatabaseOpener(
    databaseDirectory: Directory(p.join(supportDirectory.path, 'user')),
  ).open();
}
