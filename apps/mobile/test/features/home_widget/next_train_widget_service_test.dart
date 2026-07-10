import 'package:easysubway_mobile/features/home_widget/next_train_widget_repository.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_runtime.dart';
import 'package:easysubway_mobile/features/home_widget/next_train_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
