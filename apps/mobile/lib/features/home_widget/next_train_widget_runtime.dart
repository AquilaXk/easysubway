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
import 'next_train_widget_configuration_screen.dart';
import 'next_train_widget_repository.dart';
import 'next_train_widget_service.dart';

const nextTrainWidgetProviderName =
    'com.easysubway.easysubway_mobile.NextTrainWidgetProvider';
const nextTrainWidgetRefreshTask = 'nextTrainWidgetRefresh';
const nextTrainWidgetRefreshUniqueName = 'next-train-widget-refresh';

typedef ReadWidgetValue = Future<String?> Function(String key);

Future<void> refreshInstalledNextTrainWidgets({
  required List<int> widgetIds,
  required ReadWidgetValue readValue,
  required NextTrainWidgetService service,
  required DateTime now,
}) async {
  for (final widgetId in widgetIds) {
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
  }
}

Future<void> initializeNextTrainWidgetRefresh() async {
  if (!Platform.isAndroid) {
    return;
  }
  final workmanager = WorkmanagerAndroid();
  await workmanager.initialize(nextTrainWidgetCallbackDispatcher);
  await workmanager.registerPeriodicTask(
    nextTrainWidgetRefreshUniqueName,
    nextTrainWidgetRefreshTask,
    frequency: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: NetworkType.notRequired),
  );
}

Future<void> refreshNextTrainWidgets(
  NextTrainWidgetRepository repository, {
  DateTime? now,
}) async {
  if (!Platform.isAndroid) {
    return;
  }
  final widgets = await HomeWidget.getInstalledWidgets();
  final widgetIds = widgets
      .where(
        (widget) =>
            widget.androidClassName?.endsWith('NextTrainWidgetProvider') ??
            false,
      )
      .map((widget) => widget.androidWidgetId)
      .whereType<int>()
      .toList(growable: false);
  final service = NextTrainWidgetService(
    load: repository.load,
    saveValue: _saveWidgetValue,
    updateWidget: _updateNativeWidget,
  );
  await refreshInstalledNextTrainWidgets(
    widgetIds: widgetIds,
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
@visibleForTesting
class NextTrainWidgetWorkmanagerApi extends WorkmanagerFlutterApi {
  @override
  Future<void> backgroundChannelInitialized() async {}

  @override
  Future<bool> executeTask(
    String task,
    Map<String?, Object?>? inputData,
  ) async {
    if (task != nextTrainWidgetRefreshTask) {
      return true;
    }
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
}

@pragma('vm:entry-point')
Future<void> configureMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final appWidgetId = int.tryParse(
    await HomeWidget.initiallyLaunchedFromHomeWidgetConfigure() ?? '',
  );
  final databases = await _openWidgetDatabases();
  final repository = NextTrainWidgetRepository(
    catalogDatabase: databases.catalog,
    userDatabase: databases.user,
  );
  runApp(
    MaterialApp(
      title: '쉬운 지하철 위젯',
      home: NextTrainWidgetConfigurationScreen(
        loadSelections: repository.availableSelections,
        configure: (selection) async {
          if (appWidgetId == null) {
            throw StateError('Android widget id가 없습니다.');
          }
          await NextTrainWidgetService(
            load: repository.load,
            saveValue: _saveWidgetValue,
            updateWidget: _updateNativeWidget,
          ).configure(
            appWidgetId: appWidgetId,
            selection: selection,
            now: DateTime.now(),
          );
          await databases.close();
          await HomeWidget.finishHomeWidgetConfigure();
        },
      ),
    ),
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

class _WidgetDatabases {
  const _WidgetDatabases({required this.catalog, required this.user});

  final CatalogDatabase catalog;
  final UserDatabase user;

  Future<void> close() async {
    await catalog.close();
    await user.close();
  }
}
