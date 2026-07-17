import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager_android/workmanager_android.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import '../../core/database/catalog/catalog_database.dart';
import '../../core/database/catalog/catalog_database_opener.dart';
import '../../core/database/user/user_database.dart';
import '../../core/database/user/user_database_opener.dart';
import '../../core/datapack/emergency_override_repository.dart';
import '../../mobile_error_reporter.dart';
import '../get_off_alarm/get_off_alarm_reconcile_worker.dart';
import 'next_train_widget_configuration_screen.dart';
import 'next_train_widget_repository.dart';
import 'next_train_widget_service.dart';

const nextTrainWidgetProviderName =
    'com.easysubway.easysubway_mobile.NextTrainWidgetProvider';
const nextTrainWidgetRefreshTask = 'nextTrainWidgetRefresh';
const nextTrainWidgetRefreshUniqueName = 'next-train-widget-refresh';

typedef ReadWidgetValue = Future<String?> Function(String key);
typedef ReportNextTrainWidgetError =
    void Function(Object error, StackTrace stackTrace);

Future<void> runNextTrainWidgetStartup({
  required Future<List<int>> Function() installedWidgetIds,
  required Future<void> Function() registerRefresh,
  required Future<void> Function() cancelRefresh,
  required Future<void> Function(List<int> widgetIds) refresh,
  required ReportNextTrainWidgetError reportError,
}) async {
  late final List<int> widgetIds;
  try {
    widgetIds = await installedWidgetIds();
  } on Object catch (error, stackTrace) {
    reportError(error, stackTrace);
    return;
  }
  if (widgetIds.isEmpty) {
    await runNextTrainWidgetOperationSafely(
      operation: cancelRefresh,
      reportError: reportError,
    );
    return;
  }
  await runNextTrainWidgetOperationSafely(
    operation: registerRefresh,
    reportError: reportError,
  );
  await runNextTrainWidgetOperationSafely(
    operation: () => refresh(widgetIds),
    reportError: reportError,
  );
}

Future<void> runNextTrainWidgetOperationSafely({
  required Future<void> Function() operation,
  required ReportNextTrainWidgetError reportError,
}) async {
  try {
    await operation();
  } on Object catch (error, stackTrace) {
    reportError(error, stackTrace);
  }
}

@visibleForTesting
Future<T> runNextTrainWidgetConfigurationOperation<T>({
  required Future<T> Function() operation,
  required Future<void> Function() close,
}) async {
  try {
    return await operation();
  } finally {
    await close();
  }
}

@visibleForTesting
Future<void> configureNextTrainWidgetSelection({
  required WidgetStationSelection selection,
  required ConfigureWidget configure,
  required Future<void> Function() registerRefresh,
  required Future<void> Function() finish,
  required Future<void> Function() cancelRefresh,
}) async {
  await configure(selection);
  await registerRefresh();
  try {
    await finish();
  } on Object {
    await cancelRefresh();
    rethrow;
  }
}

@visibleForTesting
bool shouldCancelNextTrainWidgetRefreshAfterFailedConfiguration({
  required List<int> installedWidgetIds,
  required int configuringWidgetId,
}) {
  return installedWidgetIds.every(
    (widgetId) => widgetId == configuringWidgetId,
  );
}

@visibleForTesting
Future<void> launchNextTrainWidgetConfiguration({
  required Future<String?> Function() readWidgetId,
  required Future<void> Function(int widgetId) launch,
}) async {
  final widgetId = int.tryParse(await readWidgetId() ?? '');
  if (widgetId == null) {
    throw StateError('Android widget id가 없습니다.');
  }
  await launch(widgetId);
}

Future<void> refreshInstalledNextTrainWidgets({
  required List<int> widgetIds,
  required ReadWidgetValue readValue,
  required NextTrainWidgetService service,
  required DateTime now,
}) async {
  final failures = <String>[];
  StackTrace? firstFailureStackTrace;
  for (final widgetId in widgetIds) {
    try {
      final prefix = 'widget_${widgetId}_';
      final stationId = await readValue('${prefix}station_id');
      final lineId = await readValue('${prefix}line_id');
      final stationName = await readValue('${prefix}station_name');
      final lineName = await readValue('${prefix}line_name');
      if ([
        stationId,
        lineId,
        stationName,
        lineName,
      ].any((value) => value == null || value.trim().isEmpty)) {
        continue;
      }
      await service.refresh(
        appWidgetId: widgetId,
        selection: WidgetStationSelection(
          stationId: stationId!,
          lineId: lineId!,
          stationName: stationName!,
          lineName: lineName!,
        ),
        now: now,
      );
    } on Object catch (error, stackTrace) {
      failures.add('widget $widgetId: $error');
      firstFailureStackTrace ??= stackTrace;
    }
  }
  if (failures.isNotEmpty) {
    Error.throwWithStackTrace(
      StateError('Android widget 갱신 실패: ${failures.join('; ')}'),
      firstFailureStackTrace!,
    );
  }
}

/// process-wide WorkManager dispatcher를 초기화한다. app bootstrap에서 정확히
/// 한 번만 호출한다(다음 열차 위젯·하차 알림 reconcile이 이 단일 dispatcher를
/// 공유한다). 등록(register*)은 initialize와 분리해 개별적으로 수행한다.
Future<void> initializeWorkManagerDispatcher() async {
  if (!Platform.isAndroid) {
    return;
  }
  await WorkmanagerAndroid().initialize(nextTrainWidgetCallbackDispatcher);
}

/// 다음 열차 위젯 unique periodic work만 등록/update한다(initialize하지 않음).
Future<void> registerNextTrainWidgetRefresh() async {
  if (!Platform.isAndroid) {
    return;
  }
  await WorkmanagerAndroid().registerPeriodicTask(
    nextTrainWidgetRefreshUniqueName,
    nextTrainWidgetRefreshTask,
    frequency: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}

/// 위젯 설정 activity(별도 engine)의 진입점 전용: 그 engine에는 dispatcher가
/// 초기화돼 있지 않으므로 initialize와 register를 함께 수행한다. main bootstrap은
/// 이 함수를 쓰지 않고 [initializeWorkManagerDispatcher]로 1회만 초기화한다.
Future<void> initializeAndRegisterNextTrainWidgetRefresh() async {
  await initializeWorkManagerDispatcher();
  await registerNextTrainWidgetRefresh();
}

Future<void> cancelNextTrainWidgetRefresh() async {
  if (!Platform.isAndroid) {
    return;
  }
  await WorkmanagerAndroid().cancelByUniqueName(
    nextTrainWidgetRefreshUniqueName,
  );
}

Future<List<int>> installedNextTrainWidgetIds() async {
  if (!Platform.isAndroid) {
    return const [];
  }
  final widgets = await HomeWidget.getInstalledWidgets();
  return widgets
      .where(
        (widget) =>
            widget.androidClassName?.endsWith('NextTrainWidgetProvider') ??
            false,
      )
      .map((widget) => widget.androidWidgetId)
      .whereType<int>()
      .toList(growable: false);
}

Future<void> refreshNextTrainWidgets(
  NextTrainWidgetRepository repository, {
  DateTime? now,
  List<int>? widgetIds,
}) async {
  if (!Platform.isAndroid) {
    return;
  }
  final installedWidgetIds = widgetIds ?? await installedNextTrainWidgetIds();
  final service = NextTrainWidgetService(
    load: repository.load,
    saveValue: _saveWidgetValue,
    updateWidget: _updateNativeWidget,
  );
  await refreshInstalledNextTrainWidgets(
    widgetIds: installedWidgetIds,
    readValue: _readWidgetValue,
    service: service,
    now: now ?? DateTime.now(),
  );
}

Stream<Uri?> homeWidgetClicks() async* {
  if (!Platform.isAndroid) {
    return;
  }
  yield await HomeWidget.initiallyLaunchedFromHomeWidget();
  yield* HomeWidget.widgetClicked;
}

@pragma('vm:entry-point')
void nextTrainWidgetCallbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  WorkmanagerFlutterApi.setUp(NextTrainWidgetWorkmanagerApi());
}

// ponytail: the federated public Android API keeps iOS SwiftPM-only; replace
// this adapter when workmanager ships an official Android-only facade.
//
// 단일 process-wide dispatcher가 task 이름으로 각 handler에 라우팅한다. 알 수 없는
// task는 성공으로 삼키지 않고 fail-closed(false)로 돌려준다(두 번째 dispatcher 금지).
@visibleForTesting
class NextTrainWidgetWorkmanagerApi extends WorkmanagerFlutterApi {
  NextTrainWidgetWorkmanagerApi({
    Future<bool> Function()? runWidgetRefresh,
    Future<bool> Function()? runGetOffAlarmReconcile,
  }) : _runWidgetRefresh = runWidgetRefresh ?? _defaultRunWidgetRefresh,
       _runGetOffAlarmReconcile =
           runGetOffAlarmReconcile ?? _defaultRunGetOffAlarmReconcile;

  final Future<bool> Function() _runWidgetRefresh;
  final Future<bool> Function() _runGetOffAlarmReconcile;

  @override
  Future<void> backgroundChannelInitialized() async {}

  @override
  Future<bool> executeTask(
    String task,
    Map<String?, Object?>? inputData,
  ) async {
    switch (task) {
      case nextTrainWidgetRefreshTask:
        return _runWidgetRefresh();
      case getOffAlarmReconcileTask:
        return _runGetOffAlarmReconcile();
      default:
        return false;
    }
  }

  static Future<bool> _defaultRunWidgetRefresh() async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    final databases = await _openWidgetDatabases();
    try {
      await refreshNextTrainWidgets(
        NextTrainWidgetRepository(
          catalogDatabase: databases.catalog,
          userDatabase: databases.user,
        ),
      );
    } finally {
      await databases.close();
    }
    return true;
  }

  static Future<bool> _defaultRunGetOffAlarmReconcile() async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return runGetOffAlarmReconcileTask(
      reportError: (error, stackTrace) => reportMobileError(
        error,
        stackTrace,
        context: '하차 알림 headless reconcile 중 예외가 발생했습니다.',
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> configureMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await launchNextTrainWidgetConfiguration(
    readWidgetId: HomeWidget.initiallyLaunchedFromHomeWidgetConfigure,
    launch: (appWidgetId) async {
      runApp(
        MaterialApp(
          title: '쉬운 지하철 위젯',
          home: NextTrainWidgetConfigurationScreen(
            loadSelections: () => _withConfigurationDatabases(
              (databases) => NextTrainWidgetRepository(
                catalogDatabase: databases.catalog,
                userDatabase: databases.user,
              ).availableSelections(),
            ),
            configure: (selection) => configureNextTrainWidgetSelection(
              selection: selection,
              configure: (selection) => _withConfigurationDatabases(
                (databases) =>
                    NextTrainWidgetService(
                      load: NextTrainWidgetRepository(
                        catalogDatabase: databases.catalog,
                        userDatabase: databases.user,
                      ).load,
                      saveValue: _saveWidgetValue,
                      updateWidget: _updateNativeWidget,
                    ).configure(
                      appWidgetId: appWidgetId,
                      selection: selection,
                      now: DateTime.now(),
                    ),
              ),
              registerRefresh: initializeAndRegisterNextTrainWidgetRefresh,
              finish: HomeWidget.finishHomeWidgetConfigure,
              cancelRefresh: () async {
                final installedWidgetIds = await installedNextTrainWidgetIds();
                if (shouldCancelNextTrainWidgetRefreshAfterFailedConfiguration(
                  installedWidgetIds: installedWidgetIds,
                  configuringWidgetId: appWidgetId,
                )) {
                  await cancelNextTrainWidgetRefresh();
                }
              },
            ),
          ),
        ),
      );
    },
  );
}

Future<void> _saveWidgetValue(String key, Object? value) {
  return HomeWidget.saveWidgetData<String>(key, value?.toString());
}

Future<String?> _readWidgetValue(String key) {
  return HomeWidget.getWidgetData<String>(key);
}

Future<void> _updateNativeWidget() async {
  await HomeWidget.updateWidget(
    qualifiedAndroidName: nextTrainWidgetProviderName,
  );
}

Future<_WidgetDatabases> _openWidgetDatabases() async {
  final supportDirectory = await getApplicationSupportDirectory();
  final user = await UserDatabaseOpener(
    databaseDirectory: Directory(p.join(supportDirectory.path, 'user')),
  ).open();
  try {
    final catalog = await CatalogDatabaseOpener(
      databaseDirectory: supportDirectory,
      assetBundle: rootBundle,
      emergencyOverrideRepository: EmergencyOverrideRepository(
        userDatabase: user,
      ),
    ).open();
    return _WidgetDatabases(catalog: catalog, user: user);
  } on Object {
    await user.close();
    rethrow;
  }
}

Future<T> _withConfigurationDatabases<T>(
  Future<T> Function(_WidgetDatabases databases) operation,
) async {
  final databases = await _openWidgetDatabases();
  return runNextTrainWidgetConfigurationOperation(
    operation: () => operation(databases),
    close: databases.close,
  );
}

class _WidgetDatabases {
  const _WidgetDatabases({required this.catalog, required this.user});

  final CatalogDatabase catalog;
  final UserDatabase user;

  Future<void> close() async {
    try {
      await catalog.close();
    } finally {
      await user.close();
    }
  }
}
