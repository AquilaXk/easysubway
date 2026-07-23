import 'dart:developer' as developer;

/// profile/release에서도 켤 수 있는 성능 계측 플래그.
///
/// ```bash
/// flutter run --profile --dart-define=EASY_SUBWAY_PERF_LOGS=true
/// ```
const bool easySubwayPerfLogsEnabled = bool.fromEnvironment(
  'EASY_SUBWAY_PERF_LOGS',
);

/// [easySubwayPerfLogsEnabled]일 때만 Timeline 이벤트와 로그를 남긴다.
/// flag가 꺼져 있으면 release 경로에 부작용이 없다.
void easySubwayPerfLog(String message) {
  if (!easySubwayPerfLogsEnabled) {
    return;
  }
  developer.log(message, name: 'EasySubwayPerf');
}

/// Timeline에 동기 구간을 기록한다. flag가 꺼져 있으면 [action]만 실행한다.
T easySubwayPerfTimeSync<T>(String name, T Function() action) {
  if (!easySubwayPerfLogsEnabled) {
    return action();
  }
  final task = developer.TimelineTask()..start(name);
  final sw = Stopwatch()..start();
  try {
    return action();
  } finally {
    sw.stop();
    task.finish(arguments: {'elapsedMicros': sw.elapsedMicroseconds});
    easySubwayPerfLog('$name ${sw.elapsedMicroseconds}µs');
  }
}

/// Timeline에 비동기 구간을 기록한다. flag가 꺼져 있으면 [action]만 실행한다.
Future<T> easySubwayPerfTimeAsync<T>(
  String name,
  Future<T> Function() action,
) async {
  if (!easySubwayPerfLogsEnabled) {
    return action();
  }
  final task = developer.TimelineTask()..start(name);
  final sw = Stopwatch()..start();
  try {
    return await action();
  } finally {
    sw.stop();
    task.finish(arguments: {'elapsedMicros': sw.elapsedMicroseconds});
    easySubwayPerfLog('$name ${sw.elapsedMicroseconds}µs');
  }
}
