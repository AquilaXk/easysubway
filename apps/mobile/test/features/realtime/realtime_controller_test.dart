import 'package:easysubway_mobile/features/realtime/realtime_controller.dart';
import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime controller는 repository 실패를 unavailable 상태로 낮춘다', () async {
    final controller = RealtimeStationController(
      repository: const ThrowingRealtimeRepository(),
    );

    await controller.load(
      const RealtimeStationQuery(
        stationId: 'station-sangnoksu',
        lineId: '4',
        stationQueryName: '상록수',
      ),
    );

    expect(controller.state.status, RealtimeSnapshotStatus.unavailable);
    expect(controller.state.message, contains('역 정보와 경로 검색은 계속 이용'));
  });
}

class ThrowingRealtimeRepository implements RealtimeRepository {
  const ThrowingRealtimeRepository();

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    throw const RealtimeException('network failed');
  }
}
