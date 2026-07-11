import 'next_train_widget_repository.dart';

typedef LoadNextTrainWidgetData =
    Future<NextTrainWidgetData> Function(
      WidgetStationSelection selection,
      DateTime now,
    );
typedef SaveWidgetValue = Future<void> Function(String key, Object? value);
typedef UpdateNativeWidget = Future<void> Function();

class NextTrainWidgetService {
  const NextTrainWidgetService({
    required this.load,
    required this.saveValue,
    required this.updateWidget,
  });

  final LoadNextTrainWidgetData load;
  final SaveWidgetValue saveValue;
  final UpdateNativeWidget updateWidget;

  Future<void> configure({
    required int appWidgetId,
    required WidgetStationSelection selection,
    required DateTime now,
  }) async {
    final data = await load(selection, now);
    if (data.status == NextTrainWidgetStatus.timetableUnavailable ||
        data.directions.length < 2) {
      throw StateError('선택한 역의 시간표를 확인할 수 없어요.');
    }
    await _save(appWidgetId, data);
  }

  Future<void> refresh({
    required int appWidgetId,
    required WidgetStationSelection selection,
    required DateTime now,
  }) async {
    await _save(appWidgetId, await load(selection, now));
  }

  Future<void> _save(int appWidgetId, NextTrainWidgetData data) async {
    final selection = data.selection;
    final prefix = 'widget_${appWidgetId}_';
    final values = <String, Object?>{
      '${prefix}station_id': selection.stationId,
      '${prefix}line_id': selection.lineId,
      '${prefix}station_name': selection.stationName,
      '${prefix}line_name': selection.lineName,
      '${prefix}direction_1': data.directions.isEmpty
          ? ''
          : data.directions[0].name,
      '${prefix}departure_1': data.directions.isEmpty
          ? ''
          : data.directions[0].departureLabel,
      '${prefix}direction_2': data.directions.length < 2
          ? ''
          : data.directions[1].name,
      '${prefix}departure_2': data.directions.length < 2
          ? ''
          : data.directions[1].departureLabel,
      '${prefix}status': data.status.name,
      '${prefix}status_label': data.statusLabel,
      '${prefix}updated_at': data.updatedAt.toIso8601String(),
    };
    for (final entry in values.entries) {
      await saveValue(entry.key, entry.value);
    }
    await updateWidget();
  }
}
