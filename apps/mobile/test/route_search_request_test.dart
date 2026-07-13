import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toV2Json은 mobilityPreset이 있으면 body에 싣고 mobilityType도 함께 보낸다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'WHEELCHAIR',
      mobilityPreset: 'STEP_FREE',
    );

    final body = request.toV2Json();

    expect(body['mobilityPreset'], 'STEP_FREE');
    expect(body['mobilityType'], 'WHEELCHAIR');
    expect(body['constraintMode'], 'STRICT_STEP_FREE');
  });

  test('toV2Json은 mobilityPreset이 없으면 키를 넣지 않는다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'SENIOR',
    );

    final body = request.toV2Json();

    expect(body.containsKey('mobilityPreset'), isFalse);
    expect(body['mobilityType'], 'SENIOR');
  });

  test('STANDARD 프리셋은 strict가 아닌 PREFER_STEP_FREE로 전송된다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'STANDARD',
      mobilityPreset: 'STANDARD',
    );

    final body = request.toV2Json();

    expect(body['mobilityPreset'], 'STANDARD');
    expect(body['mobilityType'], 'STANDARD');
    expect(body['constraintMode'], 'PREFER_STEP_FREE');
  });

  test('toJson(v1)에는 mobilityPreset을 넣지 않는다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'WHEELCHAIR',
      mobilityPreset: 'STEP_FREE',
    );

    expect(request.toJson().containsKey('mobilityPreset'), isFalse);
  });
}
