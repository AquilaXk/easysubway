import 'package:easysubway_mobile/features/home_widget/next_train_widget_repository.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_runtime.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('위젯 startup plugin 실패를 보고하고 core startup은 계속한다', () async {
    final errors = <Object>[];
    var refreshed = false;

    await runNextTrainWidgetStartup(
      installedWidgetIds: () async => const [42],
      registerRefresh: () async => throw StateError('plugin unavailable'),
      cancelRefresh: () async {},
      refresh: (_) async => refreshed = true,
      reportError: (error, _) => errors.add(error),
    );

    expect(errors.single, isA<StateError>());
    expect(refreshed, isTrue);
  });

  test('설치 widget이 없으면 startup은 periodic을 취소하고 등록하지 않는다', () async {
    var registerCount = 0;
    var cancelCount = 0;
    var refreshCount = 0;

    await runNextTrainWidgetStartup(
      installedWidgetIds: () async => const [],
      registerRefresh: () async => registerCount += 1,
      cancelRefresh: () async => cancelCount += 1,
      refresh: (_) async => refreshCount += 1,
      reportError: (_, _) {},
    );

    expect(registerCount, 0);
    expect(cancelCount, 1);
    expect(refreshCount, 0);
  });

  test('설치 widget이 있으면 startup은 periodic을 등록하고 해당 ID를 갱신한다', () async {
    var registerCount = 0;
    var cancelCount = 0;
    List<int>? refreshedWidgetIds;

    await runNextTrainWidgetStartup(
      installedWidgetIds: () async => const [42],
      registerRefresh: () async => registerCount += 1,
      cancelRefresh: () async => cancelCount += 1,
      refresh: (widgetIds) async => refreshedWidgetIds = widgetIds,
      reportError: (_, _) {},
    );

    expect(registerCount, 1);
    expect(cancelCount, 0);
    expect(refreshedWidgetIds, [42]);
  });

  test('direct configuration 성공은 구성 뒤 periodic을 등록하고 완료한다', () async {
    final events = <String>[];

    await configureNextTrainWidgetSelection(
      selection: _selection,
      configure: (_) async => events.add('configure'),
      registerRefresh: () async => events.add('register'),
      finish: () async => events.add('finish'),
      cancelRefresh: () async => events.add('cancel'),
    );

    expect(events, ['configure', 'register', 'finish']);
  });

  test('direct configuration 구성 실패는 periodic을 등록하거나 취소하지 않는다', () async {
    var registerCount = 0;
    var cancelCount = 0;
    var finishCount = 0;

    await expectLater(
      configureNextTrainWidgetSelection(
        selection: _selection,
        configure: (_) async => throw StateError('configure failed'),
        registerRefresh: () async => registerCount += 1,
        finish: () async => finishCount += 1,
        cancelRefresh: () async => cancelCount += 1,
      ),
      throwsA(isA<StateError>()),
    );

    expect(registerCount, 0);
    expect(cancelCount, 0);
    expect(finishCount, 0);
  });

  test('direct configuration 완료 실패는 등록한 periodic을 취소한다', () async {
    var registerCount = 0;
    var cancelCount = 0;

    await expectLater(
      configureNextTrainWidgetSelection(
        selection: _selection,
        configure: (_) async {},
        registerRefresh: () async => registerCount += 1,
        finish: () async => throw StateError('finish failed'),
        cancelRefresh: () async => cancelCount += 1,
      ),
      throwsA(isA<StateError>()),
    );

    expect(registerCount, 1);
    expect(cancelCount, 1);
  });

  test('완료 실패에서 current pending widget만 있으면 periodic을 취소한다', () {
    expect(
      shouldCancelNextTrainWidgetRefreshAfterFailedConfiguration(
        installedWidgetIds: const [42],
        configuringWidgetId: 42,
      ),
      isTrue,
    );
  });

  test('완료 실패에서 installed widget이 없으면 periodic을 취소한다', () {
    expect(
      shouldCancelNextTrainWidgetRefreshAfterFailedConfiguration(
        installedWidgetIds: const [],
        configuringWidgetId: 42,
      ),
      isTrue,
    );
  });

  test('완료 실패에서 다른 정상 widget이 있으면 periodic을 유지한다', () {
    expect(
      shouldCancelNextTrainWidgetRefreshAfterFailedConfiguration(
        installedWidgetIds: const [7, 42],
        configuringWidgetId: 42,
      ),
      isFalse,
    );
  });

  test('configuration operation 오류에서도 resource를 한 번 닫는다', () async {
    var closeCount = 0;

    await expectLater(
      runNextTrainWidgetConfigurationOperation<void>(
        operation: () async => throw StateError('configure failed'),
        close: () async => closeCount += 1,
      ),
      throwsA(isA<StateError>()),
    );

    expect(closeCount, 1);
  });

  test('widget id가 없으면 configuration을 열지 않는다', () async {
    var launched = false;

    await expectLater(
      launchNextTrainWidgetConfiguration(
        readWidgetId: () async => null,
        launch: (_) async => launched = true,
      ),
      throwsA(isA<StateError>()),
    );

    expect(launched, isFalse);
  });

  test('알 수 없는 WorkManager task는 성공으로 무시한다', () async {
    final worker = NextTrainWidgetWorkmanagerApi();

    expect(await worker.executeTask('other-task', null), isTrue);
  });

  test('configure는 widget id별 시간표 snapshot을 저장하고 provider를 갱신한다', () async {
    final stored = <String, Object?>{};
    var updateCount = 0;
    final service = NextTrainWidgetService(
      load: (_, _) async => _availableData,
      saveValue: (key, value) async => stored[key] = value,
      updateWidget: () async => updateCount += 1,
    );

    await service.configure(
      appWidgetId: 42,
      selection: _selection,
      now: DateTime(2026, 7, 10, 9),
    );

    expect(stored, {
      'widget_42_station_id': 'station-sadang',
      'widget_42_line_id': 'seoul-4',
      'widget_42_station_name': '사당',
      'widget_42_line_name': '수도권 4호선',
      'widget_42_direction_1': '상록수 방면',
      'widget_42_departure_1': '09:12',
      'widget_42_direction_2': '사당 방면',
      'widget_42_departure_2': '09:18',
      'widget_42_status': 'available',
      'widget_42_status_label': '시간표 기준',
      'widget_42_updated_at': '2026-07-10T09:00:00.000',
    });
    expect(updateCount, 1);
  });

  test('시간표 unavailable 선택은 저장하지 않는다', () async {
    final stored = <String, Object?>{};
    final service = NextTrainWidgetService(
      load: (selection, now) async =>
          NextTrainWidgetData.unavailable(selection, now),
      saveValue: (key, value) async => stored[key] = value,
      updateWidget: () async {},
    );

    await expectLater(
      service.configure(
        appWidgetId: 42,
        selection: _selection,
        now: DateTime(2027, 1, 1, 9),
      ),
      throwsA(isA<StateError>()),
    );
    expect(stored, isEmpty);
  });

  test('기존 widget refresh는 unavailable 상태를 정직하게 저장한다', () async {
    final stored = <String, Object?>{};
    final service = NextTrainWidgetService(
      load: (selection, now) async =>
          NextTrainWidgetData.unavailable(selection, now),
      saveValue: (key, value) async => stored[key] = value,
      updateWidget: () async {},
    );

    await service.refresh(
      appWidgetId: 42,
      selection: _selection,
      now: DateTime(2027, 1, 1, 9),
    );

    expect(stored['widget_42_status'], 'timetableUnavailable');
    expect(stored['widget_42_status_label'], '시간표를 확인할 수 없어요.');
    expect(stored['widget_42_direction_1'], '');
    expect(stored['widget_42_departure_1'], '');
  });

  test('설치 widget 중 완전한 station-line 선택만 갱신한다', () async {
    final values = <String, String>{
      'widget_42_station_id': 'station-sadang',
      'widget_42_line_id': 'seoul-4',
      'widget_42_station_name': '사당',
      'widget_42_line_name': '수도권 4호선',
    };
    final loaded = <WidgetStationSelection>[];
    var updateCount = 0;
    final service = NextTrainWidgetService(
      load: (selection, _) async {
        loaded.add(selection);
        return _availableData;
      },
      saveValue: (_, _) async {},
      updateWidget: () async => updateCount += 1,
    );

    await refreshInstalledNextTrainWidgets(
      widgetIds: const [42, 43],
      readValue: (key) async => values[key],
      service: service,
      now: DateTime(2026, 7, 10, 9),
    );

    expect(loaded.single.stationId, 'station-sadang');
    expect(updateCount, 1);
  });
}

const _selection = WidgetStationSelection(
  stationId: 'station-sadang',
  lineId: 'seoul-4',
  stationName: '사당',
  lineName: '수도권 4호선',
);

final _availableData = NextTrainWidgetData(
  selection: _selection,
  status: NextTrainWidgetStatus.available,
  directions: [
    NextTrainDirection(
      name: '상록수 방면',
      departureAt: DateTime(2026, 7, 10, 9, 12),
    ),
    NextTrainDirection(
      name: '사당 방면',
      departureAt: DateTime(2026, 7, 10, 9, 18),
    ),
  ],
  statusLabel: '시간표 기준',
  updatedAt: DateTime(2026, 7, 10, 9),
);
